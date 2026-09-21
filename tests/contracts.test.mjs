import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const read=p=>fs.readFileSync(p,"utf8");
test("r42-v18 accounts staff deletion invariant is preserved",()=>{const sql=read("database/migrations/0005_finance_hr_admissions.sql");assert.match(sql,/archive-only/);assert.doesNotMatch(sql,/delete from finance\.accounts_office_staff/i)});
test("reference authentication blueprint keeps master registration modal and tenant branding",()=>{
  const h=read("frontend/index.html"),a=read("frontend/app.js"),css=read("frontend/r37-final-ui.css"),pages=read(".github/workflows/deploy-pages.yml");
  assert.match(h,/id="authBrandName">Edusentia</);
  assert.match(h,/id="authBrandTagline">The Academic Operations Platform</);
  assert.match(h,/id="tenantCode" name="tenantCode" type="hidden"/);
  assert.match(h,/id="registrationDialog"/);
  assert.match(h,/New school onboarding/i);
  assert.match(h,/Initial licence plan/i);
  assert.match(h,/Register new school/i);
  assert.match(h,/Forgot password\?/i);
  assert.match(h,/id="togglePassword"/);
  assert.doesNotMatch(h,/href="register\.html">Register school/);
  assert.match(a,/resolveSchool\(code\)/);
  assert.match(a,/Student Academic Service/);
  assert.match(a,/tenant-login/);
  assert.match(a,/registerSchoolButton/);
  assert.match(a,/requestAccessRecovery/);
  assert.match(css,/Reference-blueprint authentication controls/);
  assert.match(pages,/actions\/deploy-pages@v4/);
  assert.match(pages,/path: frontend/);
});

