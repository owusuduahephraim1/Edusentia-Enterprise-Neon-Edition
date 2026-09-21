-- Edusentia tenant foundation: grants and comments
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO PUBLIC, anon, authenticated, service_role;

GRANT DELETE ON TABLE public.academic_departments TO authenticated;

GRANT INSERT ON TABLE public.academic_departments TO authenticated;

GRANT SELECT ON TABLE public.academic_departments TO authenticated;

GRANT UPDATE ON TABLE public.academic_departments TO authenticated;

GRANT DELETE ON TABLE public.academic_departments TO service_role;

GRANT INSERT ON TABLE public.academic_departments TO service_role;

GRANT MAINTAIN ON TABLE public.academic_departments TO service_role;

GRANT REFERENCES ON TABLE public.academic_departments TO service_role;

GRANT SELECT ON TABLE public.academic_departments TO service_role;

GRANT TRIGGER ON TABLE public.academic_departments TO service_role;

GRANT TRUNCATE ON TABLE public.academic_departments TO service_role;

GRANT UPDATE ON TABLE public.academic_departments TO service_role;

GRANT DELETE ON TABLE public.academic_faculties TO authenticated;

GRANT INSERT ON TABLE public.academic_faculties TO authenticated;

GRANT SELECT ON TABLE public.academic_faculties TO authenticated;

GRANT UPDATE ON TABLE public.academic_faculties TO authenticated;

GRANT DELETE ON TABLE public.academic_faculties TO service_role;

GRANT INSERT ON TABLE public.academic_faculties TO service_role;

GRANT MAINTAIN ON TABLE public.academic_faculties TO service_role;

GRANT REFERENCES ON TABLE public.academic_faculties TO service_role;

GRANT SELECT ON TABLE public.academic_faculties TO service_role;

GRANT TRIGGER ON TABLE public.academic_faculties TO service_role;

GRANT TRUNCATE ON TABLE public.academic_faculties TO service_role;

GRANT UPDATE ON TABLE public.academic_faculties TO service_role;

GRANT DELETE ON TABLE public.academic_levels TO authenticated;

GRANT INSERT ON TABLE public.academic_levels TO authenticated;

GRANT SELECT ON TABLE public.academic_levels TO authenticated;

GRANT UPDATE ON TABLE public.academic_levels TO authenticated;

GRANT DELETE ON TABLE public.academic_levels TO service_role;

GRANT INSERT ON TABLE public.academic_levels TO service_role;

GRANT MAINTAIN ON TABLE public.academic_levels TO service_role;

GRANT REFERENCES ON TABLE public.academic_levels TO service_role;

GRANT SELECT ON TABLE public.academic_levels TO service_role;

GRANT TRIGGER ON TABLE public.academic_levels TO service_role;

GRANT TRUNCATE ON TABLE public.academic_levels TO service_role;

GRANT UPDATE ON TABLE public.academic_levels TO service_role;

GRANT DELETE ON TABLE public.academic_period_controls TO service_role;

GRANT INSERT ON TABLE public.academic_period_controls TO service_role;

GRANT MAINTAIN ON TABLE public.academic_period_controls TO service_role;

GRANT REFERENCES ON TABLE public.academic_period_controls TO service_role;

GRANT SELECT ON TABLE public.academic_period_controls TO service_role;

GRANT TRIGGER ON TABLE public.academic_period_controls TO service_role;

GRANT TRUNCATE ON TABLE public.academic_period_controls TO service_role;

GRANT UPDATE ON TABLE public.academic_period_controls TO service_role;

GRANT DELETE ON TABLE public.academic_programmes TO authenticated;

GRANT INSERT ON TABLE public.academic_programmes TO authenticated;

GRANT SELECT ON TABLE public.academic_programmes TO authenticated;

GRANT UPDATE ON TABLE public.academic_programmes TO authenticated;

GRANT DELETE ON TABLE public.academic_programmes TO service_role;

GRANT INSERT ON TABLE public.academic_programmes TO service_role;

GRANT MAINTAIN ON TABLE public.academic_programmes TO service_role;

GRANT REFERENCES ON TABLE public.academic_programmes TO service_role;

GRANT SELECT ON TABLE public.academic_programmes TO service_role;

GRANT TRIGGER ON TABLE public.academic_programmes TO service_role;

GRANT TRUNCATE ON TABLE public.academic_programmes TO service_role;

GRANT UPDATE ON TABLE public.academic_programmes TO service_role;

GRANT MAINTAIN ON TABLE public.academic_years TO authenticated;

GRANT SELECT ON TABLE public.academic_years TO authenticated;

GRANT DELETE ON TABLE public.academic_years TO service_role;

GRANT INSERT ON TABLE public.academic_years TO service_role;

GRANT MAINTAIN ON TABLE public.academic_years TO service_role;

GRANT REFERENCES ON TABLE public.academic_years TO service_role;

GRANT SELECT ON TABLE public.academic_years TO service_role;

GRANT TRIGGER ON TABLE public.academic_years TO service_role;

GRANT TRUNCATE ON TABLE public.academic_years TO service_role;

GRANT UPDATE ON TABLE public.academic_years TO service_role;

GRANT SELECT ON SEQUENCE public.accounts_office_staff_no_seq TO anon;

GRANT UPDATE ON SEQUENCE public.accounts_office_staff_no_seq TO anon;

GRANT USAGE ON SEQUENCE public.accounts_office_staff_no_seq TO anon;

GRANT SELECT ON SEQUENCE public.accounts_office_staff_no_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.accounts_office_staff_no_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.accounts_office_staff_no_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.accounts_office_staff_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.accounts_office_staff_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.accounts_office_staff_no_seq TO service_role;

GRANT DELETE ON TABLE public.accounts_office_staff TO service_role;

GRANT INSERT ON TABLE public.accounts_office_staff TO service_role;

GRANT MAINTAIN ON TABLE public.accounts_office_staff TO service_role;

GRANT REFERENCES ON TABLE public.accounts_office_staff TO service_role;

GRANT SELECT ON TABLE public.accounts_office_staff TO service_role;

GRANT TRIGGER ON TABLE public.accounts_office_staff TO service_role;

GRANT TRUNCATE ON TABLE public.accounts_office_staff TO service_role;

GRANT UPDATE ON TABLE public.accounts_office_staff TO service_role;

GRANT SELECT ON SEQUENCE public.admissions_application_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.admissions_application_seq TO service_role;

GRANT USAGE ON SEQUENCE public.admissions_application_seq TO service_role;

GRANT DELETE ON TABLE public.admissions_applications TO service_role;

GRANT INSERT ON TABLE public.admissions_applications TO service_role;

GRANT MAINTAIN ON TABLE public.admissions_applications TO service_role;

GRANT REFERENCES ON TABLE public.admissions_applications TO service_role;

GRANT SELECT ON TABLE public.admissions_applications TO service_role;

GRANT TRIGGER ON TABLE public.admissions_applications TO service_role;

GRANT TRUNCATE ON TABLE public.admissions_applications TO service_role;

GRANT UPDATE ON TABLE public.admissions_applications TO service_role;

GRANT DELETE ON TABLE public.admissions_documents TO service_role;

GRANT INSERT ON TABLE public.admissions_documents TO service_role;

GRANT MAINTAIN ON TABLE public.admissions_documents TO service_role;

GRANT REFERENCES ON TABLE public.admissions_documents TO service_role;

GRANT SELECT ON TABLE public.admissions_documents TO service_role;

GRANT TRIGGER ON TABLE public.admissions_documents TO service_role;

GRANT TRUNCATE ON TABLE public.admissions_documents TO service_role;

GRANT UPDATE ON TABLE public.admissions_documents TO service_role;

GRANT DELETE ON TABLE public.admissions_offers TO service_role;

GRANT INSERT ON TABLE public.admissions_offers TO service_role;

GRANT MAINTAIN ON TABLE public.admissions_offers TO service_role;

GRANT REFERENCES ON TABLE public.admissions_offers TO service_role;

GRANT SELECT ON TABLE public.admissions_offers TO service_role;

GRANT TRIGGER ON TABLE public.admissions_offers TO service_role;

GRANT TRUNCATE ON TABLE public.admissions_offers TO service_role;

GRANT UPDATE ON TABLE public.admissions_offers TO service_role;

GRANT SELECT ON SEQUENCE public.admissions_student_number_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.admissions_student_number_seq TO service_role;

GRANT USAGE ON SEQUENCE public.admissions_student_number_seq TO service_role;

GRANT DELETE ON TABLE public.alumni_engagements TO service_role;

GRANT INSERT ON TABLE public.alumni_engagements TO service_role;

GRANT MAINTAIN ON TABLE public.alumni_engagements TO service_role;

GRANT REFERENCES ON TABLE public.alumni_engagements TO service_role;

GRANT SELECT ON TABLE public.alumni_engagements TO service_role;

GRANT TRIGGER ON TABLE public.alumni_engagements TO service_role;

GRANT TRUNCATE ON TABLE public.alumni_engagements TO service_role;

GRANT UPDATE ON TABLE public.alumni_engagements TO service_role;

GRANT SELECT ON SEQUENCE public.alumni_record_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.alumni_record_seq TO service_role;

GRANT USAGE ON SEQUENCE public.alumni_record_seq TO service_role;

GRANT DELETE ON TABLE public.alumni_records TO service_role;

GRANT INSERT ON TABLE public.alumni_records TO service_role;

GRANT MAINTAIN ON TABLE public.alumni_records TO service_role;

GRANT REFERENCES ON TABLE public.alumni_records TO service_role;

GRANT SELECT ON TABLE public.alumni_records TO service_role;

GRANT TRIGGER ON TABLE public.alumni_records TO service_role;

GRANT TRUNCATE ON TABLE public.alumni_records TO service_role;

GRANT UPDATE ON TABLE public.alumni_records TO service_role;

GRANT DELETE ON TABLE public.alumni_verification_requests TO service_role;

GRANT INSERT ON TABLE public.alumni_verification_requests TO service_role;

GRANT MAINTAIN ON TABLE public.alumni_verification_requests TO service_role;

GRANT REFERENCES ON TABLE public.alumni_verification_requests TO service_role;

GRANT SELECT ON TABLE public.alumni_verification_requests TO service_role;

GRANT TRIGGER ON TABLE public.alumni_verification_requests TO service_role;

GRANT TRUNCATE ON TABLE public.alumni_verification_requests TO service_role;

GRANT UPDATE ON TABLE public.alumni_verification_requests TO service_role;

GRANT MAINTAIN ON TABLE public.assessment_components TO authenticated;

GRANT SELECT ON TABLE public.assessment_components TO authenticated;

GRANT DELETE ON TABLE public.assessment_components TO service_role;

GRANT INSERT ON TABLE public.assessment_components TO service_role;

GRANT MAINTAIN ON TABLE public.assessment_components TO service_role;

GRANT REFERENCES ON TABLE public.assessment_components TO service_role;

GRANT SELECT ON TABLE public.assessment_components TO service_role;

GRANT TRIGGER ON TABLE public.assessment_components TO service_role;

GRANT TRUNCATE ON TABLE public.assessment_components TO service_role;

GRANT UPDATE ON TABLE public.assessment_components TO service_role;

GRANT MAINTAIN ON TABLE public.assessment_schemes TO authenticated;

GRANT SELECT ON TABLE public.assessment_schemes TO authenticated;

GRANT DELETE ON TABLE public.assessment_schemes TO service_role;

GRANT INSERT ON TABLE public.assessment_schemes TO service_role;

GRANT MAINTAIN ON TABLE public.assessment_schemes TO service_role;

GRANT REFERENCES ON TABLE public.assessment_schemes TO service_role;

GRANT SELECT ON TABLE public.assessment_schemes TO service_role;

GRANT TRIGGER ON TABLE public.assessment_schemes TO service_role;

GRANT TRUNCATE ON TABLE public.assessment_schemes TO service_role;

GRANT UPDATE ON TABLE public.assessment_schemes TO service_role;

GRANT SELECT ON TABLE public.assessment_score_entries TO authenticated;

GRANT DELETE ON TABLE public.assessment_score_entries TO service_role;

GRANT INSERT ON TABLE public.assessment_score_entries TO service_role;

GRANT MAINTAIN ON TABLE public.assessment_score_entries TO service_role;

GRANT REFERENCES ON TABLE public.assessment_score_entries TO service_role;

GRANT SELECT ON TABLE public.assessment_score_entries TO service_role;

GRANT TRIGGER ON TABLE public.assessment_score_entries TO service_role;

GRANT TRUNCATE ON TABLE public.assessment_score_entries TO service_role;

GRANT UPDATE ON TABLE public.assessment_score_entries TO service_role;

GRANT DELETE ON TABLE public.audit_log_archive_entries TO service_role;

GRANT INSERT ON TABLE public.audit_log_archive_entries TO service_role;

GRANT MAINTAIN ON TABLE public.audit_log_archive_entries TO service_role;

GRANT REFERENCES ON TABLE public.audit_log_archive_entries TO service_role;

GRANT SELECT ON TABLE public.audit_log_archive_entries TO service_role;

GRANT TRIGGER ON TABLE public.audit_log_archive_entries TO service_role;

GRANT TRUNCATE ON TABLE public.audit_log_archive_entries TO service_role;

GRANT UPDATE ON TABLE public.audit_log_archive_entries TO service_role;

GRANT DELETE ON TABLE public.audit_log_archives TO service_role;

GRANT INSERT ON TABLE public.audit_log_archives TO service_role;

GRANT MAINTAIN ON TABLE public.audit_log_archives TO service_role;

GRANT REFERENCES ON TABLE public.audit_log_archives TO service_role;

GRANT SELECT ON TABLE public.audit_log_archives TO service_role;

GRANT TRIGGER ON TABLE public.audit_log_archives TO service_role;

GRANT TRUNCATE ON TABLE public.audit_log_archives TO service_role;

GRANT UPDATE ON TABLE public.audit_log_archives TO service_role;

GRANT SELECT ON SEQUENCE public.audit_log_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.audit_log_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.audit_log_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.audit_log_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.audit_log_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.audit_log_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.audit_log_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.audit_log_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.audit_log_id_seq TO service_role;

GRANT DELETE ON TABLE public.audit_log TO service_role;

GRANT INSERT ON TABLE public.audit_log TO service_role;

GRANT MAINTAIN ON TABLE public.audit_log TO service_role;

GRANT REFERENCES ON TABLE public.audit_log TO service_role;

GRANT SELECT ON TABLE public.audit_log TO service_role;

GRANT TRIGGER ON TABLE public.audit_log TO service_role;

GRANT TRUNCATE ON TABLE public.audit_log TO service_role;

GRANT UPDATE ON TABLE public.audit_log TO service_role;

GRANT SELECT ON TABLE public.backup_exports TO authenticated;

GRANT DELETE ON TABLE public.backup_exports TO service_role;

GRANT INSERT ON TABLE public.backup_exports TO service_role;

GRANT MAINTAIN ON TABLE public.backup_exports TO service_role;

GRANT REFERENCES ON TABLE public.backup_exports TO service_role;

GRANT SELECT ON TABLE public.backup_exports TO service_role;

GRANT TRIGGER ON TABLE public.backup_exports TO service_role;

GRANT TRUNCATE ON TABLE public.backup_exports TO service_role;

GRANT UPDATE ON TABLE public.backup_exports TO service_role;

GRANT SELECT ON TABLE public.backup_storage_objects TO authenticated;

GRANT DELETE ON TABLE public.backup_storage_objects TO service_role;

GRANT INSERT ON TABLE public.backup_storage_objects TO service_role;

GRANT MAINTAIN ON TABLE public.backup_storage_objects TO service_role;

GRANT REFERENCES ON TABLE public.backup_storage_objects TO service_role;

GRANT SELECT ON TABLE public.backup_storage_objects TO service_role;

GRANT TRIGGER ON TABLE public.backup_storage_objects TO service_role;

GRANT TRUNCATE ON TABLE public.backup_storage_objects TO service_role;

GRANT UPDATE ON TABLE public.backup_storage_objects TO service_role;

GRANT DELETE ON TABLE public.certificate_batches TO service_role;

GRANT INSERT ON TABLE public.certificate_batches TO service_role;

GRANT MAINTAIN ON TABLE public.certificate_batches TO service_role;

GRANT REFERENCES ON TABLE public.certificate_batches TO service_role;

GRANT SELECT ON TABLE public.certificate_batches TO service_role;

GRANT TRIGGER ON TABLE public.certificate_batches TO service_role;

GRANT TRUNCATE ON TABLE public.certificate_batches TO service_role;

GRANT UPDATE ON TABLE public.certificate_batches TO service_role;

GRANT SELECT ON SEQUENCE public.certificate_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.certificate_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.certificate_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.certificate_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.certificate_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.certificate_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.certificate_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.certificate_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.certificate_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.certificate_events TO service_role;

GRANT INSERT ON TABLE public.certificate_events TO service_role;

GRANT MAINTAIN ON TABLE public.certificate_events TO service_role;

GRANT REFERENCES ON TABLE public.certificate_events TO service_role;

GRANT SELECT ON TABLE public.certificate_events TO service_role;

GRANT TRIGGER ON TABLE public.certificate_events TO service_role;

GRANT TRUNCATE ON TABLE public.certificate_events TO service_role;

GRANT UPDATE ON TABLE public.certificate_events TO service_role;

GRANT SELECT ON SEQUENCE public.certificate_number_seq TO anon;

GRANT UPDATE ON SEQUENCE public.certificate_number_seq TO anon;

GRANT USAGE ON SEQUENCE public.certificate_number_seq TO anon;

GRANT SELECT ON SEQUENCE public.certificate_number_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.certificate_number_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.certificate_number_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.certificate_number_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.certificate_number_seq TO service_role;

GRANT USAGE ON SEQUENCE public.certificate_number_seq TO service_role;

GRANT DELETE ON TABLE public.certificate_templates TO service_role;

GRANT INSERT ON TABLE public.certificate_templates TO service_role;

GRANT MAINTAIN ON TABLE public.certificate_templates TO service_role;

GRANT REFERENCES ON TABLE public.certificate_templates TO service_role;

GRANT SELECT ON TABLE public.certificate_templates TO service_role;

GRANT TRIGGER ON TABLE public.certificate_templates TO service_role;

GRANT TRUNCATE ON TABLE public.certificate_templates TO service_role;

GRANT UPDATE ON TABLE public.certificate_templates TO service_role;

GRANT DELETE ON TABLE public.certificates TO service_role;

GRANT INSERT ON TABLE public.certificates TO service_role;

GRANT MAINTAIN ON TABLE public.certificates TO service_role;

GRANT REFERENCES ON TABLE public.certificates TO service_role;

GRANT SELECT ON TABLE public.certificates TO service_role;

GRANT TRIGGER ON TABLE public.certificates TO service_role;

GRANT TRUNCATE ON TABLE public.certificates TO service_role;

GRANT UPDATE ON TABLE public.certificates TO service_role;

GRANT DELETE ON TABLE public.class_attendance_registers TO service_role;

GRANT INSERT ON TABLE public.class_attendance_registers TO service_role;

GRANT MAINTAIN ON TABLE public.class_attendance_registers TO service_role;

GRANT REFERENCES ON TABLE public.class_attendance_registers TO service_role;

GRANT SELECT ON TABLE public.class_attendance_registers TO service_role;

GRANT TRIGGER ON TABLE public.class_attendance_registers TO service_role;

GRANT TRUNCATE ON TABLE public.class_attendance_registers TO service_role;

GRANT UPDATE ON TABLE public.class_attendance_registers TO service_role;

GRANT MAINTAIN ON TABLE public.class_subjects TO authenticated;

GRANT SELECT ON TABLE public.class_subjects TO authenticated;

GRANT DELETE ON TABLE public.class_subjects TO service_role;

GRANT INSERT ON TABLE public.class_subjects TO service_role;

GRANT MAINTAIN ON TABLE public.class_subjects TO service_role;

GRANT REFERENCES ON TABLE public.class_subjects TO service_role;

GRANT SELECT ON TABLE public.class_subjects TO service_role;

GRANT TRIGGER ON TABLE public.class_subjects TO service_role;

GRANT TRUNCATE ON TABLE public.class_subjects TO service_role;

GRANT UPDATE ON TABLE public.class_subjects TO service_role;

GRANT DELETE ON TABLE public.class_timetable_entries TO service_role;

GRANT INSERT ON TABLE public.class_timetable_entries TO service_role;

GRANT MAINTAIN ON TABLE public.class_timetable_entries TO service_role;

GRANT REFERENCES ON TABLE public.class_timetable_entries TO service_role;

GRANT SELECT ON TABLE public.class_timetable_entries TO service_role;

GRANT TRIGGER ON TABLE public.class_timetable_entries TO service_role;

GRANT TRUNCATE ON TABLE public.class_timetable_entries TO service_role;

GRANT UPDATE ON TABLE public.class_timetable_entries TO service_role;

GRANT MAINTAIN ON TABLE public.classes TO authenticated;

GRANT SELECT ON TABLE public.classes TO authenticated;

GRANT DELETE ON TABLE public.classes TO service_role;

GRANT INSERT ON TABLE public.classes TO service_role;

GRANT MAINTAIN ON TABLE public.classes TO service_role;

GRANT REFERENCES ON TABLE public.classes TO service_role;

GRANT SELECT ON TABLE public.classes TO service_role;

GRANT TRIGGER ON TABLE public.classes TO service_role;

GRANT TRUNCATE ON TABLE public.classes TO service_role;

GRANT UPDATE ON TABLE public.classes TO service_role;

GRANT SELECT ON SEQUENCE public.client_error_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.client_error_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.client_error_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.client_error_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.client_error_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.client_error_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.client_error_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.client_error_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.client_error_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.client_error_events TO service_role;

GRANT INSERT ON TABLE public.client_error_events TO service_role;

GRANT MAINTAIN ON TABLE public.client_error_events TO service_role;

GRANT REFERENCES ON TABLE public.client_error_events TO service_role;

GRANT SELECT ON TABLE public.client_error_events TO service_role;

GRANT TRIGGER ON TABLE public.client_error_events TO service_role;

GRANT TRUNCATE ON TABLE public.client_error_events TO service_role;

GRANT UPDATE ON TABLE public.client_error_events TO service_role;

GRANT DELETE ON TABLE public.communication_campaigns TO service_role;

GRANT INSERT ON TABLE public.communication_campaigns TO service_role;

GRANT MAINTAIN ON TABLE public.communication_campaigns TO service_role;

GRANT REFERENCES ON TABLE public.communication_campaigns TO service_role;

GRANT SELECT ON TABLE public.communication_campaigns TO service_role;

GRANT TRIGGER ON TABLE public.communication_campaigns TO service_role;

GRANT TRUNCATE ON TABLE public.communication_campaigns TO service_role;

GRANT UPDATE ON TABLE public.communication_campaigns TO service_role;

GRANT DELETE ON TABLE public.communication_deliveries TO service_role;

GRANT INSERT ON TABLE public.communication_deliveries TO service_role;

GRANT MAINTAIN ON TABLE public.communication_deliveries TO service_role;

GRANT REFERENCES ON TABLE public.communication_deliveries TO service_role;

GRANT SELECT ON TABLE public.communication_deliveries TO service_role;

GRANT TRIGGER ON TABLE public.communication_deliveries TO service_role;

GRANT TRUNCATE ON TABLE public.communication_deliveries TO service_role;

GRANT UPDATE ON TABLE public.communication_deliveries TO service_role;

GRANT DELETE ON TABLE public.communication_messages TO service_role;

GRANT INSERT ON TABLE public.communication_messages TO service_role;

GRANT MAINTAIN ON TABLE public.communication_messages TO service_role;

GRANT REFERENCES ON TABLE public.communication_messages TO service_role;

