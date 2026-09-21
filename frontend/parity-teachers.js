(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  // ---------- Teachers ----------
  async function renderTeachers(){
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Teachers</h3><p>Certified teacher lifecycle, account links and photographs.</p></div><div class="page-actions"><button id="teacherAddAdvanced" class="button primary" type="button">Add teacher</button></div></div>
      <section class="panel"><form id="teacherAdvancedFilters" class="toolbar"><label class="search"><input id="teacherAdvancedSearch" type="search" placeholder="Name, staff no., email or phone"></label><select id="teacherAdvancedStatus"><option value="">All statuses</option><option value="active">Active</option><option value="leave">Leave</option><option value="suspended">Suspended</option><option value="resigned">Resigned</option><option value="retired">Retired</option></select><select id="teacherAdvancedArchive"><option value="active">Current</option><option value="archived">Archived</option><option value="all">All</option></select><button class="button secondary">Search</button></form><div id="teacherAdvancedResults">${loading("Loading teachers")}</div></section>`;
    byId("teacherAdvancedFilters").onsubmit=e=>{e.preventDefault();loadAdvancedTeachers();};
    byId("teacherAdvancedStatus").onchange=loadAdvancedTeachers;byId("teacherAdvancedArchive").onchange=loadAdvancedTeachers;
    byId("teacherAddAdvanced").onclick=()=>openTeacherEditor();
    await loadAdvancedTeachers();
  }
  async function loadAdvancedTeachers(){
    const box=byId("teacherAdvancedResults");if(!box)return;box.innerHTML=loading("Loading teachers");
    try{
      const data=await certified("list_teachers",{search_text:byId("teacherAdvancedSearch")?.value?.trim()||"",status_filter:byId("teacherAdvancedStatus")?.value||"",archive_filter:byId("teacherAdvancedArchive")?.value||"active",page_number:1,page_size:100});
      const rows=Array.isArray(data?.rows)?data.rows:[];
      if(!rows.length){box.innerHTML=empty("No teacher records match the selected filters.");return;}
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Teacher</th><th>Staff no.</th><th>Qualification</th><th>Specialization</th><th>Status</th><th>Actions</th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${esc(String(row.first_name||row.full_name||"T").charAt(0))}</span><span class="cell-copy"><strong>${esc(row.full_name||[row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" "))}</strong><small>${esc(row.email||row.profile_email||"No email")}</small></span></div></td><td>${esc(row.staff_no||"—")}</td><td>${esc(row.qualification||"—")}</td><td>${esc(row.specialization||"—")}</td><td>${status(row.deleted_at?"archived":row.employment_status||"active")}</td><td><div class="table-actions">${row.deleted_at?`<button class="button success small" data-teacher-restore="${esc(row.id)}">Restore</button>`:`<button class="button secondary small" data-teacher-edit="${esc(row.id)}">Edit</button><button class="button danger small" data-teacher-archive="${esc(row.id)}">Remove</button>`}</div></td></tr>`).join("")}</tbody></table></div>`;
      box.querySelectorAll("[data-teacher-edit]").forEach(b=>b.onclick=()=>openTeacherEditor(b.dataset.teacherEdit));
      box.querySelectorAll("[data-teacher-archive]").forEach(b=>b.onclick=()=>archiveTeacher(b.dataset.teacherArchive));
      box.querySelectorAll("[data-teacher-restore]").forEach(b=>b.onclick=()=>restoreTeacher(b.dataset.teacherRestore));
    }catch(error){box.innerHTML=pageError(error);}
  }
  async function openTeacherEditor(id=""){
    let row={};
    if(id){const data=await certified("get_teacher_record",{target_teacher_id:id});row=data?.teacher||data||{};}
    openModal(id?"Edit teacher":"Add teacher","Certified teacher record with optimistic-concurrency protection.",`
      <form id="teacherAdvancedForm" class="form-stack"><input type="hidden" name="id" value="${esc(row.id||"")}"><input type="hidden" name="updated_at" value="${esc(row.updated_at||"")}"><div class="form-grid">
        <label class="field"><span>Staff number</span><input name="staff_no" value="${esc(row.staff_no||"")}"></label>
        <label class="field"><span>EMIS code</span><input name="emis_code" value="${esc(row.emis_code||"")}"></label>
        <label class="field"><span>First name</span><input name="first_name" value="${esc(row.first_name||"")}" required></label>
        <label class="field"><span>Middle name</span><input name="middle_name" value="${esc(row.middle_name||"")}"></label>
        <label class="field"><span>Last name</span><input name="last_name" value="${esc(row.last_name||"")}" required></label>
        <label class="field"><span>Gender</span><select name="gender">${["Male","Female","Other"].map(v=>`<option ${String(row.gender||"Other")===v?"selected":""}>${v}</option>`).join("")}</select></label>
        <label class="field"><span>Date of birth</span><input type="date" name="date_of_birth" value="${esc(row.date_of_birth||"")}"></label>
        <label class="field"><span>Date joined</span><input type="date" name="date_joined" value="${esc(row.date_joined||"")}"></label>
        <label class="field"><span>Email</span><input type="email" name="email" value="${esc(row.email||"")}"></label>
        <label class="field"><span>Phone</span><input name="phone" value="${esc(row.phone||"")}"></label>
        <label class="field"><span>Qualification</span><select name="qualification"><option value="">Select</option>${["PhD","MSc Degree","Bachelor Degree","HND","Diploma","SHS"].map(v=>`<option ${row.qualification===v?"selected":""}>${v}</option>`).join("")}</select></label>
        <label class="field"><span>Specialization</span><input name="specialization" value="${esc(row.specialization||"")}"></label>
        <label class="field"><span>Employment status</span><select name="employment_status">${["active","leave","suspended","resigned","retired"].map(v=>`<option value="${v}" ${String(row.employment_status||"active")===v?"selected":""}>${esc(v.replaceAll("_"," "))}</option>`).join("")}</select></label>
        <label class="field"><span>Address</span><input name="address" value="${esc(row.address||"")}"></label>
        <label class="field full"><span>Notes</span><textarea name="notes">${esc(row.notes||"")}</textarea></label>
        <label class="field full"><span>Photograph</span><input id="teacherPhotoAdvanced" type="file" accept="image/jpeg,image/png,image/webp"></label>
      </div><p id="teacherAdvancedMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="teacherAdvancedCancel" class="button ghost" type="button">Cancel</button><button id="teacherAdvancedSave" class="button primary" type="submit" form="teacherAdvancedForm">Save teacher</button>');
    byId("teacherAdvancedCancel").onclick=closeModal;
    byId("teacherAdvancedForm").onsubmit=async e=>{
      e.preventDefault();const button=byId("teacherAdvancedSave");button.disabled=true;
      try{
        const payload=formValues(e.currentTarget);payload.active=true;payload.reason=id?"Teacher record updated from Neon testing workspace":"Teacher record created from Neon testing workspace";
        let saved=await certified("save_teacher",{payload}),teacher=saved?.teacher||saved;
        const file=byId("teacherPhotoAdvanced")?.files?.[0];
        if(file){const uploaded=await api().uploadFile(file,"staff-photos");saved=await certified("set_teacher_photo",{target_teacher_id:teacher.id,target_photo_url:uploaded.objectKey,expected_updated_at:teacher.updated_at||null});}
        closeModal();await loadAdvancedTeachers();
      }catch(error){showMessage("teacherAdvancedMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }
  async function archiveTeacher(id){if(!confirm("Remove this teacher from active records?"))return;try{await certified("archive_teacher",{target_teacher_id:id,reason_text:"Teacher removed from active records"});await loadAdvancedTeachers();}catch(error){alert(friendly(error));}}
  async function restoreTeacher(id){try{await certified("restore_teacher",{target_teacher_id:id,reason_text:"Teacher restored to active records"});await loadAdvancedTeachers();}catch(error){alert(friendly(error));}}

  registerView({id:"teachers",label:"Teachers",icon:"♜",subtitle:"Certified teacher lifecycle and photographs",roles:["system_admin"],render:renderTeachers});
})();
