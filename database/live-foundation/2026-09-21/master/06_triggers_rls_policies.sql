-- Edusentia master foundation: triggers, RLS flags and policies
-- Read-only schema snapshot from the live Edusentia Supabase master.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

CREATE TRIGGER academic_period_controls_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON academic_period_controls FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER academic_period_controls_set_updated_at BEFORE UPDATE ON academic_period_controls FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER academic_year_auto_status AFTER INSERT OR UPDATE OF start_date, end_date, deleted_at ON academic_years FOR EACH STATEMENT EXECUTE FUNCTION academic_year_auto_status_trigger();

CREATE TRIGGER academic_year_pending_promotion_sync AFTER INSERT OR UPDATE OF start_date, end_date, deleted_at ON academic_years FOR EACH STATEMENT EXECUTE FUNCTION sync_pending_promotions_when_year_changes();

CREATE TRIGGER academic_years_audit AFTER INSERT OR DELETE OR UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER academic_years_broadcast AFTER INSERT OR DELETE OR UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER academic_years_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER academic_years_set_updated_at BEFORE UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON academic_years FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER assessment_components_audit AFTER INSERT OR DELETE OR UPDATE ON assessment_components FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER assessment_components_broadcast AFTER INSERT OR DELETE OR UPDATE ON assessment_components FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER assessment_components_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON assessment_components FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER assessment_components_set_updated_at BEFORE UPDATE ON assessment_components FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER assessment_components_weight_guard BEFORE INSERT OR DELETE OR UPDATE ON assessment_components FOR EACH ROW EXECUTE FUNCTION validate_assessment_scheme_weights();

CREATE TRIGGER assessment_schemes_audit AFTER INSERT OR DELETE OR UPDATE ON assessment_schemes FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER assessment_schemes_broadcast AFTER INSERT OR DELETE OR UPDATE ON assessment_schemes FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER assessment_schemes_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON assessment_schemes FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER assessment_schemes_set_updated_at BEFORE UPDATE ON assessment_schemes FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER assessment_score_entries_audit AFTER INSERT OR DELETE OR UPDATE ON assessment_score_entries FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER assessment_score_entries_broadcast AFTER INSERT OR DELETE OR UPDATE ON assessment_score_entries FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER assessment_score_entries_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON assessment_score_entries FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER assessment_score_entries_prepare BEFORE INSERT OR UPDATE ON assessment_score_entries FOR EACH ROW EXECUTE FUNCTION prepare_score_entry();

CREATE TRIGGER assessment_score_entries_refresh AFTER INSERT OR DELETE OR UPDATE ON assessment_score_entries FOR EACH ROW EXECUTE FUNCTION after_score_entry_change();

CREATE TRIGGER assessment_score_entries_set_updated_at BEFORE UPDATE ON assessment_score_entries FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON assessment_score_entries FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER audit_log_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON audit_log FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER backup_exports_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON backup_exports FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER backup_storage_objects_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON backup_storage_objects FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_batches_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificate_batches FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificate_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_templates_audit AFTER INSERT OR DELETE OR UPDATE ON certificate_templates FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER certificate_templates_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificate_templates FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_templates_set_updated_at BEFORE UPDATE ON certificate_templates FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER certificates_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificates FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER attendance_register_updated_at BEFORE UPDATE ON class_attendance_registers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER class_attendance_registers_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON class_attendance_registers FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON class_attendance_registers FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER class_subjects_audit AFTER INSERT OR DELETE OR UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER class_subjects_broadcast AFTER INSERT OR DELETE OR UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER class_subjects_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER class_subjects_set_updated_at BEFORE UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON class_subjects FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER sync_subject_teacher_responsibility AFTER INSERT OR DELETE OR UPDATE OF teacher_id, class_id, subject_id, active ON class_subjects FOR EACH ROW EXECUTE FUNCTION sync_subject_teacher_responsibility_trigger();

