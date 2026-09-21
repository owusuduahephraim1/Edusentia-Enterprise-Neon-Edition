begin;

alter table public.notification_outbox
  add column if not exists attempts integer not null default 0,
  add column if not exists processed_at timestamptz,
  add column if not exists created_at timestamptz not null default now();

create index if not exists notification_outbox_health_idx
  on public.notification_outbox(processed_at,created_at,attempts);

insert into app.schema_migrations(version)
values ('0048e_certified_system_health_notification_compat')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
