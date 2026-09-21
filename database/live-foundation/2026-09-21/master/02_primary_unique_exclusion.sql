-- Edusentia master foundation: primary, unique and exclusion constraints
-- Read-only schema snapshot from the live Edusentia Supabase master.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_pkey PRIMARY KEY (term_id);

ALTER TABLE ONLY public.academic_years ADD CONSTRAINT academic_years_name_key UNIQUE (name);

ALTER TABLE ONLY public.academic_years ADD CONSTRAINT academic_years_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.assessment_components ADD CONSTRAINT assessment_components_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.assessment_components ADD CONSTRAINT assessment_components_scheme_id_code_key UNIQUE (scheme_id, code);

ALTER TABLE ONLY public.assessment_schemes ADD CONSTRAINT assessment_schemes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.assessment_score_entries ADD CONSTRAINT assessment_score_entries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.assessment_score_entries ADD CONSTRAINT assessment_score_entries_subject_result_id_component_id_key UNIQUE (subject_result_id, component_id);

ALTER TABLE ONLY public.audit_log ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.audit_log_archive_entries ADD CONSTRAINT audit_log_archive_entries_pkey PRIMARY KEY (archive_id, original_event_id);

ALTER TABLE ONLY public.audit_log_archives ADD CONSTRAINT audit_log_archives_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.backup_exports ADD CONSTRAINT backup_exports_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.backup_storage_objects ADD CONSTRAINT backup_storage_objects_backup_export_id_source_bucket_sourc_key UNIQUE (backup_export_id, source_bucket, source_path);

ALTER TABLE ONLY public.backup_storage_objects ADD CONSTRAINT backup_storage_objects_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.certificate_events ADD CONSTRAINT certificate_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_certificate_number_key UNIQUE (certificate_number);

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.class_attendance_registers ADD CONSTRAINT class_attendance_registers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.class_attendance_registers ADD CONSTRAINT class_attendance_registers_term_id_class_id_attendance_date_key UNIQUE (term_id, class_id, attendance_date);

ALTER TABLE ONLY public.class_subjects ADD CONSTRAINT class_subjects_class_id_subject_id_key UNIQUE (class_id, subject_id);

ALTER TABLE ONLY public.class_subjects ADD CONSTRAINT class_subjects_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.classes ADD CONSTRAINT classes_name_key UNIQUE (name);

ALTER TABLE ONLY public.classes ADD CONSTRAINT classes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.client_error_events ADD CONSTRAINT client_error_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_data_category_key UNIQUE (data_category);

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.emergency_academic_delegation_events ADD CONSTRAINT emergency_academic_delegation_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_academic_year_id_class_id_roll_number_key UNIQUE (academic_year_id, class_id, roll_number);

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_student_id_academic_year_id_key UNIQUE (student_id, academic_year_id);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_guardian_id_student_id_key UNIQUE (guardian_id, student_id);

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_card_kind_card_number_key UNIQUE (card_kind, card_number);

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.import_batches ADD CONSTRAINT import_batches_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.import_errors ADD CONSTRAINT import_errors_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_binding_sessions ADD CONSTRAINT license_binding_sessions_pkey PRIMARY KEY (license_id, actor_id);

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_events ADD CONSTRAINT license_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_feature_catalog ADD CONSTRAINT license_feature_catalog_pkey PRIMARY KEY (code);

ALTER TABLE ONLY public.license_plan_revisions ADD CONSTRAINT license_plan_revisions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_plan_revisions ADD CONSTRAINT license_plan_revisions_plan_id_revision_key UNIQUE (plan_id, revision);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_code_key UNIQUE (code);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_verification_logs ADD CONSTRAINT license_verification_logs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.notification_outbox ADD CONSTRAINT notification_outbox_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_access_locks ADD CONSTRAINT platform_access_locks_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_audit_archives ADD CONSTRAINT platform_audit_archives_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_distribution_authorities ADD CONSTRAINT platform_distribution_authorities_actor_id_key UNIQUE (actor_id);

ALTER TABLE ONLY public.platform_distribution_authorities ADD CONSTRAINT platform_distribution_authorities_distributor_code_key UNIQUE (distributor_code);

ALTER TABLE ONLY public.platform_distribution_authorities ADD CONSTRAINT platform_distribution_authorities_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_edge_payload_chunks ADD CONSTRAINT platform_edge_payload_chunks_pkey PRIMARY KEY (release_code, function_slug, chunk_index);

ALTER TABLE ONLY public.platform_health_display_state ADD CONSTRAINT platform_health_display_state_pkey PRIMARY KEY (singleton);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_storage_path_key UNIQUE (storage_path);

ALTER TABLE ONLY public.platform_package_events ADD CONSTRAINT platform_package_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_reconciliation ADD CONSTRAINT platform_package_reconciliation_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_signing_identity ADD CONSTRAINT platform_package_signing_identity_pkey PRIMARY KEY (singleton);

ALTER TABLE ONLY public.platform_package_templates ADD CONSTRAINT platform_package_templates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_templates ADD CONSTRAINT platform_package_templates_storage_path_key UNIQUE (storage_path);

