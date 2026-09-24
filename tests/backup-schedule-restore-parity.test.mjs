import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=path=>fs.readFileSync(path,"utf8");

test("backup scheduling is promoted to the tenant template and existing isolated tenants",()=>{
  const migration=read("database/reference-compat/0069_backup_schedule_restore_experience.sql");
  const resilience=read("database/reference-compat/0070_backup_worker_batch_resilience.sql");
  const r2Repair=read("database/reference-compat/0071_backup_r2_tenant_upsert_fix.sql");
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
  assert.match(installer,/0070_backup_worker_batch_resilience/);
  assert.match(installer,/0071_backup_r2_tenant_upsert_fix/);
  assert.match(upgrade,/0069_backup_schedule_restore_experience/);
  assert.match(upgrade,/0070_backup_worker_batch_resilience/);
  assert.match(upgrade,/0071_backup_r2_tenant_upsert_fix/);
  assert.match(upgrade,/test "\$migration_count" = "47"/);
  assert.match(resilience,/backup_worker_read_batch/);
  assert.match(resilience,/heartbeat_at/);
  assert.match(resilience,/backup_worker_reconcile_stale_backups/);
  assert.match(r2Repair,/on conflict\(tenant_id,object_key\) do update set/);
  assert.doesNotMatch(r2Repair,/on conflict\(object_key\)/);
  assert.match(template,/backup_schedule_ok/);
  assert.match(template,/backup_worker_read_batch\(uuid,jsonb\)/);
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
  assert.match(worker,/action==="delete_failed"/);
  assert.match(worker,/deleteFailedBackup/);
});


test("manual backup snapshots use batched tenant-local reads and fail closed without phantom processing rows",()=>{
  const worker=read("worker/src/backup-service.ts");
  const index=read("worker/src/index.ts");
  const migration=read("database/reference-compat/0070_backup_worker_batch_resilience.sql");

  assert.match(worker,/DATABASE_BATCH_SIZE=12/);
  assert.match(worker,/backup_worker_read_batch/);
  assert.match(worker,/async function readTable\(/);
  assert.match(worker,/Persist failure state before best-effort R2 cleanup/);
  assert.match(worker,/const material=await encryptionMaterial\(env\)/);
  assert.doesNotMatch(worker,/\\"license_plans\\",\s*\\"school_licenses\\"/);
  assert.match(index,/\"55000\":409/);
  assert.match(migration,/Previous backup worker was interrupted before completion\. Safe retry is allowed\./);
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
  assert.match(enterprise,/data-backup-delete-failed/);
  assert.match(enterprise,/scheduledBackup\("delete_failed"/);
  assert.match(enterprise,/Restore from downloaded ZIP/);
  assert.match(enterprise,/prepare_restore_import/);
  assert.match(enterprise,/execute_restore_import/);
  assert.match(enterprise,/RESTORE SCHOOL/);
  assert.match(enterprise,/function backupStatIcon/);
  const css=read("frontend/style.css");
  assert.match(css,/\.stat-icon\{width:48px;height:48px;border-radius:15px;display:grid;place-items:center;font-size:21px;font-weight:900\}/);
  assert.match(css,/\.stat-icon\{width:39px;height:39px\}/);
  assert.match(css,/\.stat-card>div>span\{display:block;font-size:12px;color:var\(--muted\);font-weight:650\}/);
  assert.doesNotMatch(css,/\.stat-card span\{display:block/);
  assert.doesNotMatch(css,/\.stat-icon svg\{/);
  assert.doesNotMatch(css,/\.stat-icon\{[^}]*flex:/);
  assert.doesNotMatch(css,/\.backup-stat-icon\{[^}]*width:/);
  assert.doesNotMatch(enterprise,/backup-stat-icon/);
  assert.doesNotMatch(enterprise,/<svg viewBox="0 0 24 24"/);
  assert.doesNotMatch(enterprise,/stat-card backup-stat-card/);
  assert.match(enterprise,/symbols=\{history:"↻",automatic:"◷",next:"→",retention:"▣"\}/);
  assert.match(enterprise,/tones=\{history:"blue",automatic:"green",next:"purple",retention:"gold"\}/);
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

test("production Worker deployment provisions stable backup encryption and transfer secrets",()=>{
  const workflow=read(".github/workflows/deploy-worker.yml");
  assert.match(workflow,/ensure_worker_secret BACKUP_ENCRYPTION_KEY/);
  assert.match(workflow,/ensure_worker_secret BACKUP_SIGNING_SECRET/);
  assert.match(workflow,/preserving the existing key/);
});
