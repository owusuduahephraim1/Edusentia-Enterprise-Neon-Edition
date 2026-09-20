begin;

-- Least-privilege grants for the live Cloudflare Worker inside an isolated
-- school database. The deployment role keeps ownership/schema duties.
do $tenant_worker_connect$
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_worker_runtime') then
    raise exception 'edusentia_worker_runtime role must be provisioned before tenant template installation'
      using errcode='42704';
  end if;
  execute format('grant connect on database %I to edusentia_worker_runtime',current_database());
end
$tenant_worker_connect$;

grant usage on schema app,authn,academics,finance,storage,audit,services,documents,ops,platform
  to edusentia_worker_runtime;

grant select,insert,update,delete on all tables in schema
  app,academics,finance,storage,audit,services,documents,ops
  to edusentia_worker_runtime;
grant usage,select on all sequences in schema
  app,academics,finance,storage,audit,services,documents,ops
  to edusentia_worker_runtime;

-- Authentication tables are deliberately narrower. Password credentials remain
-- accessible only through audited SECURITY DEFINER functions.
revoke all on authn.password_credentials from edusentia_worker_runtime;
grant select on authn.users to edusentia_worker_runtime;
grant select,insert,update,delete on
  authn.sessions,
  authn.mfa_totp_factors,
  authn.mfa_recovery_codes,
  authn.login_challenges
  to edusentia_worker_runtime;

grant select on platform.license_plans,platform.license_feature_catalog
  to edusentia_worker_runtime;

grant execute on function app.set_request_context(uuid,uuid,text,smallint)
  to edusentia_worker_runtime;
grant execute on function audit.record_auth_event(uuid,uuid,text,jsonb)
  to edusentia_worker_runtime;
grant execute on function authn.lookup_login(text,text)
  to edusentia_worker_runtime;
grant execute on function authn.platform_set_initial_password_by_email(uuid,text,text,text)
  to edusentia_worker_runtime;
grant execute on function authn.platform_reset_mfa_by_email(uuid,text)
  to edusentia_worker_runtime;
grant execute on function app.platform_health_snapshot(uuid)
  to edusentia_worker_runtime;
grant execute on function app.platform_capacity_snapshot(uuid)
  to edusentia_worker_runtime;
grant execute on function app.platform_set_student_capacity(uuid,integer)
  to edusentia_worker_runtime;
grant execute on function app.platform_apply_license(uuid,uuid,text,timestamptz,timestamptz,integer,text,text)
  to edusentia_worker_runtime;

-- Certified compatibility operations exposed by the Worker allowlist.
grant execute on function public.get_bootstrap_data()
  to edusentia_worker_runtime;
grant execute on function public.get_academic_configuration()
  to edusentia_worker_runtime;
grant execute on function public.get_academic_calendar_context()
  to edusentia_worker_runtime;
grant execute on function public.academic_configuration_readiness()
  to edusentia_worker_runtime;
grant execute on function public.set_active_period(uuid,uuid)
  to edusentia_worker_runtime;
grant execute on function public.get_report_editor(uuid,uuid,uuid)
  to edusentia_worker_runtime;
grant execute on function public.get_report_revisions(uuid)
  to edusentia_worker_runtime;
grant execute on function public.list_audit_events(text,uuid,integer,integer)
  to edusentia_worker_runtime;
grant execute on function public.list_notifications(integer,integer)
  to edusentia_worker_runtime;
grant execute on function public.list_profiles_with_access()
  to edusentia_worker_runtime;
grant execute on function public.search_students(text,uuid,public.student_status,integer,integer)
  to edusentia_worker_runtime;
grant execute on function public.mark_notifications_read(uuid[])
  to edusentia_worker_runtime;
grant execute on function public.save_student(jsonb)
  to edusentia_worker_runtime;
grant execute on function public.bulk_import_students(jsonb,text)
  to edusentia_worker_runtime;
grant execute on function public.bulk_import_scores(uuid,uuid,jsonb,text)
  to edusentia_worker_runtime;
grant execute on function public.save_report_card(jsonb,integer)
  to edusentia_worker_runtime;
grant execute on function public.transition_report_status(uuid,public.report_status,text,integer)
  to edusentia_worker_runtime;
grant execute on function public.generate_school_identifier(text)
  to edusentia_worker_runtime;
grant execute on function public.validate_student_import(jsonb,uuid,uuid,text)
  to edusentia_worker_runtime;
grant execute on function public.save_promotion_cutoff(integer)
  to edusentia_worker_runtime;

alter default privileges in schema app grant select,insert,update,delete on tables to edusentia_worker_runtime;
alter default privileges in schema academics grant select,insert,update,delete on tables to edusentia_worker_runtime;
alter default privileges in schema finance grant select,insert,update,delete on tables to edusentia_worker_runtime;
alter default privileges in schema storage grant select,insert,update,delete on tables to edusentia_worker_runtime;
alter default privileges in schema audit grant select,insert,update,delete on tables to edusentia_worker_runtime;
alter default privileges in schema services grant select,insert,update,delete on tables to edusentia_worker_runtime;
alter default privileges in schema documents grant select,insert,update,delete on tables to edusentia_worker_runtime;
alter default privileges in schema ops grant select,insert,update,delete on tables to edusentia_worker_runtime;

alter default privileges in schema app grant usage,select on sequences to edusentia_worker_runtime;
alter default privileges in schema academics grant usage,select on sequences to edusentia_worker_runtime;
alter default privileges in schema finance grant usage,select on sequences to edusentia_worker_runtime;
alter default privileges in schema storage grant usage,select on sequences to edusentia_worker_runtime;
alter default privileges in schema audit grant usage,select on sequences to edusentia_worker_runtime;
alter default privileges in schema services grant usage,select on sequences to edusentia_worker_runtime;
alter default privileges in schema documents grant usage,select on sequences to edusentia_worker_runtime;
alter default privileges in schema ops grant usage,select on sequences to edusentia_worker_runtime;

commit;
