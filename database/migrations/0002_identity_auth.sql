begin;
create table if not exists authn.users(
 id uuid primary key default gen_random_uuid(), email text not null, display_name text not null default '', phone text,
 disabled_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists users_email_lower_uidx on authn.users(lower(email));
create table if not exists authn.password_credentials(
 user_id uuid primary key references authn.users(id) on delete cascade, password_hash text not null, password_salt text not null,
 algorithm text not null default 'scrypt-n32768-r8-p1', password_changed_at timestamptz not null default now(), failed_attempts integer not null default 0, locked_until timestamptz
);
create table if not exists app.tenant_memberships(
 tenant_id uuid not null references app.tenants(id) on delete cascade, user_id uuid not null references authn.users(id) on delete cascade,
 role text not null, status text not null default 'active' check(status in('invited','active','suspended','archived')), mfa_required boolean not null default false,
 created_at timestamptz not null default now(), primary key(tenant_id,user_id)
);
create table if not exists authn.sessions(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references authn.users(id) on delete cascade,
 tenant_id uuid not null references app.tenants(id) on delete cascade, token_hash text not null unique, role text not null, assurance_level smallint not null default 1 check(assurance_level between 1 and 2),
 created_at timestamptz not null default now(), expires_at timestamptz not null, last_seen_at timestamptz not null default now(), revoked_at timestamptz, ip_hash text, user_agent_hash text
);
create index if not exists sessions_active_token_idx on authn.sessions(token_hash) where revoked_at is null;
create index if not exists sessions_user_active_idx on authn.sessions(user_id,expires_at desc) where revoked_at is null;
create table if not exists authn.mfa_totp_factors(id uuid primary key default gen_random_uuid(),user_id uuid not null references authn.users(id) on delete cascade,secret_ciphertext text not null,verified_at timestamptz,disabled_at timestamptz,created_at timestamptz not null default now());
create table if not exists authn.mfa_recovery_codes(id uuid primary key default gen_random_uuid(),user_id uuid not null references authn.users(id) on delete cascade,code_hash text not null unique,used_at timestamptz,created_at timestamptz not null default now());
create table if not exists app.permissions(code text primary key,description text not null default '');
create table if not exists app.role_permissions(role text not null,permission_code text not null references app.permissions(code) on delete cascade,primary key(role,permission_code));

create or replace function authn.lookup_login(p_email text,p_tenant_code text)
returns table(user_id uuid,email text,display_name text,password_hash text,password_salt text,disabled_at timestamptz,tenant_id uuid,tenant_code text,tenant_name text,role text,status text,mfa_required boolean)
language sql stable security definer set search_path=authn,app,pg_catalog as $$
 select u.id,u.email,u.display_name,c.password_hash,c.password_salt,u.disabled_at,t.id,t.code,t.name,m.role,m.status,m.mfa_required
 from authn.users u join authn.password_credentials c on c.user_id=u.id join app.tenant_memberships m on m.user_id=u.id join app.tenants t on t.id=m.tenant_id
 where lower(u.email)=lower(trim(p_email)) and upper(t.code)=upper(trim(p_tenant_code)) limit 1
$$;
revoke all on function authn.lookup_login(text,text) from public;

insert into app.schema_migrations(version) values ('0002_identity_auth') on conflict do nothing;
commit;
