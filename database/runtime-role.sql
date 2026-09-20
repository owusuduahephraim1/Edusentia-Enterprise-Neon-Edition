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
revoke all on authn.password_credentials from edusentia_worker_runtime;
grant select,insert,update,delete on authn.mfa_totp_factors,authn.mfa_recovery_codes,authn.login_challenges to edusentia_worker_runtime;
grant select on authn.users to edusentia_worker_runtime;
grant select,insert,update,delete on authn.sessions to edusentia_worker_runtime;
grant select on platform.license_plans,platform.license_feature_catalog to edusentia_worker_runtime;
grant execute on function app.set_request_context(uuid,uuid,text,smallint) to edusentia_worker_runtime;
grant execute on function audit.record_auth_event(uuid,uuid,text,jsonb) to edusentia_worker_runtime;
grant execute on function authn.lookup_login(text,text) to edusentia_worker_runtime;
grant execute on function authn.bootstrap_first_admin(text,text,text,text,text,text,text) to edusentia_worker_runtime;

grant select on platform.admins,platform.license_plans,platform.license_feature_catalog to edusentia_worker_runtime;
grant select,insert,update,delete on platform.admin_sessions,platform.admin_login_challenges,platform.school_registrations,platform.tenant_control,platform.provisioning_jobs,platform.tenant_events,platform.tenant_health,platform.access_recovery_requests,platform.admin_audit_events to edusentia_worker_runtime;
revoke all on platform.tenant_admin_setup_tokens from edusentia_worker_runtime;
grant usage,select on all sequences in schema platform to edusentia_worker_runtime;
grant execute on function platform.bootstrap_first_super_admin(text,text,text,text),platform.lookup_admin_login(text),platform.configure_initial_license(uuid,uuid,text,text,timestamptz,timestamptz,integer),platform.approve_registration(uuid,uuid),platform.deny_registration(uuid,uuid,text),platform.complete_provisioning(uuid,uuid),platform.resume_provisioning(uuid,uuid),platform.set_tenant_status(uuid,uuid,text),platform.refresh_tenant_capacity(uuid,uuid),platform.set_student_capacity(uuid,uuid,integer,text),platform.set_tenant_license(uuid,uuid,text,text,text,timestamptz,timestamptz,integer) to edusentia_worker_runtime;

grant execute on function platform.issue_admin_setup_token(uuid,uuid,text,timestamptz),platform.inspect_admin_setup_token(text),platform.complete_admin_setup(text,text,text) to edusentia_worker_runtime;
