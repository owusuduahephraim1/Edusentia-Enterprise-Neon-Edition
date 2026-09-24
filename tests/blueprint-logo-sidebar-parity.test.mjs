import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("Neon official school logo settings preserve blueprint structure and controls",()=>{
  const ui=read("frontend/parity-enterprise-workspaces.js");
  const css=read("frontend/style.css");
  for(const token of [
    "school-logo-settings-grid","schoolLogoSettingsPreview",
    "Used automatically on official school documents",
    "Upload / Change logo","Restore package logo","Refresh published report PDFs",
    "image/png,image/jpeg,image/webp","1024 × 1024 PNG",
    "at least 512 × 512 pixels","maximum 5 MB"
  ]) assert.ok(ui.includes(token),token);
  for(const selector of [
    ".school-logo-settings-grid",".school-logo-settings-preview",
    ".school-logo-settings-actions"
  ]) assert.ok(css.includes(selector),selector);
});

test("school logo authorization follows the blueprint active-profile role path",()=>{
  const sql=read("database/reference-compat/0049w_school_identity_logo_parity.sql");
  assert.match(sql,/if not public\.is_system_admin\(\) then/);
  assert.match(sql,/perform public\.require_sensitive_access\(\)/);
  assert.doesNotMatch(sql,/current_role\s+text:=app\.current_role\(\)/);
  assert.match(sql,/clean_logo='assets\/school-logo\.png'/);
  assert.match(sql,/v_tenant_id uuid:=app\.current_tenant_id\(\)/);
  assert.match(sql,/m\.tenant_id=v_tenant_id/);
  assert.doesNotMatch(sql,/m\.tenant_id=tenant_id/);
});

test("bootstrap projects the canonical saved school logo without direct table access",()=>{
  const routes=read("worker/src/routes.ts");
  assert.match(routes,/select public\.get_bootstrap_data\(\) result/);
  assert.match(routes,/certifiedBootstrap\?\.school\?\.logo_url/);
  assert.match(routes,/settings:\{\.\.\.\(tenantRow\.settings\|\|\{\}\),logo_url:canonicalLogo\}/);
  assert.doesNotMatch(routes,/select s\.logo_url from public\.school_settings s/);
  assert.match(routes,/assets\/school-logo\.png/);
});

test("tenant sidebar inherits blueprint alignment and hides native scrollbar tracks",()=>{
  const css=read("frontend/style.css");
  const html=read("frontend/index.html");
  assert.match(css,/\.sidebar\{position:sticky;top:0;height:100vh/);
  assert.match(css,/\.nav-list\{display:grid;gap:6px;margin-top:18px;overflow:auto/);
  assert.match(css,/#mainNav\.nav-list\{overflow-y:auto;overflow-x:hidden;scrollbar-width:none/);
  assert.match(css,/#mainNav\.nav-list::-webkit-scrollbar\{display:none;width:0;height:0\}/);
  assert.doesNotMatch(css,/overflow-x:auto!important/);
  assert.doesNotMatch(css,/#mainNav \.nav-item\{width:max-content/);
  assert.match(html,/data-school-logo src="assets\/school-logo\.png"/);
  assert.match(html,/id="brandSubtitle">Academic Service</);
});

test("PWA carries the canonical blueprint school logo asset",()=>{
  const sw=read("frontend/service-worker.js");
  assert.match(sw,/edusentia-neon-v32/);
  assert.match(sw,/assets\/school-logo\.png/);
  assert.ok(fs.statSync("frontend/assets/school-logo.png").size>10000);
});
