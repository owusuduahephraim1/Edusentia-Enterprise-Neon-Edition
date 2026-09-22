begin;

create table public.student_services_staff_access (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  hr_staff_id uuid not null references public.hr_staff_members(id) on delete restrict,
  service_role text not null check (service_role in ('admissions_officer','welfare_officer','clinic_officer','communications_officer','hostel_manager','house_parent','alumni_officer')),
  active boolean not null default true,
  appointed_by uuid references public.profiles(id) on delete set null,
  appointed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(profile_id,service_role),
  unique(hr_staff_id,service_role)
);

create table public.student_services_events (
  id uuid primary key default gen_random_uuid(),
  domain text not null check (domain in ('admissions','discipline','welfare','health','communications','hostel','alumni')),
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  actor_id uuid references public.profiles(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index student_services_staff_profile_idx on public.student_services_staff_access(profile_id,active);
create index student_services_staff_hr_idx on public.student_services_staff_access(hr_staff_id,active);
create index student_services_events_domain_time_idx on public.student_services_events(domain,occurred_at desc);
create index student_services_events_entity_idx on public.student_services_events(entity_type,entity_id,occurred_at desc);
create index student_services_events_actor_idx on public.student_services_events(actor_id,occurred_at desc);

alter table public.student_services_staff_access enable row level security;
alter table public.student_services_events enable row level security;
revoke all on table public.student_services_staff_access,public.student_services_events from public,anon,authenticated;
grant all on table public.student_services_staff_access,public.student_services_events to service_role;

create or replace function public.student_services_touch_updated_at()
returns trigger language plpgsql set search_path='public','pg_catalog' as $$
begin new.updated_at=now(); return new; end $$;

create or replace function public.student_services_block_delete()
returns trigger language plpgsql security definer set search_path='public','pg_catalog' as $$
begin
  if current_setting('app.student_services_allow_hard_delete',true)='on' then return old; end if;
  raise exception 'Student Services history cannot be hard deleted; use lifecycle status instead' using errcode='42501';
end $$;

create trigger student_services_staff_touch before update on public.student_services_staff_access for each row execute function public.student_services_touch_updated_at();
create trigger student_services_staff_audit after insert or update or delete on public.student_services_staff_access for each row execute function public.audit_row_change();
create trigger student_services_staff_no_delete before delete on public.student_services_staff_access for each row execute function public.student_services_block_delete();
create trigger student_services_events_no_delete before delete on public.student_services_events for each row execute function public.student_services_block_delete();

create or replace function public.student_services_actor_context()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare
  v_app_role text;
  v_roles jsonb;
  v_license jsonb;
begin
  select public.current_app_role_for(p.role) into v_app_role from public.profiles p where p.id=auth.uid() and p.active;
  if v_app_role is null then raise exception 'Active profile required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(a.service_role order by a.service_role),'[]'::jsonb) into v_roles
  from public.student_services_staff_access a where a.profile_id=auth.uid() and a.active;
  v_license:=public.license_access_for_actor(auth.uid());
  return jsonb_build_object('app_role',v_app_role,'service_roles',v_roles,'license',v_license,'aal',public.current_aal());
end $$;

create or replace function public.student_services_has_access(target_domain text,target_action text default 'read')
returns boolean language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare
  v_app_role text;
  v_license jsonb;
  v_roles text[];
  v_allowed boolean:=false;
begin
  select public.current_app_role_for(p.role) into v_app_role from public.profiles p where p.id=auth.uid() and p.active;
  if v_app_role is null then return false; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if coalesce((v_license->>'read_allowed')::boolean,false)=false then return false; end if;
  if target_action not in ('read','write','approve','publish','enroll','configure','summary') then return false; end if;
  if target_action<>'read' and target_action<>'summary' and coalesce((v_license->>'write_allowed')::boolean,false)=false then return false; end if;

  if v_app_role='system_admin' then return true; end if;
  if v_app_role='principal' then
    return case target_domain
      when 'admissions' then target_action in ('read','approve','summary')
      when 'discipline' then target_action in ('read','approve','summary')
      when 'welfare' then target_action in ('read','approve','summary')
      when 'health' then target_action in ('summary')
      when 'communications' then target_action in ('read','approve','summary')
      when 'hostel' then target_action in ('read','approve','summary')
      when 'alumni' then target_action in ('read','summary')
      else false end;
  end if;

  select coalesce(array_agg(a.service_role),array[]::text[]) into v_roles
  from public.student_services_staff_access a where a.profile_id=auth.uid() and a.active;

  if target_domain='admissions' and 'admissions_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','approve','enroll','summary'); end if;
  if target_domain='discipline' and 'welfare_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','approve','summary'); end if;
  if target_domain='welfare' and 'welfare_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','approve','summary'); end if;
  if target_domain='health' and 'clinic_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','summary'); end if;
  if target_domain='communications' and 'communications_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','publish','summary'); end if;
  if target_domain='hostel' and ('hostel_manager'=any(v_roles) or 'house_parent'=any(v_roles)) then
    v_allowed:=target_action in ('read','write','summary') or (target_action='configure' and 'hostel_manager'=any(v_roles));
  end if;
  if target_domain='alumni' and 'alumni_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','summary'); end if;
  return v_allowed;
end $$;

create or replace function public.student_services_require_access(target_domain text,target_action text default 'read')
returns void language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
  if not public.student_services_has_access(target_domain,target_action) then raise exception 'Student Services access denied' using errcode='42501'; end if;
  if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required' using errcode='42501'; end if;
