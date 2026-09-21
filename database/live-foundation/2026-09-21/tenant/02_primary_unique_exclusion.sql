-- Edusentia tenant foundation: primary, unique and exclusion constraints
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

ALTER TABLE ONLY public.academic_departments ADD CONSTRAINT academic_departments_code_key UNIQUE (code);

ALTER TABLE ONLY public.academic_departments ADD CONSTRAINT academic_departments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.academic_faculties ADD CONSTRAINT academic_faculties_code_key UNIQUE (code);

ALTER TABLE ONLY public.academic_faculties ADD CONSTRAINT academic_faculties_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.academic_levels ADD CONSTRAINT academic_levels_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.academic_levels ADD CONSTRAINT academic_levels_programme_id_code_key UNIQUE (programme_id, code);

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_pkey PRIMARY KEY (term_id);

ALTER TABLE ONLY public.academic_programmes ADD CONSTRAINT academic_programmes_code_key UNIQUE (code);

ALTER TABLE ONLY public.academic_programmes ADD CONSTRAINT academic_programmes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.academic_years ADD CONSTRAINT academic_years_name_key UNIQUE (name);

ALTER TABLE ONLY public.academic_years ADD CONSTRAINT academic_years_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.accounts_office_staff ADD CONSTRAINT accounts_office_staff_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.accounts_office_staff ADD CONSTRAINT accounts_office_staff_profile_id_key UNIQUE (profile_id);

ALTER TABLE ONLY public.accounts_office_staff ADD CONSTRAINT accounts_office_staff_staff_no_key UNIQUE (staff_no);

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_application_no_key UNIQUE (application_no);

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.admissions_documents ADD CONSTRAINT admissions_documents_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.admissions_offers ADD CONSTRAINT admissions_offers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.alumni_engagements ADD CONSTRAINT alumni_engagements_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_alumni_code_key UNIQUE (alumni_code);

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_student_id_key UNIQUE (student_id);

ALTER TABLE ONLY public.alumni_verification_requests ADD CONSTRAINT alumni_verification_requests_pkey PRIMARY KEY (id);

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

ALTER TABLE ONLY public.communication_campaigns ADD CONSTRAINT communication_campaigns_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.communication_deliveries ADD CONSTRAINT communication_deliveries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.communication_messages ADD CONSTRAINT communication_messages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.communication_templates ADD CONSTRAINT communication_templates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.communication_templates ADD CONSTRAINT communication_templates_template_name_key UNIQUE (template_name);

ALTER TABLE ONLY public.communication_thread_participants ADD CONSTRAINT communication_thread_participants_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.communication_thread_participants ADD CONSTRAINT communication_thread_participants_thread_id_profile_id_key UNIQUE (thread_id, profile_id);

ALTER TABLE ONLY public.communication_threads ADD CONSTRAINT communication_threads_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_data_category_key UNIQUE (data_category);

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.discipline_actions ADD CONSTRAINT discipline_actions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.discipline_guardian_acknowledgements ADD CONSTRAINT discipline_guardian_acknowledg_incident_id_guardian_user_id_key UNIQUE (incident_id, guardian_user_id);

ALTER TABLE ONLY public.discipline_guardian_acknowledgements ADD CONSTRAINT discipline_guardian_acknowledgements_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.discipline_incidents ADD CONSTRAINT discipline_incidents_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.emergency_academic_delegation_events ADD CONSTRAINT emergency_academic_delegation_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.emergency_academic_delegations ADD CONSTRAINT emergency_academic_delegations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_academic_year_id_class_id_roll_number_key UNIQUE (academic_year_id, class_id, roll_number);

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.enrollments ADD CONSTRAINT enrollments_student_id_academic_year_id_key UNIQUE (student_id, academic_year_id);

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_student_id_term_id_key UNIQUE (student_id, term_id);

ALTER TABLE ONLY public.finance_fee_allocations ADD CONSTRAINT finance_fee_allocations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_fee_allocations ADD CONSTRAINT finance_fee_allocations_transaction_id_account_id_key UNIQUE (transaction_id, account_id);

ALTER TABLE ONLY public.finance_fee_group_classes ADD CONSTRAINT finance_fee_group_classes_class_unique UNIQUE (class_id);

ALTER TABLE ONLY public.finance_fee_group_classes ADD CONSTRAINT finance_fee_group_classes_pkey PRIMARY KEY (fee_group_id, class_id);

ALTER TABLE ONLY public.finance_fee_groups ADD CONSTRAINT finance_fee_groups_code_key UNIQUE (code);

