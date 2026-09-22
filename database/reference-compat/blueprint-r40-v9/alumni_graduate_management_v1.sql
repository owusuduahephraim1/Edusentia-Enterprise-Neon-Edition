begin;

create sequence public.alumni_record_seq start with 1 increment by 1;

create table public.alumni_records (
 id uuid primary key default gen_random_uuid(),
 alumni_code text not null unique,
 student_id uuid unique references public.students(id) on delete restrict,
 former_admission_no text,
 first_name text not null,
 middle_name text,
 last_name text not null,
 graduation_academic_year_id uuid references public.academic_years(id) on delete restrict,
 final_class_id uuid references public.classes(id) on delete restrict,
 personal_email text,
 phone text,
 location text,
 occupation text,
 employer text,
 further_education text,
 consent_to_contact boolean not null default false,
 directory_visible boolean not null default false,
 verification_status text not null default 'unverified' check(verification_status in ('unverified','verified','needs_review')),
 status text not null default 'active' check(status in ('active','inactive','lost_contact','deceased')),
 notes text,
 created_by uuid references public.profiles(id) on delete set null,
 verified_by uuid references public.profiles(id) on delete set null,
 verified_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.alumni_engagements (
 id uuid primary key default gen_random_uuid(),
 alumni_id uuid not null references public.alumni_records(id) on delete restrict,
 engagement_type text not null check(engagement_type in ('contact','event','mentorship','volunteering','career_talk','donation_reference','fundraising','other')),
 engagement_date date not null default current_date,
 summary text not null,
 outcome text,
 finance_reference text,
 recorded_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.alumni_verification_requests (
 id uuid primary key default gen_random_uuid(),
 alumni_id uuid references public.alumni_records(id) on delete restrict,
 request_type text not null check(request_type in ('graduation','enrolment','identity','reference','transcript','other')),
 requester_name text not null,
 requester_email text,
 requester_phone text,
 purpose text,
 status text not null default 'pending' check(status in ('pending','under_review','verified','declined','cancelled')),
 outcome_notes text,
 requested_at timestamptz not null default now(),
 reviewed_by uuid references public.profiles(id) on delete set null,
 reviewed_at timestamptz,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create index alumni_student_idx on public.alumni_records(student_id) where student_id is not null;
create index alumni_name_idx on public.alumni_records(last_name,first_name);
create index alumni_year_idx on public.alumni_records(graduation_academic_year_id,final_class_id,status);
create index alumni_created_by_idx on public.alumni_records(created_by);
create index alumni_verified_by_idx on public.alumni_records(verified_by);
create index alumni_engagement_alumni_idx on public.alumni_engagements(alumni_id,engagement_date desc);
create index alumni_engagement_recorded_by_idx on public.alumni_engagements(recorded_by);
create index alumni_verification_status_idx on public.alumni_verification_requests(status,requested_at desc);
create index alumni_verification_alumni_idx on public.alumni_verification_requests(alumni_id,requested_at desc);
create index alumni_verification_reviewed_by_idx on public.alumni_verification_requests(reviewed_by);
create index alumni_verification_created_by_idx on public.alumni_verification_requests(created_by);

alter table public.alumni_records enable row level security;
alter table public.alumni_engagements enable row level security;
alter table public.alumni_verification_requests enable row level security;
revoke all on table public.alumni_records,public.alumni_engagements,public.alumni_verification_requests from public,anon,authenticated;
grant all on table public.alumni_records,public.alumni_engagements,public.alumni_verification_requests to service_role;
revoke all on sequence public.alumni_record_seq from public,anon,authenticated;
grant usage,select on sequence public.alumni_record_seq to service_role;

create trigger alumni_record_touch before update on public.alumni_records for each row execute function public.student_services_touch_updated_at();
create trigger alumni_engagement_touch before update on public.alumni_engagements for each row execute function public.student_services_touch_updated_at();
create trigger alumni_verification_touch before update on public.alumni_verification_requests for each row execute function public.student_services_touch_updated_at();
create trigger alumni_record_audit after insert or update or delete on public.alumni_records for each row execute function public.audit_row_change();
create trigger alumni_engagement_audit after insert or update or delete on public.alumni_engagements for each row execute function public.audit_row_change();
create trigger alumni_verification_audit after insert or update or delete on public.alumni_verification_requests for each row execute function public.audit_row_change();
create trigger alumni_record_no_delete before delete on public.alumni_records for each row execute function public.student_services_block_delete();
create trigger alumni_engagement_no_delete before delete on public.alumni_engagements for each row execute function public.student_services_block_delete();
create trigger alumni_verification_no_delete before delete on public.alumni_verification_requests for each row execute function public.student_services_block_delete();

create or replace function public.alumni_next_code()
returns text language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare p text;n bigint;
begin
 select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'ALU'),'[^0-9A-Za-z]','','g')) into p from public.school_settings limit 1;
 n:=nextval('public.alumni_record_seq'); return p||'-ALU-'||lpad(n::text,7,'0');
end $$;

