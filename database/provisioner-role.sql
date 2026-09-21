-- Deployment-only tenant provisioner.
-- PostgreSQL 16+ requires SET TRUE membership to transfer database ownership
-- or CREATE DATABASE while acting as the provisioner role. The deployment role
-- deliberately does not inherit provisioner privileges.
set role neon_superuser;

do $$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_provisioner') then
    create role edusentia_provisioner nologin nosuperuser createdb nocreaterole noinherit nobypassrls;
  end if;
end$$;

alter role edusentia_provisioner nosuperuser createdb nocreaterole noinherit nobypassrls;
grant edusentia_provisioner to edusentia_runtime
  with admin false, inherit false, set true;

reset role;

revoke all on schema app,authn,academics,finance,storage,audit,services,documents,ops,platform
  from edusentia_provisioner;