test("frontend never receives database configuration",()=>{const c=read("frontend/config.js");assert.doesNotMatch(c,/DATABASE_URL|postgresql:\/\//i)});
test("certified UI parity stays inside the Worker-backed production boundary",()=>{const h=read("frontend/index.html"),a=read("frontend/app.js"),w=read(".github/workflows/worker-check.yml");assert.match(h,/id="mainNav"/);assert.match(h,/class="app-shell hidden"/);assert.match(a,/window\.EdusentiaApi/);assert.match(a,/get_academic_configuration/);assert.match(a,/set_active_period/);assert.match(w,/"frontend\/\*\*"/);assert.equal(fs.existsSync("frontend/certified"),false);assert.equal(fs.existsSync("reference/certified-ui/app.js"),true);});
test("session cookie is HttpOnly and Secure",()=>{const a=read("worker/src/auth.ts");assert.match(a,/HttpOnly/);assert.match(a,/Secure/)});
test("session authentication establishes tenant RLS context before membership validation",()=>{const a=read("worker/src/auth.ts");assert.match(a,/const sessionRows=await sql/);assert.match(a,/app\.set_request_context/);assert.match(a,/context\.mfa_required/);assert.match(a,/String\(session\.tenant_id\)!==String\(route\.tenant_id\)/);});
test("RLS migration forces tenant policies",()=>{const s=read("database/migrations/0007_rls_and_runtime_grants.sql");assert.match(s,/force row level security/i);assert.match(s,/tenant_isolation/)});

test("CLI bootstrap is secret-gated without weakening normal origin checks",()=>{const i=read("worker/src/index.ts");assert.match(i,/bootstrapCli/);assert.match(i,/x-bootstrap-secret/);assert.match(i,/origin!==env\.APP_ORIGIN/)});
test("retired modules remain retired",()=>{const m=read("docs/MODULE_CATALOG.md");for(const x of ["Inventory","Library","Transport"])assert.match(m,new RegExp(`- ${x}`))});
test("platform license catalog is outside tenant runtime write-default schema",()=>{const m=read("database/migrations/0013_operations_compliance.sql");assert.match(m,/platform\.license_plans/);assert.match(m,/grant select on platform\.license_plans,platform\.license_feature_catalog/);assert.doesNotMatch(m,/grant select,insert,update,delete on all tables in schema platform/)});
test("tenant license status executes inside tenant RLS context",()=>{const r=read("worker/src/routes.ts");const section=r.split('if(method==="GET"&&p==="/api/license/status")')[1]?.split('if(method==="GET"&&p==="/api/bootstrap")')[0]||"";assert.match(section,/tenantTx/);assert.match(section,/app\.tenant_licenses/);});

test("Turnstile is enforced on login in both browser and Worker",()=>{const c=read("frontend/config.js"),a=read("frontend/api-client.js"),r=read("worker/src/routes.ts"),v=read("worker/src/turnstile.ts");assert.match(c,/turnstileSiteKey:\s*"0x/);assert.match(a,/turnstileToken/);assert.match(r,/verifyTurnstile/);assert.match(v,/siteverify/);assert.match(v,/result\.action\s*!==\s*expectedAction/);assert.match(v,/hostname/)});

test("MFA-required users must complete a second factor before session issuance",()=>{const a=read("worker/src/auth.ts"),m=read("worker/src/mfa.ts"),s=read("database/migrations/0016_mfa_login_challenges.sql");assert.match(a,/if\(!row\.mfa_required\)/);assert.match(a,/mfaRequired:true/);assert.match(a,/assuranceLevel:2/);assert.match(a,/context\.mfa_required&&Number\(session\.assurance_level\)<2/);assert.match(a,/edusentia:mfa-challenge:v2:/);assert.doesNotMatch(a,/mfa-challenge:v2:.*SESSION_PEPPER/);assert.match(a,/set_request_context/);assert.match(a,/mfa_pending/);assert.match(m,/AES-GCM/);assert.match(m,/SHA-1/);assert.match(s,/authn\.login_challenges/);assert.match(s,/mfa_recovery_codes/)});

test("Platform Super Administrator is distinct from tenant system_admin",()=>{const s=read("database/migrations/0017_platform_control_plane_foundation.sql"),f=read("database/migrations/0018_platform_super_admin_functions.sql"),a=read("worker/src/platform-auth.ts"),r=read("worker/src/platform-routes.ts");assert.match(s,/platform\.admins/);assert.match(s,/platform_super_admin/);assert.match(f,/bootstrap_first_super_admin/);assert.match(f,/approve_registration/);assert.match(a,/platform-session:v1/);assert.match(a,/assurance_level>=2/);assert.match(r,/platform_login/);assert.doesNotMatch(a,/tenant_memberships/)});
test("Platform onboarding keeps registration approval and licensing behind AAL2 platform routes",()=>{const r=read("worker/src/platform-routes.ts"),f=read("database/migrations/0018_platform_super_admin_functions.sql");assert.match(r,/Platform Super Administrator session is required/);assert.match(r,/configure_initial_license/);assert.match(r,/approve_registration/);assert.match(r,/issue_plan_authorization/);assert.match(r,/platform_capacity_snapshot/);assert.match(f,/mfa_required/);});

test("Tenant administrator setup links are single-use and never expose password tables",()=>{const m=read("database/migrations/0019_tenant_admin_setup_handoff.sql"),r=read("worker/src/platform-routes.ts"),g=read("database/runtime-role.sql"),u=read("frontend/admin-setup.js");assert.match(m,/tenant_admin_setup_tokens/);assert.match(m,/used_at is null/);assert.match(m,/set used_at=now/);assert.match(m,/complete_admin_setup/);assert.match(r,/tenant-admin-setup:v2/);assert.match(r,/randomToken\(32\)/);assert.match(r,/passwordHash\(password\)/);assert.match(g,/revoke all on platform\.tenant_admin_setup_tokens/);assert.match(g,/revoke all on authn\.password_credentials/);assert.doesNotMatch(u,/DATABASE_URL|postgresql:\/\//i)});
test("Capacity override reason is persisted in schema 0019",()=>{const m=read("database/migrations/0019_tenant_admin_setup_handoff.sql");assert.match(m,/student_capacity_reason text not null default/);});

test("Isolated Neon tenant provisioning uses a separate least-privilege creator",()=>{const p=read("database/provisioner-role.sql"),w=read(".github/workflows/deploy-worker.yml"),x=read("worker/src/provisioning.ts");assert.match(p,/createdb nocreaterole noinherit nobypassrls/i);assert.match(p,/nosuperuser/i);assert.match(w,/PROVISIONER_DATABASE_URL/);assert.match(w,/tenant-template\/install\.sh/);assert.match(x,/create database/);assert.match(x,/template/);assert.match(x,/revoke connect on database/);assert.match(x,/edusentia_worker_runtime/);});
test("Tenant template owns school auth and operational data",()=>{const t=read("database/tenant-template/0020_tenant_runtime_parity.sql");assert.match(t,/app\.platform_initialize_tenant/);assert.match(t,/authn\.platform_set_initial_password_by_email/);assert.match(t,/authn\.platform_reset_mfa_by_email/);assert.match(t,/app\.platform_health_snapshot/);assert.match(t,/mfa_required.*true/s);});
test("School sessions route to isolated databases rather than the master",()=>{const a=read("worker/src/auth.ts"),r=read("worker/src/routes.ts"),d=read("worker/src/tenant-db.ts");assert.match(a,/platform\.resolve_login_route/);assert.match(a,/tenantDb\(env/);assert.match(a,/routedToken/);assert.match(r,/tenantDb\(env,ctx\.databaseName\)/);assert.match(d,/databaseUrl/);assert.match(d,/tokenTenantCode/);});
test("Tenant template is locked between provisioning operations",()=>{const s=read("database/tenant-template/install.sh");assert.match(s,/allow_connections false/i);assert.match(s,/revoke connect on database/);assert.match(s,/grant connect on database.*edusentia_provisioner/i);});

test("Tenant template installs certified core and least-privilege Worker grants",()=>{const i=read("database/tenant-template/install.sh"),g=read("database/tenant-template/runtime-role.sql"),r=read("database/reference-compat/install-core.sh");assert.match(i,/reference-compat\/install-core\.sh/);assert.match(i,/tenant-template\/runtime-role\.sql/);assert.match(i,/0045/);assert.match(g,/revoke all on authn\.password_credentials from edusentia_worker_runtime/i);assert.match(g,/grant select on authn\.users to edusentia_worker_runtime/i);assert.match(g,/authn\.lookup_login\(text,text\)/);assert.match(r,/0027_reference_core_part_01/);});
test("Tenant release health requires runtime and certified compatibility identities",()=>{const x=read("worker/src/tenant-release.ts"),p=read("worker/src/provisioning.ts"),r=read("worker/src/platform-routes.ts");assert.match(x,/TENANT_RUNTIME_SCHEMA_VERSION="0020"/);assert.match(x,/CERTIFIED_COMPAT_SCHEMA_VERSION="0045"/);assert.match(x,/get_bootstrap_data/);assert.match(p,/inspectTenantRelease/);assert.match(p,/tenant_release_invalid/);assert.match(r,/certifiedCoreReady/);});
test("Production school onboarding is limited to Basic JHS and Senior High",()=>{const r=read("worker/src/platform-routes.ts"),h=read("frontend/register.html"),m=read("docs/MODULE_CATALOG.md");assert.match(r,/new Set\(\["basic_jhs","senior_high"\]\)/);assert.doesNotMatch(h,/combined_pretertiary|tertiary/);assert.match(m,/Basic\/JHS and Senior High School/);});

test("Certified RPC bridge uses a fixed server-side allowlist and trusted tenant context",()=>{const b=read("worker/src/certified-rpc.ts"),r=read("worker/src/routes.ts"),g=read("database/tenant-template/runtime-role.sql"),a=read("frontend/api-client.js");assert.match(b,/CERTIFIED_RPC_OPERATIONS/);assert.match(b,/get_bootstrap_data/);assert.match(b,/get_academic_configuration/);assert.match(b,/get_academic_calendar_context/);assert.match(b,/get_my_emergency_academic_delegations/);assert.match(b,/academic_configuration_readiness/);assert.match(b,/set_active_period/);assert.match(b,/search_students/);assert.match(b,/search_students_v5/);assert.match(b,/generate_school_identifier/);assert.match(b,/validate_student_import/);assert.match(b,/save_promotion_cutoff/);assert.match(b,/save_academic_entity/);assert.match(b,/archive_academic_entity/);assert.match(b,/save_grading_scale/);assert.match(b,/archive_grading_scale/);assert.match(b,/save_assessment_scheme/);assert.match(b,/save_class_subject_assignments_batch/);assert.match(b,/get_class_timetable_console/);assert.match(b,/save_class_timetable_entry/);assert.match(b,/list_audit_events_v2/);assert.match(b,/list_audit_archives_v1/);assert.match(b,/list_audit_archive_entries_v1/);assert.match(b,/save_student/);assert.match(b,/transition_report_status/);assert.match(b,/list_notifications/);assert.match(b,/certified_rpc_not_allowed/);assert.match(b,/tenantTx/);assert.doesNotMatch(b,/select\s+public\.\$\{/i);assert.match(r,/invokeCertifiedRpc\(sql,ctx/);assert.match(g,/public\.get_bootstrap_data\(\)/);assert.match(a,/certifiedRpc/);});

test("Certified student utility foundation preserves internal least privilege",()=>{const s=read("database/reference-compat/0033_certified_student_management_utilities.sql");assert.match(s,/promotion_cutoff_score/);assert.match(s,/identifier_root/);assert.match(s,/student_identifier_seq/);assert.match(s,/report_promotion_evaluation/);assert.match(s,/refresh_report_promotion/);assert.match(s,/revoke all on function public\.safe_uuid\(text\) from edusentia_worker_runtime/i);});

test("Tenant identity regexes and certified model scope remain intact",()=>{const t=read("database/tenant-template/0020_tenant_runtime_parity.sql"),s=read("database/reference-compat/0033_certified_student_management_utilities.sql");assert.match(t,/\^\[A-Z\]\{3\}-\[0-9\]\{6\}\$/);assert.match(t,/unsupported_institution_type/);assert.match(s,/tenant_code ~ '\^\[A-Z\]\{3\}-\[0-9\]\{6\}\$'/);assert.match(s,/institution_type in\('basic_jhs','senior_high'\)/);});
test("Certified student management exposes only intended Worker entry points",()=>{const s=read("database/reference-compat/0034_certified_student_management_hardening.sql"),g=read("database/tenant-template/runtime-role.sql"),b=read("worker/src/certified-rpc.ts");assert.match(s,/grant execute on function public\.generate_school_identifier\(text\) to edusentia_worker_runtime/i);assert.match(s,/grant execute on function public\.validate_student_import\(jsonb,uuid,uuid,text\) to edusentia_worker_runtime/i);assert.match(s,/grant execute on function public\.save_promotion_cutoff\(integer\) to edusentia_worker_runtime/i);assert.match(s,/revoke all on function public\.can_manage_student\(uuid\) from edusentia_worker_runtime/i);assert.match(g,/generate_school_identifier\(text\)/);assert.match(b,/save_promotion_cutoff/);});

test("Certified teacher and principal hardening keeps management helpers internal",()=>{const s=read("database/reference-compat/0035_certified_teacher_principal_hardening.sql");assert.match(s,/headteachers_single_current_guard/);assert.match(s,/headteachers_one_current_principal_idx/);assert.match(s,/revoke all on function public\.can_manage_teachers\(\) from edusentia_worker_runtime/i);assert.match(s,/revoke all on function public\.can_manage_headteachers\(\) from edusentia_worker_runtime/i);});

test("Certified staff runtime guards preserve audit, licensing, and assignment boundaries",()=>{const s=read("database/reference-compat/0036_certified_staff_runtime_guards.sql");assert.match(s,/create view auth\.users/i);assert.match(s,/teachers_audit/);assert.match(s,/headteachers_audit/);assert.match(s,/teachers_license_write_guard/);assert.match(s,/sync_teacher_record_class_links_trigger/);assert.match(s,/classes_class_teacher_record_id_fkey/);assert.match(s,/revoke all on function public\.enforce_licensed_write\(\) from edusentia_worker_runtime/i);});

test("Certified academic configuration mutations are explicit Worker operations",()=>{const s=read("database/reference-compat/0037_certified_academic_configuration_mutations.sql"),g=read("database/tenant-template/runtime-role.sql"),b=read("worker/src/certified-rpc.ts");for(const name of ["save_academic_entity","archive_academic_entity","save_grading_scale","archive_grading_scale","save_assessment_scheme","save_class_subject_assignments_batch"]){assert.match(s,new RegExp(name));assert.match(g,new RegExp(name));assert.match(b,new RegExp(name));}assert.match(s,/revoke all on function public\.save_academic_entity\(text,jsonb\) from edusentia_worker_runtime/i);});

test("Certified teacher and principal CRUD is installed only through the Worker allowlist",()=>{
  const m=read("database/reference-compat/0038_certified_teacher_principal_crud.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0038_certified_teacher_principal_crud\.sql/);
  assert.match(m,/0038_certified_teacher_principal_crud/);
  for(const operation of ["list_teachers","get_teacher_record","get_my_teacher_profile","save_teacher","archive_teacher","restore_teacher","set_teacher_photo","list_headteachers","get_headteacher_record","get_my_headteacher_signature","save_headteacher","archive_headteacher","restore_headteacher","set_headteacher_photo","set_my_headteacher_signature"]){
    assert.match(b,new RegExp(operation));
  }
  assert.match(g,/public\.save_teacher\(jsonb\)/);
  assert.match(g,/public\.save_headteacher\(jsonb\)/);
  assert.match(g,/public\.set_teacher_photo\(uuid,text,timestamptz\)/);
  assert.match(g,/public\.set_my_headteacher_signature\(text,timestamptz\)/);
  assert.match(b,/function pathArg/);
  assert.match(b,/return "";/);
  assert.match(b,/function timestampArg/);
  assert.match(b,/archive_filter is invalid/);
  assert.doesNotMatch(b,/select\s+public\.\$\{/i);
});


test("Certified timetable parity remains function-mediated and Supabase-realtime free",()=>{
  const m=read("database/reference-compat/0039_certified_timetable_academic_alignment.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0039_certified_timetable_academic_alignment\.sql/);
  assert.match(m,/create table if not exists public\.class_timetable_entries/i);
  assert.match(m,/class_timetable_entry_integrity_guard/);
  assert.match(m,/class_timetable_entries_audit/);
  assert.doesNotMatch(m,/realtime\.broadcast_changes\s*\(/i);
  assert.match(m,/revoke all on table public\.class_timetable_entries from edusentia_worker_runtime/i);
  assert.match(m,/revoke all on function public\.can_view_class_timetable\(uuid\) from edusentia_worker_runtime/i);
  assert.match(m,/revoke all on function public\.validate_class_timetable_entry\(\) from edusentia_worker_runtime/i);
  assert.match(g,/public\.get_class_timetable_console\(uuid,uuid\)/);
  assert.match(g,/public\.save_class_timetable_entry\(jsonb\)/);
  assert.match(b,/get_class_timetable_console/);
  assert.match(b,/save_class_timetable_entry/);
  assert.doesNotMatch(b,/select\s+public\.\$\{/i);
});


test("Certified audit trail archives remain RPC-only and AAL2 guarded",()=>{
  const m=read("database/reference-compat/0040_certified_audit_trail_v1.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0040_certified_audit_trail_v1\.sql/);
  assert.match(m,/create table if not exists public\.audit_log_archives/i);
  assert.match(m,/create table if not exists public\.audit_log_archive_entries/i);
  assert.match(m,/alter table public\.audit_log_archives enable row level security/i);
  assert.match(m,/alter table public\.audit_log_archive_entries enable row level security/i);
  assert.match(m,/revoke all on table public\.audit_log_archives from edusentia_worker_runtime/i);
  assert.match(m,/revoke all on table public\.audit_log_archive_entries from edusentia_worker_runtime/i);
  for(const name of ["list_audit_events_v2","list_audit_archives_v1","list_audit_archive_entries_v1"]){
    assert.match(m,new RegExp(name));
    assert.match(g,new RegExp(name));
    assert.match(b,new RegExp(name));
  }
  assert.doesNotMatch(b,/select\s+public\.\$\{/i);
});


test("Certified notification publication synchronization stays internal to report workflow",()=>{
  const m=read("database/reference-compat/0041_certified_notification_publication_sync.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0041_certified_notification_publication_sync\.sql/);
  assert.match(m,/create or replace function public\.create_workflow_notifications/i);
  assert.match(m,/studentprofile/i);
  assert.match(m,/report card published/i);
  assert.match(m,/revoke all on function public\.create_workflow_notifications\(uuid,public\.report_status\) from edusentia_worker_runtime/i);
  assert.doesNotMatch(g,/grant execute on function public\.create_workflow_notifications/i);
  assert.doesNotMatch(b,/"create_workflow_notifications"/);
  assert.match(b,/transition_report_status/);
});


test("Neon report notification recipient compatibility removes missing student profile dependency",()=>{
  const m=read("database/reference-compat/0041b_neon_notification_recipient_compat.sql");
  const i=read("database/tenant-template/install.sh");
  const s=read("database/synthetic-school-lifecycle-smoke.sh");
  assert.match(m,/create or replace function public\.create_workflow_notifications/i);
  assert.match(m,/public\.guardian_links/);
  assert.doesNotMatch(m,/s\.profile_id/);
  assert.match(m,/revoke all on function public\.create_workflow_notifications\(uuid,public\.report_status\) from edusentia_worker_runtime/i);
  assert.match(i,/0041b_neon_notification_recipient_compat\.sql/);
  assert.match(s,/0041b_neon_notification_recipient_compat\.sql/);
});


test("Certified principal academic history search broadens read parity without records-manager access",()=>{
  const m=read("database/reference-compat/0042_certified_principal_academic_history_read.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0042_certified_principal_academic_history_read\.sql/);
  assert.match(m,/create or replace function public\.search_students_v5/i);
  assert.match(m,/current_app_role\(\) not in \('system_admin','principal'\)/i);
  assert.match(m,/grant execute on function public\.search_students_v5/i);
  assert.match(g,/public\.search_students_v5\(text,uuid,public\.student_status,text,integer,integer\)/);
  assert.match(b,/"search_students_v5"/);
  assert.match(b,/archive_filter is invalid/);
  assert.match(b,/target_status is invalid/);
  assert.doesNotMatch(b,/"can_manage_student"/);
});


test("Certified report governance prerequisites are table-protected and narrowly exposed",()=>{
  const m=read("database/reference-compat/0043_certified_report_governance_prerequisites.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0043_certified_report_governance_prerequisites\.sql/);
  for(const table of ["academic_period_controls","emergency_academic_delegations","report_correction_requests","report_correction_events"]){
    assert.match(m,new RegExp("create table if not exists public\\."+table,"i"));
    assert.match(m,new RegExp("revoke all on table public\\."+table+" from edusentia_worker_runtime","i"));
  }
  assert.match(m,/alter table public\.emergency_academic_delegations force row level security/i);
  for(const fn of ["active_emergency_delegation_ids","has_active_emergency_delegation","term_control_snapshot","term_phase_writable","has_approved_report_correction","mark_report_correction_applied"]){
    assert.match(m,new RegExp(fn));
  }
  assert.match(g,/public\.get_my_emergency_academic_delegations\(uuid,uuid\)/);
  assert.match(b,/"get_my_emergency_academic_delegations"/);
  assert.doesNotMatch(b,/"term_control_snapshot"/);
  assert.doesNotMatch(b,/"mark_report_correction_applied"/);
});


test("Certified report workflow privacy layer exposes only stable frontend report operations",()=>{
  const m=read("database/reference-compat/0044_certified_report_workflow_privacy_integrity.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0044_certified_report_workflow_privacy_integrity\.sql/);
  for(const fn of ["can_view_report_internal","get_report_revisions","get_report_headteacher_signature","get_report_editor","can_delete_report","delete_report_card_permanently","transition_report_status"]){
    assert.match(m,new RegExp(fn));
  }
  assert.match(m,/report_transition_deadline_allowed/);
  assert.match(m,/mark_report_correction_applied/);
  assert.match(m,/REPORT_DRAFT_PERMANENTLY_DELETED/);
  assert.match(g,/public\.get_report_headteacher_signature\(uuid\)/);
  assert.match(g,/public\.delete_report_card_permanently\(uuid,text\)/);
  assert.match(b,/"get_report_headteacher_signature"/);
  assert.match(b,/"delete_report_card_permanently"/);
  assert.doesNotMatch(b,/"can_view_report_internal"/);
  assert.doesNotMatch(b,/"can_delete_report"/);
});


test("Certified report transition helpers match source and stay internal",()=>{
  const m=read("database/reference-compat/0044b_certified_report_transition_helpers.sql");
  const i=read("database/tenant-template/install.sh");
  const s=read("database/synthetic-school-lifecycle-smoke.sh");
  assert.match(m,/create or replace function public\.can_submit_report/i);
  assert.match(m,/create or replace function public\.allowed_report_transitions/i);
  assert.match(m,/public\.can_submit_report\(target_report_id\)/);
  assert.match(m,/current_status='approved' and public\.can_publish_report/);
  assert.match(m,/revoke all on function public\.can_submit_report\(uuid\) from edusentia_worker_runtime/i);
  assert.match(m,/revoke all on function public\.allowed_report_transitions\(uuid\) from edusentia_worker_runtime/i);
  assert.match(i,/0044b_certified_report_transition_helpers\.sql/);
  assert.match(s,/0044b_certified_report_transition_helpers\.sql/);
});


test("Certified report assignment scope prerequisites stay internal before 0044",()=>{
  const m=read("database/reference-compat/0043b_certified_report_assignment_scope.sql");
  const i=read("database/tenant-template/install.sh");
  const b=read("worker/src/certified-rpc.ts");
  assert.match(i,/0043b_certified_report_assignment_scope\.sql/);
  assert.match(m,/is_assigned_class_teacher/);
  assert.match(m,/can_create_report_for_class_term/);
  assert.match(m,/revoke all on function public\.is_assigned_class_teacher\(uuid\) from edusentia_worker_runtime/i);
  assert.match(m,/revoke all on function public\.can_create_report_for_class_term\(uuid,uuid\) from edusentia_worker_runtime/i);
  assert.doesNotMatch(b,/"is_assigned_class_teacher"/);
  assert.doesNotMatch(b,/"can_create_report_for_class_term"/);
});


test("Neon report-view compatibility restores Principal visibility",()=>{
  const m=read("database/reference-compat/0045b_neon_report_view_compat.sql");
  const i=read("database/tenant-template/install.sh");
  const s=read("database/synthetic-school-lifecycle-smoke.sh");
  assert.match(m,/current_app_role\(\) in \('system_admin','principal'\)/);
  assert.match(m,/public\.finance_student_hold_status/);
  assert.match(m,/public\.guardian_links/);
  assert.doesNotMatch(m,/s\.profile_id/);
  assert.match(i,/0045b_neon_report_view_compat\.sql/);
  assert.match(s,/0045b_neon_report_view_compat\.sql/);
});


test("R2-native report PDF integrity preserves certified authorization and removes Supabase storage dependency",()=>{
  const m=read("database/reference-compat/0045_certified_report_pdf_integrity_r2.sql");
  const i=read("database/tenant-template/install.sh");
  const g=read("database/tenant-template/runtime-role.sql");
  const b=read("worker/src/certified-rpc.ts");
  const r=read("worker/src/routes.ts");
  const api=read("frontend/api-client.js");
  assert.match(i,/0045_certified_report_pdf_integrity_r2\.sql/);
  for(const fn of ["can_view_report_pdf","can_manage_report_pdf","can_delete_report_pdf_object","get_report_pdf_descriptor","list_report_pdf_paths","register_report_pdf"]){
    assert.match(m,new RegExp(fn));
  }
  assert.match(m,/storage\.object_metadata/);
  assert.doesNotMatch(m,/storage\.objects/);
  assert.match(m,/finance\.invoices/);
  assert.match(m,/app\.current_tenant_id\(\)/);
  assert.match(g,/public\.get_report_pdf_descriptor\(uuid\)/);
  assert.match(b,/"list_report_pdf_paths"/);
  assert.match(b,/"register_report_pdf"/);
  assert.match(r,/pdf\\\/upload-url/);
  assert.match(r,/can_manage_report_pdf/);
  assert.match(r,/guarded report PDF download endpoint/);
  assert.match(r,/can_delete_report_pdf_object/);
  assert.match(api,/uploadReportPdf/);
  assert.match(api,/downloadReportPdf/);
  assert.match(api,/deleteReportPdfObject/);
});


test("accelerated testing workspaces stay Worker-backed and certified",()=>{
  const h=read("frontend/index.html"),a=read("frontend/app.js"),api=read("frontend/api-client.js"),r=read("worker/src/routes.ts");
  const students=read("frontend/parity-students.js"),teachers=read("frontend/parity-teachers.js"),principal=read("frontend/parity-principal.js");
  const timetable=read("frontend/parity-timetable.js"),reports=read("frontend/parity-reports.js"),ops=read("frontend/parity-audit-security-finance.js"),operations=read("frontend/parity-operations.js");
  assert.match(a,/EdusentiaShell/);assert.match(a,/registerView/);
  for(const script of ["parity-common.js","parity-students.js","parity-teachers.js","parity-principal.js","parity-timetable.js","parity-reports.js","parity-audit-security-finance.js","parity-operations.js"])assert.match(h,new RegExp(script.replace(".","\\.")));
  for(const op of ["search_students_v5","validate_student_import","bulk_import_students","save_student","save_promotion_cutoff"])assert.match(students,new RegExp(op));
  for(const op of ["save_teacher","archive_teacher","restore_teacher","set_teacher_photo"])assert.match(teachers,new RegExp(op));
  for(const op of ["save_headteacher","archive_headteacher","restore_headteacher","set_headteacher_photo","set_my_headteacher_signature"])assert.match(principal,new RegExp(op));
  assert.match(timetable,/get_class_timetable_console/);assert.match(timetable,/save_class_timetable_entry/);
  for(const op of ["get_report_editor","save_report_card","transition_report_status","delete_report_card_permanently","register_report_pdf"])assert.match(reports,new RegExp(op));
  assert.match(reports,/uploadReportPdf/);assert.match(reports,/downloadReportPdf/);assert.match(reports,/deleteReportPdfObject/);
  for(const op of ["list_audit_events_v2","list_audit_archives_v1","list_audit_archive_entries_v1"])assert.match(ops,new RegExp(op));
  assert.match(ops,/mfaFactors/);assert.match(ops,/mfaEnroll/);assert.match(ops,/mfaVerify/);assert.match(ops,/mfaRemove/);
  assert.match(api,/listFinanceInvoices/);assert.match(api,/listFinancePayments/);assert.match(api,/listOperationsOverview/);
  assert.match(operations,/Admissions/);assert.match(operations,/Attendance/);assert.match(operations,/Payroll/);assert.match(operations,/Communications/);
  assert.match(r,/\/api\/finance\/invoices/);assert.match(r,/\/api\/finance\/payments/);assert.match(r,/\/api\/operations\/overview/);assert.match(r,/requireRole\(ctx,\["system_admin","principal","accountant"\]\)/);
  for(const x of [students,teachers,principal,timetable,reports,ops,operations])assert.doesNotMatch(x,/supabase|postgresql:\/\//i);
});


test("parity browser harness is isolated from production configuration",()=>{
  const prod=read("worker/wrangler.jsonc");
  const parity=read("worker/wrangler.parity.jsonc");
  const turnstile=read("worker/src/turnstile.ts");
  const workflow=read(".github/workflows/deploy-parity-test.yml");
  assert.doesNotMatch(prod,/TURNSTILE_TEST_MODE/);
  assert.match(parity,/"TURNSTILE_TEST_MODE": "true"/);
  assert.match(parity,/edusentia-enterprise-neon-parity-test/);
  assert.match(parity,/"run_worker_first": \["\/api\/\*"\]/);
  assert.match(turnstile,/result\.hostname\s*!==\s*expectedHostname/);
  assert.match(turnstile,/result\.action\s*!==\s*expectedAction/);
  assert.match(turnstile,/!result\.success \|\| metadataInvalid/);
  assert.doesNotMatch(workflow,/secrets\.PARITY_WORKER_DATABASE_URL/);
  assert.doesNotMatch(workflow,/secrets\.PARITY_PROVISIONER_DATABASE_URL/);
  assert.match(workflow,/secrets\.NEON_DATABASE_URL \|\| secrets\.DATABASE_URL/);
  assert.match(workflow,/PARITY_DATABASE_HOST/);
  assert.match(workflow,/PARITY_POOLER_DATABASE_HOST/);
  assert.match(workflow,/edusentia_worker_login/);
  assert.match(workflow,/edusentia_provisioner_login/);
  assert.match(workflow,/alter role edusentia_worker_login login password/i);
  assert.match(workflow,/alter role edusentia_provisioner_login login password/i);
  assert.match(workflow,/select session_user session_role,current_user role,current_database\(\) database/);
  assert.match(workflow,/Dedicated parity Worker and provisioner database identities verified/);
  assert.match(workflow,/PARITY_BOOTSTRAP_URL/);
  assert.doesNotMatch(workflow,/schema_version from app\.release_identity/);
  assert.doesNotMatch(workflow,/platform\.release_gate\(\)/);
  assert.match(workflow,/code_deploy_ready=false/);
  assert.match(workflow,/secret_refresh_ready=false/);
  assert.match(workflow,/Verify existing isolated parity deployment/);
  assert.match(workflow,/Existing parity Worker health passed/);
  assert.match(workflow,/Rotatable login wrappers preserve SET-only access/);
  assert.doesNotMatch(workflow,/alter role edusentia_worker_runtime login password/i);
  assert.doesNotMatch(workflow,/alter role edusentia_provisioner login password/i);
  assert.doesNotMatch(workflow,/WORKER_DB_PASSWORD|PROVISIONER_DB_PASSWORD/);
  assert.match(workflow,/ep-shy-meadow-b5e4d9e4\.c-7\.us-east-2\.aws\.neon\.tech/);
  assert.match(workflow,/ep-shy-meadow-b5e4d9e4-pooler\.c-7\.us-east-2\.aws\.neon\.tech/);
  assert.match(workflow,/edusentia-enterprise-neon-parity-test/);
});


test("authenticated parity E2E rotates credentials and exercises R2",()=>{
  const s=read("scripts/parity-authenticated-e2e.mjs");
  const w=read(".github/workflows/deploy-parity-test.yml");
  assert.match(s,/platform_set_initial_password_by_email/);
  assert.match(s,/platform_reset_mfa_by_email/);
  assert.match(s,/XXXX\.DUMMY\.TOKEN\.XXXX/);
  assert.match(s,/assuranceLevel===2/);
  assert.match(s,/\/api\/finance\/summary/);
  assert.match(s,/\/api\/operations\/overview/);
  assert.match(s,/register_report_pdf/);
  assert.match(s,/pdf\/download/);
  assert.match(s,/r2RoundTrip:true/);
  assert.doesNotMatch(s,/postgresql:\/\//i);
  assert.doesNotMatch(s,/Qa!|Nanak2026/i);
  assert.match(w,/Run authenticated parity end-to-end gate/);
  assert.match(w,/scripts\/parity-authenticated-e2e\.mjs/);
});


test("provisioner bootstrap preserves explicit SET-only membership",()=>{
  const p=read("database/provisioner-role.sql");
  const w=read(".github/workflows/deploy-parity-test.yml");
  const t=read(".github/workflows/parity-template-install.yml");
  assert.doesNotMatch(p,/^\s*set role neon_superuser\s*;/im);
  assert.match(p,/grant edusentia_provisioner to edusentia_runtime with admin false, inherit false, set true/i);
  assert.match(p,/one-time database-owner bootstrap/i);
  assert.match(p,/unsafe role attributes/i);
  assert.match(w,/PARITY_PROVISIONER_DATABASE_URL/);
  assert.match(w,/PROVISIONER_DATABASE_URL/);
  assert.match(w,/u\.username!=="edusentia_provisioner_login"/);
  assert.match(w,/inherited_provisioner/);
  assert.match(t,/current_user/);
  assert.match(t,/pg_get_userbyid\(datdba\)/);
  assert.match(t,/edusentia_provisioner/);
  assert.doesNotMatch(t,/PGOPTIONS=.*role=edusentia_provisioner/);
});


test("tenant template handoff uses provisioner after ownership transfer",()=>{
  const i=read("database/tenant-template/install.sh");
  const w=read(".github/workflows/parity-template-install.yml");
  assert.match(i,/alter database \\"\$TEMPLATE_DB\\" owner to edusentia_provisioner/);
  assert.match(i,/set role edusentia_provisioner/);
  assert.match(w,/pg_get_userbyid\(datdba\).*PARITY_TEMPLATE_DATABASE/s);
  assert.doesNotMatch(w,/alter database \\"\$PARITY_TEMPLATE_DATABASE\\" owner to/);
});


test("provisioner-owned template retains deployment-only public schema migration access",()=>{
  const i=read("database/tenant-template/install.sh");
  const w=read(".github/workflows/parity-template-install.yml");
  assert.match(i,/grant usage,create on schema public to edusentia_runtime/i);
  assert.doesNotMatch(i,/grant .*schema public to edusentia_worker_runtime/i);
  assert.doesNotMatch(w,/grant usage,create on schema public to edusentia_worker_runtime/i);
});


test("parity smoke guards avoid application-schema privilege coupling",()=>{
  for(const file of [
    ".github/workflows/schema-smoke.yml",
    ".github/workflows/reference-compat-smoke.yml",
    ".github/workflows/synthetic-school-lifecycle.yml",
    ".github/workflows/deploy-parity-test.yml"
  ]){
    const w=read(file);
    const guard=w.split("- name: Route parity smoke to non-primary Neon branch")[1]
      ?? w.split("- name: Verify isolated parity bootstrap route")[1]
      ?? "";
    const guardStep=guard.split("\n      - name:")[0];
    assert.match(guardStep,/select current_database\(\)/);
    assert.match(guardStep,/current_user/);
    assert.doesNotMatch(guardStep,/app\.release_identity|platform\.release_gate/);
  }
});


test("parity smoke databases clone the minimal pgcrypto CI base",()=>{
  const schema=read(".github/workflows/schema-smoke.yml");
  const compat=read(".github/workflows/reference-compat-smoke.yml");
  const lifecycle=read(".github/workflows/synthetic-school-lifecycle.yml");
  const script=read("database/synthetic-school-lifecycle-smoke.sh");
  for(const w of [schema,compat,lifecycle]){
    assert.match(w,/CI_TEMPLATE_DATABASE=edusentia_ci_base_v2/);
    assert.match(w,/secrets\.NEON_DATABASE_URL \|\| secrets\.DATABASE_URL/);
  }
  assert.match(schema,/owner edusentia_provisioner template/);
  assert.match(schema,/grant connect,create,temp on database .* to edusentia_runtime/i);
  assert.match(compat,/owner edusentia_provisioner template/);
  assert.match(compat,/grant connect,create,temp on database .* to edusentia_runtime/i);
  assert.match(script,/owner edusentia_provisioner template/);
  assert.match(script,/grant connect,create,temp on database .* to edusentia_runtime/i);
});


test("parity tenant infrastructure gate stays provisioner-only",()=>{
  const w=read(".github/workflows/parity-template-install.yml");
  assert.match(w,/Parity Tenant Infrastructure Verify/);
  assert.match(w,/current_user/);
  assert.match(w,/edusentia_provisioner/);
  assert.match(w,/pg_get_userbyid\(datdba\).*PARITY_CI_TEMPLATE_DATABASE/s);
  assert.match(w,/edusentia_runtime/);
  assert.match(w,/datistemplate and not datallowconn/);
  assert.match(w,/has_database_privilege\('edusentia_worker_runtime'/);
  assert.match(w,/create database .*owner edusentia_provisioner template/);
  assert.doesNotMatch(w,/PARITY_WORKER_DATABASE_URL/);
  assert.doesNotMatch(w,/0041b_neon_notification_recipient_compat\.sql/);
  assert.doesNotMatch(w,/platform_initialize_tenant/);
});


test("service login wrappers isolate rotatable passwords from fixed service roles",()=>{
  const s=read("database/service-login-roles.sql");
  assert.match(s,/create role edusentia_worker_login login nosuperuser nocreatedb nocreaterole inherit nobypassrls/i);
  assert.match(s,/create role edusentia_provisioner_login login nosuperuser createdb nocreaterole inherit nobypassrls/i);
  assert.match(s,/grant edusentia_worker_runtime to edusentia_worker_login\s+with admin false, inherit true, set true/i);
  assert.match(s,/grant edusentia_provisioner to edusentia_provisioner_login\s+with admin false, inherit true, set true/i);
  assert.match(s,/grant edusentia_worker_login to edusentia_runtime\s+with admin true, inherit false, set false/i);
  assert.match(s,/grant edusentia_provisioner_login to edusentia_runtime\s+with admin true, inherit false, set false/i);
});

test("deployment runtime assumes Worker role with SET-only membership",()=>{
  const r=read("database/runtime-role.sql");
  const d=read(".github/workflows/deploy-parity-test.yml");
  const infra=read(".github/workflows/parity-template-install.yml");
  assert.match(r,/grant edusentia_worker_runtime to edusentia_runtime with admin false, inherit false, set true/i);
  assert.match(r,/one-time database-owner bootstrap/i);
  assert.match(d,/PARITY_WORKER_DATABASE_URL/);
  assert.match(d,/PARITY_PROVISIONER_DATABASE_URL/);
  assert.doesNotMatch(d,/alter role edusentia_worker_runtime login password/i);
  assert.doesNotMatch(d,/alter role edusentia_provisioner login password/i);
  assert.match(infra,/pg_has_role\('edusentia_runtime','edusentia_worker_runtime','set'\)/);
  assert.match(infra,/not exists\(select 1 from pg_auth_members/s);
});

test("parity administrative workflows keep bootstrap operations on direct Neon sessions",()=>{
  for(const file of [
    ".github/workflows/schema-smoke.yml",
    ".github/workflows/reference-compat-smoke.yml",
    ".github/workflows/synthetic-school-lifecycle.yml",
    ".github/workflows/parity-template-install.yml"
  ]){
    const w=read(file);
    assert.match(w,/ep-shy-meadow-b5e4d9e4\.c-7\.us-east-2\.aws\.neon\.tech/);
    assert.doesNotMatch(w,/ep-shy-meadow-b5e4d9e4-pooler/);
  }
  const deploy=read(".github/workflows/deploy-parity-test.yml");
  assert.match(deploy,/PARITY_DATABASE_HOST: ep-shy-meadow-b5e4d9e4\.c-7\.us-east-2\.aws\.neon\.tech/);
  assert.match(deploy,/PARITY_POOLER_DATABASE_HOST: ep-shy-meadow-b5e4d9e4-pooler\.c-7\.us-east-2\.aws\.neon\.tech/);
  assert.match(deploy,/u\.hostname=process\.env\.PARITY_POOLER_DATABASE_HOST/);
});


test("production deployment separates direct admin and pooled Worker routes with rotatable wrappers",()=>{
  const w=read(".github/workflows/deploy-worker.yml");
  assert.match(w,/ADMIN_DATABASE_URL/);
  assert.match(w,/u\.hostname=u\.hostname\.replace\("-pooler\.","\."\)/);
  assert.match(w,/BOOTSTRAP_DATABASE_URL="\$ADMIN_DATABASE_URL" bash database\/install-master\.sh/);
  assert.match(w,/psql "\$ADMIN_DATABASE_URL".*database\/runtime-role\.sql/);
  assert.match(w,/psql "\$ADMIN_DATABASE_URL".*database\/provisioner-role\.sql/);
  assert.doesNotMatch(w,/secrets\.PRODUCTION_WORKER_DATABASE_URL/);
  assert.doesNotMatch(w,/secrets\.PRODUCTION_PROVISIONER_DATABASE_URL/);
  assert.match(w,/edusentia_worker_login/);
  assert.match(w,/edusentia_provisioner_login/);
  assert.match(w,/WORKER_LOGIN_PASSWORD="\$\(openssl rand -hex 32\)"/);
  assert.match(w,/PROVISIONER_LOGIN_PASSWORD="\$\(openssl rand -hex 32\)"/);
  assert.match(w,/worker\.hostname\.includes\("-pooler\."\)/);
  assert.match(w,/provisioner\.hostname!==admin\.hostname/);
  assert.match(w,/Production Worker and provisioner wrapper identities verified/);
  assert.match(w,/controlled owner-level promotion bootstrap/);
  assert.match(w,/BOOTSTRAP_DATABASE_URL="\$ADMIN_DATABASE_URL" TENANT_TEMPLATE_DATABASE="edusentia_tenant_template"/);
  assert.doesNotMatch(w,/alter role edusentia_worker_runtime login password/i);
  assert.doesNotMatch(w,/alter role edusentia_provisioner login password/i);
});


test("runtime-owned CI seed preserves migration and Worker grant ownership",()=>{
  const schema=read(".github/workflows/schema-smoke.yml");
  const compat=read(".github/workflows/reference-compat-smoke.yml");
  const lifecycle=read(".github/workflows/synthetic-school-lifecycle.yml");
  const infra=read(".github/workflows/parity-template-install.yml");
  for(const w of [schema,compat,lifecycle]) assert.match(w,/edusentia_ci_base_v2/);
  assert.match(infra,/PARITY_CI_TEMPLATE_DATABASE: edusentia_ci_base_v2/);
  assert.match(infra,/edusentia_runtime/);
});


test("database smokes serialize access to the shared parity CI seed",()=>{
  for(const file of [
    ".github/workflows/schema-smoke.yml",
    ".github/workflows/reference-compat-smoke.yml",
    ".github/workflows/synthetic-school-lifecycle.yml"
  ]){
    const w=read(file);
    assert.match(w,/group: edusentia-database-smoke-\$\{\{ github\.ref \}\}/);
    assert.match(w,/cancel-in-progress: false/);
  }
  const schema=read(".github/workflows/schema-smoke.yml");
  const compat=read(".github/workflows/reference-compat-smoke.yml");
  const lifecycle=read("database/synthetic-school-lifecycle-smoke.sh");
  for(const x of [schema,compat,lifecycle]) assert.match(x,/pg_terminate_backend\(pid\).*CI_TEMPLATE_DATABASE/s);
});


test("parity smoke routing locks the shared CI seed before cloning",()=>{
  for(const file of [
    ".github/workflows/schema-smoke.yml",
    ".github/workflows/reference-compat-smoke.yml",
    ".github/workflows/synthetic-school-lifecycle.yml"
  ]){
    const w=read(file);
    assert.match(w,/alter database edusentia_ci_base_v2 with allow_connections false/i);
    assert.match(w,/datistemplate and not datallowconn/);
  }
});


test("CI clones grant runtime public-schema migration access",()=>{
  for(const file of [
    ".github/workflows/schema-smoke.yml",
    ".github/workflows/reference-compat-smoke.yml",
    "database/synthetic-school-lifecycle-smoke.sh"
  ]){
    const x=read(file);
    assert.match(x,/set role edusentia_provisioner; grant usage,create on schema public to edusentia_runtime; reset role;/i);
  }
});


test("certified RPC registry is fixed to the complete 168-operation reference surface",()=>{
  const registry=read("worker/src/certified-rpc-registry.ts");
  const gateway=read("worker/src/certified-rpc.ts");
  const names=[...registry.matchAll(/^  "([^"]+)": \{$/gm)].map(m=>m[1]);
  assert.equal(names.length,168);
  assert.equal(new Set(names).size,168);
  for(const required of [
    "academic_analytics","get_class_attendance_register","save_class_attendance",
    "get_student_academic_history","get_school_prospectus_console","get_certificate_console",
    "get_id_card_console","get_compliance_console","backup_dashboard","operations_dashboard",
    "get_platform_license_console","issue_student_transcript","verify_transcript"
  ]) assert.ok(names.includes(required),required+" missing from certified registry");
  assert.match(registry,/Unknown certified operation argument/);
  assert.match(registry,/CERTIFIED_RPC_REGISTRY\[operation\]/);
  assert.match(registry,/select public\."?\+fn\+"?\(/);
  assert.doesNotMatch(registry,/from request|eval\(|new Function|execute\s+immediate/i);
  assert.match(gateway,/EXPLICIT_CERTIFIED_RPC_OPERATIONS/);
  assert.match(gateway,/return invokeRegistryCertifiedRpc\(sql,ctx,operation,args\);/);
  assert.ok(gateway.indexOf('case "save_student"')<gateway.indexOf("return invokeRegistryCertifiedRpc(sql,ctx,operation,args);"));
});

test("full reference compatibility installer orders schema and helper closure before certified RPCs",()=>{
  const installer=read("database/tenant-template/install.sh");
  const smoke=read(".github/workflows/reference-compat-smoke.yml");
  for(const source of [installer,smoke]){
    const schema=source.indexOf("0045c_certified_operational_schema.sql");
    const helpers=source.indexOf("0045d_certified_rpc_helper_closure.sql");
    const bulk=source.indexOf("0046_certified_reference_rpc_bulk.sql");
    const identity=source.indexOf("0047_certified_identity_rpc_neon.sql");
    const provider=source.indexOf("0048_certified_provider_rpc_neon_r2.sql");
    assert.ok(schema>=0&&helpers>schema&&bulk>helpers&&identity>bulk&&provider>identity);
  }
  const helpers=read("database/reference-compat/0045d_certified_rpc_helper_closure.sql");
  assert.match(helpers,/prospectus_class_range_label/);
  assert.match(helpers,/canonical_school_identity_prefix/);
  assert.match(helpers,/authn\.users/);
  assert.match(helpers,/storage\.object_metadata/);
  assert.doesNotMatch(helpers,/\bstorage\.objects\b/);
});

test("enterprise parity workspace bundle exposes the certified operational modules",()=>{
  const index=read("frontend/index.html");
  const ui=read("frontend/parity-enterprise-workspaces.js");
  assert.match(index,/parity-enterprise-workspaces\.js/);
  for(const view of [
    "attendance","history","prospectus","delegations","certificates","id_cards",
    "insights","children","users","compliance","backup_restore","license_capacity"
  ]) assert.ok(ui.includes('id:"'+view+'"'),view+" workspace missing");
  for(const operation of [
    "get_class_attendance_register","get_student_academic_history","issue_student_transcript",
    "get_school_prospectus_console","get_emergency_delegation_console","get_certificate_console",
    "get_id_card_console","get_staff_id_card_console","academic_analytics","list_my_children_reports",
    "list_profiles_with_access","list_guardian_portal_accounts","get_compliance_console",
    "backup_dashboard","get_recovery_console","get_school_license_capacity_console"
  ]) assert.ok(ui.includes('"'+operation+'"'),operation+" RPC missing");
  assert.doesNotMatch(ui,/supabase|storage\.objects|postgresql:\/\//i);
});
