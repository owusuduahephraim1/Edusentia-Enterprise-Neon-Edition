#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"
TEMPLATE_DB="${TENANT_TEMPLATE_DATABASE:-edusentia_tenant_template}"

case "$TEMPLATE_DB" in
  edusentia_[a-z0-9_]*) ;;
  *) echo "Unsafe tenant template database name"; exit 1 ;;
esac

MASTER_URL="$BOOTSTRAP_DATABASE_URL"
TEMPLATE_URL="$(BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" TEMPLATE_DB="$TEMPLATE_DB" node --input-type=module -e 'const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);u.pathname="/"+process.env.TEMPLATE_DB;process.stdout.write(u.toString())')"
echo "::add-mask::$TEMPLATE_URL"

template_exists() {
  psql "$MASTER_URL" -Atc "select 1 from pg_database where datname='$TEMPLATE_DB'" | grep -qx 1
}

template_owner() {
  psql "$MASTER_URL" -Atc "select pg_get_userbyid(datdba) from pg_database where datname='$TEMPLATE_DB'"
}

set_template_connections() {
  local value="$1"
  template_exists || return 0
  local owner
  owner="$(template_owner)"
  if [ "$owner" = "edusentia_provisioner" ]; then
    psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "set role edusentia_provisioner;" -c "alter database \"$TEMPLATE_DB\" with allow_connections $value;"
  else
    psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "alter database \"$TEMPLATE_DB\" with allow_connections $value;"
  fi
}

relock_template() {
  set_template_connections false >/dev/null 2>&1 || true
}
trap relock_template EXIT

set_template_connections true
psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='$TEMPLATE_DB' and pid<>pg_backend_pid();" >/dev/null 2>&1 || true

if ! template_exists; then
  psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "create database \"$TEMPLATE_DB\" owner edusentia_runtime;"
  for migration in     database/migrations/0001_platform_and_context.sql     database/migrations/0002_identity_auth.sql     database/migrations/0003_school_people.sql     database/migrations/0004_academics_reporting.sql     database/migrations/0005_finance_hr_admissions.sql     database/migrations/0006_audit_storage_security.sql     database/migrations/0007_rls_and_runtime_grants.sql     database/migrations/0008_bootstrap_and_retention.sql     database/migrations/0009_academic_models.sql     database/migrations/0010_student_services.sql     database/migrations/0011_finance_enterprise.sql     database/migrations/0012_documents_and_identity.sql     database/migrations/0013_operations_compliance.sql     database/migrations/0014_bootstrap_auth_hardening.sql     database/migrations/0016_mfa_login_challenges.sql
  do
    psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f "$migration"
  done
fi

psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/tenant-template/0020_tenant_runtime_parity.sql
TARGET_DATABASE_URL="$TEMPLATE_URL" bash database/reference-compat/install-core.sh
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0028_certified_compat_foundation.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0029_certified_users_access_identity.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0030_certified_academic_configuration.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0030b_certified_teacher_principal_records.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0031_certified_academic_configuration_rpc.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0032_certified_academic_calendar_context.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0033_certified_student_management_utilities.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0034_certified_student_management_hardening.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0035_certified_teacher_principal_hardening.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0036_certified_staff_runtime_guards.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0037_certified_academic_configuration_mutations.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0038_certified_teacher_principal_crud.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0039_certified_timetable_academic_alignment.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0040_certified_audit_trail_v1.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0041_certified_notification_publication_sync.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0041b_neon_notification_recipient_compat.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0042_certified_principal_academic_history_read.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0043_certified_report_governance_prerequisites.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0043b_certified_report_assignment_scope.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0044_certified_report_workflow_privacy_integrity.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0044b_certified_report_transition_helpers.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0045_certified_report_pdf_integrity_r2.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0045b_neon_report_view_compat.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0045c_certified_operational_schema.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0045d_certified_rpc_helper_closure.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0046_certified_reference_rpc_bulk.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0047_certified_identity_rpc_neon.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0048_certified_provider_rpc_neon_r2.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0048b_certified_certificate_settings_compat.sql
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0048c_certified_backup_settings_compat.sql
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0048d_certified_system_health_telemetry_compat.sql
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/reference-compat/0048e_certified_system_health_notification_compat.sql
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/tenant-template/runtime-role.sql

test "$(psql "$TEMPLATE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "0020"
test "$(psql "$TEMPLATE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"
test "$(psql "$TEMPLATE_URL" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_bootstrap_data'")" -ge 1
test "$(psql "$TEMPLATE_URL" -Atc "select has_table_privilege('edusentia_worker_runtime','app.students','select') and has_function_privilege('edusentia_worker_runtime','authn.lookup_login(text,text)','execute')")" = "t"

if [ "$(template_owner)" = "edusentia_runtime" ]; then
  psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "alter database \"$TEMPLATE_DB\" owner to edusentia_provisioner;"
fi
test "$(template_owner)" = "edusentia_provisioner"

psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -c "set role edusentia_provisioner;" -c "grant usage,create on schema public to edusentia_runtime;"
psql "$MASTER_URL" -v ON_ERROR_STOP=1 <<SQL
set role edusentia_provisioner;
revoke connect on database "$TEMPLATE_DB" from public;
grant connect on database "$TEMPLATE_DB" to edusentia_runtime;
grant connect on database "$TEMPLATE_DB" to edusentia_worker_runtime;
grant connect on database "$TEMPLATE_DB" to edusentia_provisioner;
alter database "$TEMPLATE_DB" with allow_connections false;
SQL
trap - EXIT

echo "Tenant template $TEMPLATE_DB is installed and locked."
