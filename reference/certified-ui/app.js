(() => {
  "use strict";

  async function uploadSignedStorageObject(client,bucket,path,token,file,contentType="application/octet-stream") {
    const signed=String(token||"");
    if(/^https:\/\//i.test(signed)){
      const response=await fetch(signed,{method:"PUT",headers:{"Content-Type":contentType},body:file,redirect:"error"});
      if(!response.ok)throw new Error((await response.text().catch(()=>""))||`Cloudflare R2 upload failed (${response.status})`);
      return;
    }
    const {error}=await client.storage.from(bucket).uploadToSignedUrl(path,token,file,{contentType});
    if(error)throw error;
  }
  window.RCE_RUNTIME_BUILD="7.4.0-r40-product-ready-v8";

  const RUNTIME_CONFIG = window.RCE_CONFIG || window.NIS_CONFIG || {};
  const CONFIG = Object.freeze({
    supabaseUrl: RUNTIME_CONFIG.supabaseUrl || "YOUR_SUPABASE_URL",
    supabaseAnonKey: RUNTIME_CONFIG.supabaseAnonKey || "YOUR_SUPABASE_ANON_KEY",
    productName: RUNTIME_CONFIG.productName || "Report Card Enterprise",
    productVersion: RUNTIME_CONFIG.productVersion || "7.4.0",
    productShortName: RUNTIME_CONFIG.productShortName || "RCE",
    productTagline: RUNTIME_CONFIG.productTagline || "School Report Card and Academic Records System",
    productLogoPath: RUNTIME_CONFIG.productLogoPath || "assets/rce-master-logo.png",
    masterEdition: RUNTIME_CONFIG.masterEdition === undefined ? !Boolean(RUNTIME_CONFIG.generatedSchoolPackage) : Boolean(RUNTIME_CONFIG.masterEdition),
    appName: RUNTIME_CONFIG.appName || "Report Card Enterprise",
    schoolName: RUNTIME_CONFIG.schoolName || "",
    schoolShortName: RUNTIME_CONFIG.schoolShortName || "",
    userEmailDomain: RUNTIME_CONFIG.userEmailDomain || "edusentia.app",
    reportNumberPrefix: RUNTIME_CONFIG.reportNumberPrefix || "RCE",
    generatedSchoolPackage: Boolean(RUNTIME_CONFIG.generatedSchoolPackage),
    tenantCode: RUNTIME_CONFIG.tenantCode || "",
    packageId: RUNTIME_CONFIG.packageId || "",
    installationId: RUNTIME_CONFIG.installationId || "",
    projectRef: RUNTIME_CONFIG.projectRef || "",
    authorizedDomain: RUNTIME_CONFIG.authorizedDomain || "",
    licenseKeyId: RUNTIME_CONFIG.licenseKeyId || "",
    logoPath: RUNTIME_CONFIG.logoPath || RUNTIME_CONFIG.productLogoPath || "assets/rce-master-logo.png",
    defaultReportTemplatePath: RUNTIME_CONFIG.defaultReportTemplatePath || "assets/approved-terminal-report-template.png",
    photoBucket: "student-photos",
    pdfBucket: "report-pdfs",
    backupBucket: "system-backups",
    signatureBucket: "headteacher-signatures",
    staffPhotoBucket: "staff-photos",
    brandingBucket: "school-branding",
    templateBucket: "report-card-templates",
    certificatePdfBucket: "certificate-pdfs",
    certificateTemplateBucket: "certificate-templates",
    pageSize: 20
  });

  function stableInstallationHash(value) {
    let hash=2166136261;
    for(const character of String(value||"")){
      hash^=character.charCodeAt(0);
      hash=Math.imul(hash,16777619);
    }
    return (hash>>>0).toString(36);
  }
  const INSTALLATION_SCOPE_SOURCE=[
    CONFIG.supabaseUrl,
    CONFIG.reportNumberPrefix,
    window.location.origin,
    window.location.pathname.replace(/[^/]*$/,""),
  ].join("|");
  const INSTALLATION_SCOPE_KEY=stableInstallationHash(INSTALLATION_SCOPE_SOURCE);
  const LOCAL_DATABASE_NAME=`rce-report-card-${INSTALLATION_SCOPE_KEY}`;
  const OFFLINE_AUTH_MAX_AGE_MS=24*60*60*1000;
  const OFFLINE_DATA_MAX_AGE_MS=7*24*60*60*1000;
  const OFFLINE_COLD_START_ROLES=new Set(["class_teacher","subject_teacher"]);

  function isNetworkFailure(error) {
    const message=String(error?.message||error||"").toLowerCase();
    return !navigator.onLine||error?.name==="TypeError"||message.includes("failed to fetch")||message.includes("network")||message.includes("load failed")||message.includes("offline");
  }
  function isConnectivityLimited() {
    return !navigator.onLine||state.connectionMode!=="online"||state.offlineAuthorized;
  }
  function offlineViewAllowed(view) {
    if(view==="dashboard")return true;
    if(role()==="class_teacher")return ["my_class","attendance","my_subjects","reports"].includes(view);
    if(role()==="subject_teacher")return ["my_subjects","reports"].includes(view);
    return false;
  }
  function noteNetworkSuccess() {
    const recovered=state.connectionMode!=="online"&&navigator.onLine;
    state.networkFailures=0;state.connectionMode=navigator.onLine?"online":"offline";
    if(recovered&&state.offlineAuthorized&&state.session&&!state.offlineRevalidationScheduled){
      state.offlineRevalidationScheduled=true;
      setTimeout(async()=>{try{await startAuthenticated()}finally{state.offlineRevalidationScheduled=false}},0);
    }else if(recovered&&state.initialized){
      setTimeout(()=>{renderNav();void refreshPendingCount();void flushOutbox();void reconnectRealtime()},0);
    }
  }
  function noteNetworkFailure(error) {
    if(!isNetworkFailure(error))return;
    state.networkFailures=Number(state.networkFailures||0)+1;
    state.connectionMode=navigator.onLine?"unstable":"offline";
  }

  const ROLE_LABELS = {
    platform_super_admin: "Platform Super Administrator",
    system_admin: "System Administrator",
    principal: "Principal (Headmaster/Headmistress)",
    class_teacher: "Class Teacher",
    subject_teacher: "Subject Teacher",
    parent_guardian: "Parent or Guardian",
    accountant: "Accounts Office Staff"
  };

  const REPORT_TEMPLATE_GROUPS = Object.freeze([
    {key:"early_years",label:"Creche to Kindergarten (KG 1 and KG 2)",shortLabel:"Creche to KG 2"},
    {key:"basic_1_6",label:"Basic 1 to Basic 6",shortLabel:"Basic 1-6"},
    {key:"basic_7_9",label:"Basic 7 to Basic 9",shortLabel:"Basic 7-9"}
  ]);
  const REPORT_TEMPLATE_MAX_BYTES = 20*1024*1024;
  const CERTIFICATE_TEMPLATE_MAX_BYTES = 20*1024*1024;
  const REPORT_TEMPLATE_MIME_TYPES = Object.freeze({
    "application/pdf":"pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document":"docx"
  });

  const NAV = [
    {id:"dashboard",label:"Dashboard",icon:"▦",subtitle:"Academic performance overview"},
    {id:"operations",label:"Operations",icon:"◫",subtitle:"Deadlines, health, corrections, and recovery readiness",roles:["system_admin","principal"],feature:"governance"},
    {id:"licensing",label:"Platform Licensing",icon:"◇",subtitle:"Licence plans, lifecycle, compliance, and access controls",roles:["platform_super_admin"]},
    {id:"teacher_profile",label:"My Profile",icon:"♙",subtitle:"Teacher profile, photograph, qualifications, and assignments",roles:["class_teacher","subject_teacher"]},
    {id:"my_class",label:"My Class",icon:"▣",subtitle:"Assigned class, learners, and report progress",roles:["class_teacher"]},
    {id:"attendance",label:"Attendance",icon:"✓",subtitle:"Daily class attendance and automatic term totals",roles:["class_teacher"],feature:"attendance"},
    {id:"my_subjects",label:"My Subjects",icon:"⌘",subtitle:"Assigned subjects, classes, and assessment progress",roles:["class_teacher","subject_teacher"]},
    {id:"students",label:"Students",icon:"◉",subtitle:"Student records and enrolment",roles:["system_admin","class_teacher","subject_teacher"]},
    {id:"history",label:"Academic History",icon:"▧",subtitle:"Cumulative transcripts, lifecycle, transfers, and verification",roles:["system_admin","principal","class_teacher","subject_teacher"],feature:"academic_history"},
    {id:"teachers",label:"Teachers",icon:"♜",subtitle:"Teacher records and assignments",permission:"manage_teachers"},
    {id:"headteachers",label:"Principals",icon:"★",subtitle:"Principal records and appointments",permission:"manage_headteachers"},
    {id:"academics",label:"Academics",icon:"⌘",subtitle:"Academic structure and assessment",permission:"manage_academics"},
    {id:"timetable",label:"Timetable",icon:"▦",subtitle:"Class timetable, subjects, teachers, and teaching periods",roles:["system_admin","principal","class_teacher","subject_teacher"],feature:"timetable"},
    {id:"prospectus",label:"School Prospectus",icon:"▤",subtitle:"Academic-year fees, requirements, transportation, policies, revisions, and PDF output",roles:["system_admin"],feature:"school_prospectus"},
    {id:"delegations",label:"Emergency Delegation",icon:"⚑",subtitle:"Temporary academic access, continuity, and Principal oversight",roles:["system_admin","principal"]},
    {id:"reports",label:"Report Cards",icon:"▤",subtitle:"Assessment, approval, and publication",hideFor:["parent_guardian"],feature:"report_cards"},
    {id:"certificates",label:"Certificates",icon:"✦",subtitle:"Promotion, completion, and teacher recognition awards",roles:["system_admin","principal"],feature:"certificates"},
    {id:"id_cards",label:"ID Card Management",icon:"▥",subtitle:"Professional student and staff ID cards, QR verification, printing, and lifecycle",roles:["system_admin"],feature:"id_cards"},
    {id:"insights",label:"Insights",icon:"◩",subtitle:"Performance, attendance, completion, and class trends",roles:["system_admin","principal","class_teacher","subject_teacher"],feature:"analytics"},
    {id:"children",label:"My Children",icon:"♥",subtitle:"Published academic records",roles:["parent_guardian"]},
    {id:"users",label:"Users and Access",icon:"♟",subtitle:"Roles, classes, and security",permission:"manage_users"},
    {id:"notifications",label:"Notifications",icon:"◆",subtitle:"School and workflow alerts",feature:"notifications"},
    {id:"compliance",label:"Privacy and Security",icon:"◈",subtitle:"Retention, privacy requests, security events, and verification",roles:["system_admin","principal"],feature:"governance"},
    {id:"audit",label:"Audit Trail",icon:"◎",subtitle:"Record changes and accountability",permission:"view_audit",feature:"governance"},
    {id:"backup_restore",label:"Backup & Restore",icon:"↻",subtitle:"Downloadable full-school continuity and disaster recovery",roles:["system_admin"]},
    {id:"plan_upgrade",label:"Upgrade Plan",icon:"◇",subtitle:"Verify and activate a platform-authorized plan upgrade",roles:["system_admin"]},
    {id:"license_capacity",label:"Licence and Capacity",icon:"◫",subtitle:"Read-only licence status, limits, usage, and verification",roles:["system_admin"]},
    {id:"settings",label:"Settings",icon:"⚙",subtitle:"School identity, security, and resilience",roles:["system_admin"]},
    {id:"github",label:"GitHub Navigator",icon:"⌁",subtitle:"Protected package generation and deployment controls",roles:["platform_super_admin"]}
  ];

  const ROLE_NAV_IDS = Object.freeze({
    platform_super_admin:["licensing","github"],
    system_admin:["dashboard","operations","students","history","teachers","headteachers","academics","timetable","prospectus","delegations","reports","certificates","id_cards","insights","users","notifications","compliance","audit","backup_restore","plan_upgrade","license_capacity","settings"],
    principal:["dashboard","operations","history","timetable","delegations","reports","certificates","insights","notifications","compliance"],
    class_teacher:["dashboard","teacher_profile","my_class","attendance","my_subjects","students","history","timetable","reports","insights","notifications"],
    subject_teacher:["dashboard","teacher_profile","my_subjects","students","history","timetable","reports","insights","notifications"],
    parent_guardian:["dashboard","children","notifications"]
  });

  const state = {
    client:null, session:null, boot:null, view:"dashboard", viewToken:0,
    channels:[], photoUrls:new Map(), pdfUrls:new Map(), signatureUrls:new Map(), templateUrls:new Map(), storageUrlCaches:new Map(), templateCanvases:new Map(), online:navigator.onLine,
    studentPage:1, teacherPage:1, headteacherPage:1, reportPage:1, currentStudent:null, reportEditor:null,
    academicTab:"periods", notifications:[], mfaFactorId:null, mfaEnrollment:null,
    teacherAdmin:null, headteacherAdmin:null, userAdmin:null, userAccessRows:[], assignmentClassSelections:new Set(), assignmentSubjectSelections:new Set(),
    userAccessClassSelections:new Set(), userAccessSubjectSelections:new Set(), userAccessAllSubjects:false, guardianAccounts:[], autoComments:null,
    passwordChangeRequired:false, userAccessEditingUserId:"",
    workspace:null, studentClassFilter:"", reportClassFilter:"", reportTemplates:null, reportTemplatesLoadedAt:0,
    initialized:false, realtimeConnected:0, lastSync:null, pending:0, conflicts:0,
    connectionMode:navigator.onLine?"online":"offline", networkFailures:0, offlineAuthorized:false, offlineSnapshotUsedAt:0, offlineRevalidationScheduled:false,
    packageLogoPreviewUrl:"", packageGeneratorBusy:false, packageGenerationKey:"", platformPackageOffset:0, platformPackageLimit:50, platformPackageSearch:"", bulkReportPackageBusy:false,
    licenseRefreshTimer:null, licenseRefreshBusy:false, lastLicenseVerifiedAt:0,
    attendanceTermId:"", attendanceClassId:"", attendanceDate:"", attendanceData:null,
    licenseConsole:null, schoolLicenseCapacity:null, platformPackageConsole:null, delegationConsole:null, myEmergencyDelegations:[],
    operationsConsole:null, historyStudentId:"", historyData:null, historyStudents:null, complianceConsole:null, analyticsData:null,
    certificateConsole:null, certificateConsoleYear:"", certificateConsoleType:"", certificateBatch:null, certificateBusy:false,
    certificateSettingsTemplates:[], certificateTemplateCanvases:new Map(),
    idCardConsole:null, idCardYear:"", idCardClass:"", idCardStatus:"", idCardBusy:false, idCardMode:"student",
    staffIdCardConsole:null, staffIdCardType:"", staffIdCardStatus:"", staffIdCardBusy:false, schoolLogoPreviewUrl:"",
    timetableYear:"", timetableClass:"", timetableConsole:null, teacherProfile:null, prospectusYear:"", prospectusConsole:null
  };

  const EXTERNAL_NAV_VIEW_PREFIX="extension:";
  const externalNavRegistry=new Map();
  let externalNavReplay=false;
  let externalNavScanScheduled=false;
  let externalNavObserver=null;

  const $ = (selector, root=document) => root.querySelector(selector);
  const $$ = (selector, root=document) => [...root.querySelectorAll(selector)];
  const byId = id => document.getElementById(id);
  const esc = value => String(value ?? "").replace(/[&<>"']/g, ch => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"
  })[ch]);
  const attr = esc;
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const uuid = () => crypto.randomUUID();

  function externalNavIdentity(button) {
    if(!button)return "";
    if(button.dataset.edusentiaExternalView)return button.dataset.edusentiaExternalView;
    const datasetIdentity=[
      button.dataset.studentModule&&`student:${button.dataset.studentModule}`,
      button.dataset.studentServices&&`student-services:${button.dataset.studentServices}`,
      button.dataset.inventoryAssets&&`inventory-assets:${button.dataset.inventoryAssets}`
    ].filter(Boolean).join("|");
    const classIdentity=[...button.classList]
      .filter(name=>!["nav-item","active","hidden"].includes(name))
      .sort().join(".");
    const label=String(button.querySelector(".nav-label")?.textContent||button.textContent||"external").trim().replace(/\s+/g," ").slice(0,120);
    const identity=button.id?`id:${button.id}`:datasetIdentity||`class:${classIdentity}|label:${label}`;
    return `${EXTERNAL_NAV_VIEW_PREFIX}${stableInstallationHash(identity)}`;
  }
  function externalNavForCurrentSession(view) {
    const item=externalNavRegistry.get(String(view||""));
    const userId=state.session?.user?.id||"";
    return item&&item.userId===userId?item:null;
  }
  function syncExternalNavState(view=state.view) {
    const nav=byId("mainNav");if(!nav)return;
    nav.querySelectorAll(".nav-item").forEach(button=>{
      const active=String(button.dataset.edusentiaExternalView||"")===String(view||"");
      if(button.dataset.edusentiaExternalView){
        button.classList.toggle("active",active);
        button.setAttribute("aria-current",active?"page":"false");
      }
    });
  }
  function registerExternalNavButton(button) {
    if(!button||button.dataset.view||!button.matches?.(".nav-item"))return null;
    const view=externalNavIdentity(button);if(!view)return null;
    button.dataset.edusentiaExternalView=view;
    const userId=state.session?.user?.id||"";
    externalNavRegistry.set(view,{view,button,userId,label:String(button.querySelector(".nav-label")?.textContent||button.textContent||"Workspace").trim()});
    const limited=isConnectivityLimited();
    if(limited&&button.dataset.edusentiaOfflineHidden!=="1"){
      button.dataset.edusentiaOfflineHidden="1";
      button.dataset.edusentiaPreviousHidden=button.hidden?"1":"0";
      button.dataset.edusentiaPreviousDisabled=button.disabled?"1":"0";
      button.dataset.edusentiaPreviousAriaHidden=button.getAttribute("aria-hidden")??"";
      button.hidden=true;button.disabled=true;button.setAttribute("aria-hidden","true");
    }else if(!limited&&button.dataset.edusentiaOfflineHidden==="1"){
      button.hidden=button.dataset.edusentiaPreviousHidden==="1";
      button.disabled=button.dataset.edusentiaPreviousDisabled==="1";
      const previousAria=button.dataset.edusentiaPreviousAriaHidden;
      if(previousAria==="")button.removeAttribute("aria-hidden");else button.setAttribute("aria-hidden",previousAria);
      delete button.dataset.edusentiaOfflineHidden;delete button.dataset.edusentiaPreviousHidden;delete button.dataset.edusentiaPreviousDisabled;delete button.dataset.edusentiaPreviousAriaHidden;
    }
    if(state.view===view&&!limited)syncExternalNavState(view);
    return externalNavRegistry.get(view);
  }
  function scanExternalNavigation() {
    externalNavScanScheduled=false;
    const nav=byId("mainNav");if(!nav)return;
    nav.querySelectorAll(".nav-item:not([data-view])").forEach(registerExternalNavButton);
    syncExternalNavState();
  }
  function scheduleExternalNavScan() {
    if(externalNavScanScheduled)return;
    externalNavScanScheduled=true;
    requestAnimationFrame(scanExternalNavigation);
  }
  function installExternalNavigationController() {
    const nav=byId("mainNav");if(!nav||nav.dataset.edusentiaExternalNavController==="1")return;
    nav.dataset.edusentiaExternalNavController="1";
    nav.addEventListener("click",event=>{
      if(externalNavReplay)return;
      const button=event.target.closest?.(".nav-item:not([data-view])");
      if(!button||!nav.contains(button))return;
      const item=registerExternalNavButton(button);if(!item)return;
      if(isConnectivityLimited()){
        event.preventDefault();event.stopImmediatePropagation();
        toast("Online connection required","This workspace is protected as an online-only navigation section. Reconnect and try again.","warning",6500);
        void navigate("dashboard",true);
        return;
      }
      state.view=item.view;state.viewToken++;
      byId("sidebar")?.classList.remove("open");
      nav.querySelectorAll(".nav-item").forEach(node=>node.classList.remove("active"));
      button.classList.add("active");button.setAttribute("aria-current","page");
      requestAnimationFrame(()=>{if(state.view===item.view){syncExternalNavState(item.view);byId("content")?.focus();}});
    },true);
    externalNavObserver=new MutationObserver(scheduleExternalNavScan);
    externalNavObserver.observe(nav,{childList:true,subtree:true});
    scheduleExternalNavScan();
  }
  const isoDate = value => value ? new Date(value).toLocaleDateString("en-GH",{year:"numeric",month:"short",day:"numeric"}) : "—";
  const isoDateTime = value => value ? new Date(value).toLocaleString("en-GH",{year:"numeric",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"}) : "—";
  const number = (value,digits=0) => Number(value || 0).toLocaleString("en-GH",{minimumFractionDigits:digits,maximumFractionDigits:digits});
  const fullName = row => [row?.first_name,row?.middle_name,row?.last_name].filter(Boolean).join(" ");
  const activeYear = () => state.boot?.academic_years?.find(x=>x.is_active) || null;
  const activeTerm = () => state.boot?.terms?.find(x=>x.is_active) || null;
  const role = () => state.boot?.profile?.role || "";
  const can = key => Boolean(state.boot?.permissions?.[key]);
  const licenseState = () => state.boot?.license || {};
  const licenseCanWrite = () => licenseState().write_allowed !== false;
  const LEGACY_LICENSE_FEATURE_FALLBACKS=Object.freeze({
    id_cards:"core_records",
    timetable:"core_records",
    school_prospectus:"core_records"
  });
  const LICENSE_CAPACITY_INHERITED_FEATURES=Object.freeze(["id_cards","staff_id_cards","timetable","school_prospectus"]);
  function licenseFeatureEnabled(code) {
    if(role()==="platform_super_admin")return true;
    const flags=licenseState()?.plan?.feature_flags||{};
    if(Object.prototype.hasOwnProperty.call(flags,code))return flags[code]===true;
    // Explicit signed feature flags always win. Older signed school entitlements that
    // predate a later module inherit only the documented compatible parent feature.
    if(code==="staff_id_cards")return Object.prototype.hasOwnProperty.call(flags,"id_cards")?flags.id_cards===true:flags.core_records===true;
    const parent=LEGACY_LICENSE_FEATURE_FALLBACKS[code];
    return parent?flags[parent]===true:false;
  }
  function effectiveLicenseFeatureFlags(rawFlags={}) {
    const features={...(rawFlags&&typeof rawFlags==="object"?rawFlags:{})};
    for(const code of LICENSE_CAPACITY_INHERITED_FEATURES){
      if(!Object.prototype.hasOwnProperty.call(features,code))features[code]=licenseFeatureEnabled(code);
    }
    return features;
  }
  function dateTimeLocalValue(value) {
    if(!value)return "";
    const date=new Date(value);if(Number.isNaN(date.getTime()))return "";
    const offset=date.getTimezoneOffset()*60000;
    return new Date(date.getTime()-offset).toISOString().slice(0,16);
  }
  function licenseStatusLabel(value="") {
    return ({pending_activation:"Pending activation",active:"Active",grace_period:"Grace period",expired:"Expired",suspended:"Suspended",revoked:"Revoked",perpetual:"Perpetual"})[value]||String(value||"Unknown").replaceAll("_"," ");
  }
  function licenseBannerHtml() {
    if(role()==="platform_super_admin")return "";
    const license=licenseState(),warning=String(license.warning||"").trim();
    if(!warning&&license.access_mode!=="read_only")return "";
    const readOnly=license.access_mode==="read_only";
    return `<section class="license-banner ${readOnly?"restricted":"warning"}"><div><strong>${readOnly?"Read-only licensing mode":licenseStatusLabel(license.computed_status)}</strong><span>${esc(warning||"The platform licence requires attention.")}</span></div>${license.expires_at?`<small>Expiry: ${esc(isoDateTime(license.expires_at))}</small>`:""}</section>`;
  }
  function decodePublicJwtPayload(token) {
    try{
      const encoded=String(token||"").split(".")[1]||"";
      const normalised=encoded.replaceAll("-","+").replaceAll("_","/");
      return JSON.parse(atob(normalised.padEnd(Math.ceil(normalised.length/4)*4,"=")));
    }catch(_){return {}}
  }
  function isPublicSupabaseKey(value) {
    const key=String(value||"").trim();
    if(!key||key.startsWith("YOUR_")||key.startsWith("sb_secret_"))return false;
    if(/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(key))return true;
    if(key.split(".").length===3)return decodePublicJwtPayload(key).role==="anon";
    return false;
  }
  const isConfigured = () => /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(CONFIG.supabaseUrl) && isPublicSupabaseKey(CONFIG.supabaseAnonKey);
  const legacyDefaultSchoolName = value => /^(?:nipe international school|your school|licensed school)$/i.test(String(value||"").trim());
  const legacyDefaultLogo = value => !value || /(?:^|\/)(?:nipe-school-logo|rce-master-logo(?:-[0-9]+)?|school-logo)\.png(?:$|\?)/i.test(String(value));
  function productDisplayName(){return String(CONFIG.productName||"Report Card Enterprise").trim()||"Report Card Enterprise"}
  function productDisplayLogo(){return String(CONFIG.productLogoPath||"assets/rce-master-logo.png").trim()||"assets/rce-master-logo.png"}
  function schoolDisplayName(school=state.boot?.school||{}) {
    const databaseName=String(school?.school_name||"").trim();
    if(CONFIG.generatedSchoolPackage&&legacyDefaultSchoolName(databaseName))return String(CONFIG.schoolName||"Your School").trim()||"Your School";
    return databaseName||String(CONFIG.schoolName||"Your School").trim()||"Your School";
  }
  function schoolLogoStoragePath(value) {
    const raw=String(value||"").trim(),prefix=`${CONFIG.brandingBucket}:`;
    if(raw.startsWith(prefix))return raw.slice(prefix.length).replace(/^\/+/,"");
    const marker=`/storage/v1/object/public/${CONFIG.brandingBucket}/`,index=raw.indexOf(marker);
    if(index>=0){try{return decodeURIComponent(raw.slice(index+marker.length).split("?")[0])}catch(_){return raw.slice(index+marker.length).split("?")[0]}}
    return "";
  }
  function schoolLogoPublicUrl(path) {
    const clean=String(path||"").replace(/^\/+/,"");if(!clean||!state.client)return "";
    try{return state.client.storage.from(CONFIG.brandingBucket).getPublicUrl(clean).data?.publicUrl||""}catch(_){return ""}
  }
  function resolveSchoolLogoReference(value) {
    const raw=String(value||"").trim(),stored=schoolLogoStoragePath(raw);
    if(stored)return schoolLogoPublicUrl(stored)||raw;
    return raw;
  }
  function schoolDisplayLogo(school=state.boot?.school||{}) {
    const databaseLogo=String(school?.logo_url||"").trim();
    if(CONFIG.generatedSchoolPackage&&legacyDefaultLogo(databaseLogo))return CONFIG.logoPath;
    return resolveSchoolLogoReference(databaseLogo)||CONFIG.logoPath||"assets/school-logo.png";
  }
  function shellDisplayName(school=state.boot?.school||{}){return CONFIG.masterEdition?productDisplayName():schoolDisplayName(school)}
  function shellDisplayLogo(school=state.boot?.school||{}){return CONFIG.masterEdition?productDisplayLogo():schoolDisplayLogo(school)}
  function shellDisplaySubtitle(){return CONFIG.masterEdition?"Platform Administration":"Report Card System"}
  function tenantLoginDomain() {
    const token=String(CONFIG.tenantCode||"").replace(/[^a-zA-Z0-9]/g,"").toLowerCase();
    return token?`${token}.app`:"";
  }
  function schoolEmailDomain(school=state.boot?.school||{}) {
    const tenantDomain=tenantLoginDomain();
    if(tenantDomain)return tenantDomain;
    const databaseDomain=String(school?.user_email_domain||"").trim().toLowerCase();
    if(CONFIG.generatedSchoolPackage&&(!databaseDomain||["nip.com","school.invalid"].includes(databaseDomain)))return String(CONFIG.userEmailDomain||"edusentia.app").trim().toLowerCase();
    return databaseDomain||String(CONFIG.userEmailDomain||"edusentia.app").trim().toLowerCase();
  }
  function schoolReportPrefix(school=state.boot?.school||{}) {
    const databasePrefix=String(school?.report_number_prefix||"").trim().toUpperCase();
    if(CONFIG.generatedSchoolPackage&&(!databasePrefix||["NIS","SCH","RCE"].includes(databasePrefix)))return String(CONFIG.reportNumberPrefix||"SCH").trim().toUpperCase();
    return databasePrefix||String(CONFIG.reportNumberPrefix||"SCH").trim().toUpperCase();
  }
  function slugify(value,fallback="school") {
    return String(value||"").normalize("NFKD").replace(/[\u0300-\u036f]/g,"").toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"").slice(0,70)||fallback;
  }
  function renderStaticBrand() {
    const name=shellDisplayName(),logo=shellDisplayLogo();
    document.title=CONFIG.masterEdition?productDisplayName():`${name} | Report Cards`;
    $$('[data-school-logo]').forEach(image=>{image.src=logo;image.alt=name});
    $$('[data-school-name]').forEach(node=>{node.textContent=name});
    $$('[data-brand-subtitle]').forEach(node=>{node.textContent=CONFIG.masterEdition?CONFIG.productTagline:"Student Report Card System"});
    $$('[data-shell-subtitle]').forEach(node=>{node.textContent=shellDisplaySubtitle()});
  }

  function toast(title, message="", type="success", timeout=4200) {
    const node=document.createElement("div");
    node.className=`toast ${type}`;
    node.innerHTML=`<div><strong>${esc(title)}</strong>${message?`<span>${esc(message)}</span>`:""}</div>`;
    byId("toastStack").append(node);
    setTimeout(()=>node.remove(),timeout);
  }

  function setLoading(show) { byId("loader").classList.toggle("hidden",!show); }
  const formMessageTimers=new Map();
  function setFormMessage(id,message="",timeout=8000) {
    const node=byId(id);
    if(!node) return;
    const pending=formMessageTimers.get(id);
    if(pending) clearTimeout(pending);
    const value=String(message||"").trim();
    node.textContent=value;
    node.classList.toggle("hidden",!value);
    if(value&&timeout>0) formMessageTimers.set(id,setTimeout(()=>setFormMessage(id,"",0),timeout));
    else formMessageTimers.delete(id);
  }
  function setAuthMessage(message="",timeout=8000) { setFormMessage("authMessage",message,timeout); }
  function setMfaMessage(message="",timeout=8000) { setFormMessage("mfaMessage",message,timeout); }
  function setSync(mode,label) {
    const pill=byId("syncIndicator");
    pill.className=`sync-pill ${mode}`;
    if(mode==="online") state.lastSync=new Date();
    const stamp=state.lastSync?.toLocaleTimeString("en-GH",{hour:"2-digit",minute:"2-digit"})||"";
    const display=mode==="online"&&stamp?`${label} • ${stamp}`:label;
    byId("syncLabel").textContent=display;
    pill.title=mode==="online"&&state.lastSync?`Last synchronised ${state.lastSync.toLocaleString("en-GH")}`:label;
  }
  function showOnly(id) {
    ["verifyView","authView","mfaView","appShell"].forEach(name=>byId(name).classList.toggle("hidden",name!==id));
  }
  function statusBadge(status) {
    const value=String(status||"draft");
    return `<span class="status ${attr(value)}">${esc(value.replaceAll("_"," "))}</span>`;
  }
  function optionList(rows,valueKey,labelKey,selected="",blank="Select") {
    return `<option value="">${esc(blank)}</option>`+rows.map(row=>
      `<option value="${attr(row[valueKey])}" ${String(row[valueKey])===String(selected)?"selected":""}>${esc(row[labelKey])}</option>`
    ).join("");
  }
  function modal(title,subtitle,body,footer="",size="") {
    const dialog=byId("modal"),bodyHost=byId("modalBody"),footerHost=byId("modalFooter");
    dialog.className=`modal ${size}`.trim();
    byId("modalTitle").textContent=title;
    byId("modalSubtitle").textContent=subtitle||"";
    bodyHost.innerHTML=body;
    footerHost.innerHTML=footer;
    if(/<form\b/i.test(body)&&!bodyHost.querySelector("form")){
      const error=new Error("The record form could not be created.");
      toast("Form unavailable","Reload the application and try again.","error",6500);
      throw error;
    }
    if(!dialog.open) dialog.showModal();
    return dialog;
  }
  function closeModal(force=false){
    const forced=force===true;
    if(state.passwordChangeRequired&&!forced)return;
    const dialog=byId("modal");
    if(dialog.open) dialog.close();
    byId("modalBody").replaceChildren();
    byId("modalFooter").replaceChildren();
    byId("modalClose").classList.remove("hidden");
  }
  function confirmAction(title,message,confirmLabel="Continue",danger=false) {
    return new Promise(resolve=>{
      modal(title,"",`<p>${esc(message)}</p>`,
        `<button class="button ghost" type="button" id="confirmCancel">Cancel</button>
         <button class="button ${danger?"danger":"primary"}" type="button" id="confirmOk">${esc(confirmLabel)}</button>`,"small");
      byId("confirmCancel").onclick=()=>{closeModal();resolve(false)};
      byId("confirmOk").onclick=()=>{closeModal();resolve(true)};
    });
  }

  // r25 empty-master UUID null guard contract:
  // Optional UUID RPC parameters must use SQL NULL when the UI has no selected record.
  // An empty string is not a UUID and PostgREST correctly rejects it before the RPC runs.
  function nullableId(value) {
    const text=String(value??"").trim();
    return text||null;
  }

  async function rpc(name,args={}) {
    const {data,error}=await state.client.rpc(name,args);
    if(error) {
      noteNetworkFailure(error);
      if(state.session&&(error.code==="42501"||/access denied|not authorised|not authorized|permission denied/i.test(error.message||""))&&name!=="record_security_event") {
        void (async()=>{
          try{
            await state.client.rpc("record_security_event",{
              event_type_text:"authorization_denied",severity_text:"warning",message_text:`Denied RPC operation: ${name}`,
              details_data:{rpc:name,code:error.code||"",message:String(error.message||"").slice(0,500),view:state.view},source_text:"web_client"
            });
          }catch(_){}
        })();
      }
      throw error;
    }
    noteNetworkSuccess();
    state.lastSync=new Date();
    return data;
  }
  async function query(builder) {
    const {data,error}=await builder;
    if(error){noteNetworkFailure(error);throw error;}
    noteNetworkSuccess();state.lastSync=new Date();
    return data;
  }
  async function edgeFunctionErrorMessage(error,data=null) {
    const direct=data&&typeof data==="object"?(data.error||data.message||data.msg):"";
    if(direct)return String(direct);
    const context=error?.context;
    if(context){
      try{
        const response=typeof context.clone==="function"?context.clone():context;
        const payload=await response.json();
        const message=payload?.error||payload?.message||payload?.msg;
        if(message)return String(message);
      }catch(_){
        try{
          const response=typeof context.clone==="function"?context.clone():context;
          const body=await response.text();
          if(body){
            try{const payload=JSON.parse(body);if(payload?.error||payload?.message)return String(payload.error||payload.message)}catch(__){}
            return body.slice(0,1000);
          }
        }catch(__){}
      }
    }
    return String(error?.message||"Edge Function request failed");
  }
  async function invokeEdgeFunction(name,body={}) {
    const {data,error}=await state.client.functions.invoke(name,{body});
    if(error){
      const wrapped=new Error(await edgeFunctionErrorMessage(error,data));
      wrapped.name=String(error.name||"EdgeFunctionError");
      wrapped.code=error.code||"";
      wrapped.cause=error;
      throw wrapped;
    }
    state.lastSync=new Date();
    return data;
  }
  async function rpcAllRows(name,args={},maxPages=500) {
    const rows=[];let page=1,last={};
    while(page<=maxPages){
      const data=await rpc(name,{...args,page_number:page,page_size:100})||{};
      const batch=Array.isArray(data.rows)?data.rows:[];rows.push(...batch);last=data;
      const totalRaw=data.total,total=totalRaw===null||totalRaw===undefined||totalRaw===""?Number.NaN:Number(totalRaw);
      if(!batch.length||Number.isFinite(total)&&rows.length>=total||batch.length<100)return {...last,rows,total:Number.isFinite(total)?total:rows.length};
      page+=1;
    }
    throw new Error(`The ${name} result exceeded the safe pagination limit. Narrow the search and try again.`);
  }
  async function reportClientError(error,context={}) {
    console.error(error);
    if(!state.client || !state.session) return;
    try {
      await state.client.rpc("log_client_error",{
        message_text:error?.message||String(error),stack_text:error?.stack||"",
        context_data:context,user_agent_text:navigator.userAgent
      });
    } catch (_) {}
  }
  async function removePrivateStorageObjects(bucket,paths,context={},warn=false) {
    const list=[...new Set((Array.isArray(paths)?paths:[paths]).filter(Boolean).map(String))];
    if(!list.length)return {removed:true,error:null};
    const {error}=await state.client.storage.from(bucket).remove(list);
    if(error){
      await reportClientError(error,{source:"private_storage_cleanup",bucket,paths:list,...context});
      if(warn)toast("Private Storage cleanup required","The record change succeeded, but one or more superseded private files could not be removed. Review the client-error log and the affected Storage bucket.","warning",9000);
      return {removed:false,error};
    }
    const cache=storageUrlCache(bucket);list.forEach(path=>cache.delete(path));
    return {removed:true,error:null};
  }
  function friendlyError(error) {
    const msg=error?.message||String(error||"Operation failed");
    if(msg.includes("40001")||msg.includes("changed by another user")) return "Another user changed this record. The latest version has been loaded.";
    if(msg.includes("PLATFORM_ACCESS_LOCKED:")) return msg.split("PLATFORM_ACCESS_LOCKED:").slice(1).join(":").trim()||"Platform access has been restricted.";
    if(msg.includes("LICENSE_WRITE_RESTRICTED:")) return msg.split("LICENSE_WRITE_RESTRICTED:").slice(1).join(":").trim()||"The current licence permits read-only access.";
    if(msg.includes("LICENSE_CAPACITY_REACHED:")) return msg.split("LICENSE_CAPACITY_REACHED:").slice(1).join(":").trim();
    if(msg.includes("LICENSE_FEATURE_NOT_INCLUDED:")) return msg.split("LICENSE_FEATURE_NOT_INCLUDED:").slice(1).join(":").trim()||"This feature is not included in the current licence plan.";
    if(msg.includes("LICENSE_DOWNGRADE_BLOCKED:")) return msg.split("LICENSE_DOWNGRADE_BLOCKED:").slice(1).join(":").trim()||"Current usage exceeds the selected plan capacity.";
    if(/object exceeded.*maximum allowed size|maximum allowed size|payload too large|entity too large/i.test(msg)) return "The protected package Storage capacity was too small. The updated package manager repairs it automatically; refresh GitHub Navigator and retry the upload.";
    if(msg.toLowerCase().includes("central licence authority")) return "The central licence authority could not confirm this generated package. Check connectivity, deployment binding, and package revocation status.";
    if(msg.toLowerCase().includes("licence package has been revoked")||msg.toLowerCase().includes("licence has been revoked by the platform authority")) return "This generated school package has been revoked by the platform authority.";
    if(msg.toLowerCase().includes("platform super administrator access required")) return "Only a Platform Super Administrator can manage licensing and access controls.";
    if(msg.toLowerCase().includes("permission denied for function can_publish_report")) return "Complete the current consolidated master schema sequence, then reload the system.";
    if(/authentication required|auth session missing/i.test(msg)) return "The secure setup session is no longer valid. Generate a new Admin setup link, complete MFA, and retry.";
    if(msg.includes("42501")||msg.toLowerCase().includes("access denied")||msg.toLowerCase().includes("permission denied")) return "The signed-in account is not authorised for this protected operation.";
    if(msg.includes("student_reports_enrollment_id_key")||msg.includes("student_reports_enrollment_id_term_id_key")) return "The database still has a legacy report uniqueness rule. Apply the v6.6.1 database hotfix, then save the report again.";
    if(msg.includes("list_report_card_templates")||msg.includes("report_card_templates")||msg.includes("report-card-templates")) return "Apply the v6.6.3 database hotfix, then reload the system.";
    if(error?.code==="23505"&&msg.toLowerCase().includes("student_reports")) return "A current report already exists for this student and term.";
    if(msg.toLowerCase().includes("multi-factor authentication required")) return "Multi-factor authentication is required for this protected operation. Sign out, sign in again, and complete the authenticator-code step, or enable an authenticator in Settings.";
    if(msg.includes("RCE_BACKUP_ENCRYPTION_KEY is required")||msg.includes("NIS_BACKUP_ENCRYPTION_KEY")) return "The backup encryption secret is missing from the scheduled-backup Edge Function. Configure RCE_BACKUP_ENCRYPTION_KEY and redeploy the function.";
    if(msg.includes("Package signing bootstrap SQL is not installed")) return "Install the package-signing Vault bootstrap SQL once, redeploy platform-package-manager, then refresh GitHub Navigator. The signing key will be generated and encrypted automatically.";
    if(/stored package signing public key does not match|package signing metadata repair/i.test(msg)) return "The private package-signing key remains protected. Deploy the current signing-continuity SQL and package manager, then refresh so its public metadata can be reconciled in place.";
    if(/package signing vault|stored package signing key|package signing key fingerprint/i.test(msg)) return "The protected package-signing key could not be read or verified. Apply the current signing recovery patch and review the platform-package-manager logs before generating packages.";
    if(/not having enough compute resources|compute resources|status code 546|\b546\b/i.test(msg)) return "The protected package operation exceeded the server compute budget. Report Card Enterprise r28 uses a compute-safe STORE-only generated-package path and activation reconciliation. Refresh GitHub Navigator and retry once; if it persists, review the platform-package-manager logs.";
    if(msg.toLowerCase().includes("service configuration unavailable")) return "The scheduled-backup Edge Function is missing its Supabase service configuration. Redeploy it and confirm SUPABASE_URL and the service-role secret are available.";
    if(msg.toLowerCase().includes("bucket not found")) return "A required private Storage bucket is unavailable. Apply the current setup, confirm the system-backups bucket exists, and redeploy scheduled-backup.";
    if(error?.code==="weak_password"||/password.*weak|password.*strength|should contain|minimum.*password/i.test(msg)) return "The password does not meet the tenant security policy. Use at least eight characters and include a mix of letters, numbers, and symbols.";
    if(error?.code==="same_password"||/same password|different from the old password/i.test(msg)) return "Choose a password different from the temporary/current password.";
    if(error?.code==="reauthentication_needed"||/reauthentication needed|reauthenticate/i.test(msg)) return "Your security session must be verified again before changing the password. Sign out, reopen a fresh Admin setup link, complete MFA, and retry.";
    if(/auth session missing|session.*missing|refresh token.*invalid|invalid refresh token/i.test(msg)) return "The secure setup session changed while updating the password. Reopen a fresh Admin setup link and retry.";
    if(msg.toLowerCase().includes("failed to fetch")||msg.toLowerCase().includes("network")) return "The server could not be reached.";
    return msg;
  }
  async function run(action,{success="",context={}}={}) {
    try {
      const result=await action();
      if(success) toast(success);
      return result;
    } catch(error) {
      await reportClientError(error,context);
      toast("Operation unsuccessful",friendlyError(error),"error",6500);
      throw error;
    }
  }

  function openLocalDb() {
    return new Promise((resolve,reject)=>{
      const request=indexedDB.open(LOCAL_DATABASE_NAME,3);
      request.onupgradeneeded=()=>{
        const db=request.result;
        if(!db.objectStoreNames.contains("outbox")) db.createObjectStore("outbox",{keyPath:"id"});
        if(!db.objectStoreNames.contains("drafts")) db.createObjectStore("drafts",{keyPath:"key"});
        if(!db.objectStoreNames.contains("snapshots")) db.createObjectStore("snapshots",{keyPath:"key"});
      };
      request.onsuccess=()=>resolve(request.result);
      request.onerror=()=>reject(request.error);
    });
  }
  async function idbTransaction(store,mode,operation) {
    const db=await openLocalDb();
    return new Promise((resolve,reject)=>{
      const tx=db.transaction(store,mode), os=tx.objectStore(store);
      let request;
      try { request=operation(os); } catch(error){ reject(error);return; }
      tx.oncomplete=()=>resolve(request?.result);
      tx.onerror=()=>reject(tx.error);
    });
  }
  const outboxAll=async()=>{
    const items=await idbTransaction("outbox","readonly",os=>os.getAll());
    return (items||[]).filter(item=>!item?.installationScope||item.installationScope===INSTALLATION_SCOPE_KEY);
  };
  const outboxPut=item=>idbTransaction("outbox","readwrite",os=>os.put({...item,installationScope:INSTALLATION_SCOPE_KEY}));
  const outboxDelete=id=>idbTransaction("outbox","readwrite",os=>os.delete(id));
  const draftPut=item=>idbTransaction("drafts","readwrite",os=>os.put({...item,installationScope:INSTALLATION_SCOPE_KEY}));
  const draftGet=async key=>{
    const item=await idbTransaction("drafts","readonly",os=>os.get(key));
    return item&&(!item.installationScope||item.installationScope===INSTALLATION_SCOPE_KEY)?item:undefined;
  };
  const draftDelete=key=>idbTransaction("drafts","readwrite",os=>os.delete(key));
  const snapshotPut=item=>idbTransaction("snapshots","readwrite",os=>os.put({...item,installationScope:INSTALLATION_SCOPE_KEY}));
  const snapshotGet=async key=>{
    const item=await idbTransaction("snapshots","readonly",os=>os.get(key));
    return item&&(!item.installationScope||item.installationScope===INSTALLATION_SCOPE_KEY)?item:undefined;
  };
  const snapshotDelete=key=>idbTransaction("snapshots","readwrite",os=>os.delete(key));
  function scopedSnapshotKey(kind,suffix="") {
    const userId=state.session?.user?.id||state.boot?.profile?.id||"anonymous";
    return `${kind}:${userId}:${stableScopeHash(String(suffix||"default"))}`;
  }
  async function snapshotDataPut(kind,suffix,data) {
    if(!state.session?.user?.id)return;
    const savedAt=new Date().toISOString();
    await snapshotPut({key:scopedSnapshotKey(kind,suffix),kind,userId:state.session.user.id,savedAt,data});
  }
  async function snapshotDataGet(kind,suffix,maxAgeMs=OFFLINE_DATA_MAX_AGE_MS) {
    const item=await snapshotGet(scopedSnapshotKey(kind,suffix));
    if(!item||item.userId!==state.session?.user?.id)return null;
    const age=Date.now()-Date.parse(item.savedAt||0);
    if(!Number.isFinite(age)||age<0||age>maxAgeMs)return null;
    return item.data??null;
  }
  async function cacheableRpc(kind,name,args={},suffix="default",maxAgeMs=OFFLINE_DATA_MAX_AGE_MS) {
    try{
      const data=await rpc(name,args);
      await snapshotDataPut(kind,suffix,data).catch(()=>{});
      return data;
    }catch(error){
      if(!isNetworkFailure(error))throw error;
      const cached=await snapshotDataGet(kind,suffix,maxAgeMs).catch(()=>null);
      if(cached!==null){state.connectionMode=navigator.onLine?"unstable":"offline";return cached;}
      throw error;
    }
  }
  async function requestOutboxSync() {
    if(!("serviceWorker" in navigator))return;
    try{const registration=await navigator.serviceWorker.ready;if(registration?.sync?.register)await registration.sync.register("rce-outbox");}catch(_){}
  }
  async function cacheOfflineAuthorization() {
    if(!state.session?.user?.id||!state.boot?.profile?.active||state.boot?.profile?.must_change_password||!OFFLINE_COLD_START_ROLES.has(role())||isConnectivityLimited())return;
    const savedAt=new Date().toISOString();
    await snapshotPut({
      key:`offline-auth:${state.session.user.id}`,kind:"offline-auth",userId:state.session.user.id,savedAt,expiresAt:new Date(Date.now()+OFFLINE_AUTH_MAX_AGE_MS).toISOString(),
      data:{boot:state.boot}
    }).catch(()=>{});
  }
  async function loadOfflineAuthorization() {
    const userId=state.session?.user?.id;if(!userId)return null;
    const item=await snapshotGet(`offline-auth:${userId}`).catch(()=>null);
    if(!item||item.userId!==userId||Date.parse(item.expiresAt||0)<=Date.now())return null;
    const boot=item.data?.boot;
    if(!boot?.profile?.active||boot.profile.must_change_password||!OFFLINE_COLD_START_ROLES.has(String(boot.profile.role||"")))return null;
    return item;
  }
  async function tryStartOfflineSession(error) {
    if(!isNetworkFailure(error)||!state.session)return false;
    const item=await loadOfflineAuthorization();if(!item)return false;
    state.boot=item.data.boot;state.offlineAuthorized=true;state.offlineSnapshotUsedAt=Date.now();state.connectionMode=navigator.onLine?"unstable":"offline";
    await continueAuthenticatedSession();
    toast("Offline continuity active","Using this device's last authorised teacher workspace. Eligible changes will synchronise when connectivity returns.","warning",9000);
    return true;
  }

  async function legacyOfflineDataCount() {
    if(typeof indexedDB?.databases!=="function") return 0;
    const databases=await indexedDB.databases().catch(()=>[]);
    if(!(databases||[]).some(item=>item?.name==="nis-report-card")) return 0;
    const legacyDb=await new Promise((resolve,reject)=>{
      const request=indexedDB.open("nis-report-card");
      request.onsuccess=()=>resolve(request.result);
      request.onerror=()=>reject(request.error);
    });
    try {
      const stores=["outbox","drafts"].filter(name=>legacyDb.objectStoreNames.contains(name));
      if(!stores.length) return 0;
      return await new Promise((resolve,reject)=>{
        const transaction=legacyDb.transaction(stores,"readonly");
        let total=0;
        for(const name of stores){
          const request=transaction.objectStore(name).count();
          request.onsuccess=()=>{total+=Number(request.result||0)};
        }
        transaction.oncomplete=()=>resolve(total);
        transaction.onerror=()=>reject(transaction.error);
      });
    } finally { legacyDb.close(); }
  }
  async function warnLegacyOfflineData() {
    const warningKey=`rce-legacy-offline-warning-${INSTALLATION_SCOPE_KEY}`;
    if(sessionStorage.getItem(warningKey)==="shown") return;
    const count=await legacyOfflineDataCount().catch(()=>0);
    if(!count) return;
    sessionStorage.setItem(warningKey,"shown");
    toast("Legacy offline records detected",`${count} record${count===1?"":"s"} remain in the former shared browser database. Do not clear browser data until those records have been reviewed and synchronised from the previous deployment.`,"warning",12000);
  }

  async function refreshPendingCount() {
    const items=await outboxAll().catch(()=>[]);
    state.pending=items.filter(x=>x.status!=="conflict").length;
    state.conflicts=items.filter(x=>x.status==="conflict").length;
    const bar=byId("offlineBar");
    byId("outboxCount").textContent=[state.pending?`${state.pending} pending`:"",state.conflicts?`${state.conflicts} conflict${state.conflicts===1?"":"s"}`:""].filter(Boolean).join(" • ")||"0 pending";
    bar.classList.toggle("conflict",state.conflicts>0);
    bar.classList.toggle("hidden",state.connectionMode==="online" && state.pending===0 && state.conflicts===0);
    if(state.connectionMode==="offline") setSync("offline","Offline");
    else if(state.connectionMode==="unstable") setSync("pending","Unstable");
    else if(state.conflicts) setSync("error",`${state.conflicts} conflict${state.conflicts===1?"":"s"}`);
    else if(state.pending) setSync("pending",`${state.pending} pending`);
  }
  async function queueReportSave(payload,expectedVersion) {
    const item={id:uuid(),type:"save_report",payload,expectedVersion,createdAt:new Date().toISOString(),status:"pending"};
    await outboxPut(item);await requestOutboxSync();
    await refreshPendingCount();
    toast("Saved offline","The report will synchronise automatically.","warning");
    return state.reportEditor;
  }
  function attendanceSnapshotSuffix(termId=state.attendanceTermId,classId=state.attendanceClassId,date=state.attendanceDate){return `${termId}|${classId}|${date}`}
  async function queueAttendanceSave(payload) {
    const suffix=attendanceSnapshotSuffix(payload.target_term_id,payload.target_class_id,payload.target_date);
    const current=state.attendanceData||{};
    const item={
      id:`attendance:${stableScopeHash(suffix)}`,type:"save_attendance",payload,createdAt:new Date().toISOString(),status:"pending",
      baseRegisterId:current.register?.id||null,baseUpdatedAt:current.register?.updated_at||null,cacheSuffix:suffix
    };
    const byEnrollment=new Map((payload.entries||[]).map(entry=>[entry.enrollment_id,entry.attendance_status]));
    const pendingData={...current,register:{...(current.register||{}),notes:payload.notes_text||"",offline_pending:true},students:(current.students||[]).map(row=>({...row,attendance_status:byEnrollment.get(row.enrollment_id)||row.attendance_status}))};
    state.attendanceData=pendingData;
    await snapshotDataPut("attendance-register",suffix,pendingData).catch(()=>{});
    await outboxPut(item);await requestOutboxSync();await refreshPendingCount();
    toast("Attendance saved offline","The marked register is stored on this device and will synchronise automatically.","warning",8000);
    return pendingData;
  }
  async function flushOutbox() {
    if(isConnectivityLimited()||!state.session) return;
    const items=(await outboxAll().catch(()=>[])).sort((a,b)=>a.createdAt.localeCompare(b.createdAt));
    for(const item of items) {
      if(item.status==="conflict") continue;
      try {
        if(item.type==="save_report") await rpc("save_report_card",{payload:item.payload,expected_version:item.expectedVersion});
        else if(item.type==="save_attendance"){
          const p=item.payload||{};
          const current=await rpc("get_class_attendance_register",{target_term_id:p.target_term_id,target_class_id:p.target_class_id,target_date:p.target_date});
          const currentId=current?.register?.id||null,currentUpdated=current?.register?.updated_at||null;
          const conflict=item.baseRegisterId?(currentId!==item.baseRegisterId||(item.baseUpdatedAt&&currentUpdated&&currentUpdated!==item.baseUpdatedAt)):Boolean(currentId);
          if(conflict){const err=new Error("Attendance changed by another user while this device was offline");err.code="40001";throw err;}
          const saved=await rpc("save_class_attendance",p);
          await snapshotDataPut("attendance-register",item.cacheSuffix||attendanceSnapshotSuffix(p.target_term_id,p.target_class_id,p.target_date),saved).catch(()=>{});
        }
        await outboxDelete(item.id);
      } catch(error) {
        if(error?.code==="40001"||String(error?.message).includes("changed by another user")) {
          item.status="conflict"; item.error=error.message; await outboxPut(item);
          toast("Synchronisation conflict",item.type==="save_attendance"?"Queued attendance changed on the server and needs review.":"A queued report needs review.","error",7000);
        } else {noteNetworkFailure(error);break;}
      }
    }
    await refreshPendingCount();
    if(state.connectionMode==="online" && state.pending===0) setSync("online","Synced");
  }

  async function openSyncQueue() {
    const items=(await outboxAll().catch(()=>[])).sort((a,b)=>b.createdAt.localeCompare(a.createdAt));
    modal("Synchronisation Queue",`${items.length} record${items.length===1?"":"s"}`,items.length?`
      <div class="stack-list">${items.map(item=>`<article class="list-card">
        <div><strong>${item.status==="conflict"?"Conflict":item.type==="save_attendance"?"Pending attendance":"Pending report"}</strong><small>${isoDateTime(item.createdAt)}</small>${item.error?`<span class="form-message">${esc(item.error)}</span>`:""}</div>
        <div class="button-row">
          ${item.status==="conflict"?`<button class="button primary small" type="button" data-sync-retry="${attr(item.id)}">Retry</button><button class="button outline small" type="button" data-sync-server="${attr(item.id)}">Use server record</button>`:""}
          <button class="button ghost small" type="button" data-sync-remove="${attr(item.id)}">Remove</button>
        </div>
      </article>`).join("")}</div>`:`<div class="empty"><strong>Queue clear</strong></div>`,
      `<button class="button ghost" id="syncQueueClose" type="button">Close</button>`,"wide");
    byId("syncQueueClose").onclick=closeModal;
    $$('[data-sync-remove]').forEach(button=>button.onclick=async()=>{await outboxDelete(button.dataset.syncRemove);await refreshPendingCount();openSyncQueue()});
    $$('[data-sync-server]').forEach(button=>button.onclick=async()=>{
      const item=items.find(x=>x.id===button.dataset.syncServer);await outboxDelete(item.id);await refreshPendingCount();
      if(item?.type==="save_report"&&item.payload?.report_id){state.reportEditor=await rpc("get_report_editor",{target_report_id:item.payload.report_id,target_enrollment_id:null,target_term_id:null});}
      closeModal();
      if(item?.type==="save_attendance"&&state.view==="attendance")await loadAttendanceRegister().catch(()=>{});
      else if(state.view==="reports"&&state.reportEditor)renderReportEditor();
    });
    $$('[data-sync-retry]').forEach(button=>button.onclick=async()=>{
      const item=items.find(x=>x.id===button.dataset.syncRetry);if(!item)return;
      if(item.type==="save_report"&&item.payload?.report_id){const current=await rpc("get_report_editor",{target_report_id:item.payload.report_id,target_enrollment_id:null,target_term_id:null});item.expectedVersion=Number(current.report.version);}
      if(item.type==="save_attendance"){const p=item.payload||{},current=await rpc("get_class_attendance_register",{target_term_id:p.target_term_id,target_class_id:p.target_class_id,target_date:p.target_date});item.baseRegisterId=current?.register?.id||null;item.baseUpdatedAt=current?.register?.updated_at||null;}
      item.status="pending";item.error="";await outboxPut(item);closeModal();await refreshPendingCount();await flushOutbox();
    });
  }

  function storageUrlCache(bucket) {
    if(bucket===CONFIG.photoBucket)return state.photoUrls;
    if(bucket===CONFIG.signatureBucket)return state.signatureUrls;
    if(bucket===CONFIG.templateBucket)return state.templateUrls;
    if(bucket===CONFIG.pdfBucket)return state.pdfUrls;
    if(!state.storageUrlCaches.has(bucket))state.storageUrlCaches.set(bucket,new Map());
    return state.storageUrlCaches.get(bucket);
  }
  function clearPrivateStorageCaches() {
    if(state.schoolLogoPreviewUrl){URL.revokeObjectURL(state.schoolLogoPreviewUrl);state.schoolLogoPreviewUrl=""}
    state.photoUrls.clear();state.pdfUrls.clear();state.signatureUrls.clear();state.templateUrls.clear();
    for(const cache of state.storageUrlCaches.values())cache.clear();
    state.storageUrlCaches.clear();
    state.templateCanvases.clear();state.certificateTemplateCanvases.clear();
  }
  async function signedUrl(bucket,path,seconds=900) {
    if(!path) return "";
    if(/^https?:\/\//i.test(path)||path.startsWith("data:")||path.startsWith("assets/")) return path;
    const cache=storageUrlCache(bucket);
    const cacheKey=String(path);
    const cached=cache.get(cacheKey);
    if(cached&&cached.expires>Date.now()) return cached.url;
    const {data,error}=await state.client.storage.from(bucket).createSignedUrl(path,seconds);
    if(error) throw error;
    cache.set(cacheKey,{url:data.signedUrl,expires:Date.now()+Math.max(5,seconds-30)*1000});
    return data.signedUrl;
  }

  async function init() {
    renderStaticBrand();
    setAuthMessage("",0);
    setMfaMessage("",0);
    ["loginEmail","loginPassword"].forEach(id=>byId(id)?.addEventListener("input",()=>setAuthMessage("",0)));
    byId("mfaCode")?.addEventListener("input",()=>setMfaMessage("",0));
    byId("togglePassword").onclick=()=>{
      const input=byId("loginPassword");
      input.type=input.type==="password"?"text":"password";
    };
    byId("modalClose").onclick=()=>closeModal();
    byId("modal").addEventListener("cancel",event=>{event.preventDefault();closeModal()});
    byId("loginForm").addEventListener("submit",login);
    byId("mfaForm").addEventListener("submit",verifyMfa);
    byId("mfaSignOut").onclick=logout;
    byId("logoutButton").onclick=logout;
    byId("menuButton").onclick=()=>byId("sidebar").classList.toggle("open");
    byId("refreshButton").onclick=()=>navigate(state.view,true);
    byId("notificationButton").onclick=()=>navigate("notifications");
    byId("offlineBar").onclick=openSyncQueue;
    byId("offlineBar").onkeydown=event=>{if(event.key==="Enter"||event.key===" "){event.preventDefault();openSyncQueue()}};
    window.addEventListener("online",async()=>{
      state.online=true;state.connectionMode="online";state.networkFailures=0;
      if(state.offlineAuthorized&&state.session){await startAuthenticated();return;}
      renderNav();await refreshPendingCount();await flushOutbox();await reconnectRealtime();
    });
    window.addEventListener("offline",async()=>{state.online=false;state.connectionMode="offline";renderNav();await refreshPendingCount()});
    window.addEventListener("beforeunload",event=>{if(state.pending||state.conflicts){event.preventDefault();event.returnValue=""}});
    window.addEventListener("error",event=>reportClientError(event.error||new Error(event.message),{source:"window"}));
    window.addEventListener("unhandledrejection",event=>reportClientError(event.reason,{source:"promise"}));
    if(!window.RCE_ANDROID_APP&&"serviceWorker" in navigator) {
      navigator.serviceWorker.register("service-worker.js?edusentia=r42-offline-continuity-v1").catch(()=>{});
      navigator.serviceWorker.addEventListener("message",event=>{if(event.data?.type==="FLUSH_OUTBOX")flushOutbox()});
    }
    await refreshPendingCount();
    await warnLegacyOfflineData();

    const params=new URLSearchParams(location.search);
    const verifyToken=params.get("verify");
    const transcriptToken=params.get("transcript");
    const certificateToken=params.get("certificate");
    const idCardToken=params.get("idcard");
    const staffCardToken=params.get("staffcard");
    if(verifyToken||transcriptToken||certificateToken||idCardToken||staffCardToken) {
      const publicToken=verifyToken||transcriptToken||certificateToken||idCardToken||staffCardToken;
      const publicType=staffCardToken?"staffcard":idCardToken?"idcard":certificateToken?"certificate":transcriptToken?"transcript":"report";
      await showVerification(publicToken,publicType);
      setLoading(false);
      return;
    }
    if(!isConfigured()||!window.supabase?.createClient) {
      showOnly("authView");
      setAuthMessage("Service unavailable.");
      setLoading(false);
      return;
    }
    state.client=window.supabase.createClient(CONFIG.supabaseUrl,CONFIG.supabaseAnonKey,{
      auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true},
      realtime:{params:{eventsPerSecond:20}}
    });
    const {data:{session}}=await state.client.auth.getSession();
    state.session=session;
    state.client.auth.onAuthStateChange(async(event,newSession)=>{
      state.session=newSession;
      if(event==="SIGNED_OUT"){stopGeneratedLicenseRefresh();state.initialized=false;disconnectRealtime();setAuthMessage("",0);showOnly("authView");}
      if(event==="TOKEN_REFRESHED"&&newSession){
        await state.client.realtime.setAuth(newSession.access_token).catch(()=>{});
        if(CONFIG.generatedSchoolPackage&&state.initialized)setTimeout(()=>refreshGeneratedLicenseBinding(true),0);
      }
    });
    if(session) await startAuthenticated();
    else {showOnly("authView");setLoading(false);}
  }

  async function login(event) {
    event.preventDefault(); setAuthMessage("");
    const email=byId("loginEmail").value.trim(),password=byId("loginPassword").value;
    const button=$("#loginForm button[type=submit]");button.disabled=true;
    try {
      const {data,error}=await state.client.auth.signInWithPassword({email,password});
      if(error) throw error;
      state.session=data.session;
      await startAuthenticated();
    } catch(error){setAuthMessage(friendlyError(error));}
    finally{button.disabled=false;}
  }
  async function logout() {
    const offlineUserId=state.session?.user?.id;
    stopGeneratedLicenseRefresh();
    disconnectRealtime();
    await state.client?.auth.signOut({scope:"local"});
    state.boot=null;state.session=null;state.initialized=false;state.reportTemplates=null;state.reportTemplatesLoadedAt=0;state.licenseConsole=null;state.schoolLicenseCapacity=null;state.platformPackageConsole=null;state.platformPackageOffset=0;state.platformPackageSearch="";state.packageGenerationKey="";state.licenseRefreshBusy=false;state.lastLicenseVerifiedAt=0;state.delegationConsole=null;state.myEmergencyDelegations=[];state.operationsConsole=null;state.historyStudentId="";state.historyData=null;state.historyStudents=null;state.complianceConsole=null;state.analyticsData=null;state.certificateConsole=null;state.certificateBatch=null;state.certificateSettingsTemplates=[];state.certificateTemplateCanvases.clear();state.idCardConsole=null;state.idCardYear="";state.idCardClass="";state.idCardStatus="";state.idCardBusy=false;
    clearPrivateStorageCaches();
    externalNavRegistry.clear();externalNavObserver?.disconnect();externalNavObserver=null;
    if(offlineUserId)await snapshotDelete(`offline-auth:${offlineUserId}`).catch(()=>{});
    showOnly("authView");setLoading(false);
    setTimeout(()=>location.reload(),0);
  }

  async function refreshGeneratedLicenseBinding(silent=false) {
    if(!CONFIG.generatedSchoolPackage||!state.session||state.licenseRefreshBusy)return true;
    state.licenseRefreshBusy=true;
    try{
      const {data:verification,error:verificationError}=await state.client.functions.invoke("license-verifier",{body:{action:"verify"}});
      if(verificationError||verification?.ok!==true)throw new Error(verification?.error||verificationError?.message||"Generated package licence verification failed");
      const {data:binding,error:bindingError}=await state.client.functions.invoke("license-verifier",{body:{action:"bind"}});
      if(bindingError||binding?.ok!==true||binding?.binding_verified!==true)throw new Error(binding?.error||bindingError?.message||"Generated package installation binding failed");
      state.lastLicenseVerifiedAt=Date.now();return true;
    }catch(error){
      if(!silent)throw error;
      await reportClientError(error,{source:"generated_license_refresh"});
      toast("Licence verification required",friendlyError(error),"error",8500);
      return false;
    }finally{state.licenseRefreshBusy=false}
  }
  function stopGeneratedLicenseRefresh(){if(state.licenseRefreshTimer){clearInterval(state.licenseRefreshTimer);state.licenseRefreshTimer=null}}
  function startGeneratedLicenseRefresh(){
    stopGeneratedLicenseRefresh();
    if(!CONFIG.generatedSchoolPackage)return;
    state.licenseRefreshTimer=setInterval(()=>refreshGeneratedLicenseBinding(true),4*60*60*1000);
  }

  async function startAuthenticated() {
    setLoading(true);
    try {
      if(CONFIG.generatedSchoolPackage){
        const {data:verification,error:verificationError}=await state.client.functions.invoke("license-verifier",{body:{action:"verify"}});
        if(verificationError||verification?.ok!==true)throw new Error(verification?.error||verificationError?.message||"Generated package licence verification failed");
      }
      await rpc("ensure_current_user_profile");
      if(CONFIG.generatedSchoolPackage){
        const {data:binding,error:bindingError}=await state.client.functions.invoke("license-verifier",{body:{action:"bind"}});
        if(bindingError||binding?.ok!==true||binding?.binding_verified!==true)throw new Error(binding?.error||bindingError?.message||"Generated package installation binding failed");
      }
      state.boot=await rpc("get_bootstrap_data");
      if(!state.boot?.profile?.active) throw new Error("Account inactive");
      const verified=await ensureMfa();
      if(!verified){setLoading(false);return;}
      state.lastLicenseVerifiedAt=CONFIG.generatedSchoolPackage?Date.now():0;
      state.offlineAuthorized=false;await cacheOfflineAuthorization();
      await continueAuthenticatedSession();
    } catch(error) {
      if(await tryStartOfflineSession(error))return;
      await reportClientError(error,{source:"bootstrap"});
      await state.client.auth.signOut({scope:"local"}).catch(()=>{});
      showOnly("authView");setAuthMessage(friendlyError(error));setLoading(false);
    }
  }
  async function ensureMfa() {
    if(!state.boot.profile.mfa_required) return true;
    const {data:aal,error}=await state.client.auth.mfa.getAuthenticatorAssuranceLevel();
    if(error) throw error;
    if(aal.currentLevel==="aal2") return true;
    const {data:factors,error:factorError}=await state.client.auth.mfa.listFactors();
    if(factorError) throw factorError;
    const verified=(factors.totp||[]).find(f=>f.status==="verified");
    if(verified) {
      state.mfaFactorId=verified.id;state.mfaEnrollment=null;
      byId("mfaQr").classList.add("hidden");showOnly("mfaView");byId("mfaCode").focus();return false;
    }
    const {data:enrollment,error:enrollError}=await state.client.auth.mfa.enroll({
      factorType:"totp",friendlyName:schoolDisplayName()
    });
    if(enrollError) throw enrollError;
    state.mfaFactorId=enrollment.id;state.mfaEnrollment=enrollment;
    const qr=byId("mfaQr");qr.innerHTML=`<img src="${attr(enrollment.totp.qr_code)}" alt="Authentication QR code">`;qr.classList.remove("hidden");
    showOnly("mfaView");byId("mfaCode").focus();return false;
  }
  async function verifyMfa(event) {
    event.preventDefault();setMfaMessage("");
    const code=byId("mfaCode").value.trim();
    const button=$("#mfaForm button[type=submit]");button.disabled=true;
    try {
      const {error}=await state.client.auth.mfa.challengeAndVerify({factorId:state.mfaFactorId,code});
      if(error) throw error;
      byId("mfaCode").value="";state.mfaEnrollment=null;
      state.boot=await rpc("get_bootstrap_data");
      state.offlineAuthorized=false;await cacheOfflineAuthorization();
      await continueAuthenticatedSession();
    } catch(error){setMfaMessage(friendlyError(error));}
    finally{button.disabled=false;}
  }


  async function continueAuthenticatedSession() {
    if(state.boot?.profile?.must_change_password){
      openRequiredPasswordChange();
      return;
    }
    await initializeApp();
  }

  function openRequiredPasswordChange() {
    state.passwordChangeRequired=true;
    renderBrand();
    showOnly("appShell");
    byId("mainNav").innerHTML="";
    byId("pageTitle").textContent="Password Change Required";
    byId("pageSubtitle").textContent="Set a private password before continuing";
    byId("content").innerHTML='<div class="empty"><strong>Your account is secured. Complete the required password change to continue.</strong></div>';
    setLoading(false);
    modal("Change Password Required","The System Administrator requires you to replace the temporary password.",`<form id="requiredPasswordForm" class="form-stack">
      <label class="field"><span>New password</span><div class="password-wrap"><input id="requiredPassword" name="password" type="password" minlength="8" autocomplete="new-password" required><button id="toggleRequiredPassword" class="icon-button" type="button" aria-label="Show new password"><span aria-hidden="true">◉</span></button></div></label>
      <label class="field"><span>Confirm new password</span><div class="password-wrap"><input id="requiredPasswordConfirm" name="confirm_password" type="password" minlength="8" autocomplete="new-password" required><button id="toggleRequiredPasswordConfirm" class="icon-button" type="button" aria-label="Show confirmed password"><span aria-hidden="true">◉</span></button></div></label>
      <p class="help-text">Use at least eight characters. Do not reuse the temporary password.</p>
      <p id="requiredPasswordMessage" class="form-message" role="alert"></p>
    </form>`,`<button class="button ghost" id="requiredPasswordSignOut" type="button">Sign out</button><button class="button primary" id="requiredPasswordSave" type="button">Change password</button>`,"small");
    byId("modalClose").classList.add("hidden");
    const bindPasswordVisibility=(buttonId,inputId,label)=>{
      const button=byId(buttonId),input=byId(inputId);
      if(!button||!input)return;
      button.onclick=()=>{
        const showing=input.type==="text";
        input.type=showing?"password":"text";
        button.setAttribute("aria-label",`${showing?"Show":"Hide"} ${label}`);
      };
    };
    bindPasswordVisibility("toggleRequiredPassword","requiredPassword","new password");
    bindPasswordVisibility("toggleRequiredPasswordConfirm","requiredPasswordConfirm","confirmed password");
    byId("requiredPasswordSignOut").onclick=async()=>{
      state.passwordChangeRequired=false;
      closeModal(true);
      await logout();
    };
    byId("requiredPasswordSave").onclick=async()=>{
      const form=byId("requiredPasswordForm"),button=byId("requiredPasswordSave"),message=byId("requiredPasswordMessage");
      if(message)message.textContent="";
      if(!form?.reportValidity())return;
      const password=form.elements.password.value;
      if(password!==form.elements.confirm_password.value){
        if(message)message.textContent="The two passwords do not match.";
        return;
      }
      if(password.length<8){
        if(message)message.textContent="Use at least eight characters.";
        return;
      }
      button.disabled=true;button.textContent="Changing";
      try{
        if(message)message.textContent="Verifying account security and updating password…";
        const {data,error}=await state.client.functions.invoke("admin-user-management",{
          body:{
            action:"complete_own_required_password_change",
            payload:{password}
          }
        });
        if(error){
          let detail="";
          try{
            const response=error?.context;
            if(response&&typeof response.clone==="function"){
              const parsed=await response.clone().json().catch(()=>null);
              detail=String(parsed?.message||parsed?.error||"");
            }
          }catch(_){}
          throw new Error(detail||error.message||"Password update failed");
        }
        if(!data?.ok||data?.password_changed!==true){
          throw new Error(String(data?.message||data?.error||"Password update failed"));
        }

        state.passwordChangeRequired=false;
        if(message)message.textContent="Password changed successfully. Returning to secure sign-in…";
        closeModal(true);
        toast("Password changed","Your private password is active. Sign in again with the new password.");
        try{await state.client.auth.signOut({scope:"local"})}catch(_){ }
        state.boot=null;state.session=null;state.initialized=false;
        clearPrivateStorageCaches();
        setTimeout(()=>{location.href=location.pathname},250);
      }catch(error){
        const text=friendlyError(error);
        if(message)message.textContent=text;
        toast("Password not changed",text,"error",8500);
      }finally{
        button.disabled=false;button.textContent="Change password";
      }
    };
  }

  async function initializeApp() {
    state.initialized=true;
    renderBrand();renderNav();showOnly("appShell");installExternalNavigationController();
    await refreshPendingCount();
    if(isConnectivityLimited()){
      await navigate("dashboard",true);
      setLoading(false);return;
    }
    await state.client.realtime.setAuth(state.session.access_token).catch(()=>{});
    await connectRealtime();
    await loadNotificationCount();
    await flushOutbox();
    await navigate("dashboard",true);
    startGeneratedLicenseRefresh();
    setLoading(false);
  }
  function renderBrand() {
    const school=state.boot.school||{},name=shellDisplayName(school),logo=shellDisplayLogo(school);
    byId("brandLogo").src=logo;
    byId("brandLogo").alt=name;
    byId("brandName").textContent=name;
    $$('[data-shell-subtitle]').forEach(node=>{node.textContent=shellDisplaySubtitle()});
    document.title=CONFIG.masterEdition?productDisplayName():`${name} | Report Cards`;
    byId("userName").textContent=state.boot.profile.full_name||state.session.user.email;
    byId("userRole").textContent=ROLE_LABELS[role()]||role();
    byId("userAvatar").textContent=(state.boot.profile.full_name||"N").trim().charAt(0).toUpperCase();
    document.documentElement.style.setProperty("--navy",school.primary_colour||"#082d70");
    document.documentElement.style.setProperty("--gold",school.accent_colour||"#f0b51d");
    document.body.dataset.accessMode=licenseState().access_mode||"full";
  }
  function availableNavItems() {
    const ordered=ROLE_NAV_IDS[role()]||["dashboard"];
    return ordered.map(id=>NAV.find(item=>item.id===id)).filter(item=>{
      if(!item)return false;
      if(CONFIG.generatedSchoolPackage&&["licensing","github"].includes(item.id))return false;
      if(item.permission&&!can(item.permission))return false;
      if(item.roles&&!item.roles.includes(role()))return false;
      if(item.hideFor?.includes(role()))return false;
      if(item.feature&&!licenseFeatureEnabled(item.feature))return false;
      if(isConnectivityLimited()&&!offlineViewAllowed(item.id))return false;
      return true;
    });
  }
  function renderNav() {
    byId("mainNav").innerHTML=availableNavItems().map(item=>{
      const active=item.id===state.view;
      return `<button type="button" class="nav-item ${active?"active":""}" data-view="${item.id}" aria-current="${active?"page":"false"}" aria-label="Open ${attr(item.label)}" title="${attr(item.subtitle||item.label)}">
        <span class="nav-icon" aria-hidden="true">${item.icon}</span><span class="nav-label">${esc(item.label)}</span><span class="nav-active-dot" aria-hidden="true"></span></button>`;
    }).join("");
    $$(".nav-item",byId("mainNav")).forEach(button=>button.onclick=()=>navigate(button.dataset.view));
    scheduleExternalNavScan();
  }
  async function navigate(view,force=false) {
    const external=externalNavForCurrentSession(view);
    if(external){
      if(isConnectivityLimited()){return navigate("dashboard",force);}
      state.view=external.view;state.viewToken++;
      byId("sidebar")?.classList.remove("open");
      const live=byId("mainNav")?.querySelector(`[data-edusentia-external-view="${CSS.escape(external.view)}"]`)||external.button;
      if(live){
        externalNavReplay=true;
        try{live.click();}finally{externalNavReplay=false;}
      }
      await new Promise(resolve=>requestAnimationFrame(resolve));
      if(state.view===external.view){syncExternalNavState(external.view);byId("content")?.focus();}
      return;
    }
    const allowed=availableNavItems();
    let item=allowed.find(x=>x.id===view);
    if(!item){item=allowed.find(x=>x.id==="dashboard")||allowed[0];if(!item)return;view=item.id;}
    state.view=view;state.viewToken++;
    renderNav();byId("pageTitle").textContent=item.label;byId("pageSubtitle").textContent=item.subtitle;
    byId("sidebar").classList.remove("open");byId("content").innerHTML=`<div class="panel pad"><div class="skeleton"></div></div>`;
    const token=state.viewToken;
    try {
      const renderer={
        dashboard:renderDashboard,operations:renderOperations,licensing:renderLicensing,teacher_profile:renderTeacherProfile,my_class:renderMyClass,attendance:renderAttendance,my_subjects:renderMySubjects,students:renderStudents,history:renderAcademicHistory,teachers:renderTeachers,headteachers:renderPrincipals,academics:renderAcademics,timetable:renderTimetable,prospectus:renderSchoolProspectus,delegations:renderEmergencyDelegations,reports:renderReports,certificates:renderCertificates,id_cards:renderIdCards,insights:renderInsights,
        children:renderChildren,users:renderUsers,notifications:renderNotifications,compliance:renderCompliance,audit:renderAudit,backup_restore:renderBackupRestore,plan_upgrade:renderPlanUpgrade,license_capacity:renderSchoolLicenseCapacity,settings:renderSettings,github:renderGithubNavigator
      }[view];
      await renderer?.(token,force);
      if(token===state.viewToken&&role()!=="platform_super_admin") {const banner=licenseBannerHtml();if(banner)byId("content")?.insertAdjacentHTML("afterbegin",banner);}
      if(token===state.viewToken) {
        const mode=state.connectionMode==="online"?"online":state.connectionMode==="unstable"?"pending":"offline";
        setSync(mode,state.connectionMode==="online"?"Synced":state.connectionMode==="unstable"?"Unstable":"Offline");byId("content").focus();
      }
    } catch(error) {
      if(token!==state.viewToken)return;
      await reportClientError(error,{view});
      byId("content").innerHTML=`<div class="panel pad empty"><strong>Unable to load</strong><span>${esc(friendlyError(error))}</span></div>`;
      setSync(state.online?"pending":"offline",state.online?"Retry required":"Offline");
    }
  }

  async function disconnectRealtime() {
    for(const channel of state.channels) await state.client?.removeChannel(channel).catch(()=>{});
    state.channels=[];state.realtimeConnected=0;
  }
  async function reconnectRealtime(){if(state.session){await disconnectRealtime();await connectRealtime()}}
  async function connectRealtime() {
    await disconnectRealtime();
    const topics=state.boot?.topics||[];
    if(!topics.length){setSync("online","Connected");return;}
    setSync("pending","Connecting");
    for(const topic of topics.slice(0,120)) {
      const channel=state.client.channel(topic,{config:{private:true,broadcast:{self:false},presence:{key:state.session.user.id}}});
      ["INSERT","UPDATE","DELETE"].forEach(event=>channel.on("broadcast",{event},payload=>handleRealtime(topic,payload)));
      channel.on("presence",{event:"sync"},()=>{});
      channel.subscribe(async status=>{
        if(status==="SUBSCRIBED"){
          state.realtimeConnected++;
          await channel.track({user_id:state.session.user.id,at:new Date().toISOString(),view:state.view}).catch(()=>{});
          if(state.realtimeConnected===state.channels.length)setSync("online","Live");
        } else if(["CHANNEL_ERROR","TIMED_OUT","CLOSED"].includes(status)) setSync("pending","Reconnecting");
      });
      state.channels.push(channel);
    }
  }
  function handleRealtime(topic,payload) {
    state.lastSync=new Date();setSync("online","Live");
    const table=payload?.payload?.table||payload?.table||"";
    if(["profiles","user_class_access","teachers","headteachers","classes","subjects","class_subjects","grading_scales","students","enrollments","student_reports","subject_results","class_attendance_registers","student_attendance_entries","emergency_academic_delegations","academic_period_controls","report_correction_requests","student_lifecycle_events","transcript_issuances","privacy_requests","security_events","recovery_test_runs","certificate_templates","teacher_award_categories","certificate_batches","certificates","certificate_events","id_card_settings","student_id_cards","id_card_events","staff_id_cards","staff_id_card_events","id_card_deletion_tombstones","class_timetable_entries","school_prospectuses","school_prospectus_sections","school_prospectus_items","school_prospectus_revisions"].includes(table))state.workspace=null;
    if(table==="students"||table==="enrollments")state.historyStudents=null;
    if(table==="certificate_templates"){state.certificateConsole=null;state.certificateSettingsTemplates=[];state.certificateTemplateCanvases.clear()}
    if(["id_card_settings","student_id_cards","id_card_events","id_card_deletion_tombstones"].includes(table))state.idCardConsole=null;
    if(["id_card_settings","staff_id_cards","staff_id_card_events","id_card_deletion_tombstones"].includes(table))state.staffIdCardConsole=null;
    if(table==="class_timetable_entries")state.timetableConsole=null;
    if(["school_prospectuses","school_prospectus_sections","school_prospectus_items","school_prospectus_revisions"].includes(table))state.prospectusConsole=null;
    if(table==="teachers")state.teacherProfile=null;
    if(table==="report_card_templates"){state.reportTemplates=null;state.reportTemplatesLoadedAt=0;state.templateUrls.clear();state.templateCanvases.clear()}
    if(topic.startsWith("user:")||table==="notifications") loadNotificationCount();
    clearTimeout(handleRealtime.timer);
    handleRealtime.timer=setTimeout(()=>{
      if(state.view==="dashboard") renderDashboard(state.viewToken,true);
      else if(state.view==="students"&&(table==="students"||table==="enrollments"||topic.startsWith("student:"))) renderStudents(state.viewToken,true);
      else if(state.view==="attendance"&&(table==="class_attendance_registers"||table==="student_attendance_entries"||table==="students"||table==="enrollments")) loadAttendanceRegister(state.viewToken);
      else if(state.view==="teachers"&&(table==="teachers"||table==="profiles"||table==="classes"||table==="class_subjects"||topic==="school:global")) renderTeachers(state.viewToken,true);
      else if(state.view==="teacher_profile"&&(table==="teachers"||table==="profiles"||table==="classes"||table==="class_subjects"||topic==="school:global")) renderTeacherProfile(state.viewToken,true);
      else if(state.view==="headteachers"&&(table==="headteachers"||table==="profiles"||topic==="school:global")) renderPrincipals(state.viewToken,true);
      else if(state.view==="users"&&(table==="profiles"||table==="user_class_access"||table==="teachers"||table==="headteachers"||topic==="school:global")) renderUsers(state.viewToken,true);
      else if(state.view==="reports"||state.view==="children") {
        if(state.reportEditor&&topic===`report:${state.reportEditor.report?.id}`) refreshOpenReport();
        else navigate(state.view,true);
      } else if(state.view==="academics"&&topic==="school:global") renderAcademics(state.viewToken,true);
      else if(state.view==="delegations") renderEmergencyDelegations(state.viewToken,true);
      else if(state.view==="operations") renderOperations(state.viewToken,true);
      else if(state.view==="certificates") renderCertificates(state.viewToken,true);
      else if(state.view==="id_cards") renderIdCards(state.viewToken,true);
      else if(state.view==="timetable") renderTimetable(state.viewToken,true);
      else if(state.view==="prospectus") renderSchoolProspectus(state.viewToken,true);
      else if(state.view==="history") renderAcademicHistory(state.viewToken,true);
      else if(state.view==="insights") renderInsights(state.viewToken,true);
      else if(state.view==="compliance") renderCompliance(state.viewToken,true);
      else if(state.view==="my_class") renderMyClass(state.viewToken,true);
      else if(state.view==="my_subjects") renderMySubjects(state.viewToken,true);
      else if(state.view==="notifications") renderNotifications(state.viewToken,true);
      else if(state.view==="settings"&&table==="report_card_templates") renderSettings(state.viewToken,true);
    },220);
  }

  async function loadNotificationCount() {
    if(!state.session)return;
    try {
      const data=await rpc("list_notifications",{page_number:1,page_size:5});
      state.notifications=data.rows||[];
      const badge=byId("notificationBadge"),count=Number(data.unread||0);
      badge.textContent=count>99?"99+":String(count);badge.classList.toggle("hidden",count===0);
    } catch(_){}
  }

  init().catch(error=>{console.error(error);showOnly("authView");setAuthMessage("Service unavailable.");setLoading(false)});
  if(window.__RCE_TEMPLATE_TEST_MODE__||window.__NIS_TEMPLATE_TEST_MODE__){
    window.RCE_TEMPLATE_TEST_HOOKS=Object.freeze({
      reportTemplateRangeForClass,validateReportTemplateFile,normaliseTemplateCanvas,drawAssignedTemplateOverlay,drawPreferredTerminalReport,builtInReportTemplateCanvas,
      resolveReportTemplateMimeType,renderPdfTemplateBlob,subjectScoreBreakdown,closeModal,
      ordinalReportPosition,reportBodyFontName,reportBodyFontSize,reportBodyFontScale,reportSubjectPositionMap,
      defaultGradingInterpretation,normaliseGradingGuide,defaultReportGradingGuide,drawDynamicGradingScale,reportGradingGuide,
      setBoot:value=>{state.boot=value},getState:()=>state
    });
    window.NIS_TEMPLATE_TEST_HOOKS=window.RCE_TEMPLATE_TEST_HOOKS;
  }


  async function renderDashboard(token) {
    const term=activeTerm();
    let metrics;
    try{metrics=await cacheableRpc("dashboard","get_role_dashboard",{target_term_id:term?.id||null},term?.id||"none");}
    catch(error){if(!isNetworkFailure(error))throw error;metrics={};}
    if(token!==state.viewToken)return;
    const currentRole=role(),statuses=metrics.by_status||{},reports=Number(metrics.reports||0),published=Number(metrics.published||0);
    const signatureRecord=currentRole==="principal"&&!isConnectivityLimited()?await rpc("get_my_headteacher_signature").catch(error=>({linked:false,error:friendlyError(error)})):null;
    if(token!==state.viewToken)return;
    const completion=reports?Math.round(published/reports*100):0;
    const configs={
      system_admin:{title:"System Administration Dashboard",subtitle:"Users, records, security, and report operations",cards:[["blue","♟","Active Users",metrics.active_users],["gold","♜","Active Teachers",metrics.active_teachers],["green","◉","Active Students",metrics.active_students],["purple","▤","Report Cards",reports]]},
      principal:{title:"Principal Dashboard",subtitle:"School performance, approvals, and publication",cards:[["blue","◉","Active Students",metrics.active_students],["gold","⌛","Awaiting Action",metrics.pending_review],["green","✓","Published Reports",published],["purple","%","Published Average",number(metrics.average,1)+"%"]]},
      class_teacher:{title:"Class and Subject Teacher Dashboard",subtitle:"Home-class responsibilities and subject teaching assignments",cards:[["blue","▣","Assigned Classes",metrics.assigned_classes],["gold","⌘","Assigned Subjects",metrics.assigned_subjects],["green","◉","Visible Students",metrics.active_students],["purple","✎","Draft or Returned",metrics.draft_returned]]},
      subject_teacher:{title:"Subject Teacher Dashboard",subtitle:"Assigned subjects and assessment workload",cards:[["blue","⌘","Assigned Subjects",metrics.assigned_subjects],["gold","▣","Assigned Classes",metrics.assigned_classes],["green","✎","Open Reports",metrics.draft_returned],["purple","%","Published Average",number(metrics.average,1)+"%"]]},
      parent_guardian:{title:"Parent and Guardian Dashboard",subtitle:"Linked children and published academic records",cards:[["blue","♥","My Children",metrics.children],["gold","✓","Published Reports",published],["green","◆","Unread Notifications",metrics.unread_notifications],["purple","%","Average",number(metrics.average,1)+"%"]]}
    };
    const cfg=configs[currentRole]||configs.parent_guardian;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>${esc(cfg.title)}</h3><p>${esc(cfg.subtitle)}</p></div><div class="page-actions">${dashboardQuickActions(currentRole)}</div></div>
      <div class="stat-grid">${cfg.cards.map(card=>statCard(...card)).join("")}</div>
      ${currentRole==="principal"?headteacherSignaturePanel(signatureRecord):""}
      <div class="grid two">
        <section class="panel"><div class="panel-header"><div><h3>Current Academic Period</h3><p>${esc(activeYear()?.name||"No active academic year")} • ${esc(term?.name||"No active term")}</p></div></div>
          <div class="panel-body"><div class="metric-row"><div class="metric"><span>Draft</span><strong>${number(statuses.draft)}</strong></div><div class="metric"><span>Submitted</span><strong>${number(statuses.submitted)}</strong></div><div class="metric"><span>Approved</span><strong>${number(statuses.approved)}</strong></div><div class="metric"><span>Completion</span><strong>${completion}%</strong></div></div><div class="progress"><span style="width:${completion}%"></span></div></div>
        </section>
        <section class="panel"><div class="panel-header"><div><h3>Class Performance</h3><p>Published report averages</p></div></div><div class="panel-body"><div class="bar-list">
          ${(metrics.class_performance||[]).length?(metrics.class_performance||[]).map(row=>`<div class="bar-item"><label>${esc(row.class_name)}</label><div class="bar-track"><span style="width:${Math.min(100,Number(row.average||0))}%"></span></div><b>${number(row.average,1)}</b></div>`).join(""):`<div class="empty"><strong>No published results</strong></div>`}
        </div></div></section>
      </div>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Recent Report Cards</h3><p>Latest authorised activity</p></div>${currentRole!=="parent_guardian"?`<button class="button secondary small" data-open-reports>View reports</button>`:`<button class="button secondary small" data-open-children>View children</button>`}</div>${reportTable(metrics.recent||[],true)}</section>`;
    $(`[data-open-reports]`)?.addEventListener("click",()=>navigate("reports"));
    $(`[data-open-children]`)?.addEventListener("click",()=>navigate("children"));
    $$(`[data-dashboard-view]`).forEach(button=>button.onclick=()=>navigate(button.dataset.dashboardView));
    if(currentRole==="principal")await bindPrincipalSignaturePanel(signatureRecord);
  }
  function headteacherSignaturePanel(record) {
    if(!record?.linked)return `<section class="panel signature-panel"><div class="panel-header"><div><h3>Digital Signature</h3><p>Principal report signing</p></div></div><div class="panel-body"><div class="empty"><strong>No linked principal record</strong><span>${esc(record?.error||"Ask the System Administrator to link this account to a principal record in Users and Access.")}</span></div></div></section>`;
    return `<section class="panel signature-panel"><div class="panel-header"><div><h3>Digital Signature</h3><p>The current signature replaces any signature embedded in report templates</p></div><span class="status ${record.signature_path?"published":"draft"}">${record.signature_path?"Signature ready":"Not uploaded"}</span></div>
      <div class="panel-body signature-layout"><div class="signature-preview-wrap">${record.signature_path?`<img id="headteacherSignaturePreview" alt="Principal signature">`:`<div class="signature-empty">No signature uploaded</div>`}</div>
      <div class="form-stack"><div><strong>${esc(record.full_name||"Principal")}</strong><p class="muted">Use a clear PNG, JPEG or WebP signature. A transparent PNG gives the best result.</p></div>
      <label class="field"><span>Signature image</span><input id="headteacherSignatureFile" type="file" accept="image/png,image/jpeg,image/webp"></label>
      <div class="button-row"><button class="button primary" id="headteacherSignatureUpload" type="button">Upload signature</button>${record.signature_path?`<button class="button danger" id="headteacherSignatureRemove" type="button">Remove signature</button>`:""}</div></div></div></section>`;
  }
  async function bindPrincipalSignaturePanel(record) {
    if(!record?.linked)return;
    if(record.signature_path&&byId("headteacherSignaturePreview")){
      try{byId("headteacherSignaturePreview").src=await signedUrl(CONFIG.signatureBucket,record.signature_path,900)}catch(_){byId("headteacherSignaturePreview").replaceWith(Object.assign(document.createElement("div"),{className:"signature-empty",textContent:"Signature preview unavailable"}))}
    }
    byId("headteacherSignatureUpload")?.addEventListener("click",async()=>{
      const file=byId("headteacherSignatureFile")?.files?.[0],button=byId("headteacherSignatureUpload");
      if(!file){toast("Signature not uploaded","Select a signature image first.","error");return}
      if(file.size>5*1024*1024){toast("Signature not uploaded","The image must be 5 MB or smaller.","error");return}
      button.disabled=true;button.textContent="Uploading";let uploadedPath="",registered=false;
      try{
        const blob=await prepareSignatureImage(file),path=`${state.boot.profile.id}/${Date.now()}.webp`;uploadedPath=path;
        const {error}=await state.client.storage.from(CONFIG.signatureBucket).upload(path,blob,{contentType:"image/webp",upsert:false});if(error)throw error;
        await rpc("set_my_headteacher_signature",{target_signature_path:path,expected_updated_at:record.updated_at||null});registered=true;
        if(record.signature_path&&record.signature_path!==path){let retained=true;try{retained=await rpc("id_card_principal_signature_path_is_referenced",{target_signature_path:record.signature_path})}catch(error){await reportClientError(error,{source:"principal_signature_retention_check",principal_id:record.id||null})}if(!retained)await removePrivateStorageObjects(CONFIG.signatureBucket,[record.signature_path],{source:"signature_replacement_cleanup",principal_id:record.id||null},true);}
        state.signatureUrls.clear();toast("Digital signature uploaded","New and regenerated official report cards will use this signature.");
        try{await renderDashboard(state.viewToken)}catch(refreshError){await reportClientError(refreshError,{source:"signature_upload_refresh",principal_id:record.id||null});toast("Signature saved","Reload the page to refresh the signature preview.","warning",7000)}
      }catch(error){if(uploadedPath&&!registered)await removePrivateStorageObjects(CONFIG.signatureBucket,[uploadedPath],{source:"signature_upload_rollback",principal_id:record.id||null},true);toast("Signature not uploaded",friendlyError(error),"error",6500)}
      finally{button.disabled=false;button.textContent="Upload signature"}
    });
    byId("headteacherSignatureRemove")?.addEventListener("click",async()=>{
      if(!await confirmAction("Remove Digital Signature","Published PDF files already generated remain unchanged. New and regenerated report cards will not show this signature.","Remove",true))return;
      try{await rpc("set_my_headteacher_signature",{target_signature_path:"",expected_updated_at:record.updated_at||null});if(record.signature_path){let retained=true;try{retained=await rpc("id_card_principal_signature_path_is_referenced",{target_signature_path:record.signature_path})}catch(error){await reportClientError(error,{source:"principal_signature_remove_retention_check",principal_id:record.id||null})}if(!retained)await removePrivateStorageObjects(CONFIG.signatureBucket,[record.signature_path],{source:"signature_remove_cleanup",principal_id:record.id||null},true);}state.signatureUrls.clear();toast("Digital signature removed");try{await renderDashboard(state.viewToken)}catch(refreshError){await reportClientError(refreshError,{source:"signature_remove_refresh",principal_id:record.id||null});toast("Signature removed","Reload the page to refresh the signature panel.","warning",7000)}}
      catch(error){toast("Signature not removed",friendlyError(error),"error",6500)}
    });
  }
  async function prepareSignatureImage(file,maxWidth=1200,maxHeight=420) {
    const bitmap=await createImageBitmap(file),scale=Math.min(1,maxWidth/bitmap.width,maxHeight/bitmap.height);
    const canvas=document.createElement("canvas");canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
    const ctx=canvas.getContext("2d",{willReadFrequently:true});ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();
    const image=ctx.getImageData(0,0,canvas.width,canvas.height),data=image.data;let minX=canvas.width,minY=canvas.height,maxX=-1,maxY=-1;
    for(let y=0;y<canvas.height;y++)for(let x=0;x<canvas.width;x++){const i=(y*canvas.width+x)*4,r=data[i],g=data[i+1],b=data[i+2],brightness=(r+g+b)/3;if(brightness>248)data[i+3]=0;else if(brightness>225)data[i+3]=Math.round(data[i+3]*(248-brightness)/23);if(data[i+3]>18){minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y)}}
    ctx.putImageData(image,0,0);if(maxX<minX||maxY<minY)throw new Error("The selected image does not contain a visible signature");
    const pad=18,x=Math.max(0,minX-pad),y=Math.max(0,minY-pad),w=Math.min(canvas.width-x,maxX-minX+1+pad*2),h=Math.min(canvas.height-y,maxY-minY+1+pad*2);
    const cropped=document.createElement("canvas");cropped.width=w;cropped.height=h;cropped.getContext("2d").drawImage(canvas,x,y,w,h,0,0,w,h);
    return new Promise((resolve,reject)=>cropped.toBlob(blob=>blob?resolve(blob):reject(new Error("Signature conversion failed")),"image/webp",.92));
  }
  function dashboardQuickActions(currentRole) {
    const actions=[];
    if(currentRole==="class_teacher"){
      actions.push(`<button class="button secondary" data-dashboard-view="my_class">My Class</button>`);
      actions.push(`<button class="button secondary" data-dashboard-view="attendance">Attendance</button>`);
      actions.push(`<button class="button secondary" data-dashboard-view="my_subjects">My Subjects</button>`);
    }
    if(currentRole==="subject_teacher")actions.push(`<button class="button secondary" data-dashboard-view="my_subjects">My Subjects</button>`);
    if(can("manage_students"))actions.push(`<button class="button secondary" data-dashboard-view="students">Students</button>`);
    if(can("manage_teachers"))actions.push(`<button class="button secondary" data-dashboard-view="teachers">Teachers</button>`);
    if(can("manage_headteachers"))actions.push(`<button class="button secondary" data-dashboard-view="headteachers">Principals</button>`);
    if(can("manage_emergency_delegations")||can("acknowledge_emergency_delegations"))actions.push(`<button class="button secondary" data-dashboard-view="delegations">Emergency Delegation</button>`);
    if(can("create_reports"))actions.push(`<button class="button primary" data-dashboard-view="reports">Report Cards</button>`);
    if(currentRole==="parent_guardian")actions.push(`<button class="button primary" data-dashboard-view="children">My Children</button>`);
    return actions.join("");
  }
  async function loadRoleWorkspace(force=false) {
    if(force||!state.workspace)state.workspace=await cacheableRpc("role-workspace","get_role_workspace",{},"current");
    return state.workspace||{classes:[],subjects:[]};
  }
  function assignedClassRowsFromWorkspace(workspace=state.workspace) {
    const all=state.boot?.classes||[];
    if(!["class_teacher","subject_teacher"].includes(role()))return all;
    const ids=new Set([...(workspace?.classes||[]).map(item=>item.class_id),...(workspace?.subjects||[]).map(item=>item.class_id)]);
    return all.filter(item=>ids.has(item.id));
  }
  async function visibleClassesForCurrentRole() {
    if(!["class_teacher","subject_teacher"].includes(role()))return state.boot?.classes||[];
    const workspace=await loadRoleWorkspace();
    return assignedClassRowsFromWorkspace(workspace);
  }
  async function loadMyEmergencyDelegations(force=false) {
    if(!["system_admin","class_teacher","subject_teacher"].includes(role()))return [];
    if(force||!Array.isArray(state.myEmergencyDelegations)||!state.myEmergencyDelegations.length){
      try{state.myEmergencyDelegations=await cacheableRpc("emergency-delegations","get_my_emergency_academic_delegations",{target_class_id:null,target_term_id:null},"current");}
      catch(error){if(!isNetworkFailure(error))throw error;state.myEmergencyDelegations=[];}
    }
    return state.myEmergencyDelegations||[];
  }
  function emergencyDelegationScopeLabel(item={}) {
    const subject=item.subject_name?` • ${item.subject_name}`:" • All assigned subjects";
    const capabilities=[item.allow_score_entry?"score entry":"",item.allow_class_report_fields?"class report details":""].filter(Boolean).join(" and ");
    return `${item.class_name||"Class"}${subject}${capabilities?` • ${capabilities}`:""}`;
  }
  function emergencyDelegationBannerHtml(items=[]) {
    if(!items.length)return "";
    const nearest=[...items].sort((a,b)=>new Date(a.valid_until)-new Date(b.valid_until))[0];
    return `<section class="license-banner warning emergency-delegation-banner"><div><strong>Temporary academic access active</strong><span>${esc(emergencyDelegationScopeLabel(nearest))}. Reason: ${esc(nearest.reason||"Emergency continuity access")}</span></div><small>Expires ${esc(isoDateTime(nearest.valid_until))}${items.length>1?` • ${items.length} active delegations`:""}</small></section>`;
  }
  async function editableClassesForCurrentRole() {
    const visible=await visibleClassesForCurrentRole();
    if(role()!=="system_admin")return visible;
    const delegations=await loadMyEmergencyDelegations(true),ids=new Set(delegations.map(item=>item.class_id));
    return visible.filter(item=>ids.has(item.id));
  }
  function workspaceProgress(done,total) {
    const safeTotal=Number(total||0),safeDone=Number(done||0);
    return safeTotal?Math.max(0,Math.min(100,Math.round(safeDone/safeTotal*100))):0;
  }
  async function renderMyClass(token,force=false) {
    const data=await loadRoleWorkspace(force);if(token!==state.viewToken)return;
    const classes=data.classes||[];
    byId("content").innerHTML=`<div class="page-head"><div><h3>My Class</h3><p>Assigned learners, subjects, and report completion</p></div></div>
      ${classes.length?`<div class="grid two">${classes.map(item=>{const completion=workspaceProgress(item.completed_reports,item.expected_reports);return `<section class="panel pad">
        <div class="panel-header"><div><h3>${esc(item.class_name)}</h3><p>${number(item.student_count)} learners • ${number(item.subject_count)} subjects</p></div><span class="status ${completion===100?"published":"draft"}">${completion}% complete</span></div>
        <div class="metric-row"><div class="metric"><span>Draft or returned</span><strong>${number(item.open_reports)}</strong></div><div class="metric"><span>In review</span><strong>${number(item.review_reports)}</strong></div><div class="metric"><span>Published</span><strong>${number(item.published_reports)}</strong></div></div>
        <div class="progress"><span style="width:${completion}%"></span></div><div class="button-row" style="margin-top:15px"><button class="button secondary small" data-workspace-students="${attr(item.class_id)}">Students</button><button class="button primary small" data-workspace-reports="${attr(item.class_id)}">Report Cards</button></div></section>`}).join("")}</div>`:`<section class="panel pad"><div class="empty"><strong>No assigned class</strong></div></section>`}`;
    $$('[data-workspace-students]').forEach(button=>button.onclick=()=>{state.studentClassFilter=button.dataset.workspaceStudents;navigate("students")});
    $$('[data-workspace-reports]').forEach(button=>button.onclick=()=>{state.reportClassFilter=button.dataset.workspaceReports;navigate("reports")});
  }
  function localDateValue(date=new Date()) {
    const offset=date.getTimezoneOffset()*60000;
    return new Date(date.getTime()-offset).toISOString().slice(0,10);
  }
  function attendanceDateForTerm(term) {
    const today=localDateValue();
    if(term?.start_date&&today<term.start_date)return term.start_date;
    if(term?.end_date&&today>term.end_date)return term.end_date;
    return today;
  }
  function attendanceStatusOptions(selected="present") {
    return [["present","Present"],["absent","Absent"],["late","Late"],["excused","Excused"]]
      .map(([value,label])=>`<option value="${value}" ${selected===value?"selected":""}>${label}</option>`).join("");
  }
  async function renderAttendance(token) {
    if(role()!=="class_teacher")throw new Error("Attendance is available only to assigned class teachers");
    const terms=state.boot.terms||[];
    const termId=state.attendanceTermId||activeTerm()?.id||terms[0]?.id||"";
    const term=terms.find(item=>item.id===termId)||terms[0]||null;
    state.attendanceTermId=term?.id||"";
    const classes=term?await cacheableRpc("attendance-classes","list_my_attendance_classes",{target_term_id:term.id},term.id):[];
    if(token!==state.viewToken)return;
    if(!classes.some(item=>item.id===state.attendanceClassId))state.attendanceClassId=classes[0]?.id||"";
    const today=localDateValue();
    const attendanceMaxDate=term?.end_date&&term.end_date<today?term.end_date:today;
    if(!state.attendanceDate)state.attendanceDate=attendanceDateForTerm(term);
    if(term?.start_date&&state.attendanceDate<term.start_date)state.attendanceDate=term.start_date;
    if(state.attendanceDate>attendanceMaxDate)state.attendanceDate=attendanceMaxDate;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Class Attendance</h3><p>Mark daily attendance for your assigned class. Term totals update report cards automatically.</p></div></div>
      <section class="panel pad">
        <div class="form-grid three attendance-controls">
          <label class="field"><span>Academic term</span><select id="attendanceTerm">${optionList(terms,"id","name",state.attendanceTermId)}</select></label>
          <label class="field"><span>Assigned class</span><select id="attendanceClass">${optionList(classes,"id","name",state.attendanceClassId,classes.length?null:"No assigned class")}</select></label>
          <label class="field"><span>School date</span><input id="attendanceDate" type="date" value="${attr(state.attendanceDate)}" ${term?.start_date?`min="${attr(term.start_date)}"`:""} max="${attr(attendanceMaxDate)}"></label>
        </div>
      </section>
      <section class="panel" id="attendanceResults"><div class="empty">Loading attendance register</div></section>`;
    byId("attendanceTerm").onchange=()=>{state.attendanceTermId=byId("attendanceTerm").value;state.attendanceClassId="";state.attendanceDate="";renderAttendance(token)};
    byId("attendanceClass").onchange=()=>{
      state.attendanceClassId=byId("attendanceClass").value;
      if(state.attendanceClassId)loadAttendanceRegister(token);
      else byId("attendanceResults").innerHTML=`<div class="empty"><strong>Select an assigned class</strong></div>`;
    };
    byId("attendanceDate").onchange=()=>{state.attendanceDate=byId("attendanceDate").value;loadAttendanceRegister(token)};
    if(state.attendanceClassId)await loadAttendanceRegister(token);
    else byId("attendanceResults").innerHTML=`<div class="empty"><strong>No class-teacher assignment</strong><span>Ask the System Administrator to assign you as a class teacher.</span></div>`;
  }
  function attendanceStatusButtons(row) {
    return [["present","Present"],["absent","Absent"],["late","Late"],["excused","Excused"]].map(([value,label])=>`<button type="button" class="attendance-status-button ${row.attendance_status===value?"active":""}" data-attendance-button="${attr(row.enrollment_id)}" data-status="${value}" aria-pressed="${row.attendance_status===value?"true":"false"}">${label}</button>`).join("");
  }
  function updateAttendanceSummary(root=byId("attendanceResults")) {
    const counts={present:0,absent:0,late:0,excused:0,unmarked:0};
    $$('[data-attendance-enrollment]',root).forEach(select=>{if(select.value&&counts[select.value]!==undefined)counts[select.value]++;else counts.unmarked++});
    Object.entries(counts).forEach(([key,value])=>{const target=byId(`attendanceCount-${key}`);if(target)target.textContent=number(value)});
    const disabled=!licenseCanWrite()||counts.unmarked>0||!$$('[data-attendance-enrollment]',root).length;
    const save=byId("attendanceSave"),top=byId("attendanceSaveTop");if(save)save.disabled=disabled;if(top)top.disabled=disabled;
    const stateText=byId("attendanceSaveState");if(stateText)stateText.textContent=counts.unmarked?`${number(counts.unmarked)} student${counts.unmarked===1?"":"s"} unmarked`:"All students marked and ready to save";
  }
  function setAttendanceStatus(enrollmentId,status,root=byId("attendanceResults")) {
    const select=$(`[data-attendance-enrollment="${CSS.escape(enrollmentId)}"]`,root);if(!select)return;select.value=status;
    $$(`[data-attendance-button="${CSS.escape(enrollmentId)}"]`,root).forEach(button=>{const active=button.dataset.status===status;button.classList.toggle("active",active);button.setAttribute("aria-pressed",String(active))});
    updateAttendanceSummary(root);
  }
  async function loadAttendanceRegister(token=state.viewToken) {
    const root=byId("attendanceResults");if(!root||!state.attendanceClassId||!state.attendanceTermId||!state.attendanceDate)return;
    root.innerHTML=`<div class="empty">Loading attendance register</div>`;
    const suffix=attendanceSnapshotSuffix();
    const data=await cacheableRpc("attendance-register","get_class_attendance_register",{target_term_id:state.attendanceTermId,target_class_id:state.attendanceClassId,target_date:state.attendanceDate},suffix);
    if(token!==state.viewToken||!byId("attendanceResults"))return;
    state.attendanceData=data;
    const rows=data.students||[],opened=Number(data.days_school_opened||0),marked=Boolean(data.register?.id);
    root.innerHTML=`
      <div class="panel-header attendance-header"><div><h3>${esc(data.class?.name||"Assigned Class")}</h3><p>${isoDate(state.attendanceDate)} • ${marked?"Attendance already recorded":"New attendance register"}</p></div>
        <div class="button-row"><button class="button outline small" id="attendanceAllPresent" type="button" ${rows.length&&licenseCanWrite()?"":"disabled"}>Mark all present</button><button class="button primary attendance-desktop-save" id="attendanceSaveTop" type="button" ${rows.length&&licenseCanWrite()?"":"disabled"}>Save attendance</button></div></div>
      <div class="panel-body attendance-body">
        <div class="metric-row attendance-summary"><div class="metric"><span>Students</span><strong>${number(rows.length)}</strong></div><div class="metric"><span>School days recorded</span><strong>${number(opened)}</strong></div><div class="metric"><span>Selected date</span><strong>${esc(marked?"Recorded":"Not recorded")}</strong></div></div>
        ${rows.length?`
        <div class="attendance-live-summary" aria-live="polite"><span>Present <b id="attendanceCount-present">0</b></span><span>Absent <b id="attendanceCount-absent">0</b></span><span>Late <b id="attendanceCount-late">0</b></span><span>Excused <b id="attendanceCount-excused">0</b></span><span>Unmarked <b id="attendanceCount-unmarked">0</b></span></div>
        <label class="field attendance-search-field"><span>Find student</span><input id="attendanceSearch" type="search" placeholder="Name or admission number" autocomplete="off"></label>
        <div class="attendance-mobile-list">${rows.map(row=>`<article class="attendance-student-card" data-attendance-card data-search="${attr(`${row.full_name} ${row.admission_no}`.toLowerCase())}"><div class="attendance-student-identity"><div class="student-avatar-placeholder" aria-hidden="true">${esc((row.full_name||"?").slice(0,1).toUpperCase())}</div><div><strong>${esc(row.full_name)}</strong><small>${esc(row.admission_no)}${row.roll_number?` • Roll ${esc(row.roll_number)}`:""}</small></div></div><div class="attendance-status-buttons" role="group" aria-label="Attendance status for ${attr(row.full_name)}">${attendanceStatusButtons(row)}</div><div class="attendance-term-total">Term total: <strong>${number(row.days_present)} / ${number(row.days_school_opened)}</strong> days present</div></article>`).join("")}</div>
        <div class="table-wrap attendance-desktop-table"><table><thead><tr><th>Student</th><th>Admission No.</th><th>Daily status</th><th>Term attendance</th></tr></thead><tbody>
          ${rows.map(row=>`<tr><td><div class="cell-copy"><strong>${esc(row.full_name)}</strong><small>${row.roll_number?`Roll ${esc(row.roll_number)}`:""}</small></div></td><td>${esc(row.admission_no)}</td><td><select class="attendance-status-select" data-attendance-enrollment="${attr(row.enrollment_id)}" aria-label="Attendance status for ${attr(row.full_name)}">${attendanceStatusOptions(row.attendance_status||"")}</select></td><td><strong>${number(row.days_present)} / ${number(row.days_school_opened)}</strong><small class="attendance-term-label"> days present</small></td></tr>`).join("")}
        </tbody></table></div><label class="field attendance-notes"><span>Attendance note (optional)</span><textarea id="attendanceNotes">${esc(data.register?.notes||"")}</textarea></label>
        <div class="attendance-sticky-save"><div><strong>${esc(data.class?.name||"Class attendance")}</strong><small id="attendanceSaveState">Review all students before saving</small></div><button class="button primary" id="attendanceSave" type="button">Save attendance</button></div>`:
        `<div class="empty"><strong>No students found</strong><span>No active student records are enrolled in this class for the selected term.</span></div>`}
      </div>`;
    byId("attendanceAllPresent")?.addEventListener("click",()=>$$('[data-attendance-enrollment]',root).forEach(select=>setAttendanceStatus(select.dataset.attendanceEnrollment,"present",root)));
    byId("attendanceSave")?.addEventListener("click",saveClassAttendance);byId("attendanceSaveTop")?.addEventListener("click",saveClassAttendance);
    $$('[data-attendance-button]',root).forEach(button=>button.onclick=()=>setAttendanceStatus(button.dataset.attendanceButton,button.dataset.status,root));
    $$('[data-attendance-enrollment]',root).forEach(select=>select.onchange=()=>setAttendanceStatus(select.dataset.attendanceEnrollment,select.value,root));
    byId("attendanceSearch")?.addEventListener("input",()=>{const q=byId("attendanceSearch").value.trim().toLowerCase();$$('[data-attendance-card]',root).forEach(card=>card.hidden=q&&!card.dataset.search.includes(q))});
    updateAttendanceSummary(root);
  }
  async function saveClassAttendance() {
    const button=byId("attendanceSave"),top=byId("attendanceSaveTop"),entries=$$('[data-attendance-enrollment]',byId("attendanceResults")).map(select=>({enrollment_id:select.dataset.attendanceEnrollment,attendance_status:select.value}));
    if(!entries.length)return;
    [button,top].filter(Boolean).forEach(item=>{item.disabled=true;item.dataset.originalText=item.textContent;item.textContent="Saving"});
    const stateText=byId("attendanceSaveState");if(stateText)stateText.textContent="Saving securely";
    const payload={target_term_id:state.attendanceTermId,target_class_id:state.attendanceClassId,target_date:state.attendanceDate,entries,notes_text:byId("attendanceNotes")?.value.trim()||""};
    try{
      let data,persisted=false;
      if(isConnectivityLimited())data=await queueAttendanceSave(payload);
      else{
        try{data=await rpc("save_class_attendance",payload);persisted=true;await snapshotDataPut("attendance-register",attendanceSnapshotSuffix(),data).catch(()=>{});}
        catch(error){if(isNetworkFailure(error)){noteNetworkFailure(error);data=await queueAttendanceSave(payload)}else throw error;}
      }
      state.attendanceData=data;state.workspace=null;
      if(persisted){toast("Attendance saved",`${number(data.days_school_opened||0)} school day${Number(data.days_school_opened||0)===1?"":"s"} recorded for this term.`);await loadAttendanceRegister();}
      else if(stateText)stateText.textContent="Saved on this device • waiting to synchronise";
    }catch(error){if(stateText)stateText.textContent="Not saved. Check the connection and retry.";toast("Attendance not saved",`${friendlyError(error)} Your marked selections remain on this screen for retry.`,"error",7500)}
    finally{[button,top].filter(Boolean).forEach(item=>{item.disabled=false;item.textContent=item.dataset.originalText||"Save attendance"});updateAttendanceSummary()}
  }

  async function renderMySubjects(token,force=false) {
    const data=await loadRoleWorkspace(force);if(token!==state.viewToken)return;
    const subjects=data.subjects||[];
    byId("content").innerHTML=`<div class="page-head"><div><h3>My Subjects</h3><p>Assigned classes and assessment workload</p></div></div><section class="panel"><div class="table-wrap"><table><thead><tr><th>Class</th><th>Subject</th><th>Learners</th><th>Open reports</th><th>Scored</th><th>Progress</th><th></th></tr></thead><tbody>
      ${subjects.length?subjects.map(item=>{const completion=workspaceProgress(item.scored_reports,item.expected_reports);return `<tr><td><strong>${esc(item.class_name)}</strong></td><td><div class="cell-copy"><strong>${esc(item.subject_name)}</strong><small>${esc(item.subject_code||"")}</small></div></td><td>${number(item.student_count)}</td><td>${number(item.open_reports)}</td><td>${number(item.scored_reports)} / ${number(item.expected_reports)}</td><td><div class="bar-track"><span style="width:${completion}%"></span></div><small>${completion}%</small></td><td><button class="button primary small" data-subject-reports="${attr(item.class_id)}">Report Cards</button></td></tr>`}).join(""):`<tr><td colspan="7"><div class="empty"><strong>No assigned subjects</strong></div></td></tr>`}
      </tbody></table></div></section>`;
    $$('[data-subject-reports]').forEach(button=>button.onclick=()=>{state.reportClassFilter=button.dataset.subjectReports;navigate("reports")});
  }
  function statCard(colour,icon,label,value) {
    const display=typeof value==="string"?value:number(value);
    return `<article class="stat-card"><div class="stat-icon ${colour}">${icon}</div><div><span>${esc(label)}</span><strong>${esc(display)}</strong></div></article>`;
  }
  function canRemoveReportRow(row) {
    if(!can("remove_reports")||row?.archived)return false;
    return ["system_admin","class_teacher","subject_teacher"].includes(role());
  }
  function reportTable(rows,compact=false,manage=false) {
    if(!rows.length)return `<div class="empty"><strong>No report cards</strong><span>Records will appear here when available.</span></div>`;
    return `<div class="table-wrap"><table><thead><tr>
      <th>Student</th><th>Class</th><th>Term</th><th>Average</th><th>Status</th><th>Updated</th>${compact?"":"<th></th>"}
      </tr></thead><tbody>${rows.map(row=>`<tr>
      <td><div class="cell-copy"><strong>${esc(row.student_name)}</strong><small>${esc(row.report_number||row.admission_no||"")}</small></div></td>
      <td>${esc(row.class_name)}</td><td>${esc(row.term_name||"")}</td><td><strong>${number(row.average,1)}%</strong></td>
      <td>${statusBadge(row.archived?"archived":row.status)}</td><td>${isoDateTime(row.updated_at)}</td>
      ${compact?"":`<td><div class="table-actions">
        ${!row.archived?`<button class="button secondary small" data-report-id="${attr(row.id)}">Open</button>`:""}
        ${manage&&canRemoveReportRow(row)?`<button class="button danger small" data-report-archive="${attr(row.id)}">Delete permanently</button>`:""}
      </div></td>`}
      </tr>`).join("")}</tbody></table></div>`;
  }

  async function renderStudents(token) {
    const visibleClasses=await visibleClassesForCurrentRole();
    if(token!==state.viewToken)return;
    if(state.studentClassFilter&&!visibleClasses.some(item=>item.id===state.studentClassFilter))state.studentClassFilter="";
    const content=byId("content");
    content.innerHTML=`
      <div class="page-head"><div><h3>Student Directory</h3><p>Secure student, guardian, and enrolment records</p></div>
        <div class="page-actions">
          ${can("manage_students")?`<button class="button outline" id="studentImport">Import CSV</button><button class="button outline" id="studentExport">Export CSV</button><button class="button primary" id="studentAdd">Add student</button>`:""}
        </div></div>
      <section class="panel">
        <div class="toolbar">
          <label class="search"><input id="studentSearch" type="search" placeholder="Search name or admission number"></label>
          <select id="studentClass">${optionList(visibleClasses,"id","name",state.studentClassFilter||"",["class_teacher","subject_teacher"].includes(role())?"All assigned classes":"All classes")}</select>
          <select id="studentStatus"><option value="">All statuses</option><option value="active">Active</option><option value="graduated">Graduated</option><option value="withdrawn">Withdrawn</option><option value="suspended">Suspended</option></select>
          ${can("remove_students")?`<select id="studentArchive"><option value="active">Current records</option><option value="archived">Archived records</option><option value="all">All records</option></select>`:""}
        </div>
        <div id="studentResults"><div class="empty">Loading students</div></div>
      </section>`;
    byId("studentAdd")?.addEventListener("click",()=>openStudentEditor());
    byId("studentImport")?.addEventListener("click",openStudentImport);
    byId("studentExport")?.addEventListener("click",exportStudentsCsv);
    let timer;
    byId("studentSearch").addEventListener("input",()=>{clearTimeout(timer);timer=setTimeout(()=>{state.studentPage=1;loadStudentPage(token)},250)});
    byId("studentClass").addEventListener("change",()=>{state.studentPage=1;loadStudentPage(token)});
    byId("studentStatus").addEventListener("change",()=>{state.studentPage=1;loadStudentPage(token)});
    byId("studentArchive")?.addEventListener("change",()=>{state.studentPage=1;loadStudentPage(token)});
    await loadStudentPage(token);
  }
  async function loadStudentPage(token=state.viewToken) {
    const container=byId("studentResults");if(!container)return;
    container.innerHTML=`<div class="empty">Loading students</div>`;
    const data=await rpc("search_students_v5",{
      search_text:byId("studentSearch")?.value.trim()||"",
      target_class_id:byId("studentClass")?.value||null,
      target_status:byId("studentStatus")?.value||null,
      archive_filter:byId("studentArchive")?.value||"active",
      page_number:state.studentPage,page_size:CONFIG.pageSize
    });
    if(token!==state.viewToken||!byId("studentResults"))return;
    const rows=data.rows||[];
    container.innerHTML=rows.length?`
      <div class="table-wrap"><table><thead><tr><th>Student</th><th>Admission No.</th><th>Class</th><th>Academic Year</th><th>Status</th><th></th></tr></thead>
      <tbody>${rows.map(row=>`<tr>
        <td><div class="cell-main"><img class="thumb signed-photo" data-photo="${attr(row.photo_url||"")}" src="${CONFIG.logoPath}" alt="">
          <div class="cell-copy"><strong>${esc(fullName(row))}</strong><small>${esc(row.gender||"")} ${row.roll_number?`• Roll ${esc(row.roll_number)}`:""}</small></div></div></td>
        <td>${esc(row.admission_no)}</td><td>${esc(row.class_name||"—")}</td><td>${esc(row.academic_year_name||"—")}</td>
        <td>${statusBadge(row.archived?"archived":row.status)}</td><td><div class="table-actions">
          <button class="button secondary small" data-student-view="${attr(row.id)}">View</button>
          ${can("manage_students")&&!row.archived?`<button class="button ghost small" data-student-edit="${attr(row.id)}">Edit</button>`:""}
          ${row.enrollment_id&&!row.archived&&["class_teacher","subject_teacher"].includes(role())?`<button class="button outline small" data-student-report="${attr(row.enrollment_id)}">Report</button>`:""}
          ${can("remove_students")&&!row.archived?`<button class="button danger small" data-student-archive="${attr(row.id)}">Remove</button>`:""}
          ${can("remove_students")&&row.archived?`<button class="button success small" data-student-restore="${attr(row.id)}">Restore</button>`:""}
        </div></td></tr>`).join("")}</tbody></table></div>
      ${pagination(data.total,data.page,data.page_size,"student")}`:`<div class="empty"><strong>No students found</strong><span>The current filters returned no records.</span></div>`;
    resolveSignedPhotos(container);
    $$("[data-student-view]",container).forEach(btn=>btn.onclick=()=>openStudentRecord(btn.dataset.studentView));
    $$("[data-student-edit]",container).forEach(btn=>btn.onclick=()=>openStudentEditor(btn.dataset.studentEdit));
    $$("[data-student-report]",container).forEach(btn=>btn.onclick=()=>chooseTermForReport(btn.dataset.studentReport));
    $$("[data-student-archive]",container).forEach(btn=>btn.onclick=()=>archiveStudent(btn.dataset.studentArchive));
    $$("[data-student-restore]",container).forEach(btn=>btn.onclick=()=>restoreStudent(btn.dataset.studentRestore));
    bindPagination("student",data);
  }
  function pagination(total,page,pageSize,key) {
    const pages=Math.max(1,Math.ceil(Number(total||0)/Number(pageSize||CONFIG.pageSize)));
    const start=total?((page-1)*pageSize+1):0,end=Math.min(page*pageSize,total);
    return `<div class="pagination"><small>${number(start)}–${number(end)} of ${number(total)}</small><div class="pager">
      <button class="button ghost small" data-page-key="${key}" data-page="${page-1}" ${page<=1?"disabled":""}>Previous</button>
      <button class="button ghost small" data-page-key="${key}" data-page="${page+1}" ${page>=pages?"disabled":""}>Next</button>
    </div></div>`;
  }
  function bindPagination(key,data) {
    $$(`[data-page-key="${key}"]`).forEach(button=>button.onclick=()=>{
      const page=Number(button.dataset.page);if(page<1)return;
      if(key==="student"){state.studentPage=page;loadStudentPage()}
      if(key==="teacher"){state.teacherPage=page;loadTeacherPage()}
      if(key==="principal"){state.headteacherPage=page;loadPrincipalPage()}
      if(key==="report"){state.reportPage=page;loadReportPage()}
    });
  }
  async function resolveSignedPhotos(root=document) {
    await Promise.all($$(".signed-photo",root).map(async image=>{
      const path=image.dataset.photo;if(!path)return;
      try{image.src=await signedUrl(CONFIG.photoBucket,path)}catch(_){image.src=CONFIG.logoPath}
    }));
  }

  async function openStudentRecord(id) {
    const data=await run(()=>rpc("get_student_record_v5",{target_student_id:id}),{context:{student_id:id}});
    state.currentStudent=data;
    const student=data.student||{},enrolments=data.enrollments||[],guardians=data.guardians||[],reports=data.reports||[];
    modal(fullName(student),student.admission_no,`
      <div class="grid two">
        <div class="panel pad">
          <div class="cell-main"><img id="recordPhoto" class="preview-photo" src="${CONFIG.logoPath}" alt=""><div class="cell-copy">
            <strong>${esc(fullName(student))}</strong><small>${esc(student.gender)} • ${isoDate(student.date_of_birth)}</small>
            <small>${statusBadge(student.archived?"archived":student.status)}</small></div></div>
          <div class="hr"></div><div class="section-title"><h4>Guardians</h4></div>
          ${guardians.length?guardians.map(g=>`<div class="metric"><strong>${esc(g.full_name)}</strong><span>${esc(g.relationship)} • ${esc(g.phone||"No phone")} • ${esc(g.email||"No email")}</span></div>`).join(""):`<p class="help-text">No guardian record</p>`}
        </div>
        <div class="panel pad"><div class="section-title"><h4>Enrolment History</h4></div>
          ${enrolments.length?enrolments.map(e=>`<div class="diff-row"><span>${esc(e.academic_year_name)} • ${esc(e.class_name)}</span><b>${e.active?"Active":"Closed"}</b></div>`).join(""):`<p class="help-text">No enrolment record</p>`}
        </div>
      </div>
      <div class="section-title" style="margin-top:18px"><h4>Report Cards</h4></div>
      ${reportTable(reports)}
    `,can("manage_students")?`<div class="button-row">
      ${!student.archived?`<button class="button primary" id="recordEdit">Edit student</button>`:""}
      ${can("remove_students")&&!student.archived?`<button class="button danger" id="recordArchive">Remove student</button>`:""}
      ${can("remove_students")&&student.archived?`<button class="button success" id="recordRestore">Restore student</button>`:""}
    </div>`:"","wide");
    if(student.photo_url) signedUrl(CONFIG.photoBucket,student.photo_url).then(url=>{if(byId("recordPhoto"))byId("recordPhoto").src=url}).catch(()=>{});
    byId("recordEdit")?.addEventListener("click",()=>{closeModal();openStudentEditor(id)});
    byId("recordArchive")?.addEventListener("click",()=>{closeModal();archiveStudent(id)});
    byId("recordRestore")?.addEventListener("click",()=>{closeModal();restoreStudent(id)});
    $$("[data-report-id]",byId("modalBody")).forEach(btn=>btn.onclick=()=>{closeModal();openReportEditor(btn.dataset.reportId)});
  }

  async function archiveStudent(id) {
    const ok=await confirmAction("Remove Student","The student will be archived while historical reports remain preserved.","Remove",true);
    if(!ok)return;
    try{
      await rpc("archive_student",{target_student_id:id,reason_text:"Student removed from active records"});
      state.workspace=null;toast("Student removed");await loadStudentPage();
    }catch(error){toast("Student not removed",friendlyError(error),"error")}
  }
  async function restoreStudent(id) {
    const ok=await confirmAction("Restore Student","The student will return to the current student directory.","Restore");
    if(!ok)return;
    try{
      await rpc("restore_student",{target_student_id:id,reason_text:"Student restored to active records"});
      state.workspace=null;toast("Student restored");await loadStudentPage();
    }catch(error){toast("Student not restored",friendlyError(error),"error")}
  }

  async function openStudentEditor(id=null) {
    let record={student:{status:"active",gender:"Male"},enrollments:[],guardians:[]};
    if(id) record=await run(()=>rpc("get_student_record_v5",{target_student_id:id}));
    try{state.guardianAccounts=await rpc("list_guardian_portal_accounts",{search_text:""})}catch(_){state.guardianAccounts=[]}
    const student=record.student||{},latest=record.enrollments?.[0]||{},guardian=record.guardians?.find(g=>g.is_primary)||record.guardians?.[0]||{};
    if(!id&&!student.admission_no){try{student.admission_no=await rpc("generate_school_identifier",{identifier_kind:"student"})}catch(_){student.admission_no=""}}
    const years=state.boot.academic_years||[],classes=state.boot.classes||[];
    modal(id?"Edit Student":"Add Student",id?student.admission_no:"",`
      <form id="studentForm" class="form-stack">
        <input type="hidden" name="id" value="${attr(student.id||"")}">
        <input type="hidden" name="updated_at" value="${attr(student.updated_at||"")}">
        <div class="form-grid three">
          <label class="field"><span>Admission number</span><input name="admission_no" value="${attr(student.admission_no||"")}" readonly></label>
          <label class="field"><span>First name</span><input name="first_name" value="${attr(student.first_name||"")}" required></label>
          <label class="field"><span>Middle name</span><input name="middle_name" value="${attr(student.middle_name||"")}"></label>
          <label class="field"><span>Last name</span><input name="last_name" value="${attr(student.last_name||"")}" required></label>
          <label class="field"><span>Gender</span><select name="gender">
            ${["Male","Female","Other"].map(v=>`<option ${v===student.gender?"selected":""}>${v}</option>`).join("")}</select></label>
          <label class="field"><span>Date of birth</span><input type="date" name="date_of_birth" value="${attr(student.date_of_birth||"")}"></label>
          <label class="field"><span>Status</span><select name="status">
            ${["active","graduated","withdrawn","suspended"].map(v=>`<option value="${v}" ${v===student.status?"selected":""}>${v.replaceAll("_"," ")}</option>`).join("")}</select></label>
          <label class="field"><span>Academic year</span><select name="academic_year_id">${optionList(years,"id","name",latest.academic_year_id||activeYear()?.id,"Select academic year")}</select></label>
          <label class="field"><span>Class</span><select name="class_id">${optionList(classes,"id","name",latest.class_id,"Select class")}</select></label>
          <label class="field"><span>Roll number</span><input type="number" min="1" name="roll_number" value="${attr(latest.roll_number||"")}"></label>
          <label class="field full"><span>Student photograph</span><input id="studentPhotoFile" type="file" accept="image/jpeg,image/png,image/webp"></label>
        </div>
        <div class="section-title"><h4>Primary Guardian</h4></div>
        <div class="form-grid three">
          <input type="hidden" name="guardian_id" value="${attr(guardian.id||"")}">
          <label class="field"><span>Full name</span><input name="guardian_name" value="${attr(guardian.full_name||student.guardian_name||"")}"></label>
          <label class="field"><span>Relationship</span><input name="relationship" value="${attr(guardian.relationship||"Guardian")}"></label>
          <label class="field"><span>Telephone</span><input name="guardian_phone" value="${attr(guardian.phone||student.guardian_phone||"")}"></label>
          <label class="field"><span>Email</span><input type="email" name="guardian_email" value="${attr(guardian.email||student.guardian_email||"")}"></label>
          <label class="field"><span>Portal account</span><select name="guardian_auth_user_id">${optionList((state.guardianAccounts||[]).map(item=>({...item,label:`${item.full_name}${item.email?` • ${item.email}`:""}`})),"id","label",guardian.auth_user_id,"No linked account")}</select></label>
          <label class="field"><span>Address</span><input name="guardian_address" value="${attr(guardian.address||"")}"></label>
          <label class="check-field"><input type="checkbox" name="guardian_notify" ${guardian.can_receive_notifications!==false?"checked":""}><span>Receive notifications</span></label>
        </div>
      </form>`,
      `<button class="button ghost" type="button" id="studentCancel">Cancel</button><button class="button primary" type="submit" form="studentForm" id="studentSave">Save student</button>`,"wide");
    byId("studentCancel").onclick=closeModal;
    byId("studentForm").addEventListener("submit",event=>{event.preventDefault();saveStudentForm(record)});
  }

  function formObject(form) {return Object.fromEntries(new FormData(form).entries())}
  async function saveStudentForm(record) {
    const form=byId("studentForm"),button=byId("studentSave");
    if(!form?.reportValidity()){toast("Student not saved","Complete the required student fields.","error");return}
    const values=formObject(form);if(Boolean(values.academic_year_id)!==Boolean(values.class_id)){toast("Student not saved","Academic year and class must be selected together.","error");return}
    button.disabled=true;button.textContent="Saving";
    const payload={
      student:{id:values.id,updated_at:values.updated_at,admission_no:values.admission_no.trim(),first_name:values.first_name.trim(),
        middle_name:(values.middle_name||"").trim(),last_name:values.last_name.trim(),gender:values.gender,
        date_of_birth:values.date_of_birth||"",status:values.status,photo_url:record.student?.photo_url||""},
      enrollment:values.academic_year_id&&values.class_id?{academic_year_id:values.academic_year_id,class_id:values.class_id,roll_number:values.roll_number||"",active:true}:{},
      guardian:{id:values.guardian_id,full_name:(values.guardian_name||"").trim(),relationship:(values.relationship||"Guardian").trim(),
        phone:(values.guardian_phone||"").trim(),email:(values.guardian_email||"").trim(),address:(values.guardian_address||"").trim(),
        auth_user_id:values.guardian_auth_user_id||"",is_primary:true,can_view_reports:true,
        can_receive_notifications:form.elements.guardian_notify.checked},
      reason:values.id?"Student record updated":"Student registered"
    };
    let saved;
    try {
      saved=await rpc("save_student",{payload});
    } catch(error) {
      await reportClientError(error,{source:"student_save",stage:"record"});
      toast("Student not saved",friendlyError(error),"error",6500);
      button.disabled=false;button.textContent="Save student";return;
    }

    let photoWarning="",photoReportSummary="";
    const file=byId("studentPhotoFile")?.files?.[0];
    if(file) {
      let uploadedPhotoPath="",photoSaved=false;
      try {
        uploadedPhotoPath=await uploadStudentPhoto(saved.student.id,file);
        const previousPhotoPath=record.student?.photo_url||"";
        saved=await rpc("set_student_photo",{target_student_id:saved.student.id,target_photo_url:uploadedPhotoPath,expected_updated_at:saved.student.updated_at||null});
        const committedPhotoPath=uploadedPhotoPath;uploadedPhotoPath="";photoSaved=true;
        if(previousPhotoPath&&previousPhotoPath!==committedPhotoPath){
          let retainedForIssuedCard=true;
          try{retainedForIssuedCard=Number(await rpc("id_card_photo_reference_count",{target_student_id:saved.student.id,target_photo_path:previousPhotoPath}))>0}
          catch(error){await reportClientError(error,{source:"id_card_photo_retention_check",student_id:saved.student.id});retainedForIssuedCard=true}
          if(!retainedForIssuedCard)await removePrivateStorageObjects(CONFIG.photoBucket,[previousPhotoPath],{source:"student_photo_replacement_cleanup",student_id:saved.student.id},true);
        }
      } catch(error) {
        if(uploadedPhotoPath)await removePrivateStorageObjects(CONFIG.photoBucket,[uploadedPhotoPath],{source:"student_photo_upload_rollback",student_id:saved.student.id},true);
        await reportClientError(error,{source:"student_save",stage:"photo",student_id:saved.student.id});
        photoWarning="The student record was saved, but the photograph was not updated.";
      }
      if(photoSaved){
        button.textContent="Updating report PDFs";
        const refreshed=await refreshPublishedStudentReportPdfs(saved.student);
        if(refreshed.updated)photoReportSummary=`${refreshed.updated} published report PDF${refreshed.updated===1?"":"s"} updated with the photograph.`;
        if(refreshed.failed)photoWarning=`The photograph was saved, but ${refreshed.failed} published report PDF${refreshed.failed===1?"":"s"} could not be refreshed automatically.`;
      }
    }

    state.workspace=null;closeModal();
    const saveDetail=[photoReportSummary,photoWarning].filter(Boolean).join(" ");
    toast("Student record saved",saveDetail,photoWarning?"warning":"success",7500);
    try {
      state.boot=await rpc("get_bootstrap_data");
      await loadStudentPage();
    } catch(error) {
      await reportClientError(error,{source:"student_save",stage:"refresh",student_id:saved.student.id});
      toast("Student saved","Reload the page to display the latest record.","warning",6500);
    } finally {button.disabled=false;button.textContent="Save student"}
  }
  async function compressImage(file,maxSize=1000,quality=.84) {
    const bitmap=await createImageBitmap(file),scale=Math.min(1,maxSize/Math.max(bitmap.width,bitmap.height));
    const canvas=document.createElement("canvas");canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);
    canvas.getContext("2d").drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();
    return new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error("Image conversion failed")),"image/webp",quality));
  }
  async function uploadStudentPhoto(studentId,file) {
    const blob=await compressImage(file),path=`${studentId}/${Date.now()}.webp`;
    const {error}=await state.client.storage.from(CONFIG.photoBucket).upload(path,blob,{contentType:"image/webp",upsert:false});
    if(error)throw error;
    return path;
  }
  function parseCsv(text) {
    const rows=[];let row=[],cell="",quoted=false;
    for(let i=0;i<text.length;i++){
      const ch=text[i],next=text[i+1];
      if(ch==='"'&&quoted&&next==='"'){cell+='"';i++}
      else if(ch==='"'){quoted=!quoted}
      else if(ch===","&&!quoted){row.push(cell);cell=""}
      else if((ch==="\n"||ch==="\r")&&!quoted){if(ch==="\r"&&next==="\n")i++;row.push(cell);cell="";if(row.some(v=>v.trim()))rows.push(row);row=[]}
      else cell+=ch;
    }
    row.push(cell);if(row.some(v=>v.trim()))rows.push(row);
    if(rows.length<2)return[];
    const headers=rows[0].map(h=>h.trim().toLowerCase().replace(/\s+/g,"_"));
    return rows.slice(1).map(values=>Object.fromEntries(headers.map((h,i)=>[h,(values[i]||"").trim()])));
  }
  function importValidationHtml(result) {
    const errors=result.errors||[];
    return `<div class="metric-row wrap">${maturityMetric("Rows",number(result.total))}${maturityMetric("Valid",number(result.valid_count))}${maturityMetric("Invalid",number(result.invalid_count))}</div>
      ${errors.length?`<div class="import-error-list"><div class="section-title"><h4>Rows requiring correction</h4><button class="button ghost small" id="importErrorsDownload" type="button">Download errors</button></div><div class="compact-scroll"><table><thead><tr><th>Row</th><th>Issue</th></tr></thead><tbody>${errors.slice(0,100).map(item=>`<tr><td>${number(item.row_number)}</td><td>${esc(item.message)}</td></tr>`).join("")}</tbody></table></div></div>`:`<div class="template-information success"><strong>Validation passed</strong><span>All rows are eligible for import.</span></div>`}`;
  }
  function downloadImportErrors(result,filename="import-errors.csv") {
    const rows=(result.errors||[]).map(item=>[item.row_number,item.message,JSON.stringify(item.payload||{})]);
    downloadText(filename,["row_number,message,payload",...rows.map(row=>row.map(csvCell).join(","))].join("\n"),"text/csv");
  }
  function openStudentImport() {
    modal("Import Students","CSV student registration with server-side validation and preview",`
      <form id="studentImportForm" class="form-stack">
        <div class="form-grid">
          <label class="field"><span>Academic year</span><select name="academic_year_id" required>${optionList(state.boot.academic_years||[],"id","name",activeYear()?.id)}</select></label>
          <label class="field"><span>Class</span><select name="class_id" required>${optionList(state.boot.classes||[],"id","name")}</select></label>
        </div>
        <label class="file-drop"><strong>CSV file</strong><input name="file" type="file" accept=".csv,text/csv" required></label>
        <div id="studentImportPreview"></div>
      </form>`,
      `<button class="button ghost" id="importCancel" type="button">Cancel</button><button class="button secondary" id="importValidate" type="button">Validate</button><button class="button primary" id="importRun" type="button" disabled>Import valid rows</button>`,"small");
    byId("importCancel").onclick=closeModal;
    let validation=null,fileName="";
    byId("importValidate").onclick=async()=>{
      const form=byId("studentImportForm"),file=form.elements.file.files[0];if(!file){toast("Select a CSV file","Choose the file before validation.","warning");return}
      const values=formObject(form),rows=parseCsv(await file.text()),button=byId("importValidate");button.disabled=true;button.textContent="Validating";
      try{validation=await rpc("validate_student_import",{rows,target_academic_year_id:values.academic_year_id,target_class_id:values.class_id,filename:file.name});fileName=file.name;byId("studentImportPreview").innerHTML=importValidationHtml(validation);byId("importRun").disabled=!validation.valid_count;byId("importErrorsDownload")?.addEventListener("click",()=>downloadImportErrors(validation,"student-import-errors.csv"));toast("Validation completed",`${number(validation.valid_count)} valid, ${number(validation.invalid_count)} invalid.`,validation.invalid_count?"warning":"success")}
      catch(error){toast("Validation unsuccessful",friendlyError(error),"error")}finally{button.disabled=false;button.textContent="Validate"}
    };
    byId("importRun").onclick=async()=>{
      if(!validation?.valid_count)return;const button=byId("importRun");button.disabled=true;
      try {const result=await rpc("bulk_import_students",{rows:validation.valid_rows,filename:fileName});closeModal();toast("Import completed",`${result.successful} saved, ${result.failed} failed`,result.failed?"warning":"success",7000);await loadStudentPage()}
      catch(error){toast("Import unsuccessful",friendlyError(error),"error")}finally{button.disabled=false}
    };
  }
  async function exportStudentsCsv() {
    const data=await rpcAllRows("search_students_v5",{search_text:byId("studentSearch")?.value||"",target_class_id:byId("studentClass")?.value||null,
      target_status:byId("studentStatus")?.value||null,archive_filter:byId("studentArchive")?.value||"active"});
    const headers=["admission_no","first_name","middle_name","last_name","gender","date_of_birth","status","class_name","academic_year_name","roll_number"];
    downloadText("students.csv",[headers.join(","),...(data.rows||[]).map(row=>headers.map(h=>csvCell(row[h])).join(","))].join("\n"),"text/csv");
  }
  const csvCell=value=>`"${String(value??"").replaceAll('"','""')}"`;
  function downloadText(filename,text,type="text/plain") {
    const url=URL.createObjectURL(new Blob([text],{type})),a=document.createElement("a");a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
  function chooseTermForReport(enrollmentId) {
    const enrollmentYear=(state.currentStudent?.enrollments||[]).find(e=>e.id===enrollmentId)?.academic_year_id;
    const terms=(state.boot.terms||[]).filter(t=>!enrollmentYear||t.academic_year_id===enrollmentYear);
    modal("Select Term","Create or open a report card",`<label class="field"><span>Term</span><select id="reportTermChoice">${optionList(terms,"id","name",activeTerm()?.id)}</select></label>`,
      `<button class="button ghost" id="termCancel" type="button">Cancel</button><button class="button primary" id="termOpen" type="button">Open report</button>`,"small");
    byId("termCancel").onclick=closeModal;
    byId("termOpen").onclick=()=>{const termId=byId("reportTermChoice").value;if(termId){closeModal();openReportEditor(null,enrollmentId,termId)}};
  }


  async function renderAcademics(token) {
    const data=await rpc("get_academic_configuration");
    if(token!==state.viewToken)return;
    state.academic=data;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Academic Configuration</h3><p>Periods, classes, subjects, assessment, and promotion</p></div></div>
      <div class="tabs">
        ${[["periods","Academic Periods"],["classes","Classes and Subjects"],["assessment","Assessment Schemes"],["grading","Grading Scales"],["promotion","Class Promotion"]].map(([id,label])=>
          `<button class="tab ${state.academicTab===id?"active":""}" data-academic-tab="${id}">${label}</button>`).join("")}
      </div>
      <div id="academicPanel"></div>`;
    $$("[data-academic-tab]").forEach(button=>button.onclick=()=>{state.academicTab=button.dataset.academicTab;renderAcademicTab()});
    renderAcademicTab();
  }
  function renderAcademicTab() {
    const target=byId("academicPanel");if(!target)return;
    const renderers={periods:renderPeriodsTab,classes:renderClassesTab,assessment:renderAssessmentTab,grading:renderGradingTab,promotion:renderPromotionTab};
    const activeTab=renderers[state.academicTab]?state.academicTab:"periods";
    state.academicTab=activeTab;
    [...document.querySelectorAll("[data-academic-tab]")].forEach(button=>{
      const isActive=button.dataset.academicTab===activeTab;
      button.classList.toggle("active",isActive);
      button.setAttribute("aria-selected",String(isActive));
      button.tabIndex=isActive?0:-1;
    });
    target.innerHTML=renderers[activeTab]();
    bindAcademicTabEvents();
  }
  function renderPeriodsTab() {
    const y=state.academic.academic_years||[],terms=state.academic.terms||[];
    return `<div class="grid two">
      <section class="panel"><div class="panel-header"><div><h3>Academic Years</h3><p>${y.length} configured</p></div><button class="button primary small" id="addYear">Add year</button></div>
        <div class="table-wrap"><table><thead><tr><th>Name</th><th>Dates</th><th>Status</th><th></th></tr></thead><tbody>
          ${y.map(row=>`<tr><td><strong>${esc(row.name)}</strong></td><td>${isoDate(row.start_date)} – ${isoDate(row.end_date)}</td>
            <td>${row.is_active?`<span class="status published">Active</span>`:`<span class="status draft">Inactive</span>`}</td>
            <td><div class="table-actions"><button class="button ghost small" data-edit-year="${row.id}">Edit</button>${!row.is_active?`<button class="button danger small" data-remove-year="${row.id}">Remove</button>`:""}</div></td></tr>`).join("")}
        </tbody></table></div></section>
      <section class="panel"><div class="panel-header"><div><h3>Terms</h3><p>${terms.length} configured</p></div><button class="button primary small" id="addTerm">Add term</button></div>
        <div class="table-wrap"><table><thead><tr><th>Term</th><th>Academic Year</th><th>Status</th><th></th></tr></thead><tbody>
          ${terms.map(row=>`<tr><td><div class="cell-copy"><strong>${esc(row.name)}</strong><small>${isoDate(row.start_date)} – ${isoDate(row.end_date)}</small>${row.next_term_begins?`<small>Next term reopens: ${isoDate(row.next_term_begins)}</small>`:`<small>Next-term reopening date not set</small>`}</div></td>
            <td>${esc(y.find(x=>x.id===row.academic_year_id)?.name||"")}</td>
            <td>${row.is_active?`<span class="status published">Active</span>`:`<span class="status draft">Inactive</span>`}</td>
            <td><div class="table-actions"><button class="button ghost small" data-edit-term="${row.id}">Edit</button>
            ${!row.is_active?`<button class="button success small" data-set-active="${row.academic_year_id}|${row.id}">Activate</button><button class="button danger small" data-remove-term="${row.id}">Remove</button>`:""}</div></td></tr>`).join("")}
        </tbody></table></div></section>
    </div>`;
  }
  function classSubjectAssignmentGroups(assignments=[]) {
    const groups=new Map();
    assignments.forEach(row=>{
      const key=row.teacher_id||"__unassigned__";
      if(!groups.has(key)){
        groups.set(key,{
          key,
          teacher_id:row.teacher_id||null,
          teacher_name:row.teacher_name||"Unassigned",
          rows:[],
          classes:new Map(),
          subjects:new Map(),
          active_count:0,
          inactive_count:0
        });
      }
      const group=groups.get(key);
      group.rows.push(row);
      if(row.class_id||row.class_name)group.classes.set(row.class_id||row.class_name,row.class_name||"Class");
      if(row.subject_id||row.subject_name)group.subjects.set(row.subject_id||row.subject_name,row.subject_name||"Subject");
      if(row.active)group.active_count+=1;else group.inactive_count+=1;
    });
    return [...groups.values()].sort((a,b)=>
      String(a.teacher_name).localeCompare(String(b.teacher_name),undefined,{sensitivity:"base"})
    );
  }

  function assignmentCountText(count,singular,plural=`${singular}s`) {
    return `${count} ${count===1?singular:plural}`;
  }

  function assignmentNamesPreview(values,limit=3) {
    const names=[...values.values()];
    if(!names.length)return "—";
    if(names.length<=limit)return names.join(", ");
    return `${names.slice(0,limit).join(", ")} +${names.length-limit}`;
  }

  function openAssignmentGroupManager(groupKey) {
    const group=classSubjectAssignmentGroups(state.academic?.class_subjects||[])
      .find(item=>item.key===groupKey);
    if(!group)return;
    const rows=[...group.rows].sort((a,b)=>
      String(a.class_name||"").localeCompare(String(b.class_name||""),undefined,{numeric:true,sensitivity:"base"})||
      String(a.subject_name||"").localeCompare(String(b.subject_name||""),undefined,{sensitivity:"base"})
    );
    modal("Manage Teacher Assignments",group.teacher_name,`
      <div class="assignment-group-summary">
        <div><span>Teacher</span><strong>${esc(group.teacher_name)}</strong></div>
        <div><span>Classes</span><strong>${assignmentCountText(group.classes.size,"class","classes")}</strong></div>
        <div><span>Subjects</span><strong>${assignmentCountText(group.subjects.size,"subject")}</strong></div>
        <div><span>Assignments</span><strong>${assignmentCountText(group.rows.length,"assignment")}</strong></div>
      </div>
      <div class="assignment-detail-meta">
        <div><span>Classes:</span> ${esc([...group.classes.values()].join(", ")||"—")}</div>
        <div><span>Subjects:</span> ${esc([...group.subjects.values()].join(", ")||"—")}</div>
      </div>
      <div class="table-wrap assignment-detail-table"><table>
        <thead><tr><th>Class</th><th>Subject</th><th>Status</th><th></th></tr></thead>
        <tbody>${rows.map(row=>`<tr>
          <td>${esc(row.class_name||"—")}</td>
          <td>${esc(row.subject_name||"—")}</td>
          <td>${row.active?`<span class="status published">Active</span>`:`<span class="status withdrawn">Inactive</span>`}</td>
          <td><div class="table-actions">
            <button class="button ghost small" data-group-edit-assignment="${attr(row.id)}">Edit</button>
            ${row.active
              ?`<button class="button danger small" data-group-remove-assignment="${attr(row.id)}">Remove</button>`
              :`<button class="button danger small" data-group-delete-assignment="${attr(row.id)}">Delete</button>`}
          </div></td>
        </tr>`).join("")}</tbody>
      </table></div>
    `,`<button class="button ghost" id="assignmentGroupClose" type="button">Close</button>
       ${group.teacher_id?`<button class="button primary" id="assignmentGroupAdd" type="button">Assign more</button>`:""}`,"wide");
    byId("assignmentGroupClose").onclick=closeModal;
    if(byId("assignmentGroupAdd"))byId("assignmentGroupAdd").onclick=()=>{
      const teacherId=group.teacher_id;
      closeModal();
      openAssignmentEditor(null,teacherId);
    };
    $$("[data-group-edit-assignment]").forEach(button=>button.onclick=()=>{
      const id=button.dataset.groupEditAssignment;
      closeModal();
      openAssignmentEditor(id);
    });
    $$("[data-group-remove-assignment]").forEach(button=>button.onclick=()=>{
      const id=button.dataset.groupRemoveAssignment;
      closeModal();
      removeAcademicEntity("assignment",id);
    });
    $$("[data-group-delete-assignment]").forEach(button=>button.onclick=()=>{
      const id=button.dataset.groupDeleteAssignment;
      closeModal();
      deleteClassSubjectAssignment(id);
    });
  }

  function renderClassesTab() {
    const classes=state.academic.classes||[],subjects=state.academic.subjects||[],assignments=state.academic.class_subjects||[];
    const assignmentGroups=classSubjectAssignmentGroups(assignments);
    const activeAssignments=assignments.filter(item=>item.active).length;
    const activeTeachers=assignmentGroups.filter(group=>group.active_count>0).length;
    return `<div class="grid two">
      <section class="panel"><div class="panel-header"><div><h3>Classes</h3><p>${classes.length} configured</p></div><button class="button primary small" id="addClass">Add class</button></div>
        <div class="table-wrap academic-list-scroll"><table><thead><tr><th>Class</th><th>Level</th><th>Class Teacher</th><th></th></tr></thead><tbody>
          ${classes.map(row=>`<tr><td><strong>${esc(row.name)}</strong></td><td>${number(row.level_order)}</td>
            <td>${esc(
              (state.academic.teacher_records||[]).find(t=>t.id===row.class_teacher_record_id)?.full_name
              ||(state.academic.profiles||[]).find(p=>p.id===row.class_teacher_id)?.full_name
              ||"—"
            )}</td>
            <td><div class="table-actions"><button class="button ghost small" data-edit-class="${row.id}">Edit</button><button class="button danger small" data-remove-class="${row.id}">Remove</button></div></td></tr>`).join("")}
        </tbody></table></div></section>
      <section class="panel"><div class="panel-header"><div><h3>Subjects</h3><p>${subjects.length} configured</p></div><button class="button primary small" id="addSubject">Add subject</button></div>
        <div class="table-wrap academic-list-scroll"><table><thead><tr><th>Code</th><th>Subject</th><th>Order</th><th></th></tr></thead><tbody>
          ${subjects.map(row=>`<tr><td><strong>${esc(row.code)}</strong></td><td>${esc(row.name)}</td><td>${number(row.display_order)}</td>
            <td><div class="table-actions"><button class="button ghost small" data-edit-subject="${row.id}">Edit</button><button class="button danger small" data-remove-subject="${row.id}">Remove</button></div></td></tr>`).join("")}
        </tbody></table></div></section>
      <section class="panel" style="grid-column:1/-1"><div class="panel-header"><div><h3>Class Subject Assignments</h3><p>${activeAssignments} active assignments across ${assignmentCountText(activeTeachers,"teacher")}</p></div>
        <button class="button primary small" id="addAssignment">Assign subject</button></div>
        <div class="table-wrap"><table class="compact-assignment-table"><thead><tr><th>Teacher</th><th>Classes</th><th>Subjects</th><th>Assignments</th><th>Status</th><th></th></tr></thead><tbody>
          ${assignmentGroups.length?assignmentGroups.map(group=>`<tr>
            <td><div class="cell-copy"><strong>${esc(group.teacher_name)}</strong><small>${group.teacher_id?"Assigned teacher":"No teacher selected"}</small></div></td>
            <td><div class="assignment-count"><strong>${assignmentCountText(group.classes.size,"class","classes")}</strong><small title="${attr([...group.classes.values()].join(", "))}">${esc(assignmentNamesPreview(group.classes))}</small></div></td>
            <td><div class="assignment-count"><strong>${assignmentCountText(group.subjects.size,"subject")}</strong><small title="${attr([...group.subjects.values()].join(", "))}">${esc(assignmentNamesPreview(group.subjects))}</small></div></td>
            <td><strong>${group.rows.length}</strong></td>
            <td><div class="assignment-status-stack">
              ${group.active_count?`<span class="status published">${group.active_count} active</span>`:""}
              ${group.inactive_count?`<span class="status withdrawn">${group.inactive_count} inactive</span>`:""}
            </div></td>
            <td><button class="button ghost small" data-manage-assignment-group="${attr(group.key)}">Manage</button></td>
          </tr>`).join(""):`<tr><td colspan="6"><div class="empty">No class-subject assignments configured</div></td></tr>`}
        </tbody></table></div></section>
    </div>`;
  }
  function renderAssessmentTab() {
    const schemes=state.academic.assessment_schemes||[];
    return `<section class="panel"><div class="panel-header"><div><h3>Assessment Schemes</h3><p>Weighted components by academic scope</p></div>
      <button class="button primary small" id="addScheme">Add scheme</button></div>
      <div class="table-wrap"><table><thead><tr><th>Scheme</th><th>Scope</th><th>Components</th><th>Weight</th><th>Status</th><th></th></tr></thead><tbody>
        ${schemes.map(row=>`<tr><td><strong>${esc(row.name)}</strong></td><td>${esc(schemeScope(row))}</td>
          <td>${(row.components||[]).map(c=>`<span class="chip">${esc(c.code)} ${number(c.weight,1)}%</span>`).join(" ")}</td>
          <td><strong>${number(row.total_weight,1)}%</strong></td><td>${row.active?`<span class="status published">Active</span>`:`<span class="status draft">Inactive</span>`}</td>
          <td><button class="button ghost small" data-edit-scheme="${row.id}">Edit</button></td></tr>`).join("")}
      </tbody></table></div></section>`;
  }
  function schemeScope(row) {
    const names=[];
    if(row.academic_year_id)names.push((state.academic.academic_years||[]).find(x=>x.id===row.academic_year_id)?.name);
    if(row.term_id)names.push((state.academic.terms||[]).find(x=>x.id===row.term_id)?.name);
    if(row.class_id)names.push((state.academic.classes||[]).find(x=>x.id===row.class_id)?.name);
    if(row.subject_id)names.push((state.academic.subjects||[]).find(x=>x.id===row.subject_id)?.name);
    return names.filter(Boolean).join(" • ")||"School-wide";
  }
  function renderGradingTab() {
    const scales=state.academic.grading_scales||[];
    return `<section class="panel"><div class="panel-header"><div><h3>Grading Scales</h3><p>Scope-aware grade ranges and points</p></div>
      <button class="button primary small" id="addGrade">Add grade</button></div>
      <div class="table-wrap"><table><thead><tr><th>Grade</th><th>Range</th><th>Remark</th><th>Interpretation</th><th>Point</th><th>Scope</th><th></th></tr></thead><tbody>
        ${scales.map(row=>`<tr><td><strong>${esc(row.grade)}</strong></td><td>${number(row.min_mark,2)}–${number(row.max_mark,2)}</td>
          <td>${esc(row.remark)}</td><td>${esc(row.interpretation||defaultGradingInterpretation(row.grade,row.remark))}</td><td>${number(row.grade_point,2)}</td><td>${esc(gradeScope(row))}</td>
          <td><div class="table-actions"><button class="button ghost small" data-edit-grade="${row.id}">Edit</button>
            <button class="button danger small" data-delete-grade="${row.id}">Remove</button></div></td></tr>`).join("")}
      </tbody></table></div></section>`;
  }
  function gradeScope(row) {
    return [
      (state.academic.academic_years||[]).find(x=>x.id===row.academic_year_id)?.name,
      (state.academic.classes||[]).find(x=>x.id===row.class_id)?.name,
      (state.academic.subjects||[]).find(x=>x.id===row.subject_id)?.name
    ].filter(Boolean).join(" • ")||"School-wide";
  }
  function defaultGradingInterpretation(grade="",remark="") {
    const key=String(remark||"").trim().toLowerCase(),value=String(grade||"").trim();
    if(key==="excellent"||value==="1")return "Outstanding performance. Keep it up!";
    if(key==="very good"||value==="2")return "Well above average. You are doing great!";
    if(key==="good"||value==="3")return "Good achievement. Continue to work hard.";
    if(key==="high average"||value==="4")return "Satisfactory performance. Aim higher.";
    if(key==="average"||value==="5")return "Fair performance. More effort needed.";
    if(key==="low average"||value==="6")return "Below average. Focus and improvement required.";
    if(key==="pass"||value==="7")return "Minimum pass. Consistent effort is essential.";
    if(["weak","week"].includes(key)||value==="8")return "Weak performance. Urgent improvement needed.";
    if(key==="needs improvement"||value==="9")return "Unsatisfactory. Serious improvement is required.";
    return `${remark||"Performance recorded"}. Continue working consistently to improve performance.`;
  }
  function normaliseGradingGuide(guide={}) {
    const rows=(Array.isArray(guide?.rows)?guide.rows:[]).map((row,index)=>({
      ...row,grade:String(row.grade??""),min_mark:Number(row.min_mark??0),max_mark:Number(row.max_mark??0),
      remark:String(row.remark??""),interpretation:String(row.interpretation||defaultGradingInterpretation(row.grade,row.remark)),
      display_order:Number(row.display_order??index+1)
    })).sort((a,b)=>a.display_order-b.display_order||b.min_mark-a.min_mark);
    return {...guide,rows,scope:guide?.scope||{},subject_exceptions:Array.isArray(guide?.subject_exceptions)?guide.subject_exceptions:[]};
  }
  function defaultReportGradingGuide() {
    const rows=[
      ["1",90,100,"Excellent","Outstanding performance. Keep it up!"],
      ["2",80,89,"Very Good","Well above average. You are doing great!"],
      ["3",70,79,"Good","Good achievement. Continue to work hard."],
      ["4",60,69,"High Average","Satisfactory performance. Aim higher."],
      ["5",55,59,"Average","Fair performance. More effort needed."],
      ["6",50,54,"Low Average","Below average. Focus and improvement required."],
      ["7",46,49,"Pass","Minimum pass. Consistent effort is essential."],
      ["8",40,45,"Weak","Weak performance. Urgent improvement needed."],
      ["9",0,39,"Needs improvement","Unsatisfactory. Serious improvement is required."]
    ].map((item,index)=>({grade:item[0],min_mark:item[1],max_mark:item[2],remark:item[3],interpretation:item[4],display_order:index+1}));
    return {version:1,scope:{label:"School-wide default"},rows,subject_exceptions:[]};
  }
  async function enrichReportGradingGuide(editor) {
    if(!editor)return editor;
    try{
      editor.grading_scale=normaliseGradingGuide(await rpc("get_report_grading_guide",{
        target_report_id:editor.report?.id||null,
        target_enrollment_id:editor.report?.id?null:editor.report?.enrollment_id||null,
        target_term_id:editor.report?.id?null:editor.report?.term_id||null
      }));
      editor.grading_scale_error="";
    }catch(error){
      await reportClientError(error,{source:"report_grading_guide",report_id:editor.report?.id||null});
      editor.grading_scale=defaultReportGradingGuide();
      editor.grading_scale_error=friendlyError(error);
    }
    return editor;
  }
  const PROMOTION_ALL_CLASSES="__all_eligible_classes__";
  function promotionCutoffOptions(selected=50) {
    return Array.from({length:21},(_,index)=>40+index).map(score=>`<option value="${score}" ${Number(selected)===score?"selected":""}>${score}%</option>`).join("");
  }
  function orderedActiveClasses() {
    return [...(state.academic?.classes||state.boot?.classes||[])].filter(row=>row.active!==false&&!row.deleted_at)
      .sort((a,b)=>Number(a.level_order||0)-Number(b.level_order||0)||String(a.name||"").localeCompare(String(b.name||""),undefined,{numeric:true}));
  }
  function configuredNextClass(sourceClassId) {
    const classes=orderedActiveClasses(),source=classes.find(row=>row.id===sourceClassId);if(!source)return null;
    return classes.find(row=>Number(row.level_order||0)>Number(source.level_order||0))||null;
  }
  function configuredPromotionMappings() {
    const classes=orderedActiveClasses();
    return classes.map(source=>({source,target:classes.find(row=>Number(row.level_order||0)>Number(source.level_order||0))||null}))
      .filter(mapping=>mapping.target);
  }
  function promotionAcademicYearOrderValue(row) {
    const start=Date.parse(row?.start_date||"");if(Number.isFinite(start))return start;
    const year=String(row?.name||"").match(/(?:19|20)\d{2}/)?.[0];if(year)return Date.UTC(Number(year),0,1);
    const created=Date.parse(row?.created_at||"");return Number.isFinite(created)?created:0;
  }
  function orderedPromotionAcademicYears() {
    return [...(state.academic?.academic_years||[])].filter(row=>!row.deleted_at)
      .sort((a,b)=>promotionAcademicYearOrderValue(a)-promotionAcademicYearOrderValue(b)||String(a.name||"").localeCompare(String(b.name||""),undefined,{numeric:true}));
  }
  function configuredNextAcademicYear(sourceYearId) {
    const years=orderedPromotionAcademicYears(),index=years.findIndex(row=>row.id===sourceYearId);
    return index>=0?years[index+1]||null:null;
  }
  function isTermThreeRecord(record={}) {
    if(Number(record?.term_sequence||0)===3)return true;
    const normalized=String(record?.term_name||record?.name||"").toLowerCase().replace(/[^a-z0-9]+/g,"");
    return ["term3","termthree","thirdterm","3rdterm"].includes(normalized);
  }
  function promotionTargetYearOptions(sourceYearId) {
    const target=configuredNextAcademicYear(sourceYearId);
    return target?`<option value="${attr(target.id)}" selected>${esc(target.name)}</option>`:`<option value="">Create the next academic year first</option>`;
  }
  function promotionSourceClassOptions() {
    const rows=orderedActiveClasses();
    return `<option value="">Select</option><option value="${PROMOTION_ALL_CLASSES}">All eligible classes</option>`+
      rows.map(row=>`<option value="${attr(row.id)}">${esc(row.name)}</option>`).join("");
  }
  function renderPromotionTab() {
    const cutoff=Number(state.boot?.school?.promotion_cutoff_score||50);
    const years=orderedPromotionAcademicYears();
    const sourceYearId=activeYear()?.id||years[0]?.id||"";
    return `<div class="form-stack">
      <section class="panel pad"><div class="page-head"><div><h3>Automatic Promotion Rule</h3><p>Term 3 promotion is determined from each student's overall average across all assigned subjects.</p></div></div>
        <div class="promotion-rule-layout">
          <form id="promotionCutoffForm" class="form-grid promotion-cutoff-form">
            <label class="field"><span>Promotion cutoff score</span><select name="promotion_cutoff_score" required>${promotionCutoffOptions(cutoff)}</select>
              <small>Students with a complete Term 3 average at or above this score pass. The allowed range is 40% through 60%.</small></label>
            <div class="field promotion-setting-action"><span>Academic rule</span><button class="button primary" id="savePromotionCutoff" type="button">Save cutoff score</button></div>
          </form>
          <div class="promotion-rule-card"><strong>Current rule: ${number(cutoff,0)}% pass mark</strong>
            <span>Term 1 and Term 2 do not promote students. In Term 3, the system calculates the arithmetic mean of all subject totals. A student below ${number(cutoff,0)}% is not promoted.</span></div>
        </div>
      </section>
      <section class="panel pad"><div class="page-head"><div><h3>Term 3 Promotion Processing</h3><p>The source year contains the Term 3 assessment. The immediate next academic year is selected automatically. Passing reports become eligible immediately, but the next-year enrolment is created only after Principal approval or publication.</p></div></div>
        <form id="promotionForm" class="form-grid">
          <label class="field"><span>Source academic year</span><select name="source_year" required>${optionList(years,"id","name",sourceYearId)}</select></label>
          <label class="field"><span>Source class</span><select name="source_class" required>${promotionSourceClassOptions()}</select>
            <small>Select one class, or process every class that has a configured next class.</small></label>
          <label class="field"><span>Automatic target academic year</span><select name="target_year" required>${promotionTargetYearOptions(sourceYearId)}</select>
            <small>The immediate next configured academic year is selected automatically.</small></label>
          <label class="field"><span>Automatic target class</span><input id="promotionTargetClassLabel" value="Select a source class" readonly><input type="hidden" name="target_class"></label>
          <div class="full promotion-processing-note" id="promotionProcessingNote">All complete Term 3 records are evaluated. Draft, submitted, and class-reviewed reports remain eligible pending approval; only approved or published reports create next-year enrolments. Returned and withdrawn reports are skipped.</div>
          <div class="full"><button class="button primary" id="runPromotion" type="button">Run automatic promotion</button></div>
        </form>
      </section>
    </div>`;
  }
  function syncPromotionTargetYear() {
    const form=byId("promotionForm");if(!form)return;
    const sourceYearId=form.elements.source_year?.value||"",target=configuredNextAcademicYear(sourceYearId),targetSelect=form.elements.target_year;
    if(targetSelect){
      targetSelect.innerHTML=promotionTargetYearOptions(sourceYearId);
      targetSelect.value=target?.id||"";
      targetSelect.disabled=!target;
    }
    syncPromotionTargetClass();
  }
  function syncPromotionTargetClass() {
    const form=byId("promotionForm");if(!form)return;
    const sourceYearId=form.elements.source_year?.value||"",targetYear=configuredNextAcademicYear(sourceYearId);
    const sourceValue=form.elements.source_class?.value||"",allClasses=sourceValue===PROMOTION_ALL_CLASSES;
    const mappings=allClasses?configuredPromotionMappings():[],target=allClasses?null:configuredNextClass(sourceValue);
    form.elements.target_class.value=target?.id||"";
    const label=byId("promotionTargetClassLabel"),button=byId("runPromotion"),note=byId("promotionProcessingNote");
    const validYear=Boolean(targetYear&&form.elements.target_year?.value===targetYear.id);
    if(!validYear){
      if(label)label.value="Next academic year required";
      if(button){button.disabled=true;button.textContent=allClasses?"Run all-class promotion":"Run automatic promotion"}
      if(note)note.textContent="Create the immediate next academic year before running Term 3 promotion.";
      return;
    }
    if(allClasses){
      if(label)label.value=mappings.length?`Each eligible class → its next class (${mappings.length} mappings)`:"No eligible class mappings";
      if(button){button.disabled=!mappings.length;button.textContent="Run all-class promotion"}
      if(note)note.textContent=mappings.length
        ?`Source-year Term 3 results will be evaluated for ${targetYear.name}. Approved or published passing reports create next-year enrolments; earlier workflow states remain eligible pending approval. One operation will process ${mappings.length} class mappings. The final class, and any class without a higher configured class, will be skipped.`
        :"No active class currently has a higher configured class.";
      return;
    }
    if(label)label.value=target?.name||(sourceValue?"No next class configured":"Select a source class");
    if(button){button.disabled=!target;button.textContent="Run automatic promotion"}
    if(note)note.textContent=target
      ?`Passing students are eligible for ${target.name}. The ${targetYear.name} enrolment is created only after Principal approval or publication; students below the cutoff remain unpromoted.`
      :(sourceValue?"The selected class is the final configured class or has no higher class level.":"Complete Term 3 records are evaluated under the approval-gated promotion rule. Returned and withdrawn reports are skipped.");
  }
  function bindAcademicTabEvents() {
    byId("addYear")?.addEventListener("click",()=>openYearEditor());
    $$("[data-edit-year]").forEach(b=>b.onclick=()=>openYearEditor(b.dataset.editYear));
    $$("[data-remove-year]").forEach(b=>b.onclick=()=>removeAcademicEntity("academic_year",b.dataset.removeYear));
    byId("addTerm")?.addEventListener("click",()=>openTermEditor());
    $$("[data-edit-term]").forEach(b=>b.onclick=()=>openTermEditor(b.dataset.editTerm));
    $$("[data-remove-term]").forEach(b=>b.onclick=()=>removeAcademicEntity("term",b.dataset.removeTerm));
    $$("[data-set-active]").forEach(b=>b.onclick=async()=>{
      const [yearId,termId]=b.dataset.setActive.split("|");
      if(await confirmAction("Activate Academic Period","This term will become the current reporting period.","Activate")){
        await run(()=>rpc("set_active_period",{target_academic_year_id:yearId,target_term_id:termId}),{success:"Academic period activated"});
        state.boot=await rpc("get_bootstrap_data");await renderAcademics(state.viewToken,true);
      }
    });
    byId("addClass")?.addEventListener("click",()=>openClassEditor());
    $$("[data-edit-class]").forEach(b=>b.onclick=()=>openClassEditor(b.dataset.editClass));
    $$("[data-remove-class]").forEach(b=>b.onclick=()=>removeAcademicEntity("class",b.dataset.removeClass));
    byId("addSubject")?.addEventListener("click",()=>openSubjectEditor());
    $$("[data-edit-subject]").forEach(b=>b.onclick=()=>openSubjectEditor(b.dataset.editSubject));
    $$("[data-remove-subject]").forEach(b=>b.onclick=()=>removeAcademicEntity("subject",b.dataset.removeSubject));
    byId("addAssignment")?.addEventListener("click",()=>openAssignmentEditor());
    $$("[data-manage-assignment-group]").forEach(button=>button.onclick=()=>openAssignmentGroupManager(button.dataset.manageAssignmentGroup));
    byId("addScheme")?.addEventListener("click",()=>openSchemeEditor());
    $$("[data-edit-scheme]").forEach(b=>b.onclick=()=>openSchemeEditor(b.dataset.editScheme));
    byId("addGrade")?.addEventListener("click",()=>openGradeEditor());
    $$("[data-edit-grade]").forEach(b=>b.onclick=()=>openGradeEditor(b.dataset.editGrade));
    $$("[data-delete-grade]").forEach(b=>b.onclick=()=>removeGrade(b.dataset.deleteGrade));
    byId("savePromotionCutoff")?.addEventListener("click",savePromotionCutoff);
    byId("promotionForm")?.elements.source_year?.addEventListener("change",syncPromotionTargetYear);
    byId("promotionForm")?.elements.source_class?.addEventListener("change",syncPromotionTargetClass);
    byId("runPromotion")?.addEventListener("click",runPromotion);
    syncPromotionTargetYear();
  }
  async function removeAcademicEntity(type,id) {
    const labels={academic_year:"Academic year",term:"Term",class:"Class",subject:"Subject",assignment:"Subject assignment"};
    const messages={academic_year:"The academic year and its terms will be removed from current configuration. Published historical reports remain preserved.",term:"The term will be removed from current configuration. Published historical reports remain preserved."};
    const ok=await confirmAction(`Remove ${labels[type]||"Record"}`,messages[type]||"The record will be archived while historical academic results remain preserved.","Remove",true);
    if(!ok)return;
    try{
      await rpc("archive_academic_entity",{entity_type:type,target_id:id,reason_text:`${labels[type]||"Academic record"} removed`});
      toast(`${labels[type]||"Academic record"} removed`);await refreshAcademic();
    }catch(error){toast("Record not removed",friendlyError(error),"error",6500)}
  }

  async function deleteClassSubjectAssignment(id) {
    const row=(state.academic?.class_subjects||[]).find(item=>item.id===id);if(!row)return;
    const label=[row.class_name,row.subject_name].filter(Boolean).join(" • ")||"this assignment";
    const ok=await confirmAction("Delete Subject Assignment",`Permanently delete ${label}? This cannot be undone.`,"Delete",true);
    if(!ok)return;
    try{
      await rpc("delete_class_subject_assignment",{target_id:id,reason_text:"Class subject assignment permanently deleted"});
      toast("Subject assignment deleted");await refreshAcademic();
    }catch(error){toast("Assignment not deleted",friendlyError(error),"error",6500)}
  }

  async function refreshAcademic() {
    state.workspace=null;state.academic=await rpc("get_academic_configuration");
    state.boot=await rpc("get_bootstrap_data");
    renderAcademicTab();
  }
  function openYearEditor(id=null) {
    const row=(state.academic.academic_years||[]).find(x=>x.id===id)||{};
    modal(id?"Edit Academic Year":"Add Academic Year","",`<form id="entityForm" class="form-grid">
      <label class="field full"><span>Name</span><input name="name" value="${attr(row.name||"")}" required></label>
      <label class="field"><span>Start date</span><input type="date" name="start_date" value="${attr(row.start_date||"")}"></label>
      <label class="field"><span>End date</span><input type="date" name="end_date" value="${attr(row.end_date||"")}"></label>
    </form>`,`<button class="button ghost" id="entityCancel" type="button">Cancel</button><button class="button primary" id="entitySave" type="button">Save</button>`,"small");
    byId("entityCancel").onclick=closeModal;
    byId("entitySave").onclick=()=>saveEntity("academic_years",id);
  }
  function openTermEditor(id=null) {
    const row=(state.academic.terms||[]).find(x=>x.id===id)||{};
    modal(id?"Edit Term":"Add Term","",`<form id="entityForm" class="form-grid">
      <label class="field full"><span>Academic year</span><select name="academic_year_id" required>${optionList(state.academic.academic_years||[],"id","name",row.academic_year_id||activeYear()?.id)}</select></label>
      <label class="field"><span>Name</span><input name="name" value="${attr(row.name||"")}" required></label>
      <label class="field"><span>Sequence</span><input type="number" min="1" max="6" name="sequence" value="${attr(row.sequence||1)}" required></label>
      <label class="field"><span>Start date</span><input type="date" name="start_date" value="${attr(row.start_date||"")}"></label>
      <label class="field"><span>End date</span><input type="date" name="end_date" value="${attr(row.end_date||"")}"></label>
      <label class="field full"><span>Next-term reopening date</span><input type="date" name="next_term_begins" value="${attr(row.next_term_begins||"")}"><small>This date is printed on every applicable report card. It must be after the current term end date.</small></label>
    </form>`,`<button class="button ghost" id="entityCancel" type="button">Cancel</button><button class="button primary" id="entitySave" type="button">Save</button>`,"small");
    byId("entityCancel").onclick=closeModal;byId("entitySave").onclick=()=>saveEntity("terms",id);
  }
  function openClassEditor(id=null) {
    const row=(state.academic.classes||[]).find(x=>x.id===id)||{};
    const teacherRecords=(state.academic.teacher_records||[]).filter(teacher=>teacher.active!==false);
    const selectedTeacherRecordId=row.class_teacher_record_id
      ||teacherRecords.find(teacher=>teacher.profile_id&&teacher.profile_id===row.class_teacher_id)?.id
      ||"";
    modal(id?"Edit Class":"Add Class","",`<form id="entityForm" class="form-grid">
      <label class="field"><span>Name</span><input name="name" value="${attr(row.name||"")}" required></label>
      <label class="field"><span>Level order</span><input type="number" name="level_order" value="${attr(row.level_order||0)}"></label>
      <label class="field full"><span>Class teacher</span><select name="class_teacher_record_id">${optionList(teacherRecords,"id","label",selectedTeacherRecordId,"Unassigned")}</select>
        <small class="help-text">All active teacher records are listed. A teacher without a linked account can be assigned now; portal access begins after the account is linked.</small>
      </label>
      <label class="check-field full"><input type="checkbox" name="active" ${row.active!==false?"checked":""}><span>Active class</span></label>
    </form>`,`<button class="button ghost" id="entityCancel" type="button">Cancel</button><button class="button primary" id="entitySave" type="button">Save</button>`,"small");
    byId("entityCancel").onclick=closeModal;byId("entitySave").onclick=()=>saveEntity("classes",id);
  }
  function openSubjectEditor(id=null) {
    const row=(state.academic.subjects||[]).find(x=>x.id===id)||{};
    modal(id?"Edit Subject":"Add Subject",id?"The unique subject code remains permanent.":"The code is generated automatically from the subject name.",`<form id="entityForm" class="form-grid">
      <label class="field"><span>Subject name</span><input name="name" value="${attr(row.name||"")}" required></label>
      <label class="field"><span>Unique code</span><input name="code" value="${attr(row.code||"")}" placeholder="Generated automatically" readonly></label>
      <label class="field"><span>Display order</span><input type="number" name="display_order" value="${attr(row.display_order||0)}"></label>
      <label class="check-field"><input type="checkbox" name="active" ${row.active!==false?"checked":""}><span>Active subject</span></label>
    </form>`,`<button class="button ghost" id="entityCancel" type="button">Cancel</button><button class="button primary" id="entitySave" type="button">Save</button>`,"small");
    const form=byId("entityForm"),nameInput=form.elements.name,codeInput=form.elements.code;
    if(!id){
      let timer;const generate=async()=>{const name=nameInput.value.trim();if(!name){codeInput.value="";return}try{codeInput.value=await rpc("generate_subject_code",{subject_name:name,exclude_subject_id:null})}catch(_){codeInput.value=""}};
      nameInput.addEventListener("input",()=>{clearTimeout(timer);codeInput.value="";codeInput.placeholder=`${subjectCodePrefix(nameInput.value)}####`;timer=setTimeout(generate,550)});
      nameInput.addEventListener("blur",generate);
    }
    byId("entityCancel").onclick=closeModal;byId("entitySave").onclick=()=>saveEntity("subjects",id);
  }
  function subjectCodePrefix(name) {
    const words=String(name||"").toUpperCase().replace(/[^A-Z0-9 ]/g," ").trim().split(/\s+/).filter(Boolean);
    const meaningful=words.filter(word=>!["AND","OF","THE","FOR","IN","TO"].includes(word)),source=meaningful.length?meaningful:words;
    if(!source.length)return "SUB";return source.length===1?source[0].slice(0,3):source.slice(0,4).map(word=>word[0]).join("");
  }
  async function saveEntity(table,id) {
    const form=byId("entityForm"),values=formObject(form),button=byId("entitySave");if(!form?.reportValidity())return;button.disabled=true;let saved=false;
    try {
      if(table==="terms"&&values.next_term_begins&&values.end_date&&values.next_term_begins<=values.end_date){
        throw new Error("Next-term reopening date must be after the current term end date");
      }
      const numeric=["sequence","level_order","display_order"];
      numeric.forEach(key=>{if(key in values)values[key]=Number(values[key]||0)});
      ["start_date","end_date","next_term_begins","class_teacher_id","class_teacher_record_id"].forEach(key=>{if(key in values&&!values[key])values[key]=null});
      if("active" in form.elements)values.active=form.elements.active.checked;
      await rpc("save_academic_entity",{entity_type:table,payload:{...values,id:id||null,reason:id?"Academic record updated":"Academic record created"}});
      saved=true;state.workspace=null;closeModal();toast("Academic record saved");
      try{await refreshAcademic()}catch(refreshError){await reportClientError(refreshError,{source:"academic_save",entity_type:table,stage:"refresh"});toast("Record saved","Reload the page to display the latest record.","warning",6500)}
    } catch(error){await reportClientError(error,{source:"academic_save",entity_type:table,stage:saved?"refresh":"record"});toast(saved?"Record saved":"Record not saved",saved?"Reload the page to display the latest record.":friendlyError(error),saved?"warning":"error",6500)}
    finally{button.disabled=false}
  }
  function multiSelectSummary(items,selected,emptyLabel) {
    const chosen=items.filter(item=>selected.has(item.id));
    if(!chosen.length)return emptyLabel;
    if(chosen.length===1)return chosen[0].name;
    if(chosen.length===2)return `${chosen[0].name}, ${chosen[1].name}`;
    return `${chosen.length} selected`;
  }

  function renderVerticalChecklistDropdown({
    rootId,label,items,selected,emptyLabel="Select",allLabel="",showCode=false,onChange
  }) {
    const root=byId(rootId);if(!root)return;
    const allSelected=items.length>0&&items.every(item=>selected.has(item.id));
    root.innerHTML=`<details class="vertical-check-dropdown">
      <summary><span class="vertical-check-title">${esc(label)}</span><span class="vertical-check-value">${esc(multiSelectSummary(items,selected,emptyLabel))}</span></summary>
      <div class="vertical-check-panel">
        ${allLabel?`<label class="vertical-check-option all-option"><span>${esc(allLabel)}</span><input type="checkbox" data-check-all ${allSelected?"checked":""}></label>`:""}
        ${items.map(item=>`<label class="vertical-check-option">
          <span><strong>${esc(item.name)}</strong>${showCode&&item.code?`<small>${esc(item.code)}</small>`:""}</span>
          <input type="checkbox" data-check-id="${attr(item.id)}" ${selected.has(item.id)?"checked":""}>
        </label>`).join("")||`<div class="vertical-check-empty">No records available</div>`}
      </div>
    </details>`;
    $$("[data-check-id]",root).forEach(input=>input.onchange=()=>{
      if(input.checked)selected.add(input.dataset.checkId);else selected.delete(input.dataset.checkId);
      onChange?.();
    });
    const allInput=root.querySelector("[data-check-all]");
    if(allInput)allInput.onchange=()=>{
      if(allInput.checked)items.forEach(item=>selected.add(item.id));
      else selected.clear();
      onChange?.();
    };
  }

  function classSubjectPairKey(classId,subjectId){return `${classId}|${subjectId}`}

  function renderAssignmentVerticalSelectors() {
    const classes=(state.academic.classes||[]).filter(item=>item.active!==false);
    const subjects=(state.academic.subjects||[]).filter(item=>item.active!==false);
    renderVerticalChecklistDropdown({
      rootId:"assignmentClassDropdown",
      label:"Class",
      items:classes,
      selected:state.assignmentClassSelections,
      emptyLabel:"Select class",
      onChange:renderAssignmentVerticalSelectors
    });
    renderVerticalChecklistDropdown({
      rootId:"assignmentSubjectDropdown",
      label:"Subject",
      items:subjects,
      selected:state.assignmentSubjectSelections,
      emptyLabel:"Select subject",
      allLabel:"All subjects",
      showCode:true,
      onChange:renderAssignmentVerticalSelectors
    });
    const count=state.assignmentClassSelections.size*state.assignmentSubjectSelections.size;
    const summary=byId("assignmentCombinationSummary");
    if(summary)summary.textContent=count
      ?`${count} class-subject assignment${count===1?"":"s"} will be saved.`
      :"Select one or more classes and one or more subjects.";
  }

  function openAssignmentEditor(id=null,teacherId="") {
    const row=(state.academic.class_subjects||[]).find(x=>x.id===id)||{};
    const teacherProfiles=(state.academic.profiles||[]).filter(profile=>["class_teacher","subject_teacher"].includes(profile.role));
    state.assignmentClassSelections=new Set(row.class_id?[row.class_id]:[]);
    state.assignmentSubjectSelections=new Set(row.subject_id?[row.subject_id]:[]);
    modal(id?"Edit Subject Assignment":"Assign Subjects","Select one or more classes and subjects for the selected teacher.",`<form id="entityForm" class="form-stack">
      <label class="field"><span>Teacher</span><select name="teacher_id" required>${optionList(teacherProfiles,"id","full_name",row.teacher_id||teacherId,"Select teacher")}</select></label>
      <div class="independent-check-grid">
        <div id="assignmentClassDropdown"></div>
        <div id="assignmentSubjectDropdown"></div>
      </div>
      <p class="help-text" id="assignmentCombinationSummary"></p>
      <p class="help-text">For different subject groups, save one group first, then use Assign more for the next class range.</p>
      <label class="check-field"><input type="checkbox" name="active" ${row.active!==false?"checked":""}><span>Active assignments</span></label>
    </form>`,`<button class="button ghost" id="entityCancel" type="button">Cancel</button><button class="button primary" id="entitySave" type="button">Save assignments</button>`,"wide");
    renderAssignmentVerticalSelectors();
    byId("entityCancel").onclick=closeModal;
    byId("entitySave").onclick=async()=>{
      const form=byId("entityForm"),v=formObject(form),button=byId("entitySave");if(!form?.reportValidity())return;
      const classIds=[...state.assignmentClassSelections];
      const subjectIds=[...state.assignmentSubjectSelections];
      if(!classIds.length){toast("Select at least one class","","error");return}
      if(!subjectIds.length){toast("Select at least one subject","","error");return}
      const selections=classIds.flatMap(class_id=>subjectIds.map(subject_id=>({class_id,subject_id})));
      button.disabled=true;button.textContent="Saving";let saved=false;
      try{
        await rpc("save_class_subject_assignments_batch",{payload:{id:id||null,teacher_id:v.teacher_id||null,active:form.elements.active.checked,selections,
          reason:id?"Class-subject assignments updated":"Class-subject assignments created"}});
        saved=true;state.workspace=null;closeModal();toast(`${selections.length} assignment${selections.length===1?"":"s"} saved`);
        try{await refreshAcademic()}catch(refreshError){await reportClientError(refreshError,{source:"assignment_batch_save",stage:"refresh"});toast("Assignments saved","Reload to display the latest assignments.","warning",6500)}
      }catch(error){await reportClientError(error,{source:"assignment_batch_save",stage:saved?"refresh":"record"});toast(saved?"Assignments saved":"Assignments not saved",saved?"Reload to display the latest assignments.":friendlyError(error),saved?"warning":"error",6500)}
      finally{button.disabled=false;button.textContent="Save assignments"}
    };
  }
  function openSchemeEditor(id=null) {
    const row=(state.academic.assessment_schemes||[]).find(x=>x.id===id)||{components:[
      {name:"Continuous Assessment",code:"CA",maximum_score:30,weight:30,display_order:1,required:true},
      {name:"End of Term Examination",code:"EXAM",maximum_score:70,weight:70,display_order:2,required:true}
    ]};
    modal(id?"Edit Assessment Scheme":"Add Assessment Scheme",schemeScope(row),`<form id="schemeForm" class="form-stack">
      <div class="form-grid three">
        <input type="hidden" name="id" value="${attr(row.id||"")}">
        <label class="field"><span>Name</span><input name="name" value="${attr(row.name||"")}" required></label>
        <label class="field"><span>Academic year</span><select name="academic_year_id">${optionList(state.academic.academic_years||[],"id","name",row.academic_year_id,"All years")}</select></label>
        <label class="field"><span>Term</span><select name="term_id">${optionList(state.academic.terms||[],"id","name",row.term_id,"All terms")}</select></label>
        <label class="field"><span>Class</span><select name="class_id">${optionList(state.academic.classes||[],"id","name",row.class_id,"All classes")}</select></label>
        <label class="field"><span>Subject</span><select name="subject_id">${optionList(state.academic.subjects||[],"id","name",row.subject_id,"All subjects")}</select></label>
        <label class="check-field"><input type="checkbox" name="active" ${row.active!==false?"checked":""}><span>Active scheme</span></label>
      </div>
      <div class="section-title"><h4>Components</h4><button class="button secondary small" id="addComponent" type="button">Add component</button></div>
      <div id="componentRows"></div>
    </form>`,`<button class="button ghost" id="schemeCancel" type="button">Cancel</button><button class="button primary" id="schemeSave" type="button">Save scheme</button>`,"wide");
    state.schemeComponents=(row.components||[]).map(x=>({...x}));
    renderComponentRows();
    byId("addComponent").onclick=()=>{state.schemeComponents.push({name:"",code:"",maximum_score:100,weight:0,display_order:state.schemeComponents.length+1,required:true});renderComponentRows()};
    byId("schemeCancel").onclick=closeModal;byId("schemeSave").onclick=saveScheme;
  }
  function renderComponentRows() {
    const root=byId("componentRows");if(!root)return;
    root.innerHTML=state.schemeComponents.map((c,i)=>`<div class="form-grid three component-row" data-index="${i}" style="margin-bottom:12px">
      <label class="field"><span>Component name</span><input data-key="name" value="${attr(c.name||"")}" required></label>
      <label class="field"><span>Code</span><input data-key="code" value="${attr(c.code||"")}" required></label>
      <label class="field"><span>Maximum score</span><input data-key="maximum_score" type="number" min=".01" step=".01" value="${attr(c.maximum_score||0)}" required></label>
      <label class="field"><span>Weight (%)</span><input data-key="weight" type="number" min=".001" max="100" step=".001" value="${attr(c.weight||0)}" required></label>
      <label class="field"><span>Display order</span><input data-key="display_order" type="number" value="${attr(c.display_order||i+1)}"></label>
      <div class="button-row"><label class="check-field"><input data-key="required" type="checkbox" ${c.required!==false?"checked":""}><span>Required</span></label>
        <button class="button danger small" type="button" data-remove-component="${i}">Remove</button></div>
    </div>`).join("");
    $$(".component-row",root).forEach(row=>$$("[data-key]",row).forEach(input=>input.oninput=()=>{
      const item=state.schemeComponents[Number(row.dataset.index)],key=input.dataset.key;
      item[key]=input.type==="checkbox"?input.checked:input.type==="number"?Number(input.value):input.value;
    }));
    $$("[data-remove-component]",root).forEach(button=>button.onclick=()=>{state.schemeComponents.splice(Number(button.dataset.removeComponent),1);renderComponentRows()});
  }
  async function saveScheme() {
    const form=byId("schemeForm"),v=formObject(form),button=byId("schemeSave");if(!form?.reportValidity())return;button.disabled=true;let saved=false;
    try{
      const payload={id:v.id,name:v.name,academic_year_id:v.academic_year_id,term_id:v.term_id,class_id:v.class_id,subject_id:v.subject_id,
        active:form.elements.active.checked,components:state.schemeComponents,reason:v.id?"Assessment scheme updated":"Assessment scheme created"};
      await rpc("save_assessment_scheme",{payload});saved=true;closeModal();toast("Assessment scheme saved");
      try{await refreshAcademic()}catch(refreshError){await reportClientError(refreshError,{source:"assessment_scheme_save",stage:"refresh"});toast("Scheme saved","Reload the page to display the latest scheme.","warning",6500)}
    }catch(error){await reportClientError(error,{source:"assessment_scheme_save",stage:saved?"refresh":"record"});toast(saved?"Scheme saved":"Scheme not saved",saved?"Reload the page to display the latest scheme.":friendlyError(error),saved?"warning":"error",6500)}finally{button.disabled=false}
  }
  function openGradeEditor(id=null) {
    const row=(state.academic.grading_scales||[]).find(x=>x.id===id)||{};
    modal(id?"Edit Grade":"Add Grade","",`<form id="gradeForm" class="form-grid three">
      <label class="field"><span>Grade</span><input name="grade" value="${attr(row.grade||"")}" required></label>
      <label class="field"><span>Minimum mark</span><input type="number" min="0" max="100" step=".01" name="min_mark" value="${attr(row.min_mark??"")}" required></label>
      <label class="field"><span>Maximum mark</span><input type="number" min="0" max="100" step=".01" name="max_mark" value="${attr(row.max_mark??"")}" required></label>
      <label class="field"><span>Remark</span><input name="remark" value="${attr(row.remark||"")}" required></label>
      <label class="field full"><span>Interpretation guide</span><textarea name="interpretation" maxlength="180" required>${esc(row.interpretation||defaultGradingInterpretation(row.grade,row.remark))}</textarea><small>This text is printed dynamically on new and formally reopened reports.</small></label>
      <label class="field"><span>Grade point</span><input type="number" step=".01" name="grade_point" value="${attr(row.grade_point||0)}"></label>
      <label class="field"><span>Display order</span><input type="number" name="display_order" value="${attr(row.display_order||0)}"></label>
      <label class="field"><span>Academic year</span><select name="academic_year_id">${optionList(state.academic.academic_years||[],"id","name",row.academic_year_id,"All years")}</select></label>
      <label class="field"><span>Class</span><select name="class_id">${optionList(state.academic.classes||[],"id","name",row.class_id,"All classes")}</select></label>
      <label class="field"><span>Subject</span><select name="subject_id">${optionList(state.academic.subjects||[],"id","name",row.subject_id,"All subjects")}</select></label>
    </form>`,`<button class="button ghost" id="gradeCancel" type="button">Cancel</button><button class="button primary" id="gradeSave" type="button">Save</button>`,"wide");
    byId("gradeCancel").onclick=closeModal;
    byId("gradeSave").onclick=async()=>{
      const form=byId("gradeForm");if(!form?.reportValidity())return;
      const v=formObject(form),record={id:id||null,grade:v.grade,remark:v.remark,interpretation:v.interpretation,min_mark:Number(v.min_mark),max_mark:Number(v.max_mark),
        grade_point:Number(v.grade_point||0),display_order:Number(v.display_order||0),academic_year_id:v.academic_year_id||null,class_id:v.class_id||null,subject_id:v.subject_id||null,reason:id?"Grading scale updated":"Grading scale created"};
      const button=byId("gradeSave");button.disabled=true;
      let saved=false;
      try{await rpc("save_grading_scale",{payload:record});saved=true;closeModal();toast("Grading scale saved");
        try{await refreshAcademic()}catch(refreshError){await reportClientError(refreshError,{source:"grading_scale_save",stage:"refresh"});toast("Grade saved","Reload the page to display the latest grading scale.","warning",6500)}}
      catch(error){await reportClientError(error,{source:"grading_scale_save",stage:saved?"refresh":"record"});toast(saved?"Grade saved":"Grade not saved",saved?"Reload the page to display the latest grading scale.":friendlyError(error),saved?"warning":"error",6500)}finally{button.disabled=false}
    };
  }
  async function removeGrade(id) {
    if(!await confirmAction("Remove Grade","The grade will no longer be used for future calculations.","Remove",true))return;
    await run(()=>rpc("archive_grading_scale",{target_grade_id:id,reason_text:"Grading scale removed"}),{success:"Grade removed"});
    await refreshAcademic();
  }
  async function savePromotionCutoff() {
    const form=byId("promotionCutoffForm"),score=Number(form?.elements.promotion_cutoff_score?.value||0),button=byId("savePromotionCutoff");
    if(!Number.isInteger(score)||score<40||score>60){toast("Cutoff not saved","Choose a whole-number score from 40 through 60.","error");return}
    if(button)button.disabled=true;
    try{
      const result=await rpc("save_promotion_cutoff",{target_score:score});
      state.boot.school={...(state.boot.school||{}),promotion_cutoff_score:Number(result.promotion_cutoff_score||score)};
      toast("Promotion cutoff saved",`${score}% will be used for Term 3 automatic promotion. ${number(result.reports_recalculated||0)} existing Term 3 reports were recalculated.`);
      renderAcademicTab();
    }catch(error){toast("Cutoff not saved",friendlyError(error),"error",6500)}finally{if(button)button.disabled=false}
  }
  async function runPromotion() {
    const form=byId("promotionForm"),v=formObject(form),allClasses=v.source_class===PROMOTION_ALL_CLASSES;
    if(!v.source_year||!v.source_class)return;
    const expectedTargetYear=configuredNextAcademicYear(v.source_year);
    if(!expectedTargetYear){toast("Promotion not started","Create the immediate next academic year first.","error",6500);syncPromotionTargetYear();return}
    if(v.target_year!==expectedTargetYear.id){
      form.elements.target_year.value=expectedTargetYear.id;
      toast("Target year corrected",`${expectedTargetYear.name} is the automatic next academic year.`,"warning",5000);
      v.target_year=expectedTargetYear.id;
    }
    const cutoff=Number(state.boot?.school?.promotion_cutoff_score||50),button=byId("runPromotion");
    if(allClasses){
      const mappings=configuredPromotionMappings();if(!mappings.length)return;
      if(!await confirmAction("Run All-Class Automatic Promotion",`This single operation will process ${mappings.length} eligible class mappings into ${expectedTargetYear.name}. Complete Term 3 reports with an average of ${cutoff}% or higher will be evaluated. Next-year enrolments are created only for approved or published reports; earlier workflow states remain eligible pending approval.`,"Run all classes"))return;
      if(button)button.disabled=true;
      try{
        const result=await run(()=>rpc("bulk_promote_all_classes",{source_academic_year_id:v.source_year,target_academic_year_id:v.target_year}),{success:"All-class automatic promotion completed"});
        const targetName=result.target_academic_year_name||expectedTargetYear.name;
        toast("All-class promotion result",`${number(result.classes_processed||0)} class mappings processed into ${targetName} • ${number(result.promoted||0)} promoted • ${number(result.eligible_pending_approval||0)} eligible pending approval • ${number(result.not_promoted||0)} not promoted • ${number(result.incomplete||0)} incomplete${number(result.skipped_status||0)?` • ${number(result.skipped_status||0)} returned/withdrawn skipped`:""}`);
      }finally{syncPromotionTargetYear()}
      return;
    }
    const target=configuredNextClass(v.source_class);
    if(!v.target_class||!target)return;
    if(!await confirmAction("Run Automatic Promotion",`Complete Term 3 reports with an average of ${cutoff}% or higher will be evaluated for ${target.name}. The next-year enrolment is created only after Principal approval or publication.`,"Run promotion"))return;
    if(button)button.disabled=true;
    try{
      const result=await run(()=>rpc("bulk_promote_class",{source_academic_year_id:v.source_year,source_class_id:v.source_class,
        target_academic_year_id:v.target_year,target_class_id:v.target_class}),{success:"Automatic promotion completed"});
      const targetName=result.target_academic_year_name||expectedTargetYear.name;
      toast("Promotion result",`${number(result.promoted||0)} promoted into ${targetName} • ${number(result.eligible_pending_approval||0)} eligible pending approval • ${number(result.not_promoted||0)} not promoted • ${number(result.incomplete||0)} incomplete${number(result.skipped_status||0)?` • ${number(result.skipped_status||0)} returned/withdrawn skipped`:""}`);
    }finally{syncPromotionTargetYear()}
  }


  async function renderReports(token) {
    state.reportEditor=null;
    const [visibleClasses,emergencyDelegations]=await Promise.all([visibleClassesForCurrentRole(),loadMyEmergencyDelegations(true)]);
    if(token!==state.viewToken)return;
    if(state.reportClassFilter&&!visibleClasses.some(item=>item.id===state.reportClassFilter))state.reportClassFilter="";
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Report Cards</h3><p>Transactional assessment, review, approval, and publication</p></div>
        <div class="page-actions">
          ${!isConnectivityLimited()&&can("import_scores")?`<button class="button outline" id="scoreImport">Import scores</button>`:""}
          ${!isConnectivityLimited()?`<button class="button outline" id="manualReportTemplate">Manual template</button><button class="button outline" id="reportExport">Export list</button>`:""}
          ${!isConnectivityLimited()&&canBulkDownloadPublishedReports()?`<button class="button secondary" id="reportBulkDownload">Bulk class PDFs</button>`:""}
          ${!isConnectivityLimited()&&can("bulk_submit_reports")?`<button class="button secondary" id="reportBulkSubmit">Submit class reports</button>`:""}
          ${!isConnectivityLimited()&&can("bulk_approve_reports")?`<button class="button success" id="reportBulkApprove">Approve class reports</button>`:""}
          ${!isConnectivityLimited()&&can("bulk_publish_reports")?`<button class="button success" id="reportBulkPublish">Publish class reports</button>`:""}
          ${!isConnectivityLimited()&&can("create_reports")?`<button class="button primary" id="reportNew">New report</button>`:""}
        </div></div>
      ${emergencyDelegationBannerHtml(emergencyDelegations)}
      <section class="panel">
        <div class="toolbar">
          <label class="search"><input id="reportSearch" type="search" placeholder="Search student or report number"></label>
          <select id="reportTerm">${optionList(state.boot.terms||[],"id","name",activeTerm()?.id,"All terms")}</select>
          <select id="reportClass">${optionList(visibleClasses,"id","name",state.reportClassFilter||"",["class_teacher","subject_teacher"].includes(role())?"All assigned classes":"All classes")}</select>
          <select id="reportStatus"><option value="">All statuses</option>
            ${["draft","submitted","class_reviewed","approved","published","returned","withdrawn"].map(v=>`<option value="${v}">${v.replaceAll("_"," ")}</option>`).join("")}</select>
        </div>
        <div id="reportResults"><div class="empty">Loading report cards</div></div>
      </section>`;
    byId("reportNew")?.addEventListener("click",openNewReportPicker);
    byId("scoreImport")?.addEventListener("click",openScoreImport);
    byId("manualReportTemplate")?.addEventListener("click",openManualReportTemplate);
    byId("reportExport")?.addEventListener("click",exportReportList);
    byId("reportBulkDownload")?.addEventListener("click",openBulkPublishedReportPackage);
    byId("reportBulkSubmit")?.addEventListener("click",()=>requestBulkReportTransition("submitted"));
    byId("reportBulkApprove")?.addEventListener("click",()=>requestBulkReportTransition("approved"));
    byId("reportBulkPublish")?.addEventListener("click",()=>requestBulkReportTransition("published"));
    let timer;
    byId("reportSearch").oninput=()=>{clearTimeout(timer);timer=setTimeout(()=>{state.reportPage=1;loadReportPage(token)},250)};
    ["reportTerm","reportClass","reportStatus"].forEach(id=>{if(byId(id))byId(id).onchange=()=>{state.reportPage=1;loadReportPage(token)}});
    await loadReportPage(token);
  }
  async function loadReportPage(token=state.viewToken) {
    const root=byId("reportResults");if(!root)return;
    root.innerHTML=`<div class="empty">Loading report cards</div>`;
    const args={
      target_term_id:byId("reportTerm")?.value||null,target_class_id:byId("reportClass")?.value||null,
      target_status:byId("reportStatus")?.value||null,search_text:byId("reportSearch")?.value.trim()||"",
      archive_filter:"active",page_number:state.reportPage,page_size:CONFIG.pageSize
    };
    const data=await cacheableRpc("report-list","list_report_cards_v6",args,JSON.stringify(args));
    if(token!==state.viewToken||!byId("reportResults"))return;
    root.innerHTML=reportTable(data.rows||[],false,true)+pagination(data.total,data.page,data.page_size,"report");
    $$("[data-report-id]",root).forEach(btn=>btn.onclick=()=>openReportEditor(btn.dataset.reportId));
    $$("[data-report-archive]",root).forEach(btn=>btn.onclick=()=>archiveReportCard(btn.dataset.reportArchive));
    bindPagination("report",data);
  }
  function bulkReportWorkflowDefinition(targetStatus) {
    return {
      submitted:{title:"Submit Class Reports",verb:"submit",past:"submitted",button:"Submit all eligible reports",permission:"bulk_submit_reports",source:"draft or returned"},
      approved:{title:"Approve Class Reports",verb:"approve",past:"approved",button:"Approve all eligible reports",permission:"bulk_approve_reports",source:"submitted"},
      published:{title:"Publish Class Reports",verb:"publish",past:"published",button:"Publish all approved reports",permission:"bulk_publish_reports",source:"approved"}
    }[targetStatus]||null;
  }
  async function storeBulkPublishedReportPdfs(reportIds=[]) {
    const ids=[...new Set((reportIds||[]).filter(Boolean))];
    if(!ids.length)return {created:0,failed:0};
    modal("Creating Official PDFs","Published report records are secure while the latest official PDF files are generated.",`
      <div class="template-information"><strong id="bulkPublishPdfHeading">Preparing official PDFs</strong><span id="bulkPublishPdfProgress">0 of ${ids.length} completed</span></div>`,
      `<button class="button ghost" type="button" disabled>Please wait</button>`,"small");
    let created=0,failed=0;
    for(let index=0;index<ids.length;index++){
      const reportId=ids[index];
      try{
        const editor=await rpc("get_report_editor",{target_report_id:reportId,target_enrollment_id:null,target_term_id:null});
        await enrichReportGradingGuide(editor);
        const publication=(editor.publications||[]).find(item=>!item.revoked_at);
        if(!publication)throw new Error("Active publication record not found");
        await createAndStoreOfficialPdf(editor,publication);created+=1;
      }catch(error){
        failed+=1;await reportClientError(error,{source:"bulk_publish_pdf",report_id:reportId});
      }
      const progress=byId("bulkPublishPdfProgress");
      if(progress)progress.textContent=`${index+1} of ${ids.length} completed • ${created} stored${failed?` • ${failed} failed`:""}`;
    }
    closeModal();
    return {created,failed};
  }
  async function requestBulkReportTransition(targetStatus) {
    const definition=bulkReportWorkflowDefinition(targetStatus);
    if(!definition||!can(definition.permission)){toast("Bulk action unavailable","Your account is not permitted to perform this class workflow action.","error");return}
    const termId=byId("reportTerm")?.value||"",classId=byId("reportClass")?.value||"";
    if(!termId||!classId){toast("Select a class and term","Bulk workflow actions require one specific class and one specific term.","warning",6500);return}
    const term=(state.boot.terms||[]).find(item=>item.id===termId),classRow=(state.boot.classes||[]).find(item=>item.id===classId);
    if(role()==="class_teacher"&&["submitted","published"].includes(targetStatus)){
      const workspace=await loadRoleWorkspace();
      if(!(workspace.classes||[]).some(item=>item.class_id===classId)){
        toast("Class-teacher assignment required",`You may ${definition.verb} all reports only for the class where you are the assigned class teacher.`,"error",7000);return;
      }
    }
    modal(definition.title,`${classRow?.name||"Selected class"} • ${term?.name||"Selected term"}`,`
      <div class="template-information"><strong>Class-level workflow</strong><span>All ${definition.source} reports in this class will be checked. Reports with incomplete assigned subjects or required scores will remain unchanged and will be listed as failed.</span></div>
      <label class="field" style="margin-top:15px"><span>Comment</span><textarea id="bulkWorkflowComment" placeholder="Optional workflow comment"></textarea></label>`,
      `<button class="button ghost" id="bulkWorkflowCancel" type="button">Cancel</button><button class="button primary" id="bulkWorkflowConfirm" type="button">${definition.button}</button>`,"small");
    byId("bulkWorkflowCancel").onclick=closeModal;
    byId("bulkWorkflowConfirm").onclick=async()=>{
      const button=byId("bulkWorkflowConfirm"),comment=byId("bulkWorkflowComment").value.trim();button.disabled=true;
      try{
        const result=await rpc("bulk_transition_class_reports",{target_term_id:termId,target_class_id:classId,target_status:targetStatus,comment_text:comment});
        closeModal();state.workspace=null;
        let pdfSummary="";
        if(targetStatus==="published"&&Number(result.transitioned_reports||0)>0){
          const pdf=await storeBulkPublishedReportPdfs(result.transitioned_report_ids||[]);
          pdfSummary=` • ${pdf.created} official PDF${pdf.created===1?"":"s"} stored${pdf.failed?` • ${pdf.failed} PDF failure${pdf.failed===1?"":"s"}`:""}`;
        }
        const transitioned=Number(result.transitioned_reports||0),failed=Number(result.failed_reports||0),missing=Number(result.missing_reports||0),already=Number(result.already_target_status||0);
        toast(`${definition.title} completed`,`${transitioned} report${transitioned===1?"":"s"} ${definition.past}${failed?` • ${failed} incomplete or unsuccessful`:""}${already?` • ${already} already ${definition.past}`:""}${missing?` • ${missing} student${missing===1?" has":"s have"} no report`:""}${pdfSummary}`,failed?"warning":"success",10000);
        await loadReportPage();
      }catch(error){toast(`${definition.title} unsuccessful`,friendlyError(error),"error",8000)}
      finally{if(button)button.disabled=false}
    };
  }

  async function archiveReportCard(id) {
    const ok=await confirmAction("Permanently Delete Report Card","This permanently deletes the report, scores, revisions, workflow history, publication records, stored PDFs, and related audit history. This action cannot be undone.","Delete permanently",true);if(!ok)return;
    setLoading(true);
    try{
      const paths=(await rpc("list_report_pdf_paths",{target_report_id:id})||[]).filter(Boolean);
      if(paths.length){
        const {error}=await state.client.storage.from(CONFIG.pdfBucket).remove(paths);
        if(error)throw error;
        paths.forEach(path=>state.pdfUrls.delete(path));
      }
      await rpc("delete_report_card_permanently",{target_report_id:id,reason_text:"Report card permanently deleted"});
      state.workspace=null;
      if(state.reportEditor?.report?.id===id)state.reportEditor=null;
      toast("Report card permanently deleted");
      if(byId("reportResults"))await loadReportPage();
    }catch(error){toast("Report card not deleted",friendlyError(error),"error",6500)}
    finally{setLoading(false)}
  }

  async function openNewReportPicker() {
    const visibleClasses=await editableClassesForCurrentRole();
    if(!visibleClasses.length){toast(role()==="system_admin"?"No active emergency assignment":"No assigned class",role()==="system_admin"?"Create or activate a temporary delegation before opening a report.":"No class is currently available for report entry.","warning",7000);return}
    modal("New Report Card","Select a student enrolment and term",`
      <div class="form-grid">
        <label class="field"><span>Class</span><select id="newReportClass">${optionList(visibleClasses,"id","name")}</select></label>
        <label class="field"><span>Term</span><select id="newReportTerm">${optionList(state.boot.terms||[],"id","name",activeTerm()?.id)}</select></label>
      </div>
      <label class="field new-report-student-field" style="margin-top:15px"><span>Student</span>
        <select id="newReportStudent" class="new-report-student-list" size="8" disabled aria-describedby="newReportStudentHelp"><option value="">Select a class first</option></select>
        <small id="newReportStudentHelp">The student list stays compact. Scroll up or down, use the mouse wheel, or use the keyboard arrow keys.</small>
      </label>`,
      `<button class="button ghost" id="newReportCancel" type="button">Cancel</button><button class="button primary" id="newReportOpen" type="button" disabled>Open report</button>`,"small");
    const classSelect=byId("newReportClass"),studentSelect=byId("newReportStudent"),openButton=byId("newReportOpen");
    const syncOpenButton=()=>{openButton.disabled=!(studentSelect.value&&byId("newReportTerm").value)};
    byId("newReportCancel").onclick=closeModal;
    studentSelect.onchange=syncOpenButton;
    byId("newReportTerm").onchange=syncOpenButton;
    classSelect.onchange=async()=>{
      const classId=classSelect.value;
      openButton.disabled=true;
      if(!classId){studentSelect.disabled=true;studentSelect.innerHTML=`<option value="">Select a class first</option>`;return}
      studentSelect.disabled=true;studentSelect.innerHTML=`<option value="">Loading students…</option>`;
      try{
        const data=await rpc("search_students",{search_text:"",target_class_id:classId,target_status:"active",page_number:1,page_size:500});
        const rows=(data.rows||[]).filter(x=>x.enrollment_id);
        studentSelect.innerHTML=rows.length?rows.map(row=>
          `<option value="${attr(row.enrollment_id)}">${esc(fullName(row))} • ${esc(row.admission_no)}</option>`).join(""):
          `<option value="">No active students found in this class</option>`;
        studentSelect.disabled=!rows.length;
        if(rows.length){studentSelect.selectedIndex=-1;studentSelect.focus();syncOpenButton()}
      }catch(error){
        studentSelect.innerHTML=`<option value="">Students could not be loaded</option>`;
        studentSelect.disabled=true;
        toast("Students not loaded",friendlyError(error),"error",6500);
      }
    };
    openButton.onclick=()=>{
      const enrollment=studentSelect.value,term=byId("newReportTerm").value;
      if(enrollment&&term){closeModal();openReportEditor(null,enrollment,term)}
    };
  }
  function localPromotionEvaluation(editor=state.reportEditor) {
    const student=editor?.student||{},subjects=editor?.subjects||[],previous=editor?.promotion||{};
    const cutoff=Number(previous.cutoff??state.boot?.school?.promotion_cutoff_score??50);
    const term3=isTermThreeRecord(student);
    const complete=subjects.length>0;
    const average=complete?subjects.reduce((sum,row)=>sum+Number(row.total_score||0),0)/subjects.length:0;
    // Never treat a role-filtered bootstrap class list as proof that no next class exists.
    // Preserve authoritative server context when it has already resolved the target.
    const localNext=configuredNextClass(student.class_id);
    const nextClass=previous.next_class_id
      ?{id:previous.next_class_id,name:previous.next_class_name||localNext?.name||""}
      :localNext;
    const passed=term3&&complete&&average>=cutoff;
    const targetYear=previous.target_academic_year_id?{id:previous.target_academic_year_id,name:previous.target_academic_year_name||""}:configuredNextAcademicYear(student.academic_year_id);
    const reportStatus=String(editor?.report?.status||previous.report_status||"draft");
    const governanceApproved=["approved","published"].includes(reportStatus);
    const authoritativeNextConfigured=typeof previous.next_class_configured==="boolean"?previous.next_class_configured:null;
    const nextClassConfigured=authoritativeNextConfigured??(nextClass?true:null);
    const promotionApplied=Boolean(passed&&governanceApproved&&previous.promotion_applied&&previous.next_class_id&&previous.next_class_id===nextClass?.id);
    return {term3,complete,average,cutoff,passed,eligible:passed&&Boolean(nextClass),report_status:reportStatus,
      governance_approved:governanceApproved,approval_required:passed&&!governanceApproved,
      next_class_id:nextClass?.id||null,next_class_name:nextClass?.name||"",next_class_configured:nextClassConfigured,
      target_academic_year_id:targetYear?.id||null,target_academic_year_name:targetYear?.name||"",promotion_applied:promotionApplied,
      can_create_enrollment:passed&&governanceApproved&&Boolean(nextClass&&targetYear),
      canonical:false,finalized:false,canonical_source:previous.canonical_source||"local_draft_preview",resolution_status:nextClassConfigured===null?"pending":"resolved"};
  }
  async function enrichReportPromotion(editor) {
    if(!editor)return editor;
    if(editor.report?.id){
      try{
        editor.promotion=await rpc("report_promotion_canonical",{target_report_id:editor.report.id});
        editor.promotion_error="";
      }catch(error){
        await reportClientError(error,{source:"canonical_report_promotion",report_id:editor.report.id,workflow_state:editor.report?.status||""});
        const fallback=localPromotionEvaluation(editor);
        editor.promotion={...fallback,resolution_error:true,resolution_status:"error",canonical:false,finalized:["approved","published"].includes(String(editor.report?.status||""))};
        editor.promotion_error=friendlyError(error);
      }
    }else editor.promotion=localPromotionEvaluation(editor);
    return editor;
  }
  function promotionDisplay(evaluation=localPromotionEvaluation()) {
    if(evaluation?.resolution_error)return {title:"Promotion status unavailable",detail:"The authoritative promotion decision could not be loaded. Refresh the report or contact the System Administrator. No academic decision has been inferred from this error.",state:"warning"};
    if(!evaluation?.term3)return {title:"Not applicable",detail:"This record is not recognised as Term 3. Automatic promotion uses Term 3 results only.",state:"neutral"};
    if(!evaluation.complete)return {title:"Awaiting complete results",detail:`All assigned subjects must be completed before the ${number(evaluation.cutoff||50,0)}% promotion rule is applied.`,state:"warning"};
    if(evaluation.passed&&evaluation.next_class_name&&evaluation.promotion_applied)return {title:`Promoted to ${evaluation.next_class_name}`,detail:`The approved ${evaluation.target_academic_year_name||"next academic year"} enrolment is now the student’s active class placement. The earlier enrolment remains only in protected history.`,state:"pass"};
    if(evaluation.passed&&evaluation.next_class_name&&evaluation.approval_required)return {title:`Eligible for ${evaluation.next_class_name}`,detail:`Term 3 average ${number(evaluation.average,1)}% meets the ${number(evaluation.cutoff,0)}% cutoff. The next-year enrolment will be created only after Principal approval or publication.`,state:"warning"};
    if(evaluation.passed&&evaluation.next_class_name)return {title:`Eligible for ${evaluation.next_class_name}`,detail:`Term 3 average ${number(evaluation.average,1)}% meets the cutoff. Run Term 3 Promotion Processing after approval to create the ${evaluation.target_academic_year_name||"next-year"} enrolment.`,state:"pass"};
    if(evaluation.passed&&evaluation.next_class_configured===false)return {title:"Passed, no next class configured",detail:`Term 3 average ${number(evaluation.average,1)}% meets the ${number(evaluation.cutoff,0)}% cutoff, and the authoritative class progression configuration has no following class.`,state:"pass"};
    if(evaluation.passed)return {title:"Promotion target pending",detail:`Term 3 average ${number(evaluation.average,1)}% meets the ${number(evaluation.cutoff,0)}% cutoff, but the authoritative next-class target has not been resolved yet.`,state:"warning"};
    return {title:"Not promoted",detail:`Term 3 average ${number(evaluation.average,1)}% is below the ${number(evaluation.cutoff,0)}% cutoff.`,state:"fail"};
  }
  function updatePromotionPreview() {
    if(!state.reportEditor)return;
    const reportStatus=String(state.reportEditor.report?.status||"");
    const finalized=["approved","published"].includes(reportStatus);
    const evaluation=finalized?(state.reportEditor.promotion||{resolution_error:true}):localPromotionEvaluation(state.reportEditor);
    const display=promotionDisplay(evaluation);
    if(!finalized)state.reportEditor.promotion=evaluation;
    const title=byId("automaticPromotionValue"),detail=byId("automaticPromotionDetail"),box=byId("automaticPromotionField");
    if(title)title.textContent=display.title;if(detail)detail.textContent=display.detail;
    if(box)box.dataset.promotionState=display.state;
  }

  async function openReportEditor(reportId=null,enrollmentId=null,termId=null) {
    setLoading(true);
    try {
      const args={target_report_id:reportId,target_enrollment_id:enrollmentId,target_term_id:termId};
      const suffix=reportId?`id:${reportId}`:`new:${enrollmentId||""}:${termId||""}`;
      let editor;
      if(isConnectivityLimited()){editor=await snapshotDataGet("report-editor",suffix);if(!editor)throw new Error("This report has not been made available on this device for offline work.");}
      else{
        try{editor=await rpc("get_report_editor",args);await enrichReportPromotion(editor);await enrichReportGradingGuide(editor);await snapshotDataPut("report-editor",suffix,editor).catch(()=>{});}
        catch(error){if(!isNetworkFailure(error))throw error;noteNetworkFailure(error);editor=await snapshotDataGet("report-editor",suffix);if(!editor)throw error;}
      }
      state.reportEditor=editor;
      state.view="reports";renderNav();
      renderReportEditor();
      const key=`report:${editor.report?.id||`${editor.report?.enrollment_id}:${editor.report?.term_id}`}`;
      const local=await draftGet(key).catch(()=>null);
      if(local&&Number(local.version)===Number(editor.report?.version||0)&&editor.can_edit) {
        applyLocalReportDraft(local.payload);
        toast("Draft restored","Unsaved local changes were recovered.","warning");
      }
    } catch(error){toast("Report unavailable",friendlyError(error),"error");await navigate("reports",true)}
    finally{setLoading(false)}
  }
  async function refreshOpenReport() {
    if(!state.reportEditor?.report?.id||isConnectivityLimited())return;
    try{
      const latest=await rpc("get_report_editor",{target_report_id:state.reportEditor.report.id,target_enrollment_id:null,target_term_id:null});
      await enrichReportPromotion(latest);
      await enrichReportGradingGuide(latest);
      if(state.reportEditor&&Number(latest.report.version)>Number(state.reportEditor.report.version)) {
        state.reportEditor=latest;renderReportEditor();toast("Report refreshed","A newer version was received.","warning");
      }
    }catch(_){}
  }
  function renderReportEditor() {
    const editor=state.reportEditor,report=editor.report||{},student=editor.student||{},subjects=editor.subjects||[];
    const average=subjects.length?subjects.reduce((sum,s)=>sum+Number(s.total_score||0),0)/subjects.length:0;
    const publication=(editor.publications||[]).find(p=>!p.revoked_at);
    const locked=!editor.can_edit;
    const fieldsLocked=!editor.can_edit_fields;
    const canHeadComment=!isConnectivityLimited()&&can("approve_reports")&&!['published','withdrawn'].includes(report.status);
    byId("pageTitle").textContent=student.full_name||"Report Card";
    byId("pageSubtitle").textContent=`${student.class_name||""} • ${student.term_name||""} • ${report.report_number||"New report"}`;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>${esc(student.full_name)}</h3><p>${esc(student.admission_no)} • ${esc(student.class_name)} • ${esc(student.academic_year_name)} • ${esc(student.term_name)}</p></div>
        <div class="page-actions"><button class="button ghost" id="reportBack">Back to reports</button>
          ${report.id&&!isConnectivityLimited()?`<button class="button outline" id="reportHistory">Revisions</button>`:""}
          ${publication&&!isConnectivityLimited()?`<button class="button outline" id="reportDownload">Download latest PDF</button>`:""}
          ${report.id&&!isConnectivityLimited()&&canRemoveReportRow(report)?`<button class="button danger" id="reportRemove">Delete permanently</button>`:""}
        </div></div>
      ${emergencyDelegationBannerHtml(editor.emergency_delegations||[])}
      <div class="report-layout">
        <section class="panel">
          <div class="panel-header"><div><h3>Assessment Record</h3><p>${statusBadge(report.status)}</p></div>
            <div class="button-row"><span class="chip" title="The grading guide printed on this report">${esc(editor.grading_scale?.scope?.label||"Grading guide")}</span>${locked?`<span class="chip">Read only</span>`:`<span class="chip">Version ${number(report.version||0)}</span>`}</div></div>
          <div class="panel-body">
            <form id="reportForm" class="form-stack">
              <div class="form-grid three">
                <label class="field"><span>Days school opened (automatic)</span><input name="days_school_opened" type="number" min="0" value="${attr(report.days_school_opened||0)}" readonly></label>
                <label class="field"><span>Days present (automatic)</span><input name="days_present" type="number" min="0" value="${attr(report.days_present||0)}" readonly></label>
                <label class="field"><span>Next-term reopening date</span><input type="date" value="${attr(reportNextTermReopeningDate(report,student))}" readonly><small>${reportNextTermReopeningDate(report,student)?"Printed on the official report card.":"The school has not set the date yet."}</small></label>
                ${(()=>{const display=promotionDisplay(editor.promotion||localPromotionEvaluation(editor));return `<div class="field automatic-promotion-field" id="automaticPromotionField" data-promotion-state="${display.state}"><span>Automatic promotion</span><strong id="automaticPromotionValue">${esc(display.title)}</strong><small id="automaticPromotionDetail">${esc(display.detail)}</small></div>`})()}
                <label class="field"><span>Attitude</span><input name="attitude" value="${attr(report.attitude||"")}" ${fieldsLocked?"disabled":""}></label>
                <label class="field"><span>Conduct</span><input name="conduct" value="${attr(report.conduct||"")}" ${fieldsLocked?"disabled":""}></label>
                <label class="field"><span>Interest or talent</span><input name="interest" value="${attr(report.interest||"")}" ${fieldsLocked?"disabled":""}></label>
                <div class="full comment-actions">${editor.can_edit_fields||canHeadComment?`<button class="button secondary small" id="reportGenerateComments" type="button">Generate comments</button>`:""}
                  ${locked&&canHeadComment?`<button class="button primary small" id="reportSaveComments" type="button">Save comments</button>`:""}</div>
                <label class="field full"><span>Class teacher's comment</span><textarea name="teacher_comment" ${fieldsLocked?"disabled":""}>${esc(report.teacher_comment||"")}</textarea></label>
                <label class="field full"><span>Principal's comment</span><textarea name="head_comment" ${canHeadComment?"":"disabled"}>${esc(report.head_comment||"")}</textarea></label>
              </div>
              <div class="section-title"><h4>Subject Results</h4><span class="chip">${subjects.length} subjects</span></div>
              <div class="score-grid"><table><thead><tr><th>Subject</th><th>Assessment Components</th><th>Total</th><th>Grade</th><th>Remark</th><th>Initials</th></tr></thead>
                <tbody>${subjects.map((subject,index)=>reportSubjectRow(subject,index,!subject.can_score)).join("")}</tbody></table></div>
            </form>
          </div>
        </section>
        <aside class="report-sidebar">
          <div class="report-summary"><p>Current average</p><div class="summary-number" id="reportAverage">${number(average,1)}%</div>
            <p>${esc(report.report_number||"Unpublished record")}</p></div>
          <section class="panel pad"><div class="section-title"><h4>Workflow</h4></div>
            <div class="workflow">${workflowButtons(report,publication)}</div></section>
          <section class="panel pad"><div class="section-title"><h4>Activity</h4></div>
            <div class="timeline">${(editor.workflow||[]).length?(editor.workflow||[]).slice(0,8).map(item=>`
              <div class="timeline-item"><span class="timeline-dot"></span><div class="timeline-copy"><strong>${esc(item.to_status.replaceAll("_"," "))}</strong>
              <small>${isoDateTime(item.created_at)}${item.comment?` • ${esc(item.comment)}`:""}</small></div></div>`).join(""):`<p class="help-text">No workflow activity</p>`}</div></section>
        </aside>
      </div>`;
    byId("reportBack").onclick=()=>navigate("reports",true);
    byId("reportHistory")?.addEventListener("click",openRevisionHistory);
    byId("reportDownload")?.addEventListener("click",()=>downloadLatestOfficialPdf(report.id));
    byId("reportRemove")?.addEventListener("click",async()=>{const id=report.id;await archiveReportCard(id);if(state.view==="reports")await navigate("reports",true)});
    byId("reportSave")?.addEventListener("click",saveOpenReport);
    byId("reportGenerateComments")?.addEventListener("click",()=>applyAutomaticComments(true));
    byId("reportSaveComments")?.addEventListener("click",saveLockedReportComments);
    $$("[data-transition]").forEach(button=>button.onclick=()=>requestTransition(button.dataset.transition));
    byId("reportGeneratePdf")?.addEventListener("click",()=>generateAndUploadOfficialPdf());
    byId("reportCorrection")?.addEventListener("click",openCorrection);
    $$("[data-component-input]").forEach(input=>input.addEventListener("input",()=>{
      recalculateSubject(Number(input.dataset.subjectIndex));
      scheduleLocalDraft();
    }));
    $$("[data-teacher-initials]").forEach(input=>input.addEventListener("input",scheduleLocalDraft));
    $$("#reportForm input,#reportForm textarea,#reportForm select").forEach(input=>input.addEventListener("change",scheduleLocalDraft));
    updatePromotionPreview();
    setTimeout(()=>applyAutomaticComments(false),0);
  }
  function reportSubjectRow(subject,index,locked) {
    return `<tr data-subject-row="${index}">
      <td><div class="cell-copy"><strong>${esc(subject.subject_name)}</strong><small>${esc(subject.subject_code)} • ${esc(subject.scheme_name||"")}</small></div></td>
      <td><div class="chip-list">${(subject.components||[]).map(component=>`<label class="chip">
        <span>${esc(component.code)} / ${number(component.maximum_score,0)}</span>
        <input class="score-input" data-component-input data-subject-index="${index}" data-component-id="${attr(component.component_id)}"
          data-max="${attr(component.maximum_score)}" data-weight="${attr(component.weight)}" type="number" min="0" max="${attr(component.maximum_score)}"
          step=".01" value="${attr(component.raw_score||0)}" ${locked?"disabled":""}>
      </label>`).join("")}</div></td>
      <td class="score-total" data-subject-total="${index}">${number(subject.total_score,1)}</td>
      <td data-subject-grade="${index}">${esc(subject.grade||"—")}</td><td>${esc(subject.remark||"")}</td>
      <td><input class="score-input" data-teacher-initials="${index}" value="${attr(subject.teacher_initials||"")}" ${locked?"disabled":""}></td>
    </tr>`;
  }
  function recalculateSubject(index) {
    const subject=state.reportEditor.subjects[index];
    let total=0;
    $$(`[data-subject-index="${index}"]`).forEach(input=>{
      const raw=Math.max(0,Math.min(Number(input.value||0),Number(input.dataset.max||0)));
      total+=(raw/Number(input.dataset.max||1))*Number(input.dataset.weight||0);
    });
    subject.total_score=Math.round(total*100)/100;
    $(`[data-subject-total="${index}"]`).textContent=number(subject.total_score,1);
    const totals=state.reportEditor.subjects.map(s=>Number(s.total_score||0));
    byId("reportAverage").textContent=`${number(totals.reduce((a,b)=>a+b,0)/(totals.length||1),1)}%`;
    updatePromotionPreview();
    if(byId("reportForm")?.elements.teacher_comment?.dataset.autoGenerated==="true"||byId("reportForm")?.elements.head_comment?.dataset.autoGenerated==="true")applyAutomaticComments(false);
  }
  function automaticCommentText() {
    const editor=state.reportEditor,student=editor?.student||{},subjects=editor?.subjects||[];
    const scores=subjects.map(subject=>({name:subject.subject_name||"the assessed subjects",score:Number(subject.total_score||0)}));
    const average=scores.length?scores.reduce((sum,item)=>sum+item.score,0)/scores.length:0;
    const strongest=[...scores].sort((a,b)=>b.score-a.score)[0]?.name||"the assessed subjects";
    const weakest=[...scores].sort((a,b)=>a.score-b.score)[0]?.name||"the weaker subjects";
    const firstName=student.first_name||student.full_name?.split(" ")[0]||"The student";
    const pronoun=student.gender==="Male"?"He":student.gender==="Female"?"She":"They";
    const form=byId("reportForm"),opened=Number(form?.elements.days_school_opened?.value||0),present=Number(form?.elements.days_present?.value||0);
    const attendance=opened>0?present/opened*100:0;
    const mark=number(average,1);
    let teacherComment,headComment;
    if(!scores.length){teacherComment=`${firstName}'s assessment record is incomplete and requires all subject results.`;headComment="Complete the outstanding assessment records before final approval."}
    else if(average>=85){teacherComment=`${firstName} has demonstrated outstanding academic performance with an average of ${mark}%. ${pronoun} showed exceptional strength in ${strongest}. Maintain this excellent standard.`;headComment="Excellent performance. Continue to pursue excellence and remain a positive example to others."}
    else if(average>=75){teacherComment=`${firstName} has achieved a very good academic performance with an average of ${mark}%. ${pronoun} performed especially well in ${strongest} and should continue working consistently.`;headComment="Very good performance. Keep working diligently and aim for an even higher standard next term."}
    else if(average>=65){teacherComment=`${firstName} has made good academic progress with an average of ${mark}%. ${pronoun} showed strength in ${strongest} and should give additional attention to ${weakest}.`;headComment="Good progress. Maintain steady effort and improve the areas that require greater attention."}
    else if(average>=50){teacherComment=`${firstName} has produced a satisfactory performance with an average of ${mark}%. More regular revision, active class participation, and focused practice in ${weakest} will improve future results.`;headComment="Satisfactory performance. Greater consistency and focused study are required for stronger achievement."}
    else if(average>=40){teacherComment=`${firstName} has shown a fair performance with an average of ${mark}%. ${pronoun} needs sustained support, regular practice, and closer attention to ${weakest}.`;headComment="There is potential for improvement. Work closely with teachers and maintain a disciplined study routine."}
    else {teacherComment=`${firstName} needs substantial academic improvement. The current average is ${mark}%, and immediate support is required, particularly in ${weakest}.`;headComment="Considerable improvement is required. Consistent effort, supervision, and remedial support should begin immediately."}
    if(opened>0&&attendance<85)teacherComment+=` Attendance also requires improvement (${present} of ${opened} days present).`;
    else if(opened>0&&attendance>=95)teacherComment+=` ${pronoun} maintained excellent attendance.`;
    const promotion=localPromotionEvaluation(editor);
    if(promotion.term3&&promotion.complete){
      if(promotion.passed&&promotion.next_class_name&&promotion.promotion_applied)headComment+=` Promotion: Promoted to ${promotion.next_class_name}.`;
      else if(promotion.passed&&promotion.next_class_name)headComment+=` Promotion: Eligible for ${promotion.next_class_name}, subject to Principal approval or publication.`;
      else if(!promotion.passed)headComment+=` Promotion: Not promoted because the Term 3 average is below the ${number(promotion.cutoff,0)}% cutoff.`;
    }
    return {teacherComment,headComment,average};
  }
  function applyAutomaticComments(force=false) {
    if(!state.reportEditor||!byId("reportForm"))return;
    const generated=automaticCommentText(),form=byId("reportForm");
    const teacher=form.elements.teacher_comment,head=form.elements.head_comment;
    if(teacher&&!teacher.disabled&&(force||!teacher.value.trim()||teacher.dataset.autoGenerated==="true")){
      teacher.value=generated.teacherComment;teacher.dataset.autoGenerated="true";
    }
    if(head&&!head.disabled&&(force||!head.value.trim()||head.dataset.autoGenerated==="true")){
      head.value=generated.headComment;head.dataset.autoGenerated="true";
    }
    state.autoComments=generated;scheduleLocalDraft();
  }
  async function saveLockedReportComments() {
    const report=state.reportEditor?.report,form=byId("reportForm"),button=byId("reportSaveComments");
    if(!report?.id||!form)return;if(button)button.disabled=true;
    try{
      state.reportEditor=await rpc("save_report_comments",{
        target_report_id:report.id,teacher_comment_text:null,
        head_comment_text:form.elements.head_comment?.value||"",expected_version:report.version
      });
      state.workspace=null;renderReportEditor();toast("Comments saved");
    }catch(error){if(error?.code==="40001")await refreshOpenReport();toast("Comments not saved",friendlyError(error),"error")}
    finally{if(button)button.disabled=false}
  }

  function workflowButtons(report,publication) {
    const buttons=[],allowed=new Set(state.reportEditor.allowed_transitions||[]);
    if(state.reportEditor.can_edit)buttons.push(`<button class="button primary full" id="reportSave">${isConnectivityLimited()?"Save offline":"Save report"}</button>`);
    if(isConnectivityLimited())return buttons.join("")||`<span class="help-text">This report is read only while offline.</span>`;
    if(allowed.has("submitted"))buttons.push(`<button class="button secondary full" data-transition="submitted">Submit for Principal approval</button>`);
    if(allowed.has("class_reviewed"))buttons.push(`<button class="button success full" data-transition="class_reviewed">Complete class review</button>`);
    if(allowed.has("approved"))buttons.push(`<button class="button success full" data-transition="approved">Approve report</button>`);
    if(allowed.has("published"))buttons.push(`<button class="button success full" data-transition="published">${report.status==="withdrawn"?"Republish report":"Publish report"}</button>`);
    if(allowed.has("returned"))buttons.push(`<button class="button warning full" data-transition="returned">Return for correction</button>`);
    if(report.status==="published"&&!publication?.storage_path&&can("publish_reports"))buttons.push(`<button class="button primary full" id="reportGeneratePdf">Create official PDF</button>`);
    if(["published","approved"].includes(report.status)&&["system_admin","class_teacher","subject_teacher"].includes(role()))buttons.push(`<button class="button warning full" id="reportCorrection">Request correction</button>`);
    if(allowed.has("withdrawn"))buttons.push(`<button class="button danger full" data-transition="withdrawn">Withdraw publication</button>`);
    return buttons.join("")||`<span class="help-text">No workflow action available</span>`;
  }
  function collectReportPayload() {
    const form=byId("reportForm"),values=formObject(form),editor=state.reportEditor;
    const subjects=editor.subjects.map((subject,index)=>({subject,index})).filter(item=>item.subject.can_score).map(({subject,index})=>({
      subject_id:subject.subject_id,scheme_id:subject.scheme_id,
      teacher_initials:$(`[data-teacher-initials="${index}"]`)?.value.trim()||"",
      components:(subject.components||[]).map(component=>({component_id:component.component_id,raw_score:Number($(`[data-subject-index="${index}"][data-component-id="${component.component_id}"]`)?.value||0)}))
    }));
    const fields=editor.can_edit_fields?{days_school_opened:Number(values.days_school_opened||0),days_present:Number(values.days_present||0),
      attitude:values.attitude||"",conduct:values.conduct||"",interest:values.interest||"",
      teacher_comment:values.teacher_comment||"",head_comment:values.head_comment??editor.report.head_comment??"",
      promoted_to_class_id:editor.report.promoted_to_class_id||null}:{};
    return {report_id:editor.report.id||null,enrollment_id:editor.report.enrollment_id,term_id:editor.report.term_id,fields,subjects,reason:"Report assessment updated"};
  }
  function scheduleLocalDraft() {
    clearTimeout(scheduleLocalDraft.timer);
    scheduleLocalDraft.timer=setTimeout(async()=>{
      if(!state.reportEditor?.can_edit||!byId("reportForm"))return;
      const payload=collectReportPayload(),key=`report:${state.reportEditor.report.id||`${payload.enrollment_id}:${payload.term_id}`}`;
      await draftPut({key,payload,version:state.reportEditor.report.version||0,savedAt:new Date().toISOString()}).catch(()=>{});
    },450);
  }
  function applyLocalReportDraft(payload) {
    if(!payload||!byId("reportForm"))return;
    const f=payload.fields||{},form=byId("reportForm");
    Object.entries(f).forEach(([key,value])=>{if(form.elements[key]&&!form.elements[key].disabled)form.elements[key].value=value??""});
    (payload.subjects||[]).forEach(subject=>{
      const index=(state.reportEditor.subjects||[]).findIndex(item=>item.subject_id===subject.subject_id);if(index<0||!state.reportEditor.subjects[index].can_score)return;
      (subject.components||[]).forEach(component=>{const input=$(`[data-subject-index="${index}"][data-component-id="${component.component_id}"]`);if(input&&!input.disabled)input.value=component.raw_score});
      const initials=$(`[data-teacher-initials="${index}"]`);if(initials&&!initials.disabled)initials.value=subject.teacher_initials||"";recalculateSubject(index);
    });
  }
  async function saveOpenReport() {
    const form=byId("reportForm");if(form&&!form.reportValidity())return;
    const button=byId("reportSave");if(button)button.disabled=true;
    const payload=collectReportPayload(),expected=state.reportEditor.report.version||null;let persisted=false;
    try {
      let saved;
      if(isConnectivityLimited()) saved=await queueReportSave(payload,expected);
      else {
        try{saved=await rpc("save_report_card",{payload,expected_version:expected});persisted=true}
        catch(error){
          if(error?.message?.toLowerCase().includes("fetch")||error?.name==="TypeError"){saved=await queueReportSave(payload,expected)}
          else throw error;
        }
      }
      if(saved?.report){await enrichReportPromotion(saved);await enrichReportGradingGuide(saved);state.workspace=null;state.reportEditor=saved;renderReportEditor()}
      const key=`report:${payload.report_id||`${payload.enrollment_id}:${payload.term_id}`}`;await draftDelete(key).catch(()=>{});
      if(persisted)toast("Report saved");
    } catch(error){
      if(persisted){await reportClientError(error,{source:"report_save",stage:"refresh"});toast("Report saved","Reload the page to display the latest report.","warning",6500);return}
      if(error?.code==="40001"||String(error?.message).includes("changed by another user"))await refreshOpenReport();
      toast("Report not saved",friendlyError(error),"error");
    } finally{if(button)button.disabled=false}
  }
  async function requestTransition(targetStatus) {
    const labels={submitted:"Submit report",class_reviewed:"Complete review",approved:"Approve report",published:state.reportEditor?.report?.status==="withdrawn"?"Republish report":"Publish report",returned:"Return report",withdrawn:"Withdraw publication"};
    modal(labels[targetStatus]||"Update report status","",`<label class="field"><span>Comment</span><textarea id="workflowComment"></textarea></label>`,
      `<button class="button ghost" id="workflowCancel" type="button">Cancel</button><button class="button ${targetStatus==="withdrawn"?"danger":"primary"}" id="workflowConfirm" type="button">${esc(labels[targetStatus]||"Continue")}</button>`,"small");
    byId("workflowCancel").onclick=closeModal;
    byId("workflowConfirm").onclick=async()=>{
      const comment=byId("workflowComment").value.trim(),button=byId("workflowConfirm");button.disabled=true;
      try{
        if(state.reportEditor.can_edit&&(targetStatus==="submitted"||(targetStatus==="published"&&state.reportEditor.report.status==="withdrawn")))await saveOpenReport();
        const updated=await rpc("transition_report_status",{target_report_id:state.reportEditor.report.id,target_status:targetStatus,
          comment_text:comment,expected_version:state.reportEditor.report.version});
        await enrichReportPromotion(updated);
        await enrichReportGradingGuide(updated);
        state.workspace=null;state.reportEditor=updated;closeModal();toast("Report status updated");
        renderReportEditor();
        if(targetStatus==="published")await generateAndUploadOfficialPdf();
      }catch(error){toast("Workflow action unsuccessful",friendlyError(error),"error");if(error?.code==="40001")await refreshOpenReport()}
      finally{button.disabled=false}
    };
  }
  async function openCorrection() {
    modal("Request Report Correction","The Principal must approve the request before the report is reopened. The original publication and revision remain preserved.",`<label class="field"><span>Correction reason</span><textarea id="correctionReason" required placeholder="Describe the exact error and the fields that must be corrected"></textarea></label>`,
      `<button class="button ghost" id="correctionCancel" type="button">Cancel</button><button class="button warning" id="correctionOpen" type="button">Submit request</button>`,"small");
    byId("correctionCancel").onclick=closeModal;
    byId("correctionOpen").onclick=async()=>{
      const reason=byId("correctionReason").value.trim();if(reason.length<10){toast("Correction not requested","Provide a clear reason of at least ten characters.","error");return}
      const button=byId("correctionOpen");button.disabled=true;
      try{await rpc("request_report_correction",{target_report_id:state.reportEditor.report.id,reason_text:reason,requested_fields:[]});closeModal();toast("Correction request submitted","The Principal has been notified for review.");}
      catch(error){toast("Correction not requested",friendlyError(error),"error")}
      finally{button.disabled=false}
    };
  }
  async function openRevisionHistory() {
    const revisions=await rpc("get_report_revisions",{target_report_id:state.reportEditor.report.id});
    modal("Report Revisions",state.reportEditor.report.report_number||"",`
      <div class="form-grid">
        <label class="field"><span>Earlier revision</span><select id="revisionA">${(revisions||[]).map((r,i)=>`<option value="${i}" ${i===Math.min(1,revisions.length-1)?"selected":""}>Version ${r.version} • ${isoDateTime(r.created_at)}</option>`).join("")}</select></label>
        <label class="field"><span>Later revision</span><select id="revisionB">${(revisions||[]).map((r,i)=>`<option value="${i}" ${i===0?"selected":""}>Version ${r.version} • ${isoDateTime(r.created_at)}</option>`).join("")}</select></label>
      </div>
      <div id="revisionDiff" style="margin-top:18px"></div>`,
      `<button class="button ghost" id="revisionClose" type="button">Close</button>`,"wide");
    const render=()=>renderRevisionDiff(revisions[Number(byId("revisionA").value)],revisions[Number(byId("revisionB").value)]);
    byId("revisionA").onchange=render;byId("revisionB").onchange=render;byId("revisionClose").onclick=closeModal;render();
  }
  function renderRevisionDiff(a,b) {
    const root=byId("revisionDiff");if(!root||!a||!b)return;
    const fields=["status","days_school_opened","days_present","attitude","conduct","interest","teacher_comment","head_comment"];
    const ar=a.snapshot?.report||{},br=b.snapshot?.report||{};
    const scoreMap=snapshot=>Object.fromEntries((snapshot?.results||[]).map(x=>[x.subject_name,x.total_score]));
    const as=scoreMap(a.snapshot),bs=scoreMap(b.snapshot),subjects=[...new Set([...Object.keys(as),...Object.keys(bs)])];
    const ap=a.snapshot?.promotion?promotionDisplay(a.snapshot.promotion).title:"Not recorded in this historical revision";
    const bp=b.snapshot?.promotion?promotionDisplay(b.snapshot.promotion).title:"Not recorded in this historical revision";
    root.innerHTML=`<div class="revision-compare">
      <div class="diff-card"><h4>Version ${a.version}</h4>${fields.map(key=>`<div class="diff-row ${String(ar[key]??"")!==String(br[key]??"")?"changed":""}"><span>${esc(key.replaceAll("_"," "))}</span><b>${esc(ar[key]??"—")}</b></div>`).join("")}<div class="diff-row ${ap!==bp?"changed":""}"><span>automatic promotion</span><b>${esc(ap)}</b></div></div>
      <div class="diff-card"><h4>Version ${b.version}</h4>${fields.map(key=>`<div class="diff-row ${String(ar[key]??"")!==String(br[key]??"")?"changed":""}"><span>${esc(key.replaceAll("_"," "))}</span><b>${esc(br[key]??"—")}</b></div>`).join("")}<div class="diff-row ${ap!==bp?"changed":""}"><span>automatic promotion</span><b>${esc(bp)}</b></div></div>
    </div>
    <div class="section-title" style="margin-top:18px"><h4>Score changes</h4></div>
    <div class="table-wrap"><table><thead><tr><th>Subject</th><th>Version ${a.version}</th><th>Version ${b.version}</th><th>Change</th></tr></thead><tbody>
      ${subjects.map(name=>`<tr><td>${esc(name)}</td><td>${number(as[name],1)}</td><td>${number(bs[name],1)}</td><td>${number(Number(bs[name]||0)-Number(as[name]||0),1)}</td></tr>`).join("")}
    </tbody></table></div>`;
  }
  async function openScoreImport() {
    const visibleClasses=await editableClassesForCurrentRole();
    if(!visibleClasses.length){toast("No score-entry assignment","No active class or emergency delegation is available for score import.","warning",7000);return}
    modal("Import Scores","CSV assessment entries with server-side validation and row-level error reporting",`<form id="scoreImportForm" class="form-stack">
      <div class="form-grid"><label class="field"><span>Term</span><select name="term_id" required>${optionList(state.boot.terms||[],"id","name",activeTerm()?.id)}</select></label>
      <label class="field"><span>Class</span><select name="class_id" required>${optionList(visibleClasses,"id","name")}</select></label></div>
      <label class="file-drop"><strong>CSV file</strong><input name="file" type="file" accept=".csv,text/csv" required></label><div id="scoreImportPreview"></div>
    </form>`,`<button class="button ghost" id="scoreImportCancel" type="button">Cancel</button><button class="button secondary" id="scoreImportValidate" type="button">Validate</button><button class="button primary" id="scoreImportRun" type="button" disabled>Import valid rows</button>`,"small");
    byId("scoreImportCancel").onclick=closeModal;let validation=null,fileName="",selected={};
    byId("scoreImportValidate").onclick=async()=>{const form=byId("scoreImportForm"),v=formObject(form),file=form.elements.file.files[0];if(!file){toast("Select a CSV file","Choose the file before validation.","warning");return}const rows=parseCsv(await file.text()),button=byId("scoreImportValidate");button.disabled=true;button.textContent="Validating";try{validation=await rpc("validate_score_import",{target_term_id:v.term_id,target_class_id:v.class_id,rows,filename:file.name});selected=v;fileName=file.name;byId("scoreImportPreview").innerHTML=importValidationHtml(validation);byId("scoreImportRun").disabled=!validation.valid_count;byId("importErrorsDownload")?.addEventListener("click",()=>downloadImportErrors(validation,"score-import-errors.csv"));toast("Validation completed",`${number(validation.valid_count)} valid, ${number(validation.invalid_count)} invalid.`,validation.invalid_count?"warning":"success")}catch(error){toast("Validation unsuccessful",friendlyError(error),"error")}finally{button.disabled=false;button.textContent="Validate"}};
    byId("scoreImportRun").onclick=async()=>{if(!validation?.valid_count)return;const button=byId("scoreImportRun");button.disabled=true;try{const result=await rpc("bulk_import_scores",{target_term_id:selected.term_id,target_class_id:selected.class_id,rows:validation.valid_rows,filename:fileName});closeModal();toast("Score import completed",`${result.successful} saved, ${result.failed} failed`,result.failed?"warning":"success",7000);await loadReportPage()}catch(error){toast("Score import unsuccessful",friendlyError(error),"error")}finally{button.disabled=false}};
  }
  function openManualReportTemplate() {
    const years=(state.boot.academic_years||[]).filter(item=>!item.deleted_at);
    const classes=(state.boot.classes||[]).filter(item=>item.active!==false&&!item.deleted_at);
    const activeSubjects=(state.boot.subjects||[]).filter(item=>item.active!==false&&!item.deleted_at);
    modal("Manual Report Card Template","Download a professionally formatted blank report card containing every active subject.",`
      <form id="manualTemplateForm" class="form-stack">
        <div class="form-grid">
          <label class="field"><span>Academic year</span><select name="academic_year_id">${optionList(years,"id","name",activeYear()?.id,"Leave blank")}</select></label>
          <label class="field"><span>Term</span><select name="term_id" id="manualTemplateTerm"></select></label>
          <label class="field full"><span>Class</span><select name="class_id">${optionList(classes,"id","name","","Leave blank")}</select></label>
        </div>
        <div class="template-information">
          <strong>${activeSubjects.length} active subject${activeSubjects.length===1?"":"s"} will be included.</strong>
          <span id="manualTemplateAssignment">Choose a class to apply its assigned class-range template. Student details, scores, grades, positions, comments, attendance and conduct fields remain blank for manual completion.</span>
        </div>
      </form>`,
      `<button class="button ghost" id="manualTemplateCancel" type="button">Cancel</button><button class="button primary" id="manualTemplateDownload" type="button">Download PDF template</button>`,"small");
    const form=byId("manualTemplateForm");
    const renderTerms=()=>{
      const yearId=form.elements.academic_year_id.value;
      const terms=(state.boot.terms||[]).filter(item=>!item.deleted_at&&(!yearId||item.academic_year_id===yearId));
      byId("manualTemplateTerm").innerHTML=optionList(terms,"id","name",activeTerm()?.id,"Leave blank");
    };
    const renderTemplateAssignment=async()=>{
      const classRow=classes.find(item=>item.id===form.elements.class_id.value),status=byId("manualTemplateAssignment");if(!status)return;
      if(!classRow){status.textContent="Choose a class to apply its assigned class-range template. Without a class, the built-in design is used.";return}
      try{const template=await currentReportTemplateForClass(classRow.name,true);status.textContent=template?`${classRow.name} will use the uploaded ${reportTemplateGroup(template.range_key)?.shortLabel||"class-range"} template: ${template.original_name}.`:`${classRow.name} has no uploaded class-range template and will use the approved built-in design.`}catch(_){status.textContent="Template assignment could not be checked. The system will validate it when generating the PDF."}
    };
    form.elements.academic_year_id.onchange=renderTerms;form.elements.class_id.onchange=renderTemplateAssignment;
    renderTerms();renderTemplateAssignment();
    byId("manualTemplateCancel").onclick=closeModal;
    byId("manualTemplateDownload").onclick=async()=>{
      if(!activeSubjects.length){toast("Template unavailable","Add at least one active subject first.","error");return}
      const values=formObject(form),button=byId("manualTemplateDownload");
      const year=years.find(item=>item.id===values.academic_year_id);
      const term=(state.boot.terms||[]).find(item=>item.id===values.term_id);
      const classRow=classes.find(item=>item.id===values.class_id);
      button.disabled=true;button.textContent="Preparing";
      setLoading(true);
      try{
        const pdf=await createManualReportTemplatePdf({
          academicYearId:year?.id||null,
          classId:classRow?.id||null,
          academicYearName:year?.name||"",
          termName:term?.name||"",
          className:classRow?.name||"",
          subjects:activeSubjects
        });
        const safeClass=(classRow?.name||"All_Classes").replace(/[^A-Za-z0-9_-]+/g,"_");
        downloadBlob(`${schoolReportPrefix()}_Manual_Report_Card_Template_${safeClass}.pdf`,pdf);
        closeModal();
        toast("Manual template downloaded",`${activeSubjects.length} subjects included.`);
      }catch(error){
        toast("Template not created",friendlyError(error),"error",6500);
        await reportClientError(error,{source:"manual_report_template"});
      }finally{
        setLoading(false);
        button.disabled=false;button.textContent="Download PDF template";
      }
    };
  }

  async function exportReportList() {
    const data=await rpc("list_report_cards_v6",{target_term_id:byId("reportTerm")?.value||null,target_class_id:byId("reportClass")?.value||null,
      target_status:byId("reportStatus")?.value||null,search_text:byId("reportSearch")?.value||"",archive_filter:"active",page_number:1,page_size:100});
    const headers=["report_number","student_name","admission_no","class_name","academic_year_name","term_name","average","status","updated_at"];
    downloadText("report-cards.csv",[headers.join(","),...(data.rows||[]).map(row=>headers.map(h=>csvCell(row[h])).join(","))].join("\n"),"text/csv");
  }


  function canBulkDownloadPublishedReports() {
    return ["system_admin","class_teacher","subject_teacher"].includes(role());
  }
  function safeArchiveSegment(value,fallback="report") {
    const cleaned=String(value||"").normalize("NFKD").replace(/[\u0300-\u036f]/g,"")
      .replace(/[^A-Za-z0-9._-]+/g,"_").replace(/^_+|_+$/g,"").slice(0,90);
    return cleaned||fallback;
  }
  function openBulkPublishedReportPackage() {
    if(!canBulkDownloadPublishedReports()){toast("Bulk download unavailable","Only the System Administrator and assigned teachers can download class report packages.","error");return}
    const selectedTerm=byId("reportTerm")?.value||activeTerm()?.id||"";
    const selectedClass=byId("reportClass")?.value||state.reportClassFilter||"";
    modal("Bulk Published Report Cards","Generate the latest official PDFs for one class and term, then download them in a single ZIP package.",`
      <form id="bulkPublishedReportsForm" class="form-stack">
        <div class="form-grid">
          <label class="field"><span>Term</span><select name="term_id" required>${optionList(state.boot.terms||[],"id","name",selectedTerm,"Select term")}</select></label>
          <label class="field"><span>Class</span><select name="class_id" required>${optionList(state.boot.classes||[],"id","name",selectedClass,"Select class")}</select></label>
        </div>
        <div class="template-information"><strong>Latest-format enforcement</strong><span>The system first regenerates each accessible published report with the current official design and Principal signature. If secure live regeneration is temporarily unavailable, it safely includes the previously published official PDF instead of failing the whole class package.</span></div>
        <div id="bulkPublishedReportsProgress" class="template-information hidden" aria-live="polite"><strong>Preparing package</strong><span id="bulkPublishedReportsProgressText">Waiting to start</span></div>
      </form>`,
      `<button class="button ghost" id="bulkPublishedReportsCancel" type="button">Cancel</button><button class="button primary" id="bulkPublishedReportsRun" type="button">Download class package</button>`,"small");
    byId("bulkPublishedReportsCancel").onclick=()=>{if(!state.bulkReportPackageBusy)closeModal()};
    byId("bulkPublishedReportsRun").onclick=downloadBulkPublishedReportPackage;
  }
  async function listAllPublishedReportsForClass(termId,classId) {
    const rows=[];let page=1,total=Infinity;
    while(rows.length<total){
      const data=await rpc("list_report_cards_v6",{
        target_term_id:termId,target_class_id:classId,target_status:"published",search_text:"",
        archive_filter:"active",page_number:page,page_size:100
      });
      const batch=(data.rows||[]).filter(row=>row.status==="published"&&!row.archived);
      rows.push(...batch);total=Number(data.total??rows.length);
      const pageSize=Math.max(1,Number(data.page_size||100));
      if(!batch.length||page*pageSize>=total)break;
      page+=1;
      if(page>1000)throw new Error("The published report list exceeded the safe pagination limit.");
    }
    return rows;
  }
  async function downloadBulkPublishedReportPackage() {
    if(state.bulkReportPackageBusy)return;
    if(!window.JSZip){toast("Bulk download unavailable","The packaged ZIP library did not load. Reload the system and try again.","error");return}
    const form=byId("bulkPublishedReportsForm");if(!form?.reportValidity())return;
    const values=formObject(form),term=(state.boot.terms||[]).find(item=>item.id===values.term_id),classRow=(state.boot.classes||[]).find(item=>item.id===values.class_id);
    if(!term||!classRow){toast("Package not created","Select a valid class and term.","error");return}
    const button=byId("bulkPublishedReportsRun"),cancel=byId("bulkPublishedReportsCancel"),progress=byId("bulkPublishedReportsProgress"),progressText=byId("bulkPublishedReportsProgressText");
    state.bulkReportPackageBusy=true;button.disabled=true;cancel.disabled=true;progress.classList.remove("hidden");
    try{
      progressText.textContent="Loading published reports";
      const rows=await listAllPublishedReportsForClass(term.id,classRow.id);
      if(!rows.length)throw new Error("No published report cards are available for this class and term, or your role is not assigned to them.");
      const zip=new window.JSZip(),folderName=safeArchiveSegment(`${classRow.name}_${term.name}`,"Published_Reports"),folder=zip.folder(folderName);
      const manifest=[];let completed=0,failed=0,storedRefreshes=0,fallbackDownloads=0;
      const canStoreOfficialPdf=can("publish_reports")&&["system_admin","class_teacher"].includes(role());
      for(const row of rows){
        completed+=1;progressText.textContent=`Preparing ${completed} of ${rows.length}: ${row.student_name||row.report_number||"report"}`;
        try{
          const editor=await rpc("get_report_editor",{target_report_id:row.id,target_enrollment_id:null,target_term_id:null});
          await enrichReportGradingGuide(editor);
          const publication=(editor.publications||[]).find(item=>!item.revoked_at);
          if(!publication)throw new Error("Active publication record not found");
          let pdf,storageStatus="downloaded_latest_not_stored";
          if(canStoreOfficialPdf){
            try{
              const generated=await createAndStoreOfficialPdf(editor,publication);pdf=generated.pdf;storageStatus="refreshed";storedRefreshes+=1;
            }catch(storageError){
              await reportClientError(storageError,{source:"bulk_class_pdf_storage_refresh",report_id:row.id,class_id:classRow.id,term_id:term.id});
              if(publication.storage_path){
                try{pdf=await downloadStoredOfficialReportPdf(publication);storageStatus="stored_official_fallback";fallbackDownloads+=1}
                catch(storedError){await reportClientError(storedError,{source:"bulk_class_pdf_stored_fallback",report_id:row.id,class_id:classRow.id,term_id:term.id});pdf=await createReportPdf(editor,publication);storageStatus="regenerated_not_stored";fallbackDownloads+=1}
              }else{pdf=await createReportPdf(editor,publication);storageStatus="regenerated_not_stored";fallbackDownloads+=1}
            }
          }else if(publication.storage_path){
            try{pdf=await downloadStoredOfficialReportPdf(publication);storageStatus="stored_official";fallbackDownloads+=1}
            catch(storedError){await reportClientError(storedError,{source:"bulk_class_pdf_stored_download",report_id:row.id,class_id:classRow.id,term_id:term.id});pdf=await createReportPdf(editor,publication);storageStatus="regenerated_not_stored";fallbackDownloads+=1}
          }else{pdf=await createReportPdf(editor,publication);storageStatus="regenerated_not_stored";fallbackDownloads+=1}
          const studentName=editor.student?.full_name||row.student_name||"Student",admission=editor.student?.admission_no||row.admission_no||"";
          const reportNumber=editor.report?.report_number||row.report_number||row.id;
          const filename=`${safeArchiveSegment(reportNumber,"Report")}_${safeArchiveSegment(admission,"Admission")}_${safeArchiveSegment(studentName,"Student")}.pdf`;
          folder.file(filename,pdf);
          manifest.push({report_number:reportNumber,student_name:studentName,admission_no:admission,class_name:classRow.name,term_name:term.name,status:"included",storage_refresh:storageStatus,file_name:filename,error:""});
        }catch(error){
          failed+=1;manifest.push({report_number:row.report_number||"",student_name:row.student_name||"",admission_no:row.admission_no||"",class_name:classRow.name,term_name:term.name,status:"failed",storage_refresh:"not_attempted",file_name:"",error:friendlyError(error)});
          await reportClientError(error,{source:"bulk_class_pdf_download",report_id:row.id,class_id:classRow.id,term_id:term.id});
        }
      }
      const included=manifest.filter(item=>item.status==="included");
      if(!included.length)throw new Error("None of the published reports could be generated. Review the report and Storage configuration, then try again.");
      const headers=["report_number","student_name","admission_no","class_name","term_name","status","storage_refresh","file_name","error"];
      zip.file("BULK_DOWNLOAD_MANIFEST.csv",[headers.join(","),...manifest.map(item=>headers.map(key=>csvCell(item[key])).join(","))].join("\n"));
      zip.file("README.txt",`${schoolDisplayName()} Published Report Cards\n\nClass: ${classRow.name}\nTerm: ${term.name}\nGenerated: ${new Date().toISOString()}\nReports included: ${included.length}\nFailed: ${failed}\nStored PDFs refreshed: ${storedRefreshes}\nStored or regenerated fallback downloads: ${fallbackDownloads}\n\nOnly reports accessible to the signed-in System Administrator or assigned teacher are included. See BULK_DOWNLOAD_MANIFEST.csv for details.\n`);
      progressText.textContent="Compressing ZIP package";
      const blob=await zip.generateAsync({type:"blob",compression:"DEFLATE",compressionOptions:{level:6}},metadata=>{if(progressText)progressText.textContent=`Compressing ZIP package: ${Math.round(metadata.percent)}%`});
      const date=new Date().toISOString().slice(0,10),filename=`Published_Report_Cards_${safeArchiveSegment(classRow.name,"Class")}_${safeArchiveSegment(term.name,"Term")}_${date}.zip`;
      downloadBlob(filename,blob);closeModal();
      toast(failed?"Class package downloaded with warnings":"Class package downloaded",`${included.length} published report card${included.length===1?"":"s"} included${failed?` • ${failed} failed and are listed in the manifest`:""}.`,failed?"warning":"success",9000);
    }catch(error){toast("Class package not created",friendlyError(error),"error",9000);await reportClientError(error,{source:"bulk_class_pdf_package",class_id:values.class_id,term_id:values.term_id})}
    finally{state.bulkReportPackageBusy=false;if(button)button.disabled=false;if(cancel)cancel.disabled=false;if(progress)progress.classList.add("hidden")}
  }

  async function createAndStoreOfficialPdf(editor,publication) {
    if(!can("publish_reports")||!["system_admin","class_teacher"].includes(role()))throw new Error("Only the assigned class teacher or System Administrator can store an official report PDF");
    if(!editor?.report?.id||!publication||publication.revoked_at)throw new Error("Active publication record not found");
    const pdf=await createReportPdf(editor,publication);
    const checksum=await sha256(pdf),safeName=(editor.report.report_number||editor.report.id).replace(/[^A-Za-z0-9_-]/g,"_");
    const previousPath=publication.storage_path||"";
    const path=`${editor.report.id}/${safeName}-v${editor.report.version}-${Date.now()}.pdf`;
    const {error}=await state.client.storage.from(CONFIG.pdfBucket).upload(path,pdf,{contentType:"application/pdf",upsert:false,cacheControl:"31536000"});
    if(error)throw error;
    try{
      await rpc("register_report_pdf",{target_report_id:editor.report.id,target_storage_path:path,target_checksum:checksum,target_page_count:1});
    }catch(error){
      await removePrivateStorageObjects(CONFIG.pdfBucket,[path],{source:"report_pdf_registration_rollback",report_id:editor.report.id},true);throw error;
    }
    state.pdfUrls.delete(path);
    if(previousPath&&previousPath!==path){
      state.pdfUrls.delete(previousPath);
      await removePrivateStorageObjects(CONFIG.pdfBucket,[previousPath],{source:"report_pdf_replacement_cleanup",report_id:editor.report.id},true);
    }
    return {pdf,safeName,path};
  }

  async function refreshPublishedStudentReportPdfs(student) {
    if(!student?.id||!student?.admission_no)return {updated:0,failed:0};
    let rows=[];
    try{
      const data=await rpc("list_report_cards_v6",{
        target_term_id:null,target_class_id:null,target_status:"published",search_text:student.admission_no,
        archive_filter:"active",page_number:1,page_size:100
      });
      rows=(data.rows||[]).filter(row=>row.student_id===student.id&&!row.archived&&row.status==="published");
    }catch(error){
      await reportClientError(error,{source:"student_photo_pdf_refresh",stage:"list",student_id:student.id});
      return {updated:0,failed:1};
    }
    let updated=0,failed=0;
    for(const row of rows){
      try{
        const editor=await rpc("get_report_editor",{target_report_id:row.id,target_enrollment_id:null,target_term_id:null});
        await enrichReportGradingGuide(editor);
        const publication=(editor.publications||[]).find(item=>!item.revoked_at);
        if(!publication)continue;
        await createAndStoreOfficialPdf(editor,publication);updated+=1;
      }catch(error){
        failed+=1;await reportClientError(error,{source:"student_photo_pdf_refresh",stage:"generate",student_id:student.id,report_id:row.id});
      }
    }
    return {updated,failed};
  }

  async function generateAndUploadOfficialPdf() {
    const editor=state.reportEditor,publication=(editor.publications||[]).find(p=>!p.revoked_at);
    if(!publication)throw new Error("Publication record not found");
    setLoading(true);
    try{
      const {pdf,safeName}=await createAndStoreOfficialPdf(editor,publication);
      state.reportEditor=await rpc("get_report_editor",{target_report_id:editor.report.id,target_enrollment_id:null,target_term_id:null});
      await enrichReportGradingGuide(state.reportEditor);
      renderReportEditor();downloadBlob(`${safeName}.pdf`,pdf);toast("Official PDF created");
    }catch(error){toast("PDF not created",friendlyError(error),"error");await reportClientError(error,{source:"pdf",report_id:editor.report.id})}
    finally{setLoading(false)}
  }
  async function downloadLatestOfficialPdf(reportId) {
    if(!reportId)return;
    setLoading(true);
    try{
      const editor=state.reportEditor?.report?.id===reportId
        ?state.reportEditor
        :await rpc("get_report_editor",{target_report_id:reportId,target_enrollment_id:null,target_term_id:null});
      const publication=(editor.publications||[]).find(item=>!item.revoked_at);
      if(!publication)throw new Error("Active publication record not found");
      let pdf,safeName=(editor.report.report_number||editor.report.id).replace(/[^A-Za-z0-9_-]/g,"_"),usedStoredFallback=false,refreshError=null;
      const canRefreshStoredPdf=can("publish_reports")&&["system_admin","class_teacher"].includes(role());
      if(canRefreshStoredPdf){
        try{
          const generated=await createAndStoreOfficialPdf(editor,publication);
          pdf=generated.pdf;safeName=generated.safeName;
          if(state.reportEditor?.report?.id===reportId){
            state.reportEditor=await rpc("get_report_editor",{target_report_id:reportId,target_enrollment_id:null,target_term_id:null});
            await enrichReportGradingGuide(state.reportEditor);
            renderReportEditor();
          }
        }catch(error){
          refreshError=error;
          if(publication.storage_path){pdf=await downloadStoredOfficialReportPdf(publication);usedStoredFallback=true}
          else throw error;
        }
      }else if(publication.storage_path){
        try{pdf=await downloadStoredOfficialReportPdf(publication);usedStoredFallback=true}
        catch(error){refreshError=error;pdf=await createReportPdf(editor,publication)}
      }else pdf=await createReportPdf(editor,publication);
      downloadBlob(`${safeName}.pdf`,pdf);
      if(refreshError)await reportClientError(refreshError,{source:"latest_pdf_regeneration_fallback",report_id:reportId});
      toast(usedStoredFallback?"Official PDF downloaded":"Latest official PDF downloaded",usedStoredFallback?"The secure, previously published official PDF was downloaded because live regeneration was temporarily unavailable. No report data was lost.":"Current positions, colours, typography, photograph, template, and Principal signature were applied.",usedStoredFallback?"warning":"success",8500);
    }catch(error){toast("PDF unavailable",friendlyError(error),"error",6500);await reportClientError(error,{source:"latest_pdf_download",report_id:reportId})}
    finally{setLoading(false)}
  }
  function downloadBlob(filename,blob) {
    const url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1500);
  }
  async function sha256(blob) {
    const bytes=await blob.arrayBuffer(),hash=await crypto.subtle.digest("SHA-256",bytes);
    return [...new Uint8Array(hash)].map(b=>b.toString(16).padStart(2,"0")).join("");
  }
  async function loadImage(url) {
    return new Promise((resolve,reject)=>{const image=new Image();image.crossOrigin="anonymous";image.onload=()=>resolve(image);image.onerror=()=>reject(new Error("Image could not be decoded"));image.src=url});
  }
  function normaliseStorageObjectPath(bucket,path) {
    let value=String(path||"").trim();
    if(!value)return "";
    if(value.startsWith("data:")||value.startsWith("assets/"))return value;
    try{
      if(/^https?:\/\//i.test(value)){
        const parsed=new URL(value,location.href),markers=[
          `/storage/v1/object/sign/${bucket}/`,
          `/storage/v1/object/authenticated/${bucket}/`,
          `/storage/v1/object/public/${bucket}/`,
          `/storage/v1/object/${bucket}/`
        ];
        for(const marker of markers){
          const index=parsed.pathname.indexOf(marker);
          if(index>=0){value=parsed.pathname.slice(index+marker.length);break}
        }
      }
    }catch(_){/* Keep the supplied path and continue with safe normalisation. */}
    value=value.split("?")[0].split("#")[0].replace(/^\/+/,"");
    if(value.startsWith(`${bucket}/`))value=value.slice(bucket.length+1);
    try{return decodeURIComponent(value)}catch(_){return value}
  }
  function privateBlobWithDetectedType(blob,path) {
    if(!blob)return blob;
    if(blob.type&&blob.type!=="application/octet-stream")return blob;
    const lower=String(path||"").toLowerCase();
    const type=lower.endsWith(".png")?"image/png":lower.endsWith(".webp")?"image/webp":lower.endsWith(".jpg")||lower.endsWith(".jpeg")?"image/jpeg":lower.endsWith(".pdf")?"application/pdf":"";
    return type?new Blob([blob],{type}):blob;
  }
  async function decodePrivateImageBlob(blob,path,label) {
    const typed=privateBlobWithDetectedType(blob,path),objectUrl=URL.createObjectURL(typed);
    try{return await loadImage(objectUrl)}
    catch(firstError){
      try{
        const dataUrl=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result||""));reader.onerror=()=>reject(reader.error||firstError);reader.readAsDataURL(typed)});
        return await loadImage(dataUrl);
      }catch(secondError){throw new Error(`${label} was downloaded but could not be decoded as an image.`,{cause:secondError})}
    }finally{URL.revokeObjectURL(objectUrl)}
  }
  async function downloadPrivateStorageBlob(bucket,path,label="Private file",maxAttempts=4) {
    const raw=String(path||"").trim(),normalised=normaliseStorageObjectPath(bucket,raw);
    const candidates=[...new Set([normalised,raw].filter(Boolean))];
    if(!candidates.length)throw new Error(`${label} path is missing.`);
    let lastError=null;
    for(let attempt=0;attempt<maxAttempts;attempt+=1){
      for(const candidate of candidates){
        try{
          if(/^https?:\/\//i.test(candidate)){
            const response=await fetch(candidate,{cache:"no-store"});
            if(!response.ok)throw new Error(`${label} request failed with status ${response.status}`);
            const blob=await response.blob();if(!blob.size)throw new Error(`${label} is empty`);return privateBlobWithDetectedType(blob,normalised||candidate);
          }
          const {data,error}=await state.client.storage.from(bucket).download(candidate);
          if(error||!data||!data.size)throw error||new Error(`${label} is unavailable or empty`);
          return privateBlobWithDetectedType(data,candidate);
        }catch(error){lastError=error}
        try{
          storageUrlCache(bucket).delete(candidate);
          const url=await signedUrl(bucket,candidate,900),response=await fetch(url,{cache:"no-store"});
          if(!response.ok)throw new Error(`${label} signed request failed with status ${response.status}`);
          const blob=await response.blob();if(!blob.size)throw new Error(`${label} is empty`);return privateBlobWithDetectedType(blob,candidate);
        }catch(error){lastError=error}
      }
      if(attempt<maxAttempts-1)await sleep(250*(attempt+1));
    }
    throw new Error(`${label} could not be loaded from secure Storage after ${maxAttempts} attempts. Check the connection and Storage access, then try again.`,{cause:lastError});
  }
  async function loadPrivateImageAsset(bucket,path,label="Private image") {
    if(!path)return null;
    const normalised=normaliseStorageObjectPath(bucket,path),blob=await downloadPrivateStorageBlob(bucket,path,label,4);
    return await decodePrivateImageBlob(blob,normalised||path,label);
  }
  async function downloadStoredOfficialReportPdf(publication,label="The stored official report PDF") {
    const path=publication?.storage_path||"";
    if(!path)throw new Error("No stored official report PDF is registered for this publication.");
    const blob=await downloadPrivateStorageBlob(CONFIG.pdfBucket,path,label,4),bytes=new Uint8Array(await blob.arrayBuffer());
    const signature=String.fromCharCode(...bytes.slice(0,5));
    if(bytes.length<5||signature!=="%PDF-")throw new Error(`${label} is not a valid PDF file.`);
    return new Blob([bytes],{type:"application/pdf"});
  }
  async function downloadStoredCertificatePdfBlob(certificate,label="The stored official certificate PDF") {
    const path=certificate?.pdf_storage_path||"";
    if(!path)throw new Error("No stored official certificate PDF is registered for this certificate.");
    const blob=await downloadPrivateStorageBlob(CONFIG.certificatePdfBucket,path,label,4),bytes=new Uint8Array(await blob.arrayBuffer());
    const signature=String.fromCharCode(...bytes.slice(0,5));
    if(bytes.length<5||signature!=="%PDF-")throw new Error(`${label} is not a valid PDF file.`);
    return new Blob([bytes],{type:"application/pdf"});
  }
  function drawImageContain(ctx,image,x,y,width,height) {
    const scale=Math.min(width/image.width,height/image.height),drawWidth=image.width*scale,drawHeight=image.height*scale;ctx.drawImage(image,x+(width-drawWidth)/2,y+(height-drawHeight)/2,drawWidth,drawHeight);
  }
  const signatureRenderCache=new WeakMap();
  function preparedSignatureCanvas(image) {
    if(!image)return null;
    if(signatureRenderCache.has(image))return signatureRenderCache.get(image);
    try{
      const width=image.naturalWidth||image.width,height=image.naturalHeight||image.height;
      if(!width||!height)return image;
      const source=document.createElement("canvas");source.width=width;source.height=height;
      const sourceCtx=source.getContext("2d",{willReadFrequently:true});sourceCtx.drawImage(image,0,0,width,height);
      const pixels=sourceCtx.getImageData(0,0,width,height),data=pixels.data;
      let minX=width,minY=height,maxX=-1,maxY=-1;
      for(let y=0;y<height;y+=1){for(let x=0;x<width;x+=1){
        const offset=(y*width+x)*4,r=data[offset],g=data[offset+1],b=data[offset+2],a=data[offset+3];
        if(a<=10||r>246&&g>246&&b>246){data[offset+3]=0;continue}
        minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);
      }}
      if(maxX<minX||maxY<minY){signatureRenderCache.set(image,image);return image}
      sourceCtx.putImageData(pixels,0,0);
      const padding=4,sx=Math.max(0,minX-padding),sy=Math.max(0,minY-padding),sw=Math.min(width-sx,maxX-minX+1+padding*2),sh=Math.min(height-sy,maxY-minY+1+padding*2);
      const cropped=document.createElement("canvas");cropped.width=sw;cropped.height=sh;cropped.getContext("2d").drawImage(source,sx,sy,sw,sh,0,0,sw,sh);
      signatureRenderCache.set(image,cropped);return cropped;
    }catch(_){signatureRenderCache.set(image,image);return image}
  }
  function drawSignatureOnLine(ctx,image,left,right,lineY,maxHeight=100,lineColour="#5f708b",lineWidth=1.2) {
    ctx.save();ctx.strokeStyle=lineColour;ctx.lineWidth=lineWidth;ctx.beginPath();ctx.moveTo(left,lineY);ctx.lineTo(right,lineY);ctx.stroke();
    if(image){
      const prepared=preparedSignatureCanvas(image),width=prepared.width||image.width,height=prepared.height||image.height;
      if(width&&height){const scale=Math.min((right-left)*.78/width,maxHeight/height),drawWidth=width*scale,drawHeight=height*scale,x=(left+right-drawWidth)/2,y=lineY-drawHeight+3;ctx.drawImage(prepared,x,y,drawWidth,drawHeight)}
    }
    ctx.restore();
  }
  function drawImageCover(ctx,image,x,y,width,height) {
    const scale=Math.max(width/image.width,height/image.height),drawWidth=image.width*scale,drawHeight=image.height*scale;
    ctx.drawImage(image,x+(width-drawWidth)/2,y+(height-drawHeight)/2,drawWidth,drawHeight);
  }
  function drawStaffIdPhotoCover(ctx,image,x,y,width,height) {
    // r21 staff ID portrait cover contract: object-fit: cover; object-position: 50% 20%; overflow: hidden.
    const scale=Math.max(width/image.width,height/image.height),drawWidth=image.width*scale,drawHeight=image.height*scale;
    const drawX=x+(width-drawWidth)*0.5,drawY=y+(height-drawHeight)*0.2;
    ctx.save();ctx.beginPath();ctx.rect(x,y,width,height);ctx.clip();ctx.drawImage(image,drawX,drawY,drawWidth,drawHeight);ctx.restore();
  }
  function drawWrapped(ctx,text,x,y,maxWidth,lineHeight,maxLines=3) {
    const words=String(text||"").split(/\s+/);let line="",lines=0;
    for(const word of words){
      const test=line?`${line} ${word}`:word;
      if(ctx.measureText(test).width>maxWidth&&line){ctx.fillText(line,x,y);y+=lineHeight;lines++;line=word;if(lines>=maxLines)return y}
      else line=test;
    }
    if(line&&lines<maxLines){ctx.fillText(line,x,y);y+=lineHeight}
    return y;
  }
  async function qrCanvas(text) {
    const box=byId("qrScratch");box.innerHTML="";
    if(!window.QRCode)return null;
    new window.QRCode(box,{text,width:190,height:190,correctLevel:window.QRCode.CorrectLevel.M});
    await sleep(80);
    const canvas=box.querySelector("canvas");if(canvas)return canvas;
    const img=box.querySelector("img");if(img)return img;
    return null;
  }
  const REPORT_FONT_OPTIONS=Object.freeze({
    "Times New Roman":'"Times New Roman", Times, "Liberation Serif", serif',
    "Arial":'Arial, Helvetica, "Liberation Sans", sans-serif',
    "Calibri":'Calibri, Carlito, Arial, sans-serif',
    "Georgia":'Georgia, "Times New Roman", serif',
    "Verdana":'Verdana, Geneva, sans-serif',
    "Tahoma":'Tahoma, Arial, sans-serif'
  });
  const REPORT_COMMENT_COLOUR="#0a2f73";
  const REPORT_COMMENT_HEADING_COLOUR="#000000";
  const REPORT_NEXT_TERM_REOPENING_COLOUR="#c00000";
  const REPORT_RESULT_COLOURS=Object.freeze({
    score:"#083b78",
    total:"#b00020",
    grade:"#006400",
    position:"#b00020",
    remark:"#083b78"
  });

  function reportTableLayout(ctx,subjects,columns,bodyTop,maximumTableBottom=1086) {
    const source=Array.isArray(subjects)?subjects.filter(Boolean):[];
    const displaySubjects=[...source,null]; // Always retain exactly one blank line box after the last subject.
    setReportFont(ctx,20,"normal");
    const subjectLineCounts=displaySubjects.map(subject=>subject
      ?reportTextLines(ctx,subject.subject_name||subject.name||"",columns[1]-columns[0]-16,2).length
      :1
    );
    const weights=subjectLineCounts.map(lines=>lines>1?1.34:1);
    const preferredRowUnit=56,maximumHeight=Math.max(preferredRowUnit,maximumTableBottom-bodyTop);
    const desiredHeight=Math.max(preferredRowUnit,weights.reduce((sum,value)=>sum+value,0)*preferredRowUnit);
    const availableHeight=Math.min(maximumHeight,desiredHeight);
    return {displaySubjects,subjectLineCounts,weights,availableHeight,tableBottom:bodyTop+availableHeight};
  }

  function reportBodyFontName() {
    const requested=String(state.boot?.school?.report_body_font||"Times New Roman");
    return Object.prototype.hasOwnProperty.call(REPORT_FONT_OPTIONS,requested)?requested:"Times New Roman";
  }

  function reportBodyFontFamily() {
    return REPORT_FONT_OPTIONS[reportBodyFontName()]||REPORT_FONT_OPTIONS["Times New Roman"];
  }

  function reportBodyFontSize() {
    const requested=Number(state.boot?.school?.report_body_font_size??11);
    return Number.isFinite(requested)?Math.min(16,Math.max(8,requested)):11;
  }

  function reportBodyFontScale() {
    return reportBodyFontSize()/11;
  }

  function reportFontOptionsHtml(selected="Times New Roman") {
    const current=Object.prototype.hasOwnProperty.call(REPORT_FONT_OPTIONS,selected)?selected:"Times New Roman";
    return Object.keys(REPORT_FONT_OPTIONS).map(name=>`<option value="${attr(name)}" ${name===current?"selected":""}>${esc(name)}</option>`).join("");
  }

  async function ensureReportBodyFontReady() {
    if(!document.fonts?.load)return;
    const safeName=reportBodyFontName().replace(/["\\]/g,"");
    await document.fonts.load(`${reportBodyFontSize()}pt "${safeName}"`).catch(()=>{});
  }


  function reportTemplateGroup(rangeKey) {
    return REPORT_TEMPLATE_GROUPS.find(item=>item.key===rangeKey)||null;
  }

  function normaliseClassName(value="") {
    return String(value||"").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/[^a-z0-9]+/g," ").trim();
  }

  function reportTemplateRangeForClass(className="") {
    let name=normaliseClassName(className);
    if(!name)return "";
    if(/\b(?:kg|kindergarten|nursery)\s*(?:[12]|one|two)(?:\s*[a-z])?\b/.test(name)||/\b(creche|day care|daycare|preschool|pre school|nursery|kindergarten|kg|reception)\b/.test(name))return "early_years";
    const wordLevels={one:1,two:2,three:3,four:4,five:5,six:6,seven:7,eight:8,nine:9};
    const wordMatch=name.match(/\b(?:basic|grade|primary|class)\s*(one|two|three|four|five|six|seven|eight|nine)\b/);
    if(wordMatch)name=name.replace(wordMatch[1],String(wordLevels[wordMatch[1]]));
    const basic=name.match(/\b(?:basic|grade|primary|class)\s*([1-9])(?:\s*[a-z])?\b/);
    if(basic){const level=Number(basic[1]);return level<=6?"basic_1_6":"basic_7_9"}
    const jhsWord=name.match(/\b(?:jhs|junior high(?: school)?)\s*(one|two|three)\b/);
    if(jhsWord)return "basic_7_9";
    const jhs=name.match(/\b(?:jhs|junior high(?: school)?)\s*([1-3])(?:\s*[a-z])?\b/);
    if(jhs)return "basic_7_9";
    return "";
  }

  function templateClassesForRange(rangeKey) {
    return (state.boot?.classes||[]).filter(item=>!item.deleted_at&&item.active!==false&&reportTemplateRangeForClass(item.name)===rangeKey);
  }

  function readableBytes(value) {
    const bytes=Number(value||0);if(!bytes)return "0 B";
    const units=["B","KB","MB","GB"];const index=Math.min(units.length-1,Math.floor(Math.log(bytes)/Math.log(1024)));
    return `${number(bytes/Math.pow(1024,index),index?1:0)} ${units[index]}`;
  }

  async function loadReportCardTemplates(force=false) {
    if(!state.client)return [];
    if(!force&&Array.isArray(state.reportTemplates)&&Date.now()-state.reportTemplatesLoadedAt<60000)return state.reportTemplates;
    const rows=await rpc("list_report_card_templates");
    state.reportTemplates=Array.isArray(rows)?rows:[];
    state.reportTemplatesLoadedAt=Date.now();
    return state.reportTemplates;
  }

  async function currentReportTemplateForClass(className,force=false) {
    const rangeKey=reportTemplateRangeForClass(className);
    if(!rangeKey)return null;
    const rows=await loadReportCardTemplates(force);
    return rows.find(item=>item.range_key===rangeKey&&item.active!==false&&item.storage_path)||null;
  }

  function validateReportTemplateFile(file) {
    if(!file)throw new Error("Choose a PDF or DOCX report-card template.");
    if(file.size<=0)throw new Error("The selected template file is empty.");
    if(file.size>REPORT_TEMPLATE_MAX_BYTES)throw new Error("The template file must not exceed 20 MB.");
    const extension=String(file.name||"").split(".").pop().toLowerCase();
    const mimeType=extension==="pdf"
      ?"application/pdf"
      :extension==="docx"
        ?"application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        :"";
    if(!mimeType)throw new Error("Only PDF and DOCX files are accepted.");
    const browserMime=String(file.type||"").toLowerCase();
    if(browserMime&&browserMime!=="application/octet-stream"){
      const browserExtension=REPORT_TEMPLATE_MIME_TYPES[browserMime];
      if(!browserExtension||browserExtension!==extension)throw new Error("The selected file type does not match its PDF or DOCX filename.");
    }
    return {mimeType,extension};
  }

  const REPORT_LOGICAL_WIDTH=1240,REPORT_LOGICAL_HEIGHT=1754;
  const REPORT_PRINT_WIDTH=2480,REPORT_PRINT_HEIGHT=3508,REPORT_PRINT_SCALE=2;
  function createReportPrintCanvas() {
    const canvas=document.createElement("canvas");canvas.width=REPORT_PRINT_WIDTH;canvas.height=REPORT_PRINT_HEIGHT;
    const ctx=canvas.getContext("2d",{alpha:false});
    if(!ctx)throw new Error("The browser could not create the print-quality report canvas.");
    ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality="high";
    ctx.scale(REPORT_PRINT_SCALE,REPORT_PRINT_SCALE);
    return {canvas,ctx};
  }
  function normaliseTemplateCanvas(source) {
    const canvas=document.createElement("canvas");canvas.width=REPORT_PRINT_WIDTH;canvas.height=REPORT_PRINT_HEIGHT;
    const ctx=canvas.getContext("2d");ctx.fillStyle="#ffffff";ctx.fillRect(0,0,canvas.width,canvas.height);
    const ratio=Math.min(canvas.width/source.width,canvas.height/source.height);
    const width=source.width*ratio,height=source.height*ratio;
    ctx.drawImage(source,(canvas.width-width)/2,(canvas.height-height)/2,width,height);
    return canvas;
  }

  // r23 PDF.js template security hardening: never permit eval-backed PDF parsing for uploaded templates.
  async function renderPdfTemplateBlob(blob) {
    if(!window.pdfjsLib?.getDocument)throw new Error("PDF template rendering service is unavailable. Reload the system and try again.");
    window.pdfjsLib.GlobalWorkerOptions.workerSrc="assets/vendor/pdfjs-3.11.174.worker.min.js";
    const bytes=new Uint8Array(await blob.arrayBuffer());let pdf;
    try{pdf=await window.pdfjsLib.getDocument({data:bytes.slice(),isEvalSupported:false}).promise}
    catch(workerError){
      try{pdf=await window.pdfjsLib.getDocument({data:bytes.slice(),disableWorker:true,isEvalSupported:false}).promise}
      catch(renderError){throw new Error("The report-card PDF template could not be rendered.",{cause:renderError||workerError})}
    }
    if(pdf.numPages<1)throw new Error("The PDF template has no pages.");
    const page=await pdf.getPage(1),base=page.getViewport({scale:1});
    const scale=Math.min(REPORT_PRINT_WIDTH/base.width,REPORT_PRINT_HEIGHT/base.height);
    const viewport=page.getViewport({scale});
    const source=document.createElement("canvas");source.width=Math.ceil(viewport.width);source.height=Math.ceil(viewport.height);
    await page.render({canvasContext:source.getContext("2d"),viewport}).promise;
    try{await pdf.destroy()}catch(_){}
    return normaliseTemplateCanvas(source);
  }

  async function waitForTemplateImages(root) {
    const images=[...root.querySelectorAll("img")];
    await Promise.all(images.map(image=>image.complete?Promise.resolve():new Promise(resolve=>{
      const done=()=>resolve();image.addEventListener("load",done,{once:true});image.addEventListener("error",done,{once:true});setTimeout(done,3500);
    })));
    if(document.fonts?.ready)await document.fonts.ready.catch(()=>{});
  }

  async function renderDocxTemplateBlob(blob) {
    if(!window.docx?.renderAsync||!window.html2canvas)throw new Error("DOCX template rendering service is unavailable. Reload the system and try again.");
    const host=document.createElement("div");
    host.className="docx-template-render-host";
    host.style.cssText="position:fixed;left:-100000px;top:0;width:794px;background:#fff;z-index:-1;visibility:visible;";
    document.body.append(host);
    try{
      await window.docx.renderAsync(await blob.arrayBuffer(),host,null,{
        className:"nis-docx-template",inWrapper:true,ignoreWidth:false,ignoreHeight:false,ignoreFonts:false,
        breakPages:true,ignoreLastRenderedPageBreak:false,useBase64URL:true,renderChanges:false,renderComments:false,renderAltChunks:false,experimental:false
      });
      await waitForTemplateImages(host);
      const page=host.querySelector("section.nis-docx-template")||host.querySelector(".nis-docx-template-wrapper > section")||host.firstElementChild;
      if(!page)throw new Error("The DOCX template could not be rendered.");
      const source=await window.html2canvas(page,{backgroundColor:"#ffffff",scale:3.15,useCORS:true,allowTaint:false,logging:false,windowWidth:Math.max(794,page.scrollWidth),windowHeight:Math.max(1123,page.scrollHeight)});
      return normaliseTemplateCanvas(source);
    }finally{host.remove()}
  }

  async function renderReportTemplateBlob(blob,mimeType) {
    if(mimeType==="application/pdf")return renderPdfTemplateBlob(blob);
    if(mimeType==="application/vnd.openxmlformats-officedocument.wordprocessingml.document")return renderDocxTemplateBlob(blob);
    throw new Error("Unsupported report-card template format.");
  }

  function validateCertificateTemplateFile(file) {
    if(!file)throw new Error("Choose a PDF or DOCX certificate template.");
    if(file.size<=0)throw new Error("The selected certificate template is empty.");
    if(file.size>CERTIFICATE_TEMPLATE_MAX_BYTES)throw new Error("The certificate template must not exceed 20 MB.");
    const extension=String(file.name||"").split(".").pop().toLowerCase();
    const mimeType=extension==="pdf"
      ?"application/pdf"
      :extension==="docx"
        ?"application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        :"";
    if(!mimeType)throw new Error("Only PDF and DOCX certificate templates are accepted.");
    const browserMime=String(file.type||"").toLowerCase();
    if(browserMime&&browserMime!=="application/octet-stream"){
      const browserExtension=REPORT_TEMPLATE_MIME_TYPES[browserMime];
      if(!browserExtension||browserExtension!==extension)throw new Error("The selected certificate file type does not match its filename.");
    }
    return {mimeType,extension};
  }

  function normaliseCertificateTemplateCanvas(source) {
    const canvas=document.createElement("canvas");canvas.width=1754;canvas.height=1240;
    const ctx=canvas.getContext("2d");ctx.fillStyle="#ffffff";ctx.fillRect(0,0,canvas.width,canvas.height);
    const ratio=Math.min(canvas.width/source.width,canvas.height/source.height);
    const width=source.width*ratio,height=source.height*ratio;
    ctx.drawImage(source,(canvas.width-width)/2,(canvas.height-height)/2,width,height);
    return canvas;
  }

  async function renderCertificatePdfTemplateBlob(blob) {
    if(!window.pdfjsLib?.getDocument)throw new Error("PDF certificate-template rendering service is unavailable. Reload and try again.");
    window.pdfjsLib.GlobalWorkerOptions.workerSrc="assets/vendor/pdfjs-3.11.174.worker.min.js";
    const bytes=new Uint8Array(await blob.arrayBuffer());let pdf;
    try{pdf=await window.pdfjsLib.getDocument({data:bytes.slice(),isEvalSupported:false}).promise}
    catch(workerError){try{pdf=await window.pdfjsLib.getDocument({data:bytes.slice(),disableWorker:true,isEvalSupported:false}).promise}catch(renderError){throw new Error("The certificate PDF template could not be rendered.",{cause:renderError||workerError})}}
    if(pdf.numPages<1)throw new Error("The certificate PDF template has no pages.");
    const page=await pdf.getPage(1),base=page.getViewport({scale:1});
    const scale=Math.min(1754/base.width,1240/base.height)*2;
    const viewport=page.getViewport({scale});
    const source=document.createElement("canvas");source.width=Math.ceil(viewport.width);source.height=Math.ceil(viewport.height);
    await page.render({canvasContext:source.getContext("2d"),viewport}).promise;
    try{await pdf.destroy()}catch(_){}
    return normaliseCertificateTemplateCanvas(source);
  }

  async function renderCertificateDocxTemplateBlob(blob) {
    if(!window.docx?.renderAsync||!window.html2canvas)throw new Error("DOCX certificate-template rendering service is unavailable. Reload and try again.");
    const host=document.createElement("div");
    host.className="docx-template-render-host";
    host.style.cssText="position:fixed;left:-100000px;top:0;width:1123px;background:#fff;z-index:-1;visibility:visible;";
    document.body.append(host);
    try{
      await window.docx.renderAsync(await blob.arrayBuffer(),host,null,{
        className:"nis-certificate-docx-template",inWrapper:true,ignoreWidth:false,ignoreHeight:false,ignoreFonts:false,
        breakPages:true,ignoreLastRenderedPageBreak:false,useBase64URL:true,renderChanges:false,renderComments:false,renderAltChunks:false,experimental:false
      });
      await waitForTemplateImages(host);
      const page=host.querySelector("section.nis-certificate-docx-template")||host.querySelector(".nis-certificate-docx-template-wrapper > section")||host.firstElementChild;
      if(!page)throw new Error("The DOCX certificate template could not be rendered.");
      const source=await window.html2canvas(page,{backgroundColor:"#ffffff",scale:2,useCORS:true,allowTaint:false,logging:false,windowWidth:Math.max(1123,page.scrollWidth),windowHeight:Math.max(794,page.scrollHeight)});
      return normaliseCertificateTemplateCanvas(source);
    }finally{host.remove()}
  }

  function resolveCertificateTemplateMimeType(template,blob) {
    const configured=String(template?.mime_type||"").toLowerCase();
    if(configured==="application/pdf"||configured==="application/vnd.openxmlformats-officedocument.wordprocessingml.document")return configured;
    const blobType=String(blob?.type||"").toLowerCase();
    if(blobType==="application/pdf"||blobType==="application/vnd.openxmlformats-officedocument.wordprocessingml.document")return blobType;
    const name=String(template?.original_name||template?.storage_path||"").toLowerCase().split("?")[0];
    if(name.endsWith(".pdf"))return "application/pdf";
    if(name.endsWith(".docx"))return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    throw new Error("The certificate-template file format could not be identified.");
  }

  async function renderCertificateTemplateBlob(blob,mimeType) {
    if(mimeType==="application/pdf")return renderCertificatePdfTemplateBlob(blob);
    if(mimeType==="application/vnd.openxmlformats-officedocument.wordprocessingml.document")return renderCertificateDocxTemplateBlob(blob);
    throw new Error("Unsupported certificate-template format.");
  }

  async function storedCertificateTemplateCanvas(template) {
    if(!template?.storage_path)return null;
    const cacheKey=`${template.storage_path}:${template.checksum||template.updated_at||template.version||""}`;
    if(state.certificateTemplateCanvases.has(cacheKey))return state.certificateTemplateCanvases.get(cacheKey);
    const {data,error}=await state.client.storage.from(CONFIG.certificateTemplateBucket).download(template.storage_path);
    if(error)throw new Error("The uploaded certificate template could not be downloaded.",{cause:error});
    if(!data||data.size<=0)throw new Error("The uploaded certificate template is empty.");
    const mimeType=resolveCertificateTemplateMimeType(template,data);
    const canvas=await renderCertificateTemplateBlob(data,mimeType);
    state.certificateTemplateCanvases.set(cacheKey,canvas);
    return canvas;
  }

  function resolveReportTemplateMimeType(template,blob) {
    const configured=String(template?.mime_type||"").toLowerCase();
    if(configured==="application/pdf"||configured==="application/vnd.openxmlformats-officedocument.wordprocessingml.document")return configured;
    const blobType=String(blob?.type||"").toLowerCase();
    if(blobType==="application/pdf"||blobType==="application/vnd.openxmlformats-officedocument.wordprocessingml.document")return blobType;
    const name=String(template?.original_name||template?.storage_path||"").toLowerCase().split("?")[0];
    if(name.endsWith(".pdf"))return "application/pdf";
    if(name.endsWith(".docx"))return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    throw new Error("The report-card template file format could not be identified.");
  }

  async function storedReportTemplateCanvas(template) {
    if(!template?.storage_path)return null;
    const cacheKey=`${template.storage_path}:${template.checksum||template.updated_at||template.version||""}`;
    if(state.templateCanvases.has(cacheKey))return state.templateCanvases.get(cacheKey);
    const {data,error}=await state.client.storage.from(CONFIG.templateBucket).download(template.storage_path);
    if(error)throw new Error("The uploaded report-card template could not be downloaded.",{cause:error});
    if(!data||data.size<=0)throw new Error("The uploaded report-card template is empty.");
    const mimeType=resolveReportTemplateMimeType(template,data);
    const canvas=await renderReportTemplateBlob(data,mimeType);
    state.templateCanvases.clear();state.templateCanvases.set(cacheKey,canvas);
    return canvas;
  }

  let builtInReportTemplatePromise=null;

  async function builtInReportTemplateCanvas() {
    if(!builtInReportTemplatePromise){
      builtInReportTemplatePromise=(async()=>{
        const pdfPath=String(CONFIG.defaultReportTemplatePath||"").replace(/\.png(?:\?.*)?$/i,".pdf");
        if(pdfPath&&pdfPath!==CONFIG.defaultReportTemplatePath){
          try{
            const response=await fetch(pdfPath,{cache:"no-store"});
            if(response.ok)return renderPdfTemplateBlob(await response.blob());
          }catch(_){}
        }
        return normaliseTemplateCanvas(await loadImage(CONFIG.defaultReportTemplatePath));
      })().catch(error=>{builtInReportTemplatePromise=null;throw error});
    }
    return builtInReportTemplatePromise;
  }

  async function resolveAssignedReportTemplate(className) {
    const template=await currentReportTemplateForClass(className);
    if(!template){
      try{return {template:null,templateBackground:await builtInReportTemplateCanvas(),templateSource:"built_in"}}
      catch(error){
        await reportClientError(error,{source:"built_in_report_template_load"});
        return {template:null,templateBackground:null,templateSource:"programmatic_fallback",templateLoadError:true};
      }
    }
    try{
      return {template,templateBackground:await storedReportTemplateCanvas(template),templateSource:"uploaded"};
    }catch(error){
      await reportClientError(error,{source:"report_template_load",range_key:template.range_key,storage_path:template.storage_path});
      try{
        return {template,templateBackground:await builtInReportTemplateCanvas(),templateSource:"built_in_fallback",templateLoadError:true};
      }catch(fallbackError){
        await reportClientError(fallbackError,{source:"built_in_report_template_load",after_uploaded_template_failure:true});
        return {template,templateBackground:null,templateSource:"programmatic_fallback",templateLoadError:true};
      }
    }
  }

  function setReportFont(ctx,size,weight="normal",style="normal") {
    const actualSize=Math.max(1,Number(size||0)*reportBodyFontScale());
    ctx.font=`${style} ${weight} ${actualSize}px ${reportBodyFontFamily()}`;
    return actualSize;
  }

  function drawCenteredReportText(ctx,text,x1,x2,y) {
    const value=String(text??"");
    ctx.fillText(value,x1+(x2-x1-ctx.measureText(value).width)/2,y);
  }

  function drawRightReportText(ctx,text,right,y) {
    const value=String(text??"");
    ctx.fillText(value,right-ctx.measureText(value).width,y);
  }

  function fitReportText(ctx,text,maxWidth,preferredSize=22,minimumSize=14,weight="normal") {
    const value=String(text??"");
    let size=preferredSize;
    while(size>minimumSize){
      setReportFont(ctx,size,weight);
      if(ctx.measureText(value).width<=maxWidth)break;
      size-=1;
    }
    return size;
  }

  function fitReportTextValue(ctx,text,maxWidth,preferredSize=22,minimumSize=10,weight="normal") {
    const value=String(text??"");
    let size=fitReportText(ctx,value,maxWidth,preferredSize,minimumSize,weight);
    setReportFont(ctx,size,weight);
    if(ctx.measureText(value).width<=maxWidth)return {text:value,size};
    let shortened=value;
    while(shortened.length>1&&ctx.measureText(`${shortened}…`).width>maxWidth)shortened=shortened.slice(0,-1);
    return {text:`${shortened.trimEnd()}…`,size};
  }

  function drawReportCellText(ctx,text,x1,x2,yCenter,{align="left",preferredSize=21,minimumSize=13,weight="normal",colour="#172238"}={}) {
    const value=String(text??"");
    fitReportText(ctx,value,Math.max(10,x2-x1-16),preferredSize,minimumSize,weight);
    ctx.fillStyle=colour;
    ctx.textBaseline="middle";
    const width=ctx.measureText(value).width;
    const x=align==="center"?x1+(x2-x1-width)/2:align==="right"?x2-width-8:x1+8;
    ctx.fillText(value,x,yCenter);
    ctx.textBaseline="alphabetic";
  }

  function ordinalReportPosition(value) {
    const n=Number(value||0);
    if(!n)return "";
    const mod100=n%100;
    if(mod100>=11&&mod100<=13)return `${n}th`;
    return `${n}${n%10===1?"st":n%10===2?"nd":n%10===3?"rd":"th"}`;
  }

  function subjectScoreBreakdown(subject) {
    const components=(subject.components||[]).filter(item=>item);
    const componentValue=item=>{
      if(item.weighted_score!==null&&item.weighted_score!==undefined&&item.weighted_score!==""){
        const weighted=Number(item.weighted_score);
        if(Number.isFinite(weighted))return weighted;
      }
      const raw=Number(item.raw_score);
      return Number.isFinite(raw)?raw:0;
    };
    const examMatcher=/(exam|examination|final)/i;
    let examComponents=components.filter(item=>examMatcher.test(`${item.name||""} ${item.code||""}`));
    if(!examComponents.length&&components.length>1)examComponents=[components[components.length-1]];
    const examIds=new Set(examComponents.map(item=>item.component_id||item.id||item.code||item.name));
    let examScore=examComponents.reduce((sum,item)=>sum+componentValue(item),0);
    let classScore=components.filter(item=>!examIds.has(item.component_id||item.id||item.code||item.name))
      .reduce((sum,item)=>sum+componentValue(item),0);
    const total=Number(subject.total_score||0);
    if(!components.length){classScore=0;examScore=total}
    const computed=classScore+examScore;
    if(total&&Math.abs(computed-total)>.2){
      if(examScore<=total)classScore=Math.max(0,total-examScore);
      else{examScore=Math.max(0,total-classScore)}
    }
    return {classScore,examScore,total};
  }

  async function reportSubjectPositionMap(reportId) {
    if(!reportId)return new Map();
    try{
      const rows=await rpc("report_subject_positions",{target_report_id:reportId});
      return new Map((Array.isArray(rows)?rows:[]).map(item=>[
        item.subject_id,
        ordinalReportPosition(item.position)
      ]));
    }catch(error){
      await reportClientError(error,{source:"subject_positions",report_id:reportId});
      return new Map();
    }
  }

  async function resolveReportImageAssets({reportId=null,manual=false,studentPhotoPath="",className=""}={}) {
    const school=state.boot.school||{};
    const logo=await loadImage(schoolDisplayLogo(school)).catch(()=>null);
    let signer=null,currentSigner=null;
    if(reportId){
      signer=await rpc("get_report_headteacher_signature",{target_report_id:reportId}).catch(()=>null);
    }
    currentSigner=await rpc("get_current_principal_signature").catch(()=>({full_name:school.head_name||"Principal",signature_path:""}));
    if(!signer?.full_name)signer=currentSigner;
    let signatureImage=null,studentPhotoImage=null,signatureError=null;
    if(signer?.signature_path){
      try{signatureImage=await loadPrivateImageAsset(CONFIG.signatureBucket,signer.signature_path,"The Principal signature")}
      catch(error){signatureError=error}
    }
    if(!signatureImage&&currentSigner?.signature_path&&currentSigner.signature_path!==signer?.signature_path){
      try{signatureImage=await loadPrivateImageAsset(CONFIG.signatureBucket,currentSigner.signature_path,"The current Principal signature");signer=currentSigner}
      catch(error){signatureError=error}
    }
    if(!signatureImage&&!manual){
      if(signatureError)throw signatureError;
      throw new Error("The official report PDF requires an uploaded Principal signature. Ask the active Principal to upload the signature, then try again.");
    }
    if(!manual&&studentPhotoPath){
      try{studentPhotoImage=await loadPrivateImageAsset(CONFIG.photoBucket,studentPhotoPath,"The student photograph")}
      catch(error){throw new Error("The student photograph could not be loaded for the official PDF. Verify the student photo and try again.",{cause:error})}
    }
    const assignedTemplate=await resolveAssignedReportTemplate(className);
    return {logo,signer,signatureImage,studentPhotoImage,...assignedTemplate};
  }

  function reportTextLines(ctx,text,maxWidth,maxLines=3) {
    const words=String(text||"").trim().split(/\s+/).filter(Boolean),lines=[];
    let line="";
    for(const word of words){
      const test=line?`${line} ${word}`:word;
      if(line&&ctx.measureText(test).width>maxWidth){lines.push(line);line=word;if(lines.length>=maxLines)break}
      else line=test;
    }
    if(line&&lines.length<maxLines)lines.push(line);
    return lines;
  }

  function drawReportWrappedCell(ctx,text,x1,x2,y1,y2,{preferredSize=20,minimumSize=13,weight="normal",colour="#17233b",maxLines=2}={}) {
    const value=String(text??"");
    let size=preferredSize,lines=[];
    while(size>=minimumSize){
      setReportFont(ctx,size,weight);
      lines=reportTextLines(ctx,value,Math.max(10,x2-x1-16),maxLines);
      if(lines.every(line=>ctx.measureText(line).width<=x2-x1-16))break;
      size-=1;
    }
    ctx.fillStyle=colour;ctx.textBaseline="middle";
    const lineHeight=size*reportBodyFontScale()*1.08,totalHeight=lineHeight*lines.length;
    let y=y1+(y2-y1-totalHeight)/2+lineHeight/2;
    lines.forEach(line=>{ctx.fillText(line,x1+8,y);y+=lineHeight});
    ctx.textBaseline="alphabetic";
  }

  function drawReportDottedLine(ctx,x1,x2,y) {
    ctx.save();ctx.strokeStyle="#17233b";ctx.lineWidth=1.25;ctx.setLineDash([2,5]);
    ctx.beginPath();ctx.moveTo(x1,y);ctx.lineTo(x2,y);ctx.stroke();ctx.restore();
  }

  function reportDate(value) {
    const date=value?new Date(value):new Date();
    if(Number.isNaN(date.getTime()))return "";
    return date.toLocaleDateString("en-GB",{day:"2-digit",month:"2-digit",year:"numeric"});
  }

  function reportNextTermReopeningDate(report={},student={}) {
    const frozen=["submitted","class_reviewed","approved","published"].includes(String(report.status||""));
    return String((frozen?report.next_term_reopening_date:null)||student.next_term_reopening_date||student.next_term_begins||report.next_term_reopening_date||"");
  }

  function reportNextTermReopeningText(report={},student={},manual=false) {
    if(manual)return ".../.../....";
    const value=reportNextTermReopeningDate(report,student);
    return value?reportDate(value):"To be communicated";
  }

  function reportYearDigits(value) {
    const digits=String(value||"").replace(/\D/g,"");
    return digits.length>=8?digits.slice(0,8):digits||"20252026";
  }

  function reportVerificationCode(report={},templateMeta={},manual=false) {
    if(!manual&&report.report_number)return String(report.report_number);
    return `${schoolReportPrefix()}-${reportYearDigits(templateMeta.academicYearName)}-00000`;
  }

  function drawReportNextTermReopening(ctx,value,x,y) {
    const label="Next Term Reopens: ",resolved=String(value??"");
    ctx.fillStyle=REPORT_COMMENT_HEADING_COLOUR;
    ctx.fillText(label,x,y);
    ctx.fillStyle=REPORT_NEXT_TERM_REOPENING_COLOUR;
    ctx.fillText(resolved,x+ctx.measureText(label).width,y);
  }

  function drawInlineReportField(ctx,{label,value,x,y,maxWidth=500,align="left",fontSize=20,minimumSize=13}) {
    const labelText=String(label||""),valueText=String(value??"");
    let size=fontSize,labelWidth=0,valueWidth=0;
    while(size>=minimumSize){
      setReportFont(ctx,size,"bold");labelWidth=ctx.measureText(labelText).width;
      setReportFont(ctx,size,"normal");valueWidth=ctx.measureText(valueText).width;
      if(labelWidth+7+valueWidth<=maxWidth||size===minimumSize)break;
      size-=1;
    }
    const total=labelWidth+7+valueWidth;
    let start=x;
    if(align==="right")start=x-total;
    else if(align==="center")start=x-total/2;
    ctx.fillStyle="#17233b";
    setReportFont(ctx,size,"bold");ctx.fillText(labelText,start,y);
    setReportFont(ctx,size,"normal");ctx.fillText(valueText,start+labelWidth+7,y);
  }

  // r17 canonical official-school header. Report Cards and School Prospectuses use
  // the same school identity hierarchy; only the document subtitle changes.
  function drawOfficialSchoolHeader(ctx,{school={},logo=null,subtitle="",primary="#123a79",studentPhotoImage=null}={}) {
    const left=38,right=1202,top=29,height=199,showStudentPhoto=Boolean(studentPhotoImage);
    const logoX=49,logoY=48,logoW=153,logoH=160,textLeft=214,textRight=showStudentPhoto?1057:right,maxTextWidth=textRight-textLeft-18;
    ctx.fillStyle=primary;ctx.fillRect(left,top,right-left,height);
    if(logo){
      // r20 transparent document-logo header contract: preserve the header artwork behind transparent logo pixels.
      ctx.save();ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality="high";drawImageContain(ctx,logo,logoX+7,logoY+7,logoW-14,logoH-14);ctx.restore();
    }
    ctx.fillStyle="#ffffff";
    const centered=(value,y,preferred,minimum=11,weight="normal")=>{const line=String(value||"").trim();if(!line)return;fitReportText(ctx,line,maxTextWidth,preferred,minimum,weight);drawCenteredReportText(ctx,line,textLeft,textRight,y)};
    centered(schoolDisplayName(school).toUpperCase(),72,36,22,"bold");
    centered(school.motto||"Discipline, Commitment, Excellence",101,16,11,"normal");
    centered(school.address||"",126,15.5,10.5,"normal");
    centered(school.phone||"",150,15.5,10.5,"normal");
    centered(school.website||school.email||"",174,15,10,"normal");
    centered(subtitle,210,27,17,"bold");
    if(showStudentPhoto){
      const frameX=1075,frameY=48,frameWidth=105,frameHeight=161,padding=4;
      ctx.fillStyle="#ffffff";ctx.fillRect(frameX,frameY,frameWidth,frameHeight);
      ctx.strokeStyle="rgba(255,255,255,.95)";ctx.lineWidth=2;ctx.strokeRect(frameX-.5,frameY-.5,frameWidth+1,frameHeight+1);
      ctx.save();ctx.beginPath();ctx.rect(frameX+padding,frameY+padding,frameWidth-padding*2,frameHeight-padding*2);ctx.clip();
      drawImageCover(ctx,studentPhotoImage,frameX+padding,frameY+padding,frameWidth-padding*2,frameHeight-padding*2);ctx.restore();
    }
  }


  function reportGradingGuide(report={},templateMeta={}) {
    return normaliseGradingGuide(report.grading_scale_guide||templateMeta.gradingGuide||defaultReportGradingGuide());
  }
  function gradingGuideRangeText(row={}) {
    return `${number(row.min_mark,2)} - ${number(row.max_mark,2)}`;
  }
  function gradingGuideColour(row,index) {
    const standard=["#2eb24a","#8bc63f","#2d86c6","#7750ac","#ff9f0a","#ff9f0a","#f36c21","#ef3b35","#d8092f"];
    return standard[index%standard.length];
  }
  function wrapAllReportText(ctx,text,maxWidth) {
    const words=String(text||"").trim().split(/\s+/).filter(Boolean),lines=[];let line="";
    for(const word of words){
      const test=line?`${line} ${word}`:word;
      if(line&&ctx.measureText(test).width>maxWidth){lines.push(line);line=word}else line=test;
    }
    if(line)lines.push(line);
    return lines;
  }
  function drawGradingInterpretationCell(ctx,text,x1,x2,y1,y2) {
    const value=String(text||""),maxWidth=Math.max(10,x2-x1-16),maxLines=3;let size=11,lines=[];
    while(size>=5.5){
      setReportFont(ctx,size,"normal");lines=wrapAllReportText(ctx,value,maxWidth);
      if(lines.length<=maxLines)break;
      size-=.5;
    }
    if(lines.length>maxLines){
      lines=lines.slice(0,maxLines);let last=lines[maxLines-1]||"";
      while(last.length>1&&ctx.measureText(`${last}…`).width>maxWidth)last=last.slice(0,-1);
      lines[maxLines-1]=`${last.trimEnd()}…`;
    }
    ctx.fillStyle="#17233b";ctx.textBaseline="middle";
    const lineHeight=size*reportBodyFontScale()*1.05,total=lineHeight*lines.length;let y=y1+(y2-y1-total)/2+lineHeight/2;
    lines.forEach(line=>{ctx.fillText(line,x1+8,y);y+=lineHeight});ctx.textBaseline="alphabetic";
  }
  function drawDynamicGradingScale(ctx,guide,{x=38,y=1244,width=832,height=390,manual=false}={}) {
    const resolved=normaliseGradingGuide(guide),rows=resolved.rows.length?resolved.rows:defaultReportGradingGuide().rows;
    const titleHeight=44,scopeHeight=24,headerHeight=34,bodyHeight=Math.max(120,height-titleHeight-scopeHeight-headerHeight);
    const rowHeight=bodyHeight/Math.max(1,rows.length),columns=[x,x+100,x+283,x+483,x+width];
    ctx.save();ctx.fillStyle="#ffffff";ctx.fillRect(x-2,y-2,width+4,height+4);
    ctx.strokeStyle="#123a79";ctx.lineWidth=1.5;ctx.strokeRect(x,y,width,height);
    ctx.fillStyle="#123a79";ctx.fillRect(x,y,width,titleHeight);
    ctx.fillStyle="#ffffff";setReportFont(ctx,20,"bold");drawCenteredReportText(ctx,"GRADING SCALE [Interpretation Guide]",x,x+width,y+29);
    const exceptions=(resolved.subject_exceptions||[]).map(item=>item.subject_name).filter(Boolean);
    const exceptionText=exceptions.length?` • Subject-specific exceptions: ${exceptions.join(", ")}`:"";
    const scopeText=`Scope: ${resolved.scope?.label||"School-wide default"}${exceptionText}`;
    ctx.fillStyle="#eef4fb";ctx.fillRect(x,y+titleHeight,width,scopeHeight);
    ctx.fillStyle="#334967";const fittedScope=fitReportTextValue(ctx,scopeText,width-14,13,9,"normal");setReportFont(ctx,fittedScope.size,"normal");ctx.fillText(fittedScope.text,x+7,y+titleHeight+17);
    const headerY=y+titleHeight+scopeHeight;
    ctx.fillStyle="#dce8f6";ctx.fillRect(x,headerY,width,headerHeight);
    ctx.strokeStyle="#76869c";ctx.lineWidth=.8;
    ctx.beginPath();columns.forEach(value=>{ctx.moveTo(value,headerY);ctx.lineTo(value,y+height)});ctx.stroke();
    ctx.beginPath();ctx.moveTo(x,headerY);ctx.lineTo(x+width,headerY);ctx.moveTo(x,headerY+headerHeight);ctx.lineTo(x+width,headerY+headerHeight);ctx.stroke();
    const headings=["GRADE","RANGE (%)","REMARK","INTERPRETATION"];
    ctx.fillStyle="#17233b";setReportFont(ctx,13,"bold");ctx.textBaseline="middle";
    headings.forEach((label,index)=>drawCenteredReportText(ctx,label,columns[index],columns[index+1],headerY+headerHeight/2));
    let rowY=headerY+headerHeight;
    rows.forEach((row,index)=>{
      const nextY=index===rows.length-1?y+height:rowY+rowHeight;
      ctx.fillStyle=gradingGuideColour(row,index);ctx.fillRect(columns[0],rowY,columns[1]-columns[0],nextY-rowY);
      ctx.fillStyle="#ffffff";setReportFont(ctx,Math.min(16,Math.max(10,rowHeight*.43)),"bold");drawCenteredReportText(ctx,manual?String(row.grade||""):String(row.grade||""),columns[0],columns[1],(rowY+nextY)/2);
      drawReportCellText(ctx,gradingGuideRangeText(row),columns[1],columns[2],(rowY+nextY)/2,{align:"center",preferredSize:13,minimumSize:8,colour:"#17233b"});
      drawReportCellText(ctx,row.remark||"",columns[2],columns[3],(rowY+nextY)/2,{align:"center",preferredSize:13,minimumSize:8,weight:"bold",colour:gradingGuideColour(row,index)});
      drawGradingInterpretationCell(ctx,row.interpretation||defaultGradingInterpretation(row.grade,row.remark),columns[3],columns[4],rowY,nextY);
      ctx.strokeStyle="#76869c";ctx.lineWidth=.65;ctx.beginPath();ctx.moveTo(x,nextY);ctx.lineTo(x+width,nextY);ctx.stroke();
      rowY=nextY;
    });
    ctx.textBaseline="alphabetic";ctx.restore();
  }

  async function drawAssignedTemplateOverlay(ctx,canvas,{student={},report={},subjects=[],publication=null,manual=false,templateMeta={},assets={},promotion=null}={}) {
    const school=state.boot.school||{},ink="#17233b",summaryPale="#eef4fb";
    const {logo,signer={},signatureImage,studentPhotoImage}=assets;
    const showStudentPhoto=!manual&&Boolean(studentPhotoImage);

    // Final approved Nipe Terminal Report field map. Uploaded templates use the
    // same protected A4 field map; when none is assigned, the bundled approved
    // Nipe template is loaded automatically by resolveAssignedReportTemplate().
    const tableLeft=38,tableRight=1202,tableTop=340,headerHeight=57,tableBottom=738;
    const bodyTop=tableTop+headerHeight;
    const columns=[38,320,499,681,780,874,1005,1202];
    const source=Array.isArray(subjects)?subjects.filter(Boolean):[];
    const displaySubjects=[...source,null];
    setReportFont(ctx,20,"normal");
    const weights=displaySubjects.map(subject=>subject&&reportTextLines(ctx,subject.subject_name||subject.name||"",columns[1]-columns[0]-16,2).length>1?1.34:1);
    const availableHeight=tableBottom-bodyTop;
    const weightTotal=weights.reduce((sum,value)=>sum+value,0)||1;

    ctx.textBaseline="alphabetic";

    // r19 dynamic-header contract: template artwork is never authoritative for school identity.
    // Clear the complete template header region first, then redraw the canonical live header
    // using the current official school logo and current school identity. This applies equally
    // to built-in templates, uploaded PDF/DOCX templates, official PDFs and manual templates.
    ctx.fillStyle="#ffffff";
    ctx.fillRect(0,0,REPORT_LOGICAL_WIDTH,230);
    drawOfficialSchoolHeader(ctx,{school,logo,subtitle:"Student Terminal Report",primary:"#123a79",studentPhotoImage:showStudentPhoto?studentPhotoImage:null});

    // Clear dynamic report fields. The grading-scale panel is redrawn from the
    // active or frozen academic configuration, while the How to Read panel remains.
    ctx.fillStyle="#ffffff";
    ctx.fillRect(38,232,1164,105);
    ctx.fillRect(tableLeft-1,bodyTop+1,tableRight-tableLeft+2,tableBottom-bodyTop-1);
    ctx.fillStyle=summaryPale;ctx.fillRect(tableLeft,tableBottom,tableRight-tableLeft,140);
    ctx.fillStyle="#ffffff";ctx.fillRect(38,878,1164,357);

    const identityName=manual?"....................................................................":student.full_name||"";
    const identityAdmission=manual?"NIS.......":student.admission_no||"";
    const identityClass=manual?(templateMeta.className||"Basic ........."):student.class_name||"";
    const identityYear=manual?(templateMeta.academicYearName||"................."):student.academic_year_name||"";
    const identityTerm=manual?(templateMeta.termName||"........"):student.term_name||"";
    drawInlineReportField(ctx,{label:"Name:",value:identityName,x:43,y:268,maxWidth:650,fontSize:19});
    drawInlineReportField(ctx,{label:"Admission No.:",value:identityAdmission,x:1197,y:268,maxWidth:390,align:"right",fontSize:19});
    drawInlineReportField(ctx,{label:"Class:",value:identityClass,x:43,y:323,maxWidth:360,fontSize:19});
    drawInlineReportField(ctx,{label:"Academic Year:",value:identityYear,x:620,y:323,maxWidth:410,align:"center",fontSize:19});
    drawInlineReportField(ctx,{label:"Term:",value:identityTerm,x:1197,y:323,maxWidth:300,align:"right",fontSize:19});

    if(logo){ctx.save();ctx.globalAlpha=.055;drawImageContain(ctx,logo,430,bodyTop+16,390,tableBottom-bodyTop-32);ctx.restore()}

    let rowY=bodyTop;
    const ranks=manual?new Map():await reportSubjectPositionMap(report.id);
    ctx.strokeStyle="#1d1d1d";ctx.lineWidth=1.15;
    ctx.beginPath();columns.forEach(x=>{ctx.moveTo(x,bodyTop);ctx.lineTo(x,tableBottom)});ctx.stroke();
    ctx.strokeRect(tableLeft,bodyTop,tableRight-tableLeft,tableBottom-bodyTop);
    displaySubjects.forEach((subject,index)=>{
      const rowHeight=index===displaySubjects.length-1?tableBottom-rowY:availableHeight*(weights[index]/weightTotal);
      const nextY=rowY+rowHeight;
      ctx.beginPath();ctx.moveTo(tableLeft,nextY);ctx.lineTo(tableRight,nextY);ctx.stroke();
      if(subject){
        const breakdown=manual?{classScore:null,examScore:null,total:null}:subjectScoreBreakdown(subject);
        const score=value=>value===null||value===undefined?"":number(value,1);
        drawReportWrappedCell(ctx,subject.subject_name||subject.name||"",columns[0],columns[1],rowY,nextY,{preferredSize:18,minimumSize:11,maxLines:2,colour:ink});
        drawReportCellText(ctx,score(breakdown.classScore),columns[1],columns[2],(rowY+nextY)/2,{align:"center",preferredSize:17,minimumSize:11,colour:REPORT_RESULT_COLOURS.score});
        drawReportCellText(ctx,score(breakdown.examScore),columns[2],columns[3],(rowY+nextY)/2,{align:"center",preferredSize:17,minimumSize:11,colour:REPORT_RESULT_COLOURS.score});
        drawReportCellText(ctx,score(breakdown.total),columns[3],columns[4],(rowY+nextY)/2,{align:"center",preferredSize:17,minimumSize:11,weight:"bold",colour:REPORT_RESULT_COLOURS.total});
        drawReportCellText(ctx,manual?"":subject.grade||"",columns[4],columns[5],(rowY+nextY)/2,{align:"center",preferredSize:17,minimumSize:11,weight:"bold",colour:REPORT_RESULT_COLOURS.grade});
        drawReportCellText(ctx,manual?"":ranks.get(subject.subject_id)||"",columns[5],columns[6],(rowY+nextY)/2,{align:"center",preferredSize:16,minimumSize:10,weight:"bold",colour:REPORT_RESULT_COLOURS.position});
        drawReportCellText(ctx,manual?"":subject.remark||"",columns[6],columns[7],(rowY+nextY)/2,{preferredSize:16,minimumSize:10,colour:REPORT_RESULT_COLOURS.remark});
      }
      rowY=nextY;
    });

    const average=manual?"":subjects.length?subjects.reduce((sum,item)=>sum+Number(item.total_score||0),0)/subjects.length:0;
    const position=manual?{position:0,class_size:0}:report.id?await rpc("report_position",{target_report_id:report.id}).catch(()=>({position:0,class_size:0})):{position:0,class_size:0};
    ctx.fillStyle=ink;setReportFont(ctx,18,"bold");
    ctx.fillText(`Average: ${manual?"......":`${number(average,1)}%`}`,47,786);
    drawCenteredReportText(ctx,`Attendance: ${manual?".... / ....":`${report.days_present||0} / ${report.days_school_opened||0}`}`,365,850,786);
    drawRightReportText(ctx,`Overall Position: ${manual?"..../....":position.position?`${position.position} / ${position.class_size}`:".... / ...."}`,1194,786);
    ctx.fillText(`Attitude: ${manual?".................................":report.attitude||""}`,47,842);
    drawCenteredReportText(ctx,`Conduct: ${manual?"................................":report.conduct||""}`,350,860,842);
    drawRightReportText(ctx,`Interest: ${manual?".........................":report.interest||""}`,1194,842);

    ctx.fillStyle=REPORT_COMMENT_HEADING_COLOUR;setReportFont(ctx,18,"bold");ctx.fillText("Class Teacher's Comment",38,908);
    [928,951].forEach(y=>drawReportDottedLine(ctx,38,710,y));
    setReportFont(ctx,15,"normal");ctx.fillStyle=REPORT_COMMENT_COLOUR;
    if(!manual){const lines=reportTextLines(ctx,report.teacher_comment||"",650,2);[925,948].forEach((y,index)=>{if(lines[index])ctx.fillText(lines[index],43,y)})}
    setReportFont(ctx,18,"bold");ctx.fillStyle=REPORT_COMMENT_HEADING_COLOUR;ctx.fillText("Principal's Comment",38,980);
    [1000,1024].forEach(y=>drawReportDottedLine(ctx,38,710,y));
    setReportFont(ctx,15,"normal");ctx.fillStyle=REPORT_COMMENT_COLOUR;
    if(!manual){const lines=reportTextLines(ctx,report.head_comment||"",650,2);[997,1021].forEach((y,index)=>{if(lines[index])ctx.fillText(lines[index],43,y)})}

    ctx.fillStyle=ink;const promotionTitle=manual?"Promoted To Basic.........":promotionDisplay(promotion||{resolution_error:true}).title;
    const promotionFont=fitReportText(ctx,promotionTitle,790,18,12,"bold");setReportFont(ctx,promotionFont,"bold");ctx.fillText(promotionTitle,38,1056);
    setReportFont(ctx,16,"bold");drawReportNextTermReopening(ctx,reportNextTermReopeningText(report,student,manual),38,1125);

    const base=school.verification_base_url||school.website||`${location.origin}${location.pathname}`;
    const qrText=manual?base:`${base}${base.includes("?")?"&":"?"}verify=${publication?.verification_token||""}`;
    const qr=await qrCanvas(qrText);if(qr)ctx.drawImage(qr,1015,888,145,145);
    const verificationCode=reportVerificationCode(report,templateMeta,manual);
    ctx.fillStyle="#5f708b";setReportFont(ctx,15,"normal");
    const verificationText=`Verification: ${verificationCode}`;
    if(ctx.measureText(verificationText).width<=280)drawCenteredReportText(ctx,verificationText,960,1202,1082);
    else{const splitAt=verificationCode.lastIndexOf("-");drawCenteredReportText(ctx,splitAt>0?`Verification: ${verificationCode.slice(0,splitAt+1)}`:"Verification:",950,1202,1072);drawCenteredReportText(ctx,splitAt>0?verificationCode.slice(splitAt+1):verificationCode,950,1202,1093)}

    const signatureLeft=455,signatureRight=780,signatureLineY=1122;
    drawSignatureOnLine(ctx,signatureImage,signatureLeft,signatureRight,signatureLineY,92,"#5f708b",1.2);
    ctx.fillStyle=ink;setReportFont(ctx,17,"bold");drawCenteredReportText(ctx,signer.full_name||school.head_name||"Principal",signatureLeft,signatureRight,1152);
    ctx.fillStyle="#5f708b";setReportFont(ctx,15,"normal");drawCenteredReportText(ctx,"Digitally signed by the Principal",signatureLeft,signatureRight,1177);

    const reportCode=reportVerificationCode(report,templateMeta,manual);
    ctx.fillStyle="#5f708b";setReportFont(ctx,14,"normal");ctx.fillText(`Report No.: ${reportCode}${manual?"...":""}`,38,1218);
    const manualYear=(String(templateMeta.academicYearName||"").match(/\d{4}\s*$/)||[])[0]||String(new Date().getFullYear());
    drawRightReportText(ctx,manual?`Date Issued: .../.../${manualYear}`:`Date Issued: ${reportDate(publication?.published_at||new Date())}`,1200,1218);
    drawDynamicGradingScale(ctx,reportGradingGuide(report,templateMeta),{x:38,y:1244,width:832,height:390,manual});
    return canvas;
  }

  async function drawPreferredTerminalReport({
    student={},report={},subjects=[],publication=null,manual=false,templateMeta={},assets={},promotion=null
  }) {
    await ensureReportBodyFontReady();
    const {canvas,ctx}=createReportPrintCanvas(),school=state.boot.school||{};
    const navy="#123a79",accent="#f79646",headerPale="#dce8f6",summaryPale="#eef4fb",ink="#17233b";
    const {logo,signer={},signatureImage,studentPhotoImage}=assets;
    const showStudentPhoto=!manual&&Boolean(studentPhotoImage);

    ctx.fillStyle="#ffffff";ctx.fillRect(0,0,REPORT_LOGICAL_WIDTH,REPORT_LOGICAL_HEIGHT);
    if(assets.templateBackground){
      drawImageContain(ctx,assets.templateBackground,0,0,REPORT_LOGICAL_WIDTH,REPORT_LOGICAL_HEIGHT);
      return drawAssignedTemplateOverlay(ctx,canvas,{student,report,subjects,publication,manual,templateMeta,assets,promotion});
    }

    // r17 official header parity: same school identity block as Prospectus,
    // with a larger transparent high-resolution logo and report-specific subtitle.
    drawOfficialSchoolHeader(ctx,{school,logo,subtitle:"Student Terminal Report",primary:navy,studentPhotoImage:showStudentPhoto?studentPhotoImage:null});

    const identityName=manual?"....................................................................":student.full_name||"";
    const identityAdmission=manual?"NIS.......":student.admission_no||"";
    const identityClass=manual?(templateMeta.className||"Basic ........."):student.class_name||"";
    const identityYear=manual?(templateMeta.academicYearName||"................."):student.academic_year_name||"";
    const identityTerm=manual?(templateMeta.termName||"........"):student.term_name||"";
    drawInlineReportField(ctx,{label:"Name:",value:identityName,x:43,y:268,maxWidth:650,fontSize:19});
    drawInlineReportField(ctx,{label:"Admission No.:",value:identityAdmission,x:1197,y:268,maxWidth:390,align:"right",fontSize:19});
    drawInlineReportField(ctx,{label:"Class:",value:identityClass,x:43,y:323,maxWidth:360,fontSize:19});
    drawInlineReportField(ctx,{label:"Academic Year:",value:identityYear,x:620,y:323,maxWidth:410,align:"center",fontSize:19});
    drawInlineReportField(ctx,{label:"Term:",value:identityTerm,x:1197,y:323,maxWidth:300,align:"right",fontSize:19});

    const tableLeft=38,tableRight=1202,tableTop=338,headerHeight=58,maximumTableBottom=1086;
    const columns=[38,286,464,646,762,862,994,1202];
    const labels=["SUBJECT","CLASS SCORE","EXAMS SCORE","TOTAL","GRADE","POSITION","REMARKS"];
    const bodyTop=tableTop+headerHeight,tableLayout=reportTableLayout(ctx,subjects,columns,bodyTop,maximumTableBottom);
    const {displaySubjects,weights,availableHeight,tableBottom}=tableLayout;
    const lowerOffset=tableBottom-maximumTableBottom,shift=y=>y+lowerOffset;

    // Watermark remains behind the compact subject table only.
    if(logo){
      const watermarkHeight=Math.min(390,Math.max(120,tableBottom-bodyTop-28));
      ctx.save();ctx.globalAlpha=.065;drawImageContain(ctx,logo,420,bodyTop+(tableBottom-bodyTop-watermarkHeight)/2,400,watermarkHeight);ctx.restore();
    }

    ctx.fillStyle=headerPale;ctx.fillRect(tableLeft,tableTop,tableRight-tableLeft,headerHeight);
    ctx.strokeStyle="#1d1d1d";ctx.lineWidth=1.25;ctx.strokeRect(tableLeft,tableTop,tableRight-tableLeft,tableBottom-tableTop);
    columns.slice(1,-1).forEach(x=>{ctx.beginPath();ctx.moveTo(x,tableTop);ctx.lineTo(x,tableBottom);ctx.stroke()});
    setReportFont(ctx,19,"bold");ctx.fillStyle=ink;ctx.textBaseline="middle";
    labels.forEach((label,index)=>drawCenteredReportText(ctx,label,columns[index],columns[index+1],tableTop+headerHeight/2+1));
    ctx.textBaseline="alphabetic";

    setReportFont(ctx,20,"normal");
    const weightTotal=weights.reduce((sum,value)=>sum+value,0);
    let rowY=bodyTop;
    const ranks=manual?new Map():await reportSubjectPositionMap(report.id);
    displaySubjects.forEach((subject,index)=>{
      const rowHeight=index===displaySubjects.length-1?tableBottom-rowY:availableHeight*(weights[index]/weightTotal);
      const nextY=rowY+rowHeight;
      ctx.strokeStyle="#1d1d1d";ctx.lineWidth=1;
      ctx.beginPath();ctx.moveTo(tableLeft,nextY);ctx.lineTo(tableRight,nextY);ctx.stroke();
      if(subject){
        const breakdown=manual?{classScore:null,examScore:null,total:null}:subjectScoreBreakdown(subject);
        const score=value=>value===null||value===undefined?"":number(value,1);
        drawReportWrappedCell(ctx,subject.subject_name||subject.name||"",columns[0],columns[1],rowY,nextY,{preferredSize:20,minimumSize:13,maxLines:2});
        drawReportCellText(ctx,score(breakdown.classScore),columns[1],columns[2],(rowY+nextY)/2,{align:"center",preferredSize:19,minimumSize:13,colour:REPORT_RESULT_COLOURS.score});
        drawReportCellText(ctx,score(breakdown.examScore),columns[2],columns[3],(rowY+nextY)/2,{align:"center",preferredSize:19,minimumSize:13,colour:REPORT_RESULT_COLOURS.score});
        drawReportCellText(ctx,score(breakdown.total),columns[3],columns[4],(rowY+nextY)/2,{align:"center",preferredSize:19,minimumSize:13,weight:"bold",colour:REPORT_RESULT_COLOURS.total});
        drawReportCellText(ctx,manual?"":subject.grade||"",columns[4],columns[5],(rowY+nextY)/2,{align:"center",preferredSize:19,minimumSize:13,weight:"bold",colour:REPORT_RESULT_COLOURS.grade});
        drawReportCellText(ctx,manual?"":ranks.get(subject.subject_id)||"",columns[5],columns[6],(rowY+nextY)/2,{align:"center",preferredSize:18,minimumSize:12,weight:"bold",colour:REPORT_RESULT_COLOURS.position});
        drawReportCellText(ctx,manual?"":subject.remark||"",columns[6],columns[7],(rowY+nextY)/2,{preferredSize:18,minimumSize:11,colour:REPORT_RESULT_COLOURS.remark});
      }
      rowY=nextY;
    });

    // Summary and signing fields follow immediately after the single retained blank row.
    ctx.fillStyle=summaryPale;ctx.fillRect(tableLeft,tableBottom,tableRight-tableLeft,109);
    const average=manual?"":subjects.length?subjects.reduce((sum,item)=>sum+Number(item.total_score||0),0)/subjects.length:0;
    const position=manual?{position:0,class_size:0}:report.id
      ?await rpc("report_position",{target_report_id:report.id}).catch(()=>({position:0,class_size:0}))
      :{position:0,class_size:0};
    ctx.fillStyle=ink;setReportFont(ctx,20,"bold");
    ctx.fillText(`Average: ${manual?"......":`${number(average,1)}%`}`,47,shift(1118));
    drawCenteredReportText(ctx,`Attendance: ${manual?".... / ....":`${report.days_present||0} / ${report.days_school_opened||0}`}`,365,850,shift(1118));
    drawRightReportText(ctx,`Overall Position: ${manual?"..../....":position.position?`${position.position} / ${position.class_size}`:".... / ...."}`,1194,shift(1118));
    ctx.fillText(`Attitude: ${manual?".................................":report.attitude||""}`,47,shift(1175));
    drawCenteredReportText(ctx,`Conduct: ${manual?"................................":report.conduct||""}`,350,860,shift(1175));
    drawRightReportText(ctx,`Interest: ${manual?".........................":report.interest||""}`,1194,shift(1175));

    ctx.fillStyle=REPORT_COMMENT_HEADING_COLOUR;setReportFont(ctx,20,"bold");ctx.fillText("Class Teacher's Comment",43,shift(1219));
    [1249,1278,1307].forEach(y=>drawReportDottedLine(ctx,43,850,shift(y)));
    setReportFont(ctx,17,"normal");ctx.fillStyle=REPORT_COMMENT_COLOUR;
    if(!manual){
      const lines=reportTextLines(ctx,report.teacher_comment||"",790,3);
      [1245,1274,1303].forEach((y,index)=>{if(lines[index])ctx.fillText(lines[index],47,shift(y))});
    }
    setReportFont(ctx,20,"bold");ctx.fillStyle=REPORT_COMMENT_HEADING_COLOUR;ctx.fillText("Principal's Comment",43,shift(1327));
    [1357,1386].forEach(y=>drawReportDottedLine(ctx,43,650,shift(y)));
    setReportFont(ctx,17,"normal");ctx.fillStyle=REPORT_COMMENT_COLOUR;
    if(!manual){
      const lines=reportTextLines(ctx,report.head_comment||"",590,2);
      [1353,1382].forEach((y,index)=>{if(lines[index])ctx.fillText(lines[index],47,shift(y))});
    }
    ctx.fillStyle=ink;
    const promotionTitle=manual?"Promoted To Basic.........":promotionDisplay(promotion||{resolution_error:true}).title;
    const promotionFont=fitReportText(ctx,promotionTitle,800,20,13,"bold");setReportFont(ctx,promotionFont,"bold");ctx.fillText(promotionTitle,43,shift(1422));
    setReportFont(ctx,17,"bold");
    drawReportNextTermReopening(ctx,reportNextTermReopeningText(report,student,manual),43,shift(1460));

    const base=school.verification_base_url||school.website||`${location.origin}${location.pathname}`;
    const qrText=manual?base:`${base}${base.includes("?")?"&":"?"}verify=${publication?.verification_token||""}`;
    const qr=await qrCanvas(qrText);
    if(qr)ctx.drawImage(qr,949,shift(1210),190,190);
    const verificationCode=reportVerificationCode(report,templateMeta,manual);
    ctx.fillStyle="#5f708b";setReportFont(ctx,16,"normal");
    const verificationText=`Verification: ${verificationCode}`;
    if(ctx.measureText(verificationText).width<=290)drawCenteredReportText(ctx,verificationText,900,1190,shift(1430));
    else{
      const splitAt=verificationCode.lastIndexOf("-");
      const first=splitAt>0?`Verification: ${verificationCode.slice(0,splitAt+1)}`:"Verification:";
      const second=splitAt>0?verificationCode.slice(splitAt+1):verificationCode;
      drawCenteredReportText(ctx,first,900,1190,shift(1424));
      drawCenteredReportText(ctx,second,900,1190,shift(1447));
    }

    const signatureLeft=515,signatureRight=865,signatureLineY=shift(1485);
    drawSignatureOnLine(ctx,signatureImage,signatureLeft,signatureRight,signatureLineY,100,"#5f708b",1.2);
    ctx.fillStyle=ink;setReportFont(ctx,18,"bold");drawCenteredReportText(ctx,signer.full_name||school.head_name||"Principal",signatureLeft,signatureRight,shift(1512));
    ctx.fillStyle="#5f708b";setReportFont(ctx,16,"normal");drawCenteredReportText(ctx,"Digitally signed by the Principal",signatureLeft,signatureRight,shift(1538));

    const reportCode=reportVerificationCode(report,templateMeta,manual);
    ctx.fillStyle="#5f708b";setReportFont(ctx,16,"normal");
    ctx.fillText(`Report No.: ${reportCode}${manual?"...":""}`,43,shift(1572));
    const manualYear=(String(templateMeta.academicYearName||"").match(/\d{4}\s*$/)||[])[0]||String(new Date().getFullYear());
    drawRightReportText(ctx,manual?`Date Issued: .../.../${manualYear}`:`Date Issued: ${reportDate(publication?.published_at||new Date())}`,1197,shift(1572));
    ctx.fillStyle=accent;ctx.fillRect(38,1603,1164,7);
    ctx.fillStyle="#111111";setReportFont(ctx,17,"bold","italic");
    drawCenteredReportText(ctx,"N.B.: Any Alteration, Cancellation or Erasing of any part of this report renders it void",38,1202,1654);
    ctx.fillStyle=navy;ctx.fillRect(38,1671,1164,5);

    return canvas;
  }

  async function printQualityCanvasPdf(canvas) {
    const width=canvas?.width||0,height=canvas?.height||0;
    if(width<REPORT_PRINT_WIDTH||height<REPORT_PRINT_HEIGHT)throw new Error(`Official report export was blocked because its raster resolution was only ${width} × ${height}. Minimum print quality is ${REPORT_PRINT_WIDTH} × ${REPORT_PRINT_HEIGHT}.`);
    const jpeg=await new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error("The print-quality report image could not be encoded.")),"image/jpeg",.995));
    // Release the large 300-PPI backing store before constructing the PDF to reduce
    // peak memory pressure in Android WebView and sequential batch generation.
    canvas.width=1;canvas.height=1;
    return imagePdf(jpeg,595.28,841.89,width,height);
  }

  async function createReportPdf(editor,publication) {
    if(!editor.report?.id)throw new Error("The report must be saved before an official PDF can be generated.");
    const assets=await resolveReportImageAssets({
      reportId:editor.report.id,manual:false,studentPhotoPath:editor.student?.photo_url||"",className:editor.student?.class_name||""
    });
    let gradingGuide,promotion;
    try{
      gradingGuide=normaliseGradingGuide(await rpc("get_report_grading_guide",{target_report_id:editor.report.id,target_enrollment_id:null,target_term_id:null}));
    }catch(error){
      throw new Error("The official PDF cannot be generated until the report has a valid grading guide. Verify Academic Configuration and try again.",{cause:error});
    }
    try{
      promotion=await rpc("report_promotion_canonical",{target_report_id:editor.report.id});
    }catch(error){
      await reportClientError(error,{source:"official_pdf_canonical_promotion",report_id:editor.report.id});
      throw new Error("The official PDF cannot be generated until the authoritative promotion decision is available. Refresh the report and try again.",{cause:error});
    }
    if(!gradingGuide.rows.length)throw new Error("The official PDF cannot be generated because the applicable grading guide contains no active ranges.");
    const canvas=await drawPreferredTerminalReport({
      student:editor.student||{},report:{...(editor.report||{}),grading_scale_guide:gradingGuide},subjects:editor.subjects||[],publication,manual:false,assets,promotion
    });
    return printQualityCanvasPdf(canvas);
  }

  async function createManualReportTemplatePdf({academicYearId=null,classId=null,academicYearName="",termName="",className="",subjects=[]}={}) {
    const assets=await resolveReportImageAssets({manual:true,className});
    const gradingGuide=academicYearId&&classId
      ?normaliseGradingGuide(await rpc("resolve_grading_guide",{target_academic_year_id:academicYearId,target_class_id:classId}).catch(()=>defaultReportGradingGuide()))
      :defaultReportGradingGuide();
    const templateSubjects=subjects.map(subject=>({
      subject_id:subject.id,subject_name:subject.name,subject_code:subject.code,total_score:null,grade:"",remark:"",components:[]
    }));
    const canvas=await drawPreferredTerminalReport({
      student:{},report:{days_present:null,days_school_opened:null,attitude:"",conduct:"",interest:"",teacher_comment:"",head_comment:""},
      subjects:templateSubjects,publication:null,manual:true,templateMeta:{academicYearName,termName,className,gradingGuide},assets,promotion:null
    });
    return printQualityCanvasPdf(canvas);
  }

  async function imagePdf(jpegBlob,pageWidth,pageHeight,imageWidth=1240,imageHeight=1754) {
    const jpeg=new Uint8Array(await jpegBlob.arrayBuffer()),parts=[],offsets=[0];let length=0;
    const add=value=>{const bytes=typeof value==="string"?new TextEncoder().encode(value):value;parts.push(bytes);length+=bytes.length};
    add("%PDF-1.4\n%\xFF\xFF\xFF\xFF\n");
    const object=(id,body)=>{offsets[id]=length;add(`${id} 0 obj\n${body}\nendobj\n`)};
    object(1,"<< /Type /Catalog /Pages 2 0 R >>");
    object(2,"<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
    object(3,`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth} ${pageHeight}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`);
    offsets[4]=length;add(`4 0 obj\n<< /Type /XObject /Subtype /Image /Width ${imageWidth} /Height ${imageHeight} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`);add(jpeg);add("\nendstream\nendobj\n");
    const content=`q\n${pageWidth} 0 0 ${pageHeight} 0 0 cm\n/Im0 Do\nQ`;
    object(5,`<< /Length ${content.length} >>\nstream\n${content}\nendstream`);
    const xref=length;add("xref\n0 6\n0000000000 65535 f \n");
    for(let i=1;i<=5;i++)add(`${String(offsets[i]).padStart(10,"0")} 00000 n \n`);
    add(`trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`);
    return new Blob(parts,{type:"application/pdf"});
  }


  async function imagesPdf(jpegBlobs,pageWidth,pageHeight,imageWidth=1240,imageHeight=1754) {
    if(!jpegBlobs?.length)throw new Error("At least one rendered PDF page is required");
    const images=[];for(const blob of jpegBlobs)images.push(new Uint8Array(await blob.arrayBuffer()));
    const parts=[],offsets=[0];let length=0;const add=value=>{const bytes=typeof value==="string"?new TextEncoder().encode(value):value;parts.push(bytes);length+=bytes.length};
    add("%PDF-1.4\n%\xFF\xFF\xFF\xFF\n");const object=(id,body)=>{offsets[id]=length;add(`${id} 0 obj\n${body}\nendobj\n`)};
    object(1,"<< /Type /Catalog /Pages 2 0 R >>");const pageIds=images.map((_,index)=>3+index*3);object(2,`<< /Type /Pages /Kids [${pageIds.map(id=>`${id} 0 R`).join(" ")}] /Count ${pageIds.length} >>`);
    images.forEach((jpeg,index)=>{const pageId=3+index*3,imageId=pageId+1,contentId=pageId+2,name=`Im${index}`;object(pageId,`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth} ${pageHeight}] /Resources << /XObject << /${name} ${imageId} 0 R >> >> /Contents ${contentId} 0 R >>`);offsets[imageId]=length;add(`${imageId} 0 obj\n<< /Type /XObject /Subtype /Image /Width ${imageWidth} /Height ${imageHeight} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`);add(jpeg);add("\nendstream\nendobj\n");const content=`q\n${pageWidth} 0 0 ${pageHeight} 0 0 cm\n/${name} Do\nQ`;object(contentId,`<< /Length ${content.length} >>\nstream\n${content}\nendstream`) });
    const totalObjects=2+images.length*3,xref=length;add(`xref\n0 ${totalObjects+1}\n0000000000 65535 f \n`);for(let i=1;i<=totalObjects;i++)add(`${String(offsets[i]).padStart(10,"0")} 00000 n \n`);add(`trailer\n<< /Size ${totalObjects+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`);return new Blob(parts,{type:"application/pdf"});
  }


  async function renderChildren(token) {
    const data=await rpc("list_my_children_reports");
    if(token!==state.viewToken)return;
    const children=data.children||[];
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>My Children</h3><p>Published report cards available for viewing and PDF download</p></div></div>
      <div class="grid ${children.length>1?"two":""}" id="childrenGrid">
        ${children.length?children.map(child=>`<section class="panel">
          <div class="panel-header"><div class="cell-copy"><strong>${esc(child.full_name)}</strong><small>${esc(child.admission_no)} • ${esc(child.class_name||"")}</small></div></div>
          <div class="panel-body">${(child.reports||[]).length?(child.reports||[]).map(report=>`<div class="diff-row"><span><strong>${esc(report.term_name)}</strong><br><small>${esc(report.academic_year_name)} • ${number(report.average,1)}%</small></span>
            <div class="button-row"><button class="button outline small" data-child-report="${attr(report.id)}">View report</button>${report.publication?`<button class="button secondary small" data-child-pdf="${attr(report.id)}">Download latest PDF</button>`:""}</div></div>`).join(""):`<div class="empty"><strong>No published reports</strong></div>`}</div>
        </section>`).join(""):`<section class="panel pad empty"><strong>No linked student report records</strong><span>Ask the System Administrator to verify the parent-student link.</span></section>`}
      </div>`;
    $$('[data-child-report]').forEach(button=>button.onclick=()=>openReportEditor(button.dataset.childReport));
    $$('[data-child-pdf]').forEach(button=>button.onclick=()=>downloadLatestOfficialPdf(button.dataset.childPdf));
  }

  const TEACHER_QUALIFICATIONS=Object.freeze(["PhD","MSc Degree","Bachelor Degree","HND","Diploma","SHS"]);
  async function uploadStaffPhoto(staffId,file){
    if(!file)throw new Error("Choose a staff photograph first");
    if(!/^image\/(jpeg|png|webp)$/i.test(file.type))throw new Error("Staff photographs must be JPEG, PNG, or WebP images");
    if(file.size>8*1024*1024)throw new Error("The selected photograph is too large. Choose an image below 8 MB");
    const blob=await compressImage(file,1200,.88);if(blob.size>5*1024*1024)throw new Error("The optimized photograph still exceeds the 5 MB staff-photo limit");const path=`${staffId}/${Date.now()}.webp`;
    const {error}=await state.client.storage.from(CONFIG.staffPhotoBucket).upload(path,blob,{contentType:"image/webp",upsert:false,cacheControl:"31536000"});
    if(error)throw error;return path;
  }
  function staffAvatarHtml(row,label="Staff"){
    const initials=idCardInitials(row?.full_name||fullName(row)||label);
    return row?.photo_url?`<span class="staff-avatar-photo"><img data-staff-photo="${attr(row.photo_url)}" alt="${attr(label)} photograph"><span>${esc(initials)}</span></span>`:`<span class="avatar small-avatar">${esc(initials)}</span>`;
  }
  async function hydrateStaffPhotos(root=document){
    const nodes=$$('[data-staff-photo]',root);await Promise.all(nodes.map(async img=>{const path=img.dataset.staffPhoto;if(!path)return;try{img.src=await signedUrl(CONFIG.staffPhotoBucket,path,900);img.onload=()=>img.parentElement?.classList.add("loaded")}catch(error){await reportClientError(error,{source:"staff_photo_hydrate",path}).catch(()=>{})}}));
  }
  function qualificationOptions(value=""){
    const legacy=String(value||"").trim(),options=[...TEACHER_QUALIFICATIONS];if(legacy&&!options.includes(legacy))options.unshift(legacy);
    return `<option value="">Select qualification</option>${options.map(item=>`<option value="${attr(item)}" ${item===legacy?"selected":""}>${esc(item)}${!TEACHER_QUALIFICATIONS.includes(item)?" (legacy)":""}</option>`).join("")}`;
  }
  async function renderTeachers(token) {
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Teacher Directory</h3><p>Staff records, EMIS details, photographs, accounts, classes, and subjects</p></div>
        <div class="page-actions"><button class="button outline" id="teacherPrint">Printable records</button><button class="button outline" id="teacherExport">Export CSV</button><button class="button primary" id="teacherAdd">Add teacher</button></div></div>
      <section class="panel"><div class="toolbar"><label class="search"><input id="teacherSearch" type="search" placeholder="Search teacher, staff number, or EMIS code"></label>
          <select id="teacherStatus"><option value="">All statuses</option><option value="active">Active</option><option value="leave">On leave</option><option value="suspended">Suspended</option><option value="resigned">Resigned</option><option value="retired">Retired</option></select>
          <select id="teacherArchive"><option value="active">Current records</option><option value="archived">Archived records</option><option value="all">All records</option></select></div>
        <div id="teacherResults"><div class="empty">Loading teachers</div></div></section>`;
    byId("teacherAdd").onclick=()=>openTeacherEditor();byId("teacherExport").onclick=exportTeachersCsv;byId("teacherPrint").onclick=downloadPrintableTeacherRecords;
    let timer;byId("teacherSearch").oninput=()=>{clearTimeout(timer);timer=setTimeout(()=>{state.teacherPage=1;loadTeacherPage(token)},250)};byId("teacherStatus").onchange=()=>{state.teacherPage=1;loadTeacherPage(token)};byId("teacherArchive").onchange=()=>{state.teacherPage=1;loadTeacherPage(token)};await loadTeacherPage(token);
  }
  async function loadTeacherPage(token=state.viewToken) {
    const root=byId("teacherResults");if(!root)return;root.innerHTML=`<div class="empty">Loading teachers</div>`;
    const data=await rpc("list_teachers",{search_text:byId("teacherSearch")?.value.trim()||"",status_filter:byId("teacherStatus")?.value||"",archive_filter:byId("teacherArchive")?.value||"active",page_number:state.teacherPage,page_size:CONFIG.pageSize});
    if(token!==state.viewToken||!byId("teacherResults"))return;state.teacherAdmin=data;const rows=data.rows||[];
    root.innerHTML=rows.length?`<div class="table-wrap"><table><thead><tr><th>Teacher</th><th>Staff / EMIS</th><th>Contact</th><th>Qualification</th><th>Assignments</th><th>Status</th><th></th></tr></thead><tbody>${rows.map(row=>`<tr>
      <td><div class="cell-main">${staffAvatarHtml(row,"Teacher")}<div class="cell-copy"><strong>${esc(row.full_name)}</strong><small>${esc(row.profile_email||row.email||"No linked account")}</small></div></div></td>
      <td><div class="cell-copy"><strong>${esc(row.staff_no)}</strong><small>EMIS: ${esc(row.emis_code||"—")}</small></div></td><td><div class="cell-copy"><span>${esc(row.phone||"—")}</span><small>${esc(row.email||"")}</small></div></td>
      <td><div class="cell-copy"><span>${esc(row.qualification||"—")}</span><small>${esc(row.specialization||"")}</small></div></td>
      <td><div class="chip-list"><span class="chip">${number((row.class_assignments||[]).length)} classes</span><span class="chip">${number((row.subject_assignments||[]).length)} subjects</span></div></td>
      <td>${statusBadge(row.deleted_at?"archived":row.employment_status)}</td><td><div class="table-actions"><button class="button secondary small" data-teacher-view="${attr(row.id)}">View</button>${!row.deleted_at?`<button class="button ghost small" data-teacher-edit="${attr(row.id)}">Edit</button><button class="button danger small" data-teacher-archive="${attr(row.id)}">Remove</button>`:`<button class="button success small" data-teacher-restore="${attr(row.id)}">Restore</button>`}</div></td></tr>`).join("")}</tbody></table></div>${pagination(data.total,data.page,data.page_size,"teacher")}`:`<div class="empty"><strong>No teachers found</strong></div>`;
    await hydrateStaffPhotos(root);$$('[data-teacher-view]',root).forEach(button=>button.onclick=()=>openTeacherRecord(button.dataset.teacherView));$$('[data-teacher-edit]',root).forEach(button=>button.onclick=()=>openTeacherEditor(button.dataset.teacherEdit));$$('[data-teacher-archive]',root).forEach(button=>button.onclick=()=>archiveTeacher(button.dataset.teacherArchive));$$('[data-teacher-restore]',root).forEach(button=>button.onclick=()=>restoreTeacher(button.dataset.teacherRestore));bindPagination("teacher",data);
  }
  async function openTeacherRecord(id) {
    const data=await rpc("get_teacher_record",{target_teacher_id:id}),t=data.teacher||{},classes=data.classes||[],subjects=data.subjects||[];let photo="";if(t.photo_url){try{photo=await signedUrl(CONFIG.staffPhotoBucket,t.photo_url,900)}catch(_){}}
    modal(t.full_name||"Teacher",t.staff_no||"",`<div class="staff-profile-record"><section class="staff-profile-summary">${photo?`<img src="${attr(photo)}" alt="Teacher photograph">`:`<span class="staff-profile-placeholder">${esc(idCardInitials(t.full_name))}</span>`}<div><h3>${esc(t.full_name||"Teacher")}</h3><p>${esc(t.staff_no||"")} ${t.emis_code?`• EMIS ${esc(t.emis_code)}`:""}</p>${statusBadge(t.deleted_at?"archived":t.employment_status)}</div></section>
      <div class="grid two"><section class="panel pad"><div class="metric"><span>Date of birth</span><strong>${esc(isoDate(t.date_of_birth))}</strong></div><div class="metric"><span>Gender</span><strong>${esc(t.gender||"—")}</strong></div><div class="metric"><span>Telephone</span><strong>${esc(t.phone||"—")}</strong></div><div class="metric"><span>Email</span><strong>${esc(t.email||"—")}</strong></div><div class="metric"><span>Qualification</span><strong>${esc(t.qualification||"—")}</strong></div><div class="metric"><span>Specialization</span><strong>${esc(t.specialization||"—")}</strong></div><div class="metric"><span>Date joined</span><strong>${esc(isoDate(t.date_joined))}</strong></div></section>
      <section class="panel pad"><div class="metric"><span>Linked account</span><strong>${esc(t.profile_email||"Not linked")}</strong></div><div class="metric"><span>Assigned classes</span><strong>${number(classes.length)}</strong></div><div class="chip-list">${classes.map(c=>`<span class="chip">${esc(c.name)}</span>`).join("")||'<span class="muted">No class-teacher assignment</span>'}</div><div class="metric"><span>Subject assignments</span><strong>${number(subjects.length)}</strong></div><div class="chip-list">${subjects.slice(0,30).map(s=>`<span class="chip">${esc(s.class_name)} • ${esc(s.subject_name)}</span>`).join("")||'<span class="muted">No subject assignment</span>'}</div></section></div></div>`,t.deleted_at?`<button class="button success" id="teacherRecordRestore">Restore teacher</button>`:`<button class="button primary" id="teacherRecordEdit">Edit teacher</button><button class="button danger" id="teacherRecordArchive">Remove teacher</button>`,`wide`);
    byId("teacherRecordEdit")?.addEventListener("click",()=>{closeModal();openTeacherEditor(id)});byId("teacherRecordArchive")?.addEventListener("click",()=>{closeModal();archiveTeacher(id)});byId("teacherRecordRestore")?.addEventListener("click",()=>{closeModal();restoreTeacher(id)});
  }
  async function openTeacherEditor(id=null) {
    const data=id?await rpc("get_teacher_record",{target_teacher_id:id}):{teacher:{active:true,employment_status:"active"},profiles:state.teacherAdmin?.profiles||[]},row=data.teacher||{},profiles=(state.teacherAdmin?.profiles||data.profiles||[]).filter(p=>!p.linked_teacher_id||p.id===row.profile_id);
    if(!id&&!row.staff_no){try{row.staff_no=await rpc("generate_school_identifier",{identifier_kind:"teacher"})}catch(_){row.staff_no=""}}
    let photo="";if(row.photo_url){try{photo=await signedUrl(CONFIG.staffPhotoBucket,row.photo_url,900)}catch(_){}}
    modal(id?"Edit Teacher":"Add Teacher",row.staff_no||"",`<form id="teacherForm" class="form-stack"><input type="hidden" name="id" value="${attr(row.id||"")}"><input type="hidden" name="updated_at" value="${attr(row.updated_at||"")}"><div class="staff-photo-editor">${photo?`<img src="${attr(photo)}" alt="Teacher photograph">`:`<span>${esc(idCardInitials(row.full_name||fullName(row)||"Teacher"))}</span>`}<label class="field"><span>Teacher photograph</span><input id="teacherPhotoFile" type="file" accept="image/jpeg,image/png,image/webp"><small>Optional. The teacher can also upload or replace this from My Profile.</small></label></div>
      <div class="form-grid three"><label class="field"><span>Staff number</span><input name="staff_no" value="${attr(row.staff_no||"")}" required readonly aria-readonly="true"><small>Generated automatically from the school tenant identity.</small></label><label class="field"><span>EMIS code (optional)</span><input name="emis_code" value="${attr(row.emis_code||"")}" maxlength="80"></label><label class="field"><span>Linked user account</span><select name="profile_id">${optionList(profiles,"id","full_name",row.profile_id,"No linked account")}</select></label>
        <label class="field"><span>First name</span><input name="first_name" value="${attr(row.first_name||"")}" required></label><label class="field"><span>Middle name</span><input name="middle_name" value="${attr(row.middle_name||"")}"></label><label class="field"><span>Last name</span><input name="last_name" value="${attr(row.last_name||"")}" required></label>
        <label class="field"><span>Gender</span><select name="gender"><option value="Male" ${row.gender==="Male"?"selected":""}>Male</option><option value="Female" ${row.gender==="Female"?"selected":""}>Female</option><option value="Other" ${row.gender==="Other"?"selected":""}>Other</option></select></label><label class="field"><span>Date of birth</span><input type="date" name="date_of_birth" value="${attr(row.date_of_birth||"")}"></label><label class="field"><span>Date joined</span><input type="date" name="date_joined" value="${attr(row.date_joined||"")}"></label>
        <label class="field"><span>Telephone</span><input name="phone" value="${attr(row.phone||"")}"></label><label class="field"><span>Email</span><input type="email" name="email" value="${attr(row.email||"")}"></label><label class="field"><span>Employment status</span><select name="employment_status">${["active","leave","suspended","resigned","retired"].map(v=>`<option value="${v}" ${row.employment_status===v?"selected":""}>${esc(statusText(v))}</option>`).join("")}</select></label>
        <label class="field"><span>Qualification</span><select name="qualification">${qualificationOptions(row.qualification)}</select></label><label class="field"><span>Specialization</span><input name="specialization" value="${attr(row.specialization||"")}"></label><label class="field"><span>Address</span><input name="address" value="${attr(row.address||"")}"></label><label class="field full"><span>Notes</span><textarea name="notes">${esc(row.notes||"")}</textarea></label><label class="check-field full"><input type="checkbox" name="active" ${row.active!==false?"checked":""}><span>Active teacher</span></label></div></form>`,`<button class="button ghost" id="teacherCancel" type="button">Cancel</button><button class="button primary" id="teacherSave" type="submit" form="teacherForm">Save teacher</button>`,`wide`);
    byId("teacherCancel").onclick=closeModal;byId("teacherForm").addEventListener("submit",event=>{event.preventDefault();saveTeacher(row)});
  }
  async function saveTeacher(existing={}) {
    const form=byId("teacherForm"),button=byId("teacherSave");if(!form?.reportValidity()){toast("Teacher not saved","Complete the required teacher fields.","error");return}const v=formObject(form);button.disabled=true;button.textContent="Saving";let saved=null,uploaded="";
    try{saved=await rpc("save_teacher",{payload:{...v,active:form.elements.active.checked,reason:v.id?"Teacher record updated":"Teacher record created"}});const teacher=saved.teacher||saved;const file=byId("teacherPhotoFile")?.files?.[0];if(file){uploaded=await uploadStaffPhoto(teacher.id,file);const previous=existing.photo_url||"";saved=await rpc("set_teacher_photo",{target_teacher_id:teacher.id,target_photo_url:uploaded,expected_updated_at:teacher.updated_at||null});const committed=uploaded;uploaded="";if(previous&&previous!==committed){let retained=true;try{retained=await rpc("staff_id_card_photo_path_is_referenced",{target_staff_id:teacher.id,target_photo_path:previous})}catch(error){await reportClientError(error,{source:"teacher_photo_retention_check",teacher_id:teacher.id})}if(!retained)await removePrivateStorageObjects(CONFIG.staffPhotoBucket,[previous],{source:"teacher_photo_replacement_cleanup",teacher_id:teacher.id},true)}}state.workspace=null;state.teacherProfile=null;closeModal();toast("Teacher record saved");state.boot=await rpc("get_bootstrap_data");renderBrand();renderNav();await loadTeacherPage()}
    catch(error){if(uploaded)await removePrivateStorageObjects(CONFIG.staffPhotoBucket,[uploaded],{source:"teacher_photo_upload_rollback"},true);await reportClientError(error,{source:"teacher_save"});toast("Teacher not saved",friendlyError(error),"error",7000)}finally{button.disabled=false;button.textContent="Save teacher"}
  }
  async function archiveTeacher(id){const ok=await confirmAction("Remove Teacher","The staff record will be archived and active class assignments will be cleared.","Remove",true);if(!ok)return;try{await rpc("archive_teacher",{target_teacher_id:id,reason_text:"Teacher removed from active records"});state.workspace=null;toast("Teacher removed");await loadTeacherPage()}catch(error){toast("Teacher not removed",friendlyError(error),"error")}}
  async function restoreTeacher(id){const ok=await confirmAction("Restore Teacher","The staff record will return to the teacher directory.","Restore");if(!ok)return;try{await rpc("restore_teacher",{target_teacher_id:id,reason_text:"Teacher restored to active records"});state.workspace=null;toast("Teacher restored");await loadTeacherPage()}catch(error){toast("Teacher not restored",friendlyError(error),"error")}}
  async function exportTeachersCsv(){const data=await rpcAllRows("list_teachers",{search_text:byId("teacherSearch")?.value||"",status_filter:byId("teacherStatus")?.value||"",archive_filter:byId("teacherArchive")?.value||"active"});const headers=["staff_no","emis_code","first_name","middle_name","last_name","gender","date_of_birth","phone","email","qualification","specialization","date_joined","employment_status"];downloadText("teachers.csv",[headers.join(","),...(data.rows||[]).map(row=>headers.map(h=>csvCell(row[h])).join(","))].join("\n"),"text/csv")}
  async function createPrintableTeacherRecordsPdf(rows){
    if(!rows.length)throw new Error("No teacher records are available to print");const school=state.boot?.school||{},pages=[];const perPage=14;
    for(let offset=0;offset<rows.length;offset+=perPage){const batch=rows.slice(offset,offset+perPage),canvas=document.createElement("canvas");canvas.width=3508;canvas.height=2480;const ctx=canvas.getContext("2d");ctx.fillStyle="#fff";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle=idCardSafeColour(school.primary_colour,"#0a2f73");ctx.fillRect(0,0,canvas.width,205);ctx.fillStyle="#fff";ctx.font="800 58px Arial";ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),150,92);ctx.font="700 34px Arial";ctx.fillText("TEACHER RECORDS",150,155);ctx.fillStyle="#334155";ctx.font="500 24px Arial";ctx.fillText(`Generated ${new Date().toLocaleString("en-GH")} • Page ${Math.floor(offset/perPage)+1}`,150,245);const cols=[150,520,910,1360,1770,2220,2770,3350],heads=["Staff / EMIS","Name","Gender / DOB","Contact","Qualification","Specialization","Status"];let y=315;ctx.fillStyle="#e8eef8";ctx.fillRect(140,y,3220,65);ctx.fillStyle="#10213c";ctx.font="800 23px Arial";heads.forEach((h,i)=>ctx.fillText(h,cols[i],y+42));y+=75;for(const row of batch){ctx.strokeStyle="#d5deeb";ctx.strokeRect(140,y,3220,120);ctx.fillStyle="#10213c";ctx.font="700 22px Arial";ctx.fillText(String(row.staff_no||"—"),cols[0],y+36,335);ctx.font="500 19px Arial";ctx.fillText(`EMIS ${row.emis_code||"—"}`,cols[0],y+70,335);ctx.font="700 22px Arial";ctx.fillText(String(row.full_name||fullName(row)||"—"),cols[1],y+44,365);ctx.font="500 19px Arial";ctx.fillText(`${row.gender||"—"} • ${isoDate(row.date_of_birth)}`,cols[2],y+44,420);ctx.fillText(String(row.phone||"—"),cols[3],y+36,380);ctx.fillText(String(row.email||""),cols[3],y+70,380);ctx.fillText(String(row.qualification||"—"),cols[4],y+44,410);ctx.fillText(String(row.specialization||"—"),cols[5],y+44,500);ctx.fillText(statusText(row.deleted_at?"archived":row.employment_status),cols[6],y+44,500);y+=120}pages.push(await idCardCanvasBlob(canvas,.985));releaseCanvas(canvas)}return imagesPdf(pages,841.89,595.28,3508,2480)
  }
  async function downloadPrintableTeacherRecords(){setLoading(true);try{const data=await rpcAllRows("list_teachers",{search_text:byId("teacherSearch")?.value||"",status_filter:byId("teacherStatus")?.value||"",archive_filter:byId("teacherArchive")?.value||"active"}),rows=data.rows||[];downloadBlob(`teacher-records-${new Date().toISOString().slice(0,10)}.pdf`,await createPrintableTeacherRecordsPdf(rows));toast("Printable teacher records downloaded",`${rows.length} teacher record${rows.length===1?"":"s"} included.`)}catch(error){toast("Teacher records not printed",friendlyError(error),"error",8000)}finally{setLoading(false)}}

  async function renderTeacherProfile(token,force=false){
    if(!["class_teacher","subject_teacher"].includes(role()))throw new Error("Teacher profile access denied");if(force||!state.teacherProfile)state.teacherProfile=await rpc("get_my_teacher_profile");if(token!==state.viewToken)return;const data=state.teacherProfile||{},t=data.teacher||{},classes=data.classes||[],subjects=data.subjects||[];if(!data.linked){byId("content").innerHTML=`<section class="panel pad empty"><strong>No linked teacher record</strong><span>Ask the System Administrator to link your user account to your teacher record.</span></section>`;return}let photo="";if(t.photo_url){try{photo=await signedUrl(CONFIG.staffPhotoBucket,t.photo_url,900)}catch(_){}}
    byId("content").innerHTML=`<div class="page-head"><div><h3>My Teacher Profile</h3><p>Your official staff details, photograph, qualifications, and current teaching assignments</p></div></div><div class="grid two teacher-profile-layout"><section class="panel pad"><div class="teacher-profile-hero">${photo?`<img src="${attr(photo)}" alt="Teacher photograph">`:`<span>${esc(idCardInitials(t.full_name))}</span>`}<div><h3>${esc(t.full_name)}</h3><p>${esc(t.staff_no)} ${t.emis_code?`• EMIS ${esc(t.emis_code)}`:""}</p><span class="status published">${esc(ROLE_LABELS[role()]||"Teacher")}</span></div></div><div class="metric-row wrap">${maturityMetric("Assigned classes",number(data.assigned_class_count||0))}${maturityMetric("Subject assignments",number(subjects.length))}${maturityMetric("Qualification",t.qualification||"—")}</div><div class="profile-detail-grid">${verifyField("Date of birth",isoDate(t.date_of_birth))}${verifyField("Gender",t.gender||"—")}${verifyField("Telephone",t.phone||"—")}${verifyField("Email",t.email||t.profile_email||"—")}${verifyField("Specialization",t.specialization||"—")}${verifyField("Date joined",isoDate(t.date_joined))}</div></section><section class="panel pad"><div class="section-title"><h4>Profile photograph</h4></div><p class="help-text">Upload or replace your own photograph. Updates appear immediately in the System Administrator teacher directory and future staff ID cards.</p><label class="field"><span>Choose photograph</span><input id="myTeacherPhoto" type="file" accept="image/jpeg,image/png,image/webp"></label><div class="button-row"><button class="button primary" id="myTeacherPhotoSave">Save / replace photo</button>${t.photo_url?`<button class="button danger" id="myTeacherPhotoRemove">Remove current photo</button>`:""}</div><div class="section-title" style="margin-top:24px"><h4>Assigned classes</h4></div><div class="chip-list">${classes.map(c=>`<span class="chip">${esc(c.name)}</span>`).join("")||'<span class="muted">No class-teacher assignment</span>'}</div><div class="section-title" style="margin-top:18px"><h4>Subject assignments</h4></div><div class="chip-list">${subjects.map(s=>`<span class="chip">${esc(s.class_name)} • ${esc(s.subject_name)}</span>`).join("")||'<span class="muted">No subject assignment</span>'}</div></section></div>`;
    byId("myTeacherPhotoSave").onclick=async()=>{const file=byId("myTeacherPhoto").files?.[0];if(!file){toast("Choose a photograph first","Select an image before saving.","warning");return}const button=byId("myTeacherPhotoSave");button.disabled=true;let uploaded="";try{uploaded=await uploadStaffPhoto(t.id,file);const previous=t.photo_url||"";await rpc("set_teacher_photo",{target_teacher_id:t.id,target_photo_url:uploaded,expected_updated_at:t.updated_at||null});const committed=uploaded;uploaded="";if(previous&&previous!==committed){let retained=true;try{retained=await rpc("staff_id_card_photo_path_is_referenced",{target_staff_id:t.id,target_photo_path:previous})}catch(error){await reportClientError(error,{source:"teacher_profile_photo_retention_check"})}if(!retained)await removePrivateStorageObjects(CONFIG.staffPhotoBucket,[previous],{source:"teacher_profile_photo_replacement_cleanup",teacher_id:t.id},true)}state.teacherProfile=null;toast("Profile photograph updated");await renderTeacherProfile(state.viewToken,true)}catch(error){if(uploaded)await removePrivateStorageObjects(CONFIG.staffPhotoBucket,[uploaded],{source:"teacher_profile_photo_rollback"},true);toast("Photograph not saved",friendlyError(error),"error",8000)}finally{button.disabled=false}};
    byId("myTeacherPhotoRemove")?.addEventListener("click",async()=>{if(!await confirmAction("Remove profile photograph","Your current teacher profile will no longer display a photograph. Historical issued staff ID cards retain their original photograph snapshot.","Remove",true))return;try{const previous=t.photo_url||"";await rpc("set_teacher_photo",{target_teacher_id:t.id,target_photo_url:"",expected_updated_at:t.updated_at||null});if(previous){let retained=true;try{retained=await rpc("staff_id_card_photo_path_is_referenced",{target_staff_id:t.id,target_photo_path:previous})}catch(error){await reportClientError(error,{source:"teacher_profile_photo_remove_retention_check"})}if(!retained)await removePrivateStorageObjects(CONFIG.staffPhotoBucket,[previous],{source:"teacher_profile_photo_remove_cleanup",teacher_id:t.id},true)}state.teacherProfile=null;toast("Profile photograph removed");await renderTeacherProfile(state.viewToken,true)}catch(error){toast("Photograph not removed",friendlyError(error),"error",8000)}});
  }

  const TIMETABLE_DAYS=Object.freeze(["Monday","Tuesday","Wednesday","Thursday","Friday"]);
  function timetableTime(value){return String(value||"").slice(0,5)}
  async function renderTimetable(token,force=false){
    if(!["system_admin","principal","class_teacher","subject_teacher"].includes(role()))throw new Error("Timetable access denied");const years=state.boot?.academic_years||[],classes=await visibleClassesForCurrentRole();state.timetableYear=byId("timetableYear")?.value||state.timetableYear||activeYear()?.id||years[0]?.id||"";state.timetableClass=byId("timetableClass")?.value||state.timetableClass||classes[0]?.id||"";if(!classes.some(c=>c.id===state.timetableClass))state.timetableClass=classes[0]?.id||"";
    if(!state.timetableYear||!state.timetableClass){byId("content").innerHTML=`<div class="page-head"><div><h3>Timetable</h3><p>Class teaching schedule</p></div></div><section class="panel pad empty"><strong>No accessible class</strong><span>Create or assign a class before using the timetable.</span></section>`;return}
    if(force||!state.timetableConsole)state.timetableConsole=await rpc("get_class_timetable_console",{target_academic_year_id:state.timetableYear,target_class_id:state.timetableClass});if(token!==state.viewToken)return;const data=state.timetableConsole||{},entries=data.entries||[],canManage=data.can_manage===true;
    const grouped=Object.fromEntries(TIMETABLE_DAYS.map(day=>[day,entries.filter(e=>e.day_of_week===day)]));
    byId("content").innerHTML=`<div class="page-head"><div><h3>Class Timetable</h3><p>${canManage?"Create and manage teaching periods, subjects, and teacher assignments.":"View the timetable for your accessible classes."}</p></div><div class="page-actions"><button class="button outline" id="timetablePrint">Printable timetable</button>${canManage?`<button class="button primary" id="timetableAdd">Add timetable period</button>`:""}</div></div><section class="panel pad"><div class="form-grid two"><label class="field"><span>Academic year</span><select id="timetableYear">${years.map(y=>`<option value="${attr(y.id)}" ${y.id===state.timetableYear?"selected":""}>${esc(y.name)}</option>`).join("")}</select></label><label class="field"><span>Class</span><select id="timetableClass">${classes.map(c=>`<option value="${attr(c.id)}" ${c.id===state.timetableClass?"selected":""}>${esc(c.name)}</option>`).join("")}</select></label></div></section><div class="timetable-week-grid">${TIMETABLE_DAYS.map(day=>`<section class="panel timetable-day"><div class="panel-header"><div><h3>${day}</h3><p>${grouped[day].length} period${grouped[day].length===1?"":"s"}</p></div></div><div class="timetable-period-list">${grouped[day].length?grouped[day].map(e=>`<article class="timetable-period"><div class="timetable-time"><strong>${esc(timetableTime(e.period_start))}</strong><span>to</span><strong>${esc(timetableTime(e.period_end))}</strong></div><div class="cell-copy"><strong>${esc(e.subject_name)}</strong><small>${esc(e.teacher_name)}${e.notes?` • ${esc(e.notes)}`:""}</small></div>${canManage?`<div class="table-actions"><button class="button ghost small" data-timetable-edit="${attr(e.id)}">Edit</button><button class="button danger small" data-timetable-delete="${attr(e.id)}">Delete</button></div>`:""}</article>`).join(""):emptyState("No periods","No timetable entries for this day.")}</div></section>`).join("")}</div>`;
    byId("timetableYear").onchange=()=>{state.timetableYear=byId("timetableYear").value;state.timetableConsole=null;renderTimetable(state.viewToken,true)};byId("timetableClass").onchange=()=>{state.timetableClass=byId("timetableClass").value;state.timetableConsole=null;renderTimetable(state.viewToken,true)};byId("timetablePrint").onclick=()=>downloadPrintableTimetable(data);byId("timetableAdd")?.addEventListener("click",()=>openTimetableEditor(null,data));$$('[data-timetable-edit]').forEach(button=>button.onclick=()=>openTimetableEditor(entries.find(e=>e.id===button.dataset.timetableEdit),data));$$('[data-timetable-delete]').forEach(button=>button.onclick=()=>deleteTimetableEntry(button.dataset.timetableDelete));
  }
  function openTimetableEditor(entry,data){
    const subjects=data.subjects||[],teachers=data.teachers||[];modal(entry?"Edit Timetable Period":"Add Timetable Period",`${data.class?.name||"Class"} • ${data.academic_year?.name||"Academic year"}`,`<form id="timetableEntryForm" class="form-grid"><input type="hidden" name="id" value="${attr(entry?.id||"")}"><input type="hidden" name="updated_at" value="${attr(entry?.updated_at||"")}"><input type="hidden" name="academic_year_id" value="${attr(state.timetableYear)}"><input type="hidden" name="class_id" value="${attr(state.timetableClass)}"><label class="field"><span>Day</span><select name="day_of_week" required>${TIMETABLE_DAYS.map(day=>`<option value="${day}" ${entry?.day_of_week===day?"selected":""}>${day}</option>`).join("")}</select></label><label class="field"><span>Subject</span><select name="subject_id" required><option value="">Select subject</option>${subjects.map(s=>`<option value="${attr(s.id)}" ${entry?.subject_id===s.id?"selected":""}>${esc(s.name)}</option>`).join("")}</select></label><label class="field"><span>Period start</span><input type="time" name="period_start" value="${attr(timetableTime(entry?.period_start)||"08:00")}" required></label><label class="field"><span>Period end</span><input type="time" name="period_end" value="${attr(timetableTime(entry?.period_end)||"08:40")}" required></label><label class="field full"><span>Teacher</span><select name="teacher_id" required><option value="">Select teacher</option>${teachers.map(t=>`<option value="${attr(t.id)}" ${entry?.teacher_id===t.id?"selected":""}>${esc(t.name)} • ${esc(t.staff_no)}</option>`).join("")}</select></label><label class="field full"><span>Notes (optional)</span><input name="notes" maxlength="200" value="${attr(entry?.notes||"")}" placeholder="Example: ICT Lab"></label></form>`,`<button class="button ghost" id="timetableEntryCancel">Cancel</button><button class="button primary" id="timetableEntrySave">Save period</button>`,`medium`);byId("timetableEntryCancel").onclick=closeModal;byId("timetableEntrySave").onclick=async()=>{const form=byId("timetableEntryForm"),button=byId("timetableEntrySave");if(!form.reportValidity())return;button.disabled=true;try{await rpc("save_class_timetable_entry",{payload:formObject(form)});closeModal();state.timetableConsole=null;toast("Timetable period saved");await renderTimetable(state.viewToken,true)}catch(error){toast("Timetable period not saved",friendlyError(error),"error",8000)}finally{button.disabled=false}};
  }
  async function deleteTimetableEntry(id){if(!await confirmAction("Delete timetable period","This removes the selected teaching period from the current timetable.","Delete",true))return;try{await rpc("delete_class_timetable_entry",{target_entry_id:id});state.timetableConsole=null;toast("Timetable period deleted");await renderTimetable(state.viewToken,true)}catch(error){toast("Timetable period not deleted",friendlyError(error),"error",8000)}}
  async function downloadPrintableTimetable(data){setLoading(true);try{const canvas=document.createElement("canvas");canvas.width=3508;canvas.height=2480;const ctx=canvas.getContext("2d"),school=state.boot?.school||{},entries=data.entries||[];ctx.fillStyle="#fff";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle=idCardSafeColour(school.primary_colour,"#0a2f73");ctx.fillRect(0,0,canvas.width,205);ctx.fillStyle="#fff";ctx.font="800 54px Arial";ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),130,86);ctx.font="700 32px Arial";ctx.fillText(`${data.class?.name||"Class"} TIMETABLE • ${data.academic_year?.name||""}`,130,148);const days=TIMETABLE_DAYS,columns=days.length,left=85,top=280,width=3338,colW=width/columns;days.forEach((day,i)=>{const x=left+i*colW;ctx.fillStyle="#e8eef8";ctx.fillRect(x,top,colW-10,65);ctx.fillStyle="#10213c";ctx.font="800 23px Arial";ctx.fillText(day,x+14,top+43,colW-28);let y=top+82;for(const e of entries.filter(v=>v.day_of_week===day)){if(y+142>2320)break;ctx.strokeStyle="#d5deeb";ctx.strokeRect(x,y,colW-10,132);ctx.fillStyle="#10213c";ctx.font="800 19px Arial";ctx.fillText(`${timetableTime(e.period_start)}–${timetableTime(e.period_end)}`,x+12,y+31,colW-24);ctx.font="700 18px Arial";ctx.fillText(String(e.subject_name||""),x+12,y+64,colW-24);ctx.font="500 15px Arial";ctx.fillStyle="#56647a";ctx.fillText(String(e.teacher_name||""),x+12,y+94,colW-24);y+=142}});const blob=await idCardCanvasBlob(canvas,.985);releaseCanvas(canvas);downloadBlob(`timetable-${safeArchiveSegment(data.class?.name||"class")}-${safeArchiveSegment(data.academic_year?.name||"year")}.pdf`,await imagesPdf([blob],841.89,595.28,3508,2480));toast("Printable timetable downloaded")}catch(error){toast("Timetable not printed",friendlyError(error),"error",8000)}finally{setLoading(false)}}

  async function renderPrincipals(token) {
    byId("content").innerHTML=`<div class="page-head"><div><h3>Principal Directory</h3><p>Principal names, contacts, profile photographs, linked accounts, and digital signing</p></div><div class="page-actions"><button class="button outline" id="headteacherExport">Export CSV</button><button class="button primary" id="headteacherAdd">Add principal</button></div></div><section class="panel"><div class="toolbar"><label class="search"><input id="headteacherSearch" type="search" placeholder="Search full name, contact or staff number"></label><select id="headteacherArchive"><option value="active">Current records</option><option value="archived">Removed records</option><option value="all">All records</option></select></div><div id="headteacherResults"><div class="empty">Loading principals</div></div></section>`;
    byId("headteacherAdd").onclick=()=>openPrincipalEditor();byId("headteacherExport").onclick=exportPrincipalsCsv;let timer;byId("headteacherSearch").oninput=()=>{clearTimeout(timer);timer=setTimeout(()=>{state.headteacherPage=1;loadPrincipalPage(token)},250)};byId("headteacherArchive").onchange=()=>{state.headteacherPage=1;loadPrincipalPage(token)};await loadPrincipalPage(token);
  }
  async function loadPrincipalPage(token=state.viewToken){const root=byId("headteacherResults");if(!root)return;root.innerHTML=`<div class="empty">Loading principals</div>`;const data=await rpc("list_headteachers",{search_text:byId("headteacherSearch")?.value.trim()||"",status_filter:"",archive_filter:byId("headteacherArchive")?.value||"active",page_number:state.headteacherPage,page_size:CONFIG.pageSize});if(token!==state.viewToken||!byId("headteacherResults"))return;state.headteacherAdmin=data;const rows=data.rows||[];root.innerHTML=rows.length?`<div class="table-wrap"><table><thead><tr><th>Principal</th><th>Contact</th><th>Linked Account</th><th>Signature</th><th>Status</th><th></th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main">${staffAvatarHtml(row,"Principal")}<div class="cell-copy"><strong>${esc(row.full_name)}</strong><small>${esc(row.staff_no||"")}</small></div></div></td><td>${esc(row.phone||"—")}</td><td>${esc(row.profile_email||"Not linked")}</td><td>${row.signature_path?`<span class="status published">Uploaded</span>`:`<span class="status draft">Not uploaded</span>`}</td><td>${statusBadge(row.deleted_at?"archived":"active")}</td><td><div class="table-actions"><button class="button secondary small" data-headteacher-view="${attr(row.id)}">View</button>${!row.deleted_at?`<button class="button ghost small" data-headteacher-edit="${attr(row.id)}">Edit</button><button class="button danger small" data-headteacher-archive="${attr(row.id)}">Remove</button>`:`<button class="button success small" data-headteacher-restore="${attr(row.id)}">Restore</button>`}</div></td></tr>`).join("")}</tbody></table></div>${pagination(data.total,data.page,data.page_size,"principal")}`:`<div class="empty"><strong>No principals found</strong></div>`;await hydrateStaffPhotos(root);$$('[data-headteacher-view]',root).forEach(button=>button.onclick=()=>openPrincipalRecord(button.dataset.headteacherView));$$('[data-headteacher-edit]',root).forEach(button=>button.onclick=()=>openPrincipalEditor(button.dataset.headteacherEdit));$$('[data-headteacher-archive]',root).forEach(button=>button.onclick=()=>archivePrincipal(button.dataset.headteacherArchive));$$('[data-headteacher-restore]',root).forEach(button=>button.onclick=()=>restorePrincipal(button.dataset.headteacherRestore));bindPagination("principal",data)}
  async function openPrincipalRecord(id){const data=await rpc("get_headteacher_record",{target_headteacher_id:id}),h=data.headteacher||{};let photo="";if(h.photo_url){try{photo=await signedUrl(CONFIG.staffPhotoBucket,h.photo_url,900)}catch(_){}}modal(h.full_name||"Principal",h.staff_no||"",`<div class="staff-profile-record"><section class="staff-profile-summary">${photo?`<img src="${attr(photo)}" alt="Principal photograph">`:`<span class="staff-profile-placeholder">${esc(idCardInitials(h.full_name))}</span>`}<div><h3>${esc(h.full_name||"Principal")}</h3><p>${esc(h.staff_no||"")}</p></div></section><div class="grid two"><section class="panel pad"><div class="metric"><span>Contact</span><strong>${esc(h.phone||"—")}</strong></div><div class="metric"><span>Linked account</span><strong>${esc(h.profile_email||"Not linked")}</strong></div><div class="metric"><span>Qualification</span><strong>${esc(h.qualification||"—")}</strong></div></section><section class="panel pad"><div class="metric"><span>Digital signature</span><strong>${h.signature_path?"Uploaded":"Not uploaded"}</strong></div><p class="muted">The linked Principal uploads and manages the digital signature from the Principal Dashboard. Issued ID cards freeze the signature path used at issuance.</p></section></div></div>`,h.deleted_at?`<button class="button success" id="headteacherRecordRestore" type="button">Restore principal</button>`:`<button class="button primary" id="headteacherRecordEdit" type="button">Edit principal</button><button class="button danger" id="headteacherRecordArchive" type="button">Remove principal</button>`,`wide`);byId("headteacherRecordEdit")?.addEventListener("click",()=>{closeModal();openPrincipalEditor(id)});byId("headteacherRecordArchive")?.addEventListener("click",()=>{closeModal();archivePrincipal(id)});byId("headteacherRecordRestore")?.addEventListener("click",()=>{closeModal();restorePrincipal(id)})}
  async function openPrincipalEditor(id=null){let row={active:true};if(id){const data=await rpc("get_headteacher_record",{target_headteacher_id:id});row=data.headteacher||row}else{try{row.staff_no=await rpc("generate_school_identifier",{identifier_kind:"principal"})}catch(_){row.staff_no=""}}let photo="";if(row.photo_url){try{photo=await signedUrl(CONFIG.staffPhotoBucket,row.photo_url,900)}catch(_){}}modal(id?"Edit Principal":"Add Principal","",`<form id="headteacherForm" class="form-stack"><input type="hidden" name="id" value="${attr(row.id||"")}"><input type="hidden" name="updated_at" value="${attr(row.updated_at||"")}"><input type="hidden" name="profile_id" value="${attr(row.profile_id||"")}"><input type="hidden" name="staff_no" value="${attr(row.staff_no||"")}"><div class="staff-photo-editor">${photo?`<img src="${attr(photo)}" alt="Principal photograph">`:`<span>${esc(idCardInitials(row.full_name||fullName(row)||"Principal"))}</span>`}<label class="field"><span>Principal photograph</span><input id="headteacherPhotoFile" type="file" accept="image/jpeg,image/png,image/webp"><small>Optional. Used by the staff ID card generator.</small></label></div><div class="form-grid"><label class="field full"><span>Full name</span><input name="full_name" value="${attr(row.full_name||fullName(row)||"")}" required></label><label class="field full"><span>Contact</span><input name="contact" value="${attr(row.phone||"")}" required></label></div></form>`,`<button class="button ghost" id="headteacherCancel" type="button">Cancel</button><button class="button primary" id="headteacherSave" type="submit" form="headteacherForm">Save principal</button>`,`medium`);byId("headteacherCancel").onclick=closeModal;byId("headteacherForm").addEventListener("submit",event=>{event.preventDefault();savePrincipal(row)})}
  async function savePrincipal(existing={}){const form=byId("headteacherForm"),button=byId("headteacherSave");if(!form?.reportValidity()){toast("Principal not saved","Enter the full name and contact.","error");return}const v=formObject(form);button.disabled=true;button.textContent="Saving";let uploaded="";try{let saved=await rpc("save_headteacher",{payload:{...v,reason:v.id?"Principal record updated":"Principal record created"}}),h=saved.headteacher||saved;const file=byId("headteacherPhotoFile")?.files?.[0];if(file){uploaded=await uploadStaffPhoto(h.id,file);const previous=existing.photo_url||"";saved=await rpc("set_headteacher_photo",{target_headteacher_id:h.id,target_photo_url:uploaded,expected_updated_at:h.updated_at||null});const committed=uploaded;uploaded="";if(previous&&previous!==committed){let retained=true;try{retained=await rpc("staff_id_card_photo_path_is_referenced",{target_staff_id:h.id,target_photo_path:previous})}catch(error){await reportClientError(error,{source:"principal_photo_retention_check"})}if(!retained)await removePrivateStorageObjects(CONFIG.staffPhotoBucket,[previous],{source:"principal_photo_replacement_cleanup",headteacher_id:h.id},true)}}state.workspace=null;closeModal();toast("Principal record saved");state.boot=await rpc("get_bootstrap_data");renderBrand();renderNav();await loadPrincipalPage()}catch(error){if(uploaded)await removePrivateStorageObjects(CONFIG.staffPhotoBucket,[uploaded],{source:"principal_photo_upload_rollback"},true);await reportClientError(error,{source:"headteacher_save"});toast("Principal not saved",friendlyError(error),"error",7000)}finally{button.disabled=false;button.textContent="Save principal"}}
  async function archivePrincipal(id){const ok=await confirmAction("Remove Principal","The record will be archived while audit history and published reports remain preserved.","Remove",true);if(!ok)return;try{await rpc("archive_headteacher",{target_headteacher_id:id,reason_text:"Principal removed from active records"});state.workspace=null;toast("Principal removed");await loadPrincipalPage()}catch(error){toast("Principal not removed",friendlyError(error),"error")}}
  async function restorePrincipal(id){const ok=await confirmAction("Restore Principal","The principal record will return to the active directory.","Restore");if(!ok)return;try{await rpc("restore_headteacher",{target_headteacher_id:id,reason_text:"Principal restored to active records"});state.workspace=null;toast("Principal restored");await loadPrincipalPage()}catch(error){toast("Principal not restored",friendlyError(error),"error")}}
  async function exportPrincipalsCsv(){const data=await rpcAllRows("list_headteachers",{search_text:byId("headteacherSearch")?.value||"",status_filter:"",archive_filter:byId("headteacherArchive")?.value||"active"});const headers=["staff_no","full_name","phone","profile_email"];downloadText("principals.csv",[headers.join(","),...(data.rows||[]).map(row=>headers.map(h=>csvCell(row[h])).join(","))].join("\n"),"text/csv")}

  async function renderUsers(token) {
    const data=await rpc("list_profiles_with_access");
    if(token!==state.viewToken)return;
    state.userAdmin=data;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Users and Access</h3><p>Accounts, credentials, roles, classes, and security</p></div>
        <div class="page-actions"><button class="button primary" id="userAdd">Create user</button></div></div>
      <section class="panel">
        <div class="toolbar"><label class="search"><input id="userSearch" type="search" placeholder="Search name or email"></label>
          <select id="userRoleFilter"><option value="">All roles</option>${["system_admin","principal","class_teacher","subject_teacher","parent_guardian","accountant"].map(r=>`<option value="${r}">${esc(ROLE_LABELS[r])}</option>`).join("")}</select>
          <select id="userStatusFilter"><option value="">All accounts</option><option value="active">Active</option><option value="inactive">Inactive</option></select></div>
        <div id="userResults"></div>
      </section>`;
    byId("userAdd").onclick=()=>openUserEditor();
    ["userSearch","userRoleFilter","userStatusFilter"].forEach(id=>byId(id).addEventListener(id==="userSearch"?"input":"change",renderUserRows));
    renderUserRows();
  }
  function renderUserRows() {
    const root=byId("userResults");if(!root)return;
    const search=(byId("userSearch")?.value||"").trim().toLowerCase(),roleFilter=byId("userRoleFilter")?.value||"",status=byId("userStatusFilter")?.value||"";
    const rows=(state.userAdmin?.profiles||[]).filter(user=>{
      if(search&&!`${user.full_name||""} ${user.email||""} ${user.phone||""}`.toLowerCase().includes(search))return false;
      if(roleFilter&&user.role!==roleFilter)return false;
      if(status==="active"&&!user.active)return false;
      if(status==="inactive"&&user.active)return false;
      return true;
    });
    root.innerHTML=rows.length?`<div class="table-wrap"><table><thead><tr><th>User</th><th>Role</th><th>Account</th><th>MFA</th><th>Password</th><th>Class Access</th><th>Last Seen</th><th></th></tr></thead><tbody>
      ${rows.map(user=>`<tr>
        <td><div class="cell-copy"><strong>${esc(user.full_name||"Unnamed user")}</strong><small>${esc(user.email||user.phone||"")}${user.staff_no?` • ${esc(user.staff_no)}`:""}</small></div></td>
        <td>${esc(ROLE_LABELS[user.role]||user.role)}</td>
        <td>${user.active?`<span class="status published">Active</span>`:`<span class="status withdrawn">Inactive</span>`}</td>
        <td>${user.mfa_required?`<span class="status approved">Required</span>`:`<span class="status draft">Optional</span>`}</td>
        <td>${user.must_change_password?`<span class="status withdrawn">Change required</span>`:`<span class="status published">Current</span>`}</td>
        <td>${(user.access||[]).length?`<div class="chip-list">${user.access.slice(0,3).map(a=>`<span class="chip">${esc(a.class_name)}${a.subject_name?` • ${esc(a.subject_name)}`:""}</span>`).join("")}${user.access.length>3?`<span class="chip">+${user.access.length-3}</span>`:""}</div>`:"School role"}</td>
        <td>${isoDateTime(user.last_seen_at||user.last_sign_in_at)}</td><td><div class="table-actions"><button class="button ghost small" data-user-edit="${attr(user.id)}">Edit</button><button class="button secondary small" data-user-reset="${attr(user.id)}">Reset password</button>${user.id!==state.boot.profile.id?`<button class="button danger small" data-user-delete="${attr(user.id)}">Delete</button>`:""}</div></td>
      </tr>`).join("")}</tbody></table></div>`:`<div class="empty"><strong>No users found</strong></div>`;
    $$("[data-user-edit]",root).forEach(button=>button.onclick=()=>openUserEditor(button.dataset.userEdit));
    $$("[data-user-reset]",root).forEach(button=>button.onclick=()=>openPasswordReset(button.dataset.userReset));
    $$("[data-user-delete]",root).forEach(button=>button.onclick=()=>deleteUserAccount(button.dataset.userDelete));
  }
  const ACCOUNT_EMAIL_TITLES=new Set(["mr","mrs","ms","miss","madam","master","dr","doctor","rev","reverend","prof","professor","principal","headmaster","headmistress"]);
  let userEmailPreviewTimer=0,userEmailPreviewToken=0;
  function accountEmailBase(fullNameValue) {
    const parts=String(fullNameValue||"").normalize("NFKD").replace(/[\u0300-\u036f]/g,"").toLowerCase().split(/\s+/)
      .map(part=>part.replace(/[^a-z0-9]/g,"")).filter(Boolean);
    return parts.find(part=>!ACCOUNT_EMAIL_TITLES.has(part))||parts[0]||"";
  }
  function generatedSchoolEmail(fullNameValue) {
    const base=accountEmailBase(fullNameValue);return base?`${base}@${schoolEmailDomain()}`:"";
  }
  async function refreshGeneratedUserEmail(userId=null) {
    const form=byId("userForm"),input=form?.elements?.email;if(!form||!input||userId)return;
    const base=accountEmailBase(form.elements.full_name.value),fallback=base?`${base}@${schoolEmailDomain()}`:"";
    input.value=fallback;
    if(!base||!state.boot?.profile?.id)return;
    const token=++userEmailPreviewToken;
    try{
      const resolved=await rpc("generate_nip_user_email",{actor_id:state.boot.profile.id,requested_base:base,target_user_id:null});
      if(token===userEmailPreviewToken&&byId("userForm")===form)input.value=String(resolved||fallback);
    }catch(_){/* The protected Edge Function performs the authoritative generation. */}
  }
  function scheduleGeneratedUserEmail(userId=null) {
    clearTimeout(userEmailPreviewTimer);
    userEmailPreviewTimer=setTimeout(()=>refreshGeneratedUserEmail(userId),220);
  }

  function openUserEditor(id=null) {
    const user=id?(state.userAdmin.profiles||[]).find(x=>x.id===id):{role:"parent_guardian",active:true,mfa_required:false,must_change_password:false,access:[]};if(!user)return;
    const initialEmail=id?(user.email||generatedSchoolEmail(user.full_name||"")):generatedSchoolEmail(user.full_name||"");
    state.userAccessRows=(user.access||[]).map(x=>({...x}));
    state.userAccessEditingUserId=id||"";
    state.userAccessClassSelections=new Set();
    state.userAccessSubjectSelections=new Set();
    state.userAccessAllSubjects=false;
    modal(id?"Edit User Account":"Create User Account",user.email||"",`<form id="userForm" class="form-stack">
      <div class="form-grid">
        <label class="field full hidden" id="userStaffField"><span id="userStaffLabel">Staff record</span><select id="userStaffSelect" name="staff_record_id"></select></label>
        <label class="field"><span>Full name</span><input name="full_name" value="${attr(user.full_name||"")}" required></label>
        <label class="field"><span>Email address</span><input name="email" type="email" value="${attr(initialEmail)}" readonly required></label>
        <label class="field"><span>Telephone</span><input name="phone" value="${attr(user.phone||"")}"></label>
        <label class="field"><span>Role</span><select id="userRoleSelect" name="role">
          ${["system_admin","principal","class_teacher","subject_teacher","parent_guardian","accountant"].map(r=>`<option value="${r}" ${r===user.role?"selected":""}>${esc(ROLE_LABELS[r])}</option>`).join("")}
        </select></label>
        ${id?`<div class="help-text full">Use the separate <strong>Reset password</strong> action after saving account details.</div>`:`<label class="field full"><span>Password</span><div class="password-wrap"><input id="adminUserPassword" name="password" type="password" autocomplete="new-password" required><button id="generateUserPassword" class="button ghost small" type="button">Generate</button></div></label>`}
        <label class="check-field"><input name="active" type="checkbox" ${user.active!==false?"checked":""}><span>Active account</span></label>
        <label class="check-field"><input name="mfa_required" type="checkbox" ${user.mfa_required?"checked":""}><span>Require multi-factor authentication</span></label>
        <label class="check-field full"><input name="must_change_password" type="checkbox" ${user.must_change_password?"checked":""}><span>Force password change on next login</span></label>
      </div>
      <div id="userAccessSection"><div class="section-title"><div><h4>Teaching Responsibilities</h4><p class="help-text">Class Teacher and subject-teaching access is synchronised from Academics.</p></div></div><div id="userAccessRows"></div></div>
    </form>`,`<button class="button ghost" id="userCancel" type="button">Cancel</button><button class="button primary" id="userSave" type="button">${id?"Save account":"Create account"}</button>`,"wide");
    renderUserAccessRows();
    renderUserStaffSelector(id||"",user.headteacher_id||user.teacher_id||user.accountant_id||"");
    const userForm=byId("userForm");
    userForm.elements.full_name.addEventListener("input",()=>scheduleGeneratedUserEmail(id));
    if(!id)scheduleGeneratedUserEmail(null);
    const generatePasswordButton=byId("generateUserPassword");
    if(generatePasswordButton)generatePasswordButton.onclick=()=>{const password=generateSecurePassword();byId("adminUserPassword").value=password;byId("adminUserPassword").type="text"};
    const syncRoleMfaRequirement=()=>{
      const mfaField=userForm.elements.mfa_required,financeRole=byId("userRoleSelect")?.value==="accountant";
      if(financeRole)mfaField.checked=true;
      mfaField.disabled=financeRole;
      mfaField.closest("label")?.setAttribute("title",financeRole?"MFA is mandatory for Accounts Office Staff because Finance requires AAL2.":"");
    };
    byId("userRoleSelect").onchange=()=>{
      syncUserAccessRowsFromSelections();
      renderUserAccessRows();
      renderUserStaffSelector(id||"","");
      syncRoleMfaRequirement();
    };
    syncRoleMfaRequirement();
    byId("userCancel").onclick=closeModal;
    byId("userSave").onclick=()=>saveUserAccount(id);
  }

  function staffRecordsForUserRole(roleName,userId="") {
    const source=roleName==="principal"?(state.userAdmin?.headteacher_records||[]):
      (roleName==="accountant"?(state.userAdmin?.accountant_records||[]):
      (["class_teacher","subject_teacher"].includes(roleName)?(state.userAdmin?.teacher_records||[]):[]));
    return source.filter(record=>!record.profile_id||record.profile_id===userId);
  }
  function renderUserStaffSelector(userId="",selectedId="") {
    const roleName=byId("userRoleSelect")?.value||"parent_guardian",field=byId("userStaffField"),select=byId("userStaffSelect"),label=byId("userStaffLabel");
    if(!field||!select||!label)return;
    const requiredRole=["principal","class_teacher","subject_teacher","accountant"].includes(roleName);
    field.classList.toggle("hidden",!requiredRole);select.required=requiredRole;
    if(!requiredRole){select.innerHTML='<option value="">Not applicable</option>';select.value="";return}
    const rows=staffRecordsForUserRole(roleName,userId);
    label.textContent=roleName==="principal"?"Principal record":roleName==="accountant"?"Accounts Office Staff record":"Teacher record";
    select.innerHTML=optionList(rows,"id","label",selectedId,roleName==="principal"?"Select principal":roleName==="accountant"?"Select Accounts Office Staff":"Select teacher");
    if(selectedId&&rows.some(row=>row.id===selectedId))select.value=selectedId;
    select.onchange=()=>{
      const record=rows.find(item=>item.id===select.value);if(!record)return;
      const form=byId("userForm");if(!form)return;
      form.elements.full_name.value=record.full_name||"";
      if(!userId)scheduleGeneratedUserEmail(null);
      if(record.phone)form.elements.phone.value=record.phone;
    };
  }

  function generateSecurePassword(length=14) {
    const sets=["ABCDEFGHJKLMNPQRSTUVWXYZ","abcdefghijkmnopqrstuvwxyz","23456789","!@#$%&*"];
    const values=new Uint32Array(length);crypto.getRandomValues(values);
    const chars=sets.map((set,index)=>set[values[index]%set.length]);
    const all=sets.join("");for(let i=chars.length;i<length;i++)chars.push(all[values[i]%all.length]);
    for(let i=chars.length-1;i>0;i--){const j=values[i]% (i+1);[chars[i],chars[j]]=[chars[j],chars[i]]}
    return chars.join("");
  }
  function userAccessKey(classId,subjectId){return `${classId}|${subjectId||"*"}`}

  function teacherResponsibilityAccessRows(userId=state.userAccessEditingUserId) {
    if(!userId)return [];
    const rows=[],seen=new Set();
    (state.userAdmin?.classes||[]).filter(item=>
      item.active!==false&&!item.deleted_at&&item.class_teacher_id===userId
    ).forEach(item=>{
      const key=userAccessKey(item.id,null);
      if(!seen.has(key)){seen.add(key);rows.push({class_id:item.id,subject_id:null,access_level:"edit"})}
    });
    (state.userAdmin?.class_subjects||[]).filter(item=>
      item.active!==false&&item.teacher_id===userId&&item.class_id&&item.subject_id
    ).forEach(item=>{
      const key=userAccessKey(item.class_id,item.subject_id);
      if(!seen.has(key)){seen.add(key);rows.push({class_id:item.class_id,subject_id:item.subject_id,access_level:"score"})}
    });
    return rows;
  }

  function syncUserAccessRowsFromSelections() {
    state.userAccessRows=teacherResponsibilityAccessRows();
  }

  function renderUserAccessRows() {
    const root=byId("userAccessRows"),section=byId("userAccessSection");if(!root)return;
    const roleName=byId("userRoleSelect")?.value||"parent_guardian";
    const teacherRole=["class_teacher","subject_teacher"].includes(roleName);
    if(section)section.classList.toggle("hidden",!teacherRole);
    if(!teacherRole){state.userAccessRows=[];root.innerHTML="";return}

    const userId=state.userAccessEditingUserId;
    if(!userId){
      root.innerHTML=`<div class="responsibility-empty">
        <strong>Create the teacher account first</strong>
        <span>After the account is created, assign the home class and exact subjects under Academics.</span>
      </div>`;
      state.userAccessRows=[];
      return;
    }

    const classes=state.userAdmin?.classes||[];
    const subjects=state.userAdmin?.subjects||[];
    const classById=new Map(classes.map(item=>[item.id,item]));
    const subjectById=new Map(subjects.map(item=>[item.id,item]));
    const homeClasses=classes.filter(item=>
      item.active!==false&&!item.deleted_at&&item.class_teacher_id===userId
    );
    const exactAssignments=(state.userAdmin?.class_subjects||[]).filter(item=>
      item.active!==false&&item.teacher_id===userId&&item.class_id&&item.subject_id
    );
    const grouped=new Map();
    exactAssignments.forEach(item=>{
      const classItem=classById.get(item.class_id);
      const subjectItem=subjectById.get(item.subject_id);
      if(!classItem||!subjectItem)return;
      if(!grouped.has(item.class_id))grouped.set(item.class_id,{class_name:classItem.name,subjects:[]});
      grouped.get(item.class_id).subjects.push(subjectItem.name);
    });
    state.userAccessRows=teacherResponsibilityAccessRows(userId);

    root.innerHTML=`<div class="teaching-responsibility-summary">
      <article><span>Class Teacher Responsibility</span><strong>${homeClasses.length?homeClasses.map(item=>esc(item.name)).join(", "):"Not assigned"}</strong><small>${homeClasses.length?"Full class-report responsibility":"Assign a home class under Academics → Classes"}</small></article>
      <article><span>Subject Teaching Responsibility</span><strong>${exactAssignments.length} exact assignment${exactAssignments.length===1?"":"s"}</strong><small>${grouped.size} class${grouped.size===1?"":"es"} • ${new Set(exactAssignments.map(item=>item.subject_id)).size} subject${new Set(exactAssignments.map(item=>item.subject_id)).size===1?"":"s"}</small></article>
    </div>
    <div class="responsibility-groups">
      ${grouped.size?[...grouped.values()].map(group=>`<div class="responsibility-group">
        <strong>${esc(group.class_name)}</strong>
        <span>${group.subjects.sort((a,b)=>a.localeCompare(b)).map(name=>esc(name)).join(", ")}</span>
      </div>`).join(""):`<div class="responsibility-empty"><strong>No subject assignments</strong><span>Use Assign Subjects under Academics to add exact class-subject responsibilities.</span></div>`}
    </div>
    <div class="button-row"><button class="button secondary small" id="manageTeachingResponsibilities" type="button">Manage in Academics</button></div>`;

    byId("manageTeachingResponsibilities").onclick=()=>{
      closeModal();
      state.academicTab="classes";
      navigate("academics");
    };
  }
  async function invokeAdminUserManagement(action,payload) {
    let {data:{session}}=await state.client.auth.getSession();
    if(!session)throw new Error("Your session has expired. Sign in again.");
    if(Number(session.expires_at||0)*1000-Date.now()<90000){
      const refreshed=await state.client.auth.refreshSession();session=refreshed.data.session||session;state.session=session;
    }
    const {data,error}=await state.client.functions.invoke("admin-user-management",{
      body:{action,payload},headers:{Authorization:`Bearer ${session.access_token}`}
    });
    if(error){
      let message=error.message||"User account operation failed";
      try{const detail=await error.context?.json();if(detail?.message)message=String(detail.message);else if(detail?.error)message=String(detail.error)}catch(_){}
      throw new Error(message.replaceAll("_"," "));
    }
    if(data?.error)throw new Error(String(data.message||data.error).replaceAll("_"," "));
    return data;
  }
  async function saveUserAccount(userId=null) {
    const form=byId("userForm"),button=byId("userSave");if(!form?.reportValidity())return;
    const v=formObject(form);button.disabled=true;button.textContent=userId?"Saving":"Creating";let saved=false;
    try{
      if(!userId&&String(v.password||"").length<8)throw new Error("Password must contain at least 8 characters");
      if(userId&&v.password)throw new Error("Use Reset password for password changes");
      if(["principal","class_teacher","subject_teacher","accountant"].includes(v.role)&&!v.staff_record_id)throw new Error("Select the corresponding staff record");
      syncUserAccessRowsFromSelections();
      const payload={user_id:userId||undefined,full_name:v.full_name.trim(),email:v.email.trim(),phone:v.phone.trim(),role:v.role,staff_record_id:v.staff_record_id||"",
        password:userId?"":(v.password||""),active:form.elements.active.checked,mfa_required:v.role==="accountant"?true:form.elements.mfa_required.checked,
        must_change_password:form.elements.must_change_password.checked,
        access:state.userAccessRows.filter(x=>x.class_id),reason:userId?"User account updated":"User account created"};
      await invokeAdminUserManagement(userId?"update":"create",payload);saved=true;state.workspace=null;closeModal();toast(userId?"User account saved":"User account created");
      try{state.userAdmin=await rpc("list_profiles_with_access");state.boot=await rpc("get_bootstrap_data");renderBrand();renderNav();renderUserRows()}
      catch(refreshError){await reportClientError(refreshError,{source:"user_account_save",user_id:userId,stage:"refresh"});toast("Account saved","Reload the page to display the latest access record.","warning",6500)}
    }catch(error){await reportClientError(error,{source:"user_account_save",user_id:userId,stage:saved?"refresh":"record"});toast(saved?"Account saved":"User account not saved",saved?"Reload the page to display the latest access record.":friendlyError(error),saved?"warning":"error",6500)}finally{button.disabled=false;button.textContent=userId?"Save account":"Create account"}
  }


  function openPasswordReset(userId) {
    const user=(state.userAdmin?.profiles||[]).find(item=>item.id===userId);if(!user)return;
    const temporary=generateSecurePassword();
    modal("Reset User Password",user.email||user.full_name||"",`<form id="passwordResetForm" class="form-stack">
      <label class="field"><span>Temporary password</span><div class="password-wrap"><input name="password" type="text" value="${attr(temporary)}" minlength="8" autocomplete="new-password" required><button class="button ghost small" id="regenerateResetPassword" type="button">Generate</button></div></label>
      <label class="check-field"><input name="force_password_change" type="checkbox" checked><span>Force password change on next login</span></label>
      <p class="help-text">Copy and share the temporary password securely with the account owner.</p>
    </form>`,`<button class="button ghost" id="passwordResetCancel" type="button">Cancel</button><button class="button primary" id="passwordResetSave" type="button">Reset password</button>`,"small");
    byId("regenerateResetPassword").onclick=()=>{byId("passwordResetForm").elements.password.value=generateSecurePassword()};
    byId("passwordResetCancel").onclick=closeModal;
    byId("passwordResetSave").onclick=async()=>{
      const form=byId("passwordResetForm"),button=byId("passwordResetSave");if(!form?.reportValidity())return;
      button.disabled=true;button.textContent="Resetting";
      try{
        await invokeAdminUserManagement("reset_password",{user_id:userId,password:form.elements.password.value,
          force_password_change:form.elements.force_password_change.checked,reason:"Password reset by the System Administrator"});
        closeModal();toast("Password reset",form.elements.force_password_change.checked?"The user must change it at the next login.":"The temporary password is active.");
        state.userAdmin=await rpc("list_profiles_with_access");renderUserRows();
      }catch(error){toast("Password not reset",friendlyError(error),"error",6500)}
      finally{button.disabled=false;button.textContent="Reset password"}
    };
  }

  async function deleteUserAccount(userId) {
    const user=(state.userAdmin?.profiles||[]).find(item=>item.id===userId);if(!user)return;
    const ok=await confirmAction("Delete User Account",`Permanently delete ${user.full_name||user.email||"this account"}? The linked staff record will remain but will no longer have a login.`,"Delete",true);if(!ok)return;
    try{
      await invokeAdminUserManagement("delete",{user_id:userId,reason:"User account permanently deleted by the System Administrator"});
      toast("User account deleted");state.workspace=null;
      state.userAdmin=await rpc("list_profiles_with_access");state.boot=await rpc("get_bootstrap_data");renderBrand();renderNav();renderUserRows();
    }catch(error){toast("User account not deleted",friendlyError(error),"error",6500)}
  }

  async function renderNotifications(token) {
    const data=await rpc("list_notifications",{page_number:1,page_size:100});
    if(token!==state.viewToken)return;
    state.notifications=data.rows||[];
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Notifications</h3><p>${number(data.unread)} unread • ${number(data.total)} total</p></div>
        <div class="page-actions">${data.unread?`<button class="button secondary" id="markAllRead">Mark all read</button>`:""}${state.notifications.length?`<button class="button danger" id="clearNotifications">Clear notifications</button>`:""}</div></div>
      <section class="panel"><div class="managed-card-list">
        ${state.notifications.length?state.notifications.map(item=>`<div class="panel-header" data-notification-id="${attr(item.id)}" style="${item.read_at?"opacity:.7":""}">
          <div><h4>${esc(item.title)}</h4><p>${esc(item.body)} • ${isoDateTime(item.created_at)}</p></div>
          <div class="button-row">${item.entity_type==="report"&&item.entity_id?`<button class="button outline small" data-notification-report="${attr(item.entity_id)}">Open</button>`:""}
            ${!item.read_at?`<button class="button ghost small" data-notification-read="${attr(item.id)}">Mark read</button>`:""}<button class="button danger small" data-notification-delete="${attr(item.id)}">Delete</button></div>
        </div>`).join(""):`<div class="empty"><strong>No notifications</strong></div>`}
      </div></section>`;
    byId("markAllRead")?.addEventListener("click",async()=>{await rpc("mark_notifications_read",{notification_ids:null});await loadNotificationCount();renderNotifications(state.viewToken,true)});
    byId("clearNotifications")?.addEventListener("click",async()=>{if(!await confirmAction("Clear Notifications","Delete all notifications for this account?","Clear",true))return;await rpc("delete_notifications",{notification_ids:null});await loadNotificationCount();renderNotifications(state.viewToken,true)});
    $$('[data-notification-read]').forEach(button=>button.onclick=async()=>{await rpc("mark_notifications_read",{notification_ids:[button.dataset.notificationRead]});await loadNotificationCount();renderNotifications(state.viewToken,true)});
    $$('[data-notification-delete]').forEach(button=>button.onclick=async()=>{if(!await confirmAction("Delete Notification","Remove this notification?","Delete",true))return;await rpc("delete_notifications",{notification_ids:[button.dataset.notificationDelete]});await loadNotificationCount();renderNotifications(state.viewToken,true)});
    $$('[data-notification-report]').forEach(button=>button.onclick=()=>openReportEditor(button.dataset.notificationReport));
  }

  async function renderAudit(token) {
    const data=await rpc("list_audit_events",{target_table:null,target_record_id:null,page_number:1,page_size:100});
    if(token!==state.viewToken)return;
    state.audit=data;
    const tables=[...new Set((data.rows||[]).map(x=>x.table_name))].sort();
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Audit Trail</h3><p>${number(data.total)} recorded changes</p></div><div class="page-actions"><button class="button danger" id="auditReset">Reset audit log</button></div></div>
      <section class="panel">
        <div class="toolbar"><select id="auditTable"><option value="">All records</option>${tables.map(t=>`<option value="${attr(t)}">${esc(t.replaceAll("_"," "))}</option>`).join("")}</select></div>
        <div id="auditRows">${auditRows(data.rows||[])}</div>
      </section>`;
    byId("auditTable").onchange=async()=>{
      const filtered=await rpc("list_audit_events",{target_table:byId("auditTable").value||null,target_record_id:null,page_number:1,page_size:100});
      state.audit=filtered;byId("auditRows").innerHTML=auditRows(filtered.rows||[]);bindAuditRows();
    };
    byId("auditReset").onclick=resetAuditLog;
    bindAuditRows();
  }
  function auditRows(rows) {
    return rows.length?`<div class="table-wrap"><table><thead><tr><th>Time</th><th>Actor</th><th>Record</th><th>Action</th><th>Reason</th><th></th></tr></thead><tbody>
      ${rows.map((row,index)=>`<tr><td>${isoDateTime(row.created_at)}</td><td>${esc(row.actor_name||"System")}</td><td>${esc(row.table_name)}<br><small>${esc(row.record_id||"")}</small></td>
      <td><span class="chip">${esc(row.action)}</span></td><td>${esc(row.reason||"")}</td><td><div class="table-actions"><button class="button ghost small" data-audit-index="${index}">Details</button><button class="button danger small" data-audit-delete="${attr(row.id)}">Archive</button></div></td></tr>`).join("")}
    </tbody></table></div>`:`<div class="empty"><strong>No audit events</strong></div>`;
  }
  function bindAuditRows() {
    $$('[data-audit-index]').forEach(button=>button.onclick=()=>{
      const row=(state.audit.rows||[])[Number(button.dataset.auditIndex)];
      modal("Audit Event",`${row.table_name} • ${row.action}`,`<div class="revision-compare"><div class="diff-card"><h4>Before</h4><pre>${esc(JSON.stringify(row.old_data,null,2))}</pre></div><div class="diff-card"><h4>After</h4><pre>${esc(JSON.stringify(row.new_data,null,2))}</pre></div></div>`,`<button class="button ghost" id="auditClose" type="button">Close</button>`,"wide");
      byId("auditClose").onclick=closeModal;
    });
    $$('[data-audit-delete]').forEach(button=>button.onclick=async()=>{if(!await confirmAction("Archive Audit Event","Move this event from the active console into the retained audit archive?","Archive",true))return;await rpc("delete_audit_events",{event_ids:[Number(button.dataset.auditDelete)]});toast("Audit event archived");await renderAudit(state.viewToken,true)});
  }
  async function resetAuditLog() {
    modal("Archive Audit Log","This moves the current audit trail into the retained audit archive and clears only the active console.",`<div class="form-stack"><p class="help-text">Type <strong>ARCHIVE AUDIT LOG</strong> to confirm.</p><label class="field"><span>Confirmation</span><input id="auditResetConfirm" autocomplete="off"></label></div>`,`<button class="button ghost" id="auditResetCancel" type="button">Cancel</button><button class="button danger" id="auditResetRun" type="button">Archive audit log</button>`,"small");
    byId("auditResetCancel").onclick=closeModal;
    byId("auditResetRun").onclick=async()=>{const value=byId("auditResetConfirm").value;try{const result=await rpc("reset_audit_log",{confirmation_text:value});closeModal();toast("Audit log archived",`${number(result.archived??result.deleted)} events retained in the archive`);await renderAudit(state.viewToken,true)}catch(error){toast("Audit log not archived",friendlyError(error),"error")}};
  }


  function reportTemplateCardsHtml(templates=[],loadError="") {
    if(loadError)return `<div class="template-information"><strong>Template service unavailable</strong><span>${esc(loadError)}</span></div>`;
    return `<div class="report-template-grid">${REPORT_TEMPLATE_GROUPS.map(group=>{
      const template=templates.find(item=>item.range_key===group.key),classes=templateClassesForRange(group.key);
      return `<article class="report-template-card" data-template-card="${attr(group.key)}">
        <div class="report-template-card-head"><div><h5>${esc(group.label)}</h5><p>${classes.length?esc(classes.map(item=>item.name).join(", ")):"No matching active classes found"}</p></div>
          <span class="status ${template?"published":"draft"}">${template?"Assigned":"Built-in fallback"}</span></div>
        ${template?`<div class="template-file-summary"><strong>${esc(template.original_name)}</strong><span>${esc(String(template.mime_type||"").includes("pdf")?"PDF":"DOCX")} • ${readableBytes(template.file_size)} • Version ${number(template.version||1)}</span><small>Updated ${isoDateTime(template.updated_at)}</small></div>`:
          `<div class="template-file-summary empty-template"><strong>No uploaded template</strong><span>The approved built-in terminal-report design is used automatically for this class range.</span></div>`}
        <label class="field"><span>${template?"Replace template":"Upload template"}</span><input type="file" data-template-file="${attr(group.key)}" accept=".pdf,.docx,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document"></label>
        <div class="button-row">
          <button class="button primary small" type="button" data-template-upload="${attr(group.key)}">${template?"Replace":"Upload"}</button>
          ${template?`<button class="button outline small" type="button" data-template-preview="${attr(group.key)}">Preview</button><button class="button secondary small" type="button" data-template-download="${attr(group.key)}">Download</button><button class="button danger small" type="button" data-template-remove="${attr(group.key)}">Remove</button>`:""}
        </div>
      </article>`;
    }).join("")}</div>`;
  }

  function findReportTemplate(rangeKey) {
    return (state.reportTemplates||[]).find(item=>item.range_key===rangeKey)||null;
  }

  async function uploadReportCardTemplate(rangeKey) {
    const input=document.querySelector(`[data-template-file="${rangeKey}"]`),button=document.querySelector(`[data-template-upload="${rangeKey}"]`);
    const file=input?.files?.[0];
    try{
      const info=validateReportTemplateFile(file);button.disabled=true;setLoading(true);button.textContent="Validating";
      await renderReportTemplateBlob(file,info.mimeType);
      button.textContent="Uploading";
      const checksum=await sha256(file),path=`${rangeKey}/${Date.now()}-${uuid()}.${info.extension}`,previous=findReportTemplate(rangeKey);
      const {error}=await state.client.storage.from(CONFIG.templateBucket).upload(path,file,{contentType:info.mimeType,upsert:false,cacheControl:"3600"});if(error)throw error;
      try{
        await rpc("save_report_card_template",{target_range_key:rangeKey,target_storage_path:path,target_original_name:file.name,target_mime_type:info.mimeType,target_file_size:file.size,target_checksum:checksum});
      }catch(error){await removePrivateStorageObjects(CONFIG.templateBucket,[path],{source:"report_template_upload_rollback",range_key:rangeKey},true);throw error}
      if(previous?.storage_path&&previous.storage_path!==path)await removePrivateStorageObjects(CONFIG.templateBucket,[previous.storage_path],{source:"report_template_replacement_cleanup",range_key:rangeKey},true);
      state.reportTemplates=null;state.reportTemplatesLoadedAt=0;state.templateUrls.clear();state.templateCanvases.clear();
      toast("Report-card template assigned",`${reportTemplateGroup(rangeKey)?.shortLabel||rangeKey} now uses ${file.name}.`);
      try{await renderSettings(state.viewToken,true)}catch(refreshError){await reportClientError(refreshError,{source:"report_template_upload_refresh",range_key:rangeKey});toast("Template saved","Reload the page to refresh the template settings.","warning",7000)}
    }catch(error){toast("Template not uploaded",friendlyError(error),"error",7000);await reportClientError(error,{source:"report_template_upload",range_key:rangeKey})}
    finally{setLoading(false);if(button){button.disabled=false;button.textContent=findReportTemplate(rangeKey)?"Replace":"Upload"}}
  }

  async function reportTemplateBlob(template) {
    const {data,error}=await state.client.storage.from(CONFIG.templateBucket).download(template.storage_path);if(error)throw error;return data;
  }

  async function previewReportCardTemplate(rangeKey) {
    const template=findReportTemplate(rangeKey);if(!template)return;
    setLoading(true);
    try{
      const canvas=await renderReportTemplateBlob(await reportTemplateBlob(template),template.mime_type);
      modal(
        `${reportTemplateGroup(rangeKey)?.shortLabel||"Report"} Template`,
        `${template.original_name} • exact uploaded-file preview`,
        `<div class="report-template-preview"><img src="${canvas.toDataURL("image/png")}" alt="Exact uploaded report-card template preview"></div>
         <div class="template-preview-note">This preview shows the uploaded design exactly as supplied. When an official report is generated, the system clears pre-filled sample data and inserts the current student details, results, QR code and current Principal signature without ghost text.</div>`,
        `<button class="button ghost" id="templatePreviewClose" type="button">Close</button><button class="button primary" id="templatePreviewDownload" type="button">Download original</button>`,
        "wide"
      );
      byId("templatePreviewClose").onclick=closeModal;
      byId("templatePreviewDownload").onclick=()=>downloadReportCardTemplate(rangeKey);
    }catch(error){
      toast("Preview unavailable",friendlyError(error),"error",6500);
    }finally{
      setLoading(false);
    }
  }

  async function downloadReportCardTemplate(rangeKey) {
    const template=findReportTemplate(rangeKey);if(!template)return;
    try{downloadBlob(template.original_name,await reportTemplateBlob(template))}catch(error){toast("Template not downloaded",friendlyError(error),"error")}
  }

  async function removeReportCardTemplate(rangeKey) {
    const template=findReportTemplate(rangeKey);if(!template)return;
    const group=reportTemplateGroup(rangeKey);
    if(!await confirmAction("Remove Report-card Template",`${group?.label||rangeKey} will return to the approved built-in report-card design. Existing published PDF files remain unchanged until regenerated.`,"Remove",true))return;
    try{
      const removed=await rpc("remove_report_card_template",{target_range_key:rangeKey});
      if(removed?.storage_path)await removePrivateStorageObjects(CONFIG.templateBucket,[removed.storage_path],{source:"report_template_remove_cleanup",range_key:rangeKey},true);
      state.reportTemplates=null;state.reportTemplatesLoadedAt=0;state.templateUrls.clear();state.templateCanvases.clear();
      toast("Report-card template removed",`${group?.shortLabel||rangeKey} now uses the built-in design.`);try{await renderSettings(state.viewToken,true)}catch(refreshError){await reportClientError(refreshError,{source:"report_template_remove_refresh",range_key:rangeKey});toast("Template removed","Reload the page to refresh the template settings.","warning",7000)}
    }catch(error){toast("Template not removed",friendlyError(error),"error",6500)}
  }

  function bindReportTemplateAdmin() {
    $$('[data-template-upload]').forEach(button=>button.onclick=()=>uploadReportCardTemplate(button.dataset.templateUpload));
    $$('[data-template-preview]').forEach(button=>button.onclick=()=>previewReportCardTemplate(button.dataset.templatePreview));
    $$('[data-template-download]').forEach(button=>button.onclick=()=>downloadReportCardTemplate(button.dataset.templateDownload));
    $$('[data-template-remove]').forEach(button=>button.onclick=()=>removeReportCardTemplate(button.dataset.templateRemove));
  }


  function licenceLimitText(value) {return value==null?"Unlimited":number(value)}
  function licenceUsageMetric(label,used,limit) {
    const capped=limit!=null,ratio=capped&&Number(limit)>0?Math.min(100,Math.round(Number(used||0)/Number(limit)*100)):0;
    return `<div class="metric"><span>${esc(label)}</span><strong>${number(used)}${capped?` / ${number(limit)}`:""}</strong>${capped?`<div class="progress compact"><span style="width:${ratio}%"></span></div>`:`<small>Unlimited by plan</small>`}</div>`;
  }
  function platformEventSummary(event) {
    return ({license_initialized:"Licence initialized",license_updated:"Licence updated",access_lock_applied:"Access lock applied",access_lock_released:"Access lock released",platform_admin_provisioned:"Platform administrator provisioned"})[event.event_type]||String(event.event_type||"Event").replaceAll("_"," ");
  }
  function delegationComputedStatus(row={}) {
    return row.computed_status||row.status||"unknown";
  }
  function delegationStatusHtml(row={}) {
    const value=delegationComputedStatus(row),klass=value==="active"?"published":value==="scheduled"?"submitted":value==="expired"?"returned":"withdrawn";
    return `<span class="status ${klass}">${esc(value.replaceAll("_"," "))}</span>`;
  }
  function delegationTypeLabel(value="") {
    return value==="system_admin_override"?"System Administrator emergency entry":"Replacement teacher";
  }
  function delegationCapabilities(row={}) {
    return [row.allow_score_entry?"Scores":"",row.allow_class_report_fields?"Class report details":""].filter(Boolean).join(" + ")||"None";
  }
  function delegationUserOptions(users=[],type="replacement_teacher",selected="") {
    const allowed=users.filter(user=>type==="system_admin_override"?user.role==="system_admin":["class_teacher","subject_teacher"].includes(user.role));
    return optionList(allowed,"id","full_name",selected,allowed.length?"Select delegate":"No eligible account");
  }
  function delegationSubjectOptions(data,classId,selected="") {
    const subjects=(data.class_subjects||[]).filter(item=>item.class_id===classId);
    return `<option value="">All assigned subjects</option>${subjects.map(item=>`<option value="${attr(item.subject_id)}" ${selected===item.subject_id?"selected":""}>${esc(item.subject_name)}${item.assigned_teacher_name?` • ${esc(item.assigned_teacher_name)}`:""}</option>`).join("")}`;
  }
  async function renderEmergencyDelegations(token,force=false) {
    if(!["system_admin","principal"].includes(role()))throw new Error("Emergency delegation is available only to the System Administrator and Principal");
    if(force||!state.delegationConsole)state.delegationConsole=await rpc("get_emergency_delegation_console");
    if(token!==state.viewToken)return;
    const data=state.delegationConsole||{},rows=data.delegations||[],events=data.events||[],isAdmin=can("manage_emergency_delegations"),isPrincipal=can("acknowledge_emergency_delegations");
    const currentYear=activeYear()?.id||state.boot.academic_years?.[0]?.id||"",currentTerm=activeTerm()?.id||state.boot.terms?.[0]?.id||"";
    const now=new Date(),later=new Date(now.getTime()+7*24*60*60*1000);
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Emergency Academic Delegation</h3><p>Temporary, term-scoped report entry with Principal oversight and immutable audit history.</p></div><button class="button ghost" id="delegationRefresh">Refresh</button></div>
      <section class="license-banner warning"><div><strong>Continuity control</strong><span>Emergency access does not transfer submission, approval, or publication authority. The assigned class teacher still submits, and the Principal still approves.</span></div></section>
      ${isAdmin?`<section class="panel pad"><div class="panel-header"><div><h3>Create Temporary Delegation</h3><p>Use a replacement teacher first. Select System Administrator emergency entry only when no suitable teacher is available.</p></div></div>
        <form id="delegationForm" class="form-stack">
          <div class="form-grid three">
            <label class="field"><span>Delegation type</span><select name="delegation_type"><option value="replacement_teacher">Replacement teacher</option><option value="system_admin_override">System Administrator emergency entry</option></select></label>
            <label class="field"><span>Delegate account</span><select name="delegate_user_id" required></select></label>
            <label class="field"><span>Academic year</span><select name="academic_year_id" required>${optionList(state.boot.academic_years||[],"id","name",currentYear)}</select></label>
            <label class="field"><span>Term</span><select name="term_id" required></select></label>
            <label class="field"><span>Class</span><select name="class_id" required>${optionList(state.boot.classes||[],"id","name","","Select class")}</select></label>
            <label class="field"><span>Subject scope</span><select name="subject_id"><option value="">Select a class first</option></select></label>
            <label class="field"><span>Starts</span><input type="datetime-local" name="valid_from" value="${attr(dateTimeLocalValue(now.toISOString()))}" required></label>
            <label class="field"><span>Expires</span><input type="datetime-local" name="valid_until" value="${attr(dateTimeLocalValue(later.toISOString()))}" required></label>
            <div class="field delegation-capabilities"><span>Temporary capabilities</span><label class="check"><input type="checkbox" name="allow_score_entry" checked> Enter assessment scores</label><label class="check"><input type="checkbox" name="allow_class_report_fields"> Edit class report details</label></div>
            <label class="field full"><span>Mandatory reason</span><textarea name="reason" minlength="10" required placeholder="State why the assigned teacher is unavailable and why temporary access is necessary."></textarea></label>
          </div>
          <div class="button-row"><button class="button primary" id="delegationCreate" type="button">Create temporary delegation</button></div>
        </form></section>`:""}
      <section class="panel"><div class="panel-header"><div><h3>Delegation Register</h3><p>${rows.length} recorded delegation${rows.length===1?"":"s"}</p></div></div>
        <div class="table-wrap"><table><thead><tr><th>Status</th><th>Delegate</th><th>Class and scope</th><th>Capabilities</th><th>Validity</th><th>Reason and oversight</th><th>Action</th></tr></thead><tbody>
          ${rows.length?rows.map(row=>`<tr><td>${delegationStatusHtml(row)}<small class="table-subtext">${esc(delegationTypeLabel(row.delegation_type))}</small></td>
            <td><strong>${esc(row.delegate_name||"Unknown")}</strong><small class="table-subtext">${esc(ROLE_LABELS[row.delegate_role]||row.delegate_role||"")}</small></td>
            <td><strong>${esc(row.class_name||"")}</strong><small class="table-subtext">${esc(row.subject_name||"All assigned subjects")} • ${esc(row.term_name||"")}</small></td>
            <td>${esc(delegationCapabilities(row))}<small class="table-subtext">Original: ${esc(row.original_teacher_name||"Unassigned")}</small></td>
            <td>${esc(isoDateTime(row.valid_from))}<small class="table-subtext">to ${esc(isoDateTime(row.valid_until))}</small></td>
            <td><span>${esc(row.reason||"")}</span><small class="table-subtext">${row.principal_acknowledged_at?`Acknowledged by ${esc(row.acknowledged_by_name||"Principal")} on ${esc(isoDateTime(row.principal_acknowledged_at))}`:"Principal acknowledgement pending"}</small></td>
            <td><div class="table-actions">${isAdmin&&row.status==="active"&&delegationComputedStatus(row)!=="expired"?`<button class="button danger small" data-delegation-revoke="${attr(row.id)}">Revoke</button>`:""}${isPrincipal&&!row.principal_acknowledged_at?`<button class="button primary small" data-delegation-ack="${attr(row.id)}">Acknowledge</button>`:""}</div></td></tr>`).join(""):`<tr><td colspan="7"><div class="empty"><strong>No emergency delegations recorded</strong></div></td></tr>`}
        </tbody></table></div></section>
      <section class="panel"><div class="panel-header"><div><h3>Immutable Delegation Activity</h3><p>Creation, acknowledgement, revocation, and delegated report changes</p></div></div>
        <div class="table-wrap"><table><thead><tr><th>Date</th><th>Event</th><th>Actor</th><th>Reason</th><th>Report</th></tr></thead><tbody>
          ${events.length?events.slice(0,100).map(event=>`<tr><td>${esc(isoDateTime(event.created_at))}</td><td>${esc(String(event.event_type||"").replaceAll("_"," "))}</td><td>${esc(event.actor_name||"System")}</td><td>${esc(event.event_reason||"—")}</td><td>${event.report_id?`<button class="button ghost small" data-delegation-report="${attr(event.report_id)}">Open report</button>`:"—"}</td></tr>`).join(""):`<tr><td colspan="5"><div class="empty">No delegation events</div></td></tr>`}
        </tbody></table></div></section>`;
    byId("delegationRefresh").onclick=()=>{state.delegationConsole=null;renderEmergencyDelegations(state.viewToken,true)};
    $$('[data-delegation-report]').forEach(button=>button.onclick=()=>openReportEditor(button.dataset.delegationReport));
    if(isAdmin){
      const form=byId("delegationForm"),type=form.elements.delegation_type,delegate=form.elements.delegate_user_id,year=form.elements.academic_year_id,term=form.elements.term_id,classSelect=form.elements.class_id,subject=form.elements.subject_id,fields=form.elements.allow_class_report_fields;
      const syncUsers=()=>{const selected=delegate.value;delegate.innerHTML=delegationUserOptions(data.eligible_users||[],type.value,selected);if(type.value==="system_admin_override"&&[...(delegate.options||[])].some(option=>option.value===state.boot.profile.id))delegate.value=state.boot.profile.id};
      const syncTerms=()=>{const available=(state.boot.terms||[]).filter(item=>!year.value||item.academic_year_id===year.value),selected=term.value||currentTerm;term.innerHTML=optionList(available,"id","name",selected,"Select term")};
      const syncSubjects=()=>{subject.innerHTML=delegationSubjectOptions(data,classSelect.value,subject.value);const specific=Boolean(subject.value);fields.disabled=specific;if(specific)fields.checked=false};
      type.onchange=syncUsers;year.onchange=syncTerms;classSelect.onchange=syncSubjects;subject.onchange=syncSubjects;syncUsers();syncTerms();syncSubjects();
      byId("delegationCreate").onclick=async()=>{
        if(!form.reportValidity())return;
        const values=formObject(form),button=byId("delegationCreate");button.disabled=true;
        try{
          state.delegationConsole=await rpc("create_emergency_academic_delegation",{payload:{...values,subject_id:values.subject_id||null,allow_score_entry:form.elements.allow_score_entry.checked,allow_class_report_fields:form.elements.allow_class_report_fields.checked,valid_from:new Date(values.valid_from).toISOString(),valid_until:new Date(values.valid_until).toISOString()}});
          state.boot=await rpc("get_bootstrap_data");state.workspace=null;state.myEmergencyDelegations=[];renderBrand();renderNav();toast("Emergency delegation created","The Principal and delegate have been notified.");await renderEmergencyDelegations(state.viewToken);
        }catch(error){toast("Delegation not created",friendlyError(error),"error",8000)}finally{button.disabled=false}
      };
      $$('[data-delegation-revoke]').forEach(button=>button.onclick=()=>{
        modal("Revoke Emergency Delegation","Temporary report-entry access will stop immediately.",`<label class="field"><span>Revocation reason</span><textarea id="delegationRevokeReason" minlength="5" required></textarea></label>`,`<button class="button ghost" id="delegationRevokeCancel" type="button">Cancel</button><button class="button danger" id="delegationRevokeConfirm" type="button">Revoke access</button>`,"small");
        byId("delegationRevokeCancel").onclick=closeModal;byId("delegationRevokeConfirm").onclick=async()=>{const reason=byId("delegationRevokeReason").value.trim();if(reason.length<5)return;const action=byId("delegationRevokeConfirm");action.disabled=true;try{state.delegationConsole=await rpc("revoke_emergency_academic_delegation",{target_delegation_id:button.dataset.delegationRevoke,reason_text:reason});state.boot=await rpc("get_bootstrap_data");state.workspace=null;state.myEmergencyDelegations=[];closeModal();renderBrand();renderNav();toast("Delegation revoked");await renderEmergencyDelegations(state.viewToken)}catch(error){toast("Delegation not revoked",friendlyError(error),"error")}finally{action.disabled=false}};
      });
    }
    if(isPrincipal)$$('[data-delegation-ack]').forEach(button=>button.onclick=()=>{
      modal("Acknowledge Emergency Delegation","Confirm that you have reviewed this temporary academic access.",`<label class="field"><span>Principal note</span><textarea id="delegationAckNote" placeholder="Optional oversight note"></textarea></label>`,`<button class="button ghost" id="delegationAckCancel" type="button">Cancel</button><button class="button primary" id="delegationAckConfirm" type="button">Acknowledge</button>`,"small");
      byId("delegationAckCancel").onclick=closeModal;byId("delegationAckConfirm").onclick=async()=>{const action=byId("delegationAckConfirm");action.disabled=true;try{state.delegationConsole=await rpc("acknowledge_emergency_academic_delegation",{target_delegation_id:button.dataset.delegationAck,note_text:byId("delegationAckNote").value.trim()});closeModal();toast("Delegation acknowledged");await renderEmergencyDelegations(state.viewToken)}catch(error){toast("Acknowledgement not saved",friendlyError(error),"error")}finally{action.disabled=false}};
    });
  }

  async function renderLicensing(token,force=false) {
    if(!can("manage_licenses"))throw new Error("Platform Super Administrator access required");
    if(force||!state.licenseConsole)state.licenseConsole=await rpc("get_platform_license_console");
    if(token!==state.viewToken)return;
    const data=state.licenseConsole||{},snapshot=data.snapshot||{},license=data.license||{},plan=snapshot.plan||{};
    const plans=data.plans||[],usage=data.usage||{},locks=data.active_locks||[],events=data.recent_events||[],verificationHistory=data.verification_history||[],licensingArchives=data.archives||[],admins=data.platform_admins||[],authorities=data.distribution_authorities||[],canManageDistributors=data.distribution_authority?.active===true&&data.distribution_authority?.can_revoke===true;
    const status=snapshot.computed_status||license.status||"unknown";
    byId("content").innerHTML=`
      <div class="page-head platform-page-head"><div><h3>Platform Licensing Control</h3><p>Manage the installation licence, compliance state, capacity, and access restrictions.</p></div><button class="button ghost" id="licenseRefresh">Refresh</button></div>
      ${platformSectionTabs("licensing")}
      <section class="platform-control-hero ${snapshot.access_mode==='locked'?'locked':snapshot.access_mode==='read_only'?'restricted':'active'}">
        <div><span>Current licence</span><h3>${esc(plan.name||"Unconfigured")}</h3><p>${esc(snapshot.license_reference||"No licence reference")}</p></div>
        <div><span>Status</span><strong>${esc(licenseStatusLabel(status))}</strong><small>${esc(snapshot.access_lock_status||"unlocked")}</small></div>
        <div><span>Issue date</span><strong>${esc(isoDate(snapshot.issued_on))}</strong><small>Activated ${esc(isoDateTime(snapshot.activated_at))}</small></div>
        <div><span>Expiry</span><strong>${snapshot.expires_at?esc(isoDateTime(snapshot.expires_at)):"No expiry"}</strong><small>${snapshot.days_remaining==null?"Perpetual or unset":`${number(snapshot.days_remaining)} days remaining`}</small></div>
      </section>
      ${snapshot.warning?`<section class="license-banner ${snapshot.access_mode==='read_only'||snapshot.access_mode==='locked'?'restricted':'warning'}"><div><strong>Licence attention</strong><span>${esc(snapshot.warning)}</span></div></section>`:""}
      <div class="grid two platform-license-grid">
        <section class="panel pad">
          <div class="section-title"><div><h4>Licence lifecycle</h4><p>Changes are effective immediately and recorded in immutable licensing history.</p></div></div>
          <form id="platformLicenseForm" class="form-grid">
            <label class="field"><span>Licence plan</span><select name="plan_id" required>${plans.map(item=>`<option value="${attr(item.id)}" ${item.id===license.plan_id?"selected":""}>${esc(item.name)}</option>`).join("")}</select></label>
            <label class="field"><span>Licence status</span><select name="status">${["pending_activation","active","grace_period","expired","suspended","revoked","perpetual"].map(item=>`<option value="${item}" ${item===license.status?"selected":""}>${esc(licenseStatusLabel(item))}</option>`).join("")}</select></label>
            <label class="field"><span>Issue date</span><input type="date" name="issued_on" value="${attr(license.issued_on||localDateValue())}" required></label>
            <label class="field"><span>Activation date and time</span><input type="datetime-local" name="activated_at" value="${attr(dateTimeLocalValue(license.activated_at))}"></label>
            <label class="field"><span>Expiry date and time</span><input type="datetime-local" name="expires_at" value="${attr(dateTimeLocalValue(license.expires_at))}"></label>
            <label class="field"><span>Grace-period end</span><input type="datetime-local" name="grace_ends_at" value="${attr(dateTimeLocalValue(license.grace_ends_at))}"></label>
            <label class="field full"><span>Licence reference</span><input name="license_reference" maxlength="100" value="${attr(license.license_reference||"")}" required></label>
            <label class="field full"><span>Compliance reason</span><input name="compliance_reason" maxlength="500" value="${attr(license.compliance_reason||"")}" placeholder="Required when suspended or revoked"></label>
            <label class="field full"><span>Internal notes</span><textarea name="notes">${esc(license.notes||"")}</textarea></label>
            <div class="full button-row"><button class="button primary" id="platformLicenseSave" type="button">Save licence</button></div>
          </form>
        </section>
        <section class="panel pad">
          <div class="section-title"><div><h4>Plan capacity and features</h4><p>${esc(plan.description||"")}</p></div></div>
          <div class="metric-row">
            ${licenceUsageMetric("Active students",usage.active_students,plan.max_students)}
            ${licenceUsageMetric("Active teachers",usage.active_teachers,plan.max_teachers)}
            ${licenceUsageMetric("System administrators",usage.active_system_admins,plan.max_system_admins)}
            ${licenceUsageMetric("Guardians",usage.active_guardians,plan.max_guardians)}
            ${licenceUsageMetric("Storage (MB)",usage.storage_mb,plan.max_storage_mb)}
            <div class="metric"><span>Published reports</span><strong>${number(usage.published_reports)}</strong><small>Historical total</small></div>
          </div>
          <div class="hr"></div>
          <div class="chip-list">${Object.entries(plan.feature_flags||{}).filter(([,enabled])=>enabled).map(([key])=>`<span class="chip">${esc(key.replaceAll("_"," "))}</span>`).join("")||'<span class="chip">No enabled features</span>'}</div>
          <div class="template-information" style="margin-top:18px"><strong>Capacity enforcement</strong><span>Student, teacher, guardian, System Administrator, and school Storage limits are enforced on the server. Existing records are never deleted when a limit or licence state changes.</span></div>
        </section>
        <section class="panel pad">
          <div class="section-title"><div><h4>Access lock control</h4><p>Use read-only mode before a complete denial unless a serious compliance or security condition requires full restriction.</p></div></div>
          <form id="platformLockForm" class="form-grid">
            <label class="field"><span>Lock scope</span><select name="scope"><option value="system_admin">System Administrator only</option><option value="school">All school users</option><option value="platform">Entire school platform</option></select></label>
            <label class="field"><span>Lock mode</span><select name="mode"><option value="read_only">Read-only</option><option value="deny">Deny access</option></select></label>
            <label class="field full"><span>Reason</span><textarea name="reason" required placeholder="State the contractual, security, or compliance reason"></textarea></label>
            <label class="field full"><span>Automatic end date and time (optional)</span><input type="datetime-local" name="ends_at"></label>
            <div class="full button-row"><button class="button danger" id="platformLockApply" type="button">Apply access lock</button></div>
          </form>
          <div class="hr"></div>
          <div class="section-title"><h4>Active locks</h4></div>
          ${locks.length?`<div class="record-list">${locks.map(item=>`<article class="license-lock-row"><div><strong>${esc(item.lock_scope.replaceAll("_"," "))} • ${esc(item.lock_mode.replaceAll("_"," "))}</strong><span>${esc(item.reason)}</span><small>Applied ${esc(isoDateTime(item.created_at))}${item.ends_at?` • Ends ${esc(isoDateTime(item.ends_at))}`:""}</small></div><button class="button outline small" data-release-license-lock="${attr(item.id)}">Release</button></article>`).join("")}</div>`:`<div class="empty"><strong>No active access locks</strong></div>`}
        </section>
        <section class="panel pad">
          <div class="section-title"><div><h4>Platform Super Administrators</h4><p>These accounts are isolated from school academic portals and must use multi-factor authentication.</p></div></div>
          ${admins.length?`<div class="record-list">${admins.map(item=>{const authority=authorities.find(entry=>entry.actor_id===item.id);return `<article class="license-admin-row"><div><strong>${esc(item.full_name||"Platform administrator")}</strong><span>${esc(item.email||"")}</span><small>${item.active?"Active":"Inactive"} • MFA ${item.mfa_required?"required":"not configured"} • Distributor ${authority?.active?"active":"not active"} • Last seen ${esc(isoDateTime(item.last_seen_at))}</small></div><button class="button outline small" data-distributor-edit="${attr(item.id)}" ${canManageDistributors?"":"disabled"}>Distributor access</button></article>`}).join("")}</div>`:`<div class="empty"><strong>No Platform Super Administrator profile found</strong></div>`}
          <div class="template-information"><strong>Account provisioning</strong><span>Create a separate Supabase Authentication user, then run PLATFORM_SUPER_ADMIN_SETUP.sql with that user’s email. School System Administrators cannot grant themselves this role.</span></div>
        </section>
      </div>
      <section class="panel" style="margin-top:18px">
        <div class="panel-header"><div><h3>Plan governance</h3><p>Versioned plan capacities, feature entitlements, and school-specific overrides</p></div></div>
        <div class="table-wrap"><table><thead><tr><th>Plan</th><th>Revision</th><th>Capacity</th><th>Features</th><th>Status</th><th>Action</th></tr></thead><tbody>${plans.map(item=>`<tr><td><strong>${esc(item.name)}</strong><small class="table-subtext">${esc(item.code)} • ${esc(item.billing_cycle)}</small></td><td>${number(item.revision||1)}</td><td>${item.max_students==null?"Unlimited":number(item.max_students)} students<br><small>${item.max_teachers==null?"Unlimited":number(item.max_teachers)} teachers • ${item.max_system_admins==null?"Unlimited":number(item.max_system_admins)} admins</small></td><td>${Object.values(item.feature_flags||{}).filter(Boolean).length} enabled</td><td>${item.active?"Active":"Inactive"}</td><td><button class="button outline small" data-license-plan-edit="${attr(item.id)}">Edit plan</button></td></tr>`).join("")}</tbody></table></div>
        <div class="button-row" style="padding:16px"><button class="button secondary" id="licensePlanCreate" type="button">Create plan</button><button class="button outline" id="licenseOverrideEdit" type="button">School entitlement override</button></div>
      </section>
      <section class="panel platform-history-panel">
        <div class="panel-header"><div><h3>Licence and compliance history</h3><p>Latest 200 platform events</p></div><div class="button-row"><button class="button danger small" id="licenseHistoryClear" type="button" ${(events.length||verificationHistory.length||licensingArchives.length)?"":"disabled"}>Clear all history</button></div></div>
        <div class="table-wrap platform-history-scroll"><table><thead><tr><th>Date</th><th>Event</th><th>Reason</th><th>Actor</th></tr></thead><tbody>${events.length?events.map(item=>`<tr><td>${esc(isoDateTime(item.created_at))}</td><td><strong>${esc(platformEventSummary(item))}</strong></td><td>${esc(item.event_reason||"—")}</td><td>${esc(item.actor_name||item.actor_id||"System")}</td></tr>`).join(""):`<tr><td colspan="4"><div class="empty">No licensing events recorded</div></td></tr>`}</tbody></table></div>
      </section>`;
    bindPlatformSectionTabs();
    byId("licenseRefresh").onclick=()=>{state.licenseConsole=null;renderLicensing(state.viewToken,true)};
    byId("platformLicenseSave").onclick=savePlatformLicense;
    byId("platformLockApply").onclick=applyPlatformAccessLock;
    byId("licenseHistoryClear")?.addEventListener("click",clearPlatformLicenseHistory);
    byId("licensePlanCreate")?.addEventListener("click",()=>editPlatformLicensePlan(""));
    byId("licenseOverrideEdit")?.addEventListener("click",editPlatformLicenseOverride);
    $$('[data-license-plan-edit]').forEach(button=>button.onclick=()=>editPlatformLicensePlan(button.dataset.licensePlanEdit));
    if(canManageDistributors)$$('[data-distributor-edit]').forEach(button=>button.onclick=()=>editDistributionAuthority(button.dataset.distributorEdit));
    $$('[data-release-license-lock]').forEach(button=>button.onclick=()=>releasePlatformAccessLock(button.dataset.releaseLicenseLock));
  }
  function editDistributionAuthority(actorId){
    const admin=(state.licenseConsole?.platform_admins||[]).find(item=>item.id===actorId)||{},current=(state.licenseConsole?.distribution_authorities||[]).find(item=>item.actor_id===actorId)||{};
    modal("Platform Distributor Authority",`Manage package-generation authority for ${admin.full_name||"this Platform Super Administrator"}. Enterprise School licensing alone never grants this capability.`,`<form id="distributionAuthorityForm" class="form-grid"><label class="check-row"><input name="active" type="checkbox" ${current.active?"checked":""}><span>Authority active</span></label><label class="check-row"><input name="can_generate" type="checkbox" ${current.can_generate!==false?"checked":""}><span>Can generate packages</span></label><label class="check-row"><input name="can_revoke" type="checkbox" ${current.can_revoke!==false?"checked":""}><span>Can revoke, restore, and delete packages</span></label><label class="field full"><span>Notes</span><textarea name="notes">${esc(current.notes||"")}</textarea></label></form>`,`<button class="button ghost" id="distributionAuthorityCancel" type="button">Cancel</button><button class="button primary" id="distributionAuthoritySave" type="button">Save authority</button>`,"small");
    byId("distributionAuthorityCancel").onclick=closeModal;byId("distributionAuthoritySave").onclick=async()=>{const form=byId("distributionAuthorityForm"),button=byId("distributionAuthoritySave");button.disabled=true;try{state.licenseConsole=await rpc("platform_set_distribution_authority",{target_actor_id:actorId,active_value:form.elements.active.checked,can_generate_value:form.elements.can_generate.checked,can_revoke_value:form.elements.can_revoke.checked,notes_text:form.elements.notes.value.trim()});closeModal();toast("Distributor authority updated");await renderLicensing(state.viewToken)}catch(error){toast("Authority not updated",friendlyError(error),"error",8000)}finally{button.disabled=false}};
  }

  function editPlatformLicensePlan(planId){
    const data=state.licenseConsole||{},plan=(data.plans||[]).find(item=>item.id===planId)||{feature_flags:{},billing_cycle:"annual",default_term_days:365,grace_days:30,support_level:"standard",active:true};
    modal(planId?"Edit Licence Plan":"Create Licence Plan","Every saved change creates an immutable plan revision.",`<form id="licensePlanForm" class="form-grid">
      <input type="hidden" name="id" value="${attr(plan.id||"")}"><label class="field"><span>Code</span><input name="code" value="${attr(plan.code||"")}" ${planId?"readonly":""} required></label><label class="field"><span>Name</span><input name="name" value="${attr(plan.name||"")}" required></label>
      <label class="field full"><span>Description</span><textarea name="description">${esc(plan.description||"")}</textarea></label><label class="field"><span>Billing cycle</span><select name="billing_cycle">${["monthly","annual","custom"].map(value=>`<option value="${value}" ${value===plan.billing_cycle?"selected":""}>${value}</option>`).join("")}</select></label><label class="field"><span>Support level</span><select name="support_level">${["standard","priority","enterprise","custom"].map(value=>`<option value="${value}" ${value===plan.support_level?"selected":""}>${value}</option>`).join("")}</select></label>
      <label class="field"><span>Max students</span><input name="max_students" type="number" min="1" value="${attr(plan.max_students??"")}" placeholder="Unlimited"></label><label class="field"><span>Max teachers</span><input name="max_teachers" type="number" min="1" value="${attr(plan.max_teachers??"")}" placeholder="Unlimited"></label><label class="field"><span>Max System Administrators</span><input name="max_system_admins" type="number" min="1" value="${attr(plan.max_system_admins??"")}" placeholder="Unlimited"></label><label class="field"><span>Max guardians</span><input name="max_guardians" type="number" min="1" value="${attr(plan.max_guardians??"")}" placeholder="Unlimited"></label><label class="field"><span>Max Storage (MB)</span><input name="max_storage_mb" type="number" min="1" value="${attr(plan.max_storage_mb??"")}" placeholder="Unlimited"></label><label class="field"><span>Default term days</span><input name="default_term_days" type="number" min="1" value="${attr(plan.default_term_days||365)}"></label><label class="field"><span>Grace days</span><input name="grace_days" type="number" min="0" max="365" value="${attr(plan.grace_days??30)}"></label>
      <label class="field full"><span>Feature flags JSON</span><textarea name="feature_flags" required>${esc(JSON.stringify(plan.feature_flags||{},null,2))}</textarea><small>Use only feature codes shown in the feature catalogue. Distribution authority cannot be added here.</small></label>
      <label class="check-row"><input name="perpetual_allowed" type="checkbox" ${plan.perpetual_allowed?"checked":""}><span>Allow perpetual licences</span></label><label class="check-row"><input name="active" type="checkbox" ${plan.active!==false?"checked":""}><span>Plan active</span></label><label class="field full"><span>Revision reason</span><input name="reason" minlength="5" required></label>
    </form>`,`<button class="button ghost" id="licensePlanCancel" type="button">Cancel</button><button class="button primary" id="licensePlanSave" type="button">Save plan revision</button>`);
    byId("licensePlanCancel").onclick=closeModal;byId("licensePlanSave").onclick=async()=>{const form=byId("licensePlanForm");if(!form.reportValidity())return;const values=formObject(form);let feature_flags;try{feature_flags=JSON.parse(values.feature_flags)}catch{toast("Plan not saved","Feature flags must be valid JSON.","error");return}const button=byId("licensePlanSave");button.disabled=true;try{state.licenseConsole=await rpc("platform_upsert_license_plan",{payload:{...values,feature_flags,perpetual_allowed:form.elements.perpetual_allowed.checked,active:form.elements.active.checked}});closeModal();toast("Plan revision saved");await renderLicensing(state.viewToken)}catch(error){toast("Plan not saved",friendlyError(error),"error",8000)}finally{button.disabled=false}};
  }
  function editPlatformLicenseOverride(){
    const current=state.licenseConsole?.active_override||{};
    modal("School Entitlement Override","Overrides apply only to this installation and are fully audited.",`<form id="licenseOverrideForm" class="form-grid"><label class="field"><span>Max students override</span><input name="max_students" type="number" min="1" value="${attr(current.max_students??"")}" placeholder="Use plan limit"></label><label class="field"><span>Max teachers override</span><input name="max_teachers" type="number" min="1" value="${attr(current.max_teachers??"")}" placeholder="Use plan limit"></label><label class="field"><span>Max System Administrators override</span><input name="max_system_admins" type="number" min="1" value="${attr(current.max_system_admins??"")}" placeholder="Use plan limit"></label><label class="field"><span>Max guardians override</span><input name="max_guardians" type="number" min="1" value="${attr(current.max_guardians??"")}" placeholder="Use plan limit"></label><label class="field"><span>Max Storage override (MB)</span><input name="max_storage_mb" type="number" min="1" value="${attr(current.max_storage_mb??"")}" placeholder="Use plan limit"></label><label class="field full"><span>Feature overrides JSON</span><textarea name="feature_overrides">${esc(JSON.stringify(current.feature_overrides||{},null,2))}</textarea></label><label class="field full"><span>Reason</span><input name="reason" minlength="5" required></label></form>`,`<button class="button ghost" id="licenseOverrideCancel" type="button">Cancel</button><button class="button primary" id="licenseOverrideSave" type="button">Apply override</button>`,"small");
    byId("licenseOverrideCancel").onclick=closeModal;byId("licenseOverrideSave").onclick=async()=>{const form=byId("licenseOverrideForm");if(!form.reportValidity())return;const values=formObject(form);let feature_overrides;try{feature_overrides=JSON.parse(values.feature_overrides||"{}") }catch{toast("Override not saved","Feature overrides must be valid JSON.","error");return}const button=byId("licenseOverrideSave");button.disabled=true;try{state.licenseConsole=await rpc("platform_set_license_override",{feature_overrides,max_students_value:values.max_students?Number(values.max_students):null,max_teachers_value:values.max_teachers?Number(values.max_teachers):null,max_system_admins_value:values.max_system_admins?Number(values.max_system_admins):null,max_guardians_value:values.max_guardians?Number(values.max_guardians):null,max_storage_mb_value:values.max_storage_mb?Number(values.max_storage_mb):null,reason_text:values.reason.trim()});closeModal();toast("Entitlement override applied");await renderLicensing(state.viewToken)}catch(error){toast("Override not saved",friendlyError(error),"error",8000)}finally{button.disabled=false}};
  }

  async function savePlatformLicense() {
    const form=byId("platformLicenseForm"),button=byId("platformLicenseSave");if(!form?.reportValidity())return;
    const values=formObject(form);button.disabled=true;button.textContent="Saving";
    try{
      const payload={target_plan_id:values.plan_id,target_status:values.status,issue_date:values.issued_on,
        activation_date:values.activated_at?new Date(values.activated_at).toISOString():null,
        expiry_date:values.expires_at?new Date(values.expires_at).toISOString():null,
        grace_end_date:values.grace_ends_at?new Date(values.grace_ends_at).toISOString():null,
        license_reference_text:values.license_reference.trim(),notes_text:values.notes.trim(),compliance_reason_text:values.compliance_reason.trim()};
      if(["suspended","revoked"].includes(values.status)&&payload.compliance_reason_text.length<5)throw new Error("Enter a clear compliance reason for a suspended or revoked licence.");
      state.licenseConsole=await rpc("platform_update_license",payload);state.boot=await rpc("get_bootstrap_data");renderBrand();toast("Platform licence updated");await renderLicensing(state.viewToken);
    }catch(error){toast("Licence not updated",friendlyError(error),"error",7500)}finally{button.disabled=false;button.textContent="Save licence"}
  }
  async function applyPlatformAccessLock() {
    const form=byId("platformLockForm"),button=byId("platformLockApply");if(!form?.reportValidity())return;
    const values=formObject(form);if(values.reason.trim().length<5){toast("Lock not applied","Enter a clear reason.","error");return}
    const ok=await confirmAction("Apply access lock",`Apply ${values.mode.replaceAll("_"," ")} access to ${values.scope.replaceAll("_"," ")}?`,"Apply lock",true);if(!ok)return;
    button.disabled=true;button.textContent="Applying";
    try{state.licenseConsole=await rpc("platform_set_access_lock",{lock_scope_text:values.scope,lock_mode_text:values.mode,reason_text:values.reason.trim(),ends_at_value:values.ends_at?new Date(values.ends_at).toISOString():null});toast("Access lock applied");await renderLicensing(state.viewToken)}
    catch(error){toast("Lock not applied",friendlyError(error),"error",7500)}finally{button.disabled=false;button.textContent="Apply access lock"}
  }
  async function releasePlatformAccessLock(lockId) {
    const ok=await confirmAction("Release access lock","School access will return to the level allowed by the current licence status.","Release lock");if(!ok)return;
    try{state.licenseConsole=await rpc("platform_release_access_lock",{target_lock_id:lockId,reason_text:"Access lock released through the Platform Licensing portal"});toast("Access lock released");await renderLicensing(state.viewToken)}
    catch(error){toast("Lock not released",friendlyError(error),"error",7500)}
  }
  function clearPlatformLicenseHistory(){
    modal("Clear Licence and Compliance History","This permanently removes the visible licence events, verification logs, and previous licensing archive checkpoints. Current licences, plans, users, and access settings are not changed.",`<div class="destructive-confirmation"><label class="field"><span>Reset reason</span><textarea id="licenseHistoryClearReason" minlength="5" required placeholder="Why are these history records being cleared?"></textarea></label><label class="field"><span>Type CLEAR ALL to confirm</span><input id="licenseHistoryClearText" autocomplete="off" required></label></div>`,`<button class="button ghost" id="licenseHistoryClearCancel" type="button">Cancel</button><button class="button danger" id="licenseHistoryClearConfirm" type="button">Clear all history</button>`,"small");
    byId("licenseHistoryClearCancel").onclick=closeModal;
    byId("licenseHistoryClearConfirm").onclick=async()=>{
      const reason=byId("licenseHistoryClearReason").value.trim(),confirmation=byId("licenseHistoryClearText").value.trim();
      if(reason.length<5||confirmation!=="CLEAR ALL"){toast("History not cleared","Enter a reason and type CLEAR ALL exactly.","error");return}
      const button=byId("licenseHistoryClearConfirm");button.disabled=true;button.textContent="Clearing";
      try{state.licenseConsole=await rpc("platform_clear_license_history",{reason_text:reason,confirmation_text:confirmation});closeModal();toast("Licence and compliance history cleared");await renderLicensing(state.viewToken)}
      catch(error){toast("History not cleared",friendlyError(error),"error",8000)}finally{button.disabled=false;button.textContent="Clear all history"}
    };
  }


  function terminalCorrectionHistoryCount(requests=[]){return requests.filter(item=>["rejected","cancelled","applied"].includes(String(item.status||""))).length}
  function terminalRecoveryHistoryCount(tests=[]){return tests.filter(item=>["passed","failed"].includes(String(item.status||""))).length}
  function terminalRestoreHistoryCount(jobs=[]){return jobs.filter(item=>["completed","failed","cancelled"].includes(String(item.status||""))).length}
  function safeFailedBackupHistoryCount(backups=[]){return backups.filter(item=>item.status==="failed"&&Number(item.storage_bytes||0)===0&&!String(item.storage_path||"")&&!String(item.manifest_path||"")&&!String(item.database_path||"")).length}
  async function clearSectionHistory(scope,title,description,refresh){
    modal(title,description,`<div class="destructive-confirmation"><label class="field"><span>Reset reason</span><textarea id="sectionHistoryClearReason" minlength="5" required placeholder="Why are these history records being cleared?"></textarea></label><label class="field"><span>Type CLEAR HISTORY to confirm</span><input id="sectionHistoryClearText" autocomplete="off" required></label></div>`,`<button class="button ghost" id="sectionHistoryClearCancel" type="button">Cancel</button><button class="button danger" id="sectionHistoryClearConfirm" type="button">Clear history</button>`,"small");
    byId("sectionHistoryClearCancel").onclick=closeModal;
    byId("sectionHistoryClearConfirm").onclick=async()=>{
      const reason=byId("sectionHistoryClearReason").value.trim(),confirmation=byId("sectionHistoryClearText").value.trim();
      if(reason.length<5||confirmation!=="CLEAR HISTORY"){toast("History not cleared","Enter a reason and type CLEAR HISTORY exactly.","error");return}
      const button=byId("sectionHistoryClearConfirm");button.disabled=true;button.textContent="Clearing";
      try{
        const result=await rpc("clear_section_history",{scope_text:scope,reason_text:reason,confirmation_text:confirmation});
        closeModal();
        const deleted=Object.entries(result||{}).filter(([key])=>key.endsWith("_deleted")).reduce((sum,[,value])=>sum+Number(value||0),0);
        toast("History cleared",`${number(deleted)} eligible history record${deleted===1?"":"s"} permanently removed. Protected operational records were preserved.`);
        if(refresh)await refresh();
      }catch(error){toast("History not cleared",friendlyError(error),"error",8500)}finally{button.disabled=false;button.textContent="Clear history"}
    };
  }

  async function renderBackupRestore(token) {
    let backupData=null,restoreData=null,backupLoadError="",restoreLoadError="";
    try{backupData=await rpc("backup_dashboard")}catch(error){backupLoadError=friendlyError(error)}
    try{restoreData=await rpc("school_restore_dashboard")}catch(error){restoreLoadError=friendlyError(error)}
    if(token!==state.viewToken)return;
    const host=byId("content");
    if(!host)throw new Error("The Backup & Restore content host is unavailable. Reload the application.");
    const loadWarnings=[backupLoadError?`<section class="license-banner warning"><div><strong>Backup history unavailable</strong><span>${esc(backupLoadError)}</span></div></section>`:"",restoreLoadError?`<section class="license-banner warning"><div><strong>Restore history unavailable</strong><span>${esc(restoreLoadError)}</span></div></section>`:""].join("");
    const cleanupEligible=safeFailedBackupHistoryCount(backupData?.backups||[])+terminalRestoreHistoryCount(restoreData?.jobs||[]);
    host.innerHTML=`<div class="page-head"><div><h3>Full School Backup and Restore</h3><p>Encrypted continuity packages for disaster recovery and migration to a compatible fresh installation.</p></div><div class="page-actions"><button class="button danger small" id="backupRestoreHistoryClear" type="button" ${cleanupEligible?"":"disabled"}>Clear history</button></div></div>
      ${loadWarnings}
      <section class="license-banner warning"><div><strong>High-impact administration area</strong><span>A restore replaces operational school records and protected files. Use MFA, make a current recovery backup first, and keep all users out of the system until verification completes.</span></div></section>
      <section class="panel pad backup-recovery-panel"><div class="section-title"><div><h4>Create and Download Full School Backup</h4><p>Includes academic records, users, reports, attendance, transcripts, certificates, templates, photographs and signatures. Password hashes and platform signing secrets are never exported.</p></div></div>
      <div class="button-row"><button class="button primary" id="fullSchoolBackupCreate" type="button">Create full encrypted backup</button></div>${backupHistoryHtml(backupData?.backups||[])}</section>
      <section class="panel pad"><div class="section-title"><div><h4>Restore a Downloaded School Backup</h4><p>Upload a ZIP package previously downloaded from this school. The server verifies encryption, checksums, school identity and schema compatibility before changing data.</p></div></div>
      <div class="template-information"><strong>Required sequence</strong><span>Install and license the compatible fresh system, sign in as System Administrator with MFA, create a recovery point, upload the backup, type RESTORE SCHOOL, then keep the browser open until final verification succeeds.</span></div>
      <form id="schoolRestoreForm" class="form-grid compact"><label class="field full"><span>Encrypted school backup ZIP</span><input type="file" name="backup_file" accept=".zip,application/zip,application/x-zip-compressed,application/x-zip,multipart/x-zip" required></label><label class="field full"><span>Typed confirmation</span><input name="confirmation" autocomplete="off" placeholder="RESTORE SCHOOL" required></label><label class="field full"><span>Reason</span><textarea name="reason" minlength="10" placeholder="State why this full restoration is required" required></textarea></label><div class="full button-row"><button class="button danger" id="schoolRestoreStart" type="button">Validate and restore school data</button></div></form>
      ${restoreHistoryHtml(restoreData?.jobs||[])}</section>`;
    byId("fullSchoolBackupCreate")?.addEventListener("click",createManualBackup);
    byId("schoolRestoreStart")?.addEventListener("click",startSchoolRestoreImport);
    byId("backupRestoreHistoryClear")?.addEventListener("click",()=>clearSectionHistory("backup_restore","Clear Backup & Restore History","This permanently removes completed/failed/cancelled restore-attempt records and failed backup records whose encrypted payload has already been cleaned. Completed or verified backup packages are never deleted by this action.",refreshBackupInterface));
    bindBackupHistoryControls();
  }
  function restoreHistoryHtml(jobs=[]){if(!jobs.length)return `<div class="empty"><strong>No restoration has been attempted</strong><span>Verified restore events will appear here.</span></div>`;return `<div class="table-wrap history-scroll restore-history-scroll"><table><thead><tr><th>Created</th><th>Package</th><th>Status</th><th>Source</th><th>Result</th></tr></thead><tbody>${jobs.map(j=>`<tr><td>${isoDateTime(j.created_at)}</td><td><strong>${esc(j.source_filename||"-")}</strong><br><small>${readableBytes(j.package_size||0)}</small></td><td><span class="chip ${j.status==="completed"?"success":j.status==="failed"?"danger":"warning"}">${esc(statusText(j.status))}</span></td><td>${esc(j.source_school_name||"Pending validation")}<br><small>${esc(j.source_schema_version||"")}</small></td><td>${j.error_message?`<small>${esc(j.error_message)}</small>`:esc(j.verification_notes||"")}</td></tr>`).join("")}</tbody></table></div>`}
  async function sha256File(file){const hash=await crypto.subtle.digest("SHA-256",await file.arrayBuffer());return [...new Uint8Array(hash)].map(b=>b.toString(16).padStart(2,"0")).join("")}
  async function requireAal2ForRestore(){
    const {data,error}=await state.client.auth.mfa.getAuthenticatorAssuranceLevel();
    if(error)throw error;
    if(data?.currentLevel!=="aal2")throw new Error("Multi-factor authentication required for full school restoration. Sign out, sign in again, and complete the authenticator-code step before restoring data.");
  }
  async function waitForRestore(jobId,timeoutMs=900000){const start=Date.now();while(Date.now()-start<timeoutMs){const {data,error}=await state.client.from("school_restore_jobs").select("*").eq("id",jobId).single();if(error)throw error;if(data.status==="completed")return data;if(data.status==="failed"||data.status==="cancelled")throw new Error(data.error_message||"School restoration did not complete.");await new Promise(r=>setTimeout(r,4000))}throw new Error("The restore is still running. Keep the system in maintenance mode and refresh Backup & Restore shortly.")}
  async function startSchoolRestoreImport(){
    const form=byId("schoolRestoreForm"),file=form?.elements?.backup_file?.files?.[0],confirmation=String(form?.elements?.confirmation?.value||"").trim(),reason=String(form?.elements?.reason?.value||"").trim(),button=byId("schoolRestoreStart");
    if(!file){toast("Backup required","Choose the downloaded encrypted backup ZIP.","error");return}
    if(confirmation!=="RESTORE SCHOOL"){toast("Confirmation does not match","Type RESTORE SCHOOL exactly.","error");return}
    if(reason.length<10){toast("Reason required","Enter at least 10 characters.","error");return}
    if(!await confirmAction("Restore all school data",`This will replace operational school records and protected files using ${file.name}. A pre-restore recovery backup will be created first. Do not continue while other users are active.`,"Begin restoration",true))return;
    if(!button)return;
    button.disabled=true;setSync("pending","Preparing restore");
    let preparedJobId="",restoreSubmitted=false;
    try{
      await requireAal2ForRestore();
      if(!/\.zip$/i.test(file.name)||Number(file.size||0)<=0||file.size>500*1024*1024)throw new Error("Choose a valid encrypted backup ZIP no larger than 500 MB.");
      const checksum=await sha256File(file);
      const prep=await invokeEdgeFunction("scheduled-backup",{action:"prepare_restore_import",file_name:file.name,file_size:file.size,checksum,reason});
      if(!prep?.path||!prep?.token||!prep?.job_id)throw new Error("Restore upload authorization was not returned.");
      preparedJobId=prep.job_id;
      // r26 restore ZIP MIME normalization contract: browsers on Windows may label ZIPs
      // application/x-zip-compressed. Upload the identical bytes with canonical application/zip.
      const uploadFile=String(file.type||"").toLowerCase()==="application/zip"?file:new File([file],file.name,{type:"application/zip",lastModified:file.lastModified});
      await uploadSignedStorageObject(state.client,CONFIG.backupBucket,prep.path,prep.token,uploadFile,"application/zip");
      setSync("pending","Restoring school data");
      restoreSubmitted=true;
      await invokeEdgeFunction("scheduled-backup",{action:"execute_restore_import",job_id:prep.job_id,confirmation,reason});
      const completed=await waitForRestore(prep.job_id);
      toast("School restoration completed",completed.verification_notes||"Data and protected files were restored and verified.","success",10000);setSync("online","Synced");
      await renderBackupRestore(state.viewToken);
    }catch(error){
      if(preparedJobId&&!restoreSubmitted)await invokeEdgeFunction("scheduled-backup",{action:"cancel_restore_import",job_id:preparedJobId}).catch(()=>null);
      toast("School restoration unsuccessful",friendlyError(error),"error",12000);setSync("pending","Attention required")
    }
    finally{button.disabled=false}
  }

  const SCHOOL_LOGO_MAX_BYTES=5*1024*1024,SCHOOL_LOGO_OUTPUT_SIZE=1024,SCHOOL_LOGO_ALLOWED_TYPES=Object.freeze(["image/png","image/jpeg","image/webp"]);
  async function normaliseOfficialSchoolLogo(file){
    if(!file)throw new Error("Select a school logo first.");
    if(!SCHOOL_LOGO_ALLOWED_TYPES.includes(String(file.type||"").toLowerCase()))throw new Error("School logo must be a PNG, JPEG, or WebP image.");
    if(Number(file.size||0)<=0||file.size>SCHOOL_LOGO_MAX_BYTES)throw new Error("School logo must be 5 MB or smaller.");
    const objectUrl=URL.createObjectURL(file);let image;
    try{image=await loadImage(objectUrl)}finally{URL.revokeObjectURL(objectUrl)}
    if(!image?.width||!image?.height)throw new Error("The selected school logo could not be decoded.");
    if(image.width<512||image.height<512)throw new Error("For clear report printing, upload a logo of at least 512 × 512 pixels.");
    const canvas=document.createElement("canvas");canvas.width=SCHOOL_LOGO_OUTPUT_SIZE;canvas.height=SCHOOL_LOGO_OUTPUT_SIZE;const ctx=canvas.getContext("2d");if(!ctx)throw new Error("The browser could not prepare the school logo.");
    ctx.clearRect(0,0,canvas.width,canvas.height);ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality="high";drawImageContain(ctx,image,24,24,canvas.width-48,canvas.height-48);
    const blob=await new Promise((resolve,reject)=>canvas.toBlob(value=>value?resolve(value):reject(new Error("The school logo could not be encoded.")),"image/png"));canvas.width=1;canvas.height=1;
    if(blob.size>SCHOOL_LOGO_MAX_BYTES)throw new Error("The normalized school logo exceeds 5 MB. Use a simpler PNG, JPEG, or WebP source image.");
    return blob;
  }
  async function previewSchoolLogoSelection(){
    const file=byId("schoolLogoFile")?.files?.[0],preview=byId("schoolLogoSettingsPreview");if(!file||!preview)return;
    try{const blob=await normaliseOfficialSchoolLogo(file);const url=URL.createObjectURL(blob);if(state.schoolLogoPreviewUrl)URL.revokeObjectURL(state.schoolLogoPreviewUrl);state.schoolLogoPreviewUrl=url;preview.src=url}
    catch(error){byId("schoolLogoFile").value="";preview.src=schoolDisplayLogo();toast("Logo not accepted",friendlyError(error),"error",8000)}
  }
  async function listPublishedReportIdsForOfficialLogoRefresh(){
    const ids=[];let page=1,total=0;const pageSize=100;
    do{
      const data=await rpc("list_report_cards_v6",{target_term_id:null,target_class_id:null,target_status:"published",search_text:"",archive_filter:"active",page_number:page,page_size:pageSize});
      const rows=Array.isArray(data?.rows)?data.rows:[];total=Number(data?.total||0);
      rows.forEach(row=>{if(row?.id&&row.status==="published"&&!row.archived)ids.push(row.id)});
      if(!rows.length)break;
      page+=1;
      if(page>Math.ceil(Math.max(total,1)/pageSize)+2)throw new Error("Published report enumeration did not complete safely. Refresh the page and try again.");
    }while(ids.length<total);
    return [...new Set(ids)];
  }

  async function refreshPublishedReportPdfsForOfficialLogo(){
    if(role()!=="system_admin")return toast("PDF refresh unavailable","Only the School System Administrator can refresh published report PDFs after a logo change.","error");
    if(!licenseCanWrite())return toast("PDF refresh unavailable","The current licence is read-only. Renew or reactivate the licence before refreshing official PDFs.","error");
    if(!can("publish_reports"))return toast("PDF refresh unavailable","Your account does not have permission to refresh official report PDFs.","error");
    const button=byId("schoolLogoRefreshReports");if(button)button.disabled=true;
    try{
      const ids=await listPublishedReportIdsForOfficialLogoRefresh();
      if(!ids.length){toast("No published PDFs to refresh","There are no active published report cards in this school.","success");return}
      if(!await confirmAction("Refresh published report PDFs",`${ids.length} published report card${ids.length===1?"":"s"} will be regenerated with the current official school logo and canonical Student Terminal Report header. Scores, comments, report numbers, publication records and verification tokens are not changed. Existing PDFs are replaced only after each new PDF is successfully registered.`,`Refresh ${ids.length} PDF${ids.length===1?"":"s"}`))return;
      modal("Refreshing Published Report PDFs","Applying the current official logo and canonical report header without changing academic records.",`<div class="template-information"><strong id="logoPdfRefreshHeading">Preparing published reports</strong><span id="logoPdfRefreshProgress">0 of ${ids.length} completed</span></div>`,`<button class="button ghost" type="button" disabled>Please wait</button>`,"small");
      let updated=0,failed=0;
      for(let index=0;index<ids.length;index++){
        const reportId=ids[index];
        try{
          const editor=await rpc("get_report_editor",{target_report_id:reportId,target_enrollment_id:null,target_term_id:null});
          await enrichReportGradingGuide(editor);
          const publication=(editor.publications||[]).find(item=>!item.revoked_at);
          if(!publication)throw new Error("Active publication record not found");
          await createAndStoreOfficialPdf(editor,publication);updated+=1;
        }catch(error){failed+=1;await reportClientError(error,{source:"official_logo_published_pdf_refresh",report_id:reportId})}
        const progress=byId("logoPdfRefreshProgress");
        if(progress)progress.textContent=`${index+1} of ${ids.length} completed • ${updated} refreshed${failed?` • ${failed} failed`:""}`;
        if((index+1)%5===0)await sleep(20);
      }
      state.pdfUrls.clear();closeModal();
      toast(failed?"Published PDFs refreshed with warnings":"Published PDFs refreshed",`${updated} official PDF${updated===1?"":"s"} now use the current school logo and canonical header${failed?` • ${failed} could not be regenerated and remain unchanged`:""}.`,failed?"warning":"success",10000);
    }catch(error){closeModal();toast("Published PDFs not refreshed",friendlyError(error),"error",10000);await reportClientError(error,{source:"official_logo_published_pdf_refresh",stage:"enumerate_or_refresh"})}
    finally{if(button)button.disabled=false}
  }

  async function saveOfficialSchoolLogo(){
    if(role()!=="system_admin")return toast("Logo not changed","Only the School System Administrator can change the official school logo.","error");
    if(!licenseCanWrite())return toast("Logo not changed","The current licence is read-only. Renew or reactivate the licence before changing the official logo.","error");
    const input=byId("schoolLogoFile"),file=input?.files?.[0],button=byId("schoolLogoSave");if(!file)return toast("Select a logo","Choose a PNG, JPEG, or WebP school logo first.","warning");button.disabled=true;
    let path="";
    try{
      const blob=await normaliseOfficialSchoolLogo(file),schoolId=String(state.boot?.school?.id||"").trim();if(!schoolId)throw new Error("School identity is unavailable. Refresh Settings and try again.");
      path=`official/${schoolId}/logo-${Date.now()}-${crypto.randomUUID().slice(0,8)}.png`;
      const {error:uploadError}=await state.client.storage.from(CONFIG.brandingBucket).upload(path,blob,{contentType:"image/png",upsert:false,cacheControl:"31536000"});if(uploadError)throw uploadError;
      const result=await rpc("set_school_logo_reference",{target_logo_url:`${CONFIG.brandingBucket}:${path}`});
      state.boot=await rpc("get_bootstrap_data");renderBrand();if(input)input.value="";if(state.schoolLogoPreviewUrl){URL.revokeObjectURL(state.schoolLogoPreviewUrl);state.schoolLogoPreviewUrl=""}const preview=byId("schoolLogoSettingsPreview");if(preview)preview.src=schoolDisplayLogo(state.boot.school);
      toast("Official school logo saved",result?.message||"The new print-clear logo is active for new official documents. Use Refresh published report PDFs below to update previously published report files without changing academic records.","success",10000);
    }catch(error){if(path)await state.client.storage.from(CONFIG.brandingBucket).remove([path]).catch(()=>{});toast("Logo not saved",friendlyError(error),"error",9000)}finally{button.disabled=false}
  }
  async function restorePackageSchoolLogo(){
    if(role()!=="system_admin"||!licenseCanWrite())return;
    if(!await confirmAction("Restore package logo","Use the original school logo embedded in this licensed package for future official documents? Previous uploaded logo files are retained so historical snapshots remain reproducible.","Restore logo"))return;
    const button=byId("schoolLogoReset");button.disabled=true;try{await rpc("set_school_logo_reference",{target_logo_url:CONFIG.logoPath||"assets/school-logo.png"});state.boot=await rpc("get_bootstrap_data");renderBrand();const preview=byId("schoolLogoSettingsPreview");if(preview)preview.src=schoolDisplayLogo(state.boot.school);toast("Package logo restored","Future official documents use the original package logo. Refresh published report PDFs if previously published files should also use it.")}catch(error){toast("Logo not restored",friendlyError(error),"error",8000)}finally{button.disabled=false}
  }

  async function renderSettings(token) {
    const school=state.boot.school||{};
    const brandingEnabled=licenseFeatureEnabled("custom_branding");
    const brandingDisabled=!can("manage_users")||!brandingEnabled;
    const logoManageDisabled=role()!=="system_admin"||!licenseCanWrite();
    let health=null,readiness=null,backupData=null,templates=[],templateLoadError="";
    try{templates=await loadReportCardTemplates(true)}catch(error){templateLoadError=friendlyError(error)}
    try{health=await rpc("system_health")}catch(_){}
    if(can("run_backup")){try{backupData=await rpc("backup_dashboard")}catch(_){}}
    if(can("manage_academics")||can("manage_users")){try{readiness=await rpc("validate_operational_readiness")}catch(_){}}
    if(token!==state.viewToken)return;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>System Settings</h3><p>School identity, security, health, and continuity</p></div></div>
      <div class="grid two">
        <section class="panel pad">
          <div class="section-title"><h4>School Identity</h4></div>
          <form id="schoolForm" class="form-grid">
            <label class="field full"><span>School name</span><input name="school_name" value="${attr(schoolDisplayName(school))}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field full"><span>Motto</span><input name="motto" value="${attr(school.motto||"")}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field full"><span>Address</span><input name="address" value="${attr(school.address||"")}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field"><span>Telephone</span><input name="phone" value="${attr(school.phone||"")}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field"><span>Email</span><input type="email" name="email" value="${attr(school.email||"")}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field"><span>Website</span><input name="website" value="${attr(school.website||"")}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field"><span>Principal</span><input name="head_name" value="${attr(school.head_name||"")}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field"><span>Report number prefix</span><input name="report_number_prefix" value="${attr(schoolReportPrefix(school))}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field"><span>User email domain</span><input name="user_email_domain" value="${attr(schoolEmailDomain(school))}" placeholder="school.edu.gh" ${CONFIG.tenantCode?"readonly":!can("manage_users")?"disabled":""}><small>${CONFIG.tenantCode?"Assigned permanently from the tenant code.":"Used for automatically generated user account email addresses."}</small></label>
            <label class="field"><span>Time zone</span><input name="timezone" value="${attr(school.timezone||"Africa/Accra")}" ${!can("manage_users")?"disabled":""}></label>
            <label class="field full"><span>Verification base URL</span><input name="verification_base_url" value="${attr(school.verification_base_url||"")}" ${!can("manage_users")?"disabled":""}></label>
            <div class="field full school-logo-settings">
              <span>Official school logo</span>
              <div class="school-logo-settings-grid"><div class="school-logo-settings-preview"><img id="schoolLogoSettingsPreview" src="${attr(schoolDisplayLogo(school))}" alt="${attr(schoolDisplayName(school))} official logo"></div><div class="school-logo-settings-actions"><strong>Used automatically on official school documents</strong><small>Report Cards, manual report-card templates, School Prospectuses, Certificates, Student ID Cards and Staff ID Cards use this logo. Report-card template artwork cannot override the canonical school header. Uploads are normalized to a print-clear 1024 × 1024 PNG.</small><input id="schoolLogoFile" type="file" accept="image/png,image/jpeg,image/webp" ${logoManageDisabled?"disabled":""}><div class="button-row"><button class="button secondary small" id="schoolLogoSave" type="button" ${logoManageDisabled?"disabled":""}>Upload / Change logo</button><button class="button ghost small" id="schoolLogoReset" type="button" ${logoManageDisabled?"disabled":""}>Restore package logo</button><button class="button outline small" id="schoolLogoRefreshReports" type="button" ${logoManageDisabled?"disabled":""}>Refresh published report PDFs</button></div><small>All licensed Starter, Professional and Enterprise school systems can manage the official logo. Recommended source: square image, at least 512 × 512 pixels, maximum 5 MB. Refreshing published PDFs replaces only the stored PDF file after successful regeneration; scores, comments, report numbers, publication status and verification tokens remain unchanged.</small></div></div>
            </div>
            <label class="field"><span>Primary colour</span><input type="color" name="primary_colour" value="${attr(school.primary_colour||"#082d70")}" ${brandingDisabled?"disabled":""}></label>
            <label class="field"><span>Accent colour</span><input type="color" name="accent_colour" value="${attr(school.accent_colour||"#f0b51d")}" ${brandingDisabled?"disabled":""}></label>
            <label class="field"><span>Report body font</span><select name="report_body_font" ${brandingDisabled?"disabled":""}>${reportFontOptionsHtml(school.report_body_font||"Times New Roman")}</select></label>
            <label class="field"><span>Report body font size</span><input type="number" name="report_body_font_size" min="8" max="16" step="0.5" value="${attr(school.report_body_font_size??11)}" ${brandingDisabled?"disabled":""}><small>Applied to generated report data and embedded in the downloaded PDF. Default: 11 pt.</small></label>
            ${can("manage_users")&&!brandingEnabled?`<div class="full"><p class="help-text">Colours and report typography are locked because Custom Branding is not included in the current licence. The official school logo remains available on every licensed plan. School identity and contact details remain editable.</p></div>`:""}
            ${can("manage_users")?`<div class="full"><button class="button primary" id="schoolSave" type="button">Save identity and report appearance</button></div>`:""}
          </form>
        </section>
        <div class="grid">
          <section class="panel pad"><div class="section-title"><h4>Account Security</h4></div>
            <div class="metric-row"><div class="metric"><span>Role</span><strong>${esc(ROLE_LABELS[role()]||role())}</strong></div>
              <div class="metric"><span>MFA policy</span><strong>${state.boot.profile.mfa_required?"Required":"Optional"}</strong></div></div>
            <div class="button-row" style="margin-top:15px"><button class="button secondary" id="mfaManage">Manage authentication</button></div>
          </section>
          <section class="panel pad"><div class="section-title"><h4>System Health</h4><button class="button ghost small" id="healthRefresh">Refresh</button></div>
            ${health?`<div class="metric-row">
              <div class="metric"><span>Active users</span><strong>${number(health.active_users)}</strong></div>
              <div class="metric"><span>Active teachers</span><strong>${number(health.active_teachers)}</strong></div>
              <div class="metric"><span>Active students</span><strong>${number(health.active_students)}</strong></div>
              <div class="metric"><span>Pending messages</span><strong>${number(health.pending_notifications)}</strong></div>
              <div class="metric"><span>Errors, 24h</span><strong>${number(health.client_errors_24h)}</strong></div>
            </div><div class="hr"></div>
            <div class="diff-row"><span>Latest full backup</span><b>${isoDateTime(health.latest_backup)}</b></div>
            <div class="diff-row"><span>Latest verified backup</span><b>${isoDateTime(health.latest_verified_backup)}</b></div>
            <div class="diff-row"><span>Latest off-site copy</span><b>${isoDateTime(health.latest_offsite_copy)}</b></div>
            <div class="diff-row"><span>Failed backups, 30 days</span><b>${number(health.failed_backups_30d)}</b></div>
            <div class="diff-row"><span>Completed backups awaiting verification</span><b>${number(health.unverified_completed_backups)}</b></div>
            <div class="diff-row"><span>Published reports without PDF</span><b>${number(health.published_without_pdf)}</b></div>
            <div class="diff-row"><span>Incomplete assessment schemes</span><b>${number((health.incomplete_schemes||[]).length)}</b></div>
            ${readiness?`<div class="diff-row"><span>Record save services</span><b>${readiness.ready?"Operational":"Attention required"}</b></div><div class="diff-row"><span>Data security</span><b>${Object.values(readiness.rls||{}).every(Boolean)?"Protected":"Attention required"}</b></div><div class="diff-row"><span>Data integrity</span><b>${Object.values(readiness.integrity||{}).every(value=>Number(value)===0)?"Healthy":"Attention required"}</b></div><div class="diff-row"><span>Role portals</span><b>${Object.values(readiness.roles||{}).every(Boolean)?"Ready":"Attention required"}</b></div>`:""}`:`<p class="help-text">Health details are not available for this role.</p>`}
          </section>
          ${can("run_backup")?`<section class="panel pad backup-recovery-panel"><div class="section-title"><div><h4>Backup and Recovery</h4><p>Encrypted database, authentication metadata, report files, student photographs, signatures and uploaded templates.</p></div></div>
            <form id="backupPolicyForm" class="form-grid compact">
              <label class="field"><span>Retention days</span><input type="number" name="retention_days" min="7" max="365" value="${attr(backupData?.retention_days??school.backup_retention_days??30)}"></label>
              <label class="field"><span>Minimum retained copies</span><input type="number" name="minimum_copies" min="2" max="90" value="${attr(backupData?.minimum_copies??school.backup_minimum_copies??7)}"></label>
              <div class="full button-row"><button class="button secondary" id="backupPolicySave" type="button">Save retention policy</button><button class="button primary" id="backupCreate" type="button">Create full encrypted backup</button></div>
            </form>
            <div class="template-information"><strong>Continuity rule</strong><span>Daily encrypted backups are retained under this policy. A weekly integrity rehearsal decrypts, decompresses, parses and checksum-verifies the latest backup. Download an encrypted package regularly and keep it outside Supabase.</span></div>
            ${backupHistoryHtml(backupData?.backups||[])}
          </section>`:""}
          ${can("manage_academics")?`<section class="panel pad"><div class="section-title"><h4>Scheduled Operations</h4></div>
            <div class="button-row"><button class="button secondary" id="notifyIncomplete">Queue incomplete-report alerts</button></div></section>`:""}
        </div>
      </div>
      <section class="panel pad report-template-admin">
        <div class="section-title"><div><h4>Report Card Templates by Class Range</h4><p>Upload one A4 portrait PDF or DOCX design for each fixed class range. The system automatically places the current official school header, student data, photograph, scores, comments, signature and verification details on the assigned design.</p></div></div>
        <div class="template-information"><strong>Protected dynamic header</strong><span>Uploaded designs should follow the approved A4 report-card field positions, but any logo or school identity embedded in the template header is cleared during generation and replaced with the current official logo, school name, motto, address, contact details and Student Terminal Report subtitle. The same rule applies to manual report-card templates.</span></div>
        ${reportTemplateCardsHtml(templates,templateLoadError)}
      </section>`;
    byId("schoolSave")?.addEventListener("click",saveSchoolSettings);
    byId("schoolLogoFile")?.addEventListener("change",previewSchoolLogoSelection);
    byId("schoolLogoSave")?.addEventListener("click",saveOfficialSchoolLogo);
    byId("schoolLogoReset")?.addEventListener("click",restorePackageSchoolLogo);
    byId("schoolLogoRefreshReports")?.addEventListener("click",refreshPublishedReportPdfsForOfficialLogo);
    byId("mfaManage").onclick=openMfaManager;
    byId("healthRefresh")?.addEventListener("click",()=>renderSettings(state.viewToken,true));
    byId("backupCreate")?.addEventListener("click",createManualBackup);
    byId("backupPolicySave")?.addEventListener("click",saveBackupPolicy);
    bindBackupHistoryControls();
    byId("notifyIncomplete")?.addEventListener("click",queueIncompleteNotifications);
    bindReportTemplateAdmin();
  }
  async function saveSchoolSettings() {
    const form=byId("schoolForm"),values=formObject(form),button=byId("schoolSave");button.disabled=true;
    try{
      if(licenseFeatureEnabled("custom_branding")){
        if(!Object.prototype.hasOwnProperty.call(REPORT_FONT_OPTIONS,values.report_body_font))throw new Error("Choose a supported report body font.");
        const reportFontSize=Number(values.report_body_font_size);
        if(!Number.isFinite(reportFontSize)||reportFontSize<8||reportFontSize>16)throw new Error("Report body font size must be between 8 and 16 points.");
        values.report_body_font_size=Math.round(reportFontSize*2)/2;
      }else{
        delete values.primary_colour;delete values.accent_colour;delete values.report_body_font;delete values.report_body_font_size;
      }
      values.user_email_domain=tenantLoginDomain()||String(values.user_email_domain||"").trim().toLowerCase();
      if(!/^(?:[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.)+[a-z]{2,63}$/i.test(values.user_email_domain))throw new Error("Enter a valid user email domain, for example school.edu.gh.");
      values.report_number_prefix=String(values.report_number_prefix||"").trim().toUpperCase().replace(/[^A-Z0-9]/g,"").slice(0,12);
      if(values.report_number_prefix.length<2)throw new Error("Report number prefix must contain at least two letters or numbers.");
      await query(state.client.from("school_settings").update(values).eq("id",state.boot.school.id));
      state.boot=await rpc("get_bootstrap_data");renderBrand();toast("School identity and report appearance saved");
    }catch(error){toast("Settings not saved",friendlyError(error),"error")}finally{button.disabled=false}
  }
  async function openMfaManager() {
    const {data,error}=await state.client.auth.mfa.listFactors();if(error){toast("Security details unavailable",friendlyError(error),"error");return}
    const factors=data.totp||[];
    modal("Multi-factor Authentication","",`
      <div class="section-title"><h4>Authenticator Factors</h4></div>
      ${factors.length?factors.map(f=>`<div class="diff-row"><span><strong>${esc(f.friendly_name||"Authenticator")}</strong><br><small>${esc(f.status)}</small></span>
        <button class="button danger small" data-mfa-remove="${attr(f.id)}">Remove</button></div>`).join(""):`<div class="empty"><strong>No authenticator factor</strong></div>`}`,
      `<button class="button ghost" id="mfaManagerClose" type="button">Close</button><button class="button primary" id="mfaManagerAdd" type="button">Add authenticator</button>`,"small");
    byId("mfaManagerClose").onclick=closeModal;
    byId("mfaManagerAdd").onclick=enrollMfaFromSettings;
    $$("[data-mfa-remove]").forEach(button=>button.onclick=async()=>{
      if(!await confirmAction("Remove Authenticator","This authentication factor will be removed.","Remove",true))return;
      const {error}=await state.client.auth.mfa.unenroll({factorId:button.dataset.mfaRemove});
      if(error)toast("Authenticator not removed",friendlyError(error),"error");else{closeModal();toast("Authenticator removed")}
    });
  }
  async function enrollMfaFromSettings() {
    const {data,error}=await state.client.auth.mfa.enroll({factorType:"totp",friendlyName:schoolDisplayName()});
    if(error){toast("Authenticator not added",friendlyError(error),"error");return}
    modal("Add Authenticator","",`<div class="mfa-qr"><img src="${attr(data.totp.qr_code)}" alt="Authentication QR code"></div>
      <label class="field"><span>Authentication code</span><input id="settingsMfaCode" inputmode="numeric" autocomplete="one-time-code"></label>`,
      `<button class="button ghost" id="settingsMfaCancel" type="button">Cancel</button><button class="button primary" id="settingsMfaVerify" type="button">Verify</button>`,"small");
    byId("settingsMfaCancel").onclick=async()=>{await state.client.auth.mfa.unenroll({factorId:data.id}).catch(()=>{});closeModal()};
    byId("settingsMfaVerify").onclick=async()=>{
      const button=byId("settingsMfaVerify");button.disabled=true;
      const {error}=await state.client.auth.mfa.challengeAndVerify({factorId:data.id,code:byId("settingsMfaCode").value.trim()});
      if(error){toast("Code not verified",friendlyError(error),"error");button.disabled=false}
      else{closeModal();toast("Authenticator verified");state.session=(await state.client.auth.getSession()).data.session}
    };
  }
  function backupStatusLabel(backup) {
    if(backup.status==="processing")return `<span class="chip warning">Processing</span>`;
    if(backup.status==="failed")return `<span class="chip danger">Failed</span>`;
    if(backup.verification_status==="passed")return `<span class="chip success">Verified</span>`;
    if(backup.verification_status==="failed")return `<span class="chip danger">Verification failed</span>`;
    return `<span class="chip">Completed, not tested</span>`;
  }
  function backupHistoryHtml(backups=[]) {
    if(!backups.length)return `<div class="empty"><strong>No full backup has been recorded</strong><span>Create the first encrypted continuity backup.</span></div>`;
    return `<div class="table-wrap history-scroll backup-history"><table><thead><tr><th>Created</th><th>Status</th><th>Database rows</th><th>Storage</th><th>Off-site</th><th></th></tr></thead><tbody>${backups.map(backup=>{
      const rows=Object.values(backup.row_counts||{}).reduce((sum,value)=>sum+Number(value||0),0);
      const objectCount=Object.values(backup.storage_object_counts||{}).reduce((sum,value)=>sum+Number(value||0),0);
      return `<tr><td><strong>${isoDateTime(backup.created_at)}</strong><br><small>${esc(backup.backup_key||backup.id)}</small></td><td>${backupStatusLabel(backup)}${backup.error_message?`<br><small>${esc(backup.error_message)}</small>`:""}</td><td>${number(rows)}</td><td>${number(objectCount)} files<br><small>${readableBytes(backup.storage_bytes||0)}</small></td><td>${backup.offsite_copied_at?`${isoDateTime(backup.offsite_copied_at)}${backup.offsite_copy_note?`<br><small>${esc(backup.offsite_copy_note)}</small>`:""}`:"Not confirmed"}</td><td><div class="button-row compact"><button class="button ghost small" type="button" data-backup-verify="${attr(backup.id)}" ${backup.status!=="completed"||backup.backup_type!=="full"?"disabled":""}>Verify</button><button class="button secondary small" type="button" data-backup-download="${attr(backup.id)}" ${backup.status!=="completed"||backup.backup_type!=="full"?"disabled":""}>Download encrypted package</button><button class="button ghost small" type="button" data-backup-offsite="${attr(backup.id)}" ${backup.status!=="completed"||backup.backup_type!=="full"||backup.offsite_copied_at?"disabled":""}>Confirm off-site copy</button></div></td></tr>`;
    }).join("")}</tbody></table></div>`;
  }
  function bindBackupHistoryControls() {
    $$('[data-backup-verify]').forEach(button=>button.onclick=()=>verifyFullBackup(button.dataset.backupVerify,button));
    $$('[data-backup-download]').forEach(button=>button.onclick=()=>downloadEncryptedBackupPackage(button.dataset.backupDownload,button));
    $$('[data-backup-offsite]').forEach(button=>button.onclick=()=>confirmBackupOffsiteCopy(button.dataset.backupOffsite,button));
  }
  async function saveBackupPolicy() {
    const form=byId("backupPolicyForm"),values=formObject(form),button=byId("backupPolicySave");
    const retention=Number(values.retention_days),minimum=Number(values.minimum_copies);
    if(!Number.isInteger(retention)||retention<7||retention>365){toast("Policy not saved","Retention must be a whole number from 7 through 365 days.","error");return}
    if(!Number.isInteger(minimum)||minimum<2||minimum>90){toast("Policy not saved","Minimum copies must be a whole number from 2 through 90.","error");return}
    button.disabled=true;
    try{await rpc("save_backup_policy",{target_retention_days:retention,target_minimum_copies:minimum});toast("Backup policy saved",`${minimum} copies will be retained, with age-based cleanup after ${retention} days.`)}
    catch(error){toast("Policy not saved",friendlyError(error),"error")}finally{button.disabled=false}
  }
  async function refreshBackupInterface(){
    if(state.view==="backup_restore")await renderBackupRestore(state.viewToken);
    else await renderSettings(state.viewToken,true);
  }
  function backupActionButton(eventOrButton,...ids){
    if(eventOrButton?.currentTarget)return eventOrButton.currentTarget;
    if(eventOrButton?.tagName)return eventOrButton;
    return ids.map(id=>byId(id)).find(Boolean)||null;
  }
  async function waitForBackup(backupId,timeoutMs=420000) {
    const started=Date.now();
    while(Date.now()-started<timeoutMs){
      const {data,error}=await state.client.from("backup_exports").select("*").eq("id",backupId).single();
      if(error)throw error;
      if(data.status==="completed")return data;
      if(data.status==="failed")throw new Error(data.error_message||"The full backup did not complete.");
      await new Promise(resolve=>setTimeout(resolve,3500));
    }
    throw new Error("The backup is still processing. Refresh Backup & Restore shortly to view its final status.");
  }
  async function waitForBackupVerification(backupId,startedAt,timeoutMs=420000){
    const started=Date.now(),threshold=new Date(startedAt||Date.now()).getTime();
    while(Date.now()-started<timeoutMs){
      const {data,error}=await state.client.from("backup_exports").select("verification_status,verification_checked_at,verification_notes,storage_object_counts").eq("id",backupId).single();
      if(error)throw error;
      const checkedAt=data.verification_checked_at?new Date(data.verification_checked_at).getTime():0;
      if(checkedAt>=threshold&&data.verification_status==="passed")return {...data,checked_objects:Object.values(data.storage_object_counts||{}).reduce((sum,value)=>sum+Number(value||0),0)};
      if(checkedAt>=threshold&&data.verification_status==="failed")throw new Error(data.verification_notes||"Backup verification failed.");
      await new Promise(resolve=>setTimeout(resolve,3000));
    }
    throw new Error("Backup verification is still processing. Refresh the page shortly to view its final result.");
  }
  async function createManualBackup(eventOrButton) {
    const button=backupActionButton(eventOrButton,"backupCreate","fullSchoolBackupCreate");
    if(!button){toast("Backup unavailable","The backup action control could not be found. Reload the application.","error");return}
    button.disabled=true;setSync("pending","Backing up");
    try{
      const data=await invokeEdgeFunction("scheduled-backup",{action:"create",mode:"manual"});
      const backupId=data?.backup_id;if(!backupId)throw new Error("The backup service did not return a backup identifier.");
      toast("Full backup started","Database records and private Storage objects are being encrypted and copied.","warning",5000);
      const completed=await waitForBackup(backupId);
      toast("Full backup completed",`${Object.values(completed.storage_object_counts||{}).reduce((sum,value)=>sum+Number(value||0),0)} files protected • ${readableBytes(completed.storage_bytes||0)} storage data.`);setSync("online","Synced");
      await refreshBackupInterface();
    }catch(error){toast("Backup unsuccessful",friendlyError(error),"error",10000);setSync("pending","Retry required")}
    finally{button.disabled=false}
  }
  async function verifyFullBackup(backupId,button) {
    if(!button)return;
    button.disabled=true;setSync("pending","Verifying backup");
    try{
      const data=await invokeEdgeFunction("scheduled-backup",{action:"verify",backup_id:backupId});
      const result=data?.status==="processing"?await waitForBackupVerification(backupId,data.verification_started_at):data;
      toast("Backup verification passed",`${number(result?.checked_objects||0)} storage files and the complete database export passed decryption and checksum verification.`);setSync("online","Synced");
      await refreshBackupInterface();
    }catch(error){toast("Backup verification failed",friendlyError(error),"error",11000);setSync("pending","Attention required")}
    finally{button.disabled=false}
  }

  async function downloadEncryptedBackupPackage(backupId,button) {
    if(!window.JSZip){toast("Download unavailable","The packaged ZIP library did not load.","error");return}
    if(!await confirmAction("Download Encrypted Off-site Package","This can be a large download because it contains the encrypted database and every protected Storage object in the selected backup. Keep the package and the backup encryption secret in separate secure locations.","Download package"))return;
    button.disabled=true;setSync("pending","Packaging backup");
    try{
      const {data:backup,error:backupError}=await state.client.from("backup_exports").select("*").eq("id",backupId).single();if(backupError)throw backupError;
      const {data:objects,error:objectsError}=await state.client.from("backup_storage_objects").select("backup_path").eq("backup_export_id",backupId).order("source_bucket").order("source_path");if(objectsError)throw objectsError;
      const paths=[backup.storage_path,backup.manifest_path,backup.database_path,...(objects||[]).map(item=>item.backup_path)].filter((path,index,array)=>path&&array.indexOf(path)===index);
      const zip=new window.JSZip(),prefix=`full/${backup.backup_key}/`;
      for(let index=0;index<paths.length;index+=1){
        setSync("pending",`Packaging ${index+1}/${paths.length}`);
        const path=paths[index],{data,error}=await state.client.storage.from(CONFIG.backupBucket).download(path);if(error)throw error;
        zip.file(path.startsWith(prefix)?path.slice(prefix.length):path,await data.arrayBuffer(),{binary:true});
      }
      zip.file("RESTORE_README.txt",`${schoolDisplayName()} Report Card Enterprise v7.4.0 Final Stable Multi-Platform Release\n\nThis package contains AES-256-GCM encrypted backup payloads. Keep the RCE_BACKUP_ENCRYPTION_KEY secret separately. Legacy NIS_BACKUP_ENCRYPTION_KEY remains supported temporarily. Follow FINAL_BACKUP_AND_RESTORE_RUNBOOK.md from the complete system package. Authentication password hashes are not exportable through the supported Supabase Auth API; users must reset passwords after a full project rebuild.\n`);
      const blob=await zip.generateAsync({type:"blob",compression:"STORE"});
      const filename=`${slugify(schoolDisplayName(),"school")}-Full-Backup-${backup.backup_key}.zip`;downloadBlob(filename,blob);
      toast("Encrypted package downloaded",`${filename}. After copying it to a separate secure location, use Confirm off-site copy.`);setSync("online","Synced");
    }catch(error){toast("Backup package not downloaded",friendlyError(error),"error",9000);setSync("pending","Retry required")}
    finally{button.disabled=false}
  }
  async function confirmBackupOffsiteCopy(backupId,button) {
    if(!await confirmAction("Confirm Secure Off-site Copy","Confirm only after the downloaded encrypted backup package has been stored in a separate protected location, such as an encrypted external drive or approved cloud archive.","Confirm copy"))return;
    button.disabled=true;
    try{
      const note=window.prompt("Optional location or reference note (do not enter the encryption key):","Encrypted package stored in a separate secure location")||"Encrypted package stored in a separate secure location";
      await rpc("mark_backup_offsite_copy",{target_backup_id:backupId,target_note:note});
      toast("Off-site copy confirmed","The continuity record has been updated.");
      await refreshBackupInterface();
    }catch(error){toast("Off-site copy not confirmed",friendlyError(error),"error",7000)}
    finally{button.disabled=false}
  }
  async function queueIncompleteNotifications() {
    const term=activeTerm();if(!term)return;
    const count=await run(()=>rpc("queue_incomplete_report_notifications",{target_term_id:term.id}),{success:"Notifications queued"});
    toast("Scheduled operation completed",`${number(count)} notifications queued`);
  }


  // ---------------------------------------------------------------------------
  // Report Card Enterprise v7.0.2 next-term reopening date
  // ---------------------------------------------------------------------------
  function selectedTermId(selectId="maturityTerm") {
    return nullableId(byId(selectId)?.value||activeTerm()?.id||(state.boot?.terms||[])[0]?.id);
  }
  function selectedClassId(selectId="maturityClass") {return nullableId(byId(selectId)?.value)}
  function percentValue(value){return Math.max(0,Math.min(100,Number(value||0)))}
  function statusText(value){return String(value||"unknown").replaceAll("_"," ")}
  function emptyState(title,detail="") {return `<div class="empty"><strong>${esc(title)}</strong>${detail?`<span>${esc(detail)}</span>`:""}</div>`}
  function maturityMetric(label,value,detail="") {return `<div class="metric maturity-metric"><span>${esc(label)}</span><strong>${esc(value??"—")}</strong>${detail?`<small>${esc(detail)}</small>`:""}</div>`}
  function dateInputValue(value){return value?dateTimeLocalValue(value):""}

  async function renderOperations(token,force=false) {
    const termId=nullableId(state.operationsConsole?.term_id||activeTerm()?.id||(state.boot.terms||[])[0]?.id);
    const hasAcademicTerm=Boolean(termId);
    const [ops,corrections,controls,backupData,recovery]=await Promise.all([
      rpc("operations_dashboard",{target_term_id:termId}),
      rpc("get_report_correction_console",{target_term_id:termId,target_class_id:null}),
      rpc("list_academic_period_controls"),
      role()==="system_admin"?rpc("backup_dashboard").catch(()=>({backups:[]})):Promise.resolve({backups:[]}),
      role()==="system_admin"?rpc("get_recovery_console").catch(()=>({tests:[]})):Promise.resolve({tests:[]})
    ]);
    if(token!==state.viewToken)return;
    state.operationsConsole={...ops,corrections,controls,backupData,recovery,term_id:termId};
    const control=ops.term_control||{},classes=state.boot.classes||[],progress=ops.class_progress||[],pending=(corrections.requests||[]).filter(item=>item.status==="pending");
    const correctionHistoryCount=terminalCorrectionHistoryCount(corrections.requests||[]),recoveryHistoryCount=terminalRecoveryHistoryCount(recovery.tests||[]);
    const latestBackup=(backupData.backups||[]).find(item=>item.status==="completed"&&item.backup_type==="full");
    const healthRisk=Number(ops.critical_security_events||0)>0||Number(ops.failed_backups_30d||0)>0||Number(ops.published_without_pdf||0)>0;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Production Operations</h3><p>Academic deadlines, term locks, report corrections, alerts, health, and recovery readiness</p></div><div class="page-actions"><button class="button secondary" id="operationsRefresh">Refresh</button></div></div>
      ${hasAcademicTerm?"":`<div class="template-information warning"><strong>No academic term is configured</strong><span>Academic controls are unavailable until a term exists. System health, backup verification, and the non-destructive recovery rehearsal remain available.</span></div>`}
      <section class="panel pad maturity-filter"><div class="form-grid three">
        <label class="field"><span>Academic term</span><select id="operationsTerm" ${hasAcademicTerm?"":"disabled"}>${optionList(state.boot.terms||[],"id","name",termId||"")}</select></label>
        <label class="field"><span>Class for bulk report generation</span><select id="operationsClass" ${hasAcademicTerm?"":"disabled"}>${optionList(classes,"id","name","","Select class")}</select></label>
        <div class="field"><span>Operational state</span><strong class="health-indicator ${healthRisk?"attention":"healthy"}">${healthRisk?"Attention required":"Healthy"}</strong></div>
      </div></section>
      <div class="stat-grid maturity-stat-grid">
        ${statCard("blue","◉","Expected reports",ops.reports_expected)}${statCard("purple","▤","Reports created",ops.reports_created)}
        ${statCard("gold","⌛","Awaiting approval",ops.awaiting_approval)}${statCard("green","✓","Published",ops.published)}
      </div>
      <div class="grid two maturity-grid">
        <section class="panel pad"><div class="section-title"><div><h4>Academic period control</h4><p>Set deadlines and freeze completed phases without altering historical records.</p></div></div>
          <form id="periodControlForm" class="form-grid">
            <label class="field"><span>Score-entry deadline</span><input type="datetime-local" name="score_entry_deadline" value="${attr(dateInputValue(control.score_entry_deadline))}"></label>
            <label class="field"><span>Attendance deadline</span><input type="datetime-local" name="attendance_deadline" value="${attr(dateInputValue(control.attendance_deadline))}"></label>
            <label class="field"><span>Report-submission deadline</span><input type="datetime-local" name="report_submission_deadline" value="${attr(dateInputValue(control.report_submission_deadline))}"></label>
            <label class="field"><span>Principal-approval deadline</span><input type="datetime-local" name="principal_approval_deadline" value="${attr(dateInputValue(control.principal_approval_deadline))}"></label>
            <label class="field"><span>Publication deadline</span><input type="datetime-local" name="publication_deadline" value="${attr(dateInputValue(control.publication_deadline))}"></label>
            <div class="field"><span>Phase locks</span><div class="check-grid"><label><input type="checkbox" name="scores_locked" ${control.scores_locked?"checked":""}> Scores</label><label><input type="checkbox" name="attendance_locked" ${control.attendance_locked?"checked":""}> Attendance</label><label><input type="checkbox" name="reports_locked" ${control.reports_locked?"checked":""}> Reports</label></div></div>
            <label class="field full"><span>Lock or reopening reason</span><textarea name="lock_reason" placeholder="Explain why the term is being locked or reopened">${esc(control.lock_reason||"")}</textarea></label>
            <div class="full button-row"><button class="button primary" id="periodControlSave" type="button" ${hasAcademicTerm?"":"disabled"}>Save period control</button><button class="button secondary" id="academicAlertsRun" type="button" ${hasAcademicTerm?"":"disabled"}>Queue deadline alerts</button></div>
          </form>
        </section>
        <section class="panel pad"><div class="section-title"><div><h4>System health</h4><p>Current production reliability indicators</p></div></div>
          <div class="metric-row wrap">${maturityMetric("PDFs missing",number(ops.published_without_pdf))}${maturityMetric("Client errors, 24h",number(ops.client_errors_24h))}${maturityMetric("Open security events",number(ops.open_security_events))}${maturityMetric("Failed backups, 30d",number(ops.failed_backups_30d))}</div>
          <div class="hr"></div>
          <div class="diff-row"><span>Latest full backup</span><b>${isoDateTime(ops.latest_backup)}</b></div>
          <div class="diff-row"><span>Latest verified backup</span><b>${isoDateTime(ops.latest_verified_backup)}</b></div>
          <div class="diff-row"><span>Latest recovery rehearsal</span><b>${isoDateTime(ops.latest_recovery_test)}</b></div>
          <div class="diff-row"><span>Attendance classes marked today</span><b>${number(ops.attendance_classes_today)} / ${number(ops.active_classes)}</b></div>
          <div class="diff-row"><span>Pending notification deliveries</span><b>${number(ops.pending_notifications)}</b></div>
          ${role()==="system_admin"?`<div class="button-row" style="margin-top:15px"><button class="button secondary" id="recoveryRun" ${latestBackup?"":"disabled"}>Run recovery rehearsal</button></div>`:""}
        </section>
      </div>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Class report progress</h3><p>Current created, submitted, approved, and published records by class. This is live operational data, not deletable history.</p></div><button class="button outline small" id="generateMissingReports" ${hasAcademicTerm?"":"disabled"}>Preview missing reports</button></div>
        ${progress.length?`<div class="table-wrap history-scroll class-progress-scroll"><table><thead><tr><th>Class</th><th>Enrolled</th><th>Created</th><th>Submitted</th><th>Approved</th><th>Published</th><th>Completion</th></tr></thead><tbody>${progress.map(item=>{const pct=item.enrolled?Math.round(Number(item.published||0)/Number(item.enrolled)*100):0;return `<tr><td><strong>${esc(item.class_name)}</strong></td><td>${number(item.enrolled)}</td><td>${number(item.created)}</td><td>${number(item.submitted)}</td><td>${number(item.approved)}</td><td>${number(item.published)}</td><td><div class="inline-progress"><span style="width:${pct}%"></span></div><small>${pct}%</small></td></tr>`}).join("")}</tbody></table></div>`:emptyState("No class progress available")}
      </section>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Published-report correction requests</h3><p>Original reports remain preserved; approved requests reopen controlled editing.</p></div><div class="button-row compact"><span class="chip">${number(pending.length)} pending</span>${role()==="system_admin"?`<button class="button danger small" id="correctionHistoryClear" type="button" ${correctionHistoryCount?"":"disabled"}>Clear resolved history</button>`:""}</div></div>
        ${(corrections.requests||[]).length?`<div class="table-wrap history-scroll correction-history-scroll"><table><thead><tr><th>Student and report</th><th>Class</th><th>Request</th><th>Status</th><th>Review</th></tr></thead><tbody>${(corrections.requests||[]).map(item=>`<tr><td><div class="cell-copy"><strong>${esc(item.student_name)}</strong><small>${esc(item.report_number||"Report")} • ${esc(item.term_name)}</small></div></td><td>${esc(item.class_name)}</td><td><div class="cell-copy"><strong>${esc(item.requester_name||"Authorised user")}</strong><small>${esc(item.reason)}</small></div></td><td>${statusBadge(item.status)}</td><td>${role()==="principal"&&item.status==="pending"?`<div class="button-row compact"><button class="button success small" data-correction-review="${attr(item.id)}" data-decision="approved">Approve</button><button class="button warning small" data-correction-review="${attr(item.id)}" data-decision="rejected">Reject</button></div>`:`<small>${esc(item.reviewer_name||item.review_note||"Awaiting review")}</small>`}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No correction requests")}
      </section>
      ${role()==="system_admin"?`<section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Recovery rehearsal history</h3><p>Non-destructive decrypt, reconstruction, and checksum tests</p></div><button class="button danger small" id="recoveryHistoryClear" type="button" ${recoveryHistoryCount?"":"disabled"}>Clear history</button></div>${(recovery.tests||[]).length?`<div class="table-wrap history-scroll recovery-history-scroll"><table><thead><tr><th>Started</th><th>Status</th><th>Tables</th><th>Rows</th><th>Storage objects</th><th>Notes</th></tr></thead><tbody>${(recovery.tests||[]).map(item=>`<tr><td>${isoDateTime(item.started_at)}</td><td>${statusBadge(item.status)}</td><td>${number(item.checked_tables)}</td><td>${number(item.checked_rows)}</td><td>${number(item.checked_storage_objects)}</td><td>${esc(item.notes||item.error_message||"—")}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No recovery rehearsal has been recorded")}</section>`:""}`;
    byId("operationsTerm").onchange=()=>{state.operationsConsole={term_id:nullableId(byId("operationsTerm").value)};renderOperations(token,true)};
    byId("operationsRefresh").onclick=()=>renderOperations(token,true);
    if(!hasAcademicTerm){
      $$("#periodControlForm input,#periodControlForm textarea").forEach(element=>{element.disabled=true});
    }
    byId("periodControlSave").onclick=savePeriodControl;
    byId("academicAlertsRun").onclick=runAcademicAlerts;
    byId("generateMissingReports").onclick=previewMissingReports;
    byId("recoveryRun")?.addEventListener("click",()=>runRecoveryRehearsal(latestBackup?.id));
    byId("correctionHistoryClear")?.addEventListener("click",()=>clearSectionHistory("report_corrections","Clear Resolved Correction History","This permanently removes only rejected, cancelled, and fully applied correction-request history and its event rows. Pending and approved requests, reports, revisions, publications, scores, and PDFs are preserved.",()=>renderOperations(state.viewToken,true)));
    byId("recoveryHistoryClear")?.addEventListener("click",()=>clearSectionHistory("recovery_rehearsals","Clear Recovery Rehearsal History","This permanently removes completed recovery-rehearsal evidence rows. Backup packages and production data are not deleted. Run a new rehearsal afterward if you want a fresh recovery-readiness record.",()=>renderOperations(state.viewToken,true)));
    $$('[data-correction-review]').forEach(button=>button.onclick=()=>reviewCorrectionRequest(button.dataset.correctionReview,button.dataset.decision));
  }

  async function savePeriodControl() {
    const form=byId("periodControlForm"),values=formObject(form),button=byId("periodControlSave"),termId=nullableId(byId("operationsTerm")?.value);
    if(!termId){toast("Academic term required","Create or select an academic term before changing period controls.","warning");return}
    const locked=form.elements.scores_locked.checked||form.elements.attendance_locked.checked||form.elements.reports_locked.checked;
    if(locked&&values.lock_reason.trim().length<5){toast("Period control not saved","Provide a clear reason before locking an academic phase.","error");return}
    button.disabled=true;
    try{await rpc("save_academic_period_control",{payload:{term_id:termId,...values,scores_locked:form.elements.scores_locked.checked,attendance_locked:form.elements.attendance_locked.checked,reports_locked:form.elements.reports_locked.checked}});toast("Academic period control saved");await renderOperations(state.viewToken,true)}
    catch(error){toast("Period control not saved",friendlyError(error),"error",7500)}finally{button.disabled=false}
  }
  async function runAcademicAlerts(){const button=byId("academicAlertsRun"),termId=nullableId(byId("operationsTerm")?.value);if(!termId){toast("Academic term required","Create or select an academic term before queueing deadline alerts.","warning");return}button.disabled=true;try{const result=await rpc("run_academic_alerts",{target_term_id:termId});toast("Academic alerts queued",`${number(result.queued)} new notification${Number(result.queued)===1?"":"s"} queued.`);await loadNotificationCount()}catch(error){toast("Alerts not queued",friendlyError(error),"error")}finally{button.disabled=false}}
  async function previewMissingReports(){const termId=nullableId(byId("operationsTerm")?.value),classId=nullableId(byId("operationsClass")?.value);if(!termId){toast("Academic term required","Create or select an academic term before generating report records.","warning");return}if(!classId){toast("Select a class","Choose the class before previewing missing reports.","warning");return}try{const preview=await rpc("bulk_generate_missing_reports",{target_term_id:termId,target_class_id:classId,preview_only:true});if(!preview.missing_reports){toast("No missing reports","Every active student already has a report for this term.");return}if(!await confirmAction("Generate missing draft reports",`${number(preview.missing_reports)} missing report record(s) will be created. Existing reports will not be changed.`,"Generate reports"))return;const result=await rpc("bulk_generate_missing_reports",{target_term_id:termId,target_class_id:classId,preview_only:false});toast("Draft reports generated",`${number(result.created_reports)} report record(s) created.`);await renderOperations(state.viewToken,true)}catch(error){toast("Reports not generated",friendlyError(error),"error",7500)}}
  async function reviewCorrectionRequest(id,decision){modal(`${decision==="approved"?"Approve":"Reject"} correction request`,"Principal oversight",`<label class="field"><span>Review note</span><textarea id="correctionReviewNote" placeholder="Record the approval conditions or rejection reason"></textarea></label>`,`<button class="button ghost" id="correctionReviewCancel">Cancel</button><button class="button ${decision==="approved"?"success":"warning"}" id="correctionReviewConfirm">${decision==="approved"?"Approve":"Reject"}</button>`,"small");byId("correctionReviewCancel").onclick=closeModal;byId("correctionReviewConfirm").onclick=async()=>{const button=byId("correctionReviewConfirm");button.disabled=true;try{await rpc("review_report_correction",{target_request_id:id,decision,review_note_text:byId("correctionReviewNote").value.trim()});closeModal();toast("Correction request reviewed");await renderOperations(state.viewToken,true)}catch(error){toast("Review not saved",friendlyError(error),"error")}finally{button.disabled=false}}}
  async function runRecoveryRehearsal(backupId){if(!backupId)return;if(!await confirmAction("Run recovery rehearsal","The latest completed encrypted backup will be decrypted and reconstructed in memory. Production records will not be overwritten.","Run rehearsal"))return;const button=byId("recoveryRun");button.disabled=true;setSync("pending","Testing recovery");try{const data=await invokeEdgeFunction("scheduled-backup",{action:"recovery_test",backup_id:backupId});toast("Recovery rehearsal passed",`${number(data.checked_tables)} tables, ${number(data.checked_rows)} rows, and ${number(data.checked_storage_objects)} storage objects verified.`);setSync("online","Synced");await renderOperations(state.viewToken,true)}catch(error){toast("Recovery rehearsal failed",friendlyError(error),"error",9000);setSync("pending","Attention required")}finally{button.disabled=false}}

  async function renderAcademicHistory(token,force=false) {
    const visibleClasses=await visibleClassesForCurrentRole();
    let students=state.historyStudents||[];
    if(!state.historyStudents){try{const result=await rpcAllRows("search_students_v5",{search_text:"",target_class_id:null,target_status:null,archive_filter:["system_admin","principal"].includes(role())?"all":"active"});students=result.rows||[];state.historyStudents=students}catch(_){students=[]}}
    if(token!==state.viewToken)return;
    const filtered=students.filter(item=>["system_admin","principal"].includes(role())||visibleClasses.some(c=>c.id===(item.current_class_id||item.class_id)));
    if(state.historyStudentId&&!filtered.some(item=>item.id===state.historyStudentId))state.historyStudentId="";
    if(!state.historyStudentId&&filtered.length)state.historyStudentId=filtered[0].id;
    if(state.historyStudentId){try{state.historyData=await rpc("get_student_academic_history",{target_student_id:state.historyStudentId})}catch(error){state.historyData={error:friendlyError(error)}}}else state.historyData=null;
    const data=state.historyData||{},transcript=data.transcript||{},student=transcript.student||{},records=transcript.academic_records||[],lifecycle=transcript.lifecycle||[],issuances=data.issuances||[];
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Student Academic History</h3><p>Cumulative records, lifecycle events, transcripts, and public verification</p></div><div class="page-actions">${["system_admin","principal"].includes(role())&&student.id?`<button class="button primary" id="transcriptIssue">Issue transcript</button>`:""}${role()==="system_admin"&&student.id?`<button class="button secondary" id="lifecycleAdd">Record lifecycle event</button>`:""}</div></div>
      <section class="panel pad"><div class="form-grid"><label class="field"><span>Find student</span><input id="historySearch" type="search" placeholder="Search name or admission number"></label><label class="field"><span>Student</span><select id="historyStudent">${optionList(filtered.map(item=>({...item,label:`${item.full_name||fullName(item)} • ${item.admission_no}`})),"id","label",state.historyStudentId,filtered.length?"Select student":"No accessible students")}</select></label></div></section>
      ${data.error?`<section class="panel pad">${emptyState("Academic history unavailable",data.error)}</section>`:student.id?`
      <div class="grid two maturity-grid" style="margin-top:18px">
        <section class="panel pad transcript-profile"><div class="section-title"><h4>${esc(student.full_name)}</h4><span class="status ${student.status==="active"?"published":"draft"}">${esc(statusText(student.status))}</span></div><div class="metric-row wrap">${maturityMetric("Admission number",student.admission_no)}${maturityMetric("Academic periods",number(records.length))}${maturityMetric("Transcript issuances",number(issuances.length))}</div><div class="button-row" style="margin-top:15px"><button class="button outline" id="transcriptPrint">Download transcript PDF</button><button class="button ghost" id="transcriptCsv">Export CSV</button></div></section>
        <section class="panel pad"><div class="section-title"><h4>Lifecycle</h4></div>${lifecycle.length?`<div class="timeline">${lifecycle.map(item=>`<div class="timeline-item"><span class="timeline-dot"></span><div class="timeline-copy"><strong>${esc(statusText(item.event_type))}</strong><small>${isoDate(item.effective_date)} • ${esc(item.from_class_name||"—")} ${item.to_class_name?`→ ${esc(item.to_class_name)}`:""}${item.destination_school?` • ${esc(item.destination_school)}`:""}<br>${esc(item.reason)}</small></div></div>`).join("")}</div>`:`<p class="help-text">No transfer, withdrawal, graduation, or reactivation event recorded.</p>`}</section>
      </div>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Cumulative academic record</h3><p>Approved, published, and historically withdrawn report versions</p></div></div>${records.length?records.map(record=>academicRecordHtml(record)).join(""):emptyState("No cumulative academic record")}</section>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Transcript issuances</h3><p>Only the latest valid issuance verifies as current. Permanent deletion is restricted to the System Administrator.</p></div></div>${issuances.length?`<div class="table-wrap"><table><thead><tr><th>Issued</th><th>Purpose</th><th>Status</th><th>Verification</th><th>Action</th></tr></thead><tbody>${issuances.map(item=>`<tr><td>${isoDateTime(item.issued_at)}</td><td>${esc(item.purpose)}</td><td>${statusBadge(item.status)}</td><td><code>${esc(item.verification_token)}</code></td><td><div class="button-row compact"><button class="button ghost small" data-transcript-copy="${attr(item.verification_token)}">Copy link</button>${["system_admin","principal"].includes(role())&&item.status==="valid"?`<button class="button warning small" data-transcript-revoke="${attr(item.id)}">Revoke</button>`:""}${role()==="system_admin"?`<button class="button danger small" data-transcript-delete="${attr(item.id)}">Delete permanently</button>`:""}</div></td></tr>`).join("")}</tbody></table></div>`:emptyState("No official transcript has been issued")}</section>`:`<section class="panel pad" style="margin-top:18px">${emptyState("Select a student")}</section>`}`;
    byId("historyStudent").onchange=async()=>{state.historyStudentId=byId("historyStudent").value;state.historyData=null;await renderAcademicHistory(token,true)};
    byId("historySearch").oninput=()=>{const q=byId("historySearch").value.toLowerCase();$$('#historyStudent option').forEach(option=>{if(!option.value)return;option.hidden=!option.textContent.toLowerCase().includes(q)})};
    byId("transcriptIssue")?.addEventListener("click",issueTranscript);
    byId("lifecycleAdd")?.addEventListener("click",recordLifecycleEvent);
    byId("transcriptPrint")?.addEventListener("click",()=>downloadTranscriptPdf(transcript,issuances));
    byId("transcriptCsv")?.addEventListener("click",()=>exportTranscriptCsv(transcript));
    $$('[data-transcript-copy]').forEach(button=>button.onclick=()=>copyTranscriptLink(button.dataset.transcriptCopy));
    $$('[data-transcript-revoke]').forEach(button=>button.onclick=()=>revokeTranscript(button.dataset.transcriptRevoke));
    $$('[data-transcript-delete]').forEach(button=>button.onclick=()=>deleteTranscriptIssuancePermanently(button.dataset.transcriptDelete));
  }
  function academicRecordHtml(record){const attendance=Number(record.days_school_opened||0)?Math.round(Number(record.days_present||0)/Number(record.days_school_opened)*100):0;return `<article class="academic-period-card"><header><div><strong>${esc(record.academic_year_name)} • ${esc(record.term_name)}</strong><span>${esc(record.class_name)} • ${esc(record.report_number||"Report")}</span></div><div><b>${number(record.average,1)}%</b><small>${number(record.days_present)} / ${number(record.days_school_opened)} days (${attendance}%)</small></div></header><div class="table-wrap"><table><thead><tr><th>Subject</th><th>Score</th><th>Grade</th><th>Remark</th></tr></thead><tbody>${(record.subjects||[]).map(subject=>`<tr><td>${esc(subject.subject_name)}</td><td>${number(subject.total_score,1)}</td><td>${esc(subject.grade||"—")}</td><td>${esc(subject.remark||"")}</td></tr>`).join("")}</tbody></table></div></article>`}
  async function issueTranscript(){modal("Issue official transcript","A new issuance supersedes any currently valid transcript for this student.",`<label class="field"><span>Purpose</span><input id="transcriptPurpose" value="Academic transcript"></label>`,`<button class="button ghost" id="transcriptCancel">Cancel</button><button class="button primary" id="transcriptConfirm">Issue transcript</button>`,"small");byId("transcriptCancel").onclick=closeModal;byId("transcriptConfirm").onclick=async()=>{const button=byId("transcriptConfirm");button.disabled=true;try{const result=await rpc("issue_student_transcript",{target_student_id:state.historyStudentId,purpose_text:byId("transcriptPurpose").value.trim()});closeModal();toast("Transcript issued",`Verification token: ${result.verification_token}`);state.historyData=null;await renderAcademicHistory(state.viewToken,true)}catch(error){toast("Transcript not issued",friendlyError(error),"error")}finally{button.disabled=false}}}
  async function revokeTranscript(id){const reason=window.prompt("Enter the reason for revoking this transcript:","")||"";if(reason.trim().length<5)return;try{await rpc("revoke_student_transcript",{target_issuance_id:id,reason_text:reason.trim()});toast("Transcript revoked");state.historyData=null;await renderAcademicHistory(state.viewToken,true)}catch(error){toast("Transcript not revoked",friendlyError(error),"error")}}
  function deleteTranscriptIssuancePermanently(id){
    const issuance=(state.historyData?.issuances||[]).find(item=>item.id===id);if(!issuance)return;
    modal("Delete Transcript Issuance Permanently","This removes the issuance record and immediately invalidates its public verification link. The student's academic reports and cumulative history are not deleted.",`<div class="destructive-confirmation"><label class="field"><span>Deletion reason</span><textarea id="transcriptDeleteReason" minlength="5" required placeholder="Explain why this issuance must be removed"></textarea></label><label class="field"><span>Type DELETE to confirm</span><input id="transcriptDeleteConfirmText" autocomplete="off" required></label><p class="help-text">Issuance: ${esc(isoDateTime(issuance.issued_at))} • ${esc(issuance.purpose||"Academic transcript")} • ${esc(statusText(issuance.status))}</p></div>`,`<button class="button ghost" id="transcriptDeleteCancel" type="button">Cancel</button><button class="button danger" id="transcriptDeleteConfirm" type="button">Delete permanently</button>`,"small");
    byId("transcriptDeleteCancel").onclick=closeModal;
    byId("transcriptDeleteConfirm").onclick=async()=>{
      const reason=byId("transcriptDeleteReason").value.trim(),confirmation=byId("transcriptDeleteConfirmText").value.trim();
      if(reason.length<5||confirmation!=="DELETE"){toast("Transcript not deleted","Enter a reason of at least five characters and type DELETE exactly.","error");return}
      const button=byId("transcriptDeleteConfirm");button.disabled=true;button.textContent="Deleting";
      try{await rpc("delete_transcript_issuance_permanently",{target_issuance_id:id,reason_text:reason,confirmation_text:confirmation});closeModal();toast("Transcript issuance deleted permanently");state.historyData=null;await renderAcademicHistory(state.viewToken,true)}
      catch(error){toast("Transcript issuance not deleted",friendlyError(error),"error",8000)}
      finally{if(button){button.disabled=false;button.textContent="Delete permanently"}}
    };
  }
  function copyTranscriptLink(token){const base=(state.boot.school?.verification_base_url||location.href.split("?")[0]).replace(/\?+$/,'');const url=`${base}?transcript=${encodeURIComponent(token)}`;navigator.clipboard?.writeText(url).then(()=>toast("Verification link copied")).catch(()=>window.prompt("Copy verification link:",url))}
  function transcriptTextLines(ctx,text,maxWidth) {
    const words=String(text||"").replace(/\s+/g," ").trim().split(" ").filter(Boolean),lines=[];let line="";
    for(const word of words){const candidate=line?`${line} ${word}`:word;if(line&&ctx.measureText(candidate).width>maxWidth){lines.push(line);line=word}else line=candidate}
    if(line)lines.push(line);return lines;
  }

  function transcriptPageCanvas(school,pageNumber) {
    const canvas=document.createElement("canvas");canvas.width=1240;canvas.height=1754;
    const ctx=canvas.getContext("2d"),navy=school.primary_colour||"#0a2f73",gold=school.accent_colour||"#f1b51c";
    ctx.fillStyle="#ffffff";ctx.fillRect(0,0,canvas.width,canvas.height);
    ctx.fillStyle=navy;ctx.fillRect(0,0,canvas.width,154);
    ctx.fillStyle=gold;ctx.fillRect(0,154,canvas.width,8);
    ctx.textAlign="center";ctx.fillStyle="#ffffff";ctx.font='bold 34px Georgia, "Times New Roman", serif';ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),620,64);
    ctx.font='18px Arial, sans-serif';ctx.fillText(school.address||school.motto||"",620,98);
    ctx.font='bold 27px Arial, sans-serif';ctx.fillText("CUMULATIVE ACADEMIC TRANSCRIPT",620,137);
    ctx.textAlign="left";ctx.fillStyle="#56647a";ctx.font='15px Arial, sans-serif';ctx.fillText(`Page ${pageNumber}`,1080,1718);
    return {canvas,ctx,navy,gold,y:205};
  }

  async function createTranscriptPdf(snapshot,issuances=[]) {
    const student=snapshot?.student||{},school=snapshot?.school||state.boot?.school||{},records=snapshot?.academic_records||[],lifecycle=snapshot?.lifecycle||[];
    const pages=[];let page=transcriptPageCanvas(school,1),ctx=page.ctx,y=page.y;
    const margin=64,contentWidth=1112,navy=page.navy,gold=page.gold;
    const newPage=()=>{pages.push(page);page=transcriptPageCanvas(school,pages.length+1);ctx=page.ctx;y=page.y};
    const requireSpace=height=>{if(y+height>1645)newPage()};
    let logo=null;try{logo=await loadImage(schoolDisplayLogo(school))}catch(_){}
    if(logo)drawImageContain(ctx,logo,72,22,112,112);
    const currentIssuance=issuances.find(item=>item.status==="valid")||issuances.find(item=>item.status!=="revoked")||null;
    let qr=null;if(currentIssuance?.verification_token){try{qr=await qrCanvas((state.boot.school?.verification_base_url||location.href.split("?")[0]).replace(/\?+$/,'')+`?transcript=${encodeURIComponent(currentIssuance.verification_token)}`)}catch(_){}}

    ctx.fillStyle="#f5f8fc";ctx.strokeStyle="#cfd8e6";ctx.lineWidth=2;ctx.beginPath();ctx.roundRect(margin,y,contentWidth,190,18);ctx.fill();ctx.stroke();
    ctx.fillStyle=navy;ctx.font='bold 30px Georgia, "Times New Roman", serif';ctx.fillText(student.full_name||"Student",90,y+47);
    ctx.fillStyle="#26354d";ctx.font='18px Arial, sans-serif';
    const detailRows=[
      ["Admission number",student.admission_no||"-"],["Student status",statusText(student.status||"active")],
      ["Academic periods",String(records.length)],["Transcript issued",currentIssuance?isoDateTime(currentIssuance.issued_at):"Not issued"]
    ];
    detailRows.forEach((row,index)=>{const col=index%2,rowNo=Math.floor(index/2),x=90+col*445,yy=y+88+rowNo*42;ctx.fillStyle="#61718a";ctx.font='14px Arial, sans-serif';ctx.fillText(row[0].toUpperCase(),x,yy);ctx.fillStyle="#15233b";ctx.font='bold 18px Arial, sans-serif';ctx.fillText(String(row[1]),x,yy+23)});
    if(qr){ctx.drawImage(qr,1000,y+22,142,142);ctx.fillStyle="#61718a";ctx.font='13px Arial, sans-serif';ctx.textAlign="center";ctx.fillText("SCAN TO VERIFY",1071,y+177);ctx.textAlign="left"}
    y+=220;

    if(!records.length){
      requireSpace(210);ctx.fillStyle="#f8fafc";ctx.strokeStyle="#d8e0eb";ctx.beginPath();ctx.roundRect(margin,y,contentWidth,185,16);ctx.fill();ctx.stroke();ctx.textAlign="center";ctx.fillStyle=navy;ctx.font='bold 25px Arial, sans-serif';ctx.fillText("No cumulative academic record available",620,y+76);ctx.fillStyle="#64748b";ctx.font='18px Arial, sans-serif';ctx.fillText("Approved, published, or historically retained reports will appear here.",620,y+116);ctx.textAlign="left";y+=215;
    }

    for(const record of records){
      const subjects=record.subjects||[],estimated=138+Math.max(1,subjects.length)*48+58;requireSpace(Math.min(estimated,620));
      ctx.fillStyle=navy;ctx.beginPath();ctx.roundRect(margin,y,contentWidth,58,12);ctx.fill();ctx.fillStyle="#ffffff";ctx.font='bold 21px Arial, sans-serif';ctx.fillText(`${record.academic_year_name||""}  |  ${record.term_name||""}  |  ${record.class_name||""}`,84,y+36);y+=72;
      ctx.fillStyle="#edf2f8";ctx.strokeStyle="#cbd5e1";ctx.lineWidth=1;ctx.fillRect(margin,y,contentWidth,42);ctx.strokeRect(margin,y,contentWidth,42);
      const cols=[margin,margin+545,margin+690,margin+825,margin+contentWidth];
      ["SUBJECT","SCORE","GRADE","REMARK"].forEach((label,index)=>{ctx.fillStyle="#27364d";ctx.font='bold 15px Arial, sans-serif';ctx.fillText(label,cols[index]+12,y+27)});y+=42;
      if(!subjects.length){ctx.strokeStyle="#d8e0eb";ctx.strokeRect(margin,y,contentWidth,50);ctx.fillStyle="#66758b";ctx.font='17px Arial, sans-serif';ctx.fillText("No subject results recorded",margin+14,y+31);y+=50}
      for(const subject of subjects){
        const subjectLines=transcriptTextLines(ctx,subject.subject_name||"",515),remarkLines=transcriptTextLines(ctx,subject.remark||"",270),lines=Math.max(1,subjectLines.length,remarkLines.length),rowHeight=Math.max(46,lines*21+16);
        if(y+rowHeight+75>1645){newPage();ctx.fillStyle="#edf2f8";ctx.strokeStyle="#cbd5e1";ctx.fillRect(margin,y,contentWidth,42);ctx.strokeRect(margin,y,contentWidth,42);["SUBJECT","SCORE","GRADE","REMARK"].forEach((label,index)=>{ctx.fillStyle="#27364d";ctx.font='bold 15px Arial, sans-serif';ctx.fillText(label,cols[index]+12,y+27)});y+=42}
        ctx.strokeStyle="#d8e0eb";ctx.strokeRect(margin,y,contentWidth,rowHeight);[cols[1],cols[2],cols[3]].forEach(x=>{ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x,y+rowHeight);ctx.stroke()});
        ctx.fillStyle="#1e293b";ctx.font='16px Arial, sans-serif';subjectLines.forEach((line,index)=>ctx.fillText(line,cols[0]+12,y+27+index*21));
        ctx.textAlign="center";ctx.font='bold 16px Arial, sans-serif';ctx.fillText(number(subject.total_score,1),cols[1]+72,y+28);ctx.fillText(subject.grade||"-",cols[2]+67,y+28);ctx.textAlign="left";ctx.font='15px Arial, sans-serif';remarkLines.forEach((line,index)=>ctx.fillText(line,cols[3]+12,y+27+index*21));y+=rowHeight;
      }
      const opened=Number(record.days_school_opened||0),present=Number(record.days_present||0),attendance=opened?Math.round(present/opened*100):0;
      ctx.fillStyle="#f8fafc";ctx.strokeStyle="#d8e0eb";ctx.fillRect(margin,y,contentWidth,48);ctx.strokeRect(margin,y,contentWidth,48);ctx.fillStyle=navy;ctx.font='bold 16px Arial, sans-serif';ctx.fillText(`TERM AVERAGE: ${number(record.average,1)}%`,margin+14,y+30);ctx.fillText(`ATTENDANCE: ${present} / ${opened} DAYS (${attendance}%)`,margin+370,y+30);ctx.fillStyle="#53657d";ctx.font='15px Arial, sans-serif';ctx.textAlign="right";ctx.fillText(`REPORT: ${record.report_number||"-"}`,margin+contentWidth-14,y+30);ctx.textAlign="left";y+=76;
    }

    if(lifecycle.length){requireSpace(105+lifecycle.length*38);ctx.fillStyle=navy;ctx.font='bold 21px Arial, sans-serif';ctx.fillText("STUDENT LIFECYCLE HISTORY",margin,y+15);y+=34;for(const item of lifecycle){requireSpace(42);ctx.fillStyle="#f8fafc";ctx.strokeStyle="#d8e0eb";ctx.fillRect(margin,y,contentWidth,36);ctx.strokeRect(margin,y,contentWidth,36);ctx.fillStyle="#26354d";ctx.font='15px Arial, sans-serif';ctx.fillText(`${isoDate(item.effective_date)}  |  ${statusText(item.event_type)}  |  ${item.from_class_name||"-"}${item.to_class_name?` -> ${item.to_class_name}`:""}`,margin+12,y+24);y+=38}}

    pages.push(page);
    for(let index=0;index<pages.length;index++){
      const item=pages[index],footerY=1684;item.ctx.fillStyle=navy;item.ctx.fillRect(64,footerY-22,1112,2);item.ctx.fillStyle="#53657d";item.ctx.font='14px Arial, sans-serif';item.ctx.textAlign="left";item.ctx.fillText(`Generated ${isoDateTime(new Date())}`,70,footerY);item.ctx.textAlign="center";item.ctx.fillText(currentIssuance?.verification_token?`Verification: ${currentIssuance.verification_token}`:"Unissued cumulative record",620,footerY);item.ctx.textAlign="right";item.ctx.fillText(`Page ${index+1} of ${pages.length}`,1170,footerY);item.ctx.textAlign="left";
    }
    const images=[];for(const item of pages){const jpeg=await new Promise((resolve,reject)=>item.canvas.toBlob(blob=>blob?resolve(blob):reject(new Error("Transcript page could not be rendered")),"image/jpeg",.96));images.push(jpeg)}
    return imagesPdf(images,595.28,841.89,1240,1754);
  }

  async function downloadTranscriptPdf(snapshot,issuances=[]) {
    setLoading(true);try{const student=snapshot?.student||{},pdf=await createTranscriptPdf(snapshot,issuances);downloadBlob(`${safeArchiveSegment(student.full_name||"Student","Student")}_Cumulative_Transcript.pdf`,pdf);toast("Transcript PDF downloaded",`${student.full_name||"Student"}'s cumulative transcript was prepared successfully.`)}catch(error){toast("Transcript PDF not created",friendlyError(error),"error",8000);await reportClientError(error,{source:"transcript_pdf",student_id:snapshot?.student?.id||state.historyStudentId})}finally{setLoading(false)}
  }

  function exportTranscriptCsv(snapshot){const student=snapshot.student||{},headers=["academic_year","term","class","subject","score","grade","remark","days_present","days_opened","report_number"];const rows=[];(snapshot.academic_records||[]).forEach(record=>(record.subjects||[]).forEach(subject=>rows.push([record.academic_year_name,record.term_name,record.class_name,subject.subject_name,subject.total_score,subject.grade,subject.remark,record.days_present,record.days_school_opened,record.report_number])));downloadText(`${slugify(student.full_name||"student")}-transcript.csv`,[headers.join(","),...rows.map(row=>row.map(csvCell).join(","))].join("\n"),"text/csv")}
  function recordLifecycleEvent(){const classes=state.boot.classes||[];modal("Record student lifecycle event","Transfer, withdrawal, graduation, inactivity, or reactivation is preserved as immutable history.",`<form id="lifecycleForm" class="form-grid"><label class="field"><span>Event</span><select name="event_type">${["transfer_in","transfer_out","withdrawn","graduated","inactive","reactivated","archived"].map(value=>`<option value="${value}">${esc(statusText(value))}</option>`).join("")}</select></label><label class="field"><span>Effective date</span><input type="date" name="effective_date" value="${localDateValue()}"></label><label class="field"><span>Destination or new class</span><select name="to_class_id">${optionList(classes,"id","name","","Not applicable")}</select></label><label class="field"><span>Destination school</span><input name="destination_school"></label><label class="field full"><span>Reference</span><input name="reference"></label><label class="field full"><span>Reason</span><textarea name="reason" required></textarea></label></form>`,`<button class="button ghost" id="lifecycleCancel">Cancel</button><button class="button primary" id="lifecycleSave">Save event</button>`,"small");byId("lifecycleCancel").onclick=closeModal;byId("lifecycleSave").onclick=async()=>{const form=byId("lifecycleForm"),values=formObject(form);if(values.reason.trim().length<5){toast("Reason required","Provide at least five characters.","error");return}const button=byId("lifecycleSave");button.disabled=true;try{await rpc("record_student_lifecycle_event",{payload:{student_id:state.historyStudentId,...values}});closeModal();toast("Lifecycle event recorded");state.historyData=null;state.workspace=null;await renderAcademicHistory(state.viewToken,true)}catch(error){toast("Lifecycle event not saved",friendlyError(error),"error")}finally{button.disabled=false}}}


  function capacityDisplayValue(value,unit="records") {
    if(value===null||value===undefined||value==="")return "Unlimited";
    const numeric=Number(value);if(!Number.isFinite(numeric))return "Unlimited";
    return unit==="MB"?`${number(numeric,2)} MB`:number(numeric);
  }
  function capacityPercent(used,limit) {
    const u=Number(used||0),l=Number(limit);
    if(!Number.isFinite(l)||l<=0)return 0;
    return Math.max(0,Math.min(100,u/l*100));
  }
  function capacityStateLabel(used,limit) {
    const l=Number(limit),u=Number(used||0);
    if(!Number.isFinite(l))return {label:"Unlimited",className:"approved"};
    if(u>=l)return {label:"At capacity",className:"rejected"};
    if(l>0&&u/l>=.8)return {label:"Approaching limit",className:"pending"};
    return {label:"Available",className:"approved"};
  }
  function featureFlagLabel(value="") {
    return String(value||"").replaceAll("_"," ").replace(/\b\w/g,char=>char.toUpperCase());
  }
  async function invokeLicenseVerifier(action,payload={}) {
    const {data,error}=await state.client.functions.invoke("license-verifier",{body:{action,...payload}});
    if(error)throw new Error(await edgeFunctionErrorMessage(error,data));
    if(!data?.ok)throw new Error(data?.error||"Licence verification operation failed");
    return data;
  }
  function licenceUpgradeCapacityRows(currentPlan={},targetPlan={}) {
    const rows=[
      ["Students","max_students","records"],["Teachers","max_teachers","records"],["System Administrators","max_system_admins","accounts"],["Guardians","max_guardians","accounts"],["Storage","max_storage_mb","MB"]
    ];
    return rows.map(([label,key,unit])=>({label,key,unit,from:currentPlan[key]??null,to:targetPlan[key]??null}));
  }
  function licenceUpgradePreviewHtml(currentPlan={},preview={}) {
    const target=preview.target_plan||{},currentFeatures=effectiveLicenseFeatureFlags(currentPlan.feature_flags||{}),targetFeatures=effectiveLicenseFeatureFlags(target.feature_flags||{});
    const added=Object.entries(targetFeatures).filter(([key,enabled])=>enabled===true&&currentFeatures[key]!==true).map(([key])=>key);
    const capacities=licenceUpgradeCapacityRows(currentPlan,target);
    const renewal=String(preview.authorization_type||"")==="renewal";
    return `<div class="upgrade-preview-stack">
      <div class="template-information success"><strong>${renewal?"Licence renewal":`${esc(featureFlagLabel(preview.from_plan_code||currentPlan.code||"Current"))} → ${esc(target.name||featureFlagLabel(preview.to_plan_code||target.code||"Upgraded plan"))}`}</strong><span>${renewal?"This authorization renews the current plan for a new approved coverage period.":"This authorization upgrades the plan and applies the approved coverage period."}</span><small>${esc(preview.license_period_label||"Licence period")} · ${esc(isoDate(preview.license_starts_at))} to ${esc(isoDate(preview.license_expires_at))} · ${esc(preview.license_grace_days??0)} grace days</small><small>Activation code expires ${esc(isoDateTime(preview.code_expires_at||preview.expires_at))}</small></div>
      <div class="table-wrap"><table><thead><tr><th>Capacity</th><th>Current</th><th>After upgrade</th></tr></thead><tbody>${capacities.map(item=>`<tr><td>${esc(item.label)}</td><td>${esc(capacityDisplayValue(item.from,item.unit))}</td><td><strong>${esc(capacityDisplayValue(item.to,item.unit))}</strong></td></tr>`).join("")}</tbody></table></div>
      <div><strong>Newly enabled features</strong>${added.length?`<div class="chip-grid" style="margin-top:8px">${added.map(key=>`<span class="chip success">${esc(featureFlagLabel(key))}</span>`).join("")}</div>`:`<p class="muted">No additional feature flags are required; this upgrade increases capacity or support entitlement.</p>`}</div>
    </div>`;
  }
  function openLicenceUpgradeActivation(currentPlan={}) {
    modal("Upgrade Licence Plan","Enter the one-time upgrade activation code issued specifically for this school installation. Multi-factor authentication is required.",`<form id="licenceUpgradeActivationForm" class="form-stack">
      <div class="template-information"><strong>Current plan: ${esc(currentPlan.name||featureFlagLabel(currentPlan.code||"Unknown"))}</strong><span>Supported paths are Starter → Professional, Starter → Enterprise, and Professional → Enterprise.</span><small>Renewals, expiry changes, and exceptional licence changes remain under Renew or Upgrade School Licence.</small></div>
      <label class="field"><span>Upgrade activation code</span><input id="licenceUpgradeCode" name="upgrade_code" maxlength="34" autocomplete="off" spellcheck="false" placeholder="RCE-UPG-XXXX-XXXX-XXXX-XXXX-XXXX" pattern="RCE-UPG-[A-Z2-9]{4}(-[A-Z2-9]{4}){4}" required><small>The code is installation-bound, single-use, and time-limited.</small></label>
      <div class="template-information warning"><strong>Security confirmation</strong><span>The code is verified by the central licence authority before any local entitlement changes. No student, report, staff, Storage, or school-setting data is modified.</span></div>
    </form>`,`<button class="button ghost" id="licenceUpgradeCancel" type="button">Cancel</button><button class="button primary" id="licenceUpgradeVerify" type="button">Verify upgrade</button>`,`medium`);
    byId("licenceUpgradeCancel").onclick=closeModal;
    const input=byId("licenceUpgradeCode");input.addEventListener("input",()=>{let value=input.value.toUpperCase().replace(/[^A-Z2-9]/g,"");if(value.startsWith("RCEUPG"))value=value.slice(6);else if(value.startsWith("RCE"))value=value.slice(3);const chunks=value.match(/.{1,4}/g)||[];input.value=`RCE-UPG-${chunks.slice(0,5).join("-")}`.replace(/-$/,"")});
    byId("licenceUpgradeVerify").onclick=async()=>{
      const form=byId("licenceUpgradeActivationForm");if(!form.reportValidity())return;
      const code=input.value.trim().toUpperCase(),button=byId("licenceUpgradeVerify");button.disabled=true;button.textContent="Verifying";
      try{
        const result=await invokeLicenseVerifier("preview_upgrade",{upgrade_code:code}),preview=result.preview||{};
        modal("Confirm Licence Upgrade",`${featureFlagLabel(preview.from_plan_code||currentPlan.code||"")} → ${preview.target_plan?.name||featureFlagLabel(preview.to_plan_code||"")}. Review the signed changes before activation.`,licenceUpgradePreviewHtml(currentPlan,preview),`<button class="button ghost" id="licenceUpgradeBack" type="button">Back</button><button class="button success" id="licenceUpgradeActivate" type="button">Activate ${esc(preview.target_plan?.name||featureFlagLabel(preview.to_plan_code||"upgrade"))}</button>`,`medium`);
        byId("licenceUpgradeBack").onclick=()=>openLicenceUpgradeActivation(currentPlan);
        byId("licenceUpgradeActivate").onclick=async()=>{const activate=byId("licenceUpgradeActivate");activate.disabled=true;activate.textContent="Activating securely";try{const activation=await invokeLicenseVerifier("activate_upgrade",{upgrade_code:code});state.schoolLicenseCapacity=null;state.workspace=null;await refreshGeneratedLicenseBinding(true).catch(()=>{});state.boot=await rpc("get_bootstrap_data");renderBrand();renderNav();closeModal();toast("Licence plan upgraded",`The signed ${activation.target_plan?.name||preview.target_plan?.name||featureFlagLabel(preview.to_plan_code||"")} entitlement is now active permanently for this installation.${activation.authority_finalize_pending?" Central finalization will reconcile on the next successful authority check.":""}`,activation.authority_finalize_pending?"warning":"success",11000);await renderSchoolLicenseCapacity(state.viewToken,true)}catch(error){toast("Licence upgrade not activated",friendlyError(error),"error",10000);await reportClientError(error,{source:"license_upgrade_activation"})}finally{if(activate){activate.disabled=false;activate.textContent=`Activate ${preview.target_plan?.name||featureFlagLabel(preview.to_plan_code||"upgrade")}`}}};
      }catch(error){toast("Upgrade code not verified",friendlyError(error),"error",9000);await reportClientError(error,{source:"license_upgrade_preview"})}finally{if(button){button.disabled=false;button.textContent="Verify upgrade"}}
    };
  }

  async function invokeSaasPlanUpgrade(action,upgradeCode) {
    const data=await invokeEdgeFunction("saas-plan-upgrade",{action,upgrade_code:upgradeCode});
    if(!data?.ok)throw new Error(data?.error||"Plan upgrade request failed");
    return data;
  }
  function formatSaasUpgradeCode(input) {
    let value=String(input.value||"").toUpperCase().replace(/[^A-Z2-9]/g,"");
    let prefix="LIC";
    if(value.startsWith("EDSUPG")){prefix="UPG";value=value.slice(6)}
    else if(value.startsWith("EDSLIC")){prefix="LIC";value=value.slice(6)}
    else if(value.startsWith("UPG")){prefix="UPG";value=value.slice(3)}
    else if(value.startsWith("LIC")){prefix="LIC";value=value.slice(3)}
    else if(value.startsWith("EDS"))value=value.slice(3);
    const chunks=value.match(/.{1,4}/g)||[];
    input.value=`EDS-${prefix}-${chunks.slice(0,4).join("-")}`.replace(/-$/g,"");
  }
  async function renderPlanUpgrade(token,force=false) {
    if(role()!=="system_admin")throw new Error("School System Administrator access required");
    if(force||!state.schoolLicenseCapacity)state.schoolLicenseCapacity=await rpc("get_school_license_capacity_console");
    if(token!==state.viewToken)return;
    const data=state.schoolLicenseCapacity||{},plan=data.plan||{},snapshot=data.snapshot||{},code=String(plan.code||"").toLowerCase(),isHighest=code==="enterprise";
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Renew or Upgrade Plan</h3><p>Activate a term-based renewal or higher Edusentia plan using a one-time code issued for this school.</p></div></div>
      <div class="grid two">
        <section class="panel pad"><div class="section-title"><div><h4>Current plan</h4><p>${esc(snapshot.tenant_code||CONFIG.tenantCode||"School workspace")}</p></div>${statusBadge(snapshot.computed_status||snapshot.status||"active")}</div>
          <div class="metric-row wrap"><div class="metric"><span>Plan</span><strong>${esc(plan.name||featureFlagLabel(code||"Unknown"))}</strong><small>Revision ${esc(plan.revision||snapshot.plan_revision||"—")}</small></div><div class="metric"><span>Licence</span><strong>${esc(snapshot.license_reference||"Active SaaS licence")}</strong><small>${esc(snapshot.project_ref||CONFIG.projectRef||"")}</small></div></div>
        </section>
        <section class="panel pad"><div class="section-title"><div><h4>How activation works</h4><p>Secure, tenant-bound, and auditable</p></div></div><div class="template-information"><strong>Manual code delivery</strong><span>The Platform Administrator may send the copied code through a normal WhatsApp or SMS message. Edusentia does not send messages or read your conversations.</span><small>The code is single-use, time-limited, and valid only for this school project.</small></div></section>
      </div>
      <section class="panel pad" style="margin-top:18px">
        ${CONFIG.generatedSchoolPackage?`<div class="section-title"><div><h4>Enter signed licence upgrade code</h4><p>This packaged installation uses the central signed-licence workflow.</p></div><button class="button primary" id="signedPlanUpgradeOpen" type="button">Enter upgrade code</button></div>`:`<form id="saasPlanUpgradeForm" class="form-stack"><div class="section-title"><div><h4>Enter licence activation code</h4><p>Use the current plan for renewal or an authorized higher plan for upgrade. Only the school System Administrator with MFA can complete this action.</p></div></div><label class="field"><span>Licence activation code</span><input id="saasPlanUpgradeCode" name="upgrade_code" maxlength="34" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="EDS-LIC-XXXX-XXXX-XXXX-XXXX" pattern="EDS-(UPG|LIC)-[A-Z2-9]{4}(-[A-Z2-9]{4}){3}" required><small>Review the authorized plan, coverage dates, and grace period before confirming activation.</small></label>${isHighest?`<div class="template-information success"><strong>Enterprise plan active</strong><span>Enterprise is the highest plan, but this school can still use a same-plan licence renewal code.</span></div>`:""}<div><button class="button primary" id="saasPlanUpgradePreview" type="submit">Verify activation code</button></div></form>`}
      </section>`;
    if(CONFIG.generatedSchoolPackage){byId("signedPlanUpgradeOpen").onclick=()=>openLicenceUpgradeActivation(plan);return}
    const form=byId("saasPlanUpgradeForm"),input=byId("saasPlanUpgradeCode");input.addEventListener("input",()=>formatSaasUpgradeCode(input));
    form.addEventListener("submit",async event=>{
      event.preventDefault();if(!form.reportValidity())return;
      const activationCode=input.value.trim().toUpperCase(),button=byId("saasPlanUpgradePreview");
      button.disabled=true;button.textContent="Verifying securely";
      try{
        const result=CONFIG.generatedSchoolPackage?await invokeLicenseVerifier("preview_upgrade",{upgrade_code:activationCode}):await invokeSaasPlanUpgrade("preview",activationCode),preview=result.preview||{},renewal=preview.authorization_type==="renewal";
        modal(renewal?"Confirm Licence Renewal":"Confirm Plan Upgrade",renewal?`${preview.license_period_label||"New licence period"} · ${isoDate(preview.license_starts_at)} to ${isoDate(preview.license_expires_at)}.`:`${featureFlagLabel(preview.from_plan_code||code)} → ${preview.target_plan?.name||featureFlagLabel(preview.to_plan_code||"")}.`,licenceUpgradePreviewHtml(plan,preview),`<button class="button ghost" id="saasPlanUpgradeCancel" type="button">Cancel</button><button class="button success" id="saasPlanUpgradeActivate" type="button">Activate licence</button>`,`medium`);
        byId("saasPlanUpgradeCancel").onclick=closeModal;
        byId("saasPlanUpgradeActivate").onclick=async()=>{
          const activate=byId("saasPlanUpgradeActivate");activate.disabled=true;activate.textContent="Activating securely";
          try{
            const activated=CONFIG.generatedSchoolPackage?await invokeLicenseVerifier("activate_upgrade",{upgrade_code:activationCode}):await invokeSaasPlanUpgrade("activate",activationCode);
            state.schoolLicenseCapacity=null;state.workspace=null;
            if(CONFIG.generatedSchoolPackage)await refreshGeneratedLicenseBinding(true).catch(()=>{});
            state.boot=await rpc("get_bootstrap_data");renderBrand();renderNav();closeModal();
            toast(renewal?"Licence renewed":"Plan upgraded",`${activated.target_plan?.name||preview.target_plan?.name||featureFlagLabel(preview.to_plan_code||"The authorized plan")} is active through ${isoDate(activated.license_expires_at||preview.license_expires_at)}.${activated.authority_finalize_pending?" Central status finalization will retry automatically.":""}`,activated.authority_finalize_pending?"warning":"success",11000);
            await renderPlanUpgrade(state.viewToken,true);
          }catch(error){toast("Licence not activated",friendlyError(error),"error",10000);await reportClientError(error,{source:"saas_plan_upgrade_activation"})}
          finally{if(activate){activate.disabled=false;activate.textContent="Activate licence"}}
        };
      }catch(error){toast("Activation code not verified",friendlyError(error),"error",9000);await reportClientError(error,{source:"saas_plan_upgrade_preview"})}
      finally{if(button){button.disabled=false;button.textContent="Verify activation code"}}
    });
  }

  async function renderSchoolLicenseCapacity(token,force=false) {
    if(role()!=="system_admin")throw new Error("School System Administrator access required");
    if(force||!state.schoolLicenseCapacity)state.schoolLicenseCapacity=await rpc("get_school_license_capacity_console");
    if(token!==state.viewToken)return;
    const data=state.schoolLicenseCapacity||{},snapshot=data.snapshot||{},plan=data.plan||{},capacity=Array.isArray(data.capacity)?data.capacity:[],features=effectiveLicenseFeatureFlags(data.feature_flags),storage=Array.isArray(data.storage_buckets)?data.storage_buckets:[],history=Array.isArray(data.verification_history)?data.verification_history:[];
    const status=String(snapshot.computed_status||"unknown"),accessMode=String(snapshot.access_mode||"unknown"),activeFeatures=Object.entries(features).filter(([,enabled])=>enabled===true),disabledFeatures=Object.entries(features).filter(([,enabled])=>enabled!==true);
    const expiryText=snapshot.expires_at?isoDateTime(snapshot.expires_at):status==="perpetual"||String(plan.billing_cycle||"")==="perpetual"?"No expiry":"Not specified";
    const daysRemaining=snapshot.days_remaining===null||snapshot.days_remaining===undefined?"—":number(snapshot.days_remaining);
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Licence and Capacity</h3><p>Signed entitlement, capacity, verification health, and secure plan-upgrade activation.</p></div><div class="page-actions"><button class="button secondary" id="licenseCapacityRefresh" type="button">Refresh status</button></div></div>
      <section class="panel pad">
        <div class="section-title"><div><h4>${esc(plan.name||plan.code||"School licence")}</h4><p>${esc(snapshot.license_reference||"No licence reference")}</p></div><div>${statusBadge(status)}</div></div>
        ${snapshot.warning?`<div class="template-information warning"><strong>Licence attention</strong><span>${esc(snapshot.warning)}</span></div>`:`<div class="template-information success"><strong>Licence status verified</strong><span>The signed entitlement is verified. Plan-only upgrades may be activated below with an authority-issued one-time code; renewals and other licence changes continue through the signed replacement workflow.</span></div>`}
        <div class="metric-row wrap" style="margin-top:14px">
          <div class="metric"><span>Access mode</span><strong>${esc(licenseStatusLabel(accessMode))}</strong><small>${snapshot.write_allowed===false?"Writes restricted":"Writes permitted"}</small></div>
          <div class="metric"><span>Issue date</span><strong>${esc(isoDate(snapshot.issued_on))}</strong><small>Activated ${esc(isoDateTime(snapshot.activated_at))}</small></div>
          <div class="metric"><span>Expiry</span><strong>${esc(expiryText)}</strong><small>${esc(daysRemaining)} days remaining</small></div>
          <div class="metric"><span>Plan revision</span><strong>${esc(String(plan.revision||snapshot.plan_revision||"—"))}</strong><small>${esc(String(plan.billing_cycle||"custom"))} billing</small></div>
        </div>
      </section>
      ${CONFIG.generatedSchoolPackage&&["starter","professional"].includes(String(plan.code||"").toLowerCase())?`<section class="panel pad" style="margin-top:18px"><div class="section-title"><div><h4>Upgrade Activation</h4><p>Apply a Platform-authorized plan upgrade without manually replacing the school licence package.</p></div><button class="button primary" id="licenseUpgradeOpen" type="button">Enter upgrade code</button></div><div class="template-information"><strong>Secure one-time activation</strong><span>The code is bound to this licence, project, tenant, and installation. After verification, the newly signed plan features and capacity become the authoritative entitlement immediately.</span><small>Requires an active System Administrator session with MFA (AAL2). Supported upgrades never reduce capacity or remove enabled features.</small></div></section>`:String(plan.code||"").toLowerCase()==="enterprise"?`<section class="panel pad" style="margin-top:18px"><div class="template-information success"><strong>Highest plan active</strong><span>This school is already on the Enterprise plan. No higher code-based plan upgrade is available.</span></div></section>`:""}
      <section class="panel pad" style="margin-top:18px"><div class="section-title"><div><h4>Capacity usage</h4><p>Current active usage against the signed entitlement. Unlimited limits remain unrestricted.</p></div></div>
        ${capacity.length?`<div class="license-capacity-grid">${capacity.map(item=>{const stateInfo=capacityStateLabel(item.used,item.limit),percent=capacityPercent(item.used,item.limit),remaining=item.limit===null||item.limit===undefined?"Unlimited":Math.max(Number(item.limit||0)-Number(item.used||0),0);return `<article class="license-capacity-card"><header><div><strong>${esc(item.label||item.key)}</strong><small>${esc(item.unit||"records")}</small></div><span class="status ${attr(stateInfo.className)}">${esc(stateInfo.label)}</span></header><div class="license-capacity-value"><b>${esc(capacityDisplayValue(item.used,item.unit))}</b><span>of ${esc(capacityDisplayValue(item.limit,item.unit))}</span></div>${Number.isFinite(Number(item.limit))?`<div class="bar-track" aria-label="${attr(number(percent,1))}% used"><span style="width:${percent}%"></span></div><small>${esc(capacityDisplayValue(remaining,item.unit))} remaining • ${number(percent,1)}% used</small>`:`<div class="bar-track"><span style="width:0%"></span></div><small>No signed maximum</small>`}</article>`}).join("")}</div>`:emptyState("No capacity data is available")}
      </section>
      <div class="grid two" style="margin-top:18px">
        <section class="panel pad"><div class="section-title"><div><h4>Verification and binding</h4><p>Cryptographic and central-authority checks for this installation.</p></div></div>
          <div class="detail-grid">
            <div><span>Signature</span><strong>${esc(licenseStatusLabel(snapshot.signature_status||"unknown"))}</strong></div>
            <div><span>Authority</span><strong>${esc(licenseStatusLabel(snapshot.authority_status||"unknown"))}</strong></div>
            <div><span>Authority last success</span><strong>${esc(isoDateTime(snapshot.authority_last_success_at))}</strong></div>
            <div><span>Binding</span><strong>${snapshot.binding_verified===true?"Verified":"Attention required"}</strong></div>
            <div><span>Tenant code</span><strong>${esc(snapshot.tenant_code||CONFIG.tenantCode||"—")}</strong></div>
            <div><span>Project reference</span><strong>${esc(snapshot.project_ref||CONFIG.projectRef||"—")}</strong></div>
            <div><span>Package ID</span><strong><code>${esc(snapshot.package_id||"—")}</code></strong></div>
            <div><span>Signing key</span><strong><code>${esc(snapshot.signature_key_id||"—")}</code></strong></div>
          </div>
        </section>
        <section class="panel pad"><div class="section-title"><div><h4>Enabled features</h4><p>Features included in the current signed plan revision.</p></div></div>
          ${activeFeatures.length?`<div class="chip-grid">${activeFeatures.map(([key])=>`<span class="chip success">${esc(featureFlagLabel(key))}</span>`).join("")}</div>`:emptyState("No feature flags are enabled")}
          ${disabledFeatures.length?`<details class="license-disabled-features"><summary>${number(disabledFeatures.length)} unavailable feature${disabledFeatures.length===1?"":"s"}</summary><div class="chip-grid">${disabledFeatures.map(([key])=>`<span class="chip">${esc(featureFlagLabel(key))}</span>`).join("")}</div></details>`:""}
        </section>
      </div>
      <div class="grid two" style="margin-top:18px">
        <section class="panel pad"><div class="section-title"><div><h4>Private Storage usage</h4><p>Object count and measured size by licensed school bucket.</p></div></div>${storage.length?`<div class="table-wrap"><table><thead><tr><th>Bucket</th><th>Objects</th><th>Usage</th></tr></thead><tbody>${storage.map(item=>`<tr><td>${esc(item.bucket_id)}</td><td>${number(item.object_count)}</td><td>${number(item.storage_mb,2)} MB</td></tr>`).join("")}</tbody></table></div>`:emptyState("No stored objects yet")}</section>
        <section class="panel pad"><div class="section-title"><div><h4>Recent verification history</h4><p>The latest licence checks recorded by this school project.</p></div></div>${history.length?`<div class="table-wrap"><table><thead><tr><th>Checked</th><th>Status</th><th>Access</th><th>Source</th></tr></thead><tbody>${history.slice(0,10).map(item=>`<tr><td>${esc(isoDateTime(item.created_at))}</td><td>${statusBadge(item.computed_status)}</td><td>${esc(licenseStatusLabel(item.access_mode))}</td><td>${esc(item.verification_source||"—")}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No verification history recorded yet")}</section>
      </div>`;
    byId("licenseCapacityRefresh").onclick=async()=>{const button=byId("licenseCapacityRefresh");button.disabled=true;button.textContent="Refreshing";try{if(CONFIG.generatedSchoolPackage)await refreshGeneratedLicenseBinding(true).catch(()=>{});state.schoolLicenseCapacity=null;await renderSchoolLicenseCapacity(state.viewToken,true);toast("Licence status refreshed")}catch(error){toast("Licence status not refreshed",friendlyError(error),"error",8000)}finally{if(button){button.disabled=false;button.textContent="Refresh status"}}};
    if(byId("licenseUpgradeOpen"))byId("licenseUpgradeOpen").onclick=()=>openLicenceUpgradeActivation(plan);
  }

  // ---------------------------------------------------------------------------
  // Professional School Prospectus Management r14
  // Academic-year, class-range fees, requirements, transport, policy notes,
  // immutable publication revisions, professional A4 PDF, and archive lifecycle.
  // ---------------------------------------------------------------------------
  const PROSPECTUS_RANGES=Object.freeze([
    {value:"early_years",label:"Creche to Kindergarten"},
    {value:"basic_1_6",label:"Basic 1 to Basic 6"},
    {value:"basic_7_9",label:"Basic 7 to Basic 9"}
  ]);
  const PROSPECTUS_SECTION_TYPES=Object.freeze([
    {value:"main_fees",label:"Main Fees"},{value:"other_items",label:"Other Items (One-off / Per Term)"},
    {value:"parent_provided",label:"To Be Provided by Parent"},{value:"transportation",label:"Transportation"},
    {value:"policies",label:"Important Policy Notes"},{value:"custom",label:"Custom Section"}
  ]);
  const PROSPECTUS_CHARGE_BASES=Object.freeze([
    {value:"free",label:"Free"},{value:"one_off",label:"One-off"},{value:"per_day",label:"Per Day"},
    {value:"per_week",label:"Per Week"},{value:"per_month",label:"Per Month"},{value:"per_term",label:"Per Term"},
    {value:"per_academic_year",label:"Per Academic Year"},{value:"per_occurrence",label:"Per Occurrence"},
    {value:"optional",label:"Optional"},{value:"parent_provides",label:"Parent Provides"},{value:"informational",label:"Information Only"}
  ]);
  function prospectusRangeLabel(value){return PROSPECTUS_RANGES.find(item=>item.value===value)?.label||String(value||"Prospectus")}
  function prospectusSectionTypeLabel(value){return PROSPECTUS_SECTION_TYPES.find(item=>item.value===value)?.label||String(value||"Section").replaceAll("_"," ")}
  function prospectusBasisLabel(value){return PROSPECTUS_CHARGE_BASES.find(item=>item.value===value)?.label||String(value||"").replaceAll("_"," ")}
  function prospectusRecord(snapshot){return snapshot?.prospectus||{}}
  function prospectusCurrency(snapshot){return String(prospectusRecord(snapshot).currency_code||"GHS")}
  function prospectusNumberOrNull(value){if(value===null||value===undefined||String(value).trim()==="")return null;const n=Number(value);return Number.isFinite(n)?n:null}
  function prospectusMoney(value,currency="GHS"){const n=prospectusNumberOrNull(value);if(n===null)return "";return `${currency} ${n.toLocaleString("en-GH",{minimumFractionDigits:2,maximumFractionDigits:2})}`}
  function prospectusAmountLabel(item,currency){
    if(item.charge_basis==="free")return "FREE";
    if(item.charge_basis==="parent_provides")return prospectusNumberOrNull(item.quantity)!==null?`${number(item.quantity)} ${item.unit||""}`.trim():(item.unit||"Parent provides");
    const amount=prospectusNumberOrNull(item.amount);
    if(item.charge_basis==="informational"&&amount===null)return "—";
    if(amount===null)return item.charge_basis==="optional"?"Optional":"—";
    return prospectusMoney(amount,currency);
  }
  function prospectusCalculatedAmount(item){
    if(!item?.include_in_total)return null;const amount=prospectusNumberOrNull(item.amount);if(amount===null)return null;
    if(["free","parent_provides","informational"].includes(item.charge_basis))return null;
    if(["per_day","per_week","per_month","per_occurrence"].includes(item.charge_basis)){const units=prospectusNumberOrNull(item.calculation_units);if(units===null||units<=0)return null;return amount*units}
    return amount;
  }
  function prospectusSubtotal(section){return (section?.items||[]).reduce((sum,item)=>sum+(prospectusCalculatedAmount(item)||0),0)}
  function prospectusStatusBadge(snapshot){return statusBadge(prospectusRecord(snapshot).status||"draft")}
  function prospectusOptions(items,value=""){return items.map(item=>`<option value="${attr(item.value)}" ${String(item.value)===String(value)?"selected":""}>${esc(item.label)}</option>`).join("")}
  function prospectusItemCount(snapshot){return (snapshot?.sections||[]).reduce((sum,section)=>sum+(section.items||[]).length,0)}
  function prospectusHasUncalculatedRates(snapshot){return (snapshot?.sections||[]).some(section=>(section.items||[]).some(item=>["per_day","per_week","per_month","per_occurrence"].includes(item.charge_basis)&&prospectusNumberOrNull(item.amount)!==null&&(prospectusNumberOrNull(item.calculation_units)===null||prospectusNumberOrNull(item.calculation_units)<=0)))}

  async function renderSchoolProspectus(token,force=false){
    const years=state.boot?.academic_years||[];if(!years.length){byId("content").innerHTML=emptyState("Academic year required","Create an academic year before creating a school prospectus.");return}
    const yearId=state.prospectusYear||activeYear()?.id||years[0].id;state.prospectusYear=yearId;
    if(force||!state.prospectusConsole||state.prospectusConsole.academic_year_id!==yearId)state.prospectusConsole=await rpc("get_school_prospectus_console",{target_academic_year_id:yearId});
    if(token!==state.viewToken)return;const data=state.prospectusConsole||{},prospectuses=data.prospectuses||[],map=new Map(prospectuses.map(item=>[prospectusRecord(item).class_range,item])),year=years.find(item=>item.id===yearId)||{};
    byId("content").innerHTML=`<div class="page-head"><div><h3>School Prospectus</h3><p>Academic-year fees, requirements, transportation, policies, publication revisions, and professional PDF output</p></div><div class="button-row"><button class="button secondary" id="prospectusCompletePdf" ${prospectuses.length?"":"disabled"}>Download complete prospectus</button><button class="button primary" id="prospectusCreate" ${prospectuses.length>=PROSPECTUS_RANGES.length?"disabled":""}>Create prospectus</button></div></div>
      <section class="panel pad prospectus-toolbar"><label class="field"><span>Academic year</span><select id="prospectusYear">${years.map(y=>`<option value="${attr(y.id)}" ${y.id===yearId?"selected":""}>${esc(y.name)}</option>`).join("")}</select></label><div class="prospectus-summary"><strong>${esc(year.name||"")}</strong><span>${prospectuses.length} of ${PROSPECTUS_RANGES.length} class-range prospectuses configured</span></div></section>
      <div class="grid three prospectus-range-grid">${PROSPECTUS_RANGES.map(range=>{const snap=map.get(range.value),p=prospectusRecord(snap),items=snap?prospectusItemCount(snap):0;return `<section class="panel prospectus-range-card"><div class="prospectus-card-head"><div><span class="eyebrow">${esc(range.label)}</span><h3>${esc(p.title||`${range.label} Prospectus`)}</h3></div>${snap?prospectusStatusBadge(snap):'<span class="status draft">Not created</span>'}</div>${snap?`<div class="metric-row wrap">${maturityMetric("Items",items)}${maturityMetric("Revision",p.revision_no?`R${p.revision_no}`:"Draft")}${maturityMetric("Effective",p.effective_date?isoDate(p.effective_date):"Not set")}</div><p class="help-text">${esc(p.general_notes||"Manage fees, items, transport rates and policy notes for this class range.")}</p><div class="button-row wrap"><button class="button primary" data-prospectus-edit="${attr(p.id)}">Manage</button><button class="button secondary" data-prospectus-preview="${attr(p.id)}">Preview</button><button class="button outline" data-prospectus-pdf="${attr(p.id)}">PDF</button><button class="button ghost" data-prospectus-copy="${attr(p.id)}">Copy year</button>${p.status==="draft"?`<button class="button primary" data-prospectus-publish="${attr(p.id)}">Publish</button>`:""}${p.status!=="archived"?`<button class="button warning" data-prospectus-archive="${attr(p.id)}">Archive</button>`:""}${p.status==="draft"&&Number(p.revision_no||0)===0?`<button class="button danger" data-prospectus-delete="${attr(p.id)}">Delete draft</button>`:""}</div>`:`<div class="prospectus-empty-card"><span>Not configured for ${esc(year.name||"this academic year")}.</span><button class="button primary" data-prospectus-create-range="${attr(range.value)}">Create ${esc(range.label)}</button></div>`}</section>`}).join("")}</div>
      <section class="panel pad prospectus-guidance"><h4>Professional calculation rules</h4><div class="grid three"><div><strong>Fixed charges</strong><p>One-off, per-term and per-academic-year amounts can be included directly in calculated subtotals.</p></div><div><strong>Recurring rates</strong><p>Per-day, weekly, monthly and occurrence-based fees are excluded until calculation units are supplied, preventing misleading totals.</p></div><div><strong>Publication history</strong><p>Every publication creates an immutable revision snapshot. Later edits return the working copy to Draft without changing earlier revisions.</p></div></div></section>`;
    byId("prospectusYear").onchange=()=>{state.prospectusYear=byId("prospectusYear").value;state.prospectusConsole=null;renderSchoolProspectus(state.viewToken,true)};
    byId("prospectusCreate").onclick=()=>openProspectusCreate();$$('[data-prospectus-create-range]').forEach(b=>b.onclick=()=>openProspectusCreate(b.dataset.prospectusCreateRange));
    const find=id=>prospectuses.find(item=>prospectusRecord(item).id===id);
    $$('[data-prospectus-edit]').forEach(b=>b.onclick=()=>openProspectusEditor(find(b.dataset.prospectusEdit)));
    $$('[data-prospectus-preview]').forEach(b=>b.onclick=()=>previewSchoolProspectus(find(b.dataset.prospectusPreview)));
    $$('[data-prospectus-pdf]').forEach(b=>b.onclick=()=>downloadSchoolProspectusPdf(find(b.dataset.prospectusPdf)));
    $$('[data-prospectus-copy]').forEach(b=>b.onclick=()=>copySchoolProspectus(find(b.dataset.prospectusCopy)));
    $$('[data-prospectus-publish]').forEach(b=>b.onclick=()=>publishSchoolProspectus(find(b.dataset.prospectusPublish)));
    $$('[data-prospectus-archive]').forEach(b=>b.onclick=()=>archiveSchoolProspectus(find(b.dataset.prospectusArchive)));
    $$('[data-prospectus-delete]').forEach(b=>b.onclick=()=>deleteSchoolProspectus(find(b.dataset.prospectusDelete)));
    byId("prospectusCompletePdf").onclick=async()=>{setLoading(true);try{downloadBlob(`${safeArchiveSegment(year.name||"academic-year")}-complete-school-prospectus.pdf`,await createSchoolProspectusPdf(prospectuses));toast("Complete prospectus downloaded",`${prospectuses.length} class-range prospectus${prospectuses.length===1?"":"es"} included.`)}catch(error){toast("Prospectus PDF not created",friendlyError(error),"error",9000)}finally{setLoading(false)}};
  }

  function openProspectusCreate(rangeCode=""){
    const years=state.boot?.academic_years||[],yearId=state.prospectusYear||activeYear()?.id||years[0]?.id||"",existing=new Set((state.prospectusConsole?.prospectuses||[]).map(item=>prospectusRecord(item).class_range));
    modal("Create School Prospectus","Create an academic-year prospectus for one school class range.",`<form id="prospectusCreateForm" class="form-grid"><label class="field"><span>Academic year</span><select name="academic_year_id" required>${years.map(y=>`<option value="${attr(y.id)}" ${y.id===yearId?"selected":""}>${esc(y.name)}</option>`).join("")}</select></label><label class="field"><span>Class range</span><select name="class_range" required><option value="">Select range</option>${PROSPECTUS_RANGES.filter(r=>!existing.has(r.value)||r.value===rangeCode).map(r=>`<option value="${r.value}" ${r.value===rangeCode?"selected":""}>${esc(r.label)}</option>`).join("")}</select></label><label class="field full"><span>Document title</span><input name="title" value="School Prospectus" maxlength="180" required></label><label class="field"><span>Currency</span><input name="currency_code" value="GHS" maxlength="3" required></label><label class="field"><span>Effective date</span><input type="date" name="effective_date"></label><label class="field full"><span>General note</span><textarea name="general_notes" rows="3" maxlength="5000" placeholder="Optional note shown near the prospectus heading"></textarea></label><div class="template-information full"><strong>Standard professional structure included</strong><span>Main Fees, Other Items, Parent-Provided Items, Transportation and Important Policy Notes are created automatically. You can edit, reorder, remove or add custom sections.</span></div></form>`,`<button class="button ghost" id="prospectusCreateCancel">Cancel</button><button class="button primary" id="prospectusCreateSave">Create prospectus</button>`,`wide`);
    byId("prospectusCreateCancel").onclick=closeModal;byId("prospectusCreateSave").onclick=async()=>{const button=byId("prospectusCreateSave"),values=formObject(byId("prospectusCreateForm"));button.disabled=true;try{const snap=await rpc("save_school_prospectus",{payload:values});closeModal();state.prospectusYear=values.academic_year_id;state.prospectusConsole=null;await renderSchoolProspectus(state.viewToken,true);openProspectusEditor(snap);toast("Prospectus created","Standard sections are ready for fees, requirements, transport and policy information.")}catch(error){toast("Prospectus not created",friendlyError(error),"error",9000)}finally{button.disabled=false}};
  }

  function prospectusEditorSectionHtml(section,currency){const subtotal=prospectusSubtotal(section),items=section.items||[];return `<section class="prospectus-editor-section"><div class="prospectus-section-head"><div><span class="eyebrow">${esc(prospectusSectionTypeLabel(section.section_type))}</span><h4>${esc(section.title)}</h4>${section.instructions?`<p>${esc(section.instructions)}</p>`:""}</div><div class="button-row compact"><button class="button ghost small" data-prospectus-section-edit="${attr(section.id)}">Edit section</button><button class="button primary small" data-prospectus-item-add="${attr(section.id)}">Add item</button><button class="button danger small" data-prospectus-section-delete="${attr(section.id)}">Remove</button></div></div>${items.length?`<div class="table-wrap"><table><thead><tr><th>Item</th><th>Amount / Quantity</th><th>Basis</th><th>Calculation</th><th>Notes</th><th></th></tr></thead><tbody>${items.map(item=>`<tr><td><strong>${esc(item.item_name)}</strong>${item.description?`<br><small>${esc(item.description)}</small>`:""}</td><td>${esc(prospectusAmountLabel(item,currency))}${item.quantity&&item.charge_basis!=="parent_provides"?`<br><small>Qty ${number(item.quantity)} ${esc(item.unit||"")}</small>`:""}</td><td>${esc(prospectusBasisLabel(item.charge_basis))}${item.required===false?`<br><small>Optional</small>`:""}</td><td>${prospectusCalculatedAmount(item)!=null?esc(prospectusMoney(prospectusCalculatedAmount(item),currency)):item.amount&&["per_day","per_week","per_month","per_occurrence"].includes(item.charge_basis)?`<small>Rate only${item.calculation_units?` × ${number(item.calculation_units)}`:""}</small>`:"—"}</td><td>${esc(item.notes||"—")}</td><td><div class="button-row compact"><button class="button ghost small" data-prospectus-item-edit="${attr(item.id)}" data-section-id="${attr(section.id)}">Edit</button><button class="button danger small" data-prospectus-item-delete="${attr(item.id)}">Remove</button></div></td></tr>`).join("")}</tbody></table></div>${subtotal>0?`<div class="prospectus-subtotal"><span>Calculated subtotal</span><strong>${esc(prospectusMoney(subtotal,currency))}</strong></div>`:""}`:`<div class="empty compact"><strong>No items</strong><span>Add the school requirements for this section.</span></div>`}</section>`}

  async function openProspectusEditor(snapshot){if(!snapshot)return;const p=prospectusRecord(snapshot),currency=prospectusCurrency(snapshot),history=snapshot.revision_history||[];
    modal(`${prospectusRangeLabel(p.class_range)} Prospectus`,`Manage fees, requirements, transportation, policies and publication revisions.`,`<div class="prospectus-editor"><section class="panel pad"><div class="section-title"><div><h4>Document details</h4><p>${prospectusStatusBadge(snapshot)} ${p.revision_no?`• Published revision R${number(p.revision_no)}`:"• Never published"}</p></div><div class="button-row"><button class="button secondary" id="prospectusEditorPreview">Preview</button><button class="button outline" id="prospectusEditorPdf">PDF</button>${p.status==="draft"?`<button class="button primary" id="prospectusEditorPublish">Publish</button>`:""}</div></div><form id="prospectusMetaForm" class="form-grid"><input type="hidden" name="id" value="${attr(p.id)}"><input type="hidden" name="academic_year_id" value="${attr(snapshot.academic_year?.id||p.academic_year_id||state.prospectusYear)}"><label class="field"><span>Class range</span><select name="class_range">${prospectusOptions(PROSPECTUS_RANGES,p.class_range)}</select></label><label class="field"><span>Currency</span><input name="currency_code" maxlength="3" value="${attr(p.currency_code||"GHS")}"></label><label class="field full"><span>Title</span><input name="title" maxlength="180" value="${attr(p.title||"School Prospectus")}"></label><label class="field"><span>Effective date</span><input type="date" name="effective_date" value="${attr(p.effective_date||"")}"></label><label class="field"><span>Academic year</span><input value="${attr(snapshot.academic_year?.name||"")}" disabled></label><label class="field full"><span>General notes</span><textarea name="general_notes" rows="3" maxlength="5000">${esc(p.general_notes||"")}</textarea></label><input type="hidden" name="updated_at" value="${attr(p.updated_at||"")}"><div class="field full"><button class="button primary" id="prospectusMetaSave" type="button">Save document details</button></div></form></section><section class="panel pad"><div class="section-title"><div><h4>Prospectus sections</h4><p>Add, edit, remove and organize fees, supplied items, parent requirements, transport rates and policies.</p></div><button class="button primary" id="prospectusAddSection">Add custom section</button></div><div class="prospectus-section-stack">${(snapshot.sections||[]).map(section=>prospectusEditorSectionHtml(section,currency)).join("")||emptyState("No prospectus sections")}</div></section>${history.length?`<section class="panel pad"><div class="section-title"><h4>Immutable publication history</h4></div><div class="table-wrap"><table><thead><tr><th>Revision</th><th>Published</th><th>Reason</th></tr></thead><tbody>${history.map(r=>`<tr><td><strong>R${number(r.revision_no)}</strong></td><td>${isoDateTime(r.published_at)}</td><td>${esc(r.reason||"Initial publication")}</td></tr>`).join("")}</tbody></table></div></section>`:""}</div>`,`<button class="button ghost" id="prospectusEditorClose">Close</button>`,`wide`);
    byId("prospectusEditorClose").onclick=closeModal;byId("prospectusEditorPreview").onclick=()=>previewSchoolProspectus(snapshot);byId("prospectusEditorPdf").onclick=()=>downloadSchoolProspectusPdf(snapshot);byId("prospectusEditorPublish")?.addEventListener("click",()=>publishSchoolProspectus(snapshot,true));
    byId("prospectusMetaSave").onclick=async()=>{const b=byId("prospectusMetaSave"),values=formObject(byId("prospectusMetaForm"));b.disabled=true;try{await rpc("save_school_prospectus",{payload:values});toast("Prospectus updated");await reloadProspectusEditor(p.id)}catch(error){toast("Prospectus not updated",friendlyError(error),"error",9000)}finally{b.disabled=false}};
    byId("prospectusAddSection").onclick=()=>openProspectusSectionEditor(p.id,null);const sectionById=id=>(snapshot.sections||[]).find(s=>s.id===id);$$('[data-prospectus-section-edit]').forEach(b=>b.onclick=()=>openProspectusSectionEditor(p.id,sectionById(b.dataset.prospectusSectionEdit)));$$('[data-prospectus-item-add]').forEach(b=>b.onclick=()=>openProspectusItemEditor(sectionById(b.dataset.prospectusItemAdd),null));$$('[data-prospectus-item-edit]').forEach(b=>b.onclick=()=>{const section=sectionById(b.dataset.sectionId),item=(section?.items||[]).find(i=>i.id===b.dataset.prospectusItemEdit);openProspectusItemEditor(section,item)});$$('[data-prospectus-item-delete]').forEach(b=>b.onclick=()=>removeProspectusItem(p.id,b.dataset.prospectusItemDelete));$$('[data-prospectus-section-delete]').forEach(b=>b.onclick=()=>removeProspectusSection(p.id,b.dataset.prospectusSectionDelete));
  }
  async function reloadProspectusEditor(id){closeModal();state.prospectusConsole=null;await renderSchoolProspectus(state.viewToken,true);const snap=(state.prospectusConsole?.prospectuses||[]).find(item=>prospectusRecord(item).id===id);if(snap)openProspectusEditor(snap)}

  function openProspectusSectionEditor(prospectusId,section){modal(section?"Edit Prospectus Section":"Add Prospectus Section","Organize prospectus information into clear printable sections.",`<form id="prospectusSectionForm" class="form-grid"><input type="hidden" name="id" value="${attr(section?.id||"")}"><input type="hidden" name="prospectus_id" value="${attr(prospectusId)}"><label class="field"><span>Section type</span><select name="section_type">${prospectusOptions(PROSPECTUS_SECTION_TYPES,section?.section_type||"custom")}</select></label><label class="field"><span>Display order</span><input type="number" name="display_order" min="0" max="10000" value="${attr(section?.display_order??100)}"></label><label class="field full"><span>Section title</span><input name="title" maxlength="180" value="${attr(section?.title||"")}" required></label><label class="field full"><span>Instructions / introductory note</span><textarea name="instructions" rows="3" maxlength="3000">${esc(section?.instructions||"")}</textarea></label></form>`,`<button class="button ghost" id="prospectusSectionCancel">Cancel</button><button class="button primary" id="prospectusSectionSave">Save section</button>`);byId("prospectusSectionCancel").onclick=closeModal;byId("prospectusSectionSave").onclick=async()=>{const b=byId("prospectusSectionSave"),values=formObject(byId("prospectusSectionForm"));b.disabled=true;try{await rpc("save_school_prospectus_section",{payload:values});toast("Prospectus section saved");await reloadProspectusEditor(prospectusId)}catch(error){toast("Section not saved",friendlyError(error),"error",8000)}finally{b.disabled=false}}}

  function openProspectusItemEditor(section,item){if(!section)return;const parentId=section.prospectus_id||prospectusRecord((state.prospectusConsole?.prospectuses||[]).find(s=>(s.sections||[]).some(x=>x.id===section.id)))?.id||"",basis=item?.charge_basis||(section.section_type==="parent_provided"?"parent_provides":section.section_type==="transportation"?"per_day":section.section_type==="policies"?"informational":"per_term");modal(item?"Edit Prospectus Item":"Add Prospectus Item","Configure the item, amount or quantity, charging basis and calculation behavior.",`<form id="prospectusItemForm" class="form-grid"><input type="hidden" name="id" value="${attr(item?.id||"")}"><input type="hidden" name="section_id" value="${attr(section.id)}"><label class="field full"><span>Item / description</span><input name="item_name" maxlength="220" value="${attr(item?.item_name||"")}" required></label><label class="field full"><span>Additional description</span><textarea name="description" rows="2" maxlength="2000">${esc(item?.description||"")}</textarea></label><label class="field"><span>Amount</span><input type="number" step="0.01" min="0" name="amount" value="${attr(item?.amount??"")}" placeholder="e.g. 435.00"></label><label class="field"><span>Charging basis</span><select name="charge_basis">${prospectusOptions(PROSPECTUS_CHARGE_BASES,basis)}</select></label><label class="field"><span>Quantity</span><input type="number" step="0.01" min="0.01" name="quantity" value="${attr(item?.quantity??"")}" placeholder="e.g. 4"></label><label class="field"><span>Unit</span><input name="unit" maxlength="80" value="${attr(item?.unit||"")}" placeholder="piece, bar, roll, set"></label><label class="field"><span>Calculation units</span><input type="number" step="0.01" min="0.01" name="calculation_units" value="${attr(item?.calculation_units??"")}" placeholder="e.g. 60 feeding days"></label><label class="field"><span>Display order</span><input type="number" min="0" max="10000" name="display_order" value="${attr(item?.display_order??100)}"></label><label class="check-field"><input type="checkbox" name="include_in_total" ${item?item.include_in_total!==false:!["per_day","per_week","per_month","per_occurrence","parent_provides","free","informational","optional"].includes(basis)?"checked":""}><span>Include in calculated subtotal</span></label><label class="check-field"><input type="checkbox" name="required" ${item?.required===false?"":"checked"}><span>Required item / charge</span></label><label class="field full"><span>Notes</span><textarea name="notes" rows="2" maxlength="2000">${esc(item?.notes||"")}</textarea></label><div class="template-information full"><strong>Recurring-rate protection</strong><span>Per-day, weekly, monthly and per-occurrence rates are excluded from calculated totals until Calculation Units are supplied. This prevents a daily fee from appearing as a complete term fee.</span></div></form>`,`<button class="button ghost" id="prospectusItemCancel">Cancel</button><button class="button primary" id="prospectusItemSave">Save item</button>`,`wide`);const form=byId("prospectusItemForm"),basisSelect=form.elements.charge_basis;const normalize=()=>{const k=basisSelect.value;if(["free","parent_provides","informational"].includes(k)){form.elements.amount.value=k==="free"?"":form.elements.amount.value;form.elements.include_in_total.checked=false}if(["per_day","per_week","per_month","per_occurrence"].includes(k)&&!form.elements.calculation_units.value)form.elements.include_in_total.checked=false};basisSelect.onchange=normalize;normalize();byId("prospectusItemCancel").onclick=closeModal;byId("prospectusItemSave").onclick=async()=>{const b=byId("prospectusItemSave"),values=formObject(form);values.include_in_total=form.elements.include_in_total.checked;values.required=form.elements.required.checked;b.disabled=true;try{await rpc("save_school_prospectus_item",{payload:values});toast("Prospectus item saved");await reloadProspectusEditor(parentId)}catch(error){toast("Item not saved",friendlyError(error),"error",9000)}finally{b.disabled=false}}}

  async function removeProspectusItem(prospectusId,itemId){if(!await confirmAction("Remove prospectus item","This removes the item from the current working prospectus. Published revisions already issued remain unchanged.","Remove",true))return;try{await rpc("delete_school_prospectus_item",{target_item_id:itemId});toast("Prospectus item removed");await reloadProspectusEditor(prospectusId)}catch(error){toast("Item not removed",friendlyError(error),"error",8000)}}
  async function removeProspectusSection(prospectusId,sectionId){if(!await confirmAction("Remove prospectus section","All items in this working section will be removed. Earlier published revision snapshots remain unchanged.","Remove section",true))return;try{await rpc("delete_school_prospectus_section",{target_section_id:sectionId});toast("Prospectus section removed");await reloadProspectusEditor(prospectusId)}catch(error){toast("Section not removed",friendlyError(error),"error",8000)}}

  async function publishSchoolProspectus(snapshot,fromEditor=false){const p=prospectusRecord(snapshot),reason=window.prompt(p.revision_no?"Revision reason (required for a clear audit trail):":"Publication note (optional):",p.revision_no?"Updated school prospectus":"Initial publication");if(reason===null)return;if(p.revision_no&&String(reason).trim().length<3){toast("Publication reason required","Enter a short reason describing this prospectus revision.","error");return}if(!await confirmAction("Publish School Prospectus",`Publish ${prospectusRangeLabel(p.class_range)} for ${snapshot.academic_year?.name||"this academic year"} as revision R${Number(p.revision_no||0)+1}? The publication snapshot will be preserved permanently.`,"Publish"))return;setLoading(true);try{await rpc("publish_school_prospectus",{target_prospectus_id:p.id,reason_text:String(reason||"").trim()});toast("Prospectus published",`Revision R${Number(p.revision_no||0)+1} is now the official published snapshot.`);state.prospectusConsole=null;if(fromEditor)closeModal();await renderSchoolProspectus(state.viewToken,true)}catch(error){toast("Prospectus not published",friendlyError(error),"error",9000)}finally{setLoading(false)}}
  async function archiveSchoolProspectus(snapshot){const p=prospectusRecord(snapshot);if(!await confirmAction("Archive prospectus",`Archive ${prospectusRangeLabel(p.class_range)}? Historical publication revisions remain available for audit and backup.`,"Archive"))return;try{await rpc("archive_school_prospectus",{target_prospectus_id:p.id,reason_text:"Archived by System Administrator"});state.prospectusConsole=null;toast("Prospectus archived");await renderSchoolProspectus(state.viewToken,true)}catch(error){toast("Prospectus not archived",friendlyError(error),"error",8000)}}
  async function deleteSchoolProspectus(snapshot){const p=prospectusRecord(snapshot);if(!await confirmAction("Delete draft prospectus","Only a prospectus that has never been published can be deleted. This removes its current sections and items.","Delete draft",true))return;try{await rpc("delete_school_prospectus",{target_prospectus_id:p.id});state.prospectusConsole=null;toast("Draft prospectus deleted");await renderSchoolProspectus(state.viewToken,true)}catch(error){toast("Prospectus not deleted",friendlyError(error),"error",8000)}}
  function copySchoolProspectus(snapshot){const p=prospectusRecord(snapshot),years=(state.boot?.academic_years||[]).filter(y=>y.id!==snapshot.academic_year?.id);if(!years.length){toast("No target academic year","Create the next academic year before copying this prospectus.","warning");return}modal("Copy Prospectus to Academic Year","Create a new editable draft from an existing academic-year prospectus.",`<form id="prospectusCopyForm" class="form-grid"><div class="template-information full"><strong>${esc(prospectusRangeLabel(p.class_range))}</strong><span>Sections and items are copied into a new Draft. Publication history is not copied.</span></div><label class="field full"><span>Target academic year</span><select name="academic_year_id">${years.map(y=>`<option value="${attr(y.id)}">${esc(y.name)}</option>`).join("")}</select></label></form>`,`<button class="button ghost" id="prospectusCopyCancel">Cancel</button><button class="button primary" id="prospectusCopySave">Copy prospectus</button>`);byId("prospectusCopyCancel").onclick=closeModal;byId("prospectusCopySave").onclick=async()=>{const target=formObject(byId("prospectusCopyForm")).academic_year_id,b=byId("prospectusCopySave");b.disabled=true;try{await rpc("copy_school_prospectus",{target_source_id:p.id,target_academic_year_id:target});closeModal();state.prospectusYear=target;state.prospectusConsole=null;toast("Prospectus copied","The copied prospectus is a new draft ready for the target academic year.");await renderSchoolProspectus(state.viewToken,true)}catch(error){toast("Prospectus not copied",friendlyError(error),"error",9000)}finally{b.disabled=false}}}

  function prospectusPreviewHtml(snapshot){
    const p=prospectusRecord(snapshot),currency=prospectusCurrency(snapshot),school=snapshot.school||{},sections=snapshot.sections||[],grand=sections.reduce((sum,section)=>sum+prospectusSubtotal(section),0),status=String(p.status||"draft").toUpperCase(),revision=p.revision_no?`Revision R${number(p.revision_no)}`:"Not yet published";
    return `<article class="prospectus-preview-document prospectus-preview-r16"><header><div class="prospectus-preview-brand"><img src="${attr(schoolDisplayLogo(school))}" alt=""><div><h2>${esc(school.school_name||schoolDisplayName(school))}</h2>${school.motto?`<p>${esc(school.motto)}</p>`:""}${school.address?`<p>${esc(school.address)}</p>`:""}${school.phone?`<p>${esc(school.phone)}</p>`:""}${school.website||school.email?`<p>${esc(school.website||school.email)}</p>`:""}<h1>School Prospectus</h1></div></div></header><div class="prospectus-preview-meta"><span><b>Academic Year</b>${esc(snapshot.academic_year?.name||"")}</span><span><b>Class Range</b>${esc(prospectusRangeLabel(p.class_range))}</span><span><b>Status</b>${esc(`${status} | ${revision}`)}</span><span><b>Effective</b>${esc(p.effective_date?isoDate(p.effective_date):"Not set")}</span></div>${p.general_notes?`<div class="prospectus-notice"><strong>General Note</strong><span>${esc(p.general_notes)}</span></div>`:""}${sections.map(section=>`<section><h3>${esc(section.title)}</h3>${section.instructions?`<p class="section-note">${esc(section.instructions)}</p>`:""}<div class="table-wrap"><table><thead><tr><th>Description</th><th>Amount / Quantity</th><th>Basis</th></tr></thead><tbody>${(section.items||[]).map(item=>{const detail=prospectusPdfItemDetail(item);return `<tr><td><strong>${esc(item.item_name)}</strong>${detail?`<br><small>${esc(detail)}</small>`:""}</td><td>${esc(prospectusAmountLabel(item,currency))}</td><td>${esc(prospectusPdfBasisText(item))}</td></tr>`}).join("")||`<tr><td colspan="3">No items configured</td></tr>`}</tbody></table></div>${prospectusSubtotal(section)>0?`<div class="prospectus-preview-subtotal"><span>Calculated subtotal</span><strong>${esc(prospectusMoney(prospectusSubtotal(section),currency))}</strong></div>`:""}</section>`).join("")}<footer><div><strong>Calculated payable total: ${esc(prospectusMoney(grand,currency))}</strong>${prospectusHasUncalculatedRates(snapshot)?`<small>Recurring rates without configured calculation units are shown separately and are not included in this total.</small>`:""}</div><div><span>Single-page A4 output</span><span>Page 1 of 1 per class range</span></div></footer></article>`
  }
  function previewSchoolProspectus(snapshot){if(!snapshot)return;modal(`${prospectusRangeLabel(prospectusRecord(snapshot).class_range)} Prospectus Preview`,`Review the document exactly as organized before downloading the PDF.`,prospectusPreviewHtml(snapshot),`<button class="button ghost" id="prospectusPreviewClose">Close</button><button class="button primary" id="prospectusPreviewPdf">Download PDF</button>`,`wide`);byId("prospectusPreviewClose").onclick=closeModal;byId("prospectusPreviewPdf").onclick=()=>downloadSchoolProspectusPdf(snapshot)}

  // r16 Prospectus single-page A4 print contract.
  // Uses the same school-header information and visual hierarchy as the official report card,
  // then compacts every prospectus section into one readable A4 page per class range.
  function prospectusPdfWrapLines(ctx,text,maxWidth){
    const value=String(text??"").replace(/\r/g,"");
    if(!value)return [];
    const lines=[];
    const pushWrapped=paragraph=>{
      const words=String(paragraph||"").trim().split(/\s+/).filter(Boolean);
      if(!words.length){lines.push("");return}
      let line="";
      for(const rawWord of words){
        let word=rawWord;
        const candidate=line?`${line} ${word}`:word;
        if(ctx.measureText(candidate).width<=maxWidth){line=candidate;continue}
        if(line){lines.push(line);line=""}
        if(ctx.measureText(word).width<=maxWidth){line=word;continue}
        let chunk="";
        for(const character of word){
          const next=`${chunk}${character}`;
          if(chunk&&ctx.measureText(next).width>maxWidth){lines.push(chunk);chunk=character}
          else chunk=next;
        }
        line=chunk;
      }
      if(line)lines.push(line);
    };
    value.split("\n").forEach(pushWrapped);
    return lines;
  }
  function prospectusPdfDrawLines(ctx,lines,x,y,lineHeight,{align="left",width=0}={}){
    const previous=ctx.textAlign;ctx.textAlign=align;
    const anchor=align==="center"?x+width/2:align==="right"?x+width:x;
    for(const line of lines){ctx.fillText(line,anchor,y);y+=lineHeight}
    ctx.textAlign=previous;return y;
  }
  function prospectusPdfItemDetail(item){
    return [item?.description,item?.notes].map(value=>String(value||"").trim()).filter(Boolean).join(" | ");
  }
  function prospectusPdfBasisText(item){
    const basis=prospectusBasisLabel(item?.charge_basis);
    const units=prospectusNumberOrNull(item?.calculation_units);
    return units!==null&&units>0?`${basis} x ${number(units)}`:basis;
  }
  function prospectusPdfProfileHeight(ctx,snapshot,profile,width,draw=false,originX=0,originY=0){
    const school=snapshot.school||{},p=prospectusRecord(snapshot),currency=prospectusCurrency(snapshot),primary=idCardSafeColour(school.primary_colour,"#123a79"),accent=idCardSafeColour(school.accent_colour,"#f0b51d");
    const descWidth=width*.62,amountWidth=width*.18,basisWidth=width-descWidth-amountWidth;
    const descX=originX,amountX=originX+descWidth,basisX=amountX+amountWidth;
    let y=originY;
    const line=(x1,y1,x2,y2,colour="#d4ddea",lineWidth=1)=>{if(!draw)return;ctx.strokeStyle=colour;ctx.lineWidth=lineWidth;ctx.beginPath();ctx.moveTo(x1,y1);ctx.lineTo(x2,y2);ctx.stroke()};
    const rect=(x1,y1,w,h,fill)=>{if(!draw)return;ctx.fillStyle=fill;ctx.fillRect(x1,y1,w,h)};
    if(p.general_notes){
      setReportFont(ctx,profile.detail,"normal");const noteLines=prospectusPdfWrapLines(ctx,p.general_notes,width-profile.pad*4),h=Math.max(profile.noteMin,noteLines.length*profile.detailLine+profile.pad*2+8);
      if(draw){rect(originX,y,width,h,"#fff8df");ctx.strokeStyle="#ead27a";ctx.lineWidth=1;ctx.strokeRect(originX,y,width,h);ctx.fillStyle="#6a5212";setReportFont(ctx,profile.meta,"bold");ctx.fillText("GENERAL NOTE",originX+profile.pad*2,y+profile.pad+profile.meta);ctx.fillStyle="#5b4810";setReportFont(ctx,profile.detail,"normal");prospectusPdfDrawLines(ctx,noteLines,originX+profile.pad*2,y+profile.pad+profile.meta+profile.detailLine,profile.detailLine)}
      y+=h+profile.gap;
    }
    const sections=snapshot.sections||[];
    for(let sectionIndex=0;sectionIndex<sections.length;sectionIndex++){
      const section=sections[sectionIndex];if(sectionIndex)y+=profile.gap;
      setReportFont(ctx,profile.section,"bold");const title=String(section.title||prospectusSectionTypeLabel(section.section_type)).toUpperCase(),titleLines=prospectusPdfWrapLines(ctx,title,descWidth-profile.pad*4);
      const headerH=Math.max(profile.sectionH,titleLines.length*profile.sectionLine+profile.pad*2);
      if(draw){rect(originX,y,width,headerH,primary);ctx.fillStyle="#fff";setReportFont(ctx,profile.section,"bold");prospectusPdfDrawLines(ctx,titleLines,originX+profile.pad*2,y+profile.pad+profile.section,profile.sectionLine);setReportFont(ctx,profile.column,"bold");ctx.textAlign="center";ctx.fillText("AMOUNT / QUANTITY",amountX+amountWidth/2,y+headerH/2+profile.column*.35);ctx.fillText("BASIS",basisX+basisWidth/2,y+headerH/2+profile.column*.35);ctx.textAlign="left"}
      y+=headerH;
      if(section.instructions){
        setReportFont(ctx,profile.detail,"normal");const instructionLines=prospectusPdfWrapLines(ctx,section.instructions,width-profile.pad*4),instructionH=instructionLines.length*profile.detailLine+profile.pad*2;
        if(draw){rect(originX,y,width,instructionH,"#f4f7fb");ctx.fillStyle="#52647e";prospectusPdfDrawLines(ctx,instructionLines,originX+profile.pad*2,y+profile.pad+profile.detail,profile.detailLine);line(originX,y+instructionH,originX+width,y+instructionH)}
        y+=instructionH;
      }
      const items=section.items||[];
      if(!items.length){
        const rowH=profile.minRow;
        if(draw){ctx.fillStyle="#6a778c";setReportFont(ctx,profile.detail,"normal");ctx.fillText("No items configured",originX+profile.pad*2,y+rowH/2+profile.detail*.35);line(originX,y+rowH,originX+width,y+rowH);line(amountX,y,amountX,y+rowH);line(basisX,y,basisX,y+rowH)}
        y+=rowH;
      }
      for(let itemIndex=0;itemIndex<items.length;itemIndex++){
        const item=items[itemIndex],name=String(item.item_name||""),detail=prospectusPdfItemDetail(item),amount=prospectusAmountLabel(item,currency),basis=prospectusPdfBasisText(item);
        setReportFont(ctx,profile.name,"bold");const nameLines=prospectusPdfWrapLines(ctx,name,descWidth-profile.pad*4);
        setReportFont(ctx,profile.detail,"normal");const detailLines=detail?prospectusPdfWrapLines(ctx,detail,descWidth-profile.pad*4):[];
        setReportFont(ctx,profile.amount,"bold");const amountLines=prospectusPdfWrapLines(ctx,amount,amountWidth-profile.pad*3);
        setReportFont(ctx,profile.basis,"normal");const basisLines=prospectusPdfWrapLines(ctx,basis,basisWidth-profile.pad*3);
        const descContent=nameLines.length*profile.nameLine+(detailLines.length?profile.detailGap+detailLines.length*profile.detailLine:0),amountContent=Math.max(1,amountLines.length)*profile.amountLine,basisContent=Math.max(1,basisLines.length)*profile.basisLine;
        const rowH=Math.max(profile.minRow,Math.max(descContent,amountContent,basisContent)+profile.pad*2);
        if(draw){
          if(itemIndex%2===1)rect(originX,y,width,rowH,"#fbfdff");
          ctx.fillStyle="#17233b";setReportFont(ctx,profile.name,"bold");let textY=y+profile.pad+profile.name;prospectusPdfDrawLines(ctx,nameLines,originX+profile.pad*2,textY,profile.nameLine);
          if(detailLines.length){textY+=nameLines.length*profile.nameLine+profile.detailGap-profile.name;ctx.fillStyle="#66758a";setReportFont(ctx,profile.detail,"normal");prospectusPdfDrawLines(ctx,detailLines,originX+profile.pad*2,textY+profile.detail,profile.detailLine)}
          ctx.fillStyle="#203b65";setReportFont(ctx,profile.amount,"bold");const amountTop=y+(rowH-amountLines.length*profile.amountLine)/2+profile.amount;prospectusPdfDrawLines(ctx,amountLines,amountX,y+(rowH-amountLines.length*profile.amountLine)/2+profile.amount,profile.amountLine,{align:"center",width:amountWidth});
          ctx.fillStyle="#55657d";setReportFont(ctx,profile.basis,"normal");prospectusPdfDrawLines(ctx,basisLines,basisX,y+(rowH-basisLines.length*profile.basisLine)/2+profile.basis,profile.basisLine,{align:"center",width:basisWidth});
          line(originX,y+rowH,originX+width,y+rowH);line(amountX,y,amountX,y+rowH);line(basisX,y,basisX,y+rowH);
        }
        y+=rowH;
      }
      const subtotal=prospectusSubtotal(section);
      if(subtotal>0){
        if(draw){rect(originX,y,width,profile.subtotalH,"#edf3fb");ctx.fillStyle="#12233f";setReportFont(ctx,profile.subtotal,"bold");ctx.fillText("CALCULATED SUBTOTAL",amountX+profile.pad,y+profile.subtotalH/2+profile.subtotal*.35);ctx.textAlign="right";ctx.fillText(prospectusMoney(subtotal,currency),originX+width-profile.pad*2,y+profile.subtotalH/2+profile.subtotal*.35);ctx.textAlign="left";line(originX,y+profile.subtotalH,originX+width,y+profile.subtotalH)}
        y+=profile.subtotalH;
      }
    }
    y+=profile.gap*1.5;
    const grand=(snapshot.sections||[]).reduce((sum,section)=>sum+prospectusSubtotal(section),0);
    if(draw){rect(originX,y,width,profile.totalH,"#0f274b");ctx.fillStyle="#fff";setReportFont(ctx,profile.totalLabel,"bold");ctx.fillText("CALCULATED PAYABLE TOTAL",originX+profile.pad*2,y+profile.totalH/2+profile.totalLabel*.36);ctx.textAlign="right";setReportFont(ctx,profile.totalValue,"bold");ctx.fillText(prospectusMoney(grand,currency),originX+width-profile.pad*2,y+profile.totalH/2+profile.totalValue*.34);ctx.textAlign="left"}
    y+=profile.totalH;
    if(prospectusHasUncalculatedRates(snapshot)){
      const warning="Recurring rates such as per-day transport or feeding are excluded from the calculated total until the school specifies the number of billable units.";
      setReportFont(ctx,profile.detail,"normal");const warningLines=prospectusPdfWrapLines(ctx,warning,width-profile.pad*4),warningH=warningLines.length*profile.detailLine+profile.pad*2+4;
      if(draw){rect(originX,y,width,warningH,"#fff8df");ctx.fillStyle="#6a4d12";setReportFont(ctx,profile.detail,"bold");prospectusPdfDrawLines(ctx,warningLines,originX+profile.pad*2,y+profile.pad+profile.detail,profile.detailLine)}
      y+=warningH;
    }
    if(draw&&accent){ctx.fillStyle=accent;ctx.fillRect(originX,y+profile.gap,width,3)}
    return y-originY;
  }
  async function prospectusCanvasPages(snapshot){
    await ensureReportBodyFontReady();
    const {canvas,ctx}=createReportPrintCanvas(),school=snapshot.school||{},p=prospectusRecord(snapshot),primary=idCardSafeColour(school.primary_colour,"#123a79"),accent=idCardSafeColour(school.accent_colour,"#f0b51d");
    const W=REPORT_LOGICAL_WIDTH,H=REPORT_LOGICAL_HEIGHT,left=38,right=1202,bodyWidth=right-left,footerTop=1692;let logo=null;try{logo=await loadImage(schoolDisplayLogo(school))}catch(_){}
    ctx.fillStyle="#ffffff";ctx.fillRect(0,0,W,H);

    // r17 uses the exact same official school identity header as the terminal report.
    drawOfficialSchoolHeader(ctx,{school,logo,subtitle:"School Prospectus",primary});
    ctx.fillStyle=accent;ctx.fillRect(38,228,1164,5);

    const status=String(p.status||"draft").toUpperCase(),revision=p.revision_no?`Revision R${number(p.revision_no)}`:"Not yet published",effective=p.effective_date?isoDate(p.effective_date):"Not set";
    ctx.fillStyle="#17233b";setReportFont(ctx,17,"bold");ctx.fillText("Academic Year:",43,267);setReportFont(ctx,17,"normal");ctx.fillText(String(snapshot.academic_year?.name||""),173,267,350);
    setReportFont(ctx,17,"bold");ctx.fillText("Class Range:",645,267);setReportFont(ctx,17,"normal");ctx.fillText(prospectusRangeLabel(p.class_range),765,267,427);
    setReportFont(ctx,15,"bold");ctx.fillText("Status:",43,299);setReportFont(ctx,15,"normal");ctx.fillText(`${status} | ${revision}`,105,299,490);
    setReportFont(ctx,15,"bold");ctx.fillText("Effective:",645,299);setReportFont(ctx,15,"normal");ctx.fillText(`${effective} | Currency: ${prospectusCurrency(snapshot)}`,725,299,467);
    ctx.strokeStyle="#d9e1ec";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(left,313);ctx.lineTo(right,313);ctx.stroke();

    const bodyTop=327,availableBodyHeight=footerTop-bodyTop-12;
    const profiles=[
      {name:16,detail:12,section:14,column:10,meta:10,amount:14,basis:12,subtotal:12,totalLabel:14,totalValue:17,nameLine:18,detailLine:15,sectionLine:16,amountLine:16,basisLine:15,pad:6,detailGap:2,minRow:34,sectionH:31,noteMin:46,gap:7,subtotalH:28,totalH:45},
      {name:15,detail:11,section:13,column:9.5,meta:9.5,amount:13,basis:11,subtotal:11,totalLabel:13,totalValue:16,nameLine:17,detailLine:14,sectionLine:15,amountLine:15,basisLine:14,pad:5,detailGap:2,minRow:31,sectionH:29,noteMin:42,gap:6,subtotalH:26,totalH:42},
      {name:14,detail:10,section:12,column:9,meta:9,amount:12,basis:10,subtotal:10,totalLabel:12,totalValue:15,nameLine:16,detailLine:13,sectionLine:14,amountLine:14,basisLine:13,pad:4,detailGap:1,minRow:28,sectionH:27,noteMin:38,gap:5,subtotalH:24,totalH:39}
    ];
    let profile=profiles[0],bodyHeight=prospectusPdfProfileHeight(ctx,snapshot,profile,bodyWidth,false,0,0),scale=1,virtualWidth=bodyWidth;
    for(const candidate of profiles){const measured=prospectusPdfProfileHeight(ctx,snapshot,candidate,bodyWidth,false,0,0);if(measured<=availableBodyHeight){profile=candidate;bodyHeight=measured;scale=1;virtualWidth=bodyWidth;break}profile=candidate;bodyHeight=measured}
    // Use spare vertical space deliberately so ordinary prospectuses fill the sheet like the report card instead of leaving a large blank lower half.
    if(bodyHeight<availableBodyHeight*.88){
      const stretch=Math.min(1.3,(availableBodyHeight*.91)/Math.max(1,bodyHeight));
      profile={...profile,nameLine:profile.nameLine*stretch,detailLine:profile.detailLine*stretch,sectionLine:profile.sectionLine*stretch,amountLine:profile.amountLine*stretch,basisLine:profile.basisLine*stretch,pad:profile.pad*stretch,detailGap:profile.detailGap*stretch,minRow:profile.minRow*stretch,sectionH:profile.sectionH*stretch,noteMin:profile.noteMin*stretch,gap:profile.gap*stretch,subtotalH:profile.subtotalH*stretch,totalH:profile.totalH*stretch};
      bodyHeight=prospectusPdfProfileHeight(ctx,snapshot,profile,bodyWidth,false,0,0);
    }
    if(bodyHeight>availableBodyHeight){
      for(let iteration=0;iteration<6;iteration++){
        scale=Math.min(1,availableBodyHeight/Math.max(1,bodyHeight));virtualWidth=bodyWidth/scale;bodyHeight=prospectusPdfProfileHeight(ctx,snapshot,profile,virtualWidth,false,0,0);
      }
      scale=Math.min(1,availableBodyHeight/Math.max(1,bodyHeight));virtualWidth=bodyWidth/scale;
    }
    if(!(scale>0&&Number.isFinite(scale)))throw new Error("The prospectus single-page layout could not be calculated.");
    ctx.save();ctx.translate(left,bodyTop);ctx.scale(scale,scale);prospectusPdfProfileHeight(ctx,snapshot,profile,virtualWidth,true,0,0);ctx.restore();

    // Footer is fixed so an individual class-range prospectus can never spill to a second page.
    ctx.fillStyle="#5b6b82";setReportFont(ctx,10,"normal");ctx.fillText(`Generated ${new Date().toLocaleString("en-GH")} | ${status}${p.effective_date?` | Effective ${isoDate(p.effective_date)}`:""}`,left,1720,940);
    ctx.textAlign="right";ctx.fillText("Page 1 of 1",right,1720);ctx.textAlign="left";ctx.fillStyle=accent;ctx.fillRect(0,1736,W,18);
    return [canvas];
  }

  async function createSchoolProspectusPdf(snapshots){if(!snapshots?.length)throw new Error("No school prospectus is available for PDF generation");const blobs=[];for(const snapshot of snapshots){const pages=await prospectusCanvasPages(snapshot);if(pages.length!==1)throw new Error("The prospectus single-page print contract failed. Refresh the system and try again.");for(const page of pages){try{blobs.push(await idCardCanvasBlob(page,.985))}finally{releaseCanvas(page)}}await sleep(10)}if(blobs.length!==snapshots.length)throw new Error("The prospectus PDF page count is inconsistent with the selected class ranges.");return imagesPdf(blobs,595.28,841.89,2480,3508)}
  async function downloadSchoolProspectusPdf(snapshot){if(!snapshot)return;setLoading(true);try{const p=prospectusRecord(snapshot);downloadBlob(`${safeArchiveSegment(snapshot.academic_year?.name||"year")}-${safeArchiveSegment(prospectusRangeLabel(p.class_range))}-school-prospectus${p.revision_no?`-R${p.revision_no}`:"-draft"}.pdf`,await createSchoolProspectusPdf([snapshot]));toast("Prospectus PDF downloaded","Professional single-page A4 prospectus generated successfully.")}catch(error){toast("Prospectus PDF not created",friendlyError(error),"error",9000)}finally{setLoading(false)}}


  async function renderInsights(token,force=false) {
    const termId=nullableId(state.analyticsData?.term_id||activeTerm()?.id||(state.boot.terms||[])[0]?.id),visibleClasses=await visibleClassesForCurrentRole(),classId=nullableId(state.analyticsData?.class_id);
    const data=await rpc("academic_analytics",{target_term_id:termId,target_class_id:classId});if(token!==state.viewToken)return;state.analyticsData={...data,term_id:termId,class_id:classId};const summary=data.summary||{},hasAcademicTerm=Boolean(termId);
    byId("content").innerHTML=`<div class="page-head"><div><h3>Academic Insights</h3><p>Privacy-aware class, subject, attendance, and report-completion trends</p></div><div class="page-actions"><button class="button secondary" id="insightsExport" ${hasAcademicTerm?"":"disabled"}>Export summary</button></div></div>
      ${hasAcademicTerm?"":`<div class="template-information warning"><strong>No academic term is configured</strong><span>Insights will become available after an academic term is created. The empty Master remains valid and operational.</span></div>`}
      <section class="panel pad"><div class="form-grid"><label class="field"><span>Term</span><select id="insightsTerm" ${hasAcademicTerm?"":"disabled"}>${optionList(state.boot.terms||[],"id","name",termId||"")}</select></label><label class="field"><span>Class</span><select id="insightsClass" ${hasAcademicTerm?"":"disabled"}>${optionList(visibleClasses,"id","name",classId||"","All authorised classes")}</select></label></div></section>
      <div class="stat-grid maturity-stat-grid" style="margin-top:18px">${statCard("blue","◉","Students",summary.students)}${statCard("purple","▤","Reports",summary.reports)}${statCard("gold","%","Average",`${number(summary.average,1)}%`)}${statCard("green","✓","Attendance",`${number(summary.attendance_rate,1)}%`)}</div>
      <div class="grid two maturity-grid"><section class="panel pad"><div class="section-title"><h4>Subject performance</h4></div>${(data.subjects||[]).length?`<div class="bar-list analytics-bars">${data.subjects.map(item=>`<div class="bar-item"><label><strong>${esc(item.subject_name)}</strong><small>${number(item.scored)} records • ${number(item.lowest,1)}–${number(item.highest,1)}</small></label><div class="bar-track"><span style="width:${percentValue(item.average)}%"></span></div><b>${number(item.average,1)}%</b></div>`).join("")}</div>`:emptyState("No subject results")}</section><section class="panel pad"><div class="section-title"><h4>Class overview</h4></div>${(data.classes||[]).length?`<div class="table-wrap"><table><thead><tr><th>Class</th><th>Students</th><th>Average</th><th>Attendance</th><th>Published</th></tr></thead><tbody>${data.classes.map(item=>`<tr><td>${esc(item.class_name)}</td><td>${number(item.students)}</td><td>${number(item.average,1)}%</td><td>${number(item.attendance_rate,1)}%</td><td>${number(item.published)}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No class analytics")}</section></div>`;
    byId("insightsTerm").onchange=()=>{state.analyticsData={term_id:nullableId(byId("insightsTerm").value),class_id:nullableId(byId("insightsClass").value)};renderInsights(token,true)};
    byId("insightsClass").onchange=()=>{state.analyticsData={term_id:nullableId(byId("insightsTerm").value),class_id:nullableId(byId("insightsClass").value)};renderInsights(token,true)};
    byId("insightsExport").onclick=()=>{const headers=["class","students","average","attendance_rate","published"];downloadText("academic-insights.csv",[headers.join(","),...(data.classes||[]).map(item=>[item.class_name,item.students,item.average,item.attendance_rate,item.published].map(csvCell).join(","))].join("\n"),"text/csv")};
  }

  async function renderCompliance(token,force=false) {
    const data=await rpc("get_compliance_console");if(token!==state.viewToken)return;state.complianceConsole=data;
    byId("content").innerHTML=`<div class="page-head"><div><h3>Privacy and Security</h3><p>Data retention, rights requests, security incidents, and formal verification</p></div><div class="page-actions">${role()==="system_admin"?`<button class="button secondary" id="retentionAdd">Add retention policy</button><button class="button primary" id="verificationAdd">Record security review</button>`:""}<button class="button outline" id="privacyAdd">New privacy request</button></div></div>
      <div class="stat-grid maturity-stat-grid">${statCard("blue","◈","Open privacy requests",data.open_privacy_requests)}${statCard("gold","⌛","Overdue requests",data.overdue_privacy_requests)}${statCard("red","!","High security events",data.open_high_security_events)}${statCard("green","✓","Verification runs",(data.verification_runs||[]).length)}</div>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Data retention policies</h3><p>Review periods and disposition actions; no automatic deletion is performed without governance approval.</p></div></div>${(data.retention_policies||[]).length?`<div class="table-wrap"><table><thead><tr><th>Category</th><th>Retention</th><th>Legal basis</th><th>Disposition</th><th>Status</th><th></th></tr></thead><tbody>${data.retention_policies.map(item=>`<tr><td>${esc(item.data_category)}</td><td>${item.retention_years?`${number(item.retention_years)} years`:"Indefinite review"}</td><td>${esc(item.legal_basis)}</td><td>${esc(statusText(item.disposition_action))}</td><td>${item.active?"Active":"Inactive"}</td><td>${role()==="system_admin"?`<button class="button ghost small" data-retention-edit="${attr(item.id)}">Edit</button>`:""}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No retention policies")}</section>
      <section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Privacy requests</h3><p>Access, correction, export, restriction, anonymisation, deletion, and consent review</p></div></div>${(data.privacy_requests||[]).length?`<div class="table-wrap"><table><thead><tr><th>Requester</th><th>Type</th><th>Student</th><th>Due</th><th>Status</th><th>Action</th></tr></thead><tbody>${data.privacy_requests.map(item=>`<tr><td><div class="cell-copy"><strong>${esc(item.requester_name)}</strong><small>${esc(item.requester_contact)}</small></div></td><td>${esc(statusText(item.request_type))}</td><td>${esc(item.student_name||"General request")}</td><td>${isoDateTime(item.due_at)}</td><td>${statusBadge(item.status)}</td><td><button class="button ghost small" data-privacy-update="${attr(item.id)}">Update</button></td></tr>`).join("")}</tbody></table></div>`:emptyState("No privacy requests")}</section>
      <div class="grid two maturity-grid" style="margin-top:18px"><section class="panel"><div class="panel-header"><div><h3>Security events</h3><p>Application and access-control events from the last 180 days</p></div></div>${(data.security_events||[]).length?`<div class="compact-scroll"><table><thead><tr><th>Event</th><th>Severity</th><th>Status</th><th></th></tr></thead><tbody>${data.security_events.map(item=>`<tr><td><div class="cell-copy"><strong>${esc(item.message)}</strong><small>${isoDateTime(item.created_at)} • ${esc(item.source)}</small></div></td><td><span class="severity ${attr(item.severity)}">${esc(item.severity)}</span></td><td>${statusBadge(item.status)}</td><td>${item.status==="open"?`<button class="button ghost small" data-security-resolve="${attr(item.id)}">Review</button>`:""}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No security events")}</section><section class="panel"><div class="panel-header"><div><h3>Security verification history</h3><p>OWASP ASVS or equivalent review evidence</p></div></div>${(data.verification_runs||[]).length?`<div class="compact-scroll"><table><thead><tr><th>Standard</th><th>Scope</th><th>Status</th><th>Next review</th></tr></thead><tbody>${data.verification_runs.map(item=>`<tr><td>${esc(item.standard_name)}</td><td>${esc(item.scope)}</td><td>${statusBadge(item.status)}</td><td>${isoDateTime(item.next_review_at)}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No formal security verification recorded")}</section></div>`;
    byId("retentionAdd")?.addEventListener("click",()=>editRetentionPolicy(null));$$('[data-retention-edit]').forEach(button=>button.onclick=()=>editRetentionPolicy((data.retention_policies||[]).find(item=>item.id===button.dataset.retentionEdit)));
    byId("privacyAdd").onclick=createPrivacyRequest;$$('[data-privacy-update]').forEach(button=>button.onclick=()=>updatePrivacyRequest((data.privacy_requests||[]).find(item=>item.id===button.dataset.privacyUpdate)));
    byId("verificationAdd")?.addEventListener("click",recordSecurityVerification);$$('[data-security-resolve]').forEach(button=>button.onclick=()=>resolveSecurityEvent(button.dataset.securityResolve));
  }
  function editRetentionPolicy(row={}){row=row||{};modal(row.id?"Edit retention policy":"Add retention policy","Disposition remains subject to authorised review.",`<form id="retentionForm" class="form-grid"><label class="field full"><span>Data category</span><input name="data_category" value="${attr(row.data_category||"")}" required></label><label class="field"><span>Retention years</span><input name="retention_years" type="number" min="1" max="100" value="${attr(row.retention_years||"")}"></label><label class="field"><span>Disposition</span><select name="disposition_action">${["review","archive","anonymise","delete"].map(value=>`<option value="${value}" ${row.disposition_action===value?"selected":""}>${esc(statusText(value))}</option>`).join("")}</select></label><label class="field full"><span>Legal basis</span><textarea name="legal_basis">${esc(row.legal_basis||"")}</textarea></label><label class="field full"><span>Notes</span><textarea name="notes">${esc(row.notes||"")}</textarea></label><label><input type="checkbox" name="active" ${row.active!==false?"checked":""}> Active policy</label></form>`,`<button class="button ghost" id="retentionCancel">Cancel</button><button class="button primary" id="retentionSave">Save</button>`,"small");byId("retentionCancel").onclick=closeModal;byId("retentionSave").onclick=async()=>{const form=byId("retentionForm"),values=formObject(form),button=byId("retentionSave");button.disabled=true;try{await rpc("save_retention_policy",{payload:{...values,active:form.elements.active.checked}});closeModal();toast("Retention policy saved");await renderCompliance(state.viewToken,true)}catch(error){toast("Policy not saved",friendlyError(error),"error")}finally{button.disabled=false}}}
  async function createPrivacyRequest(){let students=[];try{students=(await rpcAllRows("search_students_v5",{search_text:"",target_class_id:null,target_status:null,archive_filter:["system_admin","principal"].includes(role())?"all":"active"})).rows||[]}catch(_){}modal("Create privacy request","Record the request and its response deadline.",`<form id="privacyForm" class="form-grid"><label class="field"><span>Request type</span><select name="request_type">${["access","correction","export","restriction","anonymisation","deletion","consent_review"].map(value=>`<option value="${value}">${esc(statusText(value))}</option>`).join("")}</select></label><label class="field"><span>Student</span><select name="student_id">${optionList(students.map(item=>({...item,label:`${item.full_name||fullName(item)} • ${item.admission_no}`})),"id","label","","General request")}</select></label><label class="field"><span>Requester name</span><input name="requester_name" required></label><label class="field"><span>Contact</span><input name="requester_contact"></label><label class="field"><span>Due date</span><input type="datetime-local" name="due_at" value="${dateTimeLocalValue(new Date(Date.now()+30*86400000))}"></label><label class="field full"><span>Request details</span><textarea name="request_details" required></textarea></label></form>`,`<button class="button ghost" id="privacyCancel">Cancel</button><button class="button primary" id="privacySave">Save request</button>`,"small");byId("privacyCancel").onclick=closeModal;byId("privacySave").onclick=async()=>{const values=formObject(byId("privacyForm"));if(values.request_details.trim().length<10){toast("Details required","Provide at least ten characters.","error");return}const button=byId("privacySave");button.disabled=true;try{await rpc("create_privacy_request",{payload:values});closeModal();toast("Privacy request recorded");await renderCompliance(state.viewToken,true)}catch(error){toast("Request not saved",friendlyError(error),"error")}finally{button.disabled=false}}}
  function updatePrivacyRequest(row){modal("Update privacy request",row.requester_name,`<label class="field"><span>Status</span><select id="privacyStatus">${["open","in_review","approved","rejected","completed","cancelled"].map(value=>`<option value="${value}" ${row.status===value?"selected":""}>${esc(statusText(value))}</option>`).join("")}</select></label><label class="field"><span>Outcome or case note</span><textarea id="privacyOutcome">${esc(row.outcome||"")}</textarea></label>`,`<button class="button ghost" id="privacyUpdateCancel">Cancel</button><button class="button primary" id="privacyUpdateSave">Save</button>`,"small");byId("privacyUpdateCancel").onclick=closeModal;byId("privacyUpdateSave").onclick=async()=>{const button=byId("privacyUpdateSave");button.disabled=true;try{await rpc("update_privacy_request",{target_request_id:row.id,target_status:byId("privacyStatus").value,outcome_text:byId("privacyOutcome").value.trim()});closeModal();toast("Privacy request updated");await renderCompliance(state.viewToken,true)}catch(error){toast("Request not updated",friendlyError(error),"error")}finally{button.disabled=false}}}
  function recordSecurityVerification(){modal("Record security verification","Document an OWASP ASVS or equivalent review.",`<form id="securityVerificationForm" class="form-grid"><label class="field"><span>Standard</span><input name="standard_name" value="OWASP ASVS 5.0"></label><label class="field"><span>Status</span><select name="status">${["planned","in_progress","passed","passed_with_findings","failed"].map(value=>`<option value="${value}">${esc(statusText(value))}</option>`).join("")}</select></label><label class="field full"><span>Scope</span><input name="scope" required placeholder="Authentication, RLS, Storage, Edge Functions, file uploads"></label><label class="field full"><span>Summary</span><textarea name="summary"></textarea></label><label class="field"><span>Next review</span><input type="datetime-local" name="next_review_at"></label></form>`,`<button class="button ghost" id="verificationCancel">Cancel</button><button class="button primary" id="verificationSave">Save review</button>`,"small");byId("verificationCancel").onclick=closeModal;byId("verificationSave").onclick=async()=>{const values=formObject(byId("securityVerificationForm")),button=byId("verificationSave");button.disabled=true;try{await rpc("save_security_verification",{payload:{...values,findings:[]}});closeModal();toast("Security verification recorded");await renderCompliance(state.viewToken,true)}catch(error){toast("Verification not saved",friendlyError(error),"error")}finally{button.disabled=false}}}
  function resolveSecurityEvent(id){modal("Review security event","Record the investigation outcome.",`<label class="field"><span>Status</span><select id="securityEventStatus"><option value="acknowledged">Acknowledged</option><option value="resolved">Resolved</option><option value="false_positive">False positive</option></select></label><label class="field"><span>Resolution note</span><textarea id="securityResolution"></textarea></label>`,`<button class="button ghost" id="securityCancel">Cancel</button><button class="button primary" id="securitySave">Save</button>`,"small");byId("securityCancel").onclick=closeModal;byId("securitySave").onclick=async()=>{const button=byId("securitySave");button.disabled=true;try{await rpc("resolve_security_event",{target_event_id:Number(id),target_status:byId("securityEventStatus").value,resolution_text:byId("securityResolution").value.trim()});closeModal();toast("Security event updated");await renderCompliance(state.viewToken,true)}catch(error){toast("Security event not updated",friendlyError(error),"error")}finally{button.disabled=false}}}


  const PACKAGE_LOGO_TYPES=new Set(["image/png"]);
  const PACKAGE_LOGO_SOURCE_MAX_BYTES=5*1024*1024;
  // r28 Free-plan generated-package logo budget: accept a normal PNG source, then
  // normalize it before server generation so four intentional package copies can
  // never consume the private generated-package file-size headroom.
  const PACKAGE_LOGO_MAX_BYTES=1000000;
  const PACKAGE_TEMPLATE_MAX_BYTES=48*1000*1000;

  function githubNavigatorStepsHtml() {
    return `<div class="navigator-steps">
      <article><b>1</b><div><strong>Install protected template</strong><span>Upload the official v7.4.0 package template. It is stored in a private Supabase bucket and never published with the school frontend.</span></div></article>
      <article><b>2</b><div><strong>Generate licensed package</strong><span>Bind the package to a school, tenant code, licence reference, plan, and optional authorized domain.</span></div></article>
      <article><b>3</b><div><strong>Download securely</strong><span>The server returns a short-lived signed URL and records every authorized download.</span></div></article>
      <article><b>4</b><div><strong>Deploy and distribute</strong><span>Deploy only GITHUB_PAGES_FRONTEND, then distribute the confirmed Android r6 APK, Windows w1 setup EXE, or privately built school-branded installers.</span></div></article>
    </div>`;
  }

  async function normalisePackageSchoolLogo(file){
    if(!file)throw new Error("Select the school logo first.");
    if(!PACKAGE_LOGO_TYPES.has(String(file.type||"").toLowerCase()))throw new Error("The package school logo must be a PNG image.");
    if(Number(file.size||0)<=0||file.size>PACKAGE_LOGO_SOURCE_MAX_BYTES)throw new Error("The source school logo must be 5 MB or smaller.");
    const objectUrl=URL.createObjectURL(file);let image;
    try{image=await loadImage(objectUrl)}finally{URL.revokeObjectURL(objectUrl)}
    if(!image?.width||!image?.height)throw new Error("The selected package school logo could not be decoded.");
    if(image.width<256||image.height<256||image.width>4096||image.height>4096)throw new Error("The package school logo must be between 256 and 4096 pixels on each side.");
    const ratio=image.width/image.height;if(ratio<0.5||ratio>2)throw new Error("The package school logo must use a reasonably square aspect ratio.");
    // r28 adaptive PNG normalization contract. Preserve a high-resolution logo where
    // possible, but progressively reduce the square canvas until the deterministic
    // 1,000,000-byte package budget is met. The source file itself remains untouched.
    const sizes=[1024,896,768,640,576,512,480,448,384,320,256];
    for(const size of sizes){
      const canvas=document.createElement("canvas");canvas.width=size;canvas.height=size;const ctx=canvas.getContext("2d");if(!ctx)throw new Error("The browser could not prepare the package school logo.");
      ctx.clearRect(0,0,size,size);ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality="high";const pad=Math.max(8,Math.round(size*0.024));drawImageContain(ctx,image,pad,pad,size-pad*2,size-pad*2);
      const blob=await new Promise((resolve,reject)=>canvas.toBlob(value=>value?resolve(value):reject(new Error("The package school logo could not be encoded.")),"image/png"));canvas.width=1;canvas.height=1;
      if(blob.size<=PACKAGE_LOGO_MAX_BYTES)return blob;
    }
    throw new Error("The normalized package school logo still exceeds 1 MB. Use a simpler PNG logo.");
  }

  async function reconcileProtectedTemplateActivation(receipt){
    // r28 activation reconciliation contract: an Edge Function may commit the active
    // template and then exhaust its response compute budget. Confirm the authoritative
    // active SHA before telling the operator that installation failed.
    const expected=String(receipt?.archive_sha256||"").trim().toLowerCase();if(!/^[a-f0-9]{64}$/.test(expected))return null;
    for(let attempt=0;attempt<3;attempt+=1){
      await new Promise(resolve=>setTimeout(resolve,700+attempt*500));
      try{const status=await invokePlatformPackageManager("status",{offset:0,limit:1,search:""}),template=status?.template;if(template&&template.active!==false&&String(template.sha256||"").toLowerCase()===expected)return status}catch{}
    }
    return null;
  }

  async function invokePlatformPackageManager(action,payload={}) {
    if(role()!=="platform_super_admin")throw new Error("Platform Super Administrator access required");
    const {data,error}=await state.client.functions.invoke("platform-package-manager",{body:{action,...payload}});
    if(error)throw new Error(await edgeFunctionErrorMessage(error,data));
    if(!data?.ok)throw new Error(data?.error||"Platform package operation failed");
    return data;
  }

  async function invokeLicenseUpgradeManager(action,payload={}) {
    if(role()!=="platform_super_admin")throw new Error("Platform Super Administrator access required");
    const {data,error}=await state.client.functions.invoke("license-upgrade-manager",{body:{action,...payload}});
    if(error)throw new Error(await edgeFunctionErrorMessage(error,data));
    if(!data?.ok)throw new Error(data?.error||"Licence upgrade manager operation failed");
    return data;
  }

  function readFileAsDataUrl(file,maxBytes,allowedTypes=null) {
    return new Promise((resolve,reject)=>{
      if(!file){reject(new Error("Select the required file."));return}
      if(maxBytes&&file.size>maxBytes){reject(new Error(`File must not exceed ${readableBytes(maxBytes)}.`));return}
      if(allowedTypes&&!allowedTypes.has(file.type)){reject(new Error("The selected file type is not permitted."));return}
      const reader=new FileReader();reader.onerror=()=>reject(new Error("The selected file could not be read."));reader.onload=()=>resolve(String(reader.result||""));reader.readAsDataURL(file);
    });
  }

  function platformPackageStatusLabel(value="") {
    if(value==="ready")return '<span class="status approved">Ready</span>';
    if(value==="revoked")return '<span class="status rejected">Revoked</span>';
    return `<span class="status draft">${esc(value||"Unknown")}</span>`;
  }
  function platformPackageLifecycleLabel(item={}) {
    const action=String(item.lifecycle_action||item.metadata?.lifecycle?.action||"initial");
    const sequence=Number(item.renewal_sequence||item.metadata?.lifecycle?.renewal_sequence||0);
    if(action==="initial")return "Initial issue";
    return `${licenseStatusLabel(action)}${sequence?` R${sequence}`:""}`;
  }
  function platformPackageActionButtons(item,canGenerate=false,canRevoke=false,hasOpenReplacement=false,effectivePlanCode="") {
    const ready=item.status==="ready"&&item.deletion_state==="none",replacement=Boolean(item.supersedes_artifact_id),superseded=Boolean(item.superseded_by_artifact_id),finalized=Boolean(item.metadata?.lifecycle?.finalized_at);
    const activeAuthority=ready&&!superseded&&(!replacement||finalized),pendingReplacement=ready&&replacement&&!finalized;
    const actions=[];
    if(ready)actions.push(`<button class="button secondary small" data-package-download="${attr(item.id)}">Download</button>`);
    if(pendingReplacement&&canRevoke){
      if(item.authority_last_checked_at)actions.push(`<button class="button success small" data-package-finalize="${attr(item.id)}">Finalize replacement</button>`);
      else actions.push('<span class="status pending">Awaiting school verification</span>');
    }
    if(activeAuthority&&canGenerate){
      if(hasOpenReplacement)actions.push('<span class="status pending">Replacement pending</span>');
      else {
        const planCode=String(effectivePlanCode||item.license_plan_code||"").toLowerCase();
        if(["starter","professional"].includes(planCode))actions.push(`<button class="button success small" data-package-upgrade-code="${attr(item.id)}">Generate Upgrade Code</button>`);
        actions.push(`<button class="button primary small" data-package-renew="${attr(item.id)}">Renew / Upgrade</button>`);
      }
    }
    if(ready&&finalized)actions.push('<span class="status approved">Active replacement</span>');
    if(ready&&canRevoke)actions.push(`<button class="button warning small" data-package-revoke="${attr(item.id)}">${pendingReplacement?"Cancel replacement":"Revoke"}</button>`);
    if(item.status==="revoked"&&item.deletion_state==="none"&&canRevoke&&!superseded)actions.push(`<button class="button success small" data-package-restore="${attr(item.id)}">Restore</button>`);
    if(item.status!=="deleted"&&canRevoke)actions.push(`<button class="button danger small" data-package-delete="${attr(item.id)}">Delete permanently</button>`);
    if(item.status==="deleted")actions.push('<span class="status neutral">Receipt retained</span>');
    return actions.join("");
  }
  function platformSectionTabs(active="licensing") {
    const items=[
      {id:"licensing",label:"Platform Licensing",icon:"◇"},
      {id:"github",label:"GitHub Navigator",icon:"⌁"}
    ];
    return `<div class="tabs platform-tabs" role="tablist" aria-label="Platform Super Administrator sections">${items.map(item=>`<button type="button" class="tab ${item.id===active?"active":""}" data-platform-section="${item.id}" role="tab" aria-selected="${item.id===active}"><span aria-hidden="true">${item.icon}</span>${esc(item.label)}</button>`).join("")}</div>`;
  }
  function bindPlatformSectionTabs(){
    $$('[data-platform-section]').forEach(button=>button.onclick=()=>navigate(button.dataset.platformSection));
  }


  // Report Card Enterprise v7.4.0 Final production-stability multi-platform release
  const CERTIFICATE_TYPES=Object.freeze([
    {value:"student_promotion",label:"Student Promotion",requiresTerm:true,requiresClass:true},
    {value:"jhs_completion",label:"JHS 3 Completion",requiresTerm:false,requiresClass:true},
    {value:"teacher_recognition",label:"Teacher Recognition",requiresTerm:false,requiresClass:false}
  ]);
  function certificateTypeLabel(value){return CERTIFICATE_TYPES.find(item=>item.value===value)?.label||String(value||"Certificate").replaceAll("_"," ")}
  // ---------------------------------------------------------------------------
  // Professional Student & Staff ID Card Generator, Teacher Profile, Timetable r12
  // CR80 85.60 x 53.98 mm, rendered at approximately 300 PPI (1011 x 638 px).
  // Issued cards render from their immutable database snapshot so historical cards
  // never change when a student later changes class, profile, or academic year.
  // ---------------------------------------------------------------------------
  const ID_CARD_WIDTH=1011,ID_CARD_HEIGHT=638,ID_CARD_A4_WIDTH=2480,ID_CARD_A4_HEIGHT=3508,ID_CARD_BATCH_MAX=50;
  function idCardVerificationUrl(token){
    const school=state.boot?.school||{},base=school.verification_base_url||`${location.origin}${location.pathname}`;
    return `${base}${base.includes("?")?"&":"?"}idcard=${encodeURIComponent(token)}`;
  }
  function idCardSettingsDefaults(raw={}){return {
    template_code:["classic","modern","minimal"].includes(raw.template_code)?raw.template_code:"modern",
    card_title:String(raw.card_title||"STUDENT ID CARD").slice(0,80),validity_months:Number(raw.validity_months||12),
    show_date_of_birth:raw.show_date_of_birth===true,show_gender:raw.show_gender===true,show_guardian_phone:raw.show_guardian_phone===true,
    show_school_address:raw.show_school_address!==false,show_school_phone:raw.show_school_phone!==false,show_school_email:raw.show_school_email!==false,
    show_principal_signature:raw.show_principal_signature!==false,show_principal_name:raw.show_principal_name!==false,show_principal_title:raw.show_principal_title!==false,
    staff_card_title:String(raw.staff_card_title||"STAFF ID CARD").slice(0,80),staff_validity_months:Number(raw.staff_validity_months||24),
    back_message:String(raw.back_message||"This card remains the property of the school. If found, please return it to the school administration.").slice(0,500)
  }}
  function idCardComputedStatus(card){return String(card?.computed_status||card?.status||"unknown")}
  function idCardStatusBadge(card){return statusBadge(idCardComputedStatus(card))}
  function idCardAddMonths(value,months){const d=new Date(`${value}T12:00:00Z`);if(Number.isNaN(d.getTime()))return value;d.setUTCMonth(d.getUTCMonth()+Number(months||12));return d.toISOString().slice(0,10)}
  function idCardSafeColour(value,fallback){return /^#[0-9a-f]{6}$/i.test(String(value||""))?String(value):fallback}
  function idCardCanvasBlob(canvas,quality=.97){return new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error("ID card image could not be encoded")),"image/jpeg",quality))}
  function releaseCanvas(canvas){if(canvas){canvas.width=1;canvas.height=1}}
  function fitIdCardText(ctx,text,maxWidth,size,minSize=18,weight=700,family='Arial, Helvetica, sans-serif'){
    let current=size;ctx.font=`${weight} ${current}px ${family}`;while(current>minSize&&ctx.measureText(String(text||"")).width>maxWidth){current-=1;ctx.font=`${weight} ${current}px ${family}`}return current
  }
  function idCardInitials(name){return String(name||"Student").split(/\s+/).filter(Boolean).slice(0,2).map(v=>v[0]?.toUpperCase()||"").join("")||"ID"}
  async function idCardQrCanvas(text,size=250){
    const box=byId("qrScratch");if(!box)throw new Error("QR rendering container is unavailable");box.innerHTML="";if(!window.QRCode)throw new Error("QR rendering library is unavailable");
    new window.QRCode(box,{text,width:size,height:size,correctLevel:window.QRCode.CorrectLevel.M});await sleep(90);
    const rendered=box.querySelector("canvas")||box.querySelector("img");if(!rendered)throw new Error("QR verification code could not be rendered");return rendered;
  }
  async function idCardAssets(card){
    const snap=card?.snapshot||{},student=snap.student||{},school=snap.school||{},principal=snap.principal||{};let logo=null,photo=null,signature=null;
    try{logo=await loadImage(schoolDisplayLogo(school))}catch(_){try{logo=await loadImage(schoolDisplayLogo())}catch(__){}}
    if(student.photo_url){try{photo=await loadPrivateImageAsset(CONFIG.photoBucket,student.photo_url,"Student ID photograph")}catch(error){await reportClientError(error,{source:"id_card_photo",card_id:card?.id||""}).catch(()=>{})}}
    if(principal.signature_path){try{signature=await loadPrivateImageAsset(CONFIG.signatureBucket,principal.signature_path,"Principal ID-card signature")}catch(error){await reportClientError(error,{source:"id_card_principal_signature",card_id:card?.id||""}).catch(()=>{})}}
    return {logo,photo,signature};
  }
  async function drawStudentIdCard(card,side="front"){
    const snap=card?.snapshot||{},student=snap.student||{},academic=snap.academic||{},school=snap.school||{},settings=idCardSettingsDefaults(snap.template||{}),canvas=document.createElement("canvas");canvas.width=ID_CARD_WIDTH;canvas.height=ID_CARD_HEIGHT;
    const principal=snap.principal||{},ctx=canvas.getContext("2d"),primary=idCardSafeColour(school.primary_colour,"#0a2f73"),accent=idCardSafeColour(school.accent_colour,"#f1b51c"),verification=idCardVerificationUrl(card.verification_token||snap.card?.verification_token||"");let logo=null,photo=null,signature=null;({logo,photo,signature}=await idCardAssets(card));
    ctx.fillStyle="#ffffff";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.textBaseline="alphabetic";
    if(settings.template_code==="minimal"){ctx.fillStyle=primary;ctx.fillRect(0,0,22,canvas.height);ctx.fillStyle=accent;ctx.fillRect(22,0,8,canvas.height)}
    else if(settings.template_code==="classic"){ctx.strokeStyle=primary;ctx.lineWidth=16;ctx.strokeRect(8,8,canvas.width-16,canvas.height-16);ctx.fillStyle=accent;ctx.fillRect(16,104,canvas.width-32,8)}
    else{ctx.fillStyle=primary;ctx.fillRect(0,0,canvas.width,122);ctx.fillStyle=accent;ctx.fillRect(0,122,canvas.width,13);ctx.fillRect(0,canvas.height-18,canvas.width,18)}
    if(side==="front"){
      if(logo){drawImageContain(ctx,logo,46,26,74,74)}
      ctx.fillStyle=settings.template_code==="modern"?"#fff":primary;fitIdCardText(ctx,school.school_name||schoolDisplayName(),650,34,22,800);ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),145,62,650);
      ctx.font="700 22px Arial";ctx.fillStyle=settings.template_code==="modern"?accent:primary;ctx.fillText(settings.card_title.toUpperCase(),145,96);
      if(school.motto){ctx.font="italic 16px Arial";ctx.fillStyle=settings.template_code==="modern"?"#eaf2ff":"#56647a";ctx.fillText(String(school.motto).slice(0,90),145,119,650)}
      const px=54,py=176,pw=242,ph=316;ctx.fillStyle="#eef3fa";ctx.fillRect(px,py,pw,ph);ctx.strokeStyle="#b9c6d8";ctx.lineWidth=3;ctx.strokeRect(px,py,pw,ph);
      if(photo)drawImageCover(ctx,photo,px+5,py+5,pw-10,ph-10);else{ctx.fillStyle=primary;ctx.font="800 74px Arial";ctx.textAlign="center";ctx.fillText(idCardInitials(student.full_name),px+pw/2,py+ph/2+26);ctx.textAlign="left"}
      let y=196;ctx.fillStyle="#64748b";ctx.font="700 15px Arial";ctx.fillText("STUDENT NAME",330,y);y+=38;ctx.fillStyle="#10213c";fitIdCardText(ctx,student.full_name||"Student",445,34,21,850);ctx.fillText(student.full_name||"Student",330,y,445);y+=42;
      const field=(label,value)=>{ctx.fillStyle="#718096";ctx.font="700 14px Arial";ctx.fillText(label,330,y);y+=25;ctx.fillStyle="#132443";fitIdCardText(ctx,value||"—",420,23,17,750);ctx.fillText(String(value||"—"),330,y,420);y+=37};
      field("ADMISSION NUMBER",student.admission_no);field("CLASS",academic.class_name);field("ACADEMIC YEAR",academic.academic_year_name);
      if(settings.show_gender&&student.gender)field("GENDER",student.gender);if(settings.show_date_of_birth&&student.date_of_birth)field("DATE OF BIRTH",isoDate(student.date_of_birth));
      const qr=await idCardQrCanvas(verification,230);if(qr){ctx.fillStyle="#fff";ctx.fillRect(802,350,174,174);ctx.drawImage(qr,811,359,156,156)}
      ctx.fillStyle="#64748b";ctx.font="700 13px Arial";ctx.textAlign="center";ctx.fillText("SCAN TO VERIFY",889,536);ctx.textAlign="left";
      ctx.fillStyle="#10213c";ctx.font="800 18px monospace";ctx.fillText(card.card_number||snap.card?.card_number||"",54,542,720);ctx.font="600 15px Arial";ctx.fillStyle="#56647a";ctx.fillText(`Issued ${isoDate(card.issue_date||snap.card?.issue_date)}  •  Expires ${isoDate(card.expires_on||snap.card?.expires_on)}`,54,579,720);
    }else{
      ctx.fillStyle=primary;ctx.fillRect(0,0,canvas.width,98);ctx.fillStyle="#fff";ctx.font="850 28px Arial";ctx.textAlign="center";ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),canvas.width/2,59,850);ctx.textAlign="left";
      const qr=await idCardQrCanvas(verification,300);if(qr){ctx.fillStyle="#fff";ctx.fillRect(62,156,260,260);ctx.strokeStyle="#d9e0ea";ctx.lineWidth=2;ctx.strokeRect(62,156,260,260);ctx.drawImage(qr,76,170,232,232)}
      ctx.fillStyle="#132443";ctx.font="850 22px Arial";ctx.fillText("VERIFY THIS CARD",364,170);ctx.fillStyle="#56647a";ctx.font="500 17px Arial";drawWrapped(ctx,"Scan the QR code to confirm whether this issued student ID card is valid, expired, revoked, or replaced.",364,205,570,25,4);
      let cy=300;const contact=[];if(settings.show_school_address&&school.address)contact.push(["Address",school.address]);if(settings.show_school_phone&&school.phone)contact.push(["Phone",school.phone]);if(settings.show_school_email&&school.email)contact.push(["Email",school.email]);if(school.website)contact.push(["Website",school.website]);if(settings.show_guardian_phone&&student.guardian_phone)contact.push(["Guardian contact",student.guardian_phone]);
      for(const [label,value] of contact.slice(0,4)){ctx.fillStyle="#718096";ctx.font="700 14px Arial";ctx.fillText(`${label.toUpperCase()}:`,364,cy);ctx.fillStyle="#132443";ctx.font="600 16px Arial";ctx.fillText(String(value),485,cy,470);cy+=27}
      if(settings.show_principal_signature&&(signature||principal.full_name)){const left=640,right=936,lineY=465;if(signature)drawSignatureOnLine(ctx,signature,left,right,lineY,72,"#64748b",1.4);else{ctx.strokeStyle="#64748b";ctx.beginPath();ctx.moveTo(left,lineY);ctx.lineTo(right,lineY);ctx.stroke()}ctx.textAlign="center";ctx.fillStyle="#10213c";ctx.font="700 15px Arial";if(settings.show_principal_name&&principal.full_name)ctx.fillText(String(principal.full_name),788,489,300);if(settings.show_principal_title)ctx.fillStyle="#64748b",ctx.font="600 13px Arial",ctx.fillText("Principal's Signature",788,510);ctx.textAlign="left"}
      ctx.fillStyle="#334155";ctx.font="500 15px Arial";drawWrapped(ctx,settings.back_message,62,492,540,22,3);ctx.fillStyle="#64748b";ctx.font="700 13px Arial";ctx.fillText("CARD NUMBER",62,570);ctx.fillStyle="#10213c";ctx.font="800 18px monospace";ctx.fillText(card.card_number||snap.card?.card_number||"",180,570,600);ctx.fillStyle=accent;ctx.fillRect(0,canvas.height-18,canvas.width,18);
    }
    return canvas;
  }
  async function createStudentIdCardPdf(card){
    const blobs=[];for(const side of ["front","back"]){const canvas=await drawStudentIdCard(card,side);try{blobs.push(await idCardCanvasBlob(canvas,.985))}finally{releaseCanvas(canvas)}}
    const widthPt=85.60/25.4*72,heightPt=53.98/25.4*72;return imagesPdf(blobs,widthPt,heightPt,ID_CARD_WIDTH,ID_CARD_HEIGHT);
  }
  async function previewStudentIdCard(card){
    setLoading(true);try{const front=await drawStudentIdCard(card,"front"),back=await drawStudentIdCard(card,"back"),frontUrl=front.toDataURL("image/jpeg",.9),backUrl=back.toDataURL("image/jpeg",.9);releaseCanvas(front);releaseCanvas(back);modal("Student ID Card Preview",`${card.student_name||card.snapshot?.student?.full_name||"Student"} • ${card.card_number}`,`<div class="id-card-preview-grid"><figure><img src="${frontUrl}" alt="Student ID card front"><figcaption>Front</figcaption></figure><figure><img src="${backUrl}" alt="Student ID card back"><figcaption>Back</figcaption></figure></div>`,`<button class="button ghost" id="idCardPreviewClose">Close</button><button class="button primary" id="idCardPreviewDownload">Download front + back PDF</button>`,`large`);byId("idCardPreviewClose").onclick=closeModal;byId("idCardPreviewDownload").onclick=async()=>{const button=byId("idCardPreviewDownload");button.disabled=true;try{downloadBlob(`${safeArchiveSegment(card.card_number||"student-id")}.pdf`,await createStudentIdCardPdf(card));toast("ID card PDF downloaded")}catch(error){toast("ID card not downloaded",friendlyError(error),"error",8000)}finally{button.disabled=false}}}catch(error){toast("Preview unavailable",friendlyError(error),"error",8000)}finally{setLoading(false)}
  }
  async function drawIdCardA4Sheet(cards,side){
    const sheet=document.createElement("canvas");sheet.width=ID_CARD_A4_WIDTH;sheet.height=ID_CARD_A4_HEIGHT;const ctx=sheet.getContext("2d");ctx.fillStyle="#fff";ctx.fillRect(0,0,sheet.width,sheet.height);
    const scale=1,cw=Math.round(ID_CARD_WIDTH*scale),ch=Math.round(ID_CARD_HEIGHT*scale),gapX=80,gapY=35,totalW=cw*2+gapX,totalH=ch*5+gapY*4,startX=Math.round((sheet.width-totalW)/2),startY=Math.round((sheet.height-totalH)/2);
    for(let i=0;i<cards.length;i+=1){const row=Math.floor(i/2),col=i%2,printCol=side==="back"?1-col:col,x=startX+printCol*(cw+gapX),y=startY+row*(ch+gapY),cardCanvas=await drawStudentIdCard(cards[i],side);ctx.drawImage(cardCanvas,x,y,cw,ch);ctx.strokeStyle="#d8dee8";ctx.lineWidth=2;ctx.strokeRect(x,y,cw,ch);releaseCanvas(cardCanvas)}
    return sheet;
  }
  async function createIdCardBatchA4Pdf(cards){
    if(!cards.length)throw new Error("No ID cards are available for batch printing");if(cards.length>ID_CARD_BATCH_MAX)throw new Error(`Batch printing is limited to ${ID_CARD_BATCH_MAX} cards per PDF for device memory safety. Filter to one class or a smaller set.`);
    const pages=[];for(let offset=0;offset<cards.length;offset+=10){const group=cards.slice(offset,offset+10);for(const side of ["front","back"]){const sheet=await drawIdCardA4Sheet(group,side);try{pages.push(await idCardCanvasBlob(sheet,.97))}finally{releaseCanvas(sheet)}}await sleep(20)}
    return imagesPdf(pages,595.28,841.89,ID_CARD_A4_WIDTH,ID_CARD_A4_HEIGHT);
  }
  async function downloadIdCardBatchA4(cards){if(state.idCardBusy)return;state.idCardBusy=true;setLoading(true);try{const eligible=cards.filter(card=>["active","expired"].includes(idCardComputedStatus(card)));if(!eligible.length)throw new Error("No active or expired issued cards are available in this filter");const pdf=await createIdCardBatchA4Pdf(eligible);downloadBlob(`student-id-cards-${safeArchiveSegment(state.idCardYear||"school")}-${safeArchiveSegment(state.idCardClass||"all")}.pdf`,pdf);toast("Printable ID cards downloaded",`${eligible.length} card${eligible.length===1?"":"s"} prepared as duplex A4 front/back sheets.`)}catch(error){toast("Batch PDF not created",friendlyError(error),"error",9000);await reportClientError(error,{source:"id_card_batch_pdf"})}finally{state.idCardBusy=false;setLoading(false)}}
  function renderIdCardStats(stats={}){return `<div class="stat-grid id-card-stat-grid"><div class="stat-card"><div class="stat-icon blue">▥</div><div><span>Issued records</span><strong>${number(stats.total)}</strong></div></div><div class="stat-card"><div class="stat-icon green">✓</div><div><span>Active</span><strong>${number(stats.active)}</strong></div></div><div class="stat-card"><div class="stat-icon gold">⌛</div><div><span>Expired</span><strong>${number(stats.expired)}</strong></div></div><div class="stat-card"><div class="stat-icon red">×</div><div><span>Revoked / replaced</span><strong>${number(Number(stats.revoked||0)+Number(stats.replaced||0))}</strong></div></div></div>`}
  async function renderIdCards(token,force=false){
    if(role()!=="system_admin")throw new Error("Only the System Administrator can manage ID cards");
    const mode=state.idCardMode||"student";if(mode==="staff"&&licenseFeatureEnabled("staff_id_cards"))return renderStaffIdCards(token,force);
    const years=state.boot?.academic_years||[],classes=state.boot?.classes||[];state.idCardYear=byId("idCardYear")?.value||state.idCardYear||activeYear()?.id||years[0]?.id||"";state.idCardClass=byId("idCardClass")?.value??state.idCardClass;state.idCardStatus=byId("idCardStatus")?.value??state.idCardStatus;
    if(force||!state.idCardConsole)state.idCardConsole=await rpc("get_id_card_console",{target_academic_year_id:state.idCardYear||null,target_class_id:state.idCardClass||null,target_status:state.idCardStatus||null});if(token!==state.viewToken)return;const data=state.idCardConsole||{},cards=data.cards||[],settings=idCardSettingsDefaults(data.settings||{});
    byId("content").innerHTML=`<div class="page-head"><div><h3>ID Card Management</h3><p>Professional immutable student and staff cards with QR verification, lifecycle controls, and CR80 printing.</p></div><div class="page-actions"><button class="button outline" id="idCardSettingsButton">Card settings</button><button class="button secondary" id="idCardBatchButton" ${cards.length?"":"disabled"}>Download printable A4</button><button class="button primary" id="idCardGenerateButton">Generate student IDs</button></div></div><div class="segmented-tabs id-card-tabs"><button class="active" data-id-card-mode="student">Student ID Cards</button>${licenseFeatureEnabled("staff_id_cards")?`<button data-id-card-mode="staff">Staff ID Cards</button>`:""}</div>${renderIdCardStats(data.stats||{})}<section class="panel"><div class="toolbar"><select id="idCardYear">${years.map(y=>`<option value="${attr(y.id)}" ${y.id===state.idCardYear?"selected":""}>${esc(y.name)}</option>`).join("")}</select><select id="idCardClass"><option value="">All classes</option>${classes.map(c=>`<option value="${attr(c.id)}" ${c.id===state.idCardClass?"selected":""}>${esc(c.name)}</option>`).join("")}</select><select id="idCardStatus"><option value="">All statuses</option>${["active","expired","revoked","replaced"].map(v=>`<option value="${v}" ${v===state.idCardStatus?"selected":""}>${esc(statusText(v))}</option>`).join("")}</select><div class="id-card-template-chip">Template: <strong>${esc(statusText(settings.template_code))}</strong> • ${settings.validity_months} month validity</div></div>${cards.length?`<div class="table-shell"><table><thead><tr><th>Student</th><th>Class / year</th><th>Card number</th><th>Issue / expiry</th><th>Status</th><th>Revision</th><th></th></tr></thead><tbody>${cards.map(card=>`<tr><td><div class="cell-copy"><strong>${esc(card.student_name)}</strong><small>${esc(card.admission_no||"")}</small></div></td><td><div class="cell-copy"><strong>${esc(card.class_name||"")}</strong><small>${esc(card.academic_year_name||"")}</small></div></td><td><code>${esc(card.card_number)}</code></td><td><div class="cell-copy"><strong>${esc(isoDate(card.issue_date))}</strong><small>Expires ${esc(isoDate(card.expires_on))}</small></div></td><td>${idCardStatusBadge(card)}</td><td>R${number(card.revision_no||1)}</td><td><div class="button-row"><button class="button ghost small" data-id-card-preview="${attr(card.id)}">Preview</button><button class="button outline small" data-id-card-download="${attr(card.id)}">PDF</button>${card.status==="active"?`<button class="button secondary small" data-id-card-replace="${attr(card.id)}">Replace</button><button class="button danger small" data-id-card-revoke="${attr(card.id)}">Revoke</button>`:card.status==="revoked"||card.status==="replaced"?`<button class="button danger small" data-id-card-delete="${attr(card.id)}">Delete permanently</button>`:""}</div></td></tr>`).join("")}</tbody></table></div>`:emptyState("No ID cards in this filter","Generate cards for an active class or adjust the filters.")}</section>`;
    const cardById=id=>cards.find(card=>card.id===id);$$('[data-id-card-mode]').forEach(button=>button.onclick=()=>{state.idCardMode=button.dataset.idCardMode;state.idCardConsole=null;state.staffIdCardConsole=null;renderIdCards(state.viewToken,true)});byId("idCardYear").onchange=()=>{state.idCardYear=byId("idCardYear").value;state.idCardConsole=null;renderIdCards(state.viewToken,true)};byId("idCardClass").onchange=()=>{state.idCardClass=byId("idCardClass").value;state.idCardConsole=null;renderIdCards(state.viewToken,true)};byId("idCardStatus").onchange=()=>{state.idCardStatus=byId("idCardStatus").value;state.idCardConsole=null;renderIdCards(state.viewToken,true)};byId("idCardSettingsButton").onclick=()=>openIdCardSettings(settings);byId("idCardGenerateButton").onclick=openIdCardGenerator;byId("idCardBatchButton").onclick=()=>downloadIdCardBatchA4(cards);$$('[data-id-card-preview]').forEach(button=>button.onclick=()=>previewStudentIdCard(cardById(button.dataset.idCardPreview)));$$('[data-id-card-download]').forEach(button=>button.onclick=async()=>{const card=cardById(button.dataset.idCardDownload);button.disabled=true;try{downloadBlob(`${safeArchiveSegment(card.card_number)}.pdf`,await createStudentIdCardPdf(card));toast("ID card PDF downloaded")}catch(error){toast("ID card not downloaded",friendlyError(error),"error",8000)}finally{button.disabled=false}});$$('[data-id-card-revoke]').forEach(button=>button.onclick=()=>revokeIdCard(cardById(button.dataset.idCardRevoke)));$$('[data-id-card-replace]').forEach(button=>button.onclick=()=>replaceIdCard(cardById(button.dataset.idCardReplace)));$$('[data-id-card-delete]').forEach(button=>button.onclick=()=>deleteStudentIdCardPermanently(cardById(button.dataset.idCardDelete)));
  }
  function openIdCardSettings(settings){
    const cfg=idCardSettingsDefaults(settings);modal("ID Card Settings","Controlled templates keep student and staff cards consistent across web, Android, Windows, and print.",`<form id="idCardSettingsForm" class="form-grid"><label class="field"><span>Template</span><select name="template_code">${["modern","classic","minimal"].map(v=>`<option value="${v}" ${cfg.template_code===v?"selected":""}>${esc(statusText(v))}</option>`).join("")}</select></label><label class="field"><span>Student validity (months)</span><input name="validity_months" type="number" min="1" max="60" value="${attr(cfg.validity_months)}" required></label><label class="field"><span>Student card title</span><input name="card_title" maxlength="80" value="${attr(cfg.card_title)}" required></label><label class="field"><span>Staff validity (months)</span><input name="staff_validity_months" type="number" min="1" max="60" value="${attr(cfg.staff_validity_months)}" required></label><label class="field full"><span>Staff card title</span><input name="staff_card_title" maxlength="80" value="${attr(cfg.staff_card_title)}" required></label><div class="field full"><span>Card fields and authorization</span><div class="check-grid"><label><input type="checkbox" name="show_date_of_birth" ${cfg.show_date_of_birth?"checked":""}> Date of birth</label><label><input type="checkbox" name="show_gender" ${cfg.show_gender?"checked":""}> Gender</label><label><input type="checkbox" name="show_guardian_phone" ${cfg.show_guardian_phone?"checked":""}> Guardian phone on student back</label><label><input type="checkbox" name="show_school_address" ${cfg.show_school_address?"checked":""}> School address</label><label><input type="checkbox" name="show_school_phone" ${cfg.show_school_phone?"checked":""}> School phone</label><label><input type="checkbox" name="show_school_email" ${cfg.show_school_email?"checked":""}> School email</label><label><input type="checkbox" name="show_principal_signature" ${cfg.show_principal_signature?"checked":""}> Principal digital signature</label><label><input type="checkbox" name="show_principal_name" ${cfg.show_principal_name?"checked":""}> Principal name</label><label><input type="checkbox" name="show_principal_title" ${cfg.show_principal_title?"checked":""}> Principal title</label></div></div><label class="field full"><span>Back-of-card message</span><textarea name="back_message" maxlength="500" rows="4">${esc(cfg.back_message)}</textarea></label></form>`,`<button class="button ghost" id="idCardSettingsCancel">Cancel</button><button class="button primary" id="idCardSettingsSave">Save settings</button>`,`medium`);byId("idCardSettingsCancel").onclick=closeModal;byId("idCardSettingsSave").onclick=async()=>{const form=byId("idCardSettingsForm"),values=formObject(form),button=byId("idCardSettingsSave");button.disabled=true;try{const bools=["show_date_of_birth","show_gender","show_guardian_phone","show_school_address","show_school_phone","show_school_email","show_principal_signature","show_principal_name","show_principal_title"],payload={...values};bools.forEach(key=>payload[key]=form.elements[key].checked);await rpc("save_id_card_settings",{payload});closeModal();state.idCardConsole=null;state.staffIdCardConsole=null;toast("ID card settings saved");await renderIdCards(state.viewToken,true)}catch(error){toast("Settings not saved",friendlyError(error),"error",8000)}finally{button.disabled=false}};
  }
  async function openIdCardGenerator(){
    const years=state.boot?.academic_years||[],classes=state.boot?.classes||[],settings=idCardSettingsDefaults(state.idCardConsole?.settings||{}),today=new Date().toISOString().slice(0,10),expires=idCardAddMonths(today,settings.validity_months);modal("Generate Student ID Cards","Choose one academic year and class. Existing active cards are protected from accidental duplicate issuance.",`<form id="idCardGenerateForm" class="form-grid"><label class="field"><span>Academic year</span><select name="academic_year_id" required>${years.map(y=>`<option value="${attr(y.id)}" ${y.id===(state.idCardYear||activeYear()?.id)?"selected":""}>${esc(y.name)}</option>`).join("")}</select></label><label class="field"><span>Class</span><select name="class_id" required><option value="">Select class</option>${classes.map(c=>`<option value="${attr(c.id)}" ${c.id===state.idCardClass?"selected":""}>${esc(c.name)}</option>`).join("")}</select></label><label class="field"><span>Issue date</span><input type="date" name="issue_date" value="${today}" required></label><label class="field"><span>Expiry date</span><input type="date" name="expires_on" value="${expires}" required></label><label class="field full"><span>Find student</span><input id="idCardCandidateSearch" type="search" placeholder="Name or admission number"></label></form><div class="id-card-candidate-area"><div class="empty"><strong>Select a class</strong><span>Eligible active students will appear here.</span></div></div>`,`<button class="button ghost" id="idCardGenerateCancel">Cancel</button><button class="button primary" id="idCardIssueSelected" disabled>Issue selected cards</button>`,`large`);const form=byId("idCardGenerateForm"),area=$(".id-card-candidate-area");byId("idCardGenerateCancel").onclick=closeModal;
    const syncExpiry=()=>{const value=form.elements.issue_date.value;if(value)form.elements.expires_on.value=idCardAddMonths(value,settings.validity_months)};form.elements.issue_date.onchange=syncExpiry;
    let candidates=[];const renderCandidates=()=>{const needle=byId("idCardCandidateSearch").value.trim().toLowerCase(),visible=candidates.filter(item=>!needle||`${item.full_name} ${item.admission_no}`.toLowerCase().includes(needle));area.innerHTML=visible.length?`<div class="id-card-candidate-toolbar"><label><input type="checkbox" id="idCardSelectAll"> Select all eligible</label><span>${visible.length} student${visible.length===1?"":"s"}</span></div><div class="id-card-candidate-results">${visible.map(item=>`<label class="id-card-candidate ${item.active_card_id?"disabled":""}"><input type="checkbox" name="id_card_candidate" value="${attr(item.student_id)}" ${item.active_card_id?"disabled":""}><span><strong>${esc(item.full_name)}</strong><small>${esc(item.admission_no)} • ${esc(item.class_name)}${item.active_card_id?` • ${esc(statusText(item.active_card_status||"active"))} card ${esc(item.active_card_number)}`:""}</small></span></label>`).join("")}</div>`:emptyState("No students found","Adjust the search or selected class.");const update=()=>{byId("idCardIssueSelected").disabled=!$$('[name="id_card_candidate"]:checked',area).length};$$('[name="id_card_candidate"]',area).forEach(input=>input.onchange=update);const all=byId("idCardSelectAll");if(all)all.onchange=()=>{$$('[name="id_card_candidate"]:not(:disabled)',area).forEach(input=>input.checked=all.checked);update()};update()};
    const load=async()=>{const year=form.elements.academic_year_id.value,classId=form.elements.class_id.value;if(!year||!classId){candidates=[];renderCandidates();return}area.innerHTML=`<div class="empty">Loading eligible students…</div>`;try{candidates=await rpc("list_id_card_candidates",{target_academic_year_id:year,target_class_id:classId,search_text:""});renderCandidates()}catch(error){candidates=[];area.innerHTML=emptyState("Students unavailable",friendlyError(error))}};form.elements.academic_year_id.onchange=load;form.elements.class_id.onchange=load;byId("idCardCandidateSearch").oninput=renderCandidates;if(form.elements.class_id.value)await load();
    byId("idCardIssueSelected").onclick=async()=>{const ids=$$('[name="id_card_candidate"]:checked',area).map(input=>input.value);if(!ids.length)return;const values=formObject(form),button=byId("idCardIssueSelected");if(!window.confirm(`Issue ${ids.length} student ID card${ids.length===1?"":"s"}? Each card receives an immutable issuance snapshot and unique QR verification token.`))return;button.disabled=true;button.textContent="Issuing";try{const result=await rpc("issue_student_id_cards",{target_academic_year_id:values.academic_year_id,target_class_id:values.class_id,target_student_ids:ids,target_issue_date:values.issue_date,target_expires_on:values.expires_on});closeModal();state.idCardConsole=null;state.idCardYear=values.academic_year_id;state.idCardClass=values.class_id;state.idCardStatus="";toast("Student ID cards issued",`${result.created_count||0} card${Number(result.created_count||0)===1?"":"s"} created${result.skipped_count?`; ${result.skipped_count} protected duplicate${result.skipped_count===1?"":"s"} skipped`:""}.`);await renderIdCards(state.viewToken,true)}catch(error){toast("ID cards not issued",friendlyError(error),"error",9000)}finally{button.disabled=false;button.textContent="Issue selected cards"}};
  }
  async function revokeIdCard(card){const reason=window.prompt(`Reason for revoking ${card.card_number}:`,"")||"";if(reason.trim().length<5){if(reason)toast("Revocation reason required","Enter at least five characters.","error");return}if(!await confirmAction("Revoke student ID card","The QR verification page will immediately show this card as revoked. The historical record will be retained.","Revoke card",true))return;try{await rpc("revoke_student_id_card",{target_card_id:card.id,reason_text:reason.trim()});state.idCardConsole=null;toast("ID card revoked");await renderIdCards(state.viewToken,true)}catch(error){toast("ID card not revoked",friendlyError(error),"error",8000)}}
  async function replaceIdCard(card){const reason=window.prompt(`Reason for replacing ${card.card_number}:`,"Lost or damaged card")||"";if(reason.trim().length<5)return;const today=new Date().toISOString().slice(0,10),settings=idCardSettingsDefaults(state.idCardConsole?.settings||{}),expires=idCardAddMonths(today,settings.validity_months);modal("Replace Student ID Card","The existing card will be preserved as Replaced and its QR will no longer verify as active. A new card number and verification token will be issued.",`<form id="idCardReplaceForm" class="form-grid"><label class="field"><span>Issue date</span><input type="date" name="issue_date" value="${today}" required></label><label class="field"><span>Expiry date</span><input type="date" name="expires_on" value="${expires}" required></label><label class="field full"><span>Reason</span><textarea name="reason" minlength="5" required>${esc(reason.trim())}</textarea></label></form>`,`<button class="button ghost" id="idCardReplaceCancel">Cancel</button><button class="button primary" id="idCardReplaceConfirm">Create replacement</button>`,`small`);byId("idCardReplaceCancel").onclick=closeModal;byId("idCardReplaceConfirm").onclick=async()=>{const values=formObject(byId("idCardReplaceForm")),button=byId("idCardReplaceConfirm");button.disabled=true;try{await rpc("replace_student_id_card",{target_card_id:card.id,reason_text:values.reason,target_issue_date:values.issue_date,target_expires_on:values.expires_on});closeModal();state.idCardConsole=null;toast("Replacement ID card issued");await renderIdCards(state.viewToken,true)}catch(error){toast("Replacement not created",friendlyError(error),"error",8000)}finally{button.disabled=false}}}

  function deleteStudentIdCardPermanently(card){if(!card)return;modal("Delete Student ID Card Permanently","Only revoked or replaced cards can be removed. The issued-card record is deleted, while a minimal immutable tombstone remains so the old QR can never become valid again.",`<div class="destructive-confirmation"><label class="field"><span>Deletion reason</span><textarea id="studentIdDeleteReason" minlength="5" required placeholder="Explain why this revoked/replaced card must be removed"></textarea></label><label class="field"><span>Type DELETE to confirm</span><input id="studentIdDeleteText" autocomplete="off"></label><p class="help-text">Card ${esc(card.card_number)} • ${esc(statusText(card.status))}. This action cannot be undone.</p></div>`,`<button class="button ghost" id="studentIdDeleteCancel">Cancel</button><button class="button danger" id="studentIdDeleteConfirm">Delete permanently</button>`,`small`);byId("studentIdDeleteCancel").onclick=closeModal;byId("studentIdDeleteConfirm").onclick=async()=>{const reason=byId("studentIdDeleteReason").value.trim(),confirmation=byId("studentIdDeleteText").value.trim();if(reason.length<5||confirmation!=="DELETE"){toast("ID card not deleted","Enter a reason of at least five characters and type DELETE exactly.","error");return}const button=byId("studentIdDeleteConfirm");button.disabled=true;try{await rpc("delete_student_id_card_permanently",{target_card_id:card.id,reason_text:reason,confirmation_text:confirmation});closeModal();state.idCardConsole=null;toast("ID card permanently removed","A non-sensitive deletion tombstone was retained for QR invalidation and audit continuity.");await renderIdCards(state.viewToken,true)}catch(error){toast("ID card not deleted",friendlyError(error),"error",8500)}finally{button.disabled=false}}}

  function staffIdCardVerificationUrl(token){const school=state.boot?.school||{},base=school.verification_base_url||`${location.origin}${location.pathname}`;return `${base}${base.includes("?")?"&":"?"}staffcard=${encodeURIComponent(token)}`}
  async function staffIdCardAssets(card){const snap=card?.snapshot||{},staff=snap.staff||{},school=snap.school||{},principal=snap.principal||{};let logo=null,photo=null,signature=null;try{logo=await loadImage(schoolDisplayLogo(school))}catch(_){try{logo=await loadImage(schoolDisplayLogo())}catch(__){}}if(staff.photo_url){try{photo=await loadPrivateImageAsset(CONFIG.staffPhotoBucket,staff.photo_url,"Staff ID photograph")}catch(error){await reportClientError(error,{source:"staff_id_photo",card_id:card?.id||""})}}if(principal.signature_path){try{signature=await loadPrivateImageAsset(CONFIG.signatureBucket,principal.signature_path,"Principal ID-card signature")}catch(error){await reportClientError(error,{source:"staff_id_principal_signature",card_id:card?.id||""})}}return{logo,photo,signature}}
  async function drawStaffIdCard(card,side="front"){
    const snap=card?.snapshot||{},staff=snap.staff||{},academic=snap.academic||{},school=snap.school||{},principal=snap.principal||{},settings=idCardSettingsDefaults(snap.template||{}),canvas=document.createElement("canvas");canvas.width=ID_CARD_WIDTH;canvas.height=ID_CARD_HEIGHT;const ctx=canvas.getContext("2d"),primary=idCardSafeColour(school.primary_colour,"#0a2f73"),accent=idCardSafeColour(school.accent_colour,"#f1b51c"),verification=staffIdCardVerificationUrl(card.verification_token||snap.card?.verification_token||"");const {logo,photo,signature}=await staffIdCardAssets(card);ctx.fillStyle="#fff";ctx.fillRect(0,0,canvas.width,canvas.height);if(settings.template_code==="minimal"){ctx.fillStyle=primary;ctx.fillRect(0,0,22,canvas.height);ctx.fillStyle=accent;ctx.fillRect(22,0,8,canvas.height)}else if(settings.template_code==="classic"){ctx.strokeStyle=primary;ctx.lineWidth=16;ctx.strokeRect(8,8,canvas.width-16,canvas.height-16);ctx.fillStyle=accent;ctx.fillRect(16,104,canvas.width-32,8)}else{ctx.fillStyle=primary;ctx.fillRect(0,0,canvas.width,122);ctx.fillStyle=accent;ctx.fillRect(0,122,canvas.width,13);ctx.fillRect(0,canvas.height-18,canvas.width,18)}
    if(side==="front"){if(logo){drawImageContain(ctx,logo,46,26,74,74)}ctx.fillStyle=settings.template_code==="modern"?"#fff":primary;fitIdCardText(ctx,school.school_name||schoolDisplayName(),650,34,22,800);ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),145,62,650);ctx.font="700 22px Arial";ctx.fillStyle=settings.template_code==="modern"?accent:primary;ctx.fillText(settings.staff_card_title.toUpperCase(),145,96);const px=54,py=176,pw=242,ph=316;if(photo){drawStaffIdPhotoCover(ctx,photo,px,py,pw,ph)}else{ctx.fillStyle="#eef3fa";ctx.fillRect(px,py,pw,ph);ctx.fillStyle=primary;ctx.font="800 74px Arial";ctx.textAlign="center";ctx.fillText(idCardInitials(staff.full_name),px+pw/2,py+ph/2+26);ctx.textAlign="left"}ctx.strokeStyle="#b9c6d8";ctx.lineWidth=3;ctx.strokeRect(px,py,pw,ph);let y=196;const field=(label,value)=>{ctx.fillStyle="#718096";ctx.font="700 14px Arial";ctx.fillText(label,330,y);y+=25;ctx.fillStyle="#132443";fitIdCardText(ctx,value||"—",420,23,16,750);ctx.fillText(String(value||"—"),330,y,420);y+=37};ctx.fillStyle="#64748b";ctx.font="700 15px Arial";ctx.fillText("STAFF NAME",330,y);y+=38;ctx.fillStyle="#10213c";fitIdCardText(ctx,staff.full_name||"Staff",445,34,21,850);ctx.fillText(staff.full_name||"Staff",330,y,445);y+=42;field("STAFF NUMBER",staff.staff_no);field("ROLE",staff.role);if(staff.emis_code)field("EMIS CODE",staff.emis_code);else if(staff.qualification)field("QUALIFICATION",staff.qualification);field("ACADEMIC YEAR",academic.academic_year_name);const qr=await idCardQrCanvas(verification,230);ctx.fillStyle="#fff";ctx.fillRect(802,350,174,174);ctx.drawImage(qr,811,359,156,156);ctx.fillStyle="#64748b";ctx.font="700 13px Arial";ctx.textAlign="center";ctx.fillText("SCAN TO VERIFY",889,536);ctx.textAlign="left";ctx.fillStyle="#10213c";ctx.font="800 18px monospace";ctx.fillText(card.card_number||snap.card?.card_number||"",54,542,720);ctx.font="600 15px Arial";ctx.fillStyle="#56647a";ctx.fillText(`Issued ${isoDate(card.issue_date||snap.card?.issue_date)}  •  Expires ${isoDate(card.expires_on||snap.card?.expires_on)}`,54,579,720)}else{ctx.fillStyle=primary;ctx.fillRect(0,0,canvas.width,98);ctx.fillStyle="#fff";ctx.font="850 28px Arial";ctx.textAlign="center";ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),canvas.width/2,59,850);ctx.textAlign="left";const qr=await idCardQrCanvas(verification,300);ctx.fillStyle="#fff";ctx.fillRect(62,150,260,260);ctx.strokeStyle="#d9e0ea";ctx.strokeRect(62,150,260,260);ctx.drawImage(qr,76,164,232,232);ctx.fillStyle="#132443";ctx.font="850 22px Arial";ctx.fillText("VERIFY THIS STAFF CARD",364,170);ctx.fillStyle="#56647a";ctx.font="500 17px Arial";drawWrapped(ctx,"Scan the QR code to verify whether this issued staff ID card is valid, expired, revoked, replaced, or permanently removed.",364,205,570,25,4);let cy=300;const contact=[];if(settings.show_school_address&&school.address)contact.push(["Address",school.address]);if(settings.show_school_phone&&school.phone)contact.push(["Phone",school.phone]);if(settings.show_school_email&&school.email)contact.push(["Email",school.email]);if(school.website)contact.push(["Website",school.website]);for(const [label,value] of contact.slice(0,4)){ctx.fillStyle="#718096";ctx.font="700 14px Arial";ctx.fillText(`${label.toUpperCase()}:`,364,cy);ctx.fillStyle="#132443";ctx.font="600 16px Arial";ctx.fillText(String(value),485,cy,470);cy+=27}if(settings.show_principal_signature&&(signature||principal.full_name)){const left=640,right=936,lineY=465;if(signature)drawSignatureOnLine(ctx,signature,left,right,lineY,72,"#64748b",1.4);else{ctx.strokeStyle="#64748b";ctx.beginPath();ctx.moveTo(left,lineY);ctx.lineTo(right,lineY);ctx.stroke()}ctx.textAlign="center";ctx.fillStyle="#10213c";ctx.font="700 15px Arial";if(settings.show_principal_name&&principal.full_name)ctx.fillText(String(principal.full_name),788,489,300);if(settings.show_principal_title){ctx.fillStyle="#64748b";ctx.font="600 13px Arial";ctx.fillText("Principal's Signature",788,510)}ctx.textAlign="left"}ctx.fillStyle="#334155";ctx.font="500 15px Arial";drawWrapped(ctx,settings.back_message,62,492,540,22,3);ctx.fillStyle="#64748b";ctx.font="700 13px Arial";ctx.fillText("CARD NUMBER",62,570);ctx.fillStyle="#10213c";ctx.font="800 18px monospace";ctx.fillText(card.card_number||snap.card?.card_number||"",180,570,600);ctx.fillStyle=accent;ctx.fillRect(0,canvas.height-18,canvas.width,18)}return canvas;
  }
  async function createStaffIdCardPdf(card){const blobs=[];for(const side of ["front","back"]){const canvas=await drawStaffIdCard(card,side);try{blobs.push(await idCardCanvasBlob(canvas,.985))}finally{releaseCanvas(canvas)}}return imagesPdf(blobs,85.60/25.4*72,53.98/25.4*72,ID_CARD_WIDTH,ID_CARD_HEIGHT)}
  async function previewStaffIdCard(card){setLoading(true);try{const front=await drawStaffIdCard(card,"front"),back=await drawStaffIdCard(card,"back"),frontUrl=front.toDataURL("image/jpeg",.92),backUrl=back.toDataURL("image/jpeg",.92);releaseCanvas(front);releaseCanvas(back);modal("Staff ID Card Preview",`${card.staff_name||card.snapshot?.staff?.full_name||"Staff"} • ${card.card_number}`,`<div class="id-card-preview-grid"><figure><img src="${frontUrl}" alt="Staff ID card front"><figcaption>Front</figcaption></figure><figure><img src="${backUrl}" alt="Staff ID card back"><figcaption>Back</figcaption></figure></div>`,`<button class="button ghost" id="staffIdPreviewClose">Close</button><button class="button primary" id="staffIdPreviewDownload">Download front + back PDF</button>`,`large`);byId("staffIdPreviewClose").onclick=closeModal;byId("staffIdPreviewDownload").onclick=async()=>{const button=byId("staffIdPreviewDownload");button.disabled=true;try{downloadBlob(`${safeArchiveSegment(card.card_number||"staff-id")}.pdf`,await createStaffIdCardPdf(card));toast("Staff ID PDF downloaded")}catch(error){toast("Staff ID not downloaded",friendlyError(error),"error",8000)}finally{button.disabled=false}}}catch(error){toast("Staff ID preview unavailable",friendlyError(error),"error",8000)}finally{setLoading(false)}}
  async function createStaffIdCardBatchA4Pdf(cards){if(!cards.length)throw new Error("No staff ID cards are available for batch printing");if(cards.length>ID_CARD_BATCH_MAX)throw new Error(`Batch printing is limited to ${ID_CARD_BATCH_MAX} cards per PDF for device memory safety.`);const pages=[];for(let offset=0;offset<cards.length;offset+=10){const group=cards.slice(offset,offset+10);for(const side of ["front","back"]){const sheet=document.createElement("canvas");sheet.width=ID_CARD_A4_WIDTH;sheet.height=ID_CARD_A4_HEIGHT;const ctx=sheet.getContext("2d");ctx.fillStyle="#fff";ctx.fillRect(0,0,sheet.width,sheet.height);const gapX=80,gapY=35,totalW=ID_CARD_WIDTH*2+gapX,totalH=ID_CARD_HEIGHT*5+gapY*4,startX=Math.round((sheet.width-totalW)/2),startY=Math.round((sheet.height-totalH)/2);for(let i=0;i<group.length;i++){const row=Math.floor(i/2),col=i%2,printCol=side==="back"?1-col:col,x=startX+printCol*(ID_CARD_WIDTH+gapX),y=startY+row*(ID_CARD_HEIGHT+gapY),cardCanvas=await drawStaffIdCard(group[i],side);ctx.drawImage(cardCanvas,x,y,ID_CARD_WIDTH,ID_CARD_HEIGHT);ctx.strokeStyle="#d8dee8";ctx.strokeRect(x,y,ID_CARD_WIDTH,ID_CARD_HEIGHT);releaseCanvas(cardCanvas)}try{pages.push(await idCardCanvasBlob(sheet,.97))}finally{releaseCanvas(sheet)}}await sleep(20)}return imagesPdf(pages,595.28,841.89,ID_CARD_A4_WIDTH,ID_CARD_A4_HEIGHT)}
  async function renderStaffIdCards(token,force=false){if(!licenseFeatureEnabled("staff_id_cards"))throw new Error("Staff ID Cards are not included in this licence");state.staffIdCardType=byId("staffIdType")?.value??state.staffIdCardType;state.staffIdCardStatus=byId("staffIdStatus")?.value??state.staffIdCardStatus;if(force||!state.staffIdCardConsole)state.staffIdCardConsole=await rpc("get_staff_id_card_console",{target_staff_type:state.staffIdCardType||null,target_status:state.staffIdCardStatus||null});if(token!==state.viewToken)return;const data=state.staffIdCardConsole||{},cards=data.cards||[],settings=idCardSettingsDefaults(data.settings||{});byId("content").innerHTML=`<div class="page-head"><div><h3>ID Card Management</h3><p>Professional immutable student and staff cards with QR verification, lifecycle controls, and CR80 printing.</p></div><div class="page-actions"><button class="button outline" id="staffIdSettings">Card settings</button><button class="button secondary" id="staffIdBatch" ${cards.length?"":"disabled"}>Download printable A4</button><button class="button primary" id="staffIdGenerate">Generate staff IDs</button></div></div><div class="segmented-tabs id-card-tabs"><button data-id-card-mode="student">Student ID Cards</button><button class="active" data-id-card-mode="staff">Staff ID Cards</button></div>${renderIdCardStats(data.stats||{})}<section class="panel"><div class="toolbar"><select id="staffIdType"><option value="">All staff</option><option value="teacher" ${state.staffIdCardType==="teacher"?"selected":""}>Teachers</option><option value="principal" ${state.staffIdCardType==="principal"?"selected":""}>Principals</option></select><select id="staffIdStatus"><option value="">All statuses</option>${["active","expired","revoked","replaced"].map(v=>`<option value="${v}" ${state.staffIdCardStatus===v?"selected":""}>${esc(statusText(v))}</option>`).join("")}</select><div class="id-card-template-chip">Template: <strong>${esc(statusText(settings.template_code))}</strong> • ${settings.staff_validity_months} month staff validity</div></div>${cards.length?`<div class="table-shell"><table><thead><tr><th>Staff</th><th>Role / year</th><th>Card number</th><th>Issue / expiry</th><th>Status</th><th>Revision</th><th></th></tr></thead><tbody>${cards.map(card=>`<tr><td><div class="cell-copy"><strong>${esc(card.staff_name)}</strong><small>${esc(card.staff_no||"")}</small></div></td><td><div class="cell-copy"><strong>${esc(card.staff_role||statusText(card.staff_type))}</strong><small>${esc(card.academic_year_name||"")}</small></div></td><td><code>${esc(card.card_number)}</code></td><td><div class="cell-copy"><strong>${esc(isoDate(card.issue_date))}</strong><small>Expires ${esc(isoDate(card.expires_on))}</small></div></td><td>${idCardStatusBadge(card)}</td><td>R${number(card.revision_no||1)}</td><td><div class="button-row"><button class="button ghost small" data-staff-id-preview="${attr(card.id)}">Preview</button><button class="button outline small" data-staff-id-download="${attr(card.id)}">PDF</button>${card.status==="active"?`<button class="button secondary small" data-staff-id-replace="${attr(card.id)}">Replace</button><button class="button danger small" data-staff-id-revoke="${attr(card.id)}">Revoke</button>`:card.status==="revoked"||card.status==="replaced"?`<button class="button danger small" data-staff-id-delete="${attr(card.id)}">Delete permanently</button>`:""}</div></td></tr>`).join("")}</tbody></table></div>`:emptyState("No staff ID cards in this filter","Generate staff cards or adjust the filters.")}</section>`;const cardById=id=>cards.find(c=>c.id===id);$$('[data-id-card-mode]').forEach(button=>button.onclick=()=>{state.idCardMode=button.dataset.idCardMode;state.idCardConsole=null;state.staffIdCardConsole=null;renderIdCards(state.viewToken,true)});byId("staffIdType").onchange=()=>{state.staffIdCardType=byId("staffIdType").value;state.staffIdCardConsole=null;renderStaffIdCards(state.viewToken,true)};byId("staffIdStatus").onchange=()=>{state.staffIdCardStatus=byId("staffIdStatus").value;state.staffIdCardConsole=null;renderStaffIdCards(state.viewToken,true)};byId("staffIdSettings").onclick=()=>openIdCardSettings(settings);byId("staffIdGenerate").onclick=openStaffIdCardGenerator;byId("staffIdBatch").onclick=async()=>{if(state.staffIdCardBusy)return;state.staffIdCardBusy=true;setLoading(true);try{const eligible=cards.filter(c=>["active","expired"].includes(idCardComputedStatus(c)));downloadBlob(`staff-id-cards-${safeArchiveSegment(state.staffIdCardType||"all")}.pdf`,await createStaffIdCardBatchA4Pdf(eligible));toast("Printable staff ID cards downloaded")}catch(error){toast("Staff ID batch not created",friendlyError(error),"error",9000)}finally{state.staffIdCardBusy=false;setLoading(false)}};$$('[data-staff-id-preview]').forEach(button=>button.onclick=()=>previewStaffIdCard(cardById(button.dataset.staffIdPreview)));$$('[data-staff-id-download]').forEach(button=>button.onclick=async()=>{const c=cardById(button.dataset.staffIdDownload);button.disabled=true;try{downloadBlob(`${safeArchiveSegment(c.card_number)}.pdf`,await createStaffIdCardPdf(c));toast("Staff ID PDF downloaded")}catch(error){toast("Staff ID not downloaded",friendlyError(error),"error",8000)}finally{button.disabled=false}});$$('[data-staff-id-revoke]').forEach(button=>button.onclick=()=>revokeStaffIdCard(cardById(button.dataset.staffIdRevoke)));$$('[data-staff-id-replace]').forEach(button=>button.onclick=()=>replaceStaffIdCard(cardById(button.dataset.staffIdReplace)));$$('[data-staff-id-delete]').forEach(button=>button.onclick=()=>deleteStaffIdCardPermanently(cardById(button.dataset.staffIdDelete)))}
  async function openStaffIdCardGenerator(){const years=state.boot?.academic_years||[],settings=idCardSettingsDefaults(state.staffIdCardConsole?.settings||state.idCardConsole?.settings||{}),today=new Date().toISOString().slice(0,10),expires=idCardAddMonths(today,settings.staff_validity_months);modal("Generate Staff ID Cards","Issue QR-verifiable staff cards for active teachers and principals. Existing active staff cards are protected from duplicate issuance.",`<form id="staffIdGenerateForm" class="form-grid"><label class="field"><span>Academic year</span><select name="academic_year_id" required>${years.map(y=>`<option value="${attr(y.id)}" ${y.id===(activeYear()?.id||state.idCardYear)?"selected":""}>${esc(y.name)}</option>`).join("")}</select></label><label class="field"><span>Staff type</span><select name="staff_type"><option value="">Teachers and principals</option><option value="teacher">Teachers</option><option value="principal">Principals</option></select></label><label class="field"><span>Issue date</span><input type="date" name="issue_date" value="${today}" required></label><label class="field"><span>Expiry date</span><input type="date" name="expires_on" value="${expires}" required></label><label class="field full"><span>Find staff</span><input id="staffIdCandidateSearch" type="search" placeholder="Name, staff number, or EMIS code"></label></form><div class="id-card-candidate-area"><div class="empty">Loading staff…</div></div>`,`<button class="button ghost" id="staffIdGenerateCancel">Cancel</button><button class="button primary" id="staffIdIssueSelected" disabled>Issue selected cards</button>`,`large`);const form=byId("staffIdGenerateForm"),area=$('.id-card-candidate-area');byId("staffIdGenerateCancel").onclick=closeModal;form.elements.issue_date.onchange=()=>form.elements.expires_on.value=idCardAddMonths(form.elements.issue_date.value,settings.staff_validity_months);let candidates=[];const load=async()=>{area.innerHTML=`<div class="empty">Loading eligible staff…</div>`;try{candidates=await rpc("list_staff_id_card_candidates",{target_staff_type:form.elements.staff_type.value||null,search_text:byId("staffIdCandidateSearch").value.trim()});render()}catch(error){area.innerHTML=emptyState("Staff unavailable",friendlyError(error))}};const render=()=>{area.innerHTML=candidates.length?`<div class="id-card-candidate-toolbar"><label><input type="checkbox" id="staffIdSelectAll"> Select all eligible</label><span>${candidates.length} staff record${candidates.length===1?"":"s"}</span></div><div class="id-card-candidate-results">${candidates.map(item=>`<label class="id-card-candidate ${item.active_card_id?"disabled":""}"><input type="checkbox" name="staff_id_candidate" value="${attr(item.staff_key)}" ${item.active_card_id?"disabled":""}><span><strong>${esc(item.full_name)}</strong><small>${esc(item.role_label)} • ${esc(item.staff_no)}${item.secondary_id?` • ${esc(item.secondary_id)}`:""}${item.active_card_id?` • Active card ${esc(item.active_card_number)}`:""}</small></span></label>`).join("")}</div>`:emptyState("No eligible staff","Adjust the search or staff type.");const update=()=>byId("staffIdIssueSelected").disabled=!$$('[name="staff_id_candidate"]:checked',area).length;$$('[name="staff_id_candidate"]',area).forEach(i=>i.onchange=update);byId("staffIdSelectAll")?.addEventListener("change",event=>{$$('[name="staff_id_candidate"]:not(:disabled)',area).forEach(i=>i.checked=event.target.checked);update()});update()};let timer;byId("staffIdCandidateSearch").oninput=()=>{clearTimeout(timer);timer=setTimeout(load,250)};form.elements.staff_type.onchange=load;await load();byId("staffIdIssueSelected").onclick=async()=>{const keys=$$('[name="staff_id_candidate"]:checked',area).map(i=>i.value);if(!keys.length)return;const values=formObject(form),button=byId("staffIdIssueSelected");button.disabled=true;button.textContent="Issuing";try{const result=await rpc("issue_staff_id_cards",{target_academic_year_id:values.academic_year_id,target_staff_keys:keys,target_issue_date:values.issue_date,target_expires_on:values.expires_on});closeModal();state.staffIdCardConsole=null;toast("Staff ID cards issued",`${result.created_count||0} card${Number(result.created_count||0)===1?"":"s"} created${result.skipped_count?`; ${result.skipped_count} duplicate${result.skipped_count===1?"":"s"} skipped`:""}.`);await renderStaffIdCards(state.viewToken,true)}catch(error){toast("Staff ID cards not issued",friendlyError(error),"error",9000)}finally{button.disabled=false;button.textContent="Issue selected cards"}}}
  async function revokeStaffIdCard(card){const reason=window.prompt(`Reason for revoking ${card.card_number}:`,"")||"";if(reason.trim().length<5)return;if(!await confirmAction("Revoke staff ID card","The QR verification page will immediately show this staff card as revoked.","Revoke card",true))return;try{await rpc("revoke_staff_id_card",{target_card_id:card.id,reason_text:reason.trim()});state.staffIdCardConsole=null;toast("Staff ID card revoked");await renderStaffIdCards(state.viewToken,true)}catch(error){toast("Staff ID card not revoked",friendlyError(error),"error",8000)}}
  async function replaceStaffIdCard(card){const reason=window.prompt(`Reason for replacing ${card.card_number}:`,"Lost or damaged card")||"";if(reason.trim().length<5)return;const today=new Date().toISOString().slice(0,10),settings=idCardSettingsDefaults(state.staffIdCardConsole?.settings||{}),expires=idCardAddMonths(today,settings.staff_validity_months);modal("Replace Staff ID Card","The existing staff card remains in history as Replaced. A new immutable snapshot, card number, QR token, and current staff photograph are issued.",`<form id="staffIdReplaceForm" class="form-grid"><label class="field"><span>Issue date</span><input type="date" name="issue_date" value="${today}" required></label><label class="field"><span>Expiry date</span><input type="date" name="expires_on" value="${expires}" required></label><label class="field full"><span>Reason</span><textarea name="reason" minlength="5" required>${esc(reason.trim())}</textarea></label></form>`,`<button class="button ghost" id="staffIdReplaceCancel">Cancel</button><button class="button primary" id="staffIdReplaceConfirm">Create replacement</button>`,`small`);byId("staffIdReplaceCancel").onclick=closeModal;byId("staffIdReplaceConfirm").onclick=async()=>{const v=formObject(byId("staffIdReplaceForm")),button=byId("staffIdReplaceConfirm");button.disabled=true;try{await rpc("replace_staff_id_card",{target_card_id:card.id,reason_text:v.reason,target_issue_date:v.issue_date,target_expires_on:v.expires_on});closeModal();state.staffIdCardConsole=null;toast("Replacement staff ID card issued");await renderStaffIdCards(state.viewToken,true)}catch(error){toast("Replacement not created",friendlyError(error),"error",8000)}finally{button.disabled=false}}}
  function deleteStaffIdCardPermanently(card){modal("Delete Staff ID Card Permanently","Only revoked or replaced staff cards can be removed. A minimal tombstone is retained to keep the old QR permanently invalid.",`<div class="destructive-confirmation"><label class="field"><span>Deletion reason</span><textarea id="staffIdDeleteReason" minlength="5"></textarea></label><label class="field"><span>Type DELETE to confirm</span><input id="staffIdDeleteText" autocomplete="off"></label><p class="help-text">Card ${esc(card.card_number)} • ${esc(card.staff_name||"")}</p></div>`,`<button class="button ghost" id="staffIdDeleteCancel">Cancel</button><button class="button danger" id="staffIdDeleteConfirm">Delete permanently</button>`,`small`);byId("staffIdDeleteCancel").onclick=closeModal;byId("staffIdDeleteConfirm").onclick=async()=>{const reason=byId("staffIdDeleteReason").value.trim(),confirmation=byId("staffIdDeleteText").value.trim();if(reason.length<5||confirmation!=="DELETE"){toast("Staff ID not deleted","Enter a reason and type DELETE exactly.","error");return}const button=byId("staffIdDeleteConfirm");button.disabled=true;try{await rpc("delete_staff_id_card_permanently",{target_card_id:card.id,reason_text:reason,confirmation_text:confirmation});closeModal();state.staffIdCardConsole=null;toast("Staff ID permanently removed","A deletion tombstone was retained for verification and restore protection.");await renderStaffIdCards(state.viewToken,true)}catch(error){toast("Staff ID not deleted",friendlyError(error),"error",8500)}finally{button.disabled=false}}}

  function certificateVerificationUrl(token){const school=state.boot?.school||{},base=school.verification_base_url||school.website||`${location.origin}${location.pathname}`;return `${base}${base.includes("?")?"&":"?"}certificate=${encodeURIComponent(token)}`}
  function certificateStatusBadge(status){return statusBadge(status||"draft")}
  async function renderCertificates(token,force=false){
    if(!["system_admin","principal"].includes(role()))throw new Error("Certificate access denied");
    const selectedYear=byId("certificateYear")?.value||activeYear()?.id||"",selectedType=byId("certificateTypeFilter")?.value||"";
    if(force||!state.certificateConsole||state.certificateConsoleYear!==selectedYear||state.certificateConsoleType!==selectedType){
      state.certificateConsole=await rpc("get_certificate_console",{target_academic_year_id:selectedYear||null,target_certificate_type:selectedType||null});
      state.certificateConsoleYear=selectedYear;state.certificateConsoleType=selectedType;
    }
    if(token!==state.viewToken)return;
    const data=state.certificateConsole||{},batches=data.batches||[],templates=data.templates||[],issued=batches.reduce((sum,item)=>sum+Number(item.issued_count||0),0),pending=batches.filter(item=>["submitted","approved"].includes(item.status)).length;
    byId("content").innerHTML=`
      <div class="page-head"><div><h3>Certificates and Awards</h3><p>Promotion, JHS completion, and teacher recognition certificates with Principal approval and public verification.</p></div><div class="page-actions">${role()==="system_admin"?`<button class="button ghost" id="certificateSettings" type="button">Templates and settings</button><button class="button primary" id="newCertificateBatch" type="button">Prepare certificate batch</button>`:""}</div></div>
      <div class="stat-grid">${statCard("blue","▧","Certificate batches",batches.length)}${statCard("gold","⌛","Awaiting action",pending)}${statCard("green","✓","Issued certificates",issued)}${statCard("purple","◇","Active templates",templates.filter(item=>item.active).length)}</div>
      <section class="panel"><div class="panel-header"><div><h3>Certificate register</h3><p>Every issued certificate keeps a frozen statement, unique number, verification token, revision, and audit history.</p></div><div class="filter-row"><select id="certificateYear">${optionList(state.boot.academic_years||[],"id","name",selectedYear,"All academic years")}</select><select id="certificateTypeFilter"><option value="">All certificate types</option>${CERTIFICATE_TYPES.map(item=>`<option value="${item.value}" ${item.value===selectedType?"selected":""}>${item.label}</option>`).join("")}</select></div></div>
      ${batches.length?`<div class="table-wrap"><table><thead><tr><th>Batch</th><th>Academic scope</th><th>Recipients</th><th>Status</th><th>Prepared / approved</th><th>Action</th></tr></thead><tbody>${batches.map(item=>`<tr><td><strong>${esc(item.title)}</strong><br><small>${esc(item.type_label)} • ${isoDateTime(item.created_at)}</small></td><td>${esc(item.academic_year_name||"")}${item.term_name?`<br><small>${esc(item.term_name)}</small>`:""}${item.class_name?`<br><small>${esc(item.class_name)}</small>`:""}${item.award_category_name?`<br><small>${esc(item.award_category_name)}</small>`:""}</td><td>${number(item.recipient_count)} total<br><small>${number(item.issued_count)} issued</small></td><td>${certificateStatusBadge(item.status)}</td><td>${esc(item.prepared_by_name||"—")}${item.approved_by_name?`<br><small>Approved by ${esc(item.approved_by_name)}</small>`:""}</td><td><button class="button ghost small" data-certificate-batch="${attr(item.id)}" type="button">Open</button></td></tr>`).join("")}</tbody></table></div>`:emptyState("No certificate batches","Prepare the first certificate batch for this academic year.")}</section>`;
    byId("certificateYear").onchange=()=>{state.certificateConsole=null;renderCertificates(state.viewToken,true)};
    byId("certificateTypeFilter").onchange=()=>{state.certificateConsole=null;renderCertificates(state.viewToken,true)};
    byId("newCertificateBatch")?.addEventListener("click",openCertificateBatchBuilder);
    byId("certificateSettings")?.addEventListener("click",openCertificateSettings);
    $$('[data-certificate-batch]').forEach(button=>button.onclick=()=>openCertificateBatch(button.dataset.certificateBatch));
  }

  async function openCertificateBatchBuilder(){
    const data=state.certificateConsole||await rpc("get_certificate_console",{target_academic_year_id:activeYear()?.id||null,target_certificate_type:null}),categories=data.award_categories||[];
    modal("Prepare certificate batch","Select the certificate purpose and load only recipients who satisfy the server-side eligibility rules.",`
      <form id="certificateBatchForm" class="form-stack certificate-batch-form">
        <div class="form-grid"><label class="field"><span>Certificate type</span><select name="certificate_type" required>${CERTIFICATE_TYPES.map(item=>`<option value="${item.value}">${item.label}</option>`).join("")}</select></label><label class="field"><span>Academic year</span><select name="academic_year_id" required>${optionList(state.boot.academic_years||[],"id","name",activeYear()?.id||"","Select academic year")}</select></label></div>
        <div class="form-grid"><label class="field" id="certificateTermField"><span>Term</span><select name="term_id">${optionList(state.boot.terms||[],"id","name",activeTerm()?.id||"","Select term")}</select><small>Promotion certificates require Term 3. JHS completion can use Term 2 or another published completion term.</small></label><label class="field" id="certificateClassField"><span>Class</span><select name="class_id">${optionList(state.boot.classes||[],"id","name","","Select class")}</select></label></div>
        <label class="field hidden" id="certificateAwardField"><span>Teacher award category</span><select name="award_category_id">${optionList(categories,"id","name","","Select award category")}</select></label>
        <label class="field hidden" id="certificateCitationField"><span>Optional personalised citation</span><textarea name="custom_citation" rows="3" placeholder="Leave blank to use the category citation."></textarea></label>
        <label class="field"><span>Administrative note</span><textarea name="notes" rows="2" placeholder="Ceremony, graduation, or recognition details"></textarea></label>
        <div class="certificate-recipient-toolbar"><div class="button-row"><button class="button secondary" id="loadCertificateRecipients" type="button">Load eligible recipients</button><button class="button ghost hidden" id="selectAllCertificateRecipients" type="button">Select all eligible</button></div><span id="certificateRecipientSelectionSummary" class="certificate-selection-summary" aria-live="polite">0 selected</span></div>
        <div id="certificateRecipientResults" class="certificate-recipient-results">${emptyState("Recipients not loaded","Choose the academic scope, then load eligible recipients.")}</div>
      </form>`,`<button class="button ghost" id="certificateBatchCancel" type="button">Cancel</button><button class="button primary" id="createCertificateBatch" type="button" disabled>Create batch</button>`,`wide`);
    const form=byId("certificateBatchForm"),typeSelect=form.elements.certificate_type,termField=byId("certificateTermField"),classField=byId("certificateClassField"),awardField=byId("certificateAwardField"),citationField=byId("certificateCitationField");
    const syncFields=()=>{const type=typeSelect.value,teacher=type==="teacher_recognition",promotion=type==="student_promotion";termField.classList.toggle("hidden",teacher);classField.classList.toggle("hidden",teacher);awardField.classList.toggle("hidden",!teacher);citationField.classList.toggle("hidden",!teacher);form.elements.term_id.required=promotion;form.elements.class_id.required=!teacher;form.elements.award_category_id.required=teacher;byId("certificateRecipientResults").innerHTML=emptyState("Recipients not loaded","Load the eligible list after changing the certificate type or scope.");const createButton=byId("createCertificateBatch");createButton.disabled=true;createButton.textContent="Create batch";byId("selectAllCertificateRecipients").classList.add("hidden");form.dataset.recipients="[]";const selectionSummary=byId("certificateRecipientSelectionSummary");if(selectionSummary)selectionSummary.textContent="0 selected"};
    typeSelect.onchange=syncFields;syncFields();
    byId("certificateBatchCancel").onclick=closeModal;
    byId("loadCertificateRecipients").onclick=async()=>{
      if(!form.reportValidity())return;const values=formObject(form),button=byId("loadCertificateRecipients");button.disabled=true;button.textContent="Loading";
      try{const rows=await rpc("list_certificate_eligible_recipients",{target_certificate_type:values.certificate_type,target_academic_year_id:values.academic_year_id,target_term_id:values.term_id||null,target_class_id:values.class_id||null});
        form.dataset.recipients=JSON.stringify(rows||[]);renderCertificateRecipientChoices(rows||[]);toast("Eligibility checked",`${(rows||[]).filter(item=>!item.already_issued).length} recipients are available.`)}catch(error){byId("certificateRecipientResults").innerHTML=emptyState("Eligibility check failed",friendlyError(error));toast("Recipients not loaded",friendlyError(error),"error")}finally{button.disabled=false;button.textContent="Load eligible recipients"}
    };
    byId("selectAllCertificateRecipients").onclick=()=>{$$('[name="certificate_recipient"]',form).forEach(input=>{if(!input.disabled)input.checked=true});syncCertificateRecipientSelection()};
    byId("createCertificateBatch").onclick=async()=>{if(!form.reportValidity())return;const ids=$$('[name="certificate_recipient"]:checked',form).map(input=>input.value);if(!ids.length){toast("No recipients selected","Select at least one eligible recipient.","error");return}const values=formObject(form),button=byId("createCertificateBatch");button.disabled=true;button.textContent="Creating";try{const result=await rpc("create_certificate_batch",{payload:{certificate_type:values.certificate_type,academic_year_id:values.academic_year_id,term_id:values.term_id||"",class_id:values.class_id||"",award_category_id:values.award_category_id||"",custom_citation:values.custom_citation||"",notes:values.notes||""},recipient_ids:ids});closeModal();state.certificateConsole=null;toast("Certificate batch prepared",`${result.recipient_count} certificate records created.`);await renderCertificates(state.viewToken,true);await openCertificateBatch(result.batch_id)}catch(error){toast("Batch not created",friendlyError(error),"error",8000)}finally{button.disabled=false;button.textContent="Create batch"}};
  }
  function renderCertificateRecipientChoices(rows){const root=byId("certificateRecipientResults"),eligible=rows.filter(item=>!item.already_issued);root.innerHTML=rows.length?rows.map(item=>`<label class="certificate-recipient-card ${item.already_issued?"disabled":""}"><input type="checkbox" name="certificate_recipient" value="${attr(item.id)}" ${item.already_issued?"disabled":""}><span class="certificate-recipient-copy"><strong class="certificate-recipient-name">${esc(item.recipient_name)}</strong><span class="certificate-recipient-meta">${esc(item.identifier||"")}${item.current_class_name?` • ${esc(item.current_class_name)}`:""}${item.destination_class_name?` → ${esc(item.destination_class_name)}`:""}${item.employment_status?` • ${esc(item.employment_status)}`:""}</span>${item.already_issued?`<span class="form-message certificate-recipient-warning">A current certificate record already exists.</span>`:""}</span></label>`).join(""):emptyState("No eligible recipients","Confirm that reports are published and the selected academic scope is correct.");$$('[name="certificate_recipient"]',root).forEach(input=>input.onchange=syncCertificateRecipientSelection);byId("selectAllCertificateRecipients").classList.toggle("hidden",!eligible.length);syncCertificateRecipientSelection()}
  function syncCertificateRecipientSelection(){const count=$$('[name="certificate_recipient"]:checked',byId("certificateBatchForm")||document).length,button=byId("createCertificateBatch"),summary=byId("certificateRecipientSelectionSummary");if(button){button.disabled=count===0;button.textContent=count?`Create batch (${count})`:"Create batch"}if(summary)summary.textContent=`${count} selected`}

  function certificateTemplateRecord(certificateType){
    return (state.certificateSettingsTemplates||[]).find(item=>item.certificate_type===certificateType)||null;
  }

  function certificateTemplateDesignHtml(item){
    const type=item.certificate_type,label=certificateTypeLabel(type),hasFile=Boolean(item.storage_path);
    return `<form class="certificate-template-form list-card certificate-template-design" data-certificate-template-type="${attr(type)}">
      <input type="hidden" name="id" value="${attr(item.id)}">
      <input type="hidden" name="certificate_type" value="${attr(type)}">
      <div class="section-title"><div><h5>${esc(label)}</h5><p>Configure the automatic wording and optionally upload a professionally designed landscape PDF or DOCX background for this certificate category.</p></div><span class="status ${hasFile?"published":"draft"}">${hasFile?"Uploaded design":"Built-in design"}</span></div>
      <div class="form-grid"><label class="field"><span>${esc(label)} title</span><input name="title" value="${attr(item.title)}" required></label><label class="field"><span>Subtitle</span><input name="subtitle" value="${attr(item.subtitle||"")}"></label></div>
      <label class="field"><span>Automatic statement template</span><textarea name="statement_template" rows="4" required>${esc(item.statement_template)}</textarea><small>Supported placeholders: {{recipient_name}}, {{current_class}}, {{next_class}}, {{academic_year}}, {{school_name}}, {{award_category}}, {{custom_citation}}.</small></label>
      <label class="field"><span>Template footer</span><textarea name="footer_text" rows="2">${esc(item.footer_text||"")}</textarea></label>
      <div class="form-grid"><label class="field"><span>Primary colour</span><input type="color" name="primary_colour" value="${attr(item.primary_colour||"#0a2f73")}"></label><label class="field"><span>Accent colour</span><input type="color" name="accent_colour" value="${attr(item.accent_colour||"#f1b51c")}"></label></div>
      <div class="template-file-summary ${hasFile?"":"empty-template"}">${hasFile
        ?`<strong>${esc(item.original_name||"Uploaded certificate design")}</strong><span>${esc(String(item.mime_type||"").includes("pdf")?"PDF":"DOCX")} • ${readableBytes(item.file_size)} • Version ${number(item.version||1)}</span><small>Updated ${isoDateTime(item.updated_at)}. Earlier private files are retained for frozen certificate history.</small>`
        :`<strong>No uploaded design</strong><span>The system uses the approved built-in landscape certificate design for this category.</span>`}</div>
      <label class="field"><span>${hasFile?"Replace designed template":"Upload designed template"}</span><input type="file" data-certificate-template-file="${attr(type)}" accept=".pdf,.docx,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document"><small>Landscape A4 is recommended. Maximum 20 MB. Leave the central recipient, statement, signature, QR, and certificate-reference zones clear for live data.</small></label>
      <div class="button-row">
        <button class="button primary small" type="submit">Save wording and colours</button>
        <button class="button secondary small" type="button" data-certificate-template-upload="${attr(type)}">${hasFile?"Replace design":"Upload design"}</button>
        ${hasFile?`<button class="button outline small" type="button" data-certificate-template-preview="${attr(type)}">Preview design</button><button class="button ghost small" type="button" data-certificate-template-download="${attr(type)}">Download</button><button class="button danger small" type="button" data-certificate-template-remove="${attr(type)}">Remove design</button>`:""}
      </div>
    </form>`;
  }

  async function uploadCertificateTemplateDesign(certificateType){
    const form=document.querySelector(`.certificate-template-form[data-certificate-template-type="${certificateType}"]`);
    const input=form?.querySelector(`[data-certificate-template-file="${certificateType}"]`);
    const button=form?.querySelector(`[data-certificate-template-upload="${certificateType}"]`);
    const file=input?.files?.[0];
    try{
      const info=validateCertificateTemplateFile(file);button.disabled=true;setLoading(true);button.textContent="Validating";
      await renderCertificateTemplateBlob(file,info.mimeType);
      button.textContent="Uploading";
      const checksum=await sha256(file),path=`${certificateType}/${Date.now()}-${uuid()}.${info.extension}`;
      const {error}=await state.client.storage.from(CONFIG.certificateTemplateBucket).upload(path,file,{contentType:info.mimeType,upsert:false,cacheControl:"3600"});
      if(error)throw error;
      try{
        await rpc("save_certificate_template",{payload:{...formObject(form),storage_path:path,original_name:file.name,mime_type:info.mimeType,file_size:file.size,checksum}});
      }catch(error){
        await removePrivateStorageObjects(CONFIG.certificateTemplateBucket,[path],{source:"certificate_template_upload_rollback",certificate_type:certificateType},true);
        throw error;
      }
      state.certificateConsole=null;state.certificateSettingsTemplates=[];state.certificateTemplateCanvases.clear();
      toast("Certificate design uploaded",`${certificateTypeLabel(certificateType)} will use ${file.name} for newly prepared certificates.`);
      closeModal();await openCertificateSettings();
    }catch(error){
      toast("Certificate design not uploaded",friendlyError(error),"error",8000);
      await reportClientError(error,{source:"certificate_template_upload",certificate_type:certificateType});
    }finally{
      setLoading(false);if(button){button.disabled=false;button.textContent=certificateTemplateRecord(certificateType)?.storage_path?"Replace design":"Upload design"}
    }
  }

  async function previewCertificateTemplateDesign(certificateType){
    const template=certificateTemplateRecord(certificateType);
    if(!template?.storage_path)return;
    setLoading(true);
    try{
      const canvas=await storedCertificateTemplateCanvas(template);
      const dataUrl=canvas.toDataURL("image/png");
      modal(`${certificateTypeLabel(certificateType)} design preview`,template.original_name||"Uploaded certificate design",`<div class="certificate-template-preview"><img src="${attr(dataUrl)}" alt="${attr(certificateTypeLabel(certificateType))} uploaded template preview"></div>`,`<button class="button ghost" id="certificateDesignPreviewClose" type="button">Back to settings</button>`,`wide`);
      byId("certificateDesignPreviewClose").onclick=()=>{closeModal();openCertificateSettings()};
    }catch(error){toast("Preview unavailable",friendlyError(error),"error",7000)}
    finally{setLoading(false)}
  }

  async function downloadCertificateTemplateDesign(certificateType){
    const template=certificateTemplateRecord(certificateType);
    if(!template?.storage_path)return;
    setLoading(true);
    try{
      const {data,error}=await state.client.storage.from(CONFIG.certificateTemplateBucket).download(template.storage_path);
      if(error)throw error;
      downloadBlob(template.original_name||`${certificateType}.pdf`,data);
      toast("Certificate design downloaded");
    }catch(error){toast("Download unavailable",friendlyError(error),"error")}
    finally{setLoading(false)}
  }

  async function removeCertificateTemplateDesign(certificateType){
    const template=certificateTemplateRecord(certificateType);
    if(!template?.storage_path)return;
    if(!await confirmAction("Remove uploaded certificate design","Future certificate batches will return to the built-in design. The private file is retained for frozen historical certificate records.","Remove design",true))return;
    try{
      await rpc("remove_certificate_template_file",{target_certificate_type:certificateType});
      state.certificateConsole=null;state.certificateSettingsTemplates=[];state.certificateTemplateCanvases.clear();
      toast("Certificate design removed","Future certificates will use the built-in design.");
      closeModal();await openCertificateSettings();
    }catch(error){toast("Certificate design not removed",friendlyError(error),"error")}
  }

  async function openCertificateSettings(){
    const data=await rpc("get_certificate_console",{target_academic_year_id:null,target_certificate_type:null}),templates=data.templates||[],categories=data.award_categories||[],settings=data.settings||{};
    state.certificateSettingsTemplates=templates;
    modal("Certificate templates and settings","Configure purpose-specific statements, category designs, JHS completion settings, and teacher recognition categories.",`
      <div class="grid two"><section class="panel pad"><h4>School certificate settings</h4><form id="certificateSchoolSettings" class="form-stack"><label class="field"><span>JHS 3 completion class</span><select name="completion_class_id">${optionList(state.boot.classes||[],"id","name",settings.completion_class_id||"","Automatic Basic 9 / JHS 3 detection")}</select></label><label class="field"><span>Official footer</span><textarea name="footer_text" rows="3">${esc(settings.footer_text||"")}</textarea></label><button class="button primary" type="submit">Save settings</button></form></section><section class="panel pad"><h4>Teacher award categories</h4><div class="stack-list">${categories.map(item=>`<article class="list-card"><div><strong>${esc(item.name)}</strong><small>${esc(item.default_citation||"")}</small></div></article>`).join("")}</div><form id="newAwardCategory" class="form-stack"><label class="field"><span>New category name</span><input name="name" required></label><label class="field"><span>Default citation</span><textarea name="default_citation" rows="2"></textarea></label><button class="button secondary" type="submit">Add category</button></form></section></div>
      <section class="panel pad" style="margin-top:16px"><div class="section-title"><div><h4>Purpose-specific certificate templates</h4><p>Each certificate category can use its own uploaded landscape PDF or DOCX design. The system overlays the official recipient, statement, Principal signature, QR verification, issue date, and certificate number.</p></div></div><div class="stack-list">${templates.map(certificateTemplateDesignHtml).join("")}</div></section>`,`<button class="button ghost" id="certificateSettingsClose" type="button">Close</button>`,`wide`);
    byId("certificateSettingsClose").onclick=closeModal;
    byId("certificateSchoolSettings").onsubmit=async event=>{event.preventDefault();const form=event.currentTarget,button=form.querySelector("button");button.disabled=true;try{await rpc("save_certificate_settings",{payload:formObject(form)});toast("Certificate settings saved");state.certificateConsole=null}catch(error){toast("Settings not saved",friendlyError(error),"error")}finally{button.disabled=false}};
    byId("newAwardCategory").onsubmit=async event=>{event.preventDefault();const form=event.currentTarget,button=form.querySelector("button");button.disabled=true;try{await rpc("save_teacher_award_category",{payload:formObject(form)});toast("Award category added");closeModal();state.certificateConsole=null;await openCertificateSettings()}catch(error){toast("Category not added",friendlyError(error),"error")}finally{button.disabled=false}};
    $$(".certificate-template-form").forEach(form=>form.onsubmit=async event=>{event.preventDefault();const button=form.querySelector('button[type="submit"]');button.disabled=true;try{await rpc("save_certificate_template",{payload:formObject(form)});toast("Certificate wording and colours saved");state.certificateConsole=null}catch(error){toast("Template settings not saved",friendlyError(error),"error")}finally{button.disabled=false}});
    $$("[data-certificate-template-upload]").forEach(button=>button.onclick=()=>uploadCertificateTemplateDesign(button.dataset.certificateTemplateUpload));
    $$("[data-certificate-template-preview]").forEach(button=>button.onclick=()=>previewCertificateTemplateDesign(button.dataset.certificateTemplatePreview));
    $$("[data-certificate-template-download]").forEach(button=>button.onclick=()=>downloadCertificateTemplateDesign(button.dataset.certificateTemplateDownload));
    $$("[data-certificate-template-remove]").forEach(button=>button.onclick=()=>removeCertificateTemplateDesign(button.dataset.certificateTemplateRemove));
  }

  async function openCertificateBatch(batchId){
    const data=await rpc("get_certificate_batch",{target_batch_id:batchId});if(!data?.batch)throw new Error("Certificate batch not found");state.certificateBatch=data;const b=data.batch,certs=data.certificates||[],events=data.events||[];
    const actions=role()==="system_admin"&&["draft","rejected"].includes(b.status)?`<button class="button primary" id="certificateSubmitBatch" type="button">Submit for Principal approval</button>`:role()==="principal"&&b.status==="submitted"?`<button class="button warning" id="certificateRejectBatch" type="button">Reject</button><button class="button primary" id="certificateApproveBatch" type="button">Approve all</button>`:role()==="system_admin"&&b.status==="approved"?`<button class="button primary" id="certificateIssueBatch" type="button">Issue all and create PDFs</button>`:b.status==="issued"?`<button class="button secondary" id="certificateDownloadBatch" type="button">${role()==="system_admin"?"Refresh PDFs and download ZIP":"Download available PDFs"}</button>`:"";
    modal(b.title,`${b.type_label} • ${b.academic_year_name}${b.term_name?` • ${b.term_name}`:""}${b.class_name?` • ${b.class_name}`:""}`,`
      <div class="grid two"><section class="panel pad"><h4>Workflow</h4><div class="verify-result">${verifyField("Status",b.status)}${verifyField("Prepared by",b.prepared_by_name)}${verifyField("Submitted",isoDateTime(b.submitted_at))}${verifyField("Approved by",b.approved_by_name)}${verifyField("Issued",isoDateTime(b.issued_at))}</div>${b.review_note?`<p class="help-text"><strong>Review note:</strong> ${esc(b.review_note)}</p>`:""}</section><section class="panel pad"><h4>Eligibility and statement</h4><p>${esc(data.template?.statement_template||"")}</p>${b.award_category_name?`<p><strong>Award:</strong> ${esc(b.award_category_name)}</p>`:""}${b.custom_citation?`<p><strong>Citation:</strong> ${esc(b.custom_citation)}</p>`:""}</section></div>
      <section class="panel" style="margin-top:16px"><div class="panel-header"><div><h4>Recipients</h4><p>${certs.length} certificate record${certs.length===1?"":"s"}</p></div></div><div class="table-wrap"><table><thead><tr><th>Recipient</th><th>Purpose</th><th>Certificate</th><th>PDF</th><th>Actions</th></tr></thead><tbody>${certs.map(cert=>`<tr><td><strong>${esc(cert.recipient_name)}</strong><br><small>${esc(cert.recipient_identifier||"")}${cert.current_class_name?` • ${esc(cert.current_class_name)}`:""}</small></td><td>${cert.award_category_name?esc(cert.award_category_name):cert.destination_class_name?`${esc(cert.current_class_name)} → ${esc(cert.destination_class_name)}`:esc(certificateTypeLabel(b.certificate_type))}<br><small>Revision ${number(cert.revision_no)}</small></td><td>${cert.certificate_number?`<code>${esc(cert.certificate_number)}</code><br>`:""}${certificateStatusBadge(cert.status)}</td><td>${cert.pdf_storage_path?`Ready<br><small>${esc(cert.pdf_sha256?.slice(0,12)||"")}…</small>`:"Not created"}</td><td><div class="button-row compact">${cert.status==="issued"&&role()==="system_admin"?`<button class="button secondary small" data-cert-generate="${attr(cert.id)}">Create / refresh PDF</button>`:""}${cert.status==="issued"&&cert.pdf_storage_path?`<button class="button ghost small" data-cert-download="${attr(cert.id)}">Download</button>`:""}${cert.verification_token?`<button class="button ghost small" data-cert-copy="${attr(cert.verification_token)}">Copy verification</button>`:""}${cert.status==="issued"&&["system_admin","principal"].includes(role())?`<button class="button warning small" data-cert-revoke="${attr(cert.id)}">Revoke</button>`:""}${["issued","revoked"].includes(cert.status)&&role()==="system_admin"?`<button class="button ghost small" data-cert-replace="${attr(cert.id)}">Replacement</button>`:""}${role()==="system_admin"?`<button class="button danger small" data-cert-delete="${attr(cert.id)}">Delete permanently</button>`:""}</div></td></tr>`).join("")}</tbody></table></div></section>
      <section class="panel" style="margin-top:16px"><div class="panel-header"><div><h4>Immutable certificate history</h4><p>Preparation, approval, issue, PDF registration, revocation, and replacement events.</p></div></div>${events.length?`<div class="table-wrap"><table><thead><tr><th>Time</th><th>Event</th><th>Actor</th><th>Reason</th></tr></thead><tbody>${events.map(event=>`<tr><td>${isoDateTime(event.created_at)}</td><td>${esc(event.event_type.replaceAll("_"," "))}</td><td>${esc(event.actor_name||"System")}</td><td>${esc(event.reason||"")}</td></tr>`).join("")}</tbody></table></div>`:emptyState("No certificate events")}</section>`,
      `<button class="button ghost" id="certificateBatchClose" type="button">Close</button>${actions}`,`wide`);
    byId("certificateBatchClose").onclick=()=>{closeModal();state.certificateConsole=null;renderCertificates(state.viewToken,true)};
    byId("certificateSubmitBatch")?.addEventListener("click",()=>submitCertificateBatch(batchId));
    byId("certificateApproveBatch")?.addEventListener("click",()=>reviewCertificateBatch(batchId,"approved"));
    byId("certificateRejectBatch")?.addEventListener("click",()=>reviewCertificateBatch(batchId,"rejected"));
    byId("certificateIssueBatch")?.addEventListener("click",()=>issueCertificateBatch(batchId));
    byId("certificateDownloadBatch")?.addEventListener("click",()=>generateCertificateBatchPdfs(data,true));
    $$('[data-cert-generate]').forEach(button=>button.onclick=async()=>{button.disabled=true;try{const cert=certs.find(item=>item.id===button.dataset.certGenerate),result=await createAndStoreCertificatePdf(data,cert);toast("Certificate PDF created",result.fallbackUsed?"The uploaded design could not be rendered, so the professional built-in certificate design was used.":result.liveTemplateRecovered?"The current uploaded category design was recovered and applied successfully.":"The uploaded category design was applied successfully.");closeModal();await openCertificateBatch(batchId)}catch(error){toast("Certificate PDF not created",friendlyError(error),"error",8000)}finally{button.disabled=false}});
    $$('[data-cert-download]').forEach(button=>button.onclick=()=>downloadStoredCertificatePdf(data,certs.find(item=>item.id===button.dataset.certDownload)));
    $$('[data-cert-copy]').forEach(button=>button.onclick=async()=>{await navigator.clipboard.writeText(certificateVerificationUrl(button.dataset.certCopy));toast("Verification link copied")});
    $$('[data-cert-revoke]').forEach(button=>button.onclick=()=>revokeCertificateRecord(batchId,button.dataset.certRevoke));
    $$('[data-cert-replace]').forEach(button=>button.onclick=()=>replaceCertificateRecord(batchId,certs.find(item=>item.id===button.dataset.certReplace)));
    $$('[data-cert-delete]').forEach(button=>button.onclick=()=>deleteCertificatePermanently(batchId,certs.find(item=>item.id===button.dataset.certDelete)));
  }

  async function submitCertificateBatch(batchId){if(!await confirmAction("Submit certificate batch","The Principal will review every certificate in this batch before it can be issued.","Submit"))return;try{await rpc("submit_certificate_batch",{target_batch_id:batchId});toast("Certificates submitted");closeModal();state.certificateConsole=null;await renderCertificates(state.viewToken,true);await openCertificateBatch(batchId)}catch(error){toast("Batch not submitted",friendlyError(error),"error")}}
  async function reviewCertificateBatch(batchId,decision){const note=window.prompt(`${decision==="approved"?"Approval":"Rejection"} note:`,"")??"";if(decision==="rejected"&&note.trim().length<3){toast("Rejection note required","Enter the reason for returning the batch.","error");return}try{await rpc("review_certificate_batch",{target_batch_id:batchId,decision,review_note_text:note.trim()});toast(`Batch ${decision}`);closeModal();state.certificateConsole=null;await renderCertificates(state.viewToken,true);await openCertificateBatch(batchId)}catch(error){toast("Review not saved",friendlyError(error),"error")}}
  async function issueCertificateBatch(batchId){const issueDate=window.prompt("Certificate issue date (YYYY-MM-DD):",new Date().toISOString().slice(0,10));if(!issueDate)return;if(!/^\d{4}-\d{2}-\d{2}$/.test(issueDate)){toast("Invalid issue date","Use YYYY-MM-DD.","error");return}if(!await confirmAction("Issue all certificates","Unique certificate numbers and verification tokens will be permanently assigned. Official PDFs will then be created.","Issue certificates"))return;setLoading(true);try{await rpc("issue_certificate_batch",{target_batch_id:batchId,target_issue_date:issueDate});const data=await rpc("get_certificate_batch",{target_batch_id:batchId});await generateCertificateBatchPdfs(data,true);toast("Certificates issued",`${data.certificates?.length||0} certificates were issued and processed.`);closeModal();state.certificateConsole=null;await renderCertificates(state.viewToken,true)}catch(error){toast("Certificates not issued",friendlyError(error),"error",9000);await reportClientError(error,{source:"certificate_issue",batch_id:batchId})}finally{setLoading(false)}}
  async function revokeCertificateRecord(batchId,certificateId){const reason=window.prompt("Reason for revoking this certificate:","")||"";if(reason.trim().length<5)return;if(!await confirmAction("Revoke certificate","The public verification page will immediately show that this certificate is invalid.","Revoke",true))return;try{await rpc("revoke_certificate",{target_certificate_id:certificateId,reason_text:reason.trim()});toast("Certificate revoked");closeModal();state.certificateConsole=null;await openCertificateBatch(batchId)}catch(error){toast("Certificate not revoked",friendlyError(error),"error")}}
  async function deleteCertificatePermanently(batchId,certificate){
    if(!certificate)return;const reason=window.prompt("Reason for permanently deleting this certificate:","")||"";
    if(reason.trim().length<5){toast("Deletion reason required","Provide at least five characters.","error");return}
    const confirmation=window.prompt(`Type DELETE to permanently remove ${certificate.certificate_number||certificate.recipient_name}:`,"")||"";
    if(confirmation.trim().toUpperCase()!=="DELETE"){toast("Permanent deletion cancelled","The confirmation word did not match.","warning");return}
    if(!await confirmAction("Delete certificate permanently","This removes the certificate record, verification reference, PDF registration, and certificate events. This action cannot be undone.","Delete permanently",true))return;
    setLoading(true);try{const result=await rpc("delete_certificate_permanently",{target_certificate_id:certificate.id,reason_text:reason.trim()});if(result.storage_path){const {error}=await state.client.storage.from(CONFIG.certificatePdfBucket).remove([result.storage_path]);if(error){await reportClientError(error,{source:"certificate_pdf_cleanup",certificate_id:certificate.id,storage_path:result.storage_path});toast("Certificate deleted","The database record was removed. A private orphan PDF may require Storage cleanup.","warning",8000)}else toast("Certificate deleted permanently")}else toast("Certificate deleted permanently");closeModal();state.certificateConsole=null;await renderCertificates(state.viewToken,true);if(!result.batch_deleted)await openCertificateBatch(batchId)}catch(error){toast("Certificate not deleted",friendlyError(error),"error",8000)}finally{setLoading(false)}
  }
  async function replaceCertificateRecord(batchId,certificate){const reason=window.prompt("Reason for creating a replacement certificate:","")||"";if(reason.trim().length<5)return;modal("Replacement certificate statement","The replacement will follow the full submission and Principal approval workflow. Leave the statement unchanged or correct it below.",`<label class="field"><span>Certificate statement</span><textarea id="replacementCertificateStatement" rows="7">${esc(certificate.statement_text)}</textarea></label>`,`<button class="button ghost" id="replacementCancel">Cancel</button><button class="button primary" id="replacementCreate">Create replacement draft</button>`,`small`);byId("replacementCancel").onclick=closeModal;byId("replacementCreate").onclick=async()=>{const button=byId("replacementCreate");button.disabled=true;try{const result=await rpc("create_certificate_replacement_draft",{target_certificate_id:certificate.id,reason_text:reason.trim(),replacement_statement:byId("replacementCertificateStatement").value.trim()});closeModal();state.certificateConsole=null;toast("Replacement draft created");await renderCertificates(state.viewToken,true);await openCertificateBatch(result.batch_id)}catch(error){toast("Replacement not created",friendlyError(error),"error")}finally{button.disabled=false}}}

  async function createCertificatePdf(data,certificate){
    const canvas=document.createElement("canvas");canvas.width=1754;canvas.height=1240;
    const frozen=certificate.snapshot||{},ctx=canvas.getContext("2d"),frozenTemplate=frozen.template||{},liveTemplate=data.template||{},template=Object.keys(frozenTemplate).length?frozenTemplate:liveTemplate,school=frozen.school||data.school||state.boot?.school||{},principal=frozen.principal||data.principal||{},primary=template.primary_colour||liveTemplate.primary_colour||school.primary_colour||"#0a2f73",accent=template.accent_colour||liveTemplate.accent_colour||school.accent_colour||"#f1b51c";
    let uploadedTemplateApplied=false;certificate.__usedBuiltInTemplateFallback=false;certificate.__usedLiveTemplateRecovery=false;
    const templateCandidates=[template,liveTemplate].filter((candidate,index,list)=>candidate?.storage_path&&list.findIndex(item=>item?.storage_path===candidate.storage_path)===index);
    for(const candidate of templateCandidates){
      try{
        const background=await storedCertificateTemplateCanvas(candidate);
        if(!background)throw new Error("The uploaded certificate design returned no rendered page.");
        ctx.drawImage(background,0,0,canvas.width,canvas.height);uploadedTemplateApplied=true;certificate.__usedLiveTemplateRecovery=candidate.storage_path!==template.storage_path;break;
      }catch(error){
        await reportClientError(error,{source:"certificate_template_render_attempt",certificate_id:certificate.id,certificate_type:data.batch?.certificate_type,storage_path:candidate.storage_path});
      }
    }
    if(templateCandidates.length&&!uploadedTemplateApplied)certificate.__usedBuiltInTemplateFallback=true;
    if(!uploadedTemplateApplied){
      ctx.fillStyle="#fffdf7";ctx.fillRect(0,0,canvas.width,canvas.height);
      const gradient=ctx.createLinearGradient(0,0,canvas.width,canvas.height);gradient.addColorStop(0,"rgba(241,181,28,.12)");gradient.addColorStop(.48,"rgba(255,255,255,0)");gradient.addColorStop(1,"rgba(10,47,115,.10)");ctx.fillStyle=gradient;ctx.fillRect(0,0,canvas.width,canvas.height);
      ctx.strokeStyle=primary;ctx.lineWidth=18;ctx.strokeRect(34,34,1686,1172);
      ctx.strokeStyle=accent;ctx.lineWidth=5;ctx.strokeRect(58,58,1638,1124);
      ctx.strokeStyle=primary;ctx.lineWidth=2;ctx.strokeRect(75,75,1604,1090);
      [[85,85,0],[1669,85,Math.PI/2],[85,1155,-Math.PI/2],[1669,1155,Math.PI]].forEach(([x,y,rotation])=>{ctx.save();ctx.translate(x,y);ctx.rotate(rotation);ctx.fillStyle=accent;ctx.beginPath();ctx.moveTo(0,0);ctx.lineTo(95,0);ctx.lineTo(0,95);ctx.closePath();ctx.fill();ctx.restore()});
    }
    let logo=null,signature=null;
    try{logo=await loadImage(schoolDisplayLogo(school))}catch(_){}
    let certificateSignatureError=null;
    if(principal.signature_path){
      try{signature=await loadPrivateImageAsset(CONFIG.signatureBucket,principal.signature_path,"The Principal signature")}
      catch(error){certificateSignatureError=error}
    }
    if(!signature){
      const currentPrincipal=await rpc("get_current_principal_signature").catch(()=>null);
      if(currentPrincipal?.signature_path&&currentPrincipal.signature_path!==principal.signature_path){
        try{signature=await loadPrivateImageAsset(CONFIG.signatureBucket,currentPrincipal.signature_path,"The current Principal signature");principal.full_name=currentPrincipal.full_name||principal.full_name}
        catch(error){certificateSignatureError=error}
      }
    }
    if(!signature){
      if(certificateSignatureError)throw certificateSignatureError;
      throw new Error("The certificate cannot be generated until an active Principal signature is uploaded.");
    }
    if(!uploadedTemplateApplied&&logo){ctx.save();ctx.globalAlpha=.028;drawImageContain(ctx,logo,557,350,640,620);ctx.restore()}
    if(logo){ctx.save();ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality="high";drawImageContain(ctx,logo,767,92,220,166);ctx.restore()}
    ctx.textAlign="center";ctx.fillStyle=primary;ctx.font='bold 44px Georgia, "Times New Roman", serif';ctx.fillText(String(school.school_name||schoolDisplayName()).toUpperCase(),877,292);
    ctx.fillStyle="#5c6470";ctx.font='italic 24px Georgia, "Times New Roman", serif';ctx.fillText(school.motto||"",877,330);
    ctx.fillStyle=accent;ctx.fillRect(520,365,714,4);
    ctx.fillStyle=primary;ctx.font='bold 68px Georgia, "Times New Roman", serif';ctx.fillText(certificate.certificate_title||template.title||"Certificate",877,455);
    ctx.fillStyle="#5c6470";ctx.font='24px Arial, sans-serif';ctx.fillText(template.subtitle||certificateTypeLabel(data.batch?.certificate_type),877,500);
    ctx.fillStyle="#30343b";ctx.font='24px Georgia, "Times New Roman", serif';ctx.fillText("This certificate is presented to",877,565);
    ctx.fillStyle=primary;let recipientSize=58;
    while(recipientSize>30){ctx.font=`bold ${recipientSize}px Georgia, "Times New Roman", serif`;if(ctx.measureText(certificate.recipient_name).width<=1180)break;recipientSize-=2}
    ctx.fillText(certificate.recipient_name,877,650);
    ctx.strokeStyle=accent;ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(390,670);ctx.lineTo(1364,670);ctx.stroke();
    ctx.fillStyle="#30343b";let statementSize=27,statementLines=[];
    while(statementSize>=16){ctx.font=`${statementSize}px Georgia, "Times New Roman", serif`;statementLines=wrappedTextLines(ctx,certificate.statement_text,1280);if(statementLines.length<=7)break;statementSize-=1}
    const statementLineHeight=Math.max(27,statementSize*1.38),statementTop=710+(7-statementLines.length)*statementLineHeight/2;
    statementLines.slice(0,7).forEach((line,index)=>ctx.fillText(line,877,statementTop+index*statementLineHeight));
    if(certificate.award_category_name){ctx.fillStyle=primary;ctx.font='bold 25px Arial, sans-serif';ctx.fillText(certificate.award_category_name,877,955)}
    ctx.fillStyle="#5c6470";ctx.font='22px Arial, sans-serif';ctx.fillText(`Academic Year: ${certificate.academic_year_name}`,877,980);
    drawSignatureOnLine(ctx,signature,650,1104,1068,92,"#5c6470",1.5);
    ctx.fillStyle="#30343b";ctx.font='bold 22px Arial, sans-serif';ctx.fillText(principal.full_name||school.head_name||"Principal",877,1098);
    ctx.fillStyle="#5c6470";ctx.font='18px Arial, sans-serif';ctx.fillText("Principal",877,1125);
    const qr=await qrCanvas(certificateVerificationUrl(certificate.verification_token));if(qr)ctx.drawImage(qr,1384,900,176,176);
    ctx.fillStyle="#30343b";ctx.font='bold 16px Arial, sans-serif';ctx.fillText("SCAN TO VERIFY",1472,1105);
    ctx.textAlign="left";ctx.fillStyle="#5c6470";ctx.font='18px Arial, sans-serif';ctx.fillText(`Certificate No.: ${certificate.certificate_number||"Pending"}`,126,1048);ctx.fillText(`Issue Date: ${isoDate(certificate.issue_date)}`,126,1081);ctx.fillText(`Revision: ${certificate.revision_no||1}`,126,1114);
    ctx.textAlign="center";ctx.fillStyle="#5c6470";ctx.font='italic 16px Georgia, "Times New Roman", serif';ctx.fillText(template.footer_text||school.certificate_footer_text||"Issued under the authority of the school administration.",877,1152);
    const jpeg=await new Promise(resolve=>canvas.toBlob(resolve,"image/jpeg",.97));
    return imagePdf(jpeg,841.89,595.28,1754,1240);
  }
  function wrappedTextLines(ctx,text,maxWidth){const words=String(text||"").split(/\s+/).filter(Boolean),lines=[];let line="";for(const word of words){const next=line?`${line} ${word}`:word;if(ctx.measureText(next).width>maxWidth&&line){lines.push(line);line=word}else line=next}if(line)lines.push(line);return lines}
  async function createAndStoreCertificatePdf(data,certificate){if(role()!=="system_admin")throw new Error("Only the System Administrator can create official certificate PDFs");if(!certificate||certificate.status!=="issued")throw new Error("Only an issued certificate can have an official PDF");const pdf=await createCertificatePdf(data,certificate),checksum=await sha256(pdf),year=safeArchiveSegment(certificate.academic_year_name,"year"),safeNumber=safeArchiveSegment(certificate.certificate_number,"certificate"),path=`${data.batch.certificate_type}/${year}/${safeNumber}-r${certificate.revision_no}-${Date.now()}.pdf`,previous=certificate.pdf_storage_path||"";const {error}=await state.client.storage.from(CONFIG.certificatePdfBucket).upload(path,pdf,{contentType:"application/pdf",upsert:false,cacheControl:"31536000"});if(error)throw error;try{await rpc("register_certificate_pdf",{target_certificate_id:certificate.id,target_storage_path:path,target_checksum:checksum})}catch(error){await removePrivateStorageObjects(CONFIG.certificatePdfBucket,[path],{source:"certificate_pdf_registration_rollback",certificate_id:certificate.id},true);throw error}if(previous&&previous!==path)await removePrivateStorageObjects(CONFIG.certificatePdfBucket,[previous],{source:"certificate_pdf_replacement_cleanup",certificate_id:certificate.id},true);certificate.pdf_storage_path=path;certificate.pdf_sha256=checksum;return {pdf,path,checksum,fallbackUsed:Boolean(certificate.__usedBuiltInTemplateFallback),liveTemplateRecovered:Boolean(certificate.__usedLiveTemplateRecovery)}}
  async function downloadStoredCertificatePdf(data,certificate){
    setLoading(true);
    try{
      const blob=await downloadStoredCertificatePdfBlob(certificate);
      downloadBlob(`${safeArchiveSegment(certificate.certificate_number,"Certificate")}_${safeArchiveSegment(certificate.recipient_name,"Recipient")}.pdf`,blob);
      toast("Certificate downloaded","The frozen official certificate PDF was downloaded from secure Storage.");
    }catch(error){
      toast("Certificate unavailable",friendlyError(error),"error");
      await reportClientError(error,{source:"certificate_pdf_download",certificate_id:certificate?.id||null});
    }finally{setLoading(false)}
  }
  async function generateCertificateBatchPdfs(data,downloadZip=true){
    if(!window.JSZip&&downloadZip)throw new Error("ZIP library unavailable");
    const issued=(data.certificates||[]).filter(item=>item.status==="issued"),zip=downloadZip?new window.JSZip():null,manifest=[];
    if(!issued.length)throw new Error("No issued certificates are available");
    for(let index=0;index<issued.length;index++){
      const cert=issued[index];
      try{
        let pdf,pdfSource="stored_official";
        if(role()==="system_admin"){
          try{
            pdf=(await createAndStoreCertificatePdf(data,cert)).pdf;
            pdfSource="refreshed";
          }catch(refreshError){
            await reportClientError(refreshError,{source:"certificate_batch_pdf_refresh",certificate_id:cert.id});
            if(!cert.pdf_storage_path)throw refreshError;
            pdf=await downloadStoredCertificatePdfBlob(cert);
            pdfSource="stored_official_fallback";
          }
        }else{
          pdf=await downloadStoredCertificatePdfBlob(cert);
        }
        const filename=`${safeArchiveSegment(cert.certificate_number,"Certificate")}_${safeArchiveSegment(cert.recipient_name,"Recipient")}.pdf`;
        if(zip)zip.file(filename,pdf);
        manifest.push({certificate_number:cert.certificate_number,recipient:cert.recipient_name,status:"included",pdf_source:pdfSource,file_name:filename,error:""});
      }catch(error){
        manifest.push({certificate_number:cert.certificate_number,recipient:cert.recipient_name,status:"failed",pdf_source:"unavailable",file_name:"",error:friendlyError(error)});
        await reportClientError(error,{source:"certificate_batch_pdf",certificate_id:cert.id});
      }
    }
    if(zip){
      const headers=["certificate_number","recipient","status","pdf_source","file_name","error"];
      zip.file("CERTIFICATE_MANIFEST.csv",[headers.join(","),...manifest.map(row=>headers.map(key=>csvCell(row[key])).join(","))].join("\r\n"));
      const included=manifest.filter(row=>row.status==="included");
      if(!included.length)throw new Error("No certificate PDFs could be prepared");
      const blob=await zip.generateAsync({type:"blob",compression:"DEFLATE",compressionOptions:{level:6}});
      downloadBlob(`${safeArchiveSegment(data.batch.title,"Certificates")}_${safeArchiveSegment(data.batch.academic_year_name,"Year")}.zip`,blob);
      const fallbackCount=included.filter(row=>row.pdf_source==="stored_official_fallback").length;
      toast(fallbackCount?"Certificate package downloaded with fallback":"Certificate package downloaded",`${included.length} certificate PDF${included.length===1?"":"s"} included${fallbackCount?` • ${fallbackCount} secure stored PDF${fallbackCount===1?"":"s"} used after refresh failure`:""}.`,fallbackCount?"warning":"success",8500);
    }
    return manifest;
  }


  function platformPackageGenerationBlockers(consoleData={}) {
    const blockers=[];
    if(consoleData.can_generate!==true)blockers.push("Distributor package-generation authority is disabled.");
    const template=consoleData.template;
    if(!template)blockers.push("No active protected v7.4.0 template is installed. Install or replace the template at the top of GitHub Navigator.");
    else if(String(template.package_version||"")!=="7.4.0")blockers.push(`The active protected template is v${String(template.package_version||"unknown")}; v7.4.0 is required.`);
    const signing=consoleData.signing||{};
    if(signing.ready!==true)blockers.push(`Package signing is not ready${signing.error?`: ${String(signing.error)}`:"."}`);
    const releaseHealth=consoleData.release_health||{};
    if(releaseHealth.ready!==true)blockers.push(`System release health is not ready${Array.isArray(releaseHealth.missing)&&releaseHealth.missing.length?`: ${releaseHealth.missing.join(", ")}`:"."}`);
    if(!Array.isArray(consoleData.plans)||consoleData.plans.length===0)blockers.push("No active licence plan is available.");
    return blockers;
  }
  function platformPackageGenerationReadinessHtml(consoleData={}) {
    const blockers=platformPackageGenerationBlockers(consoleData);
    return `<div id="packageGenerationReadiness" class="template-information full${blockers.length?" warning":""}"><strong>${blockers.length?"Package generation setup required":"Package generation ready"}</strong><span>${esc(blockers.length?blockers.join(" "):"Live prerequisites are verified. Complete the school details and select Generate protected package.")}</span></div>`;
  }
  function updatePlatformPackageGenerationReadiness(consoleData={}) {
    const target=byId("packageGenerationReadiness");if(!target)return;
    const blockers=platformPackageGenerationBlockers(consoleData);
    target.className=`template-information full${blockers.length?" warning":""}`;
    target.innerHTML=`<strong>${blockers.length?"Package generation setup required":"Package generation ready"}</strong><span>${esc(blockers.length?blockers.join(" "):"Live prerequisites are verified. Complete the school details and select Generate protected package.")}</span>`;
    const button=byId("generateSchoolPackage");if(button)button.title=blockers.length?blockers.join(" "):"All package-generation prerequisites are ready.";
  }


  async function renderGithubNavigator(token,force=false) {
    if(role()!=="platform_super_admin")throw new Error("Platform Super Administrator access required");
    if(force||!state.platformPackageConsole){
      const [packageConsole,upgradeConsole]=await Promise.all([
        invokePlatformPackageManager("status",{offset:state.platformPackageOffset,limit:state.platformPackageLimit,search:state.platformPackageSearch}),
        invokeLicenseUpgradeManager("status",{})
      ]);
      state.platformPackageConsole={...packageConsole,upgrade_authorizations:upgradeConsole.upgrade_authorizations||[],upgrade_manager_can_generate:upgradeConsole.can_generate===true,upgrade_manager_can_revoke:upgradeConsole.can_revoke===true};
    }
    if(token!==state.viewToken)return;
    const consoleData=state.platformPackageConsole||{},template=consoleData.template,artifacts=consoleData.artifacts||[],events=consoleData.events||[],archives=consoleData.archives||[],upgradeAuthorizations=consoleData.upgrade_authorizations||[],packagePlans=consoleData.plans||[],storageCapacity=consoleData.storage_capacity||{},signingStatus=consoleData.signing||{},signingReady=signingStatus.ready===true,releaseHealth=consoleData.release_health||{},canGenerate=consoleData.can_generate===true,canRevoke=consoleData.can_revoke===true,generationBlockers=platformPackageGenerationBlockers(consoleData);
    const readyReplacementTargets=new Set(artifacts.filter(item=>item.status==="ready"&&item.deletion_state==="none"&&item.supersedes_artifact_id).map(item=>String(item.supersedes_artifact_id)));
    const activatedUpgradeByArtifact=new Map();for(const authorization of upgradeAuthorizations){if(authorization.status==="activated"&&!activatedUpgradeByArtifact.has(String(authorization.artifact_id)))activatedUpgradeByArtifact.set(String(authorization.artifact_id),authorization)}
    const effectiveArtifactPlanCode=item=>activatedUpgradeByArtifact.get(String(item.id))?.to_plan_code||item.license_plan_code||item.entitlement_snapshot?.plan?.code||"";
    byId("content").innerHTML=`
      <div class="page-head platform-page-head"><div><h3>GitHub Navigator</h3><p>Platform-owner-only reusable package control</p></div><div class="button-row"><button class="button ghost" id="platformPackageRefresh" type="button">Refresh</button></div></div>
      ${platformSectionTabs("github")}
      <div class="platform-package-workspace">
        <div class="grid">
          <section class="panel pad">
            <div class="section-title"><div><h4>Protected package template</h4><p>The official complete package ZIP is stored server-side and verified before use.</p></div></div>
            ${template?`<div class="template-information"><strong>Template v${esc(template.package_version)}</strong><span>SHA-256 ${esc(template.sha256)} • ${readableBytes(template.file_size)} • Installed ${esc(isoDateTime(template.created_at))}</span></div>`:`<div class="empty"><strong>No package template installed</strong><span>Upload PLATFORM_PACKAGE_TEMPLATE_v7_4_0_FINAL.zip before generating a school package.</span></div>`}
            ${storageCapacity.template?`<div class="template-information"><strong>Private Storage capacity verified</strong><span>Template ${readableBytes(storageCapacity.template.configured_bytes)} • Generated packages ${readableBytes(storageCapacity.generated?.configured_bytes||0)} • private buckets enforced automatically</span></div>`:""}
            ${signingReady?`<div class="template-information"><strong>Package signing ready</strong><span>Key ${esc(signingStatus.key_id||"verified")} • ${signingStatus.source==="vault"?"encrypted Supabase Vault persistence":"Edge Function environment secret"}${signingStatus.provisioned?" • created automatically on this refresh":""}${signingStatus.repaired?" • metadata repaired automatically":""}${signingStatus.warning?` • ${esc(signingStatus.warning)}`:""}</span></div>`:`<div class="template-information warning"><strong>Package signing setup required</strong><span>${esc(signingStatus.error||"Refresh after deploying the package-signing Vault bootstrap fix.")}</span></div>`}
            ${releaseHealth.ready===true?`<div class="template-information"><strong>v7.4.0 system health verified</strong><span>Required database objects, package services, Vault availability, and release controls are present.</span></div>`:`<div class="template-information warning"><strong>v7.4.0 system health setup required</strong><span>${esc(Array.isArray(releaseHealth.missing)&&releaseHealth.missing.length?releaseHealth.missing.join(", "):releaseHealth.error||"Run the v7.4.0 production-stability SQL, redeploy the current Edge Functions, and refresh.")}</span></div>`}
            <form id="platformTemplateForm" class="form-grid" style="margin-top:16px">
              <label class="field full"><span>Official package template ZIP</span><input id="platformPackageTemplate" name="template" type="file" accept=".zip,application/zip,application/x-zip-compressed" required ${canGenerate?"":"disabled"}><small>Maximum 48 MB. The browser performs the complete checksum scan, then the server verifies the archive digest, structure, release metadata, critical files, Android APK, and Windows EXEs without exhausting Edge Function compute resources.</small></label>
              <div class="full button-row"><button class="button secondary" id="platformTemplateUpload" type="button" ${canGenerate?"":"disabled"}>Install or replace template</button></div>
            </form>
          </section>
          <section class="panel pad"><div class="section-title"><div><h4>Deployment Navigator</h4><p>Use these links only after generating and downloading an authorized package.</p></div></div>
            ${githubNavigatorStepsHtml()}
            <div class="github-link-grid">
              <a class="github-link-card" href="https://github.com/new" target="_blank" rel="noopener"><strong>Create GitHub repository</strong><span>Open GitHub's new repository page</span></a>
              <a class="github-link-card" href="https://github.com/settings/pages" target="_blank" rel="noopener"><strong>GitHub Pages settings</strong><span>Open account Pages settings</span></a>
              <a class="github-link-card" href="https://supabase.com/dashboard/projects" target="_blank" rel="noopener"><strong>Supabase projects</strong><span>Create or open the licensed school's project</span></a>
            </div>
          </section>
        </div>
        <section class="panel pad">
          <div class="section-title"><div><h4>Generate licensed school package</h4><p>Generation occurs inside the protected Edge Function. A signed manifest and immutable audit event are created.</p></div></div>
          <form id="schoolPackageForm" class="form-grid">
            <label class="field full"><span>New school name</span><input name="school_name" maxlength="120" placeholder="Example Academy" required></label>
            <label class="field"><span>Short application name</span><input name="short_name" maxlength="30" placeholder="Example Reports"></label>
            <label class="field"><span>Report number prefix</span><input name="report_prefix" maxlength="12" placeholder="EA" required></label>
            <label class="field"><span>Tenant code</span><input name="tenant_code" maxlength="60" placeholder="EA-001" required></label>
            <label class="field"><span>Licence reference</span><input name="license_reference" maxlength="80" placeholder="RCE-... (optional)"></label>
            <label class="field"><span>Licence plan</span><select name="license_plan_code" required>${packagePlans.map(item=>`<option value="${attr(item.id)}" data-code="${attr(item.code)}" data-revision="${attr(item.revision||1)}" ${item.code==="enterprise"?"selected":""}>${esc(item.name)} (r${number(item.revision||1)})</option>`).join("")}</select></label>
            <label class="field"><span>Initial licence status</span><select name="license_status"><option value="pending_activation" selected>Pending activation</option><option value="active">Active</option><option value="perpetual">Perpetual</option></select></label>
            <div id="schoolPackagePlanSummary" class="template-information full"></div>
            <label class="field"><span>Issue date</span><input name="issued_on" type="date" value="${new Date().toISOString().slice(0,10)}" required></label>
            <label class="field"><span>Expiry date and time (optional)</span><input name="expires_at" type="datetime-local"></label>
            <label class="field full"><span>Deployment URL or hostname (optional)</span><input name="authorized_domain" inputmode="url" autocomplete="url" placeholder="https://username.github.io/repository/"><small>Leave blank for project-bound deployment without host locking. A GitHub Pages URL is accepted; a github.com repository URL is not a deployed website.</small></label>
            <label class="field full"><span>User account email domain (optional)</span><input name="email_domain" placeholder="school.edu.gh"><small>Leave blank to use a safe non-deliverable .invalid placeholder.</small></label>
            <label class="field full"><span>School logo</span><input id="schoolPackageLogo" name="school_logo" type="file" accept="image/png" required><small>PNG source up to 5 MB. It is normalized automatically to a compute/storage-safe PNG of at most 1 MB while preserving a square print-ready image.</small></label>
            <div class="package-logo-preview full"><img id="schoolPackageLogoPreview" src="${CONFIG.logoPath}" alt="Package logo preview"><div><strong id="schoolPackageNamePreview">New school package</strong><span>The official package is generated and signed on the server.</span></div></div>
            <label class="field full"><span>GitHub repository name</span><input name="repository_name" maxlength="80" placeholder="example-academy-report-card" required></label>
            <label class="field full"><span>Supabase Project URL</span><input name="supabase_url" placeholder="https://your-project.supabase.co" required></label>
            <label class="field full"><span>Supabase Publishable key</span><input name="supabase_key" placeholder="sb_publishable_..." required><small>Secret and service-role keys are rejected by the server. Branded Android and Windows builds require an sb_publishable_ key and do not accept a legacy anon JWT.</small></label>
            <div class="template-information full"><strong>Android distribution</strong><span>The licensed school package can include a ready-to-build branded Android project. The resulting APK uses the school name, school logo, unique application ID, embedded public Supabase connection, and school-specific authentication callback.</span><small>Android signing is deliberately performed outside Supabase in a private GitHub Actions repository or controlled build workstation.</small></div>
            <label class="field full"><span><input id="includeAndroidBuildKit" name="include_android_build_kit" type="checkbox" value="true" checked> Include branded Android APK build kit</span></label>
            <label class="field"><span>Android application name</span><input name="android_app_name" maxlength="80" placeholder="Example Academy Report Card"></label>
            <label class="field"><span>Android application ID</span><input name="android_application_id" maxlength="150" pattern="[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}" placeholder="com.reportcardenterprise.school.exampleacademy"><small>Must remain unchanged for future updates to this school's app.</small></label>
            <label class="field full"><span>Android authentication callback scheme</span><input name="android_callback_scheme" maxlength="64" pattern="[a-z][a-z0-9+.-]{2,63}" placeholder="rceexampleacademy"><small>Add the generated scheme://auth-callback URL to the school's Supabase Auth redirect URLs.</small></label>
            <div class="template-information full"><strong>Windows distribution</strong><span>Every generated package includes the physically accepted v7.3.9-w1 x64 and ARM64 universal Setup EXEs. It can also include a ready-to-build school-branded Windows installer project with a unique product identity, state folder, runtime port, school logo, and embedded public Supabase connection.</span><small>Use the x64 Setup EXE on standard Intel or AMD computers. Build and Authenticode-sign branded Windows installers only in a private repository or controlled workstation.</small></div>
            <label class="field full"><span><input id="includeWindowsBuildKit" name="include_windows_build_kit" type="checkbox" value="true" checked> Include branded Windows installer build kit</span></label>
            <label class="field"><span>Windows application name</span><input name="windows_app_name" maxlength="100" placeholder="Example Academy Report Card"></label>
            <label class="field"><span>Windows product ID</span><input name="windows_product_id" maxlength="48" pattern="[a-z][a-z0-9-]{2,47}" placeholder="example-academy"><small>Must remain unchanged for future Windows updates.</small></label>
            <label class="field"><span>Windows publisher</span><input name="windows_publisher" maxlength="100" placeholder="Example Academy"></label>
            <label class="field"><span>Windows local runtime port</span><input name="windows_runtime_port" type="number" min="18000" max="29999" placeholder="18439"><small>Use a unique port for each branded school product installed on the same computer.</small></label>
            ${platformPackageGenerationReadinessHtml(consoleData)}
            <div class="full button-row"><button class="button primary" id="generateSchoolPackage" type="button" ${canGenerate?"":"disabled"} title="${attr(generationBlockers.length?generationBlockers.join(" "):"All package-generation prerequisites are ready.")}">Generate protected package</button></div>
            <div id="packageGeneratorProgress" class="generator-progress full hidden" aria-live="polite"><span class="spinner small"></span><strong>Generating package</strong><span id="packageGeneratorProgressText">Authorizing platform session</span></div>
          </form>
        </section>
      </div>
      <section class="panel platform-register-panel" style="margin-top:18px">
        <div class="panel-header"><div><h3>Generated package register</h3><p>Private artifacts and authorized-download history</p></div><span class="status approved">${number(consoleData.artifact_count??artifacts.length)} records</span></div>
        <div class="platform-register-controls"><label class="field"><span>Search packages</span><input id="platformPackageSearch" value="${attr(state.platformPackageSearch)}" placeholder="School, tenant, licence, or filename"></label><div class="button-row"><button class="button secondary small" id="platformPackageSearchApply" type="button">Search</button><button class="button ghost small" id="platformPackageSearchClear" type="button" ${state.platformPackageSearch?"":"disabled"}>Clear</button></div><div class="button-row"><button class="button ghost small" id="platformPackagePrevious" type="button" ${state.platformPackageOffset<=0?"disabled":""}>Previous</button><span class="status neutral">${number(state.platformPackageOffset+1)}-${number(Math.min(state.platformPackageOffset+artifacts.length,consoleData.artifact_count??artifacts.length))}</span><button class="button ghost small" id="platformPackageNext" type="button" ${state.platformPackageOffset+artifacts.length>=(consoleData.artifact_count??artifacts.length)?"disabled":""}>Next</button></div></div>
        <div class="table-wrap platform-register-scroll"><table><thead><tr><th>Generated</th><th>School and tenant</th><th>Licence</th><th>Package</th><th>Status</th><th>Actions</th></tr></thead><tbody>${artifacts.length?artifacts.map(item=>`<tr><td>${esc(isoDateTime(item.generated_at))}<br><small>${esc(platformPackageLifecycleLabel(item))}</small></td><td><strong>${esc(item.school_name)}</strong><br><small>${esc(item.tenant_code)}${item.authorized_domain?` • ${esc(item.authorized_domain)}`:""}</small></td><td>${esc(item.license_reference)}<br><small>${esc(effectiveArtifactPlanCode(item))} • ${activatedUpgradeByArtifact.has(String(item.id))?`activation upgrade r${number(activatedUpgradeByArtifact.get(String(item.id)).to_plan_revision||1)}`:`revision ${number(item.plan_revision||1)}`}</small>${item.supersedes_artifact_id?`<br><small>Replaces ${esc(String(item.metadata?.lifecycle?.supersedes_package_id||item.supersedes_artifact_id).slice(0,18))}…</small>`:""}</td><td><span class="package-filename">${esc(item.filename)}</span><br><small>${readableBytes(item.file_size)} • ${number(item.download_count)} downloads${item.metadata?.android_distribution?.included?` • Android ${esc(item.metadata.android_distribution.application_id||"profile")}`:""}${item.metadata?.windows_distribution?.included?` • Windows ${esc(item.metadata.windows_distribution.product_id||"w1")}`:""}</small></td><td>${platformPackageStatusLabel(item.status)}${item.authority_last_checked_at?`<br><small>School verified ${esc(isoDateTime(item.authority_last_checked_at))}</small>`:""}${item.superseded_at?`<br><small>Superseded ${esc(isoDateTime(item.superseded_at))}</small>`:""}${item.revocation_reason?`<br><small>${esc(item.revocation_reason)}</small>`:""}</td><td><div class="button-row compact package-action-row">${platformPackageActionButtons(item,canGenerate,canRevoke,readyReplacementTargets.has(String(item.id)),effectiveArtifactPlanCode(item))}</div></td></tr>`).join(""):`<tr><td colspan="6"><div class="empty">No protected package has been generated</div></td></tr>`}</tbody></table></div>
      </section>
      <section class="panel platform-register-panel" style="margin-top:18px">
        <div class="panel-header"><div><h3>Upgrade activation authorizations</h3><p>Installation-bound one-time codes. Plaintext codes are shown only once at generation.</p></div><span class="status neutral">${number(upgradeAuthorizations.length)} recent</span></div>
        <div class="table-wrap platform-register-scroll"><table><thead><tr><th>Issued</th><th>School / licence</th><th>Upgrade</th><th>Code</th><th>Status</th><th>Action</th></tr></thead><tbody>${upgradeAuthorizations.length?upgradeAuthorizations.map(item=>`<tr><td>${esc(isoDateTime(item.issued_at))}<br><small>Expires ${esc(isoDateTime(item.expires_at))}</small></td><td>${esc(item.metadata?.school_name||item.tenant_code||"School")}<br><small>${esc(item.license_reference||"")}</small></td><td><strong>${esc(featureFlagLabel(item.from_plan_code))} → ${esc(featureFlagLabel(item.to_plan_code))}</strong><br><small>Target revision ${number(item.to_plan_revision||1)}</small></td><td><code>••••-${esc(item.code_hint||"????")}</code></td><td>${statusBadge(item.status)}${item.redeemed_at?`<br><small>Redeemed ${esc(isoDateTime(item.redeemed_at))}</small>`:""}${item.activated_at?`<br><small>Activated ${esc(isoDateTime(item.activated_at))}</small>`:""}</td><td>${item.status==="issued"&&canRevoke?`<button class="button warning small" data-upgrade-code-revoke="${attr(item.id)}">Revoke unused code</button>`:`<span class="status neutral">${item.status==="redeemed_pending_activation"?"Activation pending":"No action"}</span>`}</td></tr>`).join(""):`<tr><td colspan="6"><div class="empty">No upgrade activation codes have been issued</div></td></tr>`}</tbody></table></div>
      </section>
      <section class="panel platform-history-panel" style="margin-top:18px">
        <div class="panel-header"><div><h3>Package security audit</h3><p>Latest 200 package security events</p></div><div class="button-row"><button class="button danger small" id="packageAuditClear" type="button" ${(events.length||archives.length)&&canRevoke?"":"disabled"}>Clear all history</button></div></div>
        <div class="table-wrap platform-history-scroll"><table><thead><tr><th>Date</th><th>Event</th><th>Reason</th><th>Details</th></tr></thead><tbody>${events.length?events.map(item=>`<tr><td>${esc(isoDateTime(item.created_at))}</td><td><strong>${esc(String(item.event_type||"").replaceAll("_"," "))}</strong></td><td>${esc(item.event_reason||"—")}</td><td><code class="audit-json">${esc(JSON.stringify(item.event_data||{}))}</code></td></tr>`).join(""):`<tr><td colspan="4"><div class="empty">No package events recorded</div></td></tr>`}</tbody></table></div>
      </section>`;
    bindGithubNavigator(packagePlans,canGenerate,canRevoke,signingReady);
  }

  function bindGithubNavigator(packagePlans=[],canGenerate=false,canRevoke=false,signingReady=false) {
    bindPlatformSectionTabs();
    byId("platformPackageRefresh").onclick=()=>{state.platformPackageConsole=null;renderGithubNavigator(state.viewToken,true)};
    if(canGenerate)byId("platformTemplateUpload").onclick=uploadPlatformPackageTemplate;
    const form=byId("schoolPackageForm"),nameInput=form.elements.school_name,shortInput=form.elements.short_name,prefixInput=form.elements.report_prefix,repoInput=form.elements.repository_name,tenantInput=form.elements.tenant_code,logoInput=byId("schoolPackageLogo"),androidToggle=byId("includeAndroidBuildKit"),androidNameInput=form.elements.android_app_name,androidIdInput=form.elements.android_application_id,androidSchemeInput=form.elements.android_callback_scheme,windowsToggle=byId("includeWindowsBuildKit"),windowsNameInput=form.elements.windows_app_name,windowsProductInput=form.elements.windows_product_id,windowsPublisherInput=form.elements.windows_publisher,windowsPortInput=form.elements.windows_runtime_port;
    if(!canGenerate)[...form.elements].forEach(element=>{element.disabled=true});
    const syncSuggestions=()=>{
      const name=nameInput.value.trim();byId("schoolPackageNamePreview").textContent=name||"New school package";
      if(!shortInput.value.trim()||shortInput.dataset.auto==="true"){shortInput.value=name?`${suggestedPrefix(name)} Reports`:"";shortInput.dataset.auto="true"}
      if(!prefixInput.value.trim()||prefixInput.dataset.auto==="true"){prefixInput.value=name?suggestedPrefix(name):"";prefixInput.dataset.auto="true"}
      if(!repoInput.value.trim()||repoInput.dataset.auto==="true"){repoInput.value=name?`${slugify(name)}-report-card`:"";repoInput.dataset.auto="true"}
      if(!tenantInput.value.trim()||tenantInput.dataset.auto==="true"){tenantInput.value=name?`${suggestedPrefix(name)}-001`:"";tenantInput.dataset.auto="true"}
      const androidSegment=suggestedAndroidSegment(tenantInput.value||name);
      if(!androidNameInput.value.trim()||androidNameInput.dataset.auto==="true"){androidNameInput.value=name?`${name} Report Card`:"";androidNameInput.dataset.auto="true"}
      if(!androidIdInput.value.trim()||androidIdInput.dataset.auto==="true"){androidIdInput.value=androidSegment?`com.reportcardenterprise.school.${androidSegment}`:"";androidIdInput.dataset.auto="true"}
      if(!androidSchemeInput.value.trim()||androidSchemeInput.dataset.auto==="true"){androidSchemeInput.value=androidSegment?`rce${androidSegment}`:"";androidSchemeInput.dataset.auto="true"}
      const windowsProduct=suggestedWindowsProductId(tenantInput.value||name);
      if(!windowsNameInput.value.trim()||windowsNameInput.dataset.auto==="true"){windowsNameInput.value=name?`${name} Report Card`:"";windowsNameInput.dataset.auto="true"}
      if(!windowsProductInput.value.trim()||windowsProductInput.dataset.auto==="true"){windowsProductInput.value=windowsProduct;windowsProductInput.dataset.auto="true"}
      if(!windowsPublisherInput.value.trim()||windowsPublisherInput.dataset.auto==="true"){windowsPublisherInput.value=name||"";windowsPublisherInput.dataset.auto="true"}
      if(!windowsPortInput.value||windowsPortInput.dataset.auto==="true"){windowsPortInput.value=suggestedWindowsPort(tenantInput.value||name);windowsPortInput.dataset.auto="true"}
    };
    nameInput.addEventListener("input",syncSuggestions);
    [shortInput,prefixInput,repoInput,androidNameInput,androidIdInput,androidSchemeInput,windowsNameInput,windowsProductInput,windowsPublisherInput,windowsPortInput].forEach(input=>input.addEventListener("input",()=>{input.dataset.auto="false"}));tenantInput.addEventListener("input",()=>{tenantInput.dataset.auto="false";syncSuggestions()});
    logoInput.addEventListener("change",()=>{const file=logoInput.files?.[0];if(!file)return;if(state.packageLogoPreviewUrl)URL.revokeObjectURL(state.packageLogoPreviewUrl);state.packageLogoPreviewUrl=URL.createObjectURL(file);byId("schoolPackageLogoPreview").src=state.packageLogoPreviewUrl});
    const syncAndroidFields=()=>{const enabled=canGenerate&&androidToggle.checked;[androidNameInput,androidIdInput,androidSchemeInput].forEach(input=>{input.disabled=!enabled;input.required=enabled});state.packageGenerationKey=""};androidToggle.onchange=syncAndroidFields;
    const syncWindowsFields=()=>{const enabled=canGenerate&&windowsToggle.checked;[windowsNameInput,windowsProductInput,windowsPublisherInput,windowsPortInput].forEach(input=>{input.disabled=!enabled;input.required=enabled});state.packageGenerationKey=""};windowsToggle.onchange=syncWindowsFields;syncAndroidFields();syncWindowsFields();syncSuggestions();
    const planSelect=form.elements.license_plan_code,statusSelect=form.elements.license_status,expiryInput=form.elements.expires_at;
    const syncLicenceTerms=()=>{const selected=packagePlans.find(item=>String(item.id)===String(planSelect.value))||{};const perpetualOption=[...statusSelect.options].find(option=>option.value==="perpetual");if(perpetualOption)perpetualOption.disabled=selected.perpetual_allowed!==true;if(statusSelect.value==="perpetual"&&selected.perpetual_allowed!==true)statusSelect.value="pending_activation";const needsExpiry=statusSelect.value!=="perpetual"&&["monthly","annual"].includes(String(selected.billing_cycle||""));expiryInput.disabled=statusSelect.value==="perpetual";expiryInput.required=needsExpiry;if(expiryInput.disabled)expiryInput.value="";else if(needsExpiry&&!expiryInput.value){const days=Number(selected.default_term_days||365);expiryInput.value=dateTimeLocalValue(new Date(Date.now()+days*86400000))}const enabled=Object.entries(selected.feature_flags||{}).filter(([,value])=>value===true).map(([key])=>key.replaceAll("_"," "));const limits=[`Students ${selected.max_students??"Unlimited"}`,`Teachers ${selected.max_teachers??"Unlimited"}`,`System Administrators ${selected.max_system_admins??"Unlimited"}`,`Guardians ${selected.max_guardians??"Unlimited"}`,`Storage ${selected.max_storage_mb==null?"Unlimited":`${number(selected.max_storage_mb)} MB`}`];const summary=byId("schoolPackagePlanSummary");if(summary)summary.innerHTML=`<strong>${esc(selected.name||"Select a plan")} • revision ${number(selected.revision||1)}</strong><span>${esc(limits.join(" • "))}</span><small>${esc(enabled.join(", ")||"No enabled features")} • ${esc(String(selected.billing_cycle||"custom"))} billing • ${number(selected.grace_days||0)} grace days</small>`};
    planSelect.onchange=()=>{state.packageGenerationKey="";syncLicenceTerms()};statusSelect.onchange=()=>{state.packageGenerationKey="";syncLicenceTerms()};form.addEventListener("input",()=>{state.packageGenerationKey=""});syncLicenceTerms();
    byId("platformPackageSearchApply").onclick=()=>{state.platformPackageSearch=byId("platformPackageSearch").value.trim();state.platformPackageOffset=0;state.platformPackageConsole=null;renderGithubNavigator(state.viewToken,true)};
    byId("platformPackageSearch").onkeydown=event=>{if(event.key==="Enter"){event.preventDefault();byId("platformPackageSearchApply").click()}};
    byId("platformPackageSearchClear").onclick=()=>{state.platformPackageSearch="";state.platformPackageOffset=0;state.platformPackageConsole=null;renderGithubNavigator(state.viewToken,true)};
    byId("platformPackagePrevious").onclick=()=>{state.platformPackageOffset=Math.max(0,state.platformPackageOffset-state.platformPackageLimit);state.platformPackageConsole=null;renderGithubNavigator(state.viewToken,true)};
    byId("platformPackageNext").onclick=()=>{state.platformPackageOffset+=state.platformPackageLimit;state.platformPackageConsole=null;renderGithubNavigator(state.viewToken,true)};
    if(canGenerate)byId("generateSchoolPackage").onclick=generateReusableSchoolPackage;
    $$('[data-package-download]').forEach(button=>button.onclick=()=>downloadProtectedPackage(button.dataset.packageDownload,button));
    $$('[data-package-renew]').forEach(button=>button.onclick=()=>renewOrUpgradeProtectedPackage(button.dataset.packageRenew,button));
    $$('[data-package-upgrade-code]').forEach(button=>button.onclick=()=>generatePackageUpgradeCode(button.dataset.packageUpgradeCode,button));
    $$('[data-upgrade-code-revoke]').forEach(button=>button.onclick=()=>revokePackageUpgradeCode(button.dataset.upgradeCodeRevoke,button));
    $$('[data-package-finalize]').forEach(button=>button.onclick=()=>finalizeReplacementProtectedPackage(button.dataset.packageFinalize,button));
    $$('[data-package-revoke]').forEach(button=>button.onclick=()=>revokeProtectedPackage(button.dataset.packageRevoke,button));
    $$('[data-package-restore]').forEach(button=>button.onclick=()=>restoreProtectedPackage(button.dataset.packageRestore,button));
    $$('[data-package-delete]').forEach(button=>button.onclick=()=>deleteProtectedPackage(button.dataset.packageDelete,button));
    if(canRevoke)byId("packageAuditClear")?.addEventListener("click",clearPackageSecurityAudit);
  }

  function suggestedPrefix(name) {
    const words=String(name||"").trim().split(/\s+/).filter(word=>!/^(school|academy|college|international|the|of)$/i.test(word));
    const initials=(words.length?words:String(name||"").trim().split(/\s+/)).map(word=>word[0]||"").join("").replace(/[^a-z0-9]/gi,"").toUpperCase();
    return (initials||"SCH").slice(0,8);
  }
  function suggestedAndroidSegment(value) {
    const compact=slugify(value||"school").replaceAll("-","").replaceAll("_","").slice(0,48)||"school";
    return /^[a-z]/.test(compact)?compact:`s${compact}`;
  }
  function suggestedWindowsProductId(value) {
    const result=slugify(value||"school").slice(0,48)||"school";
    return /^[a-z]/.test(result)?result:`school-${result}`.slice(0,48);
  }
  function suggestedWindowsPort(value) {
    let hash=2166136261;for(const char of String(value||"school")){hash^=char.charCodeAt(0);hash=Math.imul(hash,16777619)}
    return 18000+((hash>>>0)%12000);
  }

  async function sha256BytesHex(bytes){const hash=await crypto.subtle.digest("SHA-256",bytes);return [...new Uint8Array(hash)].map(byte=>byte.toString(16).padStart(2,"0")).join("")}
  let jsZipRuntimeLoadPromise=null;
  async function ensureJSZipRuntime(){
    if(window.JSZip&&typeof window.JSZip.loadAsync==="function")return window.JSZip;
    if(jsZipRuntimeLoadPromise)return jsZipRuntimeLoadPromise;
    jsZipRuntimeLoadPromise=new Promise((resolve,reject)=>{
      const finish=()=>{if(window.JSZip&&typeof window.JSZip.loadAsync==="function")resolve(window.JSZip);else reject(new Error("The packaged ZIP validator library loaded but did not initialize."))};
      const script=document.createElement("script");
      script.src=new URL("assets/vendor/jszip-3.10.1.min.js?rce=r31-jszip-cacheproof-v2",document.baseURI).href;
      script.async=true;
      script.onload=finish;
      script.onerror=()=>reject(new Error("The packaged ZIP validator library could not be loaded. Refresh the application and try again."));
      document.head.appendChild(script);
    });
    try{return await jsZipRuntimeLoadPromise}catch(error){jsZipRuntimeLoadPromise=null;throw error}
  }
  function safeProtectedTemplatePath(path){return Boolean(path)&&!path.includes("\0")&&!path.includes("\\")&&!path.startsWith("/")&&!/^[A-Za-z]:/.test(path)&&!path.split("/").some(part=>part===".."||part===".")}
  async function validateProtectedTemplateInBrowser(file,onProgress=()=>{}){
    const JSZipRuntime=await ensureJSZipRuntime();
    onProgress("Reading protected template");
    const buffer=await file.arrayBuffer();
    const archive_sha256=await sha256BytesHex(buffer);
    onProgress("Opening ZIP and checking CRC integrity");
    const zip=await JSZipRuntime.loadAsync(buffer,{checkCRC32:true});
    const names=Object.keys(zip.files),files=names.filter(name=>!zip.files[name].dir);
    if(files.length<1||files.length>900)throw new Error(`Template contains an invalid number of files (${files.length}).`);
    const roots=[...new Set(files.filter(name=>name.endsWith("GITHUB_PAGES_FRONTEND/app.js")).map(name=>name.slice(0,-"GITHUB_PAGES_FRONTEND/app.js".length)))];
    if(roots.length!==1||!roots[0]||!roots[0].endsWith("/"))throw new Error("The ZIP must contain exactly one Report Card Enterprise package root.");
    const root=roots[0],canonical=new Set();
    for(const name of names){if(!safeProtectedTemplatePath(name)||!name.startsWith(root))throw new Error(`Unsafe or out-of-root ZIP path: ${name}`);const key=name.toLowerCase();if(canonical.has(key))throw new Error(`Duplicate case-insensitive ZIP path: ${name}`);canonical.add(key)}
    const checksumEntry=zip.file(`${root}PACKAGE_CHECKSUMS.sha256`),shaSumsEntry=zip.file(`${root}SHA256SUMS.txt`);if(!checksumEntry||!shaSumsEntry)throw new Error("The protected-template checksum files are missing.");
    const checksumBytes=await checksumEntry.async("uint8array"),shaSumsBytes=await shaSumsEntry.async("uint8array"),checksumText=new TextDecoder().decode(checksumBytes),shaSumsText=new TextDecoder().decode(shaSumsBytes),checksums=new Map();
    if(shaSumsText!==checksumText)throw new Error("PACKAGE_CHECKSUMS.sha256 and SHA256SUMS.txt do not match.");
    const checksumLines=checksumText.replace(/^\uFEFF/,"").split(/\r?\n/).filter(line=>line.trim().length>0);
    for(const line of checksumLines){
      const match=line.match(/^([a-f0-9]{64})[ \t]+(.+)$/i);
      if(!match)throw new Error("The checksum manifest contains an invalid line.");
      const relative=match[2];
      if(!safeProtectedTemplatePath(relative)||relative.endsWith("/"))throw new Error(`The checksum manifest contains an unsafe path: ${relative}`);
      if(checksums.has(relative))throw new Error(`The checksum manifest contains a duplicate entry: ${relative}`);
      checksums.set(relative,match[1].toLowerCase());
    }
    const relativeFiles=files.filter(name=>name!==`${root}PACKAGE_CHECKSUMS.sha256`&&name!==`${root}SHA256SUMS.txt`).map(name=>name.slice(root.length));
    const fileSet=new Set(relativeFiles);
    const missing=relativeFiles.filter(relative=>!checksums.has(relative));
    const extra=[...checksums.keys()].filter(relative=>!fileSet.has(relative));
    if(missing.length||extra.length)throw new Error(`The checksum manifest does not match the template file set${missing.length?`; missing ${missing.slice(0,3).join(", ")}`:""}${extra.length?`; extra ${extra.slice(0,3).join(", ")}`:""}.`);
    let totalUncompressed=checksumBytes.byteLength+shaSumsBytes.byteLength,checked=0;
    if(checksumBytes.byteLength>20*1024*1024||shaSumsBytes.byteLength>20*1024*1024)throw new Error("A checksum file exceeds the per-file safety limit.");
    for(const relative of relativeFiles){
      const entry=zip.file(`${root}${relative}`),expected=checksums.get(relative);if(!entry||!expected)throw new Error(`Checksum entry is missing for ${relative}`);
      const bytes=await entry.async("uint8array");totalUncompressed+=bytes.byteLength;if(bytes.byteLength>20*1024*1024)throw new Error(`Template file exceeds the per-file safety limit: ${relative}`);if(totalUncompressed>250*1024*1024)throw new Error("Template uncompressed size exceeds the safety limit.");
      if(await sha256BytesHex(bytes)!==expected)throw new Error(`Template checksum mismatch: ${relative}`);
      checked+=1;if(checked===1||checked%20===0||checked===relativeFiles.length){onProgress(`Validating template checksums (${checked}/${relativeFiles.length})`);await new Promise(resolve=>setTimeout(resolve,0))}
    }
    let manifest;try{manifest=JSON.parse(await zip.file(`${root}PROJECT_MANIFEST.json`).async("string"))}catch{throw new Error("PROJECT_MANIFEST.json is invalid JSON.")}
    if(String(manifest.version||"")!=="7.4.0")throw new Error("The protected template version must be 7.4.0.");
    let schemaMap;try{schemaMap=JSON.parse(await zip.file(`${root}MASTER_SCHEMA_SOURCE_MAP.json`).async("string"))}catch{throw new Error("MASTER_SCHEMA_SOURCE_MAP.json is invalid JSON.")}
    const schemaFiles=["MASTER_SCHEMA_01_OF_10.sql","MASTER_SCHEMA_02_OF_10.sql","MASTER_SCHEMA_03_OF_10.sql","MASTER_SCHEMA_04_OF_10.sql","MASTER_SCHEMA_05_OF_10.sql","MASTER_SCHEMA_06_OF_10.sql","MASTER_SCHEMA_07_OF_10.sql","MASTER_SCHEMA_08_OF_10.sql","MASTER_SCHEMA_09_OF_10.sql","MASTER_SCHEMA_10_OF_10.sql"];
    const consolidated=Array.isArray(schemaMap.consolidated_sequence)?schemaMap.consolidated_sequence:(Array.isArray(schemaMap.schema_files)?schemaMap.schema_files:[]),declaredLimit=Number(schemaMap.maximum_lines_per_schema_file??schemaMap.line_limit);
    if(schemaMap.canonical_equivalence===false||Number(schemaMap.schema_file_count)!==schemaFiles.length||declaredLimit!==2318||consolidated.length!==schemaFiles.length)throw new Error("The consolidated master schema source map is invalid.");
    for(let i=0;i<schemaFiles.length;i++){const schema=schemaFiles[i],item=consolidated[i]||{},entry=zip.file(`${root}${schema}`);if(!entry||String(item.file||"")!==schema||(item.ends_at_transaction_boundary!==undefined&&item.ends_at_transaction_boundary!==true))throw new Error(`The consolidated master schema map is invalid for ${schema}.`);const expected=String(item.sha256||"").toLowerCase();if(!/^[a-f0-9]{64}$/.test(expected)||checksums.get(schema)!==expected)throw new Error(`The consolidated master schema hash map is invalid for ${schema}.`);const schemaText=await entry.async("string"),lineCount=schemaText.replace(/\r\n/g,"\n").replace(/\n$/,"" ).split("\n").length;if(lineCount>2318||Number(item.lines)!==lineCount)throw new Error(`The consolidated master schema line map is invalid for ${schema}.`)}
    if(!(await zip.file(`${root}MASTER_SCHEMA_10_OF_10.sql`).async("string")).includes("10 SCHEMA v7.4.0 TEMPLATE STAFF ID AND WEEKDAY TIMETABLE STABILITY r13: PASS"))throw new Error("The protected template is missing the r13 final schema marker.");
    return {archive_sha256,checksum_manifest_sha256:await sha256BytesHex(checksumBytes),file_count:files.length,total_uncompressed_bytes:totalUncompressed,package_root:root};
  }

  async function uploadPlatformPackageTemplate() {
    const file=byId("platformPackageTemplate")?.files?.[0],button=byId("platformTemplateUpload");
    if(!file){toast("Template not installed","Select the official package template ZIP.","error");return}
    if(!await confirmAction("Install protected package template","The selected ZIP will replace the active server-side template after validation.","Install template"))return;
    button.disabled=true;button.textContent="Validating";setSync("pending","Validating template");
    try{
      if(file.size>PACKAGE_TEMPLATE_MAX_BYTES)throw new Error(`File must not exceed ${readableBytes(PACKAGE_TEMPLATE_MAX_BYTES)}.`);
      const receipt=await validateProtectedTemplateInBrowser(file,message=>{button.textContent="Validating";setSync("pending",message)});
      button.textContent="Uploading";setSync("pending","Uploading validated template");
      const uploadAttempt=async()=>{
        const authorization=await invokePlatformPackageManager("create_template_upload",{filename:file.name,file_size:file.size});
        const serverMax=Number(authorization.max_bytes||PACKAGE_TEMPLATE_MAX_BYTES);if(file.size>serverMax)throw new Error(`File must not exceed ${readableBytes(serverMax)}.`);
        await uploadSignedStorageObject(state.client,"platform-package-templates",authorization.storage_path,authorization.upload_token,file,"application/zip");
        return authorization;
      };
      let authorization;
      try{authorization=await uploadAttempt()}
      catch(uploadError){
        if(!/object exceeded.*maximum allowed size|maximum allowed size|payload too large|entity too large/i.test(uploadError?.message||String(uploadError)))throw uploadError;
        await invokePlatformPackageManager("repair_package_storage",{});
        authorization=await uploadAttempt();
      }
      button.textContent="Activating";setSync("pending","Activating validated template");
      let reconciledStatus=null;
      try{await invokePlatformPackageManager("activate_template_upload",{storage_path:authorization.storage_path,filename:file.name,client_validation_receipt:receipt})}
      catch(activationError){
        const message=activationError?.message||String(activationError||"");
        if(!/compute resources|status code 546|\b546\b|failed to fetch|network|timeout/i.test(message))throw activationError;
        button.textContent="Confirming";setSync("pending","Confirming active template SHA after interrupted response");
        reconciledStatus=await reconcileProtectedTemplateActivation(receipt);if(!reconciledStatus)throw activationError;
      }
      state.platformPackageConsole=reconciledStatus;toast("Protected template installed",reconciledStatus?"The server commit was confirmed by the active template SHA after an interrupted activation response.":"The complete browser checksum scan and compute-safe server validation passed.");await renderGithubNavigator(state.viewToken,true);setSync("online","Synced")
    }
    catch(error){toast("Template not installed",friendlyError(error),"error",9000);setSync("pending","Retry required")}
    finally{button.disabled=false;button.textContent="Install or replace template"}
  }

  async function generateReusableSchoolPackage() {
    if(state.packageGeneratorBusy)return;
    const form=byId("schoolPackageForm"),button=byId("generateSchoolPackage"),progress=byId("packageGeneratorProgress"),progressText=byId("packageGeneratorProgressText");
    if(!form||!button||!progress||!progressText)return;
    const originalButtonText=button.textContent;
    state.packageGeneratorBusy=true;button.disabled=true;button.textContent="Checking readiness";progress.classList.remove("hidden");progressText.textContent="Checking live package-generation prerequisites";setSync("pending","Checking readiness");
    try{
      const liveStatus=await invokePlatformPackageManager("status",{offset:0,limit:1,search:""});
      const mergedStatus={...(state.platformPackageConsole||{}),...liveStatus};state.platformPackageConsole=mergedStatus;updatePlatformPackageGenerationReadiness(mergedStatus);
      const blockers=platformPackageGenerationBlockers(mergedStatus);if(blockers.length)throw new Error(`Package generation is not ready. ${blockers.join(" ")}`);
      if(!form.reportValidity()){setSync("online","Synced");return}
      const values=formObject(form),logoFile=byId("schoolPackageLogo")?.files?.[0];
      const selectedPlan=(liveStatus.plans||[]).find(item=>String(item.id)===String(values.license_plan_code));if(!selectedPlan)throw new Error("Select a current active licence plan.");
      button.textContent="Generating package";progressText.textContent="Preparing package entitlement";setSync("pending","Generating package");
      const includeAndroid=byId("includeAndroidBuildKit")?.checked===true;
      const androidSummary=includeAndroid?` A branded Android build kit will be included for ${values.android_application_id}.`:"";
      const includeWindows=byId("includeWindowsBuildKit")?.checked===true;
      const windowsSummary=includeWindows?` A branded Windows installer build kit will be included for product ${values.windows_product_id} on local port ${values.windows_runtime_port}.`:" The confirmed universal Windows w1 installers will still be included.";
      const deploymentSummary=String(values.authorized_domain||"").trim()?` with host restriction ${String(values.authorized_domain).trim()}`:" without host restriction; the package remains bound to its Supabase project, installation, tenant, and central licence authority";
      const confirmed=await confirmAction("Confirm licensed package entitlement",`${selectedPlan.name} revision ${selectedPlan.revision||1} will be issued to ${values.school_name}${deploymentSummary}. Supabase project: ${String(values.supabase_url).replace(/^https?:\/\//,"").split(".")[0]}. The generated school cannot distribute other packages.${androidSummary}${windowsSummary}`,"Generate signed package");if(!confirmed){setSync("online","Synced");return}
      progressText.textContent="Normalizing school logo for Free-plan package headroom";const normalizedLogo=await normalisePackageSchoolLogo(logoFile),logo_base64=await readFileAsDataUrl(normalizedLogo,PACKAGE_LOGO_MAX_BYTES,PACKAGE_LOGO_TYPES);
      progressText.textContent="Generating and signing compute-safe package on the server";
      if(!state.packageGenerationKey)state.packageGenerationKey=crypto.randomUUID();
      const data=await invokePlatformPackageManager("generate",{...values,include_android_build_kit:includeAndroid,include_windows_build_kit:includeWindows,license_plan_id:selectedPlan.id,license_plan_revision:selectedPlan.revision,idempotency_key:state.packageGenerationKey,logo_base64,logo_mime:"image/png",expires_at:values.expires_at?new Date(values.expires_at).toISOString():""});
      if(!data.signed_url)throw new Error("The package was created but no download authorization was returned.");
      state.packageGenerationKey="";
      const link=document.createElement("a");link.href=data.signed_url;link.rel="noopener";link.click();
      toast("Protected package generated",`${data.artifact.filename} is ready. The signed download URL expires in ${number(data.expires_in)} seconds.`,"success",9000);state.platformPackageConsole=null;setSync("online","Synced");await renderGithubNavigator(state.viewToken,true);
    }catch(error){toast("Package not generated",friendlyError(error),"error",9000);setSync("pending","Retry required");await reportClientError(error,{source:"platform_package_manager"})}
    finally{state.packageGeneratorBusy=false;button.disabled=false;button.textContent=originalButtonText;progress.classList.add("hidden")}
  }


  function renewalCapacityText(plan={}) {
    return [`Students ${plan.max_students??"Unlimited"}`,`Teachers ${plan.max_teachers??"Unlimited"}`,`Administrators ${plan.max_system_admins??"Unlimited"}`,`Guardians ${plan.max_guardians??"Unlimited"}`,`Storage ${plan.max_storage_mb==null?"Unlimited":`${number(plan.max_storage_mb)} MB`}`].join(" • ");
  }
  function renewalDefaultExpiry(plan={},previousExpiry="") {
    if(String(plan.billing_cycle||"")==="perpetual")return "";
    const previousTime=previousExpiry?new Date(previousExpiry).getTime():Number.NaN;
    const base=Math.max(Date.now(),Number.isFinite(previousTime)?previousTime:0);
    return dateTimeLocalValue(new Date(base+Number(plan.default_term_days||365)*86400000));
  }
  function platformEffectiveEntitlementForArtifact(artifact={}) {
    const upgrades=state.platformPackageConsole?.upgrade_authorizations||[];
    const activated=upgrades.find(item=>String(item.artifact_id)===String(artifact.id)&&item.status==="activated");
    if(activated?.metadata?.target_plan)return {plan:activated.metadata.target_plan,license:artifact.entitlement_snapshot?.license||{}};
    return artifact.entitlement_snapshot||{};
  }
  function generatePackageUpgradeCode(artifactId,button) {
    const consoleData=state.platformPackageConsole||{},artifact=(consoleData.artifacts||[]).find(item=>String(item.id)===String(artifactId));if(!artifact)return;
    const activated=(consoleData.upgrade_authorizations||[]).find(item=>String(item.artifact_id)===String(artifact.id)&&item.status==="activated"),currentCode=String(activated?.to_plan_code||artifact.license_plan_code||artifact.entitlement_snapshot?.plan?.code||"").toLowerCase();
    const rank={starter:1,professional:2,enterprise:3},plans=(consoleData.plans||[]).filter(plan=>plan.active!==false&&(rank[String(plan.code||"").toLowerCase()]||0)>(rank[currentCode]||0));
    if(!plans.length){toast("No higher plan available","This school is already on the highest supported plan or its current plan is not eligible for code-based upgrade.","warning");return}
    modal("Generate Upgrade Activation Code",`${artifact.school_name} • ${featureFlagLabel(currentCode)}. The resulting code can be sent by WhatsApp or email and redeemed only by this installed school.`,`<form id="packageUpgradeCodeForm" class="form-grid">
      <div class="template-information full"><strong>Current authority plan: ${esc(featureFlagLabel(currentCode))}</strong><span>${esc(artifact.license_reference)} • ${esc(artifact.tenant_code)}</span><small>Licence dates and deployment binding will be preserved exactly.</small></div>
      <label class="field full"><span>Upgrade to</span><select name="license_plan_id" required>${plans.map(plan=>`<option value="${attr(plan.id)}">${esc(plan.name)} • revision ${number(plan.revision||1)}</option>`).join("")}</select><small id="packageUpgradeCodePlanSummary"></small></label>
      <label class="field"><span>Code validity</span><select name="validity_days"><option value="7" selected>7 days</option><option value="14">14 days</option><option value="30">30 days</option></select></label>
      <label class="field full"><span>Authorization reason</span><textarea name="reason" minlength="5" maxlength="500" required placeholder="Example: Paid upgrade from Professional to Enterprise"></textarea></label>
      <div class="template-information warning full"><strong>One-time display</strong><span>The plaintext activation code is never stored by the browser or database. Copy it from the next screen and send it to the authorized school administrator.</span></div>
    </form>`,`<button class="button ghost" id="packageUpgradeCodeCancel" type="button">Cancel</button><button class="button success" id="packageUpgradeCodeGenerate" type="button">Generate secure code</button>`,`medium`);
    const form=byId("packageUpgradeCodeForm"),select=form.elements.license_plan_id,summary=byId("packageUpgradeCodePlanSummary");
    const sync=()=>{const plan=plans.find(item=>String(item.id)===String(select.value))||{};summary.textContent=`${renewalCapacityText(plan)} • ${Object.entries(plan.feature_flags||{}).filter(([,v])=>v===true).map(([k])=>featureFlagLabel(k)).join(", ")}`};select.onchange=sync;sync();
    byId("packageUpgradeCodeCancel").onclick=closeModal;
    byId("packageUpgradeCodeGenerate").onclick=async()=>{if(!form.reportValidity())return;const values=formObject(form),plan=plans.find(item=>String(item.id)===String(values.license_plan_id));if(!plan)return;const action=byId("packageUpgradeCodeGenerate");action.disabled=true;action.textContent="Generating securely";try{const result=await invokeLicenseUpgradeManager("generate",{artifact_id:artifact.id,license_plan_id:plan.id,license_plan_revision:plan.revision,validity_days:Number(values.validity_days||7),reason:values.reason}),code=result.upgrade_code||"";if(!code)throw new Error("Upgrade authorization was created without a display code");modal("Upgrade Activation Code Generated",`${artifact.school_name} • ${featureFlagLabel(result.preview?.from_plan_code||currentCode)} → ${result.preview?.to_plan_name||featureFlagLabel(result.preview?.to_plan_code||plan.code)}. Copy this code now.`,`<div class="upgrade-code-display"><div class="template-information success"><strong>Authorization created</strong><span>Expires ${esc(isoDateTime(result.authorization?.expires_at))}. It is bound to ${esc(artifact.tenant_code)} and this package installation.</span></div><label class="field"><span>One-time activation code</span><div class="copy-field"><input id="generatedUpgradeCode" value="${attr(code)}" readonly><button class="button secondary" id="copyGeneratedUpgradeCode" type="button">Copy</button></div></label><div class="template-information warning"><strong>Do not regenerate unless necessary</strong><span>Only one open code is permitted per school. If this unused code is lost, revoke it in the authorization register before generating another.</span></div></div>`,`<button class="button primary" id="generatedUpgradeCodeDone" type="button">Done</button>`,`medium`);byId("copyGeneratedUpgradeCode").onclick=async()=>{await navigator.clipboard.writeText(code);toast("Upgrade code copied","Send it only to the authorized System Administrator for this school.")};byId("generatedUpgradeCodeDone").onclick=async()=>{closeModal();state.platformPackageConsole=null;await renderGithubNavigator(state.viewToken,true)};toast("Upgrade code generated","Copy the one-time code before closing this dialog.","success",9000)}catch(error){toast("Upgrade code not generated",friendlyError(error),"error",10000);await reportClientError(error,{source:"platform_upgrade_code_generation",artifact_id:artifact.id})}finally{if(action){action.disabled=false;action.textContent="Generate secure code"}}};
  }
  function revokePackageUpgradeCode(authorizationId,button) {
    modal("Revoke Unused Upgrade Code","This prevents the issued code from being redeemed. A code already redeemed for activation cannot be revoked through this action.",`<label class="field"><span>Revocation reason</span><textarea id="upgradeCodeRevokeReason" minlength="5" required></textarea></label>`,`<button class="button ghost" id="upgradeCodeRevokeCancel" type="button">Cancel</button><button class="button warning" id="upgradeCodeRevokeConfirm" type="button">Revoke unused code</button>`,`small`);
    byId("upgradeCodeRevokeCancel").onclick=closeModal;byId("upgradeCodeRevokeConfirm").onclick=async()=>{const reason=byId("upgradeCodeRevokeReason").value.trim();if(reason.length<5)return;const action=byId("upgradeCodeRevokeConfirm");action.disabled=true;try{await invokeLicenseUpgradeManager("revoke",{authorization_id:authorizationId,reason});closeModal();state.platformPackageConsole=null;toast("Upgrade code revoked");await renderGithubNavigator(state.viewToken,true)}catch(error){toast("Upgrade code not revoked",friendlyError(error),"error",9000)}finally{action.disabled=false}};
  }

  function renewOrUpgradeProtectedPackage(artifactId,button) {
    const consoleData=state.platformPackageConsole||{},artifact=(consoleData.artifacts||[]).find(item=>String(item.id)===String(artifactId));
    if(!artifact){toast("Package not found","Refresh GitHub Navigator and try again.","error");return}
    const plans=(consoleData.plans||[]).filter(item=>item.active!==false),activated=(consoleData.upgrade_authorizations||[]).find(item=>String(item.artifact_id)===String(artifact.id)&&item.status==="activated"),entitlement=artifact.entitlement_snapshot||{},currentPlan=activated?plans.find(item=>String(item.code)===String(activated.to_plan_code))||entitlement.plan||{}:entitlement.plan||{},currentLicense=entitlement.license||{};
    const selectedPlan=plans.find(item=>String(item.code)===String(currentPlan.code))||plans.find(item=>String(item.id)===String(currentPlan.id))||plans.find(item=>String(item.code)===String(artifact.license_plan_code))||plans[0];
    if(!selectedPlan){toast("No active plan","Create or activate a licence plan before renewing.","error");return}
    const sequence=Number(artifact.renewal_sequence||artifact.metadata?.lifecycle?.renewal_sequence||0)+1,referenceBase=String(artifact.license_reference||"RCE-LICENCE").replace(/-R\d+$/i,""),defaultReference=`${referenceBase}-R${sequence}`;
    modal("Renew or Upgrade School Licence",`${artifact.school_name} • ${artifact.tenant_code}. A new signed replacement package will be generated. The current package stays active until the replacement is installed, verified, and finalized.`,`<form id="packageRenewForm" class="form-grid">
      <div class="template-information full"><strong>Current signed entitlement</strong><span>${esc(currentPlan.name||artifact.license_plan_code)} • ${esc(renewalCapacityText(currentPlan))}</span><small>Current expiry: ${esc(currentLicense.expires_at?isoDateTime(currentLicense.expires_at):"No expiry")} • Package ${esc(String(artifact.package_id||"").slice(0,18))}…</small></div>
      <label class="field full"><span>New licence plan</span><select name="license_plan_id" required>${plans.map(plan=>`<option value="${attr(plan.id)}" data-revision="${attr(plan.revision||1)}" ${String(plan.id)===String(selectedPlan.id)?"selected":""}>${esc(plan.name)} • revision ${number(plan.revision||1)}</option>`).join("")}</select><small id="packageRenewPlanSummary"></small></label>
      <label class="field"><span>Licence status</span><select name="license_status"><option value="active" ${String(currentLicense.status||"")==="perpetual"?"":"selected"}>Active</option><option value="perpetual" ${String(currentLicense.status||"")==="perpetual"?"selected":""}>Perpetual</option></select></label>
      <label class="field"><span>Issue date</span><input name="issued_on" type="date" value="${attr(new Date().toISOString().slice(0,10))}" required></label>
      <label class="field"><span>New expiry date and time</span><input name="expires_at" type="datetime-local"></label>
      <label class="field"><span>Renewal reference</span><input name="license_reference" maxlength="80" value="${attr(defaultReference)}" required></label>
      <label class="field full"><span>Renewal or upgrade reason</span><textarea name="reason" minlength="5" required placeholder="Example: Annual renewal and increased student capacity"></textarea></label>
      <div class="template-information warning full"><strong>Safe replacement workflow</strong><span>No student, teacher, report, Storage, or school-setting data is changed. Capacity and enabled features cannot be reduced by this action. Install and verify the new package before finalizing it here.</span></div>
    </form>`,`<button class="button ghost" id="packageRenewCancel" type="button">Cancel</button><button class="button primary" id="packageRenewGenerate" type="button">Generate signed replacement</button>`,"medium");
    const form=byId("packageRenewForm"),planSelect=form.elements.license_plan_id,statusSelect=form.elements.license_status,expiryInput=form.elements.expires_at,summary=byId("packageRenewPlanSummary");
    const sync=()=>{const plan=plans.find(item=>String(item.id)===String(planSelect.value))||{};const perpetual=String(plan.billing_cycle||"")==="perpetual";const option=[...statusSelect.options].find(item=>item.value==="perpetual");if(option)option.disabled=plan.perpetual_allowed!==true;if(perpetual)statusSelect.value="perpetual";else if(statusSelect.value==="perpetual"&&plan.perpetual_allowed!==true)statusSelect.value="active";expiryInput.disabled=statusSelect.value==="perpetual";expiryInput.required=statusSelect.value!=="perpetual"&&["monthly","annual"].includes(String(plan.billing_cycle||""));if(expiryInput.disabled)expiryInput.value="";else if(!expiryInput.value)expiryInput.value=renewalDefaultExpiry(plan,currentLicense.expires_at||"");summary.textContent=`${renewalCapacityText(plan)} • ${number(plan.default_term_days||365)} term days • ${number(plan.grace_days||0)} grace days`;};
    planSelect.onchange=()=>{expiryInput.value="";sync()};statusSelect.onchange=sync;sync();
    byId("packageRenewCancel").onclick=closeModal;
    byId("packageRenewGenerate").onclick=async()=>{if(!form.reportValidity())return;const values=formObject(form),plan=plans.find(item=>String(item.id)===String(values.license_plan_id));if(!plan)return;const action=byId("packageRenewGenerate");action.disabled=true;action.textContent="Generating replacement";try{const result=await invokePlatformPackageManager("renew_or_upgrade",{artifact_id:artifact.id,license_plan_id:plan.id,license_plan_revision:plan.revision,license_status:values.license_status,issued_on:values.issued_on,expires_at:values.expires_at?new Date(values.expires_at).toISOString():"",license_reference:values.license_reference,reason:values.reason,idempotency_key:crypto.randomUUID()});if(!result.signed_url)throw new Error("The replacement was generated but no download authorization was returned.");const link=document.createElement("a");link.href=result.signed_url;link.rel="noopener";link.click();closeModal();state.platformPackageConsole=null;toast("Signed replacement generated","Back up the school, run the included r4 upgrade and SCHOOL_LICENSE_SETUP.sql, redeploy the replacement license-verifier and frontend, then verify the school before finalizing the old package.","success",12000);await renderGithubNavigator(state.viewToken,true)}catch(error){toast("Replacement not generated",friendlyError(error),"error",10000);await reportClientError(error,{source:"platform_package_renew_upgrade",artifact_id:artifact.id})}finally{if(action){action.disabled=false;action.textContent="Generate signed replacement"}}};
  }
  function finalizeReplacementProtectedPackage(artifactId,button) {
    const artifact=(state.platformPackageConsole?.artifacts||[]).find(item=>String(item.id)===String(artifactId));if(!artifact)return;
    modal("Finalize Renewed or Upgraded Licence","Finalize only after the school has installed the replacement and completed a successful central-authority check. This atomically revokes the previous package and preserves the replacement as the active authority record.",`<div class="destructive-confirmation"><div class="template-information success"><strong>Replacement verified by school</strong><span>${esc(artifact.school_name)} • checked ${esc(isoDateTime(artifact.authority_last_checked_at))}</span></div><label class="field"><span>Finalization reason</span><textarea id="packageFinalizeReason" minlength="5" required placeholder="Replacement installed and accepted by the school"></textarea></label><label class="field"><span>Type ACTIVATE to confirm</span><input id="packageFinalizeConfirmText" autocomplete="off" required></label></div>`,`<button class="button ghost" id="packageFinalizeCancel" type="button">Cancel</button><button class="button success" id="packageFinalizeConfirm" type="button">Activate replacement</button>`,"small");
    byId("packageFinalizeCancel").onclick=closeModal;
    byId("packageFinalizeConfirm").onclick=async()=>{const reason=byId("packageFinalizeReason").value.trim(),confirmation=byId("packageFinalizeConfirmText").value.trim();if(reason.length<5||confirmation!=="ACTIVATE"){toast("Replacement not finalized","Enter a clear reason and type ACTIVATE exactly.","error");return}const action=byId("packageFinalizeConfirm");action.disabled=true;action.textContent="Finalizing";try{await invokePlatformPackageManager("finalize_replacement",{artifact_id:artifact.id,reason,confirmation});closeModal();state.platformPackageConsole=null;toast("Replacement activated","The previous package is revoked and the renewed or upgraded package is now the active authority record.","success",9000);await renderGithubNavigator(state.viewToken,true)}catch(error){toast("Replacement not finalized",friendlyError(error),"error",9000)}finally{if(action){action.disabled=false;action.textContent="Activate replacement"}}};
  }

  async function downloadProtectedPackage(artifactId,button) {
    button.disabled=true;
    try{const data=await invokePlatformPackageManager("download",{artifact_id:artifactId});const link=document.createElement("a");link.href=data.signed_url;link.rel="noopener";link.click();toast("Download authorized",`${data.filename} is available through a short-lived signed URL.`);state.platformPackageConsole=null;await renderGithubNavigator(state.viewToken,true)}
    catch(error){toast("Package not downloaded",friendlyError(error),"error",8000)}finally{button.disabled=false}
  }

  async function revokeProtectedPackage(artifactId,button) {
    const reason=window.prompt("Enter the compliance or security reason for revoking this package:","")||"";if(reason.trim().length<5)return;
    if(!await confirmAction("Revoke generated package","New download URLs will be blocked. Existing short-lived URLs may remain valid until their ten-minute expiry.","Revoke package",true))return;
    button.disabled=true;
    try{await invokePlatformPackageManager("revoke",{artifact_id:artifactId,reason:reason.trim()});state.platformPackageConsole=null;toast("Package revoked");await renderGithubNavigator(state.viewToken,true)}
    catch(error){toast("Package not revoked",friendlyError(error),"error",8000)}finally{button.disabled=false}
  }
  async function restoreProtectedPackage(artifactId,button){
    const reason=window.prompt("Enter the reason for restoring this revoked package:","Package restored for authorised deployment")||"";if(reason.trim().length<5)return;
    if(!await confirmAction("Restore generated package","The package will return to Ready status and new authorized download links can be created.","Restore package"))return;
    button.disabled=true;
    try{await invokePlatformPackageManager("restore",{artifact_id:artifactId,reason:reason.trim()});state.platformPackageConsole=null;toast("Package restored");await renderGithubNavigator(state.viewToken,true)}
    catch(error){toast("Package not restored",friendlyError(error),"error",8000)}finally{button.disabled=false}
  }
  function deleteProtectedPackage(artifactId,button){
    modal("Delete Generated Package Permanently","This removes the private ZIP file but retains a deletion receipt and immutable audit record. This action cannot be undone.",`<div class="destructive-confirmation"><label class="field"><span>Deletion reason</span><textarea id="packageDeleteReason" minlength="5" required></textarea></label><label class="field"><span>Type DELETE to confirm</span><input id="packageDeleteConfirmText" autocomplete="off" required></label></div>`,`<button class="button ghost" id="packageDeleteCancel" type="button">Cancel</button><button class="button danger" id="packageDeleteConfirm" type="button">Delete permanently</button>`,"small");
    byId("packageDeleteCancel").onclick=closeModal;
    byId("packageDeleteConfirm").onclick=async()=>{
      const reason=byId("packageDeleteReason").value.trim(),confirmation=byId("packageDeleteConfirmText").value.trim();
      if(reason.length<5||confirmation!=="DELETE"){toast("Package not deleted","Enter a reason and type DELETE exactly.","error");return}
      const action=byId("packageDeleteConfirm");action.disabled=true;action.textContent="Deleting";
      try{const result=await invokePlatformPackageManager("delete",{artifact_id:artifactId,reason,confirmation});state.platformPackageConsole=null;closeModal();toast("Generated package deleted permanently",result.storage_removed===false?"Private Storage cleanup needs platform-owner reconciliation.":"The private package was removed and its deletion receipt retained.",result.storage_removed===false?"warning":"success",9000);await renderGithubNavigator(state.viewToken,true)}
      catch(error){toast("Package not deleted",friendlyError(error),"error",8500)}finally{action.disabled=false;action.textContent="Delete permanently"}
    };
  }
  function clearPackageSecurityAudit(){
    modal("Clear Package Security Audit","This permanently removes the visible package-security events and previous package archive checkpoints. Generated package records and private package files are not deleted.",`<div class="destructive-confirmation"><label class="field"><span>Reset reason</span><textarea id="packageAuditClearReason" minlength="5" required></textarea></label><label class="field"><span>Type CLEAR ALL to confirm</span><input id="packageAuditClearText" autocomplete="off" required></label></div>`,`<button class="button ghost" id="packageAuditClearCancel" type="button">Cancel</button><button class="button danger" id="packageAuditClearConfirm" type="button">Clear all history</button>`,"small");
    byId("packageAuditClearCancel").onclick=closeModal;
    byId("packageAuditClearConfirm").onclick=async()=>{
      const reason=byId("packageAuditClearReason").value.trim(),confirmation=byId("packageAuditClearText").value.trim();
      if(reason.length<5||confirmation!=="CLEAR ALL"){toast("History not cleared","Enter a reason and type CLEAR ALL exactly.","error");return}
      const action=byId("packageAuditClearConfirm");action.disabled=true;action.textContent="Clearing";
      try{await invokePlatformPackageManager("clear_events",{reason,confirmation});state.platformPackageConsole=null;closeModal();toast("Package security audit cleared");await renderGithubNavigator(state.viewToken,true)}
      catch(error){toast("History not cleared",friendlyError(error),"error",8500)}finally{action.disabled=false;action.textContent="Clear all history"}
    };
  }

  async function showVerification(token,verificationType="report") {
    showOnly("verifyView");
    const root=byId("verifyView");root.innerHTML=`<div class="verify-card"><div class="empty">Verifying ${verificationType}</div></div>`;
    try{
      if(!isConfigured()||!window.supabase?.createClient)throw new Error("Verification service unavailable");
      if(!state.client)state.client=window.supabase.createClient(CONFIG.supabaseUrl,CONFIG.supabaseAnonKey,{auth:{persistSession:false}});
      if(verificationType==="staffcard"){
        if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(token||""))){root.innerHTML=`<section class="verify-card"><div class="verify-state invalid">Staff ID card not verified</div><p class="help-text">The verification reference is invalid.</p></section>`;return}
        const data=await rpc("verify_staff_id_card",{token});
        const label=data.valid?"Valid staff ID card":data.status==="expired"?"Staff ID card expired":data.status==="revoked"?"Staff ID card revoked":data.status==="replaced"?"Staff ID card replaced":data.status==="permanently_removed"?"Staff ID card permanently removed":"Staff ID card not verified";
        root.innerHTML=`<section class="verify-card"><div class="verify-head"><img src="${schoolDisplayLogo()}" alt=""><div><h1>${esc(data.school_name||schoolDisplayName())}</h1><p>Staff ID Card Verification</p></div></div><div class="verify-state ${data.valid?"valid":"invalid"}">${esc(label)}</div>${data.found?`<div class="verify-result">${verifyField("Card number",data.card_number)}${data.staff_name?verifyField("Staff",data.staff_name):""}${data.staff_no?verifyField("Staff number",data.staff_no):""}${data.staff_role?verifyField("Role",data.staff_role):""}${data.academic_year?verifyField("Academic year",data.academic_year):""}${data.issue_date?verifyField("Issue date",isoDate(data.issue_date)):""}${data.expires_on?verifyField("Expiry date",isoDate(data.expires_on)):""}${data.revision?verifyField("Revision",`R${number(data.revision||1)}`):""}${data.replacement_card_number?verifyField("Replacement card",data.replacement_card_number):""}</div>`:""}</section>`;
      }else if(verificationType==="idcard"){
        if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(token||""))){root.innerHTML=`<section class="verify-card"><div class="verify-state invalid">ID card not verified</div><p class="help-text">The verification reference is invalid.</p></section>`;return}
        const data=await rpc("verify_student_id_card",{token});
        const label=data.valid?"Valid student ID card":data.status==="expired"?"ID card expired":data.status==="revoked"?"ID card revoked":data.status==="replaced"?"ID card replaced":data.status==="permanently_removed"?"ID card permanently removed":"ID card not verified";
        root.innerHTML=`<section class="verify-card"><div class="verify-head"><img src="${schoolDisplayLogo()}" alt=""><div><h1>${esc(data.school_name||schoolDisplayName())}</h1><p>Student ID Card Verification</p></div></div><div class="verify-state ${data.valid?"valid":"invalid"}">${esc(label)}</div>${data.found?`<div class="verify-result">${verifyField("Card number",data.card_number)}${verifyField("Student",data.student_name)}${verifyField("Admission number",data.admission_no)}${verifyField("Class",data.class_name)}${verifyField("Academic year",data.academic_year)}${verifyField("Issue date",isoDate(data.issue_date))}${verifyField("Expiry date",isoDate(data.expires_on))}${verifyField("Revision",`R${number(data.revision||1)}`)}${data.replacement_card_number?verifyField("Replacement card",data.replacement_card_number):""}</div>`:""}</section>`;
      }else if(verificationType==="certificate"){
        const data=await rpc("verify_certificate",{token});
        root.innerHTML=`<section class="verify-card"><div class="verify-head"><img src="${schoolDisplayLogo()}" alt=""><div><h1>${esc(data.school_name||schoolDisplayName())}</h1><p>Certificate Verification</p></div></div><div class="verify-state ${data.valid?"valid":"invalid"}">${data.valid?"Authentic issued certificate":data.status==="revoked"?"Certificate revoked":data.status==="superseded"?"Certificate superseded":"Certificate not verified"}</div>${data.found?`<div class="verify-result">${verifyField("Certificate number",data.certificate_number)}${verifyField("Recipient",data.recipient_name)}${verifyField("Certificate",data.certificate_title||data.certificate_type_label)}${verifyField("Academic year",data.academic_year)}${data.class_name?verifyField("Class",data.class_name):""}${data.promoted_to?verifyField("Promoted to",data.promoted_to):""}${data.award_category?verifyField("Recognition",data.award_category):""}${verifyField("Issue date",isoDate(data.issue_date))}${data.revocation_reason?verifyField("Revocation reason",data.revocation_reason):""}${data.superseded_by?verifyField("Replacement certificate",data.superseded_by):""}</div>`:""}</section>`;
      }else if(verificationType==="transcript"){
        const data=await rpc("verify_transcript",{token});
        root.innerHTML=`<section class="verify-card"><div class="verify-head"><img src="${schoolDisplayLogo()}" alt=""><div><h1>${esc(data.school_name||schoolDisplayName())}</h1><p>Academic Transcript Verification</p></div></div><div class="verify-state ${data.valid?"valid":"invalid"}">${data.valid?"Authentic current transcript":data.status==="revoked"?"Transcript revoked":data.status==="superseded"?"Transcript superseded":"Transcript not verified"}</div>${data.student_name?`<div class="verify-result">${verifyField("Student",data.student_name)}${verifyField("Admission number",data.admission_no)}${verifyField("Purpose",data.purpose)}${verifyField("Academic records",number(data.record_count))}${verifyField("Issued",isoDateTime(data.issued_at))}${data.revocation_reason?verifyField("Revocation reason",data.revocation_reason):""}</div>`:""}</section>`;
      }else{
        const data=await rpc("verify_report",{token});
        root.innerHTML=`<section class="verify-card">
          <div class="verify-head"><img src="${schoolDisplayLogo()}" alt=""><div><h1>${esc(schoolDisplayName())}</h1><p>Report Card Verification</p></div></div>
          <div class="verify-state ${data.valid?"valid":"invalid"}">${data.valid?"Authentic published report":data.revoked?"Publication withdrawn":"Report not verified"}</div>
          ${data.report_number?`<div class="verify-result">${verifyField("Report number",data.report_number)}${verifyField("Student",data.student_name)}${verifyField("Admission number",data.admission_no)}${verifyField("Class",data.class_name)}${verifyField("Academic year",data.academic_year)}${verifyField("Term",data.term_name)}${verifyField("Average",`${number(data.average,1)}%`)}${data.promotion&&Object.keys(data.promotion).length?verifyField("Automatic promotion",promotionDisplay(data.promotion).title):""}${verifyField("Published",isoDateTime(data.published_at))}</div>`:""}
        </section>`;
      }
    }catch(error){root.innerHTML=`<section class="verify-card"><div class="verify-state invalid">Verification unavailable</div><p class="help-text">${esc(friendlyError(error))}</p></section>`}
  }
  function verifyField(label,value){return `<div class="verify-field"><span>${esc(label)}</span><strong>${esc(value??"—")}</strong></div>`}

})();
