(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  // ---------- Timetable ----------
  async function renderTimetable(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Timetable</h3><p>Certified class timetable console with collision and assignment enforcement.</p></div></div>${loading("Loading timetable controls")}`;
    try{
      const config=await academicConfig(),years=Array.isArray(config?.academic_years)?config.academic_years:[],classes=Array.isArray(config?.classes)?config.classes:[];
      byId("content").innerHTML=`<div class="page-head"><div><h3>Timetable</h3><p>Certified class timetable console with collision and assignment enforcement.</p></div></div>
        <section class="panel"><form id="timetableSelector" class="toolbar"><select id="timetableYear" required>${optionRows(years,"id","name")}</select><select id="timetableClass" required>${optionRows(classes,"id","name")}</select><button class="button secondary" type="submit">Load timetable</button></form><div id="timetableResults">${empty("Select an academic year and class.")}</div></section>`;
      byId("timetableSelector").onsubmit=e=>{e.preventDefault();loadTimetable();};
    }catch(error){byId("content").innerHTML=pageError(error);}
  }
  async function loadTimetable(){
    const box=byId("timetableResults"),year=byId("timetableYear")?.value,clazz=byId("timetableClass")?.value;if(!box||!year||!clazz)return;
    box.innerHTML=loading("Loading timetable");
    try{
      const data=await certified("get_class_timetable_console",{target_academic_year_id:year,target_class_id:clazz}),entries=Array.isArray(data?.entries)?data.entries:[];
      box.innerHTML=`<div class="panel-header"><div><h3>${esc(data?.class?.name||"Class")} timetable</h3><p>${esc(data?.academic_year?.name||"Academic year")} • ${entries.length} periods</p></div>${data?.can_manage?'<button id="timetableAdd" class="button primary small" type="button">Add period</button>':""}</div>
        ${entries.length?`<div class="table-wrap"><table><thead><tr><th>Day</th><th>Time</th><th>Subject</th><th>Teacher</th><th>Notes</th>${data?.can_manage?"<th>Actions</th>":""}</tr></thead><tbody>${entries.map(e=>`<tr><td>${esc(e.day_of_week)}</td><td>${esc(String(e.period_start||"").slice(0,5))}–${esc(String(e.period_end||"").slice(0,5))}</td><td>${esc(e.subject_name||"")}</td><td>${esc(e.teacher_name||"")}</td><td>${esc(e.notes||"")}</td>${data?.can_manage?`<td><button class="button secondary small" data-timetable-edit="${esc(e.id)}">Edit</button></td>`:""}</tr>`).join("")}</tbody></table></div>`:empty("No timetable periods have been configured.")}`;
      byId("timetableAdd")?.addEventListener("click",()=>openTimetableEntry(data,null));
      box.querySelectorAll("[data-timetable-edit]").forEach(b=>b.onclick=()=>openTimetableEntry(data,entries.find(x=>x.id===b.dataset.timetableEdit)));
    }catch(error){box.innerHTML=pageError(error);}
  }
  function openTimetableEntry(data,row){
    const subjects=Array.isArray(data?.subjects)?data.subjects:[],teachers=Array.isArray(data?.teachers)?data.teachers:[];
    openModal(row?"Edit timetable period":"Add timetable period","Subject assignment and teacher collision rules are enforced by the database.",`
      <form id="timetableEntryForm" class="form-stack"><input type="hidden" name="id" value="${esc(row?.id||"")}"><input type="hidden" name="updated_at" value="${esc(row?.updated_at||"")}"><div class="form-grid">
        <label class="field"><span>Day</span><select name="day_of_week">${["Monday","Tuesday","Wednesday","Thursday","Friday"].map(v=>`<option ${row?.day_of_week===v?"selected":""}>${v}</option>`).join("")}</select></label>
        <label class="field"><span>Start</span><input type="time" name="period_start" value="${esc(String(row?.period_start||"08:00").slice(0,5))}" required></label>
        <label class="field"><span>End</span><input type="time" name="period_end" value="${esc(String(row?.period_end||"09:00").slice(0,5))}" required></label>
        <label class="field"><span>Subject</span><select id="timetableSubject" name="subject_id" required>${optionRows(subjects,"id","name",row?.subject_id)}</select></label>
        <label class="field"><span>Teacher</span><select id="timetableTeacher" name="teacher_id" required>${optionRows(teachers,"id","name",row?.teacher_id)}</select></label>
        <label class="field full"><span>Notes</span><textarea name="notes">${esc(row?.notes||"")}</textarea></label>
      </div><p id="timetableEntryMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="timetableEntryCancel" class="button ghost" type="button">Cancel</button><button id="timetableEntrySave" class="button primary" type="submit" form="timetableEntryForm">Save period</button>');
    byId("timetableEntryCancel").onclick=closeModal;
    byId("timetableSubject").onchange=()=>{const s=subjects.find(x=>String(x.id)===String(byId("timetableSubject").value));if(s?.assigned_teacher_id)byId("timetableTeacher").value=s.assigned_teacher_id;};
    byId("timetableEntryForm").onsubmit=async e=>{
      e.preventDefault();const button=byId("timetableEntrySave");button.disabled=true;
      try{const v=formValues(e.currentTarget);await certified("save_class_timetable_entry",{payload:{...v,academic_year_id:data.academic_year.id,class_id:data.class.id}});closeModal();await loadTimetable();}
      catch(error){showMessage("timetableEntryMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }

  registerView({id:"timetable",label:"Timetable",icon:"▤",subtitle:"Class timetable and assigned teaching periods",render:renderTimetable});
})();
