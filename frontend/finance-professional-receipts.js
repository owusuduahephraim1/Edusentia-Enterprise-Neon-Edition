(() => {
  "use strict";
  const F=window.EdusentiaFinanceRuntime;
  if(!F||window.EdusentiaProfessionalFinanceReceipts?.version==="v2")return;
  const esc=v=>F.esc?.(v)??String(v??"");
  const money=v=>F.money?.(v)??`GHS ${Number(v||0).toFixed(2)}`;
  const date=v=>F.date?.(v)??String(v||"");
  const statusLabel=v=>F.statusLabel?.(v)??String(v||"").replaceAll("_"," ");
  const receiverRoleLabel=v=>({system_admin:"System Administrator",accountant:"Accountant",principal:"Principal",class_teacher:"Class Teacher",subject_teacher:"Subject Teacher",parent_guardian:"Parent or Guardian",student:"Student"}[String(v||"")]||String(v||"Authorized Receiver").replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase()));
  let restoringFinance=false,restoreTimer=0;
  function logoUrl(){
    for(const image of [document.getElementById("brandLogo"),...document.querySelectorAll("[data-school-logo],.sidebar-brand img")]){
      const src=String(image?.currentSrc||image?.src||"").trim();
      if(src)return src;
    }
    return "";
  }
  function wordsUnderThousand(n){
    const ones=["","One","Two","Three","Four","Five","Six","Seven","Eight","Nine","Ten","Eleven","Twelve","Thirteen","Fourteen","Fifteen","Sixteen","Seventeen","Eighteen","Nineteen"],tens=["","","Twenty","Thirty","Forty","Fifty","Sixty","Seventy","Eighty","Ninety"];
    n=Math.floor(n);let out=[];
    if(n>=100){out.push(`${ones[Math.floor(n/100)]} Hundred`);n%=100}
    if(n>=20){out.push(tens[Math.floor(n/10)]);if(n%10)out.push(ones[n%10])}else if(n>0)out.push(ones[n]);
    return out.join(" ");
  }
  function amountInWords(value){
    let amount=Math.max(0,Number(value||0)),cedis=Math.floor(amount),pesewas=Math.round((amount-cedis)*100),parts=[];
    const scales=[[1000000000,"Billion"],[1000000,"Million"],[1000,"Thousand"]];
    for(const [size,label] of scales){if(cedis>=size){parts.push(`${wordsUnderThousand(Math.floor(cedis/size))} ${label}`);cedis%=size}}
    if(cedis>0)parts.push(wordsUnderThousand(cedis));
    if(!parts.length)parts.push("Zero");
    let result=`${parts.join(" ")} Ghana Cedi${Number(value)==1?"":"s"}`;
    if(pesewas)result+=` and ${wordsUnderThousand(pesewas)} Pesewa${pesewas===1?"":"s"}`;
    return `${result} Only`;
  }
  function receiptBody(register,row){
    const school=register?.school||{},logo=logoUrl(),balance=Number(row.balance||0),reference=String(row.reference||"").trim()||"Not provided";
    const contact=[school.address,school.phone,school.email,school.website].filter(Boolean);
    return `<style>
      @page{size:A6 portrait;margin:5mm}
      html,body{margin:0!important;padding:0!important;background:#fff!important;-webkit-print-color-adjust:exact;print-color-adjust:exact}
      *{box-sizing:border-box}
      .a6-receipt{position:relative;width:95mm;max-width:95mm;min-height:138mm;margin:0 auto;border:1px solid #cfd9e7;background:#fff;color:#12233c;font-family:Arial,Helvetica,sans-serif;overflow:hidden;break-inside:avoid;page-break-inside:avoid}
      .a6-top{height:3mm;background:#0b4da3}
      .a6-head{display:grid;grid-template-columns:15mm 1fr;gap:3mm;padding:4mm 4mm 3mm;border-bottom:1px solid #d7e0ec}
      .a6-logo{width:13mm;height:13mm;object-fit:contain}
      .a6-school h1{margin:0;color:#082f6b;font-size:11pt;line-height:1.05}.a6-school .motto{margin:1mm 0 0;font-size:5.5pt;font-weight:700;color:#556a83}.a6-contact{margin-top:1.2mm;font-size:4.9pt;line-height:1.35;color:#66788f}.a6-contact span{display:block}
      .a6-title{display:flex;align-items:flex-end;justify-content:space-between;gap:3mm;padding:2.5mm 4mm;background:#f5f8fc;border-bottom:1px solid #d7e0ec}.a6-title strong{font-size:8.5pt;color:#0b3b7c}.a6-title span{font-size:5.5pt;font-family:Consolas,monospace;color:#52657b;text-align:right}
      .a6-body{padding:3mm 4mm}.a6-grid{display:grid;grid-template-columns:1fr 1fr;gap:1.8mm 3mm}.a6-field{border-bottom:1px dotted #c9d3df;padding:0 0 1.4mm}.a6-field span{display:block;font-size:4.8pt;text-transform:uppercase;letter-spacing:.25px;color:#728197;font-weight:700}.a6-field strong{display:block;margin-top:.5mm;font-size:6.5pt;color:#12233c;overflow-wrap:anywhere}
      .a6-payment{display:grid;grid-template-columns:1.15fr .85fr;gap:2mm;margin:3mm 0}.a6-amount,.a6-balance{border-radius:2mm;padding:2.7mm}.a6-amount{background:#0b4da3;color:#fff}.a6-balance{background:#fff8e8;border:1px solid #ecd8a8}.a6-amount span,.a6-balance span{display:block;font-size:4.7pt;text-transform:uppercase;letter-spacing:.3px;font-weight:700}.a6-amount strong{display:block;font-size:12pt;margin:.5mm 0}.a6-amount small{display:block;font-size:4.5pt;line-height:1.25;opacity:.9}.a6-balance strong{display:block;font-size:10pt;color:#8a5a00;margin:.8mm 0}.a6-balance small{display:block;font-size:4.5pt;line-height:1.25;color:#6b5c3d}
      .a6-ledger{width:100%;border-collapse:collapse;margin:0}.a6-ledger th,.a6-ledger td{border:1px solid #d7e0eb;padding:1.5mm;font-size:5.2pt}.a6-ledger th{width:24%;background:#f3f6fa;color:#52657b;text-transform:uppercase;font-size:4.5pt}.a6-ledger td{color:#14263e}.a6-status{font-weight:800;color:#14724d}.a6-status.reversed{color:#a1353d}
      .a6-receiver{display:flex;justify-content:space-between;gap:3mm;margin-top:2.5mm;padding-top:2mm;border-top:1px solid #d9e1eb;font-size:5pt;color:#66778c}.a6-receiver strong{display:block;color:#24364e;font-size:5.8pt;margin-bottom:.4mm}
      .a6-footer{position:absolute;left:0;right:0;bottom:0;padding:2mm 4mm;background:#f5f8fc;border-top:1px solid #d7e0ec;text-align:center}.a6-footer strong{display:block;font-size:5.2pt;color:#0b4da3}.a6-footer p{margin:.6mm 0 0;font-size:4.2pt;color:#708096;line-height:1.3}.a6-token{font-size:3.8pt;margin-top:.6mm;color:#8a97a7;word-break:break-all}
      @media print{html,body{width:105mm!important;height:148mm!important;overflow:hidden!important}.a6-receipt{margin:0 auto!important}.a6-head,.a6-title,.a6-body,.a6-payment,.a6-ledger,.a6-footer{break-inside:avoid!important;page-break-inside:avoid!important}}
    </style>
    <article class="a6-receipt">
      <div class="a6-top"></div>
      <header class="a6-head">
        <div>${logo?`<img class="a6-logo" src="${esc(logo)}" alt="School logo">`:""}</div>
        <div class="a6-school"><h1>${esc(school.school_name||F.schoolName?.()||"School")}</h1>${school.motto?`<div class="motto">${esc(school.motto)}</div>`:""}<div class="a6-contact">${contact.map(v=>`<span>${esc(v)}</span>`).join("")}</div></div>
      </header>
      <div class="a6-title"><strong>OFFICIAL FEE RECEIPT</strong><span>${esc(row.receipt_no||"")}</span></div>
      <main class="a6-body">
        <div class="a6-grid">
          <div class="a6-field"><span>Student</span><strong>${esc(row.student||"")}</strong></div><div class="a6-field"><span>Admission No.</span><strong>${esc(row.admission_no||"")}</strong></div>
          <div class="a6-field"><span>Class</span><strong>${esc(row.class_name||"")}</strong></div><div class="a6-field"><span>Academic period</span><strong>${esc([row.academic_year_name,row.term_name].filter(Boolean).join(" • "))}</strong></div>
          <div class="a6-field"><span>Payment date</span><strong>${esc(date(row.transaction_date))}</strong></div><div class="a6-field"><span>Term fee</span><strong>${esc(money(row.due))}</strong></div>
        </div>
        <div class="a6-payment"><div class="a6-amount"><span>Amount received</span><strong>${esc(money(row.transaction_amount))}</strong><small>${esc(amountInWords(row.transaction_amount))}</small></div><div class="a6-balance"><span>Balance</span><strong>${esc(money(balance))}</strong><small>${balance<=0?"Fee obligation fully settled.":"Outstanding after this payment."}</small></div></div>
        <table class="a6-ledger"><tbody>
          <tr><th>Method</th><td>${esc(statusLabel(row.method))}</td><th>Status</th><td class="a6-status ${row.reversed?"reversed":""}">${row.reversed?"Reversed":"Posted"}</td></tr>
          <tr><th>Reference</th><td colspan="3">${esc(reference)}</td></tr>
          <tr><th>Received by</th><td colspan="3">${esc(row.received_by||"Accounts Office")}</td></tr>
        </tbody></table>
        <div class="a6-receiver"><div><strong>${esc(row.received_by||"Accounts Office")}</strong>${esc(receiverRoleLabel(row.received_by_role))} / Authorized Receiver</div><div style="text-align:right"><strong>${esc(school.tenant_code||"")}</strong>School tenant code</div></div>
      </main>
      <footer class="a6-footer"><strong>Thank you. This is an official school fee receipt.</strong><p>Computer-generated from the Edusentia Finance Ledger. Corrections must use the authorized reversal process.</p><div class="a6-token">Transaction ID: ${esc(row.transaction_id||"")}</div></footer>
    </article>`;
  }
  async function printReceipt(transactionId){
    try{
      const data=await F.rpc("finance_payment_register",{target_academic_year_id:F.S.yearId||null,target_term_id:F.S.termId||null,target_class_id:F.S.classId||null});
      const row=(data?.rows||[]).find(x=>String(x.transaction_id)===String(transactionId));
      if(!row)throw new Error("receipt_not_found");
      F.printHtml(`Receipt ${row.receipt_no||""}`,receiptBody(data,row));
    }catch(error){F.notify?.("Receipt not printed",F.friendly?.(error)||String(error),"error")}
  }
  async function printStudentPortalDocument(kind){
    try{
      const printers=window.EdusentiaFinancePortals;
      if(!printers?.printFee||!printers?.printFeeSummary)throw new Error("finance_print_service_unavailable");
      const data=await F.rpc("get_my_student_portal_v2");
      const statement=data?.fee_statement;
      if(!statement)throw new Error("fee_statement_unavailable");
      if(kind==="summary")printers.printFeeSummary(statement);else printers.printFee(statement);
    }catch(error){F.notify?.("Fee document not printed",F.friendly?.(error)||String(error),"error")}
  }
  function bindStudentPortalPrint(root=document){
    if(String(F.S?.role||F.S?.boot?.profile?.role||"")!=="student")return;
    const button=root.querySelector?.("#studentPortalPrintFees")||document.getElementById("studentPortalPrintFees");
    if(!button||button.dataset.brandedFinancePrint==="1")return;
    const replacement=button.cloneNode(true);
    replacement.id="studentPortalPrintFees";
    replacement.textContent="Full statement";
    replacement.dataset.brandedFinancePrint="1";
    button.replaceWith(replacement);
    replacement.onclick=event=>{event.preventDefault();event.stopImmediatePropagation();void printStudentPortalDocument("full")};
    if(!document.getElementById("studentPortalPrintFeeSummary")){
      const summary=document.createElement("button");
      summary.id="studentPortalPrintFeeSummary";
      summary.type="button";
      summary.className="button ghost small";
      summary.textContent="A6 summary";
      summary.onclick=event=>{event.preventDefault();event.stopImmediatePropagation();void printStudentPortalDocument("summary")};
      replacement.insertAdjacentElement("afterend",summary);
    }
  }
  function bind(root=document){
    root.querySelectorAll?.("[data-receipt]").forEach(button=>{if(button.dataset.professionalReceiptV2Bound)return;button.dataset.professionalReceiptV2Bound="1";button.onclick=event=>{event.preventDefault();event.stopImmediatePropagation();void printReceipt(button.dataset.receipt)}});
    bindStudentPortalPrint(root);
  }
  function financeWasReplacedByDashboard(){
    if(!F.S?.active)return false;
    const content=F.byId?.("content")||document.getElementById("content");
    if(!content||content.querySelector(".finance-workspace"))return false;
    const text=String(content.textContent||"");
    return /System Administration Dashboard|Principal Dashboard|Teacher Dashboard|Parent and Guardian Dashboard/.test(text);
  }
  function restoreFinanceWorkspace(){
    if(!financeWasReplacedByDashboard()||restoringFinance)return;
    clearTimeout(restoreTimer);
    restoreTimer=setTimeout(async()=>{
      if(!financeWasReplacedByDashboard()||restoringFinance)return;
      restoringFinance=true;
      try{await F.open()}catch(error){console.warn("finance_session_restore_failed",error)}finally{restoringFinance=false}
    },20);
  }
  const observer=new MutationObserver(records=>{
    if(records.some(record=>record.addedNodes.length||record.removedNodes.length))queueMicrotask(()=>{bind(document);restoreFinanceWorkspace()});
  });
  observer.observe(document.documentElement,{childList:true,subtree:true});
  bind(document);restoreFinanceWorkspace();
  window.EdusentiaProfessionalFinanceReceipts={version:"v2",printReceipt,bind,restoreFinanceWorkspace};
})();