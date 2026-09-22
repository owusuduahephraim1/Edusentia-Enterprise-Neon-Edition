(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  // ---------- Audit ----------
  async function renderAudit(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Audit Trail</h3><p>Certified tenant audit events and protected archive batches.</p></div></div>${loading("Loading audit trail")}`;
    try{
      const [events,archives]=await Promise.all([
        certified("list_audit_events_v2",{target_table:"",target_action:"",target_actor_id:null,target_record_id:null,page_number:1,page_size:100}),
        certified("list_audit_archives_v1",{page_number:1,page_size:50})
      ]);
      const rows=Array.isArray(events?.rows)?events.rows:[],batches=Array.isArray(archives?.rows)?archives.rows:[];
      byId("content").innerHTML=`
        <div class="page-head"><div><h3>Audit Trail</h3><p>Certified tenant audit events and protected archive batches.</p></div>
          <div class="page-actions">${isSystemAdmin()?'<button id="auditResetAll" class="button danger" type="button">Reset all audit history</button>':""}</div>
        </div>
        <div class="license-banner restricted"><div><strong>Permanent deletion control</strong><span>Audit reset actions permanently delete the selected Audit Trail history. They require System Administrator access, verified MFA, and typed confirmation.</span></div></div>
        <section class="panel"><div class="panel-header"><div><h3>Recent events</h3><p>${esc(events?.total??rows.length)} matching events</p></div>${isSystemAdmin()?'<button id="auditResetActive" class="button danger small" type="button">Reset recent events</button>':""}</div><div id="auditRows" class="table-wrap audit-scroll"><table><thead><tr><th>Time</th><th>Action</th><th>Table</th><th>Record</th><th>Actor</th><th>Reason</th></tr></thead><tbody>${rows.length?rows.map(x=>`<tr><td>${formatDateTime(x.created_at)}</td><td>${esc(x.action||"")}</td><td>${esc(x.table_name||"")}</td><td>${esc(x.record_id||"—")}</td><td>${esc(x.actor_name||x.actor_id||"System")}</td><td>${esc(x.reason||"")}</td></tr>`).join(""):'<tr><td colspan="6">No audit events.</td></tr>'}</tbody></table></div></section>
        <section class="panel"><div class="panel-header"><div><h3>Audit archives</h3><p>Historical audit batches previously moved out of the active console</p></div>${isSystemAdmin()?'<button id="auditResetArchives" class="button danger small" type="button">Delete all archives</button>':""}</div><div id="auditArchiveRows" class="table-wrap audit-scroll"><table><thead><tr><th>Archive</th><th>Created</th><th>Rows</th><th>Actions</th></tr></thead><tbody>${batches.length?batches.map(x=>`<tr><td>${esc(x.id||"")}</td><td>${formatDateTime(x.created_at)}</td><td>${esc(x.entry_count??x.row_count??"—")}</td><td><button class="button secondary small" data-audit-archive="${esc(x.id)}">View</button></td></tr>`).join(""):'<tr><td colspan="4">No archives.</td></tr>'}</tbody></table></div></section>`;
      byId("content").querySelectorAll("[data-audit-archive]").forEach(b=>b.onclick=()=>openAuditArchive(b.dataset.auditArchive));
      byId("auditResetActive")?.addEventListener("click",()=>openAuditReset("active"));
      byId("auditResetArchives")?.addEventListener("click",()=>openAuditReset("archives"));
      byId("auditResetAll")?.addEventListener("click",()=>openAuditReset("all"));
    }catch(error){byId("content").innerHTML=pageError(error);}
  }

  function openAuditReset(scope){
    const config={
      active:{
        title:"Reset Recent Audit Events",
        phrase:"RESET ACTIVE AUDIT",
        description:"Permanently delete every record from the active Recent events section. Audit archives are left unchanged."
      },
      archives:{
        title:"Delete All Audit Archives",
        phrase:"DELETE ALL AUDIT ARCHIVES",
        description:"Permanently delete every archived audit entry and archive batch. Recent events are left unchanged."
      },
      all:{
        title:"Reset All Audit History",
        phrase:"RESET ALL AUDIT HISTORY",
        description:"Permanently delete both Recent events and every Audit archive. This cannot be undone."
      }
    }[scope];
    if(!config)return;
    openModal(config.title,"System Administrator only",`
      <div class="license-banner restricted"><div><strong>Permanent deletion</strong><span>${esc(config.description)}</span></div></div>
      <form id="auditResetForm" class="form-stack">
        <label class="field"><span>Type <code>${esc(config.phrase)}</code> to confirm</span><input name="confirmation" autocomplete="off" required></label>
        <label class="check-field"><input type="checkbox" name="acknowledge" required><span>I understand these Audit Trail records will be permanently deleted and cannot be restored from this workspace.</span></label>
        <p id="auditResetMessage" class="form-message hidden"></p>
      </form>`,
      '<button class="button ghost" id="auditResetCancel" type="button">Cancel</button><button class="button danger" id="auditResetConfirm" type="button">Permanently delete</button>');
    byId("auditResetCancel").onclick=closeModal;
    byId("auditResetConfirm").onclick=async()=>{
      const form=byId("auditResetForm"),typed=String(form.elements.confirmation.value||"").trim().toUpperCase(),button=byId("auditResetConfirm");
      if(!form.reportValidity())return;
      if(typed!==config.phrase){showMessage("auditResetMessage","Confirmation text does not match.");return;}
      button.disabled=true;
      try{
        const result=await certified("reset_audit_log",{confirmation_text:config.phrase});
        closeModal();
        alert((result?.deleted_total??0)+" audit record(s) permanently deleted.");
        await renderAudit();
      }catch(error){showMessage("auditResetMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }

  async function openAuditArchive(id){
    try{
      const data=await certified("list_audit_archive_entries_v1",{target_archive_id:id,page_number:1,page_size:100}),rows=Array.isArray(data?.rows)?data.rows:[];
      openModal("Audit archive",id,`<div class="table-wrap audit-scroll"><table><thead><tr><th>Time</th><th>Action</th><th>Table</th><th>Record</th><th>Reason</th></tr></thead><tbody>${rows.length?rows.map(x=>`<tr><td>${formatDateTime(x.created_at)}</td><td>${esc(x.action||"")}</td><td>${esc(x.table_name||"")}</td><td>${esc(x.record_id||"")}</td><td>${esc(x.reason||"")}</td></tr>`).join(""):'<tr><td colspan="5">Archive is empty.</td></tr>'}</tbody></table></div>`,'<button id="auditArchiveClose" class="button primary" type="button">Close</button>');
      byId("auditArchiveClose").onclick=closeModal;
    }catch(error){alert(friendly(error));}
  }

  // ---------- Security ----------
  async function renderSecurity(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Security</h3><p>Authenticator factors for the current school account.</p></div><div class="page-actions"><button id="securityEnroll" class="button primary" type="button">Add authenticator</button></div></div><section id="securityFactors">${loading("Loading MFA factors")}</section>`;
    byId("securityEnroll").onclick=openMfaEnrollment;await loadMfaFactors();
  }
  async function loadMfaFactors(){
    const box=byId("securityFactors");if(!box)return;
    try{
      const data=await api().mfaFactors(),rows=Array.isArray(data?.factors)?data.factors:Array.isArray(data)?data:[];
      box.innerHTML=rows.length?`<section class="panel"><div class="table-wrap"><table><thead><tr><th>Name</th><th>Status</th><th>Created</th><th>Last used</th><th>Actions</th></tr></thead><tbody>${rows.map(x=>`<tr><td>${esc(x.friendlyName||x.friendly_name||"Authenticator")}</td><td>${status(x.verified_at||x.verified?"verified":"pending")}</td><td>${formatDateTime(x.created_at||x.createdAt)}</td><td>${formatDateTime(x.last_used_at||x.lastUsedAt)}</td><td><button class="button danger small" data-mfa-remove="${esc(x.id)}">Remove</button></td></tr>`).join("")}</tbody></table></div></section>`:empty("No authenticator factors are configured.");
      box.querySelectorAll("[data-mfa-remove]").forEach(b=>b.onclick=async()=>{if(!confirm("Remove this authenticator factor?"))return;try{await api().mfaRemove(b.dataset.mfaRemove);await loadMfaFactors();}catch(error){alert(friendly(error));}});
    }catch(error){box.innerHTML=pageError(error);}
  }
  function openMfaEnrollment(){
    openModal("Add authenticator","Create a TOTP factor, then verify the current 6-digit code.",`<form id="mfaEnrollForm" class="form-stack"><label class="field"><span>Friendly name</span><input name="friendlyName" placeholder="My authenticator" required></label><p id="mfaEnrollMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="mfaEnrollCancel" class="button ghost" type="button">Cancel</button><button id="mfaEnrollStart" class="button primary" type="submit" form="mfaEnrollForm">Create factor</button>');
    byId("mfaEnrollCancel").onclick=closeModal;
    byId("mfaEnrollForm").onsubmit=async e=>{e.preventDefault();const button=byId("mfaEnrollStart");button.disabled=true;try{const result=await api().mfaEnroll(formValues(e.currentTarget).friendlyName),enrollment=result?.enrollment||result;showMfaVerification(enrollment);}catch(error){showMessage("mfaEnrollMessage",friendly(error));}finally{button.disabled=false;}};
  }
  function showMfaVerification(enrollment){
    byId("modalTitle").textContent="Verify authenticator";byId("modalSubtitle").textContent="Add the setup key to your authenticator app, then enter the current code.";
    byId("modalBody").innerHTML=`<div class="panel pad"><p>Setup key</p><code>${esc(enrollment?.secret||enrollment?.setup?.secret||"")}</code></div><form id="mfaVerifyForm" class="form-stack"><label class="field"><span>6-digit code</span><input name="code" inputmode="numeric" autocomplete="one-time-code" required></label><p id="mfaVerifyMessage" class="form-message hidden" role="alert"></p></form>`;
    byId("modalFooter").innerHTML='<button id="mfaVerifyCancel" class="button ghost" type="button">Cancel</button><button id="mfaVerifySave" class="button primary" type="submit" form="mfaVerifyForm">Verify factor</button>';
    byId("mfaVerifyCancel").onclick=closeModal;byId("mfaVerifyForm").onsubmit=async e=>{e.preventDefault();const id=enrollment?.id||enrollment?.factorId||enrollment?.factor_id,button=byId("mfaVerifySave");button.disabled=true;try{await api().mfaVerify(id,formValues(e.currentTarget).code);closeModal();await loadMfaFactors();}catch(error){showMessage("mfaVerifyMessage",friendly(error));}finally{button.disabled=false;}};
  }

  // ---------- Finance ----------
  async function renderFinance(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Finance</h3><p>Fee balances, invoices and payment activity.</p></div></div>${loading("Loading finance workspace")}`;
    try{
      const [summary,invoices,payments]=await Promise.all([api().listFinanceSummary(),api().listFinanceInvoices({limit:100}),api().listFinancePayments({limit:100})]);
      const invoiceRows=Array.isArray(invoices?.rows)?invoices.rows:[],paymentRows=Array.isArray(payments?.rows)?payments.rows:[];
      byId("content").innerHTML=`<div class="page-head"><div><h3>Finance</h3><p>Fee balances, invoices and payment activity.</p></div></div>
        <section class="stat-grid"><article class="stat-card"><span class="stat-icon gold">¤</span><div><span>Outstanding</span><strong>${formatAmount(summary.outstanding)}</strong></div></article><article class="stat-card"><span class="stat-icon green">+</span><div><span>Received today</span><strong>${formatAmount(summary.received_today)}</strong></div></article><article class="stat-card"><span class="stat-icon purple">!</span><div><span>Overdue invoices</span><strong>${esc(summary.overdue_invoices??0)}</strong></div></article></section>
        <section class="panel"><div class="panel-header"><div><h3>Invoices</h3><p>Latest 100 tenant invoices</p></div></div><div class="table-wrap"><table><thead><tr><th>Invoice</th><th>Student</th><th>Term</th><th>Due</th><th>Paid</th><th>Balance</th><th>Status</th><th>Due date</th></tr></thead><tbody>${invoiceRows.length?invoiceRows.map(x=>`<tr><td>${esc(x.invoice_no||"")}</td><td>${esc(x.student_name||x.student_id||"")}</td><td>${esc(x.term_name||"")}</td><td>${formatAmount(x.amount_due)}</td><td>${formatAmount(x.amount_paid)}</td><td>${formatAmount(Number(x.amount_due||0)-Number(x.amount_paid||0))}</td><td>${status(x.status)}</td><td>${formatDate(x.due_date)}</td></tr>`).join(""):'<tr><td colspan="8">No invoices.</td></tr>'}</tbody></table></div></section>
        <section class="panel"><div class="panel-header"><div><h3>Payments</h3><p>Latest 100 non-reversed and reversed receipts</p></div></div><div class="table-wrap"><table><thead><tr><th>Receipt</th><th>Student</th><th>Invoice</th><th>Amount</th><th>Method</th><th>Reference</th><th>Received</th><th>Status</th></tr></thead><tbody>${paymentRows.length?paymentRows.map(x=>`<tr><td>${esc(x.receipt_no||"")}</td><td>${esc(x.student_name||x.student_id||"")}</td><td>${esc(x.invoice_no||"—")}</td><td>${formatAmount(x.amount)}</td><td>${esc(x.method||"")}</td><td>${esc(x.reference||"")}</td><td>${formatDateTime(x.received_at)}</td><td>${status(x.reversed_at?"reversed":"received")}</td></tr>`).join(""):'<tr><td colspan="8">No payments.</td></tr>'}</tbody></table></div></section>`;
    }catch(error){byId("content").innerHTML=pageError(error);}
  }
  registerView({id:"audit",label:"Audit Trail",icon:"◎",subtitle:"Record changes and accountability",permission:"view_audit",feature:"governance",render:renderAudit});
  registerView({id:"security",label:"Security",icon:"⌾",subtitle:"Multi-factor authentication and account security",render:renderSecurity});
  registerView({id:"finance",label:"Finance",icon:"¤",subtitle:"Fees, statements and payroll operations",feature:"finance_fees",roles:["system_admin","accountant","accounts_office","parent_guardian","student","class_teacher","subject_teacher"],render:renderFinance});
})();
