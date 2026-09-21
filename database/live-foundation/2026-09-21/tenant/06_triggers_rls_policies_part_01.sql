-- Edusentia tenant foundation: triggers, RLS flags and policies
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

CREATE TRIGGER academic_period_controls_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON academic_period_controls FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER academic_period_controls_set_updated_at BEFORE UPDATE ON academic_period_controls FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER academic_year_auto_status AFTER INSERT OR UPDATE OF start_date, end_date, deleted_at ON academic_years FOR EACH STATEMENT EXECUTE FUNCTION academic_year_auto_status_trigger();

CREATE TRIGGER academic_year_calendar_integrity BEFORE INSERT OR UPDATE OF start_date, end_date, deleted_at ON academic_years FOR EACH ROW EXECUTE FUNCTION validate_academic_year_calendar_integrity();

CREATE TRIGGER academic_year_pending_promotion_sync AFTER INSERT OR UPDATE OF start_date, end_date, deleted_at ON academic_years FOR EACH STATEMENT EXECUTE FUNCTION sync_pending_promotions_when_year_changes();

CREATE TRIGGER academic_years_audit AFTER INSERT OR DELETE OR UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER academic_years_broadcast AFTER INSERT OR DELETE OR UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER academic_years_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER academic_years_set_updated_at BEFORE UPDATE ON academic_years FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER accounts_office_staff_audit AFTER INSERT OR DELETE OR UPDATE ON accounts_office_staff FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER accounts_office_staff_broadcast AFTER INSERT OR DELETE OR UPDATE ON accounts_office_staff FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER accounts_office_staff_hr_sync AFTER INSERT OR DELETE OR UPDATE ON accounts_office_staff FOR EACH ROW EXECUTE FUNCTION hr_sync_staff_from_source();

CREATE TRIGGER accounts_office_staff_set_updated_at BEFORE UPDATE ON accounts_office_staff FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER admissions_app_audit AFTER INSERT OR DELETE OR UPDATE ON admissions_applications FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER admissions_app_no_delete BEFORE DELETE ON admissions_applications FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER admissions_app_touch BEFORE UPDATE ON admissions_applications FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER admissions_doc_audit AFTER INSERT OR DELETE OR UPDATE ON admissions_documents FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER admissions_doc_no_delete BEFORE DELETE ON admissions_documents FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER admissions_doc_touch BEFORE UPDATE ON admissions_documents FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER admissions_offer_audit AFTER INSERT OR DELETE OR UPDATE ON admissions_offers FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER admissions_offer_no_delete BEFORE DELETE ON admissions_offers FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER admissions_offer_touch BEFORE UPDATE ON admissions_offers FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER alumni_engagement_audit AFTER INSERT OR DELETE OR UPDATE ON alumni_engagements FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER alumni_engagement_no_delete BEFORE DELETE ON alumni_engagements FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER alumni_engagement_touch BEFORE UPDATE ON alumni_engagements FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER alumni_record_audit AFTER INSERT OR DELETE OR UPDATE ON alumni_records FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER alumni_record_no_delete BEFORE DELETE ON alumni_records FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER alumni_record_touch BEFORE UPDATE ON alumni_records FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER alumni_verification_audit AFTER INSERT OR DELETE OR UPDATE ON alumni_verification_requests FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER alumni_verification_no_delete BEFORE DELETE ON alumni_verification_requests FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER alumni_verification_touch BEFORE UPDATE ON alumni_verification_requests FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

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

CREATE TRIGGER audit_log_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON audit_log FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER backup_exports_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON backup_exports FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER trg_audit_backup_export_lifecycle AFTER INSERT OR UPDATE ON backup_exports FOR EACH ROW EXECUTE FUNCTION audit_backup_export_lifecycle();

CREATE TRIGGER backup_storage_objects_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON backup_storage_objects FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_batches_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificate_batches FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificate_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_templates_audit AFTER INSERT OR DELETE OR UPDATE ON certificate_templates FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER certificate_templates_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificate_templates FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER certificate_templates_set_updated_at BEFORE UPDATE ON certificate_templates FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER certificates_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON certificates FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER attendance_register_updated_at BEFORE UPDATE ON class_attendance_registers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER class_attendance_registers_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON class_attendance_registers FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER class_subjects_audit AFTER INSERT OR DELETE OR UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER class_subjects_broadcast AFTER INSERT OR DELETE OR UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER class_subjects_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER class_subjects_set_updated_at BEFORE UPDATE ON class_subjects FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER sync_subject_teacher_responsibility AFTER INSERT OR DELETE OR UPDATE OF teacher_id, class_id, subject_id, active ON class_subjects FOR EACH ROW EXECUTE FUNCTION sync_subject_teacher_responsibility_trigger();

CREATE TRIGGER class_timetable_entries_audit AFTER INSERT OR DELETE OR UPDATE ON class_timetable_entries FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER class_timetable_entries_broadcast AFTER INSERT OR DELETE OR UPDATE ON class_timetable_entries FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER class_timetable_entry_integrity_guard BEFORE INSERT OR UPDATE ON class_timetable_entries FOR EACH ROW EXECUTE FUNCTION validate_class_timetable_entry();

CREATE TRIGGER classes_audit AFTER INSERT OR DELETE OR UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER classes_broadcast AFTER INSERT OR DELETE OR UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER classes_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER classes_set_updated_at BEFORE UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER sync_class_teacher_responsibility AFTER INSERT OR DELETE OR UPDATE OF class_teacher_id, active, deleted_at ON classes FOR EACH ROW EXECUTE FUNCTION sync_class_teacher_responsibility_trigger();

