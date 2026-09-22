begin;

create sequence if not exists public.hr_staff_no_seq start with 1 increment by 1;

create table if not exists public.hr_staff_members (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  source_type text not null default 'other' check (source_type in ('teacher','principal','accounts_office','other')),
  source_id uuid,
  staff_no text not null,
  first_name text not null,
  middle_name text,
  last_name text not null default '',
  gender text,
  date_of_birth date,
  email text,
  phone text,
  address text,
  department text,
  job_title text,
  employment_type text not null default 'permanent' check (employment_type in ('permanent','contract','temporary','part_time','intern','volunteer','other')),
  employment_status text not null default 'active' check (employment_status in ('active','probation','leave','suspended','resigned','terminated','retired','inactive')),
  date_joined date,
  date_ended date,
  qualification text,
  specialization text,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relation text,
  notes text,
  active boolean not null default true,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hr_staff_members_source_unique unique (source_type, source_id),
  constraint hr_staff_members_staff_no_unique unique (staff_no),
  constraint hr_staff_members_profile_unique unique (profile_id),
  constraint hr_staff_members_dates_ck check (date_ended is null or date_joined is null or date_ended >= date_joined)
);

create index if not exists hr_staff_members_active_idx on public.hr_staff_members(active, employment_status) where deleted_at is null;
create index if not exists hr_staff_members_department_idx on public.hr_staff_members(department) where deleted_at is null;
create index if not exists hr_staff_members_name_idx on public.hr_staff_members(lower(first_name), lower(last_name)) where deleted_at is null;

create table if not exists public.hr_staff_qualifications (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.hr_staff_members(id) on delete restrict,
  qualification text not null,
  institution text,
  field_of_study text,
  awarded_on date,
  expires_on date,
  verification_status text not null default 'unverified' check (verification_status in ('unverified','verified','rejected','expired')),
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hr_staff_qualification_dates_ck check (expires_on is null or awarded_on is null or expires_on >= awarded_on)
);
create index if not exists hr_staff_qualifications_staff_idx on public.hr_staff_qualifications(staff_id, created_at desc);

create table if not exists public.hr_staff_documents (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.hr_staff_members(id) on delete restrict,
  document_type text not null,
  title text not null,
  reference_no text,
  issued_on date,
  expires_on date,
  storage_path text,
  verification_status text not null default 'unverified' check (verification_status in ('unverified','verified','rejected','expired')),
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hr_staff_document_dates_ck check (expires_on is null or issued_on is null or expires_on >= issued_on)
);
create index if not exists hr_staff_documents_staff_idx on public.hr_staff_documents(staff_id, created_at desc);
create index if not exists hr_staff_documents_expiry_idx on public.hr_staff_documents(expires_on) where expires_on is not null;

create table if not exists public.hr_leave_requests (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.hr_staff_members(id) on delete restrict,
  leave_type text not null check (leave_type in ('annual','sick','maternity','paternity','study','compassionate','unpaid','official_duty','other')),
  start_date date not null,
  end_date date not null,
  days numeric(8,2) not null,
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  submitted_by uuid references public.profiles(id) on delete set null,
  submitted_at timestamptz not null default now(),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz,
  decision_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hr_leave_request_dates_ck check (end_date >= start_date),
  constraint hr_leave_request_days_ck check (days > 0)
);
create index if not exists hr_leave_requests_staff_idx on public.hr_leave_requests(staff_id, start_date desc);
create index if not exists hr_leave_requests_status_idx on public.hr_leave_requests(status, start_date desc);

