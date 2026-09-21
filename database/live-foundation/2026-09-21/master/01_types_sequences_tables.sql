-- Edusentia master foundation: types, sequences, tables
-- Read-only schema snapshot from the live Edusentia Supabase master.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

CREATE TYPE public.app_role AS ENUM ('admin','teacher','viewer','system_admin','headteacher','academic_admin','class_teacher','subject_teacher','records_officer','parent_guardian','principal','platform_super_admin');

CREATE TYPE public.report_status AS ENUM ('draft','submitted','class_reviewed','approved','published','returned','withdrawn');

CREATE TYPE public.student_status AS ENUM ('active','graduated','withdrawn','suspended');

CREATE SEQUENCE public.certificate_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.saas_tenant_code_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.staff_id_card_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.student_id_card_number_seq AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

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
  created_at timestamp with time zone DEFAULT now() NOT NULL
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

CREATE TABLE public.platform_edge_payload_chunks (
  release_code text NOT NULL,
  function_slug text NOT NULL,
  chunk_index smallint NOT NULL,
  payload_base64 text NOT NULL,
  source_sha256 text NOT NULL,
  payload_encoding text DEFAULT 'gzip+base64'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_health_display_state (
  singleton boolean DEFAULT true NOT NULL,
  visible_since timestamp with time zone DEFAULT '1970-01-01 00:00:00+00'::timestamp with time zone NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by uuid,
  overview_visible_since timestamp with time zone DEFAULT '1970-01-01 00:00:00+00'::timestamp with time zone NOT NULL
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

CREATE TABLE public.platform_release_catalog (
  release_version text NOT NULL,
  git_sha text DEFAULT ''::text NOT NULL,
  status text DEFAULT 'candidate'::text NOT NULL,
  master_schema_version text DEFAULT ''::text NOT NULL,
  tenant_schema_version text DEFAULT ''::text NOT NULL,
  deployed_at timestamp with time zone,
  notes text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.platform_release_gate_runs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  release_version text NOT NULL,
  ready boolean NOT NULL,
  checks jsonb DEFAULT '{}'::jsonb NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL
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

CREATE TABLE public.saas_access_recovery_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  registration_id uuid,
  recovery_type text NOT NULL,
  requester_contact_email text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  completed_at timestamp with time zone,
  resolution_notes text DEFAULT ''::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE public.saas_plan_upgrade_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tenant_id uuid NOT NULL,
  tenant_user_id uuid,
  action text NOT NULL,
  successful boolean DEFAULT false NOT NULL,
  attempted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_plan_upgrade_codes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  code_hash text NOT NULL,
  code_hint text NOT NULL,
  from_plan_code citext NOT NULL,
  to_plan_code citext NOT NULL,
  status text DEFAULT 'issued'::text NOT NULL,
  reason text DEFAULT ''::text NOT NULL,
  issued_by uuid,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  redeemed_at timestamp with time zone,
  redeemed_by_tenant_user uuid,
  activated_at timestamp with time zone,
  revoked_at timestamp with time zone,
  revoked_by uuid,
  revoke_reason text DEFAULT ''::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  authorization_type text DEFAULT 'plan_upgrade'::text NOT NULL,
  license_period_type text DEFAULT 'academic_term'::text NOT NULL,
  license_period_label text DEFAULT ''::text NOT NULL,
  license_starts_at timestamp with time zone,
  license_expires_at timestamp with time zone,
  license_grace_days integer
);

CREATE TABLE public.saas_plans (
  code citext NOT NULL,
  name text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  billing_cycle text NOT NULL,
  price_amount numeric(12,2),
  currency text DEFAULT 'USD'::text NOT NULL,
  max_students integer,
  max_teachers integer,
  max_system_admins integer,
  max_guardians integer,
  max_storage_mb integer,
  feature_flags jsonb DEFAULT '{}'::jsonb NOT NULL,
  active boolean DEFAULT true NOT NULL,
  sort_order integer DEFAULT 100 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_provisioning_jobs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  stage text DEFAULT 'queued'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  idempotency_key text NOT NULL,
  blueprint_version text DEFAULT '7.4.0-r39'::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  last_error text DEFAULT ''::text NOT NULL,
  next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_school_deletion_jobs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  registration_id uuid,
  tenant_id uuid,
  tenant_code citext,
  project_ref text DEFAULT ''::text NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  stage text DEFAULT 'queued'::text NOT NULL,
  actor_id uuid,
  reason text DEFAULT ''::text NOT NULL,
  school_fingerprint text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  last_error text DEFAULT ''::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_student_capacity_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tenant_id uuid NOT NULL,
  event_type text NOT NULL,
  previous_limit integer,
  new_limit integer,
  active_student_count integer NOT NULL,
  total_student_count integer NOT NULL,
  admissions_blocked boolean DEFAULT false NOT NULL,
  reason text DEFAULT ''::text NOT NULL,
  actor_id uuid,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_tenant_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tenant_id uuid,
  registration_id uuid,
  event_type text NOT NULL,
  actor_id uuid,
  details jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_tenant_health (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tenant_id uuid NOT NULL,
  healthy boolean NOT NULL,
  services jsonb DEFAULT '[]'::jsonb NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_tenant_release_edge_functions (
  release_code text NOT NULL,
  ordinal integer NOT NULL,
  function_slug text NOT NULL,
  verify_jwt boolean NOT NULL,
  entrypoint_path text DEFAULT 'index.ts'::text NOT NULL,
  source_text text DEFAULT ''::text NOT NULL,
  sha256 text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  bundle_base64 text DEFAULT ''::text NOT NULL,
  bundle_bytes integer DEFAULT 0 NOT NULL
);

CREATE TABLE public.saas_tenant_release_migrations (
  release_code text NOT NULL,
  ordinal integer NOT NULL,
  migration_version text NOT NULL,
  migration_name text NOT NULL,
  sql_text text NOT NULL,
  sha256 text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.saas_tenant_releases (
  release_code text NOT NULL,
  baseline_blueprint_version text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  manifest_sha256 text DEFAULT ''::text NOT NULL,
  migration_count integer DEFAULT 0 NOT NULL,
  edge_function_count integer DEFAULT 0 NOT NULL,
  source_reference text DEFAULT ''::text NOT NULL,
  notes text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  activated_at timestamp with time zone,
  capture_nonce uuid DEFAULT gen_random_uuid() NOT NULL,
  source_schema_version integer DEFAULT 1 NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE public.saas_tenants (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  registration_id uuid,
  tenant_code citext NOT NULL,
  school_name text NOT NULL,
  slug citext NOT NULL,
  admin_email citext NOT NULL,
  status text DEFAULT 'provisioning'::text NOT NULL,
  plan_code citext NOT NULL,
  license_status text DEFAULT 'pending_activation'::text NOT NULL,
  license_started_at timestamp with time zone,
  license_expires_at timestamp with time zone,
  project_ref text DEFAULT ''::text NOT NULL,
  project_url text DEFAULT ''::text NOT NULL,
  project_region text DEFAULT ''::text NOT NULL,
  publishable_key text DEFAULT ''::text NOT NULL,
  runtime_version text DEFAULT '7.4.0-r39'::text NOT NULL,
  authorized_origin text DEFAULT 'https://edusentia.app'::text NOT NULL,
  last_health_status text DEFAULT 'unknown'::text NOT NULL,
  last_health_checked_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  activated_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  login_domain citext NOT NULL,
  upgrade_authority_token_hash text DEFAULT ''::text NOT NULL,
  student_capacity_base integer,
  student_capacity_limit integer,
  student_active_count integer DEFAULT 0 NOT NULL,
  student_total_count integer DEFAULT 0 NOT NULL,
  student_capacity_status text DEFAULT 'unknown'::text NOT NULL,
  student_admissions_blocked boolean DEFAULT false NOT NULL,
  student_capacity_checked_at timestamp with time zone,
  student_capacity_updated_at timestamp with time zone,
  student_capacity_reason text DEFAULT ''::text NOT NULL,
  license_period_type text DEFAULT 'academic_year'::text NOT NULL,
  license_period_label text DEFAULT ''::text NOT NULL,
  license_grace_days integer DEFAULT 30 NOT NULL,
  license_grace_ends_at timestamp with time zone,
  license_last_renewed_at timestamp with time zone,
  license_period_locked boolean DEFAULT false NOT NULL,
  schema_migration_version text DEFAULT ''::text NOT NULL,
  release_status text DEFAULT 'unknown'::text NOT NULL,
  release_checked_at timestamp with time zone,
  latest_backup_at timestamp with time zone,
  latest_verified_backup_at timestamp with time zone,
  client_errors_24h integer DEFAULT 0 NOT NULL,
  pending_notifications integer DEFAULT 0 NOT NULL,
  health_warning_count integer DEFAULT 0 NOT NULL,
  release_manifest_sha256 text DEFAULT ''::text NOT NULL,
  release_foundation_version text DEFAULT ''::text NOT NULL,
  release_source_schema_version integer,
  institution_type text DEFAULT 'basic_jhs'::text NOT NULL
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

CREATE TABLE public.school_registrations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  school_name text NOT NULL,
  contact_name text NOT NULL,
  contact_email citext NOT NULL,
  contact_phone text DEFAULT ''::text NOT NULL,
  country text DEFAULT ''::text NOT NULL,
  requested_plan_code citext DEFAULT 'starter'::citext NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  tenant_id uuid,
  rejection_reason text DEFAULT ''::text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  initial_license_period_type text,
  initial_license_period_label text,
  initial_license_starts_at timestamp with time zone,
  initial_license_expires_at timestamp with time zone,
  initial_license_grace_days integer,
  initial_license_configured_at timestamp with time zone,
  initial_license_configured_by uuid,
  institution_type text DEFAULT 'basic_jhs'::text NOT NULL
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
  certificate_footer_text text DEFAULT 'Issued under the authority of the school administration.'::text NOT NULL
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
  updated_at timestamp with time zone DEFAULT now() NOT NULL
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
  revocation_reason text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.user_class_access (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid NOT NULL,
  class_id uuid NOT NULL,
  subject_id uuid,
  access_level text DEFAULT 'view'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
