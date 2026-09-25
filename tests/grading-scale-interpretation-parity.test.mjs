import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=path=>fs.readFileSync(path,"utf8");

test("grading-scale interpretation schema matches the certified save contract",()=>{
  const migration=read("database/reference-compat/0072_grading_scale_interpretation_parity.sql");
  const installer=read("database/reference-compat/install-operational-parity.sh");
  const upgrade=read("scripts/update-isolated-operational-tenants.sh");
  const mutation=read("database/reference-compat/0037_certified_academic_configuration_mutations.sql");
  const template=read("database/tenant-template/install.sh");

  assert.match(migration,/alter table public\.grading_scales[\s\S]*add column if not exists interpretation text/i);
  assert.match(migration,/default_grading_interpretation\(grade,remark\)/i);
  assert.match(migration,/alter column interpretation set not null/i);
  assert.match(migration,/0072_grading_scale_interpretation_parity/);
  assert.match(installer,/0072_grading_scale_interpretation_parity/);
  assert.match(upgrade,/0072_grading_scale_interpretation_parity/);
  assert.match(upgrade,/test "\$migration_count" = "48"/);
  assert.match(upgrade,/grading_scale_contract_ok/);
  assert.match(template,/grading_scale_contract_ok/);
  assert.match(mutation,/insert into public\.grading_scales\([\s\S]*interpretation/i);
  assert.match(mutation,/interpretation=interpretation_text/i);
});