create table if not exists public.hr_employment_events (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.hr_staff_members(id) on delete restrict,
  event_type text not null,
  event_date date not null default current_date,
  details jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists hr_employment_events_staff_idx on public.hr_employment_events(staff_id, event_date desc, created_at desc);

alter table public.hr_staff_members enable row level security;
alter table public.hr_staff_qualifications enable row level security;
alter table public.hr_staff_documents enable row level security;
alter table public.hr_leave_requests enable row level security;
alter table public.hr_employment_events enable row level security;

revoke all on table public.hr_staff_members, public.hr_staff_qualifications, public.hr_staff_documents, public.hr_leave_requests, public.hr_employment_events from public, anon, authenticated;
revoke all on sequence public.hr_staff_no_seq from public, anon, authenticated;
grant all on table public.hr_staff_members, public.hr_staff_qualifications, public.hr_staff_documents, public.hr_leave_requests, public.hr_employment_events to service_role;
grant usage, select, update on sequence public.hr_staff_no_seq to service_role;

create or replace function public.hr_generate_staff_no()
returns text language plpgsql security definer
set search_path to 'public','pg_catalog','extensions'
as $$
declare root text; n bigint; candidate text;
begin
  select coalesce(nullif(regexp_replace(upper(identifier_root),'[^A-Z0-9]','','g'),''),nullif(regexp_replace(upper(school_name),'[^A-Z]','','g'),''),'SCH') into root from public.school_settings limit 1;
  root:=left(root,8);
  loop
    n:=nextval('public.hr_staff_no_seq'); candidate:=root||lpad(n::text,6,'0');
    exit when not exists(select 1 from public.hr_staff_members where staff_no=candidate)
      and not exists(select 1 from public.teachers where staff_no::text=candidate)
      and not exists(select 1 from public.headteachers where staff_no::text=candidate)
      and not exists(select 1 from public.accounts_office_staff where staff_no::text=candidate);
  end loop;
  return candidate;
end $$;

create or replace function public.hr_require_access(require_write boolean default false, allowed_roles text[] default array['system_admin','principal'])
returns text language plpgsql stable security definer
set search_path to 'public','pg_catalog','extensions'
as $$
declare v_role text; v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_role:=public.current_app_role()::text;
  if v_role is null or not (v_role=any(allowed_roles)) then raise exception 'HR access is not allowed for this role' using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'HR access is unavailable while the school licence is locked' using errcode='42501'; end if;
  if require_write and not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'HR changes are unavailable while the school licence is read-only' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required for Staff & HR' using errcode='42501'; end if;
  return v_role;
end $$;

create or replace function public.hr_block_delete()
returns trigger language plpgsql security definer
set search_path to 'public','pg_catalog','extensions'
as $$
begin
  if current_setting('app.hr_allow_hard_delete',true)='on' then return old; end if;
  raise exception 'HR history cannot be hard deleted; use lifecycle status or cancellation instead' using errcode='42501';
end $$;

create or replace function public.hr_touch_updated_at()
returns trigger language plpgsql set search_path to 'public','pg_catalog' as $$ begin new.updated_at:=now(); return new; end $$;

create or replace function public.hr_record_staff_lifecycle()
returns trigger language plpgsql security definer
set search_path to 'public','pg_catalog','extensions'
as $$
begin
  if tg_op='INSERT' then
    insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by)
    values(new.id,'staff_created',coalesce(new.date_joined,current_date),jsonb_build_object('employment_status',new.employment_status,'source_type',new.source_type),coalesce(auth.uid(),new.created_by));
  elsif tg_op='UPDATE' then
    if old.employment_status is distinct from new.employment_status then
      insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by)
      values(new.id,'employment_status_changed',current_date,jsonb_build_object('from',old.employment_status,'to',new.employment_status),auth.uid());
    end if;
    if old.job_title is distinct from new.job_title or old.department is distinct from new.department then
      insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by)
      values(new.id,'assignment_changed',current_date,jsonb_build_object('job_title_from',old.job_title,'job_title_to',new.job_title,'department_from',old.department,'department_to',new.department),auth.uid());
    end if;
  end if;
  return null;
end $$;

create or replace function public.hr_sync_staff_from_source()
returns trigger language plpgsql security definer
set search_path to 'public','pg_catalog','extensions'
as $$
declare
  v_type text; v_source_id uuid; v_profile_id uuid; v_staff_no text; v_first text; v_middle text; v_last text; v_gender text; v_dob date;
  v_email text; v_phone text; v_address text; v_job text; v_status text; v_joined date; v_qualification text; v_specialization text; v_active boolean; v_deleted timestamptz;