CREATE TRIGGER class_timetable_entries_audit AFTER INSERT OR DELETE OR UPDATE ON class_timetable_entries FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER class_timetable_entries_broadcast AFTER INSERT OR DELETE OR UPDATE ON class_timetable_entries FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON class_timetable_entries FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER classes_audit AFTER INSERT OR DELETE OR UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER classes_broadcast AFTER INSERT OR DELETE OR UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER classes_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER classes_set_updated_at BEFORE UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON classes FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER sync_class_teacher_responsibility AFTER INSERT OR DELETE OR UPDATE OF class_teacher_id, active, deleted_at ON classes FOR EACH ROW EXECUTE FUNCTION sync_class_teacher_responsibility_trigger();

CREATE TRIGGER client_error_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON client_error_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER data_retention_policies_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON data_retention_policies FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER data_retention_policies_set_updated_at BEFORE UPDATE ON data_retention_policies FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER emergency_academic_delegation_events_immutable BEFORE DELETE OR UPDATE ON emergency_academic_delegation_events FOR EACH ROW EXECUTE FUNCTION prevent_license_history_mutation();

CREATE TRIGGER emergency_academic_delegation_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON emergency_academic_delegation_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER emergency_academic_delegations_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON emergency_academic_delegations FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER emergency_academic_delegations_set_updated_at BEFORE UPDATE ON emergency_academic_delegations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON enrollments FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER enrollments_audit AFTER INSERT OR DELETE OR UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER enrollments_broadcast AFTER INSERT OR DELETE OR UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER enrollments_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER enrollments_set_updated_at BEFORE UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER grading_scale_overlap_guard BEFORE INSERT OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION validate_grading_scale_overlap();

CREATE TRIGGER grading_scales_audit AFTER INSERT OR DELETE OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER grading_scales_broadcast AFTER INSERT OR DELETE OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER grading_scales_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER grading_scales_set_updated_at BEFORE UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER guardian_links_audit AFTER INSERT OR DELETE OR UPDATE ON guardian_links FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER guardian_links_broadcast AFTER INSERT OR DELETE OR UPDATE ON guardian_links FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER guardian_links_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON guardian_links FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON headteachers FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER headteachers_audit AFTER INSERT OR DELETE OR UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER headteachers_broadcast AFTER INSERT OR DELETE OR UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER headteachers_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER headteachers_set_updated_at BEFORE UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER id_card_events_broadcast AFTER INSERT OR DELETE OR UPDATE ON id_card_events FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER id_card_settings_audit AFTER INSERT OR DELETE OR UPDATE ON id_card_settings FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER id_card_settings_broadcast AFTER INSERT OR DELETE OR UPDATE ON id_card_settings FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER import_batches_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON import_batches FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER import_errors_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON import_errors FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER license_overrides_sync_rpc_features_v730 AFTER INSERT OR DELETE OR UPDATE OF active, feature_overrides ON license_entitlement_overrides FOR EACH STATEMENT EXECUTE FUNCTION trigger_sync_license_feature_rpc_privileges();

CREATE TRIGGER license_events_immutable BEFORE DELETE OR UPDATE ON license_events FOR EACH ROW EXECUTE FUNCTION prevent_license_history_mutation();

CREATE TRIGGER license_plans_set_updated_at BEFORE UPDATE ON license_plans FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER license_plans_sync_rpc_features_v730 AFTER INSERT OR UPDATE OF feature_flags ON license_plans FOR EACH STATEMENT EXECUTE FUNCTION trigger_sync_license_feature_rpc_privileges();

CREATE TRIGGER license_verification_logs_immutable BEFORE DELETE OR UPDATE ON license_verification_logs FOR EACH ROW EXECUTE FUNCTION prevent_license_history_mutation();

CREATE TRIGGER notification_outbox_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON notification_outbox FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER notifications_broadcast AFTER INSERT OR DELETE OR UPDATE ON notifications FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER notifications_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON notifications FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER platform_access_locks_set_updated_at BEFORE UPDATE ON platform_access_locks FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER platform_package_events_immutable BEFORE DELETE OR UPDATE ON platform_package_events FOR EACH ROW EXECUTE FUNCTION prevent_license_history_mutation();

CREATE TRIGGER platform_package_templates_set_updated_at BEFORE UPDATE ON platform_package_templates FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER privacy_requests_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON privacy_requests FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER privacy_requests_set_updated_at BEFORE UPDATE ON privacy_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER profiles_audit AFTER INSERT OR DELETE OR UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER profiles_broadcast AFTER INSERT OR DELETE OR UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER profiles_license_admin_capacity_v730 BEFORE INSERT OR UPDATE OF role, active ON profiles FOR EACH ROW EXECUTE FUNCTION enforce_system_admin_capacity();

