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

printf 'plan_parity_count='
psql "$TENANT_DATABASE_URL" -Atc "select count(*) from platform.license_plans p where p.code in('starter','professional','enterprise') and (select count(*) from jsonb_object_keys(p.feature_flags))=27 and p.feature_flags->>'id_cards'='true' and p.feature_flags->>'staff_id_cards'='true' and p.feature_flags->>'timetable'='true' and p.feature_flags->>'school_prospectus'='true' and p.feature_flags->>'advanced_analytics'='false' and p.feature_flags->>'integrations'='false'"

check starter_finance_exports "select feature_flags->>'finance_exports'='false' from platform.license_plans where code='starter'"
check professional_finance_exports "select feature_flags->>'finance_exports'='true' from platform.license_plans where code='professional'"
check professional_financial_holds "select feature_flags->>'financial_holds'='true' from platform.license_plans where code='professional'"
check enterprise_payroll "select feature_flags->>'payroll'='true' from platform.license_plans where code='enterprise'"
check enterprise_payroll_statutory "select feature_flags->>'payroll_statutory'='true' from platform.license_plans where code='enterprise'"
check enterprise_custom_branding "select feature_flags->>'custom_branding'='true' from platform.license_plans where code='enterprise'"
check school_logo_exec "select has_function_privilege('edusentia_worker_runtime','public.set_school_logo_reference(text)','EXECUTE')"
check class_generator_exists "select to_regprocedure('public.generate_class_student_identifier(uuid)') is not null"
check admission_sequence_exists "select to_regclass('public.student_admission_sequences') is not null"
check reset_audit_exec "select has_function_privilege('edusentia_worker_runtime','public.reset_audit_log(text)','EXECUTE')"
check prepare_upload_exec "select has_function_privilege('edusentia_worker_runtime','public.prepare_object_upload(text,text,text,bigint)','EXECUTE')"
check get_upload_exec "select has_function_privilege('edusentia_worker_runtime','public.get_object_upload_metadata(text,text)','EXECUTE')"
check transition_upload_exec "select has_function_privilege('edusentia_worker_runtime','public.transition_object_upload(uuid,text,text)','EXECUTE')"
check school_logo_context "select position('v_tenant_id' in pg_get_functiondef('public.set_school_logo_reference(text)'::regprocedure))>0"
check report_template_path "select position('report-card-templates' in pg_get_functiondef('public.save_report_card_template(text,text,text,text,bigint,text)'::regprocedure))>0"
check report_template_constraint "select pg_get_constraintdef(oid) like '%report-card-templates%' from pg_constraint where conrelid='public.report_card_templates'::regclass and conname='report_card_templates_path_chk'"
check shs_console_exec "select has_function_privilege('edusentia_worker_runtime','public.neon_shs_academic_console()','EXECUTE')"
check shs_insert_exec "select has_function_privilege('edusentia_worker_runtime','public.neon_shs_academic_insert(text,jsonb)','EXECUTE')"
check shs_remove_exec "select has_function_privilege('edusentia_worker_runtime','public.neon_shs_academic_remove(text,uuid)','EXECUTE')"
check teacher_auth_exec "select has_function_privilege('edusentia_worker_runtime','public.neon_authorize_teacher_photo_upload(uuid)','EXECUTE')"
check teacher_desc_exec "select has_function_privilege('edusentia_worker_runtime','public.neon_teacher_photo_descriptor(uuid)','EXECUTE')"
check teacher_auth_context "select position('app.current_user_id()' in pg_get_functiondef('public.neon_authorize_teacher_photo_upload(uuid)'::regprocedure))>0"
check teacher_auth_no_auth_uid "select position('auth.uid()' in pg_get_functiondef('public.neon_authorize_teacher_photo_upload(uuid)'::regprocedure))=0"
check teacher_desc_context "select position('app.current_user_id()' in pg_get_functiondef('public.neon_teacher_photo_descriptor(uuid)'::regprocedure))>0"
check teacher_desc_no_auth_uid "select position('auth.uid()' in pg_get_functiondef('public.neon_teacher_photo_descriptor(uuid)'::regprocedure))=0"
check teacher_set_context "select position('app.current_user_id()' in pg_get_functiondef('public.set_teacher_photo(uuid,text,timestamptz)'::regprocedure))>0"
check teacher_set_storage "select position('storage.object_metadata' in pg_get_functiondef('public.set_teacher_photo(uuid,text,timestamptz)'::regprocedure))>0"

