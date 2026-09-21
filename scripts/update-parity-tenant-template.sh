#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

EXPECTED_HOST="ep-shy-meadow-b5e4d9e4.c-7.us-east-2.aws.neon.tech"
MASTER_DB="edusentia"
TEMPLATE_DB="edusentia_tenant_template"

MASTER_URL="$(EXPECTED_HOST="$EXPECTED_HOST" BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" node --input-type=module -e '
  const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);
  const direct=process.env.EXPECTED_HOST;
  const pooled=direct.replace(".c-7.","-pooler.c-7.");
  if(u.hostname!==direct && u.hostname!==pooled) throw new Error("Refusing non-parity Neon host");
  u.hostname=direct;
  u.pathname="/edusentia";
  process.stdout.write(u.toString());
')"
TEMPLATE_URL="$(MASTER_URL="$MASTER_URL" TEMPLATE_DB="$TEMPLATE_DB" node --input-type=module -e '
  const u=new URL(process.env.MASTER_URL);
  u.pathname="/"+process.env.TEMPLATE_DB;
  process.stdout.write(u.toString());
')"
echo "::add-mask::$MASTER_URL"
echo "::add-mask::$TEMPLATE_URL"

test "$(psql "$MASTER_URL" -Atc "select current_database()")" = "$MASTER_DB"
test "$(psql "$MASTER_URL" -Atc "select session_user||'|'||current_user||'|'||current_setting('role')")" = "edusentia_runtime|edusentia_runtime|none"
test "$(psql "$MASTER_URL" -Atc "select pg_get_userbyid(datdba) from pg_database where datname='$TEMPLATE_DB'")" = "edusentia_provisioner"

relock() {
  psql "$MASTER_URL" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
set role edusentia_provisioner;
alter database "$TEMPLATE_DB" with allow_connections false;
revoke connect on database "$TEMPLATE_DB" from edusentia_runtime;
SQL
}
trap relock EXIT

psql "$MASTER_URL" -v ON_ERROR_STOP=1 <<SQL
set role edusentia_provisioner;
grant connect on database "$TEMPLATE_DB" to edusentia_runtime;
alter database "$TEMPLATE_DB" with allow_connections true;
SQL
psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='$TEMPLATE_DB' and pid<>pg_backend_pid();" >/dev/null

apply_once() {
  local version="$1"
  local file="$2"
  local installed
  installed="$(psql "$TEMPLATE_URL" -Atc "select count(*) from app.schema_migrations where version='$version'")"
  if [ "$installed" = "0" ]; then
    echo "Applying $version to $TEMPLATE_DB"
    psql "$TEMPLATE_URL" -v ON_ERROR_STOP=1 -f "$file"
  else
    echo "$version already installed in $TEMPLATE_DB"
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
apply_once "0048g_certified_operational_rls_enforcement" "database/reference-compat/0048g_certified_operational_rls_enforcement.sql"
apply_once "0048h_certified_release_identity" "database/reference-compat/0048h_certified_release_identity.sql"

test "$(psql "$TEMPLATE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"

TARGET_DATABASE_URL="$TEMPLATE_URL" node scripts/reference-surface-inventory.mjs | tee /tmp/parity-template-surface.json
node - <<'NODE'
const fs=require("node:fs");
const result=JSON.parse(fs.readFileSync("/tmp/parity-template-surface.json","utf8").trim().split(/\n/).at(-1));
if(result.referenceRpcCount!==172 ||
   result.installedReferenceRpcCount!==172 ||
   result.executableReferenceRpcCount!==172 ||
   result.missingCount!==0 ||
   result.blockedCount!==0){
  console.error(result);
  process.exit(1);
}
console.log("Parity tenant template verified: 172/172 certified browser RPCs executable.");
NODE

relock
trap - EXIT
test "$(psql "$MASTER_URL" -Atc "select pg_get_userbyid(datdba)||'|'||datallowconn from pg_database where datname='$TEMPLATE_DB'")" = "edusentia_provisioner|false"
test "$(psql "$MASTER_URL" -Atc "select has_database_privilege('edusentia_runtime','$TEMPLATE_DB','connect')")" = "f"

echo "Parity tenant template updated incrementally through certified compatibility 0048 and relocked."
