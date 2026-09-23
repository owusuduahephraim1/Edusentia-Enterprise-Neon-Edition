-- Reusable class-scoped student admission numbers.
-- Production rollout is guarded by active-only uniqueness and lowest-gap allocation checks.
--
-- Active students remain unique, but an admission number is returned to the
-- class pool when a student is archived/removed. Historical student rows keep
-- the admission number they had so reports and audit records remain readable.
-- Restoring a student keeps the old number when it is still free; if that number
-- has been reused by another active student, the restored student receives the
-- lowest available number in the same admission-prefix pool.
begin;

-- The live foundation historically enforced admission_no uniqueness across
-- active and archived students. Keep the active-only case-insensitive index and
-- remove only the global uniqueness constraint so archived history can coexist
-- with a newly active student using the released number.
create unique index if not exists students_admission_no_ci_idx
  on public.students(lower(admission_no::text))
  where deleted_at is null;

alter table public.students
  drop constraint if exists students_admission_no_key;

create or replace function public.next_student_identifier_for_prefix(target_prefix text)
returns text
language plpgsql
security definer
set search_path to 'public','pg_catalog'
as $function$
declare
  root text;
  clean_prefix text:=upper(btrim(coalesce(target_prefix,'')));
  n integer;
  candidate text;
begin
  if clean_prefix='' or clean_prefix !~ '^[A-Z0-9]{1,12}$' then
    raise exception 'Student admission prefix is invalid';
  end if;

  select upper(btrim(s.identifier_root))
  into root
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;

  if coalesce(root,'') !~ '^[A-Z]{3}[0-9]{6}$' then
    raise exception 'The school identifier root is not configured correctly';
  end if;

  -- Serialize allocation per school/prefix so simultaneous admissions cannot
  -- claim the same released number.
  perform pg_advisory_xact_lock(hashtext(root),hashtext(clean_prefix));

  select g.n
  into n
  from generate_series(1,999) as g(n)
  where not exists(
    select 1
    from public.students s
    where s.deleted_at is null
      and lower(s.admission_no::text)=lower(root||'-STU-'||clean_prefix||lpad(g.n::text,3,'0'))
  )
  order by g.n
  limit 1;

  if n is null then
    raise exception 'No admission numbers are available for class prefix %',clean_prefix;
  end if;

  candidate:=root||'-STU-'||clean_prefix||lpad(n::text,3,'0');
  return candidate;
end
$function$;

create or replace function public.generate_class_student_identifier(target_class_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public','pg_catalog','extensions'
as $function$
declare
  calculated_prefix text;
  frozen_prefix text;
  candidate text;
  allocated_number integer;
begin
  if target_class_id is null then
    raise exception 'Class is required before a student admission number can be generated';
  end if;

  calculated_prefix:=public.student_class_identifier_prefix(target_class_id);

  insert into public.student_admission_sequences(class_id,class_prefix,last_number)
  values(target_class_id,calculated_prefix,0)
  on conflict(class_id) do nothing;

  select class_prefix
  into frozen_prefix
  from public.student_admission_sequences
  where class_id=target_class_id
  for update;

  candidate:=public.next_student_identifier_for_prefix(frozen_prefix);
  allocated_number:=right(candidate,3)::integer;

  update public.student_admission_sequences
  set last_number=allocated_number,
      updated_at=now()
  where class_id=target_class_id;

  return candidate;
end
$function$;

create or replace function public.save_student(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
  if not public.can_manage_student(sid) then
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
        photo_url=coalesce(student_data->>'photo_url',''),
        status=coalesce(nullif(student_data->>'status',''),'active')::public.student_status
    where id=sid and deleted_at is null;
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
$function$;

create or replace function public.restore_student(
  target_student_id uuid,
  reason_text text default 'Student restored'
)
returns boolean
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  latest_enrollment uuid;
  latest_class_id uuid;
  current_admission text;
  replacement_admission text;
  identifier_root text;
  identifier_tail text;
  original_prefix text;
begin
  if not public.is_records_manager() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  select s.admission_no::text
  into current_admission
  from public.students s
  where s.id=target_student_id
    and s.deleted_at is not null
  for update;

  if current_admission is null then
    raise exception 'Archived student record not found';
  end if;

  select e.id,e.class_id
  into latest_enrollment,latest_class_id
  from public.enrollments e
  join public.academic_years y on y.id=e.academic_year_id
  where e.student_id=target_student_id
    and e.deleted_at is null
  order by y.is_active desc,y.start_date desc nulls last,e.created_at desc
  limit 1;

  replacement_admission:=current_admission;
  identifier_root:=upper(split_part(current_admission,'-STU-',1));
  identifier_tail:=upper(split_part(current_admission,'-STU-',2));

  if identifier_root ~ '^[A-Z]{3}[0-9]{6}$'
     and length(identifier_tail)>3
     and right(identifier_tail,3) ~ '^[0-9]{3}$' then
    original_prefix:=left(identifier_tail,length(identifier_tail)-3);
    perform pg_advisory_xact_lock(hashtext(identifier_root),hashtext(original_prefix));
  end if;

  if exists(
    select 1
    from public.students s
    where s.deleted_at is null
      and s.id<>target_student_id
      and lower(s.admission_no::text)=lower(current_admission)
  ) then
    if coalesce(original_prefix,'')<>'' then
      replacement_admission:=public.next_student_identifier_for_prefix(original_prefix);
    elsif latest_class_id is not null then
      replacement_admission:=public.generate_class_student_identifier(latest_class_id);
    else
      raise exception 'The previous admission number has been reassigned and no class is available for a replacement';
    end if;
  end if;

  perform set_config(
    'app.change_reason',
    coalesce(nullif(reason_text,''),'Student restored')
      ||case when replacement_admission is distinct from current_admission
             then ' with admission number reassigned from '||current_admission||' to '||replacement_admission
             else '' end,
    true
  );

  update public.students
  set admission_no=replacement_admission,
      status='active',
      deleted_at=null,
      updated_at=now()
  where id=target_student_id;

  if latest_enrollment is not null then
    update public.enrollments
    set active=(id=latest_enrollment),
        updated_at=now()
    where student_id=target_student_id
      and deleted_at is null;
  end if;

  return true;
end
$function$;

revoke all on function public.next_student_identifier_for_prefix(text) from public;
revoke all on function public.generate_class_student_identifier(uuid) from public;
revoke all on function public.save_student(jsonb) from public;
revoke all on function public.restore_student(uuid,text) from public;

grant execute on function public.save_student(jsonb) to edusentia_worker_runtime;
grant execute on function public.restore_student(uuid,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0058_reusable_student_admission_numbers')
on conflict do nothing;

commit;
