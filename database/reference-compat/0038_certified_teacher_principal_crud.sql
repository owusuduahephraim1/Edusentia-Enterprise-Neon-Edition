-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function bodies extracted read-only with pg_get_functiondef.
-- Requires 0035 teacher/principal hardening and 0036 staff runtime guards.

begin;

CREATE OR REPLACE FUNCTION public.list_teachers(search_text text DEFAULT ''::text, status_filter text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);limit_value integer:=least(greatest(page_size,1),100);
begin
  if not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501';end if;if archive_filter not in ('active','archived','all') then archive_filter:='active';end if;
  return (with matching as (
    select t.id,t.profile_id,t.staff_no,t.emis_code,t.first_name,t.middle_name,t.last_name,t.gender,t.date_of_birth,t.phone,t.email,t.address,t.qualification,t.specialization,t.date_joined,t.employment_status,t.notes,t.photo_url,t.active,t.deleted_at,t.created_at,t.updated_at,concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name) full_name,p.role profile_role,p.active profile_active,au.email profile_email,
      coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb) class_assignments,
      coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb) subject_assignments
    from public.teachers t left join public.profiles p on p.id=t.profile_id left join auth.users au on au.id=t.profile_id
    where (archive_filter='all' or (archive_filter='active' and t.deleted_at is null) or (archive_filter='archived' and t.deleted_at is not null)) and (coalesce(status_filter,'')='' or t.employment_status=status_filter)
      and (coalesce(search_text,'')='' or t.staff_no::text ilike '%'||search_text||'%' or coalesce(t.emis_code::text,'') ilike '%'||search_text||'%' or concat_ws(' ',t.first_name,t.middle_name,t.last_name) ilike '%'||search_text||'%' or coalesce(t.email::text,'') ilike '%'||search_text||'%' or coalesce(t.phone,'') ilike '%'||search_text||'%')
  ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.last_name,x.first_name) from (select * from matching order by last_name,first_name limit limit_value offset offset_value)x),'[]'::jsonb),'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value,'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role),'email',au.email) order by p.full_name) from public.profiles p left join auth.users au on au.id=p.id where p.active and public.current_app_role_for(p.role) in ('class_teacher','subject_teacher')),'[]'::jsonb)));
end$function$;

