-- Reconcile the live Neon teacher-photo save contract with the certified
-- Supabase teacher-relative photo_url contract.
--
-- R2 stores the physical object under:
--   tenants/<tenant_uuid>/staff-photos/<teacher_uuid>/<object_name>
-- while public.teachers.photo_url stores only:
--   <teacher_uuid>/<object_name>
--
-- This preserves certified application semantics, keeps tenant isolation in the
-- Worker/R2 layer, and verifies that the referenced R2 metadata is active.
begin;

create or replace function public.set_teacher_photo(
  target_teacher_id uuid,
  target_photo_url text,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','storage','extensions','pg_catalog'
as $function$
declare
  t public.teachers%rowtype;
  clean_path text:=btrim(coalesce(target_photo_url,''));
  v_tenant_id uuid:=app.current_tenant_id();
  v_actor_id uuid:=app.current_user_id();
  v_path_teacher_id uuid;
  v_object_key text;
  v_legacy_prefix text;
begin
  select * into t
  from public.teachers
  where id=target_teacher_id
    and deleted_at is null
  for update;

  if t.id is null then
    raise exception 'Teacher record not found';
  end if;

  if not (public.is_system_admin() or t.profile_id=v_actor_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;

  perform public.require_sensitive_access();

  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes'
      using errcode='42501';
  end if;

  if expected_updated_at is not null and t.updated_at is distinct from expected_updated_at then
    raise exception 'Teacher record changed by another user' using errcode='40001';
  end if;

  if clean_path<>'' then
    if v_tenant_id is null then
      raise exception 'Teacher photograph tenant context is unavailable' using errcode='42501';
    end if;

    -- Tolerate a tenant-scoped R2 key from a stale client, but canonicalize the
    -- persisted value back to the certified teacher-relative representation.
    v_legacy_prefix:='tenants/'||v_tenant_id::text||'/staff-photos/';
    if clean_path like (v_legacy_prefix||'%') then
      clean_path:=substr(clean_path,length(v_legacy_prefix)+1);
    end if;

    if clean_path like '%..%'
       or clean_path like '/%'
       or position('/' in clean_path)=0
       or split_part(clean_path,'/',2)=''
       or split_part(clean_path,'/',3)<>'' then
      raise exception 'Teacher photograph path is invalid' using errcode='22023';
    end if;

    v_path_teacher_id:=public.safe_uuid(split_part(clean_path,'/',1));
    if v_path_teacher_id is null or v_path_teacher_id<>target_teacher_id then
      raise exception 'Teacher photograph path is invalid' using errcode='22023';
    end if;

    if split_part(clean_path,'/',1)<>target_teacher_id::text then
      clean_path:=target_teacher_id::text||'/'||split_part(clean_path,'/',2);
    end if;

    v_object_key:='tenants/'||v_tenant_id::text||'/staff-photos/'||clean_path;

    if not exists(
      select 1
      from storage.object_metadata m
      where m.tenant_id=v_tenant_id
        and m.object_key=v_object_key
        and m.status='active'
        and lower(m.content_type) like 'image/%'
    ) then
      raise exception 'The uploaded teacher photograph is not available in protected storage'
        using errcode='22023';
    end if;
  end if;

  update public.teachers
  set photo_url=clean_path,
      updated_at=now()
  where id=target_teacher_id
  returning * into t;

  return public.get_teacher_record(target_teacher_id);
end
$function$;

revoke all on function public.set_teacher_photo(uuid,text,timestamptz) from public;
grant execute on function public.set_teacher_photo(uuid,text,timestamptz) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0057_teacher_photo_reference_contract')
on conflict do nothing;

commit;
