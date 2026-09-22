(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  // ---------- Students ----------
  async function renderStudents(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Students</h3><p>Certified student directory, enrolment and bulk admission tools.</p></div></div>${loading("Loading certified student workspace")}`;
    let config;
    try{config=await academicConfig();}catch(error){byId("content").innerHTML=pageError(error);return;}
    const classes=Array.isArray(config?.classes)?config.classes:[],years=Array.isArray(config?.academic_years)?config.academic_years:[];
    const canManage=isSystemAdmin()||["principal","academic_admin","records_officer"].includes(currentRole());
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Student Directory</h3><p>Secure student, guardian, and enrolment records</p></div>
        <div class="page-actions">${isSystemAdmin()?'<button id="studentImportButton" class="button outline" type="button">Import CSV</button><button id="studentExportButton" class="button outline" type="button">Export CSV</button><button id="promotionCutoffButton" class="button ghost" type="button">Promotion cutoff</button>':""}${canManage?'<button id="studentAddButton" class="button primary" type="button">Add student</button>':""}</div></div>
      <section class="panel">
        <form id="studentFilters" class="toolbar">
          <label class="search"><span class="sr-only">Search students</span><input id="studentSearchCertified" type="search" placeholder="Name or admission number"></label>
          <select id="studentClassFilter"><option value="">All classes</option>${classes.map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join("")}</select>
          <select id="studentStatusFilter"><option value="">All statuses</option><option value="active">Active</option><option value="graduated">Graduated</option><option value="withdrawn">Withdrawn</option><option value="suspended">Suspended</option></select>
          ${["system_admin","principal"].includes(currentRole())?'<select id="studentArchiveFilter"><option value="active">Current</option><option value="archived">Archived</option><option value="all">All</option></select>':""}
          <button class="button secondary" type="submit">Search</button>
        </form>
        <div id="studentCertifiedResults">${loading("Loading students")}</div>
      </section>`;
    byId("studentFilters")?.addEventListener("submit",e=>{e.preventDefault();loadCertifiedStudents();});
    byId("studentClassFilter")?.addEventListener("change",()=>loadCertifiedStudents());
    byId("studentStatusFilter")?.addEventListener("change",()=>loadCertifiedStudents());
    byId("studentArchiveFilter")?.addEventListener("change",()=>loadCertifiedStudents());
    byId("studentAddButton")?.addEventListener("click",()=>openStudentEditor({config,years,classes}));
    byId("studentImportButton")?.addEventListener("click",()=>openStudentImport({years,classes}));
    byId("studentExportButton")?.addEventListener("click",exportStudentsCsv);
    byId("promotionCutoffButton")?.addEventListener("click",openPromotionCutoff);
    await loadCertifiedStudents();
  }

  async function loadCertifiedStudents(){
    const box=byId("studentCertifiedResults");if(!box)return;
    box.innerHTML=loading("Loading students");
    try{
      const data=await certified("search_students_v5",{
        search_text:byId("studentSearchCertified")?.value?.trim()||"",
        target_class_id:byId("studentClassFilter")?.value||null,
        target_status:byId("studentStatusFilter")?.value||null,
        archive_filter:byId("studentArchiveFilter")?.value||"active",
        page_number:1,page_size:100
      });
      const rows=Array.isArray(data?.rows)?data.rows:[];
      if(!rows.length){box.innerHTML=empty("No student records match the selected filters.");return;}
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Student</th><th>Admission no.</th><th>Class</th><th>Academic year</th><th>Roll no.</th><th>Status</th><th>Actions</th></tr></thead><tbody>
        ${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${esc(String(row.first_name||row.last_name||"S").charAt(0).toUpperCase())}</span><span class="cell-copy"><strong>${esc([row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" "))}</strong><small>${esc(row.gender||"—")} • ${formatDate(row.date_of_birth)}</small></span></div></td><td>${esc(row.admission_no||"—")}</td><td>${esc(row.class_name||"—")}</td><td>${esc(row.academic_year_name||"—")}</td><td>${esc(row.roll_number||"—")}</td><td>${status(row.archived?"archived":row.status)}</td><td><div class="table-actions"><button class="button ghost small" data-student-view="${esc(row.id)}">View</button>${canManage&&!row.archived?`<button class="button secondary small" data-student-edit="${esc(row.id)}">Edit</button>`:""}${isSystemAdmin()&&!row.archived?`<button class="button danger small" data-student-archive="${esc(row.id)}">Remove</button>`:""}${isSystemAdmin()&&row.archived?`<button class="button success small" data-student-restore="${esc(row.id)}">Restore</button>`:""}</div></td></tr>`).join("")}
      </tbody></table></div>`;
      box.querySelectorAll("[data-student-view]").forEach(b=>b.onclick=()=>openStudentRecord(b.dataset.studentView));
      box.querySelectorAll("[data-student-edit]").forEach(b=>b.onclick=async()=>{const config=await academicConfig();openStudentEditor({config,years:config?.academic_years||[],classes:config?.classes||[]},b.dataset.studentEdit);});
      box.querySelectorAll("[data-student-archive]").forEach(b=>b.onclick=()=>archiveStudent(b.dataset.studentArchive));
      box.querySelectorAll("[data-student-restore]").forEach(b=>b.onclick=()=>restoreStudent(b.dataset.studentRestore));
    }catch(error){box.innerHTML=pageError(error);}
  }

  async function openStudentRecord(id){
    try{
      const data=await certified("get_student_record_v5",{target_student_id:id}),student=data?.student||{},enrolments=Array.isArray(data?.enrollments)?data.enrollments:[],guardians=Array.isArray(data?.guardians)?data.guardians:[],reports=Array.isArray(data?.reports)?data.reports:[];
      openModal([student.first_name,student.middle_name,student.last_name].filter(Boolean).join(" ")||"Student",student.admission_no||"",`
        <div class="grid two"><section class="panel pad"><div class="cell-main"><span class="avatar large">${esc(String(student.first_name||student.last_name||"S").charAt(0).toUpperCase())}</span><div class="cell-copy"><strong>${esc([student.first_name,student.middle_name,student.last_name].filter(Boolean).join(" "))}</strong><small>${esc(student.gender||"—")} • ${formatDate(student.date_of_birth)}</small><small>${status(student.archived?"archived":student.status)}</small></div></div><div class="hr"></div><div class="section-title"><h4>Guardians</h4></div>${guardians.length?guardians.map(g=>'<div class="metric"><strong>'+esc(g.full_name||"Guardian")+'</strong><span>'+esc(g.relationship||"Guardian")+' • '+esc(g.phone||"No phone")+' • '+esc(g.email||"No email")+'</span></div>').join(""):'<p class="help-text">No guardian record</p>'}</section>
        <section class="panel pad"><div class="section-title"><h4>Enrolment History</h4></div>${enrolments.length?enrolments.map(e=>'<div class="diff-row"><span>'+esc(e.academic_year_name||"")+' • '+esc(e.class_name||"")+'</span><b>'+(e.active?"Active":"Closed")+'</b></div>').join(""):'<p class="help-text">No enrolment record</p>'}<div class="hr"></div><div class="section-title"><h4>Report Cards</h4></div>${reports.length?reports.slice(0,10).map(r=>'<div class="diff-row"><span>'+esc(r.term_name||r.report_number||"Report")+'</span><b>'+esc(String(r.status||"draft").replaceAll("_"," "))+'</b></div>').join(""):'<p class="help-text">No report cards</p>'}</section></div>`,
        '<button id="studentRecordClose" class="button ghost" type="button">Close</button>'+(student.archived?'':'<button id="studentRecordEdit" class="button primary" type="button">Edit student</button>'));
      byId("studentRecordClose").onclick=closeModal;
      byId("studentRecordEdit")?.addEventListener("click",async()=>{closeModal();const config=await academicConfig();openStudentEditor({config,years:config?.academic_years||[],classes:config?.classes||[]},id);});
    }catch(error){alert(friendly(error));}
  }
  async function archiveStudent(id){
    if(!confirm("Remove this student from the current directory? Historical records and reports remain preserved."))return;
    try{await certified("archive_student",{target_student_id:id,reason_text:"Student removed from active records"});await loadCertifiedStudents();}catch(error){alert(friendly(error));}
  }
  async function restoreStudent(id){
    if(!confirm("Restore this student to the current directory?"))return;
    try{await certified("restore_student",{target_student_id:id,reason_text:"Student restored to active records"});await loadCertifiedStudents();}catch(error){alert(friendly(error));}
  }
  async function exportStudentsCsv(){
    try{
      const data=await certified("search_students_v5",{search_text:byId("studentSearchCertified")?.value?.trim()||"",target_class_id:byId("studentClassFilter")?.value||null,target_status:byId("studentStatusFilter")?.value||null,archive_filter:byId("studentArchiveFilter")?.value||"active",page_number:1,page_size:500});
      const rows=Array.isArray(data?.rows)?data.rows:[],cell=v=>'"'+String(v??"").replaceAll('"','""')+'"',lines=[["admission_no","full_name","gender","date_of_birth","class","academic_year","roll_number","status"].join(",")];
      rows.forEach(r=>lines.push([r.admission_no,[r.first_name,r.middle_name,r.last_name].filter(Boolean).join(" "),r.gender,r.date_of_birth,r.class_name,r.academic_year_name,r.roll_number,r.archived?"archived":r.status].map(cell).join(",")));
      downloadBlob("student-directory.csv",new Blob([lines.join("\n")],{type:"text/csv;charset=utf-8"}));
    }catch(error){alert(friendly(error));}
  }
  async function openStudentEditor(ctx,id=""){
    let record={student:{status:"active",gender:"Male"},enrollments:[],guardians:[]};
    if(id)record=await certified("get_student_record_v5",{target_student_id:id});
    let guardians=[];try{guardians=await certified("list_guardian_portal_accounts",{search_text:""});}catch{}
    const student=record.student||{},latest=record.enrollments?.[0]||{},guardian=record.guardians?.find(g=>g.is_primary)||record.guardians?.[0]||{};
    let admission=student.admission_no||"";
    if(!id&&!admission){try{const generated=await certified("generate_school_identifier",{identifier_kind:"student"});admission=String(generated?.identifier||generated?.admission_no||generated||"");}catch{}}
    openModal(id?"Edit Student":"Add Student",id?admission:"Create a certified student, guardian, and optional current enrolment.",`
      <form id="studentCertifiedForm" class="form-stack"><input type="hidden" name="id" value="${esc(student.id||"")}"><input type="hidden" name="updated_at" value="${esc(student.updated_at||"")}"><div class="form-grid three">
        <label class="field"><span>Admission number</span><input name="admission_no" value="${esc(admission)}" ${id?"readonly":""} required></label>
        <label class="field"><span>First name</span><input name="first_name" value="${esc(student.first_name||"")}" required></label>
        <label class="field"><span>Middle name</span><input name="middle_name" value="${esc(student.middle_name||"")}"></label>
        <label class="field"><span>Last name</span><input name="last_name" value="${esc(student.last_name||"")}" required></label>
        <label class="field"><span>Gender</span><select name="gender">${["Male","Female","Other"].map(v=>'<option '+(v===student.gender?"selected":"")+'>'+v+'</option>').join("")}</select></label>
        <label class="field"><span>Date of birth</span><input type="date" name="date_of_birth" value="${esc(String(student.date_of_birth||"").slice(0,10))}"></label>
        <label class="field"><span>Status</span><select name="status">${["active","graduated","withdrawn","suspended"].map(v=>'<option value="'+v+'" '+(v===student.status?"selected":"")+'>'+v.replaceAll("_"," ")+'</option>').join("")}</select></label>
        <label class="field"><span>Academic year</span><select name="academic_year_id">${optionRows(ctx.years,"id","name",latest.academic_year_id||"","No enrolment")}</select></label>
        <label class="field"><span>Class</span><select name="class_id">${optionRows(ctx.classes,"id","name",latest.class_id||"","No enrolment")}</select></label>
        <label class="field"><span>Roll number</span><input type="number" min="1" name="roll_number" value="${esc(latest.roll_number||"")}"></label>
        <label class="field full"><span>Student photograph</span><input id="studentPhotoFile" type="file" accept="image/jpeg,image/png,image/webp"><small>JPEG, PNG or WebP. The file is stored in the school’s dedicated R2 space.</small></label>
      </div><div class="section-title"><h4>Primary Guardian</h4></div><div class="form-grid three"><input type="hidden" name="guardian_id" value="${esc(guardian.id||"")}">
        <label class="field"><span>Full name</span><input name="guardian_name" value="${esc(guardian.full_name||student.guardian_name||"")}"></label>
        <label class="field"><span>Relationship</span><input name="relationship" value="${esc(guardian.relationship||"Guardian")}"></label>
        <label class="field"><span>Telephone</span><input name="guardian_phone" value="${esc(guardian.phone||student.guardian_phone||"")}"></label>
        <label class="field"><span>Email</span><input type="email" name="guardian_email" value="${esc(guardian.email||student.guardian_email||"")}"></label>
        <label class="field"><span>Portal account</span><select name="guardian_auth_user_id"><option value="">No linked account</option>${(Array.isArray(guardians)?guardians:[]).map(item=>'<option value="'+esc(item.id||"")+'" '+(String(item.id||"")===String(guardian.auth_user_id||"")?"selected":"")+'>'+esc(item.full_name||item.email||"Guardian")+(item.email?" • "+esc(item.email):"")+'</option>').join("")}</select></label>
        <label class="field"><span>Address</span><input name="guardian_address" value="${esc(guardian.address||"")}"></label>
        <label class="check-field"><input type="checkbox" name="guardian_notify" ${guardian.can_receive_notifications!==false?"checked":""}><span>Receive notifications</span></label>
      </div><p id="studentCertifiedMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="studentCertifiedCancel" class="button ghost" type="button">Cancel</button><button id="studentCertifiedSave" class="button primary" type="submit" form="studentCertifiedForm">Save student</button>');
    byId("studentCertifiedCancel").onclick=closeModal;
    byId("studentCertifiedForm").onsubmit=async e=>{
      e.preventDefault();const button=byId("studentCertifiedSave");button.disabled=true;
      try{
        const v=formValues(e.currentTarget);if(Boolean(v.academic_year_id)!==Boolean(v.class_id))throw new Error("Academic year and class must be selected together.");
        const payload={student:{id:v.id||"",updated_at:v.updated_at||"",admission_no:String(v.admission_no||"").trim(),first_name:String(v.first_name||"").trim(),middle_name:String(v.middle_name||"").trim(),last_name:String(v.last_name||"").trim(),gender:v.gender,date_of_birth:v.date_of_birth||"",status:v.status||"active",photo_url:student.photo_url||""},enrollment:v.academic_year_id&&v.class_id?{academic_year_id:v.academic_year_id,class_id:v.class_id,roll_number:v.roll_number||"",active:true}:{},guardian:{id:v.guardian_id||"",full_name:String(v.guardian_name||"").trim(),relationship:String(v.relationship||"Guardian").trim(),phone:String(v.guardian_phone||"").trim(),email:String(v.guardian_email||"").trim(),address:String(v.guardian_address||"").trim(),auth_user_id:v.guardian_auth_user_id||"",is_primary:true,can_view_reports:true,can_receive_notifications:e.currentTarget.elements.guardian_notify.checked},reason:id?"Student record updated":"Student registered"};
        let saved=await certified("save_student",{payload}),file=byId("studentPhotoFile")?.files?.[0];
        if(file){const uploaded=await api().uploadFile(file,"student-photos");saved=await certified("set_student_photo",{target_student_id:saved?.student?.id||student.id,target_photo_url:uploaded.objectKey,expected_updated_at:saved?.student?.updated_at||null});}
        closeModal();await loadCertifiedStudents();
      }catch(error){showMessage("studentCertifiedMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }

  function openStudentImport(ctx){
    openModal("Import students","CSV headers should include admission_no, first_name, last_name and gender.",`
      <form id="studentImportForm" class="form-stack"><div class="form-grid">
        <label class="field"><span>Academic year</span><select name="academic_year_id" required>${optionRows(ctx.years,"id","name")}</select></label>
        <label class="field"><span>Class</span><select name="class_id" required>${optionRows(ctx.classes,"id","name")}</select></label>
        <label class="field full"><span>CSV file</span><input name="file" type="file" accept=".csv,text/csv" required></label>
      </div><div id="studentImportPreview" class="muted">Validate the file before importing.</div><p id="studentImportMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="studentImportCancel" class="button ghost" type="button">Cancel</button><button id="studentImportValidate" class="button secondary" type="button">Validate</button><button id="studentImportRun" class="button primary" type="button" disabled>Import valid rows</button>');
    let validation=null,fileName="";
    byId("studentImportCancel").onclick=closeModal;
    byId("studentImportValidate").onclick=async()=>{
      const form=byId("studentImportForm"),file=form.elements.file.files?.[0],button=byId("studentImportValidate");showMessage("studentImportMessage","");
      if(!file){showMessage("studentImportMessage","Select a CSV file.");return;}
      button.disabled=true;
      try{
        const v=formValues(form),rows=csvParse(await file.text());
        validation=await certified("validate_student_import",{rows,target_academic_year_id:v.academic_year_id,target_class_id:v.class_id,filename:file.name});
        fileName=file.name;
        byId("studentImportPreview").innerHTML=`<div class="detail-grid"><div><span>Total rows</span><strong>${esc(validation.total||0)}</strong></div><div><span>Valid</span><strong>${esc(validation.valid_count||0)}</strong></div><div><span>Invalid</span><strong>${esc(validation.invalid_count||0)}</strong></div></div>${validation.invalid_count?`<p class="muted">${esc((validation.errors||[]).slice(0,5).map(x=>`Row ${x.row_number}: ${x.message}`).join(" • "))}</p>`:""}`;
        byId("studentImportRun").disabled=!Number(validation.valid_count||0);
      }catch(error){showMessage("studentImportMessage",friendly(error));}
      finally{button.disabled=false;}
    };
    byId("studentImportRun").onclick=async()=>{
      const button=byId("studentImportRun");if(!validation?.valid_count)return;button.disabled=true;
      try{await certified("bulk_import_students",{rows:validation.valid_rows,filename:fileName});closeModal();await loadCertifiedStudents();}
      catch(error){showMessage("studentImportMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }

  function openPromotionCutoff(){
    openModal("Promotion cutoff","Set the Term 3 automatic promotion threshold. Certified rules allow 40–60%.",`
      <form id="promotionCutoffForm" class="form-stack"><label class="field"><span>Promotion cutoff (%)</span><input name="score" type="number" min="40" max="60" step="1" value="50" required></label><p id="promotionCutoffMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="promotionCutoffCancel" class="button ghost" type="button">Cancel</button><button id="promotionCutoffSave" class="button primary" type="submit" form="promotionCutoffForm">Save cutoff</button>');
    byId("promotionCutoffCancel").onclick=closeModal;
    byId("promotionCutoffForm").onsubmit=async e=>{
      e.preventDefault();const button=byId("promotionCutoffSave");button.disabled=true;
      try{const result=await certified("save_promotion_cutoff",{target_score:Number(formValues(e.currentTarget).score)});showMessage("promotionCutoffMessage",`Saved. ${Number(result?.reports_recalculated||0)} reports recalculated.`,"success");}
      catch(error){showMessage("promotionCutoffMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }

  registerView({id:"students",label:"Students",icon:"◉",subtitle:"Student records and enrolment",roles:["system_admin","class_teacher","subject_teacher"],render:renderStudents});
})();