end $$;

create or replace function public.student_services_session()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare c jsonb;
begin
  c:=public.student_services_actor_context();
  return c||jsonb_build_object('capabilities',jsonb_build_object(
    'admissions_read',public.student_services_has_access('admissions','read'),
    'admissions_write',public.student_services_has_access('admissions','write'),
    'admissions_approve',public.student_services_has_access('admissions','approve'),
    'admissions_enroll',public.student_services_has_access('admissions','enroll'),
    'discipline_read',public.student_services_has_access('discipline','read'),
    'discipline_write',public.student_services_has_access('discipline','write'),
    'welfare_read',public.student_services_has_access('welfare','read'),
    'welfare_write',public.student_services_has_access('welfare','write'),
    'health_read',public.student_services_has_access('health','read'),
    'health_write',public.student_services_has_access('health','write'),
    'health_summary',public.student_services_has_access('health','summary'),
    'communications_read',public.student_services_has_access('communications','read'),
    'communications_write',public.student_services_has_access('communications','write'),
    'communications_publish',public.student_services_has_access('communications','publish'),
    'hostel_read',public.student_services_has_access('hostel','read'),
    'hostel_write',public.student_services_has_access('hostel','write'),
    'hostel_configure',public.student_services_has_access('hostel','configure'),
    'alumni_read',public.student_services_has_access('alumni','read'),
    'alumni_write',public.student_services_has_access('alumni','write'),
    'manage_staff',(c->>'app_role')='system_admin'
  ));
end $$;

create or replace function public.student_services_staff_candidates(search_text text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage Student Services appointments' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name) from (
    select h.id hr_staff_id,h.profile_id,h.staff_no,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,h.department,h.job_title
    from public.hr_staff_members h
    where h.active and h.deleted_at is null and h.profile_id is not null
      and (search_text is null or concat_ws(' ',h.first_name,h.middle_name,h.last_name,h.staff_no,h.department,h.job_title) ilike '%'||search_text||'%')
    order by full_name limit 100
  ) q),'[]'::jsonb);
end $$;

create or replace function public.student_services_staff_register()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage Student Services appointments' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name,q.service_role) from (
    select a.id,a.profile_id,a.hr_staff_id,a.service_role,a.active,a.appointed_at,h.staff_no,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,h.department,h.job_title
    from public.student_services_staff_access a join public.hr_staff_members h on h.id=a.hr_staff_id
  ) q),'[]'::jsonb);
end $$;

create or replace function public.student_services_save_staff_access(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;v_profile uuid;v_hr uuid;v_role text;v_active boolean;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage Student Services appointments' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  v_id:=nullif(payload->>'id','')::uuid; v_hr:=(payload->>'hr_staff_id')::uuid; v_role:=payload->>'service_role'; v_active:=coalesce((payload->>'active')::boolean,true);
  if v_role not in ('admissions_officer','welfare_officer','clinic_officer','communications_officer','hostel_manager','house_parent','alumni_officer') then raise exception 'Invalid Student Services role'; end if;
  select h.profile_id into v_profile from public.hr_staff_members h where h.id=v_hr and h.active and h.deleted_at is null;
  if v_profile is null then raise exception 'Selected staff member has no active user profile'; end if;
  if v_id is null then
    insert into public.student_services_staff_access(profile_id,hr_staff_id,service_role,active,appointed_by)
    values(v_profile,v_hr,v_role,v_active,auth.uid())
    on conflict(profile_id,service_role) do update set hr_staff_id=excluded.hr_staff_id,active=excluded.active,appointed_by=auth.uid(),appointed_at=now(),updated_at=now()
    returning id into v_id;
  else
    update public.student_services_staff_access set profile_id=v_profile,hr_staff_id=v_hr,service_role=v_role,active=v_active,appointed_by=auth.uid(),updated_at=now() where id=v_id returning id into v_id;
  end if;
  if v_active then update public.profiles set mfa_required=true where id=v_profile; end if;
  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values('communications','staff_access_saved','student_services_staff_access',v_id,auth.uid(),jsonb_build_object('service_role',v_role,'active',v_active));
  return v_id;
end $$;

revoke all on function public.student_services_touch_updated_at() from public,anon,authenticated;
revoke all on function public.student_services_block_delete() from public,anon,authenticated;
revoke all on function public.student_services_actor_context() from public,anon,authenticated;
revoke all on function public.student_services_has_access(text,text) from public,anon,authenticated;
revoke all on function public.student_services_require_access(text,text) from public,anon,authenticated;
revoke all on function public.student_services_session() from public,anon,authenticated;
revoke all on function public.student_services_staff_candidates(text) from public,anon,authenticated;
revoke all on function public.student_services_staff_register() from public,anon,authenticated;
revoke all on function public.student_services_save_staff_access(jsonb) from public,anon,authenticated;
grant execute on function public.student_services_session() to authenticated;
grant execute on function public.student_services_staff_candidates(text) to authenticated;
grant execute on function public.student_services_staff_register() to authenticated;
grant execute on function public.student_services_save_staff_access(jsonb) to authenticated;
grant execute on function public.student_services_touch_updated_at(),public.student_services_block_delete(),public.student_services_actor_context(),public.student_services_has_access(text,text),public.student_services_require_access(text,text) to service_role;

commit;