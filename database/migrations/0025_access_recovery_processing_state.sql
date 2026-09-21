begin;

alter table platform.access_recovery_requests
  drop constraint if exists access_recovery_requests_status_check;
alter table platform.access_recovery_requests
  add constraint access_recovery_requests_status_check
  check(status in('pending','processing','completed','denied','cancelled'));

drop index if exists platform.platform_access_recovery_one_pending_idx;
create unique index if not exists platform_access_recovery_one_open_idx
  on platform.access_recovery_requests(tenant_id)
  where status in('pending','processing');

insert into app.schema_migrations(version) values ('0025_access_recovery_processing_state') on conflict do nothing;
update app.release_identity
   set schema_version='0025',
       version='neon-v1.0.0-r42',
       api_version='v1',
       frontend_version='neon-v1.0.0-r42',
       worker_version='neon-v1.0.0-r42'
 where edition='Edusentia Enterprise Neon Edition';

commit;
