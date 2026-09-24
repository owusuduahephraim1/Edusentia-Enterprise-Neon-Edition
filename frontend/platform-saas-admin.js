(() => {
"use strict";
const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>[...r.querySelectorAll(s)];
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const api=()=>window.EdusentiaApi;
const packageApi=()=>window.EdusentiaPlatformApi;
const cfg=window.EDS_MASTER_CONFIG||{};
const state={view:"overview",model:null,session:null,mfaChallenge:"",pendingSession:null,turnstileToken:"",turnstileId:null,loading:false,packageModel:{templates:[],artifacts:[],reconciliation:[],signing_keys:[],signing_configured:false,signing_bootstrap_available:false}};
function setMobileDrawer(open=false){
  const drawer=$("#paPlatformSidebar")||$(".pa-sidebar"),backdrop=$("#paMobileDrawerBackdrop"),button=$("#paMobileMenuButton"),active=Boolean(open);
  drawer?.classList.toggle("pa-drawer-open",active);
  backdrop?.classList.toggle("open",active);
  document.body.classList.toggle("pa-mobile-drawer-open",active);
  button?.setAttribute("aria-expanded",active?"true":"false");
  button?.setAttribute("aria-label",active?"Close platform navigation":"Open platform navigation");
}
function toggleMobileDrawer(){setMobileDrawer(!($("#paPlatformSidebar")||$(".pa-sidebar"))?.classList.contains("pa-drawer-open"));}

const titles={
  overview:["Platform Overview","Control-plane status and tenant operations"],
  registrations:["School Registrations","Review and approve new school onboarding"],
  tenants:["Tenants","Isolated school databases, access and lifecycle controls"],
  capacity:["Student Capacity","Licensed active-student allowances and enforcement"],
  licensing:["Licensing","Academic-period licence authorization and activation"],
  provisioning:["Provisioning","Dedicated Neon database provisioning jobs"],
  plans:["Plans","Commercial plans and feature entitlements"],
  packages:["Package Distribution","Signed Neon tenant packages and Cloudflare R2 lifecycle"],
  health:["Platform Health","Release gate, tenant health and operational audit"]
};
function status(message="",kind=""){const n=$("#paStatus");if(!n)return;n.textContent=message;n.className=`pa-status ${kind}`.trim();n.classList.toggle("hidden",!message);}
function authMessage(message=""){const n=$("#paMessage");if(n)n.textContent=message;}
function mfaMessage(message=""){const n=$("#paMfaMessage");if(n)n.textContent=message;}
function fmt(v){if(!v)return "—";const d=new Date(v);return Number.isNaN(d.getTime())?String(v):d.toLocaleString("en-GH",{year:"numeric",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"});}
function dateValue(v){const d=v?new Date(v):new Date();if(Number.isNaN(d.getTime()))return"";return d.toISOString().slice(0,10);}
function plusDays(v,n){const d=v instanceof Date?new Date(v):new Date(v||Date.now());d.setUTCDate(d.getUTCDate()+n);return d;}
function badge(v){const x=String(v||"unknown");return `<span class="pa-badge ${esc(x)}">${esc(x.replaceAll("_"," "))}</span>`;}
function money(v,c="USD"){if(v==null||v==="")return"Custom";try{return new Intl.NumberFormat("en",{style:"currency",currency:c,maximumFractionDigits:0}).format(Number(v));}catch{return String(v);}}
function showAuth(mode="login"){
  state.session=null;setMobileDrawer(false);
  $("#paConsole")?.classList.add("hidden");
  $("#paAuthView")?.classList.remove("hidden");
  $("#paAuthView")?.setAttribute("aria-hidden","false");
  $("#paLogin")?.classList.toggle("hidden",mode!=="login");
  $("#paMfa")?.classList.toggle("hidden",mode!=="mfa");
  $("#paRecoveryCodes")?.classList.toggle("hidden",mode!=="recovery");
  if(mode==="login"){requestAnimationFrame(()=>{renderTurnstile();$("#paEmail")?.focus();});}
}
function showConsole(session){
  state.session=session;setMobileDrawer(false);$("#paAuthView")?.classList.add("hidden");$("#paAuthView")?.setAttribute("aria-hidden","true");$("#paConsole")?.classList.remove("hidden");
  $("#paAdminIdentity").textContent=session?.user?.displayName||session?.user?.email||"Platform Administrator";
}
function renderTurnstile(){
  const key=String(cfg.turnstileSiteKey||"").trim();
  if(!key||!window.turnstile||state.turnstileId!=null||!$("#paTurnstile"))return;
  state.turnstileId=window.turnstile.render("#paTurnstile",{sitekey:key,action:"platform_login",theme:"auto",size:"flexible",
    callback:t=>{state.turnstileToken=String(t||"");authMessage("");},
    "expired-callback":()=>{state.turnstileToken="";authMessage("Verification expired. Please verify again.");},
    "error-callback":()=>{state.turnstileToken="";authMessage("Human verification could not be completed. Please retry.");}
  });
}
function resetTurnstile(){state.turnstileToken="";if(window.turnstile&&state.turnstileId!=null){try{window.turnstile.reset(state.turnstileId);}catch{}}}
window.onPlatformTurnstileLoad=renderTurnstile;
function renderQr(root,text){if(!root)return;root.innerHTML="";if(!text||!window.QRCode){root.classList.add("hidden");return;}new window.QRCode(root,{text,width:196,height:196,correctLevel:window.QRCode.CorrectLevel.M});root.classList.remove("hidden");}
function beginMfa(result){
  state.mfaChallenge=String(result.challengeToken||"");showAuth("mfa");mfaMessage("");
  const setup=result.mode==="enroll"?result.setup:null,box=$("#paMfaSetup");
  if(setup?.secret){box.innerHTML=`<strong>Set up your authenticator</strong><span>Scan the QR code or enter this manual key in a TOTP authenticator.</span><code style="display:block;margin-top:8px;word-break:break-all">${esc(setup.secret)}</code>`;box.classList.remove("hidden");renderQr($("#paMfaQr"),setup.otpauthUri);}
  else{box.classList.add("hidden");renderQr($("#paMfaQr"),"");}
  $("#paMfaCode").value="";$("#paMfaCode").focus();
}
async function enter(session){showConsole(session);setView(state.view);await load(true);}
async function boot(){
  try{const session=await api().platformSession();if(session?.authenticated){await enter(session);return;}showAuth();}
  catch(e){showAuth();}
}
async function load(force=false){
  if(state.loading&&!force)return;state.loading=true;$("#paConnection").textContent="Refreshing control plane…";
  try{state.model=await api().platformOverview();$("#paConnection").textContent="Control plane connected";render();}
  catch(e){$("#paConnection").textContent="Control plane unavailable";status(e?.message||"Could not load Platform Administration.","error");}
  finally{state.loading=false;}
}
function setView(view){
  if(!titles[view])view="overview";state.view=view;
  $$(".pa-nav [data-view]").forEach(b=>b.classList.toggle("active",b.dataset.view===view));
  const [title,subtitle]=titles[view];$("#paPageTitle").textContent=title;$("#paPageSubtitle").textContent=subtitle;
  render();if(view==="packages")loadPackages().catch(e=>status(e?.message||"Package service could not be loaded.","error"));setMobileDrawer(false);
}
function pageHead(title,subtitle,actions=""){return `<div class="pa-page-head"><div><h3>${esc(title)}</h3><p>${esc(subtitle)}</p></div><div class="pa-actions">${actions}</div></div>`;}
function empty(text){return `<div class="pa-empty">${esc(text)}</div>`;}
function table(headers,rows){return `<div class="pa-table-wrap"><table class="pa-table"><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.join("")}</tbody></table></div>`;}
function tenantById(id){return state.model?.tenants?.find(t=>String(t.tenant_id)===String(id));}
function registrationById(id){return state.model?.registrations?.find(r=>String(r.id)===String(id));}
function planByCode(code){return state.model?.plans?.find(p=>String(p.code)===String(code));}
function openModal(title,html){$("#paModalTitle").textContent=title;$("#paModalBody").innerHTML=html;const d=$("#paModal");if(!d.open)d.showModal();}
function closeModal(){const d=$("#paModal");if(d?.open)d.close();if($("#paModalBody"))$("#paModalBody").innerHTML="";}
async function copy(value){try{await navigator.clipboard.writeText(String(value||""));status("Copied to clipboard.","success");}catch{status("Clipboard access was unavailable. Select the value and copy it manually.","error");}}
function render(){
  const m=state.model;if(!m||!$("#paContent"))return;
  if(state.view==="overview")renderOverview(m);
  if(state.view==="registrations")renderRegistrations(m);
  if(state.view==="tenants")renderTenants(m);
  if(state.view==="capacity")renderCapacity(m);
  if(state.view==="licensing")renderLicensing(m);
  if(state.view==="provisioning")renderProvisioning(m);
  if(state.view==="plans")renderPlans(m);
  if(state.view==="packages")renderPackages(m);
  if(state.view==="health")renderHealth(m);
}
async function digestFile(file){const d=new Uint8Array(await crypto.subtle.digest("SHA-256",await file.arrayBuffer()));return Array.from(d,b=>b.toString(16).padStart(2,"0")).join("");}
function packageActionButton(label,action,id="",kind="secondary"){return `<button class="pa-btn ${kind} small" type="button" data-action="${esc(action)}"${id?` data-id="${esc(id)}"`:""}>${esc(label)}</button>`;}
function packageMetric(label,value,icon,kind=""){return `<article class="pa-stat ${kind}"><div class="pa-stat-icon">${icon}</div><div><span>${esc(label)}</span><strong>${esc(value)}</strong></div></article>`;}
function renderPackages(m){
  const p=state.packageModel||{},active=(p.templates||[]).find(x=>x.active),open=(p.reconciliation||[]).filter(x=>x.status!=="resolved");
  const tenants=(m.tenants||[]).map(t=>`<tr><td><code>${esc(t.tenant_code)}</code></td><td>${esc(t.school_name)}</td><td>${esc(t.plan_code||"—")}</td><td>${badge(t.status)}</td><td>${packageActionButton("Generate package","package-generate",t.tenant_id)}</td></tr>`);
  const artifacts=(p.artifacts||[]).map(a=>{const actions=[];if(a.status==="ready"){actions.push(packageActionButton("Download","package-download",a.id));actions.push(packageActionButton("Revoke","package-revoke",a.id,"warning"));}if(a.status==="revoked"){actions.push(packageActionButton("Restore","package-restore",a.id));actions.push(packageActionButton("Delete","package-delete",a.id,"danger"));}return `<tr><td><code>${esc(a.tenant_code)}</code><br><small>${esc(a.school_name)}</small></td><td>${esc(a.filename)}</td><td>${badge(a.status)}</td><td><code>${esc(String(a.sha256||"").slice(0,16))}…</code></td><td>${esc(a.signing_key_id||"—")}</td><td>${fmt(a.generated_at)}</td><td>${Number(a.download_count||0)}</td><td><div class="pa-actions">${actions.join("")||"—"}</div></td></tr>`;});
  $("#paContent").innerHTML=`${pageHead("Package Distribution","Protected repository templates, signed tenant releases and Cloudflare R2 lifecycle")}
  <section class="pa-stat-grid">
    ${packageMetric("Active template",active?active.package_version:"Not installed","⬢",active?"green":"gold")}
    ${packageMetric("Signing identity",p.signing_configured?"Persisted":"Bootstrap ready",p.signing_configured?"✓":"◇",p.signing_configured?"green":"gold")}
    ${packageMetric("Ready packages",(p.artifacts||[]).filter(a=>a.status==="ready").length,"▣")}
    ${packageMetric("R2 reconciliation",open.length,open.length?"!":"●",open.length?"red":"green")}
  </section>
  <div class="pa-grid two">
    <section class="pa-panel"><header class="pa-panel-head"><h4>Protected Neon package template</h4></header><div class="pa-panel-body">
      ${active?`<div class="pa-info success"><strong>${esc(active.package_version)}</strong><span>SHA-256 ${esc(active.sha256)} · ${esc(active.file_size)} bytes</span></div>`:'<div class="pa-info warning"><strong>No active template</strong><span>Upload a ZIP of the certified Neon repository before generating tenant packages.</span></div>'}
      <label class="pa-field"><span>Repository template ZIP</span><input id="paPackageTemplateFile" type="file" accept=".zip,application/zip"></label>
      <div class="pa-actions">${packageActionButton("Validate & activate","package-template-upload")}${packageActionButton("Reconcile R2","package-maintain","","ghost")}</div>
    </div></section>
    <section class="pa-panel"><header class="pa-panel-head"><h4>Signing continuity</h4></header><div class="pa-panel-body pa-card-list">${(p.signing_keys||[]).map(k=>`<article class="pa-event"><strong>${esc(k.key_id)}</strong><small>${esc(k.public_fingerprint)} · ${k.active?"active":"inactive"}</small></article>`).join("")||'<div class="pa-empty">The signing identity will be created securely on first package generation.</div>'}</div></section>
  </div>
  <section class="pa-panel" style="margin-top:17px"><header class="pa-panel-head"><h4>Generate tenant package</h4></header><div class="pa-panel-body">${tenants.length?table(["Tenant","School","Plan","Status","Action"],tenants):empty("No tenants are available for package generation.")}</div></section>
  <section class="pa-panel" style="margin-top:17px"><header class="pa-panel-head"><h4>Generated packages</h4></header><div class="pa-panel-body">${artifacts.length?table(["Tenant","Artifact","Status","SHA-256","Signing key","Generated","Downloads","Actions"],artifacts):empty("No generated tenant packages yet.")}</div></section>`;
}
async function loadPackages(){state.packageModel=await packageApi().packageStatus();if(state.view==="packages")renderPackages(state.model||{tenants:[]});}
function renderOverview(m){
  const gate=m.releaseGate||{},checks=gate.checks||{},pending=(m.registrations||[]).filter(r=>r.status==="pending").slice(0,6),health=(m.tenants||[]).slice(0,8);
  $("#paContent").innerHTML=`${pageHead("Platform Overview","Control-plane status and tenant operations")}
  <section class="pa-stat-grid">
    <article class="pa-stat gold"><div class="pa-stat-icon">✓</div><div><span>Pending registrations</span><strong>${Number(m.summary?.pendingRegistrations||0)}</strong></div></article>
    <article class="pa-stat green"><div class="pa-stat-icon">▦</div><div><span>Active tenants</span><strong>${Number(m.summary?.activeTenants||0)}</strong></div></article>
    <article class="pa-stat"><div class="pa-stat-icon">↻</div><div><span>Provisioning</span><strong>${Number(m.summary?.provisioningTenants||0)}</strong></div></article>
    <article class="pa-stat red"><div class="pa-stat-icon">!</div><div><span>Failed jobs</span><strong>${Number(m.summary?.failedJobs||0)}</strong></div></article>
  </section>
  <div class="pa-grid two">
    <section class="pa-panel"><header class="pa-panel-head"><h4>Registrations awaiting review</h4><button class="pa-btn secondary small" data-view-jump="registrations">Open registrations</button></header><div class="pa-panel-body">${pending.length?pending.map(r=>`<article class="pa-event"><strong>${esc(r.school_name)}</strong><small>${esc(r.contact_name)} · ${esc(r.contact_email)} · ${fmt(r.created_at)}</small></article>`).join(""):empty("No school registrations are waiting for review.")}</div></section>
    <section class="pa-panel"><header class="pa-panel-head"><h4>Release readiness</h4><button class="pa-btn secondary small" data-action="release-gate">Run gate</button></header><div class="pa-panel-body">
      <div class="pa-info ${gate.ready?"success":"warning"}"><strong>${gate.ready?"Release gate ready":"Release gate requires attention"}</strong><span>Tenant release: ${esc(gate.tenant_release_code||"not registered")} · Active tenants: ${Number(checks.active_tenants||0)} · Drift: ${Number(checks.tenant_release_drift||0)+Number(checks.tenant_schema_drift||0)}</span></div>
    </div></section>
  </div>
  <section class="pa-panel" style="margin-top:17px"><header class="pa-panel-head"><h4>Tenant control status</h4><button class="pa-btn secondary small" data-view-jump="tenants">Open tenants</button></header><div class="pa-panel-body">${health.length?health.map(t=>`<article class="pa-event"><strong>${esc(t.school_name)} · ${esc(t.tenant_code)}</strong><small>${esc(t.database_state)} · ${esc(t.plan_code)} · health ${esc(t.last_health_status)} · capacity ${esc(t.student_capacity_status)}</small></article>`).join(""):empty("No tenant schools have been approved yet.")}</div></section>`;
}
function renderRegistrations(m){
  const rows=(m.registrations||[]).map(r=>`<tr><td><strong>${esc(r.school_name)}</strong><br><small>${esc(r.institution_type)}</small></td><td>${esc(r.contact_name)}<br><small>${esc(r.contact_email)}</small></td><td>${badge(r.status)}</td><td>${fmt(r.created_at)}</td><td><div class="pa-actions">${r.status==="pending"?`<button class="pa-btn secondary small" data-action="approve" data-id="${r.id}">Approve</button><button class="pa-btn danger small" data-action="deny" data-id="${r.id}">Deny</button>`:""}</div></td></tr>`);
  $("#paContent").innerHTML=`${pageHead("School Registrations","Approve only after reviewing the registered school and licence period.")}<section class="pa-panel"><div class="pa-panel-body">${rows.length?table(["School","Primary contact","Status","Submitted","Actions"],rows):empty("No registrations have been submitted.")}</div></section>`;
}
function renderTenants(m){
  const recovery=new Map((m.recoveryRequests||[]).map(r=>[String(r.tenant_id),r]));
  const rows=(m.tenants||[]).map(t=>{
    const req=recovery.get(String(t.tenant_id)),ready=t.database_state==="isolated_ready",next=t.status==="active"?"suspended":"active";
    return `<tr><td><code>${esc(t.tenant_code)}</code></td><td><strong>${esc(t.school_name)}</strong><br><small>${esc(t.admin_email)}</small></td><td>${badge(t.status)}</td><td>${esc(t.plan_code)}<br><small>${t.license_expires_at?fmt(t.license_expires_at):"No expiry"}</small></td><td>${ready?'<span class="pa-badge ready">isolated ready</span>':badge(t.database_state)}<br><small>${esc(t.database_name||"not created")}</small></td><td>${esc(t.student_capacity_status||"unknown")}<br><small>${Number(t.student_active_count||0)} / ${t.student_capacity_limit??"∞"}</small></td><td><div class="pa-actions">
      ${!ready?`<button class="pa-btn secondary small" data-action="provision" data-id="${t.tenant_id}">Provision</button>`:""}
      ${ready?`<button class="pa-btn secondary small" data-action="setup" data-id="${t.tenant_id}">Admin setup</button><button class="pa-btn ghost small" data-action="health" data-id="${t.tenant_id}">Health</button>`:""}
      ${ready?`<button class="pa-btn ${req?"warning":"ghost"} small" data-action="recovery" data-id="${t.tenant_id}" data-request="${req?.id||""}">${req?"Recovery request":"Reset admin access"}</button>`:""}
      ${["active","suspended"].includes(t.status)?`<button class="pa-btn ghost small" data-action="status" data-id="${t.tenant_id}" data-next="${next}">${next==="active"?"Activate":"Suspend"}</button>`:""}
      ${ready?`<button class="pa-btn danger small" data-action="delete-tenant" data-id="${t.tenant_id}">Delete</button>`:""}
    </div></td></tr>`;
  });
  $("#paContent").innerHTML=`${pageHead("Tenants","Each active school owns an isolated Neon database and tenant-scoped R2 namespace.")}<section class="pa-panel"><div class="pa-panel-body">${rows.length?table(["Code","School","Status","Licence","Database","Capacity","Actions"],rows):empty("No tenants have been approved.")}</div></section>`;
}
function renderCapacity(m){
  const rows=(m.tenants||[]).map(t=>`<tr><td><strong>${esc(t.school_name)}</strong><br><code>${esc(t.tenant_code)}</code></td><td>${esc(t.plan_code)}</td><td>${Number(t.student_active_count||0)}</td><td>${t.student_capacity_base??"Unlimited"}</td><td>${t.student_capacity_limit??"Unlimited"}</td><td>${badge(t.student_capacity_status)}</td><td><div class="pa-actions"><button class="pa-btn secondary small" data-action="capacity" data-id="${t.tenant_id}">Set allowance</button><button class="pa-btn ghost small" data-action="refresh-capacity" data-id="${t.tenant_id}">Refresh usage</button></div></td></tr>`);
  $("#paContent").innerHTML=`${pageHead("Student Capacity","Capacity changes never delete or hide existing students.")}<section class="pa-panel"><div class="pa-panel-body">${rows.length?table(["School","Plan","Active","Plan base","Licensed","State","Actions"],rows):empty("No tenant capacity records are available.")}</div></section>`;
}
function renderLicensing(m){
  const auths=(m.planAuthorizations||[]),tenants=new Map((m.tenants||[]).map(t=>[String(t.tenant_id),t]));
  const tenantRows=(m.tenants||[]).filter(t=>t.database_state==="isolated_ready").map(t=>`<tr><td><strong>${esc(t.school_name)}</strong><br><code>${esc(t.tenant_code)}</code></td><td>${esc(t.plan_code)}</td><td>${badge(t.license_status)}</td><td>${esc(t.license_period_label||"—")}</td><td>${fmt(t.license_expires_at)}</td><td><button class="pa-btn secondary small" data-action="license" data-id="${t.tenant_id}">Issue authorization</button></td></tr>`);
  const authRows=auths.map(a=>{const t=tenants.get(String(a.tenant_id));return `<tr><td><strong>${esc(t?.school_name||"Tenant")}</strong><br><code>${esc(t?.tenant_code||"")}</code></td><td>${esc(a.authorization_type)}</td><td>${esc(a.from_plan_code)} → ${esc(a.to_plan_code)}</td><td>••••-${esc(a.code_hint||"")}</td><td>${badge(a.status)}</td><td>${fmt(a.expires_at)}</td><td><div class="pa-actions">${a.status==="issued"?`<button class="pa-btn warning small" data-action="revoke-license" data-id="${a.tenant_id}" data-authorization="${a.id}">Revoke</button>`:""}${a.status==="revoked"?`<button class="pa-btn danger small" data-action="delete-license" data-id="${a.tenant_id}" data-authorization="${a.id}">Delete permanently</button>`:""}</div></td></tr>`});
  $("#paContent").innerHTML=`${pageHead("Licensing","Academic-term and academic-year licence authorization codes")}
  <section class="pa-panel"><header class="pa-panel-head"><h4>School licence register</h4></header><div class="pa-panel-body">${tenantRows.length?table(["School","Plan","Status","Period","Expires","Actions"],tenantRows):empty("No isolated tenant licences are ready.")}</div></section>
  <section class="pa-panel pa-upgrade-register"><header class="pa-panel-head"><div><h4>Licence authorizations</h4><small>Plaintext codes are shown once; only hashes and the last four characters are retained.</small></div></header><div class="pa-panel-body">${authRows.length?table(["School","Type","Plan","Code","Status","Valid until","Actions"],authRows):empty("No licence authorization codes have been issued.")}</div></section>`;
}
function renderProvisioning(m){
  const tenantMap=new Map((m.tenants||[]).map(t=>[String(t.tenant_id),t]));
  const rows=(m.jobs||[]).map(j=>{const t=tenantMap.get(String(j.tenant_id));return `<tr><td><strong>${esc(t?.school_name||"Tenant")}</strong><br><code>${esc(t?.tenant_code||"")}</code></td><td>${badge(j.status)}</td><td>${esc(j.stage)}</td><td>${Number(j.attempts||0)}</td><td>${esc(j.last_error||"")}</td><td>${fmt(j.updated_at)}</td><td>${j.status==="failed"?`<button class="pa-btn secondary small" data-action="provision-resume" data-id="${j.tenant_id}">Resume</button>`:""}</td></tr>`});
  $("#paContent").innerHTML=`${pageHead("Provisioning","Dedicated Neon database creation and release verification")}<section class="pa-panel"><div class="pa-panel-body">${rows.length?table(["School","Status","Stage","Attempts","Last error","Updated","Actions"],rows):empty("No provisioning jobs exist.")}</div></section>`;
}
function renderPlans(m){
  const cards=(m.plans||[]).map(p=>`<article class="pa-plan"><h4>${esc(p.name)}</h4><p>${esc(p.description||"")}</p><div class="pa-plan-meta"><div><span>Code</span><strong>${esc(p.code)}</strong></div><div><span>Billing</span><strong>${esc(p.billing_cycle)}</strong></div><div><span>Price</span><strong>${esc(money(p.price_amount,p.currency))}</strong></div><div><span>Students</span><strong>${p.limits?.max_students??"Unlimited"}</strong></div><div><span>Status</span><strong>${p.active?"Active":"Inactive"}</strong></div></div></article>`);
  $("#paContent").innerHTML=`${pageHead("Plans","Reference plan entitlements used for isolated tenant licences")}<section class="pa-plan-grid">${cards.join("")||empty("No plans are configured.")}</section>`;
}
function renderHealth(m){
  const g=m.releaseGate||{},checks=g.checks||{},jobs=m.deletionJobs||[];
  const hRows=(m.tenantHealth||[]).slice(0,80).map(h=>`<tr><td><code>${esc(String(h.tenant_id).slice(0,8))}…</code></td><td>${h.healthy?badge("healthy"):badge("degraded")}</td><td>${esc(JSON.stringify(h.services||[]).slice(0,220))}</td><td>${fmt(h.checked_at)}</td></tr>`);
  const dRows=jobs.map(j=>`<tr><td><strong>${esc(j.school_name)}</strong><br><code>${esc(j.tenant_code)}</code></td><td>${badge(j.status)}</td><td>${j.database_deleted_at?"Deleted":"Pending"}</td><td>${j.r2_deleted_at?"Deleted":"Pending"}</td><td>${esc(j.last_error||"")}</td><td>${fmt(j.created_at)}</td></tr>`);
  $("#paContent").innerHTML=`${pageHead("Platform Health","Release gate and durable operational health",'<button class="pa-btn secondary" data-action="release-gate">Run release gate</button>')}
  <section class="pa-panel"><header class="pa-panel-head"><h4>Release gate</h4></header><div class="pa-panel-body"><div class="pa-info ${g.ready?"success":"warning"}"><strong>${g.ready?"Ready":"Attention required"}</strong><span>Release ${esc(g.release_version||"—")} · tenant release ${esc(g.tenant_release_code||"—")} · unhealthy ${Number(checks.unhealthy_tenants||0)} · stale health ${Number(checks.stale_tenant_health||0)} · failed provisioning ${Number(checks.failed_provisioning_jobs||0)}</span></div></div></section>
  <div class="pa-grid two" style="margin-top:17px"><section class="pa-panel"><header class="pa-panel-head"><h4>Tenant health history</h4></header><div class="pa-panel-body">${hRows.length?table(["Tenant","Status","Services","Checked"],hRows):empty("No tenant health checks have been recorded.")}</div></section>
  <section class="pa-panel"><header class="pa-panel-head"><h4>Permanent deletion jobs</h4></header><div class="pa-panel-body">${dRows.length?table(["School","Status","Database","R2","Error","Created"],dRows):empty("No permanent school deletion jobs have run.")}</div></section></div>`;
}
function periodLabelOptions(type,selected=""){
  if(type==="academic_year"){const y=Math.max(2026,new Date().getUTCFullYear());return Array.from({length:12},(_,i)=>`${y+i}/${y+i+1}`).map(v=>`<option value="${v}" ${v===selected?"selected":""}>${v}</option>`).join("");}
  return ["Term 1","Term 2","Term 3"].map(v=>`<option value="${v}" ${v===selected?"selected":""}>${v}</option>`).join("");
}
function openApproval(reg){
  const start=dateValue(new Date()),end=dateValue(plusDays(new Date(),120));
  openModal("Approve school and set initial licence",`<div class="pa-modal-summary"><strong>${esc(reg.school_name)}</strong><span>Initial plan: Starter · ${esc(reg.contact_name)}</span></div>
  <form id="paApprovalForm" class="pa-form"><label class="pa-field"><span>Licence period type</span><select name="periodType"><option value="academic_term">Academic Term</option><option value="academic_year">Academic Year</option></select></label>
  <label class="pa-field"><span>Period name</span><select name="periodLabel">${periodLabelOptions("academic_term")}</select></label>
  <div class="pa-form-grid"><label class="pa-field"><span>Coverage starts</span><input name="startsAt" type="date" value="${start}" required></label><label class="pa-field"><span>Coverage ends</span><input name="expiresAt" type="date" value="${end}" required></label></div>
  <label class="pa-field"><span>Grace period</span><select name="graceDays"><option>0</option><option>7</option><option selected>14</option><option>30</option><option>60</option></select></label>
  <div class="pa-info warning"><strong>Approval queues an isolated tenant database.</strong><span>The school starts on Starter and receives no plaintext database credentials.</span></div>
  <div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Cancel</button><button class="pa-primary" type="submit">Approve and queue provisioning</button></div></form>`);
  const form=$("#paApprovalForm"),type=form.elements.periodType,label=form.elements.periodLabel;
  type.addEventListener("change",()=>label.innerHTML=periodLabelOptions(type.value));
  form.addEventListener("submit",async e=>{e.preventDefault();const b=form.querySelector('button[type="submit"]'),v=Object.fromEntries(new FormData(form));b.disabled=true;try{
    const startIso=new Date(String(v.startsAt)+"T00:00:00.000Z").toISOString(),endIso=new Date(String(v.expiresAt)+"T23:59:59.999Z").toISOString();
    await api().configureInitialLicense(reg.id,{periodType:v.periodType,periodLabel:v.periodLabel,startsAt:startIso,expiresAt:endIso,graceDays:Number(v.graceDays)});
    await api().approveRegistration(reg.id);closeModal();status("Registration approved and isolated provisioning queued.","success");await load(true);
  }catch(err){status(err.message||String(err),"error");}finally{b.disabled=false;}});
}
function openCapacity(t){
  openModal("Student capacity control",`<div class="pa-modal-summary"><strong>${esc(t.school_name)}</strong><span>${esc(t.tenant_code)} · ${esc(t.plan_code)} plan</span></div>
  <div class="pa-capacity-summary"><div><span>Verified active students</span><strong>${Number(t.student_active_count||0)}</strong></div><div><span>Plan base</span><strong>${t.student_capacity_base??"Unlimited"}</strong></div><div><span>Licensed allowance</span><strong>${t.student_capacity_limit??"Unlimited"}</strong></div><div><span>Last verified</span><strong>${fmt(t.student_capacity_checked_at)}</strong></div></div>
  <form id="paCapacityForm" class="pa-form"><label class="pa-field"><span>Licensed active-student capacity</span><input name="limit" type="number" min="1" max="1000000" value="${esc(t.student_capacity_limit??"")}"><small>Leave blank to restore the plan default.</small></label>
  <label class="pa-field"><span>Commercial authorization reason</span><textarea name="reason" required minlength="5" maxlength="500"></textarea></label>
  <div class="pa-info warning"><strong>Data-safe enforcement</strong><span>Existing students are never removed. New active admissions stop at the licensed boundary.</span></div>
  <div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Cancel</button><button class="pa-primary" type="submit">Save capacity</button></div></form>`);
  $("#paCapacityForm").addEventListener("submit",async e=>{e.preventDefault();const form=e.currentTarget,b=form.querySelector('button[type="submit"]'),v=Object.fromEntries(new FormData(form));b.disabled=true;try{const limit=String(v.limit||"").trim()===""?null:Number(v.limit);await api().setTenantCapacity(t.tenant_id,limit,String(v.reason||""));closeModal();status("Student capacity authorization saved.","success");await load(true);}catch(err){status(err.message||String(err),"error");}finally{b.disabled=false;}});
}
function openLicense(t){
  const current=planByCode(t.plan_code),targets=(state.model.plans||[]).filter(p=>p.active!==false&&Number(p.sort_order)>=Number(current?.sort_order||0));
  const start=dateValue(t.license_expires_at&&new Date(t.license_expires_at)>new Date()?plusDays(t.license_expires_at,1):new Date()),end=dateValue(plusDays(start,120));
  openModal("Issue licence authorization",`<div class="pa-modal-summary"><strong>${esc(t.school_name)}</strong><span>${esc(t.tenant_code)} · Current plan: ${esc(current?.name||t.plan_code)}</span></div>
  <form id="paLicenseForm" class="pa-form"><label class="pa-field"><span>Authorized plan</span><select name="planCode">${targets.map(p=>`<option value="${esc(p.code)}">${esc(p.name)}${p.code===t.plan_code?" · renewal":""}</option>`).join("")}</select></label>
  <label class="pa-field"><span>Licence period type</span><select name="periodType"><option value="academic_term">Academic Term</option><option value="academic_year">Academic Year</option></select></label>
  <label class="pa-field"><span>Period name</span><select name="periodLabel">${periodLabelOptions("academic_term")}</select></label>
  <div class="pa-form-grid"><label class="pa-field"><span>Coverage starts</span><input name="startsAt" type="date" value="${start}" required></label><label class="pa-field"><span>Coverage ends</span><input name="expiresAt" type="date" value="${end}" required></label></div>
  <label class="pa-field"><span>Grace period</span><select name="graceDays"><option>0</option><option>7</option><option selected>14</option><option>30</option><option>60</option></select></label>
  <label class="pa-field"><span>Commercial authorization note</span><textarea name="reason" required minlength="5" maxlength="500"></textarea></label>
  <div class="pa-info"><strong>Manual delivery only</strong><span>The plaintext authorization code is returned once and is never stored by Edusentia.</span></div>
  <div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Cancel</button><button class="pa-primary" type="submit">Generate secure code</button></div></form>`);
  const form=$("#paLicenseForm"),type=form.elements.periodType,label=form.elements.periodLabel;type.addEventListener("change",()=>label.innerHTML=periodLabelOptions(type.value));
  form.addEventListener("submit",async e=>{e.preventDefault();const b=form.querySelector('button[type="submit"]'),v=Object.fromEntries(new FormData(form));b.disabled=true;try{
    const result=await api().issueTenantLicense(t.tenant_id,{planCode:v.planCode,periodType:v.periodType,periodLabel:v.periodLabel,startsAt:new Date(String(v.startsAt)+"T00:00:00.000Z").toISOString(),expiresAt:new Date(String(v.expiresAt)+"T23:59:59.999Z").toISOString(),graceDays:Number(v.graceDays),reason:String(v.reason||"")});
    openModal("Licence code generated",`<div class="pa-info success"><strong>Copy this code now</strong><span>The plaintext value is displayed only in this response.</span></div><label class="pa-field"><span>One-time licence activation code</span><div class="pa-copy-field"><input id="paGeneratedCode" value="${esc(result.authorizationCode||"")}" readonly><button id="paCopyCode" class="pa-btn secondary" type="button">Copy code</button></div></label><div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Done</button></div>`);
    $("#paCopyCode").onclick=()=>copy(result.authorizationCode||"");await load(true);
  }catch(err){status(err.message||String(err),"error");b.disabled=false;}});
}
function openSetup(t){
  openModal("Create administrator setup link",`<div class="pa-modal-summary"><strong>${esc(t.school_name)}</strong><span>${esc(t.tenant_code)} · ${esc(t.admin_email)}</span></div><div class="pa-info warning"><strong>One-time link</strong><span>The link expires after 30 minutes and invalidates any previous unused setup link.</span></div><div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Cancel</button><button id="paCreateSetup" class="pa-primary" type="button">Generate link</button></div>`);
  $("#paCreateSetup").onclick=async e=>{e.currentTarget.disabled=true;try{const r=await api().tenantAdminSetupLink(t.tenant_id);openModal("Administrator setup link",`<div class="pa-info success"><strong>Link generated</strong><span>Deliver this link only to the registered school administrator.</span></div><label class="pa-field"><span>One-time link</span><div class="pa-copy-field"><input id="paSetupLink" value="${esc(r.setupLink||"")}" readonly><button id="paCopySetup" class="pa-btn secondary" type="button">Copy</button></div></label><div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Done</button></div>`);$("#paCopySetup").onclick=()=>copy(r.setupLink||"");}catch(err){status(err.message||String(err),"error");e.currentTarget.disabled=false;}};
}
function openRecovery(t,requestId){
  const req=(state.model.recoveryRequests||[]).find(r=>String(r.id)===String(requestId));
  if(!req){status("No public recovery request is pending for this tenant. Use the administrator setup link for a password reset, or submit a protected recovery request from the sign-in page.","error");return;}
  const requested=String(req.recovery_type||"mfa");
  openModal("Reset tenant System Administrator access",`<div class="pa-modal-summary"><strong>${esc(t.school_name)}</strong><span>${esc(t.tenant_code)} · ${esc(t.admin_email)}</span></div><div class="pa-info warning"><strong>Pending protected request</strong><span>${esc(requested.replaceAll("_"," "))} · ${esc(req.requester_contact_email)} · ${fmt(req.requested_at)}</span></div>
  <form id="paRecoveryForm" class="pa-form"><label class="pa-field"><span>Recovery action</span><select name="mode"><option value="password" ${requested==="password"?"selected":""}>Reset password</option><option value="mfa" ${requested==="mfa"?"selected":""}>Reset authenticator</option><option value="both" ${requested==="both"?"selected":""}>Reset password and authenticator</option></select></label>
  <label class="pa-field"><span>Denial reason</span><textarea name="denyReason" placeholder="Used only if you deny this request"></textarea></label>
  <div class="pa-modal-actions"><button class="pa-btn danger" type="button" id="paDenyRecovery">Deny request</button><button class="pa-primary" type="submit">Apply protected recovery</button></div></form>`);
  $("#paRecoveryForm").addEventListener("submit",async e=>{e.preventDefault();const form=e.currentTarget,b=form.querySelector('button[type="submit"]');b.disabled=true;try{const r=await api().resolveRecovery(req.id,form.elements.mode.value);if(r.setupLink){openModal("Protected password recovery link",`<div class="pa-info success"><strong>Recovery prepared</strong><span>MFA changes were applied where requested. Deliver the single-use password link only to the registered administrator.</span></div><label class="pa-field"><span>Recovery link</span><div class="pa-copy-field"><input id="paRecoveryLink" value="${esc(r.setupLink)}" readonly><button id="paCopyRecovery" class="pa-btn secondary" type="button">Copy</button></div></label><div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Done</button></div>`);$("#paCopyRecovery").onclick=()=>copy(r.setupLink);}else{closeModal();status("Protected MFA recovery completed. The administrator must enroll a new factor at next sign-in.","success");}await load(true);}catch(err){status(err.message||String(err),"error");b.disabled=false;}});
  $("#paDenyRecovery").onclick=async()=>{const reason=String($("#paRecoveryForm").elements.denyReason.value||"").trim();if(reason.length<5){status("Enter a clear denial reason of at least five characters.","error");return;}try{await api().denyRecovery(req.id,reason);closeModal();status("Recovery request denied.","success");await load(true);}catch(err){status(err.message||String(err),"error");}};
}
function openDelete(t){
  const expected=`DELETE ${t.tenant_code}`;
  openModal("Permanently delete school",`<div class="pa-info warning"><strong>Irreversible tenant destruction</strong><span>This removes the dedicated Neon database, every object under the tenant R2 prefix, and the master tenant/registration records. The deletion audit job remains.</span></div>
  <div class="pa-modal-summary"><strong>${esc(t.school_name)}</strong><span>${esc(t.tenant_code)} · ${esc(t.database_name)}</span></div>
  <form id="paDeleteTenantForm" class="pa-form"><label class="pa-field"><span>Reason for permanent deletion</span><textarea name="reason" minlength="8" maxlength="1000" required></textarea></label><label class="pa-field"><span>Type exactly: ${esc(expected)}</span><input name="confirmation" autocomplete="off" required></label><div class="pa-modal-actions"><button class="pa-btn ghost" data-modal-close type="button">Cancel</button><button class="pa-btn danger" type="submit">Delete school permanently</button></div></form>`);
  $("#paDeleteTenantForm").addEventListener("submit",async e=>{e.preventDefault();const form=e.currentTarget,b=form.querySelector('button[type="submit"]'),v=Object.fromEntries(new FormData(form));if(String(v.confirmation)!==expected){status("Deletion confirmation does not match the required text.","error");return;}b.disabled=true;b.textContent="Deleting database and R2 objects…";try{await api().deleteTenant(t.tenant_id,String(v.confirmation),String(v.reason));closeModal();status("School, isolated database and tenant R2 objects were permanently deleted.","success");await load(true);}catch(err){status(err.message||String(err),"error");b.disabled=false;b.textContent="Delete school permanently";await load(true);}});
}
async function openMfaManager(){
  openModal("Security & MFA",'<div class="pa-loading">Loading authenticator security…</div>');
  try{const d=await api().platformMfaFactors(),f=d.factors||[],verified=f.filter(x=>x.verified).length;
    $("#paModalBody").innerHTML=`<div class="pa-mfa-manager"><section class="pa-mfa-manager-hero"><div><span class="eyebrow">Account resilience</span><h4>Authenticator security</h4><p>Keep at least two authenticators on independent devices. The final verified factor cannot be removed.</p></div><div class="pa-mfa-count"><strong>${verified}</strong><span>verified factor${verified===1?"":"s"}</span></div></section><div id="paMfaManagerMessage" class="pa-mfa-manager-message"></div><section class="pa-mfa-manager-section"><div class="pa-mfa-factor-list">${f.length?f.map(x=>`<article class="pa-mfa-factor-card"><div class="pa-mfa-factor-icon">${x.verified?"✓":"…"}</div><div class="pa-mfa-factor-main"><div class="pa-mfa-factor-title"><strong>${esc(x.friendlyName)}</strong><span class="pa-mfa-factor-state ${x.verified?"verified":"pending"}">${x.verified?"Verified":"Incomplete"}</span></div><small>Added ${fmt(x.createdAt)}</small><code>${esc(x.id.slice(0,8))}…</code></div><button class="pa-btn ${x.verified?"danger":"ghost"} small" data-mfa-remove="${x.id}" ${x.verified&&verified<=1?"disabled title='Add and verify a backup factor first'":""}>Remove</button></article>`).join(""):empty("No authenticator factors are registered.")}</div></section><section class="pa-mfa-add-card"><div><h5>Add backup authenticator</h5><p>Use a different physical device or secure authenticator.</p></div><div class="pa-mfa-add-controls"><label class="pa-field"><span>Authenticator name</span><input id="paMfaNewName" maxlength="64" placeholder="Backup authenticator"></label><button id="paMfaAdd" class="pa-btn secondary" type="button">Add authenticator</button></div></section></div>`;
    $$("[data-mfa-remove]",$("#paModalBody")).forEach(b=>b.onclick=async()=>{if(!confirm("Remove this authenticator?"))return;b.disabled=true;try{await api().platformMfaRemove(b.dataset.mfaRemove);await openMfaManager();status("Authenticator removed.","success");}catch(err){status(err.message||String(err),"error");b.disabled=false;}});
    $("#paMfaAdd").onclick=async()=>{const name=String($("#paMfaNewName").value||"").trim();if(name.length<3){status("Give the authenticator a clear name of at least three characters.","error");return;}try{const r=await api().platformMfaEnroll(name);renderMfaEnrollment(r.enrollment);}catch(err){status(err.message||String(err),"error");}};
  }catch(err){$("#paModalBody").innerHTML=`<div class="pa-status error">${esc(err.message||String(err))}</div>`;}
}
function renderMfaEnrollment(e){
  $("#paModalTitle").textContent="Add backup authenticator";
  $("#paModalBody").innerHTML=`<div class="pa-mfa-enroll"><button id="paMfaEnrollBack" class="pa-btn ghost small" type="button">← Cancel setup</button><span class="eyebrow">New backup factor</span><h4>Scan the authenticator QR code</h4><p>Scan the QR code on the independent device, or use the manual setup key, then enter its six-digit code.</p><div class="pa-mfa-enroll-grid"><div id="paMfaEnrollQr" class="pa-mfa-qr-large"></div><div class="pa-mfa-enroll-details"><label class="pa-field"><span>Manual setup key</span><div class="pa-copy-field"><input id="paMfaEnrollSecret" value="${esc(e.secret||"")}" readonly><button id="paMfaCopySecret" class="pa-btn ghost small" type="button">Copy</button></div></label><label class="pa-field"><span>Authenticator code</span><input id="paMfaEnrollCode" inputmode="numeric" maxlength="6"></label><button id="paMfaVerifyNew" class="pa-btn secondary" type="button">Verify authenticator</button></div></div></div>`;
  renderQr($("#paMfaEnrollQr"),e.otpauthUri);$("#paMfaCopySecret").onclick=()=>copy(e.secret||"");$("#paMfaEnrollBack").onclick=openMfaManager;
  $("#paMfaVerifyNew").onclick=async b=>{const button=b.currentTarget;button.disabled=true;try{await api().platformMfaVerify(e.factorId,$("#paMfaEnrollCode").value.trim());status("Backup authenticator added and verified.","success");await openMfaManager();}catch(err){status(err.message||String(err),"error");button.disabled=false;}};
}
async function action(event){
  const close=event.target.closest("[data-modal-close]");if(close){closeModal();return;}
  const jump=event.target.closest("[data-view-jump]");if(jump){setView(jump.dataset.viewJump);return;}
  const b=event.target.closest("[data-action]");if(!b)return;
  const id=b.dataset.id,action=b.dataset.action,t=tenantById(id),r=registrationById(id);
  if(action==="approve"&&r){openApproval(r);return;}
  if(action==="capacity"&&t){openCapacity(t);return;}
  if(action==="license"&&t){openLicense(t);return;}
  if(action==="setup"&&t){openSetup(t);return;}
  if(action==="recovery"&&t){openRecovery(t,b.dataset.request);return;}
  if(action==="delete-tenant"&&t){openDelete(t);return;}
  b.disabled=true;
  try{
    if(action==="deny"&&r){const reason=prompt("Reason for denying this registration");if(reason===null)return;await api().denyRegistration(r.id,reason);}
    if(action==="provision")await api().provisionTenant(id,"complete");
    if(action==="provision-resume")await api().provisionTenant(id,"resume");
    if(action==="status")await api().setTenantStatus(id,b.dataset.next);
    if(action==="refresh-capacity")await api().refreshTenantCapacity(id);
    if(action==="health"){const h=await api().tenantHealth(id);openModal("Tenant health",`<pre style="white-space:pre-wrap">${esc(JSON.stringify(h,null,2))}</pre>`);return;}
    if(action==="revoke-license"){const reason=prompt("Reason for revoking this unused authorization code");if(reason===null)return;await api().revokeLicenseAuthorization(id,b.dataset.authorization,reason);}
    if(action==="delete-license"){if(prompt("Type DELETE to permanently remove this revoked authorization")!=="DELETE")return;await api().deleteRevokedLicenseAuthorization(id,b.dataset.authorization);}
    if(action==="release-gate"){const g=await api().runReleaseGate();status(g.ready?"Release gate passed.":"Release gate found conditions requiring attention.",g.ready?"success":"error");}
    if(action==="package-template-upload"){const file=$("#paPackageTemplateFile")?.files?.[0];if(!file)throw new Error("Choose a Neon repository ZIP first.");if(file.size<1024||file.size>48*1024*1024)throw new Error("Template ZIP must be between 1 KB and 48 MB.");status("Hashing and validating package template…");const hash=await digestFile(file),ticket=await packageApi().packageAction("create_template_upload",{filename:file.name,file_size:file.size});const uploaded=await fetch(ticket.token,{method:"PUT",headers:{"content-type":"application/zip"},body:file});if(!uploaded.ok)throw new Error("R2 template upload failed ("+uploaded.status+")");await packageApi().packageAction("activate_template_upload",{storage_path:ticket.storage_path,filename:file.name,client_validation_receipt:{archive_sha256:hash}});await loadPackages();status("Protected Neon package template activated.","success");return;}
    if(action==="package-generate"){if(!confirm("Generate a new signed package for this tenant? Any previous ready package for the tenant will be revoked."))return;await packageApi().packageAction("generate",{tenant_id:id});await loadPackages();status("Signed tenant package generated in R2.","success");return;}
    if(action==="package-download"){const result=await packageApi().packageAction("download",{artifact_id:id}),a=document.createElement("a");a.href=result.url;a.download=result.filename||"Edusentia-Neon-Package.zip";a.rel="noopener";document.body.appendChild(a);a.click();a.remove();return;}
    if(action==="package-revoke"){const reason=prompt("Reason for revocation:","Superseded package");if(reason===null)return;await packageApi().packageAction("revoke",{artifact_id:id,reason});await loadPackages();status("Package revoked.","success");return;}
    if(action==="package-restore"){if(!confirm("Restore this revoked package as the tenant's ready package?"))return;await packageApi().packageAction("restore",{artifact_id:id});await loadPackages();status("Package restored.","success");return;}
    if(action==="package-delete"){if(!confirm("Permanently delete this revoked package object from R2?"))return;await packageApi().packageAction("delete",{artifact_id:id});await loadPackages();status("Revoked package deleted.","success");return;}
    if(action==="package-maintain"){const result=await packageApi().packageAction("repair_package_storage",{});await loadPackages();status(result.ok?"Package R2 reconciliation passed.":"Package reconciliation found missing objects.",result.ok?"success":"error");return;}
    await load(true);if(action!=="release-gate")status("Platform operation completed.","success");
  }catch(err){status(err.message||String(err),"error");}
  finally{b.disabled=false;}
}
function wire(){
  $("#paLogin")?.addEventListener("submit",async e=>{e.preventDefault();authMessage("");const b=e.currentTarget.querySelector('button[type="submit"]');if(cfg.turnstileSiteKey&&!state.turnstileToken){authMessage("Complete the human verification before signing in.");renderTurnstile();return;}b.disabled=true;try{const r=await api().platformLogin($("#paEmail").value.trim(),$("#paPassword").value,state.turnstileToken);state.turnstileToken="";beginMfa(r);}catch(err){authMessage(err.message||String(err));resetTurnstile();}finally{b.disabled=false;}});
  $("#paMfaForm")?.addEventListener("submit",async e=>{e.preventDefault();mfaMessage("");const b=e.currentTarget.querySelector('button[type="submit"]');b.disabled=true;try{const r=await api().platformCompleteMfa(state.mfaChallenge,$("#paMfaCode").value.trim());state.mfaChallenge="";if(Array.isArray(r.recoveryCodes)&&r.recoveryCodes.length){state.pendingSession=r;$("#paRecoveryCodeList").textContent=r.recoveryCodes.join("\n");showAuth("recovery");}else await enter(r);}catch(err){mfaMessage(err.message||String(err));}finally{b.disabled=false;}});
  $("#paMfaBack")?.addEventListener("click",()=>{state.mfaChallenge="";showAuth("login");resetTurnstile();renderTurnstile();});
  $("#paRecoveryContinue")?.addEventListener("click",async()=>{if(!state.pendingSession)return;const s=state.pendingSession;state.pendingSession=null;$("#paRecoveryCodeList").textContent="";await enter(s);});
  $("#paRefresh")?.addEventListener("click",()=>load(true));$("#paSignOut")?.addEventListener("click",async()=>{try{await api().platformLogout();}finally{location.replace("./platform-saas-admin.html");}});
  $("#paMfaManage")?.addEventListener("click",openMfaManager);
  $("#paMobileMenuButton")?.addEventListener("click",toggleMobileDrawer);
  $("#paMobileDrawerBackdrop")?.addEventListener("click",()=>setMobileDrawer(false));
  document.addEventListener("keydown",event=>{if(event.key==="Escape")setMobileDrawer(false);});
  window.addEventListener("resize",()=>{if(window.innerWidth>820)setMobileDrawer(false);},{passive:true});
  $(".pa-nav [data-view]").forEach(b=>b.addEventListener("click",()=>setView(b.dataset.view)));
  $("#paContent")?.addEventListener("click",action);$("#paModal")?.addEventListener("click",action);$("#paModal")?.addEventListener("close",()=>$("#paModalBody").innerHTML="");
}
wire();boot();
})();