import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("Principal photograph writes use certified relative paths over tenant staff-photo R2 keys",()=>{
  const sql=read("database/reference-compat/0060_principal_photo_r2_contract.sql");
  for(const marker of [
    "app.current_user_id()",
    "staff-photos/",
    "storage.object_metadata",
    "public.neon_authorize_headteacher_photo_upload",
    "public.neon_headteacher_photo_descriptor",
    "public.set_headteacher_photo"
  ]) assert.ok(sql.includes(marker),marker);
  assert.match(sql,/m\.status='active'/);
  assert.match(sql,/lower\(m\.content_type\) like 'image\/%'/);
  assert.match(sql,/v_keep_legacy_full_key/);
});

test("Principal photo upload and protected download are owner scoped",()=>{
  const routes=read("worker/src/routes.ts");
  const api=read("frontend/api-client.js");
  assert.match(routes,/kind==="principal-photos"/);
  assert.match(routes,/neon_authorize_headteacher_photo_upload/);
  assert.match(routes,/storageKind="staff-photos"/);
  assert.match(routes,/p==="\/api\/files\/principal-photo"/);
  assert.match(routes,/neon_headteacher_photo_descriptor/);
  assert.match(api,/downloadPrincipalPhoto/);
});

test("Principal directory and editor hydrate protected photographs and preserve certified record data",()=>{
  const ui=read("frontend/parity-principal.js");
  assert.match(ui,/principalPhotoUrls=new Map/);
  assert.match(ui,/data-principal-photo/);
  assert.match(ui,/hydratePrincipalPhotos/);
  assert.match(ui,/downloadPrincipalPhoto/);
  assert.match(ui,/data\?\.principal\|\|data\?\.headteacher/);
  assert.match(ui,/name="profile_id"/);
  assert.match(ui,/uploadFile\(file,"principal-photos",\{subfolder:principalId\}\)/);
  assert.match(ui,/uploaded\.referencePath/);
  assert.match(ui,/principalPhotoPreview/);
});

test("Principal photo contract is reconciled for future and existing tenants",()=>{
  const install=read("database/reference-compat/install-operational-parity.sh");
  const upgrade=read("scripts/update-isolated-operational-tenants.sh");
  const template=read("database/tenant-template/install.sh");
  assert.match(install,/reconcile_once_recorded "0060_principal_photo_r2_contract"/);
  assert.match(upgrade,/0060_principal_photo_r2_contract/);
  assert.match(upgrade,/migration_count" = "36/);
  assert.match(template,/principal_photo_contract_ok/);
});