CREATE TRIGGER client_error_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON client_error_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER communication_campaign_audit AFTER INSERT OR DELETE OR UPDATE ON communication_campaigns FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER communication_campaign_no_delete BEFORE DELETE ON communication_campaigns FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER communication_campaign_touch BEFORE UPDATE ON communication_campaigns FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER communication_delivery_audit AFTER INSERT OR DELETE OR UPDATE ON communication_deliveries FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER communication_delivery_no_delete BEFORE DELETE ON communication_deliveries FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER communication_message_audit AFTER INSERT OR DELETE OR UPDATE ON communication_messages FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER communication_message_no_delete BEFORE DELETE ON communication_messages FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER communication_template_audit AFTER INSERT OR DELETE OR UPDATE ON communication_templates FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER communication_template_no_delete BEFORE DELETE ON communication_templates FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER communication_template_touch BEFORE UPDATE ON communication_templates FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER communication_participant_no_delete BEFORE DELETE ON communication_thread_participants FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER communication_thread_audit AFTER INSERT OR DELETE OR UPDATE ON communication_threads FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER communication_thread_no_delete BEFORE DELETE ON communication_threads FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER communication_thread_touch BEFORE UPDATE ON communication_threads FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER data_retention_policies_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON data_retention_policies FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER data_retention_policies_set_updated_at BEFORE UPDATE ON data_retention_policies FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER discipline_action_audit AFTER INSERT OR DELETE OR UPDATE ON discipline_actions FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER discipline_action_no_delete BEFORE DELETE ON discipline_actions FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER discipline_action_touch BEFORE UPDATE ON discipline_actions FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER discipline_ack_audit AFTER INSERT OR DELETE OR UPDATE ON discipline_guardian_acknowledgements FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER discipline_ack_no_delete BEFORE DELETE ON discipline_guardian_acknowledgements FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER discipline_incident_audit AFTER INSERT OR DELETE OR UPDATE ON discipline_incidents FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER discipline_incident_no_delete BEFORE DELETE ON discipline_incidents FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER discipline_incident_touch BEFORE UPDATE ON discipline_incidents FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER emergency_academic_delegation_events_immutable BEFORE DELETE OR UPDATE ON emergency_academic_delegation_events FOR EACH ROW EXECUTE FUNCTION prevent_license_history_mutation();

CREATE TRIGGER emergency_academic_delegation_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON emergency_academic_delegation_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER emergency_academic_delegations_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON emergency_academic_delegations FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER emergency_academic_delegations_set_updated_at BEFORE UPDATE ON emergency_academic_delegations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER enrollments_audit AFTER INSERT OR DELETE OR UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER enrollments_broadcast AFTER INSERT OR DELETE OR UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER enrollments_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER enrollments_set_updated_at BEFORE UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_enrollment_fee_account_sync AFTER INSERT OR UPDATE OF student_id, academic_year_id, class_id, active, deleted_at ON enrollments FOR EACH ROW EXECUTE FUNCTION finance_sync_enrollment_fee_accounts();

CREATE TRIGGER finance_fee_accounts_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_fee_accounts FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_fee_accounts_invoice_sync AFTER INSERT OR UPDATE OF schedule_id, term_fee_amount, student_id, academic_year_id, term_id, class_id ON finance_fee_accounts FOR EACH ROW EXECUTE FUNCTION finance_sync_invoice_from_account();

CREATE TRIGGER finance_fee_allocations_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_fee_allocations FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_fee_allocations_immutable BEFORE DELETE OR UPDATE ON finance_fee_allocations FOR EACH ROW EXECUTE FUNCTION finance_immutable_row();

CREATE TRIGGER finance_fee_invoices_audit AFTER INSERT OR DELETE OR UPDATE ON finance_fee_invoices FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_fee_invoices_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_fee_invoices FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_fee_invoices_protect BEFORE DELETE OR UPDATE ON finance_fee_invoices FOR EACH ROW EXECUTE FUNCTION finance_protect_invoice();

CREATE TRIGGER finance_fee_schedules_audit AFTER INSERT OR DELETE OR UPDATE ON finance_fee_schedules FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_fee_schedules_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_fee_schedules FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_fee_schedules_set_updated_at BEFORE UPDATE ON finance_fee_schedules FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_fee_transactions_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_fee_transactions FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_fee_transactions_immutable BEFORE DELETE OR UPDATE ON finance_fee_transactions FOR EACH ROW EXECUTE FUNCTION finance_immutable_row();

CREATE TRIGGER finance_hold_overrides_audit AFTER INSERT OR DELETE OR UPDATE ON finance_hold_overrides FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_hold_overrides_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_hold_overrides FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_hold_overrides_set_updated_at BEFORE UPDATE ON finance_hold_overrides FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_hold_policy_audit AFTER INSERT OR DELETE OR UPDATE ON finance_hold_policy FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_hold_policy_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_hold_policy FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_hold_policy_set_updated_at BEFORE UPDATE ON finance_hold_policy FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_payroll_item_lines_audit AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_item_lines FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_payroll_item_lines_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_item_lines FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_payroll_items_audit AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_items FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_payroll_items_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_items FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_payroll_items_protect_final BEFORE DELETE OR UPDATE ON finance_payroll_items FOR EACH ROW EXECUTE FUNCTION finance_protect_final_payroll();

CREATE TRIGGER finance_payroll_items_set_updated_at BEFORE UPDATE ON finance_payroll_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_payroll_profiles_audit AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_profiles FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_payroll_profiles_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_profiles FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_payroll_profiles_hr_link BEFORE INSERT OR UPDATE OF teacher_id ON finance_payroll_profiles FOR EACH ROW EXECUTE FUNCTION finance_sync_hr_staff_link();

CREATE TRIGGER finance_payroll_profiles_set_updated_at BEFORE UPDATE ON finance_payroll_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_payroll_rules_audit AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_rules FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_payroll_rules_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_rules FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_payroll_rules_set_updated_at BEFORE UPDATE ON finance_payroll_rules FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_payroll_runs_audit AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_runs FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_payroll_runs_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_payroll_runs FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_payroll_runs_set_updated_at BEFORE UPDATE ON finance_payroll_runs FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_salary_grades_audit AFTER INSERT OR DELETE OR UPDATE ON finance_salary_grades FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_salary_grades_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_salary_grades FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_salary_grades_set_updated_at BEFORE UPDATE ON finance_salary_grades FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER finance_teacher_loans_audit AFTER INSERT OR DELETE OR UPDATE ON finance_teacher_loans FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER finance_teacher_loans_broadcast AFTER INSERT OR DELETE OR UPDATE ON finance_teacher_loans FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER finance_teacher_loans_set_updated_at BEFORE UPDATE ON finance_teacher_loans FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER grading_scale_overlap_guard BEFORE INSERT OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION validate_grading_scale_overlap();

