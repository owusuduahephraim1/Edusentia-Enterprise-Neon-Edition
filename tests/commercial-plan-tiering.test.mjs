import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const master=fs.readFileSync(new URL("../database/migrations/0025e_commercial_plan_tiering.sql",import.meta.url),"utf8");
const tenant=fs.readFileSync(new URL("../database/reference-compat/0068_commercial_plan_tiering.sql",import.meta.url),"utf8");
const upgradeUi=fs.readFileSync(new URL("../frontend/parity-enterprise-workspaces.js",import.meta.url),"utf8");

const featureCodes=[
  "academic_history","advanced_analytics","analytics","assessment","attendance",
  "bulk_workflow","certificates","core_records","custom_branding","finance_exports",
  "finance_fees","finance_statements","financial_holds","governance","id_cards",
  "integrations","manual_backup","notifications","payroll","payroll_statutory",
  "priority_support","report_cards","scheduled_backup","school_prospectus",
  "staff_id_cards","timetable","uploaded_templates"
].sort();

const expected={
  starter:{
    enabled:["academic_history","analytics","assessment","attendance","core_records","finance_fees","finance_statements","governance","manual_backup","notifications","report_cards","timetable"],
    disabled:["advanced_analytics","bulk_workflow","certificates","custom_branding","finance_exports","financial_holds","id_cards","integrations","payroll","payroll_statutory","priority_support","scheduled_backup","school_prospectus","staff_id_cards","uploaded_templates"]
  },
  professional:{
    enabled:["academic_history","analytics","assessment","attendance","bulk_workflow","certificates","core_records","finance_exports","finance_fees","finance_statements","financial_holds","governance","id_cards","manual_backup","notifications","priority_support","report_cards","scheduled_backup","school_prospectus","staff_id_cards","timetable","uploaded_templates"],
    disabled:["advanced_analytics","custom_branding","integrations","payroll","payroll_statutory"]
  },
  enterprise:{
    enabled:["academic_history","analytics","assessment","attendance","bulk_workflow","certificates","core_records","custom_branding","finance_exports","finance_fees","finance_statements","financial_holds","governance","id_cards","manual_backup","notifications","payroll","payroll_statutory","priority_support","report_cards","scheduled_backup","school_prospectus","staff_id_cards","timetable","uploaded_templates"],
    disabled:["advanced_analytics","integrations"]
  }
};

function planFlags(source,code){
  const marker="where code='"+code+"';";
  const end=source.indexOf(marker);
  assert.notEqual(end,-1,"missing "+code+" update");
  const start=source.lastIndexOf("feature_flags='",end);
  assert.notEqual(start,-1,"missing "+code+" feature flags");
  const jsonStart=start+"feature_flags='".length;
  const jsonEnd=source.indexOf("'::jsonb",jsonStart);
  assert.ok(jsonEnd>jsonStart,"missing "+code+" jsonb terminator");
  return JSON.parse(source.slice(jsonStart,jsonEnd));
}

test("commercial tiering v2 creates meaningful upgrade separation",()=>{
  for(const [code,contract] of Object.entries(expected)){
    const flags=planFlags(master,code);
    assert.deepEqual(Object.keys(flags).sort(),featureCodes);
    for(const name of contract.enabled)assert.equal(flags[name],true,code+" must enable "+name);
    for(const name of contract.disabled)assert.equal(flags[name],false,code+" must disable "+name);
  }
});

test("isolated tenants receive the same commercial tiering contract",()=>{
  for(const code of Object.keys(expected))assert.deepEqual(planFlags(tenant,code),planFlags(master,code));
  assert.match(tenant,/0068_commercial_plan_tiering/);
});

test("starter keeps essential school operations while premium automation is reserved",()=>{
  const flags=planFlags(master,"starter");
  for(const name of ["core_records","assessment","report_cards","attendance","academic_history","timetable","finance_fees","finance_statements","notifications","analytics","governance","manual_backup"])assert.equal(flags[name],true);
  for(const name of ["id_cards","staff_id_cards","certificates","school_prospectus","uploaded_templates","bulk_workflow","scheduled_backup","priority_support","finance_exports","financial_holds","custom_branding","payroll","payroll_statutory"])assert.equal(flags[name],false);
});

test("professional is the document automation and finance-control tier",()=>{
  const flags=planFlags(master,"professional");
  for(const name of ["id_cards","staff_id_cards","certificates","school_prospectus","uploaded_templates","bulk_workflow","scheduled_backup","priority_support","finance_exports","financial_holds"])assert.equal(flags[name],true);
  for(const name of ["custom_branding","payroll","payroll_statutory"])assert.equal(flags[name],false);
});

test("enterprise uniquely adds branding and payroll while future modules stay off",()=>{
  const flags=planFlags(master,"enterprise");
  for(const name of ["custom_branding","payroll","payroll_statutory"])assert.equal(flags[name],true);
  assert.equal(flags.advanced_analytics,false);
  assert.equal(flags.integrations,false);
});

test("upgrade workspace explains the commercial progression",()=>{
  for(const label of ["Up to 300 students","Up to 1,000 students","Unlimited configured capacity","Student and staff ID cards","Finance exports and financial-hold controls","Custom school branding","Payroll and salary history","Advanced Analytics and External Integrations"])assert.ok(upgradeUi.includes(label),label);
});
