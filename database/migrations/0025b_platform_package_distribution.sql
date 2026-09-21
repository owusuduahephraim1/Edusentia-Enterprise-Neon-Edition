begin;

-- Additive control-plane subsystem. The certified r42 release identity remains
-- schema 0025; this migration adds package distribution without changing the
-- tenant compatibility contract (0020/0048).
create table if not exists platform.package_signing_keys(
  key_id text primary key,
  public_jwk jsonb not null,
  public_fingerprint text not null unique,
  active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table if not exists platform.package_templates(
  id uuid primary key default gen_random_uuid(),
  package_version text not null,
  object_key text not null unique,
  sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
  file_size bigint not null check(file_size>0),
  required_files jsonb not null default '[]'::jsonb,
  validation jsonb not null default '{}'::jsonb,
  active boolean not null default false,
  uploaded_by uuid references authn.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists platform_package_one_active_template_idx
  on platform.package_templates((1)) where active;

create table if not exists platform.package_artifacts(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  tenant_code text not null,
  school_name text not null,
  plan_code text not null default '',
  package_version text not null,
  template_id uuid references platform.package_templates(id) on delete set null,
  object_key text not null unique,
  filename text not null,
  sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
  file_size bigint not null check(file_size>0),
  status text not null default 'ready' check(status in('ready','revoked','deleted')),
  signing_key_id text not null references platform.package_signing_keys(key_id),
  public_fingerprint text not null,
  signature text not null,
  manifest jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  generated_by uuid references authn.users(id) on delete set null,
  generated_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references authn.users(id) on delete set null,
  deleted_at timestamptz,
  download_count bigint not null default 0,
  last_downloaded_at timestamptz
);
create index if not exists platform_package_artifacts_tenant_idx
  on platform.package_artifacts(tenant_id,generated_at desc);
create index if not exists platform_package_artifacts_status_idx
  on platform.package_artifacts(status,generated_at desc);
create unique index if not exists platform_package_one_ready_per_tenant_idx
  on platform.package_artifacts(tenant_id) where status='ready';

create table if not exists platform.package_events(
  id bigint generated always as identity primary key,
  actor_user_id uuid references authn.users(id) on delete set null,
  action text not null,
  template_id uuid references platform.package_templates(id) on delete set null,
  artifact_id uuid references platform.package_artifacts(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists platform_package_events_created_idx
  on platform.package_events(created_at desc);

create table if not exists platform.package_reconciliation(
  id uuid primary key default gen_random_uuid(),
  object_key text not null,
  object_kind text not null check(object_kind in('template','artifact','staging')),
  status text not null default 'pending' check(status in('pending','resolved','failed')),
  details jsonb not null default '{}'::jsonb,
  last_error text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists platform_package_reconciliation_open_idx
  on platform.package_reconciliation(status,updated_at desc)
  where status in('pending','failed');
create unique index if not exists platform_package_reconciliation_object_uq
  on platform.package_reconciliation(object_kind,object_key);

grant select,insert,update,delete on
  platform.package_signing_keys,
  platform.package_templates,
  platform.package_artifacts,
  platform.package_events,
  platform.package_reconciliation
to edusentia_worker_runtime;
grant usage,select on all sequences in schema platform to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0025b_platform_package_distribution')
on conflict do nothing;

commit;
