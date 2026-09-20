#!/usr/bin/env bash
set -euo pipefail
: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

RUN_TOKEN="${GITHUB_RUN_ID:-local}_${GITHUB_RUN_ATTEMPT:-1}"
RUN_TOKEN="${RUN_TOKEN//-/_}"
BASIC_DB="edusentia_lifecycle_basic_${RUN_TOKEN}"
SHS_DB="edusentia_lifecycle_shs_${RUN_TOKEN}"
BASIC_DB="${BASIC_DB:0:60}"
SHS_DB="${SHS_DB:0:60}"

cleanup() {
  psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -c "drop database if exists \"$BASIC_DB\" with (force);" >/dev/null 2>&1 || true
  psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -c "drop database if exists \"$SHS_DB\" with (force);" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

url_for() {
  BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" TARGET_DB="$1" node --input-type=module -e 'const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);u.pathname="/"+process.env.TARGET_DB;process.stdout.write(u.toString())'
}

install_tenant() {
  local db_name="$1" tenant_id="$2" tenant_code="$3" school_name="$4" institution_type="$5" admin_email="$6"
  psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -c "create database \"$db_name\";"
  local db_url
  db_url="$(url_for "$db_name")"
  echo "::add-mask::$db_url"

  for migration in \
    database/migrations/0001_platform_and_context.sql \
    database/migrations/0002_identity_auth.sql \
    database/migrations/0003_school_people.sql \
    database/migrations/0004_academics_reporting.sql \
    database/migrations/0005_finance_hr_admissions.sql \
    database/migrations/0006_audit_storage_security.sql \
    database/migrations/0007_rls_and_runtime_grants.sql \
    database/migrations/0008_bootstrap_and_retention.sql \
    database/migrations/0009_academic_models.sql \
    database/migrations/0010_student_services.sql \
    database/migrations/0011_finance_enterprise.sql \
    database/migrations/0012_documents_and_identity.sql \
    database/migrations/0013_operations_compliance.sql \
    database/migrations/0014_bootstrap_auth_hardening.sql \
    database/migrations/0016_mfa_login_challenges.sql
  do
    psql "$db_url" -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
  done

  psql "$db_url" -v ON_ERROR_STOP=1 -f database/tenant-template/0020_tenant_runtime_parity.sql >/dev/null
  TARGET_DATABASE_URL="$db_url" bash database/reference-compat/install-core.sh >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0028_certified_compat_foundation.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0029_certified_users_access_identity.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0030_certified_academic_configuration.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0030b_certified_teacher_principal_records.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0031_certified_academic_configuration_rpc.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0032_certified_academic_calendar_context.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0033_certified_student_management_utilities.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0034_certified_student_management_hardening.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0035_certified_teacher_principal_hardening.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0036_certified_staff_runtime_guards.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0037_certified_academic_configuration_mutations.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0038_certified_teacher_principal_crud.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0039_certified_timetable_academic_alignment.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0040_certified_audit_trail_v1.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0041_certified_notification_publication_sync.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0042_certified_principal_academic_history_read.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0043_certified_report_governance_prerequisites.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0043b_certified_report_assignment_scope.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/reference-compat/0044_certified_report_workflow_privacy_integrity.sql >/dev/null
  psql "$db_url" -v ON_ERROR_STOP=1 -f database/tenant-template/runtime-role.sql >/dev/null

  psql "$db_url" -v ON_ERROR_STOP=1 -v tenant_id="$tenant_id" -v tenant_code="$tenant_code" -v school_name="$school_name" -v institution_type="$institution_type" -v admin_email="$admin_email" <<'SQL' >/dev/null
select app.platform_initialize_tenant(
  :'tenant_id'::uuid,
  :'tenant_code',
  :'school_name',
  :'institution_type',
  :'admin_email',
  'Synthetic System Administrator',
  'starter',
  now(),
  now()+interval '365 days'
);
SQL

  test "$(psql "$db_url" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "0020"
  test "$(psql "$db_url" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0044"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0037_certified_academic_configuration_mutations'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0038_certified_teacher_principal_crud'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0039_certified_timetable_academic_alignment'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0040_certified_audit_trail_v1'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0041_certified_notification_publication_sync'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0042_certified_principal_academic_history_read'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0043_certified_report_governance_prerequisites'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0043b_certified_report_assignment_scope'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from app.schema_migrations where version='0044_certified_report_workflow_privacy_integrity'")" = "1"
  test "$(psql "$db_url" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_bootstrap_data'")" -ge 1
  test "$(psql "$db_url" -Atc "select institution_type from app.tenants where id='$tenant_id'::uuid")" = "$institution_type"
  test "$(psql "$db_url" -Atc "select legal_name='$school_name' and email=lower('$admin_email') from app.school_settings where tenant_id='$tenant_id'::uuid")" = "t"
  EXPECTED_IDENTIFIER_ROOT="${tenant_code//-/}"
  test "$(psql "$db_url" -Atc "select school_name='$school_name' and email=lower('$admin_email') and tenant_code='$tenant_code' and identifier_root='$EXPECTED_IDENTIFIER_ROOT' and institution_type='$institution_type' from public.school_settings order by created_at,id limit 1")" = "t"
  test "$(psql "$db_url" -Atc "select count(*) from app.tenant_memberships where tenant_id='$tenant_id'::uuid and role='system_admin' and status='active' and mfa_required")" = "1"
  ADMIN_ID="$(psql "$db_url" -Atc "select id from authn.users where lower(email)=lower('$admin_email') limit 1")"
  test -n "$ADMIN_ID"
  test "$(psql "$db_url" -Atc "select count(*) from public.profiles where id='$ADMIN_ID'::uuid and role::text='system_admin' and active")" = "1"
  test "$(psql "$db_url" -Atc "select has_table_privilege('edusentia_worker_runtime','app.students','select') and has_table_privilege('edusentia_worker_runtime','authn.sessions','insert') and not has_table_privilege('edusentia_worker_runtime','authn.password_credentials','select') and has_function_privilege('edusentia_worker_runtime','authn.lookup_login(text,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.get_bootstrap_data()','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select not has_table_privilege('edusentia_worker_runtime','public.audit_log','select') and has_function_privilege('edusentia_worker_runtime','public.list_audit_events(text,uuid,integer,integer)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname='students'")" = "t"
  test "$(psql "$db_url" -Atc "select promotion_cutoff_score=50 and identifier_root='$EXPECTED_IDENTIFIER_ROOT' from public.school_settings order by created_at,id limit 1")" = "t"
  test "$(psql "$db_url" -Atc "select not has_function_privilege('edusentia_worker_runtime','public.safe_uuid(text)','execute') and not has_sequence_privilege('edusentia_worker_runtime','public.student_identifier_seq','usage')")" = "t"
  test "$(psql "$db_url" -Atc "select has_function_privilege('edusentia_worker_runtime','public.generate_school_identifier(text)','execute') and has_function_privilege('edusentia_worker_runtime','public.validate_student_import(jsonb,uuid,uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_promotion_cutoff(integer)','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_manage_student(uuid)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select has_function_privilege('edusentia_worker_runtime','public.save_academic_entity(text,jsonb)','execute') and has_function_privilege('edusentia_worker_runtime','public.archive_academic_entity(text,uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_grading_scale(jsonb)','execute') and has_function_privilege('edusentia_worker_runtime','public.archive_grading_scale(uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_assessment_scheme(jsonb)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_class_subject_assignments_batch(jsonb)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select not has_function_privilege('edusentia_worker_runtime','public.can_manage_teachers()','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_manage_headteachers()','execute') and not has_function_privilege('edusentia_worker_runtime','public.enforce_single_current_principal()','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='headteachers' and t.tgname='headteachers_single_current_guard' and not t.tgisinternal)")" = "t"
  test "$(psql "$db_url" -Atc "select to_regclass('auth.users') is not null and not has_table_privilege('edusentia_worker_runtime','auth.users','select')")" = "t"
  test "$(psql "$db_url" -Atc "select exists(select 1 from pg_constraint where conname='classes_class_teacher_record_id_fkey' and conrelid='public.classes'::regclass)")" = "t"
  test "$(psql "$db_url" -Atc "select not has_function_privilege('edusentia_worker_runtime','public.enforce_licensed_write()','execute') and not has_function_privilege('edusentia_worker_runtime','public.sync_teacher_responsibility_access(uuid)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select has_function_privilege('edusentia_worker_runtime','public.list_teachers(text,text,text,integer,integer)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_teacher(jsonb)','execute') and has_function_privilege('edusentia_worker_runtime','public.archive_teacher(uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.restore_teacher(uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.list_headteachers(text,text,text,integer,integer)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_headteacher(jsonb)','execute') and has_function_privilege('edusentia_worker_runtime','public.archive_headteacher(uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.restore_headteacher(uuid,text)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select to_regclass('public.class_timetable_entries') is not null and not has_table_privilege('edusentia_worker_runtime','public.class_timetable_entries','select') and has_function_privilege('edusentia_worker_runtime','public.get_class_timetable_console(uuid,uuid)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_class_timetable_entry(jsonb)','execute') and not has_function_privilege('edusentia_worker_runtime','public.validate_class_timetable_entry()','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_view_class_timetable(uuid)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select to_regclass('public.audit_log_archives') is not null and to_regclass('public.audit_log_archive_entries') is not null and not has_table_privilege('edusentia_worker_runtime','public.audit_log_archives','select') and not has_table_privilege('edusentia_worker_runtime','public.audit_log_archive_entries','select') and has_function_privilege('edusentia_worker_runtime','public.list_audit_events_v2(text,text,uuid,uuid,integer,integer)','execute') and has_function_privilege('edusentia_worker_runtime','public.list_audit_archives_v1(integer,integer)','execute') and has_function_privilege('edusentia_worker_runtime','public.list_audit_archive_entries_v1(uuid,integer,integer)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select not has_function_privilege('edusentia_worker_runtime','public.create_workflow_notifications(uuid,public.report_status)','execute') and has_function_privilege('edusentia_worker_runtime','public.transition_report_status(uuid,public.report_status,text,integer)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select has_function_privilege('edusentia_worker_runtime','public.search_students_v5(text,uuid,public.student_status,text,integer,integer)','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_manage_student(uuid)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select to_regclass('public.academic_period_controls') is not null and to_regclass('public.emergency_academic_delegations') is not null and to_regclass('public.report_correction_requests') is not null and to_regclass('public.report_correction_events') is not null")" = "t"
  test "$(psql "$db_url" -Atc "select not has_table_privilege('edusentia_worker_runtime','public.academic_period_controls','select') and not has_table_privilege('edusentia_worker_runtime','public.emergency_academic_delegations','select') and not has_table_privilege('edusentia_worker_runtime','public.report_correction_requests','select') and not has_table_privilege('edusentia_worker_runtime','public.report_correction_events','select')")" = "t"
  test "$(psql "$db_url" -Atc "select has_function_privilege('edusentia_worker_runtime','public.get_my_emergency_academic_delegations(uuid,uuid)','execute') and not has_function_privilege('edusentia_worker_runtime','public.term_control_snapshot(uuid)','execute') and not has_function_privilege('edusentia_worker_runtime','public.mark_report_correction_applied(uuid)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select not has_function_privilege('edusentia_worker_runtime','public.is_assigned_class_teacher(uuid)','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_create_report_for_class_term(uuid,uuid)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select has_function_privilege('edusentia_worker_runtime','public.get_report_editor(uuid,uuid,uuid)','execute') and has_function_privilege('edusentia_worker_runtime','public.get_report_revisions(uuid)','execute') and has_function_privilege('edusentia_worker_runtime','public.get_report_headteacher_signature(uuid)','execute') and has_function_privilege('edusentia_worker_runtime','public.delete_report_card_permanently(uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.transition_report_status(uuid,public.report_status,text,integer)','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_view_report_internal(uuid)','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_delete_report(uuid)','execute')")" = "t"
  test "$(psql "$db_url" -Atc "select position('report_transition_deadline_allowed' in pg_get_functiondef(p.oid))>0 and position('mark_report_correction_applied' in pg_get_functiondef(p.oid))>0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='transition_report_status' limit 1")" = "t"
  test "$(psql "$db_url" -Atc "select position('REPORT_DRAFT_PERMANENTLY_DELETED' in pg_get_functiondef(p.oid))>0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='delete_report_card_permanently' limit 1")" = "t"
  test "$(psql "$db_url" -Atc "select c.relrowsecurity and c.relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='emergency_academic_delegations'")" = "t"
  test "$(psql "$db_url" -Atc "select position('studentprofile' in lower(pg_get_functiondef(p.oid)))>0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_workflow_notifications' limit 1")" = "t"
  test "$(psql "$db_url" -Atc "select exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='class_timetable_entries' and t.tgname='class_timetable_entry_integrity_guard' and not t.tgisinternal) and exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='class_timetable_entries' and t.tgname='class_timetable_entries_audit' and not t.tgisinternal)")" = "t"
  test "$(psql "$db_url" -Atc "select count(*)=5 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal and ((c.relname='teachers' and t.tgname in('teachers_audit','teachers_license_write_guard','sync_teacher_record_class_links_trigger')) or (c.relname='headteachers' and t.tgname in('headteachers_audit','headteachers_license_write_guard')))")" = "t"

  WORKER_BOOTSTRAP_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.get_bootstrap_data() is not null; rollback;" | tail -1)"
  WORKER_ACCESS_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.list_profiles_with_access() is not null; rollback;" | tail -1)"
  WORKER_STUDENT_SEARCH_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.search_students('',null,'active'::public.student_status,1,25) is not null; rollback;" | tail -1)"
  WORKER_ACADEMIC_CONFIG_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.get_academic_configuration() is not null; rollback;" | tail -1)"
  WORKER_ACADEMIC_CALENDAR_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.get_academic_calendar_context() is not null; rollback;" | tail -1)"
  WORKER_IDENTIFIER_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.generate_school_identifier('student') like '$EXPECTED_IDENTIFIER_ROOT-STU-%'; rollback;" | tail -1)"
  WORKER_IMPORT_VALIDATION_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select (public.validate_student_import(jsonb_build_array(jsonb_build_object('admission_no','SYN-VAL-001','first_name','Ama','last_name','Owusu','gender','Female')),null,null,'preview.csv')->>'valid_count')::integer=1; rollback;" | tail -1)"
  WORKER_PROMOTION_CUTOFF_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select (public.save_promotion_cutoff(55)->>'promotion_cutoff_score')::integer=55; rollback;" | tail -1)"
  WORKER_ACADEMIC_SAVE_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.save_academic_entity('academic_years',jsonb_build_object('name','Synthetic 2026/2027','start_date','2026-09-01','end_date','2027-07-31')) is not null; rollback;" | tail -1)"
  WORKER_ASSESSMENT_SAVE_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.save_assessment_scheme(jsonb_build_object('name','Synthetic Assessment Scheme','active',true,'components',jsonb_build_array(jsonb_build_object('name','Synthetic Component','code','SYN','maximum_score',100,'weight',100,'display_order',1,'required',true)))) is not null; rollback;" | tail -1)"
  WORKER_STAFF_CRUD_OK="$(psql "$db_url" -X -qAtc "
begin;
set local role edusentia_worker_runtime;
select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint);
do \$staff_smoke\$
declare
  teacher_result jsonb;
  teacher_id uuid;
  principal_result jsonb;
  principal_id uuid;
begin
  teacher_result:=public.save_teacher(jsonb_build_object(
    'first_name','Synthetic',
    'last_name','Teacher',
    'gender','Other',
    'qualification','Bachelor Degree',
    'employment_status','active',
    'active',true,
    'reason','Synthetic lifecycle teacher'
  ));
  teacher_id:=nullif(teacher_result#>>'{teacher,id}','')::uuid;
  if teacher_id is null then raise exception 'synthetic_teacher_not_created'; end if;
  if public.get_teacher_record(teacher_id)#>>'{teacher,id}' is distinct from teacher_id::text then raise exception 'synthetic_teacher_read_failed'; end if;
  if coalesce((public.list_teachers('Synthetic','','active',1,20)->>'total')::integer,0)<1 then raise exception 'synthetic_teacher_list_failed'; end if;
  if not public.archive_teacher(teacher_id,'Synthetic lifecycle archive') then raise exception 'synthetic_teacher_archive_failed'; end if;
  if not public.restore_teacher(teacher_id,'Synthetic lifecycle restore') then raise exception 'synthetic_teacher_restore_failed'; end if;
  if coalesce((public.list_audit_events('teachers',teacher_id,1,25)->>'total')::integer,0)<1 then raise exception 'synthetic_teacher_audit_missing'; end if;

  principal_result:=public.save_headteacher(jsonb_build_object(
    'full_name','Synthetic Principal',
    'contact','+233000000000',
    'reason','Synthetic lifecycle principal'
  ));
  principal_id:=coalesce(nullif(principal_result#>>'{principal,id}','')::uuid,nullif(principal_result#>>'{headteacher,id}','')::uuid);
  if principal_id is null then raise exception 'synthetic_principal_not_created'; end if;
  if public.get_headteacher_record(principal_id)#>>'{principal,id}' is distinct from principal_id::text then raise exception 'synthetic_principal_read_failed'; end if;
  if coalesce((public.list_headteachers('Synthetic','','active',1,20)->>'total')::integer,0)<1 then raise exception 'synthetic_principal_list_failed'; end if;
  if not public.archive_headteacher(principal_id,'Synthetic lifecycle archive') then raise exception 'synthetic_principal_archive_failed'; end if;
  if not public.restore_headteacher(principal_id,'Synthetic lifecycle restore') then raise exception 'synthetic_principal_restore_failed'; end if;
  if coalesce((public.list_audit_events('headteachers',principal_id,1,25)->>'total')::integer,0)<1 then raise exception 'synthetic_principal_audit_missing'; end if;
end
\$staff_smoke\$;
select true;
rollback;
" | tail -1)"
  WORKER_TIMETABLE_CONSOLE_OK="$(psql "$db_url" -X -qAtc "
begin;
set local role edusentia_worker_runtime;
select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint);
do \$timetable_smoke\$
declare
  cfg jsonb;
  year_id uuid;
  class_id uuid;
  console jsonb;
begin
  cfg:=public.save_academic_entity(
    'academic_years',
    jsonb_build_object(
      'name','Synthetic Timetable 2026/2027',
      'start_date','2026-09-01',
      'end_date','2027-07-31'
    )
  );
  select nullif(x->>'id','')::uuid into year_id
  from jsonb_array_elements(cfg->'academic_years') x
  where x->>'name'='Synthetic Timetable 2026/2027'
  limit 1;
  if year_id is null then raise exception 'synthetic_timetable_year_missing'; end if;

  cfg:=public.save_academic_entity(
    'classes',
    jsonb_build_object(
      'name','Synthetic Timetable Class',
      'level_order',900,
      'active',true
    )
  );
  select nullif(x->>'id','')::uuid into class_id
  from jsonb_array_elements(cfg->'classes') x
  where x->>'name'='Synthetic Timetable Class'
  limit 1;
  if class_id is null then raise exception 'synthetic_timetable_class_missing'; end if;

  console:=public.get_class_timetable_console(year_id,class_id);
  if console is null or not coalesce((console->>'can_manage')::boolean,false) then
    raise exception 'synthetic_timetable_console_failed';
  end if;
end
\$timetable_smoke\$;
select true;
rollback;
" | tail -1)"
  test "$WORKER_BOOTSTRAP_OK" = "t"
  test "$WORKER_ACCESS_OK" = "t"
  test "$WORKER_STUDENT_SEARCH_OK" = "t"
  test "$WORKER_ACADEMIC_CONFIG_OK" = "t"
  test "$WORKER_ACADEMIC_CALENDAR_OK" = "t"
  test "$WORKER_IDENTIFIER_OK" = "t"
  test "$WORKER_IMPORT_VALIDATION_OK" = "t"
  test "$WORKER_PROMOTION_CUTOFF_OK" = "t"
  test "$WORKER_ACADEMIC_SAVE_OK" = "t"
  test "$WORKER_ASSESSMENT_SAVE_OK" = "t"
  test "$WORKER_STAFF_CRUD_OK" = "t"
  test "$WORKER_TIMETABLE_CONSOLE_OK" = "t"
  WORKER_AUDIT_ARCHIVE_OK="$(psql "$db_url" -X -qAtc "
begin;
with created_archive as (
  insert into public.audit_log_archives(archive_scope,reason,event_count,created_by)
  values('selected','Synthetic lifecycle archive',1,'$ADMIN_ID'::uuid)
  returning id
)
insert into public.audit_log_archive_entries(
  archive_id,original_event_id,actor_id,table_name,record_id,action,old_data,new_data,reason,original_created_at
)
select id,999999,'$ADMIN_ID'::uuid,'synthetic_lifecycle',null,'INSERT',null,'{}'::jsonb,'Synthetic lifecycle archive entry',now()
from created_archive;

set local role edusentia_worker_runtime;
select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint);

select
  coalesce((public.list_audit_events_v2(null,null,null,null,1,25)->>'total')::bigint,0)>=0
  and coalesce((public.list_audit_archives_v1(1,25)->>'total')::bigint,0)>=1
  and public.list_audit_archive_entries_v1(
    nullif(public.list_audit_archives_v1(1,25)#>>'{rows,0,id}','')::uuid,
    1,
    25
  ) is not null;
rollback;
" | tail -1)"

  test "$WORKER_AUDIT_ARCHIVE_OK" = "t"
  WORKER_PRINCIPAL_HISTORY_OK="$(psql "$db_url" -X -qAtc "
begin;
set local role edusentia_worker_runtime;
select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'principal',2::smallint);
select public.search_students_v5('',null,null,'all',1,20) is not null;
rollback;
" | tail -1)"

  test "$WORKER_PRINCIPAL_HISTORY_OK" = "t"
  WORKER_EMERGENCY_DELEGATIONS_OK="$(psql "$db_url" -X -qAtc "
begin;
set local role edusentia_worker_runtime;
select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint);
select public.get_my_emergency_academic_delegations(null,null)='[]'::jsonb;
rollback;
" | tail -1)"

  test "$WORKER_EMERGENCY_DELEGATIONS_OK" = "t"
}

install_tenant "$BASIC_DB" "00000000-0000-4000-8000-000000000101" "BSC-900001" "Synthetic Basic School" "basic_jhs" "admin@basic.synthetic.invalid"
install_tenant "$SHS_DB" "00000000-0000-4000-8000-000000000102" "SHS-900002" "Synthetic Senior High School" "senior_high" "admin@shs.synthetic.invalid"

BASIC_URL="$(url_for "$BASIC_DB")"
SHS_URL="$(url_for "$SHS_DB")"
echo "::add-mask::$BASIC_URL"
echo "::add-mask::$SHS_URL"

psql "$BASIC_URL" -v ON_ERROR_STOP=1 -c "insert into app.students(tenant_id,student_no,first_name,last_name) values('00000000-0000-4000-8000-000000000101','SYN-001','Ada','Mensah');" >/dev/null
test "$(psql "$BASIC_URL" -Atc "select count(*) from app.students where tenant_id='00000000-0000-4000-8000-000000000101'")" = "1"
test "$(psql "$SHS_URL" -Atc "select count(*) from app.students")" = "0"

echo "Synthetic Basic/JHS and Senior High isolated-school lifecycle smoke passed."
