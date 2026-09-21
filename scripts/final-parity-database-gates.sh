#!/usr/bin/env bash
set -euo pipefail
: "${SOURCE_DATABASE_URL:?SOURCE_DATABASE_URL is required}"
: "${PARITY_DATABASE_HOST:?PARITY_DATABASE_HOST is required}"

PARITY_DATABASE_URL="$(SOURCE_DATABASE_URL="$SOURCE_DATABASE_URL" PARITY_DATABASE_HOST="$PARITY_DATABASE_HOST" node --input-type=module -e '
  const u=new URL(process.env.SOURCE_DATABASE_URL);
  u.hostname=process.env.PARITY_DATABASE_HOST;
  u.pathname="/edusentia";
  process.stdout.write(u.toString());
')"
echo "::add-mask::$PARITY_DATABASE_URL"
export BOOTSTRAP_DATABASE_URL="$PARITY_DATABASE_URL"
unset CI_TEMPLATE_DATABASE || true

test "$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select current_database()")" = "edusentia"
test "$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select session_user||'|'||current_user||'|'||current_setting('role')")" = "edusentia_runtime|edusentia_runtime|none"

RUN_TOKEN="${GITHUB_RUN_ID:-local}_${GITHUB_RUN_ATTEMPT:-1}"
RUN_TOKEN="${RUN_TOKEN//-/_}"
CONTROL_DB="edusentia_final_control_${RUN_TOKEN}"
REFERENCE_DB="edusentia_final_reference_${RUN_TOKEN}"
CONTROL_DB="${CONTROL_DB:0:60}"
REFERENCE_DB="${REFERENCE_DB:0:60}"

url_for() {
  BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" TARGET_DB="$1" node --input-type=module -e '
    const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);
    u.pathname="/"+process.env.TARGET_DB;
    process.stdout.write(u.toString());
  '
}
cleanup_control(){ psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -c "drop database if exists \"$CONTROL_DB\" with (force);" >/dev/null 2>&1 || true; }
cleanup_reference(){
  psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
set role edusentia_provisioner;
drop database if exists "$REFERENCE_DB" with (force);
SQL
}
cleanup_all(){ cleanup_control; cleanup_reference; }
trap cleanup_all EXIT
cleanup_all

echo "::group::Fresh control schema gate"
psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -c "create database \"$CONTROL_DB\";"
CONTROL_URL="$(url_for "$CONTROL_DB")"
echo "::add-mask::$CONTROL_URL"
BOOTSTRAP_DATABASE_URL="$CONTROL_URL" bash database/install-master.sh
psql "$CONTROL_URL" -v ON_ERROR_STOP=1 -f database/runtime-role.sql
test "$(psql "$CONTROL_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0025"
test "$(psql "$CONTROL_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "neon-v1.0.0-r42"
test "$(psql "$CONTROL_URL" -Atc "select to_regclass('platform.school_deletion_jobs') is not null and to_regclass('platform.login_directory') is not null")" = "t"
cleanup_control
echo "Fresh production control schema gate passed."
echo "::endgroup::"

echo "::group::Disposable certified reference gate"
TENANT_TEMPLATE_DATABASE="$REFERENCE_DB" bash database/tenant-template/install.sh
psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
set role edusentia_provisioner;
alter database "$REFERENCE_DB" with allow_connections true;
SQL
REFERENCE_URL="$(url_for "$REFERENCE_DB")"
echo "::add-mask::$REFERENCE_URL"
test "$(psql "$REFERENCE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "0020"
test "$(psql "$REFERENCE_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "neon-v1.0.0-r42"
test "$(psql "$REFERENCE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"
TARGET_DATABASE_URL="$REFERENCE_URL" node scripts/reference-surface-inventory.mjs | tee /tmp/final-disposable-reference.json
node - <<'NODE'
const fs=require("node:fs");
const lines=fs.readFileSync("/tmp/final-disposable-reference.json","utf8").trim().split(/\n/);
const result=JSON.parse(lines.at(-1));
if(result.referenceRpcCount!==172||result.executableReferenceRpcCount!==172||result.missingCount!==0||result.blockedCount!==0){console.error(result);process.exit(1);}
console.log("Disposable certified reference surface verified: 172/172.");
NODE
cleanup_reference
echo "::endgroup::"

echo "::group::Synthetic Basic/JHS and Senior High lifecycle gate"
CI_TEMPLATE_DATABASE="" BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" bash database/synthetic-school-lifecycle-smoke.sh
echo "::endgroup::"

echo "::group::Persistent parity release inventory"
test "$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select pg_get_userbyid(datdba)||'|'||not datallowconn from pg_database where datname='edusentia_tenant_template'")" = "edusentia_provisioner|true"
LIVE_REFERENCE_URL="$(url_for edusentia_rpt_000001)"
echo "::add-mask::$LIVE_REFERENCE_URL"
test "$(psql "$LIVE_REFERENCE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"
test "$(psql "$LIVE_REFERENCE_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "neon-v1.0.0-r42"
TARGET_DATABASE_URL="$LIVE_REFERENCE_URL" node scripts/reference-surface-inventory.mjs | tee /tmp/final-live-reference.json
node - <<'NODE'
const fs=require("node:fs");
const lines=fs.readFileSync("/tmp/final-live-reference.json","utf8").trim().split(/\n/);
const result=JSON.parse(lines.at(-1));
if(result.referenceRpcCount!==172||result.executableReferenceRpcCount!==172||result.missingCount!==0||result.blockedCount!==0){console.error(result);process.exit(1);}
console.log("Live parity reference surface verified: 172/172.");
NODE
echo "::endgroup::"

echo "Final parity database gates passed."
