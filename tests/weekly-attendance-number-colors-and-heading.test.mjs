import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const ui=readFileSync(new URL("../frontend/tenant-class-teacher-workspace-parity-v1.js",import.meta.url),"utf8");
const css=readFileSync(new URL("../frontend/style.css",import.meta.url),"utf8");

test("weekly attendance ratio uses distinct present and recorded-day values",()=>{
  assert.match(ui,/attendance-week-ratio/);
  assert.match(ui,/attendance-week-value--present/);
  assert.match(ui,/attendance-week-value--recorded/);
  assert.match(ui,/aria-label=".* recorded school days/);
  assert.match(ui,/Number\(st\.days_present\|\|0\)/);
  assert.match(ui,/Number\(data\?\.recorded_days\|\|0\)/);
  assert.match(ui,/attendance-week-ratio-divider/);
});

test("weekly absence, late and excused values retain their meaning and styling",()=>{
  for (const [state,color] of [
    ["present","#1d4ed8"],["recorded","#15803d"],["absent","#b91c1c"],
    ["late","#a16207"],["excused","#7e22ce"]
  ]){
    assert.match(ui,new RegExp("attendance-week-value--"+state));
    assert.match(css,new RegExp("attendance-week-value--"+state+"\\{color:"+color+"\\}"));
  }
  for (const name of ["absent","late","excused"]){
    assert.match(ui,new RegExp("Number\\(st\\."+name+"\\|\\|0\\)"));
  }
});

test("weekly heading uses selected week's term-clipped dates, not absent top-level date fields",()=>{
  assert.match(ui,/const selectedWeek=weeks\.find\(w=>String\(w\.week_start\)===String\(a\.weekStart\)\)/);
  assert.match(ui,/selectedWeek\?\.start_date\|\|days\[0\]\?\.date\|\|data\?\.week_start/);
  assert.match(ui,/selectedWeek\?\.end_date\|\|days\[days\.length-1\]\?\.date\|\|data\?\.week_end/);
  assert.match(ui,/formatDate\(displayedWeekStart\)/);
  assert.match(ui,/formatDate\(displayedWeekEnd\)/);
  assert.doesNotMatch(ui,/formatDate\(data\?\.start_date\)/);
  assert.doesNotMatch(ui,/formatDate\(data\?\.end_date\)/);
});
