begin;

-- Certified backup metadata compatibility required by System Health and
-- backup continuity operations in the reference blueprint.
alter table public.backup_exports
  add column if not exists backup_type text not null default 'full',
  add column if not exists completed_at timestamptz,
  add column if not exists verification_status text not null default 'pending',
  add column if not exists verification_checked_at timestamptz,
  add column if not exists offsite_copied_at timestamptz,
  add column if not exists offsite_copy_note text not null default '';

create index if not exists backup_exports_health_idx
  on public.backup_exports(backup_type,status,created_at desc);

create index if not exists backup_exports_verification_idx
  on public.backup_exports(verification_status,verification_checked_at desc);

insert into app.schema_migrations(version)
values ('0048f_certified_backup_health_metadata_compat')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
