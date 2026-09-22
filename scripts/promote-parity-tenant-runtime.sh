#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

EXPECTED_HOST="ep-shy-meadow-b5e4d9e4.c-7.us-east-2.aws.neon.tech"
MASTER_DB="edusentia"
TEMPLATE_DB="edusentia_tenant_template"
REFERENCE_DB="edusentia_rpt_000001"

PARITY_URL="$(EXPECTED_HOST="$EXPECTED_HOST" BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" node --input-type=module -e '
  const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);
  const direct=process.env.EXPECTED_HOST;
  const pooled=direct.replace(".c-7.","-pooler.c-7.");
  if(u.hostname!==direct && u.hostname!==pooled) throw new Error("Refusing non-parity Neon host");
  u.hostname=direct;
  u.pathname="/edusentia";
  process.stdout.write(u.toString());
')"
echo "::add-mask::$PARITY_URL"

test "$(psql "$PARITY_URL" -Atc "select current_database()")" = "$MASTER_DB"
test "$(psql "$PARITY_URL" -Atc "select session_user||'|'||current_user||'|'||current_setting('role')")" = "edusentia_runtime|edusentia_runtime|none"
test "$(psql "$PARITY_URL" -Atc "select pg_has_role('edusentia_runtime','edusentia_provisioner','set')")" = "t"
test "$(psql "$PARITY_URL" -Atc "select pg_has_role('edusentia_runtime','edusentia_worker_runtime','set')")" = "t"

# Update and relock the non-primary tenant template incrementally.
BOOTSTRAP_DATABASE_URL="$PARITY_URL" bash scripts/update-parity-tenant-template.sh

# Update the persistent non-primary reference tenant only.
BOOTSTRAP_DATABASE_URL="$PARITY_URL" PARITY_REFERENCE_DATABASE="$REFERENCE_DB" bash scripts/update-parity-reference-tenant.sh

# Apply the same idempotent operational layer used for production existing tenants.
BOOTSTRAP_DATABASE_URL="$PARITY_URL" bash scripts/update-isolated-operational-tenants.sh

REFERENCE_URL="$(PARITY_URL="$PARITY_URL" REFERENCE_DB="$REFERENCE_DB" node --input-type=module -e '
  const u=new URL(process.env.PARITY_URL);
  u.pathname="/"+process.env.REFERENCE_DB;
  process.stdout.write(u.toString());
')"
echo "::add-mask::$REFERENCE_URL"

test "$(psql "$REFERENCE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"
test "$(psql "$REFERENCE_URL" -Atc "select count(*) from app.schema_migrations where version like '0049%'")" = "23"
test "$(psql "$REFERENCE_URL" -Atc "select count(*) from app.schema_migrations where version='0049_operational_blueprint_parity'")" = "1"
test "$(psql "$REFERENCE_URL" -Atc "select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('edusentia_worker_runtime',p.oid,'EXECUTE')")" -ge 258
test "$(psql "$PARITY_URL" -Atc "select pg_get_userbyid(datdba)||'|'||datallowconn from pg_database where datname='$TEMPLATE_DB'")" = "edusentia_provisioner|false"
test "$(psql "$PARITY_URL" -Atc "select pg_get_userbyid(datdba)||'|'||datallowconn from pg_database where datname='$REFERENCE_DB'")" = "edusentia_provisioner|true"

TARGET_DATABASE_URL="$REFERENCE_URL" node scripts/reference-surface-inventory.mjs | tee /tmp/parity-reference-surface.json
node - <<'NODE'
const fs=require("node:fs");
const lines=fs.readFileSync("/tmp/parity-reference-surface.json","utf8").trim().split(/\n/);
const result=JSON.parse(lines.at(-1));
if(result.referenceRpcCount!==172 ||
   result.installedReferenceRpcCount!==172 ||
   result.executableReferenceRpcCount!==172 ||
   result.missingCount!==0 ||
   result.blockedCount!==0){
  console.error(result);
  process.exit(1);
}
console.log("Persistent parity reference tenant verified: 172/172 certified browser RPCs executable.");
NODE

echo "Parity tenant template and persistent reference tenant promoted through certified compatibility 0048 plus operational parity 0049."
