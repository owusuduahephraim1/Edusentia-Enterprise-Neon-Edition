// Worker-backed certified shell parity for the Neon Edition.
// Unified blueprint authentication routes platform and tenant identities through the shared public sign-in.
(() => {
  "use strict";

  const byId = id => document.getElementById(id);
  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const api = () => window.EdusentiaApi;
  const turnstileSiteKey = String(window.EDS_MASTER_CONFIG?.turnstileSiteKey || "").trim();
  const platformMode = new URLSearchParams(location.search).get("platform")==="1";
  const state = {session:null, boot:null, view:"dashboard", loginSchool:null, authScope:platformMode?"platform":"tenant"};
  let turnstileToken = "", turnstileWidgetId = null, mfaChallenge = "", pendingSession = null, pendingScope = state.authScope;
  let registrationToken = "", registrationWidgetId = null, recoveryTurnstileToken = "", recoveryWidgetId = null;

  const NAV = [
    {id:"dashboard",label:"Dashboard",icon:"▦",subtitle:"Academic performance overview",render:renderDashboard},
    {id:"academics",label:"Academics",icon:"⌘",subtitle:"Academic structure and assessment",permission:"manage_academics",render:renderAcademics},
    {id:"students",label:"Students",icon:"◉",subtitle:"Student records and enrolment",roles:["system_admin","class_teacher","subject_teacher"],render:renderStudents},
    {id:"staff",label:"Staff & HR",icon:"♙",subtitle:"Staff directory, employment records and leave",roles:["system_admin","principal"],nav:false,render:renderStaff},
    {id:"teachers",label:"Teachers",icon:"♜",subtitle:"Teacher records and assignments",permission:"manage_teachers",render:renderTeachers},
    {id:"headteachers",label:"Principals",icon:"★",subtitle:"Principal records and appointments",permission:"manage_headteachers",render:renderPrincipal},
    {id:"finance",label:"Finance",icon:"¤",subtitle:"Fees, statements and payroll operations",feature:"finance_fees",roles:["system_admin","accountant","accounts_office","parent_guardian","student","class_teacher","subject_teacher"],nav:false,render:renderFinance},
    {id:"notifications",label:"Notifications",icon:"◆",subtitle:"School and workflow alerts",feature:"notifications",render:renderNotifications}
  ];

  const ROLE_NAV_IDS=Object.freeze({
    system_admin:["dashboard","operations","students","student_services","history","teachers","headteachers","academics","timetable","prospectus","delegations","reports","certificates","id_cards","insights","users","compliance","audit","backup_restore","plan_upgrade","license_capacity","notifications","settings"],
    principal:["dashboard","operations","student_services","staff","history","timetable","delegations","reports","certificates","insights","notifications","compliance"],
    class_teacher:["dashboard","teacher_profile","my_class","attendance","my_subjects","students","student_services","history","timetable","reports","insights","finance","notifications"],
    subject_teacher:["dashboard","teacher_profile","my_subjects","students","student_services","history","timetable","reports","insights","finance","notifications"],
    parent_guardian:["dashboard","children","student_services","finance","notifications"],
    accountant:["finance","notifications"],
    accounts_office:["finance","notifications"],
    student:["student_services","finance","notifications"]
  });
  const LEGACY_LICENSE_FEATURE_FALLBACKS=Object.freeze({id_cards:"core_records",timetable:"core_records",school_prospectus:"core_records"});
  function role(){return String(state.session?.membership?.role || state.boot?.capabilities?.role || "").toLowerCase();}
  async function certified(operation,args={}){const response=await api().certifiedRpc(operation,args);return response?.result??null;}
  function permissionEnabled(code){return Boolean(state.boot?.permissions?.[code]);}
  function featureEnabled(code){
    if(!code)return true;
    const flags=state.boot?.license?.plan?.feature_flags||{};
    if(Object.prototype.hasOwnProperty.call(flags,code))return flags[code]===true;
    if(code==="staff_id_cards")return Object.prototype.hasOwnProperty.call(flags,"id_cards")?flags.id_cards===true:flags.core_records===true;
    const parent=LEGACY_LICENSE_FEATURE_FALLBACKS[code];
    return parent?flags[parent]===true:false;
  }
  function can(item){
    const r=role();
    if(item.permission&&!permissionEnabled(item.permission)&&r!=="system_admin")return false;
    if(item.roles&&!item.roles.includes(r))return false;
    if(item.hideFor?.includes(r))return false;
    if(item.feature&&!featureEnabled(item.feature)&&r!=="system_admin")return false;
    if(typeof item.when==="function"&&!item.when(state.boot,state.session))return false;
    return true;
  }
  function planUpgradeRequired(item){return role()==="system_admin"&&Boolean(item?.feature)&&!featureEnabled(item.feature);}
  function renderPlanUpgradeRequired(item){
    const plan=state.boot?.license?.plan||{};
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>${escapeHtml(item.label)}</h3><p>${escapeHtml(item.subtitle||"Licensed school module")}</p></div></div>
      <section class="panel pad"><div class="license-banner warning"><div><strong>Plan upgrade required</strong><span>This operational workspace is part of the original Edusentia blueprint, but the <b>${escapeHtml(item.feature)}</b> entitlement is not enabled on the current ${escapeHtml(plan.name||plan.code||"school")} plan.</span></div></div>
      <p class="muted">The navigation section remains visible so the System Administrator has the same blueprint workspace structure. Data-changing operations stay disabled until the required plan entitlement is activated.</p>
      <div class="button-row"><button class="button primary" id="openUpgradePlan" type="button">Open Upgrade Plan</button></div></section>`;
    byId("openUpgradePlan")?.addEventListener("click",()=>navigate("plan_upgrade"));
  }
  function orderedNavItems(){
    const order=ROLE_NAV_IDS[role()]||["dashboard"];
    const byIdMap=new Map(NAV.map(item=>[item.id,item]));
    return order.map(id=>byIdMap.get(id)).filter(item=>item&&item.nav!==false&&can(item));
  }
  function navLabel(item){
    if(item.id!=="finance")return item.label;
    const r=role();
    if(["accountant","accounts_office"].includes(r))return "Accounts Office";
    if(r==="parent_guardian")return "Fees";
    if(r==="student")return "My Academics & Fees";
    if(["class_teacher","subject_teacher"].includes(r))return featureEnabled("payroll")?"My Salary":"Finance";
    return featureEnabled("payroll")?"Finance & Payroll":"Finance";
  }
  function canCreateStudent(){return ["system_admin","principal","academic_admin","records_officer"].includes(role());}
  function friendly(error){return error?.message || "The requested operation could not be completed.";}
  function show(view){for(const id of ["loader","authView","appShell","fatalView"])byId(id)?.classList.add("hidden");byId(view)?.classList.remove("hidden");}
  function showAuthStep(step){for(const id of ["loginForm","mfaPanel","recoveryPanel"])byId(id)?.classList.add("hidden");byId(step)?.classList.remove("hidden");}
  function message(text,kind=""){const el=byId("authMessage");if(!el)return;el.textContent=text||"";el.dataset.kind=kind;el.classList.toggle("hidden",!text);}
  function setSync(kind,label){const el=byId("syncIndicator");if(!el)return;el.className=`sync-pill ${kind}`;byId("syncLabel").textContent=label;}
  function setBusy(busy){const content=byId("content");if(content)content.setAttribute("aria-busy",busy?"true":"false");setSync(busy?"pending":"online",busy?"Loading":"Connected");}
  function status(value){const v=String(value||"unknown").toLowerCase().replace(/[^a-z0-9_]+/g,"_");return `<span class="status ${escapeHtml(v)}">${escapeHtml(String(value||"Unknown").replaceAll("_"," "))}</span>`;}
  function fullName(row){return [row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" ");}
  function formatDate(value){if(!value)return "—";const d=new Date(value);return Number.isNaN(d.valueOf())?escapeHtml(value):escapeHtml(new Intl.DateTimeFormat(undefined,{year:"numeric",month:"short",day:"2-digit"}).format(d));}
  function formatDateTime(value){if(!value)return "—";const d=new Date(value);return Number.isNaN(d.valueOf())?escapeHtml(value):escapeHtml(new Intl.DateTimeFormat(undefined,{year:"numeric",month:"short",day:"2-digit",hour:"2-digit",minute:"2-digit"}).format(d));}
  function formatAmount(value){const n=Number(value||0);return Number.isFinite(n)?new Intl.NumberFormat(undefined,{minimumFractionDigits:2,maximumFractionDigits:2}).format(n):"0.00";}
  function empty(messageText){return `<div class="panel pad"><p class="muted">${escapeHtml(messageText)}</p></div>`;}
  function loading(label="Loading records"){return `<div class="panel pad"><div class="generator-progress"><span class="spinner small"></span><span>${escapeHtml(label)}</span></div></div>`;}
  function pageError(error){return `<div class="panel pad"><div class="verify-state invalid">${escapeHtml(friendly(error))}</div><p class="muted">Use Refresh to retry. If the problem continues, contact the platform administrator.</p></div>`; }

  function resetTurnstile(){turnstileToken="";if(window.turnstile&&turnstileWidgetId!=null){try{window.turnstile.reset(turnstileWidgetId);}catch{}}}
  function renderTurnstile(){
    if(!turnstileSiteKey||!window.turnstile||turnstileWidgetId!=null||!byId("turnstileWidget"))return;
    turnstileWidgetId=window.turnstile.render("#turnstileWidget",{sitekey:turnstileSiteKey,action:platformMode?"platform_login":"login",theme:"auto",size:"flexible",callback:token=>{turnstileToken=String(token||"");message("");},"expired-callback":()=>{turnstileToken="";message("Verification expired. Please verify again.","error");},"error-callback":()=>{turnstileToken="";message("Human verification could not be completed. Please try again.","error");}});
  }
  function renderRegistrationTurnstile(){
    if(!turnstileSiteKey||!window.turnstile||registrationWidgetId!=null||!byId("registrationTurnstile"))return;
    registrationWidgetId=window.turnstile.render("#registrationTurnstile",{sitekey:turnstileSiteKey,action:"school_registration",theme:"auto",size:"flexible",callback:token=>{registrationToken=String(token||"");const el=byId("registrationMessage");if(el){el.textContent="";el.dataset.kind="";}},"expired-callback":()=>{registrationToken="";const el=byId("registrationMessage");if(el){el.textContent="Verification expired. Please verify again.";el.dataset.kind="error";}}});
  }
  function renderRecoveryTurnstile(){
    if(!turnstileSiteKey||!window.turnstile||recoveryWidgetId!=null||!byId("accessRecoveryTurnstile"))return;
    recoveryWidgetId=window.turnstile.render("#accessRecoveryTurnstile",{sitekey:turnstileSiteKey,action:"access_recovery",theme:"auto",size:"flexible",callback:token=>{recoveryTurnstileToken=String(token||"");const el=byId("accessRecoveryMessage");if(el){el.textContent="";el.dataset.kind="";}},"expired-callback":()=>{recoveryTurnstileToken="";}});
  }
  window.onTurnstileLoad=()=>{renderTurnstile();if(byId("registrationDialog")?.open)renderRegistrationTurnstile();if(byId("accessRecoveryDialog")?.open)renderRecoveryTurnstile();};

  function applyLoginBrand(school){
    const tenant=school||null;state.loginSchool=tenant;const tenantMode=Boolean(tenant?.tenant_code);
    byId("authBrandName").textContent=tenantMode?(tenant.school_name||tenant.short_name||tenant.tenant_code):"Edusentia";
    byId("authBrandTagline").textContent=tenantMode?"Student Academic Service":"The Academic Operations Platform";
    byId("authBrandLogo").alt=tenantMode?(tenant.school_name||"School"):"Edusentia";
    byId("tenantCode").value=tenantMode?String(tenant.tenant_code):"";
    byId("tenantCodeFallback").value=tenantMode?String(tenant.tenant_code):"";
    byId("registerSchoolButton")?.classList.toggle("hidden",tenantMode);
    document.body.classList.toggle("tenant-login",tenantMode);
    document.title=tenantMode?String(tenant.school_name||tenant.short_name||tenant.tenant_code)+" · Edusentia":"Edusentia Enterprise";
  }

  async function prepareLoginContext(){
    const params=new URLSearchParams(location.search),email=String(params.get("email")||"").trim();
    if(email&&byId("email"))byId("email").value=email;
    if(platformMode){applyLoginBrand(null);byId("tenantCodeField")?.classList.add("hidden");return;}
    const code=String(params.get("school")||params.get("tenant")||params.get("tenantCode")||"").trim().toUpperCase();
    if(!code){applyLoginBrand(null);return;}
    try{const result=await api().resolveSchool(code);applyLoginBrand(result?.school||null);}
    catch{applyLoginBrand(null);byId("tenantCode").value=code;byId("tenantCodeFallback").value=code;byId("tenantCodeField")?.classList.remove("hidden");message("The requested school workspace could not be resolved. You can still sign in using the institution code.","error");}
  }

  async function boot(){
    show("loader");
    try{
      await prepareLoginContext();
      if(platformMode){
        const platformSession=await api().platformSession();
        if(platformSession?.authenticated){location.replace("./platform-saas-admin.html");return;}
        show("authView");showAuthStep("loginForm");renderTurnstile();return;
      }
      const session=await api().session();
      if(!session?.authenticated){show("authView");showAuthStep("loginForm");renderTurnstile();return;}
      await enter(session);
    }catch(error){
      show("authView");showAuthStep("loginForm");renderTurnstile();
      if(error?.code!=="unauthenticated")message("The secure API is not reachable yet. Check the Worker configuration.","error");
    }
  }

  async function enter(session){
    state.session=session;
    state.boot=await api().bootstrap();
    const userName=session.user?.displayName||session.user?.email||"User";
    const roleLabel=session.membership?.roleLabel||session.membership?.role||"Member";
    const tenantName=state.boot.tenant?.name||"Edusentia Enterprise";
    byId("userName").textContent=userName;
    byId("userRole").textContent=roleLabel;
    byId("userAvatar").textContent=String(userName).trim().charAt(0).toUpperCase()||"E";
    byId("brandName").textContent=tenantName;
    byId("brandLogo").alt=tenantName;
    renderNav();
    show("appShell");
    setSync("online","Connected");
    await loadNotificationCount();
    await navigate("dashboard");
  }

  function renderNav(){
    const nav=byId("mainNav");
    const items=orderedNavItems();
    nav.innerHTML=items.map(item=>`<button class="nav-item ${planUpgradeRequired(item)?"upgrade-required":""}" type="button" data-view="${item.id}" title="${escapeHtml(item.subtitle||item.label)}${planUpgradeRequired(item)?" • Plan upgrade required":""}"><span class="nav-icon" aria-hidden="true">${item.icon}</span><span class="nav-label">${escapeHtml(navLabel(item))}${planUpgradeRequired(item)?'<small class="nav-upgrade-badge">Plan upgrade required</small>':""}</span><span class="nav-active-dot" aria-hidden="true"></span></button>`).join("");
    nav.querySelectorAll("[data-view]").forEach(button=>button.addEventListener("click",()=>navigate(button.dataset.view)));
  }

  async function navigate(id){
    const item=orderedNavItems().find(entry=>entry.id===id)||orderedNavItems()[0]||NAV.find(entry=>entry.id==="dashboard");
    state.view=item.id;
    byId("pageTitle").textContent=item.label;
    byId("pageSubtitle").textContent=item.subtitle;
    byId("mainNav").querySelectorAll("[data-view]").forEach(button=>button.classList.toggle("active",button.dataset.view===item.id));
    byId("sidebar")?.classList.remove("open");
    setBusy(true);
    let failed=false;
    try{if(planUpgradeRequired(item))renderPlanUpgradeRequired(item);else await item.render();}
    catch(error){failed=true;byId("content").innerHTML=pageError(error);setSync("error","Service issue");}
    finally{
      byId("content")?.setAttribute("aria-busy","false");
      if(!failed)setSync(navigator.onLine?"online":"offline",navigator.onLine?"Connected":"Offline");
    }
    byId("content")?.focus({preventScroll:true});
  }

  function registerView(item){
    if(!item||!item.id||typeof item.render!=="function")throw new Error("A valid workspace view is required");
    const existing=NAV.find(entry=>entry.id===item.id);
    if(existing)Object.assign(existing,item);else NAV.push(item);
    if(state.session)renderNav();
    return item;
  }

  window.EdusentiaShell=Object.freeze({
    registerView,navigate,api,certified,role,state,escapeHtml,status,formatDate,formatDateTime,formatAmount,
    loading,empty,pageError,fullName,friendly,byId,featureEnabled,permissionEnabled,orderedNavItems
  });

  async function renderDashboard(){
    state.boot=await api().bootstrap();
    const data=state.boot,tenant=data.tenant||{};
    if(role()!=="system_admin"){
      const metrics=data.metrics||{},stats=[
        ["Students",metrics.students??0,"◎","blue"],["Staff",metrics.staff??0,"♙","gold"],["Classes",metrics.classes??0,"▦","green"],
        ["Subjects",metrics.subjects??0,"◇","purple"],["Attendance today",metrics.attendanceToday??0,"✓","green"],["Pending reports",metrics.pendingReports??0,"▤","gold"]
      ];
      byId("content").innerHTML=`
        <div class="page-head"><div><h3>Operational overview</h3><p>${escapeHtml(tenant.name||"School workspace")} • ${escapeHtml(String(tenant.code||"").toUpperCase())}</p></div></div>
        <section class="stat-grid">${stats.map(([label,value,icon,tone])=>`<article class="stat-card"><span class="stat-icon ${tone}" aria-hidden="true">${icon}</span><div><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div></article>`).join("")}</section>
        <section class="grid two"><article class="panel pad"><div class="panel-header"><div><h3>School workspace</h3><p>Current institution context</p></div></div><div class="panel-body"><div class="detail-grid"><div><span>Institution model</span><strong>${escapeHtml(String(tenant.institution_type||"Not set").replaceAll("_"," "))}</strong></div><div><span>Tenant code</span><strong>${escapeHtml(tenant.code||"—")}</strong></div></div></div></article><article class="panel pad"><div class="panel-header"><div><h3>Secure session</h3><p>Worker-resolved identity and authorization</p></div></div><div class="panel-body"><div class="detail-grid"><div><span>Role</span><strong>${escapeHtml(state.session?.membership?.roleLabel||state.session?.membership?.role||"Member")}</strong></div><div><span>Assurance level</span><strong>${escapeHtml(data.capabilities?.assuranceLevel||"AAL1")}</strong></div></div></div></article></section>`;
      return;
    }
    const academic=await certified("get_academic_configuration").catch(()=>({})),terms=Array.isArray(academic?.terms)?academic.terms:[],term=terms.find(item=>item.is_active)||terms[0]||null;
    const metrics=await certified("get_role_dashboard",{target_term_id:term?.id||null}).catch(()=>data.metrics||{}),statuses=metrics?.by_status||{},reports=Number(metrics?.reports||0),published=Number(metrics?.published||0),completion=reports?Math.round(published/reports*100):0;
    const cards=[["Active Users",metrics?.active_users??0,"♟","blue"],["Active Teachers",metrics?.active_teachers??0,"♜","gold"],["Active Students",metrics?.active_students??0,"◉","green"],["Report Cards",reports,"▤","purple"]];
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>System Administration Dashboard</h3><p>Users, records, security, and report operations</p></div><div class="page-actions"><button class="button secondary small" data-dashboard-view="students">Students</button><button class="button secondary small" data-dashboard-view="teachers">Teachers</button><button class="button secondary small" data-dashboard-view="headteachers">Principals</button><button class="button secondary small" data-dashboard-view="delegations">Emergency Delegation</button></div></div>
      <section class="stat-grid">${cards.map(([label,value,icon,tone])=>`<article class="stat-card"><span class="stat-icon ${tone}" aria-hidden="true">${icon}</span><div><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div></article>`).join("")}</section>
      <section class="grid two">
        <article class="panel"><div class="panel-header"><div><h3>Current Academic Period</h3><p>${escapeHtml(term?.name||"No active term")}</p></div></div><div class="panel-body"><div class="metric-row"><div class="metric"><span>Draft</span><strong>${Number(statuses.draft||0)}</strong></div><div class="metric"><span>Submitted</span><strong>${Number(statuses.submitted||0)}</strong></div><div class="metric"><span>Approved</span><strong>${Number(statuses.approved||0)}</strong></div><div class="metric"><span>Completion</span><strong>${completion}%</strong></div></div><div class="progress"><span style="width:${completion}%"></span></div></div></article>
        <article class="panel"><div class="panel-header"><div><h3>Class Performance</h3><p>Published report averages</p></div></div><div class="panel-body"><div class="bar-list">${Array.isArray(metrics?.class_performance)&&metrics.class_performance.length?metrics.class_performance.map(row=>`<div class="bar-item"><label>${escapeHtml(row.class_name||"Class")}</label><div class="bar-track"><span style="width:${Math.min(100,Number(row.average||0))}%"></span></div><b>${Number(row.average||0).toFixed(1)}</b></div>`).join(""):`<div class="empty"><strong>No published results</strong></div>`}</div></div></article>
      </section>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Recent Report Cards</h3><p>Latest authorised activity</p></div><button class="button secondary small" data-dashboard-view="reports">View reports</button></div><div class="table-wrap"><table><thead><tr><th>Student</th><th>Class</th><th>Term</th><th>Status</th><th>Average</th><th>Updated</th></tr></thead><tbody>${Array.isArray(metrics?.recent)&&metrics.recent.length?metrics.recent.map(row=>`<tr><td>${escapeHtml(row.student_name||row.full_name||"—")}</td><td>${escapeHtml(row.class_name||"—")}</td><td>${escapeHtml(row.term_name||"—")}</td><td>${status(row.status||"draft")}</td><td>${row.average==null?"—":escapeHtml(Number(row.average||0).toFixed(1)+"%")}</td><td>${formatDateTime(row.updated_at||row.published_at)}</td></tr>`).join(""):`<tr><td colspan="6"><div class="empty"><strong>No report cards</strong><span>Records will appear here when available.</span></div></td></tr>`}</tbody></table></div></section>`;
    byId("content").querySelectorAll("[data-dashboard-view]").forEach(button=>button.onclick=()=>navigate(button.dataset.dashboardView));
  }

  async function renderAcademics(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Academic configuration</h3><p>Certified academic calendar, curriculum and readiness controls.</p></div></div>${loading("Loading academic configuration")}`;
    const [config,calendar,readiness]=await Promise.all([
      certified("get_academic_configuration"),
      certified("get_academic_calendar_context"),
      certified("academic_configuration_readiness")
    ]);
    const years=Array.isArray(config?.academic_years)?config.academic_years:[];
    const terms=Array.isArray(config?.terms)?config.terms:[];
    const classes=Array.isArray(config?.classes)?config.classes:[];
    const subjects=Array.isArray(config?.subjects)?config.subjects:[];
    const assignments=Array.isArray(config?.class_subjects)?config.class_subjects:[];
    const schemes=Array.isArray(config?.assessment_schemes)?config.assessment_schemes:[];
    const yearName=calendar?.academic_year?.name||"No active academic year";
    const termName=calendar?.term?.name||"No active term";
    const readinessTone=readiness?.ready?"valid":"invalid";
    const activeYearId=calendar?.academic_year?.id||"";
    const activeTermId=calendar?.term?.id||"";
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Academic configuration</h3><p>Certified academic calendar, curriculum and readiness controls.</p></div></div>
      <section class="stat-grid">
        <article class="stat-card"><span class="stat-icon blue" aria-hidden="true">◫</span><div><span>Academic years</span><strong>${years.length}</strong></div></article>
        <article class="stat-card"><span class="stat-icon gold" aria-hidden="true">▦</span><div><span>Classes</span><strong>${classes.length}</strong></div></article>
        <article class="stat-card"><span class="stat-icon green" aria-hidden="true">◇</span><div><span>Subjects</span><strong>${subjects.length}</strong></div></article>
        <article class="stat-card"><span class="stat-icon purple" aria-hidden="true">✓</span><div><span>Assessment schemes</span><strong>${schemes.length}</strong></div></article>
      </section>
      <section class="grid two">
        <article class="panel">
          <div class="panel-header"><div><h3>Current academic period</h3><p>Date-aware certified calendar context</p></div></div>
          <div class="panel-body">
            <div class="detail-grid"><div><span>Academic year</span><strong>${escapeHtml(yearName)}</strong></div><div><span>Term</span><strong>${escapeHtml(termName)}</strong></div></div>
            <form id="activePeriodForm" class="form-stack academic-active-period">
              <label class="field"><span>Academic year</span><select id="activeAcademicYear" name="academicYearId" required><option value="">Select academic year</option>${years.map(y=>`<option value="${escapeHtml(y.id)}" ${String(y.id)===String(activeYearId)?"selected":""}>${escapeHtml(y.name||"Academic year")}</option>`).join("")}</select></label>
              <label class="field"><span>Term</span><select id="activeTerm" name="termId" required></select></label>
              <button class="button primary" type="submit">Set active period</button>
              <p id="activePeriodMessage" class="form-message hidden" role="alert"></p>
            </form>
          </div>
        </article>
        <article class="panel">
          <div class="panel-header"><div><h3>Configuration readiness</h3><p>Certified release checks before academic operations</p></div></div>
          <div class="panel-body">
            <div class="verify-state ${readinessTone}">${escapeHtml(readiness?.message|| (readiness?.ready?"Academic configuration is ready.":"Academic configuration needs attention."))}</div>
            <div class="detail-grid"><div><span>Blocking items</span><strong>${escapeHtml(readiness?.blocking_count??0)}</strong></div><div><span>Warnings</span><strong>${escapeHtml(readiness?.warning_count??0)}</strong></div><div><span>Configured terms</span><strong>${escapeHtml(readiness?.term_count??terms.length)}</strong></div><div><span>Enrolled classes</span><strong>${escapeHtml(readiness?.enrolled_class_count??0)}</strong></div></div>
          </div>
        </article>
      </section>
      <section class="grid two academic-config-lists">
        <article class="panel"><div class="panel-header"><div><h3>Classes</h3><p>Active school class structure</p></div><span class="status neutral">${classes.length} records</span></div><div class="table-wrap"><table><thead><tr><th>Class</th><th>Order</th><th>Active</th></tr></thead><tbody>${classes.length?classes.map(row=>`<tr><td><strong>${escapeHtml(row.name||"Unnamed class")}</strong></td><td>${escapeHtml(row.level_order??0)}</td><td>${status(row.active===false?"inactive":"active")}</td></tr>`).join(""):'<tr><td colspan="3">No classes configured.</td></tr>'}</tbody></table></div></article>
        <article class="panel"><div class="panel-header"><div><h3>Subjects</h3><p>Certified curriculum subject directory</p></div><span class="status neutral">${subjects.length} records</span></div><div class="table-wrap"><table><thead><tr><th>Subject</th><th>Code</th><th>Active</th></tr></thead><tbody>${subjects.length?subjects.map(row=>`<tr><td><strong>${escapeHtml(row.name||"Unnamed subject")}</strong></td><td>${escapeHtml(row.code||"—")}</td><td>${status(row.active===false?"inactive":"active")}</td></tr>`).join(""):'<tr><td colspan="3">No subjects configured.</td></tr>'}</tbody></table></div></article>
      </section>
      <section class="panel pad"><div class="panel-header"><div><h3>Curriculum assignment coverage</h3><p>Class-subject assignments exposed by the certified compatibility layer</p></div></div><div class="panel-body"><div class="detail-grid"><div><span>Class-subject assignments</span><strong>${assignments.length}</strong></div><div><span>Active assessment schemes</span><strong>${schemes.filter(s=>s.active!==false).length}</strong></div></div></div></section>`;

    const yearSelect=byId("activeAcademicYear"),termSelect=byId("activeTerm");
    const refreshTerms=()=>{
      const selected=String(yearSelect?.value||"");
      const available=terms.filter(t=>String(t.academic_year_id)===selected);
      termSelect.innerHTML='<option value="">Select term</option>'+available.map(t=>`<option value="${escapeHtml(t.id)}" ${String(t.id)===String(activeTermId)?"selected":""}>${escapeHtml(t.name||`Term ${t.sequence||""}`)}</option>`).join("");
    };
    yearSelect?.addEventListener("change",refreshTerms);refreshTerms();
    byId("activePeriodForm")?.addEventListener("submit",async event=>{
      event.preventDefault();
      const button=event.currentTarget.querySelector('button[type="submit"]'),msg=byId("activePeriodMessage");
      button.disabled=true;msg.classList.add("hidden");
      try{
        await certified("set_active_period",{target_academic_year_id:yearSelect.value,target_term_id:termSelect.value});
        await renderAcademics();
      }catch(error){msg.textContent=friendly(error);msg.classList.remove("hidden");}
      finally{button.disabled=false;}
    });
  }

  async function renderStudents(){
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Students</h3><p>Search the active student directory.</p></div><div class="page-actions">${canCreateStudent()?'<button id="addStudentButton" class="button primary" type="button">Add student</button>':""}</div></div>
      <section class="panel"><form id="studentSearchForm" class="toolbar"><label class="search"><span class="sr-only">Search students</span><input id="studentSearch" name="q" type="search" placeholder="Search name or student number" autocomplete="off"></label><button class="button secondary" type="submit">Search</button></form><div id="studentResults">${loading("Loading students")}</div></section>`;
    byId("studentSearchForm")?.addEventListener("submit",event=>{event.preventDefault();loadStudents(byId("studentSearch").value.trim());});
    byId("addStudentButton")?.addEventListener("click",openStudentDialog);
    await loadStudents("");
  }

  async function loadStudents(q){
    const box=byId("studentResults");if(!box)return;box.innerHTML=loading("Loading students");
    try{
      const result=await api().listStudents({q,limit:50,offset:0});
      const rows=Array.isArray(result.rows)?result.rows:[];
      if(!rows.length){box.innerHTML=empty(q?"No students matched this search.":"No active student records are available yet.");return;}
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Student</th><th>Student no.</th><th>Gender</th><th>Date of birth</th><th>Status</th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${escapeHtml((row.first_name||row.last_name||"S").charAt(0).toUpperCase())}</span><span class="cell-copy"><strong>${escapeHtml(fullName(row)||"Unnamed student")}</strong><small>Created ${formatDate(row.created_at)}</small></span></div></td><td>${escapeHtml(row.student_no||"—")}</td><td>${escapeHtml(row.gender||"—")}</td><td>${formatDate(row.date_of_birth)}</td><td>${status(row.status)}</td></tr>`).join("")}</tbody></table></div>`;
    }catch(error){box.innerHTML=pageError(error);}
  }

  function openStudentDialog(){
    const dialog=byId("modal");
    byId("modalTitle").textContent="Add student";
    byId("modalSubtitle").textContent="Create a student record within the current school tenant.";
    byId("modalBody").innerHTML=`<form id="studentCreateForm" class="form-stack"><div class="form-grid"><label class="field"><span>Student number</span><input name="studentNo" required maxlength="60"></label><label class="field"><span>First name</span><input name="firstName" required maxlength="120"></label><label class="field"><span>Middle name</span><input name="middleName" maxlength="120"></label><label class="field"><span>Last name</span><input name="lastName" required maxlength="120"></label><label class="field"><span>Gender</span><select name="gender"><option value="unspecified">Unspecified</option><option value="male">Male</option><option value="female">Female</option></select></label><label class="field"><span>Date of birth</span><input name="dateOfBirth" type="date"></label></div><p id="studentCreateMessage" class="form-message hidden" role="alert"></p></form>`;
    byId("modalFooter").innerHTML='<button id="studentCancelButton" class="button ghost" type="button">Cancel</button><button id="studentSaveButton" class="button primary" type="submit" form="studentCreateForm">Save student</button>';
    byId("studentCancelButton").onclick=()=>dialog.close();
    byId("studentCreateForm").onsubmit=async event=>{
      event.preventDefault();const form=event.currentTarget,button=byId("studentSaveButton"),msg=byId("studentCreateMessage");button.disabled=true;msg.classList.add("hidden");
      try{const fd=new FormData(form);await api().createStudent(Object.fromEntries(fd.entries()));dialog.close();await renderStudents();}
      catch(error){msg.textContent=friendly(error);msg.classList.remove("hidden");}
      finally{button.disabled=false;}
    };
    if(typeof dialog.showModal==="function")dialog.showModal();else dialog.setAttribute("open","");
  }

  async function renderStaff(){
    byId("content").innerHTML='<div class="page-head"><div><h3>Staff</h3><p>Current staff and teacher directory.</p></div></div><section id="staffResults">'+loading("Loading staff")+"</section>";
    const box=byId("staffResults");
    try{
      const result=await api().listStaff();const rows=Array.isArray(result.rows)?result.rows:[];
      if(!rows.length){box.innerHTML=empty("No active staff records are available yet.");return;}
      box.innerHTML=`<section class="panel"><div class="table-wrap"><table><thead><tr><th>Staff member</th><th>Staff no.</th><th>Role / title</th><th>Type</th><th>Phone</th><th>Status</th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${escapeHtml(String(row.full_name||"S").charAt(0).toUpperCase())}</span><span class="cell-copy"><strong>${escapeHtml(row.full_name||"Unnamed staff")}</strong><small>${escapeHtml(row.email||"No email")}</small></span></div></td><td>${escapeHtml(row.staff_no||"—")}</td><td>${escapeHtml(row.job_title||"—")}</td><td>${escapeHtml(String(row.staff_type||"—").replaceAll("_"," "))}</td><td>${escapeHtml(row.phone||"—")}</td><td>${status(row.active===false?"inactive":"active")}</td></tr>`).join("")}</tbody></table></div></section>`;
    }catch(error){box.innerHTML=pageError(error);}
  }

  async function renderTeachers(){
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Teachers</h3><p>Certified teacher records, roles, and assignment visibility.</p></div><div class="page-actions"><button id="addTeacherButton" class="button primary" type="button">Add teacher</button></div></div>
      <section class="panel"><form id="teacherSearchForm" class="toolbar"><label class="search"><span class="sr-only">Search teachers</span><input id="teacherSearch" name="q" type="search" placeholder="Search name, staff number, email or phone"></label><select id="teacherStatus" aria-label="Employment status"><option value="">All statuses</option><option value="active">Active</option><option value="leave">Leave</option><option value="suspended">Suspended</option><option value="resigned">Resigned</option><option value="retired">Retired</option></select><button class="button secondary" type="submit">Search</button></form><div id="teacherResults">${loading("Loading teachers")}</div></section>`;
    byId("teacherSearchForm")?.addEventListener("submit",event=>{event.preventDefault();loadTeachers();});
    byId("addTeacherButton")?.addEventListener("click",()=>openTeacherDialog());
    await loadTeachers();
  }

  async function loadTeachers(){
    const box=byId("teacherResults");if(!box)return;box.innerHTML=loading("Loading teachers");
    try{
      const result=await certified("list_teachers",{search_text:byId("teacherSearch")?.value?.trim()||"",status_filter:byId("teacherStatus")?.value||"",archive_filter:"active",page_number:1,page_size:100});
      const rows=Array.isArray(result?.rows)?result.rows:[];
      if(!rows.length){box.innerHTML=empty("No active teacher records matched the current filters.");return;}
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Teacher</th><th>Staff no.</th><th>Qualification</th><th>Specialization</th><th>Assignments</th><th>Status</th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${escapeHtml(String(row.full_name||"T").charAt(0).toUpperCase())}</span><span class="cell-copy"><strong>${escapeHtml(row.full_name||"Unnamed teacher")}</strong><small>${escapeHtml(row.email||row.profile_email||"No email")}</small></span></div></td><td>${escapeHtml(row.staff_no||"—")}</td><td>${escapeHtml(row.qualification||"—")}</td><td>${escapeHtml(row.specialization||"—")}</td><td>${escapeHtml((Array.isArray(row.class_assignments)?row.class_assignments.length:0)+(Array.isArray(row.subject_assignments)?row.subject_assignments.length:0))}</td><td>${status(row.employment_status|| (row.active===false?"inactive":"active"))}</td></tr>`).join("")}</tbody></table></div>`;
    }catch(error){box.innerHTML=pageError(error);}
  }

  function openTeacherDialog(){
    const dialog=byId("modal");
    byId("modalTitle").textContent="Add teacher";
    byId("modalSubtitle").textContent="Create a certified teacher record. A staff number is generated when left blank.";
    byId("modalBody").innerHTML=`<form id="teacherCreateForm" class="form-stack"><div class="form-grid"><label class="field"><span>Staff number (optional)</span><input name="staff_no" maxlength="60"></label><label class="field"><span>First name</span><input name="first_name" required maxlength="120"></label><label class="field"><span>Middle name</span><input name="middle_name" maxlength="120"></label><label class="field"><span>Last name</span><input name="last_name" required maxlength="120"></label><label class="field"><span>Gender</span><select name="gender"><option value="Other">Other</option><option value="Male">Male</option><option value="Female">Female</option></select></label><label class="field"><span>Email</span><input name="email" type="email" maxlength="254"></label><label class="field"><span>Phone</span><input name="phone" type="tel" maxlength="60"></label><label class="field"><span>Qualification</span><select name="qualification"><option value="">Select</option><option>PhD</option><option>MSc Degree</option><option>Bachelor Degree</option><option>HND</option><option>Diploma</option><option>SHS</option></select></label><label class="field"><span>Specialization</span><input name="specialization" maxlength="180"></label><label class="field"><span>Date joined</span><input name="date_joined" type="date"></label></div><p id="teacherCreateMessage" class="form-message hidden" role="alert"></p></form>`;
    byId("modalFooter").innerHTML='<button id="teacherCancelButton" class="button ghost" type="button">Cancel</button><button id="teacherSaveButton" class="button primary" type="submit" form="teacherCreateForm">Save teacher</button>';
    byId("teacherCancelButton").onclick=()=>dialog.close();
    byId("teacherCreateForm").onsubmit=async event=>{
      event.preventDefault();const button=byId("teacherSaveButton"),msg=byId("teacherCreateMessage");button.disabled=true;msg.classList.add("hidden");
      try{const payload=Object.fromEntries(new FormData(event.currentTarget).entries());payload.active=true;payload.employment_status="active";payload.reason="Teacher created from Neon certified UI";await certified("save_teacher",{payload});dialog.close();await renderTeachers();}
      catch(error){msg.textContent=friendly(error);msg.classList.remove("hidden");}
      finally{button.disabled=false;}
    };
    if(typeof dialog.showModal==="function")dialog.showModal();else dialog.setAttribute("open","");
  }

  async function renderPrincipal(){
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Principal</h3><p>Certified Principal appointment and school leadership record.</p></div><div class="page-actions"><button id="addPrincipalButton" class="button primary" type="button">Add Principal record</button></div></div>
      <section class="panel"><div id="principalResults">${loading("Loading Principal record")}</div></section>`;
    byId("addPrincipalButton")?.addEventListener("click",openPrincipalDialog);
    const box=byId("principalResults");
    try{
      const result=await certified("list_headteachers",{search_text:"",status_filter:"",archive_filter:"active",page_number:1,page_size:50});
      const rows=Array.isArray(result?.rows)?result.rows:[];
      if(!rows.length){box.innerHTML=empty("No active Principal appointment is configured yet.");return;}
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Principal</th><th>Staff no.</th><th>Contact</th><th>Qualification</th><th>Appointed</th><th>Status</th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${escapeHtml(String(row.full_name||"P").charAt(0).toUpperCase())}</span><span class="cell-copy"><strong>${escapeHtml(row.full_name||"Unnamed Principal")}</strong><small>${escapeHtml(row.email||row.profile_email||"No linked email")}</small></span></div></td><td>${escapeHtml(row.staff_no||"—")}</td><td>${escapeHtml(row.phone||"—")}</td><td>${escapeHtml(row.qualification||"—")}</td><td>${formatDate(row.date_appointed)}</td><td>${status(row.employment_status|| (row.active===false?"inactive":"active"))}</td></tr>`).join("")}</tbody></table></div>`;
    }catch(error){box.innerHTML=pageError(error);}
  }

  function openPrincipalDialog(){
    const dialog=byId("modal");
    byId("modalTitle").textContent="Add Principal record";
    byId("modalSubtitle").textContent="Create the certified school leadership record. The single-current-Principal rule is enforced by the database.";
    byId("modalBody").innerHTML=`<form id="principalCreateForm" class="form-stack"><div class="form-grid"><label class="field"><span>Staff number (optional)</span><input name="staff_no" maxlength="60"></label><label class="field"><span>Full name</span><input name="full_name" required maxlength="180"></label><label class="field"><span>Contact phone</span><input name="contact" type="tel" required maxlength="60"></label></div><p id="principalCreateMessage" class="form-message hidden" role="alert"></p></form>`;
    byId("modalFooter").innerHTML='<button id="principalCancelButton" class="button ghost" type="button">Cancel</button><button id="principalSaveButton" class="button primary" type="submit" form="principalCreateForm">Save Principal</button>';
    byId("principalCancelButton").onclick=()=>dialog.close();
    byId("principalCreateForm").onsubmit=async event=>{
      event.preventDefault();const button=byId("principalSaveButton"),msg=byId("principalCreateMessage");button.disabled=true;msg.classList.add("hidden");
      try{const payload=Object.fromEntries(new FormData(event.currentTarget).entries());payload.reason="Principal record created from Neon certified UI";await certified("save_headteacher",{payload});dialog.close();await renderPrincipal();}
      catch(error){msg.textContent=friendly(error);msg.classList.remove("hidden");}
      finally{button.disabled=false;}
    };
    if(typeof dialog.showModal==="function")dialog.showModal();else dialog.setAttribute("open","");
  }

  async function renderFinance(){
    byId("content").innerHTML='<div class="page-head"><div><h3>Finance</h3><p>Current fee and collection position.</p></div></div>'+loading("Loading finance summary");
    const summary=await api().listFinanceSummary();
    byId("content").innerHTML=`<div class="page-head"><div><h3>Finance</h3><p>Current fee and collection position.</p></div></div><section class="stat-grid"><article class="stat-card"><span class="stat-icon gold" aria-hidden="true">¤</span><div><span>Outstanding balance</span><strong>${formatAmount(summary.outstanding)}</strong></div></article><article class="stat-card"><span class="stat-icon green" aria-hidden="true">+</span><div><span>Received today</span><strong>${formatAmount(summary.received_today)}</strong></div></article><article class="stat-card"><span class="stat-icon purple" aria-hidden="true">!</span><div><span>Overdue invoices</span><strong>${escapeHtml(summary.overdue_invoices??0)}</strong></div></article></section><section class="panel pad"><h3>Finance workspace</h3><p class="muted">Detailed fee schedules, invoices, payments, receipts, holds, and guardian follow-up continue through the certified Worker RPC compatibility layer as their UI slices are ported.</p></section>`;
  }

  async function loadNotificationCount(){
    if(!state.session)return;
    try{
      const data=await certified("list_notifications",{page_number:1,page_size:5});
      const count=Number(data?.unread||0),badge=byId("notificationBadge");
      if(badge){badge.textContent=count>99?"99+":String(count);badge.classList.toggle("hidden",count===0);}
    }catch{}
  }

  async function renderNotifications(){
    const data=await certified("list_notifications",{page_number:1,page_size:100});
    const rows=Array.isArray(data?.rows)?data.rows:[],unread=Number(data?.unread||0),total=Number(data?.total??rows.length);
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Notifications</h3><p>${escapeHtml(unread)} unread • ${escapeHtml(total)} total</p></div><div class="page-actions">${unread?'<button id="markAllRead" class="button secondary" type="button">Mark all read</button>':""}</div></div>
      <section class="panel"><div class="managed-card-list">${rows.length?rows.map(item=>`<article class="panel-header" data-notification-id="${escapeHtml(item.id)}" style="${item.read_at?"opacity:.72":""}"><div><h4>${escapeHtml(item.title||"Notification")}</h4><p>${escapeHtml(item.body||"")} • ${formatDateTime(item.created_at)}</p></div>${item.read_at?"":`<button class="button ghost small" type="button" data-notification-read="${escapeHtml(item.id)}">Mark read</button>`}</article>`).join(""):'<div class="panel-body"><p class="muted">No notifications.</p></div>'}</div></section>`;
    byId("markAllRead")?.addEventListener("click",async()=>{await certified("mark_notifications_read",{notification_ids:null});await loadNotificationCount();await renderNotifications();});
    byId("content").querySelectorAll("[data-notification-read]").forEach(button=>button.addEventListener("click",async()=>{button.disabled=true;try{await certified("mark_notifications_read",{notification_ids:[button.dataset.notificationRead]});await loadNotificationCount();await renderNotifications();}finally{button.disabled=false;}}));
  }

  function beginMfa(result,scope=state.authScope){
    state.authScope=scope;mfaChallenge=String(result.challengeToken||"");showAuthStep("mfaPanel");
    const enrolling=result.mode==="enroll";
    byId("mfaTitle").textContent=enrolling?"Set up two-step verification":"Two-step verification";
    byId("mfaHelp").textContent=enrolling?"Your administrator account requires MFA. Add the setup key to your authenticator app, then enter the current six-digit code.":"Enter the current six-digit code from your authenticator app, or a saved recovery code.";
    byId("mfaSetup").classList.toggle("hidden",!enrolling);byId("mfaSecret").textContent=enrolling?String(result.setup?.secret||""):"";
    byId("mfaCode").value="";byId("mfaCode").focus();
  }

  byId("loginForm")?.addEventListener("submit",async event=>{
    event.preventDefault();message("");const fd=new FormData(event.currentTarget),button=event.currentTarget.querySelector('button[type="submit"]');
    if(turnstileSiteKey&&!turnstileToken){message("Complete the human verification before signing in.","error");renderTurnstile();return;}
    const tenantCode=String(fd.get("tenantCode")||byId("tenantCodeFallback")?.value||"").trim().toUpperCase();
    button.disabled=true;
    try{
      const scope=platformMode?"platform":"tenant";
      const result=scope==="platform"
        ?await api().platformLogin(fd.get("email"),fd.get("password"),turnstileToken)
        :await api().login(fd.get("email"),fd.get("password"),tenantCode,turnstileToken);
      turnstileToken="";state.authScope=scope;
      if(result?.mfaRequired){beginMfa(result,scope);return;}
      if(scope==="platform"){location.replace("./platform-saas-admin.html");return;}
      await enter(result);
    }
    catch(error){if(!platformMode&&error?.code==="tenant_selection_required"){byId("tenantCodeField")?.classList.remove("hidden");byId("tenantCodeFallback")?.focus();}message(friendly(error),"error");resetTurnstile();}
    finally{button.disabled=false;}
  });
  byId("mfaForm")?.addEventListener("submit",async event=>{
    event.preventDefault();message("");const button=event.currentTarget.querySelector('button[type="submit"]'),code=String(byId("mfaCode").value||"").trim();button.disabled=true;
    try{
      const scope=state.authScope;
      const result=scope==="platform"?await api().platformCompleteMfa(mfaChallenge,code):await api().completeMfa(mfaChallenge,code);
      mfaChallenge="";
      if(Array.isArray(result.recoveryCodes)&&result.recoveryCodes.length){pendingSession=result;pendingScope=scope;byId("recoveryCodes").textContent=result.recoveryCodes.join("\n");showAuthStep("recoveryPanel");}
      else if(scope==="platform")location.replace("./platform-saas-admin.html");
      else await enter(result);
    }
    catch(error){message(friendly(error),"error");byId("mfaCode").select();}
    finally{button.disabled=false;}
  });
  byId("mfaBack")?.addEventListener("click",()=>{mfaChallenge="";state.authScope=platformMode?"platform":"tenant";showAuthStep("loginForm");resetTurnstile();renderTurnstile();message("");});
  byId("recoveryContinue")?.addEventListener("click",async()=>{if(!pendingSession)return;const s=pendingSession,scope=pendingScope;pendingSession=null;pendingScope=platformMode?"platform":"tenant";byId("recoveryCodes").textContent="";if(scope==="platform"){location.replace("./platform-saas-admin.html");return;}await enter(s);});
  byId("togglePassword")?.addEventListener("click",()=>{const input=byId("password"),showing=input?.type==="text";if(input)input.type=showing?"password":"text";byId("togglePassword").setAttribute("aria-label",showing?"Show password":"Hide password");});
  byId("tenantCodeFallback")?.addEventListener("input",event=>{byId("tenantCode").value=String(event.currentTarget.value||"").trim().toUpperCase();});
  byId("registerSchoolButton")?.addEventListener("click",()=>{const dialog=byId("registrationDialog");byId("registrationMessage").textContent="";if(typeof dialog.showModal==="function")dialog.showModal();else dialog.setAttribute("open","");setTimeout(renderRegistrationTurnstile,0);});
  const closeRegistration=()=>{const dialog=byId("registrationDialog");if(dialog?.open)dialog.close();};
  byId("registrationClose")?.addEventListener("click",closeRegistration);byId("registrationCancel")?.addEventListener("click",closeRegistration);byId("registrationDialog")?.addEventListener("click",event=>{if(event.target===event.currentTarget)closeRegistration();});
  byId("registrationForm")?.addEventListener("submit",async event=>{event.preventDefault();const form=event.currentTarget,button=form.querySelector('button[type="submit"]'),msg=byId("registrationMessage");msg.textContent="";msg.dataset.kind="";if(turnstileSiteKey&&!registrationToken){msg.textContent="Complete the human verification before submitting your registration.";msg.dataset.kind="error";renderRegistrationTurnstile();return;}button.disabled=true;try{const fd=new FormData(form),result=await api().registerSchool({schoolName:fd.get("schoolName"),institutionType:fd.get("institutionType"),contactName:fd.get("contactName"),contactEmail:fd.get("contactEmail"),contactPhone:fd.get("contactPhone"),country:fd.get("country"),turnstileToken:registrationToken});form.reset();registrationToken="";msg.textContent="Registration submitted successfully. The Platform Super Administrator will review it before the school workspace is provisioned.";msg.dataset.kind="success";if(window.turnstile&&registrationWidgetId!=null){try{window.turnstile.reset(registrationWidgetId);}catch{}}return result;}catch(error){msg.textContent=friendly(error);msg.dataset.kind="error";registrationToken="";if(window.turnstile&&registrationWidgetId!=null){try{window.turnstile.reset(registrationWidgetId);}catch{}}}finally{button.disabled=false;}});
  byId("forgotPasswordButton")?.addEventListener("click",()=>{const dialog=byId("accessRecoveryDialog"),form=byId("accessRecoveryForm"),email=String(byId("email")?.value||"").trim(),tenantCode=String(byId("tenantCode")?.value||"").trim();if(form){form.elements.identifier.value=tenantCode||email||"";form.elements.contactEmail.value=email||"";}byId("accessRecoveryMessage").textContent="";if(typeof dialog.showModal==="function")dialog.showModal();else dialog.setAttribute("open","");setTimeout(renderRecoveryTurnstile,0);});
  const closeRecovery=()=>{const dialog=byId("accessRecoveryDialog");if(dialog?.open)dialog.close();};
  byId("accessRecoveryClose")?.addEventListener("click",closeRecovery);byId("accessRecoveryCancel")?.addEventListener("click",closeRecovery);byId("accessRecoveryDialog")?.addEventListener("click",event=>{if(event.target===event.currentTarget)closeRecovery();});
  byId("accessRecoveryForm")?.addEventListener("submit",async event=>{event.preventDefault();const form=event.currentTarget,button=form.querySelector('button[type="submit"]'),msg=byId("accessRecoveryMessage");msg.textContent="";msg.dataset.kind="";if(turnstileSiteKey&&!recoveryTurnstileToken){msg.textContent="Complete the human verification before submitting the recovery request.";msg.dataset.kind="error";renderRecoveryTurnstile();return;}button.disabled=true;try{const fd=new FormData(form),result=await api().requestAccessRecovery({identifier:fd.get("identifier"),contactEmail:fd.get("contactEmail"),recoveryType:fd.get("recoveryType"),turnstileToken:recoveryTurnstileToken});msg.textContent=result?.message||"Recovery request submitted for protected review.";msg.dataset.kind="success";recoveryTurnstileToken="";if(window.turnstile&&recoveryWidgetId!=null){try{window.turnstile.reset(recoveryWidgetId);}catch{}}}catch(error){msg.textContent=friendly(error);msg.dataset.kind="error";recoveryTurnstileToken="";if(window.turnstile&&recoveryWidgetId!=null){try{window.turnstile.reset(recoveryWidgetId);}catch{}}}finally{button.disabled=false;}});
  byId("logoutButton")?.addEventListener("click",async()=>{try{await api().logout();}finally{location.reload();}});
  byId("menuButton")?.addEventListener("click",()=>byId("sidebar")?.classList.toggle("open"));
  byId("refreshButton")?.addEventListener("click",()=>navigate(state.view));
  byId("notificationButton")?.addEventListener("click",()=>navigate("notifications"));
  byId("modalClose")?.addEventListener("click",()=>byId("modal")?.close());
  byId("modal")?.addEventListener("click",event=>{if(event.target===event.currentTarget)event.currentTarget.close();});
  window.addEventListener("online",()=>setSync("online","Connected"));
  window.addEventListener("offline",()=>setSync("offline","Offline"));

  if("serviceWorker" in navigator)window.addEventListener("load",()=>navigator.serviceWorker.register("./service-worker.js").catch(()=>{}),{once:true});
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot,{once:true});else boot();
})();
