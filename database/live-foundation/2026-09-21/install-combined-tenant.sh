#!/usr/bin/env bash
set -euo pipefail
: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL is required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIVE="$ROOT/database/live-foundation/2026-09-21"

bash "$LIVE/install-tenant-foundation.sh"

for migration in   0001_platform_and_context.sql   0002_identity_auth.sql   0003_school_people.sql   0004_academics_reporting.sql   0005_finance_hr_admissions.sql   0006_audit_storage_security.sql   0007_rls_and_runtime_grants.sql   0008_bootstrap_and_retention.sql   0009_academic_models.sql   0010_student_services.sql   0011_finance_enterprise.sql   0012_documents_and_identity.sql   0013_operations_compliance.sql   0014_bootstrap_auth_hardening.sql   0016_mfa_login_challenges.sql
do
  psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/migrations/$migration"
done

psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/tenant-template/0020_tenant_runtime_parity.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0000_neon_compat_prelude.sql"

# The live tenant foundation is the certified reference core itself. Do not replay
# the older encoded core payload on top of the authoritative clean-room snapshot.
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
insert into app.schema_migrations(version)
values ('0027_reference_core_part_01')
on conflict do nothing;
update app.release_identity
   set schema_version='0027'
 where edition='Edusentia Enterprise Neon Edition';
SQL

psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0028_certified_compat_foundation.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0029_certified_users_access_identity.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0030_certified_academic_configuration.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0030b_certified_teacher_principal_records.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0031_certified_academic_configuration_rpc.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0032_certified_academic_calendar_context.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0033_certified_student_management_utilities.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0034_certified_student_management_hardening.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0035_certified_teacher_principal_hardening.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0036_certified_staff_runtime_guards.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0037_certified_academic_configuration_mutations.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0038_certified_teacher_principal_crud.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0039_certified_timetable_academic_alignment.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0040_certified_audit_trail_v1.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0041_certified_notification_publication_sync.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0041b_neon_notification_recipient_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0042_certified_principal_academic_history_read.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0043_certified_report_governance_prerequisites.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0043b_certified_report_assignment_scope.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0044_certified_report_workflow_privacy_integrity.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0044b_certified_report_transition_helpers.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0045_certified_report_pdf_integrity_r2.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0045b_neon_report_view_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0045c_certified_operational_schema.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0045d_certified_rpc_helper_closure.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0046_certified_reference_rpc_bulk.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0047_certified_identity_rpc_neon.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048_certified_provider_rpc_neon_r2.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048b_certified_certificate_settings_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048c_certified_backup_settings_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048d_certified_system_health_telemetry_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048e_certified_system_health_notification_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048f_certified_backup_health_metadata_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048g_certified_operational_rls_enforcement.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048h_certified_release_identity.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048i_historical_provider_bridges.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048j_notification_worker_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048k_mfa_recovery_compat.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048l_backup_worker_api.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048m_restore_worker_helpers.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048n_backup_maintenance_helpers.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0051_r2_upload_metadata_api.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0052_school_logo_tenant_context_fix.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0053_blueprint_template_path_parity.sql"

psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/tenant-template/runtime-role.sql"

test "$(psql "$TARGET_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "0020"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "neon-v1.0.0-r42"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "neon-v1.0.0-r42"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from app.schema_migrations where version='0048i_historical_provider_bridges'")" = "1"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_bootstrap_data'")" -ge "1"

echo "Combined tenant clean-room install verified."
