import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("assessment component numeric inputs match the Supabase blueprint step semantics",()=>{
  const academics=read("frontend/parity-academics.js");
  assert.match(academics,/data-key="maximum_score" type="number" min="\.01" step="\.01"/);
  assert.match(academics,/data-key="weight" type="number" min="\.001" max="100" step="\.001"/);
  assert.match(academics,/data-key="required" type="checkbox"/);
  assert.match(academics,/input\.type==="checkbox"\?input\.checked:input\.type==="number"/);
  assert.doesNotThrow(()=>new Function(academics));
});

test("50 is aligned to both assessment input step grids",()=>{
  const aligned=(value,min,step)=>{
    const quotient=(value-min)/step;
    return Math.abs(quotient-Math.round(quotient))<1e-9;
  };
  assert.equal(aligned(50,0.01,0.01),true);
  assert.equal(aligned(50,0.001,0.001),true);
});

test("Neon save_assessment_scheme keeps the certified Supabase total-weight tolerance and safe update order",()=>{
  const sql=read("database/reference-compat/0037_certified_academic_configuration_mutations.sql");
  assert.match(sql,/if abs\(weight_total-100\)>0\.01 then raise exception 'Assessment component weights must total 100'/);
  assert.match(sql,/Apply decreases first so the weight guard never sees an intermediate total above 100/);
  assert.match(sql,/Finish existing component updates, including increases, after all reductions and removals/);
});

test("assessment input fix is cache-busted for deployed tenants",()=>{
  const sw=read("frontend/service-worker.js");
  assert.match(sw,/edusentia-neon-v32/);
  assert.ok(sw.includes("./parity-academics.js"));
});
