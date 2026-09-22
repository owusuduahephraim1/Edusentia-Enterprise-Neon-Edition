-- Certified System Administrator school-logo parity for the Neon isolated tenant runtime.
-- Accepts only tenant-scoped R2 object keys and keeps both the compatibility school settings
-- record and the Neon tenant metadata in sync.
begin;

-- Reconciliation runs as edusentia_runtime, the existing certified function
-- owner; this preserves the established isolated-tenant runtime ACL boundary.
-- owner and the fixed tenant migration identity. Fail closed if an unexpected
-- owner is ever encountered rather than broadening the function's authority.
do $ownership$
declare
  existing_owner text;
begin
  select pg_get_userbyid(p.proowner)
  into existing_owner
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='set_school_logo_reference'
    and pg_get_function_identity_arguments(p.oid)='target_logo_url text'
  limit 1;

  if existing_owner is not null and existing_owner<>current_user then
    raise exception 'Unexpected owner % for public.set_school_logo_reference(text)',existing_owner;
  end if;
end
$ownership$;

create or replace function public.set_school_logo_reference(target_logo_url text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','storage','pg_catalog','extensions'
as $function$
declare
  v_tenant_id uuid:=app.current_tenant_id();
  school_id uuid;
  clean_logo text:=btrim(coalesce(target_logo_url,''));
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required' using errcode='42501';
  end if;
  if not public.is_system_admin() then
    raise exception 'Only the School System Administrator can change the official school logo' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit school logo changes' using errcode='42501';
  end if;

  select id into school_id
  from public.school_settings
  order by created_at,id
  limit 1
  for update;

  if school_id is null then
    raise exception 'School identity is unavailable' using errcode='P0002';
  end if;

  if clean_logo='assets/school-logo.png' then
    null;
  elsif clean_logo like ('tenants/'||v_tenant_id::text||'/school-branding/%') and clean_logo not like '%..%' then
    if not exists(
      select 1
      from storage.object_metadata m
      where m.tenant_id=v_tenant_id
        and m.object_key=clean_logo
        and m.status='active'
        and lower(m.content_type)='image/png'
    ) then
      raise exception 'The uploaded school logo was not found in protected R2 storage' using errcode='22023';
    end if;
  else
    raise exception 'Invalid school logo reference' using errcode='22023';
  end if;

  update public.school_settings
  set logo_url=clean_logo,
      updated_at=now()
  where id=school_id;

  return jsonb_build_object(
    'saved',true,
    'school_id',school_id,
    'logo_url',clean_logo,
    'message','Official school logo saved for future school documents.'
  );
end
$function$;

revoke all on function public.set_school_logo_reference(text) from public;
grant execute on function public.set_school_logo_reference(text) to edusentia_worker_runtime;


-- Canonical R2 object-reference parity for every upload-backed certified feature.
-- The Worker stores protected objects under tenants/<tenant_uuid>/<feature-scope>/...
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
  if clean_path<>'' then
    if app.current_tenant_id() is null or clean_path not like ('tenants/'||app.current_tenant_id()::text||'/staff-photos/%') or clean_path like '%..%' then raise exception 'Teacher photograph path is invalid' using errcode='22023';end if;
    if not exists(select 1 from storage.object_metadata m where m.tenant_id=app.current_tenant_id() and m.object_key=clean_path and m.status='active' and lower(m.content_type) like 'image/%') then raise exception 'The uploaded teacher photograph is not available in protected storage' using errcode='22023';end if;
  end if;
  update public.teachers set photo_url=clean_path,updated_at=now() where id=target_teacher_id returning * into t;
  return public.get_teacher_record(target_teacher_id);
end$function$;

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
  if clean_path<>'' then
    if app.current_tenant_id() is null or clean_path not like ('tenants/'||app.current_tenant_id()::text||'/staff-photos/%') or clean_path like '%..%' then raise exception 'Principal photograph path is invalid' using errcode='22023';end if;
    if not exists(select 1 from storage.object_metadata m where m.tenant_id=app.current_tenant_id() and m.object_key=clean_path and m.status='active' and lower(m.content_type) like 'image/%') then raise exception 'The uploaded Principal photograph is not available in protected storage' using errcode='22023';end if;
  end if;
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
  if clean_path<>'' then
    if app.current_tenant_id() is null or clean_path not like ('tenants/'||app.current_tenant_id()::text||'/principal-signatures/%') or clean_path like '%..%' then raise exception 'Signature storage path is invalid' using errcode='22023'; end if;
    if not exists(select 1 from storage.object_metadata m where m.tenant_id=app.current_tenant_id() and m.object_key=clean_path and m.status='active' and lower(m.content_type) like 'image/%') then raise exception 'The uploaded Principal signature is not available in protected storage' using errcode='22023'; end if;
  end if;
  perform set_config('app.change_reason',case when clean_path='' then 'Principal signature removed' else 'Principal signature updated' end,true);
  update public.headteachers set signature_path=clean_path,signature_updated_at=case when clean_path='' then null else now() end,updated_at=now() where id=hid;
  return public.get_my_headteacher_signature();
end $function$;

CREATE OR REPLACE FUNCTION public.set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_updated timestamptz; affected integer;
begin
  if auth.uid() is null or not public.can_manage_student(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(target_photo_url,''))='' or app.current_tenant_id() is null or target_photo_url not like ('tenants/'||app.current_tenant_id()::text||'/student-photos/%') or target_photo_url like '%..%' then raise exception 'Student photograph path is invalid' using errcode='22023'; end if;
  if not exists(select 1 from storage.object_metadata m where m.tenant_id=app.current_tenant_id() and m.object_key=btrim(target_photo_url) and m.status='active' and lower(m.content_type) like 'image/%') then raise exception 'The uploaded student photograph is not available in protected storage' using errcode='22023'; end if;
  select updated_at into current_updated from public.students where id=target_student_id and deleted_at is null for update;
  if not found then raise exception 'Student record not found'; end if;
  if expected_updated_at is not null and current_updated is distinct from expected_updated_at then raise exception 'Student record changed by another user' using errcode='40001'; end if;
  perform set_config('app.change_reason','Student photograph updated',true);
  update public.students set photo_url=target_photo_url,updated_at=now() where id=target_student_id and deleted_at is null;
  get diagnostics affected=row_count; if affected<>1 then raise exception 'Student photograph was not saved'; end if;
  return public.get_student_record_v5(target_student_id);
end $function$;

CREATE OR REPLACE FUNCTION public.save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result public.report_card_templates;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  if target_range_key not in ('early_years','basic_1_6','basic_7_9') then raise exception 'Invalid report-card class range'; end if;
  if coalesce(btrim(target_storage_path),'')='' or app.current_tenant_id() is null or target_storage_path not like ('tenants/'||app.current_tenant_id()::text||'/report-card-templates/%') or target_storage_path like '%..%' then raise exception 'Invalid template storage path' using errcode='22023'; end if;
  if coalesce(btrim(target_original_name),'')='' or length(target_original_name)>255 then raise exception 'Invalid template file name'; end if;
  if target_mime_type not in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception 'Unsupported template file type'; end if;
  if coalesce(target_file_size,0)<=0 or target_file_size>20971520 then raise exception 'Template file must be between 1 byte and 20 MB'; end if;
  if not exists(select 1 from storage.object_metadata m where m.tenant_id=app.current_tenant_id() and m.object_key=btrim(target_storage_path) and m.status='active' and lower(m.content_type)=lower(target_mime_type) and m.size_bytes=target_file_size) then raise exception 'The uploaded report-card template is not available in protected storage' using errcode='22023'; end if;
  if coalesce(length(target_checksum),0)>128 then raise exception 'Invalid template checksum'; end if;
  insert into public.report_card_templates(
    range_key,storage_path,original_name,mime_type,file_size,checksum,version,active,uploaded_by
  ) values(
    target_range_key,btrim(target_storage_path),btrim(target_original_name),target_mime_type,target_file_size,coalesce(target_checksum,''),1,true,auth.uid()
  )
  on conflict(range_key) do update set
    storage_path=excluded.storage_path,
    original_name=excluded.original_name,
    mime_type=excluded.mime_type,
    file_size=excluded.file_size,
    checksum=excluded.checksum,
    version=public.report_card_templates.version+1,
    active=true,
    uploaded_by=auth.uid(),
    updated_at=now()
  returning * into result;
  return to_jsonb(result);
end $function$;

CREATE OR REPLACE FUNCTION public.save_certificate_template(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  tid uuid:=public.safe_uuid(payload->>'id');
  ctype text:=btrim(coalesce(payload->>'certificate_type',''));
  result public.certificate_templates;
  has_file_payload boolean:=payload ? 'storage_path';
  new_storage_path text:=btrim(coalesce(payload->>'storage_path',''));
  new_original_name text:=btrim(coalesce(payload->>'original_name',''));
  new_mime_type text:=btrim(coalesce(payload->>'mime_type',''));
  new_file_size bigint:=coalesce(nullif(payload->>'file_size','')::bigint,0);
  new_checksum text:=lower(btrim(coalesce(payload->>'checksum','')));
begin
  if not public.can_manage_certificates() then
    raise exception 'Only the System Administrator can manage certificate templates' using errcode='42501';
  end if;
  if ctype not in ('student_promotion','jhs_completion','teacher_recognition') then
    raise exception 'Certificate type is invalid';
  end if;
  if btrim(coalesce(payload->>'title',''))='' or btrim(coalesce(payload->>'statement_template',''))='' then
    raise exception 'Certificate title and statement are required';
  end if;
  if length(btrim(payload->>'title'))>120 or length(btrim(payload->>'statement_template'))>800 then
    raise exception 'Certificate title or statement is too long';
  end if;
  if has_file_payload then
    if new_storage_path='' or app.current_tenant_id() is null or new_storage_path not like ('tenants/'||app.current_tenant_id()::text||'/certificate-templates/%') or new_storage_path like '%..%' then raise exception 'Certificate template storage path is invalid' using errcode='22023'; end if;
    if new_original_name='' or length(new_original_name)>255 then raise exception 'Certificate template filename is invalid'; end if;
    if new_mime_type not in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception 'Unsupported certificate template file type'; end if;
    if new_file_size<=0 or new_file_size>20971520 then raise exception 'Certificate template must be between 1 byte and 20 MB'; end if;
    if not exists(select 1 from storage.object_metadata m where m.tenant_id=app.current_tenant_id() and m.object_key=new_storage_path and m.status='active' and lower(m.content_type)=lower(new_mime_type) and m.size_bytes=new_file_size) then raise exception 'The uploaded certificate template is not available in protected storage' using errcode='22023'; end if;
    if length(new_checksum)>128 then raise exception 'Certificate template checksum is invalid'; end if;
  end if;
  update public.certificate_templates
  set active=false,updated_at=now()
  where certificate_type=ctype and active and (tid is null or id<>tid);
  if tid is null then
    insert into public.certificate_templates(
      certificate_type,name,title,subtitle,statement_template,footer_text,primary_colour,accent_colour,active,
      storage_path,original_name,mime_type,file_size,checksum,version,uploaded_by
    )
    values(
      ctype,coalesce(nullif(btrim(payload->>'name'),''),public.certificate_type_label(ctype)),
      btrim(payload->>'title'),btrim(coalesce(payload->>'subtitle','')),btrim(payload->>'statement_template'),
      btrim(coalesce(payload->>'footer_text','')),coalesce(nullif(payload->>'primary_colour',''),'#0a2f73'),
      coalesce(nullif(payload->>'accent_colour',''),'#f1b51c'),true,
      case when has_file_payload then new_storage_path else '' end,
      case when has_file_payload then new_original_name else '' end,
      case when has_file_payload then new_mime_type else '' end,
      case when has_file_payload then new_file_size else 0 end,
      case when has_file_payload then new_checksum else '' end,
      1,case when has_file_payload then auth.uid() else null end
    )
    returning * into result;
  else
    update public.certificate_templates
    set name=coalesce(nullif(btrim(payload->>'name'),''),name),
        title=btrim(payload->>'title'),
        subtitle=btrim(coalesce(payload->>'subtitle','')),
        statement_template=btrim(payload->>'statement_template'),
        footer_text=btrim(coalesce(payload->>'footer_text','')),
        primary_colour=coalesce(nullif(payload->>'primary_colour',''),primary_colour),
        accent_colour=coalesce(nullif(payload->>'accent_colour',''),accent_colour),
        active=true,
        storage_path=case when has_file_payload then new_storage_path else storage_path end,
        original_name=case when has_file_payload then new_original_name else original_name end,
        mime_type=case when has_file_payload then new_mime_type else mime_type end,
        file_size=case when has_file_payload then new_file_size else file_size end,
        checksum=case when has_file_payload then new_checksum else checksum end,
        version=case when has_file_payload then version+1 else version end,
        uploaded_by=case when has_file_payload then auth.uid() else uploaded_by end,
        updated_at=now()
    where id=tid
    returning * into result;
  end if;
  if result.id is null then raise exception 'Certificate template not found'; end if;
  if has_file_payload then
    perform public.record_certificate_event(
      null,null,'certificate_template_design_uploaded','',
      jsonb_build_object(
        'certificate_type',ctype,'storage_path',result.storage_path,'original_name',result.original_name,
        'mime_type',result.mime_type,'file_size',result.file_size,'checksum',result.checksum,'version',result.version
      )
    );
  end if;
  return to_jsonb(result);
end $function$;

revoke all on function public.set_teacher_photo(uuid,text,timestamp with time zone) from public;
grant execute on function public.set_teacher_photo(uuid,text,timestamp with time zone) to edusentia_worker_runtime;
revoke all on function public.set_headteacher_photo(uuid,text,timestamp with time zone) from public;
grant execute on function public.set_headteacher_photo(uuid,text,timestamp with time zone) to edusentia_worker_runtime;
revoke all on function public.set_my_headteacher_signature(text,timestamp with time zone) from public;
grant execute on function public.set_my_headteacher_signature(text,timestamp with time zone) to edusentia_worker_runtime;
revoke all on function public.set_student_photo(uuid,text,timestamp with time zone) from public;
grant execute on function public.set_student_photo(uuid,text,timestamp with time zone) to edusentia_worker_runtime;
revoke all on function public.save_report_card_template(text,text,text,text,bigint,text) from public;
grant execute on function public.save_report_card_template(text,text,text,text,bigint,text) to edusentia_worker_runtime;
revoke all on function public.save_certificate_template(jsonb) from public;
grant execute on function public.save_certificate_template(jsonb) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0049w_school_identity_logo_parity')
on conflict do nothing;

commit;