GRANT SELECT ON TABLE public.communication_messages TO service_role;

GRANT TRIGGER ON TABLE public.communication_messages TO service_role;

GRANT TRUNCATE ON TABLE public.communication_messages TO service_role;

GRANT UPDATE ON TABLE public.communication_messages TO service_role;

GRANT DELETE ON TABLE public.communication_templates TO service_role;

GRANT INSERT ON TABLE public.communication_templates TO service_role;

GRANT MAINTAIN ON TABLE public.communication_templates TO service_role;

GRANT REFERENCES ON TABLE public.communication_templates TO service_role;

GRANT SELECT ON TABLE public.communication_templates TO service_role;

GRANT TRIGGER ON TABLE public.communication_templates TO service_role;

GRANT TRUNCATE ON TABLE public.communication_templates TO service_role;

GRANT UPDATE ON TABLE public.communication_templates TO service_role;

GRANT DELETE ON TABLE public.communication_thread_participants TO service_role;

GRANT INSERT ON TABLE public.communication_thread_participants TO service_role;

GRANT MAINTAIN ON TABLE public.communication_thread_participants TO service_role;

GRANT REFERENCES ON TABLE public.communication_thread_participants TO service_role;

GRANT SELECT ON TABLE public.communication_thread_participants TO service_role;

GRANT TRIGGER ON TABLE public.communication_thread_participants TO service_role;

GRANT TRUNCATE ON TABLE public.communication_thread_participants TO service_role;

GRANT UPDATE ON TABLE public.communication_thread_participants TO service_role;

GRANT DELETE ON TABLE public.communication_threads TO service_role;

GRANT INSERT ON TABLE public.communication_threads TO service_role;

GRANT MAINTAIN ON TABLE public.communication_threads TO service_role;

GRANT REFERENCES ON TABLE public.communication_threads TO service_role;

GRANT SELECT ON TABLE public.communication_threads TO service_role;

GRANT TRIGGER ON TABLE public.communication_threads TO service_role;

GRANT TRUNCATE ON TABLE public.communication_threads TO service_role;

GRANT UPDATE ON TABLE public.communication_threads TO service_role;

GRANT DELETE ON TABLE public.data_retention_policies TO service_role;

GRANT INSERT ON TABLE public.data_retention_policies TO service_role;

GRANT MAINTAIN ON TABLE public.data_retention_policies TO service_role;

GRANT REFERENCES ON TABLE public.data_retention_policies TO service_role;

GRANT SELECT ON TABLE public.data_retention_policies TO service_role;

GRANT TRIGGER ON TABLE public.data_retention_policies TO service_role;

GRANT TRUNCATE ON TABLE public.data_retention_policies TO service_role;

GRANT UPDATE ON TABLE public.data_retention_policies TO service_role;

GRANT DELETE ON TABLE public.discipline_actions TO service_role;

GRANT INSERT ON TABLE public.discipline_actions TO service_role;

GRANT MAINTAIN ON TABLE public.discipline_actions TO service_role;

GRANT REFERENCES ON TABLE public.discipline_actions TO service_role;

GRANT SELECT ON TABLE public.discipline_actions TO service_role;

GRANT TRIGGER ON TABLE public.discipline_actions TO service_role;

GRANT TRUNCATE ON TABLE public.discipline_actions TO service_role;

GRANT UPDATE ON TABLE public.discipline_actions TO service_role;

GRANT DELETE ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT INSERT ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT MAINTAIN ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT REFERENCES ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT SELECT ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT TRIGGER ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT TRUNCATE ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT UPDATE ON TABLE public.discipline_guardian_acknowledgements TO service_role;

GRANT DELETE ON TABLE public.discipline_incidents TO service_role;

GRANT INSERT ON TABLE public.discipline_incidents TO service_role;

GRANT MAINTAIN ON TABLE public.discipline_incidents TO service_role;

GRANT REFERENCES ON TABLE public.discipline_incidents TO service_role;

GRANT SELECT ON TABLE public.discipline_incidents TO service_role;

GRANT TRIGGER ON TABLE public.discipline_incidents TO service_role;

GRANT TRUNCATE ON TABLE public.discipline_incidents TO service_role;

GRANT UPDATE ON TABLE public.discipline_incidents TO service_role;

GRANT SELECT ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.emergency_academic_delegation_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT INSERT ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT MAINTAIN ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT REFERENCES ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT SELECT ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT TRIGGER ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT TRUNCATE ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT UPDATE ON TABLE public.emergency_academic_delegation_events TO service_role;

GRANT DELETE ON TABLE public.emergency_academic_delegations TO service_role;

GRANT INSERT ON TABLE public.emergency_academic_delegations TO service_role;

GRANT MAINTAIN ON TABLE public.emergency_academic_delegations TO service_role;

GRANT REFERENCES ON TABLE public.emergency_academic_delegations TO service_role;

GRANT SELECT ON TABLE public.emergency_academic_delegations TO service_role;

GRANT TRIGGER ON TABLE public.emergency_academic_delegations TO service_role;

GRANT TRUNCATE ON TABLE public.emergency_academic_delegations TO service_role;

GRANT UPDATE ON TABLE public.emergency_academic_delegations TO service_role;

GRANT SELECT ON TABLE public.enrollments TO authenticated;

GRANT DELETE ON TABLE public.enrollments TO service_role;

GRANT INSERT ON TABLE public.enrollments TO service_role;

GRANT MAINTAIN ON TABLE public.enrollments TO service_role;

GRANT REFERENCES ON TABLE public.enrollments TO service_role;

GRANT SELECT ON TABLE public.enrollments TO service_role;

GRANT TRIGGER ON TABLE public.enrollments TO service_role;

GRANT TRUNCATE ON TABLE public.enrollments TO service_role;

GRANT UPDATE ON TABLE public.enrollments TO service_role;

GRANT DELETE ON TABLE public.finance_fee_account_balances TO service_role;

GRANT INSERT ON TABLE public.finance_fee_account_balances TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_account_balances TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_account_balances TO service_role;

GRANT SELECT ON TABLE public.finance_fee_account_balances TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_account_balances TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_account_balances TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_account_balances TO service_role;

GRANT DELETE ON TABLE public.finance_fee_accounts TO service_role;

GRANT INSERT ON TABLE public.finance_fee_accounts TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_accounts TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_accounts TO service_role;

GRANT SELECT ON TABLE public.finance_fee_accounts TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_accounts TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_accounts TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_accounts TO service_role;

GRANT DELETE ON TABLE public.finance_fee_allocations TO service_role;

GRANT INSERT ON TABLE public.finance_fee_allocations TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_allocations TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_allocations TO service_role;

GRANT SELECT ON TABLE public.finance_fee_allocations TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_allocations TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_allocations TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_allocations TO service_role;

GRANT DELETE ON TABLE public.finance_fee_group_classes TO service_role;

GRANT INSERT ON TABLE public.finance_fee_group_classes TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_group_classes TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_group_classes TO service_role;

GRANT SELECT ON TABLE public.finance_fee_group_classes TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_group_classes TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_group_classes TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_group_classes TO service_role;

GRANT DELETE ON TABLE public.finance_fee_groups TO service_role;

GRANT INSERT ON TABLE public.finance_fee_groups TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_groups TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_groups TO service_role;

GRANT SELECT ON TABLE public.finance_fee_groups TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_groups TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_groups TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_groups TO service_role;

GRANT DELETE ON TABLE public.finance_fee_invoices TO service_role;

GRANT INSERT ON TABLE public.finance_fee_invoices TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_invoices TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_invoices TO service_role;

GRANT SELECT ON TABLE public.finance_fee_invoices TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_invoices TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_invoices TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_invoices TO service_role;

GRANT DELETE ON TABLE public.finance_fee_schedules TO service_role;

GRANT INSERT ON TABLE public.finance_fee_schedules TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_schedules TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_schedules TO service_role;

GRANT SELECT ON TABLE public.finance_fee_schedules TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_schedules TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_schedules TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_schedules TO service_role;

GRANT DELETE ON TABLE public.finance_fee_transactions TO service_role;

GRANT INSERT ON TABLE public.finance_fee_transactions TO service_role;

GRANT MAINTAIN ON TABLE public.finance_fee_transactions TO service_role;

GRANT REFERENCES ON TABLE public.finance_fee_transactions TO service_role;

GRANT SELECT ON TABLE public.finance_fee_transactions TO service_role;

GRANT TRIGGER ON TABLE public.finance_fee_transactions TO service_role;

GRANT TRUNCATE ON TABLE public.finance_fee_transactions TO service_role;

GRANT UPDATE ON TABLE public.finance_fee_transactions TO service_role;

GRANT DELETE ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT INSERT ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT MAINTAIN ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT REFERENCES ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT SELECT ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT TRIGGER ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT TRUNCATE ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT UPDATE ON TABLE public.finance_guardian_contact_events TO service_role;

GRANT DELETE ON TABLE public.finance_hold_overrides TO service_role;

GRANT INSERT ON TABLE public.finance_hold_overrides TO service_role;

GRANT MAINTAIN ON TABLE public.finance_hold_overrides TO service_role;

GRANT REFERENCES ON TABLE public.finance_hold_overrides TO service_role;

GRANT SELECT ON TABLE public.finance_hold_overrides TO service_role;

GRANT TRIGGER ON TABLE public.finance_hold_overrides TO service_role;

GRANT TRUNCATE ON TABLE public.finance_hold_overrides TO service_role;

GRANT UPDATE ON TABLE public.finance_hold_overrides TO service_role;

GRANT DELETE ON TABLE public.finance_hold_policy TO service_role;

GRANT INSERT ON TABLE public.finance_hold_policy TO service_role;

GRANT MAINTAIN ON TABLE public.finance_hold_policy TO service_role;

GRANT REFERENCES ON TABLE public.finance_hold_policy TO service_role;

GRANT SELECT ON TABLE public.finance_hold_policy TO service_role;

GRANT TRIGGER ON TABLE public.finance_hold_policy TO service_role;

GRANT TRUNCATE ON TABLE public.finance_hold_policy TO service_role;

GRANT UPDATE ON TABLE public.finance_hold_policy TO service_role;

GRANT SELECT ON SEQUENCE public.finance_invoice_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.finance_invoice_seq TO service_role;

GRANT USAGE ON SEQUENCE public.finance_invoice_seq TO service_role;

GRANT DELETE ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT INSERT ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT MAINTAIN ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT REFERENCES ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT SELECT ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT TRIGGER ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT TRUNCATE ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT UPDATE ON TABLE public.finance_payroll_item_lines TO service_role;

GRANT DELETE ON TABLE public.finance_payroll_items TO service_role;

GRANT INSERT ON TABLE public.finance_payroll_items TO service_role;

GRANT MAINTAIN ON TABLE public.finance_payroll_items TO service_role;

GRANT REFERENCES ON TABLE public.finance_payroll_items TO service_role;

GRANT SELECT ON TABLE public.finance_payroll_items TO service_role;

GRANT TRIGGER ON TABLE public.finance_payroll_items TO service_role;

GRANT TRUNCATE ON TABLE public.finance_payroll_items TO service_role;

GRANT UPDATE ON TABLE public.finance_payroll_items TO service_role;

GRANT SELECT ON SEQUENCE public.finance_payroll_no_seq TO anon;

GRANT UPDATE ON SEQUENCE public.finance_payroll_no_seq TO anon;

GRANT USAGE ON SEQUENCE public.finance_payroll_no_seq TO anon;

GRANT SELECT ON SEQUENCE public.finance_payroll_no_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.finance_payroll_no_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.finance_payroll_no_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.finance_payroll_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.finance_payroll_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.finance_payroll_no_seq TO service_role;

GRANT DELETE ON TABLE public.finance_payroll_profiles TO service_role;

GRANT INSERT ON TABLE public.finance_payroll_profiles TO service_role;

GRANT MAINTAIN ON TABLE public.finance_payroll_profiles TO service_role;

GRANT REFERENCES ON TABLE public.finance_payroll_profiles TO service_role;

GRANT SELECT ON TABLE public.finance_payroll_profiles TO service_role;

GRANT TRIGGER ON TABLE public.finance_payroll_profiles TO service_role;

GRANT TRUNCATE ON TABLE public.finance_payroll_profiles TO service_role;

GRANT UPDATE ON TABLE public.finance_payroll_profiles TO service_role;

GRANT DELETE ON TABLE public.finance_payroll_rules TO service_role;

GRANT INSERT ON TABLE public.finance_payroll_rules TO service_role;

GRANT MAINTAIN ON TABLE public.finance_payroll_rules TO service_role;

GRANT REFERENCES ON TABLE public.finance_payroll_rules TO service_role;

GRANT SELECT ON TABLE public.finance_payroll_rules TO service_role;

GRANT TRIGGER ON TABLE public.finance_payroll_rules TO service_role;

GRANT TRUNCATE ON TABLE public.finance_payroll_rules TO service_role;

GRANT UPDATE ON TABLE public.finance_payroll_rules TO service_role;

GRANT DELETE ON TABLE public.finance_payroll_runs TO service_role;

GRANT INSERT ON TABLE public.finance_payroll_runs TO service_role;

GRANT MAINTAIN ON TABLE public.finance_payroll_runs TO service_role;

GRANT REFERENCES ON TABLE public.finance_payroll_runs TO service_role;

GRANT SELECT ON TABLE public.finance_payroll_runs TO service_role;

GRANT TRIGGER ON TABLE public.finance_payroll_runs TO service_role;

GRANT TRUNCATE ON TABLE public.finance_payroll_runs TO service_role;

GRANT UPDATE ON TABLE public.finance_payroll_runs TO service_role;

GRANT SELECT ON SEQUENCE public.finance_receipt_seq TO anon;

GRANT UPDATE ON SEQUENCE public.finance_receipt_seq TO anon;

GRANT USAGE ON SEQUENCE public.finance_receipt_seq TO anon;

GRANT SELECT ON SEQUENCE public.finance_receipt_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.finance_receipt_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.finance_receipt_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.finance_receipt_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.finance_receipt_seq TO service_role;

GRANT USAGE ON SEQUENCE public.finance_receipt_seq TO service_role;

GRANT DELETE ON TABLE public.finance_salary_grades TO service_role;

GRANT INSERT ON TABLE public.finance_salary_grades TO service_role;

GRANT MAINTAIN ON TABLE public.finance_salary_grades TO service_role;

GRANT REFERENCES ON TABLE public.finance_salary_grades TO service_role;

GRANT SELECT ON TABLE public.finance_salary_grades TO service_role;

GRANT TRIGGER ON TABLE public.finance_salary_grades TO service_role;

GRANT TRUNCATE ON TABLE public.finance_salary_grades TO service_role;

GRANT UPDATE ON TABLE public.finance_salary_grades TO service_role;

GRANT DELETE ON TABLE public.finance_teacher_loans TO service_role;

GRANT INSERT ON TABLE public.finance_teacher_loans TO service_role;

GRANT MAINTAIN ON TABLE public.finance_teacher_loans TO service_role;

GRANT REFERENCES ON TABLE public.finance_teacher_loans TO service_role;

GRANT SELECT ON TABLE public.finance_teacher_loans TO service_role;

GRANT TRIGGER ON TABLE public.finance_teacher_loans TO service_role;

GRANT TRUNCATE ON TABLE public.finance_teacher_loans TO service_role;

GRANT UPDATE ON TABLE public.finance_teacher_loans TO service_role;

GRANT MAINTAIN ON TABLE public.grading_scales TO authenticated;

GRANT SELECT ON TABLE public.grading_scales TO authenticated;

GRANT DELETE ON TABLE public.grading_scales TO service_role;

GRANT INSERT ON TABLE public.grading_scales TO service_role;

GRANT MAINTAIN ON TABLE public.grading_scales TO service_role;

GRANT REFERENCES ON TABLE public.grading_scales TO service_role;

GRANT SELECT ON TABLE public.grading_scales TO service_role;

GRANT TRIGGER ON TABLE public.grading_scales TO service_role;

GRANT TRUNCATE ON TABLE public.grading_scales TO service_role;

GRANT UPDATE ON TABLE public.grading_scales TO service_role;

GRANT SELECT ON TABLE public.guardian_links TO authenticated;

GRANT DELETE ON TABLE public.guardian_links TO service_role;

GRANT INSERT ON TABLE public.guardian_links TO service_role;

GRANT MAINTAIN ON TABLE public.guardian_links TO service_role;

GRANT REFERENCES ON TABLE public.guardian_links TO service_role;

GRANT SELECT ON TABLE public.guardian_links TO service_role;

GRANT TRIGGER ON TABLE public.guardian_links TO service_role;

GRANT TRUNCATE ON TABLE public.guardian_links TO service_role;

GRANT UPDATE ON TABLE public.guardian_links TO service_role;

GRANT SELECT ON TABLE public.headteachers TO authenticated;

GRANT DELETE ON TABLE public.headteachers TO service_role;

GRANT INSERT ON TABLE public.headteachers TO service_role;

GRANT MAINTAIN ON TABLE public.headteachers TO service_role;

GRANT REFERENCES ON TABLE public.headteachers TO service_role;

GRANT SELECT ON TABLE public.headteachers TO service_role;

GRANT TRIGGER ON TABLE public.headteachers TO service_role;

GRANT TRUNCATE ON TABLE public.headteachers TO service_role;

GRANT UPDATE ON TABLE public.headteachers TO service_role;

GRANT DELETE ON TABLE public.health_immunizations TO service_role;

GRANT INSERT ON TABLE public.health_immunizations TO service_role;

GRANT MAINTAIN ON TABLE public.health_immunizations TO service_role;

GRANT REFERENCES ON TABLE public.health_immunizations TO service_role;

GRANT SELECT ON TABLE public.health_immunizations TO service_role;

GRANT TRIGGER ON TABLE public.health_immunizations TO service_role;

GRANT TRUNCATE ON TABLE public.health_immunizations TO service_role;

GRANT UPDATE ON TABLE public.health_immunizations TO service_role;

GRANT DELETE ON TABLE public.health_medication_administrations TO service_role;

GRANT INSERT ON TABLE public.health_medication_administrations TO service_role;

GRANT MAINTAIN ON TABLE public.health_medication_administrations TO service_role;

GRANT REFERENCES ON TABLE public.health_medication_administrations TO service_role;

GRANT SELECT ON TABLE public.health_medication_administrations TO service_role;

GRANT TRIGGER ON TABLE public.health_medication_administrations TO service_role;

GRANT TRUNCATE ON TABLE public.health_medication_administrations TO service_role;

GRANT UPDATE ON TABLE public.health_medication_administrations TO service_role;

GRANT DELETE ON TABLE public.health_student_profiles TO service_role;

GRANT INSERT ON TABLE public.health_student_profiles TO service_role;

GRANT MAINTAIN ON TABLE public.health_student_profiles TO service_role;

GRANT REFERENCES ON TABLE public.health_student_profiles TO service_role;

GRANT SELECT ON TABLE public.health_student_profiles TO service_role;

GRANT TRIGGER ON TABLE public.health_student_profiles TO service_role;

GRANT TRUNCATE ON TABLE public.health_student_profiles TO service_role;

GRANT UPDATE ON TABLE public.health_student_profiles TO service_role;

GRANT DELETE ON TABLE public.health_visits TO service_role;

GRANT INSERT ON TABLE public.health_visits TO service_role;

GRANT MAINTAIN ON TABLE public.health_visits TO service_role;

GRANT REFERENCES ON TABLE public.health_visits TO service_role;

GRANT SELECT ON TABLE public.health_visits TO service_role;

GRANT TRIGGER ON TABLE public.health_visits TO service_role;

GRANT TRUNCATE ON TABLE public.health_visits TO service_role;

GRANT UPDATE ON TABLE public.health_visits TO service_role;

GRANT DELETE ON TABLE public.hostel_allocations TO service_role;

GRANT INSERT ON TABLE public.hostel_allocations TO service_role;

GRANT MAINTAIN ON TABLE public.hostel_allocations TO service_role;

GRANT REFERENCES ON TABLE public.hostel_allocations TO service_role;

GRANT SELECT ON TABLE public.hostel_allocations TO service_role;

GRANT TRIGGER ON TABLE public.hostel_allocations TO service_role;

GRANT TRUNCATE ON TABLE public.hostel_allocations TO service_role;

GRANT UPDATE ON TABLE public.hostel_allocations TO service_role;

GRANT DELETE ON TABLE public.hostel_beds TO service_role;

GRANT INSERT ON TABLE public.hostel_beds TO service_role;

GRANT MAINTAIN ON TABLE public.hostel_beds TO service_role;

GRANT REFERENCES ON TABLE public.hostel_beds TO service_role;

GRANT SELECT ON TABLE public.hostel_beds TO service_role;

GRANT TRIGGER ON TABLE public.hostel_beds TO service_role;

GRANT TRUNCATE ON TABLE public.hostel_beds TO service_role;

GRANT UPDATE ON TABLE public.hostel_beds TO service_role;

GRANT DELETE ON TABLE public.hostel_houses TO service_role;

GRANT INSERT ON TABLE public.hostel_houses TO service_role;

GRANT MAINTAIN ON TABLE public.hostel_houses TO service_role;

GRANT REFERENCES ON TABLE public.hostel_houses TO service_role;

GRANT SELECT ON TABLE public.hostel_houses TO service_role;

GRANT TRIGGER ON TABLE public.hostel_houses TO service_role;

GRANT TRUNCATE ON TABLE public.hostel_houses TO service_role;

GRANT UPDATE ON TABLE public.hostel_houses TO service_role;

GRANT DELETE ON TABLE public.hostel_incidents TO service_role;

GRANT INSERT ON TABLE public.hostel_incidents TO service_role;

GRANT MAINTAIN ON TABLE public.hostel_incidents TO service_role;

GRANT REFERENCES ON TABLE public.hostel_incidents TO service_role;

GRANT SELECT ON TABLE public.hostel_incidents TO service_role;

GRANT TRIGGER ON TABLE public.hostel_incidents TO service_role;

GRANT TRUNCATE ON TABLE public.hostel_incidents TO service_role;

GRANT UPDATE ON TABLE public.hostel_incidents TO service_role;

GRANT DELETE ON TABLE public.hostel_movements TO service_role;

GRANT INSERT ON TABLE public.hostel_movements TO service_role;

GRANT MAINTAIN ON TABLE public.hostel_movements TO service_role;

GRANT REFERENCES ON TABLE public.hostel_movements TO service_role;

GRANT SELECT ON TABLE public.hostel_movements TO service_role;

GRANT TRIGGER ON TABLE public.hostel_movements TO service_role;

GRANT TRUNCATE ON TABLE public.hostel_movements TO service_role;

GRANT UPDATE ON TABLE public.hostel_movements TO service_role;

GRANT DELETE ON TABLE public.hostel_rooms TO service_role;

GRANT INSERT ON TABLE public.hostel_rooms TO service_role;

GRANT MAINTAIN ON TABLE public.hostel_rooms TO service_role;

GRANT REFERENCES ON TABLE public.hostel_rooms TO service_role;

GRANT SELECT ON TABLE public.hostel_rooms TO service_role;

GRANT TRIGGER ON TABLE public.hostel_rooms TO service_role;

GRANT TRUNCATE ON TABLE public.hostel_rooms TO service_role;

GRANT UPDATE ON TABLE public.hostel_rooms TO service_role;

GRANT DELETE ON TABLE public.hr_employment_events TO service_role;

GRANT INSERT ON TABLE public.hr_employment_events TO service_role;

GRANT MAINTAIN ON TABLE public.hr_employment_events TO service_role;

GRANT REFERENCES ON TABLE public.hr_employment_events TO service_role;

GRANT SELECT ON TABLE public.hr_employment_events TO service_role;

