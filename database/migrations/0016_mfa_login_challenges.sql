begin;
create table if not exists authn.login_challenges(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references authn.users(id) on delete cascade,
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  factor_id uuid references authn.mfa_totp_factors(id) on delete set null,
  purpose text not null check(purpose in('mfa_enroll','mfa_verify')),
  token_hash text not null unique,
  attempts smallint not null default 0 check(attempts between 0 and 10),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
create index if not exists login_challenges_active_idx on authn.login_challenges(token_hash,expires_at) where used_at is null;
create index if not exists login_challenges_user_idx on authn.login_challenges(user_id,tenant_id,created_at desc);
create unique index if not exists mfa_totp_one_verified_active_uidx on authn.mfa_totp_factors(user_id) where verified_at is not null and disabled_at is null;
do $$begin if exists(select 1 from pg_roles where rolname='edusentia_worker_runtime') then
  revoke all on authn.password_credentials from edusentia_worker_runtime;
  grant select,insert,update,delete on authn.mfa_totp_factors,authn.mfa_recovery_codes,authn.login_challenges to edusentia_worker_runtime;
end if; end$$;
insert into app.schema_migrations(version) values ('0016_mfa_login_challenges') on conflict do nothing;
update app.release_identity set schema_version='0016' where edition='Edusentia Enterprise Neon Edition';
commit;
