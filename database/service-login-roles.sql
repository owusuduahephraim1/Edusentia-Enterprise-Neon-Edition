-- Rotatable login wrappers for deployment-managed service credentials.
-- These roles hold no application privileges. They may only SET ROLE into the
-- fixed Worker/provisioner roles. edusentia_runtime receives ADMIN only on the
-- wrappers so CI can rotate passwords without administering service roles.

do $service_login_roles$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_worker_login') then
    create role edusentia_worker_login login nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  else
    alter role edusentia_worker_login login nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  end if;

  if not exists(select 1 from pg_roles where rolname='edusentia_provisioner_login') then
    create role edusentia_provisioner_login login nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  else
    alter role edusentia_provisioner_login login nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  end if;
end
$service_login_roles$;

grant edusentia_worker_runtime to edusentia_worker_login
  with admin false, inherit false, set true;
grant edusentia_provisioner to edusentia_provisioner_login
  with admin false, inherit false, set true;

grant edusentia_worker_login to edusentia_runtime
  with admin true, inherit false, set false;
grant edusentia_provisioner_login to edusentia_runtime
  with admin true, inherit false, set false;

do $verify_service_login_roles$
declare
  unsafe_count integer;
begin
  select count(*) into unsafe_count
  from pg_roles
  where rolname in ('edusentia_worker_login','edusentia_provisioner_login')
    and (
      rolsuper or rolcreatedb or rolcreaterole or rolinherit or rolbypassrls
      or not rolcanlogin
    );
  if unsafe_count<>0 then
    raise exception 'service login wrapper has unsafe role attributes';
  end if;

  if not exists(
    select 1
    from pg_auth_members m
    join pg_roles granted on granted.oid=m.roleid
    join pg_roles member_role on member_role.oid=m.member
    where granted.rolname='edusentia_worker_runtime'
      and member_role.rolname='edusentia_worker_login'
      and not m.admin_option and not m.inherit_option and m.set_option
  ) then
    raise exception 'worker login wrapper SET-only membership is missing';
  end if;

  if not exists(
    select 1
    from pg_auth_members m
    join pg_roles granted on granted.oid=m.roleid
    join pg_roles member_role on member_role.oid=m.member
    where granted.rolname='edusentia_provisioner'
      and member_role.rolname='edusentia_provisioner_login'
      and not m.admin_option and not m.inherit_option and m.set_option
  ) then
    raise exception 'provisioner login wrapper SET-only membership is missing';
  end if;
end
$verify_service_login_roles$;
