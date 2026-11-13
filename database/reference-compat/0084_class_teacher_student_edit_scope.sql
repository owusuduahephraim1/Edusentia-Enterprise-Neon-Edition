-- Class-scoped student editing. Supabase reference remains unchanged.
-- Guardian and enrolment modifications are reserved for school system administrators.
create or replace function public.can_edit_student_record(target_student_id uuid)
returns boolean language sql stable security definer set search_path to 'public','extensions' as $scope$
  select public.is_records_manager() or (
    target_student_id is not null
    and public.current_app_role()='class_teacher'
    and exists (
      select 1 from public.enrollments e
      join public.classes c on c.id=e.class_id
      where e.student_id=target_student_id and e.active and e.deleted_at is null
        and c.active and c.deleted_at is null
        and c.class_teacher_id=(select id from public.profiles where id=auth.uid() and active)
        and exists (select 1 from public.academic_years y where y.id=e.academic_year_id and y.is_active and y.deleted_at is null)
    )
  );
$scope$;

CREATE OR REPLACE FUNCTION public.save_student(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sid uuid;
  eid uuid;
  gid uuid;
  classid uuid;
  admission text;
  student_data jsonb:=coalesce(payload->'student','{}'::jsonb);
  enrollment_data jsonb:=coalesce(payload->'enrollment','{}'::jsonb);
  guardian_data jsonb:=coalesce(payload->'guardian','{}'::jsonb);
begin
  sid:=nullif(student_data->>'id','')::uuid;
  if public.current_app_role()='class_teacher' and sid is null then
    raise exception 'Only the School System Administrator may register students' using errcode='42501';
  end if;
  if public.current_app_role()='class_teacher' and (coalesce(student_data->>'status','active') <> 'active' or nullif(student_data->>'photo_url','') is not null) then
    raise exception 'Student status and photograph changes require the School System Administrator' using errcode='42501';
  end if;
  if public.current_app_role()='class_teacher' and guardian_data <> '{}'::jsonb then
    raise exception 'Guardian details are managed only by the School System Administrator' using errcode='42501';
  end if;
  if public.current_app_role() <> 'system_admin' and guardian_data <> '{}'::jsonb then
    raise exception 'Guardian details are managed only by the School System Administrator' using errcode='42501';
  end if;
  if not public.can_edit_student_record(sid) then
    raise exception 'Access denied' using errcode='42501';
  end if;

  if btrim(coalesce(student_data->>'first_name',''))=''
    or btrim(coalesce(student_data->>'last_name',''))='' then
    raise exception 'Student first name and last name are required';
  end if;

  if sid is null then
    if btrim(coalesce(enrollment_data->>'academic_year_id',''))=''
      or btrim(coalesce(enrollment_data->>'class_id',''))='' then
      raise exception 'Academic year and class are required for a new student so the admission number can be generated';
    end if;
    classid:=(enrollment_data->>'class_id')::uuid;
    admission:=public.generate_class_student_identifier(classid);
  else
    select s.admission_no::text
    into admission
    from public.students s
    where s.id=sid and s.deleted_at is null
    for update;
    if admission is null then
      raise exception 'Student record not found';
    end if;
  end if;

  -- Archived students do not reserve an admission number. Only a current,
  -- non-deleted student may block allocation.
  if exists(
    select 1 from public.students s
    where s.deleted_at is null
      and lower(s.admission_no::text)=lower(admission)
      and (sid is null or s.id<>sid)
  ) then
    raise exception 'Admission number already exists';
  end if;

  perform set_config('app.change_reason',coalesce(payload->>'reason','Student record update'),true);

  if sid is null then
    insert into public.students(admission_no,first_name,middle_name,last_name,gender,date_of_birth,photo_url,status)
    values(
      admission,
      btrim(student_data->>'first_name'),
      btrim(coalesce(student_data->>'middle_name','')),
      btrim(student_data->>'last_name'),
      coalesce(student_data->>'gender','Other'),
      nullif(student_data->>'date_of_birth','')::date,
      coalesce(student_data->>'photo_url',''),
      coalesce(nullif(student_data->>'status',''),'active')::public.student_status
    )
    returning id into sid;
  else
    update public.students
    set first_name=btrim(student_data->>'first_name'),
        middle_name=btrim(coalesce(student_data->>'middle_name','')),
        last_name=btrim(student_data->>'last_name'),
        gender=coalesce(student_data->>'gender','Other'),
        date_of_birth=nullif(student_data->>'date_of_birth','')::date,
        photo_url=case when public.current_app_role()='class_teacher' then students.photo_url else coalesce(student_data->>'photo_url','') end,
        status=case when public.current_app_role()='class_teacher' then students.status else coalesce(nullif(student_data->>'status',''),'active')::public.student_status end
    where id=sid and deleted_at is null;
  end if;

  if public.current_app_role()='class_teacher' and enrollment_data <> '{}'::jsonb then
    raise exception 'Class placement and enrolment changes require the School System Administrator' using errcode='42501';
  end if;

  if enrollment_data ? 'academic_year_id' and enrollment_data ? 'class_id'
    and btrim(coalesce(enrollment_data->>'academic_year_id',''))<>''
    and btrim(coalesce(enrollment_data->>'class_id',''))<>'' then
    insert into public.enrollments(student_id,academic_year_id,class_id,roll_number,active)
    values(
      sid,
      (enrollment_data->>'academic_year_id')::uuid,
      (enrollment_data->>'class_id')::uuid,
      nullif(enrollment_data->>'roll_number','')::integer,
      coalesce((enrollment_data->>'active')::boolean,true)
    )
    on conflict(student_id,academic_year_id) do update
    set class_id=excluded.class_id,
        roll_number=excluded.roll_number,
        active=excluded.active,
        deleted_at=null,
        updated_at=now()
    returning id into eid;
  end if;

  if btrim(coalesce(guardian_data->>'full_name',''))<>'' then
    gid:=nullif(guardian_data->>'id','')::uuid;
    if gid is null then
      insert into public.student_guardians(full_name,relationship,phone,email,address,is_primary)
      values(
        guardian_data->>'full_name',
        coalesce(guardian_data->>'relationship','Guardian'),
        coalesce(guardian_data->>'phone',''),
        nullif(guardian_data->>'email','')::citext,
        coalesce(guardian_data->>'address',''),
        coalesce((guardian_data->>'is_primary')::boolean,true)
      )
      returning id into gid;
    else
      update public.student_guardians
      set full_name=guardian_data->>'full_name',
          relationship=coalesce(guardian_data->>'relationship','Guardian'),
          phone=coalesce(guardian_data->>'phone',''),
          email=nullif(guardian_data->>'email','')::citext,
          address=coalesce(guardian_data->>'address',''),
          is_primary=coalesce((guardian_data->>'is_primary')::boolean,false)
      where id=gid;
    end if;

    insert into public.guardian_links(guardian_id,student_id,auth_user_id,can_view_reports,can_receive_notifications)
    values(
      gid,sid,nullif(guardian_data->>'auth_user_id','')::uuid,
      coalesce((guardian_data->>'can_view_reports')::boolean,true),
      coalesce((guardian_data->>'can_receive_notifications')::boolean,true)
    )
    on conflict(guardian_id,student_id) do update
    set auth_user_id=excluded.auth_user_id,
        can_view_reports=excluded.can_view_reports,
        can_receive_notifications=excluded.can_receive_notifications;
  end if;

  return public.get_student_record(sid);
end
$function$

