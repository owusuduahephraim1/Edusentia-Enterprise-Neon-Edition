do $$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_provisioner') then
    create role edusentia_provisioner nologin nosuperuser createdb nocreaterole noinherit nobypassrls;
  end if;
end$$;

alter role edusentia_provisioner nosuperuser createdb nocreaterole noinherit nobypassrls;
grant edusentia_provisioner to edusentia_runtime;
revoke all on schema app,authn,academics,finance,storage,audit,services,documents,ops,platform from edusentia_provisioner;