ALTER TABLE ONLY public.platform_release_catalog ADD CONSTRAINT platform_release_catalog_pkey PRIMARY KEY (release_version);

ALTER TABLE ONLY public.platform_release_gate_runs ADD CONSTRAINT platform_release_gate_runs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.recovery_test_runs ADD CONSTRAINT recovery_test_runs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_pkey PRIMARY KEY (range_key);

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_storage_path_key UNIQUE (storage_path);

ALTER TABLE ONLY public.report_correction_events ADD CONSTRAINT report_correction_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.report_revisions ADD CONSTRAINT report_revisions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.report_revisions ADD CONSTRAINT report_revisions_report_id_version_key UNIQUE (report_id, version);

ALTER TABLE ONLY public.report_workflow_events ADD CONSTRAINT report_workflow_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_access_recovery_requests ADD CONSTRAINT saas_access_recovery_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_plan_upgrade_attempts ADD CONSTRAINT saas_plan_upgrade_attempts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_code_hash_key UNIQUE (code_hash);

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_pkey PRIMARY KEY (code);

ALTER TABLE ONLY public.saas_provisioning_jobs ADD CONSTRAINT saas_provisioning_jobs_idempotency_key_key UNIQUE (idempotency_key);

ALTER TABLE ONLY public.saas_provisioning_jobs ADD CONSTRAINT saas_provisioning_jobs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_school_deletion_jobs ADD CONSTRAINT saas_school_deletion_jobs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_student_capacity_events ADD CONSTRAINT saas_student_capacity_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_tenant_events ADD CONSTRAINT saas_tenant_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_tenant_health ADD CONSTRAINT saas_tenant_health_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_tenant_release_edge_functions ADD CONSTRAINT saas_tenant_release_edge_functio_release_code_function_slug_key UNIQUE (release_code, function_slug);

ALTER TABLE ONLY public.saas_tenant_release_edge_functions ADD CONSTRAINT saas_tenant_release_edge_functions_pkey PRIMARY KEY (release_code, ordinal);

ALTER TABLE ONLY public.saas_tenant_release_migrations ADD CONSTRAINT saas_tenant_release_migration_release_code_migration_versio_key UNIQUE (release_code, migration_version);

ALTER TABLE ONLY public.saas_tenant_release_migrations ADD CONSTRAINT saas_tenant_release_migrations_pkey PRIMARY KEY (release_code, ordinal);

ALTER TABLE ONLY public.saas_tenant_release_migrations ADD CONSTRAINT saas_tenant_release_migrations_release_code_migration_name_key UNIQUE (release_code, migration_name);

ALTER TABLE ONLY public.saas_tenant_releases ADD CONSTRAINT saas_tenant_releases_pkey PRIMARY KEY (release_code);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_registration_id_key UNIQUE (registration_id);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_slug_key UNIQUE (slug);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_tenant_code_key UNIQUE (tenant_code);

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_license_reference_key UNIQUE (license_reference);

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectus_revisions ADD CONSTRAINT school_prospectus_revisions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectus_revisions ADD CONSTRAINT school_prospectus_revisions_prospectus_id_revision_no_key UNIQUE (prospectus_id, revision_no);

ALTER TABLE ONLY public.school_prospectus_sections ADD CONSTRAINT school_prospectus_sections_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_academic_year_id_class_range_key UNIQUE (academic_year_id, class_range);

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_registrations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_pkey PRIMARY KEY (job_id, table_name);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.security_verification_runs ADD CONSTRAINT security_verification_runs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.staff_id_card_events ADD CONSTRAINT staff_id_card_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_card_number_key UNIQUE (card_number);

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.student_attendance_entries ADD CONSTRAINT student_attendance_entries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_attendance_entries ADD CONSTRAINT student_attendance_entries_register_id_enrollment_id_key UNIQUE (register_id, enrollment_id);

ALTER TABLE ONLY public.student_guardians ADD CONSTRAINT student_guardians_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_card_number_key UNIQUE (card_number);

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.student_lifecycle_events ADD CONSTRAINT student_lifecycle_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_report_number_key UNIQUE (report_number);

ALTER TABLE ONLY public.students ADD CONSTRAINT students_admission_no_key UNIQUE (admission_no);

ALTER TABLE ONLY public.students ADD CONSTRAINT students_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_report_id_subject_id_key UNIQUE (report_id, subject_id);

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_report_id_subject_id_key UNIQUE (report_id, subject_id);

ALTER TABLE ONLY public.subjects ADD CONSTRAINT subjects_code_key UNIQUE (code);

ALTER TABLE ONLY public.subjects ADD CONSTRAINT subjects_name_key UNIQUE (name);

ALTER TABLE ONLY public.subjects ADD CONSTRAINT subjects_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.system_maintenance_log ADD CONSTRAINT system_maintenance_log_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.teacher_award_categories ADD CONSTRAINT teacher_award_categories_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_academic_year_id_name_key UNIQUE (academic_year_id, name);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_academic_year_id_sequence_key UNIQUE (academic_year_id, sequence);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_user_id_class_id_subject_id_access_level_key UNIQUE (user_id, class_id, subject_id, access_level);
