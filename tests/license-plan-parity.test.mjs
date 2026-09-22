import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const sql=fs.readFileSync(new URL("../database/migrations/0025d_live_plan_feature_parity.sql",import.meta.url),"utf8");\nconst tenantSql=fs.readFileSync(new URL("../database/reference-compat/0049v_live_plan_feature_parity.sql",import.meta.url),"utf8");

const expectedCatalog=[
  "academic_history","advanced_analytics","analytics","assessment","attendance",
  "bulk_workflow","certificates","core_records","custom_branding","finance_exports",
  "finance_fees","finance_statements","financial_holds","governance","id_cards",
  "integrations","manual_backup","notifications","payroll","payroll_statutory",
  "priority_support","report_cards","scheduled_backup","school_prospectus",
  "staff_id_cards","timetable","uploaded_templates"
].sort();

const expectedPlans={
  starter:{
    limits:{max_students:300,max_teachers:30,max_system_admins:2,max_guardians:600,max_storage_mb:2048},
    enabled:["id_cards","analytics","timetable","assessment","attendance","governance","certificates","core_records","finance_fees","report_cards","bulk_workflow","manual_backup","notifications","staff_id_cards","academic_history","priority_support","scheduled_backup","school_prospectus","finance_statements","uploaded_templates"],
    disabled:["payroll","integrations","custom_branding","finance_exports","financial_holds","payroll_statutory","advanced_analytics"]
  },
  professional:{
    limits:{max_students:1000,max_teachers:100,max_system_admins:5,max_guardians:2000,max_storage_mb:10240},
    enabled:["id_cards","analytics","timetable","assessment","attendance","governance","certificates","core_records","finance_fees","report_cards","bulk_workflow","manual_backup","notifications","staff_id_cards","finance_exports","financial_holds","academic_history","priority_support","scheduled_backup","school_prospectus","finance_statements","uploaded_templates"],
    disabled:["payroll","integrations","custom_branding","payroll_statutory","advanced_analytics"]
  },
  enterprise:{
    limits:{},
    enabled:["payroll","id_cards","analytics","timetable","assessment","attendance","governance","certificates","core_records","finance_fees","report_cards","bulk_workflow","manual_backup","notifications","staff_id_cards","custom_branding","finance_exports","financial_holds","academic_history","priority_support","scheduled_backup","payroll_statutory","school_prospectus","finance_statements","uploaded_templates"],
    disabled:["integrations","advanced_analytics"]
  }
};

function quotedJsonAfterPlan(code){
  const marker="'"+code+"'";
  const start=sql.indexOf(marker);
  assert.notEqual(start,-1,"missing "+code+" plan");
  const segment=source.slice(start,start+3500);
  const matches=[...segment.matchAll(/'(\{[^']*\})'::jsonb/g)].map(m=>JSON.parse(m[1]));
  assert.ok(matches.length>=2,"expected limits and feature_flags for "+code);
  return {limits:matches[0],flags:matches[1]};
}

test("live Supabase feature catalogue is frozen at 27 entitlements",()=>{
  const codes=[...sql.matchAll(/\('([a-z_]+)','[^']*','[^']*',(true|false),'[^']*',(true|false)\)/g)].map(m=>m[1]).sort();
  assert.deepEqual(codes,expectedCatalog);
});

test("Starter, Professional, and Enterprise reproduce live Supabase revision-6 entitlements",()=>{
  for(const [code,expected] of Object.entries(expectedPlans)){
    const actual=quotedJsonAfterPlan(code);
    assert.deepEqual(actual.limits,expected.limits);
    for(const feature of expected.enabled) assert.equal(actual.flags[feature],true,code+" must enable "+feature);
    for(const feature of expected.disabled) assert.equal(actual.flags[feature],false,code+" must disable "+feature);
    assert.deepEqual(Object.keys(actual.flags).sort(),expectedCatalog);
  }
});

test("inactive future features remain disabled in every commercial plan",()=>{
  for(const code of Object.keys(expectedPlans)){
    const {flags}=quotedJsonAfterPlan(code);
    assert.equal(flags.advanced_analytics,false);
    assert.equal(flags.integrations,false);
  }
});

test("suffix migration preserves certified 0025 production preflight line",()=>{
  assert.match(sql,/values \('0025d_live_plan_feature_parity'\)/);
  assert.match(sql,/set schema_version='0025'/);
});


test("isolated tenant plan data matches the master commercial-plan parity patch",()=>{
  for(const code of Object.keys(expectedPlans)){
    assert.deepEqual(quotedJsonAfterPlan(code,tenantSql),quotedJsonAfterPlan(code,sql),code+" tenant plan must match master");
  }
  const tenantCodes=[...tenantSql.matchAll(/\('([a-z_]+)','[^']*','[^']*',(true|false)\)/g)].map(m=>m[1]).sort();
  assert.deepEqual(tenantCodes,expectedCatalog);
});
