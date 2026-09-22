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
      <div class="page-head"><div><h3>Students</h3><p>Certified student directory, enrolment and bulk admission tools.</p></div>
        <div class="page-actions">${isSystemAdmin()?'<button id="studentImportButton" class="button secondary" type="button">Import CSV</button><button id="promotionCutoffButton" class="button ghost" type="button">Promotion cutoff</button>':""}${canManage?'<button id="studentAddButton" class="button primary" type="button">Add student</button>':""}</div></div>
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
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Student</th><th>Admission no.</th><th>Class</th><th>Academic year</th><th>Roll no.</th><th>Status</th></tr></thead><tbody>
        ${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${esc(String(row.first_name||row.last_name||"S").charAt(0).toUpperCase())}</span><span class="cell-copy"><strong>${esc([row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" "))}</strong><small>${esc(row.gender||"—")} • ${formatDate(row.date_of_birth)}</small></span></div></td><td>${esc(row.admission_no||"—")}</td><td>${esc(row.class_name||"—")}</td><td>${esc(row.academic_year_name||"—")}</td><td>${esc(row.roll_number||"—")}</td><td>${status(row.archived?"archived":row.status)}</td></tr>`).join("")}
      </tbody></table></div>`;
    }catch(error){box.innerHTML=pageError(error);}
  }

  async function openStudentEditor(ctx){
    let admission="";
    try{const generated=await certified("generate_school_identifier",{identifier_kind:"student"});admission=String(generated?.identifier||generated?.admission_no||generated||"");}catch{}
    openModal("Add student","Create a certified student and optional current enrolment.",`
      <form id="studentCertifiedForm" class="form-stack"><div class="form-grid">
        <label class="field"><span>Admission number</span><input name="admission_no" value="${esc(admission)}" required></label>
        <label class="field"><span>First name</span><input name="first_name" required></label>
        <label class="field"><span>Middle name</span><input name="middle_name"></label>
        <label class="field"><span>Last name</span><input name="last_name" required></label>
        <label class="field"><span>Gender</span><select name="gender"><option>Male</option><option>Female</option><option>Other</option></select></label>
        <label class="field"><span>Date of birth</span><input type="date" name="date_of_birth"></label>
        <label class="field"><span>Status</span><select name="status"><option value="active">Active</option><option value="suspended">Suspended</option><option value="withdrawn">Withdrawn</option><option value="graduated">Graduated</option></select></label>
        <label class="field"><span>Academic year</span><select name="academic_year_id">${optionRows(ctx.years,"id","name","","No enrolment")}</select></label>
        <label class="field"><span>Class</span><select name="class_id">${optionRows(ctx.classes,"id","name","","No enrolment")}</select></label>
        <label class="field"><span>Roll number</span><input type="number" min="1" name="roll_number"></label>
        <label class="field"><span>Guardian full name</span><input name="guardian_name"></label>
        <label class="field"><span>Guardian phone</span><input name="guardian_phone"></label>
        <label class="field"><span>Guardian email</span><input type="email" name="guardian_email"></label>
      </div><p id="studentCertifiedMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="studentCertifiedCancel" class="button ghost" type="button">Cancel</button><button id="studentCertifiedSave" class="button primary" type="submit" form="studentCertifiedForm">Save student</button>');
    byId("studentCertifiedCancel").onclick=closeModal;
    byId("studentCertifiedForm").onsubmit=async e=>{
      e.preventDefault();const button=byId("studentCertifiedSave"),msg=byId("studentCertifiedMessage");button.disabled=true;msg.classList.add("hidden");
      try{
        const v=formValues(e.currentTarget);
        if(Boolean(v.academic_year_id)!==Boolean(v.class_id))throw new Error("Academic year and class must be selected together.");
        const payload={
          student:{id:"",updated_at:"",admission_no:String(v.admission_no||"").trim(),first_name:String(v.first_name||"").trim(),middle_name:String(v.middle_name||"").trim(),last_name:String(v.last_name||"").trim(),gender:v.gender,date_of_birth:v.date_of_birth||"",status:v.status||"active",photo_url:""},
          enrollment:v.academic_year_id&&v.class_id?{academic_year_id:v.academic_year_id,class_id:v.class_id,roll_number:v.roll_number||"",active:true}:{},
          guardian:{id:"",full_name:String(v.guardian_name||"").trim(),relationship:"Guardian",phone:String(v.guardian_phone||"").trim(),email:String(v.guardian_email||"").trim(),address:"",auth_user_id:"",is_primary:true,can_view_reports:true,can_receive_notifications:true},
          reason:"Student registered from Neon testing workspace"
        };
        await certified("save_student",{payload});closeModal();await loadCertifiedStudents();
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