ALTER TABLE ONLY public.finance_fee_groups ADD CONSTRAINT finance_fee_groups_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_account_id_key UNIQUE (account_id);

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_invoice_no_key UNIQUE (invoice_no);

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_academic_year_id_term_id_class_id_key UNIQUE (academic_year_id, term_id, class_id);

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_receipt_no_key UNIQUE (receipt_no);

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_hold_overrides ADD CONSTRAINT finance_hold_overrides_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_hold_policy ADD CONSTRAINT finance_hold_policy_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_payroll_item_lines ADD CONSTRAINT finance_payroll_item_lines_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_run_id_teacher_id_key UNIQUE (run_id, teacher_id);

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_payroll_number_key UNIQUE (payroll_number);

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_teacher_id_key UNIQUE (teacher_id);

ALTER TABLE ONLY public.finance_payroll_rules ADD CONSTRAINT finance_payroll_rules_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_payroll_rules ADD CONSTRAINT finance_payroll_rules_rule_code_effective_from_key UNIQUE (rule_code, effective_from);

ALTER TABLE ONLY public.finance_payroll_runs ADD CONSTRAINT finance_payroll_runs_payroll_year_payroll_month_key UNIQUE (payroll_year, payroll_month);

ALTER TABLE ONLY public.finance_payroll_runs ADD CONSTRAINT finance_payroll_runs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_salary_grades ADD CONSTRAINT finance_salary_grades_code_key UNIQUE (code);

ALTER TABLE ONLY public.finance_salary_grades ADD CONSTRAINT finance_salary_grades_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_teacher_loans ADD CONSTRAINT finance_teacher_loans_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.finance_teacher_loans ADD CONSTRAINT finance_teacher_loans_reference_no_key UNIQUE (reference_no);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_guardian_id_student_id_key UNIQUE (guardian_id, student_id);

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.health_immunizations ADD CONSTRAINT health_immunizations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.health_medication_administrations ADD CONSTRAINT health_medication_administrations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.health_student_profiles ADD CONSTRAINT health_student_profiles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.health_student_profiles ADD CONSTRAINT health_student_profiles_student_id_key UNIQUE (student_id);

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hostel_beds ADD CONSTRAINT hostel_beds_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hostel_beds ADD CONSTRAINT hostel_beds_room_id_bed_code_key UNIQUE (room_id, bed_code);

ALTER TABLE ONLY public.hostel_houses ADD CONSTRAINT hostel_houses_house_code_key UNIQUE (house_code);

ALTER TABLE ONLY public.hostel_houses ADD CONSTRAINT hostel_houses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hostel_incidents ADD CONSTRAINT hostel_incidents_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hostel_movements ADD CONSTRAINT hostel_movements_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hostel_rooms ADD CONSTRAINT hostel_rooms_house_id_room_code_key UNIQUE (house_id, room_code);

ALTER TABLE ONLY public.hostel_rooms ADD CONSTRAINT hostel_rooms_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hr_employment_events ADD CONSTRAINT hr_employment_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hr_staff_documents ADD CONSTRAINT hr_staff_documents_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_profile_unique UNIQUE (profile_id);

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_source_unique UNIQUE (source_type, source_id);

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_staff_no_unique UNIQUE (staff_no);

ALTER TABLE ONLY public.hr_staff_qualifications ADD CONSTRAINT hr_staff_qualifications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_card_kind_card_number_key UNIQUE (card_kind, card_number);

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.import_batches ADD CONSTRAINT import_batches_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.import_errors ADD CONSTRAINT import_errors_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_asset_assignments ADD CONSTRAINT inventory_asset_assignments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_asset_writeoffs ADD CONSTRAINT inventory_asset_writeoffs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_asset_writeoffs ADD CONSTRAINT inventory_asset_writeoffs_writeoff_no_key UNIQUE (writeoff_no);

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_asset_tag_key UNIQUE (asset_tag);

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_goods_receipts ADD CONSTRAINT inventory_goods_receipts_grn_no_key UNIQUE (grn_no);

ALTER TABLE ONLY public.inventory_goods_receipts ADD CONSTRAINT inventory_goods_receipts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_request_no_key UNIQUE (request_no);

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_item_code_key UNIQUE (item_code);

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_locations ADD CONSTRAINT inventory_locations_code_key UNIQUE (code);

ALTER TABLE ONLY public.inventory_locations ADD CONSTRAINT inventory_locations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_po_line_request_unique UNIQUE (purchase_order_id, request_line_id);

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_purchase_order_lines_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_orders_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_orders_po_no_key UNIQUE (po_no);

ALTER TABLE ONLY public.inventory_purchase_request_lines ADD CONSTRAINT inventory_purchase_request_lines_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_purchase_requests ADD CONSTRAINT inventory_purchase_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_purchase_requests ADD CONSTRAINT inventory_purchase_requests_request_no_key UNIQUE (request_no);

