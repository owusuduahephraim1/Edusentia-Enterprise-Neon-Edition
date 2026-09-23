(() => {
  "use strict";
  const LOGIN_TAGLINE="STUDENT ACADEMIC SERVICE",SHELL_SUBTITLE="Academic Service",ENROLL_FLAG="edusentia_v9_mfa_enrollment_pending";
  const RELEVANT_SELECTOR="#brandLogo,[data-school-logo],[data-brand-subtitle],[data-shell-subtitle],.sidebar-brand small,img.signed-photo,#recordPhoto,#mfaRecoveryCodeButton,#mfaRequestResetButton,#mfaQr,#modal,#modalTitle,#modalFooter,#appShell";
  let scheduled=false,issuing=false,structuralObserver=null,stateObserver=null;
  const observedStateTargets=new WeakSet();
  const byId=id=>document.getElementById(id);
  function isTenantWorkspace(){const c=window.RCE_CONFIG||window.NIS_CONFIG||{};if(String(c.tenantCode||"").trim())return true;const p=new URLSearchParams(location.search);return Boolean(p.get("tenant"))&&p.get("platform")!=="1"}
  function schoolLogoUrl(){for(const image of [byId("brandLogo"),...document.querySelectorAll("[data-school-logo]")]){const v=String(image?.currentSrc||image?.src||"").trim();if(v)return v}return""}
  function applyAcademicServiceBranding(){if(!isTenantWorkspace())return;document.querySelectorAll("[data-brand-subtitle]").forEach(e=>{if(e.textContent!==LOGIN_TAGLINE)e.textContent=LOGIN_TAGLINE});document.querySelectorAll("[data-shell-subtitle]").forEach(e=>{if(e.textContent!==SHELL_SUBTITLE)e.textContent=SHELL_SUBTITLE});const e=document.querySelector(".sidebar-brand small");if(e&&e.textContent!==SHELL_SUBTITLE)e.textContent=SHELL_SUBTITLE}
  function applyStudentPhotoFallbacks(){if(!isTenantWorkspace())return;const logo=schoolLogoUrl();if(!logo)return;document.querySelectorAll("img.signed-photo").forEach(image=>{if(!String(image.dataset.photo||"").trim()&&image.src!==logo)image.src=logo});const record=byId("recordPhoto");if(record){const current=String(record.currentSrc||record.src||"");if(/rce-master-logo|edusentia-mark|school-logo/i.test(current)&&current!==logo)record.src=logo}}
  function tenantClient(){return window.EDS_TENANT_AUTH_CLIENT||window.EdusentiaCompatClient||null}
  async function edge(action,payload={}){const client=tenantClient();if(!client)throw new Error("Tenant authentication service unavailable");const {data,error}=await client.functions.invoke("tenant-auth-recovery",{body:{action,...payload}});if(error)throw error;if(!data?.ok)throw new Error(String(data?.error||"Recovery request failed").replaceAll("_"," "));return data}
  function ensureCodesDialog(){let d=byId("v9RecoveryCodesDialog");if(d)return d;d=document.createElement("dialog");d.id="v9RecoveryCodesDialog";d.className="modal";d.innerHTML='<div class="modal-frame"><header class="modal-header"><div><h3>MFA recovery codes</h3><p>System Administrator security</p></div></header><section class="modal-body"><div class="template-information warning"><strong>Store these codes now</strong><span>Each code works once if your authenticator device is lost. Edusentia stores only protected hashes and cannot show this set again.</span></div><div id="v9RecoveryCodesGrid" class="recovery-code-grid"></div><p class="help-text">Keep a copy in a secure offline location. Generating a new set invalidates the previous set.</p></section><footer class="modal-footer"><button class="button ghost" id="v9RecoveryCodesCopy" type="button">Copy codes</button><button class="button secondary" id="v9RecoveryCodesDownload" type="button">Download text file</button><button class="button primary" id="v9RecoveryCodesSaved" type="button">I saved these codes</button></footer></div>';document.body.appendChild(d);return d}
  function downloadCodes(codes){const blob=new Blob([["Edusentia Enterprise MFA Recovery Codes","Each code works once.","",...codes].join("\n")],{type:"text/plain;charset=utf-8"}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=`edusentia-mfa-recovery-codes-${new Date().toISOString().slice(0,10)}.txt`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}
  function showCodes(codes){const d=ensureCodesDialog(),grid=byId("v9RecoveryCodesGrid");grid.innerHTML=codes.map(code=>`<code>${String(code).replace(/[<&]/g,"")}</code>`).join("");byId("v9RecoveryCodesCopy").onclick=()=>navigator.clipboard?.writeText(codes.join("\n")).catch(()=>{});byId("v9RecoveryCodesDownload").onclick=()=>downloadCodes(codes);byId("v9RecoveryCodesSaved").onclick=()=>d.close();if(!d.open)d.showModal()}
  async function issueCodes(){if(issuing)return;issuing=true;try{const data=await edge("issue_recovery_codes");if(Array.isArray(data.codes)&&data.codes.length)showCodes(data.codes)}catch(error){console.warn("mfa_recovery_codes_issue_failed",error)}finally{issuing=false}}
  async function useRecoveryCode(){const ask=window.EdusentiaPrompt||window.EdusentiaShell?.promptAction;if(typeof ask!=="function"){window.EdusentiaNotify?.("Recovery unavailable","The secure recovery dialog could not be opened.","error");return;}const code=await ask("Enter one Edusentia MFA recovery code (EDS-XXXXX-XXXXX):","",{title:"Use MFA recovery code",confirmLabel:"Verify code",required:true});if(code===null)return;try{await edge("redeem_recovery_code",{recovery_code:String(code).trim()});window.EdusentiaNotify?.("Authenticator revoked","Edusentia will reload and require a new authenticator QR enrollment.","success");setTimeout(()=>location.reload(),900)}catch(error){window.EdusentiaNotify?.("Recovery code not accepted",String(error?.message||error).replaceAll("_"," "),"error")}}
  function bindMfaRecovery(){const use=byId("mfaRecoveryCodeButton"),request=byId("mfaRequestResetButton"),qr=byId("mfaQr");if(use&&!use.dataset.v9Bound){use.dataset.v9Bound="1";use.onclick=useRecoveryCode}if(request&&!request.dataset.v9Bound){request.dataset.v9Bound="1";request.onclick=()=>window.EdusentiaAccessRecovery?.open?.("mfa","")}const enrolling=Boolean(qr&&!qr.classList.contains("hidden")&&qr.querySelector("img"));if(use)use.classList.toggle("hidden",enrolling);if(request)request.classList.toggle("hidden",enrolling);if(enrolling)sessionStorage.setItem(ENROLL_FLAG,"1")}
  function bindSettingsRecovery(){const title=String(byId("modalTitle")?.textContent||"");const footer=byId("modalFooter");if(title!=="Multi-factor Authentication"||!footer||byId("v9MfaRegenerateCodes"))return;const b=document.createElement("button");b.id="v9MfaRegenerateCodes";b.type="button";b.className="button secondary";b.textContent="Regenerate recovery codes";b.onclick=async()=>{try{byId("modal")?.close();await issueCodes()}catch{}};footer.insertBefore(b,footer.lastElementChild)}
  async function finishEnrollmentCodes(){const shell=byId("appShell");if(sessionStorage.getItem(ENROLL_FLAG)!=="1"||!shell||shell.classList.contains("hidden"))return;sessionStorage.removeItem(ENROLL_FLAG);await issueCodes()}
  function observeStateTargets(){if(!stateObserver)stateObserver=new MutationObserver(scheduleApply);for(const id of ["mfaQr","appShell","modal"]){const el=byId(id);if(!el||observedStateTargets.has(el))continue;observedStateTargets.add(el);stateObserver.observe(el,{attributes:true,attributeFilter:["class","open"],childList:true,subtree:id!=="appShell"})}}
  function apply(){scheduled=false;applyAcademicServiceBranding();applyStudentPhotoFallbacks();bindMfaRecovery();bindSettingsRecovery();observeStateTargets();void finishEnrollmentCodes();if(window.RCE_CONFIG?.productVersion==="7.4.0-r40-product-ready-v9")window.RCE_RUNTIME_BUILD="7.4.0-r40-product-ready-v9"}
  function scheduleApply(){if(scheduled)return;scheduled=true;requestAnimationFrame(apply)}
  function nodeRelevant(node){const el=node?.nodeType===1?node:node?.parentElement;if(!el)return false;return Boolean(el.matches?.(RELEVANT_SELECTOR)||el.closest?.("#modal,#mfaQr,#appShell")||el.querySelector?.(RELEVANT_SELECTOR))}
  function startObservers(){if(!document.body)return;if(!structuralObserver){structuralObserver=new MutationObserver(records=>{if(records.some(r=>nodeRelevant(r.target)||[...r.addedNodes,...r.removedNodes].some(nodeRelevant)))scheduleApply()});structuralObserver.observe(document.body,{childList:true,subtree:true})}observeStateTargets()}
  document.addEventListener("load",event=>{const target=event.target;if(target instanceof HTMLImageElement&&(target.matches("img.signed-photo,#recordPhoto,[data-school-logo]")))scheduleApply()},{capture:true,passive:true});
  document.addEventListener("DOMContentLoaded",()=>{startObservers();scheduleApply()},{once:true});window.addEventListener("pageshow",()=>{startObservers();scheduleApply()},{passive:true});if(document.readyState!=="loading"){startObservers();scheduleApply()}
})();

(() => {
  "use strict";
  function loadTenantListResilience(){
    if(document.querySelector('script[data-edusentia-tenant-list-resilience]'))return;
    const script=document.createElement("script");
    script.src="tenant-r40-v9-list-resilience.js?edusentia=r40-product-ready-v9-list-resilience-1";
    script.dataset.edusentiaTenantListResilience="1";
    script.defer=true;
    document.body.appendChild(script);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",loadTenantListResilience,{once:true});else loadTenantListResilience();
})();

(() => {
  "use strict";
  const VERSION="r40-finance-payroll-v1";
  const tenantReady=()=>Boolean(String((window.RCE_CONFIG||window.NIS_CONFIG||{}).tenantCode||"").trim());
  function loadCss(){if(document.querySelector('link[data-edusentia-finance]'))return;const link=document.createElement("link");link.rel="stylesheet";link.href=`finance-enterprise.css?edusentia=${VERSION}`;link.dataset.edusentiaFinance="1";document.head.appendChild(link)}
  function loadScript(src,key){return new Promise((resolve,reject)=>{const existing=document.querySelector(`script[data-edusentia-finance-module="${key}"]`);if(existing){if(existing.dataset.loaded==="1")resolve();else existing.addEventListener("load",()=>resolve(),{once:true});return}const script=document.createElement("script");script.src=`${src}?edusentia=${VERSION}`;script.defer=true;script.dataset.edusentiaFinanceModule=key;script.addEventListener("load",()=>{script.dataset.loaded="1";resolve()},{once:true});script.addEventListener("error",()=>reject(new Error(`Finance module failed to load: ${src}`)),{once:true});document.body.appendChild(script)})}
  function installFinancePrintFrame(){
    const F=window.EdusentiaFinanceRuntime;
    if(!F||F.__printFrameInstalled)return;
    F.__printFrameInstalled=true;
    F.printHtml=(title,body)=>{
      document.getElementById("edusentiaFinancePrintFrame")?.remove();
      const frame=document.createElement("iframe");
      frame.id="edusentiaFinancePrintFrame";frame.setAttribute("aria-hidden","true");frame.tabIndex=-1;
      Object.assign(frame.style,{position:"fixed",right:"0",bottom:"0",width:"1px",height:"1px",border:"0",opacity:"0",pointerEvents:"none"});
      document.body.appendChild(frame);
      const doc=frame.contentDocument||frame.contentWindow?.document;
      if(!doc){frame.remove();F.notify?.("Print unavailable","The browser could not create the print document.","warning");return}
      const safeTitle=String(title||"Edusentia").replace(/[&<>\"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'\"':"&quot;"}[c]));
      doc.open();doc.write(`<!doctype html><html><head><meta charset="utf-8"><title>${safeTitle}</title><style>body{font-family:Arial,sans-serif;padding:32px;color:#111}table{width:100%;border-collapse:collapse;margin:16px 0}th,td{padding:8px;border:1px solid #ccc;text-align:left}small{display:block;color:#555}@page{margin:14mm}@media print{button{display:none}}</style></head><body>${body}</body></html>`);doc.close();
      const run=()=>{try{frame.contentWindow?.focus();frame.contentWindow?.print();setTimeout(()=>frame.remove(),1500)}catch(error){console.warn("finance_print_frame_failed",error);frame.remove();F.notify?.("Print unavailable","The browser could not open the print dialog.","warning")}};
      if(doc.readyState==="complete")setTimeout(run,50);else frame.onload=()=>setTimeout(run,50);
    };
  }
  function installFinanceEntitlementUi(){
    const F=window.EdusentiaFinanceRuntime,accounts=window.EdusentiaFinanceAccounts;
    if(!F||!accounts||accounts.__entitlementUiInstalled)return;
    accounts.__entitlementUiInstalled=true;
    const wrapRole=role=>F.register(role,async()=>{
      const flags=F.flags?.()||{},payroll=flags.payroll===true,holds=flags.financial_holds===true;
      if(!holds&&F.S.tab==="holds")F.S.tab="overview";
      if(!payroll&&F.S.tab==="payroll")F.S.tab="overview";
      await accounts.render();
      const subtitle=payroll?"Fees, statements, receipts, financial clearance and payroll operations":holds?"Fees, statements, receipts and financial clearance operations":"Fees, statements, receipts and finance operations";
      const title=role==="system_admin"?(payroll?"Finance & Payroll":"Finance"):"Accounts Office";
      F.heading?.(title,subtitle);
      const root=F.byId?.("content");
      const head=root?.querySelector(".finance-workspace .page-head");
      if(head){const h=head.querySelector("h3"),p=head.querySelector("p");if(h)h.textContent=title;if(p)p.textContent=subtitle}
      if(!holds)root?.querySelectorAll('[data-finance-tab="holds"]').forEach(node=>node.remove());
      if(!payroll)root?.querySelectorAll('[data-finance-tab="payroll"]').forEach(node=>node.remove());
    });
    wrapRole("system_admin");
    wrapRole("accounts_office");
  }
  function installFeeGroupUi(){
    const F=window.EdusentiaFinanceRuntime,accounts=window.EdusentiaFinanceAccounts;
    if(!F||!accounts||accounts.__feeGroupUiInstalled)return;
    accounts.__feeGroupUiInstalled=true;
    async function openFeeGroupSchedule(scheduleId=""){
      const S=F.S;
      let data;
      try{data=await F.rpc("finance_accounts_console",{target_academic_year_id:S.yearId||null,target_term_id:S.termId||null,target_class_id:S.classId||null})}catch(error){F.notify("Fee ranges not loaded",F.friendly(error),"error");return}
      const groups=(data?.fee_groups||[]).filter(g=>g.active!==false),row=(data?.schedules||[]).find(x=>String(x.id)===String(scheduleId))||{};
      if(!groups.length){F.notify("No fee class ranges","Configure at least one active fee group before adding a term fee.","warning");return}
      const years=S.boot?.academic_years||[],selectedYear=row.academic_year_id||S.yearId||years[0]?.id||"",selectedGroup=row.fee_group_id||groups[0]?.id||"";
      const d=F.dialog(scheduleId?"Edit term fee":"Add term fee","One fee amount applies to every class included in the selected fee class range.");
      F.byId("financeDialogBody").innerHTML=`<form id="feeGroupScheduleForm" class="finance-form"><label><span>Academic year</span><select name="academic_year_id">${F.options(years,"id","name",selectedYear)}</select></label><label><span>Term</span><select name="term_id"></select></label><label class="full"><span>Fee Class Range</span><select name="fee_group_id">${F.options(groups,"id","name",selectedGroup)}</select><small id="feeGroupMembers" class="help-text"></small></label><label><span>Amount (GHS)</span><input name="amount" type="number" min="0" step="0.01" value="${F.attr(row.amount??"")}" required></label><label><span>Due date</span><input name="due_date" type="date" value="${F.attr(row.due_date||"")}"></label><label class="full"><span>Description</span><input name="description" value="${F.attr(row.description||"Term fee")}"></label><label class="finance-check full"><input name="active" type="checkbox" ${row.active!==false?"checked":""}><span>Active fee configuration</span></label><div class="button-row full"><button class="button primary" type="submit">Save changes</button><button class="button ghost" id="feeGroupScheduleCancel" type="button">Cancel</button></div></form>`;
      const form=F.byId("feeGroupScheduleForm"),yearSel=form.elements.academic_year_id,termSel=form.elements.term_id,groupSel=form.elements.fee_group_id,memberEl=F.byId("feeGroupMembers");
      const setTerms=()=>{const rows=F.termsForYear(yearSel.value);termSel.innerHTML=F.options(rows,"id","name",row.term_id||S.termId||rows[0]?.id||"")};
      const setMembers=()=>{const g=groups.find(x=>String(x.id)===String(groupSel.value));memberEl.textContent=g?.classes?.length?`Includes: ${g.classes.map(c=>c.name).join(", ")}`:"No classes assigned to this range."};
      setTerms();setMembers();yearSel.onchange=setTerms;groupSel.onchange=setMembers;F.byId("feeGroupScheduleCancel").onclick=()=>d.close();
      form.onsubmit=async event=>{event.preventDefault();const fd=new FormData(form),button=form.querySelector('button[type="submit"]');button.disabled=true;try{const result=await F.rpc("finance_save_fee_schedule",{payload:{academic_year_id:fd.get("academic_year_id"),term_id:fd.get("term_id"),fee_group_id:fd.get("fee_group_id"),amount:Number(fd.get("amount")),due_date:String(fd.get("due_date")||""),description:String(fd.get("description")||"Term fee"),active:form.elements.active.checked}});d.close();F.notify("Term fee saved",`${Number(result?.classes_configured||1)} class${Number(result?.classes_configured||1)===1?"":"es"} configured from this fee range.`);await accounts.renderTab()}catch(error){F.notify("Term fee not saved",F.friendly(error),"error")}finally{button.disabled=false}};
      d.showModal();
    }
    function patchSettingsUi(){
      const root=F.byId?.("financeTabBody");if(!root)return;
      const add=F.byId?.("feeScheduleAdd");
      if(add&&!add.dataset.feeGroupBound){add.dataset.feeGroupBound="1";add.onclick=()=>openFeeGroupSchedule("")}
      root.querySelectorAll("[data-fee-edit]").forEach(button=>{if(button.dataset.feeGroupBound)return;button.dataset.feeGroupBound="1";button.onclick=()=>openFeeGroupSchedule(button.dataset.feeEdit||"")});
      const panel=add?.closest("section.panel");
      panel?.querySelectorAll("thead th").forEach(th=>{if(th.textContent.trim()==="Class")th.textContent="Fee Class Range"});
    }
    const observer=new MutationObserver(()=>queueMicrotask(patchSettingsUi));
    const target=F.byId?.("content")||document.body;observer.observe(target,{childList:true,subtree:true});patchSettingsUi();
  }
  async function loadFinance(){if(document.documentElement.dataset.edusentiaFinanceLoaded==="1")return;for(let i=0;i<240&&!tenantReady();i++)await new Promise(r=>setTimeout(r,250));if(!tenantReady())return;document.documentElement.dataset.edusentiaFinanceLoaded="1";loadCss();try{if(window.EdusentiaFinanceRuntime&&window.EdusentiaFinanceAccounts){installFinancePrintFrame();installFinanceEntitlementUi();installFeeGroupUi();return;}await loadScript("finance-core.js","core");installFinancePrintFrame();await loadScript("finance-payroll.js","payroll");await loadScript("finance-accounts.js","accounts");await loadScript("finance-professional-receipts.js","receipts");await loadScript("finance-portals.js","portals");installFinanceEntitlementUi();installFeeGroupUi()}catch(error){console.error("edusentia_finance_modules_load_failed",error);document.documentElement.dataset.edusentiaFinanceLoaded="0"}}
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",()=>void loadFinance(),{once:true});else void loadFinance();
})();
