import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("certified system qualification list is used throughout teacher and HR entry forms",()=>{
  const app=read("frontend/app.js");
  const teachers=read("frontend/parity-teachers.js");
  const hr=read("frontend/tenant-hr-staff-v1.js");

  assert.match(app,/const SYSTEM_QUALIFICATIONS=Object\.freeze\(\["PhD","MSc Degree","Bachelor Degree","HND","Diploma","SHS"\]\)/);
  assert.match(app,/EdusentiaSystemLists\.qualifications=SYSTEM_QUALIFICATIONS/);
  assert.match(app,/select name="qualification">\$\{qualificationOptions\(\)\}<\/select>/);

  assert.match(teachers,/EdusentiaSystemLists\?\.qualifications/);
  assert.match(teachers,/qualificationOptions\(row\.qualification\)/);
  assert.doesNotMatch(teachers,/\["PhD","MSc Degree","Bachelor Degree","HND","Diploma","SHS"\]\.map/);

  assert.match(hr,/EdusentiaSystemLists\?\.qualifications/);
  assert.match(hr,/select name="qualification">\$\{qualificationOptions\(staff\?\.qualification\|\|""\)\}<\/select>/);
  assert.match(hr,/select name="qualification" required>\$\{qualificationOptions\(\)\}<\/select>/);
  assert.doesNotMatch(hr,/<input name="qualification"/);
});

test("qualification selectors retain existing legacy values without reopening free-text entry",()=>{
  for(const path of ["frontend/app.js","frontend/parity-teachers.js","frontend/tenant-hr-staff-v1.js"]){
    const source=read(path);
    assert.match(source,/legacy&&!options\.includes\(legacy\)\)options\.unshift\(legacy\)/);
    assert.ok(source.includes('?" (legacy)":""'));
  }
});