begin
  if tg_op='DELETE' then
    v_type:=case tg_table_name when 'teachers' then 'teacher' when 'headteachers' then 'principal' when 'accounts_office_staff' then 'accounts_office' else null end;
    if v_type is not null then update public.hr_staff_members set active=false,employment_status='inactive',deleted_at=coalesce(deleted_at,now()),updated_at=now() where source_type=v_type and source_id=old.id; end if;
    return old;
  end if;
  if tg_table_name='teachers' then
    v_type:='teacher'; v_source_id:=new.id; v_profile_id:=new.profile_id; v_staff_no:=new.staff_no::text; v_first:=new.first_name; v_middle:=new.middle_name; v_last:=new.last_name; v_gender:=new.gender; v_dob:=new.date_of_birth;
    v_email:=new.email::text; v_phone:=new.phone; v_address:=new.address; v_job:='Teacher'; v_status:=coalesce(new.employment_status,'active'); v_joined:=new.date_joined; v_qualification:=new.qualification; v_specialization:=new.specialization; v_active:=coalesce(new.active,true); v_deleted:=new.deleted_at;
  elsif tg_table_name='headteachers' then
    v_type:='principal'; v_source_id:=new.id; v_profile_id:=new.profile_id; v_staff_no:=new.staff_no::text; v_first:=new.first_name; v_middle:=new.middle_name; v_last:=new.last_name; v_gender:=new.gender; v_dob:=null;
    v_email:=new.email::text; v_phone:=new.phone; v_address:=new.address; v_job:='Principal'; v_status:=coalesce(new.employment_status,'active'); v_joined:=new.date_appointed; v_qualification:=new.qualification; v_specialization:=null; v_active:=coalesce(new.active,true); v_deleted:=new.deleted_at;
  elsif tg_table_name='accounts_office_staff' then
    v_type:='accounts_office'; v_source_id:=new.id; v_profile_id:=new.profile_id; v_staff_no:=new.staff_no::text; v_first:=coalesce(nullif(new.full_name,''),'Accounts Office Staff'); v_middle:=null; v_last:=''; v_gender:=null; v_dob:=null;
    v_email:=new.email::text; v_phone:=new.phone; v_address:=new.contact_address; v_job:=coalesce(new.job_title,'Accounts Office Staff'); v_status:=case when coalesce(new.active,true) then 'active' else 'inactive' end; v_joined:=null; v_qualification:=null; v_specialization:=null; v_active:=coalesce(new.active,true); v_deleted:=new.deleted_at;
  else return new; end if;
  if coalesce(v_staff_no,'')='' then v_staff_no:=public.hr_generate_staff_no(); end if;
  insert into public.hr_staff_members(profile_id,source_type,source_id,staff_no,first_name,middle_name,last_name,gender,date_of_birth,email,phone,address,job_title,employment_status,date_joined,qualification,specialization,active,deleted_at,created_by)
  values(v_profile_id,v_type,v_source_id,v_staff_no,coalesce(v_first,'Staff'),v_middle,coalesce(v_last,''),v_gender,v_dob,v_email,v_phone,v_address,v_job,case when v_status in ('active','probation','leave','suspended','resigned','terminated','retired','inactive') then v_status else case when v_active then 'active' else 'inactive' end end,v_joined,v_qualification,v_specialization,v_active,v_deleted,auth.uid())
  on conflict (source_type,source_id) do update set profile_id=excluded.profile_id,staff_no=excluded.staff_no,first_name=excluded.first_name,middle_name=excluded.middle_name,last_name=excluded.last_name,gender=excluded.gender,date_of_birth=coalesce(excluded.date_of_birth,public.hr_staff_members.date_of_birth),email=excluded.email,phone=excluded.phone,address=excluded.address,job_title=coalesce(nullif(public.hr_staff_members.job_title,''),excluded.job_title),employment_status=excluded.employment_status,date_joined=coalesce(public.hr_staff_members.date_joined,excluded.date_joined),qualification=coalesce(excluded.qualification,public.hr_staff_members.qualification),specialization=coalesce(excluded.specialization,public.hr_staff_members.specialization),active=excluded.active,deleted_at=excluded.deleted_at,updated_at=now();
  return new;
end $$;

