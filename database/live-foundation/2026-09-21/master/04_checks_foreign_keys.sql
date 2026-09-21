-- Edusentia master foundation: checks and foreign keys
-- Read-only schema snapshot from the live Edusentia Supabase master.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

ALTER TABLE ONLY public.academic_years ADD CONSTRAINT academic_year_dates_chk CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date);

ALTER TABLE ONLY public.assessment_components ADD CONSTRAINT assessment_components_maximum_score_check CHECK (maximum_score > 0::numeric);

ALTER TABLE ONLY public.assessment_components ADD CONSTRAINT assessment_components_weight_check CHECK (weight > 0::numeric AND weight <= 100::numeric);

ALTER TABLE ONLY public.assessment_score_entries ADD CONSTRAINT assessment_score_entries_raw_score_check CHECK (raw_score >= 0::numeric);

ALTER TABLE ONLY public.assessment_score_entries ADD CONSTRAINT assessment_score_entries_weighted_score_check CHECK (weighted_score >= 0::numeric AND weighted_score <= 100::numeric);

ALTER TABLE ONLY public.audit_log_archives ADD CONSTRAINT audit_log_archives_archive_scope_check CHECK (archive_scope = ANY (ARRAY['selected'::text, 'full'::text]));

ALTER TABLE ONLY public.audit_log_archives ADD CONSTRAINT audit_log_archives_event_count_check CHECK (event_count >= 0);

ALTER TABLE ONLY public.backup_exports ADD CONSTRAINT backup_exports_status_check CHECK (status = ANY (ARRAY['processing'::text, 'completed'::text, 'failed'::text]));

ALTER TABLE ONLY public.backup_exports ADD CONSTRAINT backup_exports_type_chk CHECK (backup_type = ANY (ARRAY['database'::text, 'full'::text]));

ALTER TABLE ONLY public.backup_exports ADD CONSTRAINT backup_exports_verification_chk CHECK (verification_status = ANY (ARRAY['not_tested'::text, 'passed'::text, 'failed'::text]));

ALTER TABLE ONLY public.backup_storage_objects ADD CONSTRAINT backup_storage_objects_encrypted_size_check CHECK (encrypted_size >= 0);

ALTER TABLE ONLY public.backup_storage_objects ADD CONSTRAINT backup_storage_objects_original_size_check CHECK (original_size >= 0);

ALTER TABLE ONLY public.backup_storage_objects ADD CONSTRAINT backup_storage_objects_status_check CHECK (status = ANY (ARRAY['processing'::text, 'completed'::text, 'failed'::text]));

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_certificate_type_check CHECK (certificate_type = ANY (ARRAY['student_promotion'::text, 'jhs_completion'::text, 'teacher_recognition'::text]));

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_status_check CHECK (status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'rejected'::text, 'issued'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_certificate_type_check CHECK (certificate_type = ANY (ARRAY['student_promotion'::text, 'jhs_completion'::text, 'teacher_recognition'::text]));

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_file_mime_chk CHECK (mime_type = ''::text OR (mime_type = ANY (ARRAY['application/pdf'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text])));

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_file_path_chk CHECK (storage_path = ''::text OR storage_path ~~ (certificate_type || '/%'::text));

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_file_size_chk CHECK (storage_path = ''::text AND file_size = 0 OR storage_path <> ''::text AND file_size > 0 AND file_size <= 20971520);

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_version_chk CHECK (version > 0);

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificate_recipient_chk CHECK (recipient_kind = 'student'::text AND student_id IS NOT NULL AND teacher_id IS NULL OR recipient_kind = 'teacher'::text AND teacher_id IS NOT NULL AND student_id IS NULL);

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_recipient_kind_check CHECK (recipient_kind = ANY (ARRAY['student'::text, 'teacher'::text]));

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_revision_no_check CHECK (revision_no > 0);

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_status_check CHECK (status = ANY (ARRAY['draft'::text, 'approved'::text, 'issued'::text, 'rejected'::text, 'revoked'::text, 'superseded'::text]));

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_active_weekday_check CHECK (NOT active OR (day_of_week = ANY (ARRAY['Monday'::text, 'Tuesday'::text, 'Wednesday'::text, 'Thursday'::text, 'Friday'::text])));

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_check CHECK (period_end > period_start);

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_disposition_action_check CHECK (disposition_action = ANY (ARRAY['review'::text, 'archive'::text, 'anonymise'::text, 'delete'::text]));

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_retention_years_check CHECK (retention_years IS NULL OR retention_years >= 1 AND retention_years <= 100);

ALTER TABLE ONLY public.emergency_academic_delegation_events ADD CONSTRAINT emergency_academic_delegation_events_event_type_check CHECK (event_type = ANY (ARRAY['created'::text, 'principal_acknowledged'::text, 'revoked'::text, 'report_saved'::text, 'score_imported'::text]));

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_check CHECK (valid_until > valid_from);

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_check1 CHECK (valid_until <= (valid_from + '120 days'::interval));

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_check2 CHECK (allow_score_entry OR allow_class_report_fields);

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_check3 CHECK (subject_id IS NULL OR allow_class_report_fields = false);

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_check4 CHECK (status = 'active'::text AND revoked_at IS NULL OR status = 'revoked'::text AND revoked_at IS NOT NULL);

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_delegation_type_check CHECK (delegation_type = ANY (ARRAY['replacement_teacher'::text, 'system_admin_override'::text]));

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_reason_check CHECK (length(btrim(reason)) >= 10);

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_status_check CHECK (status = ANY (ARRAY['active'::text, 'revoked'::text]));

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_origin_chk CHECK (enrollment_origin = ANY (ARRAY['manual'::text, 'automatic_promotion'::text]));

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scale_range_chk CHECK (min_mark <= max_mark);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_interpretation_length CHECK (char_length(interpretation) <= 180);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_max_mark_check CHECK (max_mark >= 0::numeric AND max_mark <= 100::numeric);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_min_mark_check CHECK (min_mark >= 0::numeric AND min_mark <= 100::numeric);

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_employment_status_check CHECK (employment_status = ANY (ARRAY['active'::text, 'leave'::text, 'suspended'::text, 'resigned'::text, 'retired'::text]));

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_gender_check CHECK (gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text]));

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_card_kind_check CHECK (card_kind = ANY (ARRAY['student'::text, 'staff'::text]));

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_staff_validity_check CHECK (staff_validity_months >= 1 AND staff_validity_months <= 60);

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_template_code_check CHECK (template_code = ANY (ARRAY['classic'::text, 'modern'::text, 'minimal'::text]));

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_validity_months_check CHECK (validity_months >= 1 AND validity_months <= 60);

