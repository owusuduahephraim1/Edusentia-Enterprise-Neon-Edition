(() => {
  "use strict";

  const content = document.getElementById("content");
  if (!content) return;

  let sequence = 0;
  let scheduled = false;

  function installSidebarOverflowGuard(){
    if(document.getElementById("edsTenantSidebarOverflowGuard"))return;
    const style=document.createElement("style");
    style.id="edsTenantSidebarOverflowGuard";
    style.textContent=`
      #sidebar{overflow:hidden;height:100vh;height:100dvh;max-height:100dvh;overscroll-behavior:contain}
      #sidebar .sidebar-brand{flex:0 0 auto;min-width:0}
      #mainNav.nav-list{flex:1 1 auto;min-height:0}
      #sidebar .sidebar-foot{flex:0 0 auto;margin-top:0}
      #sidebar .profile-chip{min-width:0}
      #sidebar .profile-copy{min-width:0}
      #sidebar .profile-copy strong,#sidebar .profile-copy small{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      #mainNav.nav-list{width:100%;min-width:0;max-width:100%;overflow-x:hidden!important;overflow-y:auto!important;scrollbar-width:none!important;-ms-overflow-style:none!important;scrollbar-gutter:auto!important}
      #mainNav.nav-list::-webkit-scrollbar{width:0!important;height:0!important;display:none!important}
      #mainNav .nav-item{min-width:0;max-width:100%;overflow:hidden}
      #mainNav .nav-label{min-width:0;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      #mainNav .accountant-parent-followup-nav-item{min-height:62px;align-items:center}
      #mainNav .accountant-parent-followup-nav-item .nav-label{white-space:normal!important;text-overflow:clip!important;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-height:1.18;max-height:2.36em;overflow:hidden}
      @media(max-width:820px){
        #sidebar{width:clamp(220px,70vw,248px);max-width:calc(100vw - 48px);height:100vh;height:100dvh;max-height:100dvh;padding:12px 10px calc(10px + env(safe-area-inset-bottom,0px))}
        #sidebar .sidebar-brand{gap:9px;padding:4px 5px 12px}
        #sidebar .sidebar-brand img{width:48px;height:48px}
        #sidebar .sidebar-brand strong{font-size:13px;line-height:1.2}
        #sidebar .sidebar-brand small{font-size:11px;line-height:1.25;margin-top:2px}
        #mainNav.nav-list{gap:3px;margin-top:10px;padding:1px 1px 6px}
        #mainNav .nav-item{min-height:44px;padding:6px 8px;gap:8px;border-radius:10px}
        #mainNav .nav-icon{width:28px;height:28px;flex:0 0 28px;border-radius:8px;font-size:15px}
        #mainNav .nav-label{font-size:13px;line-height:1.2}
        #mainNav .nav-active-dot{width:6px;height:6px;flex-basis:6px}
        #mainNav .accountant-parent-followup-nav-item{min-height:52px}
        #sidebar .sidebar-foot{padding-top:9px}
        #sidebar .profile-chip{gap:8px}
        #sidebar .avatar{width:36px;height:36px;border-radius:10px;flex:0 0 36px}
        #sidebar .profile-copy strong{font-size:13px;line-height:1.2}
        #sidebar .profile-copy small{font-size:11px;line-height:1.25}
        #sidebar .icon-button.inverse{width:36px;height:36px;flex:0 0 36px;font-size:17px}
      }
      @media(max-height:760px){
        #sidebar{padding-top:10px;padding-bottom:max(8px,env(safe-area-inset-bottom,0px))}
        #sidebar .sidebar-brand{gap:8px;padding-top:2px;padding-bottom:9px}
        #sidebar .sidebar-brand img{width:46px;height:46px}
        #mainNav.nav-list{gap:3px;margin-top:8px;padding-bottom:4px}
        #mainNav .nav-item{min-height:44px;padding-top:5px;padding-bottom:5px}
        #sidebar .sidebar-foot{padding-top:7px}
        #sidebar .avatar{width:34px;height:34px;flex-basis:34px}
        #sidebar .icon-button.inverse{width:34px;height:34px;flex-basis:34px}
      }
      @media(max-width:420px){
        #sidebar{width:clamp(216px,72vw,238px);max-width:calc(100vw - 42px);padding-left:9px;padding-right:9px}
        #sidebar .sidebar-brand{padding-left:4px;padding-right:4px}
        #mainNav .nav-label{font-size:12.5px}
      }
      #content{--eds-tenant-scroll-max:clamp(300px,42dvh,420px);--eds-tenant-scroll-two-max:clamp(270px,36dvh,360px)}
      #content .tenant-scroll-region{max-height:var(--eds-tenant-scroll-max)!important}
      #content .grid.two .tenant-scroll-region{max-height:var(--eds-tenant-scroll-two-max)!important}
      #content .tenant-scroll-region.tenant-scroll-region-expanded{max-height:min(80dvh,900px)!important}
      #content .tenant-adaptive-panel{min-width:0}
      #content .tenant-panel-scroll-region{overflow:auto!important;overscroll-behavior:contain;scrollbar-gutter:stable both-edges;-webkit-overflow-scrolling:touch}
      #content .tenant-panel-scroll-region:focus-visible{outline:3px solid rgba(13,94,200,.16);outline-offset:-3px}
      #content .tenant-scroll-region table{min-width:100%}
      #content .tenant-scroll-region table thead th{position:sticky;top:0;z-index:5;background:#f7f9fc;box-shadow:0 1px 0 #dce4ef}
      #content .tenant-adaptive-panel>.panel-header{position:relative;z-index:6;background:var(--surface,#fff)}
      @media(max-width:820px){#content{--eds-tenant-scroll-max:clamp(280px,48dvh,360px);--eds-tenant-scroll-two-max:clamp(260px,44dvh,330px)}}
      @media(max-width:560px){#content{--eds-tenant-scroll-max:clamp(250px,50dvh,320px);--eds-tenant-scroll-two-max:clamp(240px,46dvh,300px)}}
      @media print{#content .tenant-scroll-region,#content .tenant-panel-scroll-region,#content .tenant-scroll-region.tenant-scroll-region-expanded{max-height:none!important;overflow:visible!important}#content .tenant-list-toggle{display:none!important}}
    `;
    document.head.appendChild(style);
  }
  installSidebarOverflowGuard();

  const LIST_SELECTORS = [
    ".table-wrap",
    ".score-grid",
    ".timeline",
    ".bar-list",
    "[role='list']",
    ".card-list",
    ".event-list",
    ".history-list",
    ".audit-list",
    ".notification-list",
    ".record-list"
  ].join(",");

  const PANEL_DATA_HINTS = [
    "table",
    ".table-wrap",
    ".score-grid",
    ".timeline",
    ".bar-list",
    "[role='list']",
    ".card-list",
    ".event-list",
    ".history-list",
    ".audit-list",
    ".notification-list",
    ".record-list",
    "[class*='ledger']",
    "[class*='register']",
    "[class*='directory']",
    "[class*='result']",
    "[class*='record']"
  ].join(",");

  function rowCount(region) {
    const table = region.matches("table") ? region : region.querySelector(":scope > table, table");
    if (table) return table.tBodies?.[0]?.rows?.length || table.querySelectorAll("tbody tr").length;
    return region.children?.length || 0;
  }

  function isLong(region) {
    if (!region || region.closest("dialog") || region.dataset.tenantScrollIgnore === "1") return false;
    if (region.matches(".checklist-menu,.vertical-check-panel")) return false;
    const rows = rowCount(region);
    const tableLike = Boolean(region.matches(".table-wrap,.score-grid") || region.querySelector("table"));
    if (tableLike && rows >= 7) return true;
    if (!tableLike && rows >= 9) return true;
    return region.scrollHeight > 430;
  }

  function toolbarFor(region) {
    const panel = region.closest(".panel");
    const header = panel?.querySelector(":scope > .panel-header");
    if (header) {
      let controls = header.querySelector(":scope > .tenant-list-controls");
      if (!controls) {
        controls = document.createElement("div");
        controls.className = "tenant-list-controls";
        header.appendChild(controls);
      }
      return controls;
    }

    if (region.previousElementSibling?.matches?.(".tenant-list-toolbar")) return region.previousElementSibling;
    const toolbar = document.createElement("div");
    toolbar.className = "tenant-list-toolbar";
    region.parentNode?.insertBefore(toolbar, region);
    return toolbar;
  }

  function decorate(region) {
    if (!isLong(region)) return;
    if (region.dataset.tenantScrollDecorated === "1") return;

    region.dataset.tenantScrollDecorated = "1";
    region.classList.add("tenant-scroll-region");
    if (!region.id) region.id = `tenantScrollRegion${++sequence}`;
    if (!region.hasAttribute("tabindex")) region.tabIndex = 0;

    const toolbar = toolbarFor(region);
    if (!toolbar || toolbar.querySelector(`[data-tenant-list-toggle="${region.id}"]`)) return;

    const button = document.createElement("button");
    button.type = "button";
    button.className = "button ghost small tenant-list-toggle";
    const label = region.classList.contains("tenant-panel-scroll-region") ? "panel" : "list";
    button.dataset.tenantListToggle = region.id;
    button.dataset.tenantToggleLabel = label;
    button.setAttribute("aria-controls", region.id);
    button.setAttribute("aria-expanded", "false");
    button.textContent = `Expand ${label}`;
    toolbar.appendChild(button);
  }

  function normalizeTableRegion(table) {
    if (!table) return null;
    const existing = table.closest(".table-wrap,.score-grid,.tenant-scroll-region");
    if (existing) return existing;
    const parent = table.parentElement;
    if (!parent || parent === content) return null;
    return parent;
  }

  function panelBodyHasLongData(body) {
    if (!body) return false;

    let tableRows = 0;
    body.querySelectorAll("table").forEach((table) => {
      tableRows += table.tBodies?.[0]?.rows?.length || table.querySelectorAll("tbody tr").length;
    });
    if (tableRows >= 7) return true;

    for (const list of body.querySelectorAll("ul,ol,[role='list'],.card-list,.event-list,.history-list,.audit-list,.notification-list,.record-list")) {
      if ((list.children?.length || 0) >= 9) return true;
    }

    const repeated = body.querySelectorAll("[role='listitem'],.record-item,.history-item,.audit-item,.notification-item,.event-item,.card-item");
    if (repeated.length >= 9) return true;

    if (!body.querySelector("form") && (body.children?.length || 0) >= 12) return true;
    if (!body.querySelector("form") && body.querySelectorAll(":scope > .grid > *").length >= 12) return true;

    return body.scrollHeight > 520 && Boolean(body.querySelector(PANEL_DATA_HINTS));
  }

  function decoratePanelFallbacks() {
    content.querySelectorAll(".panel").forEach((panel) => {
      if (panel.closest("dialog") || panel.dataset.tenantScrollIgnore === "1") return;
      if (panel.querySelector(".tenant-scroll-region")) return;

      const body = panel.querySelector(":scope > .panel-body");
      if (!body || body.dataset.tenantScrollIgnore === "1") return;

      const hasDataHint = Boolean(body.querySelector(PANEL_DATA_HINTS));
      if (body.querySelector("form") && !hasDataHint) return;
      if (!panelBodyHasLongData(body)) return;

      panel.classList.add("tenant-adaptive-panel");
      body.classList.add("tenant-panel-scroll-region");
      if (!body.hasAttribute("aria-label")) {
        const heading = panel.querySelector(":scope > .panel-header h3, :scope > .panel-header h4");
        body.setAttribute("aria-label", heading?.textContent?.trim() ? `${heading.textContent.trim()} scrollable content` : "Scrollable panel content");
      }
      decorate(body);
    });
  }

  function decorateAll() {
    scheduled = false;
    const regions = new Set();

    content.querySelectorAll(LIST_SELECTORS).forEach((region) => regions.add(region));
    content.querySelectorAll("table").forEach((table) => {
      const region = normalizeTableRegion(table);
      if (region) regions.add(region);
    });

    content.querySelectorAll(".panel-body > ul, .panel-body > ol, .panel-body > .grid, .panel > .grid").forEach((region) => {
      if (region.matches(".form-grid,.stat-grid,.metric-row,.report-layout,.report-sidebar")) return;
      if (region.querySelector("input,textarea,select") && !region.querySelector("table")) return;
      regions.add(region);
    });

    regions.forEach(decorate);
    decoratePanelFallbacks();
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(decorateAll);
  }

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-tenant-list-toggle]");
    if (!button) return;
    event.preventDefault();

    const region = document.getElementById(String(button.dataset.tenantListToggle || ""));
    if (!region) return;

    const expanded = region.classList.toggle("tenant-scroll-region-expanded");
    const label = button.dataset.tenantToggleLabel === "panel" ? "panel" : "list";
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    button.textContent = expanded ? `Restore ${label}` : `Expand ${label}`;
  });

  const observer = new MutationObserver(schedule);
  observer.observe(content, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "hidden", "aria-hidden"] });

  window.addEventListener("resize", schedule, { passive: true });
  window.addEventListener("pageshow", schedule, { passive: true });
  schedule();

  function loadFinanceReceiptV2(){
    if(window.EdusentiaProfessionalFinanceReceipts?.version==="v2"||document.querySelector('script[data-edusentia-finance-receipt-v2]'))return;
    let attempts=0;
    const timer=setInterval(()=>{
      attempts++;
      if(window.EdusentiaProfessionalFinanceReceipts?.version==="v2"){clearInterval(timer);return}
      if(!window.EdusentiaFinanceRuntime){if(attempts>=240)clearInterval(timer);return}
      clearInterval(timer);
      const script=document.createElement("script");
      script.src="finance-professional-receipts.js?edusentia=r40-finance-receipt-v2";
      script.defer=true;
      script.dataset.edusentiaFinanceReceiptV2="1";
      script.addEventListener("error",()=>console.error("finance_receipt_v2_load_failed"),{once:true});
      document.body.appendChild(script);
    },100);
  }
  loadFinanceReceiptV2();
  window.addEventListener("pageshow",loadFinanceReceiptV2,{passive:true});

  function loadAccountantStudentRolesV2(){
    if(window.EDS_ACCOUNTANT_STUDENT_ROLES_V2||document.querySelector('script[data-edusentia-accountant-student-roles-v2]'))return;
    const script=document.createElement("script");
    script.src="tenant-accountant-student-roles-v2.js?edusentia=r40-accountant-student-roles-v2";
    script.defer=true;
    script.dataset.edusentiaAccountantStudentRolesV2="1";
    script.addEventListener("error",()=>console.error("accountant_student_roles_v2_load_failed"),{once:true});
    document.body.appendChild(script);
  }
  loadAccountantStudentRolesV2();
  window.addEventListener("pageshow",loadAccountantStudentRolesV2,{passive:true});

  function loadAccountantStudentSubmitV3(){
    if(window.EDS_ACCOUNTANT_STUDENT_SUBMIT_V3||document.querySelector('script[data-edusentia-accountant-student-submit-v3]'))return;
    const script=document.createElement("script");
    script.src="tenant-accountant-student-submit-v3.js?edusentia=r40-accountant-student-submit-v3";
    script.defer=true;
    script.dataset.edusentiaAccountantStudentSubmitV3="1";
    script.addEventListener("error",()=>console.error("accountant_student_submit_v3_load_failed"),{once:true});
    document.body.appendChild(script);
  }
  loadAccountantStudentSubmitV3();
  window.addEventListener("pageshow",loadAccountantStudentSubmitV3,{passive:true});

  function loadAccountantDashboardV1(){
    if(window.EDS_ACCOUNTANT_DASHBOARD_V1||document.querySelector('script[data-edusentia-accountant-dashboard-v1]'))return;
    const script=document.createElement("script");
    script.src="tenant-accountant-dashboard-v1.js?edusentia=r40-accountant-dashboard-v1";
    script.defer=true;
    script.dataset.edusentiaAccountantDashboardV1="1";
    script.addEventListener("error",()=>console.error("accountant_dashboard_v1_load_failed"),{once:true});
    document.body.appendChild(script);
  }
  loadAccountantDashboardV1();
  window.addEventListener("pageshow",loadAccountantDashboardV1,{passive:true});

  function loadAccountantParentFollowUpV1(){
    if(window.EDS_ACCOUNTANT_PARENT_FOLLOW_UP_V1||document.querySelector('script[data-edusentia-accountant-parent-follow-up-v1]'))return;
    const script=document.createElement("script");
    script.src="tenant-accountant-parent-follow-up-v1.js?edusentia=r40-accountant-parent-follow-up-v1";
    script.defer=true;
    script.dataset.edusentiaAccountantParentFollowUpV1="1";
    script.addEventListener("error",()=>console.error("accountant_parent_follow_up_v1_load_failed"),{once:true});
    document.body.appendChild(script);
  }
  loadAccountantParentFollowUpV1();
  window.addEventListener("pageshow",loadAccountantParentFollowUpV1,{passive:true});

  function loadAccountantParentFollowUpV2(){
    if(window.EDS_ACCOUNTANT_PARENT_FOLLOW_UP_V2||document.querySelector('script[data-edusentia-accountant-parent-follow-up-v2]'))return;
    const script=document.createElement("script");
    script.src="tenant-accountant-parent-follow-up-v2.js?edusentia=r40-accountant-parent-follow-up-v2";
    script.defer=true;
    script.dataset.edusentiaAccountantParentFollowUpV2="1";
    script.addEventListener("error",()=>console.error("accountant_parent_follow_up_v2_load_failed"),{once:true});
    document.body.appendChild(script);
  }
  loadAccountantParentFollowUpV2();
  window.addEventListener("pageshow",loadAccountantParentFollowUpV2,{passive:true});

  function loadUserCredentialActionsV2(){
    if(window.EDS_USER_CREDENTIAL_ACTIONS_V2||document.querySelector('script[data-edusentia-user-credential-actions-v2]'))return;
    const script=document.createElement("script");
    script.src="tenant-user-credential-actions-v2.js?edusentia=r40-user-credential-actions-v2";
    script.defer=true;
    script.dataset.edusentiaUserCredentialActionsV2="1";
    script.addEventListener("error",()=>console.error("user_credential_actions_v2_load_failed"),{once:true});
    document.body.appendChild(script);
  }
  loadUserCredentialActionsV2();
  window.addEventListener("pageshow",loadUserCredentialActionsV2,{passive:true});

  const DIRECT_TENANT_MODULES=[
    ["tenant-backup-r2-download-v1.js?edusentia=r40-backup-r2-download-v1","data-edusentia-backup-r2-download","backup_r2_download_v1_load_failed"],
    ["tenant-hr-staff-v1.js?edusentia=r40-hr-staff-v1","data-edusentia-hr-staff","hr_staff_v1_load_failed"],
    ["tenant-student-services-v1.js?edusentia=r40-student-services-v1","data-edusentia-student-services","student_services_v1_load_failed"]
  ];
  function loadDirectTenantModules(){
    for(const [src,marker,errorName] of DIRECT_TENANT_MODULES){
      if(document.querySelector(`script[${marker}]`))continue;
      const script=document.createElement("script");
      script.src=src;
      script.defer=true;
      script.setAttribute(marker,"1");
      script.addEventListener("error",()=>console.error(errorName),{once:true});
      document.body.appendChild(script);
    }
  }
  loadDirectTenantModules();
  window.addEventListener("pageshow",loadDirectTenantModules,{passive:true});

  let studentPortalLoadTimer=0;
  function loadStudentPortalV1(){
    if(window.EDS_STUDENT_PORTAL_V1||document.querySelector('script[data-edusentia-student-portal-v1]'))return;
    if(studentPortalLoadTimer)return;
    let attempts=0;
    studentPortalLoadTimer=setInterval(()=>{
      attempts++;
      if(window.EDS_STUDENT_PORTAL_V1){clearInterval(studentPortalLoadTimer);studentPortalLoadTimer=0;return}
      if(!window.EdusentiaFinancePortals){
        if(attempts>=240){clearInterval(studentPortalLoadTimer);studentPortalLoadTimer=0;console.error("student_portal_owner_wait_timeout")}
        return;
      }
      clearInterval(studentPortalLoadTimer);studentPortalLoadTimer=0;
      const script=document.createElement("script");
      script.src="tenant-student-portal-v1.js?edusentia=r40-student-portal-owner-v2";
      script.defer=true;
      script.dataset.edusentiaStudentPortalV1="1";
      script.addEventListener("error",()=>console.error("student_portal_v1_load_failed"),{once:true});
      document.body.appendChild(script);
    },100);
  }
  loadStudentPortalV1();
  window.addEventListener("pageshow",loadStudentPortalV1,{passive:true});

  window.EDS_TENANT_LIST_RESILIENCE = Object.freeze({ refresh: schedule });
})();