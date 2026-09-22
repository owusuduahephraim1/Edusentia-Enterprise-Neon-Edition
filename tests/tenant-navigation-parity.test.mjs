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
  assert.match(app,/item\.permission&&!permissionEnabled\(item\.permission\)/);
  assert.match(app,/item\.feature&&!featureEnabled\(item\.feature\)/);
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
  assert.match(routes,/manage_academics:Boolean\(rawPermissions\["academics\.write"\]\)/);
  assert.match(routes,/manage_teachers:Boolean\(rawPermissions\["staff\.write"\]\)/);
  assert.match(routes,/manage_headteachers:Boolean\(rawPermissions\["admin\.tenant"\]\)/);
  assert.match(routes,/manage_users:Boolean\(rawPermissions\["admin\.users"\]\)/);
  assert.match(routes,/view_audit:Boolean\(rawPermissions\["admin\.tenant"\]\)/);
});


test("System Administrator sidebar excludes extension-only HR and Finance entries",()=>{
  const hr=read("frontend/tenant-hr-staff-v1.js");
  const finance=read("frontend/finance-core.js");
  assert.match(hr,/if\(S\.role!=="principal"\)/);
  assert.doesNotMatch(finance,/S\.role==="system_admin"&&hasFeature\("finance_fees"\)/);
});