CREATE OR REPLACE FUNCTION public.get_teacher_record(target_teacher_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.can_manage_teachers() and not exists(select 1 from public.teachers t where t.id=target_teacher_id and t.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  return (select jsonb_build_object('teacher',to_jsonb(t)||jsonb_build_object('full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'profile_email',au.email,'profile_name',p.full_name,'profile_role',case when p.id is null then null else public.current_app_role_for(p.role) end),'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb),'subjects',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb)) from public.teachers t left join public.profiles p on p.id=t.profile_id left join auth.users au on au.id=t.profile_id where t.id=target_teacher_id);
end$function$;

CREATE OR REPLACE FUNCTION public.get_my_teacher_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare tid uuid;
begin
  if auth.uid() is null or public.current_app_role() not in ('class_teacher','subject_teacher') then raise exception 'Teacher access required' using errcode='42501';end if;
  select id into tid from public.teachers where profile_id=auth.uid() and deleted_at is null order by active desc,updated_at desc limit 1;
  if tid is null then return jsonb_build_object('linked',false,'teacher',null,'classes','[]'::jsonb,'subjects','[]'::jsonb,'assigned_class_count',0);end if;
  return (select jsonb_build_object(
    'linked',true,
    'teacher',to_jsonb(t)||jsonb_build_object('full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'profile_email',au.email),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb),
    'assigned_class_count',(select count(distinct x.class_id) from (select c.id class_id from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null union select cs.class_id from public.class_subjects cs where cs.teacher_id=t.profile_id and cs.active) x)
  ) from public.teachers t left join auth.users au on au.id=t.profile_id where t.id=tid);
end$function$;

CREATE OR REPLACE FUNCTION public.save_teacher(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=public.safe_uuid(payload->>'id');profileid uuid:=public.safe_uuid(payload->>'profile_id');staff text:=upper(btrim(coalesce(payload->>'staff_no','')));emis text:=upper(btrim(coalesce(payload->>'emis_code','')));current_updated timestamptz;expected_updated timestamptz:=public.safe_timestamptz(payload->>'updated_at');joined date:=public.safe_date(payload->>'date_joined');dob date:=public.safe_date(payload->>'date_of_birth');employment text:=coalesce(nullif(btrim(payload->>'employment_status'),''),'active');gender_value text:=coalesce(nullif(btrim(payload->>'gender'),''),'Other');qualification_value text:=btrim(coalesce(payload->>'qualification',''));linked_role text;affected integer;legacy_qualification text;
begin
  if auth.uid() is null or not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501';end if;
  if btrim(coalesce(payload->>'id',''))<>'' and tid is null then raise exception 'Teacher record identifier is invalid';end if;if btrim(coalesce(payload->>'profile_id',''))<>'' and profileid is null then raise exception 'Linked user account is invalid';end if;
  if btrim(coalesce(payload->>'date_joined',''))<>'' and joined is null then raise exception 'Date joined is invalid';end if;if btrim(coalesce(payload->>'date_of_birth',''))<>'' and dob is null then raise exception 'Date of birth is invalid';end if;
  if btrim(coalesce(payload->>'first_name',''))='' or btrim(coalesce(payload->>'last_name',''))='' then raise exception 'First name and last name are required';end if;if gender_value not in ('Male','Female','Other') then raise exception 'Gender selection is invalid';end if;
  if btrim(coalesce(payload->>'email',''))<>'' and payload->>'email' !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Teacher email address is invalid';end if;if employment not in ('active','leave','suspended','resigned','retired') then raise exception 'Employment status is invalid';end if;
  if joined>current_date then raise exception 'Date joined cannot be in the future';end if;if dob>current_date then raise exception 'Date of birth cannot be in the future';end if;if joined is not null and dob is not null and joined<=dob then raise exception 'Date joined must be after date of birth';end if;
  if tid is not null then select updated_at,qualification into current_updated,legacy_qualification from public.teachers where id=tid and deleted_at is null for update;if not found then raise exception 'Teacher record not found';end if;if expected_updated is not null and current_updated is distinct from expected_updated then raise exception 'Teacher record changed by another user' using errcode='40001';end if;end if;
  if qualification_value<>'' and qualification_value not in ('PhD','MSc Degree','Bachelor Degree','HND','Diploma','SHS') and (tid is null or qualification_value is distinct from legacy_qualification) then raise exception 'Qualification must be selected from the approved qualification list';end if;
  if tid is null and (staff='' or exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff))) then staff:=public.generate_school_identifier('teacher');end if;if staff='' then staff:=public.generate_school_identifier('teacher');end if;
  if exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff) and (tid is null or t.id<>tid)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff)) then raise exception 'Staff number already exists';end if;
  if emis<>'' and exists(select 1 from public.teachers t where t.deleted_at is null and lower(coalesce(t.emis_code::text,''))=lower(emis) and (tid is null or t.id<>tid)) then raise exception 'EMIS code already exists';end if;
  if profileid is not null then select public.current_app_role_for(p.role) into linked_role from public.profiles p where p.id=profileid and p.active;if linked_role is null then raise exception 'Selected user account is unavailable';end if;if linked_role not in ('class_teacher','subject_teacher') then raise exception 'Selected user account does not have a teacher role';end if;if exists(select 1 from public.teachers t where t.profile_id=profileid and t.deleted_at is null and (tid is null or t.id<>tid)) or exists(select 1 from public.headteachers h where h.profile_id=profileid and h.deleted_at is null) then raise exception 'This user account is already linked to another staff record';end if;end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Teacher record update'),true);
  if tid is null then
    insert into public.teachers(profile_id,staff_no,emis_code,first_name,middle_name,last_name,gender,date_of_birth,phone,email,address,qualification,specialization,date_joined,employment_status,notes,active,created_by,updated_at)
    values(profileid,staff,nullif(emis,'')::citext,btrim(payload->>'first_name'),btrim(coalesce(payload->>'middle_name','')),btrim(payload->>'last_name'),gender_value,dob,btrim(coalesce(payload->>'phone','')),nullif(btrim(coalesce(payload->>'email','')),'')::citext,btrim(coalesce(payload->>'address','')),qualification_value,btrim(coalesce(payload->>'specialization','')),joined,employment,btrim(coalesce(payload->>'notes','')),public.safe_boolean(payload->>'active',true),auth.uid(),now()) returning id into tid;
  else
    update public.teachers set profile_id=profileid,staff_no=staff,emis_code=nullif(emis,'')::citext,first_name=btrim(payload->>'first_name'),middle_name=btrim(coalesce(payload->>'middle_name','')),last_name=btrim(payload->>'last_name'),gender=gender_value,date_of_birth=dob,phone=btrim(coalesce(payload->>'phone','')),email=nullif(btrim(coalesce(payload->>'email','')),'')::citext,address=btrim(coalesce(payload->>'address','')),qualification=qualification_value,specialization=btrim(coalesce(payload->>'specialization','')),date_joined=joined,employment_status=employment,notes=btrim(coalesce(payload->>'notes','')),active=public.safe_boolean(payload->>'active',true),updated_at=now() where id=tid and deleted_at is null;
    get diagnostics affected=row_count;if affected<>1 then raise exception 'Teacher record was not updated';end if;
  end if;
  return public.get_teacher_record(tid);
