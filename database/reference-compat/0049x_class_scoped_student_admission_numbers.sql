-- Class-scoped immutable student admission numbers.
-- Example: NIS000001-STU-BS3001 for the first class-scoped Basic 3 admission.
-- Existing admission numbers are preserved; each class counter is seeded from
-- the current class population so new numbering begins after existing pupils.
begin;

create table if not exists public.student_admission_sequences (
  class_id uuid primary key references public.classes(id) on delete restrict,
  class_prefix text not null,
  last_number integer not null default 0 check(last_number>=0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.student_class_identifier_prefix(target_class_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to 'public','pg_catalog'
as $function$
declare
  class_name text;
  parts text[];
  prefix text;
begin
  select upper(regexp_replace(btrim(c.name::text),'[[:space:]]+',' ','g'))
  into class_name
  from public.classes c
  where c.id=target_class_id
    and c.deleted_at is null
    and c.active;

  if class_name is null then
    raise exception 'An active class is required to generate the admission number';
  end if;

  if class_name ~ '^BASIC[[:space:]]*[0-9]+[A-Z]?$' then
    parts:=regexp_match(class_name,'^BASIC[[:space:]]*([0-9]+)([A-Z]?)$');
    prefix:='BS'||parts[1]||coalesce(parts[2],'');
  elsif class_name ~ '^KINDERGARTEN[[:space:]]*KG[[:space:]]*[0-9]+[A-Z]?$' then
    parts:=regexp_match(class_name,'^KINDERGARTEN[[:space:]]*KG[[:space:]]*([0-9]+)([A-Z]?)$');
    prefix:='KG'||parts[1]||coalesce(parts[2],'');
  elsif class_name ~ '^KINDERGARTEN[[:space:]]*[0-9]+[A-Z]?$' then
    parts:=regexp_match(class_name,'^KINDERGARTEN[[:space:]]*([0-9]+)([A-Z]?)$');
    prefix:='KG'||parts[1]||coalesce(parts[2],'');
  elsif class_name ~ '^KG[[:space:]]*[0-9]+[A-Z]?$' then
    parts:=regexp_match(class_name,'^KG[[:space:]]*([0-9]+)([A-Z]?)$');
    prefix:='KG'||parts[1]||coalesce(parts[2],'');
  elsif class_name ~ '^NURSERY[[:space:]]*[0-9]+[A-Z]?$' then
    parts:=regexp_match(class_name,'^NURSERY[[:space:]]*([0-9]+)([A-Z]?)$');
    prefix:='NS'||parts[1]||coalesce(parts[2],'');
  elsif class_name in ('CRECHE','CRÈCHE') then
    prefix:='CR';
  else
    prefix:=left(regexp_replace(class_name,'[^A-Z0-9]','','g'),6);
  end if;

  if coalesce(prefix,'')='' then
    raise exception 'A class identifier prefix could not be derived for %',class_name;
  end if;

  return prefix;
end
$function$;

create or replace function public.generate_class_student_identifier(target_class_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public','pg_catalog','extensions'
as $function$
declare
  root text;
  calculated_prefix text;
  frozen_prefix text;
  seed_count integer:=0;
  n integer;
  candidate text;
begin
  if target_class_id is null then
    raise exception 'Class is required before a student admission number can be generated';
  end if;

  select upper(btrim(s.identifier_root))
  into root
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;

  if coalesce(root,'') !~ '^[A-Z]{3}[0-9]{6}$' then
    raise exception 'The school identifier root is not configured correctly';
  end if;

  calculated_prefix:=public.student_class_identifier_prefix(target_class_id);

  select count(distinct e.student_id)
  into seed_count
  from public.enrollments e
  join public.students s on s.id=e.student_id and s.deleted_at is null
  where e.class_id=target_class_id
    and e.deleted_at is null
    and e.active;

  insert into public.student_admission_sequences(class_id,class_prefix,last_number)
  values(target_class_id,calculated_prefix,seed_count)
  on conflict(class_id) do nothing;

  select class_prefix,last_number
  into frozen_prefix,n
  from public.student_admission_sequences
  where class_id=target_class_id
  for update;

  loop
    n:=n+1;
    candidate:=root||'-STU-'||frozen_prefix||lpad(n::text,3,'0');
    exit when not exists(
      select 1 from public.students s
      where lower(s.admission_no::text)=lower(candidate)
    );
  end loop;

  update public.student_admission_sequences
  set last_number=n,updated_at=now()
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

  if exists(
    select 1 from public.students s
    where lower(s.admission_no::text)=lower(admission)
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

create or replace function public.validate_student_import(
  rows jsonb,
  target_academic_year_id uuid,
  target_class_id uuid,
  filename text default ''
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  item jsonb;
  rowno integer:=0;
  valid_rows jsonb:='[]'::jsonb;
  errors jsonb:='[]'::jsonb;
  gender_text text;
begin
  if public.current_app_role()<>'system_admin' then
    raise exception 'Only the System Administrator can validate student imports' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  if target_academic_year_id is null or target_class_id is null then
    raise exception 'Academic year and class are required for student import';
  end if;
  perform public.student_class_identifier_prefix(target_class_id);

  if jsonb_typeof(coalesce(rows,'[]'::jsonb))<>'array' then
    raise exception 'Rows must be a list';
  end if;

  for item in select value from jsonb_array_elements(rows) loop
    rowno:=rowno+1;
    gender_text:=initcap(lower(btrim(coalesce(item->>'gender',''))));

    if btrim(coalesce(item->>'first_name',''))=''
      or btrim(coalesce(item->>'last_name',''))='' then
      errors:=errors||jsonb_build_array(jsonb_build_object(
        'row_number',rowno,
        'message','First name and last name are required',
        'payload',item
      ));
    elsif gender_text not in ('Male','Female','Other') then
      errors:=errors||jsonb_build_array(jsonb_build_object(
        'row_number',rowno,
        'message','Gender must be Male, Female, or Other',
        'payload',item
      ));
    else
      valid_rows:=valid_rows||jsonb_build_array(
        (item-'admission_no')||jsonb_build_object(
          'academic_year_id',target_academic_year_id,
          'class_id',target_class_id,
          'gender',gender_text
        )
      );
    end if;
  end loop;

  return jsonb_build_object(
    'filename',filename,
    'total',jsonb_array_length(rows),
    'valid_count',jsonb_array_length(valid_rows),
    'invalid_count',jsonb_array_length(errors),
    'valid_rows',valid_rows,
    'errors',errors
  );
end
$function$;

create or replace function public.bulk_import_students(rows jsonb, filename text default '')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  batchid uuid;
  rowitem jsonb;
  rowno integer:=0;
  ok integer:=0;
  failed integer:=0;
begin
  if not public.is_records_manager() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  insert into public.import_batches(import_type,filename,total_rows,created_by)
  values('students',filename,jsonb_array_length(coalesce(rows,'[]'::jsonb)),auth.uid())
  returning id into batchid;

  for rowitem in
    select value
    from jsonb_array_elements(coalesce(rows,'[]'::jsonb))
    order by lower(coalesce(value->>'last_name','')),
             lower(coalesce(value->>'first_name','')),
             lower(coalesce(value->>'middle_name',''))
  loop
    rowno:=rowno+1;
    begin
      perform public.save_student(jsonb_build_object(
        'student',jsonb_build_object(
          'first_name',rowitem->>'first_name',
          'middle_name',coalesce(rowitem->>'middle_name',''),
          'last_name',rowitem->>'last_name',
          'gender',coalesce(rowitem->>'gender','Other'),
          'date_of_birth',coalesce(rowitem->>'date_of_birth',''),
          'status',coalesce(rowitem->>'status','active'),
          'photo_url',''
        ),
        'enrollment',jsonb_build_object(
          'academic_year_id',rowitem->>'academic_year_id',
          'class_id',rowitem->>'class_id',
          'roll_number',coalesce(rowitem->>'roll_number',''),
          'active',true
        ),
        'guardian',jsonb_build_object(
          'full_name',coalesce(rowitem->>'guardian_name',''),
          'relationship',coalesce(rowitem->>'relationship','Guardian'),
          'phone',coalesce(rowitem->>'guardian_phone',''),
          'email',coalesce(rowitem->>'guardian_email',''),
          'is_primary',true
        ),
        'reason','Bulk student import with automatic class admission number'
      ));
      ok:=ok+1;
    exception when others then
      failed:=failed+1;
      insert into public.import_errors(batch_id,row_number,payload,error_message)
      values(batchid,rowno,rowitem,sqlerrm);
    end;
  end loop;

  update public.import_batches
  set successful_rows=ok,
      failed_rows=failed,
      status=case when failed=0 then 'completed' else 'completed_with_errors' end,
      completed_at=now()
  where id=batchid;

  return jsonb_build_object('batch_id',batchid,'successful',ok,'failed',failed);
end
$function$;

create or replace function public.search_students_v5(
  search_text text default '',
  target_class_id uuid default null,
  target_status public.student_status default null,
  archive_filter text default 'active',
  page_number integer default 1,
  page_size integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
  limit_value integer:=least(greatest(page_size,1),100);
begin
  if archive_filter not in ('active','archived','all') then archive_filter:='active'; end if;
  if archive_filter<>'active' and public.current_app_role() not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;

  return (
    with matching as (
      select
        s.id,s.admission_no,s.first_name,s.middle_name,s.last_name,s.gender,s.date_of_birth,
        s.photo_url,s.status,s.updated_at,s.deleted_at,(s.deleted_at is not null) archived,
        e.id enrollment_id,e.class_id,e.academic_year_id,e.roll_number,
        c.name class_name,y.name academic_year_name,
        coalesce(c.level_order,2147483647) class_level_order,
        lower(coalesce(c.name::text,'')) class_sort,
        lower(coalesce(s.last_name,'')) last_name_sort,
        lower(coalesce(s.first_name,'')) first_name_sort,
        lower(coalesce(s.middle_name,'')) middle_name_sort
      from public.students s
      left join lateral (
        select en.*
        from public.enrollments en
        join public.academic_years ay on ay.id=en.academic_year_id and ay.deleted_at is null
        where en.student_id=s.id and en.deleted_at is null
        order by en.active desc,
                 coalesce(ay.start_date,ay.end_date,en.created_at::date) desc,
                 ay.name::text desc,
                 en.created_at desc
        limit 1
      ) e on true
      left join public.classes c on c.id=e.class_id
      left join public.academic_years y on y.id=e.academic_year_id
      where (
          public.current_app_role() in ('system_admin','principal')
          or (e.id is not null and public.can_access_class(e.class_id,false))
        )
        and (
          archive_filter='all'
          or (archive_filter='active' and s.deleted_at is null)
          or (archive_filter='archived' and s.deleted_at is not null)
        )
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or s.status=target_status)
        and (
          coalesce(search_text,'')=''
          or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%'
        )
    )
    select jsonb_build_object(
      'rows',coalesce((
        select jsonb_agg(
          to_jsonb(x)
            -'class_level_order'
            -'class_sort'
            -'last_name_sort'
            -'first_name_sort'
            -'middle_name_sort'
          order by x.class_level_order,x.class_sort,x.last_name_sort,x.first_name_sort,x.middle_name_sort,x.admission_no::text
        )
        from (
          select *
          from matching
          order by class_level_order,class_sort,last_name_sort,first_name_sort,middle_name_sort,admission_no::text
          limit limit_value offset offset_value
        ) x
      ),'[]'::jsonb),
      'total',(select count(*) from matching),
      'page',greatest(page_number,1),
      'page_size',limit_value
    )
  );
end
$function$;

revoke all on table public.student_admission_sequences from public;
revoke all on function public.student_class_identifier_prefix(uuid) from public;
revoke all on function public.generate_class_student_identifier(uuid) from public;
revoke all on function public.save_student(jsonb) from public;
revoke all on function public.validate_student_import(jsonb,uuid,uuid,text) from public;
revoke all on function public.bulk_import_students(jsonb,text) from public;
revoke all on function public.search_students_v5(text,uuid,public.student_status,text,integer,integer) from public;

grant execute on function public.save_student(jsonb) to edusentia_worker_runtime;
grant execute on function public.validate_student_import(jsonb,uuid,uuid,text) to edusentia_worker_runtime;
grant execute on function public.bulk_import_students(jsonb,text) to edusentia_worker_runtime;
grant execute on function public.search_students_v5(text,uuid,public.student_status,text,integer,integer) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0049x_class_scoped_student_admission_numbers')
on conflict do nothing;

commit;
