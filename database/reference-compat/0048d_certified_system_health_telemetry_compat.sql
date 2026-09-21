begin;

-- Certified System Health telemetry compatibility for the reference blueprint.
-- The certified public.system_health() RPC depends on the hardened current-state
-- client telemetry columns introduced by the reference system-health migration.
alter table public.client_error_events
  add column if not exists severity text not null default 'error',
  add column if not exists category text not null default 'application',
  add column if not exists status text not null default 'open',
  add column if not exists occurrence_count integer not null default 1,
  add column if not exists first_seen_at timestamptz,
  add column if not exists last_seen_at timestamptz,
  add column if not exists fingerprint text not null default '',
  add column if not exists resolved_at timestamptz,
  add column if not exists resolution_note text not null default '';

update public.client_error_events
set first_seen_at=coalesce(first_seen_at,created_at,now()),
    last_seen_at=coalesce(last_seen_at,created_at,now());

alter table public.client_error_events alter column first_seen_at set default now();
alter table public.client_error_events alter column last_seen_at set default now();
alter table public.client_error_events alter column first_seen_at set not null;
alter table public.client_error_events alter column last_seen_at set not null;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='client_error_events_severity_check' and conrelid='public.client_error_events'::regclass) then
    alter table public.client_error_events add constraint client_error_events_severity_check
      check (severity in ('warning','error','critical'));
  end if;
  if not exists(select 1 from pg_constraint where conname='client_error_events_status_check' and conrelid='public.client_error_events'::regclass) then
    alter table public.client_error_events add constraint client_error_events_status_check
      check (status in ('open','resolved','ignored'));
  end if;
  if not exists(select 1 from pg_constraint where conname='client_error_events_occurrence_count_check' and conrelid='public.client_error_events'::regclass) then
    alter table public.client_error_events add constraint client_error_events_occurrence_count_check
      check (occurrence_count>0);
  end if;
end $$;

create index if not exists client_error_events_health_idx
  on public.client_error_events(status,severity,last_seen_at desc);
create index if not exists client_error_events_actor_fingerprint_idx
  on public.client_error_events(actor_id,fingerprint,last_seen_at desc);

insert into app.schema_migrations(version)
values ('0048d_certified_system_health_telemetry_compat')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
