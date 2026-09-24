begin;

-- Commercial tiering v2 for isolated Neon tenant databases.
-- The 27-feature catalogue stays stable; only commercial plan entitlements change.

update platform.license_plans
set
  description='Essential school operations for small schools, including academics, attendance, report cards, basic finance, statements, notifications, analytics, and manual continuity.',
  feature_flags='{"payroll":false,"id_cards":false,"analytics":true,"timetable":true,"assessment":true,"attendance":true,"governance":true,"certificates":false,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":false,"manual_backup":true,"notifications":true,"staff_id_cards":false,"custom_branding":false,"finance_exports":false,"financial_holds":false,"academic_history":true,"priority_support":false,"scheduled_backup":false,"payroll_statutory":false,"school_prospectus":false,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":false}'::jsonb,
  updated_at=now()
where code='starter';

update platform.license_plans
set
  description='Expanded school operations with ID cards, certificates, prospectus management, uploaded templates, bulk workflows, scheduled backups, finance exports, financial clearance controls, and priority support.',
  feature_flags='{"payroll":false,"id_cards":true,"analytics":true,"timetable":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"staff_id_cards":true,"custom_branding":false,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":false,"school_prospectus":true,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,
  updated_at=now()
where code='professional';

update platform.license_plans
set
  description='Unlimited school capacity and the complete implemented commercial feature set, including custom branding, payroll, and statutory payroll controls. Distribution authority remains separate.',
  feature_flags='{"payroll":true,"id_cards":true,"analytics":true,"timetable":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"staff_id_cards":true,"custom_branding":true,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":true,"school_prospectus":true,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,
  updated_at=now()
where code='enterprise';

insert into app.schema_migrations(version)
values ('0068_commercial_plan_tiering')
on conflict do nothing;

commit;
