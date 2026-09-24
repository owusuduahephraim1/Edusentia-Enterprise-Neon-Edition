import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=path=>fs.readFileSync(path,"utf8");

test("backup scheduling is promoted to the tenant template and existing isolated tenants",()=>{
  const migration=read("database/reference-compat/0069_backup_schedule_restore_experience.sql");
  const installer=read("database/reference-compat/install-operational-parity.sh");
  const upgrade=read("scripts/update-isolated-operational-tenants.sh");
  const template=read("database/tenant-template/install.sh");

  assert.match(migration,/backup_schedule_mode/);
  assert.match(migration,/check\(backup_schedule_mode in \('off','weekly','monthly'\)\)/);
  assert.match(migration,/trigger_mode/);
  assert.match(migration,/backup_worker_schedule_policy/);
  assert.match(migration,/backup_worker_set_schedule_policy/);
  assert.match(migration,/BACKUP_SCHEDULE_CHANGED/);
  assert.match(installer,/0069_backup_schedule_restore_experience/);
  assert.match(upgrade,/0069_backup_schedule_restore_experience/);
  assert.match(upgrade,/test "\$migration_count" = "45"/);
  assert.match(template,/backup_schedule_ok/);
});

test("automatic backups are plan gated and obey weekly or monthly tenant policy",()=>{
  const worker=read("worker/src/backup-service.ts");
  assert.match(worker,/license_feature_enabled\('scheduled_backup'\)/);
  assert.match(worker,/\["off","weekly","monthly"\]/);
  assert.match(worker,/action==="policy"/);
  assert.match(worker,/action==="set_schedule"/);
  assert.match(worker,/next_scheduled_backup_at/);
  assert.match(worker,/\["weekly","monthly"\]\.includes\(mode\)/);
  assert.match(worker,/performFullBackup\(env,sql,ctx,"scheduled"\)/);
  assert.match(worker,/verifyBackup\(env,sql,ctx,String\(backup\.id\)\)/);
});

test("backup workspace provides one tap backup, encrypted ZIP download and protected ZIP restore",()=>{
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  const download=read("frontend/tenant-backup-r2-download-core-r42-v18.js");
  const restore=read("worker/src/restore-service.ts");

  assert.match(enterprise,/Back up now/);
  assert.match(enterprise,/PLAN UPGRADE REQUIRED FOR AUTOMATIC BACKUP/);
  assert.match(enterprise,/Weekly/);
  assert.match(enterprise,/Monthly/);
  assert.match(enterprise,/data-backup-download/);
  assert.match(enterprise,/Restore from downloaded ZIP/);
  assert.match(enterprise,/prepare_restore_import/);
  assert.match(enterprise,/execute_restore_import/);
  assert.match(enterprise,/RESTORE SCHOOL/);
  assert.match(download,/backup-download-gateway/);
  assert.match(download,/new window\.JSZip/);
  assert.match(download,/AES-256-GCM encrypted database and protected-file payloads/);
  assert.match(restore,/performFullBackup\(env,sql,ctx,"pre_restore"\)/);
  assert.match(restore,/school_restore_clear_operational_data/);
  assert.match(restore,/school_restore_complete/);
});

test("commercial backup entitlements preserve manual backups for Starter and schedules for paid tiers",()=>{
  const tiering=read("database/reference-compat/0068_commercial_plan_tiering.sql");
  assert.match(tiering,/"manual_backup":true/);
  assert.match(tiering,/"scheduled_backup":false/);
  const scheduledTrue=(tiering.match(/"scheduled_backup":true/g)||[]).length;
  assert.ok(scheduledTrue>=2,"Professional and Enterprise should include scheduled backup");
});