CREATE TRIGGER profiles_protect_security_fields BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_security_fields();

CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER recovery_test_runs_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON recovery_test_runs FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_card_templates_audit AFTER INSERT OR DELETE OR UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER report_card_templates_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_card_templates_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_card_templates_set_updated_at BEFORE UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON report_correction_events FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER report_correction_events_immutable BEFORE DELETE OR UPDATE ON report_correction_events FOR EACH ROW EXECUTE FUNCTION prevent_license_history_mutation();

CREATE TRIGGER report_correction_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_correction_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON report_correction_requests FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER report_correction_requests_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_correction_requests FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_correction_requests_set_updated_at BEFORE UPDATE ON report_correction_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON report_publications FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER report_publications_audit AFTER INSERT OR DELETE OR UPDATE ON report_publications FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER report_publications_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_publications FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_publications_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_publications FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON report_revisions FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER report_revisions_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_revisions FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_revisions_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_revisions FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON report_workflow_events FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER report_workflow_events_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_workflow_events FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_workflow_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_workflow_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER saas_touch_saas_plans BEFORE UPDATE ON saas_plans FOR EACH ROW EXECUTE FUNCTION saas_touch_updated_at();

CREATE TRIGGER saas_pin_provisioning_job_release_trg BEFORE INSERT ON saas_provisioning_jobs FOR EACH ROW EXECUTE FUNCTION saas_pin_provisioning_job_release();

CREATE TRIGGER saas_touch_saas_provisioning_jobs BEFORE UPDATE ON saas_provisioning_jobs FOR EACH ROW EXECUTE FUNCTION saas_touch_updated_at();

CREATE TRIGGER saas_touch_saas_school_deletion_jobs BEFORE UPDATE ON saas_school_deletion_jobs FOR EACH ROW EXECUTE FUNCTION saas_touch_updated_at();

CREATE TRIGGER saas_guard_tenant_release_edge_functions_trg BEFORE INSERT OR DELETE OR UPDATE ON saas_tenant_release_edge_functions FOR EACH ROW EXECUTE FUNCTION saas_guard_tenant_release_child();

CREATE TRIGGER saas_guard_tenant_release_migrations_trg BEFORE INSERT OR DELETE OR UPDATE ON saas_tenant_release_migrations FOR EACH ROW EXECUTE FUNCTION saas_guard_tenant_release_child();

CREATE TRIGGER saas_guard_tenant_release_definition_trg BEFORE DELETE OR UPDATE ON saas_tenant_releases FOR EACH ROW EXECUTE FUNCTION saas_guard_tenant_release_definition();

CREATE TRIGGER saas_prepare_tenant_provisioning_row_trg BEFORE INSERT ON saas_tenants FOR EACH ROW EXECUTE FUNCTION saas_prepare_tenant_provisioning_row();

CREATE TRIGGER saas_touch_saas_tenants BEFORE UPDATE ON saas_tenants FOR EACH ROW EXECUTE FUNCTION saas_touch_updated_at();

CREATE TRIGGER trg_queue_tenant_policy_reconcile AFTER INSERT OR UPDATE OF status, plan_code, license_status, license_expires_at, license_grace_days, license_grace_ends_at ON saas_tenants FOR EACH ROW EXECUTE FUNCTION queue_tenant_policy_reconcile();

CREATE TRIGGER trg_saas_apply_initial_license_period BEFORE INSERT OR UPDATE ON saas_tenants FOR EACH ROW EXECUTE FUNCTION saas_apply_initial_license_period();

CREATE TRIGGER school_licenses_set_updated_at BEFORE UPDATE ON school_licenses FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER school_licenses_sync_rpc_features_v730 AFTER INSERT OR UPDATE OF plan_id, entitlement_snapshot ON school_licenses FOR EACH STATEMENT EXECUTE FUNCTION trigger_sync_license_feature_rpc_privileges();