GRANT TRIGGER ON TABLE public.hr_employment_events TO service_role;

GRANT TRUNCATE ON TABLE public.hr_employment_events TO service_role;

GRANT UPDATE ON TABLE public.hr_employment_events TO service_role;

GRANT DELETE ON TABLE public.hr_leave_requests TO service_role;

GRANT INSERT ON TABLE public.hr_leave_requests TO service_role;

GRANT MAINTAIN ON TABLE public.hr_leave_requests TO service_role;

GRANT REFERENCES ON TABLE public.hr_leave_requests TO service_role;

GRANT SELECT ON TABLE public.hr_leave_requests TO service_role;

GRANT TRIGGER ON TABLE public.hr_leave_requests TO service_role;

GRANT TRUNCATE ON TABLE public.hr_leave_requests TO service_role;

GRANT UPDATE ON TABLE public.hr_leave_requests TO service_role;

GRANT DELETE ON TABLE public.hr_staff_documents TO service_role;

GRANT INSERT ON TABLE public.hr_staff_documents TO service_role;

GRANT MAINTAIN ON TABLE public.hr_staff_documents TO service_role;

GRANT REFERENCES ON TABLE public.hr_staff_documents TO service_role;

GRANT SELECT ON TABLE public.hr_staff_documents TO service_role;

GRANT TRIGGER ON TABLE public.hr_staff_documents TO service_role;

GRANT TRUNCATE ON TABLE public.hr_staff_documents TO service_role;

GRANT UPDATE ON TABLE public.hr_staff_documents TO service_role;

GRANT DELETE ON TABLE public.hr_staff_members TO service_role;

GRANT INSERT ON TABLE public.hr_staff_members TO service_role;

GRANT MAINTAIN ON TABLE public.hr_staff_members TO service_role;

GRANT REFERENCES ON TABLE public.hr_staff_members TO service_role;

GRANT SELECT ON TABLE public.hr_staff_members TO service_role;

GRANT TRIGGER ON TABLE public.hr_staff_members TO service_role;

GRANT TRUNCATE ON TABLE public.hr_staff_members TO service_role;

GRANT UPDATE ON TABLE public.hr_staff_members TO service_role;

GRANT SELECT ON SEQUENCE public.hr_staff_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.hr_staff_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.hr_staff_no_seq TO service_role;

GRANT DELETE ON TABLE public.hr_staff_qualifications TO service_role;

GRANT INSERT ON TABLE public.hr_staff_qualifications TO service_role;

GRANT MAINTAIN ON TABLE public.hr_staff_qualifications TO service_role;

GRANT REFERENCES ON TABLE public.hr_staff_qualifications TO service_role;

GRANT SELECT ON TABLE public.hr_staff_qualifications TO service_role;

GRANT TRIGGER ON TABLE public.hr_staff_qualifications TO service_role;

GRANT TRUNCATE ON TABLE public.hr_staff_qualifications TO service_role;

GRANT UPDATE ON TABLE public.hr_staff_qualifications TO service_role;

GRANT SELECT ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.id_card_deletion_tombstones_id_seq TO service_role;

GRANT DELETE ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT INSERT ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT MAINTAIN ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT REFERENCES ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT SELECT ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT TRIGGER ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT TRUNCATE ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT UPDATE ON TABLE public.id_card_deletion_tombstones TO service_role;

GRANT SELECT ON SEQUENCE public.id_card_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.id_card_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.id_card_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.id_card_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.id_card_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.id_card_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.id_card_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.id_card_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.id_card_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.id_card_events TO service_role;

GRANT INSERT ON TABLE public.id_card_events TO service_role;

GRANT MAINTAIN ON TABLE public.id_card_events TO service_role;

GRANT REFERENCES ON TABLE public.id_card_events TO service_role;

GRANT SELECT ON TABLE public.id_card_events TO service_role;

GRANT TRIGGER ON TABLE public.id_card_events TO service_role;

GRANT TRUNCATE ON TABLE public.id_card_events TO service_role;

GRANT UPDATE ON TABLE public.id_card_events TO service_role;

GRANT DELETE ON TABLE public.id_card_settings TO service_role;

GRANT INSERT ON TABLE public.id_card_settings TO service_role;

GRANT MAINTAIN ON TABLE public.id_card_settings TO service_role;

GRANT REFERENCES ON TABLE public.id_card_settings TO service_role;

GRANT SELECT ON TABLE public.id_card_settings TO service_role;

GRANT TRIGGER ON TABLE public.id_card_settings TO service_role;

GRANT TRUNCATE ON TABLE public.id_card_settings TO service_role;

GRANT UPDATE ON TABLE public.id_card_settings TO service_role;

GRANT SELECT ON TABLE public.import_batches TO authenticated;

GRANT DELETE ON TABLE public.import_batches TO service_role;

GRANT INSERT ON TABLE public.import_batches TO service_role;

GRANT MAINTAIN ON TABLE public.import_batches TO service_role;

GRANT REFERENCES ON TABLE public.import_batches TO service_role;

GRANT SELECT ON TABLE public.import_batches TO service_role;

GRANT TRIGGER ON TABLE public.import_batches TO service_role;

GRANT TRUNCATE ON TABLE public.import_batches TO service_role;

GRANT UPDATE ON TABLE public.import_batches TO service_role;

GRANT SELECT ON SEQUENCE public.import_errors_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.import_errors_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.import_errors_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.import_errors_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.import_errors_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.import_errors_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.import_errors_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.import_errors_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.import_errors_id_seq TO service_role;

GRANT SELECT ON TABLE public.import_errors TO authenticated;

GRANT DELETE ON TABLE public.import_errors TO service_role;

GRANT INSERT ON TABLE public.import_errors TO service_role;

GRANT MAINTAIN ON TABLE public.import_errors TO service_role;

GRANT REFERENCES ON TABLE public.import_errors TO service_role;

GRANT SELECT ON TABLE public.import_errors TO service_role;

GRANT TRIGGER ON TABLE public.import_errors TO service_role;

GRANT TRUNCATE ON TABLE public.import_errors TO service_role;

GRANT UPDATE ON TABLE public.import_errors TO service_role;

GRANT DELETE ON TABLE public.inventory_asset_assignments TO service_role;

GRANT INSERT ON TABLE public.inventory_asset_assignments TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_asset_assignments TO service_role;

GRANT REFERENCES ON TABLE public.inventory_asset_assignments TO service_role;

GRANT SELECT ON TABLE public.inventory_asset_assignments TO service_role;

GRANT TRIGGER ON TABLE public.inventory_asset_assignments TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_asset_assignments TO service_role;

GRANT UPDATE ON TABLE public.inventory_asset_assignments TO service_role;

GRANT DELETE ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT INSERT ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT REFERENCES ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT SELECT ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT TRIGGER ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT UPDATE ON TABLE public.inventory_asset_maintenance TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_asset_tag_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_asset_tag_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_asset_tag_seq TO service_role;

GRANT DELETE ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT INSERT ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT REFERENCES ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT SELECT ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT TRIGGER ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT UPDATE ON TABLE public.inventory_asset_writeoffs TO service_role;

GRANT DELETE ON TABLE public.inventory_assets TO service_role;

GRANT INSERT ON TABLE public.inventory_assets TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_assets TO service_role;

GRANT REFERENCES ON TABLE public.inventory_assets TO service_role;

GRANT SELECT ON TABLE public.inventory_assets TO service_role;

GRANT TRIGGER ON TABLE public.inventory_assets TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_assets TO service_role;

GRANT UPDATE ON TABLE public.inventory_assets TO service_role;

GRANT DELETE ON TABLE public.inventory_events TO service_role;

GRANT INSERT ON TABLE public.inventory_events TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_events TO service_role;

GRANT REFERENCES ON TABLE public.inventory_events TO service_role;

GRANT SELECT ON TABLE public.inventory_events TO service_role;

GRANT TRIGGER ON TABLE public.inventory_events TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_events TO service_role;

GRANT UPDATE ON TABLE public.inventory_events TO service_role;

GRANT DELETE ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT INSERT ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT REFERENCES ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT SELECT ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT TRIGGER ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT UPDATE ON TABLE public.inventory_goods_receipt_lines TO service_role;

GRANT DELETE ON TABLE public.inventory_goods_receipts TO service_role;

GRANT INSERT ON TABLE public.inventory_goods_receipts TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_goods_receipts TO service_role;

GRANT REFERENCES ON TABLE public.inventory_goods_receipts TO service_role;

GRANT SELECT ON TABLE public.inventory_goods_receipts TO service_role;

GRANT TRIGGER ON TABLE public.inventory_goods_receipts TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_goods_receipts TO service_role;

GRANT UPDATE ON TABLE public.inventory_goods_receipts TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_grn_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_grn_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_grn_no_seq TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_item_code_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_item_code_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_item_code_seq TO service_role;

GRANT DELETE ON TABLE public.inventory_item_requests TO service_role;

GRANT INSERT ON TABLE public.inventory_item_requests TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_item_requests TO service_role;

GRANT REFERENCES ON TABLE public.inventory_item_requests TO service_role;

GRANT SELECT ON TABLE public.inventory_item_requests TO service_role;

GRANT TRIGGER ON TABLE public.inventory_item_requests TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_item_requests TO service_role;

GRANT UPDATE ON TABLE public.inventory_item_requests TO service_role;

GRANT DELETE ON TABLE public.inventory_items TO service_role;

GRANT INSERT ON TABLE public.inventory_items TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_items TO service_role;

GRANT REFERENCES ON TABLE public.inventory_items TO service_role;

GRANT SELECT ON TABLE public.inventory_items TO service_role;

GRANT TRIGGER ON TABLE public.inventory_items TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_items TO service_role;

GRANT UPDATE ON TABLE public.inventory_items TO service_role;

GRANT DELETE ON TABLE public.inventory_locations TO service_role;

GRANT INSERT ON TABLE public.inventory_locations TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_locations TO service_role;

GRANT REFERENCES ON TABLE public.inventory_locations TO service_role;

GRANT SELECT ON TABLE public.inventory_locations TO service_role;

GRANT TRIGGER ON TABLE public.inventory_locations TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_locations TO service_role;

GRANT UPDATE ON TABLE public.inventory_locations TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_po_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_po_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_po_no_seq TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_pr_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_pr_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_pr_no_seq TO service_role;

GRANT DELETE ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT INSERT ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT REFERENCES ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT SELECT ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT TRIGGER ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT UPDATE ON TABLE public.inventory_purchase_order_lines TO service_role;

GRANT DELETE ON TABLE public.inventory_purchase_orders TO service_role;

GRANT INSERT ON TABLE public.inventory_purchase_orders TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_purchase_orders TO service_role;

GRANT REFERENCES ON TABLE public.inventory_purchase_orders TO service_role;

GRANT SELECT ON TABLE public.inventory_purchase_orders TO service_role;

GRANT TRIGGER ON TABLE public.inventory_purchase_orders TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_purchase_orders TO service_role;

GRANT UPDATE ON TABLE public.inventory_purchase_orders TO service_role;

GRANT DELETE ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT INSERT ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT REFERENCES ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT SELECT ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT TRIGGER ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT UPDATE ON TABLE public.inventory_purchase_request_lines TO service_role;

GRANT DELETE ON TABLE public.inventory_purchase_requests TO service_role;

GRANT INSERT ON TABLE public.inventory_purchase_requests TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_purchase_requests TO service_role;

GRANT REFERENCES ON TABLE public.inventory_purchase_requests TO service_role;

GRANT SELECT ON TABLE public.inventory_purchase_requests TO service_role;

GRANT TRIGGER ON TABLE public.inventory_purchase_requests TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_purchase_requests TO service_role;

GRANT UPDATE ON TABLE public.inventory_purchase_requests TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_request_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_request_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_request_no_seq TO service_role;

GRANT DELETE ON TABLE public.inventory_settings TO service_role;

GRANT INSERT ON TABLE public.inventory_settings TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_settings TO service_role;

GRANT REFERENCES ON TABLE public.inventory_settings TO service_role;

GRANT SELECT ON TABLE public.inventory_settings TO service_role;

GRANT TRIGGER ON TABLE public.inventory_settings TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_settings TO service_role;

GRANT UPDATE ON TABLE public.inventory_settings TO service_role;

GRANT DELETE ON TABLE public.inventory_staff_access TO service_role;

GRANT INSERT ON TABLE public.inventory_staff_access TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_staff_access TO service_role;

GRANT REFERENCES ON TABLE public.inventory_staff_access TO service_role;

GRANT SELECT ON TABLE public.inventory_staff_access TO service_role;

GRANT TRIGGER ON TABLE public.inventory_staff_access TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_staff_access TO service_role;

GRANT UPDATE ON TABLE public.inventory_staff_access TO service_role;

GRANT DELETE ON TABLE public.inventory_stock_movements TO service_role;

GRANT INSERT ON TABLE public.inventory_stock_movements TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_stock_movements TO service_role;

GRANT REFERENCES ON TABLE public.inventory_stock_movements TO service_role;

GRANT SELECT ON TABLE public.inventory_stock_movements TO service_role;

GRANT TRIGGER ON TABLE public.inventory_stock_movements TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_stock_movements TO service_role;

GRANT UPDATE ON TABLE public.inventory_stock_movements TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_supplier_code_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_supplier_code_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_supplier_code_seq TO service_role;

GRANT DELETE ON TABLE public.inventory_suppliers TO service_role;

GRANT INSERT ON TABLE public.inventory_suppliers TO service_role;

GRANT MAINTAIN ON TABLE public.inventory_suppliers TO service_role;

GRANT REFERENCES ON TABLE public.inventory_suppliers TO service_role;

GRANT SELECT ON TABLE public.inventory_suppliers TO service_role;

GRANT TRIGGER ON TABLE public.inventory_suppliers TO service_role;

GRANT TRUNCATE ON TABLE public.inventory_suppliers TO service_role;

GRANT UPDATE ON TABLE public.inventory_suppliers TO service_role;

GRANT SELECT ON SEQUENCE public.inventory_writeoff_no_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.inventory_writeoff_no_seq TO service_role;

GRANT USAGE ON SEQUENCE public.inventory_writeoff_no_seq TO service_role;

GRANT SELECT ON SEQUENCE public.library_accession_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.library_accession_seq TO service_role;

GRANT USAGE ON SEQUENCE public.library_accession_seq TO service_role;

GRANT DELETE ON TABLE public.library_books TO service_role;

GRANT INSERT ON TABLE public.library_books TO service_role;

GRANT MAINTAIN ON TABLE public.library_books TO service_role;

GRANT REFERENCES ON TABLE public.library_books TO service_role;

GRANT SELECT ON TABLE public.library_books TO service_role;

GRANT TRIGGER ON TABLE public.library_books TO service_role;

GRANT TRUNCATE ON TABLE public.library_books TO service_role;

GRANT UPDATE ON TABLE public.library_books TO service_role;

GRANT DELETE ON TABLE public.library_copies TO service_role;

GRANT INSERT ON TABLE public.library_copies TO service_role;

GRANT MAINTAIN ON TABLE public.library_copies TO service_role;

GRANT REFERENCES ON TABLE public.library_copies TO service_role;

GRANT SELECT ON TABLE public.library_copies TO service_role;

GRANT TRIGGER ON TABLE public.library_copies TO service_role;

GRANT TRUNCATE ON TABLE public.library_copies TO service_role;

GRANT UPDATE ON TABLE public.library_copies TO service_role;

GRANT DELETE ON TABLE public.library_inventory_events TO service_role;

GRANT INSERT ON TABLE public.library_inventory_events TO service_role;

GRANT MAINTAIN ON TABLE public.library_inventory_events TO service_role;

GRANT REFERENCES ON TABLE public.library_inventory_events TO service_role;

GRANT SELECT ON TABLE public.library_inventory_events TO service_role;

GRANT TRIGGER ON TABLE public.library_inventory_events TO service_role;

GRANT TRUNCATE ON TABLE public.library_inventory_events TO service_role;

GRANT UPDATE ON TABLE public.library_inventory_events TO service_role;

GRANT DELETE ON TABLE public.library_loans TO service_role;

GRANT INSERT ON TABLE public.library_loans TO service_role;

GRANT MAINTAIN ON TABLE public.library_loans TO service_role;

GRANT REFERENCES ON TABLE public.library_loans TO service_role;

GRANT SELECT ON TABLE public.library_loans TO service_role;

GRANT TRIGGER ON TABLE public.library_loans TO service_role;

GRANT TRUNCATE ON TABLE public.library_loans TO service_role;

GRANT UPDATE ON TABLE public.library_loans TO service_role;

GRANT DELETE ON TABLE public.library_reservations TO service_role;

GRANT INSERT ON TABLE public.library_reservations TO service_role;

GRANT MAINTAIN ON TABLE public.library_reservations TO service_role;

GRANT REFERENCES ON TABLE public.library_reservations TO service_role;

GRANT SELECT ON TABLE public.library_reservations TO service_role;

GRANT TRIGGER ON TABLE public.library_reservations TO service_role;

GRANT TRUNCATE ON TABLE public.library_reservations TO service_role;

GRANT UPDATE ON TABLE public.library_reservations TO service_role;

GRANT DELETE ON TABLE public.library_settings TO service_role;

GRANT INSERT ON TABLE public.library_settings TO service_role;

GRANT MAINTAIN ON TABLE public.library_settings TO service_role;

GRANT REFERENCES ON TABLE public.library_settings TO service_role;

GRANT SELECT ON TABLE public.library_settings TO service_role;

GRANT TRIGGER ON TABLE public.library_settings TO service_role;

GRANT TRUNCATE ON TABLE public.library_settings TO service_role;

GRANT UPDATE ON TABLE public.library_settings TO service_role;

GRANT DELETE ON TABLE public.library_staff_access TO service_role;

GRANT INSERT ON TABLE public.library_staff_access TO service_role;

GRANT MAINTAIN ON TABLE public.library_staff_access TO service_role;

GRANT REFERENCES ON TABLE public.library_staff_access TO service_role;

GRANT SELECT ON TABLE public.library_staff_access TO service_role;

GRANT TRIGGER ON TABLE public.library_staff_access TO service_role;

GRANT TRUNCATE ON TABLE public.library_staff_access TO service_role;

GRANT UPDATE ON TABLE public.library_staff_access TO service_role;

GRANT DELETE ON TABLE public.license_binding_sessions TO service_role;

GRANT INSERT ON TABLE public.license_binding_sessions TO service_role;

GRANT MAINTAIN ON TABLE public.license_binding_sessions TO service_role;

GRANT REFERENCES ON TABLE public.license_binding_sessions TO service_role;

GRANT SELECT ON TABLE public.license_binding_sessions TO service_role;

GRANT TRIGGER ON TABLE public.license_binding_sessions TO service_role;

GRANT TRUNCATE ON TABLE public.license_binding_sessions TO service_role;

GRANT UPDATE ON TABLE public.license_binding_sessions TO service_role;

GRANT DELETE ON TABLE public.license_entitlement_overrides TO service_role;

GRANT INSERT ON TABLE public.license_entitlement_overrides TO service_role;

GRANT MAINTAIN ON TABLE public.license_entitlement_overrides TO service_role;

GRANT REFERENCES ON TABLE public.license_entitlement_overrides TO service_role;

GRANT SELECT ON TABLE public.license_entitlement_overrides TO service_role;

GRANT TRIGGER ON TABLE public.license_entitlement_overrides TO service_role;

GRANT TRUNCATE ON TABLE public.license_entitlement_overrides TO service_role;

GRANT UPDATE ON TABLE public.license_entitlement_overrides TO service_role;

GRANT SELECT ON SEQUENCE public.license_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.license_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.license_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.license_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.license_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.license_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.license_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.license_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.license_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.license_events TO service_role;

GRANT INSERT ON TABLE public.license_events TO service_role;

GRANT MAINTAIN ON TABLE public.license_events TO service_role;

GRANT REFERENCES ON TABLE public.license_events TO service_role;

GRANT SELECT ON TABLE public.license_events TO service_role;

GRANT TRIGGER ON TABLE public.license_events TO service_role;

GRANT TRUNCATE ON TABLE public.license_events TO service_role;

GRANT UPDATE ON TABLE public.license_events TO service_role;

GRANT DELETE ON TABLE public.license_feature_catalog TO service_role;

GRANT INSERT ON TABLE public.license_feature_catalog TO service_role;

GRANT MAINTAIN ON TABLE public.license_feature_catalog TO service_role;

GRANT REFERENCES ON TABLE public.license_feature_catalog TO service_role;

GRANT SELECT ON TABLE public.license_feature_catalog TO service_role;

GRANT TRIGGER ON TABLE public.license_feature_catalog TO service_role;

GRANT TRUNCATE ON TABLE public.license_feature_catalog TO service_role;

GRANT UPDATE ON TABLE public.license_feature_catalog TO service_role;

GRANT SELECT ON SEQUENCE public.license_plan_revisions_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.license_plan_revisions_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.license_plan_revisions_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.license_plan_revisions_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.license_plan_revisions_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.license_plan_revisions_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.license_plan_revisions_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.license_plan_revisions_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.license_plan_revisions_id_seq TO service_role;

GRANT DELETE ON TABLE public.license_plan_revisions TO service_role;

GRANT INSERT ON TABLE public.license_plan_revisions TO service_role;

GRANT MAINTAIN ON TABLE public.license_plan_revisions TO service_role;

GRANT REFERENCES ON TABLE public.license_plan_revisions TO service_role;

GRANT SELECT ON TABLE public.license_plan_revisions TO service_role;

GRANT TRIGGER ON TABLE public.license_plan_revisions TO service_role;

GRANT TRUNCATE ON TABLE public.license_plan_revisions TO service_role;

GRANT UPDATE ON TABLE public.license_plan_revisions TO service_role;

GRANT DELETE ON TABLE public.license_plans TO service_role;

GRANT INSERT ON TABLE public.license_plans TO service_role;

GRANT MAINTAIN ON TABLE public.license_plans TO service_role;

GRANT REFERENCES ON TABLE public.license_plans TO service_role;

GRANT SELECT ON TABLE public.license_plans TO service_role;

GRANT TRIGGER ON TABLE public.license_plans TO service_role;

GRANT TRUNCATE ON TABLE public.license_plans TO service_role;

GRANT UPDATE ON TABLE public.license_plans TO service_role;

GRANT SELECT ON SEQUENCE public.license_verification_logs_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.license_verification_logs_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.license_verification_logs_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.license_verification_logs_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.license_verification_logs_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.license_verification_logs_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.license_verification_logs_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.license_verification_logs_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.license_verification_logs_id_seq TO service_role;

GRANT DELETE ON TABLE public.license_verification_logs TO service_role;

GRANT INSERT ON TABLE public.license_verification_logs TO service_role;

GRANT MAINTAIN ON TABLE public.license_verification_logs TO service_role;

GRANT REFERENCES ON TABLE public.license_verification_logs TO service_role;

GRANT SELECT ON TABLE public.license_verification_logs TO service_role;

GRANT TRIGGER ON TABLE public.license_verification_logs TO service_role;

GRANT TRUNCATE ON TABLE public.license_verification_logs TO service_role;

GRANT UPDATE ON TABLE public.license_verification_logs TO service_role;

GRANT DELETE ON TABLE public.mfa_recovery_codes TO service_role;

GRANT INSERT ON TABLE public.mfa_recovery_codes TO service_role;

GRANT MAINTAIN ON TABLE public.mfa_recovery_codes TO service_role;

GRANT REFERENCES ON TABLE public.mfa_recovery_codes TO service_role;

GRANT SELECT ON TABLE public.mfa_recovery_codes TO service_role;

GRANT TRIGGER ON TABLE public.mfa_recovery_codes TO service_role;

