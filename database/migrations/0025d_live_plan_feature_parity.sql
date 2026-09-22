begin;

-- Live Supabase licence-plan parity for the independent Neon Edition.
-- Source of truth verified 2026-09-22 against Edusentia SaaS Master r39
-- public.license_plans revision 6 and public.license_feature_catalog.
--
-- The Neon runtime remains independent of Supabase. These rows reproduce the
-- certified commercial entitlements inside Neon-native licensing tables.

alter table platform.license_feature_catalog
  add column if not exists category text not null default 'core',
  add column if not exists active boolean not null default true;

insert into platform.license_feature_catalog(code,name,description,default_enabled,category,active)
values
('core_records','Core records','School, student, staff, class, term, and enrolment records.',true,'core',true),
('assessment','Assessment entry','Assessment schemes, components, scores, grading, and workflow.',true,'academic',true),
('report_cards','Report cards','Generate, approve, publish, store, and verify report cards.',true,'academic',true),
('attendance','Attendance','Class registers and term attendance totals.',true,'academic',true),
('academic_history','Academic history','Lifecycle records, cumulative history, and transcript issuance.',true,'academic',true),
('certificates','Certificates','Certificate templates, batches, issuance, and verification.',true,'academic',true),
('timetable','Class Timetable','Class timetable scheduling with subject and teacher assignment, conflict protection, and teacher read-only views.',true,'academics',true),
('id_cards','Student ID Card Generator','Professional front-and-back CR80 student ID cards with QR verification, lifecycle control, and printable/downloadable output.',true,'administration',true),
('staff_id_cards','Staff ID Card Generator','Professional front-and-back CR80 staff ID cards for teachers and principals with QR verification and lifecycle control.',true,'administration',true),
('school_prospectus','School Prospectus Management','Academic-year school fees, requirements, transportation and policy prospectus management with revision history and professional PDF output.',true,'administration',true),
('uploaded_templates','Uploaded templates','Custom PDF and DOCX report-card and certificate templates.',false,'configuration',true),
('custom_branding','Custom branding','Custom identity, logos, colours, and package branding.',false,'configuration',true),
('bulk_workflow','Bulk workflows','Bulk imports, transitions, and batch operations.',false,'productivity',true),
('manual_backup','Manual backups','System Administrator initiated encrypted backups.',true,'continuity',true),
('scheduled_backup','Scheduled backups','Automated encrypted backup execution.',false,'continuity',true),
('notifications','Notifications','Queued operational and academic notifications.',false,'communication',true),
('analytics','Analytics','Performance, attendance, and completion insights.',true,'analytics',true),
('advanced_analytics','Advanced analytics','Reserved for a future separately implemented analytics module. It is not available in v7.3.0.',false,'analytics',false),
('governance','Governance','Privacy, retention, audit, security, and recovery controls.',true,'governance',true),
('priority_support','Priority support','External platform-owner support entitlement; it does not unlock a local software module.',false,'support',true),
('integrations','Integrations','Reserved for future approved external integrations. It is not available in v7.3.0.',false,'integration',false),
('finance_fees','Finance Fees','Term fee configuration, student fee obligations, payment collection, balances and receipts.',true,'finance',true),
('finance_statements','Finance Statements','Student and parent fee statements, payment history and class fee status views.',true,'finance',true),
('finance_exports','Finance Excel Exports','Filtered Finance and fee registers exported in spreadsheet-compatible format.',false,'finance',true),
('financial_holds','Financial Holds','Configurable financial-clearance restrictions on selected published academic outputs without altering grades.',false,'finance',true),
('payroll','Payroll','Salary grades, teacher payroll profiles, monthly payroll, salary payment history and payslips.',false,'payroll',true),
('payroll_statutory','Payroll Statutory Rules','Effective-dated SSNIT, tax, loan and other statutory payroll deduction rules.',false,'payroll',true)
on conflict(code) do update set
  name=excluded.name,
  description=excluded.description,
  default_enabled=excluded.default_enabled,
  category=excluded.category,
  active=excluded.active;

insert into platform.license_plans(
  code,name,active,limits,description,billing_cycle,price_amount,currency,feature_flags,sort_order
)
values
(
  'starter','Starter',true,
  '{"max_students":300,"max_teachers":30,"max_system_admins":2,"max_guardians":600,"max_storage_mb":2048}'::jsonb,
  'Core academic operations for a small school.','annual',null,'USD',
  '{"payroll":false,"id_cards":true,"analytics":true,"timetable":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"staff_id_cards":true,"custom_branding":false,"finance_exports":false,"financial_holds":false,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":false,"school_prospectus":true,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,
  10
),
(
  'professional','Professional',true,
  '{"max_students":1000,"max_teachers":100,"max_system_admins":5,"max_guardians":2000,"max_storage_mb":10240}'::jsonb,
  'Expanded capacity, automation, templates, and communication for a growing school.','annual',null,'USD',
  '{"payroll":false,"id_cards":true,"analytics":true,"timetable":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"staff_id_cards":true,"custom_branding":false,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":false,"school_prospectus":true,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,
  20
),
(
  'enterprise','Enterprise School',true,
  '{}'::jsonb,
  'Unlimited school capacity and the complete school feature set. Distribution authority is separate.','custom',null,'USD',
  '{"payroll":true,"id_cards":true,"analytics":true,"timetable":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"staff_id_cards":true,"custom_branding":true,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":true,"school_prospectus":true,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,
  30
)
on conflict(code) do update set
  name=excluded.name,
  active=excluded.active,
  limits=excluded.limits,
  description=excluded.description,
  billing_cycle=excluded.billing_cycle,
  price_amount=excluded.price_amount,
  currency=excluded.currency,
  feature_flags=excluded.feature_flags,
  sort_order=excluded.sort_order;

insert into app.schema_migrations(version)
values ('0025d_live_plan_feature_parity')
on conflict do nothing;

-- Suffix migrations extend the certified 0025 control-plane schema without
-- changing the release line expected by production deployment preflight.
update app.release_identity
set schema_version='0025'
where edition='Edusentia Enterprise Neon Edition';

commit;
