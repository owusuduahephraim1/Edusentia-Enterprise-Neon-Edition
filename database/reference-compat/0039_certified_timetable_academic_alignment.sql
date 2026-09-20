-- Certified source commit: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified hardening source blob SHA: 5687c10c3dcea867a7cf40e5b19d74848c081c89
-- class_timetable_entries schema/constraints/indexes and can_view_class_timetable()
-- were extracted read-only from the certified production database.
-- Supabase realtime.broadcast_changes transport is intentionally not recreated;
-- Neon event delivery is handled at the Worker/outbox layer.

begin;

create table if not exists public.class_timetable_entries(
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references public.academic_years(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  day_of_week text not null,
  period_start time without time zone not null,
  period_end time without time zone not null,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  teacher_id uuid not null references public.teachers(id) on delete restrict,
  notes text not null default '',
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint class_timetable_entries_check check(period_end>period_start),
  constraint class_timetable_entries_active_weekday_check
    check(not active or day_of_week in('Monday','Tuesday','Wednesday','Thursday','Friday'))
);

create index if not exists class_timetable_class_day_idx
  on public.class_timetable_entries(academic_year_id,class_id,day_of_week,period_start)
  where active;
create index if not exists class_timetable_teacher_day_idx
  on public.class_timetable_entries(academic_year_id,teacher_id,day_of_week,period_start)
  where active;

alter table public.class_timetable_entries enable row level security;
revoke all on table public.class_timetable_entries from public;
revoke all on table public.class_timetable_entries from edusentia_worker_runtime;

CREATE OR REPLACE FUNCTION public.can_view_class_timetable(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select public.current_app_role() in ('system_admin','principal') or (public.current_app_role() in ('class_teacher','subject_teacher') and public.can_access_class(target_class_id,false))
$function$;

-- Edusentia Enterprise r40 — Timetable academic alignment hardening
--
-- Keeps timetable entries aligned with Academics: only active class-subject
-- assignments may be scheduled, and the scheduled teacher must be the teacher
-- assigned to that class subject. Existing timetable AAL2/licence protections
-- remain in force.

create or replace function public.validate_class_timetable_entry()
returns trigger
language plpgsql
set search_path to 'public','extensions'
as $$
declare
  assigned_profile_id uuid;
  selected_teacher_profile_id uuid;
begin
  if not new.active then return new; end if;

  if new.day_of_week not in ('Monday','Tuesday','Wednesday','Thursday','Friday') then
    raise exception 'Timetable day must be Monday to Friday';
  end if;
  if new.period_end<=new.period_start then
    raise exception 'Period end time must be after start time';
  end if;
  if not exists(select 1 from public.academic_years y where y.id=new.academic_year_id and y.deleted_at is null) then
    raise exception 'Academic year not found';
  end if;
  if not exists(select 1 from public.classes c where c.id=new.class_id and c.deleted_at is null and c.active) then
    raise exception 'Class not found or inactive';
  end if;
  if not exists(select 1 from public.subjects s where s.id=new.subject_id and s.deleted_at is null and s.active) then
    raise exception 'Subject not found or inactive';
  end if;

  select t.profile_id into selected_teacher_profile_id
  from public.teachers t
  where t.id=new.teacher_id and t.deleted_at is null and t.active and t.employment_status='active';
  if selected_teacher_profile_id is null then
    raise exception 'Teacher not found, inactive, or not linked to a teaching account';
  end if;

  select cs.teacher_id into assigned_profile_id
  from public.class_subjects cs
  where cs.class_id=new.class_id and cs.subject_id=new.subject_id and cs.active
  limit 1;
  if assigned_profile_id is null then
    raise exception 'The selected subject is not actively assigned to this class';
  end if;
  if assigned_profile_id<>selected_teacher_profile_id then
    raise exception 'The selected teacher is not the assigned teacher for this class subject';
  end if;

  if exists(
    select 1 from public.class_timetable_entries x
    where x.active and x.academic_year_id=new.academic_year_id and x.class_id=new.class_id
      and x.day_of_week=new.day_of_week
      and x.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
      and x.period_start<new.period_end and x.period_end>new.period_start
  ) then
    raise exception 'This class already has an overlapping timetable period';
  end if;

  if exists(
    select 1 from public.class_timetable_entries x
    where x.active and x.academic_year_id=new.academic_year_id and x.teacher_id=new.teacher_id
      and x.day_of_week=new.day_of_week
      and x.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
      and x.period_start<new.period_end and x.period_end>new.period_start
  ) then
    raise exception 'The selected teacher already has another class during this time';
  end if;

  return new;
end
$$;

drop trigger if exists class_timetable_entry_integrity_guard on public.class_timetable_entries;
create trigger class_timetable_entry_integrity_guard
before insert or update on public.class_timetable_entries
for each row execute function public.validate_class_timetable_entry();

revoke all on function public.validate_class_timetable_entry() from public,edusentia_worker_runtime;

create or replace function public.get_class_timetable_console(target_academic_year_id uuid,target_class_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','extensions'
as $$
declare
  v_can_manage boolean:=public.is_system_admin() and public.current_aal()='aal2';
begin
  if target_academic_year_id is null or target_class_id is null then raise exception 'Academic year and class are required'; end if;
  if not public.can_view_class_timetable(target_class_id) then raise exception 'You are not allowed to view this class timetable' using errcode='42501'; end if;
  perform public.require_license_feature('timetable');
  return jsonb_build_object(
    'academic_year',(select to_jsonb(y) from public.academic_years y where y.id=target_academic_year_id and y.deleted_at is null),
    'class',(select to_jsonb(c) from public.classes c where c.id=target_class_id and c.deleted_at is null),
    'entries',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'academic_year_id',e.academic_year_id,'class_id',e.class_id,'day_of_week',e.day_of_week,
        'period_start',e.period_start,'period_end',e.period_end,'subject_id',e.subject_id,'subject_name',s.name,
        'teacher_id',e.teacher_id,'teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
        'notes',e.notes,'active',e.active,'updated_at',e.updated_at
      ) order by array_position(array['Monday','Tuesday','Wednesday','Thursday','Friday'],e.day_of_week),e.period_start)
      from public.class_timetable_entries e
      join public.subjects s on s.id=e.subject_id
      join public.teachers t on t.id=e.teacher_id
      where e.academic_year_id=target_academic_year_id
        and e.class_id=target_class_id and e.active
        and e.day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday')
    ),'[]'::jsonb),
    'teachers',case when v_can_manage then coalesce((
      select jsonb_agg(distinct jsonb_build_object(
        'id',t.id,'name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no
      ))
      from public.class_subjects cs
      join public.teachers t on t.profile_id=cs.teacher_id
      where cs.class_id=target_class_id and cs.active
        and t.deleted_at is null and t.active and t.employment_status='active'
    ),'[]'::jsonb) else '[]'::jsonb end,
    'subjects',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'name',s.name,'code',s.code,'assigned_teacher_profile_id',cs.teacher_id,
        'assigned_teacher_id',t.id,'assigned_teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
      ) order by s.display_order,s.name)
      from public.class_subjects cs
      join public.subjects s on s.id=cs.subject_id and s.deleted_at is null and s.active
      left join public.teachers t on t.profile_id=cs.teacher_id and t.deleted_at is null and t.active and t.employment_status='active'
      where cs.class_id=target_class_id and cs.active
    ),'[]'::jsonb),
    'can_manage',v_can_manage
  );
