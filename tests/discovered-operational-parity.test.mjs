import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("report-card parity restores the certified archive-status column",()=>{
  const sql=read("database/reference-compat/0061_discovered_operational_parity_repairs.sql");
  assert.match(sql,/alter table public\.student_reports[\s\S]*add column if not exists archived_status public\.report_status/i);
  const reports=read("frontend/parity-reports.js");
  assert.match(reports,/list_report_cards_v6/);
});

test("Users and Access guardian directory is served by a protected definer bridge",()=>{
  const sql=read("database/reference-compat/0061_discovered_operational_parity_repairs.sql");
  const routes=read("worker/src/routes.ts");
  assert.match(sql,/create or replace function public\.neon_guardian_account_records\(\)/i);
  assert.match(sql,/security definer/i);
  assert.match(sql,/grant execute on function public\.neon_guardian_account_records\(\) to edusentia_worker_runtime/i);
  assert.match(routes,/select public\.neon_guardian_account_records\(\) records/);
  const section=routes.split('p==="/api/admin/guardian-account-records"')[1]?.split('p==="/api/settings/school"')[0]||"";
  assert.doesNotMatch(section,/join public\.students/i);
});

test("Operations no longer hard-depends on a cron.job relation in Neon",()=>{
  const sql=read("database/reference-compat/0061_discovered_operational_parity_repairs.sql");
  assert.match(sql,/create or replace function public\.neon_cron_jobs_snapshot\(\)/i);
  assert.match(sql,/to_regclass\('cron\.job'\)/i);
  assert.match(sql,/execute \$sql\$/i);
  const dashboard=sql.split("create or replace function public.operations_dashboard")[1]||"";
  assert.match(dashboard,/public\.neon_cron_jobs_snapshot\(\)/);
  assert.doesNotMatch(dashboard,/from cron\.job/i);
});

test("student and staff ID-card generators expose issue and expiry dates",()=>{
  const ui=read("frontend/parity-enterprise-workspaces.js");
  assert.match(ui,/Generate Student ID Cards/);
  assert.match(ui,/name="issue_date"/);
  assert.match(ui,/name="expires_on"/);
  assert.match(ui,/target_issue_date:form\.elements\.issue_date\.value/);
  assert.match(ui,/target_expires_on:form\.elements\.expires_on\.value\|\|null/);
  assert.match(ui,/Generate Staff ID Cards/);
  assert.match(ui,/Teachers and Principals/);
  assert.doesNotMatch(ui,/Generate Staff ID Cards[\s\S]{0,2500}accounts_office/);
});

test("0061 is installed and verified for future and existing tenants",()=>{
  const install=read("database/reference-compat/install-operational-parity.sh");
  const upgrade=read("scripts/update-isolated-operational-tenants.sh");
  const template=read("database/tenant-template/install.sh");
  assert.match(install,/reconcile_once_recorded "0061_discovered_operational_parity_repairs"/);
  assert.match(install,/reconcile_once_recorded "0062_user_directory_role_workspace_parity"/);
  assert.match(upgrade,/0062_user_directory_role_workspace_parity/);
  assert.match(upgrade,/0061_discovered_operational_parity_repairs/);
  assert.match(upgrade,/migration_count" = "38/);
  assert.match(template,/operational_repairs_ok/);
});


test("Users and Access exposes the certified linked-record directories on Neon",()=>{
  const sql=read("database/reference-compat/0062_user_directory_role_workspace_parity.sql");
  assert.match(sql,/create or replace function public\.list_profiles_with_access\(\)/i);
  assert.match(sql,/alter table public\.students[\s\S]*add column if not exists profile_id uuid/i);
  assert.match(sql,/students_profile_id_uidx/);
  assert.match(sql,/alter table public\.profiles[\s\S]*add column if not exists must_change_password boolean/i);
  assert.match(sql,/'teacher_records'/);
  assert.match(sql,/'headteacher_records'/);
  assert.match(sql,/'accountant_records'/);
  assert.match(sql,/'student_records'/);
  assert.match(sql,/left join authn\.users/i);
  assert.match(sql,/neon_certified_runtime_owner/);
  assert.match(sql,/'teachers','headteachers','accounts_office_staff','students'/);
  assert.match(sql,/grant execute on function public\.list_profiles_with_access\(\) to edusentia_worker_runtime/i);
});

test("Neon loads the certified user-access linkage repair instead of a missing module",()=>{
  const linkage=read("frontend/tenant-user-access-linkage-v4.js");
  const loader=read("frontend/tenant-accountant-student-submit-v3.js");
  assert.match(loader,/tenant-user-access-linkage-v4\.js/);
  assert.match(linkage,/EDS_USER_ACCESS_LINKAGE_V4/);
  assert.match(linkage,/guardianAccountRecords/);
  assert.match(linkage,/directoryUserManagement/);
  assert.match(linkage,/parent_guardian/);
  assert.match(linkage,/student/);
});

test("academic promotion and teacher assignment keep the saved Neon state visible",()=>{
  const academics=read("frontend/parity-academics.js");
  assert.match(academics,/S\.data\.school=\{\.\.\.\(S\.data\.school\|\|\{\}\),promotion_cutoff_score:saved\}/);
  assert.match(academics,/shellState\.boot\.school/);
  assert.match(academics,/teacher_records/);
  assert.match(academics,/profile_id/);
});

test("Accounts Office dashboard accepts both certified role spellings",()=>{
  const dashboard=read("frontend/tenant-accountant-dashboard-v1.js");
  assert.match(dashboard,/\["accountant","accounts_office"\]\.includes/);
});


test("Teacher and Principal linked-record choices remain selected after change",()=>{
  const ui=read("frontend/parity-enterprise-workspaces.js");
  assert.match(ui,/selected=staffSelect\.value\|\|selectedGeneric\|\|""/);
});
