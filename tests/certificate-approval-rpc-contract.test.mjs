import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const ui=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const registry=fs.readFileSync("worker/src/certified-rpc-registry.ts","utf8");
const start=ui.indexOf("const certificateBatchAction=async(");
const end=ui.indexOf('}catch(err){notify("Certificate batch unavailable"',start);
const handlers=ui.slice(start,end);

test("submitting a certificate batch matches its single-argument RPC contract",()=>{
  assert.ok(start>=0&&end>start);
  assert.match(handlers,/certificateBatchAction\("certificateSubmitBatch","submit_certificate_batch",\{target_batch_id:batch\.id\}/);
  assert.doesNotMatch(handlers,/submission_note/);
  assert.match(registry,/"submit_certificate_batch":\s*\{[\s\S]*?"name": "target_batch_id"/);
});

test("Principal review uses the registered review_note_text parameter",()=>{
  assert.match(handlers,/decision:"approved",review_note_text:/);
  assert.match(handlers,/decision:"rejected",review_note_text:note/);
  assert.doesNotMatch(handlers,/(^|[^_])review_note:/);
  assert.match(registry,/"review_certificate_batch":\s*\{[\s\S]*?"name": "review_note_text"/);
});

test("certificate workflow errors are surfaced and duplicate clicks blocked",()=>{
  assert.match(handlers,/if\(!button\|\|button\.disabled\)return/);
  assert.match(handlers,/button\.disabled=true/);
  assert.match(handlers,/catch\(error\)\{notify\("Certificate workflow not updated",friendly\(error\),"error"\)/);
  assert.match(handlers,/finally\{button\.disabled=false/);
});

test("issued certificate still requires the existing authorized issue RPC",()=>{
  assert.match(handlers,/certificateBatchAction\("certificateIssueBatch","issue_certificate_batch",\{target_batch_id:batch\.id,target_issue_date:/);
});
