import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const shell=fs.readFileSync("frontend/app.js","utf8");
const adminWorkspace=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const teacherWorkspace=fs.readFileSync("frontend/tenant-class-teacher-workspace-parity-v1.js","utf8");
const html=fs.readFileSync("frontend/index.html","utf8");
const worker=fs.readFileSync("frontend/service-worker.js","utf8");

function actualRegistry(){
  const start=shell.indexOf("  function registerView(item){");
  const end=shell.indexOf("\n\n  window.EdusentiaShell=",start);
  assert.ok(start>=0&&end>start,"core registration function not found");
  let currentRole="system_admin";
  const NAV=[{id:"history",label:"Student Academic History",feature:"academic_history",
    roles:["system_admin","principal","class_teacher","subject_teacher"],render:()=> "safe fallback"}];
  let navUpdates=0;
  const scope={NAV,state:{session:{id:"qa-session"}},renderNav:()=>navUpdates++,role:()=>currentRole};
  const registerView=vm.runInNewContext(shell.slice(start,end)+"\nregisterView",scope);
  const setRole=r=>{currentRole=r;};
  return {NAV,registerView,setRole,navUpdates:()=>navUpdates};
}

test("teacher's later history registration no longer removes administrator or Principal access",()=>{
  const x=actualRegistry();
  x.registerView({id:"history",label:"Student Academic History",
    roles:["system_admin","principal","class_teacher","subject_teacher"],
    feature:"academic_history",render:()=> "official issuer history"});
  x.registerView({id:"history",label:"Academic History",
    roles:["class_teacher","subject_teacher"],feature:"academic_history",render:()=> "teacher scoped history"});
  assert.equal(x.NAV.filter(item=>item.id==="history").length,1,"no duplicate sidebar entries");
  const item=x.NAV[0];
  assert.equal(item.label,"Student Academic History");
  for(const role of ["system_admin","principal","class_teacher","subject_teacher"])
    assert.ok(Array.from(item.roles).includes(role),role+" must retain history navigation");
  for(const role of ["system_admin","principal"]){
    x.setRole(role);
    assert.equal(item.render(),"official issuer history",role+" must retain the official transcript issuer/download view");
  }
  for(const role of ["class_teacher","subject_teacher"]){
    x.setRole(role);
    assert.equal(item.render(),"teacher scoped history",role+" must retain scoped academic history");
  }
  assert.ok(x.navUpdates()>=2,"authenticated navigation is refreshed after registration");
});

test("teacher module still registers scoped read-only history and primary module the issuing workflow",()=>{
  assert.match(teacherWorkspace,/registerView\(\{id:"history",label:"Academic History"[^;]*roles:\["class_teacher","subject_teacher"\]/);
  assert.match(adminWorkspace,/registerView\(\{id:"history",label:"Student Academic History"/);
  assert.match(adminWorkspace,/enterpriseTranscriptOfficialDownload/);
  assert.match(teacherWorkspace,/async function renderTeacherHistory\(\)/);
});

test("fresh production app shell URL carries the role collision correction",()=>{
  assert.match(html,/src="app\.js\?v=20261126-history-nav3"/);
  assert.match(worker,/\.\/app\.js\?v=20261126-history-nav3/);
  assert.match(shell,/teacherHistoryRenderer\(\):schoolHistoryRenderer\(\)/);
});
