-- Neon/R2 Principal photograph authorization, canonical reference, and protected read contract.
-- Mirrors the certified Supabase staff-photos semantics while using Neon request context.
-- New Principal photo_url values are stored as <headteacher_uuid>/<object_name>.
-- Physical R2 objects remain tenant-scoped under tenants/<tenant_uuid>/staff-photos/.
-- Legacy full tenant-scoped staff-photo keys remain readable until replaced.
begin;

create or replace function public.neon_authorize_headteacher_photo_upload(target_headteacher_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public','app','extensions'
as $function$
declare h public.headteachers%rowtype;
begin
  select * into h from public.headteachers where id=target_headteacher_id and deleted_at is null for update;
  if h.id is null then raise exception 'Principal record not found'; end if;
  if app.current_user_id() is null or not (public.is_system_admin() or h.profile_id=app.current_user_id()) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';
  end if;
  return true;
end
$function$;

create or replace function public.neon_headteacher_photo_descriptor(target_headteacher_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','app','extensions'
as $function$
declare h public.headteachers%rowtype;
begin
  select * into h from public.headteachers where id=target_headteacher_id and deleted_at is null;
  if h.id is null then raise exception 'Principal record not found'; end if;
  if app.current_user_id() is null or not (public.is_system_admin() or h.profile_id=app.current_user_id()) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return jsonb_build_object('headteacher_id',h.id,'photo_url',coalesce(h.photo_url,''));
end
$function$;

create or replace function public.set_headteacher_photo(
  target_headteacher_id uuid,
  target_photo_url text,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','storage','extensions','pg_catalog'
as $function$
declare
  h public.headteachers%rowtype;
  clean_path text:=btrim(coalesce(target_photo_url,''));
  v_tenant_id uuid:=app.current_tenant_id();
  v_actor_id uuid:=app.current_user_id();
  v_path_headteacher_id uuid;
  v_object_key text;
  v_legacy_prefix text;
  v_legacy_tail text;
  v_keep_legacy_full_key boolean:=false;
begin
  select * into h from public.headteachers where id=target_headteacher_id and deleted_at is null for update;
  if h.id is null then raise exception 'Principal record not found'; end if;
  if v_actor_id is null or not (public.is_system_admin() or h.profile_id=v_actor_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';
  end if;
  if expected_updated_at is not null and h.updated_at is distinct from expected_updated_at then
    raise exception 'Principal record changed by another user' using errcode='40001';
  end if;

  if clean_path<>'' then
    if v_tenant_id is null then raise exception 'Principal photograph tenant context is unavailable' using errcode='42501'; end if;
    v_legacy_prefix:='tenants/'||v_tenant_id::text||'/staff-photos/';
    if clean_path like (v_legacy_prefix||'%') then
      v_legacy_tail:=substr(clean_path,length(v_legacy_prefix)+1);
      if position('/' in v_legacy_tail)=0 then
        v_object_key:=clean_path;
        v_keep_legacy_full_key:=true;
      else
        clean_path:=v_legacy_tail;
      end if;
    end if;

    if not v_keep_legacy_full_key then
      if clean_path like '%..%' or clean_path like '/%' or position('/' in clean_path)=0
         or split_part(clean_path,'/',2)='' or split_part(clean_path,'/',3)<>'' then
        raise exception 'Principal photograph path is invalid' using errcode='22023';
      end if;
      v_path_headteacher_id:=public.safe_uuid(split_part(clean_path,'/',1));
      if v_path_headteacher_id is null or v_path_headteacher_id<>target_headteacher_id then
        raise exception 'Principal photograph path is invalid' using errcode='22023';
      end if;
      if split_part(clean_path,'/',1)<>target_headteacher_id::text then
        clean_path:=target_headteacher_id::text||'/'||split_part(clean_path,'/',2);
      end if;
      v_object_key:='tenants/'||v_tenant_id::text||'/staff-photos/'||clean_path;
    end if;

    if not exists(
      select 1 from storage.object_metadata m
      where m.tenant_id=v_tenant_id and m.object_key=v_object_key and m.status='active'
        and lower(m.content_type) like 'image/%'
    ) then
      raise exception 'The uploaded Principal photograph is not available in protected storage' using errcode='22023';
    end if;
  end if;

  perform set_config('app.change_reason','Principal photograph updated',true);
  update public.headteachers set photo_url=clean_path,updated_at=now()
  where id=target_headteacher_id returning * into h;
  return public.get_headteacher_record(target_headteacher_id);
end
$function$;

revoke all on function public.neon_authorize_headteacher_photo_upload(uuid) from public;
revoke all on function public.neon_headteacher_photo_descriptor(uuid) from public;
revoke all on function public.set_headteacher_photo(uuid,text,timestamptz) from public;
grant execute on function public.neon_authorize_headteacher_photo_upload(uuid) to edusentia_worker_runtime;
grant execute on function public.neon_headteacher_photo_descriptor(uuid) to edusentia_worker_runtime;
grant execute on function public.set_headteacher_photo(uuid,text,timestamptz) to edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0060_principal_photo_r2_contract') on conflict do nothing;
commit;
