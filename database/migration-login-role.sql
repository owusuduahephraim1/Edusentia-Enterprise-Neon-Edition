-- Rotatable migration-only login wrapper.
-- The wrapper has no inherited application privileges. It may SET ROLE to the
-- database owner solely for explicit migration sessions. edusentia_runtime may
-- rotate the wrapper password through ADMIN membership but cannot SET the
-- wrapper or inherit owner privileges.
do $migration_login$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_migrator_login') then
    create role edusentia_migrator_login login nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  else
    alter role edusentia_migrator_login login nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  end if;
end
$migration_login$;

do $migration_memberships$
begin
  if not exists(
    select 1
    from pg_auth_members m
    join pg_roles granted on granted.oid=m.roleid
    join pg_roles member_role on member_role.oid=m.member
    where granted.rolname='edusentia_owner'
      and member_role.rolname='edusentia_migrator_login'
      and not m.admin_option and not m.inherit_option and m.set_option
  ) then
    grant edusentia_owner to edusentia_migrator_login
      with admin false, inherit false, set true;
  end if;

  if not exists(
    select 1
    from pg_auth_members m
    join pg_roles granted on granted.oid=m.roleid
    join pg_roles member_role on member_role.oid=m.member
    where granted.rolname='edusentia_migrator_login'
      and member_role.rolname='edusentia_runtime'
      and m.admin_option and not m.inherit_option and not m.set_option
  ) then
    grant edusentia_migrator_login to edusentia_runtime
      with admin true, inherit false, set false;
  end if;
end
$migration_memberships$;

do $verify_migration_login$
declare r record;
begin
  select rolsuper,rolcreatedb,rolcreaterole,rolinherit,rolbypassrls,rolcanlogin
    into r from pg_roles where rolname='edusentia_migrator_login';
  if r.rolsuper or r.rolcreatedb or r.rolcreaterole or r.rolinherit or r.rolbypassrls or not r.rolcanlogin then
    raise exception 'edusentia_migrator_login has unsafe attributes';
  end if;

  if pg_has_role('edusentia_runtime','edusentia_owner','set') then
    raise exception 'deployment runtime must never be able to SET ROLE edusentia_owner';
  end if;
end
$verify_migration_login$;
