begin;

create table public.discipline_incidents (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete restrict,
 occurred_at timestamptz not null default now(),
 incident_type text not null,
 severity text not null default 'medium' check(severity in ('low','medium','high','critical')),
 location text,
 summary text not null,
 details text,
 status text not null default 'open' check(status in ('open','under_review','resolved','referred','cancelled')),
 guardian_visible boolean not null default false,
 guardian_notified_at timestamptz,
 reported_by uuid references public.profiles(id) on delete set null,
 resolved_by uuid references public.profiles(id) on delete set null,
 resolved_at timestamptz,
 resolution_notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.discipline_actions (
 id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.discipline_incidents(id) on delete restrict,
 action_type text not null check(action_type in ('merit','demerit','warning','detention','suspension','counselling','parent_contact','referral','restorative_action','other')),
 action_notes text not null,
 starts_at timestamptz,
 ends_at timestamptz,
 status text not null default 'active' check(status in ('planned','active','completed','cancelled')),
 assigned_hr_staff_id uuid references public.hr_staff_members(id) on delete set null,
 created_by uuid references public.profiles(id) on delete set null,
 completed_by uuid references public.profiles(id) on delete set null,
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.discipline_guardian_acknowledgements (
 id uuid primary key default gen_random_uuid(),
 incident_id uuid not null references public.discipline_incidents(id) on delete restrict,
 student_id uuid not null references public.students(id) on delete restrict,
 guardian_user_id uuid references public.profiles(id) on delete set null,
 guardian_name text,
 acknowledgement_note text,
 acknowledged_at timestamptz not null default now(),
 unique(incident_id,guardian_user_id)
);

create table public.welfare_cases (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete restrict,
 category text not null,
 priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
 summary text not null,
 confidential_notes text,
 status text not null default 'open' check(status in ('open','monitoring','referred','closed','cancelled')),
 assigned_hr_staff_id uuid references public.hr_staff_members(id) on delete set null,
 guardian_contact_status text not null default 'not_required' check(guardian_contact_status in ('not_required','pending','contacted','declined','not_safe')),
 guardian_contacted_at timestamptz,
 external_referral text,
 opened_by uuid references public.profiles(id) on delete set null,
 opened_at timestamptz not null default now(),
 closed_by uuid references public.profiles(id) on delete set null,
 closed_at timestamptz,
 closure_notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.welfare_case_notes (
 id uuid primary key default gen_random_uuid(),
 case_id uuid not null references public.welfare_cases(id) on delete restrict,
 note_type text not null default 'progress' check(note_type in ('progress','meeting','referral','guardian_contact','safeguarding','other')),
 note text not null,
 confidential boolean not null default true,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now()
);

create index discipline_incidents_student_time_idx on public.discipline_incidents(student_id,occurred_at desc);
create index discipline_incidents_status_idx on public.discipline_incidents(status,severity,occurred_at desc);
create index discipline_incidents_reported_by_idx on public.discipline_incidents(reported_by);
create index discipline_incidents_resolved_by_idx on public.discipline_incidents(resolved_by);
create index discipline_actions_incident_idx on public.discipline_actions(incident_id,created_at desc);
create index discipline_actions_assigned_staff_idx on public.discipline_actions(assigned_hr_staff_id);
create index discipline_actions_created_by_idx on public.discipline_actions(created_by);
create index discipline_actions_completed_by_idx on public.discipline_actions(completed_by);
create index discipline_ack_student_idx on public.discipline_guardian_acknowledgements(student_id,acknowledged_at desc);
create index welfare_cases_student_idx on public.welfare_cases(student_id,opened_at desc);
create index welfare_cases_status_idx on public.welfare_cases(status,priority,opened_at desc);
create index welfare_cases_assigned_idx on public.welfare_cases(assigned_hr_staff_id,status);
create index welfare_cases_opened_by_idx on public.welfare_cases(opened_by);
create index welfare_cases_closed_by_idx on public.welfare_cases(closed_by);
create index welfare_notes_case_idx on public.welfare_case_notes(case_id,created_at desc);
create index welfare_notes_created_by_idx on public.welfare_case_notes(created_by);

alter table public.discipline_incidents enable row level security;
alter table public.discipline_actions enable row level security;
alter table public.discipline_guardian_acknowledgements enable row level security;
alter table public.welfare_cases enable row level security;
alter table public.welfare_case_notes enable row level security;
revoke all on table public.discipline_incidents,public.discipline_actions,public.discipline_guardian_acknowledgements,public.welfare_cases,public.welfare_case_notes from public,anon,authenticated;
grant all on table public.discipline_incidents,public.discipline_actions,public.discipline_guardian_acknowledgements,public.welfare_cases,public.welfare_case_notes to service_role;

create trigger discipline_incident_touch before update on public.discipline_incidents for each row execute function public.student_services_touch_updated_at();
create trigger discipline_action_touch before update on public.discipline_actions for each row execute function public.student_services_touch_updated_at();
create trigger welfare_case_touch before update on public.welfare_cases for each row execute function public.student_services_touch_updated_at();
create trigger discipline_incident_audit after insert or update or delete on public.discipline_incidents for each row execute function public.audit_row_change();
create trigger discipline_action_audit after insert or update or delete on public.discipline_actions for each row execute function public.audit_row_change();
create trigger discipline_ack_audit after insert or update or delete on public.discipline_guardian_acknowledgements for each row execute function public.audit_row_change();
create trigger welfare_case_audit after insert or update or delete on public.welfare_cases for each row execute function public.audit_row_change();
create trigger welfare_note_audit after insert or update or delete on public.welfare_case_notes for each row execute function public.audit_row_change();
create trigger discipline_incident_no_delete before delete on public.discipline_incidents for each row execute function public.student_services_block_delete();
create trigger discipline_action_no_delete before delete on public.discipline_actions for each row execute function public.student_services_block_delete();
create trigger discipline_ack_no_delete before delete on public.discipline_guardian_acknowledgements for each row execute function public.student_services_block_delete();
create trigger welfare_case_no_delete before delete on public.welfare_cases for each row execute function public.student_services_block_delete();
create trigger welfare_note_no_delete before delete on public.welfare_case_notes for each row execute function public.student_services_block_delete();

create or replace function public.discipline_dashboard()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('discipline','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'open_incidents',(select count(*) from public.discipline_incidents where status in ('open','under_review','referred')),
  'critical_open',(select count(*) from public.discipline_incidents where status in ('open','under_review','referred') and severity='critical'),
  'guardian_pending',(select count(*) from public.discipline_incidents where guardian_visible and guardian_notified_at is null and status<>'cancelled'),
  'open_welfare',(select count(*) from public.welfare_cases where status in ('open','monitoring','referred')),
  'urgent_welfare',(select count(*) from public.welfare_cases where status in ('open','monitoring','referred') and priority='urgent')
 ));
end $$;

create or replace function public.discipline_incident_register(search_text text default null,status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('discipline','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (
  select i.id,i.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,i.occurred_at,i.incident_type,i.severity,i.location,i.summary,i.status,i.guardian_visible,i.guardian_notified_at,i.resolved_at,
   (select count(*) from public.discipline_actions a where a.incident_id=i.id) action_count,
   (select count(*) from public.discipline_guardian_acknowledgements g where g.incident_id=i.id) acknowledgement_count
  from public.discipline_incidents i join public.students s on s.id=i.student_id
  where (status_filter is null or i.status=status_filter)
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,i.incident_type,i.summary) ilike '%'||search_text||'%')
  order by i.occurred_at desc limit 300
 )q),'[]'::jsonb);
