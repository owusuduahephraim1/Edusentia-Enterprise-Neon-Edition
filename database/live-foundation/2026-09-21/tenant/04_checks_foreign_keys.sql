-- Edusentia tenant foundation: checks and foreign keys
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

ALTER TABLE ONLY public.academic_levels ADD CONSTRAINT academic_levels_order_chk CHECK (level_order > 0);

ALTER TABLE ONLY public.academic_levels ADD CONSTRAINT academic_levels_scope_chk CHECK (institution_scope = ANY (ARRAY['senior_high'::text, 'tertiary'::text]));

ALTER TABLE ONLY public.academic_programmes ADD CONSTRAINT academic_programmes_duration_chk CHECK (duration_years IS NULL OR duration_years > 0::numeric AND duration_years <= 12::numeric);

ALTER TABLE ONLY public.academic_programmes ADD CONSTRAINT academic_programmes_scope_chk CHECK (institution_scope = ANY (ARRAY['senior_high'::text, 'tertiary'::text]));

ALTER TABLE ONLY public.academic_years ADD CONSTRAINT academic_year_dates_chk CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date);

ALTER TABLE ONLY public.accounts_office_staff ADD CONSTRAINT accounts_office_staff_finance_role_check CHECK (finance_role = ANY (ARRAY['cashier'::text, 'accounts_officer'::text, 'accountant'::text, 'payroll_officer'::text, 'finance_manager'::text]));

ALTER TABLE ONLY public.accounts_office_staff ADD CONSTRAINT accounts_office_staff_finance_role_ck CHECK (finance_role = ANY (ARRAY['cashier'::text, 'accounts_officer'::text, 'accountant'::text, 'payroll_officer'::text, 'finance_manager'::text]));

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_gender_check CHECK (gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text]));

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_source_check CHECK (source = ANY (ARRAY['school_entry'::text, 'online'::text, 'import'::text, 'referral'::text]));

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_status_check CHECK (status = ANY (ARRAY['draft'::text, 'submitted'::text, 'under_review'::text, 'waitlisted'::text, 'offered'::text, 'accepted'::text, 'rejected'::text, 'withdrawn'::text, 'enrolled'::text, 'not_enrolled'::text]));

ALTER TABLE ONLY public.admissions_documents ADD CONSTRAINT admissions_documents_verification_status_check CHECK (verification_status = ANY (ARRAY['pending'::text, 'verified'::text, 'rejected'::text, 'not_required'::text]));

ALTER TABLE ONLY public.admissions_offers ADD CONSTRAINT admissions_offers_status_check CHECK (status = ANY (ARRAY['offered'::text, 'accepted'::text, 'declined'::text, 'expired'::text, 'withdrawn'::text, 'enrolled'::text]));

ALTER TABLE ONLY public.alumni_engagements ADD CONSTRAINT alumni_engagements_engagement_type_check CHECK (engagement_type = ANY (ARRAY['contact'::text, 'event'::text, 'mentorship'::text, 'volunteering'::text, 'career_talk'::text, 'donation_reference'::text, 'fundraising'::text, 'other'::text]));

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_status_check CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text, 'lost_contact'::text, 'deceased'::text]));

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_verification_status_check CHECK (verification_status = ANY (ARRAY['unverified'::text, 'verified'::text, 'needs_review'::text]));

ALTER TABLE ONLY public.alumni_verification_requests ADD CONSTRAINT alumni_verification_requests_request_type_check CHECK (request_type = ANY (ARRAY['graduation'::text, 'enrolment'::text, 'identity'::text, 'reference'::text, 'transcript'::text, 'other'::text]));

ALTER TABLE ONLY public.alumni_verification_requests ADD CONSTRAINT alumni_verification_requests_status_check CHECK (status = ANY (ARRAY['pending'::text, 'under_review'::text, 'verified'::text, 'declined'::text, 'cancelled'::text]));

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

ALTER TABLE ONLY public.client_error_events ADD CONSTRAINT client_error_events_occurrence_count_check CHECK (occurrence_count > 0);

ALTER TABLE ONLY public.client_error_events ADD CONSTRAINT client_error_events_severity_check CHECK (severity = ANY (ARRAY['warning'::text, 'error'::text, 'critical'::text]));

ALTER TABLE ONLY public.client_error_events ADD CONSTRAINT client_error_events_status_check CHECK (status = ANY (ARRAY['open'::text, 'resolved'::text, 'ignored'::text]));

ALTER TABLE ONLY public.communication_campaigns ADD CONSTRAINT communication_campaigns_audience_type_check CHECK (audience_type = ANY (ARRAY['all_staff'::text, 'all_students'::text, 'all_guardians'::text, 'class_students'::text, 'class_guardians'::text, 'selected_profiles'::text]));

ALTER TABLE ONLY public.communication_campaigns ADD CONSTRAINT communication_campaigns_channels_check CHECK (channels <@ ARRAY['in_app'::text, 'email'::text, 'sms'::text, 'push'::text] AND cardinality(channels) > 0);

ALTER TABLE ONLY public.communication_campaigns ADD CONSTRAINT communication_campaigns_check CHECK ((audience_type = ANY (ARRAY['class_students'::text, 'class_guardians'::text])) AND audience_class_id IS NOT NULL OR (audience_type <> ALL (ARRAY['class_students'::text, 'class_guardians'::text])));