CREATE TRIGGER school_prospectus_items_audit AFTER INSERT OR DELETE OR UPDATE ON school_prospectus_items FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER school_prospectus_items_broadcast AFTER INSERT OR DELETE OR UPDATE ON school_prospectus_items FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER school_prospectus_revisions_audit AFTER INSERT OR DELETE OR UPDATE ON school_prospectus_revisions FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER school_prospectus_revisions_broadcast AFTER INSERT OR DELETE OR UPDATE ON school_prospectus_revisions FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER school_prospectus_sections_audit AFTER INSERT OR DELETE OR UPDATE ON school_prospectus_sections FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER school_prospectus_sections_broadcast AFTER INSERT OR DELETE OR UPDATE ON school_prospectus_sections FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER school_prospectuses_audit AFTER INSERT OR DELETE OR UPDATE ON school_prospectuses FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER school_prospectuses_broadcast AFTER INSERT OR DELETE OR UPDATE ON school_prospectuses FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER saas_touch_school_registrations BEFORE UPDATE ON school_registrations FOR EACH ROW EXECUTE FUNCTION saas_touch_updated_at();

CREATE TRIGGER school_registrations_starter_only BEFORE INSERT OR UPDATE OF requested_plan_code ON school_registrations FOR EACH ROW EXECUTE FUNCTION saas_enforce_starter_registration();

CREATE TRIGGER school_settings_audit AFTER INSERT OR DELETE OR UPDATE ON school_settings FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER school_settings_broadcast AFTER INSERT OR DELETE OR UPDATE ON school_settings FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER school_settings_custom_branding_v730 BEFORE UPDATE OF primary_colour, accent_colour, report_body_font, report_body_font_size ON school_settings FOR EACH ROW EXECUTE FUNCTION enforce_custom_branding_entitlement();

CREATE TRIGGER school_settings_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON school_settings FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER school_settings_set_updated_at BEFORE UPDATE ON school_settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER security_events_immutable_delete BEFORE DELETE ON security_events FOR EACH ROW EXECUTE FUNCTION protect_security_event_delete();

CREATE TRIGGER security_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON security_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER security_verification_runs_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON security_verification_runs FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER staff_id_card_events_broadcast AFTER INSERT OR DELETE OR UPDATE ON staff_id_card_events FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER staff_id_cards_audit AFTER INSERT OR DELETE OR UPDATE ON staff_id_cards FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER staff_id_cards_broadcast AFTER INSERT OR DELETE OR UPDATE ON staff_id_cards FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER attendance_entry_updated_at BEFORE UPDATE ON student_attendance_entries FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON student_attendance_entries FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER student_attendance_entries_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON student_attendance_entries FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON student_guardians FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER student_guardians_audit AFTER INSERT OR DELETE OR UPDATE ON student_guardians FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER student_guardians_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON student_guardians FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER student_guardians_set_updated_at BEFORE UPDATE ON student_guardians FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON student_id_cards FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER student_id_cards_audit AFTER INSERT OR DELETE OR UPDATE ON student_id_cards FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER student_id_cards_broadcast AFTER INSERT OR DELETE OR UPDATE ON student_id_cards FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON student_lifecycle_events FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER student_lifecycle_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON student_lifecycle_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON student_reports FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER freeze_student_report_grading_guide BEFORE UPDATE OF status ON student_reports FOR EACH ROW EXECUTE FUNCTION freeze_report_grading_guide();

CREATE TRIGGER protect_student_reports_mutation BEFORE INSERT OR DELETE OR UPDATE ON student_reports FOR EACH ROW EXECUTE FUNCTION protect_report_mutation();

CREATE TRIGGER student_report_attendance_totals BEFORE INSERT OR UPDATE OF enrollment_id, term_id, days_school_opened, days_present ON student_reports FOR EACH ROW EXECUTE FUNCTION apply_attendance_totals_to_report();

CREATE TRIGGER student_report_publish_auto_promotion AFTER INSERT OR UPDATE OF status, deleted_at ON student_reports FOR EACH ROW EXECUTE FUNCTION apply_promotion_when_report_published();

CREATE TRIGGER student_reports_audit AFTER INSERT OR DELETE OR UPDATE ON student_reports FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER student_reports_auto_comments BEFORE UPDATE OF status ON student_reports FOR EACH ROW EXECUTE FUNCTION apply_automatic_report_comments();