end $$;

create or replace function public.discipline_incident_detail(target_incident_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare r jsonb;
begin
 perform public.student_services_require_access('discipline','read');
 select to_jsonb(q) into r from (select i.*,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name from public.discipline_incidents i join public.students s on s.id=i.student_id where i.id=target_incident_id)q;
 if r is null then raise exception 'Incident not found'; end if;
 return r||jsonb_build_object(
  'actions',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.discipline_actions a where a.incident_id=target_incident_id),'[]'::jsonb),
  'acknowledgements',coalesce((select jsonb_agg(to_jsonb(g) order by g.acknowledged_at) from public.discipline_guardian_acknowledgements g where g.incident_id=target_incident_id),'[]'::jsonb)
 );
end $$;

create or replace function public.discipline_save_incident(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('discipline','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
  insert into public.discipline_incidents(student_id,occurred_at,incident_type,severity,location,summary,details,status,guardian_visible,reported_by)
  values((payload->>'student_id')::uuid,coalesce(nullif(payload->>'occurred_at','')::timestamptz,now()),btrim(payload->>'incident_type'),coalesce(nullif(payload->>'severity',''),'medium'),nullif(btrim(payload->>'location'),''),btrim(payload->>'summary'),nullif(payload->>'details',''),coalesce(nullif(payload->>'status',''),'open'),coalesce((payload->>'guardian_visible')::boolean,false),auth.uid()) returning id into v_id;
 else
  update public.discipline_incidents set incident_type=coalesce(nullif(btrim(payload->>'incident_type'),''),incident_type),severity=coalesce(nullif(payload->>'severity',''),severity),location=case when payload ? 'location' then nullif(btrim(payload->>'location'),'') else location end,summary=coalesce(nullif(btrim(payload->>'summary'),''),summary),details=case when payload ? 'details' then nullif(payload->>'details','') else details end,guardian_visible=coalesce((payload->>'guardian_visible')::boolean,guardian_visible) where id=v_id and status not in ('resolved','cancelled');
  if not found then raise exception 'Incident is finalized or unavailable'; end if;
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('discipline','incident_saved','discipline_incident',v_id,auth.uid(),'{}');
 return v_id;
end $$;

create or replace function public.discipline_add_action(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('discipline','write');
 if not exists(select 1 from public.discipline_incidents where id=(payload->>'incident_id')::uuid and status not in ('resolved','cancelled')) then raise exception 'Incident is finalized or unavailable'; end if;
 insert into public.discipline_actions(incident_id,action_type,action_notes,starts_at,ends_at,status,assigned_hr_staff_id,created_by)
 values((payload->>'incident_id')::uuid,payload->>'action_type',btrim(payload->>'action_notes'),nullif(payload->>'starts_at','')::timestamptz,nullif(payload->>'ends_at','')::timestamptz,coalesce(nullif(payload->>'status',''),'active'),nullif(payload->>'assigned_hr_staff_id','')::uuid,auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.discipline_resolve_incident(target_incident_id uuid,resolution_notes text,new_status text default 'resolved')
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('discipline','approve');
 if new_status not in ('resolved','referred','cancelled') then raise exception 'Invalid incident outcome'; end if;
 update public.discipline_incidents set status=new_status,resolution_notes=nullif(resolution_notes,''),resolved_by=auth.uid(),resolved_at=case when new_status in ('resolved','cancelled') then now() else null end where id=target_incident_id and status not in ('resolved','cancelled');
 if not found then raise exception 'Incident is finalized or unavailable'; end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('discipline','incident_outcome','discipline_incident',target_incident_id,auth.uid(),jsonb_build_object('status',new_status));
end $$;

create or replace function public.discipline_notify_guardian(target_incident_id uuid)
returns integer language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_student uuid;v_summary text;v_count integer:=0;
begin
 perform public.student_services_require_access('discipline','write');
 select student_id,summary into v_student,v_summary from public.discipline_incidents where id=target_incident_id and guardian_visible and status<>'cancelled' for update;
 if v_student is null then raise exception 'Incident is not available for guardian notification'; end if;
 insert into public.notifications(recipient_id,title,body,category,entity_type,entity_id)
 select distinct g.auth_user_id,'Student welfare/discipline update',v_summary,'discipline','discipline_incident',target_incident_id
 from public.guardian_links g where g.student_id=v_student and g.auth_user_id is not null and g.can_receive_notifications
 on conflict do nothing;
 get diagnostics v_count=row_count;
 update public.discipline_incidents set guardian_notified_at=now() where id=target_incident_id;
 return v_count;
end $$;

create or replace function public.discipline_my_children_incidents()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (
  select i.id,i.student_id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,i.occurred_at,i.incident_type,i.severity,i.summary,i.status,i.guardian_notified_at,
   exists(select 1 from public.discipline_guardian_acknowledgements a where a.incident_id=i.id and a.guardian_user_id=auth.uid()) acknowledged
  from public.discipline_incidents i join public.students s on s.id=i.student_id
  where i.guardian_visible and exists(select 1 from public.guardian_links g where g.student_id=i.student_id and g.auth_user_id=auth.uid() and g.can_view_reports)
 )q),'[]'::jsonb);
end $$;

create or replace function public.discipline_acknowledge_incident(target_incident_id uuid,acknowledgement_note text default null)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_student uuid;v_id uuid;v_name text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select i.student_id into v_student from public.discipline_incidents i where i.id=target_incident_id and i.guardian_visible and exists(select 1 from public.guardian_links g where g.student_id=i.student_id and g.auth_user_id=auth.uid() and g.can_view_reports);
 if v_student is null then raise exception 'Incident not available to this guardian' using errcode='42501'; end if;
 select full_name into v_name from public.profiles where id=auth.uid();
 insert into public.discipline_guardian_acknowledgements(incident_id,student_id,guardian_user_id,guardian_name,acknowledgement_note) values(target_incident_id,v_student,auth.uid(),v_name,nullif(acknowledgement_note,'')) on conflict(incident_id,guardian_user_id) do update set acknowledgement_note=excluded.acknowledgement_note,acknowledged_at=now() returning id into v_id;
 return v_id;
end $$;

create or replace function public.welfare_case_register(search_text text default null,status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare v_role text;
begin
 perform public.student_services_require_access('welfare','read');
 select public.current_app_role_for(p.role) into v_role from public.profiles p where p.id=auth.uid();
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.opened_at desc) from (
  select w.id,w.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,w.category,w.priority,w.summary,w.status,w.guardian_contact_status,w.external_referral,w.opened_at,w.closed_at,
   case when v_role='principal' then null else w.confidential_notes end confidential_notes,
   case when v_role='principal' then 0 else (select count(*) from public.welfare_case_notes n where n.case_id=w.id) end note_count
  from public.welfare_cases w join public.students s on s.id=w.student_id
  where (status_filter is null or w.status=status_filter) and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,w.category,w.summary) ilike '%'||search_text||'%')
 )q),'[]'::jsonb);
