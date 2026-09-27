-- Backup interruption recovery: a Worker can be terminated before its catch
-- handler records failure. Reconcile an idle processing backup quickly so the
-- next one-click backup is not blocked behind a phantom job.
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
         error_message='Backup worker heartbeat expired before completion. Safe retry is allowed.',
         completed_at=now(),
         heartbeat_at=now()
   where status='processing'
     and backup_type='full'
     and coalesce(heartbeat_at,started_at,created_at)<now()-interval '3 minutes';

  get diagnostics changed=row_count;
  return changed;
end
$fn$;

revoke all on function public.backup_worker_reconcile_stale_backups() from public;
grant execute on function public.backup_worker_reconcile_stale_backups() to edusentia_worker_runtime;

-- Clear any already-orphaned processing row during rollout. Active workers
-- continuously refresh heartbeat while reading database pages and recording
-- protected storage objects, so only idle jobs are released here.
select public.backup_worker_reconcile_stale_backups();

insert into app.schema_migrations(version)
values ('0073_backup_interruption_recovery')
on conflict do nothing;

commit;
