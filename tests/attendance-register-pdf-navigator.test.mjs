import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const pdfSource=fs.readFileSync("frontend/tenant-attendance-register-pdf-v1.js","utf8");
const teacherSource=fs.readFileSync("frontend/tenant-class-teacher-workspace-parity-v1.js","utf8");
const principalSource=fs.readFileSync("frontend/tenant-principal-attendance-navigator-v1.js","utf8");
const shell=fs.readFileSync("frontend/app.js","utf8");
const scripts=fs.readFileSync("frontend/index.html","utf8");
const rpc=fs.readFileSync("worker/src/certified-rpc.ts","utf8");
const sql=fs.readFileSync("database/reference-compat/0087_attendance_register_pdf_export.sql","utf8");
const install=fs.readFileSync("database/reference-compat/install-operational-parity.sh","utf8");

const window={};
vm.runInNewContext(pdfSource,{window,Blob,Uint8Array,Date,console,atob});
const lib=window.EdusentiaAttendancePdf;
const sample={
  school:{name:"NIPE INTERNATIONAL SCHOOL",motto:"Knowledge and Discipline"},
  class_name:"Basic 3",term:"Term 1",academic_year:"2026/2027",main_teacher:"Test Main Teacher",
  term_start:"2026-11-16",term_end:"2026-11-27",generated_at:"2026-11-18T12:00:00Z",
  weeks:[
    {week_start:"2026-11-16",week_number:1,start_date:"2026-11-16",end_date:"2026-11-22"},
    {week_start:"2026-11-23",week_number:2,start_date:"2026-11-23",end_date:"2026-11-27"}
  ],
  students:[
    {enrollment_id:"b",name:"Test Boy",admission_no:"NIS-STU-001",gender:"boys"},
    {enrollment_id:"g",name:"Test Girl",admission_no:"NIS-STU-002",gender:"girls"},
    {enrollment_id:"r",name:"Gender Review",admission_no:"NIS-STU-003",gender:"review"}
  ],
  calendar:[
    {date:"2026-11-16",day_status:"recorded"},
    {date:"2026-11-17",day_status:"recorded"},
    {date:"2026-11-18",day_status:"closed"},
    {date:"2026-11-19",day_status:"unrecorded"},
    {date:"2026-11-20",day_status:"upcoming"},
    {date:"2026-11-23",day_status:"recorded"},
    {date:"2026-11-24",day_status:"recorded"},
    {date:"2026-11-25",day_status:"unrecorded"},
    {date:"2026-11-26",day_status:"unrecorded"},
    {date:"2026-11-27",day_status:"unrecorded"}
  ],
  marks:[
    {enrollment_id:"b",date:"2026-11-16",status:"present"},
    {enrollment_id:"b",date:"2026-11-17",status:"late"},
    {enrollment_id:"g",date:"2026-11-16",status:"absent"},
    {enrollment_id:"g",date:"2026-11-17",status:"excused"},
    {enrollment_id:"b",date:"2026-11-23",status:"present"},
    {enrollment_id:"b",date:"2026-11-24",status:"absent"}
  ]
};

test("tally symbols distinguish present, absent, late, excused, closure, unrecorded and future",()=>{
  const records=lib.getRecords(sample,{fromWeek:"2026-11-16",toWeek:"2026-11-23"});
  const boy=sample.students[0],girl=sample.students[1];
  assert.equal(records.symbol(boy,"2026-11-16"),"I");
  assert.equal(records.symbol(girl,"2026-11-16"),"0");
  assert.equal(records.symbol(boy,"2026-11-17"),"I(L)");
  assert.equal(records.symbol(girl,"2026-11-17"),"E");
  assert.equal(records.symbol(boy,"2026-11-18"),"H");
  assert.equal(records.symbol(boy,"2026-11-19"),"U");
  assert.equal(records.symbol(boy,"2026-11-20"),"F");
});

test("weekly and cumulative present count late as one present, but not an excused day",()=>{
  const records=lib.getRecords(sample,{fromWeek:"2026-11-23",toWeek:"2026-11-23"});
  const boy=sample.students[0],girl=sample.students[1];
  assert.deepEqual(JSON.parse(JSON.stringify(records.stats(boy,"2026-11-23","2026-11-27"))),{p:1,a:1,l:0,e:0});
  assert.deepEqual(JSON.parse(JSON.stringify(records.stats(boy,"2026-11-16","2026-11-27"))),{p:3,a:1,l:1,e:0});
  assert.equal(records.rate(boy,"2026-11-27"),"75.0%");
  assert.equal(records.rate(girl,"2026-11-27"),"0.0%");
  assert.equal(records.countDays("2026-11-16","2026-11-27","recorded"),4);
});