GRANT TRUNCATE ON TABLE public.mfa_recovery_codes TO service_role;

GRANT UPDATE ON TABLE public.mfa_recovery_codes TO service_role;

GRANT DELETE ON TABLE public.notification_outbox TO service_role;

GRANT INSERT ON TABLE public.notification_outbox TO service_role;

GRANT MAINTAIN ON TABLE public.notification_outbox TO service_role;

GRANT REFERENCES ON TABLE public.notification_outbox TO service_role;

GRANT SELECT ON TABLE public.notification_outbox TO service_role;

GRANT TRIGGER ON TABLE public.notification_outbox TO service_role;

GRANT TRUNCATE ON TABLE public.notification_outbox TO service_role;

GRANT UPDATE ON TABLE public.notification_outbox TO service_role;

GRANT SELECT ON TABLE public.notifications TO authenticated;

GRANT DELETE ON TABLE public.notifications TO service_role;

GRANT INSERT ON TABLE public.notifications TO service_role;

GRANT MAINTAIN ON TABLE public.notifications TO service_role;

GRANT REFERENCES ON TABLE public.notifications TO service_role;

GRANT SELECT ON TABLE public.notifications TO service_role;

GRANT TRIGGER ON TABLE public.notifications TO service_role;

GRANT TRUNCATE ON TABLE public.notifications TO service_role;

GRANT UPDATE ON TABLE public.notifications TO service_role;

GRANT DELETE ON TABLE public.platform_access_locks TO service_role;

GRANT INSERT ON TABLE public.platform_access_locks TO service_role;

GRANT MAINTAIN ON TABLE public.platform_access_locks TO service_role;

GRANT REFERENCES ON TABLE public.platform_access_locks TO service_role;

GRANT SELECT ON TABLE public.platform_access_locks TO service_role;

GRANT TRIGGER ON TABLE public.platform_access_locks TO service_role;

GRANT TRUNCATE ON TABLE public.platform_access_locks TO service_role;

GRANT UPDATE ON TABLE public.platform_access_locks TO service_role;

GRANT DELETE ON TABLE public.platform_audit_archives TO service_role;

GRANT INSERT ON TABLE public.platform_audit_archives TO service_role;

GRANT MAINTAIN ON TABLE public.platform_audit_archives TO service_role;

GRANT REFERENCES ON TABLE public.platform_audit_archives TO service_role;

GRANT SELECT ON TABLE public.platform_audit_archives TO service_role;

GRANT TRIGGER ON TABLE public.platform_audit_archives TO service_role;

GRANT TRUNCATE ON TABLE public.platform_audit_archives TO service_role;

GRANT UPDATE ON TABLE public.platform_audit_archives TO service_role;

GRANT DELETE ON TABLE public.platform_distribution_authorities TO service_role;

GRANT INSERT ON TABLE public.platform_distribution_authorities TO service_role;

GRANT MAINTAIN ON TABLE public.platform_distribution_authorities TO service_role;

GRANT REFERENCES ON TABLE public.platform_distribution_authorities TO service_role;

GRANT SELECT ON TABLE public.platform_distribution_authorities TO service_role;

GRANT TRIGGER ON TABLE public.platform_distribution_authorities TO service_role;

GRANT TRUNCATE ON TABLE public.platform_distribution_authorities TO service_role;

GRANT UPDATE ON TABLE public.platform_distribution_authorities TO service_role;

GRANT DELETE ON TABLE public.platform_package_artifacts TO service_role;

GRANT INSERT ON TABLE public.platform_package_artifacts TO service_role;

GRANT MAINTAIN ON TABLE public.platform_package_artifacts TO service_role;

GRANT REFERENCES ON TABLE public.platform_package_artifacts TO service_role;

GRANT SELECT ON TABLE public.platform_package_artifacts TO service_role;

GRANT TRIGGER ON TABLE public.platform_package_artifacts TO service_role;

GRANT TRUNCATE ON TABLE public.platform_package_artifacts TO service_role;

GRANT UPDATE ON TABLE public.platform_package_artifacts TO service_role;

GRANT SELECT ON SEQUENCE public.platform_package_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.platform_package_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.platform_package_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.platform_package_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.platform_package_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.platform_package_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.platform_package_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.platform_package_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.platform_package_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.platform_package_events TO service_role;

GRANT INSERT ON TABLE public.platform_package_events TO service_role;

GRANT MAINTAIN ON TABLE public.platform_package_events TO service_role;

GRANT REFERENCES ON TABLE public.platform_package_events TO service_role;

GRANT SELECT ON TABLE public.platform_package_events TO service_role;

GRANT TRIGGER ON TABLE public.platform_package_events TO service_role;

GRANT TRUNCATE ON TABLE public.platform_package_events TO service_role;

GRANT UPDATE ON TABLE public.platform_package_events TO service_role;

GRANT DELETE ON TABLE public.platform_package_reconciliation TO service_role;

GRANT INSERT ON TABLE public.platform_package_reconciliation TO service_role;

GRANT MAINTAIN ON TABLE public.platform_package_reconciliation TO service_role;

GRANT REFERENCES ON TABLE public.platform_package_reconciliation TO service_role;

GRANT SELECT ON TABLE public.platform_package_reconciliation TO service_role;

GRANT TRIGGER ON TABLE public.platform_package_reconciliation TO service_role;

GRANT TRUNCATE ON TABLE public.platform_package_reconciliation TO service_role;

GRANT UPDATE ON TABLE public.platform_package_reconciliation TO service_role;

GRANT DELETE ON TABLE public.platform_package_templates TO service_role;

GRANT INSERT ON TABLE public.platform_package_templates TO service_role;

GRANT MAINTAIN ON TABLE public.platform_package_templates TO service_role;

GRANT REFERENCES ON TABLE public.platform_package_templates TO service_role;

GRANT SELECT ON TABLE public.platform_package_templates TO service_role;

GRANT TRIGGER ON TABLE public.platform_package_templates TO service_role;

GRANT TRUNCATE ON TABLE public.platform_package_templates TO service_role;

GRANT UPDATE ON TABLE public.platform_package_templates TO service_role;

GRANT DELETE ON TABLE public.privacy_requests TO service_role;

GRANT INSERT ON TABLE public.privacy_requests TO service_role;

GRANT MAINTAIN ON TABLE public.privacy_requests TO service_role;

GRANT REFERENCES ON TABLE public.privacy_requests TO service_role;

GRANT SELECT ON TABLE public.privacy_requests TO service_role;

GRANT TRIGGER ON TABLE public.privacy_requests TO service_role;

GRANT TRUNCATE ON TABLE public.privacy_requests TO service_role;

GRANT UPDATE ON TABLE public.privacy_requests TO service_role;

GRANT MAINTAIN ON TABLE public.profiles TO authenticated;

GRANT SELECT ON TABLE public.profiles TO authenticated;

GRANT DELETE ON TABLE public.profiles TO service_role;

GRANT INSERT ON TABLE public.profiles TO service_role;

GRANT MAINTAIN ON TABLE public.profiles TO service_role;

GRANT REFERENCES ON TABLE public.profiles TO service_role;

GRANT SELECT ON TABLE public.profiles TO service_role;

GRANT TRIGGER ON TABLE public.profiles TO service_role;

GRANT TRUNCATE ON TABLE public.profiles TO service_role;

GRANT UPDATE ON TABLE public.profiles TO service_role;

GRANT DELETE ON TABLE public.recovery_test_runs TO service_role;

GRANT INSERT ON TABLE public.recovery_test_runs TO service_role;

GRANT MAINTAIN ON TABLE public.recovery_test_runs TO service_role;

GRANT REFERENCES ON TABLE public.recovery_test_runs TO service_role;

GRANT SELECT ON TABLE public.recovery_test_runs TO service_role;

GRANT TRIGGER ON TABLE public.recovery_test_runs TO service_role;

GRANT TRUNCATE ON TABLE public.recovery_test_runs TO service_role;

GRANT UPDATE ON TABLE public.recovery_test_runs TO service_role;

GRANT MAINTAIN ON TABLE public.report_card_summary TO authenticated;

GRANT SELECT ON TABLE public.report_card_summary TO authenticated;

GRANT DELETE ON TABLE public.report_card_summary TO service_role;

GRANT INSERT ON TABLE public.report_card_summary TO service_role;

GRANT MAINTAIN ON TABLE public.report_card_summary TO service_role;

GRANT REFERENCES ON TABLE public.report_card_summary TO service_role;

GRANT SELECT ON TABLE public.report_card_summary TO service_role;

GRANT TRIGGER ON TABLE public.report_card_summary TO service_role;

GRANT TRUNCATE ON TABLE public.report_card_summary TO service_role;

GRANT UPDATE ON TABLE public.report_card_summary TO service_role;

GRANT MAINTAIN ON TABLE public.report_card_templates TO authenticated;

GRANT SELECT ON TABLE public.report_card_templates TO authenticated;

GRANT DELETE ON TABLE public.report_card_templates TO service_role;

GRANT INSERT ON TABLE public.report_card_templates TO service_role;

GRANT MAINTAIN ON TABLE public.report_card_templates TO service_role;

GRANT REFERENCES ON TABLE public.report_card_templates TO service_role;

GRANT SELECT ON TABLE public.report_card_templates TO service_role;

GRANT TRIGGER ON TABLE public.report_card_templates TO service_role;

GRANT TRUNCATE ON TABLE public.report_card_templates TO service_role;

GRANT UPDATE ON TABLE public.report_card_templates TO service_role;

GRANT SELECT ON SEQUENCE public.report_correction_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.report_correction_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.report_correction_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.report_correction_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.report_correction_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.report_correction_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.report_correction_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.report_correction_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.report_correction_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.report_correction_events TO service_role;

GRANT INSERT ON TABLE public.report_correction_events TO service_role;

GRANT MAINTAIN ON TABLE public.report_correction_events TO service_role;

GRANT REFERENCES ON TABLE public.report_correction_events TO service_role;

GRANT SELECT ON TABLE public.report_correction_events TO service_role;

GRANT TRIGGER ON TABLE public.report_correction_events TO service_role;

GRANT TRUNCATE ON TABLE public.report_correction_events TO service_role;

GRANT UPDATE ON TABLE public.report_correction_events TO service_role;

GRANT DELETE ON TABLE public.report_correction_requests TO service_role;

GRANT INSERT ON TABLE public.report_correction_requests TO service_role;

GRANT MAINTAIN ON TABLE public.report_correction_requests TO service_role;

GRANT REFERENCES ON TABLE public.report_correction_requests TO service_role;

GRANT SELECT ON TABLE public.report_correction_requests TO service_role;

GRANT TRIGGER ON TABLE public.report_correction_requests TO service_role;

GRANT TRUNCATE ON TABLE public.report_correction_requests TO service_role;

GRANT UPDATE ON TABLE public.report_correction_requests TO service_role;

GRANT SELECT ON TABLE public.report_publications TO authenticated;

GRANT DELETE ON TABLE public.report_publications TO service_role;

GRANT INSERT ON TABLE public.report_publications TO service_role;

GRANT MAINTAIN ON TABLE public.report_publications TO service_role;

GRANT REFERENCES ON TABLE public.report_publications TO service_role;

GRANT SELECT ON TABLE public.report_publications TO service_role;

GRANT TRIGGER ON TABLE public.report_publications TO service_role;

GRANT TRUNCATE ON TABLE public.report_publications TO service_role;

GRANT UPDATE ON TABLE public.report_publications TO service_role;

GRANT SELECT ON TABLE public.report_revisions TO authenticated;

GRANT DELETE ON TABLE public.report_revisions TO service_role;

GRANT INSERT ON TABLE public.report_revisions TO service_role;

GRANT MAINTAIN ON TABLE public.report_revisions TO service_role;

GRANT REFERENCES ON TABLE public.report_revisions TO service_role;

GRANT SELECT ON TABLE public.report_revisions TO service_role;

GRANT TRIGGER ON TABLE public.report_revisions TO service_role;

GRANT TRUNCATE ON TABLE public.report_revisions TO service_role;

GRANT UPDATE ON TABLE public.report_revisions TO service_role;

GRANT SELECT ON TABLE public.report_workflow_events TO authenticated;

GRANT DELETE ON TABLE public.report_workflow_events TO service_role;

GRANT INSERT ON TABLE public.report_workflow_events TO service_role;

GRANT MAINTAIN ON TABLE public.report_workflow_events TO service_role;

GRANT REFERENCES ON TABLE public.report_workflow_events TO service_role;

GRANT SELECT ON TABLE public.report_workflow_events TO service_role;

GRANT TRIGGER ON TABLE public.report_workflow_events TO service_role;

GRANT TRUNCATE ON TABLE public.report_workflow_events TO service_role;

GRANT UPDATE ON TABLE public.report_workflow_events TO service_role;

GRANT DELETE ON TABLE public.school_licenses TO service_role;

GRANT INSERT ON TABLE public.school_licenses TO service_role;

GRANT MAINTAIN ON TABLE public.school_licenses TO service_role;

GRANT REFERENCES ON TABLE public.school_licenses TO service_role;

GRANT SELECT ON TABLE public.school_licenses TO service_role;

GRANT TRIGGER ON TABLE public.school_licenses TO service_role;

GRANT TRUNCATE ON TABLE public.school_licenses TO service_role;

GRANT UPDATE ON TABLE public.school_licenses TO service_role;

GRANT DELETE ON TABLE public.school_prospectus_items TO service_role;

GRANT INSERT ON TABLE public.school_prospectus_items TO service_role;

GRANT MAINTAIN ON TABLE public.school_prospectus_items TO service_role;

GRANT REFERENCES ON TABLE public.school_prospectus_items TO service_role;

GRANT SELECT ON TABLE public.school_prospectus_items TO service_role;

GRANT TRIGGER ON TABLE public.school_prospectus_items TO service_role;

GRANT TRUNCATE ON TABLE public.school_prospectus_items TO service_role;

GRANT UPDATE ON TABLE public.school_prospectus_items TO service_role;

GRANT DELETE ON TABLE public.school_prospectus_revisions TO service_role;

GRANT INSERT ON TABLE public.school_prospectus_revisions TO service_role;

GRANT MAINTAIN ON TABLE public.school_prospectus_revisions TO service_role;

GRANT REFERENCES ON TABLE public.school_prospectus_revisions TO service_role;

GRANT SELECT ON TABLE public.school_prospectus_revisions TO service_role;

GRANT TRIGGER ON TABLE public.school_prospectus_revisions TO service_role;

GRANT TRUNCATE ON TABLE public.school_prospectus_revisions TO service_role;

GRANT UPDATE ON TABLE public.school_prospectus_revisions TO service_role;

GRANT DELETE ON TABLE public.school_prospectus_sections TO service_role;

GRANT INSERT ON TABLE public.school_prospectus_sections TO service_role;

GRANT MAINTAIN ON TABLE public.school_prospectus_sections TO service_role;

GRANT REFERENCES ON TABLE public.school_prospectus_sections TO service_role;

GRANT SELECT ON TABLE public.school_prospectus_sections TO service_role;

GRANT TRIGGER ON TABLE public.school_prospectus_sections TO service_role;

GRANT TRUNCATE ON TABLE public.school_prospectus_sections TO service_role;

GRANT UPDATE ON TABLE public.school_prospectus_sections TO service_role;

GRANT DELETE ON TABLE public.school_prospectuses TO service_role;

GRANT INSERT ON TABLE public.school_prospectuses TO service_role;

GRANT MAINTAIN ON TABLE public.school_prospectuses TO service_role;

GRANT REFERENCES ON TABLE public.school_prospectuses TO service_role;

GRANT SELECT ON TABLE public.school_prospectuses TO service_role;

GRANT TRIGGER ON TABLE public.school_prospectuses TO service_role;

GRANT TRUNCATE ON TABLE public.school_prospectuses TO service_role;

GRANT UPDATE ON TABLE public.school_prospectuses TO service_role;

GRANT MAINTAIN ON TABLE public.school_restore_jobs TO authenticated;

GRANT SELECT ON TABLE public.school_restore_jobs TO authenticated;

GRANT DELETE ON TABLE public.school_restore_jobs TO service_role;

GRANT INSERT ON TABLE public.school_restore_jobs TO service_role;

GRANT MAINTAIN ON TABLE public.school_restore_jobs TO service_role;

GRANT REFERENCES ON TABLE public.school_restore_jobs TO service_role;

GRANT SELECT ON TABLE public.school_restore_jobs TO service_role;

GRANT TRIGGER ON TABLE public.school_restore_jobs TO service_role;

GRANT TRUNCATE ON TABLE public.school_restore_jobs TO service_role;

GRANT UPDATE ON TABLE public.school_restore_jobs TO service_role;

GRANT DELETE ON TABLE public.school_restore_stage_tables TO service_role;

GRANT INSERT ON TABLE public.school_restore_stage_tables TO service_role;

GRANT MAINTAIN ON TABLE public.school_restore_stage_tables TO service_role;

GRANT REFERENCES ON TABLE public.school_restore_stage_tables TO service_role;

GRANT SELECT ON TABLE public.school_restore_stage_tables TO service_role;

GRANT TRIGGER ON TABLE public.school_restore_stage_tables TO service_role;

GRANT TRUNCATE ON TABLE public.school_restore_stage_tables TO service_role;

GRANT UPDATE ON TABLE public.school_restore_stage_tables TO service_role;

GRANT MAINTAIN ON TABLE public.school_settings TO authenticated;

GRANT SELECT ON TABLE public.school_settings TO authenticated;

GRANT UPDATE ON TABLE public.school_settings TO authenticated;

GRANT DELETE ON TABLE public.school_settings TO service_role;

GRANT INSERT ON TABLE public.school_settings TO service_role;

GRANT MAINTAIN ON TABLE public.school_settings TO service_role;

GRANT REFERENCES ON TABLE public.school_settings TO service_role;

GRANT SELECT ON TABLE public.school_settings TO service_role;

GRANT TRIGGER ON TABLE public.school_settings TO service_role;

GRANT TRUNCATE ON TABLE public.school_settings TO service_role;

GRANT UPDATE ON TABLE public.school_settings TO service_role;

GRANT SELECT ON SEQUENCE public.school_staff_identifier_seq TO anon;

GRANT UPDATE ON SEQUENCE public.school_staff_identifier_seq TO anon;

GRANT USAGE ON SEQUENCE public.school_staff_identifier_seq TO anon;

GRANT SELECT ON SEQUENCE public.school_staff_identifier_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.school_staff_identifier_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.school_staff_identifier_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.school_staff_identifier_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.school_staff_identifier_seq TO service_role;

GRANT USAGE ON SEQUENCE public.school_staff_identifier_seq TO service_role;

GRANT SELECT ON SEQUENCE public.school_student_identifier_seq TO anon;

GRANT UPDATE ON SEQUENCE public.school_student_identifier_seq TO anon;

GRANT USAGE ON SEQUENCE public.school_student_identifier_seq TO anon;

GRANT SELECT ON SEQUENCE public.school_student_identifier_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.school_student_identifier_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.school_student_identifier_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.school_student_identifier_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.school_student_identifier_seq TO service_role;

GRANT USAGE ON SEQUENCE public.school_student_identifier_seq TO service_role;

GRANT SELECT ON SEQUENCE public.security_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.security_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.security_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.security_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.security_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.security_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.security_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.security_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.security_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.security_events TO service_role;

GRANT INSERT ON TABLE public.security_events TO service_role;

GRANT MAINTAIN ON TABLE public.security_events TO service_role;

GRANT REFERENCES ON TABLE public.security_events TO service_role;

GRANT SELECT ON TABLE public.security_events TO service_role;

GRANT TRIGGER ON TABLE public.security_events TO service_role;

GRANT TRUNCATE ON TABLE public.security_events TO service_role;

GRANT UPDATE ON TABLE public.security_events TO service_role;

GRANT DELETE ON TABLE public.security_verification_runs TO service_role;

GRANT INSERT ON TABLE public.security_verification_runs TO service_role;

GRANT MAINTAIN ON TABLE public.security_verification_runs TO service_role;

GRANT REFERENCES ON TABLE public.security_verification_runs TO service_role;

GRANT SELECT ON TABLE public.security_verification_runs TO service_role;

GRANT TRIGGER ON TABLE public.security_verification_runs TO service_role;

GRANT TRUNCATE ON TABLE public.security_verification_runs TO service_role;

GRANT UPDATE ON TABLE public.security_verification_runs TO service_role;

GRANT DELETE ON TABLE public.shs_programme_subjects TO authenticated;

GRANT INSERT ON TABLE public.shs_programme_subjects TO authenticated;

GRANT SELECT ON TABLE public.shs_programme_subjects TO authenticated;

GRANT UPDATE ON TABLE public.shs_programme_subjects TO authenticated;

GRANT DELETE ON TABLE public.shs_programme_subjects TO service_role;

GRANT INSERT ON TABLE public.shs_programme_subjects TO service_role;

GRANT MAINTAIN ON TABLE public.shs_programme_subjects TO service_role;

GRANT REFERENCES ON TABLE public.shs_programme_subjects TO service_role;

GRANT SELECT ON TABLE public.shs_programme_subjects TO service_role;

GRANT TRIGGER ON TABLE public.shs_programme_subjects TO service_role;

GRANT TRUNCATE ON TABLE public.shs_programme_subjects TO service_role;

GRANT UPDATE ON TABLE public.shs_programme_subjects TO service_role;

GRANT SELECT ON SEQUENCE public.staff_id_card_events_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.staff_id_card_events_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.staff_id_card_events_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.staff_id_card_events_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.staff_id_card_events_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.staff_id_card_events_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.staff_id_card_events_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.staff_id_card_events_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.staff_id_card_events_id_seq TO service_role;

GRANT DELETE ON TABLE public.staff_id_card_events TO service_role;

GRANT INSERT ON TABLE public.staff_id_card_events TO service_role;

GRANT MAINTAIN ON TABLE public.staff_id_card_events TO service_role;

GRANT REFERENCES ON TABLE public.staff_id_card_events TO service_role;

GRANT SELECT ON TABLE public.staff_id_card_events TO service_role;

GRANT TRIGGER ON TABLE public.staff_id_card_events TO service_role;

GRANT TRUNCATE ON TABLE public.staff_id_card_events TO service_role;

GRANT UPDATE ON TABLE public.staff_id_card_events TO service_role;

GRANT SELECT ON SEQUENCE public.staff_id_card_number_seq TO anon;

GRANT UPDATE ON SEQUENCE public.staff_id_card_number_seq TO anon;

GRANT USAGE ON SEQUENCE public.staff_id_card_number_seq TO anon;

GRANT SELECT ON SEQUENCE public.staff_id_card_number_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.staff_id_card_number_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.staff_id_card_number_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.staff_id_card_number_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.staff_id_card_number_seq TO service_role;

GRANT USAGE ON SEQUENCE public.staff_id_card_number_seq TO service_role;

GRANT DELETE ON TABLE public.staff_id_cards TO service_role;

GRANT INSERT ON TABLE public.staff_id_cards TO service_role;

GRANT MAINTAIN ON TABLE public.staff_id_cards TO service_role;

GRANT REFERENCES ON TABLE public.staff_id_cards TO service_role;

GRANT SELECT ON TABLE public.staff_id_cards TO service_role;

GRANT TRIGGER ON TABLE public.staff_id_cards TO service_role;

GRANT TRUNCATE ON TABLE public.staff_id_cards TO service_role;

GRANT UPDATE ON TABLE public.staff_id_cards TO service_role;

GRANT SELECT ON SEQUENCE public.staff_identifier_seq TO anon;

GRANT UPDATE ON SEQUENCE public.staff_identifier_seq TO anon;

GRANT USAGE ON SEQUENCE public.staff_identifier_seq TO anon;