CREATE TRIGGER grading_scales_audit AFTER INSERT OR DELETE OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER grading_scales_broadcast AFTER INSERT OR DELETE OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER grading_scales_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER grading_scales_set_updated_at BEFORE UPDATE ON grading_scales FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER guardian_links_audit AFTER INSERT OR DELETE OR UPDATE ON guardian_links FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER guardian_links_broadcast AFTER INSERT OR DELETE OR UPDATE ON guardian_links FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER guardian_links_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON guardian_links FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER headteachers_audit AFTER INSERT OR DELETE OR UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER headteachers_broadcast AFTER INSERT OR DELETE OR UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER headteachers_hr_sync AFTER INSERT OR DELETE OR UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION hr_sync_staff_from_source();

CREATE TRIGGER headteachers_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER headteachers_set_updated_at BEFORE UPDATE ON headteachers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER headteachers_single_current_guard BEFORE INSERT OR UPDATE OF active, employment_status, deleted_at ON headteachers FOR EACH ROW EXECUTE FUNCTION enforce_single_current_principal();

CREATE TRIGGER health_immunization_audit AFTER INSERT OR DELETE OR UPDATE ON health_immunizations FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER health_immunization_no_delete BEFORE DELETE ON health_immunizations FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER health_immunization_touch BEFORE UPDATE ON health_immunizations FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER health_med_audit AFTER INSERT OR DELETE OR UPDATE ON health_medication_administrations FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER health_med_no_delete BEFORE DELETE ON health_medication_administrations FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER health_profile_audit AFTER INSERT OR DELETE OR UPDATE ON health_student_profiles FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER health_profile_no_delete BEFORE DELETE ON health_student_profiles FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER health_profile_touch BEFORE UPDATE ON health_student_profiles FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER health_visit_audit AFTER INSERT OR DELETE OR UPDATE ON health_visits FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER health_visit_no_delete BEFORE DELETE ON health_visits FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER health_visit_touch BEFORE UPDATE ON health_visits FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER hostel_alloc_audit AFTER INSERT OR DELETE OR UPDATE ON hostel_allocations FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hostel_alloc_no_delete BEFORE DELETE ON hostel_allocations FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER hostel_alloc_touch BEFORE UPDATE ON hostel_allocations FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER hostel_bed_audit AFTER INSERT OR DELETE OR UPDATE ON hostel_beds FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hostel_bed_no_delete BEFORE DELETE ON hostel_beds FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER hostel_bed_touch BEFORE UPDATE ON hostel_beds FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER hostel_house_audit AFTER INSERT OR DELETE OR UPDATE ON hostel_houses FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hostel_house_no_delete BEFORE DELETE ON hostel_houses FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER hostel_house_touch BEFORE UPDATE ON hostel_houses FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER hostel_incident_audit AFTER INSERT OR DELETE OR UPDATE ON hostel_incidents FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hostel_incident_no_delete BEFORE DELETE ON hostel_incidents FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER hostel_incident_touch BEFORE UPDATE ON hostel_incidents FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER hostel_movement_audit AFTER INSERT OR DELETE OR UPDATE ON hostel_movements FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hostel_movement_no_delete BEFORE DELETE ON hostel_movements FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER hostel_room_audit AFTER INSERT OR DELETE OR UPDATE ON hostel_rooms FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hostel_room_no_delete BEFORE DELETE ON hostel_rooms FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER hostel_room_touch BEFORE UPDATE ON hostel_rooms FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER hr_employment_events_audit AFTER INSERT OR DELETE OR UPDATE ON hr_employment_events FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hr_employment_events_no_delete BEFORE DELETE ON hr_employment_events FOR EACH ROW EXECUTE FUNCTION hr_block_delete();

CREATE TRIGGER hr_leave_requests_audit AFTER INSERT OR DELETE OR UPDATE ON hr_leave_requests FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hr_leave_requests_no_delete BEFORE DELETE ON hr_leave_requests FOR EACH ROW EXECUTE FUNCTION hr_block_delete();

CREATE TRIGGER hr_leave_requests_touch BEFORE UPDATE ON hr_leave_requests FOR EACH ROW EXECUTE FUNCTION hr_touch_updated_at();

CREATE TRIGGER hr_staff_documents_audit AFTER INSERT OR DELETE OR UPDATE ON hr_staff_documents FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hr_staff_documents_no_delete BEFORE DELETE ON hr_staff_documents FOR EACH ROW EXECUTE FUNCTION hr_block_delete();

CREATE TRIGGER hr_staff_documents_touch BEFORE UPDATE ON hr_staff_documents FOR EACH ROW EXECUTE FUNCTION hr_touch_updated_at();

CREATE TRIGGER hr_staff_members_audit AFTER INSERT OR DELETE OR UPDATE ON hr_staff_members FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hr_staff_members_lifecycle AFTER INSERT OR UPDATE ON hr_staff_members FOR EACH ROW EXECUTE FUNCTION hr_record_staff_lifecycle();

CREATE TRIGGER hr_staff_members_no_delete BEFORE DELETE ON hr_staff_members FOR EACH ROW EXECUTE FUNCTION hr_block_delete();

CREATE TRIGGER hr_staff_members_touch BEFORE UPDATE ON hr_staff_members FOR EACH ROW EXECUTE FUNCTION hr_touch_updated_at();

CREATE TRIGGER hr_staff_qualifications_audit AFTER INSERT OR DELETE OR UPDATE ON hr_staff_qualifications FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER hr_staff_qualifications_no_delete BEFORE DELETE ON hr_staff_qualifications FOR EACH ROW EXECUTE FUNCTION hr_block_delete();

CREATE TRIGGER hr_staff_qualifications_touch BEFORE UPDATE ON hr_staff_qualifications FOR EACH ROW EXECUTE FUNCTION hr_touch_updated_at();

