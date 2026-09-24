import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("tenant shell follows reference role, permission and feature navigation contract",()=>{
  const app=read("frontend/app.js");
  assert.match(app,/const ROLE_NAV_IDS=Object\.freeze\(/);
  assert.match(app,/system_admin:\["dashboard","operations","students","student_services","staff","history","teachers","headteachers","academics","timetable","prospectus","delegations","reports","certificates","id_cards","insights","users","compliance","audit","backup_restore","plan_upgrade","license_capacity","notifications","settings"\]/);
  assert.match(app,/principal:\["dashboard","operations","student_services","staff","history","timetable","delegations","reports","certificates","insights","notifications","compliance"\]/);
  assert.match(app,/class_teacher:\["dashboard","teacher_profile","my_class","attendance","my_subjects","students","student_services","history","timetable","reports","insights","notifications"\]/);
  assert.match(app,/subject_teacher:\["dashboard","teacher_profile","my_subjects","students","student_services","history","timetable","reports","insights","notifications"\]/);
  assert.match(app,/permissionEnabled\(code\)/);
  assert.match(app,/featureEnabled\(code\)/);
  assert.match(app,/item\.permission&&!permissionEnabled\(item\.permission\)&&r!=="system_admin"/);
  assert.match(app,/item\.feature&&!featureEnabled\(item\.feature\)&&r!=="system_admin"/);
  assert.match(app,/Plan upgrade required/);
  assert.match(app,/planUpgradeRequired/);
  assert.match(app,/LEGACY_LICENSE_FEATURE_FALLBACKS/);
  assert.match(app,/id_cards:"core_records"/);
  assert.match(app,/timetable:"core_records"/);
  assert.match(app,/school_prospectus:"core_records"/);
});

test("bootstrap returns effective plan features and role permissions",()=>{
  const routes=read("worker/src/routes.ts");
  assert.match(routes,/from app\.tenant_licenses tl/);
  assert.match(routes,/left join platform\.license_plans lp/);
  assert.match(routes,/coalesce\(lp\.feature_flags,'\{\}'::jsonb\)\|\|coalesce\(tl\.feature_overrides,'\{\}'::jsonb\) feature_flags/);
  assert.match(routes,/from app\.role_permissions where role=\$\{ctx\.role\}/);
  assert.match(routes,/const rawPermissions=\{\.\.\.\(\(permissionRows\[0\] as any\)\?\.permissions\|\|\{\}\)\}/);
  assert.match(routes,/permissions,/);
  assert.match(routes,/license,/);
});

test("core registered views carry reference blueprint gating metadata",()=>{
  const files=[
    "frontend/app.js","frontend/parity-students.js","frontend/parity-teachers.js","frontend/parity-principal.js",
    "frontend/parity-timetable.js","frontend/parity-reports.js","frontend/parity-operations.js",
    "frontend/parity-audit-security-finance.js","frontend/parity-enterprise-workspaces.js"
  ].map(read).join("\n");
  for(const feature of ["attendance","academic_history","timetable","school_prospectus","report_cards","certificates","id_cards","analytics","notifications","governance","finance_fees"]){
    assert.match(files,new RegExp(`feature:["']${feature}["']`),feature+" feature gate missing");
  }
  for(const permission of ["manage_teachers","manage_headteachers","manage_users","view_audit"]){
    assert.match(files,new RegExp(`permission:["']${permission}["']`),permission+" permission gate missing");
  }
  assert.match(files,/id:"headteachers",label:"Principals"/);
  assert.match(files,/id:"reports",label:"Report Cards"/);
  assert.match(files,/id:"compliance",label:"Privacy and Security"/);
});


test("legacy blueprint modules receive unwrapped Worker RPC results",()=>{
  const compat=read("frontend/neon-supabase-compat.js");
  assert.match(compat,/response\?\.result\?\?response/);
  const routes=read("worker/src/routes.ts");
  assert.match(routes,/const isSystemAdmin=ctx\.role==="system_admin"/);
  assert.match(routes,/manage_academics:isSystemAdmin\|\|Boolean\(certifiedPermissions\.manage_academics\)\|\|Boolean\(rawPermissions\["academics\.write"\]\)/);
  assert.match(routes,/manage_teachers:isSystemAdmin\|\|Boolean\(certifiedPermissions\.manage_teachers\)\|\|Boolean\(rawPermissions\["staff\.write"\]\)/);
  assert.match(routes,/manage_headteachers:isSystemAdmin\|\|Boolean\(certifiedPermissions\.manage_headteachers\)\|\|Boolean\(rawPermissions\["admin\.tenant"\]\)/);
  assert.match(routes,/manage_users:isSystemAdmin\|\|Boolean\(certifiedPermissions\.manage_users\)\|\|Boolean\(rawPermissions\["admin\.users"\]\)/);
  assert.match(routes,/view_audit:isSystemAdmin\|\|Boolean\(certifiedPermissions\.view_audit\)\|\|Boolean\(rawPermissions\["admin\.tenant"\]\)/);
});


test("Principal and teacher Student Services use native shell navigation",()=>{
  const app=read("frontend/app.js");
  const studentServices=read("frontend/tenant-student-services-v1.js");
  const actions=read("frontend/tenant-student-services-actions-v1.js");

  assert.match(app,/id:"student_services",label:"Student Services"/);
  assert.match(app,/roles:\["principal","class_teacher","subject_teacher"\]/);
  assert.match(app,/render:renderStudentServices/);
  assert.match(app,/EdusentiaStudentServices/);
  assert.match(app,/await runtime\.openFromShell\(\)/);

  assert.match(studentServices,/SHELL_ROLES=new Set\(\["principal","class_teacher","subject_teacher"\]\)/);
  assert.match(studentServices,/if\(SHELL_ROLES\.has\(role\(\)\)\)\{\$\("studentServicesNav"\)\?\.remove\(\);return\}/);
  assert.match(studentServices,/async function openFromShell\(\)/);
  assert.match(studentServices,/\$\("sidebar"\)\?\.classList\.remove\("open"\)/);
  assert.match(studentServices,/window\.EdusentiaStudentServices=Object\.freeze/);

  assert.match(actions,/\$\("studentServicesNav"\)\|\|nav\.querySelector\('\[data-view="student_services"\]'\)/);
  assert.match(actions,/document\.querySelector\('#mainNav \[data-view="student_services"\]'\)/);
});

test("Student Parent Guardian and Accounts Office extension navigation is shell-managed",()=>{
  const app=read("frontend/app.js");
  const finance=read("frontend/finance-core.js");
  const student=read("frontend/tenant-student-portal-v2.js");
  const parent=read("frontend/tenant-student-portal-v1.js");

  assert.match(app,/\{id:"children",label:"My Children"[^}]*roles:\["parent_guardian"\][^}]*render:renderChildren\}/);
  assert.match(app,/parent_guardian:\["dashboard","children","notifications"\]/);
  assert.match(app,/accountant:\["dashboard","notifications"\]/);
  assert.match(app,/accounts_office:\["dashboard","notifications"\]/);
  assert.match(app,/student:\["dashboard"\]/);
  assert.match(app,/const EXTERNAL_NAV_VIEW_PREFIX="extension:"/);
  assert.match(app,/function installExternalNavigationController\(\)/);
  assert.match(app,/\.nav-item:not\(\[data-view\]\)/);
  assert.match(app,/byId\("sidebar"\)\?\.classList\.remove\("open"\)/);
  assert.match(app,/querySelectorAll\("\.nav-item"\)\.forEach\(button=>\{const active=button\.dataset\.view===item\.id/);
  assert.match(app,/externalNavForCurrentSession\(id\)/);
  assert.match(app,/Parent and Guardian Dashboard/);
  assert.match(app,/list_my_children_reports/);
  assert.match(app,/finance_portal_report_detail/);

  assert.match(finance,/\["accounts_office","accountant"\]\.includes\(S\.role\)/);
  assert.match(finance,/byId\("sidebar"\)\?\.classList\.remove\("open"\);setActive\(true\)/);
  assert.match(student,/data-student-module/);
  assert.match(student,/byId\("sidebar"\)\?\.classList\.remove\("open"\)/);
  assert.match(student,/get_my_student_portal_v2/);
  assert.match(parent,/tenant-student-portal-v2\.js/);
  assert.match(parent,/tenant-student-portal-v2-refinements\.js/);
});

test("Staff & HR uses native shell routing only for Principal and System Administrator",()=>{
  const app=read("frontend/app.js");
  const hr=read("frontend/tenant-hr-staff-v1.js");
  const finance=read("frontend/finance-core.js");
  const accountantRoles=read("frontend/tenant-accountant-student-roles-v2.js");

  assert.match(app,/id:"staff",label:"Staff & HR"[\s\S]*roles:\["system_admin","principal"\][\s\S]*render:renderStaff/);
  assert.doesNotMatch(app,/\{id:"staff"[^}]*nav:false/);
  assert.match(app,/const runtime=window\.EdusentiaHrStaff/);
  assert.match(app,/await runtime\.openFromShell\(\)/);
  assert.match(hr,/\["system_admin","principal"\]\.includes\(S\.role\)/);
  assert.match(hr,/window\.EdusentiaHrStaff=Object\.freeze\(\{openFromShell:open/);
  assert.match(hr,/function nav\(\)\{document\.querySelectorAll\("\.hr-nav-item"\)\.forEach\(x=>x\.remove\(\)\);?\}/);
  assert.match(hr,/function isActiveView\(\)/);
  assert.match(hr,/Loading staff directory/);
  assert.match(hr,/min-width:0/);
  assert.match(hr,/@media\(max-width:700px\)/);

  assert.doesNotMatch(finance,/S\.role==="system_admin"&&hasFeature\("finance_fees"\)/);
  assert.match(accountantRoles,/currentRole\(\) !== "system_admin"[\s\S]*button\?\.remove\(\)[\s\S]*setDirectoryActive\(false\)/);
  assert.match(accountantRoles,/className = "nav-item accounts-directory-nav-item"/);
  assert.match(accountantRoles,/Accounts Office Staff/);
  assert.match(accountantRoles,/admin_accounts_staff_directory/);
  assert.match(accountantRoles,/admin_save_accounts_staff/);
  assert.match(accountantRoles,/admin_deactivate_accounts_staff/);
  assert.match(accountantRoles,/data-accountant-restore/);
  assert.match(accountantRoles,/Archive \/ Remove/);
});


test("Settings separates uploaded report-card design files from class-range summaries",()=>{
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  assert.match(enterprise,/Uploaded Report Card Designs/);
  assert.match(enterprise,/data-template-design-library="1"/);
  assert.match(enterprise,/reportTemplateDesignRange/);
  assert.match(enterprise,/reportTemplateDesignFile/);
  assert.match(enterprise,/reportTemplateDesignUpload/);
  assert.match(enterprise,/data-template-range-summary="1"/);
  assert.match(enterprise,/data-template-plan-upgrade="1"/);
  assert.match(enterprise,/PLAN UPGRADE REQUIRED/);
  assert.match(enterprise,/Professional and Enterprise plans/);
  assert.match(enterprise,/Report Card Templates by Class Range/);
  assert.match(enterprise,/Manage this file in Uploaded Report Card Designs above/);
  assert.match(enterprise,/save_report_card_template/);
  assert.match(enterprise,/remove_report_card_template/);
});

test("System Administrator operational workspaces preserve blueprint UI actions",()=>{
  const shell=read("frontend/app.js");
  const operations=read("frontend/parity-operations.js");
  const students=read("frontend/parity-students.js");
  const academics=read("frontend/parity-academics.js");
  const reports=read("frontend/parity-reports.js");
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  assert.match(shell,/System Administration Dashboard/);
  assert.match(operations,/Production Operations/);
  for(const label of ["Expected reports","Academic period control","System health","Class report progress"])assert.ok(operations.includes(label),label);
  for(const label of ["Student Directory","Import CSV","Export CSV","Add student","data-student-view","data-student-edit","data-student-archive"])assert.ok(students.includes(label),label);
  for(const label of ["Academic Configuration","Academic Periods","Classes and Subjects","Assessment Schemes","Grading Scales","Class Promotion"])assert.ok(academics.includes(label),label);
  for(const label of ["Report Cards","Manage template","Export list","Bulk class PDFs","Publish class reports","New report"])assert.ok(reports.includes(label),label);
  for(const label of ["School Prospectus","Download complete prospectus","Copy year","Emergency Academic Delegation","Certificates and Awards","Templates and settings","ID Card Management","Download printable A4","Users and Access","Licence and Capacity","System Settings","Report Card Templates by Class Range"])assert.ok(enterprise.includes(label),label);
  assert.match(enterprise,/save_school_prospectus_section/);
  assert.match(enterprise,/save_school_prospectus_item/);
  assert.match(enterprise,/save_certificate_template/);
  assert.match(enterprise,/replace_student_id_card/);
  assert.match(enterprise,/name="academic_year_id" required/);
  assert.match(enterprise,/issue_staff_id_cards/);
  assert.match(enterprise,/target_academic_year_id:form\.elements\.academic_year_id\.value/);
  const idCardRuntime=read("database/reference-compat/0067_id_card_issue_runtime_prerequisites.sql");
  assert.match(idCardRuntime,/create sequence if not exists public\.staff_id_card_number_seq/);
  assert.match(idCardRuntime,/create sequence if not exists public\.student_id_card_number_seq/);
  assert.match(idCardRuntime,/create table if not exists public\.staff_id_card_events/);
  assert.match(idCardRuntime,/create table if not exists public\.id_card_events/);
  assert.match(enterprise,/updateSchoolSettings/);
});


test("Users and Access preserves blueprint directory-linked account creation",()=>{
  const ui=read("frontend/parity-enterprise-workspaces.js");
  const api=read("frontend/api-client.js");
  const routes=read("worker/src/routes.ts");
  for(const label of ["Parent / Guardian record","Student record","Accounts Office Staff record","Credentials"])assert.ok(ui.includes(label),label);
  assert.match(ui,/directoryUserManagement/);
  assert.match(ui,/guardian_record_id/);
  assert.match(ui,/student_id/);
  assert.match(ui,/staff_record_id/);
  assert.match(api,/guardianAccountRecords:\(\)=>request\("\/api\/admin\/guardian-account-records"\)/);
  assert.match(routes,/p==="\/api\/admin\/guardian-account-records"/);
  assert.match(routes,/public\.neon_guardian_account_records\(\)/);
  assert.doesNotMatch(routes.split('p==="\/api\/admin\/guardian-account-records"')[1]?.split('p==="\/api\/settings\/school"')[0]||"",/public\.students/);
});


test("Starter System Administrator enterprise navigation registrar is syntactically valid and complete",()=>{
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  assert.doesNotThrow(()=>new Function(enterprise));
  for(const id of [
    "history","prospectus","delegations","certificates","id_cards","insights",
    "users","compliance","backup_restore","plan_upgrade","license_capacity","settings"
  ]){
    assert.match(enterprise,new RegExp(`registerView\\(\\{id:["']${id}["']`),id+" registration missing");
  }
});

test("tenant shell does not render literal newline escape text above the workspace",()=>{
  const html=read("frontend/index.html");
  assert.doesNotMatch(html,/<head>\\\\n/);
});

test("PWA shell carries every navigation parity registrar",()=>{
  const sw=read("frontend/service-worker.js");
  assert.match(sw,/edusentia-neon-v36/);
  for(const asset of [
    "parity-common.js","parity-academics.js","parity-students.js","parity-teachers.js",
    "parity-principal.js","parity-timetable.js","parity-reports.js",
    "parity-audit-security-finance.js","parity-operations.js","parity-enterprise-workspaces.js","tenant-class-teacher-workspace-parity-v1.js"
  ]) assert.ok(sw.includes(asset),asset);
});


test("Class Teacher navigation uses role-scoped bootstrap data and parity workspaces",()=>{
  const routes=read("worker/src/routes.ts");
  const common=read("frontend/parity-common.js");
  const teacher=read("frontend/tenant-class-teacher-workspace-parity-v1.js");
  const index=read("frontend/index.html");
  assert.match(routes,/academic_years:Array\.isArray\(certifiedBootstrap\?\.academic_years\)/);
  assert.match(routes,/terms:Array\.isArray\(certifiedBootstrap\?\.terms\)/);
  assert.match(routes,/classes:Array\.isArray\(certifiedBootstrap\?\.classes\)/);
  assert.match(routes,/subjects:Array\.isArray\(certifiedBootstrap\?\.subjects\)/);
  assert.match(common,/if\(isSystemAdmin\(\)\)return certified\("get_academic_configuration"\)/);
  assert.match(common,/window\.EdusentiaShell\?\.state\?\.boot/);
  for(const label of ["My Teacher Profile","My Class","My Subjects","Class Attendance","Academic Insights","Mark all present","Save attendance","Export summary"]){
    assert.ok(teacher.includes(label),label);
  }
  assert.match(teacher,/save_class_attendance/);
  assert.match(teacher,/academic_analytics/);
  assert.match(teacher,/set_teacher_photo/);
  assert.match(index,/tenant-class-teacher-workspace-parity-v1\.js/);
  assert.match(teacher,/Student Academic History/);
  assert.match(teacher,/Official transcript history is read-only in the teacher workspace/);
  const reports=read("frontend/parity-reports.js");
  assert.match(reports,/id="reportWorkspace"/);
  assert.match(reports,/scrollIntoView\(\{behavior:"smooth",block:"start"\}\)/);
  const timetable=read("frontend/parity-timetable.js");
  assert.match(timetable,/await loadTimetable\(\)/);
  assert.match(timetable,/View the timetable for your accessible classes/);
  assert.match(read("frontend/app.js"),/Class and Subject Teacher Dashboard/);
  assert.match(read("frontend/app.js"),/Home-class responsibilities and subject teaching assignments/);
});


test("Class Teacher history and notifications retain Supabase operational behavior",()=>{
  const teacher=read("frontend/tenant-class-teacher-workspace-parity-v1.js");
  const students=read("frontend/parity-students.js");
  const reports=read("frontend/parity-reports.js");
  const common=read("frontend/parity-common.js");
  const app=read("frontend/app.js");
  const rpc=read("worker/src/certified-rpc.ts");
  assert.match(common,/async function certifiedAllRows\(/);
  assert.match(common,/page_number:page,page_size:100/);
  assert.match(teacher,/certifiedAllRows\("search_students_v5"/);
  assert.doesNotMatch(teacher,/search_students_v5"[^\n]*page_size:200/);
  for(const label of ["Admission number","Academic periods","Transcript issuances","Preview transcript","Download transcript preview","Export CSV","Transcript rule: latest currently valid published report per term only"]){
    assert.ok(teacher.includes(label),label);
  }
  assert.match(students,/data-student-report=/);
  assert.match(students,/pendingReportEnrollmentId/);
  assert.doesNotMatch(students,/search_students_v5"[^\n]*page_size:500/);
  assert.match(reports,/certifiedAllRows\("search_students_v5"/);
  assert.match(reports,/certifiedAllRows\("list_report_cards_v6"/);
  assert.match(reports,/pendingReportId/);
  assert.match(reports,/pendingReportEnrollmentId/);
  assert.doesNotMatch(reports,/page_size:500/);
  for(const label of ["Mark all read","Clear notifications","Delete"]){
    assert.ok(app.includes(label),label);
  }
  assert.match(app,/data-notification-report/);
  assert.match(app,/state\.pendingReportId=/);
  assert.match(app,/certified\("delete_notifications",\{notification_ids:null\}\)/);
  assert.match(app,/data-notification-delete/);
  assert.match(rpc,/const requestedPageSize=intArg\(args,"page_size",\{required:false,min:1,max:500\}\)\?\?20;/);
  assert.match(rpc,/const pageSize=Math\.min\(100,requestedPageSize\);/);
});


test("Principal workspace preserves Supabase operational navigation and AAL2 security",()=>{
  const app=read("frontend/app.js");
  const auth=read("worker/src/auth.ts");
  const operations=read("frontend/parity-operations.js");
  const reports=read("frontend/parity-reports.js");
  const enterprise=read("frontend/parity-enterprise-workspaces.js");
  const hr=read("frontend/tenant-hr-staff-v1.js");

  assert.match(auth,/\["system_admin","principal","platform_super_admin"\]\.includes\(canonicalAppRole\(role\)\)/);
  for(const label of ["Principal Dashboard","Emergency Delegation","Active Students","Awaiting Action","Published Reports","Published Average","Digital Signature","Current Academic Period","Class Performance","Recent Report Cards"]){
    assert.ok(app.includes(label),label);
  }
  assert.match(app,/get_my_headteacher_signature/);
  assert.match(app,/set_my_headteacher_signature/);
  assert.match(app,/uploadFile\(file,"principal-signatures"\)/);

  assert.match(operations,/async function config\(\)\{return academicConfig\(\);\}/);
  for(const label of ["Production Operations","Academic period control","System health","Class report progress","Published-report correction requests"]){
    assert.ok(operations.includes(label),label);
  }

  for(const label of ["Manual template","Export list","Approve class reports","Previous","Next"]){
    assert.ok(reports.includes(label),label);
  }
  assert.match(reports,/bulkTransitionReports\("approved"\)/);
  assert.match(reports,/openManualReportTemplate/);

  for(const label of ["Student Academic History","Issue transcript","Admission number","Academic periods","Transcript issuances","Preview transcript","Download transcript preview","Export CSV","Published Academic Results"]){
    assert.ok(enterprise.includes(label),label);
  }
  assert.match(enterprise,/certifiedAllRows\("search_students_v5"/);
  assert.match(enterprise,/const isAdmin=role\(\)==="system_admin",isPrincipal=role\(\)==="principal"/);
  assert.match(enterprise,/acknowledge_emergency_academic_delegation/);
  assert.match(enterprise,/const createPanel=isAdmin\?/);
  for(const label of ["Academic Insights","Export summary","Subject performance","Class overview","Privacy and Security","New privacy request","Data retention policies","Security events","Security verification history"]){
    assert.ok(enterprise.includes(label),label);
  }
  assert.match(enterprise,/create_privacy_request/);
  assert.match(enterprise,/update_privacy_request/);
  assert.match(enterprise,/resolve_security_event/);
  assert.match(hr,/Multi-factor authentication is required for Staff & HR|Sensitive HR access requires an active licence and MFA\/AAL2/);
});
