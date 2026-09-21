#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"
TARGET_DATABASE="${PARITY_REFERENCE_DATABASE:-edusentia_rpt_000001}"
EXPECTED_DATABASE="edusentia_rpt_000001"
EXPECTED_HOST="ep-shy-meadow-b5e4d9e4.c-7.us-east-2.aws.neon.tech"

if [ "$TARGET_DATABASE" != "$EXPECTED_DATABASE" ]; then
  echo "Refusing to update unexpected database: $TARGET_DATABASE" >&2
  exit 1
fi

TARGET_URL="$(EXPECTED_HOST="$EXPECTED_HOST" BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" TARGET_DATABASE="$TARGET_DATABASE" node --input-type=module -e '
  const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);
  const direct=process.env.EXPECTED_HOST;
  const pooled=direct.replace(".c-7.","-pooler.c-7.");
  if(u.hostname!==direct && u.hostname!==pooled) throw new Error("Parity reference updater received a non-parity host");
  u.hostname=direct;
  u.pathname="/"+process.env.TARGET_DATABASE;
  process.stdout.write(u.toString());
')"
echo "::add-mask::$TARGET_URL"

test "$(psql "$TARGET_URL" -Atc "select current_database()")" = "$EXPECTED_DATABASE"
test "$(psql "$TARGET_URL" -Atc "select session_user")" = "edusentia_runtime"

cleanup_schema_create() {
  psql "$TARGET_URL" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
set role edusentia_provisioner;
revoke create on schema public from edusentia_runtime;
SQL
}
trap cleanup_schema_create EXIT

psql "$TARGET_URL" -v ON_ERROR_STOP=1 <<SQL
set role edusentia_provisioner;
grant usage,create on schema public to edusentia_runtime;
SQL

apply_once() {
  local version="$1"
  local file="$2"
  local installed
  installed="$(psql "$TARGET_URL" -Atc "select count(*) from app.schema_migrations where version='$version'")"
  if [ "$installed" = "0" ]; then
    echo "Applying $version"
    psql "$TARGET_URL" -v ON_ERROR_STOP=1 -f "$file"
  else
    echo "$version already installed"
  fi
}

apply_once "0045c_certified_operational_schema" "database/reference-compat/0045c_certified_operational_schema.sql"
apply_once "0045d_certified_rpc_helper_closure" "database/reference-compat/0045d_certified_rpc_helper_closure.sql"
apply_once "0046_certified_reference_rpc_bulk" "database/reference-compat/0046_certified_reference_rpc_bulk.sql"
apply_once "0047_certified_identity_rpc_neon" "database/reference-compat/0047_certified_identity_rpc_neon.sql"
apply_once "0048_certified_provider_rpc_neon_r2" "database/reference-compat/0048_certified_provider_rpc_neon_r2.sql"
apply_once "0048b_certified_certificate_settings_compat" "database/reference-compat/0048b_certified_certificate_settings_compat.sql"
apply_once "0048c_certified_backup_settings_compat" "database/reference-compat/0048c_certified_backup_settings_compat.sql"
apply_once "0048d_certified_system_health_telemetry_compat" "database/reference-compat/0048d_certified_system_health_telemetry_compat.sql"
apply_once "0048e_certified_system_health_notification_compat" "database/reference-compat/0048e_certified_system_health_notification_compat.sql"
apply_once "0048f_certified_backup_health_metadata_compat" "database/reference-compat/0048f_certified_backup_health_metadata_compat.sql"
# 0048g preflights all certified public-table RLS policies before forcing RLS.
# 0048g named-block syntax is contract-tested before persistent parity promotion.
apply_once "0048g_certified_operational_rls_enforcement" "database/reference-compat/0048g_certified_operational_rls_enforcement.sql"

SYSTEM_HEALTH_MISSING_COLUMNS="$(psql "$TARGET_URL" -X -qAt <<'SQL'
with required(table_name,column_name) as (
  values
    ('backup_exports','completed_at'),('backup_exports','created_at'),('backup_exports','status'),
    ('backup_exports','backup_type'),('backup_exports','verification_checked_at'),('backup_exports','verification_status'),
    ('backup_exports','offsite_copied_at'),
    ('recovery_test_runs','completed_at'),('recovery_test_runs','status'),
    ('client_error_events','occurrence_count'),('client_error_events','last_seen_at'),('client_error_events','status'),('client_error_events','severity'),
    ('notification_outbox','attempts'),('notification_outbox','created_at'),('notification_outbox','processed_at'),
    ('security_events','status'),('security_events','severity'),
    ('report_publications','revoked_at'),('report_publications','storage_path'),
    ('profiles','active'),('teachers','active'),('teachers','deleted_at'),('students','status'),('students','deleted_at'),
    ('assessment_components','scheme_id'),('assessment_components','weight'),
    ('assessment_schemes','id'),('assessment_schemes','name')
)
select coalesce(string_agg(format('%I.%I',r.table_name,r.column_name),',' order by r.table_name,r.column_name),'')
from required r
where not exists (
  select 1 from information_schema.columns c
  where c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name
);
SQL
)"
echo "SYSTEM_HEALTH_MISSING_COLUMNS=${SYSTEM_HEALTH_MISSING_COLUMNS:-none}"
if [ -n "$SYSTEM_HEALTH_MISSING_COLUMNS" ]; then
  echo "::error::Certified system_health schema dependencies are missing: $SYSTEM_HEALTH_MISSING_COLUMNS"
  exit 1
fi

test "$(psql "$TARGET_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"

cleanup_schema_create
trap - EXIT
test "$(psql "$TARGET_URL" -Atc "select has_schema_privilege('edusentia_runtime','public','create')")" = "f"

echo "Parity reference tenant $EXPECTED_DATABASE updated through certified compatibility 0048."
