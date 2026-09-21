-- Edusentia tenant foundation: types, sequences, tables
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

CREATE TYPE public.app_role AS ENUM ('admin','teacher','viewer','system_admin','headteacher','academic_admin','class_teacher','subject_teacher','records_officer','parent_guardian','principal','platform_super_admin','accounts_office','student','accountant');

CREATE TYPE public.report_status AS ENUM ('draft','submitted','class_reviewed','approved','published','returned','withdrawn');

CREATE TYPE public.student_status AS ENUM ('active','graduated','withdrawn','suspended');

CREATE SEQUENCE public.accounts_office_staff_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.admissions_application_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.admissions_student_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.alumni_record_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.certificate_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.finance_invoice_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.finance_payroll_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.finance_receipt_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.hr_staff_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_asset_tag_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_grn_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_item_code_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_po_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_pr_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_request_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_supplier_code_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.inventory_writeoff_no_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.library_accession_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.school_staff_identifier_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.school_student_identifier_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.staff_id_card_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.staff_identifier_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.student_id_card_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.student_identifier_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.transcript_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.transport_route_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.transport_stop_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.transport_vehicle_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE TABLE public.academic_departments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  faculty_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.academic_faculties (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.academic_levels (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  programme_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  institution_scope text NOT NULL,
  level_order integer NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.academic_period_controls (
  term_id uuid NOT NULL,
  score_entry_deadline timestamp with time zone,
  attendance_deadline timestamp with time zone,
  report_submission_deadline timestamp with time zone,
  principal_approval_deadline timestamp with time zone,
  publication_deadline timestamp with time zone,
  scores_locked boolean DEFAULT false NOT NULL,
  attendance_locked boolean DEFAULT false NOT NULL,
  reports_locked boolean DEFAULT false NOT NULL,
  lock_reason text DEFAULT ''::text NOT NULL,
  locked_by uuid,
  locked_at timestamp with time zone,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.academic_programmes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  department_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  institution_scope text NOT NULL,
  award_type text DEFAULT ''::text NOT NULL,
  duration_years numeric(4,1),
  description text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.academic_years (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name citext NOT NULL,
  start_date date,
  end_date date,
  is_active boolean DEFAULT false NOT NULL,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.accounts_office_staff (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  profile_id uuid,
  staff_no citext NOT NULL,
  full_name text NOT NULL,
  phone text DEFAULT ''::text NOT NULL,
  email citext,
  contact_address text DEFAULT ''::text NOT NULL,
  job_title text DEFAULT 'Accounts Office Staff'::text NOT NULL,
  finance_role text DEFAULT 'accounts_officer'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.admissions_applications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  application_no text NOT NULL,
  first_name text NOT NULL,
  middle_name text,
  last_name text NOT NULL,
  gender text NOT NULL,
  date_of_birth date,
  guardian_name text NOT NULL,
  guardian_phone text,
  guardian_email text,
  address text,
  previous_school text,
  target_academic_year_id uuid,
  applying_class_id uuid,
  status text DEFAULT 'draft'::text NOT NULL,
  source text DEFAULT 'school_entry'::text NOT NULL,
  applicant_notes text,
  internal_notes text,
  submitted_at timestamp with time zone,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  decided_by uuid,
  decided_at timestamp with time zone,
  student_id uuid,
  enrolled_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.admissions_documents (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  application_id uuid NOT NULL,
  document_type text NOT NULL,
  document_name text NOT NULL,
  storage_path text,
  verification_status text DEFAULT 'pending'::text NOT NULL,
  verified_by uuid,
  verified_at timestamp with time zone,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.admissions_offers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  application_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  status text DEFAULT 'offered'::text NOT NULL,
  offer_date date DEFAULT CURRENT_DATE NOT NULL,
  expires_at date,
  conditions text,
  decision_notes text,
  accepted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.alumni_engagements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  alumni_id uuid NOT NULL,
  engagement_type text NOT NULL,
  engagement_date date DEFAULT CURRENT_DATE NOT NULL,
  summary text NOT NULL,
  outcome text,
  finance_reference text,
  recorded_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.alumni_records (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  alumni_code text NOT NULL,
  student_id uuid,
  former_admission_no text,
  first_name text NOT NULL,
  middle_name text,
  last_name text NOT NULL,
  graduation_academic_year_id uuid,
  final_class_id uuid,
  personal_email text,
  phone text,
  location text,
  occupation text,
  employer text,
  further_education text,
  consent_to_contact boolean DEFAULT false NOT NULL,
  directory_visible boolean DEFAULT false NOT NULL,
  verification_status text DEFAULT 'unverified'::text NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  notes text,
  created_by uuid,
  verified_by uuid,
  verified_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.alumni_verification_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  alumni_id uuid,
  request_type text NOT NULL,
  requester_name text NOT NULL,
  requester_email text,
  requester_phone text,
  purpose text,
  status text DEFAULT 'pending'::text NOT NULL,
  outcome_notes text,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.assessment_components (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  scheme_id uuid NOT NULL,
  name text NOT NULL,
  code citext NOT NULL,
  maximum_score numeric(7,2) NOT NULL,
  weight numeric(6,3) NOT NULL,
  display_order integer DEFAULT 0 NOT NULL,
  required boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.assessment_schemes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  academic_year_id uuid,
  term_id uuid,
  class_id uuid,
  subject_id uuid,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.assessment_score_entries (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  subject_result_id uuid NOT NULL,
  component_id uuid NOT NULL,
  raw_score numeric(7,2) DEFAULT 0 NOT NULL,
  weighted_score numeric(7,2) DEFAULT 0 NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  actor_id uuid,
  table_name text NOT NULL,
  record_id uuid,
  action text NOT NULL,
  old_data jsonb,
  new_data jsonb,
  reason text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.audit_log_archive_entries (
  archive_id uuid NOT NULL,
  original_event_id bigint NOT NULL,
  actor_id uuid,
  table_name text NOT NULL,
  record_id uuid,
  action text NOT NULL,
  old_data jsonb,
  new_data jsonb,
  reason text DEFAULT ''::text NOT NULL,
  original_created_at timestamp with time zone NOT NULL
);

CREATE TABLE public.audit_log_archives (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  archive_scope text NOT NULL,
  reason text DEFAULT ''::text NOT NULL,
  event_count bigint DEFAULT 0 NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.backup_exports (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  storage_path text NOT NULL,
  checksum text DEFAULT ''::text NOT NULL,
  status text DEFAULT 'completed'::text NOT NULL,
  row_counts jsonb DEFAULT '{}'::jsonb NOT NULL,
  initiated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  backup_key text DEFAULT ''::text NOT NULL,
  schema_version text DEFAULT '6.7.0'::text NOT NULL,
  backup_type text DEFAULT 'full'::text NOT NULL,
  manifest_path text DEFAULT ''::text NOT NULL,
  database_path text DEFAULT ''::text NOT NULL,
  storage_object_counts jsonb DEFAULT '{}'::jsonb NOT NULL,
  storage_bytes bigint DEFAULT 0 NOT NULL,
  encrypted boolean DEFAULT true NOT NULL,
  encryption_key_hint text DEFAULT ''::text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  completed_at timestamp with time zone,
  expires_at timestamp with time zone,
  error_message text DEFAULT ''::text NOT NULL,
  verification_status text DEFAULT 'not_tested'::text NOT NULL,
  verification_checked_at timestamp with time zone,
  verification_notes text DEFAULT ''::text NOT NULL,
  offsite_copied_at timestamp with time zone,
  offsite_copy_note text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.backup_storage_objects (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  backup_export_id uuid NOT NULL,
  source_bucket text NOT NULL,
  source_path text NOT NULL,
  backup_path text NOT NULL,
  content_type text DEFAULT 'application/octet-stream'::text NOT NULL,
  original_size bigint DEFAULT 0 NOT NULL,
  encrypted_size bigint DEFAULT 0 NOT NULL,
  checksum text DEFAULT ''::text NOT NULL,
  status text DEFAULT 'completed'::text NOT NULL,
  error_message text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.certificate_batches (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  certificate_type text NOT NULL,
  academic_year_id uuid NOT NULL,
  term_id uuid,
  class_id uuid,
  teacher_award_category_id uuid,
  template_id uuid NOT NULL,
  title text NOT NULL,
  custom_citation text DEFAULT ''::text NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  review_note text DEFAULT ''::text NOT NULL,
  prepared_by uuid DEFAULT auth.uid(),
  submitted_by uuid,
  approved_by uuid,
  issued_by uuid,
  submitted_at timestamp with time zone,
  approved_at timestamp with time zone,
  issued_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.certificate_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  certificate_id uuid,
  batch_id uuid,
  event_type text NOT NULL,
  actor_id uuid DEFAULT auth.uid(),
  reason text DEFAULT ''::text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.certificate_templates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  certificate_type text NOT NULL,
  name text NOT NULL,
  title text NOT NULL,
  subtitle text DEFAULT ''::text NOT NULL,
  statement_template text NOT NULL,
  footer_text text DEFAULT ''::text NOT NULL,
  primary_colour text DEFAULT '#0a2f73'::text NOT NULL,
  accent_colour text DEFAULT '#f1b51c'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  storage_path text DEFAULT ''::text NOT NULL,
  original_name text DEFAULT ''::text NOT NULL,
  mime_type text DEFAULT ''::text NOT NULL,
  file_size bigint DEFAULT 0 NOT NULL,
  checksum text DEFAULT ''::text NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  uploaded_by uuid
);

CREATE TABLE public.certificates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  batch_id uuid NOT NULL,
  recipient_kind text NOT NULL,
  student_id uuid,
  teacher_id uuid,
  source_report_id uuid,
  certificate_number citext,
  verification_token uuid DEFAULT gen_random_uuid() NOT NULL,
  revision_no integer DEFAULT 1 NOT NULL,
  supersedes_certificate_id uuid,
  recipient_name text NOT NULL,
  recipient_identifier text DEFAULT ''::text NOT NULL,
  current_class_name text DEFAULT ''::text NOT NULL,
  destination_class_name text DEFAULT ''::text NOT NULL,
  academic_year_name text NOT NULL,
  certificate_title text NOT NULL,
  award_category_name text DEFAULT ''::text NOT NULL,
  statement_text text NOT NULL,
  issue_date date,
  status text DEFAULT 'draft'::text NOT NULL,
  snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
  pdf_storage_path text DEFAULT ''::text NOT NULL,
  pdf_sha256 text DEFAULT ''::text NOT NULL,
  revocation_reason text DEFAULT ''::text NOT NULL,
  replacement_reason text DEFAULT ''::text NOT NULL,
  approved_by uuid,
  issued_by uuid,
  revoked_by uuid,
  approved_at timestamp with time zone,
  issued_at timestamp with time zone,
  revoked_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.class_attendance_registers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  term_id uuid NOT NULL,
  class_id uuid NOT NULL,
  attendance_date date NOT NULL,
  marked_by uuid NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.class_subjects (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  class_id uuid NOT NULL,
  subject_id uuid NOT NULL,
  teacher_id uuid,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.class_timetable_entries (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  day_of_week text NOT NULL,
  period_start time without time zone NOT NULL,
  period_end time without time zone NOT NULL,
  subject_id uuid NOT NULL,
  teacher_id uuid NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.classes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name citext NOT NULL,
  level_order integer DEFAULT 0 NOT NULL,
  class_teacher_id uuid,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  class_teacher_record_id uuid
);

CREATE TABLE public.client_error_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  actor_id uuid,
  message text NOT NULL,
  stack text DEFAULT ''::text NOT NULL,
  context jsonb DEFAULT '{}'::jsonb NOT NULL,
  user_agent text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  severity text DEFAULT 'error'::text NOT NULL,
  category text DEFAULT 'application'::text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  occurrence_count integer DEFAULT 1 NOT NULL,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  fingerprint text DEFAULT ''::text NOT NULL,
  resolved_at timestamp with time zone,
  resolution_note text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.communication_campaigns (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  category text DEFAULT 'general'::text NOT NULL,
  audience_type text NOT NULL,
  audience_class_id uuid,
  audience_profile_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  channels text[] DEFAULT ARRAY['in_app'::text] NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  scheduled_at timestamp with time zone,
  published_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.communication_deliveries (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  campaign_id uuid NOT NULL,
  recipient_profile_id uuid,
  student_id uuid,
  recipient_name text,
  recipient_email text,
  recipient_phone text,
  channel text NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  outbox_id uuid,
  queued_at timestamp with time zone DEFAULT now() NOT NULL,
  sent_at timestamp with time zone,
  error_message text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.communication_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  thread_id uuid NOT NULL,
  sender_profile_id uuid,
  body text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  edited_at timestamp with time zone
);

CREATE TABLE public.communication_templates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  template_name text NOT NULL,
  subject_template text,
  body_template text NOT NULL,
  category text DEFAULT 'general'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.communication_thread_participants (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  thread_id uuid NOT NULL,
  profile_id uuid NOT NULL,
  participant_role text DEFAULT 'member'::text NOT NULL,
  joined_at timestamp with time zone DEFAULT now() NOT NULL,
  last_read_at timestamp with time zone
);

CREATE TABLE public.communication_threads (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  subject text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.data_retention_policies (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data_category citext NOT NULL,
  retention_years integer,
  legal_basis text DEFAULT ''::text NOT NULL,
  disposition_action text DEFAULT 'review'::text NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.discipline_actions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  incident_id uuid NOT NULL,
  action_type text NOT NULL,
  action_notes text NOT NULL,
  starts_at timestamp with time zone,
  ends_at timestamp with time zone,
  status text DEFAULT 'active'::text NOT NULL,
  assigned_hr_staff_id uuid,
  created_by uuid,
  completed_by uuid,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.discipline_guardian_acknowledgements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  incident_id uuid NOT NULL,
  student_id uuid NOT NULL,
  guardian_user_id uuid,
  guardian_name text,
  acknowledgement_note text,
  acknowledged_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.discipline_incidents (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  incident_type text NOT NULL,
  severity text DEFAULT 'medium'::text NOT NULL,
  location text,
  summary text NOT NULL,
  details text,
  status text DEFAULT 'open'::text NOT NULL,
  guardian_visible boolean DEFAULT false NOT NULL,
  guardian_notified_at timestamp with time zone,
  reported_by uuid,
  resolved_by uuid,
  resolved_at timestamp with time zone,
  resolution_notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.emergency_academic_delegation_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  delegation_id uuid NOT NULL,
  event_type text NOT NULL,
  actor_id uuid,
  report_id uuid,
  subject_id uuid,
  event_reason text DEFAULT ''::text NOT NULL,
  event_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.emergency_academic_delegations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  delegation_type text NOT NULL,
  academic_year_id uuid NOT NULL,
  term_id uuid NOT NULL,
  class_id uuid NOT NULL,
  subject_id uuid,
  original_teacher_id uuid,
  delegate_user_id uuid NOT NULL,
  allow_score_entry boolean DEFAULT true NOT NULL,
  allow_class_report_fields boolean DEFAULT false NOT NULL,
  valid_from timestamp with time zone DEFAULT now() NOT NULL,
  valid_until timestamp with time zone NOT NULL,
  reason text NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  principal_acknowledged_at timestamp with time zone,
  principal_acknowledged_by uuid,
  principal_acknowledgement_note text DEFAULT ''::text NOT NULL,
  revoked_at timestamp with time zone,
  revoked_by uuid,
  revocation_reason text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.enrollments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  roll_number integer,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  enrollment_origin text DEFAULT 'manual'::text NOT NULL,
  promotion_source_report_id uuid,
  promotion_applied_at timestamp with time zone
);

CREATE TABLE public.finance_fee_accounts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  term_id uuid NOT NULL,
  class_id uuid NOT NULL,
  schedule_id uuid,
  term_fee_amount numeric(14,2) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_fee_allocations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  transaction_id uuid NOT NULL,
  account_id uuid NOT NULL,
  amount numeric(14,2) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_fee_group_classes (
  fee_group_id uuid NOT NULL,
  class_id uuid NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_fee_groups (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_fee_invoices (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  account_id uuid NOT NULL,
  invoice_no text NOT NULL,
  student_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  term_id uuid NOT NULL,
  class_id uuid NOT NULL,
  schedule_id uuid,
  issued_amount numeric NOT NULL,
  due_date date,
  description text DEFAULT 'Term fee'::text NOT NULL,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  created_by uuid
);

CREATE TABLE public.finance_fee_schedules (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  academic_year_id uuid NOT NULL,
  term_id uuid NOT NULL,
  class_id uuid NOT NULL,
  amount numeric(14,2) NOT NULL,
  due_date date,
  description text DEFAULT 'Term fee'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  fee_group_id uuid
);

CREATE TABLE public.finance_fee_transactions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  entry_type text NOT NULL,
  debit_amount numeric(14,2) DEFAULT 0 NOT NULL,
  credit_amount numeric(14,2) DEFAULT 0 NOT NULL,
  payment_method text,
  payment_reference text DEFAULT ''::text NOT NULL,
  receipt_no citext,
  reversal_of_id uuid,
  transaction_date date DEFAULT CURRENT_DATE NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_guardian_contact_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  guardian_key text NOT NULL,
  guardian_name text NOT NULL,
  guardian_phone text,
  guardian_email text,
  channel text NOT NULL,
  action_state text NOT NULL,
  academic_year_id uuid,
  term_id uuid,
  class_id uuid,
  child_count integer DEFAULT 0 NOT NULL,
  total_outstanding numeric(14,2) DEFAULT 0 NOT NULL,
  children jsonb DEFAULT '[]'::jsonb NOT NULL,
  message_text text,
  created_by uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_hold_overrides (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  mode text NOT NULL,
  reason text NOT NULL,
  starts_at timestamp with time zone DEFAULT now() NOT NULL,
  ends_at timestamp with time zone,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_hold_policy (
  id smallint DEFAULT 1 NOT NULL,
  enabled boolean DEFAULT false NOT NULL,
  minimum_outstanding numeric(14,2) DEFAULT 0 NOT NULL,
  grace_days integer DEFAULT 0 NOT NULL,
  block_grade_details boolean DEFAULT true NOT NULL,
  block_report_pdf boolean DEFAULT true NOT NULL,
  block_transcript boolean DEFAULT false NOT NULL,
  block_certificate boolean DEFAULT false NOT NULL,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_payroll_item_lines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  payroll_item_id uuid NOT NULL,
  loan_id uuid,
  line_type text NOT NULL,
  description text NOT NULL,
  amount numeric(14,2) NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  source_key text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.finance_payroll_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  run_id uuid NOT NULL,
  teacher_id uuid NOT NULL,
  payroll_profile_id uuid,
  basic_salary numeric(14,2) DEFAULT 0 NOT NULL,
  allowances numeric(14,2) DEFAULT 0 NOT NULL,
  ssnit_employee numeric(14,2) DEFAULT 0 NOT NULL,
  tax_amount numeric(14,2) DEFAULT 0 NOT NULL,
  loan_deductions numeric(14,2) DEFAULT 0 NOT NULL,
  other_deductions numeric(14,2) DEFAULT 0 NOT NULL,
  gross_salary numeric(14,2) DEFAULT 0 NOT NULL,
  total_deductions numeric(14,2) DEFAULT 0 NOT NULL,
  net_salary numeric(14,2) DEFAULT 0 NOT NULL,
  payment_status text DEFAULT 'unpaid'::text NOT NULL,
  paid_at timestamp with time zone,
  payment_reference text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_payroll_profiles (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  teacher_id uuid NOT NULL,
  salary_grade_id uuid,
  payroll_number citext NOT NULL,
  basic_salary_override numeric(14,2),
  ssnit_number text DEFAULT ''::text NOT NULL,
  tax_id text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  hr_staff_member_id uuid
);

CREATE TABLE public.finance_payroll_rules (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  rule_code citext NOT NULL,
  rule_type text NOT NULL,
  name text NOT NULL,
  rate numeric(12,6),
  fixed_amount numeric(14,2),
  rule_json jsonb DEFAULT '{}'::jsonb NOT NULL,
  effective_from date NOT NULL,
  effective_to date,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_payroll_runs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  payroll_year integer NOT NULL,
  payroll_month integer NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  pay_date date,
  notes text DEFAULT ''::text NOT NULL,
  created_by uuid,
  approved_by uuid,
  approved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_salary_grades (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code citext NOT NULL,
  name text NOT NULL,
  basic_salary numeric(14,2) NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.finance_teacher_loans (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  teacher_id uuid NOT NULL,
  reference_no citext NOT NULL,
  principal_amount numeric(14,2) NOT NULL,
  monthly_deduction numeric(14,2) NOT NULL,
  start_date date NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.grading_scales (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  academic_year_id uuid,
  class_id uuid,
  subject_id uuid,
  min_mark numeric(6,2) NOT NULL,
  max_mark numeric(6,2) NOT NULL,
  grade text NOT NULL,
  remark text NOT NULL,
  grade_point numeric(5,2) DEFAULT 0 NOT NULL,
  display_order integer DEFAULT 0 NOT NULL,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  interpretation text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.guardian_links (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  guardian_id uuid NOT NULL,
  student_id uuid NOT NULL,
  auth_user_id uuid,
  can_view_reports boolean DEFAULT true NOT NULL,
  can_receive_notifications boolean DEFAULT true NOT NULL,
  verified_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.headteachers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  profile_id uuid,
  staff_no citext NOT NULL,
  first_name text NOT NULL,
  middle_name text DEFAULT ''::text NOT NULL,
  last_name text NOT NULL,
  gender text DEFAULT 'Other'::text NOT NULL,
  phone text DEFAULT ''::text NOT NULL,
  email citext,
  address text DEFAULT ''::text NOT NULL,
  qualification text DEFAULT ''::text NOT NULL,
  date_appointed date,
  employment_status text DEFAULT 'active'::text NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  signature_path text DEFAULT ''::text NOT NULL,
  signature_updated_at timestamp with time zone,
  photo_url text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.health_immunizations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  vaccine_name text NOT NULL,
  dose_label text,
  administered_date date,
  next_due_date date,
  provider text,
  evidence_reference text,
  status text DEFAULT 'recorded'::text NOT NULL,
  notes text,
  recorded_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.health_medication_administrations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  visit_id uuid,
  student_id uuid NOT NULL,
  medication_name text NOT NULL,
  dosage text NOT NULL,
  route text,
  reason text,
  administered_at timestamp with time zone DEFAULT now() NOT NULL,
  consent_reference text,
  administered_by_hr_staff_id uuid,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.health_student_profiles (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  blood_group text,
  genotype text,
  allergies text,
  chronic_conditions text,
  current_medications text,
  dietary_restrictions text,
  disability_or_support_notes text,
  emergency_instructions text,
  primary_doctor_name text,
  primary_doctor_phone text,
  insurance_provider text,
  insurance_member_no text,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relation text,
  consent_notes text,
  created_by uuid,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.health_visits (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  visited_at timestamp with time zone DEFAULT now() NOT NULL,
  complaint text NOT NULL,
  observations text,
  temperature_c numeric(4,1),
  pulse_bpm integer,
  blood_pressure text,
  treatment_notes text,
  disposition text DEFAULT 'returned_to_class'::text NOT NULL,
  referral_destination text,
  guardian_notified boolean DEFAULT false NOT NULL,
  guardian_notified_at timestamp with time zone,
  status text DEFAULT 'completed'::text NOT NULL,
  attended_by_hr_staff_id uuid,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hostel_allocations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  bed_id uuid NOT NULL,
  start_date date DEFAULT CURRENT_DATE NOT NULL,
  end_date date,
  status text DEFAULT 'active'::text NOT NULL,
  boarding_type text DEFAULT 'full_boarding'::text NOT NULL,
  guardian_consent_reference text,
  allocated_by uuid,
  ended_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hostel_beds (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  room_id uuid NOT NULL,
  bed_code text NOT NULL,
  status text DEFAULT 'available'::text NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hostel_houses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  house_code text NOT NULL,
  house_name text NOT NULL,
  gender_policy text DEFAULT 'mixed'::text NOT NULL,
  capacity integer,
  house_parent_hr_staff_id uuid,
  active boolean DEFAULT true NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hostel_incidents (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  allocation_id uuid,
  student_id uuid NOT NULL,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  incident_type text NOT NULL,
  severity text DEFAULT 'medium'::text NOT NULL,
  summary text NOT NULL,
  details text,
  status text DEFAULT 'open'::text NOT NULL,
  guardian_notified boolean DEFAULT false NOT NULL,
  guardian_notified_at timestamp with time zone,
  reported_by uuid,
  resolved_by uuid,
  resolved_at timestamp with time zone,
  resolution_notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hostel_movements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  allocation_id uuid NOT NULL,
  student_id uuid NOT NULL,
  movement_type text NOT NULL,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  expected_return_at timestamp with time zone,
  actual_return_at timestamp with time zone,
  destination text,
  guardian_or_escort text,
  guardian_contact text,
  reason text,
  recorded_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hostel_rooms (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  house_id uuid NOT NULL,
  room_code text NOT NULL,
  room_name text,
  floor_label text,
  capacity integer NOT NULL,
  active boolean DEFAULT true NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hr_employment_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  staff_id uuid NOT NULL,
  event_type text NOT NULL,
  event_date date DEFAULT CURRENT_DATE NOT NULL,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hr_leave_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  staff_id uuid NOT NULL,
  leave_type text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  days numeric(8,2) NOT NULL,
  reason text,
  status text DEFAULT 'pending'::text NOT NULL,
  submitted_by uuid,
  submitted_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hr_staff_documents (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  staff_id uuid NOT NULL,
  document_type text NOT NULL,
  title text NOT NULL,
  reference_no text,
  issued_on date,
  expires_on date,
  storage_path text,
  verification_status text DEFAULT 'unverified'::text NOT NULL,
  verified_by uuid,
  verified_at timestamp with time zone,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hr_staff_members (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  profile_id uuid,
  source_type text DEFAULT 'other'::text NOT NULL,
  source_id uuid,
  staff_no text NOT NULL,
  first_name text NOT NULL,
  middle_name text,
  last_name text DEFAULT ''::text NOT NULL,
  gender text,
  date_of_birth date,
  email text,
  phone text,
  address text,
  department text,
  job_title text,
  employment_type text DEFAULT 'permanent'::text NOT NULL,
  employment_status text DEFAULT 'active'::text NOT NULL,
  date_joined date,
  date_ended date,
  qualification text,
  specialization text,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relation text,
  notes text,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.hr_staff_qualifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  staff_id uuid NOT NULL,
  qualification text NOT NULL,
  institution text,
  field_of_study text,
  awarded_on date,
  expires_on date,
  verification_status text DEFAULT 'unverified'::text NOT NULL,
  verified_by uuid,
  verified_at timestamp with time zone,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.id_card_deletion_tombstones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  card_kind text NOT NULL,
  card_number text NOT NULL,
  verification_token uuid NOT NULL,
  previous_status text NOT NULL,
  deleted_by uuid,
  deleted_at timestamp with time zone DEFAULT now() NOT NULL,
  deletion_reason text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE public.id_card_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  card_id uuid,
  student_id uuid,
  event_type text NOT NULL,
  actor_id uuid,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.id_card_settings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  template_code text DEFAULT 'modern'::text NOT NULL,
  card_title text DEFAULT 'STUDENT ID CARD'::text NOT NULL,
  validity_months integer DEFAULT 12 NOT NULL,
  show_date_of_birth boolean DEFAULT false NOT NULL,
  show_gender boolean DEFAULT false NOT NULL,
  show_guardian_phone boolean DEFAULT false NOT NULL,
  show_school_address boolean DEFAULT true NOT NULL,
  show_school_phone boolean DEFAULT true NOT NULL,
  show_school_email boolean DEFAULT true NOT NULL,
  back_message text DEFAULT 'This card remains the property of the school. If found, please return it to the school administration.'::text NOT NULL,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  show_principal_signature boolean DEFAULT true NOT NULL,
  show_principal_name boolean DEFAULT true NOT NULL,
  show_principal_title boolean DEFAULT true NOT NULL,
  staff_card_title text DEFAULT 'STAFF ID CARD'::text NOT NULL,
  staff_validity_months integer DEFAULT 24 NOT NULL
);

CREATE TABLE public.import_batches (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  import_type text NOT NULL,
  filename text DEFAULT ''::text NOT NULL,
  status text DEFAULT 'processing'::text NOT NULL,
  total_rows integer DEFAULT 0 NOT NULL,
  successful_rows integer DEFAULT 0 NOT NULL,
  failed_rows integer DEFAULT 0 NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  preview_summary jsonb DEFAULT '{}'::jsonb NOT NULL,
  validated_at timestamp with time zone,
  committed_at timestamp with time zone
);

CREATE TABLE public.import_errors (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  batch_id uuid NOT NULL,
  row_number integer NOT NULL,
  payload jsonb DEFAULT '{}'::jsonb NOT NULL,
  error_message text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_asset_assignments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  asset_id uuid NOT NULL,
  staff_id uuid NOT NULL,
  assigned_location_id uuid,
  assigned_on date DEFAULT CURRENT_DATE NOT NULL,
  due_on date,
  assignment_condition text,
  purpose text,
  assigned_by uuid,
  returned_at timestamp with time zone,
  returned_by uuid,
  return_condition text,
  return_notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_asset_maintenance (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  asset_id uuid NOT NULL,
  maintenance_type text DEFAULT 'preventive'::text NOT NULL,
  opened_on date DEFAULT CURRENT_DATE NOT NULL,
  completed_on date,
  vendor_id uuid,
  cost numeric(14,2),
  description text NOT NULL,
  outcome text,
  next_due_on date,
  status text DEFAULT 'open'::text NOT NULL,
  created_by uuid,
  completed_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_asset_writeoffs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  writeoff_no text NOT NULL,
  asset_id uuid NOT NULL,
  reason text NOT NULL,
  requested_by uuid,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_assets (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  asset_tag text NOT NULL,
  item_id uuid,
  asset_name text NOT NULL,
  category text,
  serial_number text,
  model text,
  manufacturer text,
  supplier_id uuid,
  purchase_date date,
  purchase_cost numeric(14,2),
  warranty_expires_on date,
  current_location_id uuid,
  asset_status text DEFAULT 'available'::text NOT NULL,
  asset_condition text DEFAULT 'good'::text NOT NULL,
  next_maintenance_on date,
  notes text,
  active boolean DEFAULT true NOT NULL,
  disposed_on date,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  purchase_order_line_id uuid
);

CREATE TABLE public.inventory_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_type text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  actor_id uuid,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_goods_receipt_lines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  goods_receipt_id uuid NOT NULL,
  purchase_order_line_id uuid NOT NULL,
  item_id uuid NOT NULL,
  location_id uuid,
  quantity_received numeric(14,3) NOT NULL,
  unit_cost numeric(14,2) NOT NULL,
  stock_movement_id uuid,
  asset_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_goods_receipts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  grn_no text NOT NULL,
  purchase_order_id uuid NOT NULL,
  supplier_delivery_ref text,
  received_on date DEFAULT CURRENT_DATE NOT NULL,
  notes text,
  received_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_item_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  request_no text NOT NULL,
  staff_id uuid NOT NULL,
  item_id uuid NOT NULL,
  quantity numeric(14,3) NOT NULL,
  purpose text NOT NULL,
  preferred_location_id uuid,
  status text DEFAULT 'pending'::text NOT NULL,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision_reason text,
  fulfilled_movement_id uuid,
  fulfilled_by uuid,
  fulfilled_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  item_code text NOT NULL,
  item_name text NOT NULL,
  item_type text DEFAULT 'consumable'::text NOT NULL,
  category text,
  unit_of_measure text DEFAULT 'unit'::text NOT NULL,
  description text,
  preferred_supplier_id uuid,
  reorder_level numeric(14,3) DEFAULT 0 NOT NULL,
  reorder_quantity numeric(14,3) DEFAULT 1 NOT NULL,
  estimated_unit_cost numeric(14,2),
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_locations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  location_type text DEFAULT 'store'::text NOT NULL,
  description text,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_purchase_order_lines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  purchase_order_id uuid NOT NULL,
  request_line_id uuid NOT NULL,
  item_id uuid NOT NULL,
  quantity_ordered numeric(14,3) NOT NULL,
  unit_cost numeric(14,2) NOT NULL,
  quantity_received numeric(14,3) DEFAULT 0 NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_purchase_orders (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  po_no text NOT NULL,
  request_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  order_date date DEFAULT CURRENT_DATE NOT NULL,
  expected_date date,
  status text DEFAULT 'draft'::text NOT NULL,
  notes text,
  created_by uuid,
  approved_by uuid,
  approved_at timestamp with time zone,
  decision_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_purchase_request_lines (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  request_id uuid NOT NULL,
  item_id uuid NOT NULL,
  quantity numeric(14,3) NOT NULL,
  estimated_unit_cost numeric(14,2),
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_purchase_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  request_no text NOT NULL,
  justification text NOT NULL,
  needed_by date,
  status text DEFAULT 'submitted'::text NOT NULL,
  requested_by uuid,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_settings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  singleton_key text DEFAULT 'default'::text NOT NULL,
  currency text DEFAULT 'GHS'::text NOT NULL,
  default_reorder_level numeric(14,3) DEFAULT 5 NOT NULL,
  default_reorder_quantity numeric(14,3) DEFAULT 10 NOT NULL,
  low_stock_alerts boolean DEFAULT true NOT NULL,
  asset_maintenance_alert_days integer DEFAULT 30 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_staff_access (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  staff_id uuid NOT NULL,
  profile_id uuid NOT NULL,
  access_role text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  appointed_by uuid,
  appointed_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_by uuid,
  revoked_at timestamp with time zone,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.inventory_stock_movements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  item_id uuid NOT NULL,
  location_id uuid NOT NULL,
  movement_type text NOT NULL,
  quantity_delta numeric(14,3) NOT NULL,
  unit_cost numeric(14,2),
  reference_type text,
  reference_id uuid,
  reference_no text,
  related_movement_id uuid,
  recipient_staff_id uuid,
  purpose text,
  notes text,
  posted_by uuid,
  posted_at timestamp with time zone DEFAULT now() NOT NULL,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text
);

CREATE TABLE public.inventory_suppliers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  supplier_code text NOT NULL,
  supplier_name text NOT NULL,
  contact_name text,
  phone text,
  email text,
  address text,
  tax_id text,
  payment_terms text,
  notes text,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.library_books (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  isbn text,
  title text NOT NULL,
  subtitle text,
  author text NOT NULL,
  additional_authors text,
  publisher text,
  publication_year integer,
  edition text,
  category text,
  subject text,
  language text DEFAULT 'English'::text NOT NULL,
  description text,
  cover_url text,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.library_copies (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  book_id uuid NOT NULL,
  accession_no text NOT NULL,
  barcode text,
  shelf_location text,
  acquisition_date date,
  acquisition_cost numeric(12,2),
  source text,
  condition_status text DEFAULT 'good'::text NOT NULL,
  circulation_status text DEFAULT 'available'::text NOT NULL,
  notes text,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.library_inventory_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  copy_id uuid NOT NULL,
  event_type text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  actor_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.library_loans (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  copy_id uuid NOT NULL,
  borrower_type text NOT NULL,
  borrower_student_id uuid,
  borrower_hr_staff_id uuid,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  due_date date NOT NULL,
  returned_at timestamp with time zone,
  renew_count integer DEFAULT 0 NOT NULL,
  status text DEFAULT 'issued'::text NOT NULL,
  issued_by uuid,
  returned_by uuid,
  return_condition text,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.library_reservations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  book_id uuid NOT NULL,
  borrower_type text NOT NULL,
  borrower_student_id uuid,
  borrower_hr_staff_id uuid,
  status text DEFAULT 'waiting'::text NOT NULL,
  reserved_at timestamp with time zone DEFAULT now() NOT NULL,
  ready_at timestamp with time zone,
  expires_at timestamp with time zone,
  fulfilled_loan_id uuid,
  created_by uuid,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.library_settings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_loan_days integer DEFAULT 14 NOT NULL,
  staff_loan_days integer DEFAULT 30 NOT NULL,
  student_max_loans integer DEFAULT 3 NOT NULL,
  staff_max_loans integer DEFAULT 5 NOT NULL,
  renewal_days integer DEFAULT 7 NOT NULL,
  max_renewals integer DEFAULT 1 NOT NULL,
  overdue_grace_days integer DEFAULT 0 NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.library_staff_access (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  profile_id uuid NOT NULL,
  library_role text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  appointed_by uuid,
  appointed_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.license_binding_sessions (
  license_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  origin_host text NOT NULL,
  project_ref text NOT NULL,
  installation_id uuid NOT NULL,
  verified_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone NOT NULL
);

CREATE TABLE public.license_entitlement_overrides (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  license_id uuid NOT NULL,
  feature_overrides jsonb DEFAULT '{}'::jsonb NOT NULL,
  max_students integer,
  max_teachers integer,
  max_system_admins integer,
  max_guardians integer,
  max_storage_mb integer,
  reason text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_by uuid,
  revoked_at timestamp with time zone,
  revocation_reason text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.license_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  license_id uuid,
  event_type text NOT NULL,
  actor_id uuid,
  event_reason text DEFAULT ''::text NOT NULL,
  old_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  new_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.license_feature_catalog (
  code citext NOT NULL,
  name text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  category text DEFAULT 'school'::text NOT NULL,
  default_enabled boolean DEFAULT false NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.license_plan_revisions (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  plan_id uuid NOT NULL,
  revision integer NOT NULL,
  snapshot jsonb NOT NULL,
  reason text NOT NULL,
  actor_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.license_plans (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code citext NOT NULL,
  name text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  billing_cycle text DEFAULT 'annual'::text NOT NULL,
  max_students integer,
  max_teachers integer,
  max_system_admins integer,
  feature_flags jsonb DEFAULT '{}'::jsonb NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  revision integer DEFAULT 1 NOT NULL,
  default_term_days integer DEFAULT 365 NOT NULL,
  grace_days integer DEFAULT 30 NOT NULL,
  perpetual_allowed boolean DEFAULT false NOT NULL,
  max_guardians integer,
  max_storage_mb integer,
  support_level text DEFAULT 'standard'::text NOT NULL
);

CREATE TABLE public.license_verification_logs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  license_id uuid,
  actor_id uuid,
  actor_role text DEFAULT ''::text NOT NULL,
  computed_status text NOT NULL,
  access_mode text NOT NULL,
  verification_source text DEFAULT 'bootstrap'::text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.mfa_recovery_codes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  code_hash text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone DEFAULT (now() + '365 days'::interval) NOT NULL,
  used_at timestamp with time zone,
  generation_id uuid DEFAULT gen_random_uuid() NOT NULL
);

CREATE TABLE public.notification_outbox (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  recipient_id uuid,
  recipient_email citext,
  channel text DEFAULT 'email'::text NOT NULL,
  template_key text NOT NULL,
  payload jsonb DEFAULT '{}'::jsonb NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
  processed_at timestamp with time zone,
  locked_at timestamp with time zone,
  locked_by text,
  last_error text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.notifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  recipient_id uuid NOT NULL,
  title text NOT NULL,
  body text DEFAULT ''::text NOT NULL,
  category text DEFAULT 'system'::text NOT NULL,
  entity_type text DEFAULT ''::text NOT NULL,
  entity_id uuid,
  read_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_access_locks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  lock_scope text NOT NULL,
  lock_mode text NOT NULL,
  reason text NOT NULL,
  starts_at timestamp with time zone DEFAULT now() NOT NULL,
  ends_at timestamp with time zone,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  released_by uuid,
  released_at timestamp with time zone,
  release_reason text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_audit_archives (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  archive_scope text NOT NULL,
  reason text NOT NULL,
  event_count bigint DEFAULT 0 NOT NULL,
  verification_count bigint DEFAULT 0 NOT NULL,
  cutoff_at timestamp with time zone DEFAULT now() NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_distribution_authorities (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  actor_id uuid NOT NULL,
  distributor_code text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  can_generate boolean DEFAULT true NOT NULL,
  can_revoke boolean DEFAULT true NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_package_artifacts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  package_version text NOT NULL,
  school_name text NOT NULL,
  school_slug text NOT NULL,
  tenant_code text NOT NULL,
  license_reference text NOT NULL,
  license_plan_code text NOT NULL,
  authorized_domain text DEFAULT ''::text NOT NULL,
  repository_name text NOT NULL,
  storage_path text NOT NULL,
  filename text NOT NULL,
  sha256 text NOT NULL,
  signature text NOT NULL,
  file_size bigint NOT NULL,
  status text DEFAULT 'ready'::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  generated_by uuid,
  generated_at timestamp with time zone DEFAULT now() NOT NULL,
  last_downloaded_at timestamp with time zone,
  download_count integer DEFAULT 0 NOT NULL,
  revoked_at timestamp with time zone,
  revoked_by uuid,
  revocation_reason text DEFAULT ''::text NOT NULL,
  package_id uuid,
  installation_id uuid,
  project_ref text DEFAULT ''::text NOT NULL,
  plan_revision integer DEFAULT 1 NOT NULL,
  entitlement_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
  entitlement_hash text DEFAULT ''::text NOT NULL,
  signature_algorithm text DEFAULT ''::text NOT NULL,
  signature_key_id text DEFAULT ''::text NOT NULL,
  idempotency_key text DEFAULT ''::text NOT NULL,
  request_fingerprint text DEFAULT ''::text NOT NULL,
  authority_token_hash text DEFAULT ''::text NOT NULL,
  authority_last_checked_at timestamp with time zone,
  deletion_state text DEFAULT 'none'::text NOT NULL,
  deleted_at timestamp with time zone,
  deletion_reason text DEFAULT ''::text NOT NULL,
  supersedes_artifact_id uuid,
  superseded_by_artifact_id uuid,
  superseded_at timestamp with time zone,
  supersession_reason text DEFAULT ''::text NOT NULL,
  lifecycle_action text DEFAULT 'initial'::text NOT NULL,
  renewal_sequence integer DEFAULT 0 NOT NULL
);

CREATE TABLE public.platform_package_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  event_type text NOT NULL,
  actor_id uuid,
  template_id uuid,
  artifact_id uuid,
  event_reason text DEFAULT ''::text NOT NULL,
  event_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_package_reconciliation (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  artifact_id uuid,
  storage_path text NOT NULL,
  operation text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  last_error text DEFAULT ''::text NOT NULL,
  requested_by uuid,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  completed_at timestamp with time zone
);

CREATE TABLE public.platform_package_signing_identity (
  singleton boolean DEFAULT true NOT NULL,
  key_id text NOT NULL,
  public_fingerprint text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_package_templates (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  package_version text NOT NULL,
  storage_path text NOT NULL,
  sha256 text NOT NULL,
  file_size bigint NOT NULL,
  required_files jsonb DEFAULT '[]'::jsonb NOT NULL,
  active boolean DEFAULT true NOT NULL,
  uploaded_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.privacy_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid,
  request_type text NOT NULL,
  requester_name text NOT NULL,
  requester_contact text DEFAULT ''::text NOT NULL,
  request_details text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  due_at timestamp with time zone DEFAULT (now() + '30 days'::interval) NOT NULL,
  outcome text DEFAULT ''::text NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  assigned_to uuid,
  completed_by uuid,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  full_name text DEFAULT ''::text NOT NULL,
  role app_role DEFAULT 'parent_guardian'::app_role NOT NULL,
  active boolean DEFAULT true NOT NULL,
  mfa_required boolean DEFAULT false NOT NULL,
  phone text DEFAULT ''::text NOT NULL,
  last_seen_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  must_change_password boolean DEFAULT false NOT NULL
);

CREATE TABLE public.recovery_test_runs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  backup_export_id uuid NOT NULL,
  test_type text DEFAULT 'encrypted_restore_rehearsal'::text NOT NULL,
  status text DEFAULT 'processing'::text NOT NULL,
  checked_tables integer DEFAULT 0 NOT NULL,
  checked_rows bigint DEFAULT 0 NOT NULL,
  checked_storage_objects integer DEFAULT 0 NOT NULL,
  checked_storage_bytes bigint DEFAULT 0 NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  error_message text DEFAULT ''::text NOT NULL,
  initiated_by uuid,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.report_card_templates (
  range_key text NOT NULL,
  storage_path text NOT NULL,
  original_name text NOT NULL,
  mime_type text NOT NULL,
  file_size bigint NOT NULL,
  checksum text DEFAULT ''::text NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  uploaded_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.report_correction_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  request_id uuid NOT NULL,
  event_type text NOT NULL,
  actor_id uuid DEFAULT auth.uid(),
  event_note text DEFAULT ''::text NOT NULL,
  event_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.report_correction_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  report_id uuid NOT NULL,
  requested_by uuid DEFAULT auth.uid() NOT NULL,
  reason text NOT NULL,
  requested_fields jsonb DEFAULT '[]'::jsonb NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  original_report_version integer NOT NULL,
  original_revision_id uuid,
  original_publication_id uuid,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  review_note text DEFAULT ''::text NOT NULL,
  correction_revision_id uuid,
  applied_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.report_publications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  report_id uuid NOT NULL,
  revision_id uuid,
  verification_token uuid DEFAULT gen_random_uuid() NOT NULL,
  storage_path text DEFAULT ''::text NOT NULL,
  checksum text DEFAULT ''::text NOT NULL,
  page_count integer DEFAULT 1 NOT NULL,
  revoked_at timestamp with time zone,
  revoked_by uuid,
  published_by uuid DEFAULT auth.uid(),
  published_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.report_revisions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  report_id uuid NOT NULL,
  version integer NOT NULL,
  snapshot jsonb NOT NULL,
  reason text DEFAULT ''::text NOT NULL,
  actor_id uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.report_workflow_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  report_id uuid NOT NULL,
  from_status report_status,
  to_status report_status NOT NULL,
  comment text DEFAULT ''::text NOT NULL,
  actor_id uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.school_licenses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  plan_id uuid NOT NULL,
  license_reference text NOT NULL,
  license_key_hash text DEFAULT ''::text NOT NULL,
  license_key_hint text DEFAULT ''::text NOT NULL,
  status text DEFAULT 'pending_activation'::text NOT NULL,
  issued_on date DEFAULT CURRENT_DATE NOT NULL,
  activated_at timestamp with time zone,
  expires_at timestamp with time zone,
  grace_ends_at timestamp with time zone,
  compliance_reason text DEFAULT ''::text NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  created_by uuid,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  plan_revision integer DEFAULT 1 NOT NULL,
  entitlement_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
  entitlement_payload text DEFAULT ''::text NOT NULL,
  entitlement_hash text DEFAULT ''::text NOT NULL,
  entitlement_signature text DEFAULT ''::text NOT NULL,
  signature_algorithm text DEFAULT ''::text NOT NULL,
  signature_key_id text DEFAULT ''::text NOT NULL,
  signature_status text DEFAULT 'not_required'::text NOT NULL,
  signature_verified_at timestamp with time zone,
  package_id uuid,
  installation_id uuid,
  tenant_code text DEFAULT ''::text NOT NULL,
  authorized_domains text[] DEFAULT '{}'::text[] NOT NULL,
  project_ref text DEFAULT ''::text NOT NULL,
  distributor_id uuid,
  authority_url text DEFAULT ''::text NOT NULL,
  authority_token text DEFAULT ''::text NOT NULL,
  authority_status text DEFAULT 'not_required'::text NOT NULL,
  authority_checked_at timestamp with time zone,
  authority_last_success_at timestamp with time zone
);

CREATE TABLE public.school_prospectus_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  section_id uuid NOT NULL,
  item_name text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  amount numeric(12,2),
  charge_basis text DEFAULT 'per_term'::text NOT NULL,
  quantity numeric(12,2),
  unit text DEFAULT ''::text NOT NULL,
  calculation_units numeric(12,2),
  include_in_total boolean DEFAULT true NOT NULL,
  required boolean DEFAULT true NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  display_order integer DEFAULT 100 NOT NULL,
  created_by uuid,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.school_prospectus_revisions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  prospectus_id uuid NOT NULL,
  revision_no integer NOT NULL,
  snapshot jsonb NOT NULL,
  reason text DEFAULT ''::text NOT NULL,
  published_by uuid,
  published_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.school_prospectus_sections (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  prospectus_id uuid NOT NULL,
  section_type text NOT NULL,
  title text NOT NULL,
  instructions text DEFAULT ''::text NOT NULL,
  display_order integer DEFAULT 100 NOT NULL,
  created_by uuid,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.school_prospectuses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  academic_year_id uuid NOT NULL,
  class_range text NOT NULL,
  title text DEFAULT 'School Prospectus'::text NOT NULL,
  currency_code text DEFAULT 'GHS'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  effective_date date,
  revision_no integer DEFAULT 0 NOT NULL,
  general_notes text DEFAULT ''::text NOT NULL,
  created_by uuid,
  updated_by uuid,
  published_by uuid,
  published_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.school_restore_jobs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  status text DEFAULT 'upload_pending'::text NOT NULL,
  source_filename text DEFAULT ''::text NOT NULL,
  import_path text DEFAULT ''::text NOT NULL,
  package_checksum text DEFAULT ''::text NOT NULL,
  package_size bigint DEFAULT 0 NOT NULL,
  backup_key text DEFAULT ''::text NOT NULL,
  source_schema_version text DEFAULT ''::text NOT NULL,
  source_school_name text DEFAULT ''::text NOT NULL,
  source_school_code text DEFAULT ''::text NOT NULL,
  expected_table_counts jsonb DEFAULT '{}'::jsonb NOT NULL,
  restored_table_counts jsonb DEFAULT '{}'::jsonb NOT NULL,
  expected_storage_counts jsonb DEFAULT '{}'::jsonb NOT NULL,
  restored_storage_counts jsonb DEFAULT '{}'::jsonb NOT NULL,
  auth_users_expected integer DEFAULT 0 NOT NULL,
  auth_users_reconciled integer DEFAULT 0 NOT NULL,
  pre_restore_backup_id uuid,
  initiated_by uuid,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  error_message text DEFAULT ''::text NOT NULL,
  verification_notes text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.school_restore_stage_tables (
  job_id uuid NOT NULL,
  table_name text NOT NULL,
  rows jsonb DEFAULT '[]'::jsonb NOT NULL,
  row_count integer DEFAULT 0 NOT NULL,
  staged_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.school_settings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  school_name text DEFAULT 'Your School'::text NOT NULL,
  motto text DEFAULT 'Knowledge, Character, Excellence'::text NOT NULL,
  address text DEFAULT ''::text NOT NULL,
  phone text DEFAULT ''::text NOT NULL,
  email text DEFAULT ''::text NOT NULL,
  website text DEFAULT ''::text NOT NULL,
  logo_url text DEFAULT 'assets/school-logo.png'::text NOT NULL,
  report_title text DEFAULT 'Student Terminal Report'::text NOT NULL,
  report_footer text DEFAULT 'This report is issued by the school.'::text NOT NULL,
  head_name text DEFAULT ''::text NOT NULL,
  timezone text DEFAULT 'Africa/Accra'::text NOT NULL,
  locale text DEFAULT 'en-GH'::text NOT NULL,
  report_number_prefix text DEFAULT 'SCH'::text NOT NULL,
  primary_colour text DEFAULT '#0a2f73'::text NOT NULL,
  accent_colour text DEFAULT '#f1b51c'::text NOT NULL,
  verification_base_url text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  report_body_font text DEFAULT 'Times New Roman'::text NOT NULL,
  report_body_font_size numeric(4,1) DEFAULT 11.0 NOT NULL,
  promotion_cutoff_score smallint DEFAULT 50 NOT NULL,
  backup_retention_days integer DEFAULT 7 NOT NULL,
  backup_minimum_copies integer DEFAULT 2 NOT NULL,
  user_email_domain text DEFAULT 'school.invalid'::text NOT NULL,
  certificate_completion_class_id uuid,
  certificate_footer_text text DEFAULT 'Issued under the authority of the school administration.'::text NOT NULL,
  tenant_code text DEFAULT 'SCH-000000'::text NOT NULL,
  identifier_root text DEFAULT 'SCH000000'::text NOT NULL,
  runtime_release_code text DEFAULT ''::text NOT NULL,
  runtime_release_manifest_sha256 text DEFAULT ''::text NOT NULL,
  runtime_foundation_version text DEFAULT '7.4.0-r39'::text NOT NULL,
  runtime_release_source_schema_version integer DEFAULT 1 NOT NULL,
  runtime_release_migration_count integer DEFAULT 0 NOT NULL,
  runtime_release_edge_function_count integer DEFAULT 0 NOT NULL,
  runtime_release_applied_at timestamp with time zone,
  institution_type text DEFAULT 'basic_jhs'::text NOT NULL,
  academic_period_model text DEFAULT 'term'::text NOT NULL
);

CREATE TABLE public.security_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  actor_id uuid,
  event_type text NOT NULL,
  severity text DEFAULT 'info'::text NOT NULL,
  source text DEFAULT 'application'::text NOT NULL,
  message text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  acknowledged_by uuid,
  acknowledged_at timestamp with time zone,
  resolution_note text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.security_verification_runs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  standard_name text DEFAULT 'OWASP ASVS 5.0'::text NOT NULL,
  scope text NOT NULL,
  status text NOT NULL,
  summary text DEFAULT ''::text NOT NULL,
  findings jsonb DEFAULT '[]'::jsonb NOT NULL,
  verified_by uuid DEFAULT auth.uid(),
  verified_at timestamp with time zone DEFAULT now() NOT NULL,
  next_review_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.shs_programme_subjects (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  programme_id uuid NOT NULL,
  level_id uuid,
  subject_id uuid NOT NULL,
  subject_category text DEFAULT 'elective'::text NOT NULL,
  required boolean DEFAULT true NOT NULL,
  display_order integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.staff_id_card_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  card_id uuid,
  staff_type text NOT NULL,
  staff_record_id uuid,
  event_type text NOT NULL,
  actor_id uuid,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.staff_id_cards (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  staff_type text NOT NULL,
  teacher_id uuid,
  headteacher_id uuid,
  academic_year_id uuid NOT NULL,
  card_number text NOT NULL,
  verification_token uuid DEFAULT gen_random_uuid() NOT NULL,
  revision_no integer DEFAULT 1 NOT NULL,
  supersedes_card_id uuid,
  status text DEFAULT 'active'::text NOT NULL,
  issue_date date NOT NULL,
  expires_on date NOT NULL,
  snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
  issued_by uuid,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_by uuid,
  revoked_at timestamp with time zone,
  revocation_reason text DEFAULT ''::text NOT NULL,
  replacement_reason text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.student_attendance_entries (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  register_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  attendance_status text DEFAULT 'present'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.student_guardians (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  full_name text NOT NULL,
  relationship text DEFAULT 'Guardian'::text NOT NULL,
  phone text DEFAULT ''::text NOT NULL,
  email citext,
  address text DEFAULT ''::text NOT NULL,
  is_primary boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.student_id_cards (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  enrollment_id uuid,
  academic_year_id uuid NOT NULL,
  class_id uuid NOT NULL,
  card_number text NOT NULL,
  verification_token uuid DEFAULT gen_random_uuid() NOT NULL,
  revision_no integer DEFAULT 1 NOT NULL,
  supersedes_card_id uuid,
  status text DEFAULT 'active'::text NOT NULL,
  issue_date date NOT NULL,
  expires_on date NOT NULL,
  snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
  issued_by uuid,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_by uuid,
  revoked_at timestamp with time zone,
  revocation_reason text DEFAULT ''::text NOT NULL,
  replacement_reason text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.student_lifecycle_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  event_type text NOT NULL,
  effective_date date DEFAULT CURRENT_DATE NOT NULL,
  from_class_id uuid,
  to_class_id uuid,
  destination_school text DEFAULT ''::text NOT NULL,
  reason text NOT NULL,
  reference text DEFAULT ''::text NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.student_programme_enrollments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  programme_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  level_id uuid,
  status text DEFAULT 'active'::text NOT NULL,
  started_on date,
  completed_on date,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.student_reports (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  enrollment_id uuid NOT NULL,
  term_id uuid NOT NULL,
  report_number citext,
  days_school_opened integer DEFAULT 0 NOT NULL,
  days_present integer DEFAULT 0 NOT NULL,
  attitude text DEFAULT ''::text NOT NULL,
  conduct text DEFAULT ''::text NOT NULL,
  interest text DEFAULT ''::text NOT NULL,
  teacher_comment text DEFAULT ''::text NOT NULL,
  head_comment text DEFAULT ''::text NOT NULL,
  promoted_to_class_id uuid,
  status report_status DEFAULT 'draft'::report_status NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  submitted_at timestamp with time zone,
  reviewed_at timestamp with time zone,
  approved_at timestamp with time zone,
  published_at timestamp with time zone,
  withdrawn_at timestamp with time zone,
  submitted_by uuid,
  reviewed_by uuid,
  approved_by uuid,
  published_by uuid,
  created_by uuid DEFAULT auth.uid(),
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  archived_status report_status,
  next_term_reopening_date date,
  grading_scale_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
  grading_scale_scope jsonb DEFAULT '{}'::jsonb NOT NULL,
  grading_scale_frozen_at timestamp with time zone
);

CREATE TABLE public.student_services_events (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  domain text NOT NULL,
  event_type text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  actor_id uuid,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.student_services_staff_access (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  profile_id uuid NOT NULL,
  hr_staff_id uuid NOT NULL,
  service_role text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  appointed_by uuid,
  appointed_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.students (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  admission_no citext NOT NULL,
  first_name text NOT NULL,
  middle_name text DEFAULT ''::text NOT NULL,
  last_name text NOT NULL,
  gender text NOT NULL,
  date_of_birth date,
  guardian_name text DEFAULT ''::text NOT NULL,
  guardian_phone text DEFAULT ''::text NOT NULL,
  guardian_email text DEFAULT ''::text NOT NULL,
  photo_url text DEFAULT ''::text NOT NULL,
  status student_status DEFAULT 'active'::student_status NOT NULL,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  profile_id uuid
);

CREATE TABLE public.subject_results (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  report_id uuid NOT NULL,
  subject_id uuid NOT NULL,
  scheme_id uuid,
  total_score numeric(7,2) DEFAULT 0 NOT NULL,
  grade text DEFAULT ''::text NOT NULL,
  remark text DEFAULT ''::text NOT NULL,
  grade_point numeric(5,2) DEFAULT 0 NOT NULL,
  teacher_initials text DEFAULT ''::text NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.subject_scores (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  report_id uuid NOT NULL,
  subject_id uuid NOT NULL,
  class_score numeric(7,2) DEFAULT 0 NOT NULL,
  exam_score numeric(7,2) DEFAULT 0 NOT NULL,
  total numeric(7,2) GENERATED ALWAYS AS ((class_score + exam_score)) STORED,
  grade text DEFAULT ''::text NOT NULL,
  remark text DEFAULT ''::text NOT NULL,
  grade_point numeric(5,2) DEFAULT 0 NOT NULL,
  teacher_initials text DEFAULT ''::text NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.subjects (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code citext NOT NULL,
  name citext NOT NULL,
  max_class_score numeric(6,2) DEFAULT 30 NOT NULL,
  max_exam_score numeric(6,2) DEFAULT 70 NOT NULL,
  display_order integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.system_maintenance_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  actor_id uuid,
  operation text NOT NULL,
  affected_rows integer DEFAULT 0 NOT NULL,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.system_release_state (
  singleton boolean DEFAULT true NOT NULL,
  release_version text NOT NULL,
  release_channel text DEFAULT 'production'::text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.teacher_award_categories (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  code citext NOT NULL,
  name text NOT NULL,
  default_citation text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.teachers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  profile_id uuid,
  staff_no citext NOT NULL,
  first_name text NOT NULL,
  middle_name text DEFAULT ''::text NOT NULL,
  last_name text NOT NULL,
  gender text DEFAULT 'Other'::text NOT NULL,
  phone text DEFAULT ''::text NOT NULL,
  email citext,
  address text DEFAULT ''::text NOT NULL,
  qualification text DEFAULT ''::text NOT NULL,
  specialization text DEFAULT ''::text NOT NULL,
  date_joined date,
  employment_status text DEFAULT 'active'::text NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  emis_code citext,
  date_of_birth date,
  photo_url text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.terms (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  academic_year_id uuid NOT NULL,
  name citext NOT NULL,
  sequence smallint DEFAULT 1 NOT NULL,
  start_date date,
  end_date date,
  next_term_begins date,
  is_active boolean DEFAULT false NOT NULL,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_course_offerings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  course_id uuid NOT NULL,
  academic_year_id uuid NOT NULL,
  term_id uuid NOT NULL,
  level_id uuid,
  lecturer_profile_id uuid,
  section_code text DEFAULT 'A'::text NOT NULL,
  capacity integer,
  status text DEFAULT 'open'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_course_prerequisites (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  course_id uuid NOT NULL,
  prerequisite_course_id uuid NOT NULL,
  minimum_grade_point numeric(5,2),
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_course_registrations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  programme_enrollment_id uuid,
  course_offering_id uuid NOT NULL,
  status text DEFAULT 'registered'::text NOT NULL,
  registered_at timestamp with time zone DEFAULT now() NOT NULL,
  dropped_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_course_results (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  course_registration_id uuid NOT NULL,
  continuous_assessment_score numeric(6,2),
  examination_score numeric(6,2),
  total_score numeric(6,2) NOT NULL,
  letter_grade text NOT NULL,
  grade_point numeric(5,2) NOT NULL,
  credit_hours numeric(5,2) NOT NULL,
  quality_points numeric(10,4) GENERATED ALWAYS AS ((grade_point * credit_hours)) STORED,
  passed boolean DEFAULT false NOT NULL,
  result_status text DEFAULT 'draft'::text NOT NULL,
  approved_by uuid,
  approved_at timestamp with time zone,
  published_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_courses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  department_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  credit_hours numeric(5,2) NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_degree_classifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  programme_id uuid,
  name text NOT NULL,
  minimum_cgpa numeric(5,2) NOT NULL,
  maximum_cgpa numeric(5,2) NOT NULL,
  display_order integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_grading_scale (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text DEFAULT 'Institution grading scale'::text NOT NULL,
  minimum_score numeric(5,2) NOT NULL,
  maximum_score numeric(5,2) NOT NULL,
  letter_grade text NOT NULL,
  grade_point numeric(5,2) NOT NULL,
  pass boolean DEFAULT true NOT NULL,
  display_order integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_programme_courses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  programme_id uuid NOT NULL,
  course_id uuid NOT NULL,
  level_id uuid,
  period_sequence smallint,
  course_category text DEFAULT 'core'::text NOT NULL,
  credit_hours_override numeric(5,2),
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.tertiary_programme_requirements (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  programme_id uuid NOT NULL,
  minimum_credits numeric(7,2) DEFAULT 0 NOT NULL,
  minimum_cgpa numeric(5,2) DEFAULT 0 NOT NULL,
  maximum_duration_years numeric(4,1),
  notes text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transcript_issuances (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  verification_token uuid DEFAULT gen_random_uuid() NOT NULL,
  purpose text DEFAULT 'Academic transcript'::text NOT NULL,
  snapshot jsonb NOT NULL,
  status text DEFAULT 'valid'::text NOT NULL,
  issued_by uuid DEFAULT auth.uid(),
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  revoked_by uuid,
  revoked_at timestamp with time zone,
  revocation_reason text DEFAULT ''::text NOT NULL,
  transcript_number text,
  snapshot_checksum text DEFAULT ''::text NOT NULL,
  academic_period_count integer DEFAULT 0 NOT NULL,
  latest_academic_year text DEFAULT ''::text NOT NULL,
  latest_term text DEFAULT ''::text NOT NULL,
  latest_class text DEFAULT ''::text NOT NULL,
  template_version text DEFAULT 'professional-transcript-v1'::text NOT NULL
);

CREATE TABLE public.transport_drivers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  hr_staff_id uuid NOT NULL,
  licence_no text NOT NULL,
  licence_class text,
  licence_expiry date,
  status text DEFAULT 'active'::text NOT NULL,
  notes text,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_incidents (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  trip_id uuid,
  vehicle_id uuid,
  driver_id uuid,
  student_id uuid,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  incident_type text NOT NULL,
  severity text DEFAULT 'low'::text NOT NULL,
  description text NOT NULL,
  action_taken text,
  status text DEFAULT 'open'::text NOT NULL,
  resolved_at timestamp with time zone,
  resolved_by uuid,
  resolution_notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_maintenance_records (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  vehicle_id uuid NOT NULL,
  maintenance_type text NOT NULL,
  service_date date NOT NULL,
  odometer_km numeric(12,1),
  vendor text,
  cost numeric(12,2),
  next_due_date date,
  description text NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_route_stops (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  route_id uuid NOT NULL,
  stop_id uuid NOT NULL,
  stop_order integer NOT NULL,
  planned_time time without time zone,
  active boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_routes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  route_code text NOT NULL,
  route_name text NOT NULL,
  service_type text NOT NULL,
  description text,
  default_vehicle_id uuid,
  default_driver_id uuid,
  default_attendant_hr_staff_id uuid,
  scheduled_departure time without time zone NOT NULL,
  scheduled_arrival time without time zone,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_settings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  boarding_open_minutes integer DEFAULT 30 NOT NULL,
  boarding_close_minutes integer DEFAULT 15 NOT NULL,
  maintenance_alert_days integer DEFAULT 14 NOT NULL,
  document_alert_days integer DEFAULT 30 NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_staff_access (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  profile_id uuid NOT NULL,
  hr_staff_id uuid NOT NULL,
  transport_role text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  appointed_by uuid,
  appointed_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_stops (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  stop_code text NOT NULL,
  stop_name text NOT NULL,
  address text,
  landmark text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_student_assignments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  route_id uuid NOT NULL,
  boarding_stop_id uuid,
  alighting_stop_id uuid,
  effective_from date DEFAULT CURRENT_DATE NOT NULL,
  effective_to date,
  active boolean DEFAULT true NOT NULL,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_trip_students (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  trip_id uuid NOT NULL,
  student_id uuid NOT NULL,
  assignment_id uuid,
  boarding_stop_id uuid,
  alighting_stop_id uuid,
  status text DEFAULT 'pending'::text NOT NULL,
  boarded_at timestamp with time zone,
  alighted_at timestamp with time zone,
  boarded_by uuid,
  alighted_by uuid,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_trips (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  route_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  driver_id uuid,
  attendant_hr_staff_id uuid,
  service_date date NOT NULL,
  scheduled_departure time without time zone NOT NULL,
  scheduled_arrival time without time zone,
  actual_departure timestamp with time zone,
  actual_arrival timestamp with time zone,
  status text DEFAULT 'scheduled'::text NOT NULL,
  odometer_start_km numeric(12,1),
  odometer_end_km numeric(12,1),
  cancellation_reason text,
  created_by uuid,
  started_by uuid,
  completed_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.transport_vehicles (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  fleet_no text NOT NULL,
  registration_no text NOT NULL,
  vehicle_type text DEFAULT 'bus'::text NOT NULL,
  make text,
  model text,
  manufacture_year integer,
  seating_capacity integer NOT NULL,
  ownership text DEFAULT 'school'::text NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  insurance_expiry date,
  roadworthy_expiry date,
  next_service_date date,
  odometer_km numeric(12,1),
  notes text,
  active boolean DEFAULT true NOT NULL,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.user_class_access (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  class_id uuid NOT NULL,
  subject_id uuid,
  access_level text DEFAULT 'view'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.welfare_case_notes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  case_id uuid NOT NULL,
  note_type text DEFAULT 'progress'::text NOT NULL,
  note text NOT NULL,
  confidential boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.welfare_cases (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  student_id uuid NOT NULL,
  category text NOT NULL,
  priority text DEFAULT 'normal'::text NOT NULL,
  summary text NOT NULL,
  confidential_notes text,
  status text DEFAULT 'open'::text NOT NULL,
  assigned_hr_staff_id uuid,
  guardian_contact_status text DEFAULT 'not_required'::text NOT NULL,
  guardian_contacted_at timestamp with time zone,
  external_referral text,
  opened_by uuid,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_by uuid,
  closed_at timestamp with time zone,
  closure_notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