end $$;

create or replace function public.welfare_case_detail(target_case_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare v_role text;r jsonb;
begin
 perform public.student_services_require_access('welfare','read');
 select public.current_app_role_for(p.role) into v_role from public.profiles p where p.id=auth.uid();
 select to_jsonb(q) into r from (select w.id,w.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,w.category,w.priority,w.summary,case when v_role='principal' then null else w.confidential_notes end confidential_notes,w.status,w.assigned_hr_staff_id,w.guardian_contact_status,w.guardian_contacted_at,w.external_referral,w.opened_at,w.closed_at,w.closure_notes from public.welfare_cases w join public.students s on s.id=w.student_id where w.id=target_case_id)q;
 if r is null then raise exception 'Welfare case not found'; end if;
 if v_role='principal' then return r||jsonb_build_object('notes','[]'::jsonb); end if;
 return r||jsonb_build_object('notes',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at) from public.welfare_case_notes n where n.case_id=target_case_id),'[]'::jsonb));
end $$;

create or replace function public.welfare_save_case(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('welfare','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.welfare_cases(student_id,category,priority,summary,confidential_notes,status,assigned_hr_staff_id,guardian_contact_status,external_referral,opened_by) values((payload->>'student_id')::uuid,btrim(payload->>'category'),coalesce(nullif(payload->>'priority',''),'normal'),btrim(payload->>'summary'),nullif(payload->>'confidential_notes',''),coalesce(nullif(payload->>'status',''),'open'),nullif(payload->>'assigned_hr_staff_id','')::uuid,coalesce(nullif(payload->>'guardian_contact_status',''),'not_required'),nullif(payload->>'external_referral',''),auth.uid()) returning id into v_id;
 else update public.welfare_cases set category=coalesce(nullif(btrim(payload->>'category'),''),category),priority=coalesce(nullif(payload->>'priority',''),priority),summary=coalesce(nullif(btrim(payload->>'summary'),''),summary),confidential_notes=case when payload ? 'confidential_notes' then nullif(payload->>'confidential_notes','') else confidential_notes end,assigned_hr_staff_id=case when payload ? 'assigned_hr_staff_id' then nullif(payload->>'assigned_hr_staff_id','')::uuid else assigned_hr_staff_id end,guardian_contact_status=coalesce(nullif(payload->>'guardian_contact_status',''),guardian_contact_status),guardian_contacted_at=case when payload->>'guardian_contact_status'='contacted' then coalesce(guardian_contacted_at,now()) else guardian_contacted_at end,external_referral=case when payload ? 'external_referral' then nullif(payload->>'external_referral','') else external_referral end where id=v_id and status not in ('closed','cancelled');
 end if; return v_id;
end $$;

create or replace function public.welfare_add_note(target_case_id uuid,note_type text,note_text text,confidential boolean default true)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('welfare','write');
 if not exists(select 1 from public.welfare_cases where id=target_case_id and status not in ('closed','cancelled')) then raise exception 'Welfare case is closed or unavailable'; end if;
 insert into public.welfare_case_notes(case_id,note_type,note,confidential,created_by) values(target_case_id,note_type,btrim(note_text),coalesce(confidential,true),auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.welfare_close_case(target_case_id uuid,closure_notes text,new_status text default 'closed')
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('welfare','approve');
 if new_status not in ('closed','cancelled','referred') then raise exception 'Invalid welfare outcome'; end if;
 update public.welfare_cases set status=new_status,closure_notes=nullif(closure_notes,''),closed_by=case when new_status in ('closed','cancelled') then auth.uid() else null end,closed_at=case when new_status in ('closed','cancelled') then now() else null end where id=target_case_id and status not in ('closed','cancelled');
 if not found then raise exception 'Welfare case is finalized or unavailable'; end if;
end $$;

revoke all on function public.discipline_dashboard(),public.discipline_incident_register(text,text),public.discipline_incident_detail(uuid),public.discipline_save_incident(jsonb),public.discipline_add_action(jsonb),public.discipline_resolve_incident(uuid,text,text),public.discipline_notify_guardian(uuid),public.discipline_my_children_incidents(),public.discipline_acknowledge_incident(uuid,text),public.welfare_case_register(text,text),public.welfare_case_detail(uuid),public.welfare_save_case(jsonb),public.welfare_add_note(uuid,text,text,boolean),public.welfare_close_case(uuid,text,text) from public,anon,authenticated;
grant execute on function public.discipline_dashboard(),public.discipline_incident_register(text,text),public.discipline_incident_detail(uuid),public.discipline_save_incident(jsonb),public.discipline_add_action(jsonb),public.discipline_resolve_incident(uuid,text,text),public.discipline_notify_guardian(uuid),public.welfare_case_register(text,text),public.welfare_case_detail(uuid),public.welfare_save_case(jsonb),public.welfare_add_note(uuid,text,text,boolean),public.welfare_close_case(uuid,text,text) to authenticated;
grant execute on function public.discipline_my_children_incidents(),public.discipline_acknowledge_incident(uuid,text) to authenticated;

commit;