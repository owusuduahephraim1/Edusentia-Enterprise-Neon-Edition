import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const ui=readFileSync(new URL("../frontend/parity-reports.js",import.meta.url),"utf8");
const migration=readFileSync(new URL("../database/reference-compat/0085_report_attendance_and_comment_approval.sql",import.meta.url),"utf8");
const installer=readFileSync(new URL("../database/reference-compat/install-operational-parity.sh",import.meta.url),"utf8");

test("new report card selection filters current student enrolments by class before term",()=>{
  assert.match(ui,/async function openNewReportPicker/);
  assert.match(ui,/name="class_id" required/);
  assert.match(ui,/name="enrollment_id" required disabled/);
  assert.match(ui,/target_class_id:classId/);
  assert.match(ui,/academic_years\?\.find\(y=>y\.is_active\)/);
  assert.match(ui,/list_my_attendance_classes/);
  assert.doesNotMatch(ui,/name="enrollment_id" size="10"/);
});

test("attendance is read-only and originates from saved marked class registers",()=>{
  assert.match(ui,/name="days_school_opened"[^>]*readonly/);
  assert.match(ui,/name="days_present"[^>]*readonly/);
  assert.match(migration,/CREATE OR REPLACE FUNCTION public\.attendance_counts_for_enrollment/);
  assert.match(migration,/exists\(select 1 from public\.student_attendance_entries logged/);
  assert.match(migration,/a\.attendance_status in \('present','late'\)/);
  assert.match(migration,/days_school_opened=opened_count/);
  assert.match(migration,/days_present=present_count/);
});

test("class teacher and principal receive reviewable suggestions and independent saves",()=>{
  assert.match(ui,/function suggestedReportComments/);
  assert.match(ui,/filter\(s=>s\.result_id/);
  assert.match(ui,/can_edit_teacher_comment/);
  assert.match(ui,/can_edit_principal_comment/);
  assert.match(ui,/save_report_comments/);
  assert.match(migration,/Principal comment must be reviewed and saved before approving/);
  assert.match(migration,/Class teacher comment must be reviewed and saved before submission/);
  assert.match(migration,/head_comment=head_comment/);
});

test("subject assessment saves cannot erase another role's report profile fields",()=>{
  assert.match(migration,/report_fields <> '\{\}'::jsonb and not canreportfields/);
  assert.match(migration,/teacher_comment=case when canreportfields/);
  assert.match(migration,/promoted_to_class_id=case when canreportfields/);
  assert.match(installer,/0085_report_attendance_and_comment_approval/);
});

test("the class selector never exposes unassigned classes to either teacher role",()=>{
  assert.match(ui,/currentRole\(\)==="class_teacher"/);
  assert.match(ui,/const assigned=await certified\("list_my_attendance_classes"/);
  assert.match(ui,/const workspace=await certified\("get_role_workspace",\{\}\)/);
  assert.match(ui,/workspace\?\.subjects/);
  assert.match(ui,/configuredClasses\.filter\(c=>allowed\.has\(String\(c\.id\)\)\)/);
  assert.match(ui,/teacherScoped&&classes\.length===1/);
});

test("a main class teacher sees the union of main and subject-taught classes",()=>{
  assert.match(ui,/if\(teacherScoped\)\{/);
  assert.match(ui,/const subjectClassIds=new Set\(/);
  assert.match(ui,/const assigned=await certified\("list_my_attendance_classes"/);
  assert.match(ui,/mainClassIds\.add\(String\(c\.id\)\)/);
  assert.match(ui,/const allowed=new Set\(\[\.\.\.mainClassIds,\.\.\.subjectClassIds\]\)/);
  assert.match(ui,/permitted=configuredClasses\.filter\(c=>allowed\.has\(String\(c\.id\)\)\)/);
  assert.match(ui,/Main class/);
  assert.match(ui,/Subject class/);
});
