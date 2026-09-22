-- Edusentia Neon operational parity: Finance / Accounts / Payroll foundation
-- Generated from the live Edusentia reference tenant catalog and RPC definitions.
-- This is a PostgreSQL compatibility layer only; it introduces no Supabase runtime dependency.
begin;

create sequence if not exists public.finance_invoice_seq;
create sequence if not exists public.finance_payroll_no_seq;
create sequence if not exists public.finance_receipt_seq;
create sequence if not exists public.accounts_office_staff_no_seq;

create table if not exists public.accounts_office_staff (
  id uuid default gen_random_uuid() not null,
  profile_id uuid,
  staff_no citext not null,
  full_name text not null,
  phone text default ''::text not null,
  email citext,
  contact_address text default ''::text not null,
  job_title text default 'Accounts Office Staff'::text not null,
  finance_role text default 'accounts_officer'::text not null,
  active boolean default true not null,
  deleted_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.finance_fee_accounts (
  id uuid default gen_random_uuid() not null,
  student_id uuid not null,
  enrollment_id uuid not null,
  academic_year_id uuid not null,
  term_id uuid not null,
  class_id uuid not null,
  schedule_id uuid,
  term_fee_amount numeric(14,2) not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.finance_fee_allocations (
  id uuid default gen_random_uuid() not null,
  transaction_id uuid not null,
  account_id uuid not null,
  amount numeric(14,2) not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.finance_fee_group_classes (
  fee_group_id uuid not null,
  class_id uuid not null,
  sort_order integer default 0 not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.finance_fee_groups (
  id uuid default gen_random_uuid() not null,
  code text not null,
  name text not null,
  sort_order integer default 0 not null,
  active boolean default true not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.finance_fee_invoices (
  id uuid default gen_random_uuid() not null,
  account_id uuid not null,
  invoice_no text not null,
  student_id uuid not null,
  academic_year_id uuid not null,
  term_id uuid not null,
  class_id uuid not null,
  schedule_id uuid,
  issued_amount numeric not null,
  due_date date,
  description text default 'Term fee'::text not null,
  issued_at timestamp with time zone default now() not null,
  created_by uuid
);

create table if not exists public.finance_fee_schedules (
  id uuid default gen_random_uuid() not null,
  academic_year_id uuid not null,
  term_id uuid not null,
  class_id uuid not null,
  amount numeric(14,2) not null,
  due_date date,
  description text default 'Term fee'::text not null,
  active boolean default true not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  fee_group_id uuid
);

create table if not exists public.finance_fee_transactions (
  id uuid default gen_random_uuid() not null,
  student_id uuid not null,
  entry_type text not null,
  debit_amount numeric(14,2) default 0 not null,
  credit_amount numeric(14,2) default 0 not null,
  payment_method text,
  payment_reference text default ''::text not null,
  receipt_no citext,
  reversal_of_id uuid,
  transaction_date date default CURRENT_DATE not null,
  notes text default ''::text not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.finance_guardian_contact_events (
  id uuid default gen_random_uuid() not null,
  guardian_key text not null,
  guardian_name text not null,
  guardian_phone text,
  guardian_email text,
  channel text not null,
  action_state text not null,
  academic_year_id uuid,
  term_id uuid,
  class_id uuid,
  child_count integer default 0 not null,
  total_outstanding numeric(14,2) default 0 not null,
  children jsonb default '[]'::jsonb not null,
  message_text text,
  created_by uuid not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.finance_payroll_item_lines (
  id uuid default gen_random_uuid() not null,
  payroll_item_id uuid not null,
  loan_id uuid,
  line_type text not null,
  description text not null,
  amount numeric(14,2) not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  source_key text default ''::text not null
);

create table if not exists public.finance_payroll_items (
  id uuid default gen_random_uuid() not null,
  run_id uuid not null,
  teacher_id uuid not null,
  payroll_profile_id uuid,
  basic_salary numeric(14,2) default 0 not null,
  allowances numeric(14,2) default 0 not null,
  ssnit_employee numeric(14,2) default 0 not null,
  tax_amount numeric(14,2) default 0 not null,
  loan_deductions numeric(14,2) default 0 not null,
  other_deductions numeric(14,2) default 0 not null,
  gross_salary numeric(14,2) default 0 not null,
  total_deductions numeric(14,2) default 0 not null,
  net_salary numeric(14,2) default 0 not null,
  payment_status text default 'unpaid'::text not null,
  paid_at timestamp with time zone,
  payment_reference text default ''::text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.finance_payroll_profiles (
  id uuid default gen_random_uuid() not null,
  teacher_id uuid not null,
  salary_grade_id uuid,
  payroll_number citext not null,
  basic_salary_override numeric(14,2),
  ssnit_number text default ''::text not null,
  tax_id text default ''::text not null,
  active boolean default true not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  hr_staff_member_id uuid
);

create table if not exists public.finance_payroll_rules (
  id uuid default gen_random_uuid() not null,
  rule_code citext not null,
  rule_type text not null,
  name text not null,
  rate numeric(12,6),
  fixed_amount numeric(14,2),
  rule_json jsonb default '{}'::jsonb not null,
  effective_from date not null,
  effective_to date,
  active boolean default true not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.finance_payroll_runs (
  id uuid default gen_random_uuid() not null,
  payroll_year integer not null,
  payroll_month integer not null,
  status text default 'draft'::text not null,
  pay_date date,
  notes text default ''::text not null,
  created_by uuid,
  approved_by uuid,
  approved_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.finance_salary_grades (
  id uuid default gen_random_uuid() not null,
  code citext not null,
  name text not null,
  basic_salary numeric(14,2) not null,
  active boolean default true not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.finance_teacher_loans (
  id uuid default gen_random_uuid() not null,
  teacher_id uuid not null,
  reference_no citext not null,
  principal_amount numeric(14,2) not null,
  monthly_deduction numeric(14,2) not null,
  start_date date not null,
  status text default 'active'::text not null,
  notes text default ''::text not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='accounts_office_staff_pkey' and conrelid='public.accounts_office_staff'::regclass) then
    alter table public.accounts_office_staff add constraint accounts_office_staff_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='accounts_office_staff_profile_id_key' and conrelid='public.accounts_office_staff'::regclass) then
    alter table public.accounts_office_staff add constraint accounts_office_staff_profile_id_key UNIQUE (profile_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='accounts_office_staff_staff_no_key' and conrelid='public.accounts_office_staff'::regclass) then
    alter table public.accounts_office_staff add constraint accounts_office_staff_staff_no_key UNIQUE (staff_no);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='accounts_office_staff_finance_role_check' and conrelid='public.accounts_office_staff'::regclass) then
    alter table public.accounts_office_staff add constraint accounts_office_staff_finance_role_check CHECK (finance_role = ANY (ARRAY['cashier'::text, 'accounts_officer'::text, 'accountant'::text, 'payroll_officer'::text, 'finance_manager'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='accounts_office_staff_finance_role_ck' and conrelid='public.accounts_office_staff'::regclass) then
    alter table public.accounts_office_staff add constraint accounts_office_staff_finance_role_ck CHECK (finance_role = ANY (ARRAY['cashier'::text, 'accounts_officer'::text, 'accountant'::text, 'payroll_officer'::text, 'finance_manager'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='accounts_office_staff_created_by_fkey' and conrelid='public.accounts_office_staff'::regclass) then
    alter table public.accounts_office_staff add constraint accounts_office_staff_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='accounts_office_staff_profile_id_fkey' and conrelid='public.accounts_office_staff'::regclass) then
    alter table public.accounts_office_staff add constraint accounts_office_staff_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_pkey' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_student_id_term_id_key' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_student_id_term_id_key UNIQUE (student_id, term_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_term_fee_amount_check' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_term_fee_amount_check CHECK (term_fee_amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_academic_year_id_fkey' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_class_id_fkey' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_enrollment_id_fkey' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_schedule_id_fkey' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES finance_fee_schedules(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_student_id_fkey' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_accounts_term_id_fkey' and conrelid='public.finance_fee_accounts'::regclass) then
    alter table public.finance_fee_accounts add constraint finance_fee_accounts_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_allocations_pkey' and conrelid='public.finance_fee_allocations'::regclass) then
    alter table public.finance_fee_allocations add constraint finance_fee_allocations_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_allocations_transaction_id_account_id_key' and conrelid='public.finance_fee_allocations'::regclass) then
    alter table public.finance_fee_allocations add constraint finance_fee_allocations_transaction_id_account_id_key UNIQUE (transaction_id, account_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_allocations_amount_check' and conrelid='public.finance_fee_allocations'::regclass) then
    alter table public.finance_fee_allocations add constraint finance_fee_allocations_amount_check CHECK (amount > 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_allocations_account_id_fkey' and conrelid='public.finance_fee_allocations'::regclass) then
    alter table public.finance_fee_allocations add constraint finance_fee_allocations_account_id_fkey FOREIGN KEY (account_id) REFERENCES finance_fee_accounts(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_allocations_transaction_id_fkey' and conrelid='public.finance_fee_allocations'::regclass) then
    alter table public.finance_fee_allocations add constraint finance_fee_allocations_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES finance_fee_transactions(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_group_classes_pkey' and conrelid='public.finance_fee_group_classes'::regclass) then
    alter table public.finance_fee_group_classes add constraint finance_fee_group_classes_pkey PRIMARY KEY (fee_group_id, class_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_group_classes_class_unique' and conrelid='public.finance_fee_group_classes'::regclass) then
    alter table public.finance_fee_group_classes add constraint finance_fee_group_classes_class_unique UNIQUE (class_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_group_classes_class_id_fkey' and conrelid='public.finance_fee_group_classes'::regclass) then
    alter table public.finance_fee_group_classes add constraint finance_fee_group_classes_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_group_classes_fee_group_id_fkey' and conrelid='public.finance_fee_group_classes'::regclass) then
    alter table public.finance_fee_group_classes add constraint finance_fee_group_classes_fee_group_id_fkey FOREIGN KEY (fee_group_id) REFERENCES finance_fee_groups(id) ON DELETE CASCADE;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_groups_pkey' and conrelid='public.finance_fee_groups'::regclass) then
    alter table public.finance_fee_groups add constraint finance_fee_groups_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_groups_code_key' and conrelid='public.finance_fee_groups'::regclass) then
    alter table public.finance_fee_groups add constraint finance_fee_groups_code_key UNIQUE (code);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_groups_code_check' and conrelid='public.finance_fee_groups'::regclass) then
    alter table public.finance_fee_groups add constraint finance_fee_groups_code_check CHECK (code ~ '^[a-z0-9_]+$'::text);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_groups_created_by_fkey' and conrelid='public.finance_fee_groups'::regclass) then
    alter table public.finance_fee_groups add constraint finance_fee_groups_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_pkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_account_id_key' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_account_id_key UNIQUE (account_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_invoice_no_key' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_invoice_no_key UNIQUE (invoice_no);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_issued_amount_check' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_issued_amount_check CHECK (issued_amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_academic_year_id_fkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_account_id_fkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_account_id_fkey FOREIGN KEY (account_id) REFERENCES finance_fee_accounts(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_class_id_fkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_created_by_fkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_schedule_id_fkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES finance_fee_schedules(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_student_id_fkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_invoices_term_id_fkey' and conrelid='public.finance_fee_invoices'::regclass) then
    alter table public.finance_fee_invoices add constraint finance_fee_invoices_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_pkey' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_academic_year_id_term_id_class_id_key' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_academic_year_id_term_id_class_id_key UNIQUE (academic_year_id, term_id, class_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_amount_check' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_amount_check CHECK (amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_academic_year_id_fkey' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_class_id_fkey' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_created_by_fkey' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_fee_group_id_fkey' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_fee_group_id_fkey FOREIGN KEY (fee_group_id) REFERENCES finance_fee_groups(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_schedules_term_id_fkey' and conrelid='public.finance_fee_schedules'::regclass) then
    alter table public.finance_fee_schedules add constraint finance_fee_schedules_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_pkey' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_receipt_no_key' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_receipt_no_key UNIQUE (receipt_no);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_check' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_check CHECK (debit_amount > 0::numeric AND credit_amount = 0::numeric OR credit_amount > 0::numeric AND debit_amount = 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_credit_amount_check' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_credit_amount_check CHECK (credit_amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_debit_amount_check' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_debit_amount_check CHECK (debit_amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_entry_type_check' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_entry_type_check CHECK (entry_type = ANY (ARRAY['payment'::text, 'payment_reversal'::text, 'waiver'::text, 'discount'::text, 'refund'::text, 'adjustment_debit'::text, 'adjustment_credit'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_payment_method_check' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_payment_method_check CHECK (payment_method IS NULL OR (payment_method = ANY (ARRAY['cash'::text, 'bank_transfer'::text, 'mobile_money'::text, 'cheque'::text, 'card'::text, 'other'::text])));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_receipt_semantics_ck' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_receipt_semantics_ck CHECK (entry_type = 'payment'::text AND receipt_no IS NOT NULL OR entry_type <> 'payment'::text AND receipt_no IS NULL);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_reversal_semantics_ck' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_reversal_semantics_ck CHECK (entry_type = 'payment_reversal'::text AND reversal_of_id IS NOT NULL OR entry_type <> 'payment_reversal'::text AND reversal_of_id IS NULL);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_created_by_fkey' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_reversal_of_id_fkey' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_reversal_of_id_fkey FOREIGN KEY (reversal_of_id) REFERENCES finance_fee_transactions(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_fee_transactions_student_id_fkey' and conrelid='public.finance_fee_transactions'::regclass) then
    alter table public.finance_fee_transactions add constraint finance_fee_transactions_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_pkey' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_action_state_check' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_action_state_check CHECK (action_state = ANY (ARRAY['opened'::text, 'copied'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_channel_check' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_channel_check CHECK (channel = ANY (ARRAY['sms'::text, 'whatsapp'::text, 'call'::text, 'copy'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_child_count_check' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_child_count_check CHECK (child_count >= 0);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_academic_year_id_fkey' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_academic_year_id_fkey FOREIGN KEY (academic_year_id) REFERENCES academic_years(id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_class_id_fkey' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_class_id_fkey FOREIGN KEY (class_id) REFERENCES classes(id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_created_by_fkey' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_guardian_contact_events_term_id_fkey' and conrelid='public.finance_guardian_contact_events'::regclass) then
    alter table public.finance_guardian_contact_events add constraint finance_guardian_contact_events_term_id_fkey FOREIGN KEY (term_id) REFERENCES terms(id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_item_lines_pkey' and conrelid='public.finance_payroll_item_lines'::regclass) then
    alter table public.finance_payroll_item_lines add constraint finance_payroll_item_lines_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_item_lines_amount_check' and conrelid='public.finance_payroll_item_lines'::regclass) then
    alter table public.finance_payroll_item_lines add constraint finance_payroll_item_lines_amount_check CHECK (amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_item_lines_line_type_check' and conrelid='public.finance_payroll_item_lines'::regclass) then
    alter table public.finance_payroll_item_lines add constraint finance_payroll_item_lines_line_type_check CHECK (line_type = ANY (ARRAY['allowance'::text, 'deduction'::text, 'ssnit'::text, 'tax'::text, 'loan'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_item_lines_created_by_fkey' and conrelid='public.finance_payroll_item_lines'::regclass) then
    alter table public.finance_payroll_item_lines add constraint finance_payroll_item_lines_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_item_lines_loan_id_fkey' and conrelid='public.finance_payroll_item_lines'::regclass) then
    alter table public.finance_payroll_item_lines add constraint finance_payroll_item_lines_loan_id_fkey FOREIGN KEY (loan_id) REFERENCES finance_teacher_loans(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_item_lines_payroll_item_id_fkey' and conrelid='public.finance_payroll_item_lines'::regclass) then
    alter table public.finance_payroll_item_lines add constraint finance_payroll_item_lines_payroll_item_id_fkey FOREIGN KEY (payroll_item_id) REFERENCES finance_payroll_items(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_pkey' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_run_id_teacher_id_key' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_run_id_teacher_id_key UNIQUE (run_id, teacher_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_allowances_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_allowances_check CHECK (allowances >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_basic_salary_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_basic_salary_check CHECK (basic_salary >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_gross_salary_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_gross_salary_check CHECK (gross_salary >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_loan_deductions_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_loan_deductions_check CHECK (loan_deductions >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_net_salary_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_net_salary_check CHECK (net_salary >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_other_deductions_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_other_deductions_check CHECK (other_deductions >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_payment_status_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_payment_status_check CHECK (payment_status = ANY (ARRAY['unpaid'::text, 'paid'::text, 'reversed'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_ssnit_employee_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_ssnit_employee_check CHECK (ssnit_employee >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_tax_amount_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_tax_amount_check CHECK (tax_amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_total_deductions_check' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_total_deductions_check CHECK (total_deductions >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_payroll_profile_id_fkey' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_payroll_profile_id_fkey FOREIGN KEY (payroll_profile_id) REFERENCES finance_payroll_profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_run_id_fkey' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_run_id_fkey FOREIGN KEY (run_id) REFERENCES finance_payroll_runs(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_items_teacher_id_fkey' and conrelid='public.finance_payroll_items'::regclass) then
    alter table public.finance_payroll_items add constraint finance_payroll_items_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_profiles_pkey' and conrelid='public.finance_payroll_profiles'::regclass) then
    alter table public.finance_payroll_profiles add constraint finance_payroll_profiles_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_profiles_payroll_number_key' and conrelid='public.finance_payroll_profiles'::regclass) then
    alter table public.finance_payroll_profiles add constraint finance_payroll_profiles_payroll_number_key UNIQUE (payroll_number);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_profiles_teacher_id_key' and conrelid='public.finance_payroll_profiles'::regclass) then
    alter table public.finance_payroll_profiles add constraint finance_payroll_profiles_teacher_id_key UNIQUE (teacher_id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_profiles_basic_salary_override_check' and conrelid='public.finance_payroll_profiles'::regclass) then
    alter table public.finance_payroll_profiles add constraint finance_payroll_profiles_basic_salary_override_check CHECK (basic_salary_override IS NULL OR basic_salary_override >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_profiles_created_by_fkey' and conrelid='public.finance_payroll_profiles'::regclass) then
    alter table public.finance_payroll_profiles add constraint finance_payroll_profiles_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_profiles_salary_grade_id_fkey' and conrelid='public.finance_payroll_profiles'::regclass) then
    alter table public.finance_payroll_profiles add constraint finance_payroll_profiles_salary_grade_id_fkey FOREIGN KEY (salary_grade_id) REFERENCES finance_salary_grades(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_profiles_teacher_id_fkey' and conrelid='public.finance_payroll_profiles'::regclass) then
    alter table public.finance_payroll_profiles add constraint finance_payroll_profiles_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_rules_pkey' and conrelid='public.finance_payroll_rules'::regclass) then
    alter table public.finance_payroll_rules add constraint finance_payroll_rules_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_rules_rule_code_effective_from_key' and conrelid='public.finance_payroll_rules'::regclass) then
    alter table public.finance_payroll_rules add constraint finance_payroll_rules_rule_code_effective_from_key UNIQUE (rule_code, effective_from);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_rules_check' and conrelid='public.finance_payroll_rules'::regclass) then
    alter table public.finance_payroll_rules add constraint finance_payroll_rules_check CHECK (effective_to IS NULL OR effective_to >= effective_from);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_rules_fixed_amount_check' and conrelid='public.finance_payroll_rules'::regclass) then
    alter table public.finance_payroll_rules add constraint finance_payroll_rules_fixed_amount_check CHECK (fixed_amount IS NULL OR fixed_amount >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_rules_rate_check' and conrelid='public.finance_payroll_rules'::regclass) then
    alter table public.finance_payroll_rules add constraint finance_payroll_rules_rate_check CHECK (rate IS NULL OR rate >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_rules_rule_type_check' and conrelid='public.finance_payroll_rules'::regclass) then
    alter table public.finance_payroll_rules add constraint finance_payroll_rules_rule_type_check CHECK (rule_type = ANY (ARRAY['ssnit_employee'::text, 'ssnit_employer'::text, 'tax'::text, 'allowance'::text, 'deduction'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_rules_created_by_fkey' and conrelid='public.finance_payroll_rules'::regclass) then
    alter table public.finance_payroll_rules add constraint finance_payroll_rules_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_runs_pkey' and conrelid='public.finance_payroll_runs'::regclass) then
    alter table public.finance_payroll_runs add constraint finance_payroll_runs_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_runs_payroll_year_payroll_month_key' and conrelid='public.finance_payroll_runs'::regclass) then
    alter table public.finance_payroll_runs add constraint finance_payroll_runs_payroll_year_payroll_month_key UNIQUE (payroll_year, payroll_month);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_runs_payroll_month_check' and conrelid='public.finance_payroll_runs'::regclass) then
    alter table public.finance_payroll_runs add constraint finance_payroll_runs_payroll_month_check CHECK (payroll_month >= 1 AND payroll_month <= 12);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_runs_payroll_year_check' and conrelid='public.finance_payroll_runs'::regclass) then
    alter table public.finance_payroll_runs add constraint finance_payroll_runs_payroll_year_check CHECK (payroll_year >= 2000 AND payroll_year <= 2200);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_runs_status_check' and conrelid='public.finance_payroll_runs'::regclass) then
    alter table public.finance_payroll_runs add constraint finance_payroll_runs_status_check CHECK (status = ANY (ARRAY['draft'::text, 'calculated'::text, 'approved'::text, 'paid'::text, 'locked'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_runs_approved_by_fkey' and conrelid='public.finance_payroll_runs'::regclass) then
    alter table public.finance_payroll_runs add constraint finance_payroll_runs_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_payroll_runs_created_by_fkey' and conrelid='public.finance_payroll_runs'::regclass) then
    alter table public.finance_payroll_runs add constraint finance_payroll_runs_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_salary_grades_pkey' and conrelid='public.finance_salary_grades'::regclass) then
    alter table public.finance_salary_grades add constraint finance_salary_grades_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_salary_grades_code_key' and conrelid='public.finance_salary_grades'::regclass) then
    alter table public.finance_salary_grades add constraint finance_salary_grades_code_key UNIQUE (code);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_salary_grades_basic_salary_check' and conrelid='public.finance_salary_grades'::regclass) then
    alter table public.finance_salary_grades add constraint finance_salary_grades_basic_salary_check CHECK (basic_salary >= 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_salary_grades_created_by_fkey' and conrelid='public.finance_salary_grades'::regclass) then
    alter table public.finance_salary_grades add constraint finance_salary_grades_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_teacher_loans_pkey' and conrelid='public.finance_teacher_loans'::regclass) then
    alter table public.finance_teacher_loans add constraint finance_teacher_loans_pkey PRIMARY KEY (id);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_teacher_loans_reference_no_key' and conrelid='public.finance_teacher_loans'::regclass) then
    alter table public.finance_teacher_loans add constraint finance_teacher_loans_reference_no_key UNIQUE (reference_no);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_teacher_loans_monthly_deduction_check' and conrelid='public.finance_teacher_loans'::regclass) then
    alter table public.finance_teacher_loans add constraint finance_teacher_loans_monthly_deduction_check CHECK (monthly_deduction > 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_teacher_loans_principal_amount_check' and conrelid='public.finance_teacher_loans'::regclass) then
    alter table public.finance_teacher_loans add constraint finance_teacher_loans_principal_amount_check CHECK (principal_amount > 0::numeric);
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_teacher_loans_status_check' and conrelid='public.finance_teacher_loans'::regclass) then
    alter table public.finance_teacher_loans add constraint finance_teacher_loans_status_check CHECK (status = ANY (ARRAY['active'::text, 'settled'::text, 'suspended'::text, 'cancelled'::text]));
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_teacher_loans_created_by_fkey' and conrelid='public.finance_teacher_loans'::regclass) then
    alter table public.finance_teacher_loans add constraint finance_teacher_loans_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
  end if;
end $ddl$;
do $ddl$ begin
  if not exists(select 1 from pg_constraint where conname='finance_teacher_loans_teacher_id_fkey' and conrelid='public.finance_teacher_loans'::regclass) then
    alter table public.finance_teacher_loans add constraint finance_teacher_loans_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers(id) ON DELETE RESTRICT;
  end if;
end $ddl$;

CREATE INDEX IF NOT EXISTS finance_fee_accounts_class_idx ON public.finance_fee_accounts USING btree (class_id, term_id);
CREATE INDEX IF NOT EXISTS finance_fee_accounts_student_idx ON public.finance_fee_accounts USING btree (student_id, academic_year_id, term_id);
CREATE INDEX IF NOT EXISTS finance_fee_allocations_account_idx ON public.finance_fee_allocations USING btree (account_id);
CREATE INDEX IF NOT EXISTS finance_fee_invoices_academic_year_idx ON public.finance_fee_invoices USING btree (academic_year_id);
CREATE INDEX IF NOT EXISTS finance_fee_invoices_class_idx ON public.finance_fee_invoices USING btree (class_id);
CREATE INDEX IF NOT EXISTS finance_fee_invoices_created_by_idx ON public.finance_fee_invoices USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS finance_fee_invoices_due_status_idx ON public.finance_fee_invoices USING btree (due_date, student_id);
CREATE INDEX IF NOT EXISTS finance_fee_invoices_schedule_idx ON public.finance_fee_invoices USING btree (schedule_id) WHERE (schedule_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS finance_fee_invoices_student_idx ON public.finance_fee_invoices USING btree (student_id);
CREATE INDEX IF NOT EXISTS finance_fee_invoices_term_idx ON public.finance_fee_invoices USING btree (term_id);
CREATE INDEX IF NOT EXISTS finance_fee_schedules_fee_group_idx ON public.finance_fee_schedules USING btree (fee_group_id, academic_year_id, term_id);
CREATE UNIQUE INDEX IF NOT EXISTS finance_fee_transactions_one_reversal_per_original ON public.finance_fee_transactions USING btree (reversal_of_id) WHERE (reversal_of_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS finance_fee_transactions_student_idx ON public.finance_fee_transactions USING btree (student_id, transaction_date, created_at);
CREATE INDEX IF NOT EXISTS finance_guardian_contact_events_created_idx ON public.finance_guardian_contact_events USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS finance_guardian_contact_events_guardian_idx ON public.finance_guardian_contact_events USING btree (guardian_key, created_at DESC);
CREATE INDEX IF NOT EXISTS finance_guardian_contact_events_period_idx ON public.finance_guardian_contact_events USING btree (academic_year_id, term_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS finance_payroll_item_lines_source_unique ON public.finance_payroll_item_lines USING btree (payroll_item_id, source_key) WHERE (source_key <> ''::text);
CREATE INDEX IF NOT EXISTS finance_payroll_items_teacher_idx ON public.finance_payroll_items USING btree (teacher_id, created_at DESC);
CREATE INDEX IF NOT EXISTS finance_payroll_profiles_hr_staff_idx ON public.finance_payroll_profiles USING btree (hr_staff_member_id) WHERE (hr_staff_member_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS finance_teacher_loans_teacher_idx ON public.finance_teacher_loans USING btree (teacher_id, status);

create or replace view public.finance_fee_account_balances as
 SELECT a.id,
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
  GROUP BY a.id, s.due_date, t.end_date;;

alter table public.accounts_office_staff enable row level security;
revoke all on table public.accounts_office_staff from public,anon,authenticated;
grant all on table public.accounts_office_staff to service_role;
alter table public.finance_fee_accounts enable row level security;
revoke all on table public.finance_fee_accounts from public,anon,authenticated;
grant all on table public.finance_fee_accounts to service_role;
alter table public.finance_fee_allocations enable row level security;
revoke all on table public.finance_fee_allocations from public,anon,authenticated;
grant all on table public.finance_fee_allocations to service_role;
alter table public.finance_fee_group_classes enable row level security;
revoke all on table public.finance_fee_group_classes from public,anon,authenticated;
grant all on table public.finance_fee_group_classes to service_role;
alter table public.finance_fee_groups enable row level security;
revoke all on table public.finance_fee_groups from public,anon,authenticated;
grant all on table public.finance_fee_groups to service_role;
alter table public.finance_fee_invoices enable row level security;
revoke all on table public.finance_fee_invoices from public,anon,authenticated;
grant all on table public.finance_fee_invoices to service_role;
alter table public.finance_fee_schedules enable row level security;
revoke all on table public.finance_fee_schedules from public,anon,authenticated;
grant all on table public.finance_fee_schedules to service_role;
alter table public.finance_fee_transactions enable row level security;
revoke all on table public.finance_fee_transactions from public,anon,authenticated;
grant all on table public.finance_fee_transactions to service_role;
alter table public.finance_guardian_contact_events enable row level security;
revoke all on table public.finance_guardian_contact_events from public,anon,authenticated;
grant all on table public.finance_guardian_contact_events to service_role;
alter table public.finance_payroll_item_lines enable row level security;
revoke all on table public.finance_payroll_item_lines from public,anon,authenticated;
grant all on table public.finance_payroll_item_lines to service_role;
alter table public.finance_payroll_items enable row level security;
revoke all on table public.finance_payroll_items from public,anon,authenticated;
grant all on table public.finance_payroll_items to service_role;
alter table public.finance_payroll_profiles enable row level security;
revoke all on table public.finance_payroll_profiles from public,anon,authenticated;
grant all on table public.finance_payroll_profiles to service_role;
alter table public.finance_payroll_rules enable row level security;
revoke all on table public.finance_payroll_rules from public,anon,authenticated;
grant all on table public.finance_payroll_rules to service_role;
alter table public.finance_payroll_runs enable row level security;
revoke all on table public.finance_payroll_runs from public,anon,authenticated;
grant all on table public.finance_payroll_runs to service_role;
alter table public.finance_salary_grades enable row level security;
revoke all on table public.finance_salary_grades from public,anon,authenticated;
grant all on table public.finance_salary_grades to service_role;
alter table public.finance_teacher_loans enable row level security;
revoke all on table public.finance_teacher_loans from public,anon,authenticated;
grant all on table public.finance_teacher_loans to service_role;

revoke all on sequence public.finance_invoice_seq,public.finance_payroll_no_seq,public.finance_receipt_seq,public.accounts_office_staff_no_seq from public,anon,authenticated;
grant usage,select,update on sequence public.finance_invoice_seq,public.finance_payroll_no_seq,public.finance_receipt_seq,public.accounts_office_staff_no_seq to service_role;

CREATE OR REPLACE FUNCTION public.admin_accounts_staff_directory(search_text text DEFAULT ''::text, include_inactive boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object('rows',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',a.id,'profile_id',a.profile_id,'staff_no',a.staff_no,'full_name',a.full_name,'phone',a.phone,'email',a.email,
      'contact_address',a.contact_address,'job_title',a.job_title,'active',a.active,'deleted_at',a.deleted_at,
      'portal_email',u.email,'portal_active',p.active,'last_seen_at',p.last_seen_at
    ) order by lower(a.full_name),a.staff_no::text)
    from public.accounts_office_staff a
    left join public.profiles p on p.id=a.profile_id
    left join auth.users u on u.id=a.profile_id
    where (include_inactive or (a.active and a.deleted_at is null))
      and (coalesce(search_text,'')='' or concat_ws(' ',a.full_name,a.staff_no::text,a.phone,a.email,a.contact_address) ilike '%'||search_text||'%')
  ),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_deactivate_accounts_staff(target_staff_id uuid, reason_text text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare linked uuid;l jsonb;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  l:=public.license_snapshot_for_role('system_admin');
  if coalesce((l->>'write_allowed')::boolean,false)<>true then raise exception 'The current licence is read-only' using errcode='42501'; end if;
  select profile_id into linked from public.accounts_office_staff where id=target_staff_id and deleted_at is null;
  if not found then raise exception 'Accounts Office staff record was not found'; end if;
  update public.accounts_office_staff set active=false,deleted_at=now() where id=target_staff_id;
  if linked is not null then update public.profiles set active=false,updated_at=now() where id=linked and public.current_app_role_for(role)='accountant'; end if;
  insert into public.audit_log(actor_id,table_name,record_id,action,reason) values(auth.uid(),'accounts_office_staff',target_staff_id,'ACCOUNTANT_DIRECTORY_DEACTIVATE',coalesce(nullif(reason_text,''),'Accountant directory record deactivated'));
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_remove_accounts_staff_permanently(target_staff_id uuid, reason_text text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  l jsonb;
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  perform public.require_sensitive_access();

  l := public.license_snapshot_for_role('system_admin');
  if coalesce((l->>'write_allowed')::boolean,false) <> true then
    raise exception 'The current licence is read-only' using errcode='42501';
  end if;

  perform 1
  from public.accounts_office_staff
  where id = target_staff_id;

  if not found then
    raise exception 'Accounts Office staff record was not found';
  end if;

  raise exception 'Permanent removal is disabled for Accounts Office Staff. Archive or deactivate the record instead so staff identity and finance audit history remain recoverable.'
    using errcode='42501';
end
$function$;

CREATE OR REPLACE FUNCTION public.admin_save_accounts_staff(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id');r public.accounts_office_staff%rowtype;staffno text;l jsonb;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  l:=public.license_snapshot_for_role('system_admin');
  if coalesce((l->>'write_allowed')::boolean,false)<>true then raise exception 'The current licence is read-only' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'full_name',''))='' then raise exception 'Full name is required'; end if;
  if rid is null then
    staffno:=public.finance_generate_staff_no();
    insert into public.accounts_office_staff(staff_no,full_name,phone,email,contact_address,job_title,finance_role,active,created_by)
    values(staffno,btrim(payload->>'full_name'),btrim(coalesce(payload->>'phone','')),nullif(btrim(coalesce(payload->>'email','')),''),btrim(coalesce(payload->>'contact_address','')),'Accountant','accountant',coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
    insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'accounts_office_staff',r.id,'ACCOUNTANT_DIRECTORY_CREATE',to_jsonb(r),'Accountant directory record created');
  else
    update public.accounts_office_staff set full_name=btrim(payload->>'full_name'),phone=btrim(coalesce(payload->>'phone','')),email=nullif(btrim(coalesce(payload->>'email','')),''),contact_address=btrim(coalesce(payload->>'contact_address','')),job_title='Accountant',finance_role='accountant',active=coalesce((payload->>'active')::boolean,active),deleted_at=case when coalesce((payload->>'active')::boolean,active) then null else deleted_at end where id=rid returning * into r;
    if r.id is null then raise exception 'Accounts Office staff record was not found'; end if;
    insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'accounts_office_staff',r.id,'ACCOUNTANT_DIRECTORY_UPDATE',to_jsonb(r),'Accountant directory record updated');
  end if;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_accounts_console(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('finance_fees',false);
 return jsonb_build_object(
  'metrics',jsonb_build_object(
    'expected',coalesce((select sum(b.term_fee_amount+greatest(b.debit_adjustments,0)) from public.finance_fee_account_balances b where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),0),
    'collected',coalesce((select sum(b.amount_paid) from public.finance_fee_account_balances b where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),0),
    'outstanding',coalesce((select sum(greatest(b.balance,0)) from public.finance_fee_account_balances b where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),0),
    'fully_paid',(select count(*) from public.finance_fee_account_balances b where b.status in ('fully_paid','credit') and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),
    'partial_paid',(select count(*) from public.finance_fee_account_balances b where b.status='partial_paid' and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),
    'unpaid',(select count(*) from public.finance_fee_account_balances b where b.status='unpaid' and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id))
  ),
  'fee_groups',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',g.id,'code',g.code,'name',g.name,'sort_order',g.sort_order,'active',g.active,
      'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'level_order',c.level_order) order by m.sort_order,c.level_order,c.name)
                          from public.finance_fee_group_classes m join public.classes c on c.id=m.class_id
                          where m.fee_group_id=g.id),'[]'::jsonb)
    ) order by g.sort_order,g.name)
    from public.finance_fee_groups g where g.active
  ),'[]'::jsonb),
  'schedules',coalesce((
    select jsonb_agg(to_jsonb(q)-'year_start'-'term_sequence'-'sort_order' order by q.year_start desc,q.term_sequence,q.sort_order,q.display_name)
    from (
      select (array_agg(s.id order by c.level_order,c.name))[1] id,
             s.academic_year_id,s.term_id,s.fee_group_id,g.name fee_group_name,
             null::uuid class_id,g.name display_name,g.name class_name,
             string_agg(c.name,', ' order by c.level_order,c.name) member_classes,
             s.amount,s.due_date,s.description,bool_and(s.active) active,
             y.name academic_year_name,t.name term_name,y.start_date year_start,t.sequence term_sequence,g.sort_order
      from public.finance_fee_schedules s
      join public.finance_fee_groups g on g.id=s.fee_group_id
      join public.classes c on c.id=s.class_id
      join public.academic_years y on y.id=s.academic_year_id
      join public.terms t on t.id=s.term_id
      where s.fee_group_id is not null
      group by s.academic_year_id,s.term_id,s.fee_group_id,g.name,g.sort_order,s.amount,s.due_date,s.description,y.name,t.name,y.start_date,t.sequence
      union all
      select s.id,s.academic_year_id,s.term_id,null::uuid,null::text,c.id,c.name,c.name,c.name,s.amount,s.due_date,s.description,s.active,y.name,t.name,y.start_date,t.sequence,c.level_order
      from public.finance_fee_schedules s
      join public.classes c on c.id=s.class_id
      join public.academic_years y on y.id=s.academic_year_id
      join public.terms t on t.id=s.term_id
      where s.fee_group_id is null
    ) q
  ),'[]'::jsonb),
  'statements',coalesce((select jsonb_agg(jsonb_build_object('account_id',b.id,'student_id',st.id,'student',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'admission_no',st.admission_no,'class_id',c.id,'class_name',c.name,'academic_year_id',y.id,'academic_year_name',y.name,'term_id',t.id,'term_name',t.name,'due',b.term_fee_amount,'paid',b.amount_paid,'balance',b.balance,'status',b.status,'method',(select x.payment_method from public.finance_fee_transactions x join public.finance_fee_allocations a on a.transaction_id=x.id where a.account_id=b.id and x.entry_type='payment' order by x.created_at desc limit 1),'hold',public.finance_student_hold_status(st.id)) order by c.level_order,st.last_name,st.first_name) from public.finance_fee_account_balances b join public.students st on st.id=b.student_id join public.classes c on c.id=b.class_id join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),'[]'::jsonb),
  'hold_policy',(select to_jsonb(p) from public.finance_hold_policy p where id=1),
  'staff',case when public.current_app_role()='system_admin' then coalesce((select jsonb_agg(to_jsonb(a) order by lower(a.full_name)) from public.accounts_office_staff a where a.deleted_at is null),'[]'::jsonb) else '[]'::jsonb end
 );
end $function$;

CREATE OR REPLACE FUNCTION public.finance_approve_payroll(target_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.finance_payroll_runs%rowtype;
begin perform public.finance_require_access('payroll',true); select * into r from public.finance_payroll_runs where id=target_run_id; if r.id is null or r.status<>'calculated' then raise exception 'Only calculated payroll can be approved'; end if; update public.finance_payroll_runs set status='approved',approved_by=auth.uid(),approved_at=now() where id=target_run_id returning * into r; return to_jsonb(r); end $function$;

CREATE OR REPLACE FUNCTION public.finance_calculate_payroll(target_year integer, target_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare runrow public.finance_payroll_runs%rowtype; p record; item public.finance_payroll_items%rowtype; d date:=make_date(target_year,target_month,1); base numeric; allowances numeric; deductions numeric; ssnit numeric; taxv numeric; gross numeric; taxable numeric; loan_total numeric; rule record; loan record; ratev numeric; cnt int:=0;
begin
 perform public.finance_require_access('payroll',true);
 if target_year not between 2000 and 2200 or target_month not between 1 and 12 then raise exception 'Payroll period is invalid'; end if;
 insert into public.finance_payroll_runs(payroll_year,payroll_month,status,created_by) values(target_year,target_month,'draft',auth.uid()) on conflict(payroll_year,payroll_month) do update set updated_at=now() returning * into runrow;
 if runrow.status in ('approved','paid','locked') then raise exception 'Approved or paid payroll cannot be recalculated'; end if;
 for p in select pp.*,t.first_name,t.middle_name,t.last_name,g.basic_salary grade_salary from public.finance_payroll_profiles pp join public.teachers t on t.id=pp.teacher_id and t.active and t.deleted_at is null left join public.finance_salary_grades g on g.id=pp.salary_grade_id where pp.active loop
   base:=coalesce(p.basic_salary_override,p.grade_salary,0); allowances:=0; deductions:=0;
   for rule in select * from public.finance_payroll_rules where active and effective_from<=d and (effective_to is null or effective_to>=d) and rule_type in ('allowance','deduction') order by rule_code loop
     ratev:=base*public.finance_effective_rate(rule.rate)+coalesce(rule.fixed_amount,0);
     if rule.rule_type='allowance' then allowances:=allowances+ratev; else deductions:=deductions+ratev; end if;
   end loop;
   gross:=round(base+allowances,2);
   select round(gross*public.finance_effective_rate(r.rate)+coalesce(r.fixed_amount,0),2) into ssnit from public.finance_payroll_rules r where r.rule_type='ssnit_employee' and r.active and r.effective_from<=d and (r.effective_to is null or r.effective_to>=d) order by r.effective_from desc,r.created_at desc limit 1; ssnit:=coalesce(ssnit,0);
   taxable:=greatest(gross-ssnit,0); taxv:=public.finance_compute_tax(taxable,d); loan_total:=0;
   for loan in select l.*,public.finance_loan_balance(l.id) remaining from public.finance_teacher_loans l where l.teacher_id=p.teacher_id and l.status='active' and l.start_date<=d loop loan_total:=loan_total+least(loan.monthly_deduction,loan.remaining); end loop;
   insert into public.finance_payroll_items(run_id,teacher_id,payroll_profile_id,basic_salary,allowances,ssnit_employee,tax_amount,loan_deductions,other_deductions,gross_salary,total_deductions,net_salary,payment_status)
   values(runrow.id,p.teacher_id,p.id,base,round(allowances,2),ssnit,taxv,round(loan_total,2),round(deductions,2),gross,round(ssnit+taxv+loan_total+deductions,2),greatest(round(gross-(ssnit+taxv+loan_total+deductions),2),0),'unpaid')
   on conflict(run_id,teacher_id) do update set payroll_profile_id=excluded.payroll_profile_id,basic_salary=excluded.basic_salary,allowances=excluded.allowances,ssnit_employee=excluded.ssnit_employee,tax_amount=excluded.tax_amount,loan_deductions=excluded.loan_deductions,other_deductions=excluded.other_deductions,gross_salary=excluded.gross_salary,total_deductions=excluded.total_deductions,net_salary=excluded.net_salary,updated_at=now() returning * into item;
   delete from public.finance_payroll_item_lines where payroll_item_id=item.id;
   for rule in select * from public.finance_payroll_rules where active and effective_from<=d and (effective_to is null or effective_to>=d) and rule_type in ('allowance','deduction') order by rule_code loop ratev:=round(base*public.finance_effective_rate(rule.rate)+coalesce(rule.fixed_amount,0),2); if ratev>0 then insert into public.finance_payroll_item_lines(payroll_item_id,line_type,description,amount,source_key,created_by) values(item.id,rule.rule_type,rule.name,ratev,'rule:'||rule.id::text,auth.uid()); end if; end loop;
   if ssnit>0 then insert into public.finance_payroll_item_lines(payroll_item_id,line_type,description,amount,source_key,created_by) values(item.id,'ssnit','SSNIT employee contribution',ssnit,'ssnit',auth.uid()); end if;
   if taxv>0 then insert into public.finance_payroll_item_lines(payroll_item_id,line_type,description,amount,source_key,created_by) values(item.id,'tax','Income tax',taxv,'tax',auth.uid()); end if;
   for loan in select l.*,public.finance_loan_balance(l.id) remaining from public.finance_teacher_loans l where l.teacher_id=p.teacher_id and l.status='active' and l.start_date<=d loop ratev:=least(loan.monthly_deduction,loan.remaining); if ratev>0 then insert into public.finance_payroll_item_lines(payroll_item_id,loan_id,line_type,description,amount,source_key,created_by) values(item.id,loan.id,'loan','School loan '||loan.reference_no::text,ratev,'loan:'||loan.id::text,auth.uid()); end if; end loop;
   cnt:=cnt+1;
 end loop;
 update public.finance_payroll_runs set status='calculated',updated_at=now() where id=runrow.id returning * into runrow;
 insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'finance_payroll_runs',runrow.id,'PAYROLL_CALCULATED',jsonb_build_object('year',target_year,'month',target_month,'items',cnt),'Monthly payroll calculated');
 return jsonb_build_object('run',to_jsonb(runrow),'item_count',cnt);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_class_fee_statement(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('finance_statements',false,array['accountant']);
 if target_academic_year_id is null or target_term_id is null or target_class_id is null then raise exception 'Academic year, term and class are required'; end if;
 return jsonb_build_object(
  'academic_year',(select name from public.academic_years where id=target_academic_year_id),
  'term',(select name from public.terms where id=target_term_id),
  'class',(select name from public.classes where id=target_class_id),
  'rows',coalesce((select jsonb_agg(jsonb_build_object(
    'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,
    'account_id',b.id,'due',coalesce(b.term_fee_amount,0),'paid',coalesce(b.amount_paid,0),'balance',coalesce(b.balance,0),
    'status',coalesce(b.status,case when fs.id is null then 'not_configured' else 'unpaid' end),'balance_remaining',coalesce(b.balance_remaining,false),
    'hold',public.finance_student_hold_status(s.id)
  ) order by s.last_name,s.first_name)
  from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null
  left join public.finance_fee_account_balances b on b.student_id=s.id and b.term_id=target_term_id
  left join public.finance_fee_schedules fs on fs.academic_year_id=target_academic_year_id and fs.term_id=target_term_id and fs.class_id=target_class_id and fs.active
  where e.academic_year_id=target_academic_year_id and e.class_id=target_class_id and e.active and e.deleted_at is null),'[]'::jsonb)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.finance_clear_guardian_contact_history()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleared_count integer:=0;
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  with deleted as (
    delete from public.finance_guardian_contact_events
    where true
    returning 1
  )
  select count(*)::integer into cleared_count from deleted;

  return jsonb_build_object(
    'cleared',cleared_count,
    'cleared_at',now()
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_clear_hold_override(target_student_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin perform public.finance_require_access('financial_holds',true); perform public.finance_require_capability('financial_hold'); if btrim(coalesce(reason_text,''))='' then raise exception 'A reason is required'; end if; update public.finance_hold_overrides set active=false,updated_at=now() where student_id=target_student_id and active; insert into public.audit_log(actor_id,table_name,record_id,action,reason) values(auth.uid(),'finance_hold_overrides',target_student_id,'FINANCIAL_HOLD_OVERRIDE_CLEARED',reason_text); return public.finance_student_hold_status(target_student_id); end $function$;

CREATE OR REPLACE FUNCTION public.finance_compute_tax(taxable_amount numeric, target_date date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r public.finance_payroll_rules%rowtype; bracket jsonb; lower_bound numeric; upper_bound numeric; rate_value numeric; portion numeric; total numeric:=0;
begin
  if coalesce(taxable_amount,0)<=0 then return 0; end if;
  select * into r from public.finance_payroll_rules
   where rule_type='tax' and active and effective_from<=target_date and (effective_to is null or effective_to>=target_date)
   order by effective_from desc,created_at desc limit 1;
  if r.id is null then return 0; end if;
  if jsonb_typeof(r.rule_json->'brackets')='array' then
    for bracket in select value from jsonb_array_elements(r.rule_json->'brackets') loop
      lower_bound:=greatest(coalesce((bracket->>'from')::numeric,0),0);
      upper_bound:=case when nullif(bracket->>'to','') is null then null else (bracket->>'to')::numeric end;
      rate_value:=public.finance_effective_rate(coalesce((bracket->>'rate')::numeric,0));
      if taxable_amount>lower_bound then
        portion:=case when upper_bound is null then taxable_amount-lower_bound else greatest(least(taxable_amount,upper_bound)-lower_bound,0) end;
        total:=total+portion*rate_value;
      end if;
    end loop;
    total:=total+coalesce(r.fixed_amount,0);
  else
    total:=taxable_amount*public.finance_effective_rate(r.rate)+coalesce(r.fixed_amount,0);
  end if;
  return round(greatest(total,0),2);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_deactivate_accounts_staff(target_staff_id uuid, reason_text text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare linked uuid;
begin
 perform public.finance_require_access('finance_fees',true,array['system_admin']);
 select profile_id into linked from public.accounts_office_staff where id=target_staff_id and deleted_at is null;
 if not found then raise exception 'Accounts Office staff record was not found'; end if;
 update public.accounts_office_staff set active=false,deleted_at=now() where id=target_staff_id;
 if linked is not null then update public.profiles set active=false,updated_at=now() where id=linked and role='accounts_office'; end if;
 insert into public.audit_log(actor_id,table_name,record_id,action,reason) values(auth.uid(),'accounts_office_staff',target_staff_id,'FINANCE_STAFF_DEACTIVATED',coalesce(nullif(reason_text,''),'Accounts Office staff deactivated'));
 return true;
end $function$;

CREATE OR REPLACE FUNCTION public.finance_effective_rate(raw_rate numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$ select case when raw_rate is null then 0 when raw_rate>1 then raw_rate/100 else raw_rate end $function$;

CREATE OR REPLACE FUNCTION public.finance_feature_enabled(feature_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((public.license_effective_entitlement()->'plan'->'feature_flags'->>feature_code)::boolean,false)
$function$;

CREATE OR REPLACE FUNCTION public.finance_generate_invoice_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin
  select coalesce(
    nullif(upper(split_part(coalesce(tenant_code,''),'-',1)),''),
    nullif(regexp_replace(upper(coalesce(identifier_root,'')),'[^A-Z].*$','','g'),''),
    'SCH'
  ) into root
  from public.school_settings
  limit 1;
  n:=nextval('public.finance_invoice_seq');
  return root||'-INV-'||extract(year from current_date)::int||'-'||lpad(n::text,6,'0');
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_generate_payroll_number()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin select coalesce(nullif(identifier_root,''),regexp_replace(upper(school_name),'[^A-Z]','','g'),'SCH') into root from public.school_settings limit 1; n:=nextval('public.finance_payroll_no_seq'); return left(root,8)||'-PAY-'||lpad(n::text,6,'0'); end $function$;

CREATE OR REPLACE FUNCTION public.finance_generate_receipt_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin
  select coalesce(
    nullif(upper(split_part(coalesce(tenant_code,''),'-',1)),''),
    nullif(regexp_replace(upper(coalesce(identifier_root,'')),'[^A-Z].*$','','g'),''),
    'SCH'
  ) into root
  from public.school_settings
  limit 1;
  n:=nextval('public.finance_receipt_seq');
  return root||'-RCP-'||extract(year from current_date)::int||'-'||lpad(n::text,6,'0');
end $function$;

CREATE OR REPLACE FUNCTION public.finance_generate_staff_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin select coalesce(nullif(identifier_root,''),regexp_replace(upper(school_name),'[^A-Z]','','g'),'SCH') into root from public.school_settings limit 1; n:=nextval('public.accounts_office_staff_no_seq'); return left(root,8)||'AOS'||lpad(n::text,6,'0'); end $function$;

CREATE OR REPLACE FUNCTION public.finance_guardian_contact_history(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, search_text text DEFAULT NULL::text, page_number integer DEFAULT 1, page_size integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  page_no integer:=greatest(coalesce(page_number,1),1);
  size_no integer:=least(greatest(coalesce(page_size,100),1),200);
  query_value text:=lower(trim(coalesce(search_text,'')));
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  return jsonb_build_object(
    'total',(
      select count(*)
      from public.finance_guardian_contact_events e
      where (target_academic_year_id is null or e.academic_year_id=target_academic_year_id)
        and (target_term_id is null or e.term_id=target_term_id)
        and (query_value='' or lower(concat_ws(' ',e.guardian_name,e.guardian_phone,e.guardian_email,e.channel,e.message_text)) like '%'||query_value||'%')
    ),
    'rows',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at desc)
      from (
        select
          e.id,e.guardian_key,e.guardian_name,e.guardian_phone,e.guardian_email,
          e.channel,e.action_state,e.academic_year_id,y.name::text as academic_year_name,
          e.term_id,t.name::text as term_name,e.class_id,c.name::text as class_name,
          e.child_count,e.total_outstanding,e.children,e.message_text,e.created_at,
          coalesce(p.full_name,'Accountant') as actor_name
        from public.finance_guardian_contact_events e
        left join public.academic_years y on y.id=e.academic_year_id
        left join public.terms t on t.id=e.term_id
        left join public.classes c on c.id=e.class_id
        left join public.profiles p on p.id=e.created_by
        where (target_academic_year_id is null or e.academic_year_id=target_academic_year_id)
          and (target_term_id is null or e.term_id=target_term_id)
          and (query_value='' or lower(concat_ws(' ',e.guardian_name,e.guardian_phone,e.guardian_email,e.channel,e.message_text)) like '%'||query_value||'%')
        order by e.created_at desc
        limit size_no offset (page_no-1)*size_no
      ) q
    ),'[]'::jsonb)
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_guardian_follow_up(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, status_filter text DEFAULT 'outstanding'::text, search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  yid uuid;
  tid uuid;
  filter_value text:=lower(trim(coalesce(status_filter,'outstanding')));
  query_value text:=lower(trim(coalesce(search_text,'')));
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  if filter_value not in ('outstanding','partial_paid','unpaid','fully_paid','all') then
    raise exception 'Invalid payment status filter';
  end if;

  select y.id into yid
  from public.academic_years y
  where y.deleted_at is null
    and (target_academic_year_id is null or y.id=target_academic_year_id)
  order by case when y.id=target_academic_year_id then 0 else 1 end,y.is_active desc,y.start_date desc
  limit 1;

  if yid is null then
    return jsonb_build_object(
      'period',jsonb_build_object('academic_year_id',null,'academic_year_name',null,'term_id',null,'term_name',null),
      'metrics',jsonb_build_object('guardians',0,'children',0,'outstanding',0,'missing_phone',0,'missing_guardian_contact',0),
      'rows','[]'::jsonb
    );
  end if;

  select t.id into tid
  from public.terms t
  where t.academic_year_id=yid and t.deleted_at is null
    and (target_term_id is null or t.id=target_term_id)
  order by case when t.id=target_term_id then 0 else 1 end,t.is_active desc,t.sequence desc
  limit 1;

  return (
    with selected_enrollments as (
      select distinct on (e.student_id)
        e.student_id,e.class_id,e.academic_year_id,e.active,e.updated_at
      from public.enrollments e
      where e.academic_year_id=yid
        and e.deleted_at is null
        and (target_class_id is null or e.class_id=target_class_id)
      order by e.student_id,e.active desc,e.updated_at desc
    ),
    per_student as (
      select
        s.id as student_id,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) as student_name,
        s.admission_no::text as admission_no,
        nullif(trim(s.guardian_name),'') as guardian_name,
        nullif(trim(s.guardian_phone),'') as guardian_phone,
        nullif(trim(s.guardian_email),'') as guardian_email,
        c.id as class_id,
        c.name::text as class_name,
        c.level_order,
        coalesce(sum(b.term_fee_amount),0)::numeric as due,
        coalesce(sum(b.amount_paid),0)::numeric as paid,
        coalesce(sum(b.balance),0)::numeric as balance,
        case
          when count(b.id)=0 then 'not_configured'
          when coalesce(sum(b.balance),0)<=0 then 'fully_paid'
          when coalesce(sum(b.amount_paid),0)>0 then 'partial_paid'
          else 'unpaid'
        end as account_status
      from selected_enrollments e
      join public.students s on s.id=e.student_id and s.deleted_at is null
      join public.classes c on c.id=e.class_id and c.deleted_at is null
      left join public.finance_fee_account_balances b
        on b.student_id=s.id
       and b.academic_year_id=yid
       and b.term_id=tid
       and b.class_id=e.class_id
      group by s.id,s.first_name,s.middle_name,s.last_name,s.admission_no,s.guardian_name,s.guardian_phone,s.guardian_email,c.id,c.name,c.level_order
    ),
    tagged as (
      select p.*,
        case
          when regexp_replace(coalesce(p.guardian_phone,''),'[^0-9]','','g')<>'' then 'phone:'||regexp_replace(p.guardian_phone,'[^0-9]','','g')
          when nullif(lower(trim(coalesce(p.guardian_email,''))),'') is not null then 'email:'||lower(trim(p.guardian_email))
          else 'name:'||lower(trim(coalesce(p.guardian_name,'Parent / Guardian')))
        end as guardian_key
      from per_student p
      where p.guardian_name is not null or p.guardian_phone is not null or p.guardian_email is not null
    ),
    grouped as (
      select
        guardian_key,
        coalesce(max(guardian_name),'Parent / Guardian') as guardian_name,
        max(guardian_phone) as guardian_phone,
        max(guardian_email) as guardian_email,
        count(*)::integer as child_count,
        sum(greatest(balance,0))::numeric as total_outstanding,
        sum(due)::numeric as total_due,
        sum(paid)::numeric as total_paid,
        bool_or(balance>0) as has_outstanding,
        bool_or(account_status='partial_paid') as has_partial,
        bool_or(account_status='unpaid') as has_unpaid,
        bool_or(account_status='fully_paid') as has_fully_paid,
        bool_or(account_status='not_configured') as has_not_configured,
        lower(concat_ws(' ',
          coalesce(max(guardian_name),''),
          coalesce(max(guardian_phone),''),
          coalesce(max(guardian_email),''),
          string_agg(student_name||' '||coalesce(admission_no,'')||' '||class_name,' ')
        )) as search_blob,
        jsonb_agg(jsonb_build_object(
          'student_id',student_id,
          'student',student_name,
          'admission_no',admission_no,
          'class_id',class_id,
          'class_name',class_name,
          'due',due,
          'paid',paid,
          'balance',balance,
          'status',account_status
        ) order by level_order,student_name) as children
      from tagged
      group by guardian_key
    ),
    filtered as (
      select g.*,
        case
          when g.total_outstanding>0 then 'outstanding'
          when g.has_fully_paid then 'fully_paid'
          when g.has_not_configured then 'not_configured'
          else 'clear'
        end as group_status,
        (select e.created_at from public.finance_guardian_contact_events e where e.guardian_key=g.guardian_key order by e.created_at desc limit 1) as last_contact_at,
        (select e.channel from public.finance_guardian_contact_events e where e.guardian_key=g.guardian_key order by e.created_at desc limit 1) as last_contact_channel
      from grouped g
      where (query_value='' or g.search_blob like '%'||query_value||'%')
        and (
          filter_value='all'
          or (filter_value='outstanding' and g.has_outstanding)
          or (filter_value='partial_paid' and g.has_partial)
          or (filter_value='unpaid' and g.has_unpaid)
          or (filter_value='fully_paid' and g.has_fully_paid and not g.has_outstanding)
        )
    )
    select jsonb_build_object(
      'period',jsonb_build_object(
        'academic_year_id',yid,
        'academic_year_name',(select y.name::text from public.academic_years y where y.id=yid),
        'term_id',tid,
        'term_name',(select t.name::text from public.terms t where t.id=tid),
        'class_id',target_class_id,
        'class_name',(select c.name::text from public.classes c where c.id=target_class_id)
      ),
      'metrics',jsonb_build_object(
        'guardians',coalesce((select count(*) from filtered),0),
        'children',coalesce((select sum(child_count) from filtered),0),
        'outstanding',coalesce((select sum(total_outstanding) from filtered),0),
        'missing_phone',coalesce((select count(*) from filtered where guardian_phone is null),0),
        'missing_guardian_contact',coalesce((select count(*) from per_student where guardian_name is null and guardian_phone is null and guardian_email is null),0)
      ),
      'rows',coalesce((
        select jsonb_agg(jsonb_build_object(
          'guardian_key',f.guardian_key,
          'guardian_name',f.guardian_name,
          'guardian_phone',f.guardian_phone,
          'guardian_email',f.guardian_email,
          'child_count',f.child_count,
          'total_due',f.total_due,
          'total_paid',f.total_paid,
          'total_outstanding',f.total_outstanding,
          'status',f.group_status,
          'last_contact_at',f.last_contact_at,
          'last_contact_channel',f.last_contact_channel,
          'children',f.children
        ) order by f.total_outstanding desc,lower(f.guardian_name))
        from filtered f
      ),'[]'::jsonb)
    )
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_immutable_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='DELETE'
     and current_setting('edusentia.finance_test_purge',true)='on'
     and auth.uid() is not null
     and coalesce(public.current_app_role()::text,'')='system_admin' then
    return old;
  end if;
  raise exception 'Posted finance ledger rows are immutable. Use a reversal or adjustment.' using errcode='42501';
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_invoice_detail(target_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text:=public.current_app_role()::text;
  inv public.finance_fee_invoices%rowtype;
  allowed boolean:=false;
begin
  select * into inv from public.finance_fee_invoices where id=target_invoice_id;
  if inv.id is null then raise exception 'Invoice was not found'; end if;

  if r in ('accountant','system_admin') then
    perform public.finance_require_access('finance_statements',false,array['accountant','system_admin']);
    allowed:=true;
  elsif r='parent_guardian' then
    allowed:=exists(select 1 from public.guardian_links where auth_user_id=auth.uid() and student_id=inv.student_id);
  elsif r='student' then
    allowed:=exists(select 1 from public.students where id=inv.student_id and profile_id=auth.uid() and deleted_at is null);
  end if;
  if not allowed then raise exception 'Access denied' using errcode='42501'; end if;

  return jsonb_build_object(
    'school',coalesce((select jsonb_build_object('school_name',school_name,'motto',motto,'address',address,'phone',phone,'email',email,'website',website,'logo_url',logo_url,'tenant_code',tenant_code,'report_footer',report_footer) from public.school_settings limit 1),'{}'::jsonb),
    'invoice',jsonb_build_object('id',inv.id,'invoice_no',inv.invoice_no,'issued_at',inv.issued_at,'description',inv.description,'issued_amount',inv.issued_amount,'due_date',inv.due_date),
    'student',(select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)) from public.students s where s.id=inv.student_id),
    'account',(select jsonb_build_object('academic_year_name',y.name,'term_name',t.name,'class_name',c.name,'paid',b.amount_paid,'balance',b.balance,'status',b.status)
               from public.finance_fee_account_balances b join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id join public.classes c on c.id=b.class_id where b.id=inv.account_id),
    'allocations',coalesce((select jsonb_agg(jsonb_build_object('transaction_id',x.id,'entry_type',x.entry_type,'receipt_no',x.receipt_no,'transaction_date',x.transaction_date,'method',x.payment_method,'reference',x.payment_reference,'amount',a.amount,'notes',x.notes) order by x.transaction_date,x.created_at)
                            from public.finance_fee_allocations a join public.finance_fee_transactions x on x.id=a.transaction_id where a.account_id=inv.account_id),'[]'::jsonb)
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_invoice_register(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.finance_require_access('finance_fees',false,array['accountant','system_admin']);
  return jsonb_build_object(
    'rows',coalesce((
      select jsonb_agg(jsonb_build_object(
        'invoice_id',i.id,
        'invoice_no',i.invoice_no,
        'issued_at',i.issued_at,
        'description',i.description,
        'student_id',s.id,
        'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'admission_no',s.admission_no,
        'academic_year_id',b.academic_year_id,
        'academic_year_name',y.name,
        'term_id',b.term_id,
        'term_name',t.name,
        'class_id',b.class_id,
        'class_name',c.name,
        'issued_amount',i.issued_amount,
        'due_date',i.due_date,
        'paid',b.amount_paid,
        'balance',b.balance,
        'status',b.status
      ) order by y.start_date desc,t.sequence desc,c.level_order,c.name,s.last_name,s.first_name)
      from public.finance_fee_invoices i
      join public.finance_fee_account_balances b on b.id=i.account_id
      join public.students s on s.id=i.student_id
      join public.academic_years y on y.id=b.academic_year_id
      join public.terms t on t.id=b.term_id
      join public.classes c on c.id=b.class_id
      where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id)
        and (target_term_id is null or b.term_id=target_term_id)
        and (target_class_id is null or b.class_id=target_class_id)
    ),'[]'::jsonb)
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_loan_balance(target_loan_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select greatest(l.principal_amount-coalesce((select sum(pl.amount) from public.finance_payroll_item_lines pl join public.finance_payroll_items pi on pi.id=pl.payroll_item_id where pl.loan_id=l.id and pl.line_type='loan' and pi.payment_status='paid'),0),0)::numeric
 from public.finance_teacher_loans l where l.id=target_loan_id
$function$;

CREATE OR REPLACE FUNCTION public.finance_lock_payroll(target_run_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin perform public.finance_require_access('payroll',true); if not exists(select 1 from public.finance_payroll_runs where id=target_run_id and status='paid') then raise exception 'Only fully paid payroll can be locked'; end if; update public.finance_payroll_runs set status='locked',updated_at=now() where id=target_run_id; return true; end $function$;

CREATE OR REPLACE FUNCTION public.finance_log_guardian_contact(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  channel_value text:=lower(trim(coalesce(payload->>'channel','')));
  state_value text:=lower(trim(coalesce(payload->>'action_state','opened')));
  event_id uuid;
  guardian_name_value text:=trim(coalesce(payload->>'guardian_name',''));
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  if channel_value not in ('sms','whatsapp','call','copy') then
    raise exception 'Invalid contact channel';
  end if;
  if state_value not in ('opened','copied') then
    raise exception 'Invalid contact action state';
  end if;
  if nullif(trim(coalesce(payload->>'guardian_key','')),'') is null then
    raise exception 'Guardian reference is required';
  end if;
  if guardian_name_value='' then guardian_name_value:='Parent / Guardian'; end if;

  insert into public.finance_guardian_contact_events(
    guardian_key,guardian_name,guardian_phone,guardian_email,channel,action_state,
    academic_year_id,term_id,class_id,child_count,total_outstanding,children,message_text,created_by
  ) values (
    trim(payload->>'guardian_key'),
    guardian_name_value,
    nullif(trim(coalesce(payload->>'guardian_phone','')),''),
    nullif(trim(coalesce(payload->>'guardian_email','')),''),
    channel_value,
    state_value,
    nullif(payload->>'academic_year_id','')::uuid,
    nullif(payload->>'term_id','')::uuid,
    nullif(payload->>'class_id','')::uuid,
    greatest(coalesce((payload->>'child_count')::integer,0),0),
    coalesce((payload->>'total_outstanding')::numeric,0),
    case when jsonb_typeof(payload->'children')='array' then payload->'children' else '[]'::jsonb end,
    nullif(left(coalesce(payload->>'message_text',''),4000),''),
    auth.uid()
  ) returning id into event_id;

  return jsonb_build_object('id',event_id,'recorded',true,'created_at',now());
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_mark_salary_paid(target_item_id uuid, payment_reference_text text, payment_date_value date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare i public.finance_payroll_items%rowtype; r public.finance_payroll_runs%rowtype;
begin
  perform public.finance_require_payroll_access(true);
  if btrim(coalesce(payment_reference_text,''))='' then raise exception 'A salary payment reference is required'; end if;
  select * into i from public.finance_payroll_items where id=target_item_id;
  if i.id is null then raise exception 'Payroll item was not found'; end if;
  select * into r from public.finance_payroll_runs where id=i.run_id;
  if r.status not in ('approved','paid') then raise exception 'Payroll must be approved before salary payment'; end if;
  if i.payment_status='paid' then return to_jsonb(i); end if;
  update public.finance_payroll_items
  set payment_status='paid',paid_at=(coalesce(payment_date_value,current_date)::timestamp at time zone 'UTC'),payment_reference=btrim(payment_reference_text),updated_at=now()
  where id=target_item_id returning * into i;
  if not exists(select 1 from public.finance_payroll_items where run_id=i.run_id and payment_status<>'paid') then
    update public.finance_payroll_runs set status='paid',pay_date=coalesce(payment_date_value,current_date),updated_at=now() where id=i.run_id;
  end if;
  update public.finance_teacher_loans l set status='settled',updated_at=now()
  where l.teacher_id=i.teacher_id and l.status='active' and public.finance_loan_balance(l.id)<=0;
  insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason)
  values(auth.uid(),'finance_payroll_items',i.id,'SALARY_PAYMENT_RECORDED',jsonb_build_object('payment_reference',i.payment_reference,'paid_at',i.paid_at,'net_salary',i.net_salary),'Monthly salary payment recorded');
  return to_jsonb(i);
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_my_children_fees()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 if public.current_app_role()<>'parent_guardian' then raise exception 'Parent or guardian access required' using errcode='42501'; end if;
 if not public.finance_feature_enabled('finance_statements') then return jsonb_build_object('children','[]'::jsonb); end if;
 return jsonb_build_object('children',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'class_name',coalesce(c.name,''),'statement',public.finance_student_statement(s.id)) order by s.last_name,s.first_name) from public.guardian_links gl join public.students s on s.id=gl.student_id and s.deleted_at is null left join lateral(select e.class_id from public.enrollments e where e.student_id=s.id and e.active and e.deleted_at is null order by e.updated_at desc limit 1) ce on true left join public.classes c on c.id=ce.class_id where gl.auth_user_id=auth.uid()),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.finance_my_invoices()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r text:=public.current_app_role()::text;
begin
  if r not in ('parent_guardian','student') then raise exception 'Student or parent/guardian access required' using errcode='42501'; end if;
  if not public.finance_feature_enabled('finance_statements') then return jsonb_build_object('invoices','[]'::jsonb); end if;
  return jsonb_build_object(
    'invoices',coalesce((
      select jsonb_agg(jsonb_build_object(
        'invoice_id',i.id,'invoice_no',i.invoice_no,'issued_at',i.issued_at,'description',i.description,
        'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,
        'academic_year_name',y.name,'term_name',t.name,'class_name',c.name,
        'issued_amount',i.issued_amount,'due_date',i.due_date,'paid',b.amount_paid,'balance',b.balance,'status',b.status
      ) order by y.start_date desc,t.sequence desc,s.last_name,s.first_name)
      from public.finance_fee_invoices i
      join public.finance_fee_account_balances b on b.id=i.account_id
      join public.students s on s.id=i.student_id
      join public.academic_years y on y.id=i.academic_year_id
      join public.terms t on t.id=i.term_id
      join public.classes c on c.id=i.class_id
      where (r='student' and s.profile_id=auth.uid() and s.deleted_at is null)
         or (r='parent_guardian' and exists(select 1 from public.guardian_links gl where gl.auth_user_id=auth.uid() and gl.student_id=s.id))
    ),'[]'::jsonb)
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_payment_candidates(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('finance_fees',false,array['accountant']);
 return jsonb_build_object('students',coalesce((select jsonb_agg(jsonb_build_object('student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'account_id',b.id,'term_fee',coalesce(b.term_fee_amount,0),'paid',coalesce(b.amount_paid,0),'balance',coalesce(b.balance,0),'status',coalesce(b.status,'not_configured'),'total_outstanding',public.finance_student_outstanding(s.id)) order by s.last_name,s.first_name)
 from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null left join public.finance_fee_account_balances b on b.student_id=s.id and b.term_id=target_term_id where e.academic_year_id=target_academic_year_id and e.class_id=target_class_id and e.active and e.deleted_at is null),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.finance_payment_register(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rows_json jsonb; school_json jsonb;
begin
 perform public.finance_require_access('finance_fees',false,array['accountant']);
 select coalesce((
   with eligible as (
     select distinct tx.id
     from public.finance_fee_transactions tx
     join public.finance_fee_allocations al on al.transaction_id=tx.id
     join public.finance_fee_account_balances b on b.id=al.account_id
     where tx.entry_type='payment'
       and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id)
       and (target_term_id is null or b.term_id=target_term_id)
       and (target_class_id is null or b.class_id=target_class_id)
   ), receipt_rows as (
     select tx.id transaction_id,tx.receipt_no,tx.credit_amount transaction_amount,tx.student_id,
       concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student,s.admission_no,
       string_agg(distinct c.name::text,', ' order by c.name::text) class_name,
       string_agg(distinct y.name::text,', ' order by y.name::text) academic_year_name,
       string_agg(distinct t.name::text,', ' order by t.name::text) term_name,
       coalesce(sum(b.term_fee_amount),0) due,
       coalesce(sum(al.amount),0) allocated_paid,
       public.finance_student_outstanding(s.id) balance,
       case when public.finance_student_outstanding(s.id)<=0 then 'fully_paid' else 'partial_paid' end status,
       tx.payment_method method,tx.payment_reference reference,tx.transaction_date,
       coalesce(nullif(p.full_name,''),'Accounts Office') received_by,
       'accountant'::text received_by_role,
       coalesce(nullif(p.full_name,''),'System Administrator') recorded_by,
       coalesce(p.role::text,'system_admin') recorded_by_role,
       exists(select 1 from public.finance_fee_transactions rv where rv.reversal_of_id=tx.id) reversed,
       tx.created_at
     from eligible e
     join public.finance_fee_transactions tx on tx.id=e.id
     join public.students s on s.id=tx.student_id
     left join public.profiles p on p.id=tx.created_by
     join public.finance_fee_allocations al on al.transaction_id=tx.id
     join public.finance_fee_account_balances b on b.id=al.account_id
     join public.classes c on c.id=b.class_id
     join public.academic_years y on y.id=b.academic_year_id
     join public.terms t on t.id=b.term_id
     group by tx.id,tx.receipt_no,tx.credit_amount,tx.student_id,s.id,s.first_name,s.middle_name,s.last_name,s.admission_no,tx.payment_method,tx.payment_reference,tx.transaction_date,p.full_name,p.role,tx.created_at
   )
   select jsonb_agg(to_jsonb(r) order by r.transaction_date desc,r.created_at desc,r.student)
   from receipt_rows r
 ),'[]'::jsonb) into rows_json;
 select jsonb_build_object(
   'school_name',school_name,'motto',motto,'address',address,'phone',phone,'email',email,'website',website,
   'logo_url',logo_url,'tenant_code',tenant_code,'head_name',head_name,'report_footer',report_footer
 ) into school_json from public.school_settings limit 1;
 return jsonb_build_object('rows',rows_json,'school',coalesce(school_json,'{}'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.finance_payroll_console(target_year integer DEFAULT NULL::integer, target_month integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('payroll',false);
 return jsonb_build_object(
  'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'staff_no',t.staff_no,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'has_payroll_profile',exists(select 1 from public.finance_payroll_profiles p where p.teacher_id=t.id)) order by t.last_name,t.first_name) from public.teachers t where t.active and t.deleted_at is null),'[]'::jsonb),
  'salary_grades',coalesce((select jsonb_agg(to_jsonb(g) order by lower(g.code::text)) from public.finance_salary_grades g),'[]'::jsonb),
  'profiles',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no,'grade_code',g.code,'grade_salary',g.basic_salary) order by t.last_name,t.first_name) from public.finance_payroll_profiles p join public.teachers t on t.id=p.teacher_id left join public.finance_salary_grades g on g.id=p.salary_grade_id),'[]'::jsonb),
  'rules',case when public.finance_feature_enabled('payroll_statutory') then coalesce((select jsonb_agg(to_jsonb(r) order by r.rule_type,r.effective_from desc) from public.finance_payroll_rules r),'[]'::jsonb) else '[]'::jsonb end,
  'loans',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'remaining_balance',public.finance_loan_balance(l.id)) order by l.created_at desc) from public.finance_teacher_loans l join public.teachers t on t.id=l.teacher_id),'[]'::jsonb),
  'runs',coalesce((select jsonb_agg(to_jsonb(r) order by r.payroll_year desc,r.payroll_month desc) from public.finance_payroll_runs r where (target_year is null or r.payroll_year=target_year) and (target_month is null or r.payroll_month=target_month)),'[]'::jsonb),
  'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no,'payroll_number',p.payroll_number,'year',r.payroll_year,'month',r.payroll_month,'run_status',r.status,'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.line_type,l.description) from public.finance_payroll_item_lines l where l.payroll_item_id=i.id),'[]'::jsonb)) order by t.last_name,t.first_name) from public.finance_payroll_items i join public.finance_payroll_runs r on r.id=i.run_id join public.teachers t on t.id=i.teacher_id left join public.finance_payroll_profiles p on p.id=i.payroll_profile_id where (target_year is null or r.payroll_year=target_year) and (target_month is null or r.payroll_month=target_month)),'[]'::jsonb)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.finance_portal_account_candidates()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
 if public.current_app_role()<>'system_admin' then raise exception 'Access denied' using errcode='42501'; end if;
 perform public.finance_require_access('finance_fees',false,array['system_admin']);
 return jsonb_build_object(
   'accounts_staff',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('portal_email',u.email,'portal_active',p.active,'must_change_password',p.must_change_password) order by lower(a.full_name)) from public.accounts_office_staff a left join public.profiles p on p.id=a.profile_id left join auth.users u on u.id=a.profile_id where a.deleted_at is null),'[]'::jsonb),
   'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'profile_id',s.profile_id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'class_id',e.class_id,'class_name',c.name,'portal_email',u.email,'portal_active',p.active,'must_change_password',p.must_change_password) order by c.level_order,s.last_name,s.first_name) from public.students s left join lateral(select x.class_id from public.enrollments x where x.student_id=s.id and x.active and x.deleted_at is null order by x.updated_at desc limit 1)e on true left join public.classes c on c.id=e.class_id left join public.profiles p on p.id=s.profile_id left join auth.users u on u.id=s.profile_id where s.deleted_at is null and s.status='active'),'[]'::jsonb)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.finance_portal_report_detail(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid; h jsonb; rrole text:=public.current_app_role()::text;
begin
 if rrole not in ('student','parent_guardian') then raise exception 'Student or guardian access required' using errcode='42501'; end if;
 select e.student_id into sid from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.id=target_report_id and r.status='published' and r.deleted_at is null;
 if sid is null then raise exception 'Published report was not found'; end if;
 if rrole='student' and not exists(select 1 from public.students where id=sid and profile_id=auth.uid() and deleted_at is null) then raise exception 'Access denied' using errcode='42501'; end if;
 if rrole='parent_guardian' and not exists(select 1 from public.guardian_links where student_id=sid and auth_user_id=auth.uid() and can_view_reports) then raise exception 'Access denied' using errcode='42501'; end if;
 h:=public.finance_student_hold_status(sid); if coalesce((h->>'block_grade_details')::boolean,false) then return jsonb_build_object('locked',true,'hold',h,'report_id',target_report_id); end if;
 return jsonb_build_object('locked',false,'hold',h,
  'report',(select jsonb_build_object('id',r.id,'report_number',r.report_number,'status',r.status,'published_at',r.published_at,'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'class_name',c.name,'term_name',t.name,'academic_year_name',y.name,'teacher_comment',r.teacher_comment,'head_comment',r.head_comment,'attendance_present',r.attendance_present,'attendance_total',r.attendance_total,'position',public.report_position(r.id)) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id join public.students s on s.id=e.student_id join public.classes c on c.id=e.class_id join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id where r.id=target_report_id),
  'subjects',coalesce((select jsonb_agg(jsonb_build_object('subject_id',sub.id,'subject',sub.name,'total_score',sr.total_score,'grade',sr.grade,'remark',sr.remark,'grade_point',sr.grade_point,'teacher_initials',sr.teacher_initials) order by sub.display_order,sub.name) from public.subject_results sr join public.subjects sub on sub.id=sr.subject_id where sr.report_id=target_report_id),'[]'::jsonb),
  'average',coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=target_report_id),0)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.finance_post_adjustment(target_student_id uuid, target_account_id uuid, adjustment_type text, amount_value numeric, notes_text text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare txid uuid; debit numeric:=0; credit numeric:=0;
begin perform public.finance_require_access('finance_fees',true); perform public.finance_require_capability('fee_adjust'); if adjustment_type not in ('waiver','discount','refund','adjustment_debit','adjustment_credit') then raise exception 'Adjustment type is invalid'; end if; if amount_value<=0 or btrim(coalesce(notes_text,''))='' then raise exception 'A positive amount and reason are required'; end if; if not exists(select 1 from public.finance_fee_accounts where id=target_account_id and student_id=target_student_id) then raise exception 'Student fee account was not found'; end if; if adjustment_type in ('refund','adjustment_debit') then debit:=amount_value; else credit:=amount_value; end if; insert into public.finance_fee_transactions(student_id,entry_type,debit_amount,credit_amount,transaction_date,notes,created_by) values(target_student_id,adjustment_type,debit,credit,current_date,btrim(notes_text),auth.uid()) returning id into txid; insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(txid,target_account_id,amount_value); insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'finance_fee_transactions',txid,'FEE_ADJUSTMENT_POSTED',jsonb_build_object('type',adjustment_type,'amount',amount_value,'account_id',target_account_id),notes_text); return txid; end $function$;

CREATE OR REPLACE FUNCTION public.finance_protect_final_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='DELETE' then raise exception 'Payroll rows cannot be deleted; use a corrective run.' using errcode='42501'; end if;
  if old.payment_status='paid' and (new.* is distinct from old.*) then raise exception 'Paid payroll items are locked; use a corrective run.' using errcode='42501'; end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.finance_protect_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='DELETE' then
    raise exception 'Issued invoices cannot be deleted. Use a ledger adjustment or reversal.' using errcode='42501';
  end if;
  if new.id is distinct from old.id
     or new.account_id is distinct from old.account_id
     or new.invoice_no is distinct from old.invoice_no
     or new.student_id is distinct from old.student_id
     or new.academic_year_id is distinct from old.academic_year_id
     or new.term_id is distinct from old.term_id
     or new.class_id is distinct from old.class_id
     or new.issued_at is distinct from old.issued_at then
    raise exception 'Invoice identity is immutable.' using errcode='42501';
  end if;
  if new.* is distinct from old.* and exists(
    select 1 from public.finance_fee_allocations a where a.account_id=old.account_id
  ) then
    raise exception 'An invoice with posted ledger activity is locked. Use an adjustment instead.' using errcode='42501';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_record_payment(target_student_id uuid, target_account_id uuid, amount_value numeric, payment_method_text text, payment_reference_text text DEFAULT ''::text, payment_date_value date DEFAULT CURRENT_DATE, notes_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tx public.finance_fee_transactions%rowtype; acc record; selected record; remaining numeric:=amount_value; alloc numeric; receipt text; allocated numeric:=0;
begin
 perform public.finance_require_access('finance_fees',true); perform public.finance_require_capability('fee_collect');
 if amount_value is null or amount_value<=0 then raise exception 'Payment amount must be greater than zero'; end if;
 if payment_method_text not in ('cash','bank_transfer','mobile_money','cheque','card','other') then raise exception 'Select a valid payment method'; end if;
 select b.*,y.start_date,t.sequence into selected from public.finance_fee_account_balances b join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id where b.id=target_account_id and b.student_id=target_student_id;
 if selected.id is null then raise exception 'Student fee account was not found'; end if;
 perform pg_advisory_xact_lock(hashtextextended('finance_student_'||target_student_id::text,0)); receipt:=public.finance_generate_receipt_no();
 insert into public.finance_fee_transactions(student_id,entry_type,credit_amount,payment_method,payment_reference,receipt_no,transaction_date,notes,created_by) values(target_student_id,'payment',amount_value,payment_method_text,btrim(coalesce(payment_reference_text,'')),receipt,coalesce(payment_date_value,current_date),btrim(coalesce(notes_text,'')),auth.uid()) returning * into tx;
 for acc in select b.*,y.start_date,t.sequence from public.finance_fee_account_balances b join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id where b.student_id=target_student_id and (y.start_date<selected.start_date or (y.start_date=selected.start_date and t.sequence<=selected.sequence)) and b.balance>0 order by y.start_date,t.sequence,b.created_at loop exit when remaining<=0; alloc:=least(remaining,acc.balance); insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(tx.id,acc.id,alloc); remaining:=remaining-alloc; allocated:=allocated+alloc; end loop;
 if remaining>0 then insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(tx.id,target_account_id,remaining) on conflict(transaction_id,account_id) do update set amount=public.finance_fee_allocations.amount+excluded.amount; allocated:=allocated+remaining; end if;
 insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'finance_fee_transactions',tx.id,'FEE_PAYMENT_POSTED',jsonb_build_object('student_id',target_student_id,'amount',amount_value,'receipt_no',receipt,'method',payment_method_text),'Fee payment posted');
 return jsonb_build_object('transaction_id',tx.id,'receipt_no',receipt,'amount',amount_value,'allocated',allocated,'statement',public.finance_student_statement(target_student_id));
end $function$;

CREATE OR REPLACE FUNCTION public.finance_require_access(feature_code text, require_write boolean DEFAULT false, allowed_roles text[] DEFAULT ARRAY['accountant'::text, 'system_admin'::text])
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text:=public.current_app_role()::text;
  l jsonb;
begin
  if auth.uid() is null or r is null or not (r=any(allowed_roles)) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not public.finance_feature_enabled(feature_code) then
    raise exception 'This finance feature is not enabled by the current licence plan' using errcode='42501';
  end if;
  if r='accountant' and not exists(
    select 1 from public.accounts_office_staff a
    where a.profile_id=auth.uid() and a.active and a.deleted_at is null
  ) then
    raise exception 'Accountant directory record is not active' using errcode='42501';
  end if;

  if r in ('accountant','system_admin') then
    perform public.require_sensitive_access();
    if public.current_aal()<>'aal2' then
      raise exception 'Multi-factor authentication is required for Finance access' using errcode='42501';
    end if;
  end if;

  if r='accountant' then
    if feature_code in ('finance_fees','finance_statements') and not public.finance_staff_capability('finance_read') then
      raise exception 'Your Accounts Office permission does not allow Finance access' using errcode='42501';
    elsif feature_code='financial_holds' and not public.finance_staff_capability('financial_hold') then
      raise exception 'Your Accounts Office permission does not allow financial holds' using errcode='42501';
    elsif feature_code='payroll' and not public.finance_staff_capability('payroll') then
      raise exception 'Your Accounts Office permission does not allow payroll access' using errcode='42501';
    end if;
  end if;

  l:=public.license_snapshot_for_role(r);
  if coalesce((l->>'read_allowed')::boolean,false)<>true then
    raise exception 'Platform licence access is restricted' using errcode='42501';
  end if;
  if require_write and coalesce((l->>'write_allowed')::boolean,false)<>true then
    raise exception 'The current licence is read-only' using errcode='42501';
  end if;
  return r;
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_require_capability(capability text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin if not public.finance_staff_capability(capability) then raise exception 'Your Accounts Office permission does not allow this action' using errcode='42501'; end if; end $function$;

CREATE OR REPLACE FUNCTION public.finance_require_payroll_access(require_write boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin perform public.finance_require_access('payroll',require_write); perform public.finance_require_capability('payroll'); end $function$;

CREATE OR REPLACE FUNCTION public.finance_reverse_payment(target_transaction_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare original public.finance_fee_transactions%rowtype; rev public.finance_fee_transactions%rowtype; a record;
begin perform public.finance_require_access('finance_fees',true); perform public.finance_require_capability('fee_adjust'); if btrim(coalesce(reason_text,''))='' then raise exception 'A reversal reason is required'; end if; select * into original from public.finance_fee_transactions where id=target_transaction_id and entry_type='payment'; if original.id is null then raise exception 'Posted payment was not found'; end if; if exists(select 1 from public.finance_fee_transactions where reversal_of_id=original.id) then raise exception 'This payment has already been reversed'; end if; insert into public.finance_fee_transactions(student_id,entry_type,debit_amount,payment_method,payment_reference,reversal_of_id,transaction_date,notes,created_by) values(original.student_id,'payment_reversal',original.credit_amount,original.payment_method,original.payment_reference,original.id,current_date,btrim(reason_text),auth.uid()) returning * into rev; for a in select account_id,amount from public.finance_fee_allocations where transaction_id=original.id loop insert into public.finance_fee_allocations(transaction_id,account_id,amount) values(rev.id,a.account_id,a.amount); end loop; insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason) values(auth.uid(),'finance_fee_transactions',original.id,'FEE_PAYMENT_REVERSED',to_jsonb(original),to_jsonb(rev),reason_text); return jsonb_build_object('reversal_id',rev.id,'reversed_transaction_id',original.id,'statement',public.finance_student_statement(original.student_id)); end $function$;

CREATE OR REPLACE FUNCTION public.finance_save_accounts_staff(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); r public.accounts_office_staff%rowtype; staffno text; actor_role text;
begin
 actor_role:=public.finance_require_access('finance_fees',true,array['system_admin']);
 if btrim(coalesce(payload->>'full_name',''))='' then raise exception 'Full name is required'; end if;
 if rid is null then staffno:=public.finance_generate_staff_no();
   insert into public.accounts_office_staff(staff_no,full_name,phone,email,contact_address,job_title,finance_role,active,created_by)
   values(staffno,btrim(payload->>'full_name'),btrim(coalesce(payload->>'phone','')),nullif(btrim(coalesce(payload->>'email','')),''),btrim(coalesce(payload->>'contact_address','')),coalesce(nullif(btrim(payload->>'job_title'),''),'Accounts Office Staff'),coalesce(nullif(payload->>'finance_role',''),'accounts_officer'),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else
   update public.accounts_office_staff set full_name=btrim(payload->>'full_name'),phone=btrim(coalesce(payload->>'phone','')),email=nullif(btrim(coalesce(payload->>'email','')),''),contact_address=btrim(coalesce(payload->>'contact_address','')),job_title=coalesce(nullif(btrim(payload->>'job_title'),''),job_title),finance_role=coalesce(nullif(payload->>'finance_role',''),finance_role),active=coalesce((payload->>'active')::boolean,active) where id=rid and deleted_at is null returning * into r;
   if r.id is null then raise exception 'Accounts Office staff record was not found'; end if;
 end if;
 return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_save_fee_schedule(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
 rid uuid:=public.safe_uuid(payload->>'id');
 y uuid:=public.safe_uuid(payload->>'academic_year_id');
 tm uuid:=public.safe_uuid(payload->>'term_id');
 c uuid:=public.safe_uuid(payload->>'class_id');
 g uuid:=public.safe_uuid(payload->>'fee_group_id');
 amt numeric:=coalesce((payload->>'amount')::numeric,-1);
 due_date_value date:=public.safe_date(payload->>'due_date');
 description_value text:=coalesce(nullif(btrim(payload->>'description'),''),'Term fee');
 active_value boolean:=coalesce((payload->>'active')::boolean,true);
 r public.finance_fee_schedules%rowtype;
 class_record record;
 existing_allocations int;
 synced int:=0;
 synced_one int:=0;
 configured_count int:=0;
begin
 perform public.finance_require_access('finance_fees',true);
 perform public.finance_require_capability('fee_config');
 if y is null or tm is null or amt<0 or (g is null and c is null) then
   raise exception 'Academic year, term, fee group/class and valid fee amount are required';
 end if;
 if not exists(select 1 from public.terms t where t.id=tm and t.academic_year_id=y and t.deleted_at is null) then
   raise exception 'The selected term does not belong to the academic year';
 end if;

 if g is not null then
   if not exists(select 1 from public.finance_fee_groups x where x.id=g and x.active) then
     raise exception 'The selected fee group is unavailable';
   end if;
   if not exists(
     select 1 from public.finance_fee_group_classes m
     join public.classes x on x.id=m.class_id
     where m.fee_group_id=g and x.active and x.deleted_at is null
   ) then raise exception 'The selected fee group has no active classes'; end if;

   for class_record in
     select x.id as class_id,x.name
     from public.finance_fee_group_classes m
     join public.classes x on x.id=m.class_id
     where m.fee_group_id=g and x.active and x.deleted_at is null
     order by m.sort_order,x.level_order,x.name
   loop
     select count(*) into existing_allocations
     from public.finance_fee_accounts a
     join public.finance_fee_allocations al on al.account_id=a.id
     where a.academic_year_id=y and a.term_id=tm and a.class_id=class_record.class_id;
     if existing_allocations>0 and exists(
       select 1 from public.finance_fee_schedules x
       where x.academic_year_id=y and x.term_id=tm and x.class_id=class_record.class_id and x.amount<>amt
     ) then
       raise exception 'The fee for % already has posted transactions. Keep the original fee and use an adjustment instead.',class_record.name;
     end if;
   end loop;

   for class_record in
     select x.id as class_id
     from public.finance_fee_group_classes m
     join public.classes x on x.id=m.class_id
     where m.fee_group_id=g and x.active and x.deleted_at is null
     order by m.sort_order,x.level_order,x.name
   loop
     insert into public.finance_fee_schedules(academic_year_id,term_id,class_id,fee_group_id,amount,due_date,description,active,created_by)
     values(y,tm,class_record.class_id,g,amt,due_date_value,description_value,active_value,auth.uid())
     on conflict(academic_year_id,term_id,class_id) do update
       set fee_group_id=excluded.fee_group_id,
           amount=excluded.amount,
           due_date=excluded.due_date,
           description=excluded.description,
           active=excluded.active,
           updated_at=now()
     returning * into r;
     configured_count:=configured_count+1;
     if r.active then
       synced_one:=public.finance_sync_fee_accounts(r.id);
       synced:=synced+synced_one;
     end if;
   end loop;

   return jsonb_build_object(
     'fee_group_id',g,
     'classes_configured',configured_count,
     'accounts_synchronized',synced,
     'academic_year_id',y,
     'term_id',tm,
     'amount',amt,
     'due_date',due_date_value,
     'description',description_value,
     'active',active_value
   );
 end if;

 if not exists(select 1 from public.classes x where x.id=c and x.deleted_at is null and x.active) then
   raise exception 'The selected class is unavailable';
 end if;
 select count(*) into existing_allocations
 from public.finance_fee_accounts a
 join public.finance_fee_allocations al on al.account_id=a.id
 where a.academic_year_id=y and a.term_id=tm and a.class_id=c;
 if existing_allocations>0 and exists(
   select 1 from public.finance_fee_schedules x
   where x.academic_year_id=y and x.term_id=tm and x.class_id=c and x.amount<>amt
 ) then
   raise exception 'This fee already has posted transactions. Keep the original fee and use an adjustment instead.';
 end if;
 insert into public.finance_fee_schedules(academic_year_id,term_id,class_id,fee_group_id,amount,due_date,description,active,created_by)
 values(y,tm,c,null,amt,due_date_value,description_value,active_value,auth.uid())
 on conflict(academic_year_id,term_id,class_id) do update
   set fee_group_id=null,amount=excluded.amount,due_date=excluded.due_date,description=excluded.description,active=excluded.active,updated_at=now()
 returning * into r;
 if r.active then synced:=public.finance_sync_fee_accounts(r.id); end if;
 return to_jsonb(r)||jsonb_build_object('accounts_synchronized',synced);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_save_hold_policy(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare r public.finance_hold_policy%rowtype; begin perform public.finance_require_access('financial_holds',true); perform public.finance_require_capability('financial_hold'); update public.finance_hold_policy set enabled=coalesce((payload->>'enabled')::boolean,enabled),minimum_outstanding=coalesce((payload->>'minimum_outstanding')::numeric,minimum_outstanding),grace_days=coalesce((payload->>'grace_days')::int,grace_days),block_grade_details=coalesce((payload->>'block_grade_details')::boolean,block_grade_details),block_report_pdf=coalesce((payload->>'block_report_pdf')::boolean,block_report_pdf),block_transcript=coalesce((payload->>'block_transcript')::boolean,block_transcript),block_certificate=coalesce((payload->>'block_certificate')::boolean,block_certificate),updated_by=auth.uid() where id=1 returning * into r; return to_jsonb(r); end $function$;

CREATE OR REPLACE FUNCTION public.finance_save_payroll_profile(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); teacherid uuid:=public.safe_uuid(payload->>'teacher_id'); gradeid uuid:=public.safe_uuid(payload->>'salary_grade_id'); payrollno text; r public.finance_payroll_profiles%rowtype; override_amt numeric;
begin
 perform public.finance_require_access('payroll',true);
 if teacherid is null or not exists(select 1 from public.teachers where id=teacherid and deleted_at is null and active) then raise exception 'Select an active teacher'; end if;
 if gradeid is not null and not exists(select 1 from public.finance_salary_grades where id=gradeid and active) then raise exception 'Salary grade is unavailable'; end if;
 override_amt:=case when nullif(payload->>'basic_salary_override','') is null then null else (payload->>'basic_salary_override')::numeric end;
 if override_amt is not null and override_amt<0 then raise exception 'Salary override cannot be negative'; end if;
 if rid is null then payrollno:=coalesce(nullif(btrim(payload->>'payroll_number'),''),public.finance_generate_payroll_number());
   insert into public.finance_payroll_profiles(teacher_id,salary_grade_id,payroll_number,basic_salary_override,ssnit_number,tax_id,active,created_by)
   values(teacherid,gradeid,payrollno,override_amt,btrim(coalesce(payload->>'ssnit_number','')),btrim(coalesce(payload->>'tax_id','')),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else update public.finance_payroll_profiles set salary_grade_id=gradeid,payroll_number=coalesce(nullif(btrim(payload->>'payroll_number'),''),payroll_number),basic_salary_override=override_amt,ssnit_number=btrim(coalesce(payload->>'ssnit_number','')),tax_id=btrim(coalesce(payload->>'tax_id','')),active=coalesce((payload->>'active')::boolean,active) where id=rid and teacher_id=teacherid returning * into r; end if;
 if r.id is null then raise exception 'Payroll profile was not found'; end if; return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_save_payroll_rule(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); r public.finance_payroll_rules%rowtype; typ text:=btrim(coalesce(payload->>'rule_type','')); eff date:=public.safe_date(payload->>'effective_from'); endd date:=public.safe_date(payload->>'effective_to'); ratev numeric; fixedv numeric;
begin
 perform public.finance_require_access('payroll_statutory',true);
 if typ not in ('ssnit_employee','ssnit_employer','tax','allowance','deduction') or btrim(coalesce(payload->>'rule_code',''))='' or btrim(coalesce(payload->>'name',''))='' or eff is null then raise exception 'Rule code, type, name and effective date are required'; end if;
 ratev:=case when nullif(payload->>'rate','') is null then null else (payload->>'rate')::numeric end; fixedv:=case when nullif(payload->>'fixed_amount','') is null then null else (payload->>'fixed_amount')::numeric end;
 if coalesce(ratev,0)<0 or coalesce(fixedv,0)<0 or (endd is not null and endd<eff) then raise exception 'Payroll rule values are invalid'; end if;
 if rid is null then insert into public.finance_payroll_rules(rule_code,rule_type,name,rate,fixed_amount,rule_json,effective_from,effective_to,active,created_by) values(btrim(payload->>'rule_code'),typ,btrim(payload->>'name'),ratev,fixedv,coalesce(payload->'rule_json','{}'::jsonb),eff,endd,coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else update public.finance_payroll_rules set rule_code=btrim(payload->>'rule_code'),rule_type=typ,name=btrim(payload->>'name'),rate=ratev,fixed_amount=fixedv,rule_json=coalesce(payload->'rule_json',rule_json),effective_from=eff,effective_to=endd,active=coalesce((payload->>'active')::boolean,active) where id=rid returning * into r; end if;
 return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_save_salary_grade(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); r public.finance_salary_grades%rowtype; amt numeric:=coalesce((payload->>'basic_salary')::numeric,-1);
begin
 perform public.finance_require_access('payroll',true);
 if btrim(coalesce(payload->>'code',''))='' or btrim(coalesce(payload->>'name',''))='' or amt<0 then raise exception 'Grade code, name and a valid basic salary are required'; end if;
 if rid is null then insert into public.finance_salary_grades(code,name,basic_salary,active,created_by) values(btrim(payload->>'code'),btrim(payload->>'name'),amt,coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
 else update public.finance_salary_grades set code=btrim(payload->>'code'),name=btrim(payload->>'name'),basic_salary=amt,active=coalesce((payload->>'active')::boolean,active) where id=rid returning * into r; end if;
 return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.finance_save_teacher_loan(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id'); tid uuid:=public.safe_uuid(payload->>'teacher_id'); r public.finance_teacher_loans%rowtype; principal numeric:=coalesce((payload->>'principal_amount')::numeric,0); monthly numeric:=coalesce((payload->>'monthly_deduction')::numeric,0); ref text;
begin
 perform public.finance_require_access('payroll',true);
 if tid is null or principal<=0 or monthly<=0 or public.safe_date(payload->>'start_date') is null then raise exception 'Teacher, principal, monthly deduction and start date are required'; end if;
 if rid is null then ref:=coalesce(nullif(btrim(payload->>'reference_no'),''),'LOAN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)));
   insert into public.finance_teacher_loans(teacher_id,reference_no,principal_amount,monthly_deduction,start_date,status,notes,created_by) values(tid,ref,principal,monthly,public.safe_date(payload->>'start_date'),coalesce(nullif(payload->>'status',''),'active'),btrim(coalesce(payload->>'notes','')),auth.uid()) returning * into r;
 else if exists(select 1 from public.finance_payroll_item_lines l join public.finance_payroll_items i on i.id=l.payroll_item_id where l.loan_id=rid and i.payment_status='paid') and exists(select 1 from public.finance_teacher_loans x where x.id=rid and (x.principal_amount<>principal or x.monthly_deduction<>monthly)) then raise exception 'A loan with paid deductions cannot have its financial terms changed'; end if;
   update public.finance_teacher_loans set principal_amount=principal,monthly_deduction=monthly,start_date=public.safe_date(payload->>'start_date'),status=coalesce(nullif(payload->>'status',''),status),notes=btrim(coalesce(payload->>'notes','')) where id=rid and teacher_id=tid returning * into r; end if;
 return to_jsonb(r)||jsonb_build_object('remaining_balance',public.finance_loan_balance(r.id));
end $function$;

CREATE OR REPLACE FUNCTION public.finance_session_capabilities()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r text:=public.current_app_role()::text;
begin
  if r not in ('accountant','system_admin') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.finance_require_access('finance_fees',false,array['accountant','system_admin']);
  return jsonb_build_object(
    'finance_read',public.finance_staff_capability('finance_read'),
    'fee_collect',public.finance_staff_capability('fee_collect'),
    'fee_config',public.finance_staff_capability('fee_config'),
    'fee_adjust',public.finance_staff_capability('fee_adjust'),
    'financial_hold',public.finance_feature_enabled('financial_holds') and public.finance_staff_capability('financial_hold'),
    'payroll',public.finance_feature_enabled('payroll') and public.finance_staff_capability('payroll'),
    'manage_finance_staff',(r='system_admin')
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_set_hold_override(target_student_id uuid, mode_text text, reason_text text, ends_at_value timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare r public.finance_hold_overrides%rowtype; begin perform public.finance_require_access('financial_holds',true); perform public.finance_require_capability('financial_hold'); if mode_text not in ('force_lock','force_unlock') or btrim(coalesce(reason_text,''))='' then raise exception 'Lock/unlock action and reason are required'; end if; update public.finance_hold_overrides set active=false,updated_at=now() where student_id=target_student_id and active; insert into public.finance_hold_overrides(student_id,mode,reason,ends_at,created_by) values(target_student_id,mode_text,btrim(reason_text),ends_at_value,auth.uid()) returning * into r; return public.finance_student_hold_status(target_student_id)||jsonb_build_object('override_id',r.id); end $function$;

CREATE OR REPLACE FUNCTION public.finance_staff_capability(capability text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text:=public.current_app_role()::text;
  fr text;
begin
  if r='system_admin' then return true; end if;
  if r<>'accountant' then return false; end if;
  select a.finance_role into fr
  from public.accounts_office_staff a
  where a.profile_id=auth.uid() and a.active and a.deleted_at is null
  order by a.updated_at desc limit 1;
  if fr is null then return false; end if;
  return case fr
    when 'cashier' then capability in ('finance_read','fee_collect')
    when 'accounts_officer' then capability in ('finance_read','fee_collect')
    when 'accountant' then capability in ('finance_read','fee_collect','fee_config','fee_adjust','financial_hold','payroll')
    when 'payroll_officer' then capability in ('finance_read','payroll')
    when 'finance_manager' then capability in ('finance_read','fee_collect','fee_config','fee_adjust','financial_hold','payroll')
    else false
  end;
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_student_hold_status(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare p public.finance_hold_policy%rowtype; o public.finance_hold_overrides%rowtype; overdue numeric:=0; total_due numeric:=0; automatic boolean:=false; locked boolean:=false; reason text:='';
begin
  total_due:=public.finance_student_outstanding(target_student_id);
  select * into p from public.finance_hold_policy where id=1;
  if not public.finance_feature_enabled('financial_holds') then
    return jsonb_build_object('locked',false,'automatic',false,'outstanding',total_due,'reason','','block_grade_details',false,'block_report_pdf',false,'block_transcript',false,'block_certificate',false);
  end if;
  select coalesce(sum(greatest(b.balance,0)),0) into overdue
  from public.finance_fee_account_balances b
  where b.student_id=target_student_id and greatest(b.balance,0)>0
    and coalesce(b.due_date,current_date)+(coalesce(p.grace_days,0)||' days')::interval<now();
  automatic:=coalesce(p.enabled,false) and overdue>coalesce(p.minimum_outstanding,0);
  select * into o from public.finance_hold_overrides x where x.student_id=target_student_id and x.active and x.starts_at<=now() and (x.ends_at is null or x.ends_at>now()) order by x.created_at desc limit 1;
  if o.id is not null then locked:=o.mode='force_lock'; reason:=o.reason;
  else locked:=automatic; if automatic then reason:='Outstanding school fees require financial clearance.'; end if; end if;
  return jsonb_build_object('locked',locked,'automatic',automatic,'outstanding',total_due,'overdue',overdue,'reason',reason,
    'block_grade_details',locked and coalesce(p.block_grade_details,true),'block_report_pdf',locked and coalesce(p.block_report_pdf,true),
    'block_transcript',locked and coalesce(p.block_transcript,false),'block_certificate',locked and coalesce(p.block_certificate,false));
end $function$;

CREATE OR REPLACE FUNCTION public.finance_student_outstanding(target_student_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select coalesce(sum(greatest(balance,0)),0)::numeric from public.finance_fee_account_balances where student_id=target_student_id
$function$;

CREATE OR REPLACE FUNCTION public.finance_student_statement(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r text:=public.current_app_role()::text; allowed boolean:=false;
begin
  if r in ('accountant','system_admin') then
    perform public.finance_require_access('finance_statements',false,array['accountant','system_admin']); allowed:=true;
  elsif r='parent_guardian' then
    allowed:=exists(select 1 from public.guardian_links where auth_user_id=auth.uid() and student_id=target_student_id);
  elsif r='student' then
    allowed:=exists(select 1 from public.students where id=target_student_id and profile_id=auth.uid() and deleted_at is null);
  end if;
  if not allowed then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'school',coalesce((select jsonb_build_object('school_name',school_name,'motto',motto,'address',address,'phone',phone,'email',email,'website',website,'logo_url',logo_url,'tenant_code',tenant_code,'report_footer',report_footer) from public.school_settings limit 1),'{}'::jsonb),
    'student',(select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)) from public.students s where s.id=target_student_id),
    'outstanding',public.finance_student_outstanding(target_student_id),
    'hold',public.finance_student_hold_status(target_student_id),
    'accounts',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,
      'invoice_id',i.id,'invoice_no',i.invoice_no,'invoice_issued_at',i.issued_at,'invoice_amount',i.issued_amount,'invoice_description',i.description,
      'academic_year_id',b.academic_year_id,'academic_year_name',y.name,
      'term_id',b.term_id,'term_name',t.name,'class_id',b.class_id,'class_name',c.name,
      'term_fee',b.term_fee_amount,'due_date',b.due_date,'paid',b.amount_paid,'balance',b.balance,'status',b.status,'balance_remaining',b.balance_remaining
    ) order by y.start_date,t.sequence)
    from public.finance_fee_account_balances b
    join public.academic_years y on y.id=b.academic_year_id
    join public.terms t on t.id=b.term_id
    join public.classes c on c.id=b.class_id
    left join public.finance_fee_invoices i on i.account_id=b.id
    where b.student_id=target_student_id),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'receipt_no',x.receipt_no,'amount',x.credit_amount,'method',x.payment_method,'reference',x.payment_reference,'transaction_date',x.transaction_date,'notes',x.notes,'reversed',exists(select 1 from public.finance_fee_transactions r2 where r2.reversal_of_id=x.id)) order by x.transaction_date desc,x.created_at desc) from public.finance_fee_transactions x where x.student_id=target_student_id and x.entry_type='payment'),'[]'::jsonb)
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_sync_enrollment_fee_accounts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s record;
begin
  if new.active and new.deleted_at is null then
    for s in select * from public.finance_fee_schedules where academic_year_id=new.academic_year_id and class_id=new.class_id and active loop
      insert into public.finance_fee_accounts(student_id,enrollment_id,academic_year_id,term_id,class_id,schedule_id,term_fee_amount)
      values(new.student_id,new.id,new.academic_year_id,s.term_id,new.class_id,s.id,s.amount)
      on conflict(student_id,term_id) do nothing;
    end loop;
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.finance_sync_fee_accounts(target_schedule_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s public.finance_fee_schedules%rowtype; affected_count int:=0;
begin
 select * into s from public.finance_fee_schedules where id=target_schedule_id and active;
 if s.id is null then raise exception 'Fee schedule was not found'; end if;

 insert into public.finance_fee_accounts(student_id,enrollment_id,academic_year_id,term_id,class_id,schedule_id,term_fee_amount)
 select e.student_id,e.id,e.academic_year_id,s.term_id,e.class_id,s.id,s.amount
 from public.enrollments e
 join public.students st on st.id=e.student_id
 where e.academic_year_id=s.academic_year_id
   and e.class_id=s.class_id
   and e.active and e.deleted_at is null
   and st.deleted_at is null and st.status='active'
 on conflict(student_id,term_id) do update
 set enrollment_id=excluded.enrollment_id,
     academic_year_id=excluded.academic_year_id,
     class_id=excluded.class_id,
     schedule_id=excluded.schedule_id,
     term_fee_amount=excluded.term_fee_amount
 where not exists(
   select 1 from public.finance_fee_allocations al
   where al.account_id=finance_fee_accounts.id
 );
 get diagnostics affected_count=row_count;
 return affected_count;
end $function$;

CREATE OR REPLACE FUNCTION public.finance_sync_hr_staff_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  if new.teacher_id is not null then select id into new.hr_staff_member_id from public.hr_staff_members where source_type='teacher' and source_id=new.teacher_id; end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.finance_sync_invoice_from_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  inv_id uuid;
  due_value date;
  description_value text;
  schedule_value uuid;
begin
  select s.id,s.due_date,coalesce(nullif(btrim(s.description),''),'Term fee')
  into schedule_value,due_value,description_value
  from public.finance_fee_schedules s
  where s.id=new.schedule_id;

  description_value:=coalesce(description_value,'Term fee');
  select i.id into inv_id from public.finance_fee_invoices i where i.account_id=new.id;

  if inv_id is null then
    insert into public.finance_fee_invoices(
      account_id,invoice_no,student_id,academic_year_id,term_id,class_id,schedule_id,
      issued_amount,due_date,description,issued_at,created_by
    ) values(
      new.id,public.finance_generate_invoice_no(),new.student_id,new.academic_year_id,new.term_id,new.class_id,
      schedule_value,new.term_fee_amount,due_value,description_value,coalesce(new.created_at,now()),auth.uid()
    );
  else
    update public.finance_fee_invoices
    set schedule_id=schedule_value,
        issued_amount=new.term_fee_amount,
        due_date=due_value,
        description=description_value
    where id=inv_id
      and (schedule_id,issued_amount,due_date,description)
          is distinct from (schedule_value,new.term_fee_amount,due_value,description_value);
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.finance_teacher_salary_history()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid;
begin
 if public.current_app_role() not in ('class_teacher','subject_teacher') then raise exception 'Teacher access required' using errcode='42501'; end if;
 if not public.finance_feature_enabled('payroll') then return jsonb_build_object('teacher',null,'payments','[]'::jsonb); end if;
 select id into tid from public.teachers where profile_id=auth.uid() and active and deleted_at is null order by updated_at desc limit 1;
 if tid is null then return jsonb_build_object('teacher',null,'payments','[]'::jsonb); end if;
 return jsonb_build_object('teacher',(select jsonb_build_object('id',t.id,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no,'payroll_number',p.payroll_number) from public.teachers t left join public.finance_payroll_profiles p on p.teacher_id=t.id where t.id=tid),
 'payments',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('year',r.payroll_year,'month',r.payroll_month,'pay_date',r.pay_date,'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.line_type,l.description) from public.finance_payroll_item_lines l where l.payroll_item_id=i.id),'[]'::jsonb)) order by r.payroll_year desc,r.payroll_month desc) from public.finance_payroll_items i join public.finance_payroll_runs r on r.id=i.run_id where i.teacher_id=tid and i.payment_status='paid'),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.get_my_student_portal()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid; h jsonb;
begin
 if public.current_app_role()<>'student' then raise exception 'Student access required' using errcode='42501'; end if;
 select id into sid from public.students where profile_id=auth.uid() and deleted_at is null order by updated_at desc limit 1;
 if sid is null then return jsonb_build_object('linked',false,'student',null,'fee_statement',null,'reports','[]'::jsonb); end if;
 h:=public.finance_student_hold_status(sid);
 return jsonb_build_object('linked',true,
  'student',(select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'status',s.status,'class_name',coalesce(c.name,'')) from public.students s left join lateral(select e.class_id from public.enrollments e where e.student_id=s.id and e.active and e.deleted_at is null order by e.updated_at desc limit 1) ce on true left join public.classes c on c.id=ce.class_id where s.id=sid),
  'financial_hold',h,'fee_statement',public.finance_student_statement(sid),
  'reports',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'report_number',r.report_number,'term_name',t.name,'academic_year_name',y.name,'published_at',r.published_at,'locked',coalesce((h->>'block_grade_details')::boolean,false),'average',case when coalesce((h->>'block_grade_details')::boolean,false) then null else coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0) end,'publication',case when coalesce((h->>'block_report_pdf')::boolean,false) then null else (select jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at) from public.report_publications rp where rp.report_id=r.id and rp.revoked_at is null order by rp.published_at desc limit 1) end) order by y.start_date desc nulls last,t.sequence desc) from public.enrollments e join public.student_reports r on r.enrollment_id=e.id and r.status='published' and r.deleted_at is null join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id where e.student_id=sid and e.deleted_at is null),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.get_my_student_portal_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  sid uuid;
  current_enrollment_id uuid;
  current_class_id uuid;
  current_year_id uuid;
  current_roll_number integer;
  current_class_name text;
  current_year_name text;
  current_year_start date;
  current_term_id uuid;
  current_term_name text;
  current_term_sequence smallint;
  h jsonb;
  finance_enabled boolean:=public.license_feature_enabled('finance_statements');
  timetable_enabled boolean:=public.license_feature_enabled('timetable');
  attendance_enabled boolean:=public.license_feature_enabled('attendance');
  notifications_enabled boolean:=public.license_feature_enabled('notifications');
begin
  if public.current_app_role()::text<>'student' then
    raise exception 'Student access required' using errcode='42501';
  end if;

  select s.id into sid
  from public.students s
  where s.profile_id=auth.uid() and s.deleted_at is null
  order by s.updated_at desc
  limit 1;

  if sid is null then
    return jsonb_build_object(
      'linked',false,
      'student',null,
      'account',(select jsonb_build_object(
        'email',coalesce(auth.jwt()->>'email',''),
        'phone',p.phone,
        'mfa_required',p.mfa_required,
        'must_change_password',p.must_change_password,
        'last_seen_at',p.last_seen_at
      ) from public.profiles p where p.id=auth.uid()),
      'features',jsonb_build_object(
        'finance',finance_enabled,
        'timetable',timetable_enabled,
        'attendance',attendance_enabled,
        'notifications',notifications_enabled
      ),
      'fee_statement',null,
      'reports','[]'::jsonb,
      'attendance',null,
      'timetable',null,
      'notifications',jsonb_build_object('unread',0,'total',0,'recent','[]'::jsonb)
    );
  end if;

  select e.id,e.class_id,e.academic_year_id,e.roll_number,c.name::text,y.name::text,y.start_date
  into current_enrollment_id,current_class_id,current_year_id,current_roll_number,current_class_name,current_year_name,current_year_start
  from public.enrollments e
  join public.classes c on c.id=e.class_id and c.deleted_at is null
  join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
  where e.student_id=sid and e.deleted_at is null
  order by y.is_active desc,e.active desc,y.start_date desc,e.updated_at desc
  limit 1;

  if current_year_id is not null then
    select t.id,t.name::text,t.sequence
    into current_term_id,current_term_name,current_term_sequence
    from public.terms t
    where t.academic_year_id=current_year_id and t.deleted_at is null
    order by t.is_active desc,t.sequence desc
    limit 1;
  end if;

  h:=public.finance_student_hold_status(sid);

  return jsonb_build_object(
    'linked',true,
    'student',(select jsonb_build_object(
      'id',s.id,
      'admission_no',s.admission_no,
      'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
      'first_name',s.first_name,
      'middle_name',s.middle_name,
      'last_name',s.last_name,
      'gender',s.gender,
      'date_of_birth',s.date_of_birth,
      'status',s.status,
      'photo_url',s.photo_url,
      'guardian_name',s.guardian_name,
      'guardian_phone',s.guardian_phone,
      'guardian_email',s.guardian_email,
      'enrollment_id',current_enrollment_id,
      'class_id',current_class_id,
      'class_name',coalesce(current_class_name,''),
      'roll_number',current_roll_number,
      'academic_year_id',current_year_id,
      'academic_year_name',coalesce(current_year_name,''),
      'term_id',current_term_id,
      'term_name',coalesce(current_term_name,''),
      'class_teacher',(select concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
        from public.classes c
        left join public.teachers t on t.id=c.class_teacher_record_id and t.deleted_at is null
        where c.id=current_class_id)
    ) from public.students s where s.id=sid),
    'account',(select jsonb_build_object(
      'email',coalesce(auth.jwt()->>'email',''),
      'phone',p.phone,
      'mfa_required',p.mfa_required,
      'must_change_password',p.must_change_password,
      'last_seen_at',p.last_seen_at
    ) from public.profiles p where p.id=auth.uid()),
    'features',jsonb_build_object(
      'finance',finance_enabled,
      'timetable',timetable_enabled,
      'attendance',attendance_enabled,
      'notifications',notifications_enabled
    ),
    'financial_hold',h,
    'fee_statement',case when finance_enabled then public.finance_student_statement(sid) else null end,
    'reports',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'report_number',r.report_number,
        'term_name',t.name,
        'term_sequence',t.sequence,
        'academic_year_name',y.name,
        'academic_year_start',y.start_date,
        'published_at',r.published_at,
        'locked',coalesce((h->>'block_grade_details')::boolean,false),
        'average',case when coalesce((h->>'block_grade_details')::boolean,false) then null else coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0) end,
        'attendance_present',r.days_present,
        'attendance_total',r.days_school_opened,
        'publication',case when coalesce((h->>'block_report_pdf')::boolean,false) then null else (
          select jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at)
          from public.report_publications rp
          where rp.report_id=r.id and rp.revoked_at is null
          order by rp.published_at desc
          limit 1
        ) end
      ) order by y.start_date desc nulls last,t.sequence desc)
      from public.enrollments e
      join public.student_reports r on r.enrollment_id=e.id and r.status='published' and r.deleted_at is null
      join public.terms t on t.id=r.term_id
      join public.academic_years y on y.id=t.academic_year_id
      where e.student_id=sid and e.deleted_at is null
    ),'[]'::jsonb),
    'attendance',case when attendance_enabled and current_enrollment_id is not null then jsonb_build_object(
      'current',case when current_term_id is null then null else (
        select jsonb_build_object(
          'term_id',current_term_id,
          'term_name',current_term_name,
          'class_name',current_class_name,
          'days_opened',count(distinct r.id),
          'present',count(a.id) filter(where a.attendance_status='present'),
          'late',count(a.id) filter(where a.attendance_status='late'),
          'absent',count(a.id) filter(where a.attendance_status='absent'),
          'excused',count(a.id) filter(where a.attendance_status='excused'),
          'days_present',count(a.id) filter(where a.attendance_status in ('present','late')),
          'percentage',case when count(distinct r.id)>0 then round((count(a.id) filter(where a.attendance_status in ('present','late')))::numeric*100/count(distinct r.id),1) else 0 end
        )
        from public.class_attendance_registers r
        left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=current_enrollment_id
        where r.term_id=current_term_id and r.class_id=current_class_id
      ) end,
      'history',coalesce((
        select jsonb_agg(jsonb_build_object(
          'term_id',q.term_id,
          'term_name',q.term_name,
          'term_sequence',q.term_sequence,
          'academic_year_name',q.academic_year_name,
          'class_name',q.class_name,
          'days_opened',q.days_opened,
          'present',q.present,
          'late',q.late,
          'absent',q.absent,
          'excused',q.excused,
          'days_present',q.days_present,
          'percentage',q.percentage
        ) order by q.year_start desc,q.term_sequence desc)
        from (
          select
            t.id as term_id,
            t.name::text as term_name,
            t.sequence as term_sequence,
            y.name::text as academic_year_name,
            y.start_date as year_start,
            c.name::text as class_name,
            count(distinct r.id)::integer as days_opened,
            count(a.id) filter(where a.attendance_status='present')::integer as present,
            count(a.id) filter(where a.attendance_status='late')::integer as late,
            count(a.id) filter(where a.attendance_status='absent')::integer as absent,
            count(a.id) filter(where a.attendance_status='excused')::integer as excused,
            count(a.id) filter(where a.attendance_status in ('present','late'))::integer as days_present,
            case when count(distinct r.id)>0 then round((count(a.id) filter(where a.attendance_status in ('present','late')))::numeric*100/count(distinct r.id),1) else 0 end as percentage
          from public.enrollments e
          join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
          join public.classes c on c.id=e.class_id and c.deleted_at is null
          join public.terms t on t.academic_year_id=e.academic_year_id and t.deleted_at is null
          left join public.class_attendance_registers r on r.term_id=t.id and r.class_id=e.class_id
          left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=e.id
          where e.student_id=sid and e.deleted_at is null
          group by t.id,t.name,t.sequence,y.name,y.start_date,c.name
        ) q
      ),'[]'::jsonb)
    ) else null end,
    'timetable',case when timetable_enabled and current_year_id is not null and current_class_id is not null then jsonb_build_object(
      'academic_year_id',current_year_id,
      'academic_year_name',current_year_name,
      'class_id',current_class_id,
      'class_name',current_class_name,
      'entries',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',e.id,
          'day_of_week',e.day_of_week,
          'period_start',e.period_start,
          'period_end',e.period_end,
          'subject_id',e.subject_id,
          'subject_name',s.name,
          'teacher_id',e.teacher_id,
          'teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
          'notes',e.notes
        ) order by array_position(array['Monday','Tuesday','Wednesday','Thursday','Friday'],e.day_of_week),e.period_start)
        from public.class_timetable_entries e
        join public.subjects s on s.id=e.subject_id and s.deleted_at is null
        join public.teachers t on t.id=e.teacher_id and t.deleted_at is null
        where e.academic_year_id=current_year_id and e.class_id=current_class_id and e.active
          and e.day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday')
      ),'[]'::jsonb)
    ) else null end,
    'notifications',case when notifications_enabled then jsonb_build_object(
      'unread',(select count(*) from public.notifications n where n.recipient_id=auth.uid() and n.read_at is null),
      'total',(select count(*) from public.notifications n where n.recipient_id=auth.uid()),
      'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
        select n.id,n.title,n.body,n.category,n.entity_type,n.entity_id,n.read_at,n.created_at
        from public.notifications n
        where n.recipient_id=auth.uid()
        order by n.created_at desc
        limit 8
      ) q),'[]'::jsonb)
    ) else jsonb_build_object('unread',0,'total',0,'recent','[]'::jsonb) end
  );
end
$function$;

drop trigger if exists accounts_office_staff_audit on public.accounts_office_staff;
CREATE TRIGGER accounts_office_staff_audit AFTER INSERT OR DELETE OR UPDATE ON public.accounts_office_staff FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists accounts_office_staff_set_updated_at on public.accounts_office_staff;
CREATE TRIGGER accounts_office_staff_set_updated_at BEFORE UPDATE ON public.accounts_office_staff FOR EACH ROW EXECUTE FUNCTION set_updated_at();
drop trigger if exists finance_fee_accounts_invoice_sync on public.finance_fee_accounts;
CREATE TRIGGER finance_fee_accounts_invoice_sync AFTER INSERT OR UPDATE OF schedule_id, term_fee_amount, student_id, academic_year_id, term_id, class_id ON public.finance_fee_accounts FOR EACH ROW EXECUTE FUNCTION finance_sync_invoice_from_account();
drop trigger if exists finance_fee_allocations_immutable on public.finance_fee_allocations;
CREATE TRIGGER finance_fee_allocations_immutable BEFORE DELETE OR UPDATE ON public.finance_fee_allocations FOR EACH ROW EXECUTE FUNCTION finance_immutable_row();
drop trigger if exists finance_fee_invoices_audit on public.finance_fee_invoices;
CREATE TRIGGER finance_fee_invoices_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_fee_invoices FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_fee_invoices_protect on public.finance_fee_invoices;
CREATE TRIGGER finance_fee_invoices_protect BEFORE DELETE OR UPDATE ON public.finance_fee_invoices FOR EACH ROW EXECUTE FUNCTION finance_protect_invoice();
drop trigger if exists finance_fee_schedules_audit on public.finance_fee_schedules;
CREATE TRIGGER finance_fee_schedules_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_fee_schedules FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_fee_schedules_set_updated_at on public.finance_fee_schedules;
CREATE TRIGGER finance_fee_schedules_set_updated_at BEFORE UPDATE ON public.finance_fee_schedules FOR EACH ROW EXECUTE FUNCTION set_updated_at();
drop trigger if exists finance_fee_transactions_immutable on public.finance_fee_transactions;
CREATE TRIGGER finance_fee_transactions_immutable BEFORE DELETE OR UPDATE ON public.finance_fee_transactions FOR EACH ROW EXECUTE FUNCTION finance_immutable_row();
drop trigger if exists finance_payroll_item_lines_audit on public.finance_payroll_item_lines;
CREATE TRIGGER finance_payroll_item_lines_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_payroll_item_lines FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_payroll_items_audit on public.finance_payroll_items;
CREATE TRIGGER finance_payroll_items_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_payroll_items FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_payroll_items_protect_final on public.finance_payroll_items;
CREATE TRIGGER finance_payroll_items_protect_final BEFORE DELETE OR UPDATE ON public.finance_payroll_items FOR EACH ROW EXECUTE FUNCTION finance_protect_final_payroll();
drop trigger if exists finance_payroll_items_set_updated_at on public.finance_payroll_items;
CREATE TRIGGER finance_payroll_items_set_updated_at BEFORE UPDATE ON public.finance_payroll_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();
drop trigger if exists finance_payroll_profiles_audit on public.finance_payroll_profiles;
CREATE TRIGGER finance_payroll_profiles_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_payroll_profiles FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_payroll_profiles_set_updated_at on public.finance_payroll_profiles;
CREATE TRIGGER finance_payroll_profiles_set_updated_at BEFORE UPDATE ON public.finance_payroll_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
drop trigger if exists finance_payroll_rules_audit on public.finance_payroll_rules;
CREATE TRIGGER finance_payroll_rules_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_payroll_rules FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_payroll_rules_set_updated_at on public.finance_payroll_rules;
CREATE TRIGGER finance_payroll_rules_set_updated_at BEFORE UPDATE ON public.finance_payroll_rules FOR EACH ROW EXECUTE FUNCTION set_updated_at();
drop trigger if exists finance_payroll_runs_audit on public.finance_payroll_runs;
CREATE TRIGGER finance_payroll_runs_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_payroll_runs FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_payroll_runs_set_updated_at on public.finance_payroll_runs;
CREATE TRIGGER finance_payroll_runs_set_updated_at BEFORE UPDATE ON public.finance_payroll_runs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
drop trigger if exists finance_salary_grades_audit on public.finance_salary_grades;
CREATE TRIGGER finance_salary_grades_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_salary_grades FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_salary_grades_set_updated_at on public.finance_salary_grades;
CREATE TRIGGER finance_salary_grades_set_updated_at BEFORE UPDATE ON public.finance_salary_grades FOR EACH ROW EXECUTE FUNCTION set_updated_at();
drop trigger if exists finance_teacher_loans_audit on public.finance_teacher_loans;
CREATE TRIGGER finance_teacher_loans_audit AFTER INSERT OR DELETE OR UPDATE ON public.finance_teacher_loans FOR EACH ROW EXECUTE FUNCTION audit_row_change();
drop trigger if exists finance_teacher_loans_set_updated_at on public.finance_teacher_loans;
CREATE TRIGGER finance_teacher_loans_set_updated_at BEFORE UPDATE ON public.finance_teacher_loans FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Worker access remains function-only. The certified RPC registry is the public API allowlist.
do $grant$
declare r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (p.proname like 'finance_%'
           or p.proname like 'admin_%accounts_staff%'
           or p.proname in ('get_my_student_portal','get_my_student_portal_v2'))
  loop
    execute format('revoke all on function %s from public,anon,authenticated',r.signature);
    execute format('grant execute on function %s to service_role',r.signature);
    execute format('grant execute on function %s to edusentia_worker_runtime',r.signature);
  end loop;
end
$grant$;

insert into app.schema_migrations(version)
values ('0049a_operational_finance_reference')
on conflict do nothing;

commit;
