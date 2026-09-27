-- Keep one-click full-school backups below Cloudflare Free external
-- subrequest limits by recording R2 metadata and source-object inventory in
-- bounded Neon batches instead of one database request per object.
begin;

create or replace function public.backup_worker_record_object_batch(
  target_backup uuid,
  target_tenant uuid,
  target_actor uuid,
  target_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path=public,storage,pg_catalog
as $fn$
declare
  item jsonb;
  item_count integer;
  recorded integer:=0;
  v_object_key text;
  object_name text;
  object_type text;
  object_size bigint;
  inventory_type text;
  record_inventory boolean;
  source_bucket text;
  source_path text;
  backup_path text;
  original_size bigint;
  encrypted_size bigint;
  checksum text;
begin
  if target_backup is null or target_tenant is null or target_actor is null then
    raise exception 'backup, tenant and actor are required' using errcode='22023';
  end if;

  if jsonb_typeof(target_rows) is distinct from 'array' then
    raise exception 'backup object batch must be a JSON array' using errcode='22023';
  end if;

  item_count:=jsonb_array_length(target_rows);
  if item_count<1 or item_count>200 then
    raise exception 'backup object batch must contain between 1 and 200 items' using errcode='22023';
  end if;

  if not exists(
    select 1 from public.backup_exports
     where id=target_backup and status='processing' and backup_type='full'
  ) then
    raise exception 'Backup is not processing' using errcode='55000';
  end if;

  for item in select value from jsonb_array_elements(target_rows)
  loop
    v_object_key:=coalesce(item->>'r2_key','');
    object_name:=left(coalesce(nullif(item->>'r2_name',''),'backup-object'),512);
    object_type:=coalesce(nullif(item->>'r2_content_type',''),'application/octet-stream');
    object_size:=greatest(coalesce(nullif(item->>'r2_size','')::bigint,0),0);
    record_inventory:=coalesce((item->>'record_inventory')::boolean,false);

    if v_object_key='' or v_object_key not like 'tenants/'||target_tenant::text||'/system-backups/%' then
      raise exception 'invalid backup R2 tenant scope' using errcode='42501';
    end if;

    insert into storage.object_metadata(
      tenant_id,object_key,original_name,content_type,size_bytes,created_by,status,stored_at
    )
    values(
      target_tenant,v_object_key,object_name,object_type,object_size,target_actor,'active',now()
    )
    on conflict(tenant_id,object_key) do update set
      original_name=excluded.original_name,
      content_type=excluded.content_type,
      size_bytes=excluded.size_bytes,
      created_by=coalesce(storage.object_metadata.created_by,excluded.created_by),
      status='active',
      stored_at=now(),
      deleted_at=null;

    if record_inventory then
      source_bucket:=coalesce(item->>'source_bucket','');
      source_path:=coalesce(item->>'source_path','');
      backup_path:=coalesce(item->>'backup_path','');
      original_size:=greatest(coalesce(nullif(item->>'original_size','')::bigint,0),0);
      encrypted_size:=greatest(coalesce(nullif(item->>'encrypted_size','')::bigint,0),0);
      checksum:=lower(coalesce(item->>'checksum',''));
      inventory_type:=coalesce(nullif(item->>'content_type',''),'application/octet-stream');

      if source_bucket='' or source_path='' or backup_path='' or checksum='' then
        raise exception 'backup source inventory item is incomplete' using errcode='22023';
      end if;

      insert into public.backup_storage_objects(
        backup_export_id,source_bucket,source_path,backup_path,content_type,
        original_size,encrypted_size,checksum,status,error_message
      )
      values(
        target_backup,source_bucket,source_path,backup_path,inventory_type,
        original_size,encrypted_size,checksum,'completed',''
      );
    end if;

    recorded:=recorded+1;
  end loop;

  update public.backup_exports
     set heartbeat_at=now()
   where id=target_backup and status='processing';

  return recorded;
end
$fn$;

create or replace function public.backup_worker_mark_r2_deleted_batch(
  target_tenant uuid,
  target_keys jsonb
)
returns integer
language plpgsql
security definer
set search_path=storage,pg_catalog
as $fn$
declare changed integer;
begin
  if target_tenant is null then
    raise exception 'tenant is required' using errcode='22023';
  end if;
  if jsonb_typeof(target_keys) is distinct from 'array' or jsonb_array_length(target_keys)>500 then
    raise exception 'R2 deletion batch must be a JSON array with at most 500 keys' using errcode='22023';
  end if;

  if exists(
    select 1
      from jsonb_array_elements_text(target_keys) k(object_key)
     where k.object_key not like 'tenants/'||target_tenant::text||'/system-backups/%'
  ) then
    raise exception 'invalid backup R2 tenant scope' using errcode='42501';
  end if;

  update storage.object_metadata
     set status='deleted',deleted_at=now()
   where tenant_id=target_tenant
     and storage.object_metadata.object_key in (select jsonb_array_elements_text(target_keys));

  get diagnostics changed=row_count;
  return changed;
end
$fn$;

revoke all on function public.backup_worker_record_object_batch(uuid,uuid,uuid,jsonb) from public;
revoke all on function public.backup_worker_mark_r2_deleted_batch(uuid,jsonb) from public;
grant execute on function public.backup_worker_record_object_batch(uuid,uuid,uuid,jsonb) to edusentia_worker_runtime;
grant execute on function public.backup_worker_mark_r2_deleted_batch(uuid,jsonb) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0074_backup_worker_bulk_object_recording')
on conflict do nothing;

commit;
