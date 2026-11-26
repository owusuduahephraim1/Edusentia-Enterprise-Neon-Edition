import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const source=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");

test("teacher recognition batch offers a creation action for an empty award category list",()=>{
  assert.match(source,/id="certificateAddAwardCategory"/);
  assert.match(source,/No teacher award categories exist for this school/);
  assert.match(source,/id="certificateAwardHint"/);
});

test("new teacher award category is saved using certified API and reloaded into the batch selector",()=>{
  const begin=source.indexOf('byId("certificateAddAwardCategory").onclick=');
  const end=source.indexOf('byId("certificateBatchCancel").onclick=',begin);
  assert.ok(begin>=0 && end>begin);
  const block=source.slice(begin,end);
  assert.match(block,/certified\("save_teacher_award_category"/);
  assert.match(block,/certified\("get_certificate_console"/);
  assert.match(block,/select\.innerHTML=/);
  assert.match(block,/select\.value=String\(saved\.id\)/);
  assert.match(block,/catch\(error\)/);
});

test("teacher award category selection remains required for batch eligibility loading",()=>{
  assert.match(source,/form\.elements\.award_category_id\.required=teacher/);
  assert.match(source,/if\(!form\.reportValidity\(\)\)return/);
});
