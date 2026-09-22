begin;

create table public.health_student_profiles (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null unique references public.students(id) on delete restrict,
 blood_group text,
 genotype text,
 allergies text,
 chronic_conditions text,
 current_medications text,
 dietary_restrictions text,
 disability_or_support_notes text,
 emergency_instructions text,
 primary_doctor_name text,
 primary_doctor_phone text,
 insurance_provider text,
 insurance_member_no text,
 emergency_contact_name text,
 emergency_contact_phone text,
 emergency_contact_relation text,
 consent_notes text,
 created_by uuid references public.profiles(id) on delete set null,
 updated_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.health_visits (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete restrict,
 visited_at timestamptz not null default now(),
 complaint text not null,
 observations text,
 temperature_c numeric(4,1) check(temperature_c is null or temperature_c between 30 and 45),
 pulse_bpm integer check(pulse_bpm is null or pulse_bpm between 20 and 250),
 blood_pressure text,
 treatment_notes text,
 disposition text not null default 'returned_to_class' check(disposition in ('returned_to_class','sent_home','referred','emergency_transfer','observation','other')),
 referral_destination text,
 guardian_notified boolean not null default false,
 guardian_notified_at timestamptz,
 status text not null default 'completed' check(status in ('open','observation','completed','referred','cancelled')),
 attended_by_hr_staff_id uuid references public.hr_staff_members(id) on delete set null,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.health_medication_administrations (
 id uuid primary key default gen_random_uuid(),
 visit_id uuid references public.health_visits(id) on delete restrict,
 student_id uuid not null references public.students(id) on delete restrict,
 medication_name text not null,
 dosage text not null,
 route text,
 reason text,
 administered_at timestamptz not null default now(),
 consent_reference text,
 administered_by_hr_staff_id uuid references public.hr_staff_members(id) on delete set null,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now()
);

create table public.health_immunizations (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete restrict,
 vaccine_name text not null,
 dose_label text,
 administered_date date,
 next_due_date date,
 provider text,
 evidence_reference text,
 status text not null default 'recorded' check(status in ('recorded','due','overdue','declined','not_required')),
 notes text,
 recorded_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create index health_profiles_created_by_idx on public.health_student_profiles(created_by);
create index health_profiles_updated_by_idx on public.health_student_profiles(updated_by);
create index health_visits_student_time_idx on public.health_visits(student_id,visited_at desc);
create index health_visits_status_idx on public.health_visits(status,visited_at desc);
create index health_visits_staff_idx on public.health_visits(attended_by_hr_staff_id);
create index health_visits_created_by_idx on public.health_visits(created_by);
create index health_meds_student_time_idx on public.health_medication_administrations(student_id,administered_at desc);
create index health_meds_visit_idx on public.health_medication_administrations(visit_id,administered_at);
create index health_meds_staff_idx on public.health_medication_administrations(administered_by_hr_staff_id);
create index health_meds_created_by_idx on public.health_medication_administrations(created_by);
create index health_immunizations_student_idx on public.health_immunizations(student_id,next_due_date);
create index health_immunizations_recorded_by_idx on public.health_immunizations(recorded_by);

alter table public.health_student_profiles enable row level security;
alter table public.health_visits enable row level security;
alter table public.health_medication_administrations enable row level security;
alter table public.health_immunizations enable row level security;
revoke all on table public.health_student_profiles,public.health_visits,public.health_medication_administrations,public.health_immunizations from public,anon,authenticated;
grant all on table public.health_student_profiles,public.health_visits,public.health_medication_administrations,public.health_immunizations to service_role;

create trigger health_profile_touch before update on public.health_student_profiles for each row execute function public.student_services_touch_updated_at();
create trigger health_visit_touch before update on public.health_visits for each row execute function public.student_services_touch_updated_at();
create trigger health_immunization_touch before update on public.health_immunizations for each row execute function public.student_services_touch_updated_at();
create trigger health_profile_audit after insert or update or delete on public.health_student_profiles for each row execute function public.audit_row_change();
create trigger health_visit_audit after insert or update or delete on public.health_visits for each row execute function public.audit_row_change();
create trigger health_med_audit after insert or update or delete on public.health_medication_administrations for each row execute function public.audit_row_change();
create trigger health_immunization_audit after insert or update or delete on public.health_immunizations for each row execute function public.audit_row_change();
create trigger health_profile_no_delete before delete on public.health_student_profiles for each row execute function public.student_services_block_delete();
create trigger health_visit_no_delete before delete on public.health_visits for each row execute function public.student_services_block_delete();
create trigger health_med_no_delete before delete on public.health_medication_administrations for each row execute function public.student_services_block_delete();
create trigger health_immunization_no_delete before delete on public.health_immunizations for each row execute function public.student_services_block_delete();

create or replace function public.health_dashboard()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('health','summary');
 return jsonb_build_object('metrics',jsonb_build_object(
  'student_profiles',(select count(*) from public.health_student_profiles),
  'visits_today',(select count(*) from public.health_visits where visited_at::date=current_date and status<>'cancelled'),
  'open_observations',(select count(*) from public.health_visits where status in ('open','observation')),
  'referrals_30_days',(select count(*) from public.health_visits where disposition in ('referred','emergency_transfer') and visited_at>=now()-interval '30 days'),
  'immunizations_due',(select count(*) from public.health_immunizations where status in ('due','overdue') or (next_due_date is not null and next_due_date<=current_date))
 ));
end $$;

create or replace function public.health_student_profile(target_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare r jsonb;
begin
 perform public.student_services_require_access('health','read');
 select to_jsonb(q) into r from (
  select s.id student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,s.gender,s.date_of_birth,
   p.id profile_record_id,p.blood_group,p.genotype,p.allergies,p.chronic_conditions,p.current_medications,p.dietary_restrictions,p.disability_or_support_notes,p.emergency_instructions,p.primary_doctor_name,p.primary_doctor_phone,p.insurance_provider,p.insurance_member_no,p.emergency_contact_name,p.emergency_contact_phone,p.emergency_contact_relation,p.consent_notes,p.updated_at
  from public.students s left join public.health_student_profiles p on p.student_id=s.id where s.id=target_student_id and s.deleted_at is null
 )q;
 if r is null then raise exception 'Student not found'; end if;
 return r||jsonb_build_object(
  'recent_visits',coalesce((select jsonb_agg(to_jsonb(v) order by v.visited_at desc) from (select * from public.health_visits where student_id=target_student_id order by visited_at desc limit 25)v),'[]'::jsonb),
  'immunizations',coalesce((select jsonb_agg(to_jsonb(i) order by i.administered_date desc nulls last,i.created_at desc) from public.health_immunizations i where i.student_id=target_student_id),'[]'::jsonb)
 );
end $$;

create or replace function public.health_visit_register(search_text text default null,date_from date default null,date_to date default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('health','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.visited_at desc) from (
  select v.id,v.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,v.visited_at,v.complaint,v.temperature_c,v.pulse_bpm,v.disposition,v.referral_destination,v.guardian_notified,v.status
  from public.health_visits v join public.students s on s.id=v.student_id
  where (date_from is null or v.visited_at::date>=date_from) and (date_to is null or v.visited_at::date<=date_to)
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,v.complaint,v.referral_destination) ilike '%'||search_text||'%')
  order by v.visited_at desc limit 300
 )q),'[]'::jsonb);
end $$;

create or replace function public.health_save_profile(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;v_student uuid;
begin
 perform public.student_services_require_access('health','write');
 v_student:=(payload->>'student_id')::uuid;
 insert into public.health_student_profiles(student_id,blood_group,genotype,allergies,chronic_conditions,current_medications,dietary_restrictions,disability_or_support_notes,emergency_instructions,primary_doctor_name,primary_doctor_phone,insurance_provider,insurance_member_no,emergency_contact_name,emergency_contact_phone,emergency_contact_relation,consent_notes,created_by,updated_by)
 values(v_student,nullif(payload->>'blood_group',''),nullif(payload->>'genotype',''),nullif(payload->>'allergies',''),nullif(payload->>'chronic_conditions',''),nullif(payload->>'current_medications',''),nullif(payload->>'dietary_restrictions',''),nullif(payload->>'disability_or_support_notes',''),nullif(payload->>'emergency_instructions',''),nullif(payload->>'primary_doctor_name',''),nullif(payload->>'primary_doctor_phone',''),nullif(payload->>'insurance_provider',''),nullif(payload->>'insurance_member_no',''),nullif(payload->>'emergency_contact_name',''),nullif(payload->>'emergency_contact_phone',''),nullif(payload->>'emergency_contact_relation',''),nullif(payload->>'consent_notes',''),auth.uid(),auth.uid())
 on conflict(student_id) do update set blood_group=excluded.blood_group,genotype=excluded.genotype,allergies=excluded.allergies,chronic_conditions=excluded.chronic_conditions,current_medications=excluded.current_medications,dietary_restrictions=excluded.dietary_restrictions,disability_or_support_notes=excluded.disability_or_support_notes,emergency_instructions=excluded.emergency_instructions,primary_doctor_name=excluded.primary_doctor_name,primary_doctor_phone=excluded.primary_doctor_phone,insurance_provider=excluded.insurance_provider,insurance_member_no=excluded.insurance_member_no,emergency_contact_name=excluded.emergency_contact_name,emergency_contact_phone=excluded.emergency_contact_phone,emergency_contact_relation=excluded.emergency_contact_relation,consent_notes=excluded.consent_notes,updated_by=auth.uid(),updated_at=now()
 returning id into v_id;
 return v_id;
end $$;

create or replace function public.health_save_visit(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('health','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
  insert into public.health_visits(student_id,visited_at,complaint,observations,temperature_c,pulse_bpm,blood_pressure,treatment_notes,disposition,referral_destination,guardian_notified,guardian_notified_at,status,attended_by_hr_staff_id,created_by)
  values((payload->>'student_id')::uuid,coalesce(nullif(payload->>'visited_at','')::timestamptz,now()),btrim(payload->>'complaint'),nullif(payload->>'observations',''),nullif(payload->>'temperature_c','')::numeric,nullif(payload->>'pulse_bpm','')::integer,nullif(payload->>'blood_pressure',''),nullif(payload->>'treatment_notes',''),coalesce(nullif(payload->>'disposition',''),'returned_to_class'),nullif(payload->>'referral_destination',''),coalesce((payload->>'guardian_notified')::boolean,false),case when coalesce((payload->>'guardian_notified')::boolean,false) then now() end,coalesce(nullif(payload->>'status',''),'completed'),nullif(payload->>'attended_by_hr_staff_id','')::uuid,auth.uid()) returning id into v_id;
 else
  update public.health_visits set complaint=coalesce(nullif(btrim(payload->>'complaint'),''),complaint),observations=case when payload ? 'observations' then nullif(payload->>'observations','') else observations end,temperature_c=case when payload ? 'temperature_c' then nullif(payload->>'temperature_c','')::numeric else temperature_c end,pulse_bpm=case when payload ? 'pulse_bpm' then nullif(payload->>'pulse_bpm','')::integer else pulse_bpm end,blood_pressure=case when payload ? 'blood_pressure' then nullif(payload->>'blood_pressure','') else blood_pressure end,treatment_notes=case when payload ? 'treatment_notes' then nullif(payload->>'treatment_notes','') else treatment_notes end,disposition=coalesce(nullif(payload->>'disposition',''),disposition),referral_destination=case when payload ? 'referral_destination' then nullif(payload->>'referral_destination','') else referral_destination end,guardian_notified=coalesce((payload->>'guardian_notified')::boolean,guardian_notified),guardian_notified_at=case when coalesce((payload->>'guardian_notified')::boolean,false) and guardian_notified_at is null then now() else guardian_notified_at end,status=coalesce(nullif(payload->>'status',''),status),attended_by_hr_staff_id=case when payload ? 'attended_by_hr_staff_id' then nullif(payload->>'attended_by_hr_staff_id','')::uuid else attended_by_hr_staff_id end where id=v_id and status<>'cancelled';
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('health','clinic_visit_saved','health_visit',v_id,auth.uid(),'{}');
 return v_id;
end $$;

create or replace function public.health_record_medication(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('health','write');
 insert into public.health_medication_administrations(visit_id,student_id,medication_name,dosage,route,reason,administered_at,consent_reference,administered_by_hr_staff_id,created_by)
 values(nullif(payload->>'visit_id','')::uuid,(payload->>'student_id')::uuid,btrim(payload->>'medication_name'),btrim(payload->>'dosage'),nullif(payload->>'route',''),nullif(payload->>'reason',''),coalesce(nullif(payload->>'administered_at','')::timestamptz,now()),nullif(payload->>'consent_reference',''),nullif(payload->>'administered_by_hr_staff_id','')::uuid,auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.health_save_immunization(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('health','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.health_immunizations(student_id,vaccine_name,dose_label,administered_date,next_due_date,provider,evidence_reference,status,notes,recorded_by) values((payload->>'student_id')::uuid,btrim(payload->>'vaccine_name'),nullif(payload->>'dose_label',''),nullif(payload->>'administered_date','')::date,nullif(payload->>'next_due_date','')::date,nullif(payload->>'provider',''),nullif(payload->>'evidence_reference',''),coalesce(nullif(payload->>'status',''),'recorded'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.health_immunizations set vaccine_name=coalesce(nullif(btrim(payload->>'vaccine_name'),''),vaccine_name),dose_label=case when payload ? 'dose_label' then nullif(payload->>'dose_label','') else dose_label end,administered_date=case when payload ? 'administered_date' then nullif(payload->>'administered_date','')::date else administered_date end,next_due_date=case when payload ? 'next_due_date' then nullif(payload->>'next_due_date','')::date else next_due_date end,provider=case when payload ? 'provider' then nullif(payload->>'provider','') else provider end,evidence_reference=case when payload ? 'evidence_reference' then nullif(payload->>'evidence_reference','') else evidence_reference end,status=coalesce(nullif(payload->>'status',''),status),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $$;

create or replace function public.health_my_children_emergency_summary()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.student_name) from (
  select s.id student_id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,p.blood_group,p.allergies,p.chronic_conditions,p.current_medications,p.dietary_restrictions,p.emergency_instructions,p.emergency_contact_name,p.emergency_contact_phone,p.emergency_contact_relation
  from public.guardian_links g join public.students s on s.id=g.student_id left join public.health_student_profiles p on p.student_id=s.id
  where g.auth_user_id=auth.uid() and g.can_view_reports and s.deleted_at is null
 )q),'[]'::jsonb);
end $$;

revoke all on function public.health_dashboard(),public.health_student_profile(uuid),public.health_visit_register(text,date,date),public.health_save_profile(jsonb),public.health_save_visit(jsonb),public.health_record_medication(jsonb),public.health_save_immunization(jsonb),public.health_my_children_emergency_summary() from public,anon,authenticated;
grant execute on function public.health_dashboard(),public.health_student_profile(uuid),public.health_visit_register(text,date,date),public.health_save_profile(jsonb),public.health_save_visit(jsonb),public.health_record_medication(jsonb),public.health_save_immunization(jsonb),public.health_my_children_emergency_summary() to authenticated;

commit;