begin;

-- Create the dedicated Worker role during the schema phase, but do not
-- tighten its object privileges until every later migration has finished.
-- database/runtime-role.sql is the authoritative least-privilege grant set
-- and is applied after database/install-master.sh by CI/deployment.
do $$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_worker_runtime') then
    execute 'create role edusentia_worker_runtime nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls';
  end if;
end$$;

insert into app.schema_migrations(version) values ('0015_runtime_role_separation') on conflict do nothing;
update app.release_identity set schema_version='0015' where edition='Edusentia Enterprise Neon Edition';

commit;
