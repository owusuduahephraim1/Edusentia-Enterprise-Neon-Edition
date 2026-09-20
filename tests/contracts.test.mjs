import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const read=p=>fs.readFileSync(p,"utf8");
test("r42-v18 accounts staff deletion invariant is preserved",()=>{const sql=read("database/migrations/0005_finance_hr_admissions.sql");assert.match(sql,/archive-only/);assert.doesNotMatch(sql,/delete from finance\.accounts_office_staff/i)});
test("frontend never receives database configuration",()=>{const c=read("frontend/config.js");assert.doesNotMatch(c,/DATABASE_URL|postgresql:\/\//i)});
test("session cookie is HttpOnly and Secure",()=>{const a=read("worker/src/auth.ts");assert.match(a,/HttpOnly/);assert.match(a,/Secure/)});
test("RLS migration forces tenant policies",()=>{const s=read("database/migrations/0007_rls_and_runtime_grants.sql");assert.match(s,/force row level security/i);assert.match(s,/tenant_isolation/)});

test("CLI bootstrap is secret-gated without weakening normal origin checks",()=>{const i=read("worker/src/index.ts");assert.match(i,/bootstrapCli/);assert.match(i,/x-bootstrap-secret/);assert.match(i,/origin!==env\.APP_ORIGIN/)});
test("retired modules remain retired",()=>{const m=read("docs/MODULE_CATALOG.md");for(const x of ["Inventory","Library","Transport"])assert.match(m,new RegExp(`- ${x}`))});
test("platform license catalog is outside tenant runtime write-default schema",()=>{const m=read("database/migrations/0013_operations_compliance.sql");assert.match(m,/platform\.license_plans/);assert.match(m,/grant select on platform\.license_plans,platform\.license_feature_catalog/);assert.doesNotMatch(m,/grant select,insert,update,delete on all tables in schema platform/)});