ALTER TABLE ONLY public.import_batches ADD CONSTRAINT import_batches_status_check CHECK (status = ANY (ARRAY['processing'::text, 'completed'::text, 'completed_with_errors'::text, 'failed'::text]));

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_max_guardians_check CHECK (max_guardians IS NULL OR max_guardians > 0);

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_max_storage_mb_check CHECK (max_storage_mb IS NULL OR max_storage_mb > 0);

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_max_students_check CHECK (max_students IS NULL OR max_students > 0);

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_max_system_admins_check CHECK (max_system_admins IS NULL OR max_system_admins > 0);

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_max_teachers_check CHECK (max_teachers IS NULL OR max_teachers > 0);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_billing_cycle_check CHECK (billing_cycle = ANY (ARRAY['monthly'::text, 'annual'::text, 'perpetual'::text, 'custom'::text]));

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_default_term_days_check CHECK (default_term_days > 0);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_grace_days_check CHECK (grace_days >= 0 AND grace_days <= 365);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_max_guardians_check CHECK (max_guardians IS NULL OR max_guardians > 0);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_max_storage_mb_check CHECK (max_storage_mb IS NULL OR max_storage_mb > 0);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_max_students_check CHECK (max_students IS NULL OR max_students > 0);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_max_system_admins_check CHECK (max_system_admins IS NULL OR max_system_admins > 0);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_max_teachers_check CHECK (max_teachers IS NULL OR max_teachers > 0);

ALTER TABLE ONLY public.notification_outbox ADD CONSTRAINT notification_outbox_channel_check CHECK (channel = ANY (ARRAY['email'::text, 'sms'::text, 'push'::text]));

ALTER TABLE ONLY public.platform_access_locks ADD CONSTRAINT platform_access_lock_dates_chk CHECK (ends_at IS NULL OR ends_at > starts_at);

ALTER TABLE ONLY public.platform_access_locks ADD CONSTRAINT platform_access_locks_lock_mode_check CHECK (lock_mode = ANY (ARRAY['read_only'::text, 'deny'::text]));

ALTER TABLE ONLY public.platform_access_locks ADD CONSTRAINT platform_access_locks_lock_scope_check CHECK (lock_scope = ANY (ARRAY['system_admin'::text, 'school'::text, 'platform'::text]));

ALTER TABLE ONLY public.platform_audit_archives ADD CONSTRAINT platform_audit_archives_archive_scope_check CHECK (archive_scope = ANY (ARRAY['licensing'::text, 'packages'::text]));

ALTER TABLE ONLY public.platform_edge_payload_chunks ADD CONSTRAINT platform_edge_payload_chunks_chunk_index_check CHECK (chunk_index >= 0 AND chunk_index < 100);

ALTER TABLE ONLY public.platform_edge_payload_chunks ADD CONSTRAINT platform_edge_payload_chunks_payload_base64_check CHECK (length(payload_base64) > 0);

ALTER TABLE ONLY public.platform_edge_payload_chunks ADD CONSTRAINT platform_edge_payload_chunks_payload_encoding_check CHECK (payload_encoding = 'gzip+base64'::text);

ALTER TABLE ONLY public.platform_edge_payload_chunks ADD CONSTRAINT platform_edge_payload_chunks_source_sha256_check CHECK (source_sha256 ~ '^[0-9a-f]{64}$'::text);

ALTER TABLE ONLY public.platform_health_display_state ADD CONSTRAINT platform_health_display_state_singleton_check CHECK (singleton);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_deletion_state_check CHECK (deletion_state = ANY (ARRAY['none'::text, 'pending'::text, 'storage_removed'::text, 'failed'::text, 'completed'::text]));

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_download_count_check CHECK (download_count >= 0);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_file_size_check CHECK (file_size > 0);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_lifecycle_action_chk CHECK (lifecycle_action = ANY (ARRAY['initial'::text, 'renewal'::text, 'upgrade'::text, 'renewal_upgrade'::text]));

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_renewal_sequence_chk CHECK (renewal_sequence >= 0);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_status_check CHECK (status = ANY (ARRAY['ready'::text, 'revoked'::text, 'deleted'::text]));

