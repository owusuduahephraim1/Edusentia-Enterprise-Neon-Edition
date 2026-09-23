import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("student photograph writes use certified relative paths over tenant R2 keys",()=>{
  const sql=read("database/reference-compat/0059_student_photo_r2_contract.sql");
  for(const marker of [
    "app.current_user_id()",
    "student-photos/",
    "storage.object_metadata",
    "split_part(clean_path",
    "public.neon_authorize_student_photo_upload",
    "public.neon_student_photo_descriptor",
    "public.set_student_photo"
  ]) assert.ok(sql.includes(marker),marker);
  assert.match(sql,/m\.status='active'/);
  assert.match(sql,/lower\(m\.content_type\) like 'image\/%'/);
});

test("student photo upload and private download are student scoped",()=>{
  const routes=read("worker/src/routes.ts");
  const api=read("frontend/api-client.js");
  assert.match(routes,/kind==="student-photos"/);
  assert.match(routes,/neon_authorize_student_photo_upload/);
  assert.match(routes,/A student identifier is required for student photographs/);
  assert.match(routes,/kind==="staff-photos"\|\|kind==="student-photos"/);
  assert.match(routes,/p==="\/api\/files\/student-photo"/);
  assert.match(routes,/neon_student_photo_descriptor/);
  assert.match(routes,/legacyPrefix=\`tenants\/\$\{ctx\.tenantId\}\/student-photos\//);
  assert.match(api,/downloadStudentPhoto/);
});

test("student directory, record and editor hydrate protected photographs",()=>{
  const ui=read("frontend/parity-students.js");
  assert.match(ui,/studentPhotoUrls=new Map/);
  assert.match(ui,/data-student-photo/);
  assert.match(ui,/hydrateStudentPhotos/);
  assert.match(ui,/downloadStudentPhoto/);
  assert.match(ui,/uploadFile\(file,"student-photos",\{subfolder:studentId\}\)/);
  assert.match(ui,/uploaded\.referencePath/);
  assert.match(ui,/studentPhotoPreview/);
});

test("student photo contract is reconciled for future and existing tenants",()=>{
  const install=read("database/reference-compat/install-operational-parity.sh");
  const upgrade=read("scripts/update-isolated-operational-tenants.sh");
  const template=read("database/tenant-template/install.sh");
  assert.match(install,/reconcile_once_recorded "0059_student_photo_r2_contract"/);
  assert.match(upgrade,/0059_student_photo_r2_contract/);
  assert.match(upgrade,/migration_count" = "37/);
  assert.match(template,/student_photo_contract_ok/);
});
