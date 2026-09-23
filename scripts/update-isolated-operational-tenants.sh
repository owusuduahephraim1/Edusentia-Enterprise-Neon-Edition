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
      '0049u_student_portal_report_attendance_fix','0049v_live_plan_feature_parity','0049w_school_identity_logo_parity','0049x_class_scoped_student_admission_numbers','0049y_audit_permanent_reset','0049z_operational_runtime_grants','0051_r2_upload_metadata_api','0052_school_logo_tenant_context_fix','0053_blueprint_template_path_parity','0054_shs_operational_parity','0055_teacher_photo_r2_authorization','0056_teacher_photo_neon_context_fix','0057_teacher_photo_reference_contract','0058_reusable_student_admission_numbers','0059_student_photo_r2_contract','0060_principal_photo_r2_contract','0061_discovered_operational_parity_repairs','0062_user_directory_role_workspace_parity'
    )
  ")"
  test "$migration_count" = "38"

  user_workspace_parity_ok="$(psql "$TENANT_DATABASE_URL" -Atc "
    select exists(select 1 from information_schema.columns where table_schema='public' and table_name='students' and column_name='profile_id')
      and to_regclass('public.students_profile_id_uidx') is not null
      and has_function_privilege('edusentia_worker_runtime','public.list_profiles_with_access()','execute')
      and position('''teacher_records''' in pg_get_functiondef('public.list_profiles_with_access()'::regprocedure))>0
      and position('''headteacher_records''' in pg_get_functiondef('public.list_profiles_with_access()'::regprocedure))>0
      and position('''accountant_records''' in pg_get_functiondef('public.list_profiles_with_access()'::regprocedure))>0
      and position('''student_records''' in pg_get_functiondef('public.list_profiles_with_access()'::regprocedure))>0
      and position('authn.users' in pg_get_functiondef('public.list_profiles_with_access()'::regprocedure))>0
      and exists(select 1 from pg_policies where schemaname='public' and tablename='teachers' and policyname='neon_certified_runtime_owner' and 'edusentia_runtime'=any(roles))
      and exists(select 1 from pg_policies where schemaname='public' and tablename='headteachers' and policyname='neon_certified_runtime_owner' and 'edusentia_runtime'=any(roles))
  ")"
  test "$user_workspace_parity_ok" = "t"

  plan_parity_count="$(psql "$TENANT_DATABASE_URL" -Atc "
    select count(*)
    from platform.license_plans p
    where p.code in('starter','professional','enterprise')
      and (select count(*) from jsonb_object_keys(p.feature_flags))=27
      and p.feature_flags->>'id_cards'='true'
      and p.feature_flags->>'staff_id_cards'='true'
      and p.feature_flags->>'timetable'='true'
      and p.feature_flags->>'school_prospectus'='true'
      and p.feature_flags->>'advanced_analytics'='false'
      and p.feature_flags->>'integrations'='false'
  ")"
  test "$plan_parity_count" = "3"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select feature_flags->>'finance_exports' from platform.license_plans where code='starter'")" = "false"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select feature_flags->>'finance_exports' from platform.license_plans where code='professional'")" = "true"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select feature_flags->>'financial_holds' from platform.license_plans where code='professional'")" = "true"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select feature_flags->>'payroll' from platform.license_plans where code='enterprise'")" = "true"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select feature_flags->>'payroll_statutory' from platform.license_plans where code='enterprise'")" = "true"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select feature_flags->>'custom_branding' from platform.license_plans where code='enterprise'")" = "true"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.set_school_logo_reference(text)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select to_regprocedure('public.generate_class_student_identifier(uuid)') is not null")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select to_regclass('public.student_admission_sequences') is not null")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.reset_audit_log(text)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.prepare_object_upload(text,text,text,bigint)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.get_object_upload_metadata(text,text)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.transition_object_upload(uuid,text,text)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('v_tenant_id' in pg_get_functiondef('public.set_school_logo_reference(text)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('report-card-templates' in pg_get_functiondef('public.save_report_card_template(text,text,text,text,bigint,text)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select pg_get_constraintdef(oid) like '%report-card-templates%' from pg_constraint where conrelid='public.report_card_templates'::regclass and conname='report_card_templates_path_chk'")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_shs_academic_console()','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_shs_academic_insert(text,jsonb)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_shs_academic_remove(text,uuid)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_authorize_teacher_photo_upload(uuid)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_teacher_photo_descriptor(uuid)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('app.current_user_id()' in pg_get_functiondef('public.neon_authorize_teacher_photo_upload(uuid)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('auth.uid()' in pg_get_functiondef('public.neon_authorize_teacher_photo_upload(uuid)'::regprocedure))=0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('app.current_user_id()' in pg_get_functiondef('public.neon_teacher_photo_descriptor(uuid)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('auth.uid()' in pg_get_functiondef('public.neon_teacher_photo_descriptor(uuid)'::regprocedure))=0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('app.current_user_id()' in pg_get_functiondef('public.set_teacher_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('staff-photos/' in pg_get_functiondef('public.set_teacher_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('storage.object_metadata' in pg_get_functiondef('public.set_teacher_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('split_part(clean_path' in pg_get_functiondef('public.set_teacher_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select not exists(select 1 from pg_constraint where conrelid='public.students'::regclass and conname='students_admission_no_key')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select to_regclass('public.students_admission_no_ci_idx') is not null")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('generate_series(1,999)' in replace(pg_get_functiondef('public.next_student_identifier_for_prefix(text)'::regprocedure),' ',''))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('s.deleted_at is null' in pg_get_functiondef('public.next_student_identifier_for_prefix(text)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('public.next_student_identifier_for_prefix' in pg_get_functiondef('public.restore_student(uuid,text)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_authorize_student_photo_upload(uuid)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_student_photo_descriptor(uuid)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('app.current_user_id()' in pg_get_functiondef('public.neon_authorize_student_photo_upload(uuid)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('student-photos/' in pg_get_functiondef('public.set_student_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('storage.object_metadata' in pg_get_functiondef('public.set_student_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_authorize_headteacher_photo_upload(uuid)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_headteacher_photo_descriptor(uuid)','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('app.current_user_id()' in pg_get_functiondef('public.neon_authorize_headteacher_photo_upload(uuid)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('app.current_user_id()' in pg_get_functiondef('public.set_headteacher_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('staff-photos/' in pg_get_functiondef('public.set_headteacher_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('storage.object_metadata' in pg_get_functiondef('public.set_headteacher_photo(uuid,text,timestamptz)'::regprocedure))>0")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_reports' and column_name='archived_status')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select has_function_privilege('edusentia_worker_runtime','public.neon_guardian_account_records()','EXECUTE')")" = "t"
  test "$(psql "$TENANT_DATABASE_URL" -Atc "select position('public.neon_cron_jobs_snapshot()' in pg_get_functiondef('public.operations_dashboard(uuid)'::regprocedure))>0")" = "t"

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

  psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -v tenant_code="$tenant_code" -v database_name="$database_name" <<'SQL'
insert into platform.tenant_events(tenant_id,registration_id,event_type,details)
select
  tenant_id,
  registration_id,
  'tenant_commercial_plan_parity_verified',
  jsonb_build_object(
    'database_name',:'database_name',
    'migration','0049v_live_plan_feature_parity',
    'feature_count',27,
    'rpc_count',258,
    'verified_at',now()
  )
from platform.tenant_control
where tenant_code=:'tenant_code'
  and database_name=:'database_name';
SQL

  echo "Tenant $tenant_code operational surface verified: 258/258 executable and 27-feature plan parity confirmed."
  upgraded=$((upgraded+1))
done

echo "Existing isolated tenant operational upgrades verified: $upgraded tenant(s)."
