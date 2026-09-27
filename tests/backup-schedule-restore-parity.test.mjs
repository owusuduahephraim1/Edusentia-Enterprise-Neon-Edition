import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=path=>fs.readFileSync(path,"utf8");

test("backup scheduling is promoted to the tenant template and existing isolated tenants",()=>{
  const migration=read("database/reference-compat/0069_backup_schedule_restore_experience.sql");
  const resilience=read("database/reference-compat/0070_backup_worker_batch_resilience.sql");
  const r2Repair=read("database/reference-compat/0071_backup_r2_tenant_upsert_fix.sql");
  const interruptionRecovery=read("database/reference-compat/0073_backup_interruption_recovery.sql");
  const bulkObjectRecording=read("database/reference-compat/0074_backup_worker_bulk_object_recording.sql");
  const ambiguityFix=read("database/reference-compat/0075_backup_bulk_object_ambiguity_fix.sql");
  const restoreBridge=read("database/reference-compat/0077_restore_worker_bridge.sql");
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
  assert.match(installer,/0073_backup_interruption_recovery/);
  assert.match(installer,/0074_backup_worker_bulk_object_recording/);
  assert.match(installer,/0075_backup_bulk_object_ambiguity_fix/);
  assert.match(installer,/0077_restore_worker_bridge/);
  assert.match(upgrade,/0069_backup_schedule_restore_experience/);
  assert.match(upgrade,/0070_backup_worker_batch_resilience/);
  assert.match(upgrade,/0071_backup_r2_tenant_upsert_fix/);
  assert.match(upgrade,/0072_grading_scale_interpretation_parity/);
  assert.match(upgrade,/0074_backup_worker_bulk_object_recording/);
  assert.match(upgrade,/0075_backup_bulk_object_ambiguity_fix/);
  assert.match(upgrade,/0077_restore_worker_bridge/);
  assert.match(upgrade,/test "\$migration_count" = "53"/);
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
  assert.match(worker,/backup_worker_reconcile_stale_backups/);
  assert.match(worker,/OBJECT_METADATA_BATCH_SIZE=200/);
  assert.match(worker,/backup_worker_record_object_batch/);
  assert.doesNotMatch(worker,/backup_worker_record_object\(/);
  assert.match(worker,/async function readTable\(/);
  assert.match(worker,/Persist failure state before best-effort R2 cleanup/);
  assert.match(worker,/const material=await encryptionMaterial\(env\)/);
  assert.doesNotMatch(worker,/\\"license_plans\\",\s*\\"school_licenses\\"/);
  assert.match(index,/\"55000\":409/);
  assert.match(migration,/Previous backup worker was interrupted before completion\. Safe retry is allowed\./);
});

test("backup workspace provides simple one-click backup and protected one-confirm restore",()=>{
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  const worker=read("worker/src/backup-service.ts");
  const download=read("frontend/tenant-backup-r2-download-core-r42-v18.js");
  const restore=read("worker/src/restore-service.ts");

  assert.match(enterprise,/Create backup/);
  assert.match(enterprise,/scheduledBackup\("backup_now"\)/);
  assert.match(worker,/action==="backup_now"/);
  assert.match(worker,/verifyBackup\(env,sql,ctx,String\(backup\.id\)\)/);
  assert.match(enterprise,/Automatic backup & advanced tools/);
  assert.match(enterprise,/Weekly/);
  assert.match(enterprise,/Monthly/);
  assert.match(enterprise,/data-backup-download/);
  assert.match(enterprise,/data-backup-delete-failed/);
  assert.match(enterprise,/scheduledBackup\("delete_failed"/);
  assert.match(enterprise,/Restore backup/);
  assert.match(enterprise,/prepare_restore_import/);
  assert.match(enterprise,/execute_restore_import/);
  assert.match(enterprise,/confirmation:"RESTORE SCHOOL"/);
  assert.doesNotMatch(enterprise,/Type RESTORE SCHOOL to continue/);
  assert.match(download,/backup-download-gateway/);
  assert.match(download,/new window\.JSZip/);
  assert.match(download,/AES-256-GCM encrypted database and protected-file payloads/);
  assert.match(worker,/tenant_code:ctx\.tenantCode,tenant_name:ctx\.tenantName/);
  assert.match(download,/Tenant number:/);
  assert.match(download,/School:/);
  assert.match(download,/\$\{school\}-\$\{tenant\}-encrypted-backup-/);
  assert.match(restore,/String\(body\.confirmation\|\|""\)!=="RESTORE SCHOOL"/);
  assert.match(restore,/performFullBackup\(env,sql,ctx,"pre_restore"\)/);
  assert.match(restore,/restore_wrong_tenant/);
  assert.match(restore,/school_restore_clear_operational_data/);
  assert.match(restore,/school_restore_complete/);
  assert.ok(
    restore.indexOf('"classes","school_settings"')>=0,
    "school_settings must restore after classes because it can reference certificate_completion_class_id"
  );
  for(const fn of [
    "school_restore_begin","school_restore_set_status","school_restore_clear_operational_data",
    "school_restore_apply_table","school_restore_complete"
  ]) assert.match(restoreBridge,new RegExp("create or replace function public\\."+fn+"\\("));
  assert.match(restoreBridge,/backup_worker_require_restore_context/);
  assert.match(restoreBridge,/current_setting\('app\.role',true\)/);
  assert.match(restoreBridge,/student_admission_sequences/);
  assert.match(restoreBridge,/jsonb_populate_recordset/);
  assert.match(restoreBridge,/overriding system value/);
  assert.match(restoreBridge,/0077_restore_worker_bridge/);
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
  const wrangler=read("worker/wrangler.jsonc");
  assert.doesNotMatch(wrangler,/"cpu_ms"/);
  assert.match(workflow,/ensure_worker_secret BACKUP_ENCRYPTION_KEY/);
  assert.match(workflow,/ensure_worker_secret BACKUP_SIGNING_SECRET/);
  assert.match(workflow,/preserving the existing key/);
});