insert into public.hr_staff_members(profile_id,source_type,source_id,staff_no,first_name,middle_name,last_name,gender,date_of_birth,email,phone,address,department,job_title,employment_status,date_joined,qualification,specialization,active,deleted_at,created_by)
select t.profile_id,'teacher',t.id,t.staff_no::text,t.first_name,t.middle_name,t.last_name,t.gender,t.date_of_birth,t.email::text,t.phone,t.address,'Academic','Teacher',case when coalesce(t.employment_status,'active') in ('active','probation','leave','suspended','resigned','terminated','retired','inactive') then coalesce(t.employment_status,'active') else case when t.active then 'active' else 'inactive' end end,t.date_joined,t.qualification,t.specialization,t.active,t.deleted_at,t.created_by from public.teachers t on conflict (source_type,source_id) do nothing;
insert into public.hr_staff_members(profile_id,source_type,source_id,staff_no,first_name,middle_name,last_name,gender,email,phone,address,department,job_title,employment_status,date_joined,qualification,active,deleted_at,created_by)
select h.profile_id,'principal',h.id,h.staff_no::text,h.first_name,h.middle_name,h.last_name,h.gender,h.email::text,h.phone,h.address,'Leadership','Principal',case when coalesce(h.employment_status,'active') in ('active','probation','leave','suspended','resigned','terminated','retired','inactive') then coalesce(h.employment_status,'active') else case when h.active then 'active' else 'inactive' end end,h.date_appointed,h.qualification,h.active,h.deleted_at,h.created_by from public.headteachers h on conflict (source_type,source_id) do nothing;
insert into public.hr_staff_members(profile_id,source_type,source_id,staff_no,first_name,last_name,email,phone,address,department,job_title,employment_status,active,deleted_at,created_by)
select a.profile_id,'accounts_office',a.id,a.staff_no::text,coalesce(nullif(a.full_name,''),'Accounts Office Staff'),' ',a.email::text,a.phone,a.contact_address,'Finance',coalesce(a.job_title,'Accounts Office Staff'),case when a.active then 'active' else 'inactive' end,a.active,a.deleted_at,a.created_by from public.accounts_office_staff a on conflict (source_type,source_id) do nothing;

create trigger hr_staff_members_touch before update on public.hr_staff_members for each row execute function public.hr_touch_updated_at();
create trigger hr_staff_qualifications_touch before update on public.hr_staff_qualifications for each row execute function public.hr_touch_updated_at();
create trigger hr_staff_documents_touch before update on public.hr_staff_documents for each row execute function public.hr_touch_updated_at();
create trigger hr_leave_requests_touch before update on public.hr_leave_requests for each row execute function public.hr_touch_updated_at();
create trigger hr_staff_members_no_delete before delete on public.hr_staff_members for each row execute function public.hr_block_delete();
create trigger hr_staff_qualifications_no_delete before delete on public.hr_staff_qualifications for each row execute function public.hr_block_delete();
create trigger hr_staff_documents_no_delete before delete on public.hr_staff_documents for each row execute function public.hr_block_delete();
create trigger hr_leave_requests_no_delete before delete on public.hr_leave_requests for each row execute function public.hr_block_delete();
create trigger hr_employment_events_no_delete before delete on public.hr_employment_events for each row execute function public.hr_block_delete();
create trigger hr_staff_members_lifecycle after insert or update on public.hr_staff_members for each row execute function public.hr_record_staff_lifecycle();
create trigger hr_staff_members_audit after insert or update or delete on public.hr_staff_members for each row execute function public.audit_row_change();
create trigger hr_staff_qualifications_audit after insert or update or delete on public.hr_staff_qualifications for each row execute function public.audit_row_change();
create trigger hr_staff_documents_audit after insert or update or delete on public.hr_staff_documents for each row execute function public.audit_row_change();
create trigger hr_leave_requests_audit after insert or update or delete on public.hr_leave_requests for each row execute function public.audit_row_change();
create trigger hr_employment_events_audit after insert or update or delete on public.hr_employment_events for each row execute function public.audit_row_change();
create trigger teachers_hr_sync after insert or update or delete on public.teachers for each row execute function public.hr_sync_staff_from_source();
create trigger headteachers_hr_sync after insert or update or delete on public.headteachers for each row execute function public.hr_sync_staff_from_source();
create trigger accounts_office_staff_hr_sync after insert or update or delete on public.accounts_office_staff for each row execute function public.hr_sync_staff_from_source();

alter table public.finance_payroll_profiles add column if not exists hr_staff_member_id uuid references public.hr_staff_members(id) on delete restrict;
create index if not exists finance_payroll_profiles_hr_staff_idx on public.finance_payroll_profiles(hr_staff_member_id) where hr_staff_member_id is not null;
update public.finance_payroll_profiles p set hr_staff_member_id=h.id from public.hr_staff_members h where h.source_type='teacher' and h.source_id=p.teacher_id and p.hr_staff_member_id is distinct from h.id;
create or replace function public.finance_sync_hr_staff_link() returns trigger language plpgsql set search_path to 'public','pg_catalog' as $$ begin if new.teacher_id is not null then select id into new.hr_staff_member_id from public.hr_staff_members where source_type='teacher' and source_id=new.teacher_id; end if; return new; end $$;
create trigger finance_payroll_profiles_hr_link before insert or update of teacher_id on public.finance_payroll_profiles for each row execute function public.finance_sync_hr_staff_link();

