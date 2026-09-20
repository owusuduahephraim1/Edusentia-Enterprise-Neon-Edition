-- Certified source commit: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source blob SHA: 32758d3679784cf40cff43a085e093646f2bad47
-- Neon adaptation: SQL ACL/policy target roles only. Business authorization logic is unchanged.

-- Edusentia Enterprise r40
-- Academic configuration security, calendar integrity, grading precision and readiness.
-- This migration does not invent academic dates, curriculum assignments or teacher appointments.

select set_config('app.change_reason','Academic configuration integrity hardening',true);

create or replace function public.is_academic_manager()
returns boolean
language sql
stable
security definer
set search_path='public','extensions'
as $$
  select coalesce(
    public.has_role(array['system_admin'])
    and public.current_aal()='aal2',
    false
  )
$$;

-- Academic configuration is read through SELECT/RPC and written only through
-- protected SECURITY DEFINER RPCs. Browser roles keep SELECT only.
do $$
declare t text;
begin
  foreach t in array array[
    'academic_years','terms','classes','subjects','class_subjects',
    'grading_scales','assessment_schemes','assessment_components'
  ] loop
    execute format('revoke all privileges on table public.%I from public',t);
    execute format('revoke insert,update,delete,truncate,references,trigger on table public.%I from edusentia_worker_runtime',t);
    execute format('grant select on table public.%I to edusentia_worker_runtime',t);
    execute format('drop policy if exists license_feature_select_guard_v730 on public.%I',t);
    execute format('drop policy if exists platform_license_select_guard on public.%I',t);
    execute format('drop policy if exists platform_license_insert_guard on public.%I',t);
    execute format('drop policy if exists platform_license_update_guard on public.%I',t);
    execute format('drop policy if exists platform_license_delete_guard on public.%I',t);
  end loop;
end
$$;

drop policy if exists academic_years_license_read_restrict on public.academic_years;
create policy academic_years_license_read_restrict on public.academic_years
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('core_records')));

drop policy if exists terms_license_read_restrict on public.terms;
create policy terms_license_read_restrict on public.terms
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('core_records')));

drop policy if exists classes_license_read_restrict on public.classes;
create policy classes_license_read_restrict on public.classes
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('core_records')));

drop policy if exists subjects_license_read_restrict on public.subjects;
create policy subjects_license_read_restrict on public.subjects
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('core_records')));

drop policy if exists class_subjects_license_read_restrict on public.class_subjects;
create policy class_subjects_license_read_restrict on public.class_subjects
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('core_records')));

drop policy if exists grading_scales_license_read_restrict on public.grading_scales;
create policy grading_scales_license_read_restrict on public.grading_scales
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('assessment')));

drop policy if exists assessment_schemes_license_read_restrict on public.assessment_schemes;
create policy assessment_schemes_license_read_restrict on public.assessment_schemes
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('assessment')));

drop policy if exists assessment_components_license_read_restrict on public.assessment_components;
create policy assessment_components_license_read_restrict on public.assessment_components
  as restrictive for select to edusentia_worker_runtime
  using (public.license_read_allowed() and (public.is_platform_super_admin() or public.license_feature_enabled('assessment')));