GRANT SELECT ON SEQUENCE public.staff_identifier_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.staff_identifier_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.staff_identifier_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.staff_identifier_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.staff_identifier_seq TO service_role;

GRANT USAGE ON SEQUENCE public.staff_identifier_seq TO service_role;

GRANT DELETE ON TABLE public.student_attendance_entries TO service_role;

GRANT INSERT ON TABLE public.student_attendance_entries TO service_role;

GRANT MAINTAIN ON TABLE public.student_attendance_entries TO service_role;

GRANT REFERENCES ON TABLE public.student_attendance_entries TO service_role;

GRANT SELECT ON TABLE public.student_attendance_entries TO service_role;

GRANT TRIGGER ON TABLE public.student_attendance_entries TO service_role;

GRANT TRUNCATE ON TABLE public.student_attendance_entries TO service_role;

GRANT UPDATE ON TABLE public.student_attendance_entries TO service_role;

GRANT SELECT ON TABLE public.student_guardians TO authenticated;

GRANT DELETE ON TABLE public.student_guardians TO service_role;

GRANT INSERT ON TABLE public.student_guardians TO service_role;

GRANT MAINTAIN ON TABLE public.student_guardians TO service_role;

GRANT REFERENCES ON TABLE public.student_guardians TO service_role;

GRANT SELECT ON TABLE public.student_guardians TO service_role;

GRANT TRIGGER ON TABLE public.student_guardians TO service_role;

GRANT TRUNCATE ON TABLE public.student_guardians TO service_role;

GRANT UPDATE ON TABLE public.student_guardians TO service_role;

GRANT SELECT ON SEQUENCE public.student_id_card_number_seq TO anon;

GRANT UPDATE ON SEQUENCE public.student_id_card_number_seq TO anon;

GRANT USAGE ON SEQUENCE public.student_id_card_number_seq TO anon;

GRANT SELECT ON SEQUENCE public.student_id_card_number_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.student_id_card_number_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.student_id_card_number_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.student_id_card_number_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.student_id_card_number_seq TO service_role;

GRANT USAGE ON SEQUENCE public.student_id_card_number_seq TO service_role;

GRANT DELETE ON TABLE public.student_id_cards TO service_role;

GRANT INSERT ON TABLE public.student_id_cards TO service_role;

GRANT MAINTAIN ON TABLE public.student_id_cards TO service_role;

GRANT REFERENCES ON TABLE public.student_id_cards TO service_role;

GRANT SELECT ON TABLE public.student_id_cards TO service_role;

GRANT TRIGGER ON TABLE public.student_id_cards TO service_role;

GRANT TRUNCATE ON TABLE public.student_id_cards TO service_role;

GRANT UPDATE ON TABLE public.student_id_cards TO service_role;

GRANT SELECT ON SEQUENCE public.student_identifier_seq TO anon;

GRANT UPDATE ON SEQUENCE public.student_identifier_seq TO anon;

GRANT USAGE ON SEQUENCE public.student_identifier_seq TO anon;

GRANT SELECT ON SEQUENCE public.student_identifier_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.student_identifier_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.student_identifier_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.student_identifier_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.student_identifier_seq TO service_role;

GRANT USAGE ON SEQUENCE public.student_identifier_seq TO service_role;

GRANT DELETE ON TABLE public.student_lifecycle_events TO service_role;

GRANT INSERT ON TABLE public.student_lifecycle_events TO service_role;

GRANT MAINTAIN ON TABLE public.student_lifecycle_events TO service_role;

GRANT REFERENCES ON TABLE public.student_lifecycle_events TO service_role;

GRANT SELECT ON TABLE public.student_lifecycle_events TO service_role;

GRANT TRIGGER ON TABLE public.student_lifecycle_events TO service_role;

GRANT TRUNCATE ON TABLE public.student_lifecycle_events TO service_role;

GRANT UPDATE ON TABLE public.student_lifecycle_events TO service_role;

GRANT DELETE ON TABLE public.student_programme_enrollments TO authenticated;

GRANT INSERT ON TABLE public.student_programme_enrollments TO authenticated;

GRANT SELECT ON TABLE public.student_programme_enrollments TO authenticated;

GRANT UPDATE ON TABLE public.student_programme_enrollments TO authenticated;

GRANT DELETE ON TABLE public.student_programme_enrollments TO service_role;

GRANT INSERT ON TABLE public.student_programme_enrollments TO service_role;

GRANT MAINTAIN ON TABLE public.student_programme_enrollments TO service_role;

GRANT REFERENCES ON TABLE public.student_programme_enrollments TO service_role;

GRANT SELECT ON TABLE public.student_programme_enrollments TO service_role;

GRANT TRIGGER ON TABLE public.student_programme_enrollments TO service_role;

GRANT TRUNCATE ON TABLE public.student_programme_enrollments TO service_role;

GRANT UPDATE ON TABLE public.student_programme_enrollments TO service_role;

GRANT SELECT ON TABLE public.student_reports TO authenticated;

GRANT DELETE ON TABLE public.student_reports TO service_role;

GRANT INSERT ON TABLE public.student_reports TO service_role;

GRANT MAINTAIN ON TABLE public.student_reports TO service_role;

GRANT REFERENCES ON TABLE public.student_reports TO service_role;

GRANT SELECT ON TABLE public.student_reports TO service_role;

GRANT TRIGGER ON TABLE public.student_reports TO service_role;

GRANT TRUNCATE ON TABLE public.student_reports TO service_role;

GRANT UPDATE ON TABLE public.student_reports TO service_role;

GRANT DELETE ON TABLE public.student_services_events TO service_role;

GRANT INSERT ON TABLE public.student_services_events TO service_role;

GRANT MAINTAIN ON TABLE public.student_services_events TO service_role;

GRANT REFERENCES ON TABLE public.student_services_events TO service_role;

GRANT SELECT ON TABLE public.student_services_events TO service_role;

GRANT TRIGGER ON TABLE public.student_services_events TO service_role;

GRANT TRUNCATE ON TABLE public.student_services_events TO service_role;

GRANT UPDATE ON TABLE public.student_services_events TO service_role;

GRANT DELETE ON TABLE public.student_services_staff_access TO service_role;

GRANT INSERT ON TABLE public.student_services_staff_access TO service_role;

GRANT MAINTAIN ON TABLE public.student_services_staff_access TO service_role;

GRANT REFERENCES ON TABLE public.student_services_staff_access TO service_role;

GRANT SELECT ON TABLE public.student_services_staff_access TO service_role;

GRANT TRIGGER ON TABLE public.student_services_staff_access TO service_role;

GRANT TRUNCATE ON TABLE public.student_services_staff_access TO service_role;

GRANT UPDATE ON TABLE public.student_services_staff_access TO service_role;

GRANT SELECT ON TABLE public.students TO authenticated;

GRANT DELETE ON TABLE public.students TO service_role;

GRANT INSERT ON TABLE public.students TO service_role;

GRANT MAINTAIN ON TABLE public.students TO service_role;

GRANT REFERENCES ON TABLE public.students TO service_role;

GRANT SELECT ON TABLE public.students TO service_role;

GRANT TRIGGER ON TABLE public.students TO service_role;

GRANT TRUNCATE ON TABLE public.students TO service_role;

GRANT UPDATE ON TABLE public.students TO service_role;

GRANT SELECT ON TABLE public.subject_results TO authenticated;

GRANT DELETE ON TABLE public.subject_results TO service_role;

GRANT INSERT ON TABLE public.subject_results TO service_role;

GRANT MAINTAIN ON TABLE public.subject_results TO service_role;

GRANT REFERENCES ON TABLE public.subject_results TO service_role;

GRANT SELECT ON TABLE public.subject_results TO service_role;

GRANT TRIGGER ON TABLE public.subject_results TO service_role;

GRANT TRUNCATE ON TABLE public.subject_results TO service_role;

GRANT UPDATE ON TABLE public.subject_results TO service_role;

GRANT SELECT ON TABLE public.subject_scores TO authenticated;

GRANT DELETE ON TABLE public.subject_scores TO service_role;

GRANT INSERT ON TABLE public.subject_scores TO service_role;

GRANT MAINTAIN ON TABLE public.subject_scores TO service_role;

GRANT REFERENCES ON TABLE public.subject_scores TO service_role;

GRANT SELECT ON TABLE public.subject_scores TO service_role;

GRANT TRIGGER ON TABLE public.subject_scores TO service_role;

GRANT TRUNCATE ON TABLE public.subject_scores TO service_role;

GRANT UPDATE ON TABLE public.subject_scores TO service_role;

GRANT MAINTAIN ON TABLE public.subjects TO authenticated;

GRANT SELECT ON TABLE public.subjects TO authenticated;

GRANT DELETE ON TABLE public.subjects TO service_role;

GRANT INSERT ON TABLE public.subjects TO service_role;

GRANT MAINTAIN ON TABLE public.subjects TO service_role;

GRANT REFERENCES ON TABLE public.subjects TO service_role;

GRANT SELECT ON TABLE public.subjects TO service_role;

GRANT TRIGGER ON TABLE public.subjects TO service_role;

GRANT TRUNCATE ON TABLE public.subjects TO service_role;

GRANT UPDATE ON TABLE public.subjects TO service_role;

GRANT SELECT ON SEQUENCE public.system_maintenance_log_id_seq TO anon;

GRANT UPDATE ON SEQUENCE public.system_maintenance_log_id_seq TO anon;

GRANT USAGE ON SEQUENCE public.system_maintenance_log_id_seq TO anon;

GRANT SELECT ON SEQUENCE public.system_maintenance_log_id_seq TO authenticated;

GRANT UPDATE ON SEQUENCE public.system_maintenance_log_id_seq TO authenticated;

GRANT USAGE ON SEQUENCE public.system_maintenance_log_id_seq TO authenticated;

GRANT SELECT ON SEQUENCE public.system_maintenance_log_id_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.system_maintenance_log_id_seq TO service_role;

GRANT USAGE ON SEQUENCE public.system_maintenance_log_id_seq TO service_role;

GRANT DELETE ON TABLE public.system_maintenance_log TO service_role;

GRANT INSERT ON TABLE public.system_maintenance_log TO service_role;

GRANT MAINTAIN ON TABLE public.system_maintenance_log TO service_role;

GRANT REFERENCES ON TABLE public.system_maintenance_log TO service_role;

GRANT SELECT ON TABLE public.system_maintenance_log TO service_role;

GRANT TRIGGER ON TABLE public.system_maintenance_log TO service_role;

GRANT TRUNCATE ON TABLE public.system_maintenance_log TO service_role;

GRANT UPDATE ON TABLE public.system_maintenance_log TO service_role;

GRANT DELETE ON TABLE public.system_release_state TO service_role;

GRANT INSERT ON TABLE public.system_release_state TO service_role;

GRANT MAINTAIN ON TABLE public.system_release_state TO service_role;

GRANT REFERENCES ON TABLE public.system_release_state TO service_role;

GRANT SELECT ON TABLE public.system_release_state TO service_role;

GRANT TRIGGER ON TABLE public.system_release_state TO service_role;

GRANT TRUNCATE ON TABLE public.system_release_state TO service_role;

GRANT UPDATE ON TABLE public.system_release_state TO service_role;

GRANT DELETE ON TABLE public.teacher_award_categories TO service_role;

GRANT INSERT ON TABLE public.teacher_award_categories TO service_role;

GRANT MAINTAIN ON TABLE public.teacher_award_categories TO service_role;

GRANT REFERENCES ON TABLE public.teacher_award_categories TO service_role;

GRANT SELECT ON TABLE public.teacher_award_categories TO service_role;

GRANT TRIGGER ON TABLE public.teacher_award_categories TO service_role;

GRANT TRUNCATE ON TABLE public.teacher_award_categories TO service_role;

GRANT UPDATE ON TABLE public.teacher_award_categories TO service_role;

GRANT SELECT ON TABLE public.teachers TO authenticated;

GRANT DELETE ON TABLE public.teachers TO service_role;

GRANT INSERT ON TABLE public.teachers TO service_role;

GRANT MAINTAIN ON TABLE public.teachers TO service_role;

GRANT REFERENCES ON TABLE public.teachers TO service_role;

GRANT SELECT ON TABLE public.teachers TO service_role;

GRANT TRIGGER ON TABLE public.teachers TO service_role;

GRANT TRUNCATE ON TABLE public.teachers TO service_role;

GRANT UPDATE ON TABLE public.teachers TO service_role;

GRANT MAINTAIN ON TABLE public.terms TO authenticated;

GRANT SELECT ON TABLE public.terms TO authenticated;

GRANT DELETE ON TABLE public.terms TO service_role;

GRANT INSERT ON TABLE public.terms TO service_role;

GRANT MAINTAIN ON TABLE public.terms TO service_role;

GRANT REFERENCES ON TABLE public.terms TO service_role;

GRANT SELECT ON TABLE public.terms TO service_role;

GRANT TRIGGER ON TABLE public.terms TO service_role;

GRANT TRUNCATE ON TABLE public.terms TO service_role;

GRANT UPDATE ON TABLE public.terms TO service_role;

GRANT DELETE ON TABLE public.tertiary_course_offerings TO authenticated;

GRANT INSERT ON TABLE public.tertiary_course_offerings TO authenticated;

GRANT SELECT ON TABLE public.tertiary_course_offerings TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_course_offerings TO authenticated;

GRANT DELETE ON TABLE public.tertiary_course_offerings TO service_role;

GRANT INSERT ON TABLE public.tertiary_course_offerings TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_course_offerings TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_course_offerings TO service_role;

GRANT SELECT ON TABLE public.tertiary_course_offerings TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_course_offerings TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_course_offerings TO service_role;

GRANT UPDATE ON TABLE public.tertiary_course_offerings TO service_role;

GRANT DELETE ON TABLE public.tertiary_course_prerequisites TO authenticated;

GRANT INSERT ON TABLE public.tertiary_course_prerequisites TO authenticated;

GRANT SELECT ON TABLE public.tertiary_course_prerequisites TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_course_prerequisites TO authenticated;

GRANT DELETE ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT INSERT ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT SELECT ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT UPDATE ON TABLE public.tertiary_course_prerequisites TO service_role;

GRANT DELETE ON TABLE public.tertiary_course_registrations TO authenticated;

GRANT INSERT ON TABLE public.tertiary_course_registrations TO authenticated;

GRANT SELECT ON TABLE public.tertiary_course_registrations TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_course_registrations TO authenticated;

GRANT DELETE ON TABLE public.tertiary_course_registrations TO service_role;

GRANT INSERT ON TABLE public.tertiary_course_registrations TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_course_registrations TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_course_registrations TO service_role;

GRANT SELECT ON TABLE public.tertiary_course_registrations TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_course_registrations TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_course_registrations TO service_role;

GRANT UPDATE ON TABLE public.tertiary_course_registrations TO service_role;

GRANT SELECT ON TABLE public.tertiary_course_results TO authenticated;

GRANT DELETE ON TABLE public.tertiary_course_results TO service_role;

GRANT INSERT ON TABLE public.tertiary_course_results TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_course_results TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_course_results TO service_role;

GRANT SELECT ON TABLE public.tertiary_course_results TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_course_results TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_course_results TO service_role;

GRANT UPDATE ON TABLE public.tertiary_course_results TO service_role;

GRANT DELETE ON TABLE public.tertiary_courses TO authenticated;

GRANT INSERT ON TABLE public.tertiary_courses TO authenticated;

GRANT SELECT ON TABLE public.tertiary_courses TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_courses TO authenticated;

GRANT DELETE ON TABLE public.tertiary_courses TO service_role;

GRANT INSERT ON TABLE public.tertiary_courses TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_courses TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_courses TO service_role;

GRANT SELECT ON TABLE public.tertiary_courses TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_courses TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_courses TO service_role;

GRANT UPDATE ON TABLE public.tertiary_courses TO service_role;

GRANT DELETE ON TABLE public.tertiary_degree_classifications TO authenticated;

GRANT INSERT ON TABLE public.tertiary_degree_classifications TO authenticated;

GRANT SELECT ON TABLE public.tertiary_degree_classifications TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_degree_classifications TO authenticated;

GRANT DELETE ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT INSERT ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT SELECT ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT UPDATE ON TABLE public.tertiary_degree_classifications TO service_role;

GRANT DELETE ON TABLE public.tertiary_grading_scale TO authenticated;

GRANT INSERT ON TABLE public.tertiary_grading_scale TO authenticated;

GRANT SELECT ON TABLE public.tertiary_grading_scale TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_grading_scale TO authenticated;

GRANT DELETE ON TABLE public.tertiary_grading_scale TO service_role;

GRANT INSERT ON TABLE public.tertiary_grading_scale TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_grading_scale TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_grading_scale TO service_role;

GRANT SELECT ON TABLE public.tertiary_grading_scale TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_grading_scale TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_grading_scale TO service_role;

GRANT UPDATE ON TABLE public.tertiary_grading_scale TO service_role;

GRANT DELETE ON TABLE public.tertiary_programme_courses TO authenticated;

GRANT INSERT ON TABLE public.tertiary_programme_courses TO authenticated;

GRANT SELECT ON TABLE public.tertiary_programme_courses TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_programme_courses TO authenticated;

GRANT DELETE ON TABLE public.tertiary_programme_courses TO service_role;

GRANT INSERT ON TABLE public.tertiary_programme_courses TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_programme_courses TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_programme_courses TO service_role;

GRANT SELECT ON TABLE public.tertiary_programme_courses TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_programme_courses TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_programme_courses TO service_role;

GRANT UPDATE ON TABLE public.tertiary_programme_courses TO service_role;

GRANT DELETE ON TABLE public.tertiary_programme_requirements TO authenticated;

GRANT INSERT ON TABLE public.tertiary_programme_requirements TO authenticated;

GRANT SELECT ON TABLE public.tertiary_programme_requirements TO authenticated;

GRANT UPDATE ON TABLE public.tertiary_programme_requirements TO authenticated;

GRANT DELETE ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT INSERT ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT MAINTAIN ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT REFERENCES ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT SELECT ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT TRIGGER ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT TRUNCATE ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT UPDATE ON TABLE public.tertiary_programme_requirements TO service_role;

GRANT DELETE ON TABLE public.transcript_issuances TO service_role;

GRANT INSERT ON TABLE public.transcript_issuances TO service_role;

GRANT MAINTAIN ON TABLE public.transcript_issuances TO service_role;

GRANT REFERENCES ON TABLE public.transcript_issuances TO service_role;

GRANT SELECT ON TABLE public.transcript_issuances TO service_role;

GRANT TRIGGER ON TABLE public.transcript_issuances TO service_role;

GRANT TRUNCATE ON TABLE public.transcript_issuances TO service_role;

GRANT UPDATE ON TABLE public.transcript_issuances TO service_role;

GRANT SELECT ON SEQUENCE public.transcript_number_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.transcript_number_seq TO service_role;

GRANT USAGE ON SEQUENCE public.transcript_number_seq TO service_role;

GRANT DELETE ON TABLE public.transport_drivers TO service_role;

GRANT INSERT ON TABLE public.transport_drivers TO service_role;

GRANT MAINTAIN ON TABLE public.transport_drivers TO service_role;

GRANT REFERENCES ON TABLE public.transport_drivers TO service_role;

GRANT SELECT ON TABLE public.transport_drivers TO service_role;

GRANT TRIGGER ON TABLE public.transport_drivers TO service_role;

GRANT TRUNCATE ON TABLE public.transport_drivers TO service_role;

GRANT UPDATE ON TABLE public.transport_drivers TO service_role;

GRANT DELETE ON TABLE public.transport_incidents TO service_role;

GRANT INSERT ON TABLE public.transport_incidents TO service_role;

GRANT MAINTAIN ON TABLE public.transport_incidents TO service_role;

GRANT REFERENCES ON TABLE public.transport_incidents TO service_role;

GRANT SELECT ON TABLE public.transport_incidents TO service_role;

GRANT TRIGGER ON TABLE public.transport_incidents TO service_role;

GRANT TRUNCATE ON TABLE public.transport_incidents TO service_role;

GRANT UPDATE ON TABLE public.transport_incidents TO service_role;

GRANT DELETE ON TABLE public.transport_maintenance_records TO service_role;

GRANT INSERT ON TABLE public.transport_maintenance_records TO service_role;

GRANT MAINTAIN ON TABLE public.transport_maintenance_records TO service_role;

GRANT REFERENCES ON TABLE public.transport_maintenance_records TO service_role;

GRANT SELECT ON TABLE public.transport_maintenance_records TO service_role;

GRANT TRIGGER ON TABLE public.transport_maintenance_records TO service_role;

GRANT TRUNCATE ON TABLE public.transport_maintenance_records TO service_role;

GRANT UPDATE ON TABLE public.transport_maintenance_records TO service_role;

GRANT SELECT ON SEQUENCE public.transport_route_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.transport_route_seq TO service_role;

GRANT USAGE ON SEQUENCE public.transport_route_seq TO service_role;

GRANT DELETE ON TABLE public.transport_route_stops TO service_role;

GRANT INSERT ON TABLE public.transport_route_stops TO service_role;

GRANT MAINTAIN ON TABLE public.transport_route_stops TO service_role;

GRANT REFERENCES ON TABLE public.transport_route_stops TO service_role;

GRANT SELECT ON TABLE public.transport_route_stops TO service_role;

GRANT TRIGGER ON TABLE public.transport_route_stops TO service_role;

GRANT TRUNCATE ON TABLE public.transport_route_stops TO service_role;

GRANT UPDATE ON TABLE public.transport_route_stops TO service_role;

GRANT DELETE ON TABLE public.transport_routes TO service_role;

GRANT INSERT ON TABLE public.transport_routes TO service_role;

GRANT MAINTAIN ON TABLE public.transport_routes TO service_role;

GRANT REFERENCES ON TABLE public.transport_routes TO service_role;

GRANT SELECT ON TABLE public.transport_routes TO service_role;

GRANT TRIGGER ON TABLE public.transport_routes TO service_role;

GRANT TRUNCATE ON TABLE public.transport_routes TO service_role;

GRANT UPDATE ON TABLE public.transport_routes TO service_role;

GRANT DELETE ON TABLE public.transport_settings TO service_role;

GRANT INSERT ON TABLE public.transport_settings TO service_role;

GRANT MAINTAIN ON TABLE public.transport_settings TO service_role;

GRANT REFERENCES ON TABLE public.transport_settings TO service_role;

GRANT SELECT ON TABLE public.transport_settings TO service_role;

GRANT TRIGGER ON TABLE public.transport_settings TO service_role;

GRANT TRUNCATE ON TABLE public.transport_settings TO service_role;

GRANT UPDATE ON TABLE public.transport_settings TO service_role;

GRANT DELETE ON TABLE public.transport_staff_access TO service_role;

GRANT INSERT ON TABLE public.transport_staff_access TO service_role;

GRANT MAINTAIN ON TABLE public.transport_staff_access TO service_role;

GRANT REFERENCES ON TABLE public.transport_staff_access TO service_role;

GRANT SELECT ON TABLE public.transport_staff_access TO service_role;

GRANT TRIGGER ON TABLE public.transport_staff_access TO service_role;

GRANT TRUNCATE ON TABLE public.transport_staff_access TO service_role;

GRANT UPDATE ON TABLE public.transport_staff_access TO service_role;

GRANT SELECT ON SEQUENCE public.transport_stop_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.transport_stop_seq TO service_role;

GRANT USAGE ON SEQUENCE public.transport_stop_seq TO service_role;

GRANT DELETE ON TABLE public.transport_stops TO service_role;

GRANT INSERT ON TABLE public.transport_stops TO service_role;

GRANT MAINTAIN ON TABLE public.transport_stops TO service_role;

GRANT REFERENCES ON TABLE public.transport_stops TO service_role;