CREATE TRIGGER id_card_events_broadcast AFTER INSERT OR DELETE OR UPDATE ON id_card_events FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER id_card_settings_audit AFTER INSERT OR DELETE OR UPDATE ON id_card_settings FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER id_card_settings_broadcast AFTER INSERT OR DELETE OR UPDATE ON id_card_settings FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER import_batches_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON import_batches FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER import_errors_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON import_errors FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER inventory_asset_assignments_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_asset_assignments FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_asset_assignments_no_delete BEFORE DELETE ON inventory_asset_assignments FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_asset_assignments_touch BEFORE UPDATE ON inventory_asset_assignments FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_asset_maintenance_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_asset_maintenance FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_asset_maintenance_no_delete BEFORE DELETE ON inventory_asset_maintenance FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_asset_maintenance_touch BEFORE UPDATE ON inventory_asset_maintenance FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_asset_writeoffs_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_asset_writeoffs FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_asset_writeoffs_no_delete BEFORE DELETE ON inventory_asset_writeoffs FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_asset_writeoffs_touch BEFORE UPDATE ON inventory_asset_writeoffs FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_assets_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_assets FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_assets_no_delete BEFORE DELETE ON inventory_assets FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_assets_touch BEFORE UPDATE ON inventory_assets FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_events_no_delete BEFORE DELETE ON inventory_events FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_goods_receipt_lines_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_goods_receipt_lines FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_goods_receipt_lines_no_delete BEFORE DELETE ON inventory_goods_receipt_lines FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_goods_receipts_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_goods_receipts FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_goods_receipts_no_delete BEFORE DELETE ON inventory_goods_receipts FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_item_requests_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_item_requests FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_item_requests_no_delete BEFORE DELETE ON inventory_item_requests FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_item_requests_touch BEFORE UPDATE ON inventory_item_requests FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_items_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_items FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_items_no_delete BEFORE DELETE ON inventory_items FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_items_touch BEFORE UPDATE ON inventory_items FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_locations_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_locations FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_locations_no_delete BEFORE DELETE ON inventory_locations FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_locations_touch BEFORE UPDATE ON inventory_locations FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_purchase_order_lines_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_purchase_order_lines FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_purchase_order_lines_no_delete BEFORE DELETE ON inventory_purchase_order_lines FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_purchase_order_lines_touch BEFORE UPDATE ON inventory_purchase_order_lines FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_purchase_orders_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_purchase_orders FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_purchase_orders_no_delete BEFORE DELETE ON inventory_purchase_orders FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_purchase_orders_touch BEFORE UPDATE ON inventory_purchase_orders FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_purchase_request_lines_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_purchase_request_lines FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_purchase_request_lines_no_delete BEFORE DELETE ON inventory_purchase_request_lines FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_purchase_requests_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_purchase_requests FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_purchase_requests_no_delete BEFORE DELETE ON inventory_purchase_requests FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_purchase_requests_touch BEFORE UPDATE ON inventory_purchase_requests FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_settings_touch BEFORE UPDATE ON inventory_settings FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_staff_access_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_staff_access FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_staff_access_no_delete BEFORE DELETE ON inventory_staff_access FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_staff_access_touch BEFORE UPDATE ON inventory_staff_access FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER inventory_stock_movements_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_stock_movements FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_stock_movements_no_delete BEFORE DELETE ON inventory_stock_movements FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_suppliers_audit AFTER INSERT OR DELETE OR UPDATE ON inventory_suppliers FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER inventory_suppliers_no_delete BEFORE DELETE ON inventory_suppliers FOR EACH ROW EXECUTE FUNCTION inventory_block_delete();

CREATE TRIGGER inventory_suppliers_touch BEFORE UPDATE ON inventory_suppliers FOR EACH ROW EXECUTE FUNCTION inventory_touch_updated_at();

CREATE TRIGGER library_books_audit AFTER INSERT OR DELETE OR UPDATE ON library_books FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER library_books_no_delete BEFORE DELETE ON library_books FOR EACH ROW EXECUTE FUNCTION library_block_delete();

CREATE TRIGGER library_books_touch BEFORE UPDATE ON library_books FOR EACH ROW EXECUTE FUNCTION library_touch_updated_at();

CREATE TRIGGER library_copies_audit AFTER INSERT OR DELETE OR UPDATE ON library_copies FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER library_copies_no_delete BEFORE DELETE ON library_copies FOR EACH ROW EXECUTE FUNCTION library_block_delete();

CREATE TRIGGER library_copies_touch BEFORE UPDATE ON library_copies FOR EACH ROW EXECUTE FUNCTION library_touch_updated_at();

CREATE TRIGGER library_copy_events AFTER INSERT OR UPDATE ON library_copies FOR EACH ROW EXECUTE FUNCTION library_record_copy_event();

CREATE TRIGGER library_inventory_events_audit AFTER INSERT OR DELETE OR UPDATE ON library_inventory_events FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER library_inventory_events_no_delete BEFORE DELETE ON library_inventory_events FOR EACH ROW EXECUTE FUNCTION library_block_delete();

CREATE TRIGGER library_loans_audit AFTER INSERT OR DELETE OR UPDATE ON library_loans FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER library_loans_no_delete BEFORE DELETE ON library_loans FOR EACH ROW EXECUTE FUNCTION library_block_delete();

CREATE TRIGGER library_loans_touch BEFORE UPDATE ON library_loans FOR EACH ROW EXECUTE FUNCTION library_touch_updated_at();

CREATE TRIGGER library_reservations_audit AFTER INSERT OR DELETE OR UPDATE ON library_reservations FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER library_reservations_no_delete BEFORE DELETE ON library_reservations FOR EACH ROW EXECUTE FUNCTION library_block_delete();

CREATE TRIGGER library_reservations_touch BEFORE UPDATE ON library_reservations FOR EACH ROW EXECUTE FUNCTION library_touch_updated_at();

CREATE TRIGGER library_settings_audit AFTER INSERT OR DELETE OR UPDATE ON library_settings FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER library_settings_no_delete BEFORE DELETE ON library_settings FOR EACH ROW EXECUTE FUNCTION library_block_delete();

CREATE TRIGGER library_settings_touch BEFORE UPDATE ON library_settings FOR EACH ROW EXECUTE FUNCTION library_touch_updated_at();

CREATE TRIGGER library_staff_access_audit AFTER INSERT OR DELETE OR UPDATE ON library_staff_access FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER library_staff_access_no_delete BEFORE DELETE ON library_staff_access FOR EACH ROW EXECUTE FUNCTION library_block_delete();

CREATE TRIGGER library_staff_access_touch BEFORE UPDATE ON library_staff_access FOR EACH ROW EXECUTE FUNCTION library_touch_updated_at();

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

CREATE TRIGGER profiles_preserve_historical_identity BEFORE DELETE ON profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_historical_identity();

CREATE TRIGGER profiles_protect_security_fields BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_security_fields();

CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER recovery_test_runs_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON recovery_test_runs FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_card_templates_audit AFTER INSERT OR DELETE OR UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER report_card_templates_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_card_templates_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_card_templates_set_updated_at BEFORE UPDATE ON report_card_templates FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER report_correction_events_immutable BEFORE DELETE OR UPDATE ON report_correction_events FOR EACH ROW EXECUTE FUNCTION prevent_license_history_mutation();

