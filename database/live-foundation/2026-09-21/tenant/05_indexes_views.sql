-- Edusentia tenant foundation: indexes and views
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

CREATE INDEX academic_departments_faculty_idx ON public.academic_departments USING btree (faculty_id);

CREATE INDEX academic_programmes_department_idx ON public.academic_programmes USING btree (department_id);

CREATE INDEX admissions_applications_applying_class_idx ON public.admissions_applications USING btree (applying_class_id);

CREATE INDEX admissions_applications_created_by_idx ON public.admissions_applications USING btree (created_by);

CREATE INDEX admissions_applications_decided_by_idx ON public.admissions_applications USING btree (decided_by);

CREATE INDEX admissions_applications_reviewed_by_idx ON public.admissions_applications USING btree (reviewed_by);

CREATE INDEX admissions_applications_status_idx ON public.admissions_applications USING btree (status, created_at DESC);

CREATE INDEX admissions_applications_student_idx ON public.admissions_applications USING btree (student_id) WHERE (student_id IS NOT NULL);

CREATE INDEX admissions_applications_year_class_idx ON public.admissions_applications USING btree (target_academic_year_id, applying_class_id, status);

CREATE INDEX admissions_documents_application_idx ON public.admissions_documents USING btree (application_id, created_at DESC);

CREATE INDEX admissions_documents_created_by_idx ON public.admissions_documents USING btree (created_by);

CREATE INDEX admissions_documents_verified_by_idx ON public.admissions_documents USING btree (verified_by);

CREATE INDEX admissions_offers_application_idx ON public.admissions_offers USING btree (application_id, created_at DESC);

CREATE INDEX admissions_offers_class_idx ON public.admissions_offers USING btree (class_id);

CREATE INDEX admissions_offers_created_by_idx ON public.admissions_offers USING btree (created_by);

CREATE INDEX admissions_offers_year_class_idx ON public.admissions_offers USING btree (academic_year_id, class_id, status);

CREATE UNIQUE INDEX admissions_one_live_offer_idx ON public.admissions_offers USING btree (application_id) WHERE (status = ANY (ARRAY['offered'::text, 'accepted'::text]));

CREATE INDEX alumni_created_by_idx ON public.alumni_records USING btree (created_by);

CREATE INDEX alumni_engagement_alumni_idx ON public.alumni_engagements USING btree (alumni_id, engagement_date DESC);

CREATE INDEX alumni_engagement_recorded_by_idx ON public.alumni_engagements USING btree (recorded_by);

CREATE INDEX alumni_name_idx ON public.alumni_records USING btree (last_name, first_name);

CREATE INDEX alumni_records_final_class_idx ON public.alumni_records USING btree (final_class_id);

CREATE INDEX alumni_student_idx ON public.alumni_records USING btree (student_id) WHERE (student_id IS NOT NULL);

CREATE INDEX alumni_verification_alumni_idx ON public.alumni_verification_requests USING btree (alumni_id, requested_at DESC);

CREATE INDEX alumni_verification_created_by_idx ON public.alumni_verification_requests USING btree (created_by);

CREATE INDEX alumni_verification_reviewed_by_idx ON public.alumni_verification_requests USING btree (reviewed_by);

CREATE INDEX alumni_verification_status_idx ON public.alumni_verification_requests USING btree (status, requested_at DESC);

CREATE INDEX alumni_verified_by_idx ON public.alumni_records USING btree (verified_by);

CREATE INDEX alumni_year_idx ON public.alumni_records USING btree (graduation_academic_year_id, final_class_id, status);

