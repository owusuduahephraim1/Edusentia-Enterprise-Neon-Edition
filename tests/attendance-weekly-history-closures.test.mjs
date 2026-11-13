import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const frontend=readFileSync(new URL("../frontend/tenant-class-teacher-workspace-parity-v1.js",import.meta.url),"utf8");
const styles=readFileSync(new URL("../frontend/style.css",import.meta.url),"utf8");
const migration=readFileSync(new URL("../database/reference-compat/0086_weekly_attendance_school_closures.sql",import.meta.url),"utf8");
const worker=readFileSync(new URL("../worker/src/certified-rpc.ts",import.meta.url),"utf8");
const installer=readFileSync(new URL("../database/reference-compat/install-operational-parity.sh",import.meta.url),"utf8");
const upgrader=readFileSync(new URL("../scripts/update-isolated-operational-tenants.sh",import.meta.url),"utf8");

test("weekly attendance supports term-based week numbers, days and per-student recorded summaries",()=>{
  assert.match(migration,/CREATE OR REPLACE FUNCTION public\.get_attendance_weekly_history/);
  assert.match(migration,/week_zero:=first_day-/);
  assert.match(migration,/generate_series\(week_zero::timestamp,last_week::timestamp,'7 days'\)/);
  assert.match(migration,/IS NOT NULL THEN 'closed'/);
  assert.match(migration,/THEN 'weekend'/);
  assert.match(migration,/THEN 'unrecorded'/);
  assert.match(migration,/THEN 'recorded'/);
  assert.match(migration,/attendance_status='present'/);
  assert.match(migration,/attendance_status='late'/);
  assert.match(frontend,/async function loadWeeklyAttendanceHistory/);
  assert.match(frontend,/id="attendanceWeekSelect"/);
  assert.match(frontend,/data-week-day/);
  assert.match(frontend,/Student attendance for selected week/);
  assert.match(styles,/\.attendance-week-days/);
});

test("school closures and weekends exclude days without turning missing records into absences",()=>{
  assert.match(migration,/CREATE TABLE IF NOT EXISTS public\.school_closures/);
  assert.match(migration,/closure_type text NOT NULL CHECK/);
  assert.match(migration,/midterm_break/);
  assert.match(migration,/public_holiday/);
  assert.match(migration,/emergency_closure/);
  assert.match(migration,/unrecorded_days/);
  assert.match(migration,/extract\(isodow from r\.attendance_date\)::integer<=5/);
  assert.match(migration,/r\.attendance_date between c\.start_date and c\.end_date/);
  assert.match(migration,/Attendance already exists in this closure period/);
  assert.match(migration,/School closed on this date/);
  assert.match(frontend,/data\?\.closed_date/);
  assert.match(frontend,/School closed for this date/);
  assert.match(frontend,/Unrecorded days are not absences/);
});

test("administrator alone controls closures, teachers have assigned-class weekly scope",()=>{
  assert.match(migration,/IF NOT public\.is_system_admin\(\)/);
  assert.match(migration,/PERFORM public\.require_sensitive_access\(\)/);
  assert.match(migration,/IF NOT public\.is_assigned_class_teacher\(target_class_id\)/);
  assert.match(migration,/ENABLE ROW LEVEL SECURITY/);
  assert.match(migration,/REVOKE ALL ON TABLE public\.school_closures FROM edusentia_worker_runtime/);
  assert.match(frontend,/roles:\["system_admin"\].*render:renderSchoolCalendar/);
  assert.match(frontend,/registerView\(\{id:"attendance"/);
  for(const op of ["get_attendance_weekly_history","list_school_closures","save_school_closure","archive_school_closure"]){
    assert.ok(worker.includes('case "'+op+'"'),op+" certified worker operation");
  }
  assert.match(worker,/function dateArg/);
});

test("migration is installed for all tenants without modifying the Supabase reference",()=>{
  assert.match(installer,/0086_weekly_attendance_school_closures/);
  assert.match(upgrader,/0086_weekly_attendance_school_closures/);
  assert.match(migration,/Supabase reference remains unchanged/);
  assert.match(migration,/attendance_counts_for_enrollment/);
  assert.match(migration,/get_class_attendance_register/);
  assert.match(migration,/save_class_attendance/);
});