create or replace function public.validate_academic_year_calendar_integrity()
returns trigger
language plpgsql
security definer
set search_path='public','extensions'
as $$
begin
  if new.deleted_at is null and new.start_date is not null and new.end_date is not null then
    if exists(
      select 1 from public.academic_years y
      where y.id<>new.id and y.deleted_at is null
        and y.start_date is not null and y.end_date is not null
        and daterange(y.start_date,y.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')
    ) then
      raise exception 'Academic year dates cannot overlap another academic year';
    end if;

    if exists(
      select 1 from public.terms t
      where t.academic_year_id=new.id and t.deleted_at is null
        and ((t.start_date is not null and t.start_date<new.start_date)
          or (t.end_date is not null and t.end_date>new.end_date))
    ) then
      raise exception 'Academic year dates cannot exclude an existing term';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists academic_year_calendar_integrity on public.academic_years;
create trigger academic_year_calendar_integrity
before insert or update of start_date,end_date,deleted_at on public.academic_years
for each row execute function public.validate_academic_year_calendar_integrity();

create or replace function public.validate_term_calendar_integrity()
returns trigger
language plpgsql
security definer
set search_path='public','extensions'
as $$
declare
  year_start date;
  year_end date;
  year_deleted timestamptz;
begin
  select y.start_date,y.end_date,y.deleted_at
  into year_start,year_end,year_deleted
  from public.academic_years y
  where y.id=new.academic_year_id;

  if not found or year_deleted is not null then
    raise exception 'Term must belong to an active academic-year record';
  end if;

  if new.deleted_at is null then
    if new.start_date is not null and year_start is not null and new.start_date<year_start then
      raise exception 'Term start date cannot be before the academic year start date';
    end if;
    if new.end_date is not null and year_end is not null and new.end_date>year_end then
      raise exception 'Term end date cannot be after the academic year end date';
    end if;
    if new.start_date is not null and new.end_date is not null and exists(
      select 1 from public.terms t
      where t.academic_year_id=new.academic_year_id
        and t.id<>new.id
        and t.deleted_at is null
        and t.start_date is not null and t.end_date is not null
        and daterange(t.start_date,t.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')
    ) then
      raise exception 'Term dates cannot overlap another term in the same academic year';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists term_calendar_integrity on public.terms;
create trigger term_calendar_integrity
before insert or update of academic_year_id,start_date,end_date,deleted_at on public.terms
for each row execute function public.validate_term_calendar_integrity();

create or replace function public.sync_current_academic_year_status()
returns uuid
language plpgsql
security definer
set search_path='public','pg_catalog','extensions'
as $$
declare
  current_year_id uuid;
  current_term_id uuid;
begin
  select y.id into current_year_id
  from public.academic_years y
  where y.deleted_at is null
    and y.start_date is not null
    and y.start_date<=current_date
    and (y.end_date is null or y.end_date>=current_date)
  order by y.start_date desc,y.created_at desc
  limit 1;

  if current_year_id is not null then
    select t.id into current_term_id
    from public.terms t
    where t.academic_year_id=current_year_id
      and t.deleted_at is null
      and t.start_date is not null
      and t.start_date<=current_date
      and (t.end_date is null or t.end_date>=current_date)
    order by t.start_date desc,t.sequence desc
    limit 1;
  end if;

  update public.terms t
  set is_active=false,updated_at=now()
  where t.deleted_at is null and t.is_active
    and t.id is distinct from current_term_id;

  update public.academic_years y
  set is_active=false,updated_at=now()
  where y.deleted_at is null and y.is_active
    and y.id is distinct from current_year_id;

  if current_year_id is not null then
    update public.academic_years y
    set is_active=true,updated_at=now()
    where y.id=current_year_id and y.deleted_at is null and not y.is_active;
  end if;

  if current_term_id is not null then
    update public.terms t
    set is_active=true,updated_at=now()
    where t.id=current_term_id and t.deleted_at is null and not t.is_active;
  end if;

  return current_year_id;
end
$$;

create or replace function public.term_calendar_status_trigger()
returns trigger
language plpgsql
security definer
set search_path='public','extensions'
as $$
begin
  if pg_trigger_depth()>1 then return null; end if;
  perform public.sync_current_academic_year_status();
  return null;
end
$$;

drop trigger if exists term_calendar_auto_status on public.terms;
create trigger term_calendar_auto_status
after insert or delete or update of academic_year_id,start_date,end_date,deleted_at on public.terms
for each statement execute function public.term_calendar_status_trigger();

create or replace function public.set_active_period(target_academic_year_id uuid,target_term_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','extensions'
as $$
declare
  y_start date;
  y_end date;
  t_start date;
  t_end date;
begin
  if not public.is_academic_manager() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select y.start_date,y.end_date,t.start_date,t.end_date
  into y_start,y_end,t_start,t_end
  from public.academic_years y
  join public.terms t on t.academic_year_id=y.id
  where y.id=target_academic_year_id and y.deleted_at is null
    and t.id=target_term_id and t.deleted_at is null;

  if not found then
    raise exception 'The selected term does not belong to the selected academic year';
  end if;

  if y_start is null or current_date<y_start or (y_end is not null and current_date>y_end)
     or t_start is null or current_date<t_start or (t_end is not null and current_date>t_end) then
    raise exception 'Academic periods are calendar-controlled and cannot be activated before or after their configured dates';
  end if;

  perform set_config('app.change_reason','Calendar-controlled academic period synchronization',true);
  perform public.sync_current_academic_year_status();
  return public.get_bootstrap_data();
end
$$;

-- Re-evaluate date-derived status whenever term date configuration changes.
create or replace function public.term_calendar_status_trigger()
returns trigger
language plpgsql
security definer
set search_path='public','extensions'
as $$
begin
  if pg_trigger_depth()>1 then return null; end if;
  perform public.sync_current_academic_year_status();
  return null;
end
$$;

drop trigger if exists term_calendar_auto_status on public.terms;
create trigger term_calendar_auto_status
after insert or delete or update of academic_year_id,start_date,end_date,deleted_at on public.terms
for each statement execute function public.term_calendar_status_trigger();

-- Two-decimal subject scores need continuous grade coverage. Repair only small
-- gaps between adjacent bands; do not rewrite school-defined thresholds.
with ordered as (
  select g.id,g.max_mark,
    lead(g.min_mark) over(
      partition by g.academic_year_id,g.class_id,g.subject_id
      order by g.min_mark
    ) as next_min
  from public.grading_scales g
  where g.deleted_at is null
), fixes as (
  select id,next_min-0.01 as repaired_max
  from ordered
  where next_min is not null
    and next_min>max_mark
    and next_min-max_mark<=1.00
    and max_mark<next_min-0.01
)
update public.grading_scales g
set max_mark=f.repaired_max,updated_at=now()
from fixes f
where g.id=f.id;

update public.grading_scales
set remark='Weak',updated_at=now()
where deleted_at is null and lower(btrim(remark))='week';

create or replace function public.academic_configuration_readiness()
returns jsonb
language plpgsql
security definer
set search_path='public','extensions'
as $$
declare
  target_year_id uuid;
  target_year_name text;
  target_year_start date;
  target_year_end date;
  term_count integer:=0;
  last_term_end date;
  term_gap_days integer:=0;
  enrolled_class_count integer:=0;
  zero_subject_count integer:=0;
  no_class_teacher_count integer:=0;
  grading_issue_count integer:=0;
  scheme_issue_count integer:=0;
  active_scheme_count integer:=0;
  zero_subject_classes jsonb:='[]'::jsonb;
  no_class_teacher_classes jsonb:='[]'::jsonb;
  grading_issues jsonb:='[]'::jsonb;
  scheme_issues jsonb:='[]'::jsonb;
  blocking_count integer:=0;
  warning_count integer:=0;
begin
  if not public.is_academic_manager() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select y.id,y.name::text,y.start_date,y.end_date
  into target_year_id,target_year_name,target_year_start,target_year_end
  from public.academic_years y
  where y.deleted_at is null
    and (
      (y.start_date is not null and y.start_date<=current_date and (y.end_date is null or y.end_date>=current_date))
      or y.start_date>current_date
    )
  order by
    case when y.start_date<=current_date and (y.end_date is null or y.end_date>=current_date) then 0 else 1 end,
    y.start_date
  limit 1;

  if target_year_id is null then
    return jsonb_build_object(
      'ready',false,'status','attention','blocking_count',1,'warning_count',0,
      'target_academic_year',null,'term_count',0,'term_coverage_gap_days',null,
      'enrolled_class_count',0,'classes_without_subjects','[]'::jsonb,
      'classes_without_class_teacher','[]'::jsonb,
      'grading_issues','[]'::jsonb,'assessment_scheme_issues','[]'::jsonb,
      'message','No current or upcoming academic year is configured.'
    );
  end if;

  select count(*)::int,max(t.end_date)
  into term_count,last_term_end
  from public.terms t
  where t.academic_year_id=target_year_id and t.deleted_at is null;

  if target_year_end is not null and last_term_end is not null and last_term_end<target_year_end then
    term_gap_days:=target_year_end-last_term_end;
  end if;

  with enrolled_classes as (
    select c.id,c.name::text,c.level_order,c.class_teacher_id,
      count(distinct e.id)::int as enrollment_count,
      count(distinct cs.id) filter(where cs.active)::int as subject_count
    from public.enrollments e
    join public.classes c on c.id=e.class_id and c.deleted_at is null and c.active
    left join public.class_subjects cs on cs.class_id=c.id and cs.active
    where e.academic_year_id=target_year_id and e.active and e.deleted_at is null
    group by c.id,c.name,c.level_order,c.class_teacher_id
  )
  select
    count(*)::int,
    count(*) filter(where subject_count=0)::int,
    count(*) filter(where class_teacher_id is null)::int,
    coalesce(jsonb_agg(jsonb_build_object('class_id',id,'class_name',name,'enrollments',enrollment_count)
      order by level_order) filter(where subject_count=0),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('class_id',id,'class_name',name,'enrollments',enrollment_count)
      order by level_order) filter(where class_teacher_id is null),'[]'::jsonb)
  into enrolled_class_count,zero_subject_count,no_class_teacher_count,zero_subject_classes,no_class_teacher_classes
  from enrolled_classes;

  with bands as (
    select g.id,g.academic_year_id,g.class_id,g.subject_id,g.min_mark,g.max_mark,
      lead(g.min_mark) over(
        partition by g.academic_year_id,g.class_id,g.subject_id
        order by g.min_mark
      ) as next_min
    from public.grading_scales g
    where g.deleted_at is null
  ), scope_summary as (
    select academic_year_id,class_id,subject_id,
      min(min_mark) as first_min,max(max_mark) as last_max,
      count(*) filter(where next_min is not null and next_min-max_mark>0.01)::int as internal_gaps
    from bands
    group by academic_year_id,class_id,subject_id
  ), problems as (
    select s.*,ay.name::text as academic_year_name,c.name::text as class_name,sb.name::text as subject_name
    from scope_summary s
    left join public.academic_years ay on ay.id=s.academic_year_id
    left join public.classes c on c.id=s.class_id
    left join public.subjects sb on sb.id=s.subject_id
    where s.first_min>0 or s.last_max<100 or s.internal_gaps>0
  )
  select count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object(
      'academic_year',academic_year_name,'class_name',class_name,'subject_name',subject_name,
      'first_min',first_min,'last_max',last_max,'internal_gaps',internal_gaps
    )),'[]'::jsonb)
  into grading_issue_count,grading_issues
  from problems;

  select count(*)::int into active_scheme_count
  from public.assessment_schemes s
  where s.deleted_at is null and s.active;

  with problems as (
    select s.id,s.name::text as name,count(c.id)::int as component_count,coalesce(sum(c.weight),0) as total_weight
    from public.assessment_schemes s
    left join public.assessment_components c on c.scheme_id=s.id
    where s.deleted_at is null and s.active
    group by s.id,s.name
    having count(c.id)=0 or abs(coalesce(sum(c.weight),0)-100)>0.01
  )
  select count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object('scheme_id',id,'name',name,'components',component_count,'total_weight',total_weight)),'[]'::jsonb)
  into scheme_issue_count,scheme_issues
  from problems;

  blocking_count:=zero_subject_count+grading_issue_count+scheme_issue_count;
  if term_count=0 then blocking_count:=blocking_count+1; end if;
  if active_scheme_count=0 then blocking_count:=blocking_count+1; end if;

  warning_count:=no_class_teacher_count;
  if term_gap_days>21 then warning_count:=warning_count+1; end if;

  return jsonb_build_object(
    'ready',blocking_count=0,
    'status',case when blocking_count=0 and warning_count=0 then 'ready' else 'attention' end,
    'blocking_count',blocking_count,
    'warning_count',warning_count,
    'checked_at',now(),
    'target_academic_year',jsonb_build_object(
      'id',target_year_id,'name',target_year_name,'start_date',target_year_start,'end_date',target_year_end
    ),
    'term_count',term_count,
    'last_term_end',last_term_end,
    'term_coverage_gap_days',term_gap_days,
    'enrolled_class_count',enrolled_class_count,
    'classes_without_subjects',zero_subject_classes,
    'classes_without_class_teacher',no_class_teacher_classes,
    'grading_issues',grading_issues,
    'assessment_scheme_issues',scheme_issues,
    'active_assessment_schemes',active_scheme_count
  );
end
$$;

revoke all on function public.academic_configuration_readiness() from public;
grant execute on function public.academic_configuration_readiness() to edusentia_worker_runtime;

select public.sync_current_academic_year_status();


insert into app.schema_migrations(version)
values ('0030_certified_academic_configuration')
on conflict do nothing;

update app.release_identity
set schema_version='0030'
where edition='Edusentia Enterprise Neon Edition';
