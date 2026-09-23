#!/usr/bin/env bash
set -euo pipefail
: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL is required}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT="$DIR/blueprint-r40-v9"

has_migration() {
  psql "$TARGET_DATABASE_URL" -Atc "select 1 from app.schema_migrations where version='$1' limit 1" | grep -qx 1
}

mark_migration() {
  psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -c "insert into app.schema_migrations(version) values ('$1') on conflict do nothing;" >/dev/null
}

run_once() {
  local key="$1" file="$2"
  if has_migration "$key"; then
    echo "Operational compatibility $key already installed."
    return 0
  fi
  echo "Installing operational compatibility $key ..."
  psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
  mark_migration "$key"
}

run_reference_once() {
  local key="$1" file="$2" tmp
  if has_migration "$key"; then
    echo "Operational compatibility $key already installed."
    return 0
  fi
  tmp="$(mktemp)"
  # The blueprint SQL includes Supabase ACL roles (anon/authenticated/service_role).
  # Neon preserves the business schema/functions but applies its own Worker-only ACLs in 0049z.
  sed -E '/^[[:space:]]*(grant|revoke)[[:space:]].*(anon|authenticated|service_role)([ ,;]|$)/Id' "$file" > "$tmp"
  echo "Installing Neon-adapted blueprint compatibility $key ..."
  psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$tmp"
  rm -f "$tmp"
  mark_migration "$key"
}

reconcile_once_recorded() {
  local key="$1" file="$2"
  echo "Reconciling operational reference data $key ..."
  psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
  mark_migration "$key"
}

run_once "0049a_operational_finance_reference" "$DIR/0049a_operational_finance_reference.sql"
run_reference_once "0049b_hr_staff_management" "$BLUEPRINT/hr_staff_management_v1.sql"
run_reference_once "0049c_hr_staff_hardening" "$BLUEPRINT/hr_staff_performance_and_sync_hardening_v1.sql"

run_reference_once "0049d_student_services_foundation" "$BLUEPRINT/student_services_foundation_v1.sql"
run_reference_once "0049e_admissions_management" "$BLUEPRINT/admissions_applicant_management_v1.sql"
run_reference_once "0049f_admissions_actions" "$BLUEPRINT/admissions_applicant_actions_v1.sql"
run_reference_once "0049g_admissions_enrollment_reversal" "$BLUEPRINT/admissions_enrollment_reversal_v1.sql"
run_reference_once "0049h_admissions_core_student_compat" "$BLUEPRINT/admissions_core_student_compatibility_v1.sql"

run_reference_once "0049i_discipline_welfare" "$BLUEPRINT/discipline_welfare_management_v1.sql"
run_reference_once "0049j_health_clinic" "$BLUEPRINT/health_clinic_management_v1.sql"
run_reference_once "0049k_communications" "$BLUEPRINT/communications_messaging_centre_v1.sql"
run_reference_once "0049l_hostel_boarding" "$BLUEPRINT/hostel_boarding_management_v1.sql"
run_reference_once "0049m_alumni" "$BLUEPRINT/alumni_graduate_management_v1.sql"

run_reference_once "0049n_student_services_directory" "$BLUEPRINT/student_services_common_directory_v1.sql"
run_reference_once "0049o_student_services_reference" "$BLUEPRINT/student_services_reference_data_v1.sql"
run_reference_once "0049p_student_services_hostel_bridge" "$BLUEPRINT/student_services_hostel_reference_bridge_v1.sql"
run_reference_once "0049q_student_services_resolution" "$BLUEPRINT/student_services_resolution_parameter_hardening_v1.sql"
run_reference_once "0049r_student_services_hardening" "$BLUEPRINT/student_services_security_performance_hardening_v1.sql"

run_reference_once "0049s_user_student_guardian_linkage" "$BLUEPRINT/user_access_student_guardian_linkage_v1.sql"
run_reference_once "0049t_student_portal" "$BLUEPRINT/student_portal_v1.sql"
run_reference_once "0049u_student_portal_report_attendance_fix" "$BLUEPRINT/student_portal_v2_report_attendance_fix.sql"

reconcile_once_recorded "0049v_live_plan_feature_parity" "$DIR/0049v_live_plan_feature_parity.sql"
reconcile_once_recorded "0049w_school_identity_logo_parity" "$DIR/0049w_school_identity_logo_parity.sql"
reconcile_once_recorded "0049x_class_scoped_student_admission_numbers" "$DIR/0049x_class_scoped_student_admission_numbers.sql"
reconcile_once_recorded "0049y_audit_permanent_reset" "$DIR/0049y_audit_permanent_reset.sql"
run_once "0049z_operational_runtime_grants" "$DIR/0049z_operational_runtime_grants.sql"
run_once "0051_r2_upload_metadata_api" "$DIR/0051_r2_upload_metadata_api.sql"
run_once "0052_school_logo_tenant_context_fix" "$DIR/0052_school_logo_tenant_context_fix.sql"
run_once "0053_blueprint_template_path_parity" "$DIR/0053_blueprint_template_path_parity.sql"
run_once "0054_shs_operational_parity" "$DIR/0054_shs_operational_parity.sql"
run_once "0055_teacher_photo_r2_authorization" "$DIR/0055_teacher_photo_r2_authorization.sql"
run_once "0056_teacher_photo_neon_context_fix" "$DIR/0056_teacher_photo_neon_context_fix.sql"

test "$(psql "$TARGET_DATABASE_URL" -Atc "select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('edusentia_worker_runtime',p.oid,'EXECUTE') and (p.proname like 'finance_%' or p.proname like 'hr_%' or p.proname like 'student_services_%' or p.proname like 'admissions_%' or p.proname like 'discipline_%' or p.proname like 'welfare_%' or p.proname like 'health_%' or p.proname like 'communications_%' or p.proname like 'hostel_%' or p.proname like 'alumni_%' or p.proname in ('get_my_student_portal','get_my_student_portal_v2'))")" -ge 85

echo "Operational tenant parity compatibility installed."
