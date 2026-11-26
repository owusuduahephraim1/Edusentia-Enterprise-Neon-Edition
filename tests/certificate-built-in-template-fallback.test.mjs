import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const front=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const migration=fs.readFileSync("database/reference-compat/0088_certificate_builtin_template_fallback.sql","utf8");
const reference=fs.readFileSync("reference/certified-ui/app.js","utf8");

test("certificate batch uses an active saved/uploaded template rather than creating a duplicate",()=>{
  assert.match(front,/!templates\.some\(t=>t\.certificate_type===v\.certificate_type&&t\.active!==false\)/);
  assert.match(front,/certified\("save_certificate_template",\{payload:/);
  assert.match(migration,/where ct\.certificate_type=v_certificate_type and ct\.active/);
  assert.match(migration,/if v_template\.id is null then/);
});
test("fallback is defined for all 3 certificate types without uploading a file",()=>{
  for (const type of ["student_promotion","jhs_completion","teacher_recognition"]){
    assert.ok(front.includes(type+":"),type);
    assert.ok(migration.includes("'"+type+"'"),type);
  }
  assert.match(migration,/true,'','','',0,''/);
  assert.match(migration,/pg_advisory_xact_lock/);
});
test("existing certificate authorization, eligibility, approval and immutable snapshot remain",()=>{
  assert.match(migration,/public\.can_manage_certificates\(\)/);
  assert.match(migration,/public\.apply_certificate_placeholders/);
  assert.match(migration,/public\.record_certificate_event/);
  assert.match(migration,/jsonb_build_object\('eligibility'/);
  assert.match(reference,/professional built-in certificate design was used/);
});
