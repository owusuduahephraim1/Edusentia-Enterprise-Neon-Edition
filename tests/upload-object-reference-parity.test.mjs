import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=(path)=>fs.readFileSync(new URL("../"+path,import.meta.url),"utf8");

test("shared uploads use canonical tenant-scoped R2 storage",()=>{
  const api=read("frontend/api-client.js");
  const routes=read("worker/src/routes.ts");
  assert.ok(api.includes("function uploadContentType(file)"));
  assert.ok(routes.includes("tenants/${ctx.tenantId}/${kind}/"));
  assert.ok(routes.includes("object_storage_write_failed"));
  assert.ok(routes.includes("upload_finalize_failed"));
});

test("upload-backed certified functions accept protected R2 scopes",()=>{
  const sql=read("database/reference-compat/0049w_school_identity_logo_parity.sql");
  for(const scope of ["school-branding","staff-photos","principal-signatures","student-photos","report-card-templates","certificate-templates"]){
    assert.ok(sql.includes(scope),scope+" scope must be certified");
  }
  assert.ok(sql.includes("storage.object_metadata"));
  assert.ok(!sql.includes("split_part(clean_path,'/',1)<>target_teacher_id::text"));
  assert.ok(!sql.includes("target_storage_path not like target_range_key||'/%'"));
});

test("school website accepts a typed address and normalizes missing scheme",()=>{
  const ui=read("frontend/parity-enterprise-workspaces.js");
  const routes=read("worker/src/routes.ts");
  assert.ok(ui.includes('field("website","Website",settings.website,"text"'));
  assert.ok(ui.includes('inputmode="url"'));
  assert.ok(ui.includes('"https://"+raw'));
  assert.ok(routes.includes("website:webAddress(b.website,500)"));
  assert.ok(routes.includes("verification_base_url:webAddress(b.verification_base_url,500)"));
  assert.ok(ui.includes('field("verification_base_url","Verification base URL",settings.verification_base_url,"text"'));
  assert.ok(!ui.includes('id="schoolLogoFile" type="file" accept="image/png" required'));
});

test("long tenant listings are compact and vertically scrollable",()=>{
  const css=read("frontend/style.css");
  assert.ok(css.includes("v10.2 compact bounded tenant lists"));
  assert.ok(css.includes("#content .grid.two{align-items:start}"));
  assert.ok(css.includes("max-height:clamp(220px,40vh,380px)"));
  assert.ok(css.includes("overflow-y:auto"));
});

test("explicit database validation failures are not rendered as generic internal errors",()=>{
  const worker=read("worker/src/index.ts");
  assert.ok(worker.includes('"P0001":422'));
  assert.ok(worker.includes('"42501":403'));
  assert.ok(worker.includes('"40001":409'));
});


test("privileged administrators always require verified MFA for destructive operations",()=>{
  const auth=read("worker/src/auth.ts");
  const routes=read("worker/src/routes.ts");
  assert.ok(auth.includes("privilegedRoleRequiresMfa"));
  assert.ok(auth.includes("if(!row.mfa_required)"));
  assert.ok(auth.includes("if(!privilegedRoleRequiresMfa(row.role))"));
  assert.ok(auth.includes("privilegedRoleRequiresMfa(context.role)&&Number(session.assurance_level)<2"));
  assert.ok(routes.includes("destructiveMutation"));
  assert.ok(routes.includes("mutation_not_applied"));
});

test("core archive UIs reject silent false mutation results",()=>{
  for(const path of ["frontend/parity-academics.js","frontend/parity-teachers.js","frontend/parity-students.js","frontend/parity-principal.js"]){
    const source=read(path);
    assert.ok(source.includes("The remove operation did not complete."),path);
  }
});
