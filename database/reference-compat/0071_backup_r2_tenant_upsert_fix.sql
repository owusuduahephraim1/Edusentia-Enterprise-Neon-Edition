-- Repair tenant-scoped R2 backup metadata upserts for existing Neon schools.
-- storage.object_metadata is unique by (tenant_id, object_key), not object_key alone.
begin;

create or replace function public.backup_worker_register_r2_object(
  target_tenant uuid,target_key text,target_name text,target_content_type text,
  target_size bigint,target_actor uuid
)
returns uuid
language plpgsql
security definer
set search_path=storage,pg_catalog
as $fn$
declare object_id uuid;
begin
  if target_key not like 'tenants/'||target_tenant::text||'/%' then
    raise exception 'invalid R2 tenant scope' using errcode='42501';
  end if;

  insert into storage.object_metadata(
    tenant_id,object_key,original_name,content_type,size_bytes,created_by,status,stored_at
  )
  values(
    target_tenant,target_key,left(coalesce(target_name,'backup-object'),512),
    coalesce(nullif(target_content_type,''),'application/octet-stream'),
    greatest(target_size,0),target_actor,'active',now()
  )
  on conflict(tenant_id,object_key) do update set
    original_name=excluded.original_name,
    content_type=excluded.content_type,
    size_bytes=excluded.size_bytes,
    created_by=coalesce(storage.object_metadata.created_by,excluded.created_by),
    status='active',
    stored_at=now(),
    deleted_at=null
  returning id into object_id;

  return object_id;
end
$fn$;

revoke all on function public.backup_worker_register_r2_object(uuid,text,text,text,bigint,uuid) from public;
grant execute on function public.backup_worker_register_r2_object(uuid,text,text,text,bigint,uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0071_backup_r2_tenant_upsert_fix')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
