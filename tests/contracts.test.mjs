import test from "node:test";import assert from "node:assert/strict";import fs from "node:fs";
const read=p=>fs.readFileSync(p,"utf8");
test("r42-v18 accounts staff deletion invariant is preserved",()=>{const sql=read("database/migrations/0005_finance_hr_admissions.sql");assert.match(sql,/archive-only/);assert.doesNotMatch(sql,/delete from finance\.accounts_office_staff/i)});
test("frontend never receives database configuration",()=>{const c=read("frontend/config.js");assert.doesNotMatch(c,/DATABASE_URL|postgresql:\/\//i)});
test("certified UI parity stays inside the Worker-backed production boundary",()=>{const h=read("frontend/index.html"),a=read("frontend/app.js"),w=read(".github/workflows/worker-check.yml");assert.match(h,/id="mainNav"/);assert.match(h,/class="app-shell hidden"/);assert.match(a,/window\.EdusentiaApi/);assert.match(a,/get_academic_configuration/);assert.match(a,/set_active_period/);assert.match(w,/"frontend\/\*\*"/);assert.equal(fs.existsSync("frontend/certified"),false);assert.equal(fs.existsSync("reference/certified-ui/app.js"),true);});
test("session cookie is HttpOnly and Secure",()=>{const a=read("worker/src/auth.ts");assert.match(a,/HttpOnly/);assert.match(a,/Secure/)});
test("RLS migration forces tenant policies",()=>{const s=read("database/migrations/0007_rls_and_runtime_grants.sql");assert.match(s,/force row level security/i);assert.match(s,/tenant_isolation/)});

test("CLI bootstrap is secret-gated without weakening normal origin checks",()=>{const i=read("worker/src/index.ts");assert.match(i,/bootstrapCli/);assert.match(i,/x-bootstrap-secret/);assert.match(i,/origin!==env\.APP_ORIGIN/)});
test("retired modules remain retired",()=>{const m=read("docs/MODULE_CATALOG.md");for(const x of ["Inventory","Library","Transport"])assert.match(m,new RegExp(`- ${x}`))});
test("platform license catalog is outside tenant runtime write-default schema",()=>{const m=read("database/migrations/0013_operations_compliance.sql");assert.match(m,/platform\.license_plans/);assert.match(m,/grant select on platform\.license_plans,platform\.license_feature_catalog/);assert.doesNotMatch(m,/grant select,insert,update,delete on all tables in schema platform/)});

test("Turnstile is enforced on login in both browser and Worker",()=>{const c=read("frontend/config.js"),a=read("frontend/api-client.js"),r=read("worker/src/routes.ts"),v=read("worker/src/turnstile.ts");assert.match(c,/turnstileSiteKey:\s*"0x/);assert.match(a,/turnstileToken/);assert.match(r,/verifyTurnstile/);assert.match(v,/siteverify/);assert.match(v,/result\.action\s*!==\s*expectedAction/);assert.match(v,/hostname/)});

test("MFA-required users must complete a second factor before session issuance",()=>{const a=read("worker/src/auth.ts"),m=read("worker/src/mfa.ts"),s=read("database/migrations/0016_mfa_login_challenges.sql");assert.match(a,/if\(!row\.mfa_required\)/);assert.match(a,/mfaRequired:true/);assert.match(a,/assuranceLevel:2/);assert.match(a,/m\.mfa_required or s\.assurance_level>=2/);assert.match(m,/AES-GCM/);assert.match(m,/SHA-1/);assert.match(s,/authn\.login_challenges/);assert.match(s,/mfa_recovery_codes/)});

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
