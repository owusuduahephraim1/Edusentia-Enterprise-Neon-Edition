(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,esc,status,formatDate,formatDateTime,formatAmount,loading,pageError,byId}=P;
  const table=(headers,rows,render,emptyText)=>`<div class="table-wrap"><table><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.length?rows.map(render).join(""):`<tr><td colspan="${headers.length}">${esc(emptyText)}</td></tr>`}</tbody></table></div>`;
  async function renderOperations(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Operations</h3><p>Cross-domain testing console for active Neon school services.</p></div></div>${loading("Loading active-domain operations")}`;
    try{
      const data=await api().listOperationsOverview(),c=data.counts||{};
      const cards=[
        ["Admissions",c.admissions||0],["Attendance registers",c.attendance_registers||0],["Discipline",c.discipline_incidents||0],
        ["Welfare",c.welfare_cases||0],["Health visits",c.health_visits||0],["Hostel allocations",c.hostel_allocations||0],
        ["Payroll runs",c.payroll_runs||0],["Campaigns",c.communication_campaigns||0],["Certificate batches",c.certificate_batches||0],["Imports",c.import_batches||0]
      ];
      byId("content").innerHTML=`
        <div class="page-head"><div><h3>Operations</h3><p>Cross-domain testing console for admissions, attendance, student services, payroll, communications, documents and continuity.</p></div></div>
        <section class="stat-grid">${cards.map(([label,value])=>`<article class="stat-card"><span class="stat-icon">•</span><div><span>${esc(label)}</span><strong>${esc(value)}</strong></div></article>`).join("")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Admissions</h3><p>Latest applications</p></div></div>${table(["Application","Applicant","Class","Status","Submitted"],data.admissions||[],x=>`<tr><td>${esc(x.application_no||"")}</td><td>${esc(x.applicant_name||"")}</td><td>${esc(x.applying_class||"—")}</td><td>${status(x.status)}</td><td>${formatDateTime(x.submitted_at)}</td></tr>`,"No admission applications.")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Attendance</h3><p>Latest class registers</p></div></div>${table(["Date","Class","Term","Entries","Status"],data.attendance||[],x=>`<tr><td>${formatDate(x.attendance_date)}</td><td>${esc(x.class_name||"—")}</td><td>${esc(x.term_name||"—")}</td><td>${esc(x.entry_count||0)}</td><td>${status(x.status)}</td></tr>`,"No attendance registers.")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Discipline</h3><p>Latest incidents</p></div></div>${table(["Date","Student","Category","Severity","Summary","Status"],data.discipline||[],x=>`<tr><td>${formatDate(x.incident_date)}</td><td>${esc(x.student_name||"—")}</td><td>${esc(x.category||"")}</td><td>${status(x.severity||"")}</td><td>${esc(x.summary||"")}</td><td>${status(x.status)}</td></tr>`,"No discipline incidents.")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Welfare & Health</h3><p>Recent support activity</p></div></div>
          ${table(["Opened","Student","Type","Priority","Summary","Status"],data.welfare||[],x=>`<tr><td>${formatDateTime(x.opened_at)}</td><td>${esc(x.student_name||"—")}</td><td>${esc(x.case_type||"")}</td><td>${status(x.priority||"")}</td><td>${esc(x.summary||"")}</td><td>${status(x.status)}</td></tr>`,"No welfare cases.")}
          ${table(["Visited","Student","Complaint","Assessment","Disposition"],data.health||[],x=>`<tr><td>${formatDateTime(x.visited_at)}</td><td>${esc(x.student_name||"—")}</td><td>${esc(x.complaint||"")}</td><td>${esc(x.assessment||"")}</td><td>${esc(x.disposition||"")}</td></tr>`,"No health visits.")}
        </section>
        <section class="panel"><div class="panel-header"><div><h3>Hostel / Boarding</h3><p>Recent student allocations</p></div></div>${table(["Student","Starts","Ends","Status"],data.hostel||[],x=>`<tr><td>${esc(x.student_name||"—")}</td><td>${formatDate(x.starts_on)}</td><td>${formatDate(x.ends_on)}</td><td>${status(x.status)}</td></tr>`,"No hostel allocations.")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Payroll</h3><p>Latest payroll runs</p></div></div>${table(["Period","Status","Entries","Net total","Created"],data.payroll||[],x=>`<tr><td>${formatDate(x.period_start)} – ${formatDate(x.period_end)}</td><td>${status(x.status)}</td><td>${esc(x.entry_count||0)}</td><td>${formatAmount(x.total_net)}</td><td>${formatDateTime(x.created_at)}</td></tr>`,"No payroll runs.")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Communications</h3><p>Recent campaigns</p></div></div>${table(["Campaign","Channel","Audience","Subject","Status","Published"],data.communications||[],x=>`<tr><td>${esc(x.name||"")}</td><td>${esc(x.channel||"")}</td><td>${esc(x.audience||"")}</td><td>${esc(x.subject||"")}</td><td>${status(x.status)}</td><td>${formatDateTime(x.published_at||x.scheduled_at)}</td></tr>`,"No communication campaigns.")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Certificates & Documents</h3><p>Recent certificate batches</p></div></div>${table(["Batch","Type","Status","Submitted","Reviewed"],data.documents||[],x=>`<tr><td>${esc(x.batch_no||"")}</td><td>${esc(x.certificate_type||"")}</td><td>${status(x.status)}</td><td>${formatDateTime(x.submitted_at)}</td><td>${formatDateTime(x.reviewed_at)}</td></tr>`,"No certificate batches.")}</section>
        <section class="panel"><div class="panel-header"><div><h3>Imports & Continuity</h3><p>Latest protected import batches</p></div></div>${table(["Type","File","Status","Rows","Success","Errors","Created"],data.continuity||[],x=>`<tr><td>${esc(x.import_type||"")}</td><td>${esc(x.file_name||"")}</td><td>${status(x.status)}</td><td>${esc(x.row_count||0)}</td><td>${esc(x.success_count||0)}</td><td>${esc(x.error_count||0)}</td><td>${formatDateTime(x.created_at)}</td></tr>`,"No import batches.")}</section>`;
    }catch(error){byId("content").innerHTML=pageError(error);}
  }
  registerView({id:"operations",label:"Operations",icon:"▦",subtitle:"Admissions, attendance, services, payroll and continuity",roles:["system_admin","principal"],render:renderOperations});
})();