CREATE TRIGGER student_reports_broadcast AFTER INSERT OR DELETE OR UPDATE ON student_reports FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER student_reports_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON student_reports FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER student_reports_reopening_date_insert BEFORE INSERT ON student_reports FOR EACH ROW EXECUTE FUNCTION sync_report_next_term_reopening_date();

CREATE TRIGGER student_reports_reopening_date_transition BEFORE UPDATE OF status, term_id ON student_reports FOR EACH ROW EXECUTE FUNCTION sync_report_next_term_reopening_date();

CREATE TRIGGER student_reports_set_updated_at BEFORE UPDATE ON student_reports FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON students FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER students_audit AFTER INSERT OR DELETE OR UPDATE ON students FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER students_broadcast AFTER INSERT OR DELETE OR UPDATE ON students FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER students_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON students FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER students_set_updated_at BEFORE UPDATE ON students FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON subject_results FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER protect_subject_results_mutation BEFORE INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION protect_report_mutation();

CREATE TRIGGER subject_result_auto_promotion_sync AFTER INSERT OR DELETE OR UPDATE OF total_score ON subject_results FOR EACH ROW EXECUTE FUNCTION sync_report_promotion_from_subject_result();

CREATE TRIGGER subject_results_audit AFTER INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER subject_results_broadcast AFTER INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER subject_results_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER subject_results_set_updated_at BEFORE UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON subject_scores FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER subject_scores_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON subject_scores FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER subject_scores_set_updated_at BEFORE UPDATE ON subject_scores FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON subjects FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER subjects_audit AFTER INSERT OR DELETE OR UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER subjects_broadcast AFTER INSERT OR DELETE OR UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER subjects_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER subjects_set_updated_at BEFORE UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER system_maintenance_log_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON system_maintenance_log FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER teacher_award_categories_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON teacher_award_categories FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON teachers FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER sync_teacher_record_class_links_trigger AFTER INSERT OR DELETE OR UPDATE OF profile_id, active, deleted_at, employment_status ON teachers FOR EACH ROW EXECUTE FUNCTION sync_teacher_record_class_links();

CREATE TRIGGER teachers_audit AFTER INSERT OR DELETE OR UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER teachers_broadcast AFTER INSERT OR DELETE OR UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER teachers_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER teachers_set_updated_at BEFORE UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER terms_audit AFTER INSERT OR DELETE OR UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER terms_broadcast AFTER INSERT OR DELETE OR UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER terms_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER terms_reopening_date_guard BEFORE INSERT OR UPDATE OF end_date, next_term_begins ON terms FOR EACH ROW EXECUTE FUNCTION validate_term_reopening_date();

CREATE TRIGGER terms_set_updated_at BEFORE UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER transcript_issuances_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transcript_issuances FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER edusentia_master_isolation_guard BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON user_class_access FOR EACH STATEMENT EXECUTE FUNCTION master_reject_tenant_operational_write();

CREATE TRIGGER user_class_access_audit AFTER INSERT OR DELETE OR UPDATE ON user_class_access FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER user_class_access_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON user_class_access FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

ALTER TABLE public.academic_period_controls ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.academic_years ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.assessment_components ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.assessment_schemes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.assessment_score_entries ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.audit_log_archive_entries ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.audit_log_archives ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.backup_exports ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.backup_storage_objects ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.certificate_batches ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.certificate_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.certificate_templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.class_attendance_registers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_attendance_registers FORCE ROW LEVEL SECURITY;

ALTER TABLE public.class_subjects ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.class_timetable_entries ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.client_error_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.data_retention_policies ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.emergency_academic_delegation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_academic_delegation_events FORCE ROW LEVEL SECURITY;