CREATE TRIGGER report_correction_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_correction_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_correction_requests_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_correction_requests FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_correction_requests_set_updated_at BEFORE UPDATE ON report_correction_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER report_publications_audit AFTER INSERT OR DELETE OR UPDATE ON report_publications FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER report_publications_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_publications FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_publications_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_publications FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER trg_supersede_transcripts_on_publication_change AFTER INSERT OR UPDATE OF revision_id, published_at, revoked_at ON report_publications FOR EACH ROW EXECUTE FUNCTION supersede_transcripts_on_publication_change();

CREATE TRIGGER report_revisions_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_revisions FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_revisions_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_revisions FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER report_workflow_events_broadcast AFTER INSERT OR DELETE OR UPDATE ON report_workflow_events FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER report_workflow_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON report_workflow_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

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

CREATE TRIGGER trg_audit_school_restore_lifecycle AFTER INSERT OR UPDATE ON school_restore_jobs FOR EACH ROW EXECUTE FUNCTION audit_school_restore_lifecycle();

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

CREATE TRIGGER student_attendance_entries_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON student_attendance_entries FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER student_guardians_audit AFTER INSERT OR DELETE OR UPDATE ON student_guardians FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER student_guardians_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON student_guardians FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER student_guardians_set_updated_at BEFORE UPDATE ON student_guardians FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER student_id_cards_audit AFTER INSERT OR DELETE OR UPDATE ON student_id_cards FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER student_id_cards_broadcast AFTER INSERT OR DELETE OR UPDATE ON student_id_cards FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER student_lifecycle_events_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON student_lifecycle_events FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

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

CREATE TRIGGER student_services_events_no_delete BEFORE DELETE ON student_services_events FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER student_services_staff_audit AFTER INSERT OR DELETE OR UPDATE ON student_services_staff_access FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER student_services_staff_no_delete BEFORE DELETE ON student_services_staff_access FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER student_services_staff_touch BEFORE UPDATE ON student_services_staff_access FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

CREATE TRIGGER admissions_student_lifecycle_sync AFTER UPDATE OF status, deleted_at ON students FOR EACH ROW EXECUTE FUNCTION admissions_sync_student_lifecycle();

CREATE TRIGGER students_audit AFTER INSERT OR DELETE OR UPDATE ON students FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER students_broadcast AFTER INSERT OR DELETE OR UPDATE ON students FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER students_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON students FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER students_sensitive_access_guard BEFORE INSERT OR DELETE OR UPDATE ON students FOR EACH ROW EXECUTE FUNCTION enforce_student_management_aal2_write();

CREATE TRIGGER students_set_updated_at BEFORE UPDATE ON students FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER protect_subject_results_mutation BEFORE INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION protect_report_mutation();

CREATE TRIGGER subject_result_auto_promotion_sync AFTER INSERT OR DELETE OR UPDATE OF total_score ON subject_results FOR EACH ROW EXECUTE FUNCTION sync_report_promotion_from_subject_result();

CREATE TRIGGER subject_results_audit AFTER INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER subject_results_broadcast AFTER INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER subject_results_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER subject_results_set_updated_at BEFORE UPDATE ON subject_results FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER subject_scores_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON subject_scores FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER subject_scores_set_updated_at BEFORE UPDATE ON subject_scores FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER subjects_audit AFTER INSERT OR DELETE OR UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER subjects_broadcast AFTER INSERT OR DELETE OR UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER subjects_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER subjects_set_updated_at BEFORE UPDATE ON subjects FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER system_maintenance_log_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON system_maintenance_log FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER teacher_award_categories_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON teacher_award_categories FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER sync_teacher_record_class_links_trigger AFTER INSERT OR DELETE OR UPDATE OF profile_id, active, deleted_at, employment_status ON teachers FOR EACH ROW EXECUTE FUNCTION sync_teacher_record_class_links();

CREATE TRIGGER teachers_audit AFTER INSERT OR DELETE OR UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER teachers_broadcast AFTER INSERT OR DELETE OR UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER teachers_hr_sync AFTER INSERT OR DELETE OR UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION hr_sync_staff_from_source();

CREATE TRIGGER teachers_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER teachers_set_updated_at BEFORE UPDATE ON teachers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER term_calendar_auto_status AFTER INSERT OR DELETE OR UPDATE OF academic_year_id, start_date, end_date, deleted_at ON terms FOR EACH STATEMENT EXECUTE FUNCTION term_calendar_status_trigger();

CREATE TRIGGER term_calendar_integrity BEFORE INSERT OR UPDATE OF academic_year_id, start_date, end_date, deleted_at ON terms FOR EACH ROW EXECUTE FUNCTION validate_term_calendar_integrity();

CREATE TRIGGER terms_audit AFTER INSERT OR DELETE OR UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER terms_broadcast AFTER INSERT OR DELETE OR UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION broadcast_application_change();

CREATE TRIGGER terms_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER terms_reopening_date_guard BEFORE INSERT OR UPDATE OF end_date, next_term_begins ON terms FOR EACH ROW EXECUTE FUNCTION validate_term_reopening_date();