create or replace function public.hr_staff_directory(search_text text default null,status_filter text default null,department_filter text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_role text;
begin
  v_role:=public.hr_require_access(false,array['system_admin','principal']);
  return jsonb_build_object('role',v_role,'metrics',jsonb_build_object('total',(select count(*) from public.hr_staff_members where deleted_at is null),'active',(select count(*) from public.hr_staff_members where deleted_at is null and active and employment_status in ('active','probation','leave')),'teachers',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='teacher'),'leadership',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='principal'),'accounts_office',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='accounts_office'),'other',(select count(*) from public.hr_staff_members where deleted_at is null and source_type='other'),'pending_leave',(select count(*) from public.hr_leave_requests where status='pending')),'rows',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'profile_id',s.profile_id,'source_type',s.source_type,'staff_no',s.staff_no,'full_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,''))),'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,'gender',s.gender,'email',s.email,'phone',s.phone,'department',s.department,'job_title',s.job_title,'employment_type',s.employment_type,'employment_status',s.employment_status,'date_joined',s.date_joined,'active',s.active,'payroll_linked',exists(select 1 from public.finance_payroll_profiles p where p.hr_staff_member_id=s.id)) order by s.active desc,s.last_name,s.first_name) from public.hr_staff_members s where s.deleted_at is null and (coalesce(nullif(search_text,''),'')='' or s.staff_no ilike '%'||search_text||'%' or s.first_name ilike '%'||search_text||'%' or s.last_name ilike '%'||search_text||'%' or coalesce(s.email,'') ilike '%'||search_text||'%') and (coalesce(nullif(status_filter,''),'')='' or s.employment_status=status_filter) and (coalesce(nullif(department_filter,''),'')='' or coalesce(s.department,'')=department_filter)),'[]'::jsonb),'departments',coalesce((select jsonb_agg(x.department order by x.department) from (select distinct department from public.hr_staff_members where deleted_at is null and coalesce(department,'')<>'') x),'[]'::jsonb));
end $$;

create or replace function public.hr_staff_detail(target_staff_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_staff jsonb;
begin
  perform public.hr_require_access(false,array['system_admin','principal']);
  select to_jsonb(s)||jsonb_build_object('full_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,'')))) into v_staff from public.hr_staff_members s where s.id=target_staff_id and s.deleted_at is null;
  if v_staff is null then raise exception 'Staff member not found'; end if;
  return jsonb_build_object('staff',v_staff,'qualifications',coalesce((select jsonb_agg(to_jsonb(q) order by q.awarded_on desc nulls last,q.created_at desc) from public.hr_staff_qualifications q where q.staff_id=target_staff_id),'[]'::jsonb),'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.expires_on nulls last,d.created_at desc) from public.hr_staff_documents d where d.staff_id=target_staff_id),'[]'::jsonb),'leave',coalesce((select jsonb_agg(to_jsonb(l) order by l.start_date desc,l.created_at desc) from public.hr_leave_requests l where l.staff_id=target_staff_id),'[]'::jsonb),'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.event_date desc,e.created_at desc) from public.hr_employment_events e where e.staff_id=target_staff_id),'[]'::jsonb),'payroll',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'payroll_number',p.payroll_number::text,'active',p.active,'salary_grade_id',p.salary_grade_id,'basic_salary_override',p.basic_salary_override)) from public.finance_payroll_profiles p where p.hr_staff_member_id=target_staff_id),'[]'::jsonb));
end $$;