EXPECTED_FILE="$(mktemp)"
ACTUAL_FILE="$(mktemp)"
MISSING_FILE="$(mktemp)"
trap 'rm -f "$EXPECTED_FILE" "$ACTUAL_FILE" "$MISSING_FILE"' EXIT
node --input-type=module -e '
  import fs from "node:fs";
  const x=JSON.parse(fs.readFileSync("reference/future-tenant-rpc-surface.json","utf8"));
  process.stdout.write([...x.operations].sort().join("\n")+"\n");
' > "$EXPECTED_FILE"
psql "$TENANT_DATABASE_URL" -Atc "
  select distinct p.proname
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and has_function_privilege('edusentia_worker_runtime',p.oid,'EXECUTE')
  order by p.proname
" > "$ACTUAL_FILE"
comm -23 "$EXPECTED_FILE" "$ACTUAL_FILE" > "$MISSING_FILE"
echo "missing_rpc_count=$(wc -l < "$MISSING_FILE" | tr -d ' ')"
if [ -s "$MISSING_FILE" ]; then
  echo "missing_rpcs:"
  cat "$MISSING_FILE"
fi

echo "functional_reuse_test=starting"
psql "$TENANT_DATABASE_URL" -v ON_ERROR_STOP=1 -At <<'SQL'
begin;
select app.set_request_context(
  (select id from app.tenants order by created_at limit 1),
  (select id from public.profiles where public.current_app_role_for(role)='system_admin' and active order by created_at limit 1),
  'system_admin',
  2::smallint
);
do $reuse$
declare
  y uuid;
  c uuid;
  first_saved jsonb;
  second_saved jsonb;
  first_id uuid;
  first_no text;
  second_no text;
begin
  select id into y
  from public.academic_years
  where deleted_at is null
  order by is_active desc,start_date desc nulls last,created_at
  limit 1;

  select id into c
  from public.classes
  where deleted_at is null and active
  order by level_order,name
  limit 1;

  if y is null or c is null then
    raise exception 'No academic year/class available for functional reuse diagnostic';
  end if;

  first_saved:=public.save_student(jsonb_build_object(
    'student',jsonb_build_object(
      'first_name','ReuseDiagnosticOne',
      'last_name','Temporary',
      'gender','Other',
      'status','active'
    ),
    'enrollment',jsonb_build_object(
      'academic_year_id',y,
      'class_id',c,
      'active',true
    ),
    'guardian',jsonb_build_object(),
    'reason','Transactional admission reuse diagnostic'
  ));
  first_id:=nullif(first_saved#>>'{student,id}','')::uuid;
  first_no:=first_saved#>>'{student,admission_no}';

  if first_id is null or coalesce(first_no,'')='' then
    raise exception 'First diagnostic student was not created';
  end if;

  if not public.archive_student(first_id,'Transactional admission reuse diagnostic') then
    raise exception 'First diagnostic student was not archived';
  end if;

  second_saved:=public.save_student(jsonb_build_object(
    'student',jsonb_build_object(
      'first_name','ReuseDiagnosticTwo',
      'last_name','Temporary',
      'gender','Other',
      'status','active'
    ),
    'enrollment',jsonb_build_object(
      'academic_year_id',y,
      'class_id',c,
      'active',true
    ),
    'guardian',jsonb_build_object(),
    'reason','Transactional admission reuse diagnostic replacement'
  ));
  second_no:=second_saved#>>'{student,admission_no}';

  if second_no is distinct from first_no then
    raise exception 'Released admission number was not reused: first %, second %',first_no,second_no;
  end if;

  raise notice 'FUNCTIONAL_REUSE_OK|%|%',first_no,second_no;
end
$reuse$;
rollback;
SQL
echo "functional_reuse_test=passed"

echo "Admission reuse diagnostic complete."