test("builds a native vector PDF with separate gender sections, class header and cumulative summary",async()=>{
  const pdf=lib.buildBlob(sample,{fromWeek:"2026-11-16",toWeek:"2026-11-23"});
  assert.equal(pdf.type,"application/pdf");
  const buffer=Buffer.from(await pdf.arrayBuffer());
  assert.equal(buffer.subarray(0,8).toString("latin1"),"%PDF-1.4");
  const body=buffer.toString("latin1");
  for(const item of ["STUDENTS REGISTER ATTENDANCE SUMMARY DETAILS","BOYS ATTENDANCE REGISTER","GIRLS ATTENDANCE REGISTER","GENDER REVIEW REQUIRED","CUMULATIVE ATTENDANCE","NIPE INTERNATIONAL SCHOOL","I\\(L\\)","xref","%%EOF"]){
    assert.ok(body.includes(item),"Missing PDF component "+item);
  }
  const pageCount=(body.match(/\/Type \/Page /g)||[]).length;
  assert.equal(pageCount,3,"Two teaching weeks and one cumulative report should use three pages for this small class");
  const streams=[...body.matchAll(/\/Length \\d+ >>\\nstream\\n([\\s\\S]*?)\\nendstream/g)].map(match=>match[1]);
  assert.equal(streams.length,3);
  assert.match(streams[0],/BOYS ATTENDANCE REGISTER/);
  assert.match(streams[0],/GIRLS ATTENDANCE REGISTER/);
  assert.match(streams[1],/BOYS ATTENDANCE REGISTER/);
  assert.match(streams[1],/GIRLS ATTENDANCE REGISTER/);
  assert.match(streams[2],/BOYS - CUMULATIVE ATTENDANCE/);
  assert.match(streams[2],/GIRLS - CUMULATIVE ATTENDANCE/);
  assert.match(body,/\/BaseFont \/Helvetica-Bold/);
  assert.match(body,/Page 1 of /);
  assert.match(body,/W-P/);
  assert.match(body,/C-P/);
});
test("single-week attendance mirrors the two-page school template without splitting gender groups",async()=>{
  const blob=lib.buildBlob(sample,{fromWeek:"2026-11-16",toWeek:"2026-11-16"});
  const content=Buffer.from(await blob.arrayBuffer()).toString("latin1");
  const streams=[...content.matchAll(/\/Length \d+ >>\nstream\n([\s\S]*?)\nendstream/g)].map(match=>match[1]);
  assert.equal(streams.length,2,"A small class must have one weekly page and one cumulative page");
  assert.ok(streams[0].indexOf("BOYS ATTENDANCE REGISTER")<streams[0].indexOf("GIRLS ATTENDANCE REGISTER"));
  assert.ok(streams[1].indexOf("BOYS - CUMULATIVE ATTENDANCE")<streams[1].indexOf("GIRLS - CUMULATIVE ATTENDANCE"));
  assert.ok(streams[0].includes("NIPE INTERNATIONAL SCHOOL")&&streams[1].includes("NIPE INTERNATIONAL SCHOOL"));
  assert.ok(streams[0].includes("ACADEMIC YEAR: 2026/2027")&&streams[1].includes("ACADEMIC YEAR: 2026/2027"));
  assert.ok(streams[0].includes("Page 1 of 2")&&streams[1].includes("Page 2 of 2"));
  assert.match(streams[0],/16\/11\/2026 - 20\/11\/2026/);
  assert.doesNotMatch(content,/16\/11\/2026 - 22\/11\/2026/);
});
test("large classes continue safely onto additional pages without dropping attendance rows",async()=>{
  const students=Array.from({length:88},(_,i)=>({
    enrollment_id:"batch-"+i,
    gender:i<42?"boys":"girls",
    name:(i<42?"Boy":"Girl")+" Learner Number "+String(i+1).padStart(2,"0"),
    admission_no:"NIS-TEST-"+String(i+1).padStart(3,"0")
  }));
  const blob=lib.buildBlob({...sample,students},{fromWeek:"2026-11-16",toWeek:"2026-11-16"});
  const content=Buffer.from(await blob.arrayBuffer()).toString("latin1");
  const pageCount=(content.match(/\/Type \/Page /g)||[]).length;
  assert.ok(pageCount>2,"Overflow requires additional pages rather than text shrinkage");
  assert.match(content,/Boy Learner Number 01/);
  assert.match(content,/Boy Learner Number 42/);
  assert.match(content,/Girl Learner Number 43/);
  assert.match(content,/Girl Learner Number 88/);
  assert.match(content,/BOYS ATTENDANCE REGISTER/);
  assert.match(content,/GIRLS ATTENDANCE REGISTER/);
  assert.match(content,/BOYS - CUMULATIVE ATTENDANCE/);
  assert.match(content,/GIRLS - CUMULATIVE ATTENDANCE/);
  assert.match(content,/continued/);
});