end
$$;

create or replace function public.save_class_timetable_entry(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $$
declare
  eid uuid:=public.safe_uuid(payload->>'id');
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id');
  classid uuid:=public.safe_uuid(payload->>'class_id');
  subjectid uuid:=public.safe_uuid(payload->>'subject_id');
  teacherid uuid:=public.safe_uuid(payload->>'teacher_id');
  day_value text:=initcap(lower(btrim(coalesce(payload->>'day_of_week',''))));
  start_value time;end_value time;current_updated timestamptz;
  expected_updated timestamptz:=public.safe_timestamptz(payload->>'updated_at');
  assigned_profile_id uuid;selected_teacher_profile_id uuid;
  row public.class_timetable_entries%rowtype;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage class timetables' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  perform public.require_license_feature('timetable');
  if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit timetable changes' using errcode='42501'; end if;
  if yearid is null or classid is null or subjectid is null or teacherid is null then raise exception 'Academic year, class, subject, and teacher are required'; end if;
  if day_value not in ('Monday','Tuesday','Wednesday','Thursday','Friday') then raise exception 'Timetable day must be Monday to Friday'; end if;
  begin start_value:=(payload->>'period_start')::time;end_value:=(payload->>'period_end')::time;exception when others then raise exception 'Period start and end times are invalid';end;
  if end_value<=start_value then raise exception 'Period end time must be after start time'; end if;
  if not exists(select 1 from public.academic_years where id=yearid and deleted_at is null) then raise exception 'Academic year not found'; end if;
  if not exists(select 1 from public.classes where id=classid and deleted_at is null and active) then raise exception 'Class not found'; end if;
  if not exists(select 1 from public.subjects where id=subjectid and deleted_at is null and active) then raise exception 'Subject not found'; end if;
  select profile_id into selected_teacher_profile_id from public.teachers where id=teacherid and deleted_at is null and active and employment_status='active';
  if selected_teacher_profile_id is null then raise exception 'Teacher not found or not active'; end if;
  select cs.teacher_id into assigned_profile_id from public.class_subjects cs where cs.class_id=classid and cs.subject_id=subjectid and cs.active limit 1;
  if assigned_profile_id is null then raise exception 'The selected subject is not actively assigned to this class'; end if;
  if assigned_profile_id<>selected_teacher_profile_id then raise exception 'The selected teacher is not the assigned teacher for this class subject'; end if;
  if eid is not null then
    select updated_at into current_updated from public.class_timetable_entries where id=eid and active for update;
    if current_updated is null then raise exception 'Timetable period not found'; end if;
    if expected_updated is not null and current_updated<>expected_updated then raise exception 'This timetable period changed in another session. Reload and try again.'; end if;
  end if;
  if exists(select 1 from public.class_timetable_entries x where x.active and x.academic_year_id=yearid and x.class_id=classid and x.day_of_week=day_value and (eid is null or x.id<>eid) and x.period_start<end_value and x.period_end>start_value) then raise exception 'This class already has an overlapping timetable period'; end if;
  if exists(select 1 from public.class_timetable_entries x where x.active and x.academic_year_id=yearid and x.teacher_id=teacherid and x.day_of_week=day_value and (eid is null or x.id<>eid) and x.period_start<end_value and x.period_end>start_value) then raise exception 'The selected teacher already has another class during this time'; end if;
  if eid is null then
    insert into public.class_timetable_entries(academic_year_id,class_id,day_of_week,period_start,period_end,subject_id,teacher_id,notes,created_by)
    values(yearid,classid,day_value,start_value,end_value,subjectid,teacherid,btrim(coalesce(payload->>'notes','')),auth.uid()) returning * into row;
  else
    update public.class_timetable_entries set academic_year_id=yearid,class_id=classid,day_of_week=day_value,period_start=start_value,period_end=end_value,subject_id=subjectid,teacher_id=teacherid,notes=btrim(coalesce(payload->>'notes','')),updated_at=now() where id=eid returning * into row;
  end if;
  return to_jsonb(row);
end
$$;


drop trigger if exists class_timetable_entries_audit on public.class_timetable_entries;
create trigger class_timetable_entries_audit
after insert or delete or update on public.class_timetable_entries
for each row execute function public.audit_row_change();

revoke all on function public.can_view_class_timetable(uuid) from public;
revoke all on function public.can_view_class_timetable(uuid) from edusentia_worker_runtime;
revoke all on function public.validate_class_timetable_entry() from public;
revoke all on function public.validate_class_timetable_entry() from edusentia_worker_runtime;
revoke all on function public.get_class_timetable_console(uuid,uuid) from public;
revoke all on function public.get_class_timetable_console(uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.save_class_timetable_entry(jsonb) from public;
revoke all on function public.save_class_timetable_entry(jsonb) from edusentia_worker_runtime;

grant execute on function public.get_class_timetable_console(uuid,uuid)
  to edusentia_worker_runtime;
grant execute on function public.save_class_timetable_entry(jsonb)
  to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0039_certified_timetable_academic_alignment')
on conflict do nothing;

update app.release_identity
set schema_version='0039'
where edition='Edusentia Enterprise Neon Edition';

commit;
