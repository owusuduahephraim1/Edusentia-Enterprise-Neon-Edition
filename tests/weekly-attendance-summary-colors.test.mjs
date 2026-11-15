import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const ui=readFileSync(new URL("../frontend/tenant-class-teacher-workspace-parity-v1.js",import.meta.url),"utf8");
const css=readFileSync(new URL("../frontend/style.css",import.meta.url),"utf8");

const categories=[
  ["scheduled","Scheduled teaching days","scheduled_days","#eff6ff","#bfdbfe","#1d4ed8"],
  ["recorded","Days recorded","recorded_days","#f0fdf4","#86efac","#15803d"],
  ["closed","School closure days","closed_days","#faf5ff","#d8b4fe","#7e22ce"],
  ["unrecorded","Unrecorded past days","unrecorded_days","#fffbeb","#fcd34d","#a16207"]
];

test("four weekly attendance cards retain existing numeric sources and semantic labels",()=>{
  for(const [state,label,dataKey] of categories){
    assert.ok(ui.includes('class="attendance-week-total attendance-week-total--'+state+'"'),"Missing "+state+" style hook");
    assert.ok(ui.includes("<span>"+label+"</span>"),"Missing "+label+" label");
    assert.ok(ui.includes("Number(data?."+dataKey+"||0)"),"Changed "+label+" calculation source");
  }
  assert.match(ui,/function loadWeeklyAttendanceHistory/);
  assert.match(ui,/Scheduled days exclude weekends and school holidays/);
});

test("weekly summary label and number colors match the selected category",()=>{
  for(const [state,, ,bg,border,color] of categories){
    const main=".attendance-week-totals > .attendance-week-total--"+state;
    const idx=css.indexOf(main+"{");
    assert.ok(idx>=0,"Missing "+state+" CSS rule");
    const rule=css.slice(idx,css.indexOf("}",idx));
    assert.ok(rule.includes("background:"+bg),state+" background mismatch");
    assert.ok(rule.includes("border-color:"+border),state+" border mismatch");
    const textRule=main+" span,\n"+main+" strong{color:"+color+"}";
    assert.ok(css.includes(textRule),state+" label/value color mismatch");
  }
  assert.match(css,/\.attendance-week-totals\{display:grid;grid-template-columns:repeat\(4,minmax\(0,1fr\)\)/);
});