test("teaching week ranges end on Friday, including legacy Sunday-ended API data",async()=>{
  assert.equal(lib.teachingWeekEnd(sample.weeks[0]),"2026-11-20");
  assert.equal(lib.teachingWeekEnd(sample.weeks[1]),"2026-11-27");
  assert.equal(lib.teachingWeekEnd({week_start:"2026-11-16",end_date:"2026-11-18"}),"2026-11-18");
  const blob=lib.buildBlob(sample,{fromWeek:"2026-11-16",toWeek:"2026-11-16"});
  const content=Buffer.from(await blob.arrayBuffer()).toString("latin1");
  assert.match(content,/16\/11\/2026 - 20\/11\/2026/);
  assert.doesNotMatch(content,/16\/11\/2026 - 22\/11\/2026/);
  assert.match(teacherSource,/days=arr\(data\?\.days\)\.filter\(day=>isTeachingDay\(day\.date\)\)/);
  assert.match(teacherSource,/formatDate\(teachingWeekEnd\(w\.week_start,w\.end_date\)\)/);
  assert.match(principalSource,/const friday=addDays\(d,4\)/);
  assert.match(principalSource,/if\(weekStart<=weekEnd\)out\.push/);
  const css=fs.readFileSync("frontend/style.css","utf8");
  assert.match(css,/\.attendance-week-days\{display:grid;grid-template-columns:repeat\(5,minmax\(0,1fr\)\)/);
});

test("PDF week range validation prevents inverted or unknown week choices",()=>{
  assert.throws(()=>lib.getRecords(sample,{fromWeek:"2026-11-23",toWeek:"2026-11-16"}),/valid start and end week/);
  assert.throws(()=>lib.getRecords(sample,{fromWeek:"2025-01-01",toWeek:"2026-11-23"}),/valid start and end week/);
});

test("role-based navigator and teacher controls are registered and protected",()=>{
  assert.match(shell,/principal:\["dashboard","operations","student_services","staff","history","attendance_navigator","timetable"/);
  assert.match(principalSource,/id:"attendance_navigator",label:"Attendance Navigator"/);
  assert.match(principalSource,/roles:\["principal"\]/);
  assert.match(principalSource,/list_attendance_export_classes/);
  assert.match(principalSource,/get_attendance_register_export/);
  assert.match(teacherSource,/id="attendanceWeekPdf"/);
  assert.match(teacherSource,/id="attendanceTermPdf"/);
  assert.match(teacherSource,/target_through_week_start:allWeeks\?null:a\.weekStart/);
  assert.match(scripts,/tenant-attendance-register-pdf-v1\.js/);
  assert.match(scripts,/tenant-principal-attendance-navigator-v1\.js/);
});

test("Neon worker, tenant migration, and audit log enforce independent role-scoped access",()=>{
  assert.match(rpc,/"list_attendance_export_classes"/);
  assert.match(rpc,/"get_attendance_register_export"/);
  assert.match(rpc,/select public\.get_attendance_register_export/);
  assert.match(sql,/role_name NOT IN \('principal','class_teacher'\)/);
  assert.match(sql,/role_name='class_teacher' AND NOT public\.is_assigned_class_teacher\(target_class_id\)/);
  assert.match(sql,/CREATE TABLE IF NOT EXISTS public\.attendance_export_events/);
  assert.match(sql,/INSERT INTO public\.attendance_export_events/);
  assert.match(sql,/REVOKE ALL ON FUNCTION public\.get_attendance_register_export\(uuid,uuid,date\) FROM PUBLIC/);
  assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.get_attendance_register_export\(uuid,uuid,date\) TO edusentia_worker_runtime/);
  assert.match(install,/0087_attendance_register_pdf_export/);
});