CREATE TRIGGER terms_set_updated_at BEFORE UPDATE ON terms FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER transcript_issuances_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transcript_issuances FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER transport_drivers_audit AFTER INSERT OR DELETE OR UPDATE ON transport_drivers FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_drivers_no_delete BEFORE DELETE ON transport_drivers FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_drivers_touch BEFORE UPDATE ON transport_drivers FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_drivers_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_drivers FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_incidents_audit AFTER INSERT OR DELETE OR UPDATE ON transport_incidents FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_incidents_no_delete BEFORE DELETE ON transport_incidents FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_incidents_touch BEFORE UPDATE ON transport_incidents FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_incidents_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_incidents FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_maintenance_records_audit AFTER INSERT OR DELETE OR UPDATE ON transport_maintenance_records FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_maintenance_records_no_delete BEFORE DELETE ON transport_maintenance_records FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_maintenance_records_touch BEFORE UPDATE ON transport_maintenance_records FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_maintenance_records_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_maintenance_records FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_route_stops_audit AFTER INSERT OR DELETE OR UPDATE ON transport_route_stops FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_route_stops_no_delete BEFORE DELETE ON transport_route_stops FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_route_stops_touch BEFORE UPDATE ON transport_route_stops FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_route_stops_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_route_stops FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_routes_audit AFTER INSERT OR DELETE OR UPDATE ON transport_routes FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_routes_no_delete BEFORE DELETE ON transport_routes FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_routes_touch BEFORE UPDATE ON transport_routes FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_routes_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_routes FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_settings_audit AFTER INSERT OR DELETE OR UPDATE ON transport_settings FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_settings_no_delete BEFORE DELETE ON transport_settings FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_settings_touch BEFORE UPDATE ON transport_settings FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_settings_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_settings FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_staff_access_audit AFTER INSERT OR DELETE OR UPDATE ON transport_staff_access FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_staff_access_no_delete BEFORE DELETE ON transport_staff_access FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_staff_access_touch BEFORE UPDATE ON transport_staff_access FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_staff_access_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_staff_access FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_stops_audit AFTER INSERT OR DELETE OR UPDATE ON transport_stops FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_stops_no_delete BEFORE DELETE ON transport_stops FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_stops_touch BEFORE UPDATE ON transport_stops FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_stops_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_stops FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_student_assignments_audit AFTER INSERT OR DELETE OR UPDATE ON transport_student_assignments FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_student_assignments_no_delete BEFORE DELETE ON transport_student_assignments FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_student_assignments_touch BEFORE UPDATE ON transport_student_assignments FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_student_assignments_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_student_assignments FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_trip_students_audit AFTER INSERT OR DELETE OR UPDATE ON transport_trip_students FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_trip_students_no_delete BEFORE DELETE ON transport_trip_students FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_trip_students_touch BEFORE UPDATE ON transport_trip_students FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_trip_students_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_trip_students FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_trips_audit AFTER INSERT OR DELETE OR UPDATE ON transport_trips FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_trips_no_delete BEFORE DELETE ON transport_trips FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_trips_touch BEFORE UPDATE ON transport_trips FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_trips_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_trips FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER transport_vehicles_audit AFTER INSERT OR DELETE OR UPDATE ON transport_vehicles FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER transport_vehicles_no_delete BEFORE DELETE ON transport_vehicles FOR EACH ROW EXECUTE FUNCTION transport_block_delete();

CREATE TRIGGER transport_vehicles_touch BEFORE UPDATE ON transport_vehicles FOR EACH ROW EXECUTE FUNCTION transport_touch_updated_at();

CREATE TRIGGER transport_vehicles_write_guard BEFORE INSERT OR DELETE OR UPDATE ON transport_vehicles FOR EACH ROW EXECUTE FUNCTION transport_enforce_write();

CREATE TRIGGER user_class_access_audit AFTER INSERT OR DELETE OR UPDATE ON user_class_access FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER user_class_access_license_write_guard BEFORE INSERT OR DELETE OR UPDATE ON user_class_access FOR EACH ROW EXECUTE FUNCTION enforce_licensed_write();

CREATE TRIGGER welfare_note_audit AFTER INSERT OR DELETE OR UPDATE ON welfare_case_notes FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER welfare_note_no_delete BEFORE DELETE ON welfare_case_notes FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER welfare_case_audit AFTER INSERT OR DELETE OR UPDATE ON welfare_cases FOR EACH ROW EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER welfare_case_no_delete BEFORE DELETE ON welfare_cases FOR EACH ROW EXECUTE FUNCTION student_services_block_delete();

CREATE TRIGGER welfare_case_touch BEFORE UPDATE ON welfare_cases FOR EACH ROW EXECUTE FUNCTION student_services_touch_updated_at();

ALTER TABLE public.academic_departments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.academic_faculties ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.academic_levels ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.academic_period_controls ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.academic_programmes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.academic_years ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.accounts_office_staff ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.admissions_applications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.admissions_documents ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.admissions_offers ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alumni_engagements ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alumni_records ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alumni_verification_requests ENABLE ROW LEVEL SECURITY;

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

ALTER TABLE public.communication_campaigns ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.communication_deliveries ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.communication_messages ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.communication_templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.communication_thread_participants ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.communication_threads ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.data_retention_policies ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.discipline_actions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.discipline_guardian_acknowledgements ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.discipline_incidents ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.emergency_academic_delegation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_academic_delegation_events FORCE ROW LEVEL SECURITY;

ALTER TABLE public.emergency_academic_delegations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_academic_delegations FORCE ROW LEVEL SECURITY;

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_fee_accounts ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_fee_allocations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_fee_group_classes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_fee_groups ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_fee_invoices ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_fee_schedules ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_fee_transactions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_guardian_contact_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_hold_overrides ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_hold_policy ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_payroll_item_lines ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_payroll_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_payroll_profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_payroll_rules ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_payroll_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_salary_grades ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.finance_teacher_loans ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.grading_scales ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.guardian_links ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.headteachers ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.health_immunizations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.health_medication_administrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.health_student_profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.health_visits ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hostel_allocations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hostel_beds ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hostel_houses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hostel_incidents ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hostel_movements ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hostel_rooms ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hr_employment_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hr_leave_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hr_staff_documents ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hr_staff_members ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.hr_staff_qualifications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.id_card_deletion_tombstones ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.id_card_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.id_card_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.import_batches ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.import_errors ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_asset_assignments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_asset_maintenance ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_asset_writeoffs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_assets ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_goods_receipt_lines ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_goods_receipts ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_item_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_locations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_purchase_order_lines ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_purchase_orders ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_purchase_request_lines ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_purchase_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_staff_access ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_stock_movements ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.inventory_suppliers ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.library_books ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.library_copies ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.library_inventory_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.library_loans ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.library_reservations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.library_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.library_staff_access ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_binding_sessions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_entitlement_overrides ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_feature_catalog ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_plan_revisions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_plans ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.license_verification_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.mfa_recovery_codes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_access_locks ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_audit_archives ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_distribution_authorities ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_artifacts ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_reconciliation ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_signing_identity ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.platform_package_templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.privacy_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.recovery_test_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_card_templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_correction_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_correction_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_publications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_revisions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.report_workflow_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_licenses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectus_items ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectus_revisions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectus_sections ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_prospectuses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_restore_jobs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_restore_stage_tables ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.school_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.security_verification_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.shs_programme_subjects ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.staff_id_card_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.staff_id_cards ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_attendance_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_attendance_entries FORCE ROW LEVEL SECURITY;

