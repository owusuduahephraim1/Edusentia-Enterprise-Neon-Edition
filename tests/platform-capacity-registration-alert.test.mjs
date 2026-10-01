import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("tenant student mutations synchronize the master capacity snapshot",()=>{
  const routes=read("worker/src/routes.ts");
  assert.match(routes,/STUDENT_CAPACITY_MUTATIONS/);
  assert.match(routes,/"save_student"/);
  assert.match(routes,/"bulk_import_students"/);
  assert.match(routes,/"archive_student"/);
  assert.match(routes,/"restore_student"/);
  assert.match(routes,/"admissions_enroll_application"/);
  assert.match(routes,/platform_capacity_snapshot/);
  assert.match(routes,/student_active_count/);
  assert.match(routes,/syncMasterStudentCapacity\(master,sql,ctx,operation\)/);
});

test("platform admin displays licensed usage as active over capacity",()=>{
  const ui=read("frontend/platform-saas-admin.js");
  assert.match(ui,/Live licensed usage is synchronized after student changes/);
  assert.match(ui,/Example: 2 \/ 300 means 2 active students out of 300 licensed places/);
  assert.match(ui,/\$\{active\} \/ \$\{limit\}/);
  assert.match(ui,/student_capacity_checked_at/);
  assert.match(ui,/30000/);
  assert.match(ui,/reconcileCapacitySnapshots/);
  assert.match(ui,/refreshTenantCapacity/);
});

test("successful school registration offers WhatsApp and SMS app alerts",()=>{
  const config=read("frontend/config.js");
  const html=read("frontend/register.html");
  const script=read("frontend/register.js");
  assert.match(config,/platformAdminPhoneE164/);
  assert.match(html,/registrationAlertActions/);
  assert.match(script,/https:\/\/wa\.me\//);
  assert.match(script,/sms:/);
  assert.match(script,/Platform Super Administrator/);
  assert.match(script,/Registration ID/);
});

test("platform capacity telemetry counts the certified public student directory",()=>{
  const migration=read("database/reference-compat/0079_platform_capacity_public_students.sql");
  const installer=read("database/reference-compat/install-operational-parity.sh");
  const upgrader=read("scripts/update-isolated-operational-tenants.sh");
  assert.match(migration,/from public\.students/);
  assert.match(migration,/status='active' and deleted_at is null/);
  assert.doesNotMatch(migration,/from app\.students/);
  assert.match(migration,/platform_health_snapshot/);
  assert.match(installer,/0079_platform_capacity_public_students/);
  assert.match(upgrader,/0079_platform_capacity_public_students/);
  assert.match(upgrader,/migration_count\" = \"55\"/);
  assert.match(upgrader,/platform_capacity_snapshot/);
  assert.match(upgrader,/student_active_count=:'capacity_active'::integer/);
  assert.match(upgrader,/student_total_count=:'capacity_total'::integer/);
  assert.match(upgrader,/student_capacity_checked_at=now\(\)/);
  assert.match(upgrader,/student capacity synchronized/);
});
