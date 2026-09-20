-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Columns, constraints, and indexes extracted read-only from the stable edition.

begin;

-- Certified teacher/principal record contract extracted read-only from the
-- stable Supabase edition. These tables live only inside an isolated school DB.
-- Direct Worker table access is intentionally denied; certified functions are
-- the application boundary.

create table if not exists public.teachers(
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  staff_no citext not null,
  first_name text not null,
  middle_name text not null default '',
  last_name text not null,
  gender text not null default 'Other' check(gender in('Male','Female','Other')),
  phone text not null default '',
  email citext,
  address text not null default '',
  qualification text not null default '',
  specialization text not null default '',
  date_joined date,
  employment_status text not null default 'active' check(employment_status in('active','leave','suspended','resigned','retired')),
  notes text not null default '',
  active boolean not null default true,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  emis_code citext,
  date_of_birth date,
  photo_url text not null default ''
);

create table if not exists public.headteachers(
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  staff_no citext not null,
  first_name text not null,
  middle_name text not null default '',
  last_name text not null,
  gender text not null default 'Other' check(gender in('Male','Female','Other')),
  phone text not null default '',
  email citext,
  address text not null default '',
  qualification text not null default '',
  date_appointed date,
  employment_status text not null default 'active' check(employment_status in('active','leave','suspended','resigned','retired')),
  notes text not null default '',
  active boolean not null default true,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  signature_path text not null default '',
  signature_updated_at timestamptz,
  photo_url text not null default ''
);

create unique index if not exists teachers_emis_code_ci_idx
  on public.teachers(lower(emis_code::text))
  where emis_code is not null and btrim(emis_code::text)<>'' and deleted_at is null;
create index if not exists teachers_name_search_idx
  on public.teachers(lower(last_name),lower(first_name)) where deleted_at is null;
create unique index if not exists teachers_profile_active_idx
  on public.teachers(profile_id) where profile_id is not null and deleted_at is null;
create unique index if not exists teachers_staff_no_ci_idx
  on public.teachers(lower(staff_no::text)) where deleted_at is null;
create index if not exists teachers_status_idx
  on public.teachers(employment_status,active) where deleted_at is null;

create index if not exists headteachers_name_search_idx
  on public.headteachers(lower(last_name),lower(first_name)) where deleted_at is null;
create unique index if not exists headteachers_one_current_principal_idx
  on public.headteachers((1)) where deleted_at is null and active and employment_status='active';
create unique index if not exists headteachers_profile_active_idx
  on public.headteachers(profile_id) where profile_id is not null and deleted_at is null;
create unique index if not exists headteachers_staff_no_ci_idx
  on public.headteachers(lower(staff_no::text)) where deleted_at is null;
create index if not exists headteachers_status_idx
  on public.headteachers(employment_status,active) where deleted_at is null;

drop trigger if exists teachers_set_updated_at on public.teachers;
create trigger teachers_set_updated_at
before update on public.teachers
for each row execute function public.set_updated_at();

drop trigger if exists headteachers_set_updated_at on public.headteachers;
create trigger headteachers_set_updated_at
before update on public.headteachers
for each row execute function public.set_updated_at();

alter table public.teachers enable row level security;
alter table public.teachers force row level security;
alter table public.headteachers enable row level security;
alter table public.headteachers force row level security;

revoke all on table public.teachers from public;
revoke all on table public.headteachers from public;
revoke all on table public.teachers from edusentia_worker_runtime;
revoke all on table public.headteachers from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0030b_certified_teacher_principal_records')
on conflict do nothing;

commit;