ALTER TABLE ONLY public.inventory_settings ADD CONSTRAINT inventory_settings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_settings ADD CONSTRAINT inventory_settings_singleton_key_key UNIQUE (singleton_key);

ALTER TABLE ONLY public.inventory_staff_access ADD CONSTRAINT inventory_staff_access_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_suppliers ADD CONSTRAINT inventory_suppliers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory_suppliers ADD CONSTRAINT inventory_suppliers_supplier_code_key UNIQUE (supplier_code);

ALTER TABLE ONLY public.library_books ADD CONSTRAINT library_books_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_accession_unique UNIQUE (accession_no);

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_barcode_unique UNIQUE (barcode);

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_inventory_events ADD CONSTRAINT library_inventory_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_staff_access ADD CONSTRAINT library_staff_access_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_staff_access ADD CONSTRAINT library_staff_access_profile_unique UNIQUE (profile_id);

ALTER TABLE ONLY public.license_binding_sessions ADD CONSTRAINT license_binding_sessions_pkey PRIMARY KEY (license_id, actor_id);

ALTER TABLE ONLY public.license_entitlement_overrides ADD CONSTRAINT license_entitlement_overrides_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_events ADD CONSTRAINT license_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_feature_catalog ADD CONSTRAINT license_feature_catalog_pkey PRIMARY KEY (code);

ALTER TABLE ONLY public.license_plan_revisions ADD CONSTRAINT license_plan_revisions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_plan_revisions ADD CONSTRAINT license_plan_revisions_plan_id_revision_key UNIQUE (plan_id, revision);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_code_key UNIQUE (code);

ALTER TABLE ONLY public.license_plans ADD CONSTRAINT license_plans_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.license_verification_logs ADD CONSTRAINT license_verification_logs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.mfa_recovery_codes ADD CONSTRAINT mfa_recovery_codes_code_hash_key UNIQUE (code_hash);

ALTER TABLE ONLY public.mfa_recovery_codes ADD CONSTRAINT mfa_recovery_codes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.notification_outbox ADD CONSTRAINT notification_outbox_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_access_locks ADD CONSTRAINT platform_access_locks_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_audit_archives ADD CONSTRAINT platform_audit_archives_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_distribution_authorities ADD CONSTRAINT platform_distribution_authorities_actor_id_key UNIQUE (actor_id);

ALTER TABLE ONLY public.platform_distribution_authorities ADD CONSTRAINT platform_distribution_authorities_distributor_code_key UNIQUE (distributor_code);

ALTER TABLE ONLY public.platform_distribution_authorities ADD CONSTRAINT platform_distribution_authorities_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_artifacts ADD CONSTRAINT platform_package_artifacts_storage_path_key UNIQUE (storage_path);

ALTER TABLE ONLY public.platform_package_events ADD CONSTRAINT platform_package_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_reconciliation ADD CONSTRAINT platform_package_reconciliation_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_signing_identity ADD CONSTRAINT platform_package_signing_identity_pkey PRIMARY KEY (singleton);

ALTER TABLE ONLY public.platform_package_templates ADD CONSTRAINT platform_package_templates_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.platform_package_templates ADD CONSTRAINT platform_package_templates_storage_path_key UNIQUE (storage_path);

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

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_license_reference_key UNIQUE (license_reference);

ALTER TABLE ONLY public.school_licenses ADD CONSTRAINT school_licenses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectus_items ADD CONSTRAINT school_prospectus_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectus_revisions ADD CONSTRAINT school_prospectus_revisions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectus_revisions ADD CONSTRAINT school_prospectus_revisions_prospectus_id_revision_no_key UNIQUE (prospectus_id, revision_no);

ALTER TABLE ONLY public.school_prospectus_sections ADD CONSTRAINT school_prospectus_sections_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_academic_year_id_class_range_key UNIQUE (academic_year_id, class_range);

ALTER TABLE ONLY public.school_prospectuses ADD CONSTRAINT school_prospectuses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_pkey PRIMARY KEY (job_id, table_name);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.security_verification_runs ADD CONSTRAINT security_verification_runs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.shs_programme_subjects ADD CONSTRAINT shs_programme_subjects_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.shs_programme_subjects ADD CONSTRAINT shs_programme_subjects_programme_id_level_id_subject_id_key UNIQUE (programme_id, level_id, subject_id);

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

ALTER TABLE ONLY public.student_programme_enrollments ADD CONSTRAINT student_programme_enrollments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_programme_enrollments ADD CONSTRAINT student_programme_enrollments_student_id_academic_year_id_key UNIQUE (student_id, academic_year_id);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_report_number_key UNIQUE (report_number);

ALTER TABLE ONLY public.student_services_events ADD CONSTRAINT student_services_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_services_staff_access ADD CONSTRAINT student_services_staff_access_hr_staff_id_service_role_key UNIQUE (hr_staff_id, service_role);