ALTER TABLE public.emergency_academic_delegations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_academic_delegations FORCE ROW LEVEL SECURITY;

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.grading_scales ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.guardian_links ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.headteachers ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.id_card_deletion_tombstones ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.id_card_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.id_card_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.import_batches ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.import_errors ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_binding_sessions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_entitlement_overrides ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_feature_catalog ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_plan_revisions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_plans ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_verification_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_access_locks ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_audit_archives ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_distribution_authorities ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_edge_payload_chunks ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_health_display_state ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_artifacts ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_reconciliation ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_signing_identity ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_release_catalog ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_release_gate_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.privacy_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.recovery_test_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_card_templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_correction_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_correction_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_publications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_revisions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_workflow_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_access_recovery_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_plan_upgrade_attempts ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_plan_upgrade_codes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_plans ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_provisioning_jobs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_school_deletion_jobs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_student_capacity_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_tenant_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_tenant_health ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_tenant_release_edge_functions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_tenant_release_migrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_tenant_releases ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.saas_tenants ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_licenses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectus_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectus_revisions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectus_sections ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectuses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_registrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_restore_jobs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_restore_stage_tables ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.security_verification_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.staff_id_card_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.staff_id_cards ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_attendance_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_attendance_entries FORCE ROW LEVEL SECURITY;

ALTER TABLE public.student_guardians ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_id_cards ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_lifecycle_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_reports ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subject_results ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subject_scores ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.system_maintenance_log ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.teacher_award_categories ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.terms ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transcript_issuances ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_class_access ENABLE ROW LEVEL SECURITY;

CREATE POLICY license_feature_select_guard_v730 ON public.academic_period_controls AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY academic_years_manage ON public.academic_years AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY academic_years_select ON public.academic_years AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.academic_years AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.academic_years AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.academic_years AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.academic_years AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.academic_years AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY assessment_components_manage ON public.assessment_components AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY assessment_components_select ON public.assessment_components AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.assessment_components AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('assessment'::text)));

CREATE POLICY platform_license_delete_guard ON public.assessment_components AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.assessment_components AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.assessment_components AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.assessment_components AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY assessment_schemes_manage ON public.assessment_schemes AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY assessment_schemes_select ON public.assessment_schemes AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.assessment_schemes AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('assessment'::text)));

CREATE POLICY platform_license_delete_guard ON public.assessment_schemes AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.assessment_schemes AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.assessment_schemes AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.assessment_schemes AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY assessment_entries_select ON public.assessment_score_entries AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM subject_results sr
  WHERE ((sr.id = assessment_score_entries.subject_result_id) AND can_view_report(sr.report_id)))));

CREATE POLICY license_feature_select_guard_v730 ON public.assessment_score_entries AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('assessment'::text)));

CREATE POLICY platform_license_delete_guard ON public.assessment_score_entries AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.assessment_score_entries AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.assessment_score_entries AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.assessment_score_entries AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY audit_select ON public.audit_log AS PERMISSIVE FOR SELECT TO authenticated USING (is_system_admin());

CREATE POLICY license_feature_select_guard_v730 ON public.audit_log AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY platform_license_delete_guard ON public.audit_log AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.audit_log AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.audit_log AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.audit_log AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY backup_exports_admin ON public.backup_exports AS PERMISSIVE FOR SELECT TO authenticated USING (is_system_admin());

CREATE POLICY license_feature_select_guard_v730 ON public.backup_exports AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('manual_backup'::text)));

CREATE POLICY platform_license_delete_guard ON public.backup_exports AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.backup_exports AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.backup_exports AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.backup_exports AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY backup_storage_objects_admin ON public.backup_storage_objects AS PERMISSIVE FOR SELECT TO authenticated USING (is_system_admin());

CREATE POLICY license_feature_select_guard_v730 ON public.backup_storage_objects AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('manual_backup'::text)));

CREATE POLICY platform_license_delete_guard ON public.backup_storage_objects AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.backup_storage_objects AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.backup_storage_objects AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.backup_storage_objects AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY license_feature_select_guard_v730 ON public.certificate_batches AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('certificates'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.certificate_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('certificates'::text)));

CREATE POLICY certificate_templates_module_guard_v730 ON public.certificate_templates AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('certificates'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.certificate_templates AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('uploaded_templates'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.certificates AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('certificates'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.class_attendance_registers AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('attendance'::text)));

CREATE POLICY platform_license_delete_guard ON public.class_attendance_registers AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.class_attendance_registers AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.class_attendance_registers AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.class_attendance_registers AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY class_subjects_manage ON public.class_subjects AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY class_subjects_select ON public.class_subjects AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.class_subjects AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.class_subjects AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.class_subjects AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.class_subjects AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.class_subjects AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY classes_manage ON public.classes AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY classes_select ON public.classes AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.classes AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.classes AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.classes AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.classes AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.classes AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY client_errors_admin ON public.client_error_events AS PERMISSIVE FOR SELECT TO authenticated USING (has_role(ARRAY['system_admin'::text, 'headteacher'::text]));

CREATE POLICY license_feature_select_guard_v730 ON public.client_error_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY platform_license_delete_guard ON public.client_error_events AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.client_error_events AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.client_error_events AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.client_error_events AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY license_feature_select_guard_v730 ON public.data_retention_policies AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.emergency_academic_delegation_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.emergency_academic_delegations AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY enrollments_select ON public.enrollments AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_student(student_id));

