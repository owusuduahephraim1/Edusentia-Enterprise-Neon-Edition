import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const shell=fs.readFileSync("frontend/app.js","utf8");
const workspaces=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const index=fs.readFileSync("frontend/index.html","utf8");

test("Student Academic History always has a core sidebar entry even before extension registration",()=>{
  assert.match(shell,/\{id:"history",label:"Student Academic History",icon:"▧"/);
  assert.match(shell,/roles:\["system_admin","principal","class_teacher","subject_teacher"\],feature:"academic_history"/);
  assert.match(shell,/The academic history workspace is not ready\. Refresh the application/);
});

test("the history nav entry remains in authorized role navigation order",()=>{
  for(const role of ["system_admin","principal","class_teacher","subject_teacher"]){
    const pattern=new RegExp(role+':\\[(.*?)\\]','s');
    const found=shell.match(pattern);
    assert.ok(found,role+" ordering missing");
    assert.match(found[1],/"history"/);
  }
  assert.match(shell,/function orderedNavItems\(\)/);
  assert.match(shell,/return order\.map\(id=>byIdMap\.get\(id\)\)\.filter\(item=>item&&item\.nav!==false&&can\(item\)\)/);
});

test("registered full history view upgrades the core fallback and keeps the exact navigation label",()=>{
  assert.match(workspaces,/registerView\(\{id:"history",label:"Student Academic History"/);
  assert.match(workspaces,/render:renderHistory\}/);
  assert.match(shell,/else if\(existing\)Object\.assign\(existing,item\)/);
  assert.match(shell,/else NAV\.push\(item\)/);
  assert.match(shell,/teacherHistoryRenderer\(\):schoolHistoryRenderer\(\)/);
  assert.match(shell,/if\(state\.session\)renderNav\(\)/);
});

test("authorized history page continues to expose official transcript download",()=>{
  assert.match(workspaces,/enterpriseTranscriptOfficialDownload/);
  assert.match(workspaces,/window\.EdusentiaOfficialTranscriptPdf\.render\(issuance,deps\)/);
  assert.match(workspaces,/const verification=obj\(await certified\("verify_transcript"/);
  assert.ok(index.includes('src="official-transcript-pdf.js?v=20261126-history-nav2"'));
});
