import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");
const active=[
  "finance-core.js","finance-payroll.js","finance-accounts.js","finance-professional-receipts.js","finance-portals.js","finance-invoices-v1.js",
  "tenant-accountant-dashboard-v1.js","tenant-accountant-student-roles-v2.js","tenant-accountant-student-submit-v3.js",
  "tenant-hr-staff-v1.js","tenant-student-services-v1.js","tenant-student-services-actions-v1.js",
  "tenant-student-portal-v1.js","tenant-student-portal-v2.js","tenant-student-portal-v2-refinements.js",
  "tenant-r40-product-fixes.js","tenant-r40-v9-list-resilience.js",
  "tenant-accountant-parent-follow-up-v1.js","tenant-accountant-parent-follow-up-v2.js",
  "tenant-user-credential-actions-v2.js","tenant-user-credential-actions-v3.js",
  "tenant-backup-r2-download-v1.js","tenant-backup-r2-download-core-r42-v18.js",
  "tenant-teacher-subject-summary.js","tenant-teacher-subject-summary-v2.js"
];

function collectRpc(source){
  const names=new Set();
  for(const re of [/\brpc\(\s*["'`]([^"'`]+)["'`]/g,/\.rpc\(\s*["'`]([^"'`]+)["'`]/g]){
    for(const match of source.matchAll(re))names.add(match[1]);
  }
  return names;
}

test("every active inherited operational RPC is reachable through Neon",()=>{
  const manifest=JSON.parse(read("reference/future-tenant-rpc-surface.json"));
  const certified=new Set(manifest.operations||[]);
  const dedicated=new Set([
    "finance_log_guardian_contact",
    "finance_guardian_follow_up",
    "finance_guardian_contact_history",
    "finance_clear_guardian_contact_history",
  ]);
  const names=new Set();
  for(const name of active){
    for(const rpc of collectRpc(read("frontend/"+name)))names.add(rpc);
  }
  const missing=[...names].filter(name=>!certified.has(name)&&!dedicated.has(name)).sort();
  assert.deepEqual(missing,[]);
});

test("guardian follow-up exceptions to the fixed 258 RPC manifest use a narrow MFA-gated Worker bridge",()=>{
  const manifest=JSON.parse(read("reference/future-tenant-rpc-surface.json"));
  const compat=read("frontend/neon-supabase-compat.js");
  const api=read("frontend/api-client.js");
  const routes=read("worker/src/routes.ts");
  assert.equal(manifest.rpcCount,258);
  const operations=[
    "finance_log_guardian_contact",
    "finance_guardian_follow_up",
    "finance_guardian_contact_history",
    "finance_clear_guardian_contact_history",
  ];
  for(const op of operations){
    assert.ok(!manifest.operations.includes(op),op+" must remain outside the fixed certified manifest");
    assert.ok(compat.includes(op),op+" missing from compatibility bridge");
    assert.ok(routes.includes(op),op+" missing from Worker bridge");
  }
  assert.match(compat,/financeGuardianRpc/);
  assert.match(api,/financeGuardianRpc/);
  assert.match(routes,/finance-guardian-rpc/);
  assert.match(routes,/requireRole\(ctx,\["accountant","accounts_office"\]\)/);
  assert.match(routes,/A verified MFA session is required for parent and guardian fee follow-up/);
});

test("Accounts Office portal identity actions normalize the blueprint UI alias to Neon's accountant role",()=>{
  const compat=read("frontend/neon-supabase-compat.js");
  const accounts=read("frontend/finance-accounts.js");
  const identity=read("worker/src/identity-admin.ts");
  assert.match(accounts,/openPortalCreate\('accounts_office'/);
  assert.match(compat,/payload\?\.role==="accounts_office"\?"accountant":payload\?\.role/);
  assert.match(identity,/\["accountant","student","parent_guardian"\]/);
});

test("active inherited operational function invocations are all mapped by the Neon compatibility client",()=>{
  const compat=read("frontend/neon-supabase-compat.js");
  const invoked=new Set();
  for(const name of active){
    const source=read("frontend/"+name);
    for(const match of source.matchAll(/functions\.invoke\(\s*["'`]([^"'`]+)["'`]/g))invoked.add(match[1]);
  }
  const missing=[...invoked].filter(name=>!compat.includes(`name==="${name}"`)).sort();
  assert.deepEqual(missing,[]);
});

test("active inherited tenant workflows never fall back to native browser action dialogs",()=>{
  const violations=[];
  for(const name of active){
    const source=read("frontend/"+name);
    if(/\b(?:window\.)?(?:alert|prompt|confirm)\s*\(/.test(source))violations.push(name);
  }
  assert.deepEqual(violations,[]);
});