exception when unique_violation then raise exception 'Staff number, EMIS code, or linked user account is already in use';
end$function$;

CREATE OR REPLACE FUNCTION public.archive_teacher(target_teacher_id uuid, reason_text text DEFAULT 'Teacher archived'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare profileid uuid;
begin
  if not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  select profile_id into profileid from public.teachers where id=target_teacher_id and deleted_at is null for update;
  if not found then raise exception 'Teacher record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Teacher archived'),true);
  update public.teachers set active=false,employment_status=case when employment_status='active' then 'resigned' else employment_status end,
    deleted_at=now(),updated_at=now() where id=target_teacher_id;
  if profileid is not null then
    update public.classes set class_teacher_id=null where class_teacher_id=profileid;
    update public.class_subjects set teacher_id=null where teacher_id=profileid;
  end if;
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.restore_teacher(target_teacher_id uuid, reason_text text DEFAULT 'Teacher restored'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.teachers where id=target_teacher_id and deleted_at is not null) then
    raise exception 'Archived teacher record not found';
  end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Teacher restored'),true);
  update public.teachers set active=true,employment_status='active',deleted_at=null,updated_at=now()
  where id=target_teacher_id;
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.set_teacher_photo(target_teacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare t public.teachers%rowtype;clean_path text:=btrim(coalesce(target_photo_url,''));
begin
  select * into t from public.teachers where id=target_teacher_id and deleted_at is null for update;
  if t.id is null then raise exception 'Teacher record not found';end if;
  if not(public.is_system_admin() or t.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  perform public.require_sensitive_access();if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';end if;
  if expected_updated_at is not null and t.updated_at is distinct from expected_updated_at then raise exception 'Teacher record changed by another user' using errcode='40001';end if;
  if clean_path<>'' and split_part(clean_path,'/',1)<>target_teacher_id::text then raise exception 'Teacher photograph path is invalid';end if;
  update public.teachers set photo_url=clean_path,updated_at=now() where id=target_teacher_id returning * into t;
  return public.get_teacher_record(target_teacher_id);
end$function$;

CREATE OR REPLACE FUNCTION public.list_headteachers(search_text text DEFAULT ''::text, status_filter text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);limit_value integer:=least(greatest(page_size,1),100);
begin
  if not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501';end if;if archive_filter not in ('active','archived','all') then archive_filter:='active';end if;
  return (with matching as (
    select h.id,h.profile_id,h.staff_no,h.first_name,h.middle_name,h.last_name,h.gender,h.phone,h.email,h.address,h.qualification,h.date_appointed,h.employment_status,h.notes,h.photo_url,h.active,h.signature_path,h.signature_updated_at,h.deleted_at,h.created_at,h.updated_at,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,p.role profile_role,p.active profile_active,au.email profile_email
    from public.headteachers h left join public.profiles p on p.id=h.profile_id left join auth.users au on au.id=h.profile_id
    where (archive_filter='all' or (archive_filter='active' and h.deleted_at is null) or (archive_filter='archived' and h.deleted_at is not null)) and (coalesce(status_filter,'')='' or h.employment_status=status_filter)
      and (coalesce(search_text,'')='' or h.staff_no::text ilike '%'||search_text||'%' or concat_ws(' ',h.first_name,h.middle_name,h.last_name) ilike '%'||search_text||'%' or coalesce(h.phone,'') ilike '%'||search_text||'%' or coalesce(au.email::text,'') ilike '%'||search_text||'%')
  ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.full_name),x.staff_no::text) from (select * from matching order by lower(full_name),staff_no::text limit limit_value offset offset_value)x),'[]'::jsonb),'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value));