ALTER TABLE public.student_guardians ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_id_cards ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_lifecycle_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_programme_enrollments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_reports ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_services_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_services_staff_access ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subject_results ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subject_scores ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.system_maintenance_log ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.system_release_state ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.teacher_award_categories ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.terms ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_course_offerings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_course_prerequisites ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_course_registrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_course_results ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_courses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_degree_classifications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_grading_scale ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_programme_courses ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.tertiary_programme_requirements ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transcript_issuances ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_drivers ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_incidents ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_maintenance_records ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_route_stops ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_routes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_settings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_staff_access ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_stops ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_student_assignments ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_trip_students ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_trips ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.transport_vehicles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.user_class_access ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.welfare_case_notes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.welfare_cases ENABLE ROW LEVEL SECURITY;

CREATE POLICY academic_departments_delete ON public.academic_departments AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY academic_departments_insert ON public.academic_departments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY academic_departments_read ON public.academic_departments AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY academic_departments_update ON public.academic_departments AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY academic_faculties_delete ON public.academic_faculties AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY academic_faculties_insert ON public.academic_faculties AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY academic_faculties_read ON public.academic_faculties AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY academic_faculties_update ON public.academic_faculties AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY academic_levels_delete ON public.academic_levels AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY academic_levels_insert ON public.academic_levels AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY academic_levels_read ON public.academic_levels AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY academic_levels_update ON public.academic_levels AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY license_feature_select_guard_v730 ON public.academic_period_controls AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY academic_programmes_delete ON public.academic_programmes AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY academic_programmes_insert ON public.academic_programmes AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY academic_programmes_read ON public.academic_programmes AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY academic_programmes_update ON public.academic_programmes AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY academic_years_license_read_restrict ON public.academic_years AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('core_records'::text))));

CREATE POLICY academic_years_manage ON public.academic_years AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY academic_years_select ON public.academic_years AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY assessment_components_license_read_restrict ON public.assessment_components AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('assessment'::text))));

CREATE POLICY assessment_components_manage ON public.assessment_components AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY assessment_components_select ON public.assessment_components AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY assessment_schemes_license_read_restrict ON public.assessment_schemes AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('assessment'::text))));

CREATE POLICY assessment_schemes_manage ON public.assessment_schemes AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY assessment_schemes_select ON public.assessment_schemes AS PERMISSIVE FOR SELECT TO authenticated USING (true);

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

CREATE POLICY backup_exports_sensitive_admin_read ON public.backup_exports AS PERMISSIVE FOR SELECT TO authenticated USING ((is_system_admin() AND (current_aal() = 'aal2'::text)));

CREATE POLICY platform_license_delete_guard ON public.backup_exports AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.backup_exports AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_update_guard ON public.backup_exports AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY backup_storage_objects_sensitive_admin_read ON public.backup_storage_objects AS PERMISSIVE FOR SELECT TO authenticated USING ((is_system_admin() AND (current_aal() = 'aal2'::text)));

CREATE POLICY platform_license_delete_guard ON public.backup_storage_objects AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.backup_storage_objects AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

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

CREATE POLICY class_subjects_license_read_restrict ON public.class_subjects AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('core_records'::text))));

CREATE POLICY class_subjects_manage ON public.class_subjects AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY class_subjects_select ON public.class_subjects AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY classes_license_read_restrict ON public.classes AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('core_records'::text))));

CREATE POLICY classes_manage ON public.classes AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY classes_select ON public.classes AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY license_feature_select_guard_v730 ON public.emergency_academic_delegation_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.emergency_academic_delegations AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('governance'::text)));

CREATE POLICY enrollments_select ON public.enrollments AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_student(student_id));

CREATE POLICY license_feature_select_guard_v730 ON public.enrollments AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_delete_guard ON public.enrollments AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.enrollments AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.enrollments AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.enrollments AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY grading_scales_license_read_restrict ON public.grading_scales AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('assessment'::text))));

CREATE POLICY grading_scales_manage ON public.grading_scales AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY grading_scales_select ON public.grading_scales AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY guardian_links_select ON public.guardian_links AS PERMISSIVE FOR SELECT TO authenticated USING (((auth_user_id = ( SELECT auth.uid() AS uid)) OR can_view_student(student_id) OR is_records_manager()));

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

CREATE POLICY profiles_select ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated USING (((id = ( SELECT auth.uid() AS uid)) OR has_role(ARRAY['system_admin'::text, 'headteacher'::text, 'academic_admin'::text])));

CREATE POLICY profiles_update_self ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated USING ((id = ( SELECT auth.uid() AS uid))) WITH CHECK ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY license_feature_select_guard_v730 ON public.report_card_templates AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('uploaded_templates'::text)));

CREATE POLICY platform_license_select_guard ON public.report_card_templates AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

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

CREATE POLICY publications_select ON public.report_publications AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report_pdf(report_id));

CREATE POLICY license_feature_select_guard_v730 ON public.report_revisions AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.report_revisions AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.report_revisions AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.report_revisions AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.report_revisions AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY revisions_select ON public.report_revisions AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report_internal(report_id));

CREATE POLICY license_feature_select_guard_v730 ON public.report_workflow_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('report_cards'::text)));

CREATE POLICY platform_license_delete_guard ON public.report_workflow_events AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.report_workflow_events AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.report_workflow_events AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.report_workflow_events AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY workflow_select ON public.report_workflow_events AS PERMISSIVE FOR SELECT TO authenticated USING (can_view_report_internal(report_id));

CREATE POLICY school_restore_jobs_sensitive_admin_read ON public.school_restore_jobs AS PERMISSIVE FOR SELECT TO authenticated USING ((is_system_admin() AND (current_aal() = 'aal2'::text)));

CREATE POLICY license_feature_select_guard_v730 ON public.school_settings AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('core_records'::text)));

CREATE POLICY platform_license_select_guard ON public.school_settings AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY school_settings_manage ON public.school_settings AS PERMISSIVE FOR ALL TO authenticated USING ((is_system_admin() AND license_write_allowed() AND (current_aal() = 'aal2'::text))) WITH CHECK ((is_system_admin() AND license_write_allowed() AND (current_aal() = 'aal2'::text)));

CREATE POLICY school_settings_select ON public.school_settings AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY school_settings_sensitive_admin_update ON public.school_settings AS PERMISSIVE FOR UPDATE TO authenticated USING ((is_system_admin() AND license_write_allowed() AND (current_aal() = 'aal2'::text))) WITH CHECK ((is_system_admin() AND license_write_allowed() AND (current_aal() = 'aal2'::text)));