GRANT SELECT ON TABLE public.transport_stops TO service_role;

GRANT TRIGGER ON TABLE public.transport_stops TO service_role;

GRANT TRUNCATE ON TABLE public.transport_stops TO service_role;

GRANT UPDATE ON TABLE public.transport_stops TO service_role;

GRANT DELETE ON TABLE public.transport_student_assignments TO service_role;

GRANT INSERT ON TABLE public.transport_student_assignments TO service_role;

GRANT MAINTAIN ON TABLE public.transport_student_assignments TO service_role;

GRANT REFERENCES ON TABLE public.transport_student_assignments TO service_role;

GRANT SELECT ON TABLE public.transport_student_assignments TO service_role;

GRANT TRIGGER ON TABLE public.transport_student_assignments TO service_role;

GRANT TRUNCATE ON TABLE public.transport_student_assignments TO service_role;

GRANT UPDATE ON TABLE public.transport_student_assignments TO service_role;

GRANT DELETE ON TABLE public.transport_trip_students TO service_role;

GRANT INSERT ON TABLE public.transport_trip_students TO service_role;

GRANT MAINTAIN ON TABLE public.transport_trip_students TO service_role;

GRANT REFERENCES ON TABLE public.transport_trip_students TO service_role;

GRANT SELECT ON TABLE public.transport_trip_students TO service_role;

GRANT TRIGGER ON TABLE public.transport_trip_students TO service_role;

GRANT TRUNCATE ON TABLE public.transport_trip_students TO service_role;

GRANT UPDATE ON TABLE public.transport_trip_students TO service_role;

GRANT DELETE ON TABLE public.transport_trips TO service_role;

GRANT INSERT ON TABLE public.transport_trips TO service_role;

GRANT MAINTAIN ON TABLE public.transport_trips TO service_role;

GRANT REFERENCES ON TABLE public.transport_trips TO service_role;

GRANT SELECT ON TABLE public.transport_trips TO service_role;

GRANT TRIGGER ON TABLE public.transport_trips TO service_role;

GRANT TRUNCATE ON TABLE public.transport_trips TO service_role;

GRANT UPDATE ON TABLE public.transport_trips TO service_role;

GRANT SELECT ON SEQUENCE public.transport_vehicle_seq TO service_role;

GRANT UPDATE ON SEQUENCE public.transport_vehicle_seq TO service_role;

GRANT USAGE ON SEQUENCE public.transport_vehicle_seq TO service_role;

GRANT DELETE ON TABLE public.transport_vehicles TO service_role;

GRANT INSERT ON TABLE public.transport_vehicles TO service_role;

GRANT MAINTAIN ON TABLE public.transport_vehicles TO service_role;

GRANT REFERENCES ON TABLE public.transport_vehicles TO service_role;

GRANT SELECT ON TABLE public.transport_vehicles TO service_role;

GRANT TRIGGER ON TABLE public.transport_vehicles TO service_role;

GRANT TRUNCATE ON TABLE public.transport_vehicles TO service_role;

GRANT UPDATE ON TABLE public.transport_vehicles TO service_role;

GRANT MAINTAIN ON TABLE public.user_class_access TO authenticated;

GRANT SELECT ON TABLE public.user_class_access TO authenticated;

GRANT DELETE ON TABLE public.user_class_access TO service_role;

GRANT INSERT ON TABLE public.user_class_access TO service_role;

GRANT MAINTAIN ON TABLE public.user_class_access TO service_role;

GRANT REFERENCES ON TABLE public.user_class_access TO service_role;

GRANT SELECT ON TABLE public.user_class_access TO service_role;

GRANT TRIGGER ON TABLE public.user_class_access TO service_role;

GRANT TRUNCATE ON TABLE public.user_class_access TO service_role;

GRANT UPDATE ON TABLE public.user_class_access TO service_role;

GRANT DELETE ON TABLE public.welfare_case_notes TO service_role;

GRANT INSERT ON TABLE public.welfare_case_notes TO service_role;

GRANT MAINTAIN ON TABLE public.welfare_case_notes TO service_role;

GRANT REFERENCES ON TABLE public.welfare_case_notes TO service_role;

GRANT SELECT ON TABLE public.welfare_case_notes TO service_role;

GRANT TRIGGER ON TABLE public.welfare_case_notes TO service_role;

GRANT TRUNCATE ON TABLE public.welfare_case_notes TO service_role;

GRANT UPDATE ON TABLE public.welfare_case_notes TO service_role;

GRANT DELETE ON TABLE public.welfare_cases TO service_role;

GRANT INSERT ON TABLE public.welfare_cases TO service_role;

GRANT MAINTAIN ON TABLE public.welfare_cases TO service_role;

GRANT REFERENCES ON TABLE public.welfare_cases TO service_role;

GRANT SELECT ON TABLE public.welfare_cases TO service_role;

GRANT TRIGGER ON TABLE public.welfare_cases TO service_role;

GRANT TRUNCATE ON TABLE public.welfare_cases TO service_role;

GRANT UPDATE ON TABLE public.welfare_cases TO service_role;