CREATE POLICY license_feature_select_guard_v730 ON public.enrollments AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.enrollments AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.enrollments AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.enrollments AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.enrollments AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY grading_scales_manage ON public.grading_scales AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY grading_scales_select ON public.grading_scales AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.grading_scales AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('assessment'::text)));

CREATE POLICY platform_license_delete_guard ON public.grading_scales AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.grading_scales AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.grading_scales AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.grading_scales AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY guardian_links_select ON public.guardian_links AS PERMISSIVE FOR SELECT TO authenticated USING (((auth_user_id = ( SELECT auth.uid() AS uid)) OR can_view_student(student_id) OR is_records_manager()));

CREATE POLICY license_feature_select_guard_v730 ON public.guardian_links AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.guardian_links AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.guardian_links AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.guardian_links AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.guardian_links AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY headteachers_select ON public.headteachers AS PERMISSIVE FOR SELECT TO authenticated USING ((can_manage_headteachers() OR (profile_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY license_feature_select_guard_v730 ON public.headteachers AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.headteachers AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.headteachers AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.headteachers AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.headteachers AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY import_batches_select ON public.import_batches AS PERMISSIVE FOR SELECT TO authenticated USING (((created_by = ( SELECT auth.uid() AS uid)) OR is_records_manager()));

CREATE POLICY license_feature_select_guard_v730 ON public.import_batches AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('bulk_workflow'::text)));

CREATE POLICY platform_license_delete_guard ON public.import_batches AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.import_batches AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.import_batches AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.import_batches AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY import_errors_select ON public.import_errors AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM import_batches b
  WHERE ((b.id = import_errors.batch_id) AND ((b.created_by = ( SELECT auth.uid() AS uid)) OR is_records_manager())))));

CREATE POLICY license_feature_select_guard_v730 ON public.import_errors AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('bulk_workflow'::text)));

CREATE POLICY platform_license_delete_guard ON public.import_errors AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.import_errors AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.import_errors AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.import_errors AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY license_feature_select_guard_v730 ON public.notification_outbox AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('notifications'::text)));

CREATE POLICY outbox_admin ON public.notification_outbox AS PERMISSIVE FOR SELECT TO authenticated USING (is_system_admin());

CREATE POLICY platform_license_delete_guard ON public.notification_outbox AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.notification_outbox AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.notification_outbox AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.notification_outbox AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY license_feature_select_guard_v730 ON public.notifications AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('notifications'::text)));