end$function$;

CREATE OR REPLACE FUNCTION public.get_headteacher_record(target_headteacher_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.can_manage_headteachers() and not exists(
    select 1 from public.headteachers h where h.id=target_headteacher_id and h.profile_id=auth.uid()
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  return (
    select jsonb_build_object(
      'principal',to_jsonb(h)||jsonb_build_object(
        'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
        'profile_email',au.email,'profile_name',p.full_name,
        'profile_role',case when p.id is null then null else public.current_app_role_for(p.role) end
      )
    )
    from public.headteachers h
    left join public.profiles p on p.id=h.profile_id
    left join auth.users au on au.id=h.profile_id
    where h.id=target_headteacher_id
  );
end $function$;

CREATE OR REPLACE FUNCTION public.get_my_headteacher_signature()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result jsonb;
begin
  if auth.uid() is null or public.current_app_role()<>'principal' then raise exception 'Access denied' using errcode='42501'; end if;
  select jsonb_build_object('linked',true,'headteacher_id',h.id,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'contact',h.phone,'signature_path',h.signature_path,'signature_updated_at',h.signature_updated_at,'updated_at',h.updated_at)
  into result from public.headteachers h where h.profile_id=auth.uid() and h.deleted_at is null and h.active order by h.updated_at desc limit 1;
  return coalesce(result,jsonb_build_object('linked',false,'full_name',(select p.full_name from public.profiles p where p.id=auth.uid()),'signature_path',''));
end $function$;

CREATE OR REPLACE FUNCTION public.save_headteacher(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  hid uuid:=public.safe_uuid(payload->>'id');
  profileid uuid:=public.safe_uuid(payload->>'profile_id');
  staff text:=upper(btrim(coalesce(payload->>'staff_no','')));
  full_name_value text:=regexp_replace(btrim(coalesce(payload->>'full_name','')),'[[:space:]]+',' ','g');
  contact_value text:=btrim(coalesce(payload->>'contact',payload->>'phone',''));
  name_parts text[];
  first_name_value text;
  last_name_value text:='';
  current_updated timestamptz;
  expected_updated timestamptz:=public.safe_timestamptz(payload->>'updated_at');
  linked_role text;
  affected integer;
begin
  if auth.uid() is null or not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and hid is null then raise exception 'Principal record identifier is invalid'; end if;
  if btrim(coalesce(payload->>'profile_id',''))<>'' and profileid is null then raise exception 'Linked user account is invalid'; end if;
  if full_name_value='' then raise exception 'Principal full name is required'; end if;
  if contact_value='' then raise exception 'Principal contact is required'; end if;
  name_parts:=regexp_split_to_array(full_name_value,'[[:space:]]+');
  first_name_value:=name_parts[1];
  if cardinality(name_parts)>1 then last_name_value:=array_to_string(name_parts[2:cardinality(name_parts)],' '); end if;
  if hid is not null then
    select updated_at into current_updated from public.headteachers where id=hid and deleted_at is null for update;
    if not found then raise exception 'Principal record not found'; end if;
    if expected_updated is not null and current_updated is distinct from expected_updated then raise exception 'Principal record changed by another user' using errcode='40001'; end if;
  end if;
  if hid is null and (staff='' or exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff))) then staff:=public.generate_school_identifier('principal'); end if;
  if staff='' then staff:=public.generate_school_identifier('principal'); end if;
  if exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff) and (hid is null or h.id<>hid)) then raise exception 'Staff number already exists'; end if;
  if profileid is not null then
    select public.current_app_role_for(p.role) into linked_role from public.profiles p where p.id=profileid and p.active;
    if linked_role is null then raise exception 'Selected user account is unavailable'; end if;
    if linked_role<>'principal' then raise exception 'Selected user account is not a Principal account'; end if;
    if exists(select 1 from public.headteachers h where h.profile_id=profileid and h.deleted_at is null and (hid is null or h.id<>hid)) or exists(select 1 from public.teachers t where t.profile_id=profileid and t.deleted_at is null) then raise exception 'This user account is already linked to another staff record'; end if;
  end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Principal record update'),true);
  if hid is null then
    insert into public.headteachers(profile_id,staff_no,first_name,middle_name,last_name,phone,employment_status,active,created_by,updated_at)
    values(profileid,staff,first_name_value,'',last_name_value,contact_value,'active',true,auth.uid(),now()) returning id into hid;
  else
    update public.headteachers set profile_id=profileid,staff_no=staff,first_name=first_name_value,middle_name='',last_name=last_name_value,phone=contact_value,employment_status='active',active=true,updated_at=now()
    where id=hid and deleted_at is null;
    get diagnostics affected=row_count;
    if affected<>1 then raise exception 'Principal record was not updated'; end if;
  end if;
  update public.school_settings
  set head_name=full_name_value,
      updated_at=now()
  where id=(select id from public.school_settings order by created_at,id limit 1);
  return public.get_headteacher_record(hid);
