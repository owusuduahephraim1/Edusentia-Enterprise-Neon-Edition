import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const attendance=readFileSync(new URL("../frontend/tenant-class-teacher-workspace-parity-v1.js",import.meta.url),"utf8");
const css=readFileSync(new URL("../frontend/style.css",import.meta.url),"utf8");

const statuses=["present","absent","late","excused","unmarked"];
const tones={
  present:{background:"#dcfce7",foreground:"#166534"},
  absent:{background:"#fee2e2",foreground:"#991b1b"},
  late:{background:"#fef3c7",foreground:"#92400e"},
  excused:{background:"#f3e8ff",foreground:"#6b21a8"},
  unmarked:{background:"#e2e8f0",foreground:"#475569"},
};

test("all five attendance counts retain labels and dedicated status styling",()=>{
  for(const status of statuses){
    assert.match(attendance,new RegExp('data-attendance-state="'+status+'"'));
    assert.match(attendance,new RegExp('id="attendanceCount-'+status+'"'));
    const start=css.indexOf('.attendance-live-summary .attendance-summary-chip[data-attendance-state="'+status+'"]');
    assert.ok(start>=0,"Missing "+status+" colour rule");
    const rule=css.slice(start,css.indexOf("}",start));
    assert.ok(rule.includes(tones[status].background),status+" background");
    assert.ok(rule.includes(tones[status].foreground),status+" text contrast");
  }
});

test("selection dropdown colour tracks the currently marked attendance",()=>{
  assert.match(attendance,/select\.dataset\.status=state/);
  assert.match(attendance,/counts\[state\]\+\+/);
  assert.match(attendance,/data-attendance-enrollment/);
  assert.match(attendance,/updateAttendanceSummary\(\)/);
  for(const status of statuses){
    assert.ok(css.includes('.attendance-desktop-table .attendance-status-select[data-status="'+status+'"]'));
  }
});

test("mobile status options keep text labels and Present uses green when selected",()=>{
  for(const status of statuses.slice(0,4)){
    assert.ok(attendance.includes('["'+status+'","'+status.charAt(0).toUpperCase()+status.slice(1)+'"]'));
  }
  assert.match(css,/\.attendance-status-button\[data-status="present"\]\.active/);
  assert.match(css,/font-variant-numeric:tabular-nums/);
  assert.match(css,/\.attendance-summary-chip::before/);
});
