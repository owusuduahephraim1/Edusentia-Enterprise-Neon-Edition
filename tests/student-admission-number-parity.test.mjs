import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("student admission numbers remain class scoped while active",()=>{
  const base=read("database/reference-compat/0049x_class_scoped_student_admission_numbers.sql");
  const reuse=read("database/reference-compat/0058_reusable_student_admission_numbers.sql");
  assert.match(base,/prefix:='BS'\|\|parts\[1\]/);
  assert.match(base,/prefix:='KG'\|\|parts\[1\]/);
  assert.match(base,/prefix:='NS'\|\|parts\[1\]/);
  assert.match(base,/prefix:='CR'/);
  assert.match(reuse,/candidate:=root\|\|'-STU-'\|\|clean_prefix\|\|lpad\(n::text,3,'0'\)/);
  assert.match(reuse,/select s\.admission_no::text[\s\S]*into admission[\s\S]*for update/);
});

test("removed students release their admission number for lowest-gap reuse",()=>{
  const sql=read("database/reference-compat/0058_reusable_student_admission_numbers.sql");
  for(const marker of [
    "drop constraint if exists students_admission_no_key",
    "create unique index if not exists students_admission_no_ci_idx",
    "where deleted_at is null",
    "generate_series(1,999)",
    "s.deleted_at is null",
    "pg_advisory_xact_lock",
    "Archived students do not reserve an admission number",
    "public.next_student_identifier_for_prefix(original_prefix)"
  ]) assert.ok(sql.includes(marker),marker);
  assert.doesNotMatch(sql,/last_number\s*\+\s*1/i);
});

test("restore keeps a released number when free and reallocates on collision",()=>{
  const sql=read("database/reference-compat/0058_reusable_student_admission_numbers.sql");
  assert.match(sql,/replacement_admission:=current_admission/);
  assert.match(sql,/lower\(s\.admission_no::text\)=lower\(current_admission\)/);
  assert.match(sql,/replacement_admission:=public\.next_student_identifier_for_prefix\(original_prefix\)/);
  assert.match(sql,/admission number reassigned from/);
});

test("student UI explains automatic lowest-available class numbering",()=>{
  const ui=read("frontend/parity-students.js");
  assert.match(ui,/Generated automatically on save/);
  assert.match(ui,/Basic 3 → NIS000001-STU-BS3001/);
  assert.match(ui,/lowest available/);
  assert.match(ui,/released for reuse/i);
  assert.doesNotMatch(ui,/generate_school_identifier",\{identifier_kind:"student"\}/);
  assert.match(ui,/Academic year and class are required for a new student/);
});