exception when unique_violation then
  raise exception 'Staff number or linked user account is already in use';
end $function$;

CREATE OR REPLACE FUNCTION public.archive_headteacher(target_headteacher_id uuid, reason_text text DEFAULT 'Principal archived'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.headteachers where id=target_headteacher_id and deleted_at is null for update) then raise exception 'Principal record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Principal archived'),true);
  update public.headteachers set active=false,
    employment_status=case when employment_status='active' then 'resigned' else employment_status end,
    deleted_at=now(),updated_at=now() where id=target_headteacher_id;
  update public.school_settings
  set head_name=coalesce((
    select concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)
    from public.headteachers h where h.deleted_at is null and h.active and h.employment_status='active'
    order by h.date_appointed desc nulls last,h.created_at desc limit 1
  ),''),
      updated_at=now()
  where id=(select id from public.school_settings order by created_at,id limit 1);
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.restore_headteacher(target_headteacher_id uuid, reason_text text DEFAULT 'Principal restored'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.headteachers where id=target_headteacher_id and deleted_at is not null for update) then raise exception 'Archived Principal record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Principal restored'),true);
  update public.headteachers set active=true,employment_status='active',deleted_at=null,updated_at=now() where id=target_headteacher_id;
  update public.school_settings
  set head_name=(
    select concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)
    from public.headteachers h
    where h.id=target_headteacher_id
  ),
      updated_at=now()
  where id=(select id from public.school_settings order by created_at,id limit 1);
  return true;
exception when unique_violation then raise exception 'The Principal record cannot be restored because its staff number or linked account is already in use';
end $function$;