CREATE UNIQUE INDEX assessment_scheme_scope_idx ON public.assessment_schemes USING btree (lower(name), COALESCE(academic_year_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(term_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE (deleted_at IS NULL);

CREATE INDEX assessment_score_entries_component_idx ON public.assessment_score_entries USING btree (component_id);

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

CREATE INDEX certificate_batches_class_idx ON public.certificate_batches USING btree (class_id) WHERE (class_id IS NOT NULL);

CREATE INDEX certificate_batches_scope_idx ON public.certificate_batches USING btree (academic_year_id, certificate_type, status, created_at DESC);

CREATE INDEX certificate_batches_template_idx ON public.certificate_batches USING btree (template_id);

CREATE INDEX certificate_batches_term_idx ON public.certificate_batches USING btree (term_id);

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

CREATE INDEX client_error_events_actor_fingerprint_idx ON public.client_error_events USING btree (actor_id, fingerprint, last_seen_at DESC);

CREATE INDEX client_error_events_health_idx ON public.client_error_events USING btree (status, severity, last_seen_at DESC);

CREATE INDEX communication_campaign_created_by_idx ON public.communication_campaigns USING btree (created_by);

CREATE INDEX communication_campaign_status_idx ON public.communication_campaigns USING btree (status, scheduled_at, created_at DESC);

CREATE INDEX communication_campaigns_audience_class_idx ON public.communication_campaigns USING btree (audience_class_id);

CREATE INDEX communication_delivery_campaign_idx ON public.communication_deliveries USING btree (campaign_id, status, channel);

CREATE INDEX communication_delivery_outbox_idx ON public.communication_deliveries USING btree (outbox_id) WHERE (outbox_id IS NOT NULL);

CREATE INDEX communication_delivery_profile_idx ON public.communication_deliveries USING btree (recipient_profile_id, created_at DESC);

CREATE INDEX communication_delivery_student_idx ON public.communication_deliveries USING btree (student_id, created_at DESC);

CREATE INDEX communication_message_sender_idx ON public.communication_messages USING btree (sender_profile_id, created_at DESC);

CREATE INDEX communication_message_thread_idx ON public.communication_messages USING btree (thread_id, created_at);

CREATE INDEX communication_participant_profile_idx ON public.communication_thread_participants USING btree (profile_id, thread_id);

CREATE INDEX communication_template_created_by_idx ON public.communication_templates USING btree (created_by);

CREATE INDEX communication_thread_created_by_idx ON public.communication_threads USING btree (created_by);

CREATE INDEX discipline_ack_guardian_user_idx ON public.discipline_guardian_acknowledgements USING btree (guardian_user_id);

CREATE INDEX discipline_ack_student_idx ON public.discipline_guardian_acknowledgements USING btree (student_id, acknowledged_at DESC);

CREATE INDEX discipline_actions_assigned_staff_idx ON public.discipline_actions USING btree (assigned_hr_staff_id);

CREATE INDEX discipline_actions_completed_by_idx ON public.discipline_actions USING btree (completed_by);

CREATE INDEX discipline_actions_created_by_idx ON public.discipline_actions USING btree (created_by);

CREATE INDEX discipline_actions_incident_idx ON public.discipline_actions USING btree (incident_id, created_at DESC);

CREATE INDEX discipline_incidents_reported_by_idx ON public.discipline_incidents USING btree (reported_by);

CREATE INDEX discipline_incidents_resolved_by_idx ON public.discipline_incidents USING btree (resolved_by);

CREATE INDEX discipline_incidents_status_idx ON public.discipline_incidents USING btree (status, severity, occurred_at DESC);

CREATE INDEX discipline_incidents_student_time_idx ON public.discipline_incidents USING btree (student_id, occurred_at DESC);

CREATE INDEX emergency_academic_delegation_events_created_idx ON public.emergency_academic_delegation_events USING btree (created_at DESC);

CREATE INDEX emergency_academic_delegation_events_delegation_idx ON public.emergency_academic_delegation_events USING btree (delegation_id, created_at DESC);

CREATE INDEX emergency_academic_delegation_events_report_idx ON public.emergency_academic_delegation_events USING btree (report_id, created_at DESC) WHERE (report_id IS NOT NULL);

CREATE INDEX emergency_academic_delegations_console_idx ON public.emergency_academic_delegations USING btree (created_at DESC);

CREATE INDEX emergency_academic_delegations_delegate_idx ON public.emergency_academic_delegations USING btree (delegate_user_id, term_id, class_id, valid_until DESC) WHERE (status = 'active'::text);

CREATE INDEX emergency_academic_delegations_scope_idx ON public.emergency_academic_delegations USING btree (term_id, class_id, subject_id, valid_from, valid_until);

CREATE INDEX enrollments_class_year_idx ON public.enrollments USING btree (class_id, academic_year_id) WHERE (deleted_at IS NULL);

CREATE INDEX enrollments_promotion_source_report_idx ON public.enrollments USING btree (promotion_source_report_id) WHERE (promotion_source_report_id IS NOT NULL);

CREATE INDEX enrollments_student_idx ON public.enrollments USING btree (student_id) WHERE (deleted_at IS NULL);

CREATE INDEX finance_fee_accounts_class_idx ON public.finance_fee_accounts USING btree (class_id, term_id);

CREATE INDEX finance_fee_accounts_student_idx ON public.finance_fee_accounts USING btree (student_id, academic_year_id, term_id);

CREATE INDEX finance_fee_allocations_account_idx ON public.finance_fee_allocations USING btree (account_id);

CREATE INDEX finance_fee_invoices_academic_year_idx ON public.finance_fee_invoices USING btree (academic_year_id);

CREATE INDEX finance_fee_invoices_class_idx ON public.finance_fee_invoices USING btree (class_id);

CREATE INDEX finance_fee_invoices_created_by_idx ON public.finance_fee_invoices USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX finance_fee_invoices_due_status_idx ON public.finance_fee_invoices USING btree (due_date, student_id);

CREATE INDEX finance_fee_invoices_schedule_idx ON public.finance_fee_invoices USING btree (schedule_id) WHERE (schedule_id IS NOT NULL);

CREATE INDEX finance_fee_invoices_student_idx ON public.finance_fee_invoices USING btree (student_id);

CREATE INDEX finance_fee_invoices_term_idx ON public.finance_fee_invoices USING btree (term_id);

CREATE INDEX finance_fee_schedules_fee_group_idx ON public.finance_fee_schedules USING btree (fee_group_id, academic_year_id, term_id);

CREATE UNIQUE INDEX finance_fee_transactions_one_reversal_per_original ON public.finance_fee_transactions USING btree (reversal_of_id) WHERE (reversal_of_id IS NOT NULL);

CREATE INDEX finance_fee_transactions_student_idx ON public.finance_fee_transactions USING btree (student_id, transaction_date, created_at);

CREATE INDEX finance_guardian_contact_events_created_idx ON public.finance_guardian_contact_events USING btree (created_at DESC);

CREATE INDEX finance_guardian_contact_events_guardian_idx ON public.finance_guardian_contact_events USING btree (guardian_key, created_at DESC);

CREATE INDEX finance_guardian_contact_events_period_idx ON public.finance_guardian_contact_events USING btree (academic_year_id, term_id, created_at DESC);

CREATE INDEX finance_hold_overrides_student_idx ON public.finance_hold_overrides USING btree (student_id, active, starts_at DESC);

CREATE UNIQUE INDEX finance_payroll_item_lines_source_unique ON public.finance_payroll_item_lines USING btree (payroll_item_id, source_key) WHERE (source_key <> ''::text);

CREATE INDEX finance_payroll_items_teacher_idx ON public.finance_payroll_items USING btree (teacher_id, created_at DESC);

CREATE INDEX finance_payroll_profiles_hr_staff_idx ON public.finance_payroll_profiles USING btree (hr_staff_member_id) WHERE (hr_staff_member_id IS NOT NULL);

CREATE INDEX finance_teacher_loans_teacher_idx ON public.finance_teacher_loans USING btree (teacher_id, status);

CREATE INDEX grading_scale_range_idx ON public.grading_scales USING btree (min_mark, max_mark);

CREATE UNIQUE INDEX grading_scale_scope_grade_idx ON public.grading_scales USING btree (COALESCE(academic_year_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(grade)) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX guardian_auth_student_unique ON public.guardian_links USING btree (auth_user_id, student_id) WHERE (auth_user_id IS NOT NULL);

CREATE INDEX guardian_links_student_idx ON public.guardian_links USING btree (student_id);

CREATE INDEX headteachers_name_search_idx ON public.headteachers USING btree (lower(last_name), lower(first_name)) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX headteachers_one_current_principal_idx ON public.headteachers USING btree ((1)) WHERE ((deleted_at IS NULL) AND active AND (employment_status = 'active'::text));

CREATE UNIQUE INDEX headteachers_profile_active_idx ON public.headteachers USING btree (profile_id) WHERE ((profile_id IS NOT NULL) AND (deleted_at IS NULL));

CREATE UNIQUE INDEX headteachers_staff_no_ci_idx ON public.headteachers USING btree (lower((staff_no)::text)) WHERE (deleted_at IS NULL);

CREATE INDEX headteachers_status_idx ON public.headteachers USING btree (employment_status, active) WHERE (deleted_at IS NULL);

CREATE INDEX health_immunizations_recorded_by_idx ON public.health_immunizations USING btree (recorded_by);

CREATE INDEX health_immunizations_student_idx ON public.health_immunizations USING btree (student_id, next_due_date);

CREATE INDEX health_meds_created_by_idx ON public.health_medication_administrations USING btree (created_by);

CREATE INDEX health_meds_staff_idx ON public.health_medication_administrations USING btree (administered_by_hr_staff_id);

CREATE INDEX health_meds_student_time_idx ON public.health_medication_administrations USING btree (student_id, administered_at DESC);

CREATE INDEX health_meds_visit_idx ON public.health_medication_administrations USING btree (visit_id, administered_at);

CREATE INDEX health_profiles_created_by_idx ON public.health_student_profiles USING btree (created_by);

CREATE INDEX health_profiles_updated_by_idx ON public.health_student_profiles USING btree (updated_by);

CREATE INDEX health_visits_created_by_idx ON public.health_visits USING btree (created_by);

CREATE INDEX health_visits_staff_idx ON public.health_visits USING btree (attended_by_hr_staff_id);

CREATE INDEX health_visits_status_idx ON public.health_visits USING btree (status, visited_at DESC);

CREATE INDEX health_visits_student_time_idx ON public.health_visits USING btree (student_id, visited_at DESC);

CREATE INDEX hostel_alloc_allocated_by_idx ON public.hostel_allocations USING btree (allocated_by);

CREATE INDEX hostel_alloc_ended_by_idx ON public.hostel_allocations USING btree (ended_by);

CREATE INDEX hostel_alloc_student_year_idx ON public.hostel_allocations USING btree (student_id, academic_year_id, status);

CREATE INDEX hostel_alloc_year_idx ON public.hostel_allocations USING btree (academic_year_id, status);

CREATE INDEX hostel_beds_created_by_idx ON public.hostel_beds USING btree (created_by);

CREATE INDEX hostel_beds_room_status_idx ON public.hostel_beds USING btree (room_id, status);

CREATE INDEX hostel_houses_created_by_idx ON public.hostel_houses USING btree (created_by);

CREATE INDEX hostel_houses_parent_idx ON public.hostel_houses USING btree (house_parent_hr_staff_id);

CREATE INDEX hostel_incidents_allocation_idx ON public.hostel_incidents USING btree (allocation_id);

CREATE INDEX hostel_incidents_reported_by_idx ON public.hostel_incidents USING btree (reported_by);

CREATE INDEX hostel_incidents_resolved_by_idx ON public.hostel_incidents USING btree (resolved_by);

CREATE INDEX hostel_incidents_status_idx ON public.hostel_incidents USING btree (status, severity, occurred_at DESC);

CREATE INDEX hostel_incidents_student_time_idx ON public.hostel_incidents USING btree (student_id, occurred_at DESC);

CREATE INDEX hostel_movements_allocation_idx ON public.hostel_movements USING btree (allocation_id, occurred_at DESC);

CREATE INDEX hostel_movements_recorded_by_idx ON public.hostel_movements USING btree (recorded_by);

CREATE INDEX hostel_movements_student_time_idx ON public.hostel_movements USING btree (student_id, occurred_at DESC);

CREATE UNIQUE INDEX hostel_one_active_bed_allocation_idx ON public.hostel_allocations USING btree (bed_id) WHERE (status = 'active'::text);

CREATE UNIQUE INDEX hostel_one_active_student_allocation_idx ON public.hostel_allocations USING btree (student_id) WHERE (status = 'active'::text);

CREATE INDEX hostel_rooms_created_by_idx ON public.hostel_rooms USING btree (created_by);

CREATE INDEX hostel_rooms_house_idx ON public.hostel_rooms USING btree (house_id, active);

CREATE INDEX hr_employment_events_created_by_idx ON public.hr_employment_events USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX hr_employment_events_staff_idx ON public.hr_employment_events USING btree (staff_id, event_date DESC, created_at DESC);

CREATE INDEX hr_leave_requests_decided_by_idx ON public.hr_leave_requests USING btree (decided_by) WHERE (decided_by IS NOT NULL);

CREATE INDEX hr_leave_requests_staff_idx ON public.hr_leave_requests USING btree (staff_id, start_date DESC);

CREATE INDEX hr_leave_requests_status_idx ON public.hr_leave_requests USING btree (status, start_date DESC);

CREATE INDEX hr_leave_requests_submitted_by_idx ON public.hr_leave_requests USING btree (submitted_by) WHERE (submitted_by IS NOT NULL);

CREATE INDEX hr_staff_documents_created_by_idx ON public.hr_staff_documents USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX hr_staff_documents_expiry_idx ON public.hr_staff_documents USING btree (expires_on) WHERE (expires_on IS NOT NULL);

CREATE INDEX hr_staff_documents_staff_idx ON public.hr_staff_documents USING btree (staff_id, created_at DESC);

CREATE INDEX hr_staff_documents_verified_by_idx ON public.hr_staff_documents USING btree (verified_by) WHERE (verified_by IS NOT NULL);

CREATE INDEX hr_staff_members_active_idx ON public.hr_staff_members USING btree (active, employment_status) WHERE (deleted_at IS NULL);

CREATE INDEX hr_staff_members_created_by_idx ON public.hr_staff_members USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX hr_staff_members_department_idx ON public.hr_staff_members USING btree (department) WHERE (deleted_at IS NULL);

CREATE INDEX hr_staff_members_name_idx ON public.hr_staff_members USING btree (lower(first_name), lower(last_name)) WHERE (deleted_at IS NULL);

CREATE INDEX hr_staff_qualifications_created_by_idx ON public.hr_staff_qualifications USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX hr_staff_qualifications_staff_idx ON public.hr_staff_qualifications USING btree (staff_id, created_at DESC);

CREATE INDEX hr_staff_qualifications_verified_by_idx ON public.hr_staff_qualifications USING btree (verified_by) WHERE (verified_by IS NOT NULL);

CREATE INDEX id_card_events_card_idx ON public.id_card_events USING btree (card_id, created_at DESC);

CREATE UNIQUE INDEX id_card_settings_singleton_idx ON public.id_card_settings USING btree ((true));

CREATE INDEX import_errors_batch_idx ON public.import_errors USING btree (batch_id);

CREATE INDEX inventory_asset_assignments_assigned_by_idx ON public.inventory_asset_assignments USING btree (assigned_by);

CREATE UNIQUE INDEX inventory_asset_assignments_current_uq ON public.inventory_asset_assignments USING btree (asset_id) WHERE (returned_at IS NULL);

CREATE INDEX inventory_asset_assignments_location_idx ON public.inventory_asset_assignments USING btree (assigned_location_id);

CREATE INDEX inventory_asset_assignments_returned_by_idx ON public.inventory_asset_assignments USING btree (returned_by);

CREATE INDEX inventory_asset_assignments_staff_idx ON public.inventory_asset_assignments USING btree (staff_id, assigned_on DESC);

CREATE INDEX inventory_asset_maintenance_asset_idx ON public.inventory_asset_maintenance USING btree (asset_id, opened_on DESC);

CREATE INDEX inventory_asset_maintenance_completed_by_idx ON public.inventory_asset_maintenance USING btree (completed_by);

CREATE INDEX inventory_asset_maintenance_created_by_idx ON public.inventory_asset_maintenance USING btree (created_by);

CREATE INDEX inventory_asset_maintenance_due_idx ON public.inventory_asset_maintenance USING btree (next_due_on) WHERE ((status = 'completed'::text) AND (next_due_on IS NOT NULL));

CREATE INDEX inventory_asset_maintenance_vendor_idx ON public.inventory_asset_maintenance USING btree (vendor_id);

CREATE INDEX inventory_asset_writeoffs_decided_by_idx ON public.inventory_asset_writeoffs USING btree (decided_by);

CREATE UNIQUE INDEX inventory_asset_writeoffs_pending_uq ON public.inventory_asset_writeoffs USING btree (asset_id) WHERE (status = 'pending'::text);

CREATE INDEX inventory_asset_writeoffs_requested_by_idx ON public.inventory_asset_writeoffs USING btree (requested_by);

CREATE INDEX inventory_asset_writeoffs_status_idx ON public.inventory_asset_writeoffs USING btree (status, requested_at DESC);

CREATE INDEX inventory_assets_created_by_idx ON public.inventory_assets USING btree (created_by);

CREATE INDEX inventory_assets_item_idx ON public.inventory_assets USING btree (item_id) WHERE (item_id IS NOT NULL);

CREATE INDEX inventory_assets_location_idx ON public.inventory_assets USING btree (current_location_id);

CREATE INDEX inventory_assets_purchase_order_line_idx ON public.inventory_assets USING btree (purchase_order_line_id) WHERE (purchase_order_line_id IS NOT NULL);

CREATE UNIQUE INDEX inventory_assets_serial_uq ON public.inventory_assets USING btree (lower(serial_number)) WHERE ((serial_number IS NOT NULL) AND (btrim(serial_number) <> ''::text));

CREATE INDEX inventory_assets_status_idx ON public.inventory_assets USING btree (asset_status, current_location_id) WHERE active;

CREATE INDEX inventory_assets_status_location_idx ON public.inventory_assets USING btree (asset_status, current_location_id);

CREATE INDEX inventory_assets_supplier_idx ON public.inventory_assets USING btree (supplier_id);

CREATE INDEX inventory_events_actor_idx ON public.inventory_events USING btree (actor_id);

CREATE INDEX inventory_events_entity_idx ON public.inventory_events USING btree (entity_type, entity_id, occurred_at DESC);

CREATE INDEX inventory_events_type_idx ON public.inventory_events USING btree (event_type, occurred_at DESC);

CREATE INDEX inventory_goods_receipt_lines_item_idx ON public.inventory_goods_receipt_lines USING btree (item_id);

CREATE INDEX inventory_goods_receipt_lines_location_idx ON public.inventory_goods_receipt_lines USING btree (location_id);

CREATE INDEX inventory_goods_receipt_lines_po_line_idx ON public.inventory_goods_receipt_lines USING btree (purchase_order_line_id);

CREATE INDEX inventory_goods_receipt_lines_receipt_idx ON public.inventory_goods_receipt_lines USING btree (goods_receipt_id);

CREATE INDEX inventory_goods_receipt_lines_stock_movement_idx ON public.inventory_goods_receipt_lines USING btree (stock_movement_id);

CREATE INDEX inventory_goods_receipts_po_idx ON public.inventory_goods_receipts USING btree (purchase_order_id, received_on DESC);

CREATE INDEX inventory_goods_receipts_received_by_idx ON public.inventory_goods_receipts USING btree (received_by);

CREATE INDEX inventory_goods_receipts_received_on_idx ON public.inventory_goods_receipts USING btree (received_on DESC);

CREATE INDEX inventory_item_requests_decided_by_idx ON public.inventory_item_requests USING btree (decided_by);

CREATE INDEX inventory_item_requests_fulfilled_by_idx ON public.inventory_item_requests USING btree (fulfilled_by);

CREATE INDEX inventory_item_requests_fulfilled_movement_idx ON public.inventory_item_requests USING btree (fulfilled_movement_id);

CREATE INDEX inventory_item_requests_item_idx ON public.inventory_item_requests USING btree (item_id);

CREATE INDEX inventory_item_requests_location_idx ON public.inventory_item_requests USING btree (preferred_location_id);

CREATE INDEX inventory_item_requests_staff_idx ON public.inventory_item_requests USING btree (staff_id, requested_at DESC);

CREATE INDEX inventory_item_requests_status_created_idx ON public.inventory_item_requests USING btree (status, created_at DESC);

CREATE INDEX inventory_item_requests_status_idx ON public.inventory_item_requests USING btree (status, requested_at DESC);

CREATE INDEX inventory_items_category_idx ON public.inventory_items USING btree (category, item_type) WHERE active;

CREATE INDEX inventory_items_created_by_idx ON public.inventory_items USING btree (created_by);

CREATE INDEX inventory_items_name_idx ON public.inventory_items USING btree (lower(item_name)) WHERE active;

CREATE INDEX inventory_items_preferred_supplier_idx ON public.inventory_items USING btree (preferred_supplier_id);

CREATE INDEX inventory_locations_created_by_idx ON public.inventory_locations USING btree (created_by);

CREATE INDEX inventory_purchase_order_lines_item_idx ON public.inventory_purchase_order_lines USING btree (item_id);

CREATE INDEX inventory_purchase_order_lines_po_idx ON public.inventory_purchase_order_lines USING btree (purchase_order_id);

CREATE INDEX inventory_purchase_order_lines_request_line_idx ON public.inventory_purchase_order_lines USING btree (request_line_id);

CREATE UNIQUE INDEX inventory_purchase_orders_active_request_uq ON public.inventory_purchase_orders USING btree (request_id) WHERE (status <> ALL (ARRAY['rejected'::text, 'cancelled'::text]));

CREATE INDEX inventory_purchase_orders_approved_by_idx ON public.inventory_purchase_orders USING btree (approved_by);

CREATE INDEX inventory_purchase_orders_created_by_idx ON public.inventory_purchase_orders USING btree (created_by);

CREATE INDEX inventory_purchase_orders_status_created_idx ON public.inventory_purchase_orders USING btree (status, created_at DESC);

CREATE INDEX inventory_purchase_orders_status_idx ON public.inventory_purchase_orders USING btree (status, order_date DESC);

CREATE INDEX inventory_purchase_orders_supplier_idx ON public.inventory_purchase_orders USING btree (supplier_id, order_date DESC);

CREATE INDEX inventory_purchase_request_lines_item_idx ON public.inventory_purchase_request_lines USING btree (item_id);

CREATE INDEX inventory_purchase_request_lines_request_idx ON public.inventory_purchase_request_lines USING btree (request_id);

CREATE INDEX inventory_purchase_requests_decided_by_idx ON public.inventory_purchase_requests USING btree (decided_by);

CREATE INDEX inventory_purchase_requests_requested_by_idx ON public.inventory_purchase_requests USING btree (requested_by);

CREATE INDEX inventory_purchase_requests_status_created_idx ON public.inventory_purchase_requests USING btree (status, created_at DESC);

CREATE INDEX inventory_purchase_requests_status_idx ON public.inventory_purchase_requests USING btree (status, requested_at DESC);

CREATE UNIQUE INDEX inventory_staff_access_active_profile_uq ON public.inventory_staff_access USING btree (profile_id) WHERE (active AND (revoked_at IS NULL));

CREATE UNIQUE INDEX inventory_staff_access_active_staff_uq ON public.inventory_staff_access USING btree (staff_id) WHERE (active AND (revoked_at IS NULL));

CREATE INDEX inventory_staff_access_appointed_by_idx ON public.inventory_staff_access USING btree (appointed_by);

CREATE INDEX inventory_staff_access_revoked_by_idx ON public.inventory_staff_access USING btree (revoked_by);

CREATE INDEX inventory_stock_movements_balance_idx ON public.inventory_stock_movements USING btree (item_id, location_id, posted_at) WHERE (voided_at IS NULL);

CREATE INDEX inventory_stock_movements_item_location_posted_idx ON public.inventory_stock_movements USING btree (item_id, location_id, posted_at DESC);

CREATE INDEX inventory_stock_movements_location_idx ON public.inventory_stock_movements USING btree (location_id);

CREATE INDEX inventory_stock_movements_posted_by_idx ON public.inventory_stock_movements USING btree (posted_by);

CREATE INDEX inventory_stock_movements_recipient_idx ON public.inventory_stock_movements USING btree (recipient_staff_id, posted_at DESC) WHERE (recipient_staff_id IS NOT NULL);

CREATE INDEX inventory_stock_movements_reference_idx ON public.inventory_stock_movements USING btree (reference_type, reference_id) WHERE (reference_id IS NOT NULL);

CREATE INDEX inventory_stock_movements_related_idx ON public.inventory_stock_movements USING btree (related_movement_id) WHERE (related_movement_id IS NOT NULL);

CREATE INDEX inventory_stock_movements_voided_by_idx ON public.inventory_stock_movements USING btree (voided_by);

CREATE INDEX inventory_suppliers_created_by_idx ON public.inventory_suppliers USING btree (created_by);

CREATE INDEX inventory_suppliers_name_idx ON public.inventory_suppliers USING btree (lower(supplier_name)) WHERE active;

CREATE INDEX library_books_author_idx ON public.library_books USING btree (lower(author)) WHERE (deleted_at IS NULL);

CREATE INDEX library_books_category_idx ON public.library_books USING btree (category) WHERE (deleted_at IS NULL);

CREATE INDEX library_books_created_by_idx ON public.library_books USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX library_books_isbn_idx ON public.library_books USING btree (isbn) WHERE ((isbn IS NOT NULL) AND (deleted_at IS NULL));

CREATE INDEX library_books_title_idx ON public.library_books USING btree (lower(title)) WHERE (deleted_at IS NULL);

CREATE INDEX library_copies_book_idx ON public.library_copies USING btree (book_id) WHERE (deleted_at IS NULL);

CREATE INDEX library_copies_created_by_idx ON public.library_copies USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX library_copies_shelf_idx ON public.library_copies USING btree (shelf_location) WHERE (deleted_at IS NULL);

CREATE INDEX library_copies_status_idx ON public.library_copies USING btree (circulation_status, active) WHERE (deleted_at IS NULL);

CREATE INDEX library_inventory_events_actor_idx ON public.library_inventory_events USING btree (actor_id) WHERE (actor_id IS NOT NULL);

CREATE INDEX library_inventory_events_copy_idx ON public.library_inventory_events USING btree (copy_id, created_at DESC);

CREATE INDEX library_loans_copy_idx ON public.library_loans USING btree (copy_id);

CREATE INDEX library_loans_due_idx ON public.library_loans USING btree (due_date) WHERE ((status = 'issued'::text) AND (returned_at IS NULL));

CREATE INDEX library_loans_issued_by_idx ON public.library_loans USING btree (issued_by) WHERE (issued_by IS NOT NULL);

CREATE UNIQUE INDEX library_loans_one_active_per_copy_idx ON public.library_loans USING btree (copy_id) WHERE ((status = 'issued'::text) AND (returned_at IS NULL));

CREATE INDEX library_loans_returned_by_idx ON public.library_loans USING btree (returned_by) WHERE (returned_by IS NOT NULL);

CREATE INDEX library_loans_staff_idx ON public.library_loans USING btree (borrower_hr_staff_id, issued_at DESC) WHERE (borrower_hr_staff_id IS NOT NULL);

CREATE INDEX library_loans_student_idx ON public.library_loans USING btree (borrower_student_id, issued_at DESC) WHERE (borrower_student_id IS NOT NULL);

CREATE UNIQUE INDEX library_reservation_active_staff_unique ON public.library_reservations USING btree (book_id, borrower_hr_staff_id) WHERE ((borrower_hr_staff_id IS NOT NULL) AND (status = ANY (ARRAY['waiting'::text, 'ready'::text])));

CREATE UNIQUE INDEX library_reservation_active_student_unique ON public.library_reservations USING btree (book_id, borrower_student_id) WHERE ((borrower_student_id IS NOT NULL) AND (status = ANY (ARRAY['waiting'::text, 'ready'::text])));

CREATE INDEX library_reservations_book_idx ON public.library_reservations USING btree (book_id, status, reserved_at);

CREATE INDEX library_reservations_created_by_idx ON public.library_reservations USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX library_reservations_fulfilled_loan_idx ON public.library_reservations USING btree (fulfilled_loan_id) WHERE (fulfilled_loan_id IS NOT NULL);

CREATE INDEX library_reservations_staff_idx ON public.library_reservations USING btree (borrower_hr_staff_id, status) WHERE (borrower_hr_staff_id IS NOT NULL);

CREATE INDEX library_reservations_student_idx ON public.library_reservations USING btree (borrower_student_id, status) WHERE (borrower_student_id IS NOT NULL);

CREATE INDEX library_settings_created_by_idx ON public.library_settings USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE UNIQUE INDEX library_settings_singleton_idx ON public.library_settings USING btree ((true));

CREATE INDEX library_staff_access_appointed_by_idx ON public.library_staff_access USING btree (appointed_by) WHERE (appointed_by IS NOT NULL);

CREATE UNIQUE INDEX license_entitlement_overrides_one_active_idx ON public.license_entitlement_overrides USING btree (license_id) WHERE active;

CREATE INDEX license_events_created_idx ON public.license_events USING btree (created_at DESC);

CREATE INDEX license_verification_created_idx ON public.license_verification_logs USING btree (created_at DESC);

CREATE INDEX mfa_recovery_codes_user_active_idx ON public.mfa_recovery_codes USING btree (user_id, created_at DESC) WHERE (used_at IS NULL);

CREATE INDEX notification_outbox_recipient_idx ON public.notification_outbox USING btree (recipient_id);

CREATE INDEX notifications_recipient_idx ON public.notifications USING btree (recipient_id, read_at, created_at DESC);

CREATE UNIQUE INDEX one_active_academic_year_idx ON public.academic_years USING btree (is_active) WHERE (is_active AND (deleted_at IS NULL));

CREATE UNIQUE INDEX one_active_certificate_template_type_idx ON public.certificate_templates USING btree (certificate_type) WHERE active;

CREATE UNIQUE INDEX one_active_term_idx ON public.terms USING btree (is_active) WHERE (is_active AND (deleted_at IS NULL));

CREATE UNIQUE INDEX one_live_publication_per_report_idx ON public.report_publications USING btree (report_id) WHERE (revoked_at IS NULL);

CREATE INDEX outbox_lock_idx ON public.notification_outbox USING btree (locked_by, locked_at) WHERE (processed_at IS NULL);

CREATE INDEX outbox_pending_idx ON public.notification_outbox USING btree (next_attempt_at, locked_at) WHERE (processed_at IS NULL);

CREATE INDEX platform_access_locks_active_idx ON public.platform_access_locks USING btree (active, starts_at DESC, ends_at);

CREATE INDEX platform_package_artifacts_generated_idx ON public.platform_package_artifacts USING btree (generated_at DESC);

CREATE UNIQUE INDEX platform_package_artifacts_idempotency_idx ON public.platform_package_artifacts USING btree (idempotency_key) WHERE (idempotency_key <> ''::text);

CREATE UNIQUE INDEX platform_package_artifacts_installation_id_idx ON public.platform_package_artifacts USING btree (installation_id) WHERE (installation_id IS NOT NULL);

CREATE UNIQUE INDEX platform_package_artifacts_one_ready_replacement_idx ON public.platform_package_artifacts USING btree (supersedes_artifact_id) WHERE ((supersedes_artifact_id IS NOT NULL) AND (status = 'ready'::text) AND (deletion_state = 'none'::text));

CREATE UNIQUE INDEX platform_package_artifacts_package_id_idx ON public.platform_package_artifacts USING btree (package_id) WHERE (package_id IS NOT NULL);

CREATE INDEX platform_package_artifacts_supersedes_idx ON public.platform_package_artifacts USING btree (supersedes_artifact_id, generated_at DESC) WHERE (supersedes_artifact_id IS NOT NULL);

CREATE INDEX platform_package_artifacts_tenant_idx ON public.platform_package_artifacts USING btree (tenant_code, generated_at DESC);

CREATE INDEX platform_package_events_created_idx ON public.platform_package_events USING btree (created_at DESC);

CREATE UNIQUE INDEX platform_package_reconciliation_one_open_idx ON public.platform_package_reconciliation USING btree (artifact_id) WHERE ((artifact_id IS NOT NULL) AND (status = ANY (ARRAY['pending'::text, 'failed'::text])));

CREATE UNIQUE INDEX platform_package_templates_one_active_idx ON public.platform_package_templates USING btree (active) WHERE active;

CREATE INDEX profiles_role_idx ON public.profiles USING btree (role) WHERE active;

CREATE UNIQUE INDEX report_correction_one_pending_idx ON public.report_correction_requests USING btree (report_id) WHERE (status = 'pending'::text);

CREATE INDEX report_correction_status_created_idx ON public.report_correction_requests USING btree (status, created_at DESC);

CREATE UNIQUE INDEX report_number_unique_idx ON public.student_reports USING btree (report_number) WHERE (report_number IS NOT NULL);

CREATE INDEX reports_enrollment_idx ON public.student_reports USING btree (enrollment_id) WHERE (deleted_at IS NULL);

CREATE INDEX reports_term_status_idx ON public.student_reports USING btree (term_id, status) WHERE (deleted_at IS NULL);

CREATE INDEX revisions_report_idx ON public.report_revisions USING btree (report_id, version DESC);

CREATE UNIQUE INDEX school_licenses_singleton_idx ON public.school_licenses USING btree ((true));

CREATE INDEX school_prospectus_items_section_idx ON public.school_prospectus_items USING btree (section_id, display_order, id);

CREATE INDEX school_prospectus_revisions_parent_idx ON public.school_prospectus_revisions USING btree (prospectus_id, revision_no DESC);

CREATE INDEX school_prospectus_sections_parent_idx ON public.school_prospectus_sections USING btree (prospectus_id, display_order, id);

CREATE INDEX school_prospectuses_year_status_idx ON public.school_prospectuses USING btree (academic_year_id, status, class_range);

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

CREATE INDEX student_programme_enrollments_programme_idx ON public.student_programme_enrollments USING btree (programme_id, academic_year_id);

CREATE UNIQUE INDEX student_reports_active_enrollment_term_uidx ON public.student_reports USING btree (enrollment_id, term_id) WHERE (deleted_at IS NULL);

CREATE INDEX student_reports_deleted_idx ON public.student_reports USING btree (deleted_at, term_id);

CREATE INDEX student_services_events_actor_idx ON public.student_services_events USING btree (actor_id, occurred_at DESC);

CREATE INDEX student_services_events_domain_time_idx ON public.student_services_events USING btree (domain, occurred_at DESC);

CREATE INDEX student_services_events_entity_idx ON public.student_services_events USING btree (entity_type, entity_id, occurred_at DESC);

CREATE INDEX student_services_staff_appointed_by_idx ON public.student_services_staff_access USING btree (appointed_by);

CREATE INDEX student_services_staff_hr_idx ON public.student_services_staff_access USING btree (hr_staff_id, active);

CREATE INDEX student_services_staff_profile_idx ON public.student_services_staff_access USING btree (profile_id, active);

CREATE UNIQUE INDEX students_admission_no_ci_idx ON public.students USING btree (lower((admission_no)::text)) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX students_profile_id_unique ON public.students USING btree (profile_id) WHERE (profile_id IS NOT NULL);

CREATE INDEX students_search_idx ON public.students USING btree (lower(last_name), lower(first_name), admission_no) WHERE (deleted_at IS NULL);

CREATE INDEX subject_results_report_idx ON public.subject_results USING btree (report_id);

CREATE INDEX subject_results_scheme_idx ON public.subject_results USING btree (scheme_id) WHERE (scheme_id IS NOT NULL);

CREATE INDEX subject_results_subject_idx ON public.subject_results USING btree (subject_id);

CREATE INDEX subjects_active_idx ON public.subjects USING btree (display_order, name) WHERE (active AND (deleted_at IS NULL));

CREATE UNIQUE INDEX teacher_award_categories_code_idx ON public.teacher_award_categories USING btree (lower((code)::text));

CREATE UNIQUE INDEX teacher_award_categories_name_idx ON public.teacher_award_categories USING btree (lower(name));

CREATE UNIQUE INDEX teachers_emis_code_ci_idx ON public.teachers USING btree (lower((emis_code)::text)) WHERE ((emis_code IS NOT NULL) AND (btrim((emis_code)::text) <> ''::text) AND (deleted_at IS NULL));

CREATE INDEX teachers_name_search_idx ON public.teachers USING btree (lower(last_name), lower(first_name)) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX teachers_profile_active_idx ON public.teachers USING btree (profile_id) WHERE ((profile_id IS NOT NULL) AND (deleted_at IS NULL));

CREATE UNIQUE INDEX teachers_staff_no_ci_idx ON public.teachers USING btree (lower((staff_no)::text)) WHERE (deleted_at IS NULL);

CREATE INDEX teachers_status_idx ON public.teachers USING btree (employment_status, active) WHERE (deleted_at IS NULL);

CREATE INDEX terms_year_idx ON public.terms USING btree (academic_year_id) WHERE (deleted_at IS NULL);

CREATE INDEX tertiary_course_offerings_period_idx ON public.tertiary_course_offerings USING btree (academic_year_id, term_id);

CREATE INDEX tertiary_course_prerequisites_course_idx ON public.tertiary_course_prerequisites USING btree (course_id);

CREATE INDEX tertiary_course_registrations_student_idx ON public.tertiary_course_registrations USING btree (student_id, status);

CREATE INDEX tertiary_course_results_status_idx ON public.tertiary_course_results USING btree (result_status);

CREATE INDEX tertiary_degree_classifications_programme_idx ON public.tertiary_degree_classifications USING btree (programme_id, active, minimum_cgpa, maximum_cgpa);

CREATE UNIQUE INDEX transcript_issuances_transcript_number_key ON public.transcript_issuances USING btree (transcript_number) WHERE (transcript_number IS NOT NULL);

CREATE INDEX transcript_student_issued_idx ON public.transcript_issuances USING btree (student_id, issued_at DESC);

CREATE INDEX transport_assignments_alighting_stop_idx ON public.transport_student_assignments USING btree (alighting_stop_id);

CREATE INDEX transport_assignments_boarding_stop_idx ON public.transport_student_assignments USING btree (boarding_stop_id);

CREATE INDEX transport_assignments_created_by_idx ON public.transport_student_assignments USING btree (created_by);

CREATE INDEX transport_assignments_route_effective_idx ON public.transport_student_assignments USING btree (route_id, effective_from, effective_to) WHERE active;

CREATE INDEX transport_drivers_created_by_idx ON public.transport_drivers USING btree (created_by);

CREATE INDEX transport_incidents_created_by_idx ON public.transport_incidents USING btree (created_by);

CREATE INDEX transport_incidents_driver_idx ON public.transport_incidents USING btree (driver_id);

CREATE INDEX transport_incidents_resolved_by_idx ON public.transport_incidents USING btree (resolved_by);

CREATE INDEX transport_incidents_status_occurred_idx ON public.transport_incidents USING btree (status, occurred_at DESC);

CREATE INDEX transport_incidents_student_idx ON public.transport_incidents USING btree (student_id);

CREATE INDEX transport_incidents_trip_idx ON public.transport_incidents USING btree (trip_id);

CREATE INDEX transport_incidents_vehicle_idx ON public.transport_incidents USING btree (vehicle_id);

CREATE INDEX transport_maintenance_created_by_idx ON public.transport_maintenance_records USING btree (created_by);

CREATE INDEX transport_maintenance_vehicle_idx ON public.transport_maintenance_records USING btree (vehicle_id, service_date DESC);

CREATE INDEX transport_route_stops_created_by_idx ON public.transport_route_stops USING btree (created_by);

CREATE INDEX transport_route_stops_stop_idx ON public.transport_route_stops USING btree (stop_id);

CREATE INDEX transport_routes_active_service_idx ON public.transport_routes USING btree (active, service_type) WHERE (deleted_at IS NULL);

CREATE INDEX transport_routes_attendant_idx ON public.transport_routes USING btree (default_attendant_hr_staff_id);

CREATE INDEX transport_routes_created_by_idx ON public.transport_routes USING btree (created_by);

CREATE INDEX transport_routes_driver_idx ON public.transport_routes USING btree (default_driver_id);

CREATE INDEX transport_routes_vehicle_idx ON public.transport_routes USING btree (default_vehicle_id);

CREATE INDEX transport_settings_created_by_idx ON public.transport_settings USING btree (created_by);

CREATE UNIQUE INDEX transport_settings_singleton_idx ON public.transport_settings USING btree ((true));

CREATE INDEX transport_staff_access_appointed_by_idx ON public.transport_staff_access USING btree (appointed_by);

CREATE INDEX transport_stops_created_by_idx ON public.transport_stops USING btree (created_by);

CREATE UNIQUE INDEX transport_student_assignment_active_unique ON public.transport_student_assignments USING btree (student_id, route_id) WHERE (active AND (effective_to IS NULL));

CREATE INDEX transport_trip_students_alighted_by_idx ON public.transport_trip_students USING btree (alighted_by);

CREATE INDEX transport_trip_students_alighting_stop_idx ON public.transport_trip_students USING btree (alighting_stop_id);

CREATE INDEX transport_trip_students_assignment_idx ON public.transport_trip_students USING btree (assignment_id);

CREATE INDEX transport_trip_students_boarded_by_idx ON public.transport_trip_students USING btree (boarded_by);

CREATE INDEX transport_trip_students_boarding_stop_idx ON public.transport_trip_students USING btree (boarding_stop_id);

CREATE INDEX transport_trip_students_status_idx ON public.transport_trip_students USING btree (trip_id, status);

CREATE INDEX transport_trip_students_student_idx ON public.transport_trip_students USING btree (student_id, trip_id);

CREATE INDEX transport_trips_attendant_idx ON public.transport_trips USING btree (attendant_hr_staff_id);

CREATE INDEX transport_trips_completed_by_idx ON public.transport_trips USING btree (completed_by);

CREATE INDEX transport_trips_created_by_idx ON public.transport_trips USING btree (created_by);

CREATE INDEX transport_trips_driver_idx ON public.transport_trips USING btree (driver_id);

CREATE INDEX transport_trips_service_status_idx ON public.transport_trips USING btree (service_date, status, scheduled_departure);

CREATE INDEX transport_trips_started_by_idx ON public.transport_trips USING btree (started_by);

CREATE INDEX transport_trips_vehicle_idx ON public.transport_trips USING btree (vehicle_id);

CREATE INDEX transport_vehicles_created_by_idx ON public.transport_vehicles USING btree (created_by);

CREATE INDEX transport_vehicles_insurance_due_idx ON public.transport_vehicles USING btree (insurance_expiry) WHERE ((deleted_at IS NULL) AND active);

CREATE INDEX transport_vehicles_roadworthy_due_idx ON public.transport_vehicles USING btree (roadworthy_expiry) WHERE ((deleted_at IS NULL) AND active);

CREATE INDEX transport_vehicles_service_due_idx ON public.transport_vehicles USING btree (next_service_date) WHERE ((deleted_at IS NULL) AND active);

CREATE INDEX transport_vehicles_status_idx ON public.transport_vehicles USING btree (status, active) WHERE (deleted_at IS NULL);

CREATE INDEX user_class_access_class_idx ON public.user_class_access USING btree (class_id);

CREATE UNIQUE INDEX user_class_access_class_scope_idx ON public.user_class_access USING btree (user_id, class_id) WHERE (subject_id IS NULL);

CREATE INDEX user_class_access_subject_idx ON public.user_class_access USING btree (subject_id) WHERE (subject_id IS NOT NULL);

CREATE UNIQUE INDEX user_class_access_subject_scope_idx ON public.user_class_access USING btree (user_id, class_id, subject_id) WHERE (subject_id IS NOT NULL);

CREATE INDEX user_class_access_user_idx ON public.user_class_access USING btree (user_id, class_id);

CREATE INDEX welfare_cases_assigned_idx ON public.welfare_cases USING btree (assigned_hr_staff_id, status);

CREATE INDEX welfare_cases_closed_by_idx ON public.welfare_cases USING btree (closed_by);

CREATE INDEX welfare_cases_opened_by_idx ON public.welfare_cases USING btree (opened_by);

CREATE INDEX welfare_cases_status_idx ON public.welfare_cases USING btree (status, priority, opened_at DESC);

CREATE INDEX welfare_cases_student_idx ON public.welfare_cases USING btree (student_id, opened_at DESC);

CREATE INDEX welfare_notes_case_idx ON public.welfare_case_notes USING btree (case_id, created_at DESC);

CREATE INDEX welfare_notes_created_by_idx ON public.welfare_case_notes USING btree (created_by);

CREATE INDEX workflow_report_idx ON public.report_workflow_events USING btree (report_id, created_at DESC);

CREATE OR REPLACE VIEW public.finance_fee_account_balances AS  SELECT a.id,
    a.student_id,
    a.enrollment_id,
    a.academic_year_id,
    a.term_id,
    a.class_id,
    a.schedule_id,
    a.term_fee_amount,
    COALESCE(s.due_date, t.end_date) AS due_date,
    COALESCE(sum(
        CASE
            WHEN tx.debit_amount > 0::numeric THEN al.amount
            ELSE 0::numeric
        END), 0::numeric)::numeric(14,2) AS debit_adjustments,
    COALESCE(sum(
        CASE
            WHEN tx.credit_amount > 0::numeric THEN al.amount
            ELSE 0::numeric
        END), 0::numeric)::numeric(14,2) AS credit_adjustments,
    COALESCE(sum(
        CASE
            WHEN tx.entry_type = 'payment'::text THEN al.amount
            WHEN tx.entry_type = 'payment_reversal'::text THEN - al.amount
            ELSE 0::numeric
        END), 0::numeric)::numeric(14,2) AS amount_paid,
    (a.term_fee_amount + COALESCE(sum(
        CASE
            WHEN tx.debit_amount > 0::numeric THEN al.amount
            ELSE - al.amount
        END), 0::numeric))::numeric(14,2) AS balance,
        CASE
            WHEN (a.term_fee_amount + COALESCE(sum(
            CASE
                WHEN tx.debit_amount > 0::numeric THEN al.amount
                ELSE - al.amount
            END), 0::numeric)) < 0::numeric THEN 'credit'::text
            WHEN (a.term_fee_amount + COALESCE(sum(
            CASE
                WHEN tx.debit_amount > 0::numeric THEN al.amount
                ELSE - al.amount
            END), 0::numeric)) = 0::numeric THEN 'fully_paid'::text
            WHEN COALESCE(sum(
            CASE
                WHEN tx.credit_amount > 0::numeric THEN al.amount
                ELSE 0::numeric
            END), 0::numeric) = 0::numeric THEN 'unpaid'::text
            ELSE 'partial_paid'::text
        END AS status,
    (a.term_fee_amount + COALESCE(sum(
        CASE
            WHEN tx.debit_amount > 0::numeric THEN al.amount
            ELSE - al.amount
        END), 0::numeric)) > 0::numeric AS balance_remaining,
    a.created_at
   FROM finance_fee_accounts a
     JOIN terms t ON t.id = a.term_id
     LEFT JOIN finance_fee_schedules s ON s.id = a.schedule_id
     LEFT JOIN finance_fee_allocations al ON al.account_id = a.id
     LEFT JOIN finance_fee_transactions tx ON tx.id = al.transaction_id
  GROUP BY a.id, s.due_date, t.end_date;

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
