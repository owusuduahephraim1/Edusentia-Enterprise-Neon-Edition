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
});

test("tenant sidebar keeps blueprint fixed shell with explicit two-axis navigation scrolling",()=>{
  const css=read("frontend/style.css");
  const html=read("frontend/index.html");
  assert.match(css,/#sidebar\{overflow:hidden;height:100vh;height:100dvh;max-height:100dvh/);
  assert.match(css,/#mainNav\.nav-list\{[\s\S]*flex:1 1 auto;[\s\S]*min-height:0;[\s\S]*overflow-y:auto!important;[\s\S]*overflow-x:auto!important;/);
  assert.match(css,/scrollbar-gutter:stable both-edges/);
  assert.match(html,/data-school-logo src="assets\/school-logo\.png"/);
  assert.match(html,/id="brandSubtitle">Academic Service</);
});

test("PWA carries the canonical blueprint school logo asset",()=>{
  const sw=read("frontend/service-worker.js");
  assert.match(sw,/edusentia-neon-v15/);
  assert.match(sw,/assets\/school-logo\.png/);
  assert.ok(fs.statSync("frontend/assets/school-logo.png").size>10000);
});
