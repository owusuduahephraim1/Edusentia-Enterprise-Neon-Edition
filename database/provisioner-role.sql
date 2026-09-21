-- Deployment-only tenant provisioner.
-- PostgreSQL 16+ requires SET TRUE membership to transfer database ownership
-- or CREATE DATABASE while acting as the provisioner role.
-- Neon does not permit ordinary sessions to SET ROLE neon_superuser, so the
-- deployment script never attempts that escalation. The membership is either
-- already bootstrapped by the database owner/control plane or grantable by the
-- current deployment role.

do $$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_provisioner') then
    create role edusentia_provisioner nologin nosuperuser createdb nocreaterole noinherit nobypassrls;
  end if;
end$$;

do $provisioner_attributes$
declare r record;
begin
  select rolsuper,rolcreatedb,rolcreaterole,rolinherit,rolbypassrls
    into r
  from pg_roles
  where rolname='edusentia_provisioner';

  if r.rolsuper or not r.rolcreatedb or r.rolcreaterole or r.rolinherit or r.rolbypassrls then
    raise exception 'edusentia_provisioner has unsafe role attributes'
      using errcode='42501',
            hint='Provisioner must be NOSUPERUSER CREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS.';
  end if;
end
$provisioner_attributes$;

do $provisioner_membership$
begin
  if not exists(
    select 1
    from pg_auth_members m
    join pg_roles granted on granted.oid=m.roleid
    join pg_roles member_role on member_role.oid=m.member
    where granted.rolname='edusentia_provisioner'
      and member_role.rolname='edusentia_runtime'
      and m.set_option
      and not m.inherit_option
      and not m.admin_option
  ) then
    begin
      execute 'grant edusentia_provisioner to edusentia_runtime with admin false, inherit false, set true';
    exception
      when insufficient_privilege then
        raise exception 'edusentia_provisioner membership requires one-time database-owner bootstrap'
          using errcode='42501',
                hint='Grant edusentia_provisioner to edusentia_runtime with ADMIN FALSE, INHERIT FALSE, SET TRUE using the Neon database owner, then rerun deployment.';
    end;
  end if;
end
$provisioner_membership$;

do $provisioner_schema_privileges$
declare
  s text;
begin
  if current_user <> 'edusentia_provisioner' then
    revoke all on schema app,authn,academics,finance,storage,audit,services,documents,ops,platform
      from edusentia_provisioner;
  else
    foreach s in array array['app','authn','academics','finance','storage','audit','services','documents','ops','platform']
    loop
      if has_schema_privilege('edusentia_provisioner',s,'usage')
         or has_schema_privilege('edusentia_provisioner',s,'create') then
        raise exception 'edusentia_provisioner unexpectedly has application schema privileges on %',s
          using errcode='42501';
      end if;
    end loop;
  end if;
end
$provisioner_schema_privileges$;

-- CI revalidation anchor: provisioner bootstrap must remain idempotent on persistent parity.