create or replace function public.alumni_dashboard()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('alumni','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'alumni',(select count(*) from public.alumni_records where status='active'),
  'verified',(select count(*) from public.alumni_records where verification_status='verified'),
  'contactable',(select count(*) from public.alumni_records where consent_to_contact and status='active'),
  'engagements_90_days',(select count(*) from public.alumni_engagements where engagement_date>=current_date-90),
  'pending_verifications',(select count(*) from public.alumni_verification_requests where status in ('pending','under_review')),
  'graduated_not_synced',(select count(*) from public.students s where s.status='graduated' and s.deleted_at is null and not exists(select 1 from public.alumni_records a where a.student_id=s.id))
 ));
end $$;

create or replace function public.alumni_candidate_register(search_text text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('alumni','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name) from (
  select s.id student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) full_name,s.gender,s.status,
   (select e.academic_year_id from public.enrollments e where e.student_id=s.id order by e.created_at desc limit 1) last_academic_year_id,
   (select e.class_id from public.enrollments e where e.student_id=s.id order by e.created_at desc limit 1) last_class_id
  from public.students s where s.deleted_at is null and s.status='graduated' and not exists(select 1 from public.alumni_records a where a.student_id=s.id)
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
 )q),'[]'::jsonb);
end $$;

create or replace function public.alumni_register(search_text text default null,status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('alumni','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.last_name,q.first_name) from (
  select a.id,a.alumni_code,a.student_id,a.former_admission_no,a.first_name,a.middle_name,a.last_name,concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) full_name,a.graduation_academic_year_id,y.name graduation_year,a.final_class_id,c.name final_class,a.personal_email,a.phone,a.location,a.occupation,a.employer,a.consent_to_contact,a.directory_visible,a.verification_status,a.status,a.updated_at
  from public.alumni_records a left join public.academic_years y on y.id=a.graduation_academic_year_id left join public.classes c on c.id=a.final_class_id
  where (status_filter is null or a.status=status_filter) and (search_text is null or concat_ws(' ',a.alumni_code,a.former_admission_no,a.first_name,a.middle_name,a.last_name,a.personal_email,a.phone,a.occupation,a.employer) ilike '%'||search_text||'%')
  order by a.last_name,a.first_name limit 500
 )q),'[]'::jsonb);
end $$;

create or replace function public.alumni_create_from_student(target_student_id uuid,graduation_academic_year_id uuid default null,final_class_id uuid default null)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare s public.students%rowtype;v_year uuid;v_class uuid;v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 select * into s from public.students where id=target_student_id and deleted_at is null for update;
 if s.id is null then raise exception 'Student not found'; end if;
 if exists(select 1 from public.alumni_records where student_id=s.id) then raise exception 'Student already has an alumni record'; end if;
 select coalesce(graduation_academic_year_id,e.academic_year_id),coalesce(final_class_id,e.class_id) into v_year,v_class from public.enrollments e where e.student_id=s.id order by e.created_at desc limit 1;
 if v_year is null then v_year:=graduation_academic_year_id; v_class:=final_class_id; end if;
 insert into public.alumni_records(alumni_code,student_id,former_admission_no,first_name,middle_name,last_name,graduation_academic_year_id,final_class_id,verification_status,created_by)
 values(public.alumni_next_code(),s.id,s.admission_no,s.first_name,nullif(s.middle_name,''),s.last_name,v_year,v_class,'verified',auth.uid()) returning id into v_id;
 update public.alumni_records set verified_by=auth.uid(),verified_at=now() where id=v_id;
 if s.status<>'graduated' then update public.students set status='graduated',updated_at=now() where id=s.id; end if;
 update public.enrollments set active=false,updated_at=now() where student_id=s.id and active;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('alumni','graduate_synced','alumni_record',v_id,auth.uid(),jsonb_build_object('student_id',s.id,'former_admission_no',s.admission_no));
 return v_id;
end $$;