GRANT EXECUTE ON FUNCTION public.academic_analytics_v729(target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.academic_analytics(target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.academic_analytics(target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.academic_configuration_readiness() TO anon;

GRANT EXECUTE ON FUNCTION public.academic_configuration_readiness() TO authenticated;

GRANT EXECUTE ON FUNCTION public.academic_configuration_readiness() TO service_role;

GRANT EXECUTE ON FUNCTION public.academic_year_auto_status_trigger() TO service_role;

GRANT EXECUTE ON FUNCTION public.acknowledge_emergency_academic_delegation(target_delegation_id uuid, note_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.acknowledge_emergency_academic_delegation(target_delegation_id uuid, note_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.active_emergency_delegation_ids(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean, require_class_fields boolean, target_user_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.active_emergency_delegation_ids(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean, require_class_fields boolean, target_user_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_accounts_staff_directory(search_text text, include_inactive boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_accounts_staff_directory(search_text text, include_inactive boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_apply_user_bundle(actor_id uuid, bundle jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_deactivate_accounts_staff(target_staff_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_deactivate_accounts_staff(target_staff_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_finance_test_payment_cleanup_list() TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_finance_test_payment_cleanup_list() TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_guardian_account_records() TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_guardian_account_records() TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_permanently_delete_test_fee_payment(target_transaction_id uuid, confirmation_receipt text, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_permanently_delete_test_fee_payment(target_transaction_id uuid, confirmation_receipt text, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_remove_accounts_staff_permanently(target_staff_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_remove_accounts_staff_permanently(target_staff_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_save_accounts_staff(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_save_accounts_staff(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_validate_user_bundle(actor_id uuid, bundle jsonb, require_existing_user boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_accept_offer(target_offer_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_accept_offer(target_offer_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_application_detail(target_application_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_application_detail(target_application_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_application_register(search_text text, status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_application_register(search_text text, status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_decide_application(target_application_id uuid, decision text, offered_academic_year_id uuid, offered_class_id uuid, decision_notes text, offer_expires_at date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_decide_application(target_application_id uuid, decision text, offered_academic_year_id uuid, offered_class_id uuid, decision_notes text, offer_expires_at date) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_delete_application(target_application_id uuid, reason text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_delete_application(target_application_id uuid, reason text) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_enroll_application(target_application_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_enroll_application(target_application_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_mark_not_enrolled(target_application_id uuid, reason text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_mark_not_enrolled(target_application_id uuid, reason text) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_next_application_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_next_student_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_permanently_remove_application(target_application_id uuid, confirmation_application_no text, reason text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_permanently_remove_application(target_application_id uuid, confirmation_application_no text, reason text) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_reference_data() TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_reference_data() TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_save_application(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_save_application(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_save_document(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_save_document(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_submit_application(target_application_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admissions_submit_application(target_application_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.admissions_sync_student_lifecycle() TO service_role;

GRANT EXECUTE ON FUNCTION public.after_score_entry_change() TO service_role;

GRANT EXECUTE ON FUNCTION public.allowed_report_transitions(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.allowed_report_transitions(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_add_engagement(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_add_engagement(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_candidate_register(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_candidate_register(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_create_from_student(target_student_id uuid, graduation_academic_year_id uuid, final_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_create_from_student(target_student_id uuid, graduation_academic_year_id uuid, final_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_my_record() TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_my_record() TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_next_code() TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_record_detail(target_alumni_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_record_detail(target_alumni_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_register(search_text text, status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_register(search_text text, status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_save_record(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_save_record(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_save_verification_request(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_save_verification_request(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.alumni_verification_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.alumni_verification_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.apply_attendance_totals_to_report() TO service_role;

GRANT EXECUTE ON FUNCTION public.apply_automatic_report_comments() TO service_role;

GRANT EXECUTE ON FUNCTION public.apply_certificate_placeholders(template_text text, context_data jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.apply_pending_term3_promotions() TO service_role;

GRANT EXECUTE ON FUNCTION public.apply_promotion_when_report_published() TO service_role;

GRANT EXECUTE ON FUNCTION public.archive_academic_entity(entity_type text, target_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_academic_entity(entity_type text, target_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.archive_grading_scale(target_grade_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_grading_scale(target_grade_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.archive_headteacher(target_headteacher_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_headteacher(target_headteacher_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.archive_report_card(target_report_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_report_card(target_report_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.archive_school_prospectus(target_prospectus_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_school_prospectus(target_prospectus_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.archive_student(target_student_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_student(target_student_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.archive_teacher(target_teacher_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.archive_teacher(target_teacher_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.attendance_counts_for_enrollment(target_enrollment_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.audit_backup_export_lifecycle() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.audit_backup_export_lifecycle() TO anon;

GRANT EXECUTE ON FUNCTION public.audit_backup_export_lifecycle() TO authenticated;

GRANT EXECUTE ON FUNCTION public.audit_backup_export_lifecycle() TO service_role;

GRANT EXECUTE ON FUNCTION public.audit_row_change() TO service_role;

GRANT EXECUTE ON FUNCTION public.audit_school_restore_lifecycle() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.audit_school_restore_lifecycle() TO anon;

GRANT EXECUTE ON FUNCTION public.audit_school_restore_lifecycle() TO authenticated;

GRANT EXECUTE ON FUNCTION public.audit_school_restore_lifecycle() TO service_role;

GRANT EXECUTE ON FUNCTION public.backup_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.backup_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.begin_report_correction(target_report_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.begin_report_correction(target_report_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.broadcast_application_change() TO service_role;

GRANT EXECUTE ON FUNCTION public.build_report_snapshot(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.build_school_prospectus_snapshot(target_prospectus_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.build_staff_id_card_snapshot(target_staff_type text, target_staff_id uuid, target_academic_year_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.build_student_id_card_snapshot(target_student_id uuid, target_enrollment_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.build_student_transcript_snapshot(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.build_student_transcript_snapshot(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.bulk_generate_missing_reports(target_term_id uuid, target_class_id uuid, preview_only boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bulk_generate_missing_reports(target_term_id uuid, target_class_id uuid, preview_only boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.bulk_import_scores(target_term_id uuid, target_class_id uuid, rows jsonb, filename text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bulk_import_scores(target_term_id uuid, target_class_id uuid, rows jsonb, filename text) TO service_role;

GRANT EXECUTE ON FUNCTION public.bulk_import_students(rows jsonb, filename text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bulk_import_students(rows jsonb, filename text) TO service_role;

GRANT EXECUTE ON FUNCTION public.bulk_promote_all_classes(source_academic_year_id uuid, target_academic_year_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bulk_promote_all_classes(source_academic_year_id uuid, target_academic_year_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.bulk_promote_class(source_academic_year_id uuid, source_class_id uuid, target_academic_year_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bulk_promote_class(source_academic_year_id uuid, source_class_id uuid, target_academic_year_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.bulk_transition_class_reports(target_term_id uuid, target_class_id uuid, target_status report_status, comment_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.bulk_transition_class_reports(target_term_id uuid, target_class_id uuid, target_status report_status, comment_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_access_class(target_class_id uuid, require_write boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_access_class(target_class_id uuid, require_write boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_create_report_for_class_term(target_class_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_create_report_for_class_term(target_class_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_create_report_for_class(target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_create_report_for_class(target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_create_report_scope(target_class_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_create_report_scope(target_class_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_delete_report_pdf_object(target_report_id uuid, target_storage_path text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_delete_report_pdf_object(target_report_id uuid, target_storage_path text) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_delete_report(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_delete_report(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_edit_report(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_edit_report(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_enter_tertiary_course_result(p_course_registration_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_enter_tertiary_course_result(p_course_registration_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_academic_model() TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_academic_model() TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_certificates() TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_certificates() TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_class_report_fields_for_term(target_class_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_class_report_fields_for_term(target_class_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_class_report_fields_scope(target_class_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_class_report_fields_scope(target_class_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_class_report_fields(target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_class_report_fields(target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_headteachers() TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_headteachers() TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_report_pdf(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_report_pdf(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_staff_photo(target_staff_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_staff_photo(target_staff_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_student(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_student(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_manage_teachers() TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_manage_teachers() TO service_role;

GRANT EXECUTE ON FUNCTION public.can_modify_certificate_template_object(target_path text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_modify_certificate_template_object(target_path text) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_publish_report(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_publish_report(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_read_principal_signature() TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_read_principal_signature() TO service_role;

GRANT EXECUTE ON FUNCTION public.can_read_student_academic_record(p_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_read_student_academic_record(p_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_read_tertiary_student_record(p_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_read_tertiary_student_record(p_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_remove_report(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_remove_report(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_review_certificates() TO service_role;

GRANT EXECUTE ON FUNCTION public.can_score_class_subject_for_term(target_class_id uuid, target_subject_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_score_class_subject_for_term(target_class_id uuid, target_subject_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_score_class_subject_scope(target_class_id uuid, target_subject_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_score_class_subject_scope(target_class_id uuid, target_subject_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_score_class_subject(target_class_id uuid, target_subject_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_score_class_subject(target_class_id uuid, target_subject_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_score_subject(target_report_id uuid, target_subject_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_score_subject(target_report_id uuid, target_subject_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_submit_report(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_view_class_timetable(target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_class_timetable(target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_view_report_internal(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_report_internal(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_view_report_pdf(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_report_pdf(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_view_report(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_report(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_view_staff_photo(target_staff_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_staff_photo(target_staff_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_view_student_history(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_student_history(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.can_view_student(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.can_view_student(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.canonical_school_email_domain() TO service_role;

GRANT EXECUTE ON FUNCTION public.canonical_school_identity_prefix() TO service_role;

GRANT EXECUTE ON FUNCTION public.certificate_type_code(target_type text) TO service_role;

GRANT EXECUTE ON FUNCTION public.certificate_type_label(target_type text) TO service_role;

GRANT EXECUTE ON FUNCTION public.claim_notification_jobs(target_batch_size integer, target_worker_id text) TO service_role;

GRANT EXECUTE ON FUNCTION public.clear_section_history(scope_text text, reason_text text, confirmation_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.clear_section_history(scope_text text, reason_text text, confirmation_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_campaign_options() TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_campaign_options() TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_campaign_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_campaign_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_create_thread(subject_text text, participant_profile_ids uuid[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_create_thread(subject_text text, participant_profile_ids uuid[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_delivery_register(target_campaign_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_delivery_register(target_campaign_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_my_threads() TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_my_threads() TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_publish_campaign(target_campaign_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_publish_campaign(target_campaign_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_save_campaign(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_save_campaign(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_save_template(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_save_template(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_send_message(target_thread_id uuid, message_body text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_send_message(target_thread_id uuid, message_body text) TO service_role;

GRANT EXECUTE ON FUNCTION public.communications_thread_messages(target_thread_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.communications_thread_messages(target_thread_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.complete_notification_job(target_job_id uuid, target_worker_id text, target_success boolean, target_error text) TO service_role;

GRANT EXECUTE ON FUNCTION public.complete_required_password_change() TO authenticated;

GRANT EXECUTE ON FUNCTION public.complete_required_password_change() TO service_role;

GRANT EXECUTE ON FUNCTION public.control_plane_health_snapshot() TO service_role;

GRANT EXECUTE ON FUNCTION public.copy_school_prospectus(target_source_id uuid, target_academic_year_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.copy_school_prospectus(target_source_id uuid, target_academic_year_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.create_certificate_batch(payload jsonb, recipient_ids uuid[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_certificate_batch(payload jsonb, recipient_ids uuid[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.create_certificate_replacement_draft(target_certificate_id uuid, reason_text text, replacement_statement text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_certificate_replacement_draft(target_certificate_id uuid, reason_text text, replacement_statement text) TO service_role;

GRANT EXECUTE ON FUNCTION public.create_emergency_academic_delegation(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_emergency_academic_delegation(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.create_notification(target_recipient uuid, target_title text, target_body text, target_category text, target_entity_type text, target_entity_id uuid, queue_email boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.create_privacy_request(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_privacy_request(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.create_workflow_notifications(target_report_id uuid, target_status report_status) TO service_role;

GRANT EXECUTE ON FUNCTION public.current_aal() TO authenticated;

GRANT EXECUTE ON FUNCTION public.current_aal() TO service_role;

GRANT EXECUTE ON FUNCTION public.current_app_role_for(input_role app_role) TO service_role;

GRANT EXECUTE ON FUNCTION public.current_app_role() TO authenticated;

GRANT EXECUTE ON FUNCTION public.current_app_role() TO service_role;

GRANT EXECUTE ON FUNCTION public.current_id_card_principal_snapshot() TO service_role;

GRANT EXECUTE ON FUNCTION public.default_grading_interpretation(grade_text text, remark_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.default_grading_interpretation(grade_text text, remark_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_audit_events(event_ids bigint[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_audit_events(event_ids bigint[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_certificate_permanently(target_certificate_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_certificate_permanently(target_certificate_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_class_subject_assignment(target_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_class_subject_assignment(target_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_class_timetable_entry(target_entry_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_class_timetable_entry(target_entry_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_notifications(notification_ids uuid[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_notifications(notification_ids uuid[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_report_card_permanently(target_report_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_report_card_permanently(target_report_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_school_prospectus_item(target_item_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_school_prospectus_item(target_item_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_school_prospectus_section(target_section_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_school_prospectus_section(target_section_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_school_prospectus(target_prospectus_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_school_prospectus(target_prospectus_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_staff_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_staff_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_student_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_student_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.delete_transcript_issuance_permanently(target_issuance_id uuid, reason_text text, confirmation_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.delete_transcript_issuance_permanently(target_issuance_id uuid, reason_text text, confirmation_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_acknowledge_incident(target_incident_id uuid, acknowledgement_note text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_acknowledge_incident(target_incident_id uuid, acknowledgement_note text) TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_add_action(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_add_action(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_incident_detail(target_incident_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_incident_detail(target_incident_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_incident_register(search_text text, status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_incident_register(search_text text, status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_my_children_incidents() TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_my_children_incidents() TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_notify_guardian(target_incident_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_notify_guardian(target_incident_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_resolve_incident(target_incident_id uuid, resolution_notes text, new_status text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_resolve_incident(target_incident_id uuid, resolution_notes text, new_status text) TO service_role;

GRANT EXECUTE ON FUNCTION public.discipline_save_incident(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.discipline_save_incident(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.enforce_custom_branding_entitlement() TO service_role;

GRANT EXECUTE ON FUNCTION public.enforce_licensed_storage_capacity() TO service_role;

GRANT EXECUTE ON FUNCTION public.enforce_licensed_write() TO service_role;

GRANT EXECUTE ON FUNCTION public.enforce_single_current_principal() TO service_role;

GRANT EXECUTE ON FUNCTION public.enforce_student_management_aal2_write() TO service_role;

GRANT EXECUTE ON FUNCTION public.enforce_system_admin_capacity() TO service_role;

GRANT EXECUTE ON FUNCTION public.ensure_current_user_profile() TO authenticated;

GRANT EXECUTE ON FUNCTION public.ensure_current_user_profile() TO service_role;

GRANT EXECUTE ON FUNCTION public.export_backup_snapshot() TO authenticated;

GRANT EXECUTE ON FUNCTION public.export_backup_snapshot() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_accounts_console(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_accounts_console(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_approve_payroll(target_run_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_approve_payroll(target_run_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_calculate_payroll(target_year integer, target_month integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_calculate_payroll(target_year integer, target_month integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_class_fee_statement(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_class_fee_statement(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_clear_guardian_contact_history() TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_clear_guardian_contact_history() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_clear_hold_override(target_student_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_clear_hold_override(target_student_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_compute_tax(taxable_amount numeric, target_date date) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_deactivate_accounts_staff(target_staff_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_deactivate_accounts_staff(target_staff_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_effective_rate(raw_rate numeric) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_feature_enabled(feature_code text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_generate_invoice_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_generate_payroll_number() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_generate_receipt_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_generate_staff_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_guardian_contact_history(target_academic_year_id uuid, target_term_id uuid, search_text text, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_guardian_contact_history(target_academic_year_id uuid, target_term_id uuid, search_text text, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_guardian_follow_up(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid, status_filter text, search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_guardian_follow_up(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid, status_filter text, search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_immutable_row() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_invoice_detail(target_invoice_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_invoice_detail(target_invoice_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_invoice_register(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_invoice_register(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_loan_balance(target_loan_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_lock_payroll(target_run_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_lock_payroll(target_run_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_log_guardian_contact(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_log_guardian_contact(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_mark_salary_paid(target_item_id uuid, payment_reference_text text, payment_date_value date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_mark_salary_paid(target_item_id uuid, payment_reference_text text, payment_date_value date) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_my_children_fees() TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_my_children_fees() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_my_invoices() TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_my_invoices() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_payment_candidates(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_payment_candidates(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_payment_register(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_payment_register(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_payroll_console(target_year integer, target_month integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_payroll_console(target_year integer, target_month integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_portal_account_candidates() TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_portal_account_candidates() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_portal_report_detail(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_portal_report_detail(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_post_adjustment(target_student_id uuid, target_account_id uuid, adjustment_type text, amount_value numeric, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_post_adjustment(target_student_id uuid, target_account_id uuid, adjustment_type text, amount_value numeric, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_protect_final_payroll() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_protect_invoice() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_record_payment(target_student_id uuid, target_account_id uuid, amount_value numeric, payment_method_text text, payment_reference_text text, payment_date_value date, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_record_payment(target_student_id uuid, target_account_id uuid, amount_value numeric, payment_method_text text, payment_reference_text text, payment_date_value date, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_require_access(feature_code text, require_write boolean, allowed_roles text[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_require_capability(capability text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_require_payroll_access(require_write boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_reverse_payment(target_transaction_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_reverse_payment(target_transaction_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_save_accounts_staff(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_save_accounts_staff(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_save_fee_schedule(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_save_fee_schedule(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_save_hold_policy(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_save_hold_policy(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_save_payroll_profile(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_save_payroll_profile(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_save_payroll_rule(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_save_payroll_rule(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_save_salary_grade(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_save_salary_grade(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_save_teacher_loan(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_save_teacher_loan(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_session_capabilities() TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_session_capabilities() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_set_hold_override(target_student_id uuid, mode_text text, reason_text text, ends_at_value timestamp with time zone) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_set_hold_override(target_student_id uuid, mode_text text, reason_text text, ends_at_value timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_staff_capability(capability text) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_student_hold_status(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_student_outstanding(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_student_statement(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_student_statement(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_sync_enrollment_fee_accounts() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_sync_fee_accounts(target_schedule_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_sync_hr_staff_link() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.finance_sync_hr_staff_link() TO anon;

GRANT EXECUTE ON FUNCTION public.finance_sync_hr_staff_link() TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_sync_hr_staff_link() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_sync_invoice_from_account() TO service_role;

GRANT EXECUTE ON FUNCTION public.finance_teacher_salary_history() TO authenticated;

GRANT EXECUTE ON FUNCTION public.finance_teacher_salary_history() TO service_role;

GRANT EXECUTE ON FUNCTION public.freeze_report_grading_guide() TO service_role;

GRANT EXECUTE ON FUNCTION public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.generate_report_number(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.generate_school_identifier(identifier_kind text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.generate_school_identifier(identifier_kind text) TO service_role;

GRANT EXECUTE ON FUNCTION public.generate_staff_id_card_number(target_academic_year_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.generate_student_id_card_number(target_academic_year_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.generate_subject_code(subject_name text, exclude_subject_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.generate_subject_code(subject_name text, exclude_subject_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_academic_calendar_context() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_academic_calendar_context() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_academic_configuration() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_academic_configuration() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_bootstrap_data() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_bootstrap_data() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_certificate_batch(target_batch_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_certificate_batch(target_batch_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_certificate_console(target_academic_year_id uuid, target_certificate_type text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_certificate_console(target_academic_year_id uuid, target_certificate_type text) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_class_attendance_register(target_term_id uuid, target_class_id uuid, target_date date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_class_attendance_register(target_term_id uuid, target_class_id uuid, target_date date) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_class_timetable_console(target_academic_year_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_class_timetable_console(target_academic_year_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_compliance_console() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_compliance_console() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_current_principal_signature() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_current_principal_signature() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_dashboard_metrics(target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_dashboard_metrics(target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_emergency_delegation_console() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_emergency_delegation_console() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_headteacher_record(target_headteacher_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_headteacher_record(target_headteacher_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_id_card_console(target_academic_year_id uuid, target_class_id uuid, target_status text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_id_card_console(target_academic_year_id uuid, target_class_id uuid, target_status text) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_my_emergency_academic_delegations(target_class_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_my_emergency_academic_delegations(target_class_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_my_headteacher_signature() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_my_headteacher_signature() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_my_student_portal_v2() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_my_student_portal_v2() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_my_student_portal() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_my_student_portal() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_my_teacher_profile() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_my_teacher_profile() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_platform_license_console() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_platform_license_console() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_recovery_console() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_recovery_console() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_report_correction_console(target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_report_correction_console(target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_report_editor(target_report_id uuid, target_enrollment_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_report_editor(target_report_id uuid, target_enrollment_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_report_grading_guide(target_report_id uuid, target_enrollment_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_report_grading_guide(target_report_id uuid, target_enrollment_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_report_headteacher_signature(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_report_headteacher_signature(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_report_revisions(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_report_revisions(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_role_dashboard(target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_role_dashboard(target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_role_workspace() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_role_workspace() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_school_license_capacity_console() TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_school_license_capacity_console() TO service_role;

GRANT EXECUTE ON FUNCTION public.get_school_prospectus_console(target_academic_year_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_school_prospectus_console(target_academic_year_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_staff_id_card_console(target_staff_type text, target_status text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_staff_id_card_console(target_staff_type text, target_status text) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_student_academic_history(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_student_academic_history(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_student_record_v5(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_student_record_v5(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_student_record(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_student_record(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.get_teacher_record(target_teacher_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_teacher_record(target_teacher_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.grade_for_mark(mark numeric, target_academic_year_id uuid, target_class_id uuid, target_subject_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

GRANT EXECUTE ON FUNCTION public.has_active_emergency_delegation(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean, require_class_fields boolean, target_user_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.has_active_emergency_delegation(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean, require_class_fields boolean, target_user_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.has_any_active_emergency_delegation(target_user_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.has_any_active_emergency_delegation(target_user_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.has_approved_report_correction(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.has_approved_report_correction(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.has_role(allowed text[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.has_role(allowed text[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.health_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.health_my_children_emergency_summary() TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_my_children_emergency_summary() TO service_role;

GRANT EXECUTE ON FUNCTION public.health_record_medication(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_record_medication(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.health_save_immunization(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_save_immunization(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.health_save_profile(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_save_profile(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.health_save_visit(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_save_visit(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.health_student_profile(target_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_student_profile(target_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.health_visit_register(search_text text, date_from date, date_to date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.health_visit_register(search_text text, date_from date, date_to date) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_allocate_student(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_allocate_student(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_allocation_register(search_text text, status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_allocation_register(search_text text, status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_end_allocation(target_allocation_id uuid, end_reason text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_end_allocation(target_allocation_id uuid, end_reason text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_incident_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_incident_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_movement_register(target_allocation_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_movement_register(target_allocation_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_my_children_boarding() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_my_children_boarding() TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_record_movement(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_record_movement(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_resolve_incident(target_incident_id uuid, resolution_notes text, new_status text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_resolve_incident(target_incident_id uuid, resolution_notes text, new_status text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_save_bed(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_save_bed(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_save_house(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_save_house(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_save_incident(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_save_incident(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hostel_save_room(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hostel_save_room(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_block_delete() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.hr_block_delete() TO anon;

GRANT EXECUTE ON FUNCTION public.hr_block_delete() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_block_delete() TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_cancel_leave(target_request_id uuid, cancellation_reason text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_cancel_leave(target_request_id uuid, cancellation_reason text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_decide_leave(target_request_id uuid, decision text, decision_reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_decide_leave(target_request_id uuid, decision text, decision_reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_generate_staff_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_leave_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_leave_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_my_profile() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_my_profile() TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_record_staff_lifecycle() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.hr_record_staff_lifecycle() TO anon;

GRANT EXECUTE ON FUNCTION public.hr_record_staff_lifecycle() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_record_staff_lifecycle() TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_require_access(require_write boolean, allowed_roles text[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_save_document(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_save_document(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_save_qualification(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_save_qualification(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_save_staff(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_save_staff(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_staff_detail(target_staff_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_staff_detail(target_staff_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_staff_directory(search_text text, status_filter text, department_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_staff_directory(search_text text, status_filter text, department_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_submit_leave_for_staff(target_staff_id uuid, leave_kind text, start_on date, end_on date, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_submit_leave_for_staff(target_staff_id uuid, leave_kind text, start_on date, end_on date, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_submit_my_leave(leave_kind text, start_on date, end_on date, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_submit_my_leave(leave_kind text, start_on date, end_on date, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_sync_staff_from_source() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.hr_sync_staff_from_source() TO anon;

GRANT EXECUTE ON FUNCTION public.hr_sync_staff_from_source() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_sync_staff_from_source() TO service_role;

GRANT EXECUTE ON FUNCTION public.hr_touch_updated_at() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.hr_touch_updated_at() TO anon;

GRANT EXECUTE ON FUNCTION public.hr_touch_updated_at() TO authenticated;

GRANT EXECUTE ON FUNCTION public.hr_touch_updated_at() TO service_role;

GRANT EXECUTE ON FUNCTION public.id_card_effective_status(target_status text, target_expires_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.id_card_photo_path_is_referenced(target_student_id uuid, target_photo_path text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.id_card_photo_path_is_referenced(target_student_id uuid, target_photo_path text) TO service_role;

GRANT EXECUTE ON FUNCTION public.id_card_photo_reference_count(target_student_id uuid, target_photo_path text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.id_card_photo_reference_count(target_student_id uuid, target_photo_path text) TO service_role;

GRANT EXECUTE ON FUNCTION public.id_card_principal_signature_path_is_referenced(target_signature_path text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.id_card_principal_signature_path_is_referenced(target_signature_path text) TO service_role;

GRANT EXECUTE ON FUNCTION public.institution_academic_model() TO authenticated;

GRANT EXECUTE ON FUNCTION public.institution_academic_model() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_access_snapshot() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_adjust_stock(target_item_id uuid, target_location_id uuid, quantity_change numeric, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_adjust_stock(target_item_id uuid, target_location_id uuid, quantity_change numeric, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_asset_assignment_register(active_only boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_asset_assignment_register(active_only boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_asset_maintenance_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_asset_maintenance_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_asset_writeoff_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_asset_writeoff_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_assets_register(search_text text, status_filter text, location_filter uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_assets_register(search_text text, status_filter text, location_filter uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_assign_asset(target_asset_id uuid, target_staff_id uuid, target_location_id uuid, due_date_value date, purpose_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_assign_asset(target_asset_id uuid, target_staff_id uuid, target_location_id uuid, due_date_value date, purpose_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_block_delete() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_catalog(search_text text, item_type_filter text, category_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_catalog(search_text text, item_type_filter text, category_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_complete_asset_maintenance(target_maintenance_id uuid, outcome_text text, next_due_date date, cost_value numeric) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_complete_asset_maintenance(target_maintenance_id uuid, outcome_text text, next_due_date date, cost_value numeric) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_create_purchase_order(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_create_purchase_order(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_create_purchase_request(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_create_purchase_request(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_current_stock(target_item_id uuid, target_location_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_decide_asset_writeoff(target_writeoff_id uuid, decision text, decision_reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_decide_asset_writeoff(target_writeoff_id uuid, decision text, decision_reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_decide_item_request(target_request_id uuid, decision text, decision_reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_decide_item_request(target_request_id uuid, decision text, decision_reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_decide_purchase_order(target_po_id uuid, decision text, decision_reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_decide_purchase_order(target_po_id uuid, decision text, decision_reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_decide_purchase_request(target_request_id uuid, decision text, decision_reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_decide_purchase_request(target_request_id uuid, decision text, decision_reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_fulfill_item_request(target_request_id uuid, target_location_id uuid, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_fulfill_item_request(target_request_id uuid, target_location_id uuid, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_generate_code(code_kind text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_generate_procurement_no(code_kind text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_goods_receipt_detail(target_grn_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_goods_receipt_detail(target_grn_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_goods_receipt_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_goods_receipt_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_identifier_root() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_issue_stock(target_item_id uuid, target_location_id uuid, quantity numeric, recipient_staff_uuid uuid, purpose_text text, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_issue_stock(target_item_id uuid, target_location_id uuid, quantity numeric, recipient_staff_uuid uuid, purpose_text text, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_item_request_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_item_request_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_locations_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_locations_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_my_account() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_my_account() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_my_request_options() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_my_request_options() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_order_detail(target_po_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_order_detail(target_po_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_order_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_order_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_request_detail(target_request_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_request_detail(target_request_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_request_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_purchase_request_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_receive_purchase_order(target_po_id uuid, supplier_delivery_ref_text text, receipt_lines jsonb, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_receive_purchase_order(target_po_id uuid, supplier_delivery_ref_text text, receipt_lines jsonb, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_record_asset_maintenance(target_asset_id uuid, maintenance_kind text, description_text text, vendor_uuid uuid, cost_value numeric, next_due_date date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_record_asset_maintenance(target_asset_id uuid, maintenance_kind text, description_text text, vendor_uuid uuid, cost_value numeric, next_due_date date) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_record_stock_movement(target_item_id uuid, target_location_id uuid, movement_kind text, quantity_change numeric, unit_cost_value numeric, reference_kind text, reference_uuid uuid, reference_text text, related_movement_uuid uuid, recipient_staff_uuid uuid, purpose_text text, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_request_asset_writeoff(target_asset_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_request_asset_writeoff(target_asset_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_require_access(capability text, require_write boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_return_asset(target_assignment_id uuid, return_condition_value text, return_notes_text text, target_location_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_return_asset(target_assignment_id uuid, return_condition_value text, return_notes_text text, target_location_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_return_stock(issue_movement_id uuid, quantity numeric, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_return_stock(issue_movement_id uuid, quantity numeric, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_revoke_staff_access(target_access_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_revoke_staff_access(target_access_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_save_asset(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_save_asset(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_save_item(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_save_item(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_save_location(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_save_location(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_save_settings(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_save_settings(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_save_staff_access(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_save_staff_access(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_save_supplier(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_save_supplier(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_session() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_session() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_settings_read() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_settings_read() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_staff_access_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_staff_access_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_staff_candidates() TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_staff_candidates() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_staff_directory(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_staff_directory(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_stock_movement_register(search_text text, location_filter uuid, movement_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_stock_movement_register(search_text text, location_filter uuid, movement_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_stock_register(search_text text, location_filter uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_stock_register(search_text text, location_filter uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_submit_my_item_request(target_item_id uuid, quantity numeric, purpose_text text, preferred_location_uuid uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_submit_my_item_request(target_item_id uuid, quantity numeric, purpose_text text, preferred_location_uuid uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_suppliers_register(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_suppliers_register(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_touch_updated_at() TO service_role;

GRANT EXECUTE ON FUNCTION public.inventory_transfer_stock(target_item_id uuid, from_location_id uuid, to_location_id uuid, quantity numeric, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.inventory_transfer_stock(target_item_id uuid, from_location_id uuid, to_location_id uuid, quantity numeric, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.is_academic_manager() TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_academic_manager() TO service_role;

GRANT EXECUTE ON FUNCTION public.is_assigned_class_teacher(target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.is_official_class_teacher_for_class(target_class_id uuid, target_user_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_official_class_teacher_for_class(target_class_id uuid, target_user_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.is_official_subject_teacher_for_class(target_class_id uuid, target_subject_id uuid, target_user_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_official_subject_teacher_for_class(target_class_id uuid, target_subject_id uuid, target_user_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.is_platform_super_admin() TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_platform_super_admin() TO service_role;

GRANT EXECUTE ON FUNCTION public.is_records_manager() TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_records_manager() TO service_role;

GRANT EXECUTE ON FUNCTION public.is_system_admin() TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_system_admin() TO service_role;

GRANT EXECUTE ON FUNCTION public.is_term_three(term_sequence integer, term_name text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_term_three(term_sequence integer, term_name text) TO service_role;

GRANT EXECUTE ON FUNCTION public.issue_certificate_batch(target_batch_id uuid, target_issue_date date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.issue_certificate_batch(target_batch_id uuid, target_issue_date date) TO service_role;

GRANT EXECUTE ON FUNCTION public.issue_staff_id_cards(target_academic_year_id uuid, target_staff_keys text[], target_issue_date date, target_expires_on date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.issue_staff_id_cards(target_academic_year_id uuid, target_staff_keys text[], target_issue_date date, target_expires_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date, target_expires_on date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date, target_expires_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.issue_student_transcript(target_student_id uuid, purpose_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.issue_student_transcript(target_student_id uuid, purpose_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_actor_access() TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_actor_access() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_block_delete() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_book_detail(target_book_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_book_detail(target_book_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_cancel_my_reservation(target_reservation_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_cancel_my_reservation(target_reservation_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_catalog_register(search_text text, category_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_catalog_register(search_text text, category_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_generate_accession_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_issue_copy(target_copy_id uuid, borrower_kind text, borrower_id uuid, due_on date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_issue_copy(target_copy_id uuid, borrower_kind text, borrower_id uuid, due_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_loan_register(status_filter text, search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_loan_register(status_filter text, search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_member_search(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_member_search(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_my_account() TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_my_account() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_place_my_reservation(target_book_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_place_my_reservation(target_book_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_public_catalog(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_public_catalog(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_record_copy_event() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_renew_loan(target_loan_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_renew_loan(target_loan_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_require_access(require_write boolean, required_capability text) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_return_copy(target_loan_id uuid, return_condition_status text, return_notes text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_return_copy(target_loan_id uuid, return_condition_status text, return_notes text) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_save_book(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_save_book(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_save_copy(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_save_copy(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_save_staff_access(target_profile_id uuid, target_library_role text, target_active boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_save_staff_access(target_profile_id uuid, target_library_role text, target_active boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.library_session() TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_session() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_settings_get() TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_settings_get() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_staff_access_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_staff_access_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_touch_updated_at() TO service_role;

GRANT EXECUTE ON FUNCTION public.library_update_settings(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.library_update_settings(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.license_access_for_actor(actor_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.license_effective_entitlement() TO authenticated;

GRANT EXECUTE ON FUNCTION public.license_effective_entitlement() TO service_role;

GRANT EXECUTE ON FUNCTION public.license_feature_enabled(feature_code text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.license_feature_enabled(feature_code text) TO service_role;

GRANT EXECUTE ON FUNCTION public.license_feature_for_table(table_name text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.license_feature_for_table(table_name text) TO anon;

GRANT EXECUTE ON FUNCTION public.license_feature_for_table(table_name text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.license_feature_for_table(table_name text) TO service_role;

GRANT EXECUTE ON FUNCTION public.license_read_allowed() TO authenticated;

GRANT EXECUTE ON FUNCTION public.license_read_allowed() TO service_role;

GRANT EXECUTE ON FUNCTION public.license_snapshot_for_role(target_role text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.license_snapshot_for_role(target_role text) TO service_role;

GRANT EXECUTE ON FUNCTION public.license_write_allowed() TO authenticated;

GRANT EXECUTE ON FUNCTION public.license_write_allowed() TO service_role;

GRANT EXECUTE ON FUNCTION public.list_academic_period_controls() TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_academic_period_controls() TO service_role;

GRANT EXECUTE ON FUNCTION public.list_audit_archive_entries_v1(target_archive_id uuid, page_number integer, page_size integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_audit_archive_entries_v1(target_archive_id uuid, page_number integer, page_size integer) TO anon;

GRANT EXECUTE ON FUNCTION public.list_audit_archive_entries_v1(target_archive_id uuid, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_audit_archive_entries_v1(target_archive_id uuid, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_audit_archives_v1(page_number integer, page_size integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_audit_archives_v1(page_number integer, page_size integer) TO anon;

GRANT EXECUTE ON FUNCTION public.list_audit_archives_v1(page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_audit_archives_v1(page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_audit_events_v2(target_table text, target_action text, target_actor_id uuid, target_record_id uuid, page_number integer, page_size integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_audit_events_v2(target_table text, target_action text, target_actor_id uuid, target_record_id uuid, page_number integer, page_size integer) TO anon;

GRANT EXECUTE ON FUNCTION public.list_audit_events_v2(target_table text, target_action text, target_actor_id uuid, target_record_id uuid, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_audit_events_v2(target_table text, target_action text, target_actor_id uuid, target_record_id uuid, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_audit_events(target_table text, target_record_id uuid, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_audit_events(target_table text, target_record_id uuid, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_certificate_eligible_recipients(target_certificate_type text, target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_certificate_eligible_recipients(target_certificate_type text, target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_client_health_events(page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_client_health_events(page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_guardian_portal_accounts(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_guardian_portal_accounts(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_headteachers(search_text text, status_filter text, archive_filter text, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_headteachers(search_text text, status_filter text, archive_filter text, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid, search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid, search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_my_attendance_classes(target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_my_attendance_classes(target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_my_children_reports() TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_my_children_reports() TO service_role;

GRANT EXECUTE ON FUNCTION public.list_notifications(page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_notifications(page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_profiles_with_access() TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_profiles_with_access() TO service_role;

GRANT EXECUTE ON FUNCTION public.list_report_card_templates() TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_report_card_templates() TO service_role;

GRANT EXECUTE ON FUNCTION public.list_report_cards_v6(target_term_id uuid, target_class_id uuid, target_status report_status, search_text text, archive_filter text, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_report_cards_v6(target_term_id uuid, target_class_id uuid, target_status report_status, search_text text, archive_filter text, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_report_cards(target_term_id uuid, target_class_id uuid, target_status report_status, search_text text, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_report_cards(target_term_id uuid, target_class_id uuid, target_status report_status, search_text text, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_report_pdf_paths(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_report_pdf_paths(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_staff_id_card_candidates(target_staff_type text, search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_staff_id_card_candidates(target_staff_type text, search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.list_teachers(search_text text, status_filter text, archive_filter text, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.list_teachers(search_text text, status_filter text, archive_filter text, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.log_client_error(message_text text, stack_text text, context_data jsonb, user_agent_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.log_client_error(message_text text, stack_text text, context_data jsonb, user_agent_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.maintain_client_error_events() TO authenticated;

GRANT EXECUTE ON FUNCTION public.maintain_client_error_events() TO service_role;

GRANT EXECUTE ON FUNCTION public.mark_backup_offsite_copy(target_backup_id uuid, target_note text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.mark_backup_offsite_copy(target_backup_id uuid, target_note text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mark_notifications_read(notification_ids uuid[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.mark_notifications_read(notification_ids uuid[]) TO service_role;

GRANT EXECUTE ON FUNCTION public.mark_report_correction_applied(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.my_realtime_topics() TO authenticated;

GRANT EXECUTE ON FUNCTION public.my_realtime_topics() TO service_role;

GRANT EXECUTE ON FUNCTION public.next_promotion_academic_year(source_year_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.next_promotion_academic_year(source_year_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.operations_dashboard(target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.operations_dashboard(target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.performance_comment_suggestions(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.performance_comment_suggestions(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_clear_license_history(reason_text text, confirmation_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_clear_license_history(reason_text text, confirmation_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_clear_package_history(reason_text text, actor_id_value uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_finalize_package_replacement(target_artifact_id uuid, target_actor_id uuid, reason_text text, confirmation_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_package_session() TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_package_session() TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_package_signing_key_install(target_envelope jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_package_signing_key_read() TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_package_signing_key_repair(target_envelope jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_preview_license_change(target_plan_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_preview_license_change(target_plan_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_record_package_download(target_artifact_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_register_package_template(target_package_version text, target_storage_path text, target_sha256 text, target_file_size bigint, target_required_files jsonb, target_uploaded_by uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_release_access_lock(target_lock_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_release_access_lock(target_lock_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_release_health() TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_set_access_lock(lock_scope_text text, lock_mode_text text, reason_text text, ends_at_value timestamp with time zone) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_set_access_lock(lock_scope_text text, lock_mode_text text, reason_text text, ends_at_value timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_set_distribution_authority(target_actor_id uuid, active_value boolean, can_generate_value boolean, can_revoke_value boolean, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_set_distribution_authority(target_actor_id uuid, active_value boolean, can_generate_value boolean, can_revoke_value boolean, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_set_license_override(feature_overrides jsonb, max_students_value integer, max_teachers_value integer, max_system_admins_value integer, max_guardians_value integer, max_storage_mb_value integer, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_set_license_override(feature_overrides jsonb, max_students_value integer, max_teachers_value integer, max_system_admins_value integer, max_guardians_value integer, max_storage_mb_value integer, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_update_license(target_plan_id uuid, target_status text, issue_date date, activation_date timestamp with time zone, expiry_date timestamp with time zone, grace_end_date timestamp with time zone, license_reference_text text, notes_text text, compliance_reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_update_license(target_plan_id uuid, target_status text, issue_date date, activation_date timestamp with time zone, expiry_date timestamp with time zone, grace_end_date timestamp with time zone, license_reference_text text, notes_text text, compliance_reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.platform_upsert_license_plan(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.platform_upsert_license_plan(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.prepare_score_entry() TO service_role;

GRANT EXECUTE ON FUNCTION public.prevent_license_history_mutation() TO service_role;

GRANT EXECUTE ON FUNCTION public.prospectus_class_range_label(value text) TO service_role;

GRANT EXECUTE ON FUNCTION public.protect_profile_historical_identity() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.protect_profile_historical_identity() TO anon;

GRANT EXECUTE ON FUNCTION public.protect_profile_historical_identity() TO authenticated;

GRANT EXECUTE ON FUNCTION public.protect_profile_historical_identity() TO service_role;

GRANT EXECUTE ON FUNCTION public.protect_profile_security_fields() TO service_role;

GRANT EXECUTE ON FUNCTION public.protect_report_mutation() TO service_role;

GRANT EXECUTE ON FUNCTION public.protect_security_event_delete() TO service_role;

GRANT EXECUTE ON FUNCTION public.publish_school_prospectus(target_prospectus_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.publish_school_prospectus(target_prospectus_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.queue_incomplete_report_notifications(target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.queue_incomplete_report_notifications(target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.rce_finalized_storage_object_size(target_metadata jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.recalculate_report_grades(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_backup_export(target_storage_path text, target_checksum text, target_row_counts jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.record_backup_export(target_storage_path text, target_checksum text, target_row_counts jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_certificate_event(target_batch_id uuid, target_certificate_id uuid, event_name text, reason_text text, details_data jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_id_card_event(target_card_id uuid, target_student_id uuid, target_event_type text, target_details jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_license_authority_verification(expected_hash text, authority_state text, details jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_license_binding_verification(target_actor_id uuid, verified_origin_host text, verified_project_ref text, verified_installation_id uuid, details jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_license_signature_verification(expected_hash text, key_id text, verified boolean, details jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_security_event(event_type_text text, severity_text text, message_text text, details_data jsonb, source_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.record_security_event(event_type_text text, severity_text text, message_text text, details_data jsonb, source_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_staff_id_card_event(target_card_id uuid, target_staff_type text, target_staff_id uuid, event_name text, event_details jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.record_student_lifecycle_event(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.record_student_lifecycle_event(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.refresh_report_promotion(target_report_id uuid, create_target_enrollment boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.refresh_subject_result(target_result_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.register_certificate_pdf(target_certificate_id uuid, target_storage_path text, target_checksum text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.register_certificate_pdf(target_certificate_id uuid, target_storage_path text, target_checksum text) TO service_role;

GRANT EXECUTE ON FUNCTION public.register_report_pdf(target_report_id uuid, target_storage_path text, target_checksum text, target_page_count integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.register_report_pdf(target_report_id uuid, target_storage_path text, target_checksum text, target_page_count integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.remove_certificate_template_file(target_certificate_type text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.remove_certificate_template_file(target_certificate_type text) TO service_role;

GRANT EXECUTE ON FUNCTION public.remove_report_card_template(target_range_key text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.remove_report_card_template(target_range_key text) TO service_role;

GRANT EXECUTE ON FUNCTION public.replace_staff_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.replace_staff_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.replace_student_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.replace_student_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) TO service_role;

GRANT EXECUTE ON FUNCTION public.report_class_id(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.report_class_id(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.report_position(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.report_position(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.report_promotion_canonical(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.report_promotion_canonical(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.report_promotion_evaluation(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.report_promotion_evaluation(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.report_student_id(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.report_student_id(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.report_subject_positions(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.report_subject_positions(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.report_transition_deadline_allowed(target_report_id uuid, target_status report_status) TO authenticated;

GRANT EXECUTE ON FUNCTION public.report_transition_deadline_allowed(target_report_id uuid, target_status report_status) TO service_role;

GRANT EXECUTE ON FUNCTION public.request_report_correction(target_report_id uuid, reason_text text, requested_fields jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.request_report_correction(target_report_id uuid, reason_text text, requested_fields jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.require_license_feature(feature_code text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.require_license_feature(feature_code text) TO service_role;

GRANT EXECUTE ON FUNCTION public.require_platform_super_admin() TO service_role;

GRANT EXECUTE ON FUNCTION public.require_sensitive_access() TO service_role;

GRANT EXECUTE ON FUNCTION public.reset_audit_log(confirmation_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.reset_audit_log(confirmation_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.resolve_assessment_scheme(target_class_id uuid, target_subject_id uuid, target_academic_year_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.resolve_grading_guide(target_academic_year_id uuid, target_class_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.resolve_grading_guide(target_academic_year_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.resolve_report_grading_guide(target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.resolve_report_grading_guide(target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.resolve_security_event(target_event_id bigint, target_status text, resolution_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.resolve_security_event(target_event_id bigint, target_status text, resolution_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.restore_headteacher(target_headteacher_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.restore_headteacher(target_headteacher_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.restore_report_card(target_report_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.restore_report_card(target_report_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.restore_student(target_student_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.restore_student(target_student_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.restore_teacher(target_teacher_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.restore_teacher(target_teacher_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.review_certificate_batch(target_batch_id uuid, decision text, review_note_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.review_certificate_batch(target_batch_id uuid, decision text, review_note_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.review_report_correction(target_request_id uuid, decision text, review_note_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.review_report_correction(target_request_id uuid, decision text, review_note_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.revoke_certificate(target_certificate_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.revoke_certificate(target_certificate_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.revoke_emergency_academic_delegation(target_delegation_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.revoke_emergency_academic_delegation(target_delegation_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.revoke_staff_id_card(target_card_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.revoke_staff_id_card(target_card_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.revoke_student_id_card(target_card_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.revoke_student_id_card(target_card_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.revoke_student_transcript(target_issuance_id uuid, reason_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.revoke_student_transcript(target_issuance_id uuid, reason_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.run_academic_alerts(target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.run_academic_alerts(target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.safe_boolean(value text, default_value boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.safe_boolean(value text, default_value boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.safe_date(value text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.safe_date(value text) TO service_role;

GRANT EXECUTE ON FUNCTION public.safe_integer(value text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.safe_integer(value text) TO service_role;

GRANT EXECUTE ON FUNCTION public.safe_numeric(value text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.safe_numeric(value text) TO service_role;

GRANT EXECUTE ON FUNCTION public.safe_timestamptz(value text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.safe_timestamptz(value text) TO service_role;

GRANT EXECUTE ON FUNCTION public.safe_uuid(value text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.safe_uuid(value text) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_academic_entity(entity_type text, payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_academic_entity(entity_type text, payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_academic_period_control(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_academic_period_control(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_assessment_scheme(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_assessment_scheme(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_backup_policy(target_retention_days integer, target_minimum_copies integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_backup_policy(target_retention_days integer, target_minimum_copies integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_certificate_settings(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_certificate_settings(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_certificate_template(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_certificate_template(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_class_attendance(target_term_id uuid, target_class_id uuid, target_date date, entries jsonb, notes_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_class_attendance(target_term_id uuid, target_class_id uuid, target_date date, entries jsonb, notes_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_class_subject_assignments_batch(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_class_subject_assignments_batch(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_class_subject_assignment(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_class_subject_assignment(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_class_timetable_entry(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_class_timetable_entry(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_grading_scale(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_grading_scale(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_headteacher(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_headteacher(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_id_card_settings(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_id_card_settings(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_profile_access(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_promotion_cutoff(target_score integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_promotion_cutoff(target_score integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_report_card(payload jsonb, expected_version integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_report_card(payload jsonb, expected_version integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_report_comments(target_report_id uuid, teacher_comment_text text, head_comment_text text, expected_version integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_report_comments(target_report_id uuid, teacher_comment_text text, head_comment_text text, expected_version integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_retention_policy(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_retention_policy(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_school_identity_settings(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_school_identity_settings(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_school_prospectus_item(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_school_prospectus_item(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_school_prospectus_section(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_school_prospectus_section(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_school_prospectus(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_school_prospectus(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_security_verification(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_security_verification(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_student(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_student(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_teacher_award_category(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_teacher_award_category(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.save_teacher(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_teacher(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_apply_table(target_job uuid, target_table text, target_rows jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_begin(target_filename text, target_path text, target_checksum text, target_size bigint, target_actor uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_clear_operational_data(target_job uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_commit_staged(target_job uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_complete(target_job uuid, target_expected jsonb, target_storage jsonb, target_auth_expected integer, target_auth_reconciled integer, target_backup_key text, target_schema text, target_school_name text, target_school_code text, target_notes text) TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.school_restore_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_set_status(target_job uuid, target_status text, target_error text, target_notes text) TO service_role;

GRANT EXECUTE ON FUNCTION public.school_restore_stage_table(target_job uuid, target_table text, target_rows jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.search_students_v5(search_text text, target_class_id uuid, target_status student_status, archive_filter text, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.search_students_v5(search_text text, target_class_id uuid, target_status student_status, archive_filter text, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.search_students(search_text text, target_class_id uuid, target_status student_status, page_number integer, page_size integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.search_students(search_text text, target_class_id uuid, target_status student_status, page_number integer, page_size integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.set_active_period(target_academic_year_id uuid, target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_active_period(target_academic_year_id uuid, target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.set_headteacher_photo(target_headteacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_headteacher_photo(target_headteacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.set_my_headteacher_signature(target_signature_path text, expected_updated_at timestamp with time zone) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_my_headteacher_signature(target_signature_path text, expected_updated_at timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.set_school_logo_reference(target_logo_url text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_school_logo_reference(target_logo_url text) TO service_role;

GRANT EXECUTE ON FUNCTION public.set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.set_teacher_photo(target_teacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_teacher_photo(target_teacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.set_updated_at() TO service_role;

GRANT EXECUTE ON FUNCTION public.staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text) TO service_role;

GRANT EXECUTE ON FUNCTION public.staff_id_card_photo_reference_count(target_staff_id uuid, target_photo_path text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.staff_id_card_photo_reference_count(target_staff_id uuid, target_photo_path text) TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_actor_context() TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_block_delete() TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_has_access(target_domain text, target_action text) TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_reference_data(target_domain text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.student_services_reference_data(target_domain text) TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_require_access(target_domain text, target_action text) TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_save_staff_access(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.student_services_save_staff_access(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_session() TO authenticated;

GRANT EXECUTE ON FUNCTION public.student_services_session() TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_staff_candidates(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.student_services_staff_candidates(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_staff_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.student_services_staff_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_student_picker(target_domain text, search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.student_services_student_picker(target_domain text, search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.student_services_touch_updated_at() TO service_role;

GRANT EXECUTE ON FUNCTION public.submit_certificate_batch(target_batch_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.submit_certificate_batch(target_batch_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.supersede_transcripts_on_publication_change() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.supersede_transcripts_on_publication_change() TO anon;

GRANT EXECUTE ON FUNCTION public.supersede_transcripts_on_publication_change() TO authenticated;

GRANT EXECUTE ON FUNCTION public.supersede_transcripts_on_publication_change() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_attendance_reports(target_term_id uuid, target_class_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_class_teacher_responsibility_trigger() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_current_academic_year_status() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_license_feature_rpc_privileges() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_pending_promotions_when_year_changes() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_report_next_term_reopening_date() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_report_promotion_from_subject_result() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_subject_teacher_responsibility_trigger() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_teacher_record_class_links() TO service_role;

GRANT EXECUTE ON FUNCTION public.sync_teacher_responsibility_access(target_user_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.system_health() TO authenticated;

GRANT EXECUTE ON FUNCTION public.system_health() TO service_role;

GRANT EXECUTE ON FUNCTION public.tenant_runtime_release_identity() TO authenticated;

GRANT EXECUTE ON FUNCTION public.tenant_runtime_release_identity() TO service_role;

GRANT EXECUTE ON FUNCTION public.term_calendar_status_trigger() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.term_calendar_status_trigger() TO anon;

GRANT EXECUTE ON FUNCTION public.term_calendar_status_trigger() TO authenticated;

GRANT EXECUTE ON FUNCTION public.term_calendar_status_trigger() TO service_role;

GRANT EXECUTE ON FUNCTION public.term_control_snapshot(target_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.term_control_snapshot(target_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.term_phase_writable(target_term_id uuid, target_phase text, target_report_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.term_phase_writable(target_term_id uuid, target_phase text, target_report_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_grade_for_score(p_score numeric) TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_grade_for_score(p_score numeric) TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_grading_scale_readiness() TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_grading_scale_readiness() TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_programme_completion_readiness(p_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_programme_completion_readiness(p_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_save_course_result(p_course_registration_id uuid, p_continuous_assessment_score numeric, p_examination_score numeric, p_total_score numeric) TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_save_course_result(p_course_registration_id uuid, p_continuous_assessment_score numeric, p_examination_score numeric, p_total_score numeric) TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_set_result_status(p_result_id uuid, p_status text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_set_result_status(p_result_id uuid, p_status text) TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_student_cgpa(p_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_student_cgpa(p_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_student_gpa(p_student_id uuid, p_academic_year_id uuid, p_term_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_student_gpa(p_student_id uuid, p_academic_year_id uuid, p_term_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.tertiary_transcript_snapshot(p_student_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.tertiary_transcript_snapshot(p_student_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.transition_report_status(target_report_id uuid, target_status report_status, comment_text text, expected_version integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transition_report_status(target_report_id uuid, target_status report_status, comment_text text, expected_version integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_actor_access() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_add_incident(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_add_incident(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_add_maintenance(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_add_maintenance(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_assign_student(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_assign_student(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_assignment_register(target_route_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_assignment_register(target_route_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_block_delete() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_can_operate_trip(target_trip_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_cancel_trip(target_trip_id uuid, reason text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_cancel_trip(target_trip_id uuid, reason text) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_complete_trip(target_trip_id uuid, end_odometer_km numeric) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_complete_trip(target_trip_id uuid, end_odometer_km numeric) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_create_trip(target_route_id uuid, target_service_date date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_create_trip(target_route_id uuid, target_service_date date) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_dashboard() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_dashboard() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_driver_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_driver_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_end_assignment(target_assignment_id uuid, end_date date) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_end_assignment(target_assignment_id uuid, end_date date) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_enforce_write() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_generate_fleet_no() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_generate_route_code() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_generate_stop_code() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_identifier_root() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_incident_register(status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_incident_register(status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_maintenance_register(target_vehicle_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_maintenance_register(target_vehicle_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_mark_student(target_trip_student_id uuid, target_status text, note text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_mark_student(target_trip_student_id uuid, target_status text, note text) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_my_account() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_my_account() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_require_access(require_write boolean, required_capability text) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_resolve_incident(target_incident_id uuid, resolution text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_resolve_incident(target_incident_id uuid, resolution text) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_route_detail(target_route_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_route_detail(target_route_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_route_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_route_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_save_driver(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_save_driver(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_save_route(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_save_route(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_save_stop(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_save_stop(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_save_vehicle(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_save_vehicle(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_session() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_session() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_set_route_stops(target_route_id uuid, stops jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_set_route_stops(target_route_id uuid, stops jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_set_staff_access(target_hr_staff_id uuid, target_role text, target_active boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_set_staff_access(target_hr_staff_id uuid, target_role text, target_active boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_settings_get() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_settings_get() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_settings_save(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_settings_save(payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_staff_candidates() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_staff_candidates() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_start_trip(target_trip_id uuid, start_odometer_km numeric) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_start_trip(target_trip_id uuid, start_odometer_km numeric) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_stop_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_stop_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_student_search(search_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_student_search(search_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_touch_updated_at() TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_trip_detail(target_trip_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_trip_detail(target_trip_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_trip_register(date_from date, date_to date, status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_trip_register(date_from date, date_to date, status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.transport_vehicle_register() TO authenticated;

GRANT EXECUTE ON FUNCTION public.transport_vehicle_register() TO service_role;

GRANT EXECUTE ON FUNCTION public.trigger_sync_license_feature_rpc_privileges() TO service_role;

GRANT EXECUTE ON FUNCTION public.update_privacy_request(target_request_id uuid, target_status text, outcome_text text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.update_privacy_request(target_request_id uuid, target_status text, outcome_text text) TO service_role;

GRANT EXECUTE ON FUNCTION public.user_account_lifecycle_summary() TO authenticated;

GRANT EXECUTE ON FUNCTION public.user_account_lifecycle_summary() TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_academic_year_calendar_integrity() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.validate_academic_year_calendar_integrity() TO anon;

GRANT EXECUTE ON FUNCTION public.validate_academic_year_calendar_integrity() TO authenticated;

GRANT EXECUTE ON FUNCTION public.validate_academic_year_calendar_integrity() TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_assessment_scheme_weights() TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_class_timetable_entry() TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_grading_scale_overlap() TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_operational_readiness() TO authenticated;

GRANT EXECUTE ON FUNCTION public.validate_operational_readiness() TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_score_import(target_term_id uuid, target_class_id uuid, rows jsonb, filename text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.validate_score_import(target_term_id uuid, target_class_id uuid, rows jsonb, filename text) TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_student_import(rows jsonb, target_academic_year_id uuid, target_class_id uuid, filename text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.validate_student_import(rows jsonb, target_academic_year_id uuid, target_class_id uuid, filename text) TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_term_calendar_integrity() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.validate_term_calendar_integrity() TO anon;

GRANT EXECUTE ON FUNCTION public.validate_term_calendar_integrity() TO authenticated;

GRANT EXECUTE ON FUNCTION public.validate_term_calendar_integrity() TO service_role;

GRANT EXECUTE ON FUNCTION public.validate_term_reopening_date() TO service_role;

GRANT EXECUTE ON FUNCTION public.verify_certificate(token uuid) TO anon;

GRANT EXECUTE ON FUNCTION public.verify_certificate(token uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.verify_certificate(token uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.verify_license_binding(client_origin text, client_project_ref text, client_installation_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.verify_report(token uuid) TO anon;

GRANT EXECUTE ON FUNCTION public.verify_report(token uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.verify_report(token uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.verify_staff_id_card(token uuid) TO anon;

GRANT EXECUTE ON FUNCTION public.verify_staff_id_card(token uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.verify_staff_id_card(token uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.verify_student_id_card(token uuid) TO anon;

GRANT EXECUTE ON FUNCTION public.verify_student_id_card(token uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.verify_student_id_card(token uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.verify_transcript(token uuid) TO anon;

GRANT EXECUTE ON FUNCTION public.verify_transcript(token uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.verify_transcript(token uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.welfare_add_note(target_case_id uuid, note_type text, note_text text, confidential boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.welfare_add_note(target_case_id uuid, note_type text, note_text text, confidential boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.welfare_case_detail(target_case_id uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.welfare_case_detail(target_case_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.welfare_case_register(search_text text, status_filter text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.welfare_case_register(search_text text, status_filter text) TO service_role;

GRANT EXECUTE ON FUNCTION public.welfare_close_case(target_case_id uuid, closure_notes text, new_status text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.welfare_close_case(target_case_id uuid, closure_notes text, new_status text) TO service_role;

GRANT EXECUTE ON FUNCTION public.welfare_save_case(payload jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.welfare_save_case(payload jsonb) TO service_role;

COMMENT ON TABLE public.audit_log IS 'Protected audit trail. Authenticated clients must use guarded audit RPCs; direct table reads are revoked so MFA-sensitive access cannot be bypassed.';

COMMENT ON COLUMN public.school_settings.identifier_root IS 'Hyphen-free root used for globally unique student and staff identifiers.';

COMMENT ON COLUMN public.school_settings.promotion_cutoff_score IS 'Term 3 overall-average pass mark for automatic promotion. System Administrator selectable from 40 through 60.';

COMMENT ON COLUMN public.school_settings.report_body_font IS 'Font family embedded into the generated report-card body. Defaults to Times New Roman.';

COMMENT ON COLUMN public.school_settings.report_body_font_size IS 'Base report-card body font size in points. Valid range: 8 to 16. Defaults to 11.';

COMMENT ON COLUMN public.school_settings.tenant_code IS 'Canonical school tenant code, for example NIS-000002.';

COMMENT ON COLUMN public.school_settings.user_email_domain IS 'Domain used when the system automatically generates user account email addresses.';

COMMENT ON FUNCTION public.admin_remove_accounts_staff_permanently(target_staff_id uuid, reason_text text) IS 'Compatibility RPC retained for older clients. Hard deletion is blocked; Accounts Office Staff records must be archived/deactivated for audit and identity continuity.';

COMMENT ON FUNCTION public.audit_row_change() IS 'v7.3.3 audit trigger. Suppresses profile heartbeat-only changes and preserves substantive immutable audit records.';

COMMENT ON FUNCTION public.bulk_promote_all_classes(source_academic_year_id uuid, target_academic_year_id uuid) IS 'Processes every active source class that has a configured next class and maps each class to its respective next class in one atomic operation.';

COMMENT ON FUNCTION public.bulk_promote_class(source_academic_year_id uuid, source_class_id uuid, target_academic_year_id uuid, target_class_id uuid) IS 'Evaluates all complete Term 3 records but creates next-year enrolments only for approved or published reports.';

COMMENT ON FUNCTION public.delete_report_card_permanently(target_report_id uuid, reason_text text) IS 'Permanently removes an authorised report and all cascading score, workflow, revision, publication, notification, and related audit records.';

COMMENT ON FUNCTION public.enforce_licensed_storage_capacity() IS 'r9 two-phase Supabase Storage compatibility guard. Permission probes pass; finalized object sizes remain licence-capacity enforced.';

COMMENT ON FUNCTION public.enforce_licensed_write() IS 'v7.3.3 table-safe licensing guard. Uses JSONB trigger records and permits trusted operational evidence in every licence mode.';

COMMENT ON FUNCTION public.enforce_system_admin_capacity() IS 'v7.3.1 profile capacity trigger. Uses v_now timestamptz to avoid the PostgreSQL CURRENT_TIME timetz keyword collision.';

COMMENT ON FUNCTION public.ensure_current_user_profile() IS 'v7.3.3 idempotent authenticated profile bootstrap. Repairs only missing or legacy profile values.';

COMMENT ON FUNCTION public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid) IS 'Generates a unique user email using the configurable school_settings.user_email_domain. The legacy function name is retained for API compatibility.';

COMMENT ON FUNCTION public.generate_school_identifier(identifier_kind text) IS 'Generates school-scoped admission and staff identifiers from the canonical tenant identity.';

COMMENT ON FUNCTION public.get_report_headteacher_signature(target_report_id uuid) IS 'Returns the currently active Principal name and signature for every newly generated or regenerated official report PDF.';

COMMENT ON FUNCTION public.get_school_license_capacity_console() IS 'Read-only licence status, verification, feature, usage, and capacity console. r17 includes official school-branding Storage.';

COMMENT ON FUNCTION public.is_term_three(term_sequence integer, term_name text) IS 'Recognises Term 3 by configured sequence or common Term 3 naming formats.';

COMMENT ON FUNCTION public.license_feature_enabled(feature_code text) IS 'r14 feature resolver. Explicit signed flags always win; compatible pre-feature school licences inherit ID cards, timetable and school prospectus only from core_records.';

COMMENT ON FUNCTION public.license_snapshot_for_role(target_role text) IS 'v7.3.1 licensing runtime snapshot. Uses v_now timestamptz to avoid the PostgreSQL CURRENT_TIME timetz keyword collision.';

COMMENT ON FUNCTION public.list_report_pdf_paths(target_report_id uuid) IS 'Returns stored PDF paths so the authorised client can remove Storage objects before permanent report deletion.';

COMMENT ON FUNCTION public.next_promotion_academic_year(source_year_id uuid) IS 'Returns the immediate next configured academic year for promotion processing.';

COMMENT ON FUNCTION public.rce_finalized_storage_object_size(target_metadata jsonb) IS 'Returns the finalized Supabase Storage object size. Permission-probe metadata such as contentLength intentionally returns NULL.';

COMMENT ON FUNCTION public.report_promotion_evaluation(target_report_id uuid) IS 'Evaluates Term 3 eligibility and reports whether the immediate next-year enrolment has actually been applied.';

COMMENT ON FUNCTION public.report_subject_positions(target_report_id uuid) IS 'Returns independent dense subject positions for a report by comparing each total score with the same subject in the same class and term.';

COMMENT ON FUNCTION public.save_promotion_cutoff(target_score integer) IS 'System Administrator-only academic setting for the Term 3 automatic-promotion pass mark.';

COMMENT ON FUNCTION public.school_restore_commit_staged(target_job uuid) IS 'Atomic school restore commit. Tenant-bound identifier root, email domain, verification URL, and platform licence boundary are preserved; legacy academic identifiers remain unchanged.';

COMMENT ON FUNCTION public.tenant_runtime_release_identity() IS 'Returns the immutable release identity stamped by the master provisioner after the complete tenant release has been applied.';


ALTER DEFAULT PRIVILEGES FOR ROLE edusentia_owner IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE edusentia_owner IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE edusentia_owner IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
