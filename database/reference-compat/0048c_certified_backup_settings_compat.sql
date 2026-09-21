begin;

-- Certified backup/recovery policy compatibility for the reference blueprint.
-- The certified backup_dashboard() and save_backup_policy() RPCs read/write
-- these school_settings fields. Keep release identity at 0048 because this is
-- a schema-completeness hotfix for the already-certified 0048 surface.
alter table public.school_settings
  add column if not exists backup_retention_days integer not null default 30;

alter table public.school_settings
  add column if not exists backup_minimum_copies integer not null default 7;

insert into app.schema_migrations(version)
values ('0048c_certified_backup_settings_compat')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
