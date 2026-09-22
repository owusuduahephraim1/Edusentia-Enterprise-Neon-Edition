#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

MASTER_DATABASE="${MASTER_DATABASE:-edusentia}"
EXPECTED_RUNTIME_USER="${EXPECTED_RUNTIME_USER:-edusentia_runtime}"
MANIFEST="reference/future-tenant-rpc-surface.json"

command -v psql >/dev/null 2>&1 || { echo "psql is required" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node is required" >&2; exit 1; }
test -f "$MANIFEST"

test "$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select current_database()")" = "$MASTER_DATABASE"
test "$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select current_user")" = "$EXPECTED_RUNTIME_USER"

BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" node --input-type=module -e '
  const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);
  if(u.hostname.includes("-pooler."))throw new Error("Existing tenant upgrades require the direct Neon endpoint");
  if(u.pathname!=="/edusentia")throw new Error("Existing tenant upgrades must start from the edusentia control database");
'

EXPECTED_FILE="$(mktemp)"
ACTUAL_FILE="$(mktemp)"
MISSING_FILE="$(mktemp)"
trap 'rm -f "$EXPECTED_FILE" "$ACTUAL_FILE" "$MISSING_FILE"' EXIT

node --input-type=module -e '
  import fs from "node:fs";
  const x=JSON.parse(fs.readFileSync("reference/future-tenant-rpc-surface.json","utf8"));
  if(x.rpcCount!==258||x.operations.length!==258||new Set(x.operations).size!==258){
    throw new Error("Future tenant RPC manifest must contain exactly 258 unique operations");
  }
  process.stdout.write([...x.operations].sort().join("\n")+"\n");
' > "$EXPECTED_FILE"

mapfile -t TENANTS < <(
  psql "$BOOTSTRAP_DATABASE_URL" -At -F $'\t' -c "
    select tenant_code,database_name
    from platform.tenant_control
    where database_state='isolated_ready'
      and database_name is not null
      and database_name<>''
    order by tenant_code
  "
)

if [ "${#TENANTS[@]}" -eq 0 ]; then
  echo "No isolated-ready tenant databases require operational compatibility verification."
  exit 0
fi

upgraded=0
for row in "${TENANTS[@]}"; do
  IFS=$'\t' read -r tenant_code database_name <<< "$row"

  [[ "$tenant_code" =~ ^[A-Z0-9][A-Z0-9_-]{2,31}$ ]] || {
    echo "::error::Unsafe tenant code returned by control plane: $tenant_code" >&2
    exit 1
  }
  [[ "$database_name" =~ ^edusentia_[a-z0-9_]{3,50}$ ]] || {
    echo "::error::Unsafe tenant database name returned by control plane: $database_name" >&2
    exit 1
  }
  case "$database_name" in
    edusentia|edusentia_tenant_template|edusentia_ci_*|edusentia_final_*|edusentia_lifecycle_*|edusentia_ref_ci_*)
      echo "::error::Refusing to upgrade reserved database: $database_name" >&2
      exit 1
      ;;
  esac

  exists="$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select count(*) from pg_database where datname='$database_name'")"
  test "$exists" = "1" || {
    echo "::error::Control plane tenant database is missing: $database_name" >&2
    exit 1
  }

  TENANT_DATABASE_URL="$(BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" TENANT_DATABASE="$database_name" node --input-type=module -e '
    const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);
    u.pathname="/"+process.env.TENANT_DATABASE;
    process.stdout.write(u.toString());
  ')"
  echo "::add-mask::$TENANT_DATABASE_URL"

  test "$(psql "$TENANT_DATABASE_URL" -Atc "select current_database()")" = "$database_name"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select current_user")" = "$EXPECTED_RUNTIME_USER"

  tenant_identity="$(psql "$TENANT_DATABASE_URL" -Atc "select code from app.tenants order by created_at limit 1")"
  test "$tenant_identity" = "$tenant_code" || {
    echo "::error::Tenant identity mismatch for $database_name" >&2
    exit 1
  }

  test "$(psql "$TENANT_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "0020"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "neon-v1.0.0-r42"

  (
    restore_public_create=false
    cleanup_public_create() {
      if [ "$restore_public_create" = true ]; then
        psql "$TENANT_DATABASE_URL" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL' || true
set role edusentia_provisioner;
revoke create on schema public from edusentia_runtime;
SQL
      fi
    }
    trap cleanup_public_create EXIT

    if [ "$(psql "$TENANT_DATABASE_URL" -Atc "select has_schema_privilege('edusentia_runtime','public','create')")" != "t" ]; then
      psql "$TENANT_DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
set role edusentia_provisioner;
grant usage,create on schema public to edusentia_runtime;
reset role;
SQL
      restore_public_create=true
    fi

    echo "Applying operational compatibility to $tenant_code ($database_name) ..."
    TARGET_DATABASE_URL="$TENANT_DATABASE_URL" bash database/reference-compat/install-operational-parity.sh
  )

  migration_count="$(psql "$TENANT_DATABASE_URL" -Atc "
    select count(*) from app.schema_migrations
    where version in(
      '0049a_operational_finance_reference','0049b_hr_staff_management','0049c_hr_staff_hardening',
      '0049d_student_services_foundation','0049e_admissions_management','0049f_admissions_actions',
      '0049g_admissions_enrollment_reversal','0049h_admissions_core_student_compat',
      '0049i_discipline_welfare','0049j_health_clinic','0049k_communications','0049l_hostel_boarding',
      '0049m_alumni','0049n_student_services_directory','0049o_student_services_reference',
      '0049p_student_services_hostel_bridge','0049q_student_services_resolution',
      '0049r_student_services_hardening','0049s_user_student_guardian_linkage','0049t_student_portal',
      '0049u_student_portal_report_attendance_fix','0049z_operational_runtime_grants'
    )
  ")"
  test "$migration_count" = "22"

  psql "$TENANT_DATABASE_URL" -Atc "
    select distinct p.proname
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and has_function_privilege('edusentia_worker_runtime',p.oid,'EXECUTE')
    order by p.proname
  " > "$ACTUAL_FILE"

  comm -23 "$EXPECTED_FILE" "$ACTUAL_FILE" > "$MISSING_FILE"
  if [ -s "$MISSING_FILE" ]; then
    echo "::error::Tenant $tenant_code is missing executable future-tenant RPCs:" >&2
    cat "$MISSING_FILE" >&2
    exit 1
  fi

  echo "Tenant $tenant_code operational surface verified: 258/258 executable."
  upgraded=$((upgraded+1))
done

echo "Existing isolated tenant operational upgrades verified: $upgraded tenant(s)."
