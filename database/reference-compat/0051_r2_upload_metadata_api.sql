-- Harden tenant-scoped R2 upload metadata access behind certified Worker RPC helpers.
-- Direct browser-facing Worker routes must not depend on raw table DML under forced RLS.
begin;

create or replace function public.prepare_object_upload(
  target_object_key text,
  target_original_name text,
  target_content_type text,
  target_size_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','storage','pg_catalog'
as $function$
declare
  tid uuid:=app.current_tenant_id();
  actor uuid:=auth.uid();
  clean_key text:=btrim(coalesce(target_object_key,''));
  clean_name text:=left(btrim(coalesce(target_original_name,'')),120);
  clean_type text:=lower(split_part(btrim(coalesce(target_content_type,'')),';',1));
  object_id uuid;
begin
  if tid is null or actor is null then
    raise exception 'Authenticated tenant context is required' using errcode='42501';
  end if;
  if clean_key='' or clean_key not like ('tenants/'||tid::text||'/%') or clean_key like '%..%' then
    raise exception 'Invalid tenant object scope' using errcode='22023';
  end if;
  if clean_name='' then
    raise exception 'Original file name is required' using errcode='22023';
  end if;
  if clean_type='' then
    raise exception 'File content type is required' using errcode='22023';
  end if;
  if target_size_bytes is null or target_size_bytes<=0 or target_size_bytes>20*1024*1024 then
    raise exception 'File size must be between 1 byte and 20 MB' using errcode='22023';
  end if;

  insert into storage.object_metadata(
    tenant_id,object_key,original_name,content_type,size_bytes,created_by,status
  ) values(
    tid,clean_key,clean_name,clean_type,target_size_bytes,actor,'pending'
  )
  returning id into object_id;

  return jsonb_build_object(
    'id',object_id,
    'object_key',clean_key,
    'original_name',clean_name,
    'content_type',clean_type,
    'size_bytes',target_size_bytes,
    'status','pending'
  );
end
$function$;

create or replace function public.get_object_upload_metadata(
  target_object_key text,
  target_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','app','storage','pg_catalog'
as $function$
declare
  tid uuid:=app.current_tenant_id();
  actor uuid:=auth.uid();
  clean_key text:=btrim(coalesce(target_object_key,''));
  clean_status text:=nullif(lower(btrim(coalesce(target_status,''))),'');
  result jsonb;
begin
  if tid is null or actor is null then
    raise exception 'Authenticated tenant context is required' using errcode='42501';
  end if;
  if clean_key='' or clean_key not like ('tenants/'||tid::text||'/%') or clean_key like '%..%' then
    raise exception 'Invalid tenant object scope' using errcode='22023';
  end if;
  if clean_status is not null and clean_status not in ('pending','active','quarantined','deleted') then
    raise exception 'Invalid object status' using errcode='22023';
  end if;

  select jsonb_build_object(
    'id',m.id,
    'object_key',m.object_key,
    'original_name',m.original_name,
    'content_type',m.content_type,
    'size_bytes',m.size_bytes,
    'status',m.status,
    'created_by',m.created_by,
    'created_at',m.created_at,
    'stored_at',m.stored_at,
    'deleted_at',m.deleted_at
  )
  into result
  from storage.object_metadata m
  where m.tenant_id=tid
    and m.object_key=clean_key
    and (clean_status is null or m.status=clean_status)
  limit 1;

  return result;
end
$function$;

create or replace function public.transition_object_upload(
  target_object_id uuid,
  target_from_status text,
  target_to_status text
)
returns boolean
language plpgsql
security definer
set search_path to 'public','app','storage','pg_catalog'
as $function$
declare
  tid uuid:=app.current_tenant_id();
  actor uuid:=auth.uid();
  from_status text:=lower(btrim(coalesce(target_from_status,'')));
  to_status text:=lower(btrim(coalesce(target_to_status,'')));
  changed integer:=0;
begin
  if tid is null or actor is null then
    raise exception 'Authenticated tenant context is required' using errcode='42501';
  end if;
  if not (
    (from_status='pending' and to_status in ('active','quarantined'))
    or (from_status='active' and to_status='deleted')
  ) then
    raise exception 'Invalid object status transition' using errcode='22023';
  end if;

  update storage.object_metadata
  set status=to_status,
      stored_at=case when to_status='active' then coalesce(stored_at,now()) else stored_at end,
      deleted_at=case when to_status='deleted' then now() else deleted_at end
  where id=target_object_id
    and tenant_id=tid
    and status=from_status;

  get diagnostics changed=row_count;
  return changed=1;
end
$function$;

revoke all on function public.prepare_object_upload(text,text,text,bigint) from public;
revoke all on function public.get_object_upload_metadata(text,text) from public;
revoke all on function public.transition_object_upload(uuid,text,text) from public;
grant execute on function public.prepare_object_upload(text,text,text,bigint) to edusentia_worker_runtime;
grant execute on function public.get_object_upload_metadata(text,text) to edusentia_worker_runtime;
grant execute on function public.transition_object_upload(uuid,text,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0051_r2_upload_metadata_api')
on conflict do nothing;

commit;
