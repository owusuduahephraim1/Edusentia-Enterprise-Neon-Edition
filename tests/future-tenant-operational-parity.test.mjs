import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("future tenant operational assets are Worker-backed and loaded by the Neon shell",()=>{
  const html=read("frontend/index.html");
  const required=[
    "neon-supabase-compat.js","finance-core.js","finance-payroll.js","finance-accounts.js",
    "finance-professional-receipts.js","finance-portals.js","tenant-accountant-dashboard-v1.js",
    "tenant-accountant-student-roles-v2.js","tenant-accountant-student-submit-v3.js",
    "tenant-hr-staff-v1.js","tenant-student-services-v1.js","tenant-student-services-actions-v1.js",
    "tenant-student-portal-v1.js","tenant-institution-academics-loader-v1.js"
  ];
  for(const file of required)assert.match(html,new RegExp(file.replaceAll(".","\\.")),file+" is not loaded");
  assert.match(html,/finance-enterprise\.css/);

  const productionFiles=[
    "frontend/neon-supabase-compat.js","frontend/finance-core.js","frontend/finance-accounts.js",
    "frontend/finance-payroll.js","frontend/finance-portals.js","frontend/finance-professional-receipts.js",
    "frontend/finance-invoices-v1.js","frontend/tenant-accountant-dashboard-v1.js",
    "frontend/tenant-accountant-student-roles-v2.js","frontend/tenant-accountant-student-submit-v3.js",
    "frontend/tenant-hr-staff-v1.js","frontend/tenant-student-services-v1.js",
    "frontend/tenant-student-services-actions-v1.js","frontend/tenant-student-portal-v1.js",
    "frontend/tenant-student-portal-v2.js","frontend/tenant-student-portal-v2-refinements.js",
    "frontend/tenant-institution-academics-loader-v1.js","frontend/tenant-institution-academics-v1.js"
  ];
  const forbidden=/supabase\.co|@supabase\/|createClient\s*\(|supabaseUrl|supabaseAnonKey|service_role|functions\/v1/i;
  for(const file of productionFiles){
    const source=read(file);
    assert.doesNotMatch(source,forbidden,file+" reintroduced a legacy browser runtime dependency");
    assert.doesNotThrow(()=>new Function(source),file+" must parse as browser JavaScript");
  }
  const shim=read("frontend/neon-supabase-compat.js");
  assert.match(shim,/EdusentiaCompatClient/);
  assert.match(shim,/certifiedRpc/);
  assert.match(shim,/directoryUserManagement/);
});

test("tenant template installs deep blueprint module compatibility additively",()=>{
  const template=read("database/tenant-template/install.sh");
  const installer=read("database/reference-compat/install-operational-parity.sh");
  const grants=read("database/reference-compat/0049z_operational_runtime_grants.sql");
  assert.match(template,/install-operational-parity\.sh/);
  assert.match(template,/count\(distinct p\.proname\)[\s\S]*258/);
  for(const migration of [
    "0049a_operational_finance_reference.sql","0049v_live_plan_feature_parity.sql","0049w_school_identity_logo_parity.sql","0068_commercial_plan_tiering.sql","0049x_class_scoped_student_admission_numbers.sql","0049y_audit_permanent_reset.sql","hr_staff_management_v1.sql",
    "student_services_foundation_v1.sql","admissions_applicant_management_v1.sql",
    "discipline_welfare_management_v1.sql","health_clinic_management_v1.sql",
    "communications_messaging_centre_v1.sql","hostel_boarding_management_v1.sql",
    "alumni_graduate_management_v1.sql","student_portal_v1.sql"
  ]) assert.match(installer,new RegExp(migration.replaceAll(".","\\.")),migration+" is not installed");
  assert.match(grants,/edusentia_worker_runtime/);
  assert.match(grants,/student_services_%/);
  assert.match(grants,/finance_%/);
  assert.match(installer,/reconcile_once_recorded "0049v_live_plan_feature_parity"/);
  assert.match(installer,/reconcile_once_recorded "0049w_school_identity_logo_parity"/);
  assert.match(installer,/reconcile_once_recorded "0068_commercial_plan_tiering"/);
  assert.doesNotMatch(installer,/run_once "0049w_school_identity_logo_parity"/);
  assert.match(installer,/reconcile_once_recorded "0049x_class_scoped_student_admission_numbers"/);
  assert.doesNotMatch(installer,/run_once "0049x_class_scoped_student_admission_numbers"/);
  assert.match(installer,/reconcile_once_recorded "0049y_audit_permanent_reset"/);
  assert.doesNotMatch(installer,/run_once "0049y_audit_permanent_reset"/);
  const auditReset=read("database/reference-compat/0049y_audit_permanent_reset.sql");
  assert.match(auditReset,/RESET ACTIVE AUDIT/);
  assert.match(auditReset,/DELETE ALL AUDIT ARCHIVES/);
  assert.match(auditReset,/RESET ALL AUDIT HISTORY/);
  assert.match(auditReset,/Only the System Administrator can permanently reset audit history/);
  assert.match(auditReset,/require_sensitive_access/);
  const admissionParity=read("database/reference-compat/0049x_class_scoped_student_admission_numbers.sql");
  assert.match(admissionParity,/NIS000001-STU-BS3001/);
  assert.match(admissionParity,/generate_class_student_identifier/);
  assert.match(admissionParity,/student_admission_sequences/);
  assert.match(admissionParity,/order by lower\(coalesce\(value->>'last_name'/);
  const logoParity=read("database/reference-compat/0049w_school_identity_logo_parity.sql");
  assert.match(logoParity,/create or replace function public\.set_school_logo_reference/);
  assert.match(logoParity,/school-branding/);
  assert.match(logoParity,/grant execute on function public\.set_school_logo_reference\(text\) to edusentia_worker_runtime/);
  assert.match(logoParity,/existing_owner<>current_user/);
  assert.doesNotMatch(logoParity,/owner to edusentia_provisioner/);
  assert.doesNotMatch(logoParity,/set role edusentia_provisioner/);
  assert.doesNotMatch(installer,/run_once "0049v_live_plan_feature_parity"/);
  assert.equal(installer.includes("\\nrun_once"),false,"installer must not contain a literal backslash-n escape between migration calls");
  assert.equal(template.includes("\\ntest"),false,"tenant template must not contain a literal backslash-n escape between validation checks");
  const upgrader=read("scripts/update-isolated-operational-tenants.sh");
  assert.match(upgrader,/tenant_commercial_plan_tiering_v2_verified/);
  assert.match(upgrader,/0068_commercial_plan_tiering/);
  assert.match(upgrader,/feature_count',27/);
  assert.match(upgrader,/rpc_count',258/);
});

test("reference module navigation remains feature and role scoped",()=>{
  const app=read("frontend/app.js");
  const finance=read("frontend/finance-core.js");
  const hr=read("frontend/tenant-hr-staff-v1.js");
  const services=read("frontend/tenant-student-services-v1.js");
  assert.match(app,/featureEnabled/);
  assert.match(app,/permissionEnabled/);
  assert.match(finance,/hasFeature\("finance_fees"\)/);
  assert.match(finance,/hasFeature\("payroll"\)/);
  assert.match(hr,/\["system_admin","principal"\]\.includes\(S\.role\)/);
  assert.match(app,/id:"staff",label:"Staff & HR"[\s\S]*roles:\["system_admin","principal"\]/);
  assert.match(services,/student_services_session/);
  assert.match(services,/cap\("admissions_read"\)/);
  assert.match(services,/cap\("health_summary"\)/);
});
