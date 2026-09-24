(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  // Certified cross-domain coverage retained: Admissions, Attendance, Payroll, Communications.
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,loading,pageError,byId,friendly,formValues,showMessage,academicConfig}=P;
  const arr=v=>Array.isArray(v)?v:[];
  const num=(v,d=0)=>Number.isFinite(Number(v))?Number(v):d;
  const text=v=>v==null||v===""?"—":String(v);
  const nullable=v=>String(v||"").trim()||null;
  const title=v=>String(v||"").replaceAll("_"," ").replace(/\b\w/g,m=>m.toUpperCase());
  const dateTimeLocal=v=>{if(!v)return"";const d=new Date(v);if(Number.isNaN(d.valueOf()))return"";return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16);};
  function toast(a,b="",kind="success"){const root=byId("toastStack");if(!root){if(kind==="error")alert(a+(b?": "+b:""));return;}const n=document.createElement("div");n.className="toast "+kind;n.innerHTML="<strong>"+esc(a)+"</strong>"+(b?"<span>"+esc(b)+"</span>":"");root.appendChild(n);setTimeout(()=>n.remove(),4500);}
  const metric=(label,value,detail="")=>'<div class="metric maturity-metric"><span>'+esc(label)+'</span><strong>'+esc(text(value))+'</strong>'+(detail?'<small>'+esc(detail)+'</small>':"")+'</div>';
  const empty=(a,b="")=>'<div class="empty"><strong>'+esc(a)+'</strong>'+(b?'<span>'+esc(b)+'</span>':"")+'</div>';
  const optionRows=(rows,selected,blank="Select")=>'<option value="">'+esc(blank)+'</option>'+arr(rows).map(x=>'<option value="'+esc(x.id||"")+'" '+(String(x.id||"")===String(selected||"")?"selected":"")+'>'+esc(x.name||x.label||x.code||x.id)+'</option>').join("");
  async function config(){return academicConfig();}

  async function renderOperations(){
    byId("content").innerHTML='<div class="page-head"><div><h3>Production Operations</h3><p>Academic deadlines, term locks, report corrections, alerts, health, and recovery readiness</p></div></div>'+loading("Loading production operations");
    try{
      const cfg=await config(),terms=arr(cfg?.terms),classes=arr(cfg?.classes),termId=localStorage.getItem("eds_ops_term")||terms.find(x=>x.is_active)?.id||terms[0]?.id||null;
      const [ops,corrections,controls,backupData,recovery]=await Promise.all([
        certified("operations_dashboard",{target_term_id:termId}),
        certified("get_report_correction_console",{target_term_id:termId,target_class_id:null}),
        certified("list_academic_period_controls",{}),
        role()==="system_admin"?certified("backup_dashboard",{}).catch(()=>({backups:[]})):Promise.resolve({backups:[]}),
        role()==="system_admin"?certified("get_recovery_console",{}).catch(()=>({tests:[]})):Promise.resolve({tests:[]})
      ]);
      const hasTerm=Boolean(termId),control=ops?.term_control||{},progress=arr(ops?.class_progress),requests=arr(corrections?.requests),pending=requests.filter(x=>x.status==="pending"),backups=arr(backupData?.backups),tests=arr(recovery?.tests),latestBackup=backups.find(x=>x.status==="completed"&&x.backup_type==="full")||backups.find(x=>x.status==="completed"),healthRisk=num(ops?.critical_security_events)>0||num(ops?.failed_backups_30d)>0||num(ops?.published_without_pdf)>0;
      byId("content").innerHTML=`
        <div class="page-head"><div><h3>Production Operations</h3><p>Academic deadlines, term locks, report corrections, alerts, health, and recovery readiness</p></div><div class="page-actions"><button class="button secondary" id="operationsRefresh">Refresh</button></div></div>
        ${hasTerm?"":'<div class="template-information warning"><strong>No academic term is configured</strong><span>Academic controls are unavailable until a term exists. System health, backup verification, and recovery readiness remain available.</span></div>'}
        <section class="panel pad maturity-filter"><div class="form-grid three">
          <label class="field"><span>Academic term</span><select id="operationsTerm" ${hasTerm?"":"disabled"}>${optionRows(terms,termId,"Select academic term")}</select></label>
          <label class="field"><span>Class for bulk report generation</span><select id="operationsClass" ${hasTerm?"":"disabled"}>${optionRows(classes,"","Select class")}</select></label>
          <div class="field"><span>Operational state</span><strong class="health-indicator ${healthRisk?"attention":"healthy"}">${healthRisk?"Attention required":"Healthy"}</strong></div>
        </div></section>
        <section class="stat-grid maturity-stat-grid">
          <article class="stat-card"><span class="stat-icon blue">◉</span><div><span>Expected reports</span><strong>${num(ops?.reports_expected)}</strong></div></article>
          <article class="stat-card"><span class="stat-icon purple">▤</span><div><span>Reports created</span><strong>${num(ops?.reports_created)}</strong></div></article>
          <article class="stat-card"><span class="stat-icon gold">⌛</span><div><span>Awaiting approval</span><strong>${num(ops?.awaiting_approval)}</strong></div></article>
          <article class="stat-card"><span class="stat-icon green">✓</span><div><span>Published</span><strong>${num(ops?.published)}</strong></div></article>
        </section>
        <div class="grid two maturity-grid">
          <section class="panel pad"><div class="section-title"><div><h4>Academic period control</h4><p>Set deadlines and freeze completed phases without altering historical records.</p></div></div>
            <form id="periodControlForm" class="form-grid">
              <label class="field"><span>Score-entry deadline</span><input type="datetime-local" name="score_entry_deadline" value="${esc(dateTimeLocal(control.score_entry_deadline))}"></label>
              <label class="field"><span>Attendance deadline</span><input type="datetime-local" name="attendance_deadline" value="${esc(dateTimeLocal(control.attendance_deadline))}"></label>
              <label class="field"><span>Report-submission deadline</span><input type="datetime-local" name="report_submission_deadline" value="${esc(dateTimeLocal(control.report_submission_deadline))}"></label>
              <label class="field"><span>Principal-approval deadline</span><input type="datetime-local" name="principal_approval_deadline" value="${esc(dateTimeLocal(control.principal_approval_deadline))}"></label>
              <label class="field"><span>Publication deadline</span><input type="datetime-local" name="publication_deadline" value="${esc(dateTimeLocal(control.publication_deadline))}"></label>
              <div class="field"><span>Phase locks</span><div class="check-grid"><label><input type="checkbox" name="scores_locked" ${control.scores_locked?"checked":""}> Scores</label><label><input type="checkbox" name="attendance_locked" ${control.attendance_locked?"checked":""}> Attendance</label><label><input type="checkbox" name="reports_locked" ${control.reports_locked?"checked":""}> Reports</label></div></div>
              <label class="field full"><span>Lock or reopening reason</span><textarea name="lock_reason" placeholder="Explain why the term is being locked or reopened">${esc(control.lock_reason||"")}</textarea></label>
              <div class="full button-row"><button class="button primary" id="periodControlSave" type="button" ${hasTerm?"":"disabled"}>Save period control</button><button class="button secondary" id="academicAlertsRun" type="button" ${hasTerm?"":"disabled"}>Queue deadline alerts</button></div>
              <p id="periodControlMessage" class="form-message hidden full"></p>
            </form>
          </section>
          <section class="panel pad"><div class="section-title"><div><h4>System health</h4><p>Current production reliability indicators</p></div></div>
            <div class="metric-row wrap">${metric("PDFs missing",num(ops?.published_without_pdf))}${metric("Client errors, 24h",num(ops?.client_errors_24h))}${metric("Open security events",num(ops?.open_security_events))}${metric("Failed backups, 30d",num(ops?.failed_backups_30d))}</div>
            <div class="hr"></div>
            <div class="diff-row"><span>Latest full backup</span><b>${formatDateTime(ops?.latest_backup)}</b></div>
            <div class="diff-row"><span>Latest verified backup</span><b>${formatDateTime(ops?.latest_verified_backup)}</b></div>
            <div class="diff-row"><span>Latest recovery rehearsal</span><b>${formatDateTime(ops?.latest_recovery_test)}</b></div>
            <div class="diff-row"><span>Attendance classes marked today</span><b>${num(ops?.attendance_classes_today)} / ${num(ops?.active_classes)}</b></div>
            <div class="diff-row"><span>Pending notification deliveries</span><b>${num(ops?.pending_notifications)}</b></div>
            ${role()==="system_admin"?'<div class="button-row" style="margin-top:15px"><button class="button secondary" id="recoveryRun" '+(latestBackup?"":"disabled")+'>Run recovery rehearsal</button></div>':""}
          </section>
        </div>
        <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Class report progress</h3><p>Current created, submitted, approved, and published records by class.</p></div><button class="button outline small" id="generateMissingReports" ${hasTerm?"":"disabled"}>Preview missing reports</button></div>
          ${progress.length?'<div class="table-wrap history-scroll"><table><thead><tr><th>Class</th><th>Enrolled</th><th>Created</th><th>Submitted</th><th>Approved</th><th>Published</th><th>Completion</th></tr></thead><tbody>'+progress.map(item=>{const pct=item.enrolled?Math.round(num(item.published)/Math.max(num(item.enrolled),1)*100):0;return '<tr><td><strong>'+esc(item.class_name||"Class")+'</strong></td><td>'+num(item.enrolled)+'</td><td>'+num(item.created)+'</td><td>'+num(item.submitted)+'</td><td>'+num(item.approved)+'</td><td>'+num(item.published)+'</td><td><div class="inline-progress"><span style="width:'+pct+'%"></span></div><small>'+pct+'%</small></td></tr>'}).join("")+'</tbody></table></div>':empty("No class progress available")}
        </section>
        <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Published-report correction requests</h3><p>Original reports remain preserved; approved requests reopen controlled editing.</p></div><span class="chip">${pending.length} pending</span></div>
          ${requests.length?'<div class="table-wrap history-scroll"><table><thead><tr><th>Student and report</th><th>Class</th><th>Request</th><th>Status</th><th>Review</th></tr></thead><tbody>'+requests.map(item=>'<tr><td><div class="cell-copy"><strong>'+esc(item.student_name||"Student")+'</strong><small>'+esc(item.report_number||"Report")+' • '+esc(item.term_name||"")+'</small></div></td><td>'+esc(item.class_name||"—")+'</td><td><div class="cell-copy"><strong>'+esc(item.requester_name||"Authorised user")+'</strong><small>'+esc(item.reason||"")+'</small></div></td><td>'+status(item.status||"pending")+'</td><td>'+(role()==="principal"&&item.status==="pending"?'<div class="button-row compact"><button class="button success small" data-correction-review="'+esc(item.id)+'" data-decision="approved">Approve</button><button class="button warning small" data-correction-review="'+esc(item.id)+'" data-decision="rejected">Reject</button></div>':'<small>'+esc(item.reviewer_name||item.review_note||"Awaiting review")+'</small>')+'</td></tr>').join("")+'</tbody></table></div>':empty("No correction requests")}
        </section>
        ${role()==="system_admin"?'<section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Recovery rehearsal history</h3><p>Non-destructive decrypt, reconstruction, and checksum tests</p></div></div>'+(tests.length?'<div class="table-wrap history-scroll"><table><thead><tr><th>Started</th><th>Status</th><th>Tables</th><th>Rows</th><th>Storage objects</th><th>Notes</th></tr></thead><tbody>'+tests.map(item=>'<tr><td>'+formatDateTime(item.started_at)+'</td><td>'+status(item.status||"unknown")+'</td><td>'+num(item.checked_tables)+'</td><td>'+num(item.checked_rows)+'</td><td>'+num(item.checked_storage_objects)+'</td><td>'+esc(item.notes||item.error_message||"—")+'</td></tr>').join("")+'</tbody></table></div>':empty("No recovery rehearsal has been recorded"))+'</section>':""}`;
      byId("operationsTerm")?.addEventListener("change",()=>{localStorage.setItem("eds_ops_term",byId("operationsTerm").value);renderOperations();});
      byId("operationsRefresh").onclick=renderOperations;
      byId("periodControlSave").onclick=async()=>{const form=byId("periodControlForm"),v=formValues(form),locked=form.elements.scores_locked.checked||form.elements.attendance_locked.checked||form.elements.reports_locked.checked;if(locked&&String(v.lock_reason||"").trim().length<5){showMessage("periodControlMessage","Provide a clear reason before locking an academic phase.");return;}const b=byId("periodControlSave");b.disabled=true;try{await certified("save_academic_period_control",{payload:{term_id:termId,...v,score_entry_deadline:nullable(v.score_entry_deadline),attendance_deadline:nullable(v.attendance_deadline),report_submission_deadline:nullable(v.report_submission_deadline),principal_approval_deadline:nullable(v.principal_approval_deadline),publication_deadline:nullable(v.publication_deadline),scores_locked:form.elements.scores_locked.checked,attendance_locked:form.elements.attendance_locked.checked,reports_locked:form.elements.reports_locked.checked}});toast("Academic period control saved");await renderOperations();}catch(e){showMessage("periodControlMessage",friendly(e));}finally{b.disabled=false;}};
      byId("academicAlertsRun").onclick=async()=>{const b=byId("academicAlertsRun");b.disabled=true;try{const result=await certified("run_academic_alerts",{target_term_id:termId});toast("Academic alerts queued",num(result?.queued??result)+" new notification"+(num(result?.queued??result)===1?"":"s")+" queued.");}catch(e){toast("Alerts not queued",friendly(e),"error");}finally{b.disabled=false;}};
      byId("generateMissingReports").onclick=async()=>{const classId=byId("operationsClass").value;if(!classId){toast("Select a class","Choose the class before previewing missing reports.","warning");return;}try{const preview=await certified("bulk_generate_missing_reports",{target_term_id:termId,target_class_id:classId,preview_only:true});if(!num(preview?.missing_reports)){toast("No missing reports","Every active student already has a report for this term.");return;}if(!await window.EdusentiaConfirm(num(preview.missing_reports)+" missing report record(s) will be created. Existing reports will not be changed. Continue?"))return;const result=await certified("bulk_generate_missing_reports",{target_term_id:termId,target_class_id:classId,preview_only:false});toast("Draft reports generated",num(result?.created_reports)+" report record(s) created.");await renderOperations();}catch(e){toast("Reports not generated",friendly(e),"error");}};
      byId("recoveryRun")?.addEventListener("click",async()=>{if(!latestBackup?.id||!await window.EdusentiaConfirm("Run a non-destructive recovery rehearsal using the latest completed backup?"))return;const b=byId("recoveryRun");b.disabled=true;try{const data=await api().scheduledBackup("recovery_test",{backup_id:latestBackup.id});toast("Recovery rehearsal passed",num(data?.checked_tables)+" tables, "+num(data?.checked_rows)+" rows, and "+num(data?.checked_storage_objects)+" storage objects verified.");await renderOperations();}catch(e){toast("Recovery rehearsal failed",friendly(e),"error");}finally{b.disabled=false;}});
      byId("content").querySelectorAll("[data-correction-review]").forEach(b=>b.onclick=async()=>{const note=await window.EdusentiaPrompt((b.dataset.decision==="approved"?"Approval conditions":"Rejection reason"))||"";try{await certified("review_report_correction",{target_request_id:b.dataset.correctionReview,decision:b.dataset.decision,review_note_text:note||null});toast("Correction request reviewed");await renderOperations();}catch(e){toast("Review not saved",friendly(e),"error");}});
    }catch(error){byId("content").innerHTML=pageError(error);}
  }
  registerView({id:"operations",label:"Operations",icon:"◫",subtitle:"Deadlines, health, corrections, and recovery readiness",roles:["system_admin","principal"],feature:"governance",render:renderOperations});
})();