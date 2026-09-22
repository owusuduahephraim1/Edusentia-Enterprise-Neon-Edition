(() => {
  "use strict";
  if (window.EdusentiaFinanceInvoices) return;
  const F=window.EdusentiaFinanceRuntime;
  if(!F) return;

  const {S,byId,esc,attr,money,date,statusLabel,statusClass,rpc,notify,options,termsForYear,printHtml,schoolName}=F;
  let portalLoadToken=0;

  const internalRole=()=>["system_admin","accounts_office","accountant"].includes(String(S.role||""));
  const invoiceRows=data=>Array.isArray(data?.rows)?data.rows:[];

  function invoiceFilterHtml(){
    const years=S.boot?.academic_years||[],terms=termsForYear(S.yearId),classes=S.boot?.classes||[];
    return `<div class="finance-filterbar">
      <label><span>Academic year</span><select id="financeInvoiceYear"><option value="">All years</option>${options(years,'id','name',S.yearId)}</select></label>
      <label><span>Term</span><select id="financeInvoiceTerm"><option value="">All terms</option>${options(terms,'id','name',S.termId)}</select></label>
      <label><span>Class</span><select id="financeInvoiceClass"><option value="">All classes</option>${options(classes,'id','name',S.classId)}</select></label>
      <label><span>Search</span><input id="financeInvoiceSearch" type="search" placeholder="Invoice, student or admission no."></label>
      <button class="button secondary" id="financeInvoiceApply" type="button">Apply</button>
    </div>`;
  }

  function invoiceTable(rows,{showStudent=true}={}){
    return `<div class="finance-table-scroll"><table><thead><tr>
      <th>Invoice</th>${showStudent?'<th>Student</th>':''}<th>Class</th><th>Period</th><th>Issued</th><th>Due date</th><th>Paid</th><th>Balance</th><th>Status</th><th></th>
    </tr></thead><tbody>${rows.length?rows.map(r=>`<tr>
      <td><strong>${esc(r.invoice_no||'—')}</strong><small>${esc(date(r.issued_at))}</small></td>
      ${showStudent?`<td><strong>${esc(r.student||'')}</strong><small>${esc(r.admission_no||'')}</small></td>`:''}
      <td>${esc(r.class_name||'—')}</td>
      <td>${esc([r.academic_year_name,r.term_name].filter(Boolean).join(' / ')||'—')}</td>
      <td>${money(r.issued_amount)}</td><td>${esc(date(r.due_date))}</td><td>${money(r.paid)}</td><td>${money(r.balance)}</td>
      <td><span class="status ${statusClass(r.status)}">${esc(statusLabel(r.status))}</span></td>
      <td><button class="button ghost small" type="button" data-finance-invoice-print="${attr(r.invoice_id)}">Print</button></td>
    </tr>`).join(''):`<tr><td colspan="${showStudent?10:9}"><div class="empty"><strong>No invoices found</strong></div></td></tr>`}</tbody></table></div>`;
  }

  function invoiceMetrics(rows){
    const issued=rows.reduce((n,r)=>n+Number(r.issued_amount||0),0),paid=rows.reduce((n,r)=>n+Number(r.paid||0),0),balance=rows.reduce((n,r)=>n+Number(r.balance||0),0);
    return `<div class="finance-metrics">
      <div class="finance-metric"><span>Invoices</span><strong>${rows.length}</strong></div>
      <div class="finance-metric"><span>Issued</span><strong>${money(issued)}</strong></div>
      <div class="finance-metric"><span>Paid</span><strong>${money(paid)}</strong></div>
      <div class="finance-metric"><span>Outstanding</span><strong>${money(balance)}</strong></div>
    </div>`;
  }

  async function printInvoice(invoiceId){
    try{
      const d=await rpc('finance_invoice_detail',{target_invoice_id:invoiceId}),school=d.school||{},student=d.student||{},inv=d.invoice||{},account=d.account||{},alloc=d.allocations||[];
      const allocations=alloc.length?alloc.map(x=>`<tr><td>${esc(date(x.transaction_date))}</td><td>${esc(x.receipt_no||statusLabel(x.entry_type)||'—')}</td><td>${esc(statusLabel(x.method||'—'))}</td><td>${esc(x.reference||'—')}</td><td style="text-align:right">${esc(money(x.amount))}</td></tr>`).join(''):'<tr><td colspan="5">No posted payment allocations for this invoice.</td></tr>';
      const body=`
        <style>@page{size:A4 portrait;margin:14mm}.invoice-sheet{max-width:185mm;margin:0 auto;font-family:Arial,sans-serif;color:#14253d}.invoice-head{display:flex;justify-content:space-between;gap:20px;border-bottom:3px solid #0b4da3;padding-bottom:14px}.invoice-head h1{margin:0 0 4px;color:#082f6b}.invoice-title{text-align:right}.invoice-title strong{display:block;font-size:20px}.invoice-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin:18px 0}.invoice-field{border:1px solid #d7e1ed;border-radius:8px;padding:10px}.invoice-field span{display:block;font-size:9px;text-transform:uppercase;color:#6b7b90;font-weight:700}.invoice-field strong{display:block;margin-top:4px}.invoice-summary{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:16px 0}.invoice-card{border:1px solid #d7e1ed;border-radius:8px;padding:12px}.invoice-card span{display:block;font-size:9px;text-transform:uppercase;color:#6b7b90;font-weight:700}.invoice-card strong{display:block;font-size:18px;margin-top:4px;color:#0b3269}.invoice-sheet table{width:100%;border-collapse:collapse;margin-top:10px}.invoice-sheet th,.invoice-sheet td{border:1px solid #d9e2ec;padding:8px;text-align:left}.invoice-sheet th{background:#eef4fb}.invoice-footer{margin-top:22px;border-top:1px solid #d9e2ec;padding-top:10px;color:#6c7b8f;font-size:9px}</style>
        <article class="invoice-sheet">
          <header class="invoice-head"><div><h1>${esc(school.school_name||schoolName())}</h1><div>${esc([school.address,school.phone,school.email,school.website].filter(Boolean).join(' • '))}</div></div><div class="invoice-title"><strong>Fee Invoice</strong><span>${esc(inv.invoice_no||'')}</span></div></header>
          <section class="invoice-grid"><div class="invoice-field"><span>Student</span><strong>${esc(student.full_name||'—')}</strong></div><div class="invoice-field"><span>Admission No.</span><strong>${esc(student.admission_no||'—')}</strong></div><div class="invoice-field"><span>Academic period</span><strong>${esc([account.academic_year_name,account.term_name].filter(Boolean).join(' / ')||'—')}</strong></div><div class="invoice-field"><span>Class</span><strong>${esc(account.class_name||'—')}</strong></div><div class="invoice-field"><span>Issue date</span><strong>${esc(date(inv.issued_at))}</strong></div><div class="invoice-field"><span>Due date</span><strong>${esc(date(inv.due_date))}</strong></div></section>
          <table><thead><tr><th>Description</th><th style="text-align:right">Amount</th></tr></thead><tbody><tr><td>${esc(inv.description||'Term fee')}</td><td style="text-align:right">${esc(money(inv.issued_amount))}</td></tr></tbody></table>
          <section class="invoice-summary"><div class="invoice-card"><span>Invoice amount</span><strong>${esc(money(inv.issued_amount))}</strong></div><div class="invoice-card"><span>Paid</span><strong>${esc(money(account.paid))}</strong></div><div class="invoice-card"><span>Outstanding</span><strong>${esc(money(account.balance))}</strong></div></section>
          <h3>Allocated payments and adjustments</h3><table><thead><tr><th>Date</th><th>Receipt / Entry</th><th>Method</th><th>Reference</th><th style="text-align:right">Amount</th></tr></thead><tbody>${allocations}</tbody></table>
          <footer class="invoice-footer">${esc(school.report_footer||'Computer-generated finance record from Edusentia Enterprise.')} • ${esc(school.tenant_code||'')}</footer>
        </article>`;
      printHtml(`Invoice ${inv.invoice_no||''}`,body);
    }catch(e){notify('Invoice could not be opened',F.friendly(e),'error')}
  }

  function bindInvoicePrint(root){root.querySelectorAll('[data-finance-invoice-print]').forEach(b=>b.onclick=()=>printInvoice(b.dataset.financeInvoicePrint));}

  async function renderAdminInvoices(root,tabButton,tabs){
    tabs.querySelectorAll('[data-finance-tab]').forEach(x=>x.classList.toggle('active',x===tabButton));
    root.innerHTML='<div class="finance-loading">Loading invoices…</div>';
    try{
      const data=await rpc('finance_invoice_register',{target_academic_year_id:S.yearId||null,target_term_id:S.termId||null,target_class_id:S.classId||null});
      const all=invoiceRows(data);
      root.innerHTML=`${invoiceFilterHtml()}${invoiceMetrics(all)}<section class="panel"><div class="panel-header"><div><h3>Fee invoices</h3><p>Immutable invoice identities linked to the authoritative fee ledger</p></div></div><div id="financeInvoiceRows">${invoiceTable(all)}</div></section>`;
      const year=byId('financeInvoiceYear'),term=byId('financeInvoiceTerm'),clazz=byId('financeInvoiceClass'),search=byId('financeInvoiceSearch');
      const applySearch=()=>{const q=String(search?.value||'').trim().toLowerCase(),rows=q?all.filter(r=>[r.invoice_no,r.student,r.admission_no,r.class_name,r.academic_year_name,r.term_name,r.status].some(v=>String(v||'').toLowerCase().includes(q))):all;const slot=byId('financeInvoiceRows');if(slot){slot.innerHTML=invoiceTable(rows);bindInvoicePrint(slot)}};
      search?.addEventListener('input',applySearch);
      year?.addEventListener('change',()=>{const ts=termsForYear(year.value);if(term)term.innerHTML='<option value="">All terms</option>'+options(ts,'id','name','')});
      byId('financeInvoiceApply')?.addEventListener('click',()=>{S.yearId=year?.value||'';S.termId=term?.value||'';S.classId=clazz?.value||'';renderAdminInvoices(root,tabButton,tabs)});
      bindInvoicePrint(root);
    }catch(e){root.innerHTML=`<section class="panel pad finance-error"><strong>Invoices could not be loaded</strong><span>${esc(F.friendly(e))}</span></section>`;}
  }

  function injectAdminTab(){
    if(!internalRole())return;
    const tabs=document.querySelector('.finance-workspace .finance-tabs'),body=byId('financeTabBody');
    if(!tabs||!body||tabs.querySelector('[data-finance-tab="invoices"]'))return;
    const b=document.createElement('button');
    b.className='finance-tab';b.type='button';b.dataset.financeTab='invoices';b.textContent='Invoices';
    b.onclick=()=>{S.tab='invoices';renderAdminInvoices(body,b,tabs)};
    const statements=tabs.querySelector('[data-finance-tab="statements"]');
    statements?.insertAdjacentElement('afterend',b)||tabs.appendChild(b);
  }

  async function injectPortalInvoices(){
    if(!['parent_guardian','student'].includes(String(S.role||'')))return;
    const workspace=document.querySelector('#content .finance-workspace');
    if(!workspace||workspace.querySelector('[data-finance-portal-invoices]'))return;
    const token=++portalLoadToken;
    const panel=document.createElement('section');panel.className='panel';panel.dataset.financePortalInvoices='loading';
    panel.innerHTML='<div class="panel-header"><div><h3>Fee Invoices</h3><p>Loading authorized invoice records…</p></div></div>';
    workspace.appendChild(panel);
    try{
      const data=await rpc('finance_my_invoices');if(token!==portalLoadToken||!panel.isConnected)return;
      const rows=Array.isArray(data?.invoices)?data.invoices:[];
      panel.dataset.financePortalInvoices='ready';
      panel.innerHTML=`<div class="panel-header"><div><h3>Fee Invoices</h3><p>Read-only invoices for ${S.role==='parent_guardian'?'linked students':'your student record'}</p></div></div>${invoiceTable(rows,{showStudent:S.role==='parent_guardian'})}`;
      bindInvoicePrint(panel);
    }catch(e){if(panel.isConnected){panel.dataset.financePortalInvoices='error';panel.innerHTML=`<div class="panel-header"><div><h3>Fee Invoices</h3><p>${esc(F.friendly(e))}</p></div></div>`;}}
  }

  function reconcile(){injectAdminTab();injectPortalInvoices();}
  const observer=new MutationObserver(()=>queueMicrotask(reconcile));
  observer.observe(document.documentElement,{childList:true,subtree:true});
  document.addEventListener('click',e=>{if(e.target.closest('.finance-nav-item'))setTimeout(reconcile,80)},true);
  window.EdusentiaFinanceInvoices={reconcile,printInvoice};
  reconcile();
})();