ALTER TABLE ONLY public.platform_package_reconciliation ADD CONSTRAINT platform_package_reconciliation_operation_check CHECK (operation = ANY (ARRAY['delete_storage'::text, 'verify_storage'::text]));

ALTER TABLE ONLY public.platform_package_reconciliation ADD CONSTRAINT platform_package_reconciliation_status_check CHECK (status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text]));

ALTER TABLE ONLY public.platform_package_signing_identity ADD CONSTRAINT platform_package_signing_identity_key_id_check CHECK (key_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$'::text);

ALTER TABLE ONLY public.platform_package_signing_identity ADD CONSTRAINT platform_package_signing_identity_public_fingerprint_check CHECK (public_fingerprint ~ '^[0-9a-f]{64}$'::text);

ALTER TABLE ONLY public.platform_package_signing_identity ADD CONSTRAINT platform_package_signing_identity_singleton_check CHECK (singleton);

ALTER TABLE ONLY public.platform_package_templates ADD CONSTRAINT platform_package_templates_file_size_check CHECK (file_size > 0);

ALTER TABLE ONLY public.platform_release_catalog ADD CONSTRAINT platform_release_catalog_status_check CHECK (status = ANY (ARRAY['candidate'::text, 'active'::text, 'retired'::text]));

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_request_details_check CHECK (length(btrim(request_details)) >= 10);

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_request_type_check CHECK (request_type = ANY (ARRAY['access'::text, 'correction'::text, 'export'::text, 'restriction'::text, 'anonymisation'::text, 'deletion'::text, 'consent_review'::text]));

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_status_check CHECK (status = ANY (ARRAY['open'::text, 'in_review'::text, 'approved'::text, 'rejected'::text, 'completed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.recovery_test_runs ADD CONSTRAINT recovery_test_runs_status_check CHECK (status = ANY (ARRAY['processing'::text, 'passed'::text, 'failed'::text]));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_mime_chk CHECK (mime_type = ANY (ARRAY['application/pdf'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text]));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_path_chk CHECK (storage_path ~~ (range_key || '/%'::text));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_range_chk CHECK (range_key = ANY (ARRAY['early_years'::text, 'basic_1_6'::text, 'basic_7_9'::text]));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_size_chk CHECK (file_size > 0 AND file_size <= 20971520);

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_version_chk CHECK (version > 0);

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_reason_check CHECK (length(btrim(reason)) >= 10);

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text, 'applied'::text]));

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_page_count_check CHECK (page_count > 0);

ALTER TABLE ONLY public.saas_access_recovery_requests ADD CONSTRAINT saas_access_recovery_requests_recovery_type_check CHECK (recovery_type = ANY (ARRAY['password'::text, 'mfa'::text, 'both'::text]));

ALTER TABLE ONLY public.saas_access_recovery_requests ADD CONSTRAINT saas_access_recovery_requests_status_check CHECK (status = ANY (ARRAY['pending'::text, 'completed'::text, 'denied'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.saas_plan_upgrade_attempts ADD CONSTRAINT saas_plan_upgrade_attempts_action_check CHECK (action = ANY (ARRAY['preview'::text, 'activate'::text]));

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_code_hash_check CHECK (code_hash ~ '^[a-f0-9]{64}$'::text);

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_code_hint_check CHECK (code_hint ~ '^[A-Z2-9]{4}$'::text);

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_status_check CHECK (status = ANY (ARRAY['issued'::text, 'redeemed_pending_activation'::text, 'activated'::text, 'revoked'::text, 'expired'::text]));

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_direction_chk CHECK (authorization_type = 'renewal'::text AND lower(from_plan_code::text) = lower(to_plan_code::text) OR (authorization_type = ANY (ARRAY['plan_upgrade'::text, 'plan_change'::text])) AND lower(from_plan_code::text) <> lower(to_plan_code::text));

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_expiry_chk CHECK (expires_at > issued_at);

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_upgrade_authorization_type_check CHECK (authorization_type = ANY (ARRAY['plan_upgrade'::text, 'renewal'::text, 'plan_change'::text]));

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_upgrade_license_dates_check CHECK (license_expires_at IS NULL OR license_starts_at IS NULL OR license_expires_at > license_starts_at);

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_upgrade_license_grace_days_check CHECK (license_grace_days IS NULL OR license_grace_days >= 0 AND license_grace_days <= 90);

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_upgrade_license_period_type_check CHECK (license_period_type = ANY (ARRAY['academic_term'::text, 'academic_year'::text]));

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_billing_cycle_check CHECK (billing_cycle = ANY (ARRAY['monthly'::text, 'annual'::text, 'custom'::text]));

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_max_guardians_check CHECK (max_guardians IS NULL OR max_guardians > 0);

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_max_storage_mb_check CHECK (max_storage_mb IS NULL OR max_storage_mb > 0);

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_max_students_check CHECK (max_students IS NULL OR max_students > 0);

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_max_system_admins_check CHECK (max_system_admins IS NULL OR max_system_admins > 0);

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_max_teachers_check CHECK (max_teachers IS NULL OR max_teachers > 0);

ALTER TABLE ONLY public.saas_plans ADD CONSTRAINT saas_plans_price_amount_check CHECK (price_amount IS NULL OR price_amount >= 0::numeric);

ALTER TABLE ONLY public.saas_provisioning_jobs ADD CONSTRAINT saas_provisioning_jobs_status_check CHECK (status = ANY (ARRAY['queued'::text, 'running'::text, 'waiting_project'::text, 'failed'::text, 'ready'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.saas_school_deletion_jobs ADD CONSTRAINT saas_school_deletion_jobs_status_check CHECK (status = ANY (ARRAY['queued'::text, 'running'::text, 'failed'::text, 'completed'::text]));

ALTER TABLE ONLY public.saas_student_capacity_events ADD CONSTRAINT saas_student_capacity_events_active_student_count_check CHECK (active_student_count >= 0);

ALTER TABLE ONLY public.saas_student_capacity_events ADD CONSTRAINT saas_student_capacity_events_event_type_check CHECK (event_type = ANY (ARRAY['usage_synced'::text, 'capacity_changed'::text]));

ALTER TABLE ONLY public.saas_student_capacity_events ADD CONSTRAINT saas_student_capacity_events_total_student_count_check CHECK (total_student_count >= 0);

ALTER TABLE ONLY public.saas_tenant_release_edge_functions ADD CONSTRAINT saas_tenant_release_edge_functions_bundle_bytes_check CHECK (bundle_bytes >= 0);

ALTER TABLE ONLY public.saas_tenant_release_edge_functions ADD CONSTRAINT saas_tenant_release_edge_functions_ordinal_check CHECK (ordinal > 0);

ALTER TABLE ONLY public.saas_tenant_release_edge_functions ADD CONSTRAINT saas_tenant_release_edge_functions_sha256_check CHECK (sha256 ~ '^[a-f0-9]{64}$'::text);

ALTER TABLE ONLY public.saas_tenant_release_migrations ADD CONSTRAINT saas_tenant_release_migrations_ordinal_check CHECK (ordinal > 0);

ALTER TABLE ONLY public.saas_tenant_release_migrations ADD CONSTRAINT saas_tenant_release_migrations_sha256_check CHECK (sha256 ~ '^[a-f0-9]{64}$'::text);

ALTER TABLE ONLY public.saas_tenant_releases ADD CONSTRAINT saas_tenant_releases_edge_function_count_check CHECK (edge_function_count >= 0);

ALTER TABLE ONLY public.saas_tenant_releases ADD CONSTRAINT saas_tenant_releases_migration_count_check CHECK (migration_count >= 0);

ALTER TABLE ONLY public.saas_tenant_releases ADD CONSTRAINT saas_tenant_releases_status_check CHECK (status = ANY (ARRAY['draft'::text, 'active'::text, 'retired'::text]));

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_institution_type_chk CHECK (institution_type = ANY (ARRAY['basic_jhs'::text, 'senior_high'::text, 'combined_pretertiary'::text, 'tertiary'::text]));

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_license_dates_check CHECK (license_expires_at IS NULL OR license_started_at IS NULL OR license_expires_at > license_started_at);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_license_grace_days_check CHECK (license_grace_days >= 0 AND license_grace_days <= 90);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_license_period_type_check CHECK (license_period_type = ANY (ARRAY['academic_term'::text, 'academic_year'::text]));

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_license_status_check CHECK (license_status = ANY (ARRAY['pending_activation'::text, 'active'::text, 'grace_period'::text, 'expired'::text, 'suspended'::text, 'revoked'::text]));

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_release_status_check CHECK (release_status = ANY (ARRAY['unknown'::text, 'current'::text, 'drifted'::text, 'schema_drift'::text, 'unhealthy'::text]));

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_status_check CHECK (status = ANY (ARRAY['provisioning'::text, 'active'::text, 'suspended'::text, 'denied'::text, 'deleting'::text, 'cancelled'::text, 'failed'::text]));

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_student_capacity_base_check CHECK (student_capacity_base IS NULL OR student_capacity_base > 0);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_student_capacity_limit_check CHECK (student_capacity_limit IS NULL OR student_capacity_limit > 0);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_student_capacity_status_check CHECK (student_capacity_status = ANY (ARRAY['unknown'::text, 'available'::text, 'near_limit'::text, 'at_limit'::text, 'over_limit'::text, 'unlimited'::text]));

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_student_counts_check CHECK (student_active_count >= 0 AND student_total_count >= 0 AND student_active_count <= student_total_count);

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_upgrade_token_hash_chk CHECK (upgrade_authority_token_hash = ''::text OR upgrade_authority_token_hash ~ '^[a-f0-9]{64}$'::text);

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_license_dates_chk CHECK ((activated_at IS NULL OR activated_at::date >= issued_on) AND (expires_at IS NULL OR activated_at IS NULL OR expires_at >= activated_at) AND (grace_ends_at IS NULL OR expires_at IS NULL OR grace_ends_at >= expires_at));

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_authority_status_check CHECK (authority_status = ANY (ARRAY['not_required'::text, 'pending'::text, 'active'::text, 'revoked'::text, 'unreachable'::text]));

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_signature_status_check CHECK (signature_status = ANY (ARRAY['not_required'::text, 'pending'::text, 'verified'::text, 'invalid'::text]));

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_status_check CHECK (status = ANY (ARRAY['pending_activation'::text, 'active'::text, 'grace_period'::text, 'expired'::text, 'suspended'::text, 'revoked'::text, 'perpetual'::text]));

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_amount_check CHECK (amount IS NULL OR amount >= 0::numeric);

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_calculation_units_check CHECK (calculation_units IS NULL OR calculation_units > 0::numeric);

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_charge_basis_check CHECK (charge_basis = ANY (ARRAY['free'::text, 'one_off'::text, 'per_day'::text, 'per_week'::text, 'per_month'::text, 'per_term'::text, 'per_academic_year'::text, 'per_occurrence'::text, 'optional'::text, 'parent_provides'::text, 'informational'::text]));

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_display_order_check CHECK (display_order >= 0 AND display_order <= 10000);

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_quantity_check CHECK (quantity IS NULL OR quantity > 0::numeric);

ALTER TABLE ONLY public.school_prospectus_revisions ADD CONSTRAINT school_prospectus_revisions_revision_no_check CHECK (revision_no > 0);

ALTER TABLE ONLY public.school_prospectus_sections ADD CONSTRAINT school_prospectus_sections_display_order_check CHECK (display_order >= 0 AND display_order <= 10000);

ALTER TABLE ONLY public.school_prospectus_sections ADD CONSTRAINT school_prospectus_sections_section_type_check CHECK (section_type = ANY (ARRAY['main_fees'::text, 'other_items'::text, 'parent_provided'::text, 'transportation'::text, 'policies'::text, 'custom'::text]));

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_class_range_check CHECK (class_range = ANY (ARRAY['early_years'::text, 'basic_1_6'::text, 'basic_7_9'::text]));

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_currency_code_check CHECK (currency_code ~ '^[A-Z]{3}$'::text);

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_revision_no_check CHECK (revision_no >= 0);

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_status_check CHECK (status = ANY (ARRAY['draft'::text, 'published'::text, 'archived'::text]));

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_reg_initial_license_dates_check CHECK (initial_license_expires_at IS NULL OR initial_license_starts_at IS NULL OR initial_license_expires_at > initial_license_starts_at);

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_reg_initial_license_grace_days_check CHECK (initial_license_grace_days IS NULL OR initial_license_grace_days >= 0 AND initial_license_grace_days <= 90);

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_reg_initial_license_period_type_check CHECK (initial_license_period_type IS NULL OR (initial_license_period_type = ANY (ARRAY['academic_term'::text, 'academic_year'::text])));

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_registrations_institution_type_chk CHECK (institution_type = ANY (ARRAY['basic_jhs'::text, 'senior_high'::text, 'combined_pretertiary'::text, 'tertiary'::text]));

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_registrations_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'denied'::text, 'provisioning'::text, 'active'::text, 'failed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_package_size_check CHECK (package_size >= 0);

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_status_check CHECK (status = ANY (ARRAY['upload_pending'::text, 'uploaded'::text, 'validating'::text, 'restoring'::text, 'completed'::text, 'failed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_row_count_check CHECK (row_count >= 0);

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_rows_check CHECK (jsonb_typeof(rows) = 'array'::text);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_backup_minimum_copies_chk CHECK (backup_minimum_copies >= 2 AND backup_minimum_copies <= 90);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_backup_retention_chk CHECK (backup_retention_days >= 7 AND backup_retention_days <= 365);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_promotion_cutoff_score_chk CHECK (promotion_cutoff_score >= 40 AND promotion_cutoff_score <= 60);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_report_body_font_chk CHECK (report_body_font = ANY (ARRAY['Times New Roman'::text, 'Arial'::text, 'Calibri'::text, 'Georgia'::text, 'Verdana'::text, 'Tahoma'::text]));

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_report_body_font_size_chk CHECK (report_body_font_size >= 8.0 AND report_body_font_size <= 16.0);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_user_email_domain_chk CHECK (user_email_domain ~ '^(?:[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.)+[a-z]{2,63}$'::text);

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_severity_check CHECK (severity = ANY (ARRAY['info'::text, 'warning'::text, 'high'::text, 'critical'::text]));

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_status_check CHECK (status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'false_positive'::text]));

ALTER TABLE ONLY public.security_verification_runs ADD CONSTRAINT security_verification_runs_status_check CHECK (status = ANY (ARRAY['planned'::text, 'in_progress'::text, 'passed'::text, 'passed_with_findings'::text, 'failed'::text]));

ALTER TABLE ONLY public.staff_id_card_events ADD CONSTRAINT staff_id_card_events_staff_type_check CHECK (staff_type = ANY (ARRAY['teacher'::text, 'principal'::text]));

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_check CHECK (staff_type = 'teacher'::text AND teacher_id IS NOT NULL AND headteacher_id IS NULL OR staff_type = 'principal'::text AND headteacher_id IS NOT NULL AND teacher_id IS NULL);

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_check1 CHECK (expires_on >= issue_date);

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_revision_no_check CHECK (revision_no > 0);

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_staff_type_check CHECK (staff_type = ANY (ARRAY['teacher'::text, 'principal'::text]));

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_status_check CHECK (status = ANY (ARRAY['active'::text, 'revoked'::text, 'replaced'::text]));

ALTER TABLE ONLY public.student_attendance_entries ADD CONSTRAINT student_attendance_entries_attendance_status_check CHECK (attendance_status = ANY (ARRAY['present'::text, 'absent'::text, 'late'::text, 'excused'::text]));

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_check CHECK (expires_on >= issue_date);

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_revision_no_check CHECK (revision_no > 0);

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_status_check CHECK (status = ANY (ARRAY['active'::text, 'revoked'::text, 'replaced'::text]));

ALTER TABLE ONLY public.student_lifecycle_events ADD CONSTRAINT student_lifecycle_events_event_type_check CHECK (event_type = ANY (ARRAY['transfer_in'::text, 'transfer_out'::text, 'withdrawn'::text, 'graduated'::text, 'inactive'::text, 'reactivated'::text, 'archived'::text]));

ALTER TABLE ONLY public.student_lifecycle_events ADD CONSTRAINT student_lifecycle_events_reason_check CHECK (length(btrim(reason)) >= 5);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT report_attendance_chk CHECK (days_present <= days_school_opened);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_days_present_check CHECK (days_present >= 0);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_days_school_opened_check CHECK (days_school_opened >= 0);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_version_check CHECK (version > 0);

ALTER TABLE ONLY public.students ADD CONSTRAINT students_gender_check CHECK (gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text]));

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_total_score_check CHECK (total_score >= 0::numeric AND total_score <= 100::numeric);

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_class_score_check CHECK (class_score >= 0::numeric);

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_exam_score_check CHECK (exam_score >= 0::numeric);

ALTER TABLE ONLY public.subjects ADD CONSTRAINT subject_legacy_score_bounds_chk CHECK (max_class_score > 0::numeric AND max_exam_score > 0::numeric AND (max_class_score + max_exam_score) <= 100::numeric);

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_employment_status_check CHECK (employment_status = ANY (ARRAY['active'::text, 'leave'::text, 'suspended'::text, 'resigned'::text, 'retired'::text]));

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_gender_check CHECK (gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text]));

ALTER TABLE ONLY public.terms ADD CONSTRAINT term_dates_chk CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date);

ALTER TABLE ONLY public.terms ADD CONSTRAINT term_reopening_after_end_chk CHECK (next_term_begins IS NULL OR end_date IS NULL OR next_term_begins > end_date);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_sequence_check CHECK (sequence >= 1 AND sequence <= 6);

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_status_check CHECK (status = ANY (ARRAY['valid'::text, 'superseded'::text, 'revoked'::text]));

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_access_level_check CHECK (access_level = ANY (ARRAY['view'::text, 'edit'::text, 'score'::text, 'review'::text]));

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.assessment_components ADD CONSTRAINT assessment_components_scheme_id_fkey FOREIGN KEY (scheme_id) REFERENCES assessment_schemes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.assessment_schemes ADD CONSTRAINT assessment_schemes_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.assessment_schemes ADD CONSTRAINT assessment_schemes_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.assessment_schemes ADD CONSTRAINT assessment_schemes_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.assessment_schemes ADD CONSTRAINT assessment_schemes_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.assessment_schemes ADD CONSTRAINT assessment_schemes_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.assessment_score_entries ADD CONSTRAINT assessment_score_entries_component_id_fkey FOREIGN KEY (component_id) REFERENCES assessment_components(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.assessment_score_entries ADD CONSTRAINT assessment_score_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.assessment_score_entries ADD CONSTRAINT assessment_score_entries_subject_result_id_fkey FOREIGN KEY (subject_result_id) REFERENCES subject_results(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.audit_log_archive_entries ADD CONSTRAINT audit_log_archive_entries_archive_id_fkey FOREIGN KEY (archive_id) REFERENCES audit_log_archives(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.audit_log_archives ADD CONSTRAINT audit_log_archives_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.audit_log ADD CONSTRAINT audit_log_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.backup_exports ADD CONSTRAINT backup_exports_initiated_by_fkey FOREIGN KEY (initiated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.backup_storage_objects ADD CONSTRAINT backup_storage_objects_backup_export_id_fkey FOREIGN KEY (backup_export_id) REFERENCES backup_exports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_prepared_by_fkey FOREIGN KEY (prepared_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_teacher_award_category_id_fkey FOREIGN KEY (teacher_award_category_id) REFERENCES teacher_award_categories(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_template_id_fkey FOREIGN KEY (template_id) REFERENCES certificate_templates(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificate_batches ADD CONSTRAINT certificate_batches_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificate_events ADD CONSTRAINT certificate_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificate_events ADD CONSTRAINT certificate_events_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES certificate_batches(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificate_events ADD CONSTRAINT certificate_events_certificate_id_fkey FOREIGN KEY (certificate_id) REFERENCES certificates(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificate_templates ADD CONSTRAINT certificate_templates_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES certificate_batches(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_source_report_id_fkey FOREIGN KEY (source_report_id) REFERENCES student_reports(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_supersedes_certificate_id_fkey FOREIGN KEY (supersedes_certificate_id) REFERENCES certificates(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.certificates ADD CONSTRAINT certificates_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.class_attendance_registers ADD CONSTRAINT class_attendance_registers_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.class_attendance_registers ADD CONSTRAINT class_attendance_registers_marked_by_fkey FOREIGN KEY (marked_by) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.class_attendance_registers ADD CONSTRAINT class_attendance_registers_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.class_subjects ADD CONSTRAINT class_subjects_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.class_subjects ADD CONSTRAINT class_subjects_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.class_subjects ADD CONSTRAINT class_subjects_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.class_timetable_entries ADD CONSTRAINT class_timetable_entries_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.classes ADD CONSTRAINT classes_class_teacher_id_fkey FOREIGN KEY (class_teacher_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.classes ADD CONSTRAINT classes_class_teacher_record_id_fkey FOREIGN KEY (class_teacher_record_id) REFERENCES teachers(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.client_error_events ADD CONSTRAINT client_error_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.emergency_academic_delegation_events ADD CONSTRAINT emergency_academic_delegation_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.emergency_academic_delegation_events ADD CONSTRAINT emergency_academic_delegation_events_delegation_id_fkey FOREIGN KEY (delegation_id) REFERENCES emergency_academic_delegations(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.emergency_academic_delegation_events ADD CONSTRAINT emergency_academic_delegation_events_report_id_fkey FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.emergency_academic_delegation_events ADD CONSTRAINT emergency_academic_delegation_events_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_delegate_user_id_fkey FOREIGN KEY (delegate_user_id) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_original_teacher_id_fkey FOREIGN KEY (original_teacher_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_principal_acknowledged_by_fkey FOREIGN KEY (principal_acknowledged_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_promotion_source_report_fk FOREIGN KEY (promotion_source_report_id) REFERENCES student_reports(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES student_guardians(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_card_id_fkey FOREIGN KEY (card_id) REFERENCES student_id_cards(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.import_batches ADD CONSTRAINT import_batches_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.import_errors ADD CONSTRAINT import_errors_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES import_batches(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.license_binding_sessions ADD CONSTRAINT license_binding_sessions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.license_binding_sessions ADD CONSTRAINT license_binding_sessions_license_id_fkey FOREIGN KEY (license_id) REFERENCES school_licenses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_license_id_fkey FOREIGN KEY (license_id) REFERENCES school_licenses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.license_events ADD CONSTRAINT license_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.license_events ADD CONSTRAINT license_events_license_id_fkey FOREIGN KEY (license_id) REFERENCES school_licenses(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.license_plan_revisions ADD CONSTRAINT license_plan_revisions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.license_plan_revisions ADD CONSTRAINT license_plan_revisions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES license_plans(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.license_verification_logs ADD CONSTRAINT license_verification_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.license_verification_logs ADD CONSTRAINT license_verification_logs_license_id_fkey FOREIGN KEY (license_id) REFERENCES school_licenses(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.notification_outbox ADD CONSTRAINT notification_outbox_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.platform_access_locks ADD CONSTRAINT platform_access_locks_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_access_locks ADD CONSTRAINT platform_access_locks_released_by_fkey FOREIGN KEY (released_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_audit_archives ADD CONSTRAINT platform_audit_archives_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_distribution_authorities ADD CONSTRAINT platform_distribution_authorities_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_generated_by_fkey FOREIGN KEY (generated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_superseded_by_fk FOREIGN KEY (superseded_by_artifact_id) REFERENCES platform_package_artifacts(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_supersedes_fk FOREIGN KEY (supersedes_artifact_id) REFERENCES platform_package_artifacts(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_events ADD CONSTRAINT platform_package_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_events ADD CONSTRAINT platform_package_events_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES platform_package_artifacts(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_events ADD CONSTRAINT platform_package_events_template_id_fkey FOREIGN KEY (template_id) REFERENCES platform_package_templates(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_reconciliation ADD CONSTRAINT platform_package_reconciliation_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES platform_package_artifacts(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_reconciliation ADD CONSTRAINT platform_package_reconciliation_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.platform_package_templates ADD CONSTRAINT platform_package_templates_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.recovery_test_runs ADD CONSTRAINT recovery_test_runs_backup_export_id_fkey FOREIGN KEY (backup_export_id) REFERENCES backup_exports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.recovery_test_runs ADD CONSTRAINT recovery_test_runs_initiated_by_fkey FOREIGN KEY (initiated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_correction_events ADD CONSTRAINT report_correction_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_correction_events ADD CONSTRAINT report_correction_events_request_id_fkey FOREIGN KEY (request_id) REFERENCES report_correction_requests(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_correction_revision_id_fkey FOREIGN KEY (correction_revision_id) REFERENCES report_revisions(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_original_publication_id_fkey FOREIGN KEY (original_publication_id) REFERENCES report_publications(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_original_revision_id_fkey FOREIGN KEY (original_revision_id) REFERENCES report_revisions(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_report_id_fkey FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_published_by_fkey FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_report_id_fkey FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES report_revisions(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_revisions ADD CONSTRAINT report_revisions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_revisions ADD CONSTRAINT report_revisions_report_id_fkey FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.report_workflow_events ADD CONSTRAINT report_workflow_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.report_workflow_events ADD CONSTRAINT report_workflow_events_report_id_fkey FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_access_recovery_requests ADD CONSTRAINT saas_access_recovery_requests_registration_id_fkey FOREIGN KEY (registration_id) REFERENCES school_registrations(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_access_recovery_requests ADD CONSTRAINT saas_access_recovery_requests_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_plan_upgrade_attempts ADD CONSTRAINT saas_plan_upgrade_attempts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_from_plan_code_fkey FOREIGN KEY (from_plan_code) REFERENCES saas_plans(code) ON DELETE RESTRICT;

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_plan_upgrade_codes ADD CONSTRAINT saas_plan_upgrade_codes_to_plan_code_fkey FOREIGN KEY (to_plan_code) REFERENCES saas_plans(code) ON DELETE RESTRICT;

ALTER TABLE ONLY public.saas_provisioning_jobs ADD CONSTRAINT saas_provisioning_jobs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_school_deletion_jobs ADD CONSTRAINT saas_school_deletion_jobs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_student_capacity_events ADD CONSTRAINT saas_student_capacity_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_student_capacity_events ADD CONSTRAINT saas_student_capacity_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_tenant_events ADD CONSTRAINT saas_tenant_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_tenant_events ADD CONSTRAINT saas_tenant_events_registration_id_fkey FOREIGN KEY (registration_id) REFERENCES school_registrations(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_tenant_events ADD CONSTRAINT saas_tenant_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.saas_tenant_health ADD CONSTRAINT saas_tenant_health_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_tenant_release_edge_functions ADD CONSTRAINT saas_tenant_release_edge_functions_release_code_fkey FOREIGN KEY (release_code) REFERENCES saas_tenant_releases(release_code) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_tenant_release_migrations ADD CONSTRAINT saas_tenant_release_migrations_release_code_fkey FOREIGN KEY (release_code) REFERENCES saas_tenant_releases(release_code) ON DELETE CASCADE;

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_plan_code_fkey FOREIGN KEY (plan_code) REFERENCES saas_plans(code) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY public.saas_tenants ADD CONSTRAINT saas_tenants_registration_id_fkey FOREIGN KEY (registration_id) REFERENCES school_registrations(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES license_plans(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_section_id_fkey FOREIGN KEY (section_id) REFERENCES school_prospectus_sections(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectus_revisions ADD CONSTRAINT school_prospectus_revisions_prospectus_id_fkey FOREIGN KEY (prospectus_id) REFERENCES school_prospectuses(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.school_prospectus_revisions ADD CONSTRAINT school_prospectus_revisions_published_by_fkey FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectus_sections ADD CONSTRAINT school_prospectus_sections_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectus_sections ADD CONSTRAINT school_prospectus_sections_prospectus_id_fkey FOREIGN KEY (prospectus_id) REFERENCES school_prospectuses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.school_prospectus_sections ADD CONSTRAINT school_prospectus_sections_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_published_by_fkey FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_registrations_requested_plan_code_fkey FOREIGN KEY (requested_plan_code) REFERENCES saas_plans(code) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_registrations_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_registrations ADD CONSTRAINT school_registrations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES saas_tenants(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_initiated_by_fkey FOREIGN KEY (initiated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_pre_restore_backup_id_fkey FOREIGN KEY (pre_restore_backup_id) REFERENCES backup_exports(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_job_id_fkey FOREIGN KEY (job_id) REFERENCES school_restore_jobs(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_certificate_completion_class_id_fkey FOREIGN KEY (certificate_completion_class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.security_verification_runs ADD CONSTRAINT security_verification_runs_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.staff_id_card_events ADD CONSTRAINT staff_id_card_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.staff_id_card_events ADD CONSTRAINT staff_id_card_events_card_id_fkey FOREIGN KEY (card_id) REFERENCES staff_id_cards(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_headteacher_id_fkey FOREIGN KEY (headteacher_id) REFERENCES headteachers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_supersedes_card_id_fkey FOREIGN KEY (supersedes_card_id) REFERENCES staff_id_cards(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.staff_id_cards ADD CONSTRAINT staff_id_cards_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.student_attendance_entries ADD CONSTRAINT student_attendance_entries_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.student_attendance_entries ADD CONSTRAINT student_attendance_entries_register_id_fkey FOREIGN KEY (register_id) REFERENCES class_attendance_registers(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.student_id_cards ADD CONSTRAINT student_id_cards_supersedes_card_id_fkey FOREIGN KEY (supersedes_card_id) REFERENCES student_id_cards(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_lifecycle_events ADD CONSTRAINT student_lifecycle_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_lifecycle_events ADD CONSTRAINT student_lifecycle_events_from_class_id_fkey FOREIGN KEY (from_class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_lifecycle_events ADD CONSTRAINT student_lifecycle_events_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.student_lifecycle_events ADD CONSTRAINT student_lifecycle_events_to_class_id_fkey FOREIGN KEY (to_class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_promoted_to_class_id_fkey FOREIGN KEY (promoted_to_class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_published_by_fkey FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_report_id_fkey FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_scheme_id_fkey FOREIGN KEY (scheme_id) REFERENCES assessment_schemes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_report_id_fkey FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.system_maintenance_log ADD CONSTRAINT system_maintenance_log_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.teacher_award_categories ADD CONSTRAINT teacher_award_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