create or replace function public.alumni_save_record(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
  insert into public.alumni_records(alumni_code,former_admission_no,first_name,middle_name,last_name,graduation_academic_year_id,final_class_id,personal_email,phone,location,occupation,employer,further_education,consent_to_contact,directory_visible,verification_status,status,notes,created_by)
  values(public.alumni_next_code(),nullif(payload->>'former_admission_no',''),btrim(payload->>'first_name'),nullif(btrim(payload->>'middle_name'),''),btrim(payload->>'last_name'),nullif(payload->>'graduation_academic_year_id','')::uuid,nullif(payload->>'final_class_id','')::uuid,nullif(lower(btrim(payload->>'personal_email')),''),nullif(btrim(payload->>'phone'),''),nullif(payload->>'location',''),nullif(payload->>'occupation',''),nullif(payload->>'employer',''),nullif(payload->>'further_education',''),coalesce((payload->>'consent_to_contact')::boolean,false),coalesce((payload->>'directory_visible')::boolean,false),coalesce(nullif(payload->>'verification_status',''),'unverified'),coalesce(nullif(payload->>'status',''),'active'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else
  update public.alumni_records set personal_email=case when payload ? 'personal_email' then nullif(lower(btrim(payload->>'personal_email')),'') else personal_email end,phone=case when payload ? 'phone' then nullif(btrim(payload->>'phone'),'') else phone end,location=case when payload ? 'location' then nullif(payload->>'location','') else location end,occupation=case when payload ? 'occupation' then nullif(payload->>'occupation','') else occupation end,employer=case when payload ? 'employer' then nullif(payload->>'employer','') else employer end,further_education=case when payload ? 'further_education' then nullif(payload->>'further_education','') else further_education end,consent_to_contact=coalesce((payload->>'consent_to_contact')::boolean,consent_to_contact),directory_visible=coalesce((payload->>'directory_visible')::boolean,directory_visible),verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when payload->>'verification_status'='verified' then auth.uid() else verified_by end,verified_at=case when payload->>'verification_status'='verified' then now() else verified_at end,status=coalesce(nullif(payload->>'status',''),status),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $$;

create or replace function public.alumni_record_detail(target_alumni_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare r jsonb;
begin
 perform public.student_services_require_access('alumni','read');
 select to_jsonb(a) into r from public.alumni_records a where a.id=target_alumni_id;
 if r is null then raise exception 'Alumni record not found'; end if;
 return r||jsonb_build_object(
  'engagements',coalesce((select jsonb_agg(to_jsonb(e) order by e.engagement_date desc,e.created_at desc) from public.alumni_engagements e where e.alumni_id=target_alumni_id),'[]'::jsonb),
  'verification_requests',coalesce((select jsonb_agg(to_jsonb(v) order by v.requested_at desc) from public.alumni_verification_requests v where v.alumni_id=target_alumni_id),'[]'::jsonb)
 );
end $$;

create or replace function public.alumni_add_engagement(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 insert into public.alumni_engagements(alumni_id,engagement_type,engagement_date,summary,outcome,finance_reference,recorded_by) values((payload->>'alumni_id')::uuid,payload->>'engagement_type',coalesce(nullif(payload->>'engagement_date','')::date,current_date),btrim(payload->>'summary'),nullif(payload->>'outcome',''),nullif(payload->>'finance_reference',''),auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.alumni_save_verification_request(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.alumni_verification_requests(alumni_id,request_type,requester_name,requester_email,requester_phone,purpose,status,created_by) values(nullif(payload->>'alumni_id','')::uuid,payload->>'request_type',btrim(payload->>'requester_name'),nullif(payload->>'requester_email',''),nullif(payload->>'requester_phone',''),nullif(payload->>'purpose',''),coalesce(nullif(payload->>'status',''),'pending'),auth.uid()) returning id into v_id;
 else update public.alumni_verification_requests set status=coalesce(nullif(payload->>'status',''),status),outcome_notes=case when payload ? 'outcome_notes' then nullif(payload->>'outcome_notes','') else outcome_notes end,reviewed_by=case when payload->>'status' in ('verified','declined') then auth.uid() else reviewed_by end,reviewed_at=case when payload->>'status' in ('verified','declined') then now() else reviewed_at end where id=v_id;
 end if; return v_id;
end $$;

create or replace function public.alumni_verification_register(status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('alumni','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.requested_at desc) from (select v.*,a.alumni_code,concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) alumni_name from public.alumni_verification_requests v left join public.alumni_records a on a.id=v.alumni_id where status_filter is null or v.status=status_filter)q),'[]'::jsonb);
end $$;

create or replace function public.alumni_my_record()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare v_student uuid;r jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select id into v_student from public.students where profile_id=auth.uid() and deleted_at is null limit 1;
 if v_student is null then return null; end if;
 select jsonb_build_object('alumni_code',a.alumni_code,'former_admission_no',a.former_admission_no,'name',concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name),'graduation_academic_year_id',a.graduation_academic_year_id,'final_class_id',a.final_class_id,'personal_email',a.personal_email,'phone',a.phone,'location',a.location,'occupation',a.occupation,'employer',a.employer,'further_education',a.further_education,'verification_status',a.verification_status) into r from public.alumni_records a where a.student_id=v_student;
 return r;
end $$;

revoke all on function public.alumni_next_code(),public.alumni_dashboard(),public.alumni_candidate_register(text),public.alumni_register(text,text),public.alumni_create_from_student(uuid,uuid,uuid),public.alumni_save_record(jsonb),public.alumni_record_detail(uuid),public.alumni_add_engagement(jsonb),public.alumni_save_verification_request(jsonb),public.alumni_verification_register(text),public.alumni_my_record() from public,anon,authenticated;
grant execute on function public.alumni_dashboard(),public.alumni_candidate_register(text),public.alumni_register(text,text),public.alumni_create_from_student(uuid,uuid,uuid),public.alumni_save_record(jsonb),public.alumni_record_detail(uuid),public.alumni_add_engagement(jsonb),public.alumni_save_verification_request(jsonb),public.alumni_verification_register(text),public.alumni_my_record() to authenticated;
grant execute on function public.alumni_next_code() to service_role;

commit;