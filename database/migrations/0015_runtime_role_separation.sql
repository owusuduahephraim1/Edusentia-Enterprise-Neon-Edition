begin;

do $$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_worker_runtime') then
    execute 'create role edusentia_worker_runtime nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls';
  end if;
end$$;

do $$
begin
  execute format('grant connect on database %I to edusentia_worker_runtime',current_database());
end$$;

grant usage on schema app,authn,academics,finance,storage,audit,services,documents,ops,platform to edusentia_worker_runtime;
grant select,insert,update,delete on all tables in schema app,academics,finance,storage,audit,services,documents,ops to edusentia_worker_runtime;
grant usage,select on all sequences in schema app,academics,finance,storage,audit,services,documents,ops to edusentia_worker_runtime;

revoke all on authn.password_credentials,authn.mfa_totp_factors,authn.mfa_recovery_codes from edusentia_worker_runtime;
grant select on authn.users to edusentia_worker_runtime;
grant select,insert,update,delete on authn.sessions to edusentia_worker_runtime;
grant select on platform.license_plans,platform.license_feature_catalog to edusentia_worker_runtime;
grant execute on function app.set_request_context(uuid,uuid,text,smallint) to edusentia_worker_runtime;
grant execute on function audit.record_auth_event(uuid,uuid,text,jsonb) to edusentia_worker_runtime;
grant execute on function authn.lookup_login(text,text) to edusentia_worker_runtime;
grant execute on function authn.bootstrap_first_admin(text,text,text,text,text,text,text) to edusentia_worker_runtime;

do $$
begin
  if exists(select 1 from pg_roles where rolname='edusentia_runtime')
     and current_user <> 'edusentia_runtime'
     and not exists(
       select 1
         from pg_auth_members m
         join pg_roles granted_role on granted_role.oid=m.roleid
         join pg_roles member_role on member_role.oid=m.member
        where granted_role.rolname='edusentia_worker_runtime'
          and member_role.rolname='edusentia_runtime'
          and m.admin_option
     ) then
    execute 'grant edusentia_worker_runtime to edusentia_runtime with admin option';
  end if;
end$$;

insert into app.schema_migrations(version) values ('0015_runtime_role_separation') on conflict do nothing;
update app.release_identity set schema_version='0015' where edition='Edusentia Enterprise Neon Edition';

commit;
