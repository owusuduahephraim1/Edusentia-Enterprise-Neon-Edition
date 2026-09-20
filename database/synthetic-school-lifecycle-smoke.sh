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
  test "$(psql "$db_url" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0034"
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
  test "$(psql "$db_url" -Atc "select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname='students'")" = "t"
  test "$(psql "$db_url" -Atc "select promotion_cutoff_score=50 and identifier_root='$EXPECTED_IDENTIFIER_ROOT' from public.school_settings order by created_at,id limit 1")" = "t"
  test "$(psql "$db_url" -Atc "select not has_function_privilege('edusentia_worker_runtime','public.safe_uuid(text)','execute') and not has_sequence_privilege('edusentia_worker_runtime','public.student_identifier_seq','usage')")" = "t"
  test "$(psql "$db_url" -Atc "select has_function_privilege('edusentia_worker_runtime','public.generate_school_identifier(text)','execute') and has_function_privilege('edusentia_worker_runtime','public.validate_student_import(jsonb,uuid,uuid,text)','execute') and has_function_privilege('edusentia_worker_runtime','public.save_promotion_cutoff(integer)','execute') and not has_function_privilege('edusentia_worker_runtime','public.can_manage_student(uuid)','execute')")" = "t"

  WORKER_BOOTSTRAP_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.get_bootstrap_data() is not null; rollback;" | tail -1)"
  WORKER_ACCESS_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.list_profiles_with_access() is not null; rollback;" | tail -1)"
  WORKER_STUDENT_SEARCH_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.search_students('',null,'active'::public.student_status,1,25) is not null; rollback;" | tail -1)"
  WORKER_ACADEMIC_CONFIG_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.get_academic_configuration() is not null; rollback;" | tail -1)"
  WORKER_ACADEMIC_CALENDAR_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.get_academic_calendar_context() is not null; rollback;" | tail -1)"
  WORKER_IDENTIFIER_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select public.generate_school_identifier('student') like '$EXPECTED_IDENTIFIER_ROOT-STU-%'; rollback;" | tail -1)"
  WORKER_IMPORT_VALIDATION_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select (public.validate_student_import('[{"admission_no":"SYN-VAL-001","first_name":"Ama","last_name":"Owusu","gender":"Female"}]'::jsonb,null,null,'preview.csv')->>'valid_count')::integer=1; rollback;" | tail -1)"
  WORKER_PROMOTION_CUTOFF_OK="$(psql "$db_url" -X -qAtc "begin; set local role edusentia_worker_runtime; select app.set_request_context('$tenant_id'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint); select (public.save_promotion_cutoff(55)->>'promotion_cutoff_score')::integer=55; rollback;" | tail -1)"
  test "$WORKER_BOOTSTRAP_OK" = "t"
  test "$WORKER_ACCESS_OK" = "t"
  test "$WORKER_STUDENT_SEARCH_OK" = "t"
  test "$WORKER_ACADEMIC_CONFIG_OK" = "t"
  test "$WORKER_ACADEMIC_CALENDAR_OK" = "t"
  test "$WORKER_IDENTIFIER_OK" = "t"
  test "$WORKER_IMPORT_VALIDATION_OK" = "t"
  test "$WORKER_PROMOTION_CUTOFF_OK" = "t"
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
