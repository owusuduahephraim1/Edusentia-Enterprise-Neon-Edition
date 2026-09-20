do $$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_worker_runtime') then
    execute 'create role edusentia_worker_runtime nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls';
  end if;
end$$;

grant connect on database edusentia to edusentia_worker_runtime;
grant usage on schema app,authn,academics,finance,storage,audit,services,documents,ops,platform to edusentia_worker_runtime;
grant select,insert,update,delete on all tables in schema app,academics,finance,storage,audit,services,documents,ops to edusentia_worker_runtime;
grant usage,select on all sequences in schema app,academics,finance,storage,audit,services,documents,ops to edusentia_worker_runtime;
revoke all on authn.password_credentials from edusentia_worker_runtime;\ngrant select,insert,update,delete on authn.mfa_totp_factors,authn.mfa_recovery_codes,authn.login_challenges to edusentia_worker_runtime;
grant select on authn.users to edusentia_worker_runtime;
grant select,insert,update,delete on authn.sessions to edusentia_worker_runtime;
grant select on platform.license_plans,platform.license_feature_catalog to edusentia_worker_runtime;
grant execute on function app.set_request_context(uuid,uuid,text,smallint) to edusentia_worker_runtime;
grant execute on function audit.record_auth_event(uuid,uuid,text,jsonb) to edusentia_worker_runtime;
grant execute on function authn.lookup_login(text,text) to edusentia_worker_runtime;
grant execute on function authn.bootstrap_first_admin(text,text,text,text,text,text,text) to edusentia_worker_runtime;
