-- Edusentia Enterprise Neon Edition — certified operational schema parity.
-- Certified source: nduah385/Edusentia-Enterprise @ a181e18e0ca044db756193209b5b089cd03efb0f
-- Dependency-safe order: sequences, tables, key/check constraints, foreign keys, indexes, ACL.
-- Legacy duplicate licence-state tables are intentionally excluded.
begin;

create sequence if not exists public."certificate_number_seq" increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1 no cycle;
create sequence if not exists public."transcript_number_seq" increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1 no cycle;

create table if not exists public."backup_storage_objects"(
  "id" uuid default gen_random_uuid() not null,
  "backup_export_id" uuid not null,
  "source_bucket" text not null,
  "source_path" text not null,
  "backup_path" text not null,
  "content_type" text default 'application/octet-stream'::text not null,
  "original_size" bigint default 0 not null,
  "encrypted_size" bigint default 0 not null,
  "checksum" text default ''::text not null,
  "status" text default 'completed'::text not null,
  "error_message" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."certificate_batches"(
  "id" uuid default gen_random_uuid() not null,
  "certificate_type" text not null,
  "academic_year_id" uuid not null,
  "term_id" uuid,
  "class_id" uuid,
  "teacher_award_category_id" uuid,
  "template_id" uuid not null,
  "title" text not null,
  "custom_citation" text default ''::text not null,
  "notes" text default ''::text not null,
  "status" text default 'draft'::text not null,
  "review_note" text default ''::text not null,
  "prepared_by" uuid default auth.uid(),
  "submitted_by" uuid,
  "approved_by" uuid,
  "issued_by" uuid,
  "submitted_at" timestamp with time zone,
  "approved_at" timestamp with time zone,
  "issued_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."certificate_events"(
  "id" bigint generated always as identity not null,
  "certificate_id" uuid,
  "batch_id" uuid,
  "event_type" text not null,
  "actor_id" uuid default auth.uid(),
  "reason" text default ''::text not null,
  "details" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."certificate_templates"(
  "id" uuid default gen_random_uuid() not null,
  "certificate_type" text not null,
  "name" text not null,
  "title" text not null,
  "subtitle" text default ''::text not null,
  "statement_template" text not null,
  "footer_text" text default ''::text not null,
  "primary_colour" text default '#0a2f73'::text not null,
  "accent_colour" text default '#f1b51c'::text not null,
  "active" boolean default true not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "storage_path" text default ''::text not null,
  "original_name" text default ''::text not null,
  "mime_type" text default ''::text not null,
  "file_size" bigint default 0 not null,
  "checksum" text default ''::text not null,
  "version" integer default 1 not null,
  "uploaded_by" uuid
);

create table if not exists public."certificates"(
  "id" uuid default gen_random_uuid() not null,
  "batch_id" uuid not null,
  "recipient_kind" text not null,
  "student_id" uuid,
  "teacher_id" uuid,
  "source_report_id" uuid,
  "certificate_number" citext,
  "verification_token" uuid default gen_random_uuid() not null,
  "revision_no" integer default 1 not null,
  "supersedes_certificate_id" uuid,
  "recipient_name" text not null,
  "recipient_identifier" text default ''::text not null,
  "current_class_name" text default ''::text not null,
  "destination_class_name" text default ''::text not null,
  "academic_year_name" text not null,
  "certificate_title" text not null,
  "award_category_name" text default ''::text not null,
  "statement_text" text not null,
  "issue_date" date,
  "status" text default 'draft'::text not null,
  "snapshot" jsonb default '{}'::jsonb not null,
  "pdf_storage_path" text default ''::text not null,
  "pdf_sha256" text default ''::text not null,
  "revocation_reason" text default ''::text not null,
  "replacement_reason" text default ''::text not null,
  "approved_by" uuid,
  "issued_by" uuid,
  "revoked_by" uuid,
  "approved_at" timestamp with time zone,
  "issued_at" timestamp with time zone,
  "revoked_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."class_attendance_registers"(
  "id" uuid default gen_random_uuid() not null,
  "term_id" uuid not null,
  "class_id" uuid not null,
  "attendance_date" date not null,
  "marked_by" uuid not null,
  "notes" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."data_retention_policies"(
  "id" uuid default gen_random_uuid() not null,
  "data_category" citext not null,
  "retention_years" integer,
  "legal_basis" text default ''::text not null,
  "disposition_action" text default 'review'::text not null,
  "notes" text default ''::text not null,
  "active" boolean default true not null,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."emergency_academic_delegation_events"(
  "id" bigint generated always as identity not null,
  "delegation_id" uuid not null,
  "event_type" text not null,
  "actor_id" uuid,
  "report_id" uuid,
  "subject_id" uuid,
  "event_reason" text default ''::text not null,
  "event_data" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."id_card_deletion_tombstones"(
  "id" bigint generated always as identity not null,
  "card_kind" text not null,
  "card_number" text not null,
  "verification_token" uuid not null,
  "previous_status" text not null,
  "deleted_by" uuid,
  "deleted_at" timestamp with time zone default now() not null,
  "deletion_reason" text not null,
  "details" jsonb default '{}'::jsonb not null
);

create table if not exists public."id_card_settings"(
  "id" uuid default gen_random_uuid() not null,
  "template_code" text default 'modern'::text not null,
  "card_title" text default 'STUDENT ID CARD'::text not null,
  "validity_months" integer default 12 not null,
  "show_date_of_birth" boolean default false not null,
  "show_gender" boolean default false not null,
  "show_guardian_phone" boolean default false not null,
  "show_school_address" boolean default true not null,
  "show_school_phone" boolean default true not null,
  "show_school_email" boolean default true not null,
  "back_message" text default 'This card remains the property of the school. If found, please return it to the school administration.'::text not null,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "show_principal_signature" boolean default true not null,
  "show_principal_name" boolean default true not null,
  "show_principal_title" boolean default true not null,
  "staff_card_title" text default 'STAFF ID CARD'::text not null,
  "staff_validity_months" integer default 24 not null
);

create table if not exists public."platform_access_locks"(
  "id" uuid default gen_random_uuid() not null,
  "lock_scope" text not null,
  "lock_mode" text not null,
  "reason" text not null,
  "starts_at" timestamp with time zone default now() not null,
  "ends_at" timestamp with time zone,
  "active" boolean default true not null,
  "created_by" uuid,
  "released_by" uuid,
  "released_at" timestamp with time zone,
  "release_reason" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."platform_distribution_authorities"(
  "id" uuid default gen_random_uuid() not null,
  "actor_id" uuid not null,
  "distributor_code" text not null,
  "active" boolean default true not null,
  "can_generate" boolean default true not null,
  "can_revoke" boolean default true not null,
  "notes" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."privacy_requests"(
  "id" uuid default gen_random_uuid() not null,
  "student_id" uuid,
  "request_type" text not null,
  "requester_name" text not null,
  "requester_contact" text default ''::text not null,
  "request_details" text not null,
  "status" text default 'open'::text not null,
  "due_at" timestamp with time zone default (now() + '30 days'::interval) not null,
  "outcome" text default ''::text not null,
  "created_by" uuid default auth.uid(),
  "assigned_to" uuid,
  "completed_by" uuid,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."recovery_test_runs"(
  "id" uuid default gen_random_uuid() not null,
  "backup_export_id" uuid not null,
  "test_type" text default 'encrypted_restore_rehearsal'::text not null,
  "status" text default 'processing'::text not null,
  "checked_tables" integer default 0 not null,
  "checked_rows" bigint default 0 not null,
  "checked_storage_objects" integer default 0 not null,
  "checked_storage_bytes" bigint default 0 not null,
  "notes" text default ''::text not null,
  "error_message" text default ''::text not null,
  "initiated_by" uuid,
  "started_at" timestamp with time zone default now() not null,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."report_card_templates"(
  "range_key" text not null,
  "storage_path" text not null,
  "original_name" text not null,
  "mime_type" text not null,
  "file_size" bigint not null,
  "checksum" text default ''::text not null,
  "version" integer default 1 not null,
  "active" boolean default true not null,
  "uploaded_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."school_prospectus_items"(
  "id" uuid default gen_random_uuid() not null,
  "section_id" uuid not null,
  "item_name" text not null,
  "description" text default ''::text not null,
  "amount" numeric(12,2),
  "charge_basis" text default 'per_term'::text not null,
  "quantity" numeric(12,2),
  "unit" text default ''::text not null,
  "calculation_units" numeric(12,2),
  "include_in_total" boolean default true not null,
  "required" boolean default true not null,
  "notes" text default ''::text not null,
  "display_order" integer default 100 not null,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."school_prospectus_revisions"(
  "id" uuid default gen_random_uuid() not null,
  "prospectus_id" uuid not null,
  "revision_no" integer not null,
  "snapshot" jsonb not null,
  "reason" text default ''::text not null,
  "published_by" uuid,
  "published_at" timestamp with time zone default now() not null
);

create table if not exists public."school_prospectus_sections"(
  "id" uuid default gen_random_uuid() not null,
  "prospectus_id" uuid not null,
  "section_type" text not null,
  "title" text not null,
  "instructions" text default ''::text not null,
  "display_order" integer default 100 not null,
  "created_by" uuid,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."school_prospectuses"(
  "id" uuid default gen_random_uuid() not null,
  "academic_year_id" uuid not null,
  "class_range" text not null,
  "title" text default 'School Prospectus'::text not null,
  "currency_code" text default 'GHS'::text not null,
  "status" text default 'draft'::text not null,
  "effective_date" date,
  "revision_no" integer default 0 not null,
  "general_notes" text default ''::text not null,
  "created_by" uuid,
  "updated_by" uuid,
  "published_by" uuid,
  "published_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."school_restore_jobs"(
  "id" uuid default gen_random_uuid() not null,
  "status" text default 'upload_pending'::text not null,
  "source_filename" text default ''::text not null,
  "import_path" text default ''::text not null,
  "package_checksum" text default ''::text not null,
  "package_size" bigint default 0 not null,
  "backup_key" text default ''::text not null,
  "source_schema_version" text default ''::text not null,
  "source_school_name" text default ''::text not null,
  "source_school_code" text default ''::text not null,
  "expected_table_counts" jsonb default '{}'::jsonb not null,
  "restored_table_counts" jsonb default '{}'::jsonb not null,
  "expected_storage_counts" jsonb default '{}'::jsonb not null,
  "restored_storage_counts" jsonb default '{}'::jsonb not null,
  "auth_users_expected" integer default 0 not null,
  "auth_users_reconciled" integer default 0 not null,
  "pre_restore_backup_id" uuid,
  "initiated_by" uuid,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "error_message" text default ''::text not null,
  "verification_notes" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."security_events"(
  "id" bigint generated always as identity not null,
  "actor_id" uuid,
  "event_type" text not null,
  "severity" text default 'info'::text not null,
  "source" text default 'application'::text not null,
  "message" text not null,
  "details" jsonb default '{}'::jsonb not null,
  "status" text default 'open'::text not null,
  "acknowledged_by" uuid,
  "acknowledged_at" timestamp with time zone,
  "resolution_note" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."security_verification_runs"(
  "id" uuid default gen_random_uuid() not null,
  "standard_name" text default 'OWASP ASVS 5.0'::text not null,
  "scope" text not null,
  "status" text not null,
  "summary" text default ''::text not null,
  "findings" jsonb default '[]'::jsonb not null,
  "verified_by" uuid default auth.uid(),
  "verified_at" timestamp with time zone default now() not null,
  "next_review_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."staff_id_cards"(
  "id" uuid default gen_random_uuid() not null,
  "staff_type" text not null,
  "teacher_id" uuid,
  "headteacher_id" uuid,
  "academic_year_id" uuid not null,
  "card_number" text not null,
  "verification_token" uuid default gen_random_uuid() not null,
  "revision_no" integer default 1 not null,
  "supersedes_card_id" uuid,
  "status" text default 'active'::text not null,
  "issue_date" date not null,
  "expires_on" date not null,
  "snapshot" jsonb default '{}'::jsonb not null,
  "issued_by" uuid,
  "issued_at" timestamp with time zone default now() not null,
  "revoked_by" uuid,
  "revoked_at" timestamp with time zone,
  "revocation_reason" text default ''::text not null,
  "replacement_reason" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."student_attendance_entries"(
  "id" uuid default gen_random_uuid() not null,
  "register_id" uuid not null,
  "enrollment_id" uuid not null,
  "attendance_status" text default 'present'::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."student_id_cards"(
  "id" uuid default gen_random_uuid() not null,
  "student_id" uuid not null,
  "enrollment_id" uuid,
  "academic_year_id" uuid not null,
  "class_id" uuid not null,
  "card_number" text not null,
  "verification_token" uuid default gen_random_uuid() not null,
  "revision_no" integer default 1 not null,
  "supersedes_card_id" uuid,
  "status" text default 'active'::text not null,
  "issue_date" date not null,
  "expires_on" date not null,
  "snapshot" jsonb default '{}'::jsonb not null,
  "issued_by" uuid,
  "issued_at" timestamp with time zone default now() not null,
  "revoked_by" uuid,
  "revoked_at" timestamp with time zone,
  "revocation_reason" text default ''::text not null,
  "replacement_reason" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."student_lifecycle_events"(
  "id" uuid default gen_random_uuid() not null,
  "student_id" uuid not null,
  "event_type" text not null,
  "effective_date" date default CURRENT_DATE not null,
  "from_class_id" uuid,
  "to_class_id" uuid,
  "destination_school" text default ''::text not null,
  "reason" text not null,
  "reference" text default ''::text not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."system_maintenance_log"(
  "id" bigint generated always as identity not null,
  "actor_id" uuid,
  "operation" text not null,
  "affected_rows" integer default 0 not null,
  "details" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null
);

create table if not exists public."teacher_award_categories"(
  "id" uuid default gen_random_uuid() not null,
  "code" citext not null,
  "name" text not null,
  "default_citation" text default ''::text not null,
  "active" boolean default true not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table if not exists public."transcript_issuances"(
  "id" uuid default gen_random_uuid() not null,
  "student_id" uuid not null,
  "verification_token" uuid default gen_random_uuid() not null,
  "purpose" text default 'Academic transcript'::text not null,
  "snapshot" jsonb not null,
  "status" text default 'valid'::text not null,
  "issued_by" uuid default auth.uid(),
  "issued_at" timestamp with time zone default now() not null,
  "revoked_by" uuid,
  "revoked_at" timestamp with time zone,
  "revocation_reason" text default ''::text not null,
  "transcript_number" text,
  "snapshot_checksum" text default ''::text not null,
  "academic_period_count" integer default 0 not null,
  "latest_academic_year" text default ''::text not null,
  "latest_term" text default ''::text not null,
  "latest_class" text default ''::text not null,
  "template_version" text default 'professional-transcript-v1'::text not null
);

alter table public."backup_storage_objects" add constraint "backup_storage_objects_encrypted_size_check" CHECK (encrypted_size >= 0);
alter table public."backup_storage_objects" add constraint "backup_storage_objects_original_size_check" CHECK (original_size >= 0);
alter table public."backup_storage_objects" add constraint "backup_storage_objects_status_check" CHECK (status = ANY (ARRAY['processing'::text, 'completed'::text, 'failed'::text]));
alter table public."certificate_batches" add constraint "certificate_batches_certificate_type_check" CHECK (certificate_type = ANY (ARRAY['student_promotion'::text, 'jhs_completion'::text, 'teacher_recognition'::text]));
alter table public."certificate_batches" add constraint "certificate_batches_status_check" CHECK (status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'rejected'::text, 'issued'::text, 'cancelled'::text]));
alter table public."certificate_templates" add constraint "certificate_templates_certificate_type_check" CHECK (certificate_type = ANY (ARRAY['student_promotion'::text, 'jhs_completion'::text, 'teacher_recognition'::text]));
alter table public."certificate_templates" add constraint "certificate_templates_file_mime_chk" CHECK (mime_type = ''::text OR (mime_type = ANY (ARRAY['application/pdf'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text])));
alter table public."certificate_templates" add constraint "certificate_templates_file_path_chk" CHECK (storage_path = ''::text OR storage_path ~~ (certificate_type || '/%'::text));
alter table public."certificate_templates" add constraint "certificate_templates_file_size_chk" CHECK (storage_path = ''::text AND file_size = 0 OR storage_path <> ''::text AND file_size > 0 AND file_size <= 20971520);
alter table public."certificate_templates" add constraint "certificate_templates_version_chk" CHECK (version > 0);
alter table public."certificates" add constraint "certificate_recipient_chk" CHECK (recipient_kind = 'student'::text AND student_id IS NOT NULL AND teacher_id IS NULL OR recipient_kind = 'teacher'::text AND teacher_id IS NOT NULL AND student_id IS NULL);
alter table public."certificates" add constraint "certificates_recipient_kind_check" CHECK (recipient_kind = ANY (ARRAY['student'::text, 'teacher'::text]));
alter table public."certificates" add constraint "certificates_revision_no_check" CHECK (revision_no > 0);
alter table public."certificates" add constraint "certificates_status_check" CHECK (status = ANY (ARRAY['draft'::text, 'approved'::text, 'issued'::text, 'rejected'::text, 'revoked'::text, 'superseded'::text]));
alter table public."data_retention_policies" add constraint "data_retention_policies_disposition_action_check" CHECK (disposition_action = ANY (ARRAY['review'::text, 'archive'::text, 'anonymise'::text, 'delete'::text]));
alter table public."data_retention_policies" add constraint "data_retention_policies_retention_years_check" CHECK (retention_years IS NULL OR retention_years >= 1 AND retention_years <= 100);
alter table public."emergency_academic_delegation_events" add constraint "emergency_academic_delegation_events_event_type_check" CHECK (event_type = ANY (ARRAY['created'::text, 'principal_acknowledged'::text, 'revoked'::text, 'report_saved'::text, 'score_imported'::text]));
alter table public."id_card_deletion_tombstones" add constraint "id_card_deletion_tombstones_card_kind_check" CHECK (card_kind = ANY (ARRAY['student'::text, 'staff'::text]));
alter table public."id_card_settings" add constraint "id_card_settings_staff_validity_check" CHECK (staff_validity_months >= 1 AND staff_validity_months <= 60);
alter table public."id_card_settings" add constraint "id_card_settings_template_code_check" CHECK (template_code = ANY (ARRAY['classic'::text, 'modern'::text, 'minimal'::text]));
alter table public."id_card_settings" add constraint "id_card_settings_validity_months_check" CHECK (validity_months >= 1 AND validity_months <= 60);
alter table public."platform_access_locks" add constraint "platform_access_lock_dates_chk" CHECK (ends_at IS NULL OR ends_at > starts_at);
alter table public."platform_access_locks" add constraint "platform_access_locks_lock_mode_check" CHECK (lock_mode = ANY (ARRAY['read_only'::text, 'deny'::text]));
alter table public."platform_access_locks" add constraint "platform_access_locks_lock_scope_check" CHECK (lock_scope = ANY (ARRAY['system_admin'::text, 'school'::text, 'platform'::text]));
alter table public."privacy_requests" add constraint "privacy_requests_request_details_check" CHECK (length(btrim(request_details)) >= 10);
alter table public."privacy_requests" add constraint "privacy_requests_request_type_check" CHECK (request_type = ANY (ARRAY['access'::text, 'correction'::text, 'export'::text, 'restriction'::text, 'anonymisation'::text, 'deletion'::text, 'consent_review'::text]));
alter table public."privacy_requests" add constraint "privacy_requests_status_check" CHECK (status = ANY (ARRAY['open'::text, 'in_review'::text, 'approved'::text, 'rejected'::text, 'completed'::text, 'cancelled'::text]));
alter table public."recovery_test_runs" add constraint "recovery_test_runs_status_check" CHECK (status = ANY (ARRAY['processing'::text, 'passed'::text, 'failed'::text]));
alter table public."report_card_templates" add constraint "report_card_templates_mime_chk" CHECK (mime_type = ANY (ARRAY['application/pdf'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text]));
alter table public."report_card_templates" add constraint "report_card_templates_path_chk" CHECK (storage_path ~~ (range_key || '/%'::text));
alter table public."report_card_templates" add constraint "report_card_templates_range_chk" CHECK (range_key = ANY (ARRAY['early_years'::text, 'basic_1_6'::text, 'basic_7_9'::text]));
alter table public."report_card_templates" add constraint "report_card_templates_size_chk" CHECK (file_size > 0 AND file_size <= 20971520);
alter table public."report_card_templates" add constraint "report_card_templates_version_chk" CHECK (version > 0);
alter table public."school_prospectus_items" add constraint "school_prospectus_items_amount_check" CHECK (amount IS NULL OR amount >= 0::numeric);
alter table public."school_prospectus_items" add constraint "school_prospectus_items_calculation_units_check" CHECK (calculation_units IS NULL OR calculation_units > 0::numeric);
alter table public."school_prospectus_items" add constraint "school_prospectus_items_charge_basis_check" CHECK (charge_basis = ANY (ARRAY['free'::text, 'one_off'::text, 'per_day'::text, 'per_week'::text, 'per_month'::text, 'per_term'::text, 'per_academic_year'::text, 'per_occurrence'::text, 'optional'::text, 'parent_provides'::text, 'informational'::text]));
alter table public."school_prospectus_items" add constraint "school_prospectus_items_display_order_check" CHECK (display_order >= 0 AND display_order <= 10000);
alter table public."school_prospectus_items" add constraint "school_prospectus_items_quantity_check" CHECK (quantity IS NULL OR quantity > 0::numeric);
alter table public."school_prospectus_revisions" add constraint "school_prospectus_revisions_revision_no_check" CHECK (revision_no > 0);
alter table public."school_prospectus_sections" add constraint "school_prospectus_sections_display_order_check" CHECK (display_order >= 0 AND display_order <= 10000);
alter table public."school_prospectus_sections" add constraint "school_prospectus_sections_section_type_check" CHECK (section_type = ANY (ARRAY['main_fees'::text, 'other_items'::text, 'parent_provided'::text, 'transportation'::text, 'policies'::text, 'custom'::text]));
alter table public."school_prospectuses" add constraint "school_prospectuses_class_range_check" CHECK (class_range = ANY (ARRAY['early_years'::text, 'basic_1_6'::text, 'basic_7_9'::text]));
alter table public."school_prospectuses" add constraint "school_prospectuses_currency_code_check" CHECK (currency_code ~ '^[A-Z]{3}$'::text);
alter table public."school_prospectuses" add constraint "school_prospectuses_revision_no_check" CHECK (revision_no >= 0);
alter table public."school_prospectuses" add constraint "school_prospectuses_status_check" CHECK (status = ANY (ARRAY['draft'::text, 'published'::text, 'archived'::text]));
alter table public."school_restore_jobs" add constraint "school_restore_jobs_package_size_check" CHECK (package_size >= 0);
alter table public."school_restore_jobs" add constraint "school_restore_jobs_status_check" CHECK (status = ANY (ARRAY['upload_pending'::text, 'uploaded'::text, 'validating'::text, 'restoring'::text, 'completed'::text, 'failed'::text, 'cancelled'::text]));
alter table public."security_events" add constraint "security_events_severity_check" CHECK (severity = ANY (ARRAY['info'::text, 'warning'::text, 'high'::text, 'critical'::text]));
alter table public."security_events" add constraint "security_events_status_check" CHECK (status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'false_positive'::text]));
alter table public."security_verification_runs" add constraint "security_verification_runs_status_check" CHECK (status = ANY (ARRAY['planned'::text, 'in_progress'::text, 'passed'::text, 'passed_with_findings'::text, 'failed'::text]));
alter table public."staff_id_cards" add constraint "staff_id_cards_check" CHECK (staff_type = 'teacher'::text AND teacher_id IS NOT NULL AND headteacher_id IS NULL OR staff_type = 'principal'::text AND headteacher_id IS NOT NULL AND teacher_id IS NULL);
alter table public."staff_id_cards" add constraint "staff_id_cards_check1" CHECK (expires_on >= issue_date);
alter table public."staff_id_cards" add constraint "staff_id_cards_revision_no_check" CHECK (revision_no > 0);
alter table public."staff_id_cards" add constraint "staff_id_cards_staff_type_check" CHECK (staff_type = ANY (ARRAY['teacher'::text, 'principal'::text]));
alter table public."staff_id_cards" add constraint "staff_id_cards_status_check" CHECK (status = ANY (ARRAY['active'::text, 'revoked'::text, 'replaced'::text]));
alter table public."student_attendance_entries" add constraint "student_attendance_entries_attendance_status_check" CHECK (attendance_status = ANY (ARRAY['present'::text, 'absent'::text, 'late'::text, 'excused'::text]));
alter table public."student_id_cards" add constraint "student_id_cards_check" CHECK (expires_on >= issue_date);
alter table public."student_id_cards" add constraint "student_id_cards_revision_no_check" CHECK (revision_no > 0);
alter table public."student_id_cards" add constraint "student_id_cards_status_check" CHECK (status = ANY (ARRAY['active'::text, 'revoked'::text, 'replaced'::text]));
alter table public."student_lifecycle_events" add constraint "student_lifecycle_events_event_type_check" CHECK (event_type = ANY (ARRAY['transfer_in'::text, 'transfer_out'::text, 'withdrawn'::text, 'graduated'::text, 'inactive'::text, 'reactivated'::text, 'archived'::text]));
alter table public."student_lifecycle_events" add constraint "student_lifecycle_events_reason_check" CHECK (length(btrim(reason)) >= 5);
alter table public."transcript_issuances" add constraint "transcript_issuances_status_check" CHECK (status = ANY (ARRAY['valid'::text, 'superseded'::text, 'revoked'::text]));
alter table public."backup_storage_objects" add constraint "backup_storage_objects_pkey" PRIMARY KEY (id);
alter table public."certificate_batches" add constraint "certificate_batches_pkey" PRIMARY KEY (id);
alter table public."certificate_events" add constraint "certificate_events_pkey" PRIMARY KEY (id);
alter table public."certificate_templates" add constraint "certificate_templates_pkey" PRIMARY KEY (id);
alter table public."certificates" add constraint "certificates_pkey" PRIMARY KEY (id);
alter table public."class_attendance_registers" add constraint "class_attendance_registers_pkey" PRIMARY KEY (id);
alter table public."data_retention_policies" add constraint "data_retention_policies_pkey" PRIMARY KEY (id);
alter table public."emergency_academic_delegation_events" add constraint "emergency_academic_delegation_events_pkey" PRIMARY KEY (id);
alter table public."id_card_deletion_tombstones" add constraint "id_card_deletion_tombstones_pkey" PRIMARY KEY (id);
alter table public."id_card_settings" add constraint "id_card_settings_pkey" PRIMARY KEY (id);
alter table public."platform_access_locks" add constraint "platform_access_locks_pkey" PRIMARY KEY (id);
alter table public."platform_distribution_authorities" add constraint "platform_distribution_authorities_pkey" PRIMARY KEY (id);
alter table public."privacy_requests" add constraint "privacy_requests_pkey" PRIMARY KEY (id);
alter table public."recovery_test_runs" add constraint "recovery_test_runs_pkey" PRIMARY KEY (id);
alter table public."report_card_templates" add constraint "report_card_templates_pkey" PRIMARY KEY (range_key);
alter table public."school_prospectus_items" add constraint "school_prospectus_items_pkey" PRIMARY KEY (id);
alter table public."school_prospectus_revisions" add constraint "school_prospectus_revisions_pkey" PRIMARY KEY (id);
alter table public."school_prospectus_sections" add constraint "school_prospectus_sections_pkey" PRIMARY KEY (id);
alter table public."school_prospectuses" add constraint "school_prospectuses_pkey" PRIMARY KEY (id);
alter table public."school_restore_jobs" add constraint "school_restore_jobs_pkey" PRIMARY KEY (id);
alter table public."security_events" add constraint "security_events_pkey" PRIMARY KEY (id);
alter table public."security_verification_runs" add constraint "security_verification_runs_pkey" PRIMARY KEY (id);
alter table public."staff_id_cards" add constraint "staff_id_cards_pkey" PRIMARY KEY (id);
alter table public."student_attendance_entries" add constraint "student_attendance_entries_pkey" PRIMARY KEY (id);
alter table public."student_id_cards" add constraint "student_id_cards_pkey" PRIMARY KEY (id);
alter table public."student_lifecycle_events" add constraint "student_lifecycle_events_pkey" PRIMARY KEY (id);
alter table public."system_maintenance_log" add constraint "system_maintenance_log_pkey" PRIMARY KEY (id);
alter table public."teacher_award_categories" add constraint "teacher_award_categories_pkey" PRIMARY KEY (id);
alter table public."transcript_issuances" add constraint "transcript_issuances_pkey" PRIMARY KEY (id);
alter table public."backup_storage_objects" add constraint "backup_storage_objects_backup_export_id_source_bucket_sourc_key" UNIQUE (backup_export_id, source_bucket, source_path);
alter table public."certificates" add constraint "certificates_certificate_number_key" UNIQUE (certificate_number);
alter table public."certificates" add constraint "certificates_verification_token_key" UNIQUE (verification_token);
alter table public."class_attendance_registers" add constraint "class_attendance_registers_term_id_class_id_attendance_date_key" UNIQUE (term_id, class_id, attendance_date);
alter table public."data_retention_policies" add constraint "data_retention_policies_data_category_key" UNIQUE (data_category);
alter table public."id_card_deletion_tombstones" add constraint "id_card_deletion_tombstones_card_kind_card_number_key" UNIQUE (card_kind, card_number);
alter table public."id_card_deletion_tombstones" add constraint "id_card_deletion_tombstones_verification_token_key" UNIQUE (verification_token);
alter table public."platform_distribution_authorities" add constraint "platform_distribution_authorities_actor_id_key" UNIQUE (actor_id);
alter table public."platform_distribution_authorities" add constraint "platform_distribution_authorities_distributor_code_key" UNIQUE (distributor_code);
alter table public."report_card_templates" add constraint "report_card_templates_storage_path_key" UNIQUE (storage_path);
alter table public."school_prospectus_revisions" add constraint "school_prospectus_revisions_prospectus_id_revision_no_key" UNIQUE (prospectus_id, revision_no);
alter table public."school_prospectuses" add constraint "school_prospectuses_academic_year_id_class_range_key" UNIQUE (academic_year_id, class_range);
alter table public."staff_id_cards" add constraint "staff_id_cards_card_number_key" UNIQUE (card_number);
alter table public."staff_id_cards" add constraint "staff_id_cards_verification_token_key" UNIQUE (verification_token);
alter table public."student_attendance_entries" add constraint "student_attendance_entries_register_id_enrollment_id_key" UNIQUE (register_id, enrollment_id);
alter table public."student_id_cards" add constraint "student_id_cards_card_number_key" UNIQUE (card_number);
alter table public."student_id_cards" add constraint "student_id_cards_verification_token_key" UNIQUE (verification_token);
alter table public."transcript_issuances" add constraint "transcript_issuances_verification_token_key" UNIQUE (verification_token);

alter table public."backup_storage_objects" add constraint "backup_storage_objects_backup_export_id_fkey" FOREIGN KEY (backup_export_id) REFERENCES backup_exports(id) ON DELETE CASCADE;
alter table public."certificate_batches" add constraint "certificate_batches_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;
alter table public."certificate_batches" add constraint "certificate_batches_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificate_batches" add constraint "certificate_batches_class_id_fkey" FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;
alter table public."certificate_batches" add constraint "certificate_batches_issued_by_fkey" FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificate_batches" add constraint "certificate_batches_prepared_by_fkey" FOREIGN KEY (prepared_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificate_batches" add constraint "certificate_batches_submitted_by_fkey" FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificate_batches" add constraint "certificate_batches_teacher_award_category_id_fkey" FOREIGN KEY (teacher_award_category_id) REFERENCES teacher_award_categories(id) ON DELETE RESTRICT;
alter table public."certificate_batches" add constraint "certificate_batches_template_id_fkey" FOREIGN KEY (template_id) REFERENCES certificate_templates(id) ON DELETE RESTRICT;
alter table public."certificate_batches" add constraint "certificate_batches_term_id_fkey" FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;
alter table public."certificate_events" add constraint "certificate_events_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificate_events" add constraint "certificate_events_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES certificate_batches(id) ON DELETE RESTRICT;
alter table public."certificate_events" add constraint "certificate_events_certificate_id_fkey" FOREIGN KEY (certificate_id) REFERENCES certificates(id) ON DELETE RESTRICT;
alter table public."certificate_templates" add constraint "certificate_templates_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificate_templates" add constraint "certificate_templates_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificates" add constraint "certificates_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificates" add constraint "certificates_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES certificate_batches(id) ON DELETE RESTRICT;
alter table public."certificates" add constraint "certificates_issued_by_fkey" FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificates" add constraint "certificates_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."certificates" add constraint "certificates_source_report_id_fkey" FOREIGN KEY (source_report_id) REFERENCES student_reports(id) ON DELETE SET NULL;
alter table public."certificates" add constraint "certificates_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;
alter table public."certificates" add constraint "certificates_supersedes_certificate_id_fkey" FOREIGN KEY (supersedes_certificate_id) REFERENCES certificates(id) ON DELETE SET NULL;
alter table public."certificates" add constraint "certificates_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;
alter table public."class_attendance_registers" add constraint "class_attendance_registers_class_id_fkey" FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;
alter table public."class_attendance_registers" add constraint "class_attendance_registers_marked_by_fkey" FOREIGN KEY (marked_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table public."class_attendance_registers" add constraint "class_attendance_registers_term_id_fkey" FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE CASCADE;
alter table public."data_retention_policies" add constraint "data_retention_policies_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."emergency_academic_delegation_events" add constraint "emergency_academic_delegation_events_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."emergency_academic_delegation_events" add constraint "emergency_academic_delegation_events_delegation_id_fkey" FOREIGN KEY (delegation_id) REFERENCES emergency_academic_delegations(id) ON DELETE RESTRICT;
alter table public."emergency_academic_delegation_events" add constraint "emergency_academic_delegation_events_report_id_fkey" FOREIGN KEY (report_id) REFERENCES student_reports(id) ON DELETE SET NULL;
alter table public."emergency_academic_delegation_events" add constraint "emergency_academic_delegation_events_subject_id_fkey" FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE SET NULL;
alter table public."id_card_deletion_tombstones" add constraint "id_card_deletion_tombstones_deleted_by_fkey" FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."id_card_settings" add constraint "id_card_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."platform_access_locks" add constraint "platform_access_locks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."platform_access_locks" add constraint "platform_access_locks_released_by_fkey" FOREIGN KEY (released_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."platform_distribution_authorities" add constraint "platform_distribution_authorities_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public."privacy_requests" add constraint "privacy_requests_assigned_to_fkey" FOREIGN KEY (assigned_to) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."privacy_requests" add constraint "privacy_requests_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."privacy_requests" add constraint "privacy_requests_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."privacy_requests" add constraint "privacy_requests_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE SET NULL;
alter table public."recovery_test_runs" add constraint "recovery_test_runs_backup_export_id_fkey" FOREIGN KEY (backup_export_id) REFERENCES backup_exports(id) ON DELETE CASCADE;
alter table public."recovery_test_runs" add constraint "recovery_test_runs_initiated_by_fkey" FOREIGN KEY (initiated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."report_card_templates" add constraint "report_card_templates_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectus_items" add constraint "school_prospectus_items_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectus_items" add constraint "school_prospectus_items_section_id_fkey" FOREIGN KEY (section_id) REFERENCES school_prospectus_sections(id) ON DELETE CASCADE;
alter table public."school_prospectus_items" add constraint "school_prospectus_items_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectus_revisions" add constraint "school_prospectus_revisions_prospectus_id_fkey" FOREIGN KEY (prospectus_id) REFERENCES school_prospectuses(id) ON DELETE RESTRICT;
alter table public."school_prospectus_revisions" add constraint "school_prospectus_revisions_published_by_fkey" FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectus_sections" add constraint "school_prospectus_sections_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectus_sections" add constraint "school_prospectus_sections_prospectus_id_fkey" FOREIGN KEY (prospectus_id) REFERENCES school_prospectuses(id) ON DELETE CASCADE;
alter table public."school_prospectus_sections" add constraint "school_prospectus_sections_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectuses" add constraint "school_prospectuses_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;
alter table public."school_prospectuses" add constraint "school_prospectuses_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectuses" add constraint "school_prospectuses_published_by_fkey" FOREIGN KEY (published_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_prospectuses" add constraint "school_prospectuses_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_restore_jobs" add constraint "school_restore_jobs_initiated_by_fkey" FOREIGN KEY (initiated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."school_restore_jobs" add constraint "school_restore_jobs_pre_restore_backup_id_fkey" FOREIGN KEY (pre_restore_backup_id) REFERENCES backup_exports(id) ON DELETE SET NULL;
alter table public."security_events" add constraint "security_events_acknowledged_by_fkey" FOREIGN KEY (acknowledged_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."security_events" add constraint "security_events_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."security_verification_runs" add constraint "security_verification_runs_verified_by_fkey" FOREIGN KEY (verified_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."staff_id_cards" add constraint "staff_id_cards_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;
alter table public."staff_id_cards" add constraint "staff_id_cards_headteacher_id_fkey" FOREIGN KEY (headteacher_id) REFERENCES headteachers(id) ON DELETE RESTRICT;
alter table public."staff_id_cards" add constraint "staff_id_cards_issued_by_fkey" FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."staff_id_cards" add constraint "staff_id_cards_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."staff_id_cards" add constraint "staff_id_cards_supersedes_card_id_fkey" FOREIGN KEY (supersedes_card_id) REFERENCES staff_id_cards(id) ON DELETE SET NULL;
alter table public."staff_id_cards" add constraint "staff_id_cards_teacher_id_fkey" FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;
alter table public."student_attendance_entries" add constraint "student_attendance_entries_enrollment_id_fkey" FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE;
alter table public."student_attendance_entries" add constraint "student_attendance_entries_register_id_fkey" FOREIGN KEY (register_id) REFERENCES class_attendance_registers(id) ON DELETE CASCADE;
alter table public."student_id_cards" add constraint "student_id_cards_academic_year_id_fkey" FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;
alter table public."student_id_cards" add constraint "student_id_cards_class_id_fkey" FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;
alter table public."student_id_cards" add constraint "student_id_cards_enrollment_id_fkey" FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE SET NULL;
alter table public."student_id_cards" add constraint "student_id_cards_issued_by_fkey" FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."student_id_cards" add constraint "student_id_cards_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."student_id_cards" add constraint "student_id_cards_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;
alter table public."student_id_cards" add constraint "student_id_cards_supersedes_card_id_fkey" FOREIGN KEY (supersedes_card_id) REFERENCES student_id_cards(id) ON DELETE SET NULL;
alter table public."student_lifecycle_events" add constraint "student_lifecycle_events_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."student_lifecycle_events" add constraint "student_lifecycle_events_from_class_id_fkey" FOREIGN KEY (from_class_id) REFERENCES classes(id) ON DELETE SET NULL;
alter table public."student_lifecycle_events" add constraint "student_lifecycle_events_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
alter table public."student_lifecycle_events" add constraint "student_lifecycle_events_to_class_id_fkey" FOREIGN KEY (to_class_id) REFERENCES classes(id) ON DELETE SET NULL;
alter table public."system_maintenance_log" add constraint "system_maintenance_log_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."teacher_award_categories" add constraint "teacher_award_categories_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."transcript_issuances" add constraint "transcript_issuances_issued_by_fkey" FOREIGN KEY (issued_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."transcript_issuances" add constraint "transcript_issuances_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public."transcript_issuances" add constraint "transcript_issuances_student_id_fkey" FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;

create index if not exists backup_storage_objects_export_idx on public.backup_storage_objects USING btree (backup_export_id, source_bucket, source_path);
create index if not exists certificate_batches_class_idx on public.certificate_batches USING btree (class_id) WHERE (class_id IS NOT NULL);
create index if not exists certificate_batches_scope_idx on public.certificate_batches USING btree (academic_year_id, certificate_type, status, created_at DESC);
create index if not exists certificate_batches_template_idx on public.certificate_batches USING btree (template_id);
create index if not exists certificate_batches_term_idx on public.certificate_batches USING btree (term_id);
create index if not exists certificate_events_batch_idx on public.certificate_events USING btree (batch_id, created_at DESC);
create index if not exists certificate_events_certificate_idx on public.certificate_events USING btree (certificate_id, created_at DESC);
create unique index if not exists certificate_templates_storage_path_uidx on public.certificate_templates USING btree (storage_path) WHERE (storage_path <> ''::text);
create unique index if not exists one_active_certificate_template_type_idx on public.certificate_templates USING btree (certificate_type) WHERE active;
create index if not exists certificates_batch_idx on public.certificates USING btree (batch_id, status, recipient_name);
create index if not exists certificates_student_idx on public.certificates USING btree (student_id, created_at DESC) WHERE (student_id IS NOT NULL);
create index if not exists certificates_teacher_idx on public.certificates USING btree (teacher_id, created_at DESC) WHERE (teacher_id IS NOT NULL);
create index if not exists attendance_register_term_class_date_idx on public.class_attendance_registers USING btree (term_id, class_id, attendance_date);
create index if not exists emergency_academic_delegation_events_created_idx on public.emergency_academic_delegation_events USING btree (created_at DESC);
create index if not exists emergency_academic_delegation_events_delegation_idx on public.emergency_academic_delegation_events USING btree (delegation_id, created_at DESC);
create index if not exists emergency_academic_delegation_events_report_idx on public.emergency_academic_delegation_events USING btree (report_id, created_at DESC) WHERE (report_id IS NOT NULL);
create unique index if not exists id_card_settings_singleton_idx on public.id_card_settings USING btree ((true));
create index if not exists platform_access_locks_active_idx on public.platform_access_locks USING btree (active, starts_at DESC, ends_at);
create index if not exists school_prospectus_items_section_idx on public.school_prospectus_items USING btree (section_id, display_order, id);
create index if not exists school_prospectus_revisions_parent_idx on public.school_prospectus_revisions USING btree (prospectus_id, revision_no DESC);
create index if not exists school_prospectus_sections_parent_idx on public.school_prospectus_sections USING btree (prospectus_id, display_order, id);
create index if not exists school_prospectuses_year_status_idx on public.school_prospectuses USING btree (academic_year_id, status, class_range);
create index if not exists school_restore_jobs_created_idx on public.school_restore_jobs USING btree (created_at DESC);
create unique index if not exists school_restore_one_active_idx on public.school_restore_jobs USING btree ((true)) WHERE (status = ANY (ARRAY['validating'::text, 'restoring'::text]));
create index if not exists security_events_status_severity_idx on public.security_events USING btree (status, severity, created_at DESC);
create unique index if not exists staff_id_cards_principal_active_idx on public.staff_id_cards USING btree (headteacher_id) WHERE ((status = 'active'::text) AND (headteacher_id IS NOT NULL));
create unique index if not exists staff_id_cards_teacher_active_idx on public.staff_id_cards USING btree (teacher_id) WHERE ((status = 'active'::text) AND (teacher_id IS NOT NULL));
create index if not exists staff_id_cards_year_status_idx on public.staff_id_cards USING btree (academic_year_id, staff_type, status, issued_at DESC);
create index if not exists attendance_entry_enrollment_idx on public.student_attendance_entries USING btree (enrollment_id, register_id);
create unique index if not exists student_id_cards_one_active_year_idx on public.student_id_cards USING btree (student_id, academic_year_id) WHERE (status = 'active'::text);
create index if not exists student_id_cards_student_idx on public.student_id_cards USING btree (student_id, issued_at DESC);
create index if not exists student_id_cards_year_class_idx on public.student_id_cards USING btree (academic_year_id, class_id, status, issued_at DESC);
create unique index if not exists teacher_award_categories_code_idx on public.teacher_award_categories USING btree (lower((code)::text));
create unique index if not exists teacher_award_categories_name_idx on public.teacher_award_categories USING btree (lower(name));
create unique index if not exists transcript_issuances_transcript_number_key on public.transcript_issuances USING btree (transcript_number) WHERE (transcript_number IS NOT NULL);
create index if not exists transcript_student_issued_idx on public.transcript_issuances USING btree (student_id, issued_at DESC);

revoke all on table public."backup_storage_objects" from public;
revoke all on table public."backup_storage_objects" from edusentia_worker_runtime;
revoke all on table public."certificate_batches" from public;
revoke all on table public."certificate_batches" from edusentia_worker_runtime;
revoke all on table public."certificate_events" from public;
revoke all on table public."certificate_events" from edusentia_worker_runtime;
revoke all on table public."certificate_templates" from public;
revoke all on table public."certificate_templates" from edusentia_worker_runtime;
revoke all on table public."certificates" from public;
revoke all on table public."certificates" from edusentia_worker_runtime;
revoke all on table public."class_attendance_registers" from public;
revoke all on table public."class_attendance_registers" from edusentia_worker_runtime;
revoke all on table public."data_retention_policies" from public;
revoke all on table public."data_retention_policies" from edusentia_worker_runtime;
revoke all on table public."emergency_academic_delegation_events" from public;
revoke all on table public."emergency_academic_delegation_events" from edusentia_worker_runtime;
revoke all on table public."id_card_deletion_tombstones" from public;
revoke all on table public."id_card_deletion_tombstones" from edusentia_worker_runtime;
revoke all on table public."id_card_settings" from public;
revoke all on table public."id_card_settings" from edusentia_worker_runtime;
revoke all on table public."platform_access_locks" from public;
revoke all on table public."platform_access_locks" from edusentia_worker_runtime;
revoke all on table public."platform_distribution_authorities" from public;
revoke all on table public."platform_distribution_authorities" from edusentia_worker_runtime;
revoke all on table public."privacy_requests" from public;
revoke all on table public."privacy_requests" from edusentia_worker_runtime;
revoke all on table public."recovery_test_runs" from public;
revoke all on table public."recovery_test_runs" from edusentia_worker_runtime;
revoke all on table public."report_card_templates" from public;
revoke all on table public."report_card_templates" from edusentia_worker_runtime;
revoke all on table public."school_prospectus_items" from public;
revoke all on table public."school_prospectus_items" from edusentia_worker_runtime;
revoke all on table public."school_prospectus_revisions" from public;
revoke all on table public."school_prospectus_revisions" from edusentia_worker_runtime;
revoke all on table public."school_prospectus_sections" from public;
revoke all on table public."school_prospectus_sections" from edusentia_worker_runtime;
revoke all on table public."school_prospectuses" from public;
revoke all on table public."school_prospectuses" from edusentia_worker_runtime;
revoke all on table public."school_restore_jobs" from public;
revoke all on table public."school_restore_jobs" from edusentia_worker_runtime;
revoke all on table public."security_events" from public;
revoke all on table public."security_events" from edusentia_worker_runtime;
revoke all on table public."security_verification_runs" from public;
revoke all on table public."security_verification_runs" from edusentia_worker_runtime;
revoke all on table public."staff_id_cards" from public;
revoke all on table public."staff_id_cards" from edusentia_worker_runtime;
revoke all on table public."student_attendance_entries" from public;
revoke all on table public."student_attendance_entries" from edusentia_worker_runtime;
revoke all on table public."student_id_cards" from public;
revoke all on table public."student_id_cards" from edusentia_worker_runtime;
revoke all on table public."student_lifecycle_events" from public;
revoke all on table public."student_lifecycle_events" from edusentia_worker_runtime;
revoke all on table public."system_maintenance_log" from public;
revoke all on table public."system_maintenance_log" from edusentia_worker_runtime;
revoke all on table public."teacher_award_categories" from public;
revoke all on table public."teacher_award_categories" from edusentia_worker_runtime;
revoke all on table public."transcript_issuances" from public;
revoke all on table public."transcript_issuances" from edusentia_worker_runtime;
revoke all on sequence public."certificate_number_seq" from public;
revoke all on sequence public."certificate_number_seq" from edusentia_worker_runtime;
revoke all on sequence public."transcript_number_seq" from public;
revoke all on sequence public."transcript_number_seq" from edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0045c_certified_operational_schema') on conflict do nothing;
update app.release_identity set schema_version='0045c' where edition='Edusentia Enterprise Neon Edition';
commit;
