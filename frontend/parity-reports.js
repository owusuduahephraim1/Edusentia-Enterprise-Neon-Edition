(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,certifiedAllRows,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  const shellState=()=>window.EdusentiaShell?.state||{};

  // ---------- Report-card student-photo parity ----------
  const reportStudentPhotoUrls=new Map();
  function reportStudentInitials(student={}){
    const words=String(student.full_name||[student.first_name,student.middle_name,student.last_name].filter(Boolean).join(" ")||"Student").trim().split(/\s+/).filter(Boolean);
    return ((words[0]?.[0]||"S")+(words.length>1?(words.at(-1)?.[0]||""):"")).toUpperCase();
  }
  async function reportStudentPhotoUrl(student={}){
    const id=String(student.id||"").trim(),path=String(student.photo_url||"").trim();
    if(!id||!path)return "";
    const key=id+"|"+path;
    if(reportStudentPhotoUrls.has(key))return reportStudentPhotoUrls.get(key);
    const blob=await api().downloadStudentPhoto(id,path);
    const url=URL.createObjectURL(blob);
    reportStudentPhotoUrls.set(key,url);
    return url;
  }
  async function hydrateReportStudentPhoto(student={}){
    const img=byId("reportStudentPhoto");if(!img||!student.photo_url)return;
    try{img.src=await reportStudentPhotoUrl(student);img.onload=()=>img.parentElement?.classList.add("loaded");}
    catch(error){console.warn("report_student_photo_display_failed",error);}
  }
  function blobDataUrl(blob){
    return new Promise((resolve,reject)=>{
      const reader=new FileReader();
      reader.onload=()=>resolve(String(reader.result||""));
      reader.onerror=()=>reject(reader.error||new Error("The photograph could not be prepared for printing."));
      reader.readAsDataURL(blob);
    });
  }
  async function reportStudentPhotoDataUrl(student={}){
    const id=String(student.id||"").trim(),path=String(student.photo_url||"").trim();
    if(!id||!path)return "";
    try{return await blobDataUrl(await api().downloadStudentPhoto(id,path));}
    catch(error){console.warn("report_student_photo_print_failed",error);return "";}
  }
  function printableReportHtml(editor,photoData=""){
    const report=editor?.report||{},student=editor?.student||{},subjects=Array.isArray(editor?.subjects)?editor.subjects:[],school=window.EdusentiaShell?.state?.boot?.tenant||window.EdusentiaShell?.state?.boot?.school||{};
    const studentName=student.full_name||[student.first_name,student.middle_name,student.last_name].filter(Boolean).join(" ")||"Student";
    const reportNumber=report.report_number||"";
    const subjectRows=subjects.map((subject,index)=>`<tr><td>${index+1}</td><td>${esc(subject.subject_name||subject.name||"Subject")}</td><td>${esc(subject.total_score??"")}</td><td>${esc(subject.grade||"")}</td><td>${esc(subject.remark||"")}</td></tr>`).join("");
    const photo=photoData
      ?`<img src="${photoData}" alt="Student photograph">`
      :'<span>STUDENT<br>PHOTO</span>';
    const average=subjects.length?(subjects.reduce((sum,item)=>sum+Number(item.total_score||0),0)/subjects.length).toFixed(1):"";
    return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(reportNumber||studentName)} Report Card</title><style>
      @page{size:A4;margin:10mm}*{box-sizing:border-box}body{margin:0;color:#17233b;font:10.5pt Arial,Helvetica,sans-serif;background:#fff}.actions{margin:0 0 12px}.actions button{padding:9px 14px;border:0;border-radius:7px;background:#123a79;color:#fff;font-weight:700;cursor:pointer}.sheet{max-width:190mm;margin:auto;border:1px solid #cbd5e1}.head{min-height:37mm;background:#123a79;color:#fff;padding:8mm 7mm;display:grid;grid-template-columns:1fr 31mm;gap:7mm;align-items:center}.school h1{font-size:18pt;margin:0 0 3px;text-transform:uppercase}.school h2{font-size:11pt;margin:0;font-weight:600}.photo{height:34mm;width:28mm;border:2px solid rgba(255,255,255,.9);background:#fff;color:#64748b;display:flex;align-items:center;justify-content:center;text-align:center;font-size:8pt;overflow:hidden}.photo img{width:100%;height:100%;object-fit:cover;object-position:center 20%}.body{padding:6mm}.meta{display:grid;grid-template-columns:2fr 1fr 1fr;gap:3mm 5mm;margin-bottom:5mm}.meta div{border-bottom:1px solid #94a3b8;padding:2mm 0}.meta b{display:block;font-size:7.8pt;text-transform:uppercase;color:#64748b;margin-bottom:1mm}table{width:100%;border-collapse:collapse;margin:3mm 0 5mm}th,td{border:1px solid #94a3b8;padding:2.2mm 2mm}th{background:#eef4fb;text-transform:uppercase;font-size:8pt;text-align:left}td:nth-child(1),td:nth-child(3),td:nth-child(4){text-align:center}.summary{display:grid;grid-template-columns:repeat(3,1fr);gap:3mm;margin:4mm 0}.summary div,.comments section{border:1px solid #cbd5e1;padding:3mm}.summary b{display:block;font-size:8pt;color:#64748b;text-transform:uppercase}.summary strong{font-size:13pt}.comments{display:grid;grid-template-columns:1fr 1fr;gap:4mm}.comments section{min-height:28mm}.comments h3{font-size:9pt;margin:0 0 2mm;text-transform:uppercase;color:#123a79}.footer{margin-top:5mm;border-top:1px solid #cbd5e1;padding-top:3mm;display:flex;justify-content:space-between;color:#64748b;font-size:8pt}@media print{.actions{display:none}.sheet{border:0;max-width:none}}</style></head><body>
      <div class="actions"><button onclick="window.print()">Print / Save as PDF</button></div>
      <article class="sheet"><header class="head"><div class="school"><h1>${esc(school.name||"School")}</h1><h2>Student Terminal Report</h2></div><div class="photo">${photo}</div></header><main class="body">
      <section class="meta"><div><b>Student</b>${esc(studentName)}</div><div><b>Admission No.</b>${esc(student.admission_no||"—")}</div><div><b>Report No.</b>${esc(reportNumber||"—")}</div><div><b>Class</b>${esc(student.class_name||"—")}</div><div><b>Academic Year</b>${esc(student.academic_year_name||"—")}</div><div><b>Term</b>${esc(student.term_name||"—")}</div></section>
      <table><thead><tr><th>#</th><th>Subject</th><th>Total</th><th>Grade</th><th>Remark</th></tr></thead><tbody>${subjectRows||'<tr><td colspan="5">No subject results available.</td></tr>'}</tbody></table>
      <section class="summary"><div><b>Average</b><strong>${average?average+"%":"—"}</strong></div><div><b>Days present</b><strong>${esc(report.days_present??"—")}</strong></div><div><b>Days school opened</b><strong>${esc(report.days_school_opened??"—")}</strong></div></section>
      <section class="comments"><section><h3>Class Teacher Comment</h3>${esc(report.teacher_comment||"")}</section><section><h3>Principal Comment</h3>${esc(report.head_comment||"")}</section><section><h3>Conduct</h3>${esc(report.conduct||"")}</section><section><h3>Attitude / Interest</h3>${esc([report.attitude,report.interest].filter(Boolean).join(" • "))}</section></section>
      <footer class="footer"><span>Status: ${esc(String(report.status||"draft").replaceAll("_"," "))}</span><span>Generated from the current protected school record</span></footer>
      </main></article></body></html>`;
  }
  async function openPrintableReport(editor){
    const popup=window.open("","_blank");
    if(!popup){window.EdusentiaNotify?.("Report preview blocked","Allow pop-ups for this school workspace and try again.","warning");return;}
    popup.document.write("<!doctype html><title>Preparing report</title><p style='font:16px Arial;padding:30px'>Preparing the latest report and protected student photograph…</p>");
    try{
      const reportId=editor?.report?.id;
      const current=reportId?await certified("get_report_editor",{target_report_id:reportId,target_enrollment_id:null,target_term_id:null}):editor;
      const photoData=await reportStudentPhotoDataUrl(current?.student||{});
      popup.document.open();popup.document.write(printableReportHtml(current,photoData));popup.document.close();
    }catch(error){
      popup.close();
      showMessage("reportEditorMessage",friendly(error));
    }
  }

  // ---------- Reports ----------
  let reportConfig=null,reportPage=1;
  async function renderReports(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Report Cards</h3><p>Transactional assessment, review, approval, and publication</p></div></div>${loading("Loading report cards")}`;
    try{
      reportConfig=await academicConfig();
      const terms=Array.isArray(reportConfig?.terms)?reportConfig.terms:[],classes=Array.isArray(reportConfig?.classes)?reportConfig.classes:[],activeTerm=terms.find(x=>x.is_active)?.id||"",requestedClass=classes.some(x=>String(x.id)===String(shellState().reportClassFilter||""))?String(shellState().reportClassFilter):"";
      if(!requestedClass)shellState().reportClassFilter="";
      byId("content").innerHTML=`
        <div class="page-head"><div><h3>Report Cards</h3><p>Transactional assessment, review, approval, and publication</p></div>
          <div class="page-actions">${isSystemAdmin()?'<button id="reportTemplate" class="button outline" type="button">Manage template</button>':currentRole()==="principal"?'<button id="reportManualTemplate" class="button outline" type="button">Manual template</button>':""}<button id="reportExport" class="button outline" type="button">Export list</button>${currentRole()==="principal"?'<button id="reportBulkApprove" class="button success" type="button">Approve class reports</button>':'<button id="reportBulkDownload" class="button secondary" type="button">Bulk class PDFs</button>'}${["system_admin","class_teacher"].includes(currentRole())?'<button id="reportBulkPublish" class="button success" type="button">Publish class reports</button>':""}${["system_admin","class_teacher","subject_teacher"].includes(currentRole())?'<button id="reportNew" class="button primary" type="button">New report</button>':""}</div></div>
        <section class="panel"><div class="toolbar"><label class="search"><input id="reportSearch" type="search" placeholder="Search student or report number"></label><select id="reportTerm"><option value="">All terms</option>${terms.map(x=>`<option value="${esc(x.id)}" ${String(x.id)===String(activeTerm)?"selected":""}>${esc(x.name)}</option>`).join("")}</select><select id="reportClass"><option value="">${["class_teacher","subject_teacher"].includes(currentRole())?"All assigned classes":"All classes"}</option>${classes.map(x=>`<option value="${esc(x.id)}" ${String(x.id)===String(requestedClass)?"selected":""}>${esc(x.name)}</option>`).join("")}</select><select id="reportStatus"><option value="">All statuses</option>${["draft","submitted","class_reviewed","approved","published","returned","withdrawn"].map(v=>`<option value="${v}">${esc(v.replaceAll("_"," "))}</option>`).join("")}</select></div><div id="reportResults">${loading("Loading report cards")}</div></section>
        <section class="panel" id="reportWorkspace" style="margin-top:18px">${empty("Select a report card to open the assessment workspace.")}</section>`;
      byId("reportTemplate")?.addEventListener("click",()=>window.EdusentiaShell?.navigate?.("settings"));
      byId("reportManualTemplate")?.addEventListener("click",openManualReportTemplate);
      byId("reportExport").onclick=exportReportList;
      byId("reportBulkDownload")?.addEventListener("click",bulkDownloadPublishedReports);
      byId("reportBulkApprove")?.addEventListener("click",()=>bulkTransitionReports("approved"));
      byId("reportBulkPublish")?.addEventListener("click",()=>bulkTransitionReports("published"));
      byId("reportNew")?.addEventListener("click",openNewReportPicker);
      let timer;byId("reportSearch").oninput=()=>{clearTimeout(timer);timer=setTimeout(()=>{reportPage=1;loadReportList();},250);};
      ["reportTerm","reportStatus"].forEach(id=>byId(id).onchange=()=>{reportPage=1;loadReportList();});byId("reportClass").onchange=()=>{reportPage=1;shellState().reportClassFilter=byId("reportClass").value;loadReportList();};
      await loadReportList();
      const pendingReportId=String(shellState().pendingReportId||""),pendingEnrollmentId=String(shellState().pendingReportEnrollmentId||"");
      delete shellState().pendingReportId;delete shellState().pendingReportEnrollmentId;
      if(pendingReportId)await openReportEditor(pendingReportId,null,null);
      else if(pendingEnrollmentId)await openNewReportPicker(pendingEnrollmentId);
    }catch(error){byId("content").innerHTML=pageError(error);}
  }
  async function loadReportList(){
    const box=byId("reportResults");if(!box)return;box.innerHTML=loading("Loading report cards");
    try{
      const data=await certified("list_report_cards_v6",{target_term_id:byId("reportTerm")?.value||null,target_class_id:byId("reportClass")?.value||null,target_status:byId("reportStatus")?.value||null,search_text:byId("reportSearch")?.value?.trim()||"",archive_filter:"active",page_number:reportPage,page_size:50}),rows=Array.isArray(data?.rows)?data.rows:[],total=Number(data?.total??rows.length),start=total?(reportPage-1)*50+1:0,end=Math.min(reportPage*50,total);
      box.innerHTML=(rows.length?`<div class="table-wrap"><table><thead><tr><th>Student</th><th>Class</th><th>Term</th><th>Average</th><th>Status</th><th>Updated</th><th></th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-copy"><strong>${esc(row.student_name||"Student")}</strong><small>${esc(row.report_number||row.admission_no||"")}</small></div></td><td>${esc(row.class_name||"—")}</td><td>${esc(row.term_name||"—")}</td><td><strong>${Number(row.average||0).toFixed(1)}%</strong></td><td>${status(row.status||"draft")}</td><td>${formatDateTime(row.updated_at)}</td><td><button class="button secondary small" data-report-open="${esc(row.id)}">Open</button>${["draft","returned"].includes(String(row.status||""))&&currentRole()!=="principal"?'<button class="button danger small" data-report-delete="'+esc(row.id)+'">Delete</button>':""}</td></tr>`).join("")}</tbody></table></div>`:empty("No report cards match the current filters."))+`<div class="panel-footer"><span>${start}–${end} of ${total}</span><div class="button-row"><button class="button ghost small" id="reportPrevious" type="button" ${reportPage<=1?"disabled":""}>Previous</button><button class="button ghost small" id="reportNext" type="button" ${end>=total?"disabled":""}>Next</button></div></div>`;
      byId("reportPrevious")?.addEventListener("click",()=>{if(reportPage>1){reportPage-=1;loadReportList();}});
      byId("reportNext")?.addEventListener("click",()=>{if(end<total){reportPage+=1;loadReportList();}});
      box.querySelectorAll("[data-report-open]").forEach(b=>b.onclick=()=>openReportEditor(b.dataset.reportOpen,null,null));
      box.querySelectorAll("[data-report-delete]").forEach(b=>b.onclick=async()=>{if(!await window.EdusentiaConfirm("Permanently delete this never-approved draft report?"))return;try{await certified("delete_report_card_permanently",{target_report_id:b.dataset.reportDelete,reason_text:"Draft report deleted by authorised school user"});await loadReportList();}catch(error){alert(friendly(error));}});
    }catch(error){box.innerHTML=pageError(error);}
  }
  function openManualReportTemplate(){
    const years=Array.isArray(reportConfig?.academic_years)?reportConfig.academic_years:[],terms=Array.isArray(reportConfig?.terms)?reportConfig.terms:[],classes=Array.isArray(reportConfig?.classes)?reportConfig.classes:[],subjects=Array.isArray(reportConfig?.subjects)?reportConfig.subjects.filter(x=>x.active!==false):[];
    const activeYear=years.find(x=>x.is_active)?.id||years[0]?.id||"",activeTerm=terms.find(x=>x.is_active)?.id||terms[0]?.id||"";
    openModal("Manual Report Card Template","Prepare a professionally formatted blank report card for manual completion.",`
      <form id="manualReportTemplateForm" class="form-stack"><div class="form-grid">
        <label class="field"><span>Academic year</span><select name="academic_year_id"><option value="">Leave blank</option>${optionRows(years,"id","name",activeYear).replace('<option value="">Select</option>',"")}</select></label>
        <label class="field"><span>Term</span><select name="term_id"><option value="">Leave blank</option>${optionRows(terms,"id","name",activeTerm).replace('<option value="">Select</option>',"")}</select></label>
        <label class="field full"><span>Class</span><select name="class_id"><option value="">Leave blank</option>${optionRows(classes,"id","name","").replace('<option value="">Select</option>',"")}</select></label>
      </div><div class="template-information"><strong>${subjects.length} active subject${subjects.length===1?"":"s"} will be included.</strong><span>Student details, scores, grades, positions, comments, attendance and conduct fields remain blank for manual completion.</span></div></form>`,
      '<button class="button ghost" id="manualTemplateCancel" type="button">Cancel</button><button class="button primary" id="manualTemplateOpen" type="button">Open printable template</button>');
    byId("manualTemplateCancel").onclick=closeModal;
    byId("manualTemplateOpen").onclick=()=>{
      if(!subjects.length){showMessage("reportEditorMessage","At least one active subject is required.");return;}
      const form=byId("manualReportTemplateForm"),v=formValues(form),year=years.find(x=>String(x.id)===String(v.academic_year_id)),term=terms.find(x=>String(x.id)===String(v.term_id)),clazz=classes.find(x=>String(x.id)===String(v.class_id)),school=window.EdusentiaShell?.state?.boot?.tenant||{},win=window.open("","_blank");
      if(!win){window.EdusentiaNotify?.("Template preview blocked","Allow pop-ups for this school workspace and try again.","warning");return;}
      const rows=subjects.map((s,i)=>'<tr><td>'+(i+1)+'</td><td>'+esc(s.name||s.subject_name||"Subject")+'</td><td></td><td></td><td></td><td></td></tr>').join("");
      win.document.write('<!doctype html><html><head><meta charset="utf-8"><title>Manual Report Card Template</title><style>@page{size:A4;margin:12mm}body{font:11pt Arial,sans-serif;color:#17233b;margin:0}header{text-align:center;border-bottom:3px solid #123a79;margin-bottom:6mm}h1{font-size:18pt;margin:0}h2{font-size:14pt;color:#123a79}.meta{display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin:12px 0}.blank{border-bottom:1px solid #334155;min-height:20px}table{width:100%;border-collapse:collapse}th,td{border:1px solid #b7c2d1;padding:6px;height:22px}th{background:#eef3fa}.notes{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:16px}.box{border:1px solid #b7c2d1;min-height:70px;padding:8px}.actions{margin:0 0 15px}@media print{.actions{display:none}}</style></head><body><div class="actions"><button onclick="window.print()">Print / Save as PDF</button></div><header><h1>'+esc(school.name||"School")+'</h1><h2>Manual Report Card Template</h2></header><div class="meta"><div><strong>Academic year:</strong> '+esc(year?.name||"________________")+'</div><div><strong>Term:</strong> '+esc(term?.name||"________________")+'</div><div><strong>Class:</strong> '+esc(clazz?.name||"________________")+'</div><div><strong>Admission no.:</strong> ____________________</div><div><strong>Student:</strong> ______________________________</div><div><strong>Attendance:</strong> ______ / ______</div></div><table><thead><tr><th>#</th><th>Subject</th><th>Class score</th><th>Exam</th><th>Total</th><th>Grade</th></tr></thead><tbody>'+rows+'</tbody></table><div class="notes"><div><strong>Class Teacher Comment</strong><div class="box"></div></div><div><strong>Principal Comment</strong><div class="box"></div></div><div><strong>Conduct / Attitude</strong><div class="box"></div></div><div><strong>Promotion / Next Class</strong><div class="box"></div></div></div></body></html>');
      win.document.close();closeModal();
    };
  }

  async function openNewReportPicker(preselectedEnrollmentId=""){
    try{
      const students=await certifiedAllRows("search_students_v5",{search_text:"",target_class_id:null,target_status:"active",archive_filter:"active"}),rows=Array.isArray(students?.rows)?students.rows:[],terms=Array.isArray(reportConfig?.terms)?reportConfig.terms:[];
      openModal("New Report Card","Select a current student enrolment and term.",`<form id="newReportForm" class="form-stack"><label class="field"><span>Student</span><select name="enrollment_id" size="10" required><option value="">Select student</option>${rows.filter(x=>x.enrollment_id).map(x=>`<option value="${esc(x.enrollment_id)}" data-year="${esc(x.academic_year_id||"")}">${esc([x.first_name,x.middle_name,x.last_name].filter(Boolean).join(" "))} • ${esc(x.class_name||"No class")}</option>`).join("")}</select></label><label class="field"><span>Term</span><select name="term_id" required>${optionRows(terms,"id","name",terms.find(x=>x.is_active)?.id||"")}</select></label><p id="newReportMessage" class="form-message hidden"></p></form>`,'<button class="button ghost" id="newReportCancel">Cancel</button><button class="button primary" id="newReportOpen">Open report</button>');
      const form=byId("newReportForm");byId("newReportCancel").onclick=closeModal;const syncTerms=()=>{const year=form.elements.enrollment_id.selectedOptions[0]?.dataset.year||"";form.elements.term_id.innerHTML=optionRows(terms.filter(t=>!year||String(t.academic_year_id)===String(year)),"id","name",terms.find(t=>t.is_active&&(!year||String(t.academic_year_id)===String(year)))?.id||"");};form.elements.enrollment_id.onchange=syncTerms;if(preselectedEnrollmentId){form.elements.enrollment_id.value=preselectedEnrollmentId;syncTerms();}
      byId("newReportOpen").onclick=async()=>{if(!form.reportValidity())return;const v=formValues(form);closeModal();await openReportEditor(null,v.enrollment_id,v.term_id);};
    }catch(error){alert(friendly(error));}
  }
  async function exportReportList(){
    try{
      const data=await certifiedAllRows("list_report_cards_v6",{target_term_id:byId("reportTerm")?.value||null,target_class_id:byId("reportClass")?.value||null,target_status:byId("reportStatus")?.value||null,search_text:byId("reportSearch")?.value?.trim()||"",archive_filter:"active"}),rows=Array.isArray(data?.rows)?data.rows:[],cell=v=>'"'+String(v??"").replaceAll('"','""')+'"',lines=["report_number,student,class,term,average,status,updated_at"];
      rows.forEach(r=>lines.push([r.report_number,r.student_name,r.class_name,r.term_name,r.average,r.status,r.updated_at].map(cell).join(",")));
      downloadBlob("report-cards.csv",new Blob([lines.join("\n")],{type:"text/csv;charset=utf-8"}));
    }catch(error){alert(friendly(error));}
  }
  async function bulkTransitionReports(targetStatus){
    const termId=byId("reportTerm")?.value||"",classId=byId("reportClass")?.value||"";if(!termId||!classId){alert("Select one term and one class before using a bulk workflow action.");return;}
    const action=targetStatus==="published"?"Publish":targetStatus==="approved"?"Approve":"Update";if(!await window.EdusentiaConfirm(action+" every eligible report in the selected class? Incomplete or ineligible reports remain unchanged."))return;
    try{const result=await certified("bulk_transition_class_reports",{target_term_id:termId,target_class_id:classId,target_status:targetStatus,comment_text:"Bulk "+targetStatus+" from Report Cards workspace"});alert(String(result?.transitioned_reports||0)+" report(s) "+targetStatus+".");await loadReportList();}catch(error){alert(friendly(error));}
  }
  async function bulkDownloadPublishedReports(){
    const termId=byId("reportTerm")?.value||"",classId=byId("reportClass")?.value||"";if(!termId||!classId){alert("Select one term and one class before downloading a class package.");return;}
    try{
      const data=await certifiedAllRows("list_report_cards_v6",{target_term_id:termId,target_class_id:classId,target_status:"published",search_text:"",archive_filter:"active"}),rows=Array.isArray(data?.rows)?data.rows:[];
      if(!rows.length){alert("No published reports are available for this class and term.");return;}
      for(const row of rows){try{downloadBlob(`${safeName(row.report_number||row.student_name||"report")}.pdf`,await api().downloadReportPdf(row.id));await new Promise(r=>setTimeout(r,120));}catch{}}
    }catch(error){alert(friendly(error));}
  }

  async function openReportEditor(reportId,enrollmentId,termId){
    const box=byId("reportWorkspace");if(!box){window.EdusentiaNotify?.("Report workspace unavailable","Refresh the Report Cards page and try again.","error");return;}
    box.innerHTML=loading("Opening report");
    try{
      const editor=await certified("get_report_editor",{target_report_id:reportId,target_enrollment_id:enrollmentId,target_term_id:termId});
      renderReportEditor(editor);
      box.scrollIntoView({behavior:"smooth",block:"start"});
    }catch(error){box.innerHTML=pageError(error);}
  }
  function renderReportEditor(editor){
    const box=byId("reportWorkspace");if(!box)return;
    const report=editor?.report||{},student=editor?.student||{},subjects=Array.isArray(editor?.subjects)?editor.subjects:[],publication=(editor?.publications||[]).find(p=>!p.revoked_at);
    const reportPhoto=student.photo_url?`<span class="staff-avatar-photo"><img id="reportStudentPhoto" alt="Student photograph"><span>${esc(reportStudentInitials(student))}</span></span>`:`<span class="avatar">${esc(reportStudentInitials(student))}</span>`;
    box.innerHTML=`<div class="panel-header"><div class="cell-main">${reportPhoto}<span class="cell-copy"><h3>${esc(student.full_name||"Student report")}</h3><p>${esc(student.admission_no||"")} • ${esc(student.class_name||"")} • ${esc(student.term_name||"")} • ${status(report.status||"draft")}</p></span></div><div class="page-actions">${report.id?'<button id="reportRefresh" class="button ghost small" type="button">Refresh</button><button id="reportPrintLatest" class="button outline small" type="button">Print / Save PDF</button>':""}${publication?'<button id="reportPdfDownload" class="button secondary small" type="button">Download official PDF</button>':""}${report.id&&report.status==="published"?'<button id="reportPdfUpload" class="button secondary small" type="button">Upload official PDF</button>':""}</div></div>
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
    hydrateReportStudentPhoto(student);
    byId("reportRefresh")?.addEventListener("click",()=>openReportEditor(report.id,null,null));
    byId("reportPrintLatest")?.addEventListener("click",()=>openPrintableReport(editor));
    byId("reportDeleteDraft")?.addEventListener("click",async()=>{if(!await window.EdusentiaConfirm("Permanently delete this never-approved draft report?"))return;try{await certified("delete_report_card_permanently",{target_report_id:report.id,reason_text:"Draft report deleted from Neon testing workspace"});byId("reportWorkspace").innerHTML=empty("Draft report deleted.");}catch(error){showMessage("reportEditorMessage",friendly(error));}});
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
