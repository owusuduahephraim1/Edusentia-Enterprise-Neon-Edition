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
    "0049a_operational_finance_reference.sql","0049v_live_plan_feature_parity.sql","hr_staff_management_v1.sql",
    "student_services_foundation_v1.sql","admissions_applicant_management_v1.sql",
    "discipline_welfare_management_v1.sql","health_clinic_management_v1.sql",
    "communications_messaging_centre_v1.sql","hostel_boarding_management_v1.sql",
    "alumni_graduate_management_v1.sql","student_portal_v1.sql"
  ]) assert.match(installer,new RegExp(migration.replaceAll(".","\\.")),migration+" is not installed");
  assert.match(grants,/edusentia_worker_runtime/);
  assert.match(grants,/student_services_%/);
  assert.match(grants,/finance_%/);
  assert.match(installer,/reconcile_once_recorded "0049v_live_plan_feature_parity"/);
  assert.doesNotMatch(installer,/run_once "0049v_live_plan_feature_parity"/);
  assert.equal(installer.includes("\\nrun_once"),false,"installer must not contain a literal backslash-n escape between migration calls");
  assert.equal(template.includes("\\ntest"),false,"tenant template must not contain a literal backslash-n escape between validation checks");
  const upgrader=read("scripts/update-isolated-operational-tenants.sh");
  assert.match(upgrader,/tenant_commercial_plan_parity_verified/);
  assert.match(upgrader,/0049v_live_plan_feature_parity/);
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
  assert.match(hr,/\["system_admin","principal"\]/);
  assert.match(services,/student_services_session/);
  assert.match(services,/cap\("admissions_read"\)/);
  assert.match(services,/cap\("health_summary"\)/);
});
