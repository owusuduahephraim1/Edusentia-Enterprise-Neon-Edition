import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("Senior High blueprint UI flow is inherited without a Supabase runtime",()=>{
  const ui=read("frontend/tenant-institution-academics-v1.js");
  const html=read("frontend/index.html");
  for(const label of [
    "SHS Programmes",
    "SHS Programme Structure",
    "Programme Levels",
    "Programme Subjects",
    "Student Programme Assignment",
    "Add programme",
    "Add level",
    "Assign subject",
    "Assign student"
  ]) assert.ok(ui.includes(label),label);
  assert.match(ui,/shsAcademicConsole/);
  assert.match(ui,/shsAcademicInsert/);
  assert.match(ui,/shsAcademicRemove/);
  assert.doesNotMatch(ui,/supabase/i);
  assert.match(html,/tenant-institution-academics-v1\.js/);
  assert.doesNotThrow(()=>new Function(ui));
});

test("Senior High operations are exposed only through authenticated Neon Worker routes",()=>{
  const routes=read("worker/src/routes.ts");
  const api=read("frontend/api-client.js");
  assert.match(routes,/p==="\/api\/academics\/shs"/);
  assert.match(routes,/p==="\/api\/academics\/shs\/insert"/);
  assert.match(routes,/p==="\/api\/academics\/shs\/remove"/);
  assert.match(routes,/requireRole\(ctx,\["system_admin","principal"\]\)/);
  assert.match(routes,/A verified MFA session is required to remove Senior High academic records/);
  assert.match(routes,/public\.neon_shs_academic_console\(\)/);
  assert.match(routes,/public\.neon_shs_academic_insert/);
  assert.match(routes,/public\.neon_shs_academic_remove/);
  assert.match(api,/shsAcademicConsole/);
  assert.match(api,/shsAcademicInsert/);
  assert.match(api,/shsAcademicRemove/);
});

test("Senior High Neon functions preserve blueprint institution, role, licence and entity rules",()=>{
  const sql=read("database/reference-compat/0054_shs_operational_parity.sql");
  assert.match(sql,/current_app_role\(\)::text not in \('system_admin','principal'\)/);
  assert.match(sql,/license_read_allowed\(\)/);
  assert.match(sql,/license_write_allowed\(\)/);
  assert.match(sql,/require_license_feature\('core_records'\)/);
  assert.match(sql,/institution_type/);
  assert.match(sql,/senior_high/);
  for(const table of ["academic_programmes","academic_levels","shs_programme_subjects","student_programme_enrollments"])assert.ok(sql.includes("public."+table),table);
  assert.match(sql,/grant execute on function public\.neon_shs_academic_console\(\) to edusentia_worker_runtime/);
  assert.match(sql,/grant execute on function public\.neon_shs_academic_insert\(text,jsonb\) to edusentia_worker_runtime/);
  assert.match(sql,/grant execute on function public\.neon_shs_academic_remove\(text,uuid\) to edusentia_worker_runtime/);
});

test("Senior High parity is installed for future and existing isolated tenants",()=>{
  const install=read("database/reference-compat/install-operational-parity.sh");
  const upgrade=read("scripts/update-isolated-operational-tenants.sh");
  assert.match(install,/0054_shs_operational_parity/);
  assert.match(upgrade,/0054_shs_operational_parity/);
  assert.match(upgrade,/migration_count\" = \"39/);
  assert.match(upgrade,/neon_shs_academic_console/);
  assert.match(upgrade,/neon_shs_academic_insert/);
  assert.match(upgrade,/neon_shs_academic_remove/);
});
