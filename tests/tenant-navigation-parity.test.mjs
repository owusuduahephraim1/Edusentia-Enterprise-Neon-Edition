import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("tenant shell follows reference role, permission and feature navigation contract",()=>{
  const app=read("frontend/app.js");
  assert.match(app,/const ROLE_NAV_IDS=Object\.freeze\(/);
  assert.match(app,/system_admin:\["dashboard","operations","students","student_services","history","teachers","headteachers","academics","timetable","prospectus","delegations","reports","certificates","id_cards","insights","users","compliance","audit","backup_restore","plan_upgrade","license_capacity","notifications","settings"\]/);
  assert.match(app,/permissionEnabled\(code\)/);
  assert.match(app,/featureEnabled\(code\)/);
  assert.match(app,/item\.permission&&!permissionEnabled\(item\.permission\)&&r!=="system_admin"/);
  assert.match(app,/item\.feature&&!featureEnabled\(item\.feature\)&&r!=="system_admin"/);
  assert.match(app,/Plan upgrade required/);
  assert.match(app,/planUpgradeRequired/);
  assert.match(app,/LEGACY_LICENSE_FEATURE_FALLBACKS/);
  assert.match(app,/id_cards:"core_records"/);
  assert.match(app,/timetable:"core_records"/);
  assert.match(app,/school_prospectus:"core_records"/);
});

test("bootstrap returns effective plan features and role permissions",()=>{
  const routes=read("worker/src/routes.ts");
  assert.match(routes,/from app\.tenant_licenses tl/);
  assert.match(routes,/left join platform\.license_plans lp/);
  assert.match(routes,/coalesce\(lp\.feature_flags,'\{\}'::jsonb\)\|\|coalesce\(tl\.feature_overrides,'\{\}'::jsonb\) feature_flags/);
  assert.match(routes,/from app\.role_permissions where role=\$\{ctx\.role\}/);
  assert.match(routes,/const rawPermissions=\{\.\.\.\(\(permissionRows\[0\] as any\)\?\.permissions\|\|\{\}\)\}/);
  assert.match(routes,/permissions,/);
  assert.match(routes,/license,/);
});

test("core registered views carry reference blueprint gating metadata",()=>{
  const files=[
    "frontend/app.js","frontend/parity-students.js","frontend/parity-teachers.js","frontend/parity-principal.js",
    "frontend/parity-timetable.js","frontend/parity-reports.js","frontend/parity-operations.js",
    "frontend/parity-audit-security-finance.js","frontend/parity-enterprise-workspaces.js"
  ].map(read).join("\n");
  for(const feature of ["attendance","academic_history","timetable","school_prospectus","report_cards","certificates","id_cards","analytics","notifications","governance","finance_fees"]){
    assert.match(files,new RegExp(`feature:["']${feature}["']`),feature+" feature gate missing");
  }
  for(const permission of ["manage_teachers","manage_headteachers","manage_users","view_audit"]){
    assert.match(files,new RegExp(`permission:["']${permission}["']`),permission+" permission gate missing");
  }
  assert.match(files,/id:"headteachers",label:"Principals"/);
  assert.match(files,/id:"reports",label:"Report Cards"/);
  assert.match(files,/id:"compliance",label:"Privacy and Security"/);
});


test("legacy blueprint modules receive unwrapped Worker RPC results",()=>{
  const compat=read("frontend/neon-supabase-compat.js");
  assert.match(compat,/response\?\.result\?\?response/);
  const routes=read("worker/src/routes.ts");
  assert.match(routes,/const isSystemAdmin=ctx\.role==="system_admin"/);
  assert.match(routes,/manage_academics:isSystemAdmin\|\|Boolean\(rawPermissions\["academics\.write"\]\)/);
  assert.match(routes,/manage_teachers:isSystemAdmin\|\|Boolean\(rawPermissions\["staff\.write"\]\)/);
  assert.match(routes,/manage_headteachers:isSystemAdmin\|\|Boolean\(rawPermissions\["admin\.tenant"\]\)/);
  assert.match(routes,/manage_users:isSystemAdmin\|\|Boolean\(rawPermissions\["admin\.users"\]\)/);
  assert.match(routes,/view_audit:isSystemAdmin\|\|Boolean\(rawPermissions\["admin\.tenant"\]\)/);
});


test("System Administrator sidebar excludes extension-only HR and Finance entries",()=>{
  const hr=read("frontend/tenant-hr-staff-v1.js");
  const finance=read("frontend/finance-core.js");
  const accountantRoles=read("frontend/tenant-accountant-student-roles-v2.js");
  assert.match(hr,/if\(S\.role!=="principal"\)/);
  assert.doesNotMatch(finance,/S\.role==="system_admin"&&hasFeature\("finance_fees"\)/);
  assert.match(accountantRoles,/currentRole\(\) === "system_admin"[\s\S]*existing\?\.remove\(\)[\s\S]*setDirectoryActive\(false\)/);
});


test("System Administrator operational workspaces preserve blueprint UI actions",()=>{
  const shell=read("frontend/app.js");
  const operations=read("frontend/parity-operations.js");
  const students=read("frontend/parity-students.js");
  const academics=read("frontend/parity-academics.js");
  const reports=read("frontend/parity-reports.js");
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  assert.match(shell,/System Administration Dashboard/);
  assert.match(operations,/Production Operations/);
  for(const label of ["Expected reports","Academic period control","System health","Class report progress"])assert.ok(operations.includes(label),label);
  for(const label of ["Student Directory","Import CSV","Export CSV","Add student","data-student-view","data-student-edit","data-student-archive"])assert.ok(students.includes(label),label);
  for(const label of ["Academic Configuration","Academic Periods","Classes and Subjects","Assessment Schemes","Grading Scales","Class Promotion"])assert.ok(academics.includes(label),label);
  for(const label of ["Report Cards","Manage template","Export list","Bulk class PDFs","Publish class reports","New report"])assert.ok(reports.includes(label),label);
  for(const label of ["School Prospectus","Download complete prospectus","Copy year","Emergency Academic Delegation","Certificates and Awards","Templates and settings","ID Card Management","Download printable A4","Users and Access","Licence and Capacity","System Settings","Report Card Templates by Class Range"])assert.ok(enterprise.includes(label),label);
  assert.match(enterprise,/save_school_prospectus_section/);
  assert.match(enterprise,/save_school_prospectus_item/);
  assert.match(enterprise,/save_certificate_template/);
  assert.match(enterprise,/replace_student_id_card/);
  assert.match(enterprise,/updateSchoolSettings/);
});


test("Users and Access preserves blueprint directory-linked account creation",()=>{
  const ui=read("frontend/parity-enterprise-workspaces.js");
  const api=read("frontend/api-client.js");
  const routes=read("worker/src/routes.ts");
  for(const label of ["Parent / Guardian record","Student record","Accounts Office Staff record","Credentials"])assert.ok(ui.includes(label),label);
  assert.match(ui,/directoryUserManagement/);
  assert.match(ui,/guardian_record_id/);
  assert.match(ui,/student_id/);
  assert.match(ui,/staff_record_id/);
  assert.match(api,/guardianAccountRecords:\(\)=>request\("\/api\/admin\/guardian-account-records"\)/);
  assert.match(routes,/p==="\/api\/admin\/guardian-account-records"/);
  assert.match(routes,/public\.neon_guardian_account_records\(\)/);
  assert.doesNotMatch(routes.split('p==="\/api\/admin\/guardian-account-records"')[1]?.split('p==="\/api\/settings\/school"')[0]||"",/public\.students/);
});


test("Starter System Administrator enterprise navigation registrar is syntactically valid and complete",()=>{
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  assert.doesNotThrow(()=>new Function(enterprise));
  for(const id of [
    "history","prospectus","delegations","certificates","id_cards","insights",
    "users","compliance","backup_restore","plan_upgrade","license_capacity","settings"
  ]){
    assert.match(enterprise,new RegExp(`registerView\\(\\{id:["']${id}["']`),id+" registration missing");
  }
});

test("tenant shell does not render literal newline escape text above the workspace",()=>{
  const html=read("frontend/index.html");
  assert.doesNotMatch(html,/<head>\\\\n/);
});

test("PWA shell carries every navigation parity registrar",()=>{
  const sw=read("frontend/service-worker.js");
  assert.match(sw,/edusentia-neon-v25/);
  for(const asset of [
    "parity-common.js","parity-academics.js","parity-students.js","parity-teachers.js",
    "parity-principal.js","parity-timetable.js","parity-reports.js",
    "parity-audit-security-finance.js","parity-operations.js","parity-enterprise-workspaces.js"
  ]) assert.ok(sw.includes(asset),asset);
});
