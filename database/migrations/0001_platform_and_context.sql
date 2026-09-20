begin;
create extension if not exists pgcrypto;
create schema if not exists app;
create schema if not exists authn;
create schema if not exists academics;
create schema if not exists finance;
create schema if not exists storage;
create schema if not exists audit;

create table if not exists app.schema_migrations(version text primary key, applied_at timestamptz not null default now());
create table if not exists app.tenants(
  id uuid primary key default gen_random_uuid(), code text not null unique check(code ~ '^[A-Z0-9][A-Z0-9_-]{2,31}$'),
  name text not null, institution_type text not null default 'basic_jhs', status text not null default 'active' check(status in('provisioning','active','suspended','archived')),
  settings jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists app.release_identity(
  edition text primary key, version text not null, source_baseline text not null, source_commit text not null,
  schema_version text not null, api_version text not null, frontend_version text not null, worker_version text not null, created_at timestamptz not null default now()
);
create or replace function app.current_tenant_id() returns uuid language sql stable as $$select nullif(current_setting('app.tenant_id',true),'')::uuid$$;
create or replace function app.current_user_id() returns uuid language sql stable as $$select nullif(current_setting('app.user_id',true),'')::uuid$$;
create or replace function app.current_role() returns text language sql stable as $$select nullif(current_setting('app.role',true),'')$$;
create or replace function app.current_aal() returns smallint language sql stable as $$select coalesce(nullif(current_setting('app.aal',true),'')::smallint,0)$$;
create or replace function app.set_request_context(p_tenant uuid,p_user uuid,p_role text,p_aal smallint) returns boolean language plpgsql security invoker as $$begin
  perform set_config('app.tenant_id',p_tenant::text,true); perform set_config('app.user_id',p_user::text,true); perform set_config('app.role',p_role,true); perform set_config('app.aal',p_aal::text,true); return true; end$$;
insert into app.schema_migrations(version) values ('0001_platform_and_context') on conflict do nothing;
commit;
