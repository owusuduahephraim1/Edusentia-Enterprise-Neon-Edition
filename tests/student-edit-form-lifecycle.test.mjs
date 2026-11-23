import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const ui = fs.readFileSync("frontend/parity-students.js", "utf8");

function studentSubmitHandler(context) {
  const anchor = "studentForm.onsubmit=async e=>{";
  const index = ui.indexOf(anchor);
  assert.ok(index >= 0, "Student editor save handler must exist");
  const start = index + "studentForm.onsubmit=".length;
  const end = ui.indexOf("\n    };", start);
  assert.ok(end > start, "Student editor save handler must end before the next function");
  const body = ui.slice(start, end + "\n    }".length);
  assert.doesNotMatch(body, /e\.currentTarget/, "Async student saves must never access a transient event.currentTarget");
  return vm.runInNewContext("(" + body + ")", context);
}

test("existing student save completes after event.currentTarget expires during permission check", async () => {
  const studentId = "student-17";
  const file = {name:"updated-photo.jpg", size:1024, type:"image/jpeg"};
  const button = {disabled:false};
  const form = {elements:{guardian_notify:{checked:false}}};
  const event = {currentTarget:form, preventDefault(){}};
  const calls = [];
  const failures = [];
  let closed = 0;
  let reloaded = 0;

  const values = {
    id:studentId, updated_at:"2026-11-23T10:00:00Z",
    admission_no:"NIS000001-STU-BS031", first_name:"Test", middle_name:"",
    last_name:"Student", gender:"Female", date_of_birth:"",
    status:"active", academic_year_id:"year-1", class_id:"basic-5",
    roll_number:"", guardian_id:"", guardian_name:"", relationship:"Guardian",
    guardian_phone:"", guardian_email:"", guardian_address:"",
    guardian_auth_user_id:""
  };
  const context = {
    id:studentId,
    student:{id:studentId, admission_no:values.admission_no, photo_url:studentId+"/previous.jpg"},
    studentForm:form, teacherEdit:false, localPhotoPreview:"",
    byId:key=>key==="studentCertifiedSave"?button:key==="studentPhotoFile"?{files:[file]}:null,
    formValues:given=>{assert.equal(given,form);return values;},
    canEditStudent:async target=>{
      assert.equal(target,studentId);
      // Browser event.currentTarget is reset when dispatch ends while the
      // awaited permission request is pending.
      event.currentTarget = null;
      return true;
    },
    certified:async (method,payload)=>{
      calls.push({method,payload});
      if(method==="save_student") return {student:{id:studentId,updated_at:"2026-11-23T10:02:00Z"}};
      if(method==="set_student_photo") return {student:{id:studentId,photo_url:payload.target_photo_url}};
      throw new Error("Unexpected operation: "+method);
    },
    api:()=>({uploadFile:async (selected,kind,options)=>{
      calls.push({method:"uploadFile",selected,kind,options});
      return {referencePath:studentId+"/updated.jpg"};
    }}),
    URL:{revokeObjectURL:()=>{}},
    closeModal:()=>{closed++;},
    loadCertifiedStudents:async()=>{reloaded++;},
    showMessage:(key,message)=>failures.push({key,message}),
    friendly:error=>String(error.message||error)
  };

  await studentSubmitHandler(context)(event);

  assert.deepEqual(calls.map(c=>c.method),["save_student","uploadFile","set_student_photo"]);
  assert.equal(calls[0].payload.guardian.can_receive_notifications,false);
  assert.equal(calls[0].payload.student.admission_no,values.admission_no);
  assert.equal(calls[0].payload.student.id,studentId);
  assert.deepEqual(calls[1].options,{subfolder:studentId});
  assert.equal(calls[2].payload.target_student_id,studentId);
  assert.equal(calls[2].payload.target_photo_url,studentId+"/updated.jpg");
  assert.equal(calls[2].payload.expected_updated_at,"2026-11-23T10:02:00Z");
  assert.equal(failures.length,0);
  assert.equal(button.disabled,false);
  assert.equal(closed,1);
  assert.equal(reloaded,1);
});

test("failed permission check blocks writes and keeps the edit dialog open", async () => {
  const failures = [];
  const button = {disabled:false};
  const form = {elements:{guardian_notify:{checked:true}}};
  const event = {currentTarget:form,preventDefault(){}};
  const context = {
    id:"student-17",student:{id:"student-17",admission_no:"NIS000001-STU-BS031"},
    studentForm:form, teacherEdit:false,localPhotoPreview:"",
    byId:key=>key==="studentCertifiedSave"?button:null,
    formValues:()=>({id:"student-17",academic_year_id:"year-1",class_id:"class-1"}),
    canEditStudent:async()=>{event.currentTarget=null;return false;},
    certified:async()=>{throw new Error("Unauthorized write attempted");},
    api:()=>({}),
    friendly:e=>e.message,
    showMessage:(key,message)=>failures.push({key,message}),
    closeModal:()=>{throw new Error("Should remain open");},
    loadCertifiedStudents:()=>{throw new Error("Should not reload");}
  };
  await studentSubmitHandler(context)(event);
  assert.equal(button.disabled,false);
  assert.equal(failures.length,1);
  assert.match(failures[0].message,/not assigned/i);
});
