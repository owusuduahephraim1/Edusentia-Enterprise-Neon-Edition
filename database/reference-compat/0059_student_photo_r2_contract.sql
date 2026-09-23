-- Neon/R2 student photograph authorization, canonical reference, and protected read contract.
-- Permanent parity guard for upload, persistence, protected retrieval, and legacy full-key reads.
-- Certified Supabase stores new student photo references as <student_uuid>/<object_name>.
-- R2 stores the physical object under tenants/<tenant_uuid>/student-photos/<student_uuid>/<object_name>.
-- Older Neon full-key references remain readable until the photograph is replaced.
begin;

create or replace function public.neon_authorize_student_photo_upload(target_student_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public','app','extensions'
as $function$
begin
  if app.current_user_id() is null then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not exists(select 1 from public.students s where s.id=target_student_id and s.deleted_at is null) then
    raise exception 'Student record not found';
  end if;
  if not public.can_manage_student(target_student_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit student record changes' using errcode='42501';
  end if;
  return true;
end
$function$;

create or replace function public.neon_student_photo_descriptor(target_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','app','extensions'
as $function$
declare s public.students%rowtype;
begin
  select * into s from public.students where id=target_student_id;
  if s.id is null then raise exception 'Student record not found'; end if;
  if app.current_user_id() is null or not public.can_view_student(target_student_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return jsonb_build_object('student_id',s.id,'photo_url',coalesce(s.photo_url,''),'archived',s.deleted_at is not null);
end
$function$;

create or replace function public.set_student_photo(
  target_student_id uuid,
  target_photo_url text,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','storage','extensions','pg_catalog'
as $function$
declare
  s public.students%rowtype;
  clean_path text:=btrim(coalesce(target_photo_url,''));
  v_tenant_id uuid:=app.current_tenant_id();
  v_actor_id uuid:=app.current_user_id();
  v_path_student_id uuid;
  v_object_key text;
  v_legacy_prefix text;
  v_legacy_tail text;
  v_keep_legacy_full_key boolean:=false;
begin
  select * into s from public.students where id=target_student_id and deleted_at is null for update;
  if s.id is null then raise exception 'Student record not found'; end if;
  if v_actor_id is null or not public.can_manage_student(target_student_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit student record changes' using errcode='42501';
  end if;
  if expected_updated_at is not null and s.updated_at is distinct from expected_updated_at then
    raise exception 'Student record changed by another user' using errcode='40001';
  end if;
  if clean_path='' then raise exception 'Student photograph path is invalid' using errcode='22023'; end if;
  if v_tenant_id is null then raise exception 'Student photograph tenant context is unavailable' using errcode='42501'; end if;

  v_legacy_prefix:='tenants/'||v_tenant_id::text||'/student-photos/';
  if clean_path like (v_legacy_prefix||'%') then
    v_legacy_tail:=substr(clean_path,length(v_legacy_prefix)+1);
    if position('/' in v_legacy_tail)=0 then
      -- Backward compatibility for pre-0059 uploads, which were stored directly under student-photos/.
      v_object_key:=clean_path;
      v_keep_legacy_full_key:=true;
    else
      clean_path:=v_legacy_tail;
    end if;
  end if;

  if not v_keep_legacy_full_key then
    if clean_path like '%..%' or clean_path like '/%' or position('/' in clean_path)=0
       or split_part(clean_path,'/',2)='' or split_part(clean_path,'/',3)<>'' then
      raise exception 'Student photograph path is invalid' using errcode='22023';
    end if;
    v_path_student_id:=public.safe_uuid(split_part(clean_path,'/',1));
    if v_path_student_id is null or v_path_student_id<>target_student_id then
      raise exception 'Student photograph path is invalid' using errcode='22023';
    end if;
    if split_part(clean_path,'/',1)<>target_student_id::text then
      clean_path:=target_student_id::text||'/'||split_part(clean_path,'/',2);
    end if;
    v_object_key:='tenants/'||v_tenant_id::text||'/student-photos/'||clean_path;
  end if;

  if not exists(
    select 1 from storage.object_metadata m
    where m.tenant_id=v_tenant_id and m.object_key=v_object_key and m.status='active'
      and lower(m.content_type) like 'image/%'
  ) then
    raise exception 'The uploaded student photograph is not available in protected storage' using errcode='22023';
  end if;

  perform set_config('app.change_reason','Student photograph updated',true);
  update public.students set photo_url=clean_path,updated_at=now() where id=target_student_id returning * into s;
  return public.get_student_record_v5(target_student_id);
end
$function$;

revoke all on function public.neon_authorize_student_photo_upload(uuid) from public;
revoke all on function public.neon_student_photo_descriptor(uuid) from public;
revoke all on function public.set_student_photo(uuid,text,timestamptz) from public;
grant execute on function public.neon_authorize_student_photo_upload(uuid) to edusentia_worker_runtime;
grant execute on function public.neon_student_photo_descriptor(uuid) to edusentia_worker_runtime;
grant execute on function public.set_student_photo(uuid,text,timestamptz) to edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0059_student_photo_r2_contract') on conflict do nothing;
commit;
