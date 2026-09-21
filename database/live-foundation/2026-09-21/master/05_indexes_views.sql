-- Edusentia master foundation: indexes and views
-- Read-only schema snapshot from the live Edusentia Supabase master.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

CREATE UNIQUE INDEX assessment_scheme_scope_idx ON public.assessment_schemes USING btree (lower(name), COALESCE(academic_year_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(term_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE (deleted_at IS NULL);

CREATE INDEX attendance_entry_enrollment_idx ON public.student_attendance_entries USING btree (enrollment_id, register_id);

CREATE INDEX attendance_register_term_class_date_idx ON public.class_attendance_registers USING btree (term_id, class_id, attendance_date);

CREATE INDEX audit_actor_idx ON public.audit_log USING btree (actor_id, created_at DESC);

CREATE INDEX audit_log_archive_entries_original_created_at_idx ON public.audit_log_archive_entries USING btree (original_created_at DESC);

CREATE INDEX audit_log_archives_created_at_idx ON public.audit_log_archives USING btree (created_at DESC);

CREATE INDEX audit_record_idx ON public.audit_log USING btree (table_name, record_id, created_at DESC);

CREATE UNIQUE INDEX backup_exports_backup_key_uidx ON public.backup_exports USING btree (backup_key) WHERE (backup_key <> ''::text);

CREATE INDEX backup_exports_expiry_idx ON public.backup_exports USING btree (expires_at) WHERE (status = 'completed'::text);

CREATE UNIQUE INDEX backup_exports_single_processing_full_uidx ON public.backup_exports USING btree ((1)) WHERE ((status = 'processing'::text) AND (backup_type = 'full'::text));

CREATE INDEX backup_exports_status_created_idx ON public.backup_exports USING btree (status, created_at DESC);

CREATE INDEX backup_storage_objects_export_idx ON public.backup_storage_objects USING btree (backup_export_id, source_bucket, source_path);

CREATE INDEX certificate_batches_scope_idx ON public.certificate_batches USING btree (academic_year_id, certificate_type, status, created_at DESC);

CREATE INDEX certificate_events_batch_idx ON public.certificate_events USING btree (batch_id, created_at DESC);

CREATE INDEX certificate_events_certificate_idx ON public.certificate_events USING btree (certificate_id, created_at DESC);

CREATE UNIQUE INDEX certificate_templates_storage_path_uidx ON public.certificate_templates USING btree (storage_path) WHERE (storage_path <> ''::text);

CREATE INDEX certificates_batch_idx ON public.certificates USING btree (batch_id, status, recipient_name);

CREATE INDEX certificates_student_idx ON public.certificates USING btree (student_id, created_at DESC) WHERE (student_id IS NOT NULL);

CREATE INDEX certificates_teacher_idx ON public.certificates USING btree (teacher_id, created_at DESC) WHERE (teacher_id IS NOT NULL);

CREATE INDEX class_subjects_class_idx ON public.class_subjects USING btree (class_id) WHERE active;

CREATE INDEX class_subjects_teacher_idx ON public.class_subjects USING btree (teacher_id) WHERE ((teacher_id IS NOT NULL) AND active);

CREATE INDEX class_timetable_class_day_idx ON public.class_timetable_entries USING btree (academic_year_id, class_id, day_of_week, period_start) WHERE active;

CREATE INDEX class_timetable_teacher_day_idx ON public.class_timetable_entries USING btree (academic_year_id, teacher_id, day_of_week, period_start) WHERE active;

CREATE INDEX classes_active_idx ON public.classes USING btree (level_order, name) WHERE (active AND (deleted_at IS NULL));

CREATE INDEX classes_class_teacher_record_idx ON public.classes USING btree (class_teacher_record_id) WHERE ((deleted_at IS NULL) AND (class_teacher_record_id IS NOT NULL));

CREATE INDEX emergency_academic_delegation_events_created_idx ON public.emergency_academic_delegation_events USING btree (created_at DESC);

CREATE INDEX emergency_academic_delegation_events_delegation_idx ON public.emergency_academic_delegation_events USING btree (delegation_id, created_at DESC);

CREATE INDEX emergency_academic_delegation_events_report_idx ON public.emergency_academic_delegation_events USING btree (report_id, created_at DESC) WHERE (report_id IS NOT NULL);

CREATE INDEX emergency_academic_delegations_console_idx ON public.emergency_academic_delegations USING btree (created_at DESC);

CREATE INDEX emergency_academic_delegations_delegate_idx ON public.emergency_academic_delegations USING btree (delegate_user_id, term_id, class_id, valid_until DESC) WHERE (status = 'active'::text);

CREATE INDEX emergency_academic_delegations_scope_idx ON public.emergency_academic_delegations USING btree (term_id, class_id, subject_id, valid_from, valid_until);

CREATE INDEX enrollments_class_year_idx ON public.enrollments USING btree (class_id, academic_year_id) WHERE (deleted_at IS NULL);

CREATE INDEX enrollments_promotion_source_report_idx ON public.enrollments USING btree (promotion_source_report_id) WHERE (promotion_source_report_id IS NOT NULL);

CREATE INDEX enrollments_student_idx ON public.enrollments USING btree (student_id) WHERE (deleted_at IS NULL);

CREATE INDEX grading_scale_range_idx ON public.grading_scales USING btree (min_mark, max_mark);

CREATE UNIQUE INDEX grading_scale_scope_grade_idx ON public.grading_scales USING btree (COALESCE(academic_year_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(grade)) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX guardian_auth_student_unique ON public.guardian_links USING btree (auth_user_id, student_id) WHERE (auth_user_id IS NOT NULL);

CREATE INDEX headteachers_name_search_idx ON public.headteachers USING btree (lower(last_name), lower(first_name)) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX headteachers_profile_active_idx ON public.headteachers USING btree (profile_id) WHERE ((profile_id IS NOT NULL) AND (deleted_at IS NULL));

CREATE UNIQUE INDEX headteachers_staff_no_ci_idx ON public.headteachers USING btree (lower((staff_no)::text)) WHERE (deleted_at IS NULL);

CREATE INDEX headteachers_status_idx ON public.headteachers USING btree (employment_status, active) WHERE (deleted_at IS NULL);

CREATE INDEX id_card_events_card_idx ON public.id_card_events USING btree (card_id, created_at DESC);

CREATE UNIQUE INDEX id_card_settings_singleton_idx ON public.id_card_settings USING btree ((true));

CREATE UNIQUE INDEX license_entitlement_overrides_one_active_idx ON public.license_entitlement_overrides USING btree (license_id) WHERE active;

CREATE INDEX license_events_created_idx ON public.license_events USING btree (created_at DESC);

CREATE INDEX license_verification_created_idx ON public.license_verification_logs USING btree (created_at DESC);

CREATE INDEX notifications_recipient_idx ON public.notifications USING btree (recipient_id, read_at, created_at DESC);

CREATE UNIQUE INDEX one_active_academic_year_idx ON public.academic_years USING btree (is_active) WHERE (is_active AND (deleted_at IS NULL));

CREATE UNIQUE INDEX one_active_certificate_template_type_idx ON public.certificate_templates USING btree (certificate_type) WHERE active;

CREATE UNIQUE INDEX one_active_term_idx ON public.terms USING btree (is_active) WHERE (is_active AND (deleted_at IS NULL));

CREATE UNIQUE INDEX one_live_publication_per_report_idx ON public.report_publications USING btree (report_id) WHERE (revoked_at IS NULL);

CREATE INDEX outbox_lock_idx ON public.notification_outbox USING btree (locked_by, locked_at) WHERE (processed_at IS NULL);

CREATE INDEX outbox_pending_idx ON public.notification_outbox USING btree (next_attempt_at, locked_at) WHERE (processed_at IS NULL);

CREATE INDEX platform_access_locks_active_idx ON public.platform_access_locks USING btree (active, starts_at DESC, ends_at);

CREATE INDEX platform_package_artifacts_generated_by_idx ON public.platform_package_artifacts USING btree (generated_by) WHERE (generated_by IS NOT NULL);

CREATE INDEX platform_package_artifacts_generated_idx ON public.platform_package_artifacts USING btree (generated_at DESC);

CREATE UNIQUE INDEX platform_package_artifacts_idempotency_idx ON public.platform_package_artifacts USING btree (idempotency_key) WHERE (idempotency_key <> ''::text);

CREATE UNIQUE INDEX platform_package_artifacts_installation_id_idx ON public.platform_package_artifacts USING btree (installation_id) WHERE (installation_id IS NOT NULL);

CREATE UNIQUE INDEX platform_package_artifacts_one_ready_replacement_idx ON public.platform_package_artifacts USING btree (supersedes_artifact_id) WHERE ((supersedes_artifact_id IS NOT NULL) AND (status = 'ready'::text) AND (deletion_state = 'none'::text));

CREATE UNIQUE INDEX platform_package_artifacts_package_id_idx ON public.platform_package_artifacts USING btree (package_id) WHERE (package_id IS NOT NULL);

CREATE INDEX platform_package_artifacts_revoked_by_idx ON public.platform_package_artifacts USING btree (revoked_by) WHERE (revoked_by IS NOT NULL);

CREATE INDEX platform_package_artifacts_superseded_by_idx ON public.platform_package_artifacts USING btree (superseded_by_artifact_id) WHERE (superseded_by_artifact_id IS NOT NULL);

CREATE INDEX platform_package_artifacts_supersedes_idx ON public.platform_package_artifacts USING btree (supersedes_artifact_id, generated_at DESC) WHERE (supersedes_artifact_id IS NOT NULL);

CREATE INDEX platform_package_artifacts_tenant_idx ON public.platform_package_artifacts USING btree (tenant_code, generated_at DESC);

CREATE INDEX platform_package_events_actor_idx ON public.platform_package_events USING btree (actor_id) WHERE (actor_id IS NOT NULL);

CREATE INDEX platform_package_events_artifact_idx ON public.platform_package_events USING btree (artifact_id) WHERE (artifact_id IS NOT NULL);

CREATE INDEX platform_package_events_created_idx ON public.platform_package_events USING btree (created_at DESC);

CREATE INDEX platform_package_events_template_idx ON public.platform_package_events USING btree (template_id) WHERE (template_id IS NOT NULL);

CREATE UNIQUE INDEX platform_package_reconciliation_one_open_idx ON public.platform_package_reconciliation USING btree (artifact_id) WHERE ((artifact_id IS NOT NULL) AND (status = ANY (ARRAY['pending'::text, 'failed'::text])));

CREATE INDEX platform_package_reconciliation_requested_by_idx ON public.platform_package_reconciliation USING btree (requested_by) WHERE (requested_by IS NOT NULL);

CREATE UNIQUE INDEX platform_package_templates_one_active_idx ON public.platform_package_templates USING btree (active) WHERE active;

CREATE INDEX platform_package_templates_uploaded_by_idx ON public.platform_package_templates USING btree (uploaded_by) WHERE (uploaded_by IS NOT NULL);

CREATE UNIQUE INDEX platform_release_catalog_one_active_idx ON public.platform_release_catalog USING btree (status) WHERE (status = 'active'::text);

CREATE INDEX platform_release_gate_runs_checked_idx ON public.platform_release_gate_runs USING btree (checked_at DESC);

CREATE INDEX profiles_role_idx ON public.profiles USING btree (role) WHERE active;

CREATE UNIQUE INDEX report_correction_one_pending_idx ON public.report_correction_requests USING btree (report_id) WHERE (status = 'pending'::text);

CREATE INDEX report_correction_status_created_idx ON public.report_correction_requests USING btree (status, created_at DESC);

CREATE UNIQUE INDEX report_number_unique_idx ON public.student_reports USING btree (report_number) WHERE (report_number IS NOT NULL);

CREATE INDEX reports_enrollment_idx ON public.student_reports USING btree (enrollment_id) WHERE (deleted_at IS NULL);

CREATE INDEX reports_term_status_idx ON public.student_reports USING btree (term_id, status) WHERE (deleted_at IS NULL);

CREATE INDEX revisions_report_idx ON public.report_revisions USING btree (report_id, version DESC);

CREATE UNIQUE INDEX saas_access_recovery_requests_one_pending_idx ON public.saas_access_recovery_requests USING btree (tenant_id) WHERE (status = 'pending'::text);

CREATE INDEX saas_access_recovery_requests_requested_idx ON public.saas_access_recovery_requests USING btree (requested_at DESC);

CREATE INDEX saas_access_recovery_requests_tenant_status_idx ON public.saas_access_recovery_requests USING btree (tenant_id, status, requested_at DESC);

CREATE INDEX saas_plan_upgrade_attempts_rate_idx ON public.saas_plan_upgrade_attempts USING btree (tenant_id, attempted_at DESC) WHERE (successful = false);

CREATE INDEX saas_plan_upgrade_codes_expiry_idx ON public.saas_plan_upgrade_codes USING btree (status, expires_at);

CREATE INDEX saas_plan_upgrade_codes_from_plan_idx ON public.saas_plan_upgrade_codes USING btree (from_plan_code);

CREATE INDEX saas_plan_upgrade_codes_issued_by_idx ON public.saas_plan_upgrade_codes USING btree (issued_by);

CREATE INDEX saas_plan_upgrade_codes_license_expiry_idx ON public.saas_plan_upgrade_codes USING btree (license_expires_at) WHERE (license_expires_at IS NOT NULL);

CREATE INDEX saas_plan_upgrade_codes_revoked_by_idx ON public.saas_plan_upgrade_codes USING btree (revoked_by);

CREATE INDEX saas_plan_upgrade_codes_tenant_history_idx ON public.saas_plan_upgrade_codes USING btree (tenant_id, issued_at DESC);

CREATE INDEX saas_plan_upgrade_codes_to_plan_idx ON public.saas_plan_upgrade_codes USING btree (to_plan_code);

CREATE UNIQUE INDEX saas_plan_upgrade_one_open_per_tenant_idx ON public.saas_plan_upgrade_codes USING btree (tenant_id) WHERE (status = ANY (ARRAY['issued'::text, 'redeemed_pending_activation'::text]));

CREATE UNIQUE INDEX saas_provisioning_one_open_job_idx ON public.saas_provisioning_jobs USING btree (tenant_id) WHERE (status = ANY (ARRAY['queued'::text, 'running'::text, 'waiting_project'::text, 'failed'::text]));

CREATE INDEX saas_provisioning_queue_idx ON public.saas_provisioning_jobs USING btree (status, next_attempt_at, created_at);

CREATE INDEX saas_school_deletion_jobs_actor_idx ON public.saas_school_deletion_jobs USING btree (actor_id) WHERE (actor_id IS NOT NULL);

CREATE UNIQUE INDEX saas_school_deletion_one_open_idx ON public.saas_school_deletion_jobs USING btree (registration_id) WHERE ((registration_id IS NOT NULL) AND (status <> 'completed'::text));

CREATE INDEX saas_school_deletion_status_idx ON public.saas_school_deletion_jobs USING btree (status, updated_at);

CREATE INDEX saas_student_capacity_events_actor_idx ON public.saas_student_capacity_events USING btree (actor_id) WHERE (actor_id IS NOT NULL);

CREATE INDEX saas_student_capacity_events_tenant_created_idx ON public.saas_student_capacity_events USING btree (tenant_id, created_at DESC);

CREATE INDEX saas_tenant_events_actor_idx ON public.saas_tenant_events USING btree (actor_id) WHERE (actor_id IS NOT NULL);

CREATE INDEX saas_tenant_events_registration_idx ON public.saas_tenant_events USING btree (registration_id) WHERE (registration_id IS NOT NULL);

CREATE INDEX saas_tenant_events_tenant_created_idx ON public.saas_tenant_events USING btree (tenant_id, created_at DESC);

CREATE INDEX saas_tenant_health_tenant_checked_idx ON public.saas_tenant_health USING btree (tenant_id, checked_at DESC);

CREATE INDEX saas_tenant_release_edge_functions_slug_idx ON public.saas_tenant_release_edge_functions USING btree (function_slug);

CREATE UNIQUE INDEX saas_tenant_release_edge_functions_slug_uidx ON public.saas_tenant_release_edge_functions USING btree (release_code, function_slug);

CREATE INDEX saas_tenant_release_migrations_name_idx ON public.saas_tenant_release_migrations USING btree (migration_name);

CREATE UNIQUE INDEX saas_tenant_release_migrations_version_uidx ON public.saas_tenant_release_migrations USING btree (release_code, migration_version);

CREATE UNIQUE INDEX saas_tenant_releases_one_active ON public.saas_tenant_releases USING btree (status) WHERE (status = 'active'::text);

CREATE UNIQUE INDEX saas_tenant_releases_one_active_uidx ON public.saas_tenant_releases USING btree (status) WHERE (status = 'active'::text);

CREATE INDEX saas_tenants_license_expiry_idx ON public.saas_tenants USING btree (license_expires_at) WHERE (license_expires_at IS NOT NULL);

CREATE UNIQUE INDEX saas_tenants_login_domain_uidx ON public.saas_tenants USING btree (login_domain);

CREATE INDEX saas_tenants_plan_code_idx ON public.saas_tenants USING btree (plan_code);

CREATE UNIQUE INDEX saas_tenants_project_ref_idx ON public.saas_tenants USING btree (project_ref) WHERE (project_ref <> ''::text);

CREATE INDEX saas_tenants_release_status_idx ON public.saas_tenants USING btree (release_status, release_checked_at DESC);

CREATE INDEX saas_tenants_status_plan_idx ON public.saas_tenants USING btree (status, plan_code);

CREATE UNIQUE INDEX school_licenses_singleton_idx ON public.school_licenses USING btree ((true));

CREATE INDEX school_prospectus_items_section_idx ON public.school_prospectus_items USING btree (section_id, display_order, id);

CREATE INDEX school_prospectus_revisions_parent_idx ON public.school_prospectus_revisions USING btree (prospectus_id, revision_no DESC);

CREATE INDEX school_prospectus_sections_parent_idx ON public.school_prospectus_sections USING btree (prospectus_id, display_order, id);

CREATE INDEX school_prospectuses_year_status_idx ON public.school_prospectuses USING btree (academic_year_id, status, class_range);

CREATE UNIQUE INDEX school_registrations_open_school_email_idx ON public.school_registrations USING btree (lower(school_name), lower((contact_email)::text)) WHERE (status = ANY (ARRAY['pending'::text, 'approved'::text, 'provisioning'::text, 'active'::text]));

CREATE INDEX school_registrations_requested_plan_idx ON public.school_registrations USING btree (requested_plan_code);

CREATE INDEX school_registrations_reviewed_by_idx ON public.school_registrations USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);

CREATE INDEX school_registrations_status_created_idx ON public.school_registrations USING btree (status, created_at);

CREATE INDEX school_registrations_tenant_idx ON public.school_registrations USING btree (tenant_id) WHERE (tenant_id IS NOT NULL);

CREATE INDEX school_restore_jobs_created_idx ON public.school_restore_jobs USING btree (created_at DESC);

CREATE UNIQUE INDEX school_restore_one_active_idx ON public.school_restore_jobs USING btree ((true)) WHERE (status = ANY (ARRAY['validating'::text, 'restoring'::text]));

CREATE INDEX school_restore_stage_tables_staged_at_idx ON public.school_restore_stage_tables USING btree (staged_at);

CREATE UNIQUE INDEX school_settings_singleton_idx ON public.school_settings USING btree ((true));

CREATE INDEX score_entries_result_idx ON public.assessment_score_entries USING btree (subject_result_id);

CREATE INDEX security_events_status_severity_idx ON public.security_events USING btree (status, severity, created_at DESC);

CREATE INDEX staff_id_card_events_card_idx ON public.staff_id_card_events USING btree (card_id, created_at DESC);

CREATE UNIQUE INDEX staff_id_cards_principal_active_idx ON public.staff_id_cards USING btree (headteacher_id) WHERE ((status = 'active'::text) AND (headteacher_id IS NOT NULL));

CREATE UNIQUE INDEX staff_id_cards_teacher_active_idx ON public.staff_id_cards USING btree (teacher_id) WHERE ((status = 'active'::text) AND (teacher_id IS NOT NULL));

CREATE INDEX staff_id_cards_year_status_idx ON public.staff_id_cards USING btree (academic_year_id, staff_type, status, issued_at DESC);

CREATE UNIQUE INDEX student_id_cards_one_active_year_idx ON public.student_id_cards USING btree (student_id, academic_year_id) WHERE (status = 'active'::text);

CREATE INDEX student_id_cards_student_idx ON public.student_id_cards USING btree (student_id, issued_at DESC);

CREATE INDEX student_id_cards_year_class_idx ON public.student_id_cards USING btree (academic_year_id, class_id, status, issued_at DESC);

CREATE UNIQUE INDEX student_reports_active_enrollment_term_uidx ON public.student_reports USING btree (enrollment_id, term_id) WHERE (deleted_at IS NULL);

CREATE INDEX student_reports_deleted_idx ON public.student_reports USING btree (deleted_at, term_id);

CREATE UNIQUE INDEX students_admission_no_ci_idx ON public.students USING btree (lower((admission_no)::text)) WHERE (deleted_at IS NULL);

CREATE INDEX students_search_idx ON public.students USING btree (lower(last_name), lower(first_name), admission_no) WHERE (deleted_at IS NULL);

CREATE INDEX subject_results_report_idx ON public.subject_results USING btree (report_id);

CREATE INDEX subjects_active_idx ON public.subjects USING btree (display_order, name) WHERE (active AND (deleted_at IS NULL));

CREATE UNIQUE INDEX teacher_award_categories_code_idx ON public.teacher_award_categories USING btree (lower((code)::text));

CREATE UNIQUE INDEX teacher_award_categories_name_idx ON public.teacher_award_categories USING btree (lower(name));

CREATE UNIQUE INDEX teachers_emis_code_ci_idx ON public.teachers USING btree (lower((emis_code)::text)) WHERE ((emis_code IS NOT NULL) AND (btrim((emis_code)::text) <> ''::text) AND (deleted_at IS NULL));

CREATE INDEX teachers_name_search_idx ON public.teachers USING btree (lower(last_name), lower(first_name)) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX teachers_profile_active_idx ON public.teachers USING btree (profile_id) WHERE ((profile_id IS NOT NULL) AND (deleted_at IS NULL));

CREATE UNIQUE INDEX teachers_staff_no_ci_idx ON public.teachers USING btree (lower((staff_no)::text)) WHERE (deleted_at IS NULL);

CREATE INDEX teachers_status_idx ON public.teachers USING btree (employment_status, active) WHERE (deleted_at IS NULL);

CREATE INDEX terms_year_idx ON public.terms USING btree (academic_year_id) WHERE (deleted_at IS NULL);

CREATE INDEX transcript_student_issued_idx ON public.transcript_issuances USING btree (student_id, issued_at DESC);

CREATE UNIQUE INDEX user_class_access_class_scope_idx ON public.user_class_access USING btree (user_id, class_id) WHERE (subject_id IS NULL);

CREATE UNIQUE INDEX user_class_access_subject_scope_idx ON public.user_class_access USING btree (user_id, class_id, subject_id) WHERE (subject_id IS NOT NULL);

CREATE INDEX user_class_access_user_idx ON public.user_class_access USING btree (user_id, class_id);

CREATE INDEX workflow_report_idx ON public.report_workflow_events USING btree (report_id, created_at DESC);

CREATE OR REPLACE VIEW public.license_upgrade_authorizations WITH (security_invoker=true) AS  SELECT 'upgrade_code'::text AS record_type,
    c.id::text AS record_id,
    c.tenant_id,
    c.created_at AS recorded_at,
    to_jsonb(c.*) AS payload
   FROM saas_plan_upgrade_codes c
UNION ALL
 SELECT 'upgrade_attempt'::text AS record_type,
    a.id::text AS record_id,
    a.tenant_id,
    a.attempted_at AS recorded_at,
    to_jsonb(a.*) AS payload
   FROM saas_plan_upgrade_attempts a;

CREATE OR REPLACE VIEW public.report_card_summary WITH (security_invoker=true) AS  SELECT r.id,
    r.report_number,
    r.status,
    r.version,
    r.updated_at,
    r.published_at,
    e.student_id,
    e.class_id,
    r.term_id,
    s.admission_no,
    concat_ws(' '::text, s.first_name, NULLIF(s.middle_name, ''::text), s.last_name) AS student_name,
    c.name AS class_name,
    t.name AS term_name,
    y.name AS academic_year_name,
    round(COALESCE(avg(sr.total_score), 0::numeric), 2) AS average,
    round(COALESCE(sum(sr.grade_point), 0::numeric), 2) AS aggregate,
    count(sr.id) AS subject_count
   FROM student_reports r
     JOIN enrollments e ON e.id = r.enrollment_id
     JOIN students s ON s.id = e.student_id
     JOIN classes c ON c.id = e.class_id
     JOIN terms t ON t.id = r.term_id
     JOIN academic_years y ON y.id = t.academic_year_id
     LEFT JOIN subject_results sr ON sr.report_id = r.id
  WHERE r.deleted_at IS NULL
  GROUP BY r.id, e.id, s.id, c.id, t.id, y.id;
