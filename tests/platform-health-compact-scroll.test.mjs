import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("Platform Health history panels stay compact and internally scrollable",()=>{
  const ui=read("frontend/platform-saas-admin.js");
  const css=read("frontend/platform-saas-admin.css");

  assert.match(ui,/Tenant health history/);
  assert.match(ui,/Permanent deletion jobs/);
  assert.match(ui,/pa-health-grid/);
  assert.equal((ui.match(/pa-panel-body pa-health-scroll/g)||[]).length,2);

  assert.match(css,/\.pa-health-grid\{align-items:start\}/);
  assert.match(css,/\.pa-health-scroll\{[^}]*max-height:250px/);
  assert.match(css,/\.pa-health-scroll\{[^}]*overflow-y:auto/);
  assert.match(css,/scrollbar-gutter:stable/);
  assert.match(css,/overscroll-behavior:contain/);
});
