-- Restore, recovery-rehearsal and retention helpers for the Neon/R2 Worker.
begin;

create or replace function public.backup_worker_reconcile_auth_user(
  target_old_id uuid,
  target_email text,
  target_phone text,
  target_user_meta jsonb,
  target_app_meta jsonb
)
returns uuid
language plpgsql
security definer
set search_path=authn,extensions,pg_catalog
as $fn$
declare
  result_id uuid;
  normalized_email text:=lower(btrim(coalesce(target_email,'')));
begin
  if normalized_email='' or normalized_email not like '%@%' then
    raise exception 'restore auth email is invalid' using errcode='22023';
  end if;

  select id into result_id from authn.users where lower(email)=normalized_email limit 1;
  if result_id is not null then
    update authn.users
       set phone=coalesce(nullif(btrim(target_phone),''),phone),
           raw_user_meta_data=coalesce(target_user_meta,'{}'::jsonb),
           raw_app_meta_data=coalesce(target_app_meta,'{}'::jsonb),
           updated_at=now()
     where id=result_id;
    return result_id;
  end if;

  result_id:=target_old_id;
  if result_id is null or exists(select 1 from authn.users where id=result_id) then
    result_id:=gen_random_uuid();
  end if;

  insert into authn.users(id,email,display_name,phone,raw_user_meta_data,raw_app_meta_data)
  values(
    result_id,
    normalized_email,
    coalesce(nullif(target_user_meta->>'full_name',''),split_part(normalized_email,'@',1)),
    nullif(btrim(target_phone),''),
    coalesce(target_user_meta,'{}'::jsonb),
    coalesce(target_app_meta,'{}'::jsonb)
  );
  return result_id;
end
$fn$;

create or replace function public.backup_worker_rebuild_memberships(target_tenant uuid)
returns integer
language plpgsql
security definer
set search_path=app,public,authn,pg_catalog
as $fn$
declare changed integer:=0;
begin
  delete from app.tenant_memberships m
   where m.tenant_id=target_tenant
     and not exists(select 1 from public.profiles p where p.id=m.user_id);

  insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required)
  select
    target_tenant,
    p.id,
    public.current_app_role_for(p.role),
    case when p.active then 'active' else 'suspended' end,
    coalesce(p.mfa_required,false)
  from public.profiles p
  join authn.users u on u.id=p.id
  on conflict(tenant_id,user_id) do update set
    role=excluded.role,
    status=excluded.status,
    mfa_required=excluded.mfa_required;

  get diagnostics changed=row_count;
  return changed;
end
$fn$;

create or replace function public.backup_worker_recovery_test_begin(
  target_backup uuid,target_actor uuid
)
returns uuid
language plpgsql
security definer
set search_path=public,extensions,pg_catalog
as $fn$
declare result_id uuid;
begin
  insert into public.recovery_test_runs(
    backup_export_id,test_type,status,notes,error_message,initiated_by,started_at
  )
  values(
    target_backup,'encrypted_restore_rehearsal','processing',
    'Recovery rehearsal started. Production data will not be overwritten.','',
    target_actor,now()
  )
  returning id into result_id;
  return result_id;
end
$fn$;

create or replace function public.backup_worker_recovery_test_complete(
  target_run uuid,target_status text,target_tables integer,target_rows bigint,
  target_objects integer,target_bytes bigint,target_notes text,target_error text
)
returns void
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
begin
  if target_status not in ('passed','failed') then
    raise exception 'invalid recovery-test status' using errcode='22023';
  end if;
  update public.recovery_test_runs
     set status=target_status,
         checked_tables=greatest(target_tables,0),
         checked_rows=greatest(target_rows,0),
         checked_storage_objects=greatest(target_objects,0),
         checked_storage_bytes=greatest(target_bytes,0),
         notes=left(coalesce(target_notes,''),4000),
         error_message=left(coalesce(target_error,''),2000),
         completed_at=now()
   where id=target_run;
end
$fn$;

create or replace function public.backup_worker_purge_backup(target_backup uuid)
returns boolean
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare row_status text;row_expires timestamptz;
begin
  select status,expires_at into row_status,row_expires
    from public.backup_exports where id=target_backup for update;
  if row_status is null then return false; end if;
  if exists(select 1 from public.recovery_test_runs where backup_export_id=target_backup)
     or exists(select 1 from public.school_restore_jobs where pre_restore_backup_id=target_backup) then
    return false;
  end if;
  if row_status<>'failed' and not (row_status='completed' and row_expires is not null and row_expires<now()) then
    return false;
  end if;
  delete from public.backup_exports where id=target_backup;
  return found;
end
$fn$;

revoke all on function public.backup_worker_reconcile_auth_user(uuid,text,text,jsonb,jsonb) from public;
revoke all on function public.backup_worker_rebuild_memberships(uuid) from public;
revoke all on function public.backup_worker_recovery_test_begin(uuid,uuid) from public;
revoke all on function public.backup_worker_recovery_test_complete(uuid,text,integer,bigint,integer,bigint,text,text) from public;
revoke all on function public.backup_worker_purge_backup(uuid) from public;

grant execute on function public.backup_worker_reconcile_auth_user(uuid,text,text,jsonb,jsonb) to edusentia_worker_runtime;
grant execute on function public.backup_worker_rebuild_memberships(uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_recovery_test_begin(uuid,uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_recovery_test_complete(uuid,text,integer,bigint,integer,bigint,text,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_purge_backup(uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0048m_restore_worker_helpers')
on conflict do nothing;

commit;
