-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Governance table contracts and function bodies extracted read-only from certified production.
-- Supabase authenticated/service_role ACLs are mapped to a function-mediated Neon Worker boundary.

begin;

create table if not exists public.academic_period_controls(
  term_id uuid primary key references public.terms(id) on delete cascade,
  score_entry_deadline timestamptz,
  attendance_deadline timestamptz,
  report_submission_deadline timestamptz,
  principal_approval_deadline timestamptz,
  publication_deadline timestamptz,
  scores_locked boolean not null default false,
  attendance_locked boolean not null default false,
  reports_locked boolean not null default false,
  lock_reason text not null default '',
  locked_by uuid references public.profiles(id) on delete set null,
  locked_at timestamptz,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.emergency_academic_delegations(
  id uuid primary key default gen_random_uuid(),
  delegation_type text not null constraint emergency_academic_delegations_delegation_type_check check(delegation_type in('replacement_teacher','system_admin_override')),
  academic_year_id uuid not null references public.academic_years(id) on delete restrict,
  term_id uuid not null references public.terms(id) on delete restrict,
  class_id uuid not null references public.classes(id) on delete restrict,
  subject_id uuid references public.subjects(id) on delete restrict,
  original_teacher_id uuid references public.profiles(id) on delete set null,
  delegate_user_id uuid not null references public.profiles(id) on delete restrict,
  allow_score_entry boolean not null default true,
  allow_class_report_fields boolean not null default false,
  valid_from timestamptz not null default now(),
  valid_until timestamptz not null,
  reason text not null constraint emergency_academic_delegations_reason_check check(length(btrim(reason))>=10),
  status text not null default 'active' constraint emergency_academic_delegations_status_check check(status in('active','revoked')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  principal_acknowledged_at timestamptz,
  principal_acknowledged_by uuid references public.profiles(id) on delete set null,
  principal_acknowledgement_note text not null default '',
  revoked_at timestamptz,
  revoked_by uuid references public.profiles(id) on delete set null,
  revocation_reason text not null default '',
  constraint emergency_academic_delegations_check check(valid_until>valid_from),
  constraint emergency_academic_delegations_check1 check(valid_until<=valid_from+interval '120 days'),
  constraint emergency_academic_delegations_check2 check(allow_score_entry or allow_class_report_fields),
  constraint emergency_academic_delegations_check3 check(subject_id is null or allow_class_report_fields=false),
  constraint emergency_academic_delegations_check4 check((status='active' and revoked_at is null) or (status='revoked' and revoked_at is not null))
);

create table if not exists public.report_correction_requests(
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.student_reports(id) on delete cascade,
  requested_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  reason text not null constraint report_correction_requests_reason_check check(length(btrim(reason))>=10),
  requested_fields jsonb not null default '[]'::jsonb,
  status text not null default 'pending' constraint report_correction_requests_status_check check(status in('pending','approved','rejected','cancelled','applied')),
  original_report_version integer not null,
  original_revision_id uuid references public.report_revisions(id) on delete set null,
  original_publication_id uuid references public.report_publications(id) on delete set null,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_note text not null default '',
  correction_revision_id uuid references public.report_revisions(id) on delete set null,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.report_correction_events(
  id bigint generated always as identity primary key,
  request_id uuid not null references public.report_correction_requests(id) on delete cascade,
  event_type text not null,
  actor_id uuid default auth.uid() references public.profiles(id) on delete set null,
  event_note text not null default '',
  event_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists emergency_academic_delegations_console_idx
  on public.emergency_academic_delegations(created_at desc);
create index if not exists emergency_academic_delegations_delegate_idx
  on public.emergency_academic_delegations(delegate_user_id,term_id,class_id,valid_until desc)
  where status='active';
create index if not exists emergency_academic_delegations_scope_idx
  on public.emergency_academic_delegations(term_id,class_id,subject_id,valid_from,valid_until);
create unique index if not exists report_correction_one_pending_idx
  on public.report_correction_requests(report_id) where status='pending';
create index if not exists report_correction_status_created_idx
  on public.report_correction_requests(status,created_at desc);

alter table public.academic_period_controls enable row level security;
alter table public.emergency_academic_delegations enable row level security;
alter table public.emergency_academic_delegations force row level security;
alter table public.report_correction_requests enable row level security;
alter table public.report_correction_events enable row level security;

revoke all on table public.academic_period_controls from public;
revoke all on table public.emergency_academic_delegations from public;
revoke all on table public.report_correction_requests from public;
revoke all on table public.report_correction_events from public;
revoke all on table public.academic_period_controls from edusentia_worker_runtime;
revoke all on table public.emergency_academic_delegations from edusentia_worker_runtime;
revoke all on table public.report_correction_requests from edusentia_worker_runtime;
revoke all on table public.report_correction_events from edusentia_worker_runtime;

CREATE OR REPLACE FUNCTION public.active_emergency_delegation_ids(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean DEFAULT false, require_class_fields boolean DEFAULT false, target_user_id uuid DEFAULT auth.uid())
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(array_agg(d.id order by d.valid_until,d.created_at),'{}'::uuid[])
  from public.emergency_academic_delegations d
  join public.profiles p on p.id=d.delegate_user_id and p.active
  join public.terms t on t.id=d.term_id and t.deleted_at is null
  join public.academic_years y on y.id=d.academic_year_id and y.deleted_at is null
  join public.classes c on c.id=d.class_id and c.active and c.deleted_at is null
  where d.delegate_user_id=target_user_id
    and d.class_id=target_class_id
    and d.term_id=target_term_id
    and t.academic_year_id=d.academic_year_id
    and d.status='active'
    and now()>=d.valid_from
    and now()<d.valid_until
    and (not require_score_entry or d.allow_score_entry)
    and (not require_class_fields or d.allow_class_report_fields)
    and (
      target_subject_id is null
      or d.subject_id is null
      or d.subject_id=target_subject_id
    )
$function$;

CREATE OR REPLACE FUNCTION public.has_active_emergency_delegation(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean DEFAULT false, require_class_fields boolean DEFAULT false, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select cardinality(public.active_emergency_delegation_ids(
    target_class_id,target_subject_id,target_term_id,
    require_score_entry,require_class_fields,target_user_id
  ))>0
$function$;

CREATE OR REPLACE FUNCTION public.is_official_class_teacher_for_class(target_class_id uuid, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.classes c
    where c.id=target_class_id and c.class_teacher_id=target_user_id
      and c.active and c.deleted_at is null
  )
$function$;

CREATE OR REPLACE FUNCTION public.is_official_subject_teacher_for_class(target_class_id uuid, target_subject_id uuid, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.class_subjects cs
    join public.classes c on c.id=cs.class_id
    join public.subjects s on s.id=cs.subject_id
    where cs.class_id=target_class_id and cs.subject_id=target_subject_id
      and cs.teacher_id=target_user_id and cs.active
      and c.active and c.deleted_at is null
      and s.active and s.deleted_at is null
  )
$function$;

CREATE OR REPLACE FUNCTION public.has_approved_report_correction(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.report_correction_requests r
    where r.report_id=target_report_id and r.status='approved'
      and r.reviewed_at>=now()-interval '180 days'
  )
$function$;

CREATE OR REPLACE FUNCTION public.term_control_snapshot(target_term_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select jsonb_build_object(
    'term_id',t.id,'term_name',t.name,'academic_year_id',t.academic_year_id,
    'score_entry_deadline',c.score_entry_deadline,'attendance_deadline',c.attendance_deadline,
    'report_submission_deadline',c.report_submission_deadline,
    'principal_approval_deadline',c.principal_approval_deadline,
    'publication_deadline',c.publication_deadline,
    'scores_locked',coalesce(c.scores_locked,false) or (c.score_entry_deadline is not null and now()>c.score_entry_deadline),
    'attendance_locked',coalesce(c.attendance_locked,false) or (c.attendance_deadline is not null and now()>c.attendance_deadline),
    'reports_locked',coalesce(c.reports_locked,false),
    'submission_overdue',c.report_submission_deadline is not null and now()>c.report_submission_deadline,
    'approval_overdue',c.principal_approval_deadline is not null and now()>c.principal_approval_deadline,
    'publication_overdue',c.publication_deadline is not null and now()>c.publication_deadline,
    'lock_reason',coalesce(c.lock_reason,''),'locked_at',c.locked_at
  )
  from public.terms t left join public.academic_period_controls c on c.term_id=t.id
  where t.id=target_term_id and t.deleted_at is null
$function$;

CREATE OR REPLACE FUNCTION public.term_phase_writable(target_term_id uuid, target_phase text, target_report_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb;
begin
  if not public.license_write_allowed() then return false; end if;
  s:=public.term_control_snapshot(target_term_id);
  if s is null then return false; end if;
  if target_report_id is not null and public.has_approved_report_correction(target_report_id) then return true; end if;
  if target_phase='scores' then return not coalesce((s->>'scores_locked')::boolean,false) and ((s->>'score_entry_deadline') is null or (s->>'score_entry_deadline')::timestamptz>=now()); end if;
  if target_phase='attendance' then return not coalesce((s->>'attendance_locked')::boolean,false) and ((s->>'attendance_deadline') is null or (s->>'attendance_deadline')::timestamptz>=now()); end if;
  if target_phase='reports' then return not coalesce((s->>'reports_locked')::boolean,false) and ((s->>'report_submission_deadline') is null or (s->>'report_submission_deadline')::timestamptz>=now()); end if;
  return false;
end $function$;

CREATE OR REPLACE FUNCTION public.can_manage_class_report_fields_scope(target_class_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_official_class_teacher_for_class(target_class_id,auth.uid())
    or public.has_active_emergency_delegation(target_class_id,null,target_term_id,false,true,auth.uid())
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_class_report_fields_for_term(target_class_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.term_phase_writable(target_term_id,'reports',null) and public.can_manage_class_report_fields_scope(target_class_id,target_term_id)
$function$;

CREATE OR REPLACE FUNCTION public.can_score_class_subject_scope(target_class_id uuid, target_subject_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_official_subject_teacher_for_class(target_class_id,target_subject_id,auth.uid())
    or public.is_official_class_teacher_for_class(target_class_id,auth.uid())
    or public.has_active_emergency_delegation(target_class_id,target_subject_id,target_term_id,true,false,auth.uid())
$function$;

CREATE OR REPLACE FUNCTION public.can_score_class_subject_for_term(target_class_id uuid, target_subject_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.term_phase_writable(target_term_id,'scores',null) and public.can_score_class_subject_scope(target_class_id,target_subject_id,target_term_id)
$function$;

CREATE OR REPLACE FUNCTION public.get_my_emergency_academic_delegations(target_class_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(q) order by q.valid_until,q.class_name,q.subject_name nulls first),'[]'::jsonb)
  from (
    select d.id,d.delegation_type,d.academic_year_id,d.term_id,d.class_id,d.subject_id,
      d.allow_score_entry,d.allow_class_report_fields,d.valid_from,d.valid_until,d.reason,
      d.principal_acknowledged_at,c.name class_name,t.name term_name,y.name academic_year_name,
      s.name subject_name,op.full_name original_teacher_name,cp.full_name created_by_name
    from public.emergency_academic_delegations d
    join public.classes c on c.id=d.class_id
    join public.terms t on t.id=d.term_id
    join public.academic_years y on y.id=d.academic_year_id
    left join public.subjects s on s.id=d.subject_id
    left join public.profiles op on op.id=d.original_teacher_id
    left join public.profiles cp on cp.id=d.created_by
    where d.delegate_user_id=auth.uid()
      and d.status='active' and now()>=d.valid_from and now()<d.valid_until
      and (target_class_id is null or d.class_id=target_class_id)
      and (target_term_id is null or d.term_id=target_term_id)
  ) q
$function$;

CREATE OR REPLACE FUNCTION public.is_academic_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(
    public.has_role(array['system_admin'])
    and public.current_aal()='aal2',
    false
  )
$function$;

CREATE OR REPLACE FUNCTION public.report_transition_deadline_allowed(target_report_id uuid, target_status report_status)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb; deadline_value timestamptz;
begin
  if public.has_approved_report_correction(target_report_id) then return true; end if;
  s:=public.term_control_snapshot((select term_id from public.student_reports where id=target_report_id));
  if s is null or coalesce((s->>'reports_locked')::boolean,false) then return false; end if;
  if target_status in ('submitted','class_reviewed','returned') then deadline_value:=public.safe_timestamptz(s->>'report_submission_deadline');
  elsif target_status='approved' then deadline_value:=public.safe_timestamptz(s->>'principal_approval_deadline');
  elsif target_status in ('published','withdrawn') then deadline_value:=public.safe_timestamptz(s->>'publication_deadline');
  end if;
  return deadline_value is null or deadline_value>=now();
end $function$;

CREATE OR REPLACE FUNCTION public.mark_report_correction_applied(target_report_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  update public.report_correction_requests set status='applied',applied_at=now(),updated_at=now()
  where report_id=target_report_id and status='approved';
  insert into public.report_correction_events(request_id,event_type,event_note)
  select id,'applied','Corrected report republished' from public.report_correction_requests
  where report_id=target_report_id and status='applied' and applied_at>=now()-interval '5 seconds';
end $function$;

revoke all on function public.active_emergency_delegation_ids(uuid,uuid,uuid,boolean,boolean,uuid) from public;
revoke all on function public.has_active_emergency_delegation(uuid,uuid,uuid,boolean,boolean,uuid) from public;
revoke all on function public.is_official_class_teacher_for_class(uuid,uuid) from public;
revoke all on function public.is_official_subject_teacher_for_class(uuid,uuid,uuid) from public;
revoke all on function public.has_approved_report_correction(uuid) from public;
revoke all on function public.term_control_snapshot(uuid) from public;
revoke all on function public.term_phase_writable(uuid,text,uuid) from public;
revoke all on function public.can_manage_class_report_fields_scope(uuid,uuid) from public;
revoke all on function public.can_manage_class_report_fields_for_term(uuid,uuid) from public;
revoke all on function public.can_score_class_subject_scope(uuid,uuid,uuid) from public;
revoke all on function public.can_score_class_subject_for_term(uuid,uuid,uuid) from public;
revoke all on function public.get_my_emergency_academic_delegations(uuid,uuid) from public;
revoke all on function public.is_academic_manager() from public;
revoke all on function public.report_transition_deadline_allowed(uuid,public.report_status) from public;
revoke all on function public.mark_report_correction_applied(uuid) from public;

revoke all on function public.active_emergency_delegation_ids(uuid,uuid,uuid,boolean,boolean,uuid) from edusentia_worker_runtime;
revoke all on function public.has_active_emergency_delegation(uuid,uuid,uuid,boolean,boolean,uuid) from edusentia_worker_runtime;
revoke all on function public.is_official_class_teacher_for_class(uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.is_official_subject_teacher_for_class(uuid,uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.has_approved_report_correction(uuid) from edusentia_worker_runtime;
revoke all on function public.term_control_snapshot(uuid) from edusentia_worker_runtime;
revoke all on function public.term_phase_writable(uuid,text,uuid) from edusentia_worker_runtime;
revoke all on function public.can_manage_class_report_fields_scope(uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.can_manage_class_report_fields_for_term(uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.can_score_class_subject_scope(uuid,uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.can_score_class_subject_for_term(uuid,uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.get_my_emergency_academic_delegations(uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.is_academic_manager() from edusentia_worker_runtime;
revoke all on function public.report_transition_deadline_allowed(uuid,public.report_status) from edusentia_worker_runtime;
revoke all on function public.mark_report_correction_applied(uuid) from edusentia_worker_runtime;

grant execute on function public.get_my_emergency_academic_delegations(uuid,uuid)
  to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0043_certified_report_governance_prerequisites')
on conflict do nothing;

update app.release_identity
set schema_version='0043'
where edition='Edusentia Enterprise Neon Edition';

commit;
