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

psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "alter database \"$TEMPLATE_DB\" with allow_connections true;" 2>/dev/null || true
psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='$TEMPLATE_DB' and pid<>pg_backend_pid();" >/dev/null 2>&1 || true

if ! psql "$MASTER_URL" -Atc "select 1 from pg_database where datname='$TEMPLATE_DB'" | grep -qx 1; then
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
psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f database/tenant-template/runtime-role.sql

test "$(psql "$TEMPLATE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "0020"
test "$(psql "$TEMPLATE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0032"
test "$(psql "$TEMPLATE_URL" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_bootstrap_data'")" -ge 1
test "$(psql "$TEMPLATE_URL" -Atc "select has_table_privilege('edusentia_worker_runtime','app.students','select') and has_function_privilege('edusentia_worker_runtime','authn.lookup_login(text,text)','execute')")" = "t"

psql "$MASTER_URL" -v ON_ERROR_STOP=1 <<SQL
alter database "$TEMPLATE_DB" owner to edusentia_provisioner;
revoke connect on database "$TEMPLATE_DB" from public;
grant connect on database "$TEMPLATE_DB" to edusentia_runtime;
grant connect on database "$TEMPLATE_DB" to edusentia_worker_runtime;
grant connect on database "$TEMPLATE_DB" to edusentia_provisioner;
alter database "$TEMPLATE_DB" with allow_connections false;
SQL

echo "Tenant template $TEMPLATE_DB is installed and locked."