CREATE POLICY shs_programme_subjects_delete ON public.shs_programme_subjects AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY shs_programme_subjects_insert ON public.shs_programme_subjects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY shs_programme_subjects_read ON public.shs_programme_subjects AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY shs_programme_subjects_update ON public.shs_programme_subjects AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY license_feature_select_guard_v730 ON public.student_attendance_entries AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('attendance'::text)));

CREATE POLICY platform_license_delete_guard ON public.student_attendance_entries AS RESTRICTIVE FOR DELETE TO authenticated USING (license_write_allowed());

CREATE POLICY platform_license_insert_guard ON public.student_attendance_entries AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (license_write_allowed());

CREATE POLICY platform_license_select_guard ON public.student_attendance_entries AS RESTRICTIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY platform_license_update_guard ON public.student_attendance_entries AS RESTRICTIVE FOR UPDATE TO authenticated USING (license_write_allowed()) WITH CHECK (license_write_allowed());

CREATE POLICY guardians_select ON public.student_guardians AS PERMISSIVE FOR SELECT TO authenticated USING ((is_records_manager() OR (EXISTS ( SELECT 1
   FROM guardian_links gl
  WHERE ((gl.guardian_id = student_guardians.id) AND ((gl.auth_user_id = auth.uid()) OR can_view_student(gl.student_id)))))));

CREATE POLICY license_feature_select_guard_v730 ON public.student_lifecycle_events AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('academic_history'::text)));

CREATE POLICY student_programme_enrollments_delete ON public.student_programme_enrollments AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY student_programme_enrollments_insert ON public.student_programme_enrollments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY student_programme_enrollments_read ON public.student_programme_enrollments AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM academic_programmes p
  WHERE ((p.id = student_programme_enrollments.programme_id) AND (((p.institution_scope = 'tertiary'::text) AND can_read_tertiary_student_record(student_programme_enrollments.student_id)) OR ((p.institution_scope = 'senior_high'::text) AND can_read_student_academic_record(student_programme_enrollments.student_id)))))));

CREATE POLICY student_programme_enrollments_update ON public.student_programme_enrollments AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

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

CREATE POLICY subjects_license_read_restrict ON public.subjects AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('core_records'::text))));

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

CREATE POLICY terms_license_read_restrict ON public.terms AS RESTRICTIVE FOR SELECT TO authenticated USING ((license_read_allowed() AND (is_platform_super_admin() OR license_feature_enabled('core_records'::text))));

CREATE POLICY terms_manage ON public.terms AS PERMISSIVE FOR ALL TO authenticated USING (is_academic_manager()) WITH CHECK (is_academic_manager());

CREATE POLICY terms_select ON public.terms AS PERMISSIVE FOR SELECT TO authenticated USING (true);

CREATE POLICY tertiary_course_offerings_delete ON public.tertiary_course_offerings AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_course_offerings_insert ON public.tertiary_course_offerings AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_course_offerings_read ON public.tertiary_course_offerings AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY tertiary_course_offerings_update ON public.tertiary_course_offerings AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_course_prerequisites_delete ON public.tertiary_course_prerequisites AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_course_prerequisites_insert ON public.tertiary_course_prerequisites AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_course_prerequisites_read ON public.tertiary_course_prerequisites AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY tertiary_course_prerequisites_update ON public.tertiary_course_prerequisites AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_course_registrations_delete ON public.tertiary_course_registrations AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_course_registrations_insert ON public.tertiary_course_registrations AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_course_registrations_read ON public.tertiary_course_registrations AS PERMISSIVE FOR SELECT TO authenticated USING (can_read_tertiary_student_record(student_id));

CREATE POLICY tertiary_course_registrations_update ON public.tertiary_course_registrations AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_course_results_delete ON public.tertiary_course_results AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_course_results_insert ON public.tertiary_course_results AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_course_results_read ON public.tertiary_course_results AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM tertiary_course_registrations cr
  WHERE ((cr.id = tertiary_course_results.course_registration_id) AND can_read_tertiary_student_record(cr.student_id)))));

CREATE POLICY tertiary_course_results_update ON public.tertiary_course_results AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_courses_delete ON public.tertiary_courses AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_courses_insert ON public.tertiary_courses AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_courses_read ON public.tertiary_courses AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY tertiary_courses_update ON public.tertiary_courses AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_degree_classifications_delete ON public.tertiary_degree_classifications AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_degree_classifications_insert ON public.tertiary_degree_classifications AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_degree_classifications_read ON public.tertiary_degree_classifications AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY tertiary_degree_classifications_update ON public.tertiary_degree_classifications AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_grading_scale_delete ON public.tertiary_grading_scale AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_grading_scale_insert ON public.tertiary_grading_scale AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_grading_scale_read ON public.tertiary_grading_scale AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY tertiary_grading_scale_update ON public.tertiary_grading_scale AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_programme_courses_delete ON public.tertiary_programme_courses AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_programme_courses_insert ON public.tertiary_programme_courses AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_programme_courses_read ON public.tertiary_programme_courses AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY tertiary_programme_courses_update ON public.tertiary_programme_courses AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_programme_requirements_delete ON public.tertiary_programme_requirements AS PERMISSIVE FOR DELETE TO authenticated USING (can_manage_academic_model());

CREATE POLICY tertiary_programme_requirements_insert ON public.tertiary_programme_requirements AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (can_manage_academic_model());

CREATE POLICY tertiary_programme_requirements_read ON public.tertiary_programme_requirements AS PERMISSIVE FOR SELECT TO authenticated USING (license_read_allowed());

CREATE POLICY tertiary_programme_requirements_update ON public.tertiary_programme_requirements AS PERMISSIVE FOR UPDATE TO authenticated USING (can_manage_academic_model()) WITH CHECK (can_manage_academic_model());

CREATE POLICY license_feature_select_guard_v730 ON public.transcript_issuances AS RESTRICTIVE FOR SELECT TO authenticated USING ((is_platform_super_admin() OR license_feature_enabled('academic_history'::text)));

CREATE POLICY user_class_access_manage ON public.user_class_access AS PERMISSIVE FOR ALL TO authenticated USING (is_system_admin()) WITH CHECK (is_system_admin());

CREATE POLICY user_class_access_select ON public.user_class_access AS PERMISSIVE FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_system_admin()));

