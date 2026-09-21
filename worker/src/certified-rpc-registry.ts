import type { SessionContext } from "./types";
import type { Sql } from "./db";
import { tenantTx } from "./db";

export type CertifiedRegistryArgument=Readonly<{name:string;type:string;required:boolean}>;
export type CertifiedRegistrySpec=Readonly<{args:readonly CertifiedRegistryArgument[];resultType:string;setof:boolean}>;

// Generated from the certified stable PostgreSQL function signatures at
// nduah385/Edusentia-Enterprise @ a181e18e0ca044db756193209b5b089cd03efb0f.
// Names, argument names and casts below are trusted build-time metadata, never request-provided SQL.
export const CERTIFIED_RPC_REGISTRY=Object.freeze({
  "academic_analytics": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "acknowledge_emergency_academic_delegation": {
    "args": [
      {
        "name": "target_delegation_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "note_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "archive_academic_entity": {
    "args": [
      {
        "name": "entity_type",
        "type": "text",
        "required": true
      },
      {
        "name": "target_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "archive_grading_scale": {
    "args": [
      {
        "name": "target_grade_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "archive_headteacher": {
    "args": [
      {
        "name": "target_headteacher_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "archive_school_prospectus": {
    "args": [
      {
        "name": "target_prospectus_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "archive_student": {
    "args": [
      {
        "name": "target_student_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "archive_teacher": {
    "args": [
      {
        "name": "target_teacher_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "backup_dashboard": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "bulk_generate_missing_reports": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "preview_only",
        "type": "boolean",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "bulk_import_scores": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "rows",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "filename",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "bulk_import_students": {
    "args": [
      {
        "name": "rows",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "filename",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "bulk_promote_all_classes": {
    "args": [
      {
        "name": "source_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "bulk_promote_class": {
    "args": [
      {
        "name": "source_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "source_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "bulk_transition_class_reports": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_status",
        "type": "report_status",
        "required": true
      },
      {
        "name": "comment_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "clear_section_history": {
    "args": [
      {
        "name": "scope_text",
        "type": "text",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "confirmation_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "copy_school_prospectus": {
    "args": [
      {
        "name": "target_source_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "create_certificate_batch": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "recipient_ids",
        "type": "uuid[]",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "create_certificate_replacement_draft": {
    "args": [
      {
        "name": "target_certificate_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "replacement_statement",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "create_emergency_academic_delegation": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "create_privacy_request": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "delete_audit_events": {
    "args": [
      {
        "name": "event_ids",
        "type": "bigint[]",
        "required": true
      }
    ],
    "resultType": "integer",
    "setof": false
  },
  "delete_certificate_permanently": {
    "args": [
      {
        "name": "target_certificate_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "delete_class_subject_assignment": {
    "args": [
      {
        "name": "target_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "delete_class_timetable_entry": {
    "args": [
      {
        "name": "target_entry_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "void",
    "setof": false
  },
  "delete_notifications": {
    "args": [
      {
        "name": "notification_ids",
        "type": "uuid[]",
        "required": false
      }
    ],
    "resultType": "integer",
    "setof": false
  },
  "delete_report_card_permanently": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "delete_school_prospectus": {
    "args": [
      {
        "name": "target_prospectus_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "void",
    "setof": false
  },
  "delete_school_prospectus_item": {
    "args": [
      {
        "name": "target_item_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "void",
    "setof": false
  },
  "delete_school_prospectus_section": {
    "args": [
      {
        "name": "target_section_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "void",
    "setof": false
  },
  "delete_staff_id_card_permanently": {
    "args": [
      {
        "name": "target_card_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "confirmation_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "delete_student_id_card_permanently": {
    "args": [
      {
        "name": "target_card_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "confirmation_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "delete_transcript_issuance_permanently": {
    "args": [
      {
        "name": "target_issuance_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "confirmation_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "ensure_current_user_profile": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "generate_nip_user_email": {
    "args": [
      {
        "name": "actor_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "requested_base",
        "type": "text",
        "required": true
      },
      {
        "name": "target_user_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "text",
    "setof": false
  },
  "generate_school_identifier": {
    "args": [
      {
        "name": "identifier_kind",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "text",
    "setof": false
  },
  "generate_subject_code": {
    "args": [
      {
        "name": "subject_name",
        "type": "text",
        "required": true
      },
      {
        "name": "exclude_subject_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "text",
    "setof": false
  },
  "get_academic_configuration": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_bootstrap_data": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_certificate_batch": {
    "args": [
      {
        "name": "target_batch_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_certificate_console": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_certificate_type",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_class_attendance_register": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_date",
        "type": "date",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_class_timetable_console": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_compliance_console": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_current_principal_signature": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_emergency_delegation_console": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_headteacher_record": {
    "args": [
      {
        "name": "target_headteacher_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_id_card_console": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_status",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_my_headteacher_signature": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_my_teacher_profile": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_platform_license_console": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_recovery_console": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_report_correction_console": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_report_editor": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_enrollment_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_report_grading_guide": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_enrollment_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_report_headteacher_signature": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_report_revisions": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_school_license_capacity_console": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "get_school_prospectus_console": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_staff_id_card_console": {
    "args": [
      {
        "name": "target_staff_type",
        "type": "text",
        "required": false
      },
      {
        "name": "target_status",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_student_academic_history": {
    "args": [
      {
        "name": "target_student_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_student_record_v5": {
    "args": [
      {
        "name": "target_student_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "get_teacher_record": {
    "args": [
      {
        "name": "target_teacher_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "id_card_photo_reference_count": {
    "args": [
      {
        "name": "target_student_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_photo_path",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "integer",
    "setof": false
  },
  "id_card_principal_signature_path_is_referenced": {
    "args": [
      {
        "name": "target_signature_path",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "issue_certificate_batch": {
    "args": [
      {
        "name": "target_batch_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_issue_date",
        "type": "date",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "issue_staff_id_cards": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_staff_keys",
        "type": "text[]",
        "required": true
      },
      {
        "name": "target_issue_date",
        "type": "date",
        "required": false
      },
      {
        "name": "target_expires_on",
        "type": "date",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "issue_student_id_cards": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_student_ids",
        "type": "uuid[]",
        "required": true
      },
      {
        "name": "target_issue_date",
        "type": "date",
        "required": false
      },
      {
        "name": "target_expires_on",
        "type": "date",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "issue_student_transcript": {
    "args": [
      {
        "name": "target_student_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "purpose_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "list_academic_period_controls": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "list_audit_events": {
    "args": [
      {
        "name": "target_table",
        "type": "text",
        "required": false
      },
      {
        "name": "target_record_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "page_number",
        "type": "integer",
        "required": false
      },
      {
        "name": "page_size",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "list_certificate_eligible_recipients": {
    "args": [
      {
        "name": "target_certificate_type",
        "type": "text",
        "required": true
      },
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "list_guardian_portal_accounts": {
    "args": [
      {
        "name": "search_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "list_headteachers": {
    "args": [
      {
        "name": "search_text",
        "type": "text",
        "required": false
      },
      {
        "name": "status_filter",
        "type": "text",
        "required": false
      },
      {
        "name": "archive_filter",
        "type": "text",
        "required": false
      },
      {
        "name": "page_number",
        "type": "integer",
        "required": false
      },
      {
        "name": "page_size",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "list_id_card_candidates": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "search_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "TABLE(student_id uuid, enrollment_id uuid, full_name text, admission_no text, class_id uuid, class_name text, academic_year_id uuid, academic_year_name text, photo_url text, gender text, date_of_birth date, guardian_phone text, active_card_id uuid, active_card_number text, active_card_status text)",
    "setof": true
  },
  "list_my_children_reports": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "list_notifications": {
    "args": [
      {
        "name": "page_number",
        "type": "integer",
        "required": false
      },
      {
        "name": "page_size",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "list_profiles_with_access": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "list_report_card_templates": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "list_report_cards_v6": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_status",
        "type": "report_status",
        "required": false
      },
      {
        "name": "search_text",
        "type": "text",
        "required": false
      },
      {
        "name": "archive_filter",
        "type": "text",
        "required": false
      },
      {
        "name": "page_number",
        "type": "integer",
        "required": false
      },
      {
        "name": "page_size",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "list_report_pdf_paths": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "text[]",
    "setof": false
  },
  "list_staff_id_card_candidates": {
    "args": [
      {
        "name": "target_staff_type",
        "type": "text",
        "required": false
      },
      {
        "name": "search_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "TABLE(staff_key text, staff_type text, staff_id uuid, full_name text, staff_no text, secondary_id text, role_label text, photo_url text, qualification text, active_card_id uuid, active_card_number text, active_card_status text)",
    "setof": true
  },
  "list_teachers": {
    "args": [
      {
        "name": "search_text",
        "type": "text",
        "required": false
      },
      {
        "name": "status_filter",
        "type": "text",
        "required": false
      },
      {
        "name": "archive_filter",
        "type": "text",
        "required": false
      },
      {
        "name": "page_number",
        "type": "integer",
        "required": false
      },
      {
        "name": "page_size",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "log_client_error": {
    "args": [
      {
        "name": "message_text",
        "type": "text",
        "required": true
      },
      {
        "name": "stack_text",
        "type": "text",
        "required": false
      },
      {
        "name": "context_data",
        "type": "jsonb",
        "required": false
      },
      {
        "name": "user_agent_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "bigint",
    "setof": false
  },
  "mark_backup_offsite_copy": {
    "args": [
      {
        "name": "target_backup_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_note",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "mark_notifications_read": {
    "args": [
      {
        "name": "notification_ids",
        "type": "uuid[]",
        "required": false
      }
    ],
    "resultType": "integer",
    "setof": false
  },
  "operations_dashboard": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "platform_clear_license_history": {
    "args": [
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "confirmation_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "platform_release_access_lock": {
    "args": [
      {
        "name": "target_lock_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "platform_set_access_lock": {
    "args": [
      {
        "name": "lock_scope_text",
        "type": "text",
        "required": true
      },
      {
        "name": "lock_mode_text",
        "type": "text",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "ends_at_value",
        "type": "timestamp with time zone",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "platform_set_distribution_authority": {
    "args": [
      {
        "name": "target_actor_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "active_value",
        "type": "boolean",
        "required": true
      },
      {
        "name": "can_generate_value",
        "type": "boolean",
        "required": true
      },
      {
        "name": "can_revoke_value",
        "type": "boolean",
        "required": true
      },
      {
        "name": "notes_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "platform_set_license_override": {
    "args": [
      {
        "name": "feature_overrides",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "max_students_value",
        "type": "integer",
        "required": true
      },
      {
        "name": "max_teachers_value",
        "type": "integer",
        "required": true
      },
      {
        "name": "max_system_admins_value",
        "type": "integer",
        "required": true
      },
      {
        "name": "max_guardians_value",
        "type": "integer",
        "required": true
      },
      {
        "name": "max_storage_mb_value",
        "type": "integer",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "platform_update_license": {
    "args": [
      {
        "name": "target_plan_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_status",
        "type": "text",
        "required": true
      },
      {
        "name": "issue_date",
        "type": "date",
        "required": true
      },
      {
        "name": "activation_date",
        "type": "timestamp with time zone",
        "required": false
      },
      {
        "name": "expiry_date",
        "type": "timestamp with time zone",
        "required": false
      },
      {
        "name": "grace_end_date",
        "type": "timestamp with time zone",
        "required": false
      },
      {
        "name": "license_reference_text",
        "type": "text",
        "required": false
      },
      {
        "name": "notes_text",
        "type": "text",
        "required": false
      },
      {
        "name": "compliance_reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "platform_upsert_license_plan": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "publish_school_prospectus": {
    "args": [
      {
        "name": "target_prospectus_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "queue_incomplete_report_notifications": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "integer",
    "setof": false
  },
  "record_security_event": {
    "args": [
      {
        "name": "event_type_text",
        "type": "text",
        "required": true
      },
      {
        "name": "severity_text",
        "type": "text",
        "required": true
      },
      {
        "name": "message_text",
        "type": "text",
        "required": true
      },
      {
        "name": "details_data",
        "type": "jsonb",
        "required": false
      },
      {
        "name": "source_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "bigint",
    "setof": false
  },
  "record_student_lifecycle_event": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "register_certificate_pdf": {
    "args": [
      {
        "name": "target_certificate_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_storage_path",
        "type": "text",
        "required": true
      },
      {
        "name": "target_checksum",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "register_report_pdf": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_storage_path",
        "type": "text",
        "required": true
      },
      {
        "name": "target_checksum",
        "type": "text",
        "required": false
      },
      {
        "name": "target_page_count",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "remove_certificate_template_file": {
    "args": [
      {
        "name": "target_certificate_type",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "remove_report_card_template": {
    "args": [
      {
        "name": "target_range_key",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "replace_staff_id_card": {
    "args": [
      {
        "name": "target_card_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "target_issue_date",
        "type": "date",
        "required": false
      },
      {
        "name": "target_expires_on",
        "type": "date",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "replace_student_id_card": {
    "args": [
      {
        "name": "target_card_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "target_issue_date",
        "type": "date",
        "required": false
      },
      {
        "name": "target_expires_on",
        "type": "date",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "report_position": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "report_promotion_canonical": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "report_subject_positions": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "request_report_correction": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      },
      {
        "name": "requested_fields",
        "type": "jsonb",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "reset_audit_log": {
    "args": [
      {
        "name": "confirmation_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "resolve_grading_guide": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "resolve_security_event": {
    "args": [
      {
        "name": "target_event_id",
        "type": "bigint",
        "required": true
      },
      {
        "name": "target_status",
        "type": "text",
        "required": true
      },
      {
        "name": "resolution_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "restore_headteacher": {
    "args": [
      {
        "name": "target_headteacher_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "restore_student": {
    "args": [
      {
        "name": "target_student_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "restore_teacher": {
    "args": [
      {
        "name": "target_teacher_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "review_certificate_batch": {
    "args": [
      {
        "name": "target_batch_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "decision",
        "type": "text",
        "required": true
      },
      {
        "name": "review_note_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "review_report_correction": {
    "args": [
      {
        "name": "target_request_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "decision",
        "type": "text",
        "required": true
      },
      {
        "name": "review_note_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "revoke_certificate": {
    "args": [
      {
        "name": "target_certificate_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "revoke_emergency_academic_delegation": {
    "args": [
      {
        "name": "target_delegation_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "revoke_staff_id_card": {
    "args": [
      {
        "name": "target_card_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "revoke_student_id_card": {
    "args": [
      {
        "name": "target_card_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "revoke_student_transcript": {
    "args": [
      {
        "name": "target_issuance_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "reason_text",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "run_academic_alerts": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_academic_entity": {
    "args": [
      {
        "name": "entity_type",
        "type": "text",
        "required": true
      },
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_academic_period_control": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_assessment_scheme": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_backup_policy": {
    "args": [
      {
        "name": "target_retention_days",
        "type": "integer",
        "required": true
      },
      {
        "name": "target_minimum_copies",
        "type": "integer",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_certificate_settings": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_certificate_template": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_class_attendance": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_date",
        "type": "date",
        "required": true
      },
      {
        "name": "entries",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "notes_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_class_subject_assignments_batch": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_class_timetable_entry": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_grading_scale": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_headteacher": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_id_card_settings": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_promotion_cutoff": {
    "args": [
      {
        "name": "target_score",
        "type": "integer",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_report_card": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "expected_version",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_report_card_template": {
    "args": [
      {
        "name": "target_range_key",
        "type": "text",
        "required": true
      },
      {
        "name": "target_storage_path",
        "type": "text",
        "required": true
      },
      {
        "name": "target_original_name",
        "type": "text",
        "required": true
      },
      {
        "name": "target_mime_type",
        "type": "text",
        "required": true
      },
      {
        "name": "target_file_size",
        "type": "bigint",
        "required": true
      },
      {
        "name": "target_checksum",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_report_comments": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "teacher_comment_text",
        "type": "text",
        "required": false
      },
      {
        "name": "head_comment_text",
        "type": "text",
        "required": false
      },
      {
        "name": "expected_version",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_retention_policy": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_school_prospectus": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_school_prospectus_item": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_school_prospectus_section": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_security_verification": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_student": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_teacher": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "save_teacher_award_category": {
    "args": [
      {
        "name": "payload",
        "type": "jsonb",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "school_restore_dashboard": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "search_students": {
    "args": [
      {
        "name": "search_text",
        "type": "text",
        "required": false
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_status",
        "type": "student_status",
        "required": false
      },
      {
        "name": "page_number",
        "type": "integer",
        "required": false
      },
      {
        "name": "page_size",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "search_students_v5": {
    "args": [
      {
        "name": "search_text",
        "type": "text",
        "required": false
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": false
      },
      {
        "name": "target_status",
        "type": "student_status",
        "required": false
      },
      {
        "name": "archive_filter",
        "type": "text",
        "required": false
      },
      {
        "name": "page_number",
        "type": "integer",
        "required": false
      },
      {
        "name": "page_size",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "set_active_period": {
    "args": [
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "set_headteacher_photo": {
    "args": [
      {
        "name": "target_headteacher_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_photo_url",
        "type": "text",
        "required": true
      },
      {
        "name": "expected_updated_at",
        "type": "timestamp with time zone",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "set_my_headteacher_signature": {
    "args": [
      {
        "name": "target_signature_path",
        "type": "text",
        "required": true
      },
      {
        "name": "expected_updated_at",
        "type": "timestamp with time zone",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "set_school_logo_reference": {
    "args": [
      {
        "name": "target_logo_url",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "set_student_photo": {
    "args": [
      {
        "name": "target_student_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_photo_url",
        "type": "text",
        "required": true
      },
      {
        "name": "expected_updated_at",
        "type": "timestamp with time zone",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "set_teacher_photo": {
    "args": [
      {
        "name": "target_teacher_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_photo_url",
        "type": "text",
        "required": true
      },
      {
        "name": "expected_updated_at",
        "type": "timestamp with time zone",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "staff_id_card_photo_path_is_referenced": {
    "args": [
      {
        "name": "target_staff_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_photo_path",
        "type": "text",
        "required": true
      }
    ],
    "resultType": "boolean",
    "setof": false
  },
  "submit_certificate_batch": {
    "args": [
      {
        "name": "target_batch_id",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "system_health": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "transition_report_status": {
    "args": [
      {
        "name": "target_report_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_status",
        "type": "report_status",
        "required": true
      },
      {
        "name": "comment_text",
        "type": "text",
        "required": false
      },
      {
        "name": "expected_version",
        "type": "integer",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "update_privacy_request": {
    "args": [
      {
        "name": "target_request_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_status",
        "type": "text",
        "required": true
      },
      {
        "name": "outcome_text",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "validate_operational_readiness": {
    "args": [],
    "resultType": "jsonb",
    "setof": false
  },
  "validate_score_import": {
    "args": [
      {
        "name": "target_term_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "rows",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "filename",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "validate_student_import": {
    "args": [
      {
        "name": "rows",
        "type": "jsonb",
        "required": true
      },
      {
        "name": "target_academic_year_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "target_class_id",
        "type": "uuid",
        "required": true
      },
      {
        "name": "filename",
        "type": "text",
        "required": false
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "verify_certificate": {
    "args": [
      {
        "name": "token",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "verify_report": {
    "args": [
      {
        "name": "token",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "verify_staff_id_card": {
    "args": [
      {
        "name": "token",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "verify_student_id_card": {
    "args": [
      {
        "name": "token",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  },
  "verify_transcript": {
    "args": [
      {
        "name": "token",
        "type": "uuid",
        "required": true
      }
    ],
    "resultType": "jsonb",
    "setof": false
  }
}) as Readonly<Record<string,CertifiedRegistrySpec>>;
export const CERTIFIED_RPC_REGISTRY_NAMES=Object.freeze(Object.keys(CERTIFIED_RPC_REGISTRY).sort());

type Args=Record<string,unknown>;
function invalid(message:string):never{throw Object.assign(new Error(message),{code:"invalid_rpc_arguments",status:422});}
function quoteIdent(value:string){return '"'+value.replaceAll('"','""')+'"';}
function scalarText(value:unknown,name:string,max=20000){
  if(typeof value!=="string"||value.length>max)invalid(name+" is invalid");
  return value;
}
function normalizeValue(value:unknown,type:string,name:string){
  if(value===null)return null;
  switch(type){
    case "uuid":{
      const v=scalarText(value,name,64);
      if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v))invalid(name+" must be a UUID");
      return v;
    }
    case "integer":{
      const v=Number(value);if(!Number.isInteger(v)||v<-2147483648||v>2147483647)invalid(name+" is invalid");return v;
    }
    case "bigint":{
      if((typeof value!=="number"||!Number.isSafeInteger(value))&&(typeof value!=="string"||!/^[-+]?\d+$/.test(value)))invalid(name+" is invalid");
      return String(value);
    }
    case "boolean":
      if(typeof value!=="boolean")invalid(name+" must be Boolean");return value;
    case "jsonb":
      if(typeof value!=="object"||value===null)invalid(name+" must be JSON");return JSON.stringify(value);
    case "date":{
      const v=scalarText(value,name,32);if(!/^\d{4}-\d{2}-\d{2}$/.test(v)||Number.isNaN(Date.parse(v+"T00:00:00Z")))invalid(name+" is invalid");return v;
    }
    case "timestamp with time zone":{
      const v=scalarText(value,name,80);if(Number.isNaN(Date.parse(v)))invalid(name+" is invalid");return v;
    }
    case "uuid[]":{
      if(!Array.isArray(value)||value.length>1000)invalid(name+" is invalid");
      const vals=value.map((x,i)=>normalizeValue(x,"uuid",name+"["+i+"]"));return "{"+vals.join(",")+"}";
    }
    case "text[]":{
      if(!Array.isArray(value)||value.length>1000)invalid(name+" is invalid");
      return value.map((x,i)=>scalarText(x,name+"["+i+"]",5000));
    }
    case "bigint[]":{
      if(!Array.isArray(value)||value.length>1000)invalid(name+" is invalid");
      return "{"+value.map((x,i)=>normalizeValue(x,"bigint",name+"["+i+"]")).join(",")+"}";
    }
    case "text": return scalarText(value,name);
    default:{
      // Remaining certified input types are PostgreSQL enums. Accept only compact text and let the fixed cast enforce membership.
      const v=scalarText(value,name,128);
      if(!/^[a-zA-Z0-9_ -]+$/.test(v))invalid(name+" is invalid");
      return v;
    }
  }
}
export function isRegistryCertifiedRpc(operation:string){return Object.prototype.hasOwnProperty.call(CERTIFIED_RPC_REGISTRY,operation);}
export async function invokeRegistryCertifiedRpc(sql:Sql,ctx:SessionContext,operation:string,argsInput:unknown){
  const spec=CERTIFIED_RPC_REGISTRY[operation];if(!spec)throw Object.assign(new Error("This certified operation is not exposed by the Neon API"),{code:"certified_rpc_not_allowed",status:404});
  if(argsInput==null)argsInput={};
  if(typeof argsInput!=="object"||Array.isArray(argsInput))invalid("Certified operation arguments must be an object");
  const args=argsInput as Args;
  const allowed=new Set(spec.args.map(a=>a.name));
  for(const key of Object.keys(args))if(!allowed.has(key))invalid("Unknown certified operation argument: "+key);
  const supplied:CertifiedRegistryArgument[]=[];const values:unknown[]=[];
  for(const arg of spec.args){
    const present=Object.prototype.hasOwnProperty.call(args,arg.name)&&args[arg.name]!==undefined;
    if(!present){if(arg.required)invalid(arg.name+" is required");continue;}
    supplied.push(arg);values.push(normalizeValue(args[arg.name],arg.type,arg.name));
  }
  const fn=quoteIdent(operation);
  const callArgs=supplied.map((arg,index)=>quoteIdent(arg.name)+" => $"+(index+1)+"::"+arg.type).join(",");
  const text=spec.setof
    ?"select to_jsonb(q) as result from public."+fn+"("+callArgs+") q"
    :"select public."+fn+"("+callArgs+") as result";
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[(txn as any).query(text,values)]);
  if(spec.setof)return (rows as any[]).map(row=>(row as any).result);
  return (rows[0] as any)?.result??null;
}
