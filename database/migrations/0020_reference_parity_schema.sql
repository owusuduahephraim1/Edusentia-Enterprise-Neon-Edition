begin;

alter table platform.tenant_control
  add column if not exists database_name text not null default '',
  add column if not exists database_state text not null default 'shared',
  add column if not exists release_manifest_sha256 text not null default '',
  add column if not exists release_foundation_version text not null default 'neon-v1.0.0',
  add column if not exists release_source_schema_version integer not null default 25,
  add column if not exists release_migration_count integer not null default 25,
  add column if not exists release_worker_function_count integer not null default 2,
  add column if not exists release_checked_at timestamptz,
  add column if not exists license_period_locked boolean not null default false;

alter table authn.mfa_totp_factors add column if not exists friendly_name text not null default 'Authenticator';
drop index if exists authn.mfa_totp_one_verified_active_uidx;

alter table platform.access_recovery_requests drop constraint if exists access_recovery_requests_status_check;
alter table platform.access_recovery_requests
  add constraint access_recovery_requests_status_check
  check(status in('pending','processing','completed','denied','cancelled'));

create table if not exists platform.plan_authorizations(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  code_hash text not null unique,
  code_hint text not null default '',
  authorization_type text not null check(authorization_type in('renewal','plan_upgrade')),
  from_plan_code text not null,
  to_plan_code text not null,
  status text not null default 'issued' check(status in('issued','redeemed_pending_activation','used','revoked','expired')),
  reason text not null,
  issued_by uuid references authn.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  used_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid references authn.users(id) on delete set null,
  revoke_reason text not null default '',
  license_period_type text not null check(license_period_type in('academic_term','academic_year')),
  license_period_label text not null,
  license_starts_at timestamptz not null,
  license_expires_at timestamptz not null,
  license_grace_days integer not null default 14 check(license_grace_days between 0 and 90),
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists platform_plan_authorizations_tenant_idx on platform.plan_authorizations(tenant_id,issued_at desc);
create unique index if not exists platform_plan_authorizations_one_open_idx
  on platform.plan_authorizations(tenant_id)
  where status in('issued','redeemed_pending_activation');

create table if not exists platform.plan_authorization_attempts(
  id bigserial primary key,
  tenant_id uuid references app.tenants(id) on delete set null,
  authorization_id uuid references platform.plan_authorizations(id) on delete set null,
  actor_id uuid references authn.users(id) on delete set null,
  outcome text not null,
  details jsonb not null default '{}'::jsonb,
  attempted_at timestamptz not null default now()
);
create index if not exists platform_plan_authorization_attempts_idx
  on platform.plan_authorization_attempts(tenant_id,attempted_at desc);

create table if not exists platform.release_catalog(
  id uuid primary key default gen_random_uuid(),
  release_version text not null unique,
  git_sha text not null,
  status text not null check(status in('draft','active','retired')),
  master_schema_version text not null,
  tenant_schema_version text not null,
  manifest_sha256 text not null default '',
  source_baseline text not null default '',
  deployed_at timestamptz,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists platform_release_one_active_idx
  on platform.release_catalog((status)) where status='active';

create table if not exists platform.tenant_releases(
  id uuid primary key default gen_random_uuid(),
  release_code text not null unique,
  status text not null check(status in('draft','active','retired')),
  baseline_blueprint_version text not null,
  manifest_sha256 text not null,
  migration_count integer not null check(migration_count>=0),
  worker_function_count integer not null check(worker_function_count>=0),
  source_schema_version integer not null check(source_schema_version>=0),
  source_reference text not null,
  metadata jsonb not null default '{}'::jsonb,
  notes text not null default '',
  created_at timestamptz not null default now(),
  activated_at timestamptz
);
create unique index if not exists platform_tenant_release_one_active_idx
  on platform.tenant_releases((status)) where status='active';

create table if not exists platform.tenant_release_migrations(
  id bigserial primary key,
  release_code text not null references platform.tenant_releases(release_code) on delete cascade,
  ordinal integer not null,
  migration_version text not null,
  migration_path text not null,
  sha256 text not null default '',
  created_at timestamptz not null default now(),
  unique(release_code,ordinal),
  unique(release_code,migration_version)
);

create table if not exists platform.tenant_release_worker_functions(
  id bigserial primary key,
  release_code text not null references platform.tenant_releases(release_code) on delete cascade,
  ordinal integer not null,
  function_name text not null,
  source_path text not null,
  sha256 text not null default '',
  created_at timestamptz not null default now(),
  unique(release_code,ordinal),
  unique(release_code,function_name)
);

create table if not exists platform.release_gate_runs(
  id bigserial primary key,
  release_version text not null,
  ready boolean not null,
  checks jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now()
);
create index if not exists platform_release_gate_runs_checked_idx on platform.release_gate_runs(checked_at desc);

create table if not exists platform.health_display_state(
  singleton boolean primary key default true check(singleton),
  visible_since timestamptz not null default '1970-01-01T00:00:00Z',
  overview_visible_since timestamptz not null default '1970-01-01T00:00:00Z',
  updated_at timestamptz not null default now(),
  updated_by uuid references authn.users(id) on delete set null
);
insert into platform.health_display_state(singleton) values(true) on conflict(singleton) do nothing;

create table if not exists platform.school_deletion_jobs(
  id uuid primary key default gen_random_uuid(),
  registration_id uuid references platform.school_registrations(id) on delete set null,
  tenant_id uuid references app.tenants(id) on delete set null,
  tenant_code text,
  database_name text,
  status text not null default 'queued' check(status in('queued','running','completed','failed','cancelled')),
  stage text not null default 'queued',
  actor_id uuid references authn.users(id) on delete set null,
  reason text not null,
  school_fingerprint text not null default '',
  attempts integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  last_error text not null default '',
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists platform_school_deletion_jobs_idx on platform.school_deletion_jobs(status,created_at desc);

insert into app.schema_migrations(version) values ('0020_reference_parity_schema') on conflict do nothing;
commit;
