import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const shell=readFileSync(new URL("../frontend/app.js",import.meta.url),"utf8");
const school=readFileSync(new URL("../frontend/tenant-class-teacher-workspace-parity-v1.js",import.meta.url),"utf8");

test("School System Administrator sidebar includes School Calendar immediately after Academics",()=>{
  const match=shell.match(/system_admin:\[([^\]]+)\]/);
  assert.ok(match,"System Administrator navigation must exist");
  const entries=[...match[1].matchAll(/"([^"]+)"/g)].map(x=>x[1]);
  assert.ok(entries.includes("school_calendar"),"Calendar must be included in authorized sidebar order");
  assert.equal(entries.filter(x=>x==="school_calendar").length,1,"Only one calendar navigation entry is allowed");
  assert.equal(entries.indexOf("school_calendar"),entries.indexOf("academics")+1);
});

test("Calendar workspace is registered only for school administrators and has the actual calendar view",()=>{
  assert.match(school,/registerView\(\{id:"school_calendar",label:"School Calendar"/);
  assert.match(school,/roles:\["system_admin"\],feature:"attendance",render:renderSchoolCalendar/);
  assert.match(school,/async function renderSchoolCalendar\(\)/);
  assert.match(school,/certified\("list_school_closures"/);
  assert.match(school,/certified\("save_school_closure"/);
  assert.match(school,/certified\("archive_school_closure"/);
  assert.match(shell,/function orderedNavItems\(\)/);
  assert.match(shell,/return order\.map\(id=>byIdMap\.get\(id\)\)\.filter\(item=>item&&item\.nav!==false&&can\(item\)\)/);
});

test("Calendar is absent from non-administrator sidebar allowlists",()=>{
  const nav=shell.slice(shell.indexOf("const ROLE_NAV_IDS"),shell.indexOf("const LEGACY_LICENSE_FEATURE_FALLBACKS"));
  for(const role of ["principal","class_teacher","subject_teacher","parent_guardian","accountant","accounts_office","student"]){
    const roleLine=nav.split("\n").find(line=>line.trim().startsWith(role+":"));
    assert.ok(roleLine,"Missing role navigation: "+role);
    assert.doesNotMatch(roleLine,/"school_calendar"/,"Calendar should not be advertised to "+role);
  }
});
