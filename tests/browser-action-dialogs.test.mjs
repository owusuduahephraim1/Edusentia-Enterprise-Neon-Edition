import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("tenant shell provides in-app action dialogs and notifications",()=>{
  const html=read("frontend/index.html");
  const app=read("frontend/app.js");
  assert.match(html,/id="toastStack"/);
  assert.match(app,/window\.EdusentiaConfirm=confirmAction/);
  assert.match(app,/window\.EdusentiaPrompt=promptAction/);
  assert.match(app,/window\.EdusentiaNotify=notifyAction/);
  assert.match(app,/window\.alert=messageText=>notifyAction/);
});

test("loaded tenant scripts do not depend on native confirm dialogs",()=>{
  const html=read("frontend/index.html");
  const scripts=[...html.matchAll(/<script[^>]+src=["']([^"']+\.js)(?:\?[^"']*)?["']/g)]
    .map(m=>m[1].replace(/^\.\//,""))
    .filter(src=>!/^https?:/i.test(src));
  for(const src of scripts){
    const source=read("frontend/"+src);
    assert.doesNotMatch(source,/\b(?:window\.)?confirm\s*\(/,src+" must not rely on native confirm()");
  }
});

test("class and student removal surface visible outcomes",()=>{
  const academics=read("frontend/parity-academics.js");
  const students=read("frontend/parity-students.js");
  assert.match(academics,/EdusentiaConfirm/);
  assert.match(academics,/Record not removed/);
  assert.match(students,/EdusentiaConfirm/);
  assert.match(students,/Student not removed/);
  assert.match(students,/EdusentiaNotify\("Student removed"/);
});
