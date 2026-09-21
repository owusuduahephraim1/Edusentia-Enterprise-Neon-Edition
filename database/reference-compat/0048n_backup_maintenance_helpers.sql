-- Backup retention, stale-job reconciliation and scheduled-backup helpers.
begin;

create or replace function public.backup_worker_reconcile_stale_backups()
returns integer
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare changed integer;
begin
  update public.backup_exports
     set status='failed',
         error_message='Previous backup did not complete within two hours',
         completed_at=now()
   where status='processing'
     and backup_type='full'
     and started_at<now()-interval '2 hours';
  get diagnostics changed=row_count;
  return changed;
end
$fn$;

create or replace function public.backup_worker_reconcile_stale_restore_jobs()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare result jsonb;
begin
  update public.school_restore_jobs
     set status='cancelled',
         error_message='Restore upload did not complete within 30 minutes.',
         verification_notes='The abandoned restore-import slot was reconciled automatically; production data was not changed.',
         completed_at=coalesce(completed_at,now()),
         updated_at=now()
   where status='upload_pending'
     and created_at<now()-interval '30 minutes';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,
    'import_path',import_path,
    'status',status,
    'updated_at',updated_at
  ) order by updated_at),'[]'::jsonb)
    into result
    from public.school_restore_jobs
   where import_path<>''
     and (
       (status='cancelled' and updated_at<now()-interval '1 minute')
       or (status in ('completed','failed') and updated_at<now()-interval '2 hours')
     );
  return result;
end
$fn$;

create or replace function public.backup_worker_clear_restore_import_path(target_job uuid)
returns void
language sql
security definer
set search_path=public,pg_catalog
as $fn$
  update public.school_restore_jobs
     set import_path='',updated_at=now()
   where id=target_job
     and status in ('cancelled','completed','failed')
$fn$;

create or replace function public.backup_worker_scheduled_context()
returns jsonb
language plpgsql
security definer
set search_path=public,authn,app,pg_catalog
as $fn$
declare
  tenant_id uuid;
  tenant_code text;
  tenant_name text;
  user_id uuid;
  email text;
  display_name text;
begin
  select t.id,t.code,t.name
    into tenant_id,tenant_code,tenant_name
    from app.tenants t
   where t.status='active'
   order by t.created_at
   limit 1;

  if tenant_id is null then return null; end if;

  select p.id,u.email,u.display_name
    into user_id,email,display_name
    from public.profiles p
    join authn.users u on u.id=p.id
   where p.active
     and public.current_app_role_for(p.role)='system_admin'
     and u.disabled_at is null
   order by p.created_at
   limit 1;

  if user_id is null then return null; end if;

  return jsonb_build_object(
    'tenant_id',tenant_id,
    'tenant_code',tenant_code,
    'tenant_name',tenant_name,
    'user_id',user_id,
    'email',email,
    'display_name',display_name,
    'role','system_admin',
    'assurance_level',2
  );
end
$fn$;

revoke all on function public.backup_worker_reconcile_stale_backups() from public;
revoke all on function public.backup_worker_reconcile_stale_restore_jobs() from public;
revoke all on function public.backup_worker_clear_restore_import_path(uuid) from public;
revoke all on function public.backup_worker_scheduled_context() from public;

grant execute on function public.backup_worker_reconcile_stale_backups() to edusentia_worker_runtime;
grant execute on function public.backup_worker_reconcile_stale_restore_jobs() to edusentia_worker_runtime;
grant execute on function public.backup_worker_clear_restore_import_path(uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_scheduled_context() to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0048n_backup_maintenance_helpers')
on conflict do nothing;

commit;
