#!/usr/bin/env bash
set -euo pipefail

: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

ADMIN_DATABASE_URL="$(BOOTSTRAP_DATABASE_URL="$BOOTSTRAP_DATABASE_URL" node --input-type=module -e '
  const u=new URL(process.env.BOOTSTRAP_DATABASE_URL);
  u.hostname=u.hostname.replace("-pooler.",".");
  u.pathname="/edusentia";
  process.stdout.write(u.toString());
')"
TENANT_DATABASE_URL="$(ADMIN_DATABASE_URL="$ADMIN_DATABASE_URL" node --input-type=module -e '
  const u=new URL(process.env.ADMIN_DATABASE_URL);
  u.pathname="/edusentia_nis_000001";
  process.stdout.write(u.toString());
')"
echo "::add-mask::$ADMIN_DATABASE_URL"
echo "::add-mask::$TENANT_DATABASE_URL"

check() {
  local label="$1" sql="$2"
  printf '%s=' "$label"
  psql "$TENANT_DATABASE_URL" -Atc "$sql"
}

check migration_0058 "select exists(select 1 from app.schema_migrations where version='0058_reusable_student_admission_numbers')"
check global_constraint_absent "select not exists(select 1 from pg_constraint where conrelid='public.students'::regclass and conname='students_admission_no_key')"
check active_index_exists "select to_regclass('public.students_admission_no_ci_idx') is not null"
check generator_exists "select to_regprocedure('public.next_student_identifier_for_prefix(text)') is not null"
check generator_has_series "select position('generate_series(1,999)' in replace(pg_get_functiondef('public.next_student_identifier_for_prefix(text)'::regprocedure),' ',''))>0"
check generator_active_only "select position('s.deleted_at is null' in pg_get_functiondef('public.next_student_identifier_for_prefix(text)'::regprocedure))>0"
check restore_reallocates "select position('public.next_student_identifier_for_prefix' in pg_get_functiondef('public.restore_student(uuid,text)'::regprocedure))>0"
check save_active_only "select position('s.deleted_at is null' in pg_get_functiondef('public.save_student(jsonb)'::regprocedure))>0"

printf 'migration_count='
psql "$TENANT_DATABASE_URL" -Atc "select count(*) from app.schema_migrations where version in(
  '0049a_operational_finance_reference','0049b_hr_staff_management','0049c_hr_staff_hardening',
  '0049d_student_services_foundation','0049e_admissions_management','0049f_admissions_actions',
  '0049g_admissions_enrollment_reversal','0049h_admissions_core_student_compat',
  '0049i_discipline_welfare','0049j_health_clinic','0049k_communications','0049l_hostel_boarding',
  '0049m_alumni','0049n_student_services_directory','0049o_student_services_reference',
  '0049p_student_services_hostel_bridge','0049q_student_services_resolution',
  '0049r_student_services_hardening','0049s_user_student_guardian_linkage','0049t_student_portal',
  '0049u_student_portal_report_attendance_fix','0049v_live_plan_feature_parity','0049w_school_identity_logo_parity',
  '0049x_class_scoped_student_admission_numbers','0049y_audit_permanent_reset','0049z_operational_runtime_grants',
  '0051_r2_upload_metadata_api','0052_school_logo_tenant_context_fix','0053_blueprint_template_path_parity',
  '0054_shs_operational_parity','0055_teacher_photo_r2_authorization','0056_teacher_photo_neon_context_fix',
  '0057_teacher_photo_reference_contract','0058_reusable_student_admission_numbers'
)"

echo "Admission reuse diagnostic complete."