ALTER TABLE ONLY public.student_services_staff_access ADD CONSTRAINT student_services_staff_access_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_services_staff_access ADD CONSTRAINT student_services_staff_access_profile_id_service_role_key UNIQUE (profile_id, service_role);

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

ALTER TABLE ONLY public.system_release_state ADD CONSTRAINT system_release_state_pkey PRIMARY KEY (singleton);

ALTER TABLE ONLY public.teacher_award_categories ADD CONSTRAINT teacher_award_categories_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_academic_year_id_name_key UNIQUE (academic_year_id, name);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_academic_year_id_sequence_key UNIQUE (academic_year_id, sequence);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_course_id_academic_year_id_term_i_key UNIQUE (course_id, academic_year_id, term_id, section_code);

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_course_prerequisites ADD CONSTRAINT tertiary_course_prerequisites_course_id_prerequisite_course_key UNIQUE (course_id, prerequisite_course_id);

ALTER TABLE ONLY public.tertiary_course_prerequisites ADD CONSTRAINT tertiary_course_prerequisites_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_course_registrations ADD CONSTRAINT tertiary_course_registrations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_course_registrations ADD CONSTRAINT tertiary_course_registrations_student_id_course_offering_id_key UNIQUE (student_id, course_offering_id);

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_course_registration_id_key UNIQUE (course_registration_id);

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_courses ADD CONSTRAINT tertiary_courses_code_key UNIQUE (code);

ALTER TABLE ONLY public.tertiary_courses ADD CONSTRAINT tertiary_courses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_degree_classifications ADD CONSTRAINT tertiary_degree_classifications_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_degree_classifications ADD CONSTRAINT tertiary_degree_classifications_programme_id_name_key UNIQUE (programme_id, name);

ALTER TABLE ONLY public.tertiary_grading_scale ADD CONSTRAINT tertiary_grading_scale_minimum_score_maximum_score_letter_g_key UNIQUE (minimum_score, maximum_score, letter_grade);

ALTER TABLE ONLY public.tertiary_grading_scale ADD CONSTRAINT tertiary_grading_scale_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_programme_id_course_id_level_id__key UNIQUE (programme_id, course_id, level_id, period_sequence);

ALTER TABLE ONLY public.tertiary_programme_requirements ADD CONSTRAINT tertiary_programme_requirements_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.tertiary_programme_requirements ADD CONSTRAINT tertiary_programme_requirements_programme_id_key UNIQUE (programme_id);

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_verification_token_key UNIQUE (verification_token);

ALTER TABLE ONLY public.transport_drivers ADD CONSTRAINT transport_drivers_hr_staff_id_key UNIQUE (hr_staff_id);

ALTER TABLE ONLY public.transport_drivers ADD CONSTRAINT transport_drivers_licence_no_key UNIQUE (licence_no);

ALTER TABLE ONLY public.transport_drivers ADD CONSTRAINT transport_drivers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_maintenance_records ADD CONSTRAINT transport_maintenance_records_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_route_stops ADD CONSTRAINT transport_route_stops_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_route_stops ADD CONSTRAINT transport_route_stops_route_order_unique UNIQUE (route_id, stop_order);

ALTER TABLE ONLY public.transport_route_stops ADD CONSTRAINT transport_route_stops_route_stop_unique UNIQUE (route_id, stop_id);

ALTER TABLE ONLY public.transport_routes ADD CONSTRAINT transport_routes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_routes ADD CONSTRAINT transport_routes_route_code_key UNIQUE (route_code);

ALTER TABLE ONLY public.transport_settings ADD CONSTRAINT transport_settings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_staff_access ADD CONSTRAINT transport_staff_access_hr_unique UNIQUE (hr_staff_id);

ALTER TABLE ONLY public.transport_staff_access ADD CONSTRAINT transport_staff_access_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_staff_access ADD CONSTRAINT transport_staff_access_profile_unique UNIQUE (profile_id);

ALTER TABLE ONLY public.transport_stops ADD CONSTRAINT transport_stops_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_stops ADD CONSTRAINT transport_stops_stop_code_key UNIQUE (stop_code);

ALTER TABLE ONLY public.transport_student_assignments ADD CONSTRAINT transport_student_assignments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_unique UNIQUE (trip_id, student_id);

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trip_unique UNIQUE (route_id, service_date, scheduled_departure);

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_fleet_no_key UNIQUE (fleet_no);

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_registration_no_key UNIQUE (registration_no);

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_user_id_class_id_subject_id_access_level_key UNIQUE (user_id, class_id, subject_id, access_level);

ALTER TABLE ONLY public.welfare_case_notes ADD CONSTRAINT welfare_case_notes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_pkey PRIMARY KEY (id);