create or replace function public.hr_save_staff(payload jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_id uuid; v_row public.hr_staff_members; v_staff_no text;
begin
  perform public.hr_require_access(true,array['system_admin']); v_id:=nullif(payload->>'id','')::uuid;
  if v_id is null then
    v_staff_no:=coalesce(nullif(btrim(payload->>'staff_no'),''),public.hr_generate_staff_no());
    insert into public.hr_staff_members(source_type,staff_no,first_name,middle_name,last_name,gender,date_of_birth,email,phone,address,department,job_title,employment_type,employment_status,date_joined,date_ended,qualification,specialization,emergency_contact_name,emergency_contact_phone,emergency_contact_relation,notes,active,created_by)
    values('other',v_staff_no,coalesce(nullif(btrim(payload->>'first_name'),''),'Staff'),nullif(btrim(payload->>'middle_name'),''),coalesce(nullif(btrim(payload->>'last_name'),''),''),nullif(payload->>'gender',''),nullif(payload->>'date_of_birth','')::date,nullif(btrim(payload->>'email'),''),nullif(btrim(payload->>'phone'),''),nullif(btrim(payload->>'address'),''),nullif(btrim(payload->>'department'),''),nullif(btrim(payload->>'job_title'),''),coalesce(nullif(payload->>'employment_type',''),'permanent'),coalesce(nullif(payload->>'employment_status',''),'active'),nullif(payload->>'date_joined','')::date,nullif(payload->>'date_ended','')::date,nullif(btrim(payload->>'qualification'),''),nullif(btrim(payload->>'specialization'),''),nullif(btrim(payload->>'emergency_contact_name'),''),nullif(btrim(payload->>'emergency_contact_phone'),''),nullif(btrim(payload->>'emergency_contact_relation'),''),nullif(btrim(payload->>'notes'),''),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into v_row;
  else
    update public.hr_staff_members s set department=coalesce(nullif(btrim(payload->>'department'),''),s.department),job_title=coalesce(nullif(btrim(payload->>'job_title'),''),s.job_title),employment_type=coalesce(nullif(payload->>'employment_type',''),s.employment_type),employment_status=coalesce(nullif(payload->>'employment_status',''),s.employment_status),date_joined=coalesce(nullif(payload->>'date_joined','')::date,s.date_joined),date_ended=nullif(payload->>'date_ended','')::date,emergency_contact_name=coalesce(nullif(btrim(payload->>'emergency_contact_name'),''),s.emergency_contact_name),emergency_contact_phone=coalesce(nullif(btrim(payload->>'emergency_contact_phone'),''),s.emergency_contact_phone),emergency_contact_relation=coalesce(nullif(btrim(payload->>'emergency_contact_relation'),''),s.emergency_contact_relation),notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else s.notes end,active=coalesce((payload->>'active')::boolean,s.active),first_name=case when s.source_type='other' and payload?'first_name' then coalesce(nullif(btrim(payload->>'first_name'),''),s.first_name) else s.first_name end,middle_name=case when s.source_type='other' and payload?'middle_name' then nullif(btrim(payload->>'middle_name'),'') else s.middle_name end,last_name=case when s.source_type='other' and payload?'last_name' then coalesce(nullif(btrim(payload->>'last_name'),''),s.last_name) else s.last_name end,email=case when s.source_type='other' and payload?'email' then nullif(btrim(payload->>'email'),'') else s.email end,phone=case when s.source_type='other' and payload?'phone' then nullif(btrim(payload->>'phone'),'') else s.phone end,address=case when s.source_type='other' and payload?'address' then nullif(btrim(payload->>'address'),'') else s.address end,gender=case when s.source_type='other' and payload?'gender' then nullif(payload->>'gender','') else s.gender end,date_of_birth=case when s.source_type='other' and payload?'date_of_birth' then nullif(payload->>'date_of_birth','')::date else s.date_of_birth end,qualification=case when payload?'qualification' then nullif(btrim(payload->>'qualification'),'') else s.qualification end,specialization=case when payload?'specialization' then nullif(btrim(payload->>'specialization'),'') else s.specialization end where s.id=v_id and s.deleted_at is null returning * into v_row;
    if v_row.id is null then raise exception 'Staff member not found'; end if;
  end if;
  return to_jsonb(v_row)||jsonb_build_object('full_name',btrim(concat_ws(' ',v_row.first_name,nullif(v_row.middle_name,''),nullif(v_row.last_name,''))));
end $$;

create or replace function public.hr_save_qualification(payload jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_id uuid; v_staff uuid; v_row public.hr_staff_qualifications;
begin
  perform public.hr_require_access(true,array['system_admin']); v_id:=nullif(payload->>'id','')::uuid; v_staff:=nullif(payload->>'staff_id','')::uuid; if v_staff is null then raise exception 'Staff member is required'; end if;
  if v_id is null then insert into public.hr_staff_qualifications(staff_id,qualification,institution,field_of_study,awarded_on,expires_on,verification_status,notes,created_by) values(v_staff,coalesce(nullif(btrim(payload->>'qualification'),''),'Qualification'),nullif(btrim(payload->>'institution'),''),nullif(btrim(payload->>'field_of_study'),''),nullif(payload->>'awarded_on','')::date,nullif(payload->>'expires_on','')::date,coalesce(nullif(payload->>'verification_status',''),'unverified'),nullif(btrim(payload->>'notes'),''),auth.uid()) returning * into v_row;
  else update public.hr_staff_qualifications set qualification=coalesce(nullif(btrim(payload->>'qualification'),''),qualification),institution=case when payload?'institution' then nullif(btrim(payload->>'institution'),'') else institution end,field_of_study=case when payload?'field_of_study' then nullif(btrim(payload->>'field_of_study'),'') else field_of_study end,awarded_on=case when payload?'awarded_on' then nullif(payload->>'awarded_on','')::date else awarded_on end,expires_on=case when payload?'expires_on' then nullif(payload->>'expires_on','')::date else expires_on end,verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then auth.uid() else verified_by end,verified_at=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then now() else verified_at end,notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else notes end where id=v_id and staff_id=v_staff returning * into v_row; end if; return to_jsonb(v_row);
end $$;

create or replace function public.hr_save_document(payload jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_id uuid; v_staff uuid; v_row public.hr_staff_documents;
begin
  perform public.hr_require_access(true,array['system_admin']); v_id:=nullif(payload->>'id','')::uuid; v_staff:=nullif(payload->>'staff_id','')::uuid; if v_staff is null then raise exception 'Staff member is required'; end if;
  if v_id is null then insert into public.hr_staff_documents(staff_id,document_type,title,reference_no,issued_on,expires_on,storage_path,verification_status,notes,created_by) values(v_staff,coalesce(nullif(btrim(payload->>'document_type'),''),'other'),coalesce(nullif(btrim(payload->>'title'),''),'Document'),nullif(btrim(payload->>'reference_no'),''),nullif(payload->>'issued_on','')::date,nullif(payload->>'expires_on','')::date,nullif(btrim(payload->>'storage_path'),''),coalesce(nullif(payload->>'verification_status',''),'unverified'),nullif(btrim(payload->>'notes'),''),auth.uid()) returning * into v_row;
  else update public.hr_staff_documents set document_type=coalesce(nullif(btrim(payload->>'document_type'),''),document_type),title=coalesce(nullif(btrim(payload->>'title'),''),title),reference_no=case when payload?'reference_no' then nullif(btrim(payload->>'reference_no'),'') else reference_no end,issued_on=case when payload?'issued_on' then nullif(payload->>'issued_on','')::date else issued_on end,expires_on=case when payload?'expires_on' then nullif(payload->>'expires_on','')::date else expires_on end,storage_path=case when payload?'storage_path' then nullif(btrim(payload->>'storage_path'),'') else storage_path end,verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then auth.uid() else verified_by end,verified_at=case when coalesce(nullif(payload->>'verification_status',''),verification_status)='verified' then now() else verified_at end,notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else notes end where id=v_id and staff_id=v_staff returning * into v_row; end if; return to_jsonb(v_row);
end $$;

create or replace function public.hr_submit_leave_for_staff(target_staff_id uuid,leave_kind text,start_on date,end_on date,reason_text text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_row public.hr_leave_requests; v_days numeric;
begin perform public.hr_require_access(true,array['system_admin']); if end_on<start_on then raise exception 'Leave end date cannot be before start date'; end if; v_days:=(end_on-start_on)+1; insert into public.hr_leave_requests(staff_id,leave_type,start_date,end_date,days,reason,status,submitted_by) values(target_staff_id,leave_kind,start_on,end_on,v_days,reason_text,'pending',auth.uid()) returning * into v_row; return to_jsonb(v_row); end $$;

create or replace function public.hr_decide_leave(target_request_id uuid,decision text,decision_reason_text text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_row public.hr_leave_requests; v_role text;
begin v_role:=public.hr_require_access(true,array['system_admin','principal']); if decision not in ('approved','rejected') then raise exception 'Leave decision must be approved or rejected'; end if; update public.hr_leave_requests set status=decision,decided_by=auth.uid(),decided_at=now(),decision_reason=nullif(btrim(decision_reason_text),'') where id=target_request_id and status='pending' returning * into v_row; if v_row.id is null then raise exception 'Pending leave request not found'; end if; insert into public.hr_employment_events(staff_id,event_type,event_date,details,created_by) values(v_row.staff_id,'leave_'||decision,current_date,jsonb_build_object('leave_request_id',v_row.id,'start_date',v_row.start_date,'end_date',v_row.end_date,'decided_by_role',v_role,'reason',decision_reason_text),auth.uid()); return to_jsonb(v_row); end $$;

create or replace function public.hr_cancel_leave(target_request_id uuid,cancellation_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_row public.hr_leave_requests;
begin perform public.hr_require_access(true,array['system_admin']); update public.hr_leave_requests set status='cancelled',decided_by=auth.uid(),decided_at=now(),decision_reason=nullif(btrim(cancellation_reason),'') where id=target_request_id and status in ('pending','approved') returning * into v_row; if v_row.id is null then raise exception 'Leave request cannot be cancelled'; end if; return to_jsonb(v_row); end $$;

create or replace function public.hr_leave_register(status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog','extensions'
as $$
begin perform public.hr_require_access(false,array['system_admin','principal']); return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'staff_id',l.staff_id,'staff_no',s.staff_no,'staff_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,''))),'department',s.department,'job_title',s.job_title,'leave_type',l.leave_type,'start_date',l.start_date,'end_date',l.end_date,'days',l.days,'reason',l.reason,'status',l.status,'submitted_at',l.submitted_at,'decided_at',l.decided_at,'decision_reason',l.decision_reason) order by case when l.status='pending' then 0 else 1 end,l.start_date desc) from public.hr_leave_requests l join public.hr_staff_members s on s.id=l.staff_id where s.deleted_at is null and (coalesce(nullif(status_filter,''),'')='' or l.status=status_filter)),'[]'::jsonb); end $$;

create or replace function public.hr_my_profile()
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_id uuid; v_license jsonb;
begin if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if; v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Access unavailable' using errcode='42501'; end if; select id into v_id from public.hr_staff_members where profile_id=auth.uid() and deleted_at is null and active; if v_id is null then return null; end if; return jsonb_build_object('staff',(select to_jsonb(s)||jsonb_build_object('full_name',btrim(concat_ws(' ',s.first_name,nullif(s.middle_name,''),nullif(s.last_name,'')))) from public.hr_staff_members s where s.id=v_id),'qualifications',coalesce((select jsonb_agg(to_jsonb(q) order by q.awarded_on desc nulls last) from public.hr_staff_qualifications q where q.staff_id=v_id),'[]'::jsonb),'leave',coalesce((select jsonb_agg(to_jsonb(l) order by l.start_date desc) from public.hr_leave_requests l where l.staff_id=v_id),'[]'::jsonb)); end $$;

create or replace function public.hr_submit_my_leave(leave_kind text,start_on date,end_on date,reason_text text default null)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog','extensions'
as $$
declare v_staff uuid; v_license jsonb; v_row public.hr_leave_requests; v_days numeric;
begin if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if; v_license:=public.license_access_for_actor(auth.uid()); if not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Leave requests are unavailable while the school licence is read-only' using errcode='42501'; end if; select id into v_staff from public.hr_staff_members where profile_id=auth.uid() and deleted_at is null and active; if v_staff is null then raise exception 'Active staff record not found' using errcode='42501'; end if; if end_on<start_on then raise exception 'Leave end date cannot be before start date'; end if; v_days:=(end_on-start_on)+1; insert into public.hr_leave_requests(staff_id,leave_type,start_date,end_date,days,reason,status,submitted_by) values(v_staff,leave_kind,start_on,end_on,v_days,reason_text,'pending',auth.uid()) returning * into v_row; return to_jsonb(v_row); end $$;

revoke all on function public.hr_generate_staff_no() from public, anon, authenticated;
revoke all on function public.hr_require_access(boolean,text[]) from public, anon, authenticated;
revoke all on function public.hr_staff_directory(text,text,text),public.hr_staff_detail(uuid),public.hr_save_staff(jsonb),public.hr_save_qualification(jsonb),public.hr_save_document(jsonb),public.hr_submit_leave_for_staff(uuid,text,date,date,text),public.hr_decide_leave(uuid,text,text),public.hr_cancel_leave(uuid,text),public.hr_leave_register(text),public.hr_my_profile(),public.hr_submit_my_leave(text,date,date,text) from public, anon;
grant execute on function public.hr_staff_directory(text,text,text),public.hr_staff_detail(uuid),public.hr_save_staff(jsonb),public.hr_save_qualification(jsonb),public.hr_save_document(jsonb),public.hr_submit_leave_for_staff(uuid,text,date,date,text),public.hr_decide_leave(uuid,text,text),public.hr_cancel_leave(uuid,text),public.hr_leave_register(text),public.hr_my_profile(),public.hr_submit_my_leave(text,date,date,text) to authenticated, service_role;
grant execute on function public.hr_generate_staff_no(),public.hr_require_access(boolean,text[]) to service_role;

commit;
