(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  // ---------- Reports ----------
  async function renderReports(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Reports</h3><p>Certified assessment, workflow and official R2 PDF workspace.</p></div></div>${loading("Loading report workspace")}`;
    try{
      const [config,students]=await Promise.all([
        academicConfig(),
        certified("search_students_v5",{search_text:"",target_class_id:null,target_status:"active",archive_filter:"active",page_number:1,page_size:100})
      ]);
      const terms=Array.isArray(config?.terms)?config.terms:[],rows=Array.isArray(students?.rows)?students.rows:[];
      byId("content").innerHTML=`<div class="page-head"><div><h3>Reports</h3><p>Certified assessment, workflow and official R2 PDF workspace.</p></div></div>
        <section class="panel"><form id="reportOpenForm" class="toolbar"><select id="reportStudentEnrollment" required><option value="">Select student / current enrolment</option>${rows.filter(x=>x.enrollment_id).map(x=>`<option value="${esc(x.enrollment_id)}" data-year="${esc(x.academic_year_id||"")}">${esc([x.first_name,x.middle_name,x.last_name].filter(Boolean).join(" "))} • ${esc(x.class_name||"No class")}</option>`).join("")}</select><select id="reportTerm" required>${optionRows(terms,"id","name")}</select><button class="button primary" type="submit">Open report</button></form><div id="reportWorkspace">${rows.length?empty("Select a student and term to open or create a report."):empty("No enrolled students are available yet.")}</div></section>`;
      const filterTerms=()=>{const opt=byId("reportStudentEnrollment")?.selectedOptions?.[0],year=opt?.dataset?.year||"";byId("reportTerm").innerHTML=optionRows(terms.filter(t=>!year||String(t.academic_year_id)===String(year)),"id","name");};
      byId("reportStudentEnrollment").onchange=filterTerms;
      byId("reportOpenForm").onsubmit=async e=>{e.preventDefault();await openReportEditor(null,byId("reportStudentEnrollment").value,byId("reportTerm").value);};
    }catch(error){byId("content").innerHTML=pageError(error);}
  }
  async function openReportEditor(reportId,enrollmentId,termId){
    const box=byId("reportWorkspace");if(box)box.innerHTML=loading("Opening report");
    try{
      const editor=await certified("get_report_editor",{target_report_id:reportId,target_enrollment_id:enrollmentId,target_term_id:termId});
      renderReportEditor(editor);
    }catch(error){if(box)box.innerHTML=pageError(error);}
  }
  function renderReportEditor(editor){
    const box=byId("reportWorkspace");if(!box)return;
    const report=editor?.report||{},student=editor?.student||{},subjects=Array.isArray(editor?.subjects)?editor.subjects:[],publication=(editor?.publications||[]).find(p=>!p.revoked_at);
    box.innerHTML=`<div class="panel-header"><div><h3>${esc(student.full_name||"Student report")}</h3><p>${esc(student.admission_no||"")} • ${esc(student.class_name||"")} • ${esc(student.term_name||"")} • ${status(report.status||"draft")}</p></div><div class="page-actions">${report.id?'<button id="reportRefresh" class="button ghost small" type="button">Refresh</button>':""}${publication?'<button id="reportPdfDownload" class="button secondary small" type="button">Download PDF</button>':""}${report.id&&report.status==="published"?'<button id="reportPdfUpload" class="button secondary small" type="button">Upload official PDF</button>':""}</div></div>
      <div class="panel-body"><form id="reportEditorForm" class="form-stack"><div class="form-grid">
        <label class="field"><span>Days school opened</span><input name="days_school_opened" type="number" min="0" value="${esc(report.days_school_opened||0)}" ${editor.can_edit_fields?"":"disabled"}></label>
        <label class="field"><span>Days present</span><input name="days_present" type="number" min="0" value="${esc(report.days_present||0)}" ${editor.can_edit_fields?"":"disabled"}></label>
        <label class="field"><span>Attitude</span><input name="attitude" value="${esc(report.attitude||"")}" ${editor.can_edit_fields?"":"disabled"}></label>
        <label class="field"><span>Conduct</span><input name="conduct" value="${esc(report.conduct||"")}" ${editor.can_edit_fields?"":"disabled"}></label>
        <label class="field full"><span>Interest / talent</span><input name="interest" value="${esc(report.interest||"")}" ${editor.can_edit_fields?"":"disabled"}></label>
        <label class="field full"><span>Class teacher comment</span><textarea name="teacher_comment" ${editor.can_edit_fields?"":"disabled"}>${esc(report.teacher_comment||"")}</textarea></label>
        <label class="field full"><span>Principal comment</span><textarea name="head_comment" ${editor.can_edit_fields?"":"disabled"}>${esc(report.head_comment||"")}</textarea></label>
      </div>
      <div class="section-title"><h4>Subject results</h4><span class="chip">${subjects.length} subjects</span></div>
      <div class="table-wrap"><table><thead><tr><th>Subject</th><th>Components</th><th>Total</th><th>Grade</th><th>Initials</th></tr></thead><tbody>${subjects.map((s,i)=>`<tr><td><strong>${esc(s.subject_name||"")}</strong><br><small>${esc(s.subject_code||"")}</small></td><td>${(s.components||[]).map(c=>`<label class="chip">${esc(c.code||c.name)} <input class="score-input" data-report-subject="${i}" data-component-id="${esc(c.component_id)}" type="number" min="0" max="${esc(c.maximum_score)}" step=".01" value="${esc(c.raw_score||0)}" ${s.can_score?"":"disabled"}></label>`).join("")}</td><td>${esc(s.total_score||0)}</td><td>${esc(s.grade||"—")}</td><td><input class="score-input" data-report-initials="${i}" value="${esc(s.teacher_initials||"")}" ${s.can_score?"":"disabled"}></td></tr>`).join("")}</tbody></table></div>
      <div class="page-actions">${editor.can_edit?'<button id="reportSaveAdvanced" class="button primary" type="submit">Save report</button>':""}${(editor.allowed_transitions||[]).map(t=>`<button class="button secondary report-transition" type="button" data-transition="${esc(t)}">${esc(String(t).replaceAll("_"," "))}</button>`).join("")}${report.id&&["draft","returned"].includes(report.status||"")?'<button id="reportDeleteDraft" class="button danger" type="button">Delete draft</button>':""}</div><p id="reportEditorMessage" class="form-message hidden" role="alert"></p></form></div>
      ${report.id?`<section class="panel pad"><h4>Workflow history</h4><div class="timeline">${(editor.workflow||[]).slice(0,10).map(w=>`<div class="timeline-item"><span class="timeline-dot"></span><div class="timeline-copy"><strong>${esc(w.to_status||w.action||"Update")}</strong><small>${formatDateTime(w.created_at)}${w.comment?` • ${esc(w.comment)}`:""}</small></div></div>`).join("")||'<p class="muted">No workflow events.</p>'}</div></section>`:""}`;
    const collect=()=>{
      const v=formValues(byId("reportEditorForm"));
      const scored=subjects.filter(s=>s.can_score).map(s=>({subject_id:s.subject_id,scheme_id:s.scheme_id,teacher_initials:byId("reportWorkspace").querySelector(`[data-report-initials="${subjects.indexOf(s)}"]`)?.value?.trim()||"",components:(s.components||[]).map(c=>({component_id:c.component_id,raw_score:Number(byId("reportWorkspace").querySelector(`[data-report-subject="${subjects.indexOf(s)}"][data-component-id="${c.component_id}"]`)?.value||0)}))}));
      return {report_id:report.id||null,enrollment_id:report.enrollment_id,term_id:report.term_id,fields:editor.can_edit_fields?{days_school_opened:Number(v.days_school_opened||0),days_present:Number(v.days_present||0),attitude:v.attitude||"",conduct:v.conduct||"",interest:v.interest||"",teacher_comment:v.teacher_comment||"",head_comment:v.head_comment||"",promoted_to_class_id:report.promoted_to_class_id||null}:{},subjects:scored,reason:"Report assessment updated from Neon testing workspace"};
    };
    byId("reportEditorForm").onsubmit=async e=>{e.preventDefault();const button=byId("reportSaveAdvanced");if(button)button.disabled=true;try{const saved=await certified("save_report_card",{payload:collect(),expected_version:Number(report.version||0)});renderReportEditor(saved);}catch(error){showMessage("reportEditorMessage",friendly(error));}finally{if(button)button.disabled=false;}};
    box.querySelectorAll(".report-transition").forEach(button=>button.onclick=async()=>{button.disabled=true;try{const updated=await certified("transition_report_status",{target_report_id:report.id,target_status:button.dataset.transition,comment_text:"Workflow transition from Neon testing workspace",expected_version:Number(report.version||0)});renderReportEditor(updated);}catch(error){showMessage("reportEditorMessage",friendly(error));}finally{button.disabled=false;}});
    byId("reportRefresh")?.addEventListener("click",()=>openReportEditor(report.id,null,null));
    byId("reportDeleteDraft")?.addEventListener("click",async()=>{if(!confirm("Permanently delete this never-approved draft report?"))return;try{await certified("delete_report_card_permanently",{target_report_id:report.id,reason_text:"Draft report deleted from Neon testing workspace"});byId("reportWorkspace").innerHTML=empty("Draft report deleted.");}catch(error){showMessage("reportEditorMessage",friendly(error));}});
    byId("reportPdfDownload")?.addEventListener("click",async()=>{try{downloadBlob(`${safeName(report.report_number||"report")}.pdf`,await api().downloadReportPdf(report.id));}catch(error){showMessage("reportEditorMessage",friendly(error));}});
    byId("reportPdfUpload")?.addEventListener("click",()=>openReportPdfUpload(report,editor));
  }
  function openReportPdfUpload(report,editor){
    openModal("Upload official report PDF",report.report_number||"Published report",`<form id="reportPdfForm" class="form-stack"><label class="field"><span>PDF file</span><input id="reportPdfFile" type="file" accept="application/pdf" required></label><p id="reportPdfMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="reportPdfCancel" class="button ghost" type="button">Cancel</button><button id="reportPdfSave" class="button primary" type="submit" form="reportPdfForm">Upload and register</button>');
    byId("reportPdfCancel").onclick=closeModal;
    byId("reportPdfForm").onsubmit=async e=>{e.preventDefault();const file=byId("reportPdfFile").files?.[0],button=byId("reportPdfSave");if(!file)return;button.disabled=true;let objectKey="";try{const uploaded=await api().uploadReportPdf(report.id,file);objectKey=uploaded.objectKey;await certified("register_report_pdf",{target_report_id:report.id,target_storage_path:objectKey,target_checksum:await sha256(file),target_page_count:1});closeModal();await openReportEditor(report.id,null,null);}catch(error){if(objectKey)await api().deleteReportPdfObject(report.id,objectKey).catch(()=>{});showMessage("reportPdfMessage",friendly(error));}finally{button.disabled=false;}};
  }

  registerView({id:"reports",label:"Report Cards",icon:"▤",subtitle:"Assessment, approval, and publication",hideFor:["parent_guardian"],feature:"report_cards",render:renderReports});
})();
