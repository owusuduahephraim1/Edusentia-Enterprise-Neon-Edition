import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read = path => readFileSync(new URL("../"+path, import.meta.url),"utf8");
const sql=read("database/reference-compat/0084_class_teacher_student_edit_scope.sql");
const ui=read("frontend/parity-students.js");
const gateway=read("worker/src/certified-rpc.ts");

test("student edit permission is separate from general management permission",()=>{
  assert.match(sql,/create or replace function public\.can_edit_student_record\(target_student_id uuid\)/i);
  assert.doesNotMatch(sql,/create or replace function public\.can_manage_student\(/i);
  assert.match(sql,/c\.class_teacher_id=auth\.uid\(\)/);
  assert.match(sql,/e\.active and e\.deleted_at is null/);
  assert.match(sql,/public\.is_records_manager\(\)/);
});
test("teacher cannot change guardian, class placement or register new student",()=>{
  assert.match(sql,/class_teacher' and guardian_data <> '\{\}'::jsonb/);
  assert.match(sql,/class_teacher' and enrollment_data <> '\{\}'::jsonb/);
  assert.match(sql,/class_teacher' and sid is null/);
  assert.match(sql,/if not public\.can_edit_student_record\(sid\)/);
});
test("student editor requires backend authorization and excludes protected teacher changes",()=>{
  assert.match(ui,/certified\("can_edit_student_record"/);
  assert.match(ui,/if\(id&&!await canEditStudent\(id\)\)/);
  assert.match(ui,/guardian:teacherEdit\?\{\}:\{/);
  assert.match(ui,/enrollment:teacherEdit\?\{\}:/);
  assert.match(ui,/teacherEdit\?'disabled style="display:none"'/);
  assert.match(gateway,/case "can_edit_student_record":/);
});
