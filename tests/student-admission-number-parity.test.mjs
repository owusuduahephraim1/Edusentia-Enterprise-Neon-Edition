import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("student admission numbers are immutable and class scoped",()=>{
  const sql=read("database/reference-compat/0049x_class_scoped_student_admission_numbers.sql");
  assert.match(sql,/candidate:=root\|\|'-STU-'\|\|frozen_prefix\|\|lpad\(n::text,3,'0'\)/);
  assert.match(sql,/prefix:='BS'\|\|parts\[1\]/);
  assert.match(sql,/prefix:='KG'\|\|parts\[1\]/);
  assert.match(sql,/prefix:='NS'\|\|parts\[1\]/);
  assert.match(sql,/prefix:='CR'/);
  assert.match(sql,/select s\.admission_no::text[\s\S]*into admission[\s\S]*for update/);
  assert.doesNotMatch(sql,/update public\.students set admission_no=/i);
});

test("class counters seed from existing pupils and never recycle used admission numbers",()=>{
  const sql=read("database/reference-compat/0049x_class_scoped_student_admission_numbers.sql");
  assert.match(sql,/select count\(distinct e\.student_id\)[\s\S]*where e\.class_id=target_class_id/);
  assert.match(sql,/student_admission_sequences/);
  assert.match(sql,/for update/);
  assert.match(sql,/exit when not exists\([\s\S]*public\.students/);
});

test("student UI and CSV import use automatic class numbering and alphabetical ordering",()=>{
  const ui=read("frontend/parity-students.js");
  const sql=read("database/reference-compat/0049x_class_scoped_student_admission_numbers.sql");
  assert.match(ui,/Generated automatically on save/);
  assert.match(ui,/Basic 3 → NIS000001-STU-BS3001/);
  assert.doesNotMatch(ui,/generate_school_identifier",\{identifier_kind:"student"\}/);
  assert.match(ui,/Academic year and class are required for a new student/);
  assert.match(sql,/order by lower\(coalesce\(value->>'last_name',''\)\)/);
  assert.match(sql,/last_name_sort,first_name_sort,middle_name_sort/);
});
