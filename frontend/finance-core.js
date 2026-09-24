(() => {
  "use strict";
  if (window.EdusentiaFinanceRuntime) return;
  const S={client:null,boot:null,role:"",active:false,tab:"overview",yearId:"",termId:"",classId:"",channels:[],navTimer:0,refreshTimer:0,views:{},payroll:null};
  const byId=id=>document.getElementById(id), $$=(s,r=document)=>[...r.querySelectorAll(s)];
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c])), attr=esc;
  const money=v=>`GHS ${Number(v||0).toLocaleString("en-GH",{minimumFractionDigits:2,maximumFractionDigits:2})}`;
  const date=v=>v?new Date(v).toLocaleDateString("en-GH",{year:"numeric",month:"short",day:"numeric"}):"—";
  const monthName=n=>new Date(2026,Math.max(0,Number(n)-1),1).toLocaleDateString("en-GH",{month:"long"});
  const statusLabel=v=>({fully_paid:"Fully Paid",partial_paid:"Partially Paid",unpaid:"Unpaid",credit:"Credit",not_configured:"Not Configured",accounts_office:"Accounts Office",bank_transfer:"Bank Transfer",mobile_money:"Mobile Money",ssnit_employee:"SSNIT Employee",ssnit_employer:"SSNIT Employer"})[v]||String(v||"").replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());
  const statusClass=v=>["fully_paid","paid","approved","credit"].includes(v)?"published":["partial_paid","calculated"].includes(v)?"approved":["unpaid","locked","reversed"].includes(v)?"withdrawn":"draft";
  const cfg=()=>window.RCE_CONFIG||window.NIS_CONFIG||{}, flags=()=>S.boot?.license?.plan?.feature_flags||{}, hasFeature=k=>flags()[k]===true, can=k=>Boolean(S.boot?.permissions?.[k]);
  const schoolName=()=>S.boot?.school?.school_name||cfg().schoolName||"School";
  const friendly=e=>String(e?.message||e||"Request failed").replace(/^PGRST\d+:\s*/i,"").replaceAll("_"," ");
  async function rpc(name,args={}){const {data,error}=await S.client.rpc(name,args);if(error)throw error;return data;}
  async function invokeUser(action,payload){const {data,error}=await S.client.functions.invoke("finance-user-management",{body:{action,payload}});if(error)throw error;if(data?.error)throw new Error(data.error);return data;}
  function notify(title,message="",kind="info"){const stack=byId("toastStack");if(!stack){console.log(title,message);return}const n=document.createElement("div");n.className=`toast ${kind}`;n.innerHTML=`<strong>${esc(title)}</strong>${message?`<span>${esc(message)}</span>`:""}`;stack.appendChild(n);setTimeout(()=>n.remove(),5000)}
  function metric(label,value){return `<div class="finance-metric"><span>${esc(label)}</span><strong>${esc(value)}</strong></div>`}
  function options(rows,value,label,selected=""){return rows.map(r=>`<option value="${attr(r[value])}" ${String(r[value])===String(selected)?"selected":""}>${esc(typeof label==="function"?label(r):r[label])}</option>`).join("")}
  function termsForYear(id){return (S.boot?.terms||[]).filter(t=>!id||t.academic_year_id===id)}
  function miniTable(headers,rows){return `<div class="finance-table-scroll small"><table><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.length?rows.map(r=>`<tr>${r.map(c=>`<td>${String(c).startsWith("<")?c:esc(c)}</td>`).join("")}</tr>`).join(""):`<tr><td colspan="${headers.length}"><div class="empty"><strong>No records</strong></div></td></tr>`}</tbody></table></div>`}
  function dialog(title,subtitle=""){let d=byId("financeDialog");if(!d){d=document.createElement("dialog");d.id="financeDialog";d.className="modal finance-modal";d.innerHTML=`<div class="modal-frame"><header class="modal-header"><div><h3 id="financeDialogTitle"></h3><p id="financeDialogSubtitle"></p></div><button class="icon-button" id="financeDialogClose" type="button">×</button></header><section id="financeDialogBody" class="modal-body"></section></div>`;document.body.appendChild(d);byId("financeDialogClose").onclick=()=>d.close()}byId("financeDialogTitle").textContent=title;byId("financeDialogSubtitle").textContent=subtitle;return d}
  function askReason(title,subtitle,button="Confirm"){return new Promise(resolve=>{const d=dialog(title,subtitle);byId("financeDialogBody").innerHTML=`<form id="financeReason" class="finance-form"><label class="full"><span>Reason</span><textarea name="reason" rows="4" required></textarea></label><div class="button-row full"><button class="button primary" type="submit">${esc(button)}</button><button class="button ghost" id="financeReasonCancel" type="button">Cancel</button></div></form>`;byId("financeReasonCancel").onclick=()=>{d.close();resolve("")};byId("financeReason").onsubmit=e=>{e.preventDefault();const v=String(new FormData(e.currentTarget).get("reason")||"").trim();d.close();resolve(v)};d.showModal()})}
  function printHtml(title,body){const w=window.open("","_blank","noopener,noreferrer,width=900,height=700");if(!w){notify("Print window blocked","Allow pop-ups to print.","warning");return}w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><style>body{font-family:Arial,sans-serif;padding:32px;color:#111}table{width:100%;border-collapse:collapse;margin:16px 0}th,td{padding:8px;border:1px solid #ccc;text-align:left}small{display:block;color:#555}@media print{button{display:none}}</style></head><body>${body}<script>window.onload=()=>window.print()</script></body></html>`);w.document.close()}
  function exportXls(rows,cols,name){const xe=v=>String(v??"").replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));const t=`<table><tr>${cols.map(c=>`<th>${xe(c[0])}</th>`).join("")}</tr>${rows.map(r=>`<tr>${cols.map(c=>`<td>${xe(r[c[1]])}</td>`).join("")}</tr>`).join("")}</table>`;const blob=new Blob([`<html xmlns:x="urn:schemas-microsoft-com:office:excel"><head><meta charset="utf-8"></head><body>${t}</body></html>`],{type:"application/vnd.ms-excel"}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000)}
  function register(role,fn){S.views[role]=fn;if(role==="accounts_office")S.views.accountant=fn}
  function navSpec(){if(["accounts_office","accountant"].includes(S.role)&&hasFeature("finance_fees"))return["Accounts Office","₵"];if(S.role==="parent_guardian"&&hasFeature("finance_statements"))return["Fees","₵"];if(S.role==="student"&&hasFeature("finance_statements"))return["My Academics & Fees","▤"];if(["class_teacher","subject_teacher"].includes(S.role)&&hasFeature("payroll"))return["My Salary","₵"];return null}
  function injectNav(){const nav=byId("mainNav");if(!nav)return;const spec=navSpec();let b=nav.querySelector(".finance-nav-item");if(!spec){b?.remove();nav.querySelectorAll('[data-view="dashboard"]').forEach(x=>x.classList.remove("finance-core-hidden"));return;}if(!b){b=document.createElement("button");b.type="button";b.className="nav-item finance-nav-item";b.innerHTML=`<span class="nav-icon">${spec[1]}</span><span class="nav-label">${esc(spec[0])}</span><span class="nav-active-dot"></span>`;b.onclick=open;}else{const label=b.querySelector(".nav-label");if(label)label.textContent=spec[0]}const before=S.role==="system_admin"?nav.querySelector('[data-view="users"]'):nav.querySelector('[data-view="notifications"]');if(before&&before!==b)nav.insertBefore(b,before);else if(b.parentElement!==nav)nav.appendChild(b);if(["accounts_office","accountant","student"].includes(S.role))nav.querySelectorAll('[data-view="dashboard"]').forEach(x=>x.classList.add("finance-core-hidden"));else nav.querySelectorAll('[data-view="dashboard"]').forEach(x=>x.classList.remove("finance-core-hidden"))}
  function scheduleNav(){clearTimeout(S.navTimer);S.navTimer=setTimeout(injectNav,30)}
  function setActive(v){S.active=v;$$('.finance-nav-item').forEach(x=>x.classList.toggle("active",v));if(v)$$('#mainNav [data-view]').forEach(x=>x.classList.remove("active"))}
  function heading(t,s){if(byId("pageTitle"))byId("pageTitle").textContent=t;if(byId("pageSubtitle"))byId("pageSubtitle").textContent=s}
  async function open(){byId("sidebar")?.classList.remove("open");setActive(true);const fn=S.views[S.role];if(!fn)return;try{await fn()}catch(e){byId("content").innerHTML=`<section class="panel pad"><strong>Finance workspace could not be loaded</strong><p>${esc(friendly(e))}</p><button class="button secondary" id="financeRetry">Retry</button></section>`;byId("financeRetry")?.addEventListener("click",open);notify("Finance workspace error",friendly(e),"error")}}
  async function refresh(){if(S.active)await open()}
  async function subscribe(){S.channels.forEach(c=>S.client.removeChannel(c));S.channels=[];for(const topic of (S.boot?.topics||[]).slice(0,30)){const c=S.client.channel(`finance:${topic}:${Math.random()}`,{config:{private:true}}).on("broadcast",{event:"*"},()=>{clearTimeout(S.refreshTimer);S.refreshTimer=setTimeout(refresh,500)}).subscribe();S.channels.push(c)}}
  async function waitForShell(){for(let i=0;i<240;i++){const shell=byId("appShell"),nav=byId("mainNav"),content=byId("content");if(shell&&nav&&content&&!shell.classList.contains("hidden")){return true}await new Promise(r=>setTimeout(r,100))}return false}
  async function activate(){try{S.boot=await rpc("get_bootstrap_data");S.role=String(S.boot?.profile?.role||"")}catch{return}const y=S.boot?.academic_years?.find(x=>x.is_active)||S.boot?.academic_years?.[0];S.yearId=S.yearId||y?.id||"";const t=S.boot?.terms?.find(x=>x.is_active)||termsForYear(S.yearId)[0];S.termId=S.termId||t?.id||"";S.classId=S.classId||S.boot?.classes?.[0]?.id||"";await subscribe();if(!await waitForShell())return;if(byId("userRole"))byId("userRole").textContent={accounts_office:"Accounts Office Staff",accountant:"Accounts Office Staff",student:"Student"}[S.role]||byId("userRole").textContent;scheduleNav();if(["accounts_office","accountant","student"].includes(S.role))setTimeout(open,0)}
  function deactivate(){setActive(false);S.channels.forEach(c=>S.client?.removeChannel?.(c));S.channels=[];S.boot=null;S.role="";S.yearId="";S.termId="";S.classId="";const nav=byId("mainNav");nav?.querySelector(".finance-nav-item")?.remove();nav?.querySelectorAll('[data-view="dashboard"]').forEach(x=>x.classList.remove("finance-core-hidden"))}
  async function boot(){
    for(let i=0;i<240;i++){
      const c=cfg();
      if(c.masterEdition===false&&c.tenantCode&&window.EdusentiaCompatClient){
        S.client=window.EDS_TENANT_AUTH_CLIENT||window.EdusentiaCompatClient;
        break;
      }
      await new Promise(r=>setTimeout(r,250));
    }
    if(!S.client)return;
    let activeUserId="";
    let activationPromise=null;
    const activateFor=async session=>{
      const userId=String(session?.user?.id||"");
      if(!userId)return;
      if(S.boot&&activeUserId===userId)return;
      if(activationPromise)return activationPromise;
      activeUserId=userId;
      activationPromise=Promise.resolve(activate()).finally(()=>{activationPromise=null});
      return activationPromise;
    };
    S.client.auth.onAuthStateChange((event,session)=>{
      if(event==="SIGNED_OUT"||!session){activeUserId="";deactivate();return;}
      // r42-v15: a token refresh must not recursively bootstrap Finance. The main
      // tenant runtime owns session refresh and realtime token propagation.
      if(event==="TOKEN_REFRESHED")return;
      setTimeout(()=>{void activateFor(session)},0);
    });
    const {data:{session}}=await S.client.auth.getSession();
    if(session)await activateFor(session);
    byId("refreshButton")?.addEventListener("click",e=>{if(S.active){e.preventDefault();e.stopImmediatePropagation();refresh()}},true);
    byId("mainNav")?.addEventListener("click",e=>{if(e.target.closest("[data-view]"))setActive(false)},true);
    const nav=byId("mainNav");if(nav)new MutationObserver(scheduleNav).observe(nav,{childList:true});
  }
  window.EdusentiaFinanceRuntime={S,byId,$$,esc,attr,money,date,monthName,statusLabel,statusClass,cfg,flags,hasFeature,can,schoolName,friendly,rpc,invokeUser,notify,metric,options,termsForYear,miniTable,dialog,askReason,printHtml,exportXls,register,heading,open,refresh};
  if(!document.querySelector('script[data-finance-invoices-v1]')){const s=document.createElement('script');s.src='finance-invoices-v1.js?v=20260826';s.defer=true;s.dataset.financeInvoicesV1='1';document.head.appendChild(s)}
  boot().catch(console.error);
})();