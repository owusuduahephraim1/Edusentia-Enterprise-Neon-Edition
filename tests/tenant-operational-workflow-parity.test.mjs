import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("live blueprint tenant enhancement chain is present and syntactically valid",()=>{
  const files=["tenant-r40-product-fixes.js","tenant-r40-v9-list-resilience.js","tenant-accountant-parent-follow-up-v1.js","tenant-accountant-parent-follow-up-v2.js","tenant-user-credential-actions-v2.js","tenant-user-credential-actions-v3.js","tenant-backup-r2-download-v1.js","tenant-backup-r2-download-core-r42-v18.js","tenant-teacher-subject-summary.js","tenant-teacher-subject-summary-v2.js"];
  for(const name of files)assert.doesNotThrow(()=>new Function(read("frontend/"+name)),name);
});

test("Neon loads live tenant workflow entry points",()=>{
  const html=read("frontend/index.html");
  assert.match(html,/assets\/vendor\/jszip-3\.10\.1\.min\.js/);
  assert.match(html,/tenant-r40-product-fixes\.js/);
  assert.match(html,/tenant-teacher-subject-summary\.js/);
});

test("Worker compatibility supports protected backup assurance flow",()=>{
  const compat=read("frontend/neon-supabase-compat.js");
  const api=read("frontend/api-client.js");
  assert.match(compat,/name==="backup-download-gateway"/);
  assert.match(compat,/backupDownloadGateway/);
  assert.match(compat,/getAuthenticatorAssuranceLevel/);
  assert.match(api,/backupDownloadGateway:/);
});

test("finance workflow preserves upgrade-plan gates",()=>{
  const product=read("frontend/tenant-r40-product-fixes.js");
  assert.match(product,/flags\.financial_holds===true/);
  assert.match(product,/flags\.payroll===true/);
  assert.match(product,/data-finance-tab="holds"/);
  assert.match(product,/data-finance-tab="payroll"/);
  assert.match(product,/Fee Class Range/);
  assert.match(product,/EdusentiaShell\?\.state\?\.session/);
  assert.match(product,/setTimeout\(\(\)=>void loadFinance\(\),1000\)/);
});

test("accounts office follow-up and credential workflows are inherited",()=>{
  const follow=read("frontend/tenant-accountant-parent-follow-up-v1.js");
  const follow2=read("frontend/tenant-accountant-parent-follow-up-v2.js");
  const credentials=read("frontend/tenant-user-credential-actions-v3.js");
  for(const rpc of ["finance_log_guardian_contact","finance_guardian_follow_up","finance_guardian_contact_history"])assert.ok(follow.includes(rpc),rpc);
  assert.ok(follow2.includes("finance_clear_guardian_contact_history"));
  assert.ok(credentials.includes("list_profiles_with_access"));
  assert.ok(credentials.includes("admin-user-management"));
});

test("backup and teacher refinements are inherited",()=>{
  const backup=read("frontend/tenant-backup-r2-download-core-r42-v18.js");
  const summary=read("frontend/tenant-teacher-subject-summary-v2.js");
  assert.match(backup,/backup-download-gateway/);
  assert.match(backup,/Multi-factor authentication is required/);
  assert.match(backup,/Cloudflare R2/);
  assert.match(summary,/subject/i);
});

test("PWA caches full tenant workflow parity",()=>{
  const sw=read("frontend/service-worker.js");
  assert.match(sw,/edusentia-neon-v35/);
  for(const asset of ["assets/vendor/jszip-3.10.1.min.js","tenant-r40-product-fixes.js","tenant-r40-v9-list-resilience.js","tenant-accountant-parent-follow-up-v1.js","tenant-accountant-parent-follow-up-v2.js","tenant-user-credential-actions-v2.js","tenant-user-credential-actions-v3.js","tenant-backup-r2-download-v1.js","tenant-backup-r2-download-core-r42-v18.js","tenant-teacher-subject-summary.js","tenant-teacher-subject-summary-v2.js"])assert.ok(sw.includes(asset),asset);
});
