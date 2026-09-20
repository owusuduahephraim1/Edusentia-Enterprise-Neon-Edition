begin;

alter table platform.license_plans add column if not exists description text not null default '';
alter table platform.license_plans add column if not exists billing_cycle text not null default 'annual';
alter table platform.license_plans add column if not exists price_amount numeric;
alter table platform.license_plans add column if not exists currency text not null default 'USD';
alter table platform.license_plans add column if not exists feature_flags jsonb not null default '{}'::jsonb;
alter table platform.license_plans add column if not exists sort_order integer not null default 100;
create sequence if not exists platform.tenant_code_seq start with 1 increment by 1;

create table if not exists platform.admins(
  user_id uuid primary key references authn.users(id) on delete cascade,
  role text not null default 'platform_super_admin' check(role='platform_super_admin'),
  active boolean not null default true,
  mfa_required boolean not null default true check(mfa_required=true),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists platform.admin_sessions(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references authn.users(id) on delete cascade,
  token_hash text not null unique,
  assurance_level smallint not null default 2 check(assurance_level between 1 and 3),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_seen_at timestamptz not null default now()
);
create index if not exists platform_admin_sessions_active_idx on platform.admin_sessions(token_hash,expires_at) where revoked_at is null;
create table if not exists platform.admin_login_challenges(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references authn.users(id) on delete cascade,
  factor_id uuid references authn.mfa_totp_factors(id) on delete set null,
  purpose text not null check(purpose in('mfa_enroll','mfa_verify')),
  token_hash text not null unique,
  attempts smallint not null default 0 check(attempts between 0 and 10),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
create index if not exists platform_admin_challenge_active_idx on platform.admin_login_challenges(token_hash,expires_at) where used_at is null;

create table if not exists platform.school_registrations(
  id uuid primary key default gen_random_uuid(),
  school_name text not null,
  contact_name text not null,
  contact_email text not null,
  contact_phone text not null default '',
  country text not null default '',
  requested_plan_code text not null default 'starter',
  institution_type text not null default 'basic_jhs' check(institution_type in('basic_jhs','senior_high','combined_pretertiary','tertiary')),
  status text not null default 'pending' check(status in('pending','provisioning','active','denied','rejected','cancelled')),
  tenant_id uuid references app.tenants(id) on delete set null,
  rejection_reason text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  initial_license_period_type text,
  initial_license_period_label text,
  initial_license_starts_at timestamptz,
  initial_license_expires_at timestamptz,
  initial_license_grace_days integer,
  initial_license_configured_at timestamptz,
  initial_license_configured_by uuid references authn.users(id) on delete set null,
  reviewed_at timestamptz,
  reviewed_by uuid references authn.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists platform_registration_open_email_uidx on platform.school_registrations(lower(contact_email)) where status in('pending','provisioning');

create table if not exists platform.tenant_control(
  tenant_id uuid primary key references app.tenants(id) on delete cascade,
  registration_id uuid unique references platform.school_registrations(id) on delete set null,
  tenant_code text not null unique,
  school_name text not null,
  slug text not null unique,
  institution_type text not null,
  admin_email text not null,
  login_domain text not null,
  status text not null default 'provisioning' check(status in('provisioning','active','suspended','cancelled','denied','archived')),
  plan_code text not null default 'starter',
  license_status text not null default 'pending_activation',
  license_period_type text not null default 'academic_year',
  license_period_label text not null default '',
  license_started_at timestamptz,
  license_expires_at timestamptz,
  license_grace_days integer not null default 30 check(license_grace_days between 0 and 90),
  license_grace_ends_at timestamptz,
  student_capacity_base integer,
  student_capacity_limit integer,
  student_active_count integer not null default 0,
  student_total_count integer not null default 0,
  student_capacity_status text not null default 'unknown',
  student_admissions_blocked boolean not null default false,
  student_capacity_checked_at timestamptz,
  last_health_status text not null default 'unknown',
  last_health_checked_at timestamptz,
  latest_backup_at timestamptz,
  latest_verified_backup_at timestamptz,
  client_errors_24h integer not null default 0,
  pending_notifications integer not null default 0,
  health_warning_count integer not null default 0,
  runtime_version text not null default 'neon-v1.0.0',
  schema_version text not null default '0017',
  release_status text not null default 'current',
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists platform.provisioning_jobs(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  status text not null default 'queued' check(status in('queued','running','ready','failed','cancelled')),
  stage text not null default 'queued',
  attempts integer not null default 0,
  idempotency_key text not null unique,
  blueprint_version text not null default 'neon-v1.0.0',
  metadata jsonb not null default '{}'::jsonb,
  last_error text not null default '',
  next_attempt_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists platform_provisioning_status_idx on platform.provisioning_jobs(status,next_attempt_at,created_at);
create table if not exists platform.tenant_events(
  id bigserial primary key,
  tenant_id uuid references app.tenants(id) on delete set null,
  registration_id uuid references platform.school_registrations(id) on delete set null,
  event_type text not null,
  actor_id uuid references authn.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists platform_tenant_events_created_idx on platform.tenant_events(created_at desc);
create table if not exists platform.tenant_health(
  id bigserial primary key,
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  healthy boolean not null,
  services jsonb not null default '[]'::jsonb,
  checked_at timestamptz not null default now()
);
create index if not exists platform_tenant_health_idx on platform.tenant_health(tenant_id,checked_at desc);
create table if not exists platform.access_recovery_requests(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  registration_id uuid references platform.school_registrations(id) on delete set null,
  recovery_type text not null check(recovery_type in('password','mfa','both')),
  requester_contact_email text not null,
  status text not null default 'pending' check(status in('pending','completed','denied','cancelled')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references authn.users(id) on delete set null,
  completed_at timestamptz,
  resolution_notes text not null default '',
  metadata jsonb not null default '{}'::jsonb
);
create unique index if not exists platform_access_recovery_one_pending_idx on platform.access_recovery_requests(tenant_id) where status='pending';
create table if not exists platform.admin_audit_events(
  id bigserial primary key,
  actor_user_id uuid references authn.users(id) on delete set null,
  action text not null,
  target_type text not null default '',
  target_id text not null default '',
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists platform_admin_audit_created_idx on platform.admin_audit_events(created_at desc);
create table if not exists platform.tenant_admin_setup_tokens(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  user_id uuid not null references authn.users(id) on delete cascade,
  token_hash text not null unique,
  created_by uuid references authn.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
create index if not exists platform_tenant_admin_setup_active_idx on platform.tenant_admin_setup_tokens(token_hash,expires_at) where used_at is null;

insert into platform.license_plans(code,name,active,limits,description,billing_cycle,price_amount,currency,feature_flags,sort_order)
values
('starter','Starter',true,'{"max_students":300,"max_teachers":30,"max_system_admins":2,"max_guardians":600,"max_storage_mb":2048}'::jsonb,'Core academic operations for a small school.','annual',null,'USD','{"payroll":false,"analytics":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"custom_branding":false,"finance_exports":false,"financial_holds":false,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":false,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,10),
('professional','Professional',true,'{"max_students":1000,"max_teachers":100,"max_system_admins":5,"max_guardians":2000,"max_storage_mb":10240}'::jsonb,'Expanded capacity, automation, templates, communication, and scheduled continuity.','annual',null,'USD','{"payroll":false,"analytics":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"custom_branding":false,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":false,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,20),
('enterprise','Enterprise School',true,'{}'::jsonb,'Unlimited school capacity and the complete implemented school feature set.','custom',null,'USD','{"payroll":true,"analytics":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"custom_branding":true,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":true,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,30)
on conflict(code) do update set name=excluded.name,active=excluded.active,limits=excluded.limits,description=excluded.description,billing_cycle=excluded.billing_cycle,price_amount=excluded.price_amount,currency=excluded.currency,feature_flags=excluded.feature_flags,sort_order=excluded.sort_order;

insert into app.schema_migrations(version) values ('0017_platform_control_plane_foundation') on conflict do nothing;
update app.release_identity set schema_version='0017' where edition='Edusentia Enterprise Neon Edition';
commit;