CREATE POLICY notifications_delete_own ON public.notifications AS PERMISSIVE FOR DELETE TO authenticated USING ((recipient_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY notifications_select ON public.notifications AS PERMISSIVE FOR SELECT TO authenticated USING ((recipient_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY notifications_update ON public.notifications AS PERMISSIVE FOR UPDATE TO authenticated USING ((recipient_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((recipient_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY platform_license_delete_guard ON public.notifications AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.notifications AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.notifications AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.notifications AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY license_feature_select_guard_v730 ON public.privacy_requests AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.profiles AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.profiles AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.profiles AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.profiles AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.profiles AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY profiles_select ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated USING (((id = ( SELECT auth.uid() AS uid)) OR has_role(ARRAY['system_admin'::text, 'headteacher'::text, 'academic_admin'::text])));

CREATE POLICY profiles_update_self ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated USING ((id = ( SELECT auth.uid() AS uid))) WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY license_feature_select_guard_v730 ON public.recovery_test_runs AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('manual_backup'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.report_card_templates AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('uploaded_templates'::text)));

CREATE POLICY platform_license_delete_guard ON public.report_card_templates AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.report_card_templates AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.report_card_templates AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.report_card_templates AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY report_card_templates_admin ON public.report_card_templates AS PERMISSIVE FOR ALL TO authenticated USING (is_system_admin()) WITH CHECK (is_system_admin());

CREATE POLICY report_card_templates_module_guard_v730 ON public.report_card_templates AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY report_card_templates_read ON public.report_card_templates AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.report_correction_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.report_correction_requests AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.report_publications AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.report_publications AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.report_publications AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.report_publications AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.report_publications AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY publications_select ON public.report_publications AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report(report_id));

CREATE POLICY license_feature_select_guard_v730 ON public.report_revisions AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.report_revisions AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.report_revisions AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.report_revisions AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.report_revisions AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY revisions_select ON public.report_revisions AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report(report_id));

CREATE POLICY license_feature_select_guard_v730 ON public.report_workflow_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.report_workflow_events AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.report_workflow_events AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.report_workflow_events AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.report_workflow_events AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY workflow_select ON public.report_workflow_events AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report(report_id));

CREATE POLICY school_restore_jobs_admin_read ON public.school_restore_jobs AS PERMISSIVE FOR SELECT TO authenticated USING (((current_app_role())::text = 'system_admin'::text));

CREATE POLICY license_feature_select_guard_v730 ON public.school_settings AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.school_settings AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.school_settings AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.school_settings AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.school_settings AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY school_settings_manage ON public.school_settings AS PERMISSIVE FOR ALL TO authenticated USING (is_system_admin()) WITH CHECK (is_system_admin());

CREATE POLICY school_settings_select ON public.school_settings AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.security_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.security_verification_runs AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.student_attendance_entries AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('attendance'::text)));

CREATE POLICY platform_license_delete_guard ON public.student_attendance_entries AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.student_attendance_entries AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.student_attendance_entries AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.student_attendance_entries AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY guardians_select ON public.student_guardians AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM guardian_links gl
  WHERE ((gl.guardian_id = gl.id) AND can_view_student(gl.student_id)))));

CREATE POLICY license_feature_select_guard_v730 ON public.student_guardians AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.student_guardians AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.student_guardians AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.student_guardians AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.student_guardians AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY license_feature_select_guard_v730 ON public.student_lifecycle_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('academic_history'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.student_reports AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.student_reports AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.student_reports AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.student_reports AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.student_reports AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY student_reports_select ON public.student_reports AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report(id));

CREATE POLICY license_feature_select_guard_v730 ON public.students AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.students AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.students AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.students AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.students AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY students_select ON public.students AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_student(id));

CREATE POLICY license_feature_select_guard_v730 ON public.subject_results AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.subject_results AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.subject_results AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.subject_results AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.subject_results AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY subject_results_select ON public.subject_results AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report(report_id));

CREATE POLICY license_feature_select_guard_v730 ON public.subject_scores AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.subject_scores AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.subject_scores AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.subject_scores AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.subject_scores AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY subject_scores_select ON public.subject_scores AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report(report_id));

CREATE POLICY license_feature_select_guard_v730 ON public.subjects AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.subjects AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.subjects AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.subjects AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.subjects AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY subjects_manage ON public.subjects AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY subjects_select ON public.subjects AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.system_maintenance_log AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY platform_license_delete_guard ON public.system_maintenance_log AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.system_maintenance_log AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.system_maintenance_log AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.system_maintenance_log AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY license_feature_select_guard_v730 ON public.teacher_award_categories AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('certificates'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.teachers AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.teachers AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.teachers AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.teachers AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.teachers AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY teachers_select ON public.teachers AS PERMISSIVE FOR SELECT TO authenticated USING ((can_manage_teachers() OR (profile_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY license_feature_select_guard_v730 ON public.terms AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.terms AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.terms AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.terms AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.terms AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY terms_manage ON public.terms AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY terms_select ON public.terms AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.transcript_issuances AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('academic_history'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.user_class_access AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.user_class_access AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.user_class_access AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.user_class_access AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.user_class_access AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY user_class_access_manage ON public.user_class_access AS PERMISSIVE FOR ALL TO authenticated USING (is_system_admin()) WITH CHECK (is_system_admin());

CREATE POLICY user_class_access_select ON public.user_class_access AS PERMISSIVE FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_system_admin()));