CREATE OR REPLACE FUNCTION public.set_headteacher_photo(target_headteacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare h public.headteachers%rowtype;clean_path text:=btrim(coalesce(target_photo_url,''));
begin
  select * into h from public.headteachers where id=target_headteacher_id and deleted_at is null for update;
  if h.id is null then raise exception 'Principal record not found';end if;
  if not(public.is_system_admin() or h.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  perform public.require_sensitive_access();if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';end if;
  if expected_updated_at is not null and h.updated_at is distinct from expected_updated_at then raise exception 'Principal record changed by another user' using errcode='40001';end if;
  if clean_path<>'' and split_part(clean_path,'/',1)<>target_headteacher_id::text then raise exception 'Principal photograph path is invalid';end if;
  update public.headteachers set photo_url=clean_path,updated_at=now() where id=target_headteacher_id returning * into h;
  return jsonb_build_object('headteacher',to_jsonb(h));
end$function$;

CREATE OR REPLACE FUNCTION public.set_my_headteacher_signature(target_signature_path text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare hid uuid;current_updated timestamptz;clean_path text:=btrim(coalesce(target_signature_path,''));
begin
  if auth.uid() is null or public.current_app_role()<>'principal' then raise exception 'Access denied' using errcode='42501'; end if;
  select h.id,h.updated_at into hid,current_updated from public.headteachers h where h.profile_id=auth.uid() and h.deleted_at is null and h.active order by h.updated_at desc limit 1 for update;
  if hid is null then raise exception 'No active Principal record is linked to this account'; end if;
  if expected_updated_at is not null and current_updated is distinct from expected_updated_at then raise exception 'Principal record changed. Reload and try again.' using errcode='40001'; end if;
  if clean_path<>'' and clean_path not like auth.uid()::text||'/%' then raise exception 'Signature storage path is invalid'; end if;
  perform set_config('app.change_reason',case when clean_path='' then 'Principal signature removed' else 'Principal signature updated' end,true);
  update public.headteachers set signature_path=clean_path,signature_updated_at=case when clean_path='' then null else now() end,updated_at=now() where id=hid;
  return public.get_my_headteacher_signature();
end $function$;

revoke all on function public.list_teachers(text,text,text,integer,integer) from public;
revoke all on function public.list_teachers(text,text,text,integer,integer) from edusentia_worker_runtime;
grant execute on function public.list_teachers(text,text,text,integer,integer) to edusentia_worker_runtime;
revoke all on function public.get_teacher_record(uuid) from public;
revoke all on function public.get_teacher_record(uuid) from edusentia_worker_runtime;
grant execute on function public.get_teacher_record(uuid) to edusentia_worker_runtime;
revoke all on function public.get_my_teacher_profile() from public;
revoke all on function public.get_my_teacher_profile() from edusentia_worker_runtime;
grant execute on function public.get_my_teacher_profile() to edusentia_worker_runtime;
revoke all on function public.save_teacher(jsonb) from public;
revoke all on function public.save_teacher(jsonb) from edusentia_worker_runtime;
grant execute on function public.save_teacher(jsonb) to edusentia_worker_runtime;
revoke all on function public.archive_teacher(uuid,text) from public;
revoke all on function public.archive_teacher(uuid,text) from edusentia_worker_runtime;
grant execute on function public.archive_teacher(uuid,text) to edusentia_worker_runtime;
revoke all on function public.restore_teacher(uuid,text) from public;
revoke all on function public.restore_teacher(uuid,text) from edusentia_worker_runtime;
grant execute on function public.restore_teacher(uuid,text) to edusentia_worker_runtime;
revoke all on function public.set_teacher_photo(uuid,text,timestamp with time zone) from public;
revoke all on function public.set_teacher_photo(uuid,text,timestamp with time zone) from edusentia_worker_runtime;
grant execute on function public.set_teacher_photo(uuid,text,timestamp with time zone) to edusentia_worker_runtime;
revoke all on function public.list_headteachers(text,text,text,integer,integer) from public;
revoke all on function public.list_headteachers(text,text,text,integer,integer) from edusentia_worker_runtime;
grant execute on function public.list_headteachers(text,text,text,integer,integer) to edusentia_worker_runtime;
revoke all on function public.get_headteacher_record(uuid) from public;
revoke all on function public.get_headteacher_record(uuid) from edusentia_worker_runtime;
grant execute on function public.get_headteacher_record(uuid) to edusentia_worker_runtime;
revoke all on function public.get_my_headteacher_signature() from public;
revoke all on function public.get_my_headteacher_signature() from edusentia_worker_runtime;
grant execute on function public.get_my_headteacher_signature() to edusentia_worker_runtime;
revoke all on function public.save_headteacher(jsonb) from public;
revoke all on function public.save_headteacher(jsonb) from edusentia_worker_runtime;
grant execute on function public.save_headteacher(jsonb) to edusentia_worker_runtime;
revoke all on function public.archive_headteacher(uuid,text) from public;
revoke all on function public.archive_headteacher(uuid,text) from edusentia_worker_runtime;
grant execute on function public.archive_headteacher(uuid,text) to edusentia_worker_runtime;
revoke all on function public.restore_headteacher(uuid,text) from public;
revoke all on function public.restore_headteacher(uuid,text) from edusentia_worker_runtime;
grant execute on function public.restore_headteacher(uuid,text) to edusentia_worker_runtime;
revoke all on function public.set_headteacher_photo(uuid,text,timestamp with time zone) from public;
revoke all on function public.set_headteacher_photo(uuid,text,timestamp with time zone) from edusentia_worker_runtime;
grant execute on function public.set_headteacher_photo(uuid,text,timestamp with time zone) to edusentia_worker_runtime;
revoke all on function public.set_my_headteacher_signature(text,timestamp with time zone) from public;
revoke all on function public.set_my_headteacher_signature(text,timestamp with time zone) from edusentia_worker_runtime;
grant execute on function public.set_my_headteacher_signature(text,timestamp with time zone) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0038_certified_teacher_principal_crud')
on conflict do nothing;

update app.release_identity
set schema_version='0038'
where edition='Edusentia Enterprise Neon Edition';

commit;