ALTER TABLE ONLY public.communication_campaigns ADD CONSTRAINT communication_campaigns_status_check CHECK (status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'published'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.communication_deliveries ADD CONSTRAINT communication_deliveries_channel_check CHECK (channel = ANY (ARRAY['in_app'::text, 'email'::text, 'sms'::text, 'push'::text]));

ALTER TABLE ONLY public.communication_deliveries ADD CONSTRAINT communication_deliveries_status_check CHECK (status = ANY (ARRAY['queued'::text, 'sent'::text, 'failed'::text, 'skipped'::text]));

ALTER TABLE ONLY public.communication_thread_participants ADD CONSTRAINT communication_thread_participants_participant_role_check CHECK (participant_role = ANY (ARRAY['owner'::text, 'member'::text]));

ALTER TABLE ONLY public.communication_threads ADD CONSTRAINT communication_threads_status_check CHECK (status = ANY (ARRAY['open'::text, 'closed'::text, 'archived'::text]));

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_disposition_action_check CHECK (disposition_action = ANY (ARRAY['review'::text, 'archive'::text, 'anonymise'::text, 'delete'::text]));

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_retention_years_check CHECK (retention_years IS NULL OR retention_years >= 1 AND retention_years <= 100);

ALTER TABLE ONLY public.discipline_actions ADD CONSTRAINT discipline_actions_action_type_check CHECK (action_type = ANY (ARRAY['merit'::text, 'demerit'::text, 'warning'::text, 'detention'::text, 'suspension'::text, 'counselling'::text, 'parent_contact'::text, 'referral'::text, 'restorative_action'::text, 'other'::text]));

ALTER TABLE ONLY public.discipline_actions ADD CONSTRAINT discipline_actions_status_check CHECK (status = ANY (ARRAY['planned'::text, 'active'::text, 'completed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.discipline_incidents ADD CONSTRAINT discipline_incidents_severity_check CHECK (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]));

ALTER TABLE ONLY public.discipline_incidents ADD CONSTRAINT discipline_incidents_status_check CHECK (status = ANY (ARRAY['open'::text, 'under_review'::text, 'resolved'::text, 'referred'::text, 'cancelled'::text]));

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

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_term_fee_amount_check CHECK (term_fee_amount >= 0::numeric);

ALTER TABLE ONLY public.finance_fee_allocations ADD CONSTRAINT finance_fee_allocations_amount_check CHECK (amount > 0::numeric);

ALTER TABLE ONLY public.finance_fee_groups ADD CONSTRAINT finance_fee_groups_code_check CHECK (code ~ '^[a-z0-9_]+$'::text);

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_issued_amount_check CHECK (issued_amount >= 0::numeric);

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_amount_check CHECK (amount >= 0::numeric);

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_check CHECK (debit_amount > 0::numeric AND credit_amount = 0::numeric OR credit_amount > 0::numeric AND debit_amount = 0::numeric);

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_credit_amount_check CHECK (credit_amount >= 0::numeric);

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_debit_amount_check CHECK (debit_amount >= 0::numeric);

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_entry_type_check CHECK (entry_type = ANY (ARRAY['payment'::text, 'payment_reversal'::text, 'waiver'::text, 'discount'::text, 'refund'::text, 'adjustment_debit'::text, 'adjustment_credit'::text]));

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_payment_method_check CHECK (payment_method IS NULL OR (payment_method = ANY (ARRAY['cash'::text, 'bank_transfer'::text, 'mobile_money'::text, 'cheque'::text, 'card'::text, 'other'::text])));

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_receipt_semantics_ck CHECK (entry_type = 'payment'::text AND receipt_no IS NOT NULL OR entry_type <> 'payment'::text AND receipt_no IS NULL);

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_reversal_semantics_ck CHECK (entry_type = 'payment_reversal'::text AND reversal_of_id IS NOT NULL OR entry_type <> 'payment_reversal'::text AND reversal_of_id IS NULL);

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_action_state_check CHECK (action_state = ANY (ARRAY['opened'::text, 'copied'::text]));

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_channel_check CHECK (channel = ANY (ARRAY['sms'::text, 'whatsapp'::text, 'call'::text, 'copy'::text]));

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_child_count_check CHECK (child_count >= 0);

ALTER TABLE ONLY public.finance_hold_overrides ADD CONSTRAINT finance_hold_overrides_check CHECK (ends_at IS NULL OR ends_at > starts_at);

ALTER TABLE ONLY public.finance_hold_overrides ADD CONSTRAINT finance_hold_overrides_mode_check CHECK (mode = ANY (ARRAY['force_lock'::text, 'force_unlock'::text]));

ALTER TABLE ONLY public.finance_hold_policy ADD CONSTRAINT finance_hold_policy_grace_days_check CHECK (grace_days >= 0 AND grace_days <= 365);

ALTER TABLE ONLY public.finance_hold_policy ADD CONSTRAINT finance_hold_policy_id_check CHECK (id = 1);

ALTER TABLE ONLY public.finance_hold_policy ADD CONSTRAINT finance_hold_policy_minimum_outstanding_check CHECK (minimum_outstanding >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_item_lines ADD CONSTRAINT finance_payroll_item_lines_amount_check CHECK (amount >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_item_lines ADD CONSTRAINT finance_payroll_item_lines_line_type_check CHECK (line_type = ANY (ARRAY['allowance'::text, 'deduction'::text, 'ssnit'::text, 'tax'::text, 'loan'::text]));

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_allowances_check CHECK (allowances >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_basic_salary_check CHECK (basic_salary >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_gross_salary_check CHECK (gross_salary >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_loan_deductions_check CHECK (loan_deductions >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_net_salary_check CHECK (net_salary >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_other_deductions_check CHECK (other_deductions >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_payment_status_check CHECK (payment_status = ANY (ARRAY['unpaid'::text, 'paid'::text, 'reversed'::text]));

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_ssnit_employee_check CHECK (ssnit_employee >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_tax_amount_check CHECK (tax_amount >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_total_deductions_check CHECK (total_deductions >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_basic_salary_override_check CHECK (basic_salary_override IS NULL OR basic_salary_override >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_rules ADD CONSTRAINT finance_payroll_rules_check CHECK (effective_to IS NULL OR effective_to >= effective_from);

ALTER TABLE ONLY public.finance_payroll_rules ADD CONSTRAINT finance_payroll_rules_fixed_amount_check CHECK (fixed_amount IS NULL OR fixed_amount >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_rules ADD CONSTRAINT finance_payroll_rules_rate_check CHECK (rate IS NULL OR rate >= 0::numeric);

ALTER TABLE ONLY public.finance_payroll_rules ADD CONSTRAINT finance_payroll_rules_rule_type_check CHECK (rule_type = ANY (ARRAY['ssnit_employee'::text, 'ssnit_employer'::text, 'tax'::text, 'allowance'::text, 'deduction'::text]));

ALTER TABLE ONLY public.finance_payroll_runs ADD CONSTRAINT finance_payroll_runs_payroll_month_check CHECK (payroll_month >= 1 AND payroll_month <= 12);

ALTER TABLE ONLY public.finance_payroll_runs ADD CONSTRAINT finance_payroll_runs_payroll_year_check CHECK (payroll_year >= 2000 AND payroll_year <= 2200);

ALTER TABLE ONLY public.finance_payroll_runs ADD CONSTRAINT finance_payroll_runs_status_check CHECK (status = ANY (ARRAY['draft'::text, 'calculated'::text, 'approved'::text, 'paid'::text, 'locked'::text]));

ALTER TABLE ONLY public.finance_salary_grades ADD CONSTRAINT finance_salary_grades_basic_salary_check CHECK (basic_salary >= 0::numeric);

ALTER TABLE ONLY public.finance_teacher_loans ADD CONSTRAINT finance_teacher_loans_monthly_deduction_check CHECK (monthly_deduction > 0::numeric);

ALTER TABLE ONLY public.finance_teacher_loans ADD CONSTRAINT finance_teacher_loans_principal_amount_check CHECK (principal_amount > 0::numeric);

ALTER TABLE ONLY public.finance_teacher_loans ADD CONSTRAINT finance_teacher_loans_status_check CHECK (status = ANY (ARRAY['active'::text, 'settled'::text, 'suspended'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scale_range_chk CHECK (min_mark <= max_mark);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_interpretation_length CHECK (char_length(interpretation) <= 180);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_max_mark_check CHECK (max_mark >= 0::numeric AND max_mark <= 100::numeric);

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_min_mark_check CHECK (min_mark >= 0::numeric AND min_mark <= 100::numeric);

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_employment_status_check CHECK (employment_status = ANY (ARRAY['active'::text, 'leave'::text, 'suspended'::text, 'resigned'::text, 'retired'::text]));

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_gender_check CHECK (gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text]));

ALTER TABLE ONLY public.health_immunizations ADD CONSTRAINT health_immunizations_status_check CHECK (status = ANY (ARRAY['recorded'::text, 'due'::text, 'overdue'::text, 'declined'::text, 'not_required'::text]));

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_disposition_check CHECK (disposition = ANY (ARRAY['returned_to_class'::text, 'sent_home'::text, 'referred'::text, 'emergency_transfer'::text, 'observation'::text, 'other'::text]));

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_pulse_bpm_check CHECK (pulse_bpm IS NULL OR pulse_bpm >= 20 AND pulse_bpm <= 250);

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_status_check CHECK (status = ANY (ARRAY['open'::text, 'observation'::text, 'completed'::text, 'referred'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_temperature_c_check CHECK (temperature_c IS NULL OR temperature_c >= 30::numeric AND temperature_c <= 45::numeric);

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_boarding_type_check CHECK (boarding_type = ANY (ARRAY['full_boarding'::text, 'weekly_boarding'::text, 'temporary'::text]));

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_status_check CHECK (status = ANY (ARRAY['active'::text, 'ended'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.hostel_beds ADD CONSTRAINT hostel_beds_status_check CHECK (status = ANY (ARRAY['available'::text, 'occupied'::text, 'maintenance'::text, 'inactive'::text]));

ALTER TABLE ONLY public.hostel_houses ADD CONSTRAINT hostel_houses_capacity_check CHECK (capacity IS NULL OR capacity > 0);

ALTER TABLE ONLY public.hostel_houses ADD CONSTRAINT hostel_houses_gender_policy_check CHECK (gender_policy = ANY (ARRAY['male'::text, 'female'::text, 'mixed'::text]));

ALTER TABLE ONLY public.hostel_incidents ADD CONSTRAINT hostel_incidents_severity_check CHECK (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]));

ALTER TABLE ONLY public.hostel_incidents ADD CONSTRAINT hostel_incidents_status_check CHECK (status = ANY (ARRAY['open'::text, 'under_review'::text, 'resolved'::text, 'referred'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.hostel_movements ADD CONSTRAINT hostel_movements_movement_type_check CHECK (movement_type = ANY (ARRAY['check_in'::text, 'check_out'::text, 'weekend_leave'::text, 'return_from_leave'::text, 'temporary_exit'::text, 'return'::text, 'other'::text]));

ALTER TABLE ONLY public.hostel_rooms ADD CONSTRAINT hostel_rooms_capacity_check CHECK (capacity > 0);

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_request_dates_ck CHECK (end_date >= start_date);

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_request_days_ck CHECK (days > 0::numeric);

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_leave_type_check CHECK (leave_type = ANY (ARRAY['annual'::text, 'sick'::text, 'maternity'::text, 'paternity'::text, 'study'::text, 'compassionate'::text, 'unpaid'::text, 'official_duty'::text, 'other'::text]));

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.hr_staff_documents ADD CONSTRAINT hr_staff_document_dates_ck CHECK (expires_on IS NULL OR issued_on IS NULL OR expires_on >= issued_on);

ALTER TABLE ONLY public.hr_staff_documents ADD CONSTRAINT hr_staff_documents_verification_status_check CHECK (verification_status = ANY (ARRAY['unverified'::text, 'verified'::text, 'rejected'::text, 'expired'::text]));

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_dates_ck CHECK (date_ended IS NULL OR date_joined IS NULL OR date_ended >= date_joined);

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_employment_status_check CHECK (employment_status = ANY (ARRAY['active'::text, 'probation'::text, 'leave'::text, 'suspended'::text, 'resigned'::text, 'terminated'::text, 'retired'::text, 'inactive'::text]));

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_employment_type_check CHECK (employment_type = ANY (ARRAY['permanent'::text, 'contract'::text, 'temporary'::text, 'part_time'::text, 'intern'::text, 'volunteer'::text, 'other'::text]));

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_source_type_check CHECK (source_type = ANY (ARRAY['teacher'::text, 'principal'::text, 'accounts_office'::text, 'other'::text]));

ALTER TABLE ONLY public.hr_staff_qualifications ADD CONSTRAINT hr_staff_qualification_dates_ck CHECK (expires_on IS NULL OR awarded_on IS NULL OR expires_on >= awarded_on);

ALTER TABLE ONLY public.hr_staff_qualifications ADD CONSTRAINT hr_staff_qualifications_verification_status_check CHECK (verification_status = ANY (ARRAY['unverified'::text, 'verified'::text, 'rejected'::text, 'expired'::text]));

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_card_kind_check CHECK (card_kind = ANY (ARRAY['student'::text, 'staff'::text]));

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_staff_validity_check CHECK (staff_validity_months >= 1 AND staff_validity_months <= 60);

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_template_code_check CHECK (template_code = ANY (ARRAY['classic'::text, 'modern'::text, 'minimal'::text]));

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_validity_months_check CHECK (validity_months >= 1 AND validity_months <= 60);

ALTER TABLE ONLY public.import_batches ADD CONSTRAINT import_batches_status_check CHECK (status = ANY (ARRAY['processing'::text, 'completed'::text, 'completed_with_errors'::text, 'failed'::text]));

ALTER TABLE ONLY public.inventory_asset_assignments ADD CONSTRAINT inventory_asset_assignment_due_ck CHECK (due_on IS NULL OR due_on >= assigned_on);

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_cost_check CHECK (cost IS NULL OR cost >= 0::numeric);

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_dates_ck CHECK (completed_on IS NULL OR completed_on >= opened_on);

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_maintenance_type_check CHECK (maintenance_type = ANY (ARRAY['preventive'::text, 'repair'::text, 'inspection'::text, 'calibration'::text, 'other'::text]));

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_status_check CHECK (status = ANY (ARRAY['open'::text, 'completed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.inventory_asset_writeoffs ADD CONSTRAINT inventory_asset_writeoffs_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_asset_disposal_ck CHECK (asset_status = 'disposed'::text AND disposed_on IS NOT NULL OR asset_status <> 'disposed'::text);

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_asset_condition_check CHECK (asset_condition = ANY (ARRAY['new'::text, 'good'::text, 'fair'::text, 'poor'::text, 'damaged'::text]));

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_asset_status_check CHECK (asset_status = ANY (ARRAY['available'::text, 'assigned'::text, 'maintenance'::text, 'lost'::text, 'retired'::text, 'disposed'::text]));

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_purchase_cost_check CHECK (purchase_cost IS NULL OR purchase_cost >= 0::numeric);

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_quantity_received_check CHECK (quantity_received > 0::numeric);

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_unit_cost_check CHECK (unit_cost >= 0::numeric);

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_quantity_check CHECK (quantity > 0::numeric);

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'fulfilled'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_estimated_unit_cost_check CHECK (estimated_unit_cost IS NULL OR estimated_unit_cost >= 0::numeric);

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_item_type_check CHECK (item_type = ANY (ARRAY['consumable'::text, 'asset'::text]));

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_reorder_level_check CHECK (reorder_level >= 0::numeric);

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_reorder_quantity_check CHECK (reorder_quantity > 0::numeric);

ALTER TABLE ONLY public.inventory_locations ADD CONSTRAINT inventory_locations_location_type_check CHECK (location_type = ANY (ARRAY['store'::text, 'warehouse'::text, 'office'::text, 'classroom'::text, 'laboratory'::text, 'library'::text, 'workshop'::text, 'other'::text]));

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_po_line_received_ck CHECK (quantity_received <= quantity_ordered);

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_purchase_order_lines_quantity_ordered_check CHECK (quantity_ordered > 0::numeric);

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_purchase_order_lines_quantity_received_check CHECK (quantity_received >= 0::numeric);

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_purchase_order_lines_unit_cost_check CHECK (unit_cost >= 0::numeric);

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_order_dates_ck CHECK (expected_date IS NULL OR expected_date >= order_date);

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_orders_status_check CHECK (status = ANY (ARRAY['draft'::text, 'approved'::text, 'rejected'::text, 'partially_received'::text, 'received'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.inventory_purchase_request_lines ADD CONSTRAINT inventory_purchase_request_lines_estimated_unit_cost_check CHECK (estimated_unit_cost IS NULL OR estimated_unit_cost >= 0::numeric);

ALTER TABLE ONLY public.inventory_purchase_request_lines ADD CONSTRAINT inventory_purchase_request_lines_quantity_check CHECK (quantity > 0::numeric);

ALTER TABLE ONLY public.inventory_purchase_requests ADD CONSTRAINT inventory_purchase_requests_status_check CHECK (status = ANY (ARRAY['submitted'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text, 'converted'::text]));

ALTER TABLE ONLY public.inventory_settings ADD CONSTRAINT inventory_settings_asset_maintenance_alert_days_check CHECK (asset_maintenance_alert_days >= 1 AND asset_maintenance_alert_days <= 365);

ALTER TABLE ONLY public.inventory_settings ADD CONSTRAINT inventory_settings_default_reorder_level_check CHECK (default_reorder_level >= 0::numeric);

ALTER TABLE ONLY public.inventory_settings ADD CONSTRAINT inventory_settings_default_reorder_quantity_check CHECK (default_reorder_quantity > 0::numeric);

ALTER TABLE ONLY public.inventory_settings ADD CONSTRAINT inventory_settings_singleton_key_check CHECK (singleton_key = 'default'::text);

ALTER TABLE ONLY public.inventory_staff_access ADD CONSTRAINT inventory_staff_access_access_role_check CHECK (access_role = ANY (ARRAY['inventory_manager'::text, 'procurement_officer'::text, 'storekeeper'::text, 'asset_officer'::text, 'inventory_auditor'::text]));

ALTER TABLE ONLY public.inventory_staff_access ADD CONSTRAINT inventory_staff_access_profile_staff_ck CHECK (profile_id IS NOT NULL);

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_movement_type_check CHECK (movement_type = ANY (ARRAY['opening'::text, 'receipt'::text, 'issue'::text, 'return'::text, 'adjust_in'::text, 'adjust_out'::text, 'transfer_in'::text, 'transfer_out'::text]));

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_quantity_delta_check CHECK (quantity_delta <> 0::numeric);

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_unit_cost_check CHECK (unit_cost IS NULL OR unit_cost >= 0::numeric);

ALTER TABLE ONLY public.library_books ADD CONSTRAINT library_books_publication_year_check CHECK (publication_year IS NULL OR publication_year >= 1000 AND publication_year <= 2200);

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_acquisition_cost_check CHECK (acquisition_cost IS NULL OR acquisition_cost >= 0::numeric);

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_circulation_status_check CHECK (circulation_status = ANY (ARRAY['available'::text, 'on_loan'::text, 'reserved'::text, 'lost'::text, 'damaged'::text, 'repair'::text, 'withdrawn'::text]));

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_condition_status_check CHECK (condition_status = ANY (ARRAY['new'::text, 'good'::text, 'fair'::text, 'poor'::text, 'damaged'::text]));

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_borrower_ck CHECK (borrower_type = 'student'::text AND borrower_student_id IS NOT NULL AND borrower_hr_staff_id IS NULL OR borrower_type = 'staff'::text AND borrower_hr_staff_id IS NOT NULL AND borrower_student_id IS NULL);

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_borrower_type_check CHECK (borrower_type = ANY (ARRAY['student'::text, 'staff'::text]));

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_renew_count_check CHECK (renew_count >= 0);

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_status_check CHECK (status = ANY (ARRAY['issued'::text, 'returned'::text, 'lost'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_borrower_ck CHECK (borrower_type = 'student'::text AND borrower_student_id IS NOT NULL AND borrower_hr_staff_id IS NULL OR borrower_type = 'staff'::text AND borrower_hr_staff_id IS NOT NULL AND borrower_student_id IS NULL);

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_borrower_type_check CHECK (borrower_type = ANY (ARRAY['student'::text, 'staff'::text]));

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_status_check CHECK (status = ANY (ARRAY['waiting'::text, 'ready'::text, 'fulfilled'::text, 'cancelled'::text, 'expired'::text]));

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_max_renewals_check CHECK (max_renewals >= 0 AND max_renewals <= 10);

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_overdue_grace_days_check CHECK (overdue_grace_days >= 0 AND overdue_grace_days <= 30);

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_renewal_days_check CHECK (renewal_days >= 1 AND renewal_days <= 90);

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_staff_loan_days_check CHECK (staff_loan_days >= 1 AND staff_loan_days <= 365);

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_staff_max_loans_check CHECK (staff_max_loans >= 1 AND staff_max_loans <= 100);

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_student_loan_days_check CHECK (student_loan_days >= 1 AND student_loan_days <= 180);

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_student_max_loans_check CHECK (student_max_loans >= 1 AND student_max_loans <= 50);

ALTER TABLE ONLY public.library_staff_access ADD CONSTRAINT library_staff_access_library_role_check CHECK (library_role = ANY (ARRAY['librarian'::text, 'assistant'::text]));

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

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_request_details_check CHECK (length(btrim(request_details)) >= 10);

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_request_type_check CHECK (request_type = ANY (ARRAY['access'::text, 'correction'::text, 'export'::text, 'restriction'::text, 'anonymisation'::text, 'deletion'::text, 'consent_review'::text]));

ALTER TABLE ONLY public.privacy_requests ADD CONSTRAINT privacy_requests_status_check CHECK (status = ANY (ARRAY['open'::text, 'in_review'::text, 'approved'::text, 'rejected'::text, 'completed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.profiles ADD CONSTRAINT profiles_privileged_mfa_required CHECK ((current_app_role_for(role) <> ALL (ARRAY['system_admin'::text, 'platform_super_admin'::text])) OR mfa_required);

ALTER TABLE ONLY public.recovery_test_runs ADD CONSTRAINT recovery_test_runs_status_check CHECK (status = ANY (ARRAY['processing'::text, 'passed'::text, 'failed'::text]));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_mime_chk CHECK (mime_type = ANY (ARRAY['application/pdf'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text]));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_path_chk CHECK (storage_path ~~ (range_key || '/%'::text));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_range_chk CHECK (range_key = ANY (ARRAY['early_years'::text, 'basic_1_6'::text, 'basic_7_9'::text]));

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_size_chk CHECK (file_size > 0 AND file_size <= 20971520);

ALTER TABLE ONLY public.report_card_templates ADD CONSTRAINT report_card_templates_version_chk CHECK (version > 0);

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_reason_check CHECK (length(btrim(reason)) >= 10);

ALTER TABLE ONLY public.report_correction_requests ADD CONSTRAINT report_correction_requests_status_check CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text, 'applied'::text]));

ALTER TABLE ONLY public.report_publications ADD CONSTRAINT report_publications_page_count_check CHECK (page_count > 0);

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

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_package_size_check CHECK (package_size >= 0);

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_status_check CHECK (status = ANY (ARRAY['upload_pending'::text, 'uploaded'::text, 'validating'::text, 'restoring'::text, 'completed'::text, 'failed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_row_count_check CHECK (row_count >= 0);

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_rows_check CHECK (jsonb_typeof(rows) = 'array'::text);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_academic_period_model_chk CHECK (academic_period_model = ANY (ARRAY['term'::text, 'semester'::text, 'trimester'::text, 'quarter'::text]));

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_backup_minimum_copies_chk CHECK (backup_minimum_copies >= 2 AND backup_minimum_copies <= 90);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_backup_retention_chk CHECK (backup_retention_days >= 7 AND backup_retention_days <= 365);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_identifier_root_chk CHECK (identifier_root ~ '^[A-Z]{3}[0-9]{6}$'::text);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_institution_type_chk CHECK (institution_type = ANY (ARRAY['basic_jhs'::text, 'senior_high'::text, 'combined_pretertiary'::text, 'tertiary'::text]));

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_promotion_cutoff_score_chk CHECK (promotion_cutoff_score >= 40 AND promotion_cutoff_score <= 60);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_report_body_font_chk CHECK (report_body_font = ANY (ARRAY['Times New Roman'::text, 'Arial'::text, 'Calibri'::text, 'Georgia'::text, 'Verdana'::text, 'Tahoma'::text]));

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_report_body_font_size_chk CHECK (report_body_font_size >= 8.0 AND report_body_font_size <= 16.0);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_runtime_release_counts_chk CHECK (runtime_release_migration_count >= 0 AND runtime_release_edge_function_count >= 0);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_runtime_release_manifest_chk CHECK (runtime_release_manifest_sha256 = ''::text OR runtime_release_manifest_sha256 ~ '^[a-f0-9]{64}$'::text);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_tenant_code_chk CHECK (tenant_code ~ '^[A-Z]{3}-[0-9]{6}$'::text);

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_user_email_domain_chk CHECK (user_email_domain ~ '^(?:[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.)+[a-z]{2,63}$'::text);

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_severity_check CHECK (severity = ANY (ARRAY['info'::text, 'warning'::text, 'high'::text, 'critical'::text]));

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_status_check CHECK (status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'false_positive'::text]));

ALTER TABLE ONLY public.security_verification_runs ADD CONSTRAINT security_verification_runs_status_check CHECK (status = ANY (ARRAY['planned'::text, 'in_progress'::text, 'passed'::text, 'passed_with_findings'::text, 'failed'::text]));

ALTER TABLE ONLY public.shs_programme_subjects ADD CONSTRAINT shs_programme_subject_category_chk CHECK (subject_category = ANY (ARRAY['core'::text, 'elective'::text, 'optional'::text]));

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

ALTER TABLE ONLY public.student_programme_enrollments ADD CONSTRAINT student_programme_enrollments_status_chk CHECK (status = ANY (ARRAY['active'::text, 'completed'::text, 'withdrawn'::text, 'deferred'::text, 'suspended'::text]));

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT report_attendance_chk CHECK (days_present <= days_school_opened);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_days_present_check CHECK (days_present >= 0);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_days_school_opened_check CHECK (days_school_opened >= 0);

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_version_check CHECK (version > 0);

ALTER TABLE ONLY public.student_services_events ADD CONSTRAINT student_services_events_domain_check CHECK (domain = ANY (ARRAY['admissions'::text, 'discipline'::text, 'welfare'::text, 'health'::text, 'communications'::text, 'hostel'::text, 'alumni'::text]));

ALTER TABLE ONLY public.student_services_staff_access ADD CONSTRAINT student_services_staff_access_service_role_check CHECK (service_role = ANY (ARRAY['admissions_officer'::text, 'welfare_officer'::text, 'clinic_officer'::text, 'communications_officer'::text, 'hostel_manager'::text, 'house_parent'::text, 'alumni_officer'::text]));

ALTER TABLE ONLY public.students ADD CONSTRAINT students_gender_check CHECK (gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text]));

ALTER TABLE ONLY public.subject_results ADD CONSTRAINT subject_results_total_score_check CHECK (total_score >= 0::numeric AND total_score <= 100::numeric);

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_class_score_check CHECK (class_score >= 0::numeric);

ALTER TABLE ONLY public.subject_scores ADD CONSTRAINT subject_scores_exam_score_check CHECK (exam_score >= 0::numeric);

ALTER TABLE ONLY public.subjects ADD CONSTRAINT subject_legacy_score_bounds_chk CHECK (max_class_score > 0::numeric AND max_exam_score > 0::numeric AND (max_class_score + max_exam_score) <= 100::numeric);

ALTER TABLE ONLY public.system_release_state ADD CONSTRAINT system_release_state_release_channel_check CHECK (release_channel = ANY (ARRAY['production'::text, 'staging'::text, 'development'::text]));

ALTER TABLE ONLY public.system_release_state ADD CONSTRAINT system_release_state_singleton_check CHECK (singleton);

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_employment_status_check CHECK (employment_status = ANY (ARRAY['active'::text, 'leave'::text, 'suspended'::text, 'resigned'::text, 'retired'::text]));

ALTER TABLE ONLY public.teachers ADD CONSTRAINT teachers_gender_check CHECK (gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other'::text]));

ALTER TABLE ONLY public.terms ADD CONSTRAINT term_dates_chk CHECK (start_date IS NULL OR end_date IS NULL OR start_date <= end_date);

ALTER TABLE ONLY public.terms ADD CONSTRAINT term_reopening_after_end_chk CHECK (next_term_begins IS NULL OR end_date IS NULL OR next_term_begins > end_date);

ALTER TABLE ONLY public.terms ADD CONSTRAINT terms_sequence_check CHECK (sequence >= 1 AND sequence <= 6);

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_capacity_chk CHECK (capacity IS NULL OR capacity > 0);

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_status_chk CHECK (status = ANY (ARRAY['draft'::text, 'open'::text, 'closed'::text, 'completed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.tertiary_course_prerequisites ADD CONSTRAINT tertiary_course_prerequisites_grade_chk CHECK (minimum_grade_point IS NULL OR minimum_grade_point >= 0::numeric AND minimum_grade_point <= 10::numeric);

ALTER TABLE ONLY public.tertiary_course_prerequisites ADD CONSTRAINT tertiary_course_prerequisites_not_self_chk CHECK (course_id <> prerequisite_course_id);

ALTER TABLE ONLY public.tertiary_course_registrations ADD CONSTRAINT tertiary_course_registrations_status_chk CHECK (status = ANY (ARRAY['registered'::text, 'dropped'::text, 'withdrawn'::text, 'completed'::text]));

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_ca_chk CHECK (continuous_assessment_score IS NULL OR continuous_assessment_score >= 0::numeric);

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_credit_chk CHECK (credit_hours > 0::numeric AND credit_hours <= 30::numeric);

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_exam_chk CHECK (examination_score IS NULL OR examination_score >= 0::numeric);

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_point_chk CHECK (grade_point >= 0::numeric AND grade_point <= 10::numeric);

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_status_chk CHECK (result_status = ANY (ARRAY['draft'::text, 'approved'::text, 'published'::text, 'withdrawn'::text]));

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_total_chk CHECK (total_score >= 0::numeric AND total_score <= 100::numeric);

ALTER TABLE ONLY public.tertiary_courses ADD CONSTRAINT tertiary_courses_credit_hours_chk CHECK (credit_hours > 0::numeric AND credit_hours <= 30::numeric);

ALTER TABLE ONLY public.tertiary_degree_classifications ADD CONSTRAINT tertiary_degree_classifications_range_chk CHECK (minimum_cgpa >= 0::numeric AND maximum_cgpa <= 10::numeric AND minimum_cgpa <= maximum_cgpa);

ALTER TABLE ONLY public.tertiary_grading_scale ADD CONSTRAINT tertiary_grading_scale_point_chk CHECK (grade_point >= 0::numeric AND grade_point <= 10::numeric);

ALTER TABLE ONLY public.tertiary_grading_scale ADD CONSTRAINT tertiary_grading_scale_score_chk CHECK (minimum_score >= 0::numeric AND maximum_score <= 100::numeric AND minimum_score <= maximum_score);

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_category_chk CHECK (course_category = ANY (ARRAY['core'::text, 'elective'::text, 'optional'::text]));

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_credit_override_chk CHECK (credit_hours_override IS NULL OR credit_hours_override > 0::numeric AND credit_hours_override <= 30::numeric);

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_period_chk CHECK (period_sequence IS NULL OR period_sequence >= 1 AND period_sequence <= 12);

ALTER TABLE ONLY public.tertiary_programme_requirements ADD CONSTRAINT tertiary_programme_requirements_cgpa_chk CHECK (minimum_cgpa >= 0::numeric AND minimum_cgpa <= 10::numeric);

ALTER TABLE ONLY public.tertiary_programme_requirements ADD CONSTRAINT tertiary_programme_requirements_credits_chk CHECK (minimum_credits >= 0::numeric);

ALTER TABLE ONLY public.tertiary_programme_requirements ADD CONSTRAINT tertiary_programme_requirements_duration_chk CHECK (maximum_duration_years IS NULL OR maximum_duration_years > 0::numeric);

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_status_check CHECK (status = ANY (ARRAY['valid'::text, 'superseded'::text, 'revoked'::text]));

ALTER TABLE ONLY public.transport_drivers ADD CONSTRAINT transport_drivers_status_check CHECK (status = ANY (ARRAY['active'::text, 'suspended'::text, 'expired'::text, 'inactive'::text]));

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incident_resolution_ck CHECK (status = 'resolved'::text AND resolved_at IS NOT NULL OR status <> 'resolved'::text);

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_incident_type_check CHECK (incident_type = ANY (ARRAY['accident'::text, 'medical'::text, 'behaviour'::text, 'breakdown'::text, 'safety'::text, 'other'::text]));

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_severity_check CHECK (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]));

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_status_check CHECK (status = ANY (ARRAY['open'::text, 'under_review'::text, 'resolved'::text]));

ALTER TABLE ONLY public.transport_maintenance_records ADD CONSTRAINT transport_maintenance_records_cost_check CHECK (cost IS NULL OR cost >= 0::numeric);

ALTER TABLE ONLY public.transport_maintenance_records ADD CONSTRAINT transport_maintenance_records_maintenance_type_check CHECK (maintenance_type = ANY (ARRAY['scheduled_service'::text, 'repair'::text, 'inspection'::text, 'tyre'::text, 'battery'::text, 'other'::text]));

ALTER TABLE ONLY public.transport_maintenance_records ADD CONSTRAINT transport_maintenance_records_odometer_km_check CHECK (odometer_km IS NULL OR odometer_km >= 0::numeric);

ALTER TABLE ONLY public.transport_route_stops ADD CONSTRAINT transport_route_stops_stop_order_check CHECK (stop_order >= 1 AND stop_order <= 500);

ALTER TABLE ONLY public.transport_routes ADD CONSTRAINT transport_routes_service_type_check CHECK (service_type = ANY (ARRAY['morning_pickup'::text, 'afternoon_dropoff'::text, 'shuttle'::text, 'other'::text]));

ALTER TABLE ONLY public.transport_settings ADD CONSTRAINT transport_settings_boarding_close_minutes_check CHECK (boarding_close_minutes >= 0 AND boarding_close_minutes <= 180);

ALTER TABLE ONLY public.transport_settings ADD CONSTRAINT transport_settings_boarding_open_minutes_check CHECK (boarding_open_minutes >= 0 AND boarding_open_minutes <= 180);

ALTER TABLE ONLY public.transport_settings ADD CONSTRAINT transport_settings_document_alert_days_check CHECK (document_alert_days >= 0 AND document_alert_days <= 365);

ALTER TABLE ONLY public.transport_settings ADD CONSTRAINT transport_settings_maintenance_alert_days_check CHECK (maintenance_alert_days >= 0 AND maintenance_alert_days <= 365);

ALTER TABLE ONLY public.transport_staff_access ADD CONSTRAINT transport_staff_access_transport_role_check CHECK (transport_role = ANY (ARRAY['manager'::text, 'dispatcher'::text, 'driver'::text, 'attendant'::text, 'maintenance'::text]));

ALTER TABLE ONLY public.transport_stops ADD CONSTRAINT transport_stops_latitude_check CHECK (latitude IS NULL OR latitude >= '-90'::integer::numeric AND latitude <= 90::numeric);

ALTER TABLE ONLY public.transport_stops ADD CONSTRAINT transport_stops_longitude_check CHECK (longitude IS NULL OR longitude >= '-180'::integer::numeric AND longitude <= 180::numeric);

ALTER TABLE ONLY public.transport_student_assignments ADD CONSTRAINT transport_assignment_dates_ck CHECK (effective_to IS NULL OR effective_to >= effective_from);

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_student_times_ck CHECK (alighted_at IS NULL OR boarded_at IS NOT NULL);

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_status_check CHECK (status = ANY (ARRAY['pending'::text, 'boarded'::text, 'alighted'::text, 'missed'::text, 'excused'::text]));

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trip_odometer_ck CHECK (odometer_end_km IS NULL OR odometer_start_km IS NULL OR odometer_end_km >= odometer_start_km);

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_odometer_end_km_check CHECK (odometer_end_km IS NULL OR odometer_end_km >= 0::numeric);

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_odometer_start_km_check CHECK (odometer_start_km IS NULL OR odometer_start_km >= 0::numeric);

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_status_check CHECK (status = ANY (ARRAY['scheduled'::text, 'boarding'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_manufacture_year_check CHECK (manufacture_year IS NULL OR manufacture_year >= 1950 AND manufacture_year <= 2200);

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_odometer_km_check CHECK (odometer_km IS NULL OR odometer_km >= 0::numeric);

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_ownership_check CHECK (ownership = ANY (ARRAY['school'::text, 'leased'::text, 'contracted'::text]));

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_seating_capacity_check CHECK (seating_capacity >= 1 AND seating_capacity <= 200);

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_status_check CHECK (status = ANY (ARRAY['active'::text, 'maintenance'::text, 'out_of_service'::text, 'retired'::text]));

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_vehicle_type_check CHECK (vehicle_type = ANY (ARRAY['bus'::text, 'minibus'::text, 'van'::text, 'car'::text, 'other'::text]));

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_access_level_check CHECK (access_level = ANY (ARRAY['view'::text, 'edit'::text, 'score'::text, 'review'::text]));

ALTER TABLE ONLY public.welfare_case_notes ADD CONSTRAINT welfare_case_notes_note_type_check CHECK (note_type = ANY (ARRAY['progress'::text, 'meeting'::text, 'referral'::text, 'guardian_contact'::text, 'safeguarding'::text, 'other'::text]));

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_guardian_contact_status_check CHECK (guardian_contact_status = ANY (ARRAY['not_required'::text, 'pending'::text, 'contacted'::text, 'declined'::text, 'not_safe'::text]));

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_priority_check CHECK (priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]));

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_status_check CHECK (status = ANY (ARRAY['open'::text, 'monitoring'::text, 'referred'::text, 'closed'::text, 'cancelled'::text]));

ALTER TABLE ONLY public.academic_departments ADD CONSTRAINT academic_departments_faculty_id_fkey FOREIGN KEY (faculty_id) REFERENCES academic_faculties(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.academic_levels ADD CONSTRAINT academic_levels_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES academic_programmes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.academic_period_controls ADD CONSTRAINT academic_period_controls_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.academic_programmes ADD CONSTRAINT academic_programmes_department_id_fkey FOREIGN KEY (department_id) REFERENCES academic_departments(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.accounts_office_staff ADD CONSTRAINT accounts_office_staff_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.accounts_office_staff ADD CONSTRAINT accounts_office_staff_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_applying_class_id_fkey FOREIGN KEY (applying_class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.admissions_applications ADD CONSTRAINT admissions_applications_target_academic_year_id_fkey FOREIGN KEY (target_academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.admissions_documents ADD CONSTRAINT admissions_documents_application_id_fkey FOREIGN KEY (application_id) REFERENCES admissions_applications(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.admissions_documents ADD CONSTRAINT admissions_documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.admissions_documents ADD CONSTRAINT admissions_documents_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.admissions_offers ADD CONSTRAINT admissions_offers_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.admissions_offers ADD CONSTRAINT admissions_offers_application_id_fkey FOREIGN KEY (application_id) REFERENCES admissions_applications(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.admissions_offers ADD CONSTRAINT admissions_offers_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.admissions_offers ADD CONSTRAINT admissions_offers_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.alumni_engagements ADD CONSTRAINT alumni_engagements_alumni_id_fkey FOREIGN KEY (alumni_id) REFERENCES alumni_records(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.alumni_engagements ADD CONSTRAINT alumni_engagements_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_final_class_id_fkey FOREIGN KEY (final_class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_graduation_academic_year_id_fkey FOREIGN KEY (graduation_academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.alumni_records ADD CONSTRAINT alumni_records_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.alumni_verification_requests ADD CONSTRAINT alumni_verification_requests_alumni_id_fkey FOREIGN KEY (alumni_id) REFERENCES alumni_records(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.alumni_verification_requests ADD CONSTRAINT alumni_verification_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.alumni_verification_requests ADD CONSTRAINT alumni_verification_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;

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

ALTER TABLE ONLY public.communication_campaigns ADD CONSTRAINT communication_campaigns_audience_class_id_fkey FOREIGN KEY (audience_class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.communication_campaigns ADD CONSTRAINT communication_campaigns_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.communication_deliveries ADD CONSTRAINT communication_deliveries_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES communication_campaigns(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.communication_deliveries ADD CONSTRAINT communication_deliveries_outbox_id_fkey FOREIGN KEY (outbox_id) REFERENCES notification_outbox(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.communication_deliveries ADD CONSTRAINT communication_deliveries_recipient_profile_id_fkey FOREIGN KEY (recipient_profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.communication_deliveries ADD CONSTRAINT communication_deliveries_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.communication_messages ADD CONSTRAINT communication_messages_sender_profile_id_fkey FOREIGN KEY (sender_profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.communication_messages ADD CONSTRAINT communication_messages_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES communication_threads(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.communication_templates ADD CONSTRAINT communication_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.communication_thread_participants ADD CONSTRAINT communication_thread_participants_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.communication_thread_participants ADD CONSTRAINT communication_thread_participants_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES communication_threads(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.communication_threads ADD CONSTRAINT communication_threads_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.data_retention_policies ADD CONSTRAINT data_retention_policies_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.discipline_actions ADD CONSTRAINT discipline_actions_assigned_hr_staff_id_fkey FOREIGN KEY (assigned_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.discipline_actions ADD CONSTRAINT discipline_actions_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.discipline_actions ADD CONSTRAINT discipline_actions_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.discipline_actions ADD CONSTRAINT discipline_actions_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES discipline_incidents(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.discipline_guardian_acknowledgements ADD CONSTRAINT discipline_guardian_acknowledgements_guardian_user_id_fkey FOREIGN KEY (guardian_user_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.discipline_guardian_acknowledgements ADD CONSTRAINT discipline_guardian_acknowledgements_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES discipline_incidents(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.discipline_guardian_acknowledgements ADD CONSTRAINT discipline_guardian_acknowledgements_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.discipline_incidents ADD CONSTRAINT discipline_incidents_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.discipline_incidents ADD CONSTRAINT discipline_incidents_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.discipline_incidents ADD CONSTRAINT discipline_incidents_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

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

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES finance_fee_schedules(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_accounts ADD CONSTRAINT finance_fee_accounts_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_allocations ADD CONSTRAINT finance_fee_allocations_account_id_fkey FOREIGN KEY (account_id) REFERENCES finance_fee_accounts(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_allocations ADD CONSTRAINT finance_fee_allocations_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES finance_fee_transactions(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_group_classes ADD CONSTRAINT finance_fee_group_classes_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_group_classes ADD CONSTRAINT finance_fee_group_classes_fee_group_id_fkey FOREIGN KEY (fee_group_id) REFERENCES finance_fee_groups(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.finance_fee_groups ADD CONSTRAINT finance_fee_groups_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_account_id_fkey FOREIGN KEY (account_id) REFERENCES finance_fee_accounts(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES finance_fee_schedules(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_invoices ADD CONSTRAINT finance_fee_invoices_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_fee_group_id_fkey FOREIGN KEY (fee_group_id) REFERENCES finance_fee_groups(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_fee_schedules ADD CONSTRAINT finance_fee_schedules_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_reversal_of_id_fkey FOREIGN KEY (reversal_of_id) REFERENCES finance_fee_transactions(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_fee_transactions ADD CONSTRAINT finance_fee_transactions_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id);

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id);

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);

ALTER TABLE ONLY public.finance_guardian_contact_events ADD CONSTRAINT finance_guardian_contact_events_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id);

ALTER TABLE ONLY public.finance_hold_overrides ADD CONSTRAINT finance_hold_overrides_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_hold_overrides ADD CONSTRAINT finance_hold_overrides_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_hold_policy ADD CONSTRAINT finance_hold_policy_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_item_lines ADD CONSTRAINT finance_payroll_item_lines_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_item_lines ADD CONSTRAINT finance_payroll_item_lines_loan_id_fkey FOREIGN KEY (loan_id) REFERENCES finance_teacher_loans(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_item_lines ADD CONSTRAINT finance_payroll_item_lines_payroll_item_id_fkey FOREIGN KEY (payroll_item_id) REFERENCES finance_payroll_items(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_payroll_profile_id_fkey FOREIGN KEY (payroll_profile_id) REFERENCES finance_payroll_profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_run_id_fkey FOREIGN KEY (run_id) REFERENCES finance_payroll_runs(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_payroll_items ADD CONSTRAINT finance_payroll_items_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_hr_staff_member_id_fkey FOREIGN KEY (hr_staff_member_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_salary_grade_id_fkey FOREIGN KEY (salary_grade_id) REFERENCES finance_salary_grades(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_profiles ADD CONSTRAINT finance_payroll_profiles_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.finance_payroll_rules ADD CONSTRAINT finance_payroll_rules_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_runs ADD CONSTRAINT finance_payroll_runs_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_payroll_runs ADD CONSTRAINT finance_payroll_runs_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_salary_grades ADD CONSTRAINT finance_salary_grades_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_teacher_loans ADD CONSTRAINT finance_teacher_loans_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.finance_teacher_loans ADD CONSTRAINT finance_teacher_loans_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.grading_scales ADD CONSTRAINT grading_scales_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES student_guardians(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.guardian_links ADD CONSTRAINT guardian_links_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.headteachers ADD CONSTRAINT headteachers_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_immunizations ADD CONSTRAINT health_immunizations_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_immunizations ADD CONSTRAINT health_immunizations_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.health_medication_administrations ADD CONSTRAINT health_medication_administrati_administered_by_hr_staff_id_fkey FOREIGN KEY (administered_by_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_medication_administrations ADD CONSTRAINT health_medication_administrations_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_medication_administrations ADD CONSTRAINT health_medication_administrations_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.health_medication_administrations ADD CONSTRAINT health_medication_administrations_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES health_visits(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.health_student_profiles ADD CONSTRAINT health_student_profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_student_profiles ADD CONSTRAINT health_student_profiles_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.health_student_profiles ADD CONSTRAINT health_student_profiles_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_attended_by_hr_staff_id_fkey FOREIGN KEY (attended_by_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.health_visits ADD CONSTRAINT health_visits_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_allocated_by_fkey FOREIGN KEY (allocated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_bed_id_fkey FOREIGN KEY (bed_id) REFERENCES hostel_beds(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_ended_by_fkey FOREIGN KEY (ended_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_allocations ADD CONSTRAINT hostel_allocations_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_beds ADD CONSTRAINT hostel_beds_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_beds ADD CONSTRAINT hostel_beds_room_id_fkey FOREIGN KEY (room_id) REFERENCES hostel_rooms(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_houses ADD CONSTRAINT hostel_houses_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_houses ADD CONSTRAINT hostel_houses_house_parent_hr_staff_id_fkey FOREIGN KEY (house_parent_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_incidents ADD CONSTRAINT hostel_incidents_allocation_id_fkey FOREIGN KEY (allocation_id) REFERENCES hostel_allocations(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_incidents ADD CONSTRAINT hostel_incidents_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_incidents ADD CONSTRAINT hostel_incidents_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_incidents ADD CONSTRAINT hostel_incidents_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_movements ADD CONSTRAINT hostel_movements_allocation_id_fkey FOREIGN KEY (allocation_id) REFERENCES hostel_allocations(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_movements ADD CONSTRAINT hostel_movements_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_movements ADD CONSTRAINT hostel_movements_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hostel_rooms ADD CONSTRAINT hostel_rooms_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hostel_rooms ADD CONSTRAINT hostel_rooms_house_id_fkey FOREIGN KEY (house_id) REFERENCES hostel_houses(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hr_employment_events ADD CONSTRAINT hr_employment_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_employment_events ADD CONSTRAINT hr_employment_events_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hr_leave_requests ADD CONSTRAINT hr_leave_requests_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_staff_documents ADD CONSTRAINT hr_staff_documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_staff_documents ADD CONSTRAINT hr_staff_documents_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hr_staff_documents ADD CONSTRAINT hr_staff_documents_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_staff_members ADD CONSTRAINT hr_staff_members_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_staff_qualifications ADD CONSTRAINT hr_staff_qualifications_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.hr_staff_qualifications ADD CONSTRAINT hr_staff_qualifications_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.hr_staff_qualifications ADD CONSTRAINT hr_staff_qualifications_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_deletion_tombstones ADD CONSTRAINT id_card_deletion_tombstones_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_card_id_fkey FOREIGN KEY (card_id) REFERENCES student_id_cards(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_events ADD CONSTRAINT id_card_events_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.id_card_settings ADD CONSTRAINT id_card_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.import_batches ADD CONSTRAINT import_batches_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.import_errors ADD CONSTRAINT import_errors_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES import_batches(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.inventory_asset_assignments ADD CONSTRAINT inventory_asset_assignments_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES inventory_assets(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_asset_assignments ADD CONSTRAINT inventory_asset_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_asset_assignments ADD CONSTRAINT inventory_asset_assignments_assigned_location_id_fkey FOREIGN KEY (assigned_location_id) REFERENCES inventory_locations(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_asset_assignments ADD CONSTRAINT inventory_asset_assignments_returned_by_fkey FOREIGN KEY (returned_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_asset_assignments ADD CONSTRAINT inventory_asset_assignments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES inventory_assets(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_asset_maintenance ADD CONSTRAINT inventory_asset_maintenance_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES inventory_suppliers(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_asset_writeoffs ADD CONSTRAINT inventory_asset_writeoffs_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES inventory_assets(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_asset_writeoffs ADD CONSTRAINT inventory_asset_writeoffs_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_asset_writeoffs ADD CONSTRAINT inventory_asset_writeoffs_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_current_location_id_fkey FOREIGN KEY (current_location_id) REFERENCES inventory_locations(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_item_id_fkey FOREIGN KEY (item_id) REFERENCES inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_purchase_order_line_id_fkey FOREIGN KEY (purchase_order_line_id) REFERENCES inventory_purchase_order_lines(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_assets ADD CONSTRAINT inventory_assets_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES inventory_suppliers(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_goods_receipt_id_fkey FOREIGN KEY (goods_receipt_id) REFERENCES inventory_goods_receipts(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_item_id_fkey FOREIGN KEY (item_id) REFERENCES inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_location_id_fkey FOREIGN KEY (location_id) REFERENCES inventory_locations(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_purchase_order_line_id_fkey FOREIGN KEY (purchase_order_line_id) REFERENCES inventory_purchase_order_lines(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_goods_receipt_lines ADD CONSTRAINT inventory_goods_receipt_lines_stock_movement_id_fkey FOREIGN KEY (stock_movement_id) REFERENCES inventory_stock_movements(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_goods_receipts ADD CONSTRAINT inventory_goods_receipts_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES inventory_purchase_orders(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_goods_receipts ADD CONSTRAINT inventory_goods_receipts_received_by_fkey FOREIGN KEY (received_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_fulfilled_by_fkey FOREIGN KEY (fulfilled_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_fulfilled_movement_id_fkey FOREIGN KEY (fulfilled_movement_id) REFERENCES inventory_stock_movements(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_item_id_fkey FOREIGN KEY (item_id) REFERENCES inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_preferred_location_id_fkey FOREIGN KEY (preferred_location_id) REFERENCES inventory_locations(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_item_requests ADD CONSTRAINT inventory_item_requests_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_items ADD CONSTRAINT inventory_items_preferred_supplier_id_fkey FOREIGN KEY (preferred_supplier_id) REFERENCES inventory_suppliers(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_locations ADD CONSTRAINT inventory_locations_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_purchase_order_lines_item_id_fkey FOREIGN KEY (item_id) REFERENCES inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_purchase_order_lines_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES inventory_purchase_orders(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_purchase_order_lines ADD CONSTRAINT inventory_purchase_order_lines_request_line_id_fkey FOREIGN KEY (request_line_id) REFERENCES inventory_purchase_request_lines(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_orders_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_orders_request_id_fkey FOREIGN KEY (request_id) REFERENCES inventory_purchase_requests(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_purchase_orders ADD CONSTRAINT inventory_purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES inventory_suppliers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_purchase_request_lines ADD CONSTRAINT inventory_purchase_request_lines_item_id_fkey FOREIGN KEY (item_id) REFERENCES inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_purchase_request_lines ADD CONSTRAINT inventory_purchase_request_lines_request_id_fkey FOREIGN KEY (request_id) REFERENCES inventory_purchase_requests(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_purchase_requests ADD CONSTRAINT inventory_purchase_requests_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_purchase_requests ADD CONSTRAINT inventory_purchase_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_staff_access ADD CONSTRAINT inventory_staff_access_appointed_by_fkey FOREIGN KEY (appointed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_staff_access ADD CONSTRAINT inventory_staff_access_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_staff_access ADD CONSTRAINT inventory_staff_access_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_staff_access ADD CONSTRAINT inventory_staff_access_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_item_id_fkey FOREIGN KEY (item_id) REFERENCES inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_location_id_fkey FOREIGN KEY (location_id) REFERENCES inventory_locations(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_posted_by_fkey FOREIGN KEY (posted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_recipient_staff_id_fkey FOREIGN KEY (recipient_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_related_movement_id_fkey FOREIGN KEY (related_movement_id) REFERENCES inventory_stock_movements(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_stock_movements ADD CONSTRAINT inventory_stock_movements_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_suppliers ADD CONSTRAINT inventory_suppliers_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_books ADD CONSTRAINT library_books_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_book_id_fkey FOREIGN KEY (book_id) REFERENCES library_books(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_copies ADD CONSTRAINT library_copies_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_inventory_events ADD CONSTRAINT library_inventory_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_inventory_events ADD CONSTRAINT library_inventory_events_copy_id_fkey FOREIGN KEY (copy_id) REFERENCES library_copies(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_borrower_hr_staff_id_fkey FOREIGN KEY (borrower_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_borrower_student_id_fkey FOREIGN KEY (borrower_student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_copy_id_fkey FOREIGN KEY (copy_id) REFERENCES library_copies(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_loans ADD CONSTRAINT library_loans_returned_by_fkey FOREIGN KEY (returned_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_book_id_fkey FOREIGN KEY (book_id) REFERENCES library_books(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_borrower_hr_staff_id_fkey FOREIGN KEY (borrower_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_borrower_student_id_fkey FOREIGN KEY (borrower_student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_reservations ADD CONSTRAINT library_reservations_fulfilled_loan_id_fkey FOREIGN KEY (fulfilled_loan_id) REFERENCES library_loans(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.library_settings ADD CONSTRAINT library_settings_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_staff_access ADD CONSTRAINT library_staff_access_appointed_by_fkey FOREIGN KEY (appointed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.library_staff_access ADD CONSTRAINT library_staff_access_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;

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

ALTER TABLE ONLY public.mfa_recovery_codes ADD CONSTRAINT mfa_recovery_codes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

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

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_initiated_by_fkey FOREIGN KEY (initiated_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_restore_jobs ADD CONSTRAINT school_restore_jobs_pre_restore_backup_id_fkey FOREIGN KEY (pre_restore_backup_id) REFERENCES backup_exports(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.school_restore_stage_tables ADD CONSTRAINT school_restore_stage_tables_job_id_fkey FOREIGN KEY (job_id) REFERENCES school_restore_jobs(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.school_settings ADD CONSTRAINT school_settings_certificate_completion_class_id_fkey FOREIGN KEY (certificate_completion_class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.security_events ADD CONSTRAINT security_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.security_verification_runs ADD CONSTRAINT security_verification_runs_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.shs_programme_subjects ADD CONSTRAINT shs_programme_subjects_level_id_fkey FOREIGN KEY (level_id) REFERENCES academic_levels(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.shs_programme_subjects ADD CONSTRAINT shs_programme_subjects_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES academic_programmes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.shs_programme_subjects ADD CONSTRAINT shs_programme_subjects_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE;

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

ALTER TABLE ONLY public.student_programme_enrollments ADD CONSTRAINT student_programme_enrollments_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.student_programme_enrollments ADD CONSTRAINT student_programme_enrollments_level_id_fkey FOREIGN KEY (level_id) REFERENCES academic_levels(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_programme_enrollments ADD CONSTRAINT student_programme_enrollments_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES academic_programmes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.student_programme_enrollments ADD CONSTRAINT student_programme_enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_promoted_to_class_id_fkey FOREIGN KEY (promoted_to_class_id) REFERENCES classes(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_published_by_fkey FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_reports ADD CONSTRAINT student_reports_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.student_services_events ADD CONSTRAINT student_services_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_services_staff_access ADD CONSTRAINT student_services_staff_access_appointed_by_fkey FOREIGN KEY (appointed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.student_services_staff_access ADD CONSTRAINT student_services_staff_access_hr_staff_id_fkey FOREIGN KEY (hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.student_services_staff_access ADD CONSTRAINT student_services_staff_access_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.students ADD CONSTRAINT students_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

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

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_course_id_fkey FOREIGN KEY (course_id) REFERENCES tertiary_courses(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_lecturer_profile_id_fkey FOREIGN KEY (lecturer_profile_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_level_id_fkey FOREIGN KEY (level_id) REFERENCES academic_levels(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.tertiary_course_offerings ADD CONSTRAINT tertiary_course_offerings_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.tertiary_course_prerequisites ADD CONSTRAINT tertiary_course_prerequisites_course_id_fkey FOREIGN KEY (course_id) REFERENCES tertiary_courses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tertiary_course_prerequisites ADD CONSTRAINT tertiary_course_prerequisites_prerequisite_course_id_fkey FOREIGN KEY (prerequisite_course_id) REFERENCES tertiary_courses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tertiary_course_registrations ADD CONSTRAINT tertiary_course_registrations_course_offering_id_fkey FOREIGN KEY (course_offering_id) REFERENCES tertiary_course_offerings(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.tertiary_course_registrations ADD CONSTRAINT tertiary_course_registrations_programme_enrollment_id_fkey FOREIGN KEY (programme_enrollment_id) REFERENCES student_programme_enrollments(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.tertiary_course_registrations ADD CONSTRAINT tertiary_course_registrations_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.tertiary_course_results ADD CONSTRAINT tertiary_course_results_course_registration_id_fkey FOREIGN KEY (course_registration_id) REFERENCES tertiary_course_registrations(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tertiary_courses ADD CONSTRAINT tertiary_courses_department_id_fkey FOREIGN KEY (department_id) REFERENCES academic_departments(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.tertiary_degree_classifications ADD CONSTRAINT tertiary_degree_classifications_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES academic_programmes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_course_id_fkey FOREIGN KEY (course_id) REFERENCES tertiary_courses(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_level_id_fkey FOREIGN KEY (level_id) REFERENCES academic_levels(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.tertiary_programme_courses ADD CONSTRAINT tertiary_programme_courses_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES academic_programmes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.tertiary_programme_requirements ADD CONSTRAINT tertiary_programme_requirements_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES academic_programmes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transcript_issuances ADD CONSTRAINT transcript_issuances_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.transport_drivers ADD CONSTRAINT transport_drivers_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_drivers ADD CONSTRAINT transport_drivers_hr_staff_id_fkey FOREIGN KEY (hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES transport_drivers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES transport_trips(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_incidents ADD CONSTRAINT transport_incidents_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES transport_vehicles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_maintenance_records ADD CONSTRAINT transport_maintenance_records_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_maintenance_records ADD CONSTRAINT transport_maintenance_records_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES transport_vehicles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_route_stops ADD CONSTRAINT transport_route_stops_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_route_stops ADD CONSTRAINT transport_route_stops_route_id_fkey FOREIGN KEY (route_id) REFERENCES transport_routes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_route_stops ADD CONSTRAINT transport_route_stops_stop_id_fkey FOREIGN KEY (stop_id) REFERENCES transport_stops(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_routes ADD CONSTRAINT transport_routes_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_routes ADD CONSTRAINT transport_routes_default_attendant_hr_staff_id_fkey FOREIGN KEY (default_attendant_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_routes ADD CONSTRAINT transport_routes_default_driver_id_fkey FOREIGN KEY (default_driver_id) REFERENCES transport_drivers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_routes ADD CONSTRAINT transport_routes_default_vehicle_id_fkey FOREIGN KEY (default_vehicle_id) REFERENCES transport_vehicles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_settings ADD CONSTRAINT transport_settings_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_staff_access ADD CONSTRAINT transport_staff_access_appointed_by_fkey FOREIGN KEY (appointed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_staff_access ADD CONSTRAINT transport_staff_access_hr_staff_id_fkey FOREIGN KEY (hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_staff_access ADD CONSTRAINT transport_staff_access_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_stops ADD CONSTRAINT transport_stops_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_student_assignments ADD CONSTRAINT transport_student_assignments_alighting_stop_id_fkey FOREIGN KEY (alighting_stop_id) REFERENCES transport_stops(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_student_assignments ADD CONSTRAINT transport_student_assignments_boarding_stop_id_fkey FOREIGN KEY (boarding_stop_id) REFERENCES transport_stops(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_student_assignments ADD CONSTRAINT transport_student_assignments_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_student_assignments ADD CONSTRAINT transport_student_assignments_route_id_fkey FOREIGN KEY (route_id) REFERENCES transport_routes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_student_assignments ADD CONSTRAINT transport_student_assignments_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_alighted_by_fkey FOREIGN KEY (alighted_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_alighting_stop_id_fkey FOREIGN KEY (alighting_stop_id) REFERENCES transport_stops(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES transport_student_assignments(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_boarded_by_fkey FOREIGN KEY (boarded_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_boarding_stop_id_fkey FOREIGN KEY (boarding_stop_id) REFERENCES transport_stops(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trip_students ADD CONSTRAINT transport_trip_students_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES transport_trips(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_attendant_hr_staff_id_fkey FOREIGN KEY (attendant_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES transport_drivers(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_route_id_fkey FOREIGN KEY (route_id) REFERENCES transport_routes(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_started_by_fkey FOREIGN KEY (started_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.transport_trips ADD CONSTRAINT transport_trips_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES transport_vehicles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.transport_vehicles ADD CONSTRAINT transport_vehicles_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.user_class_access ADD CONSTRAINT user_class_access_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.welfare_case_notes ADD CONSTRAINT welfare_case_notes_case_id_fkey FOREIGN KEY (case_id) REFERENCES welfare_cases(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.welfare_case_notes ADD CONSTRAINT welfare_case_notes_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_assigned_hr_staff_id_fkey FOREIGN KEY (assigned_hr_staff_id) REFERENCES hr_staff_members(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.welfare_cases ADD CONSTRAINT welfare_cases_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;
