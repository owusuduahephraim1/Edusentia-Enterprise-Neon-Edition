import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("master migration repairs the durable school deletion schema",()=>{
  const migration=read("database/migrations/0025f_platform_school_deletion_repair.sql");
  assert.match(migration,/add column if not exists school_name text/);
  assert.match(migration,/add column if not exists database_deleted_at timestamptz/);
  assert.match(migration,/add column if not exists r2_deleted_at timestamptz/);
  assert.match(migration,/add column if not exists master_deleted_at timestamptz/);
  assert.match(migration,/create or replace function platform\.prepare_school_deletion/);
  assert.match(migration,/create or replace function platform\.finalize_school_deletion/);
  assert.match(migration,/delete from audit\.security_events where tenant_id=j\.tenant_id/);
  assert.match(migration,/delete from audit\.events where tenant_id=j\.tenant_id/);
  assert.match(migration,/0025f_platform_school_deletion_repair/);
  assert.match(migration,/schema_version='0025'/);
});

test("denied registrations can be permanently deleted with audited confirmation",()=>{
  const migration=read("database/migrations/0025f_platform_school_deletion_repair.sql");
  const routes=read("worker/src/platform-routes.ts");
  const api=read("frontend/api-client.js");
  const ui=read("frontend/platform-saas-admin.js");

  assert.match(migration,/platform\.delete_denied_registration/);
  assert.match(migration,/r\.status not in\('denied','rejected','cancelled'\)/);
  assert.match(migration,/platform\.registration\.deleted_permanently/);
  assert.match(routes,/registrations\\\/\(\[0-9a-f-\]\{36\}\)\\\/delete/);
  assert.match(routes,/delete_denied_registration/);
  assert.match(routes,/deleteIsolatedTenant\(env,String\(registration\.tenant_id\)/);
  assert.match(api,/deleteRegistration:\(registrationId,confirmation,reason\)/);
  assert.match(ui,/\["denied","rejected","cancelled"\]/);
  assert.match(ui,/data-action="delete-registration"/);
  assert.match(ui,/Permanently delete registration/);
  assert.match(ui,/Delete permanently/);
});

test("full tenant deletion remains database and R2 destructive only after exact confirmation",()=>{
  const deletion=read("worker/src/deletion.ts");
  const ui=read("frontend/platform-saas-admin.js");
  assert.match(deletion,/drop database/);
  assert.match(deletion,/const prefix=`tenants\/\$\{tenantId\}\/`/);
  assert.match(deletion,/finalize_school_deletion/);
  assert.match(ui,/const expected=`DELETE \$\{t\.tenant_code\}`/);
  assert.match(ui,/Deleting database and R2 objects/);
});
