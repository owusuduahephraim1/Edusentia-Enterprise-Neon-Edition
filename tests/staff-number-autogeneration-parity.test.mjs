import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("teacher and principal editors use blueprint auto-generated staff numbers",()=>{
  const teachers=read("frontend/parity-teachers.js");
  const principals=read("frontend/parity-principal.js");

  assert.match(teachers,/generate_school_identifier",\{identifier_kind:"teacher"\}/);
  assert.match(teachers,/name="staff_no"[^>]*required readonly aria-readonly="true"/);
  assert.match(teachers,/Generated automatically from the school tenant identity/);

  assert.match(principals,/generate_school_identifier",\{identifier_kind:"principal"\}/);
  assert.match(principals,/<input type="hidden" name="staff_no" value=/);
  assert.doesNotMatch(principals,/<span>Staff number<\/span><input name="staff_no"/);
});

test("certified database remains authoritative for staff-number generation",()=>{
  const crud=read("database/reference-compat/0038_certified_teacher_principal_crud.sql");
  const rpc=read("worker/src/certified-rpc.ts");

  assert.match(crud,/staff:=public\.generate_school_identifier\('teacher'\)/);
  assert.match(crud,/staff:=public\.generate_school_identifier\('principal'\)/);
  assert.match(crud,/raise exception 'Staff number already exists'/);
  assert.match(rpc,/"generate_school_identifier"/);
});
