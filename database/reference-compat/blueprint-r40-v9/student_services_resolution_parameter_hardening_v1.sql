create or replace function public.discipline_resolve_incident(target_incident_id uuid,resolution_notes text,new_status text default 'resolved')
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('discipline','approve');
 if $3 not in ('resolved','referred','cancelled') then raise exception 'Invalid incident outcome'; end if;
 update public.discipline_incidents i set status=$3,resolution_notes=nullif($2,''),resolved_by=auth.uid(),resolved_at=case when $3 in ('resolved','cancelled') then now() else null end where i.id=$1 and i.status not in ('resolved','cancelled');
 if not found then raise exception 'Incident is finalized or unavailable'; end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('discipline','incident_outcome','discipline_incident',$1,auth.uid(),jsonb_build_object('status',$3));
end $$;

create or replace function public.welfare_close_case(target_case_id uuid,closure_notes text,new_status text default 'closed')
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('welfare','approve');
 if $3 not in ('closed','cancelled','referred') then raise exception 'Invalid welfare outcome'; end if;
 update public.welfare_cases w set status=$3,closure_notes=nullif($2,''),closed_by=case when $3 in ('closed','cancelled') then auth.uid() else null end,closed_at=case when $3 in ('closed','cancelled') then now() else null end where w.id=$1 and w.status not in ('closed','cancelled');
 if not found then raise exception 'Welfare case is finalized or unavailable'; end if;
end $$;

create or replace function public.hostel_resolve_incident(target_incident_id uuid,resolution_notes text,new_status text default 'resolved')
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('hostel','write');
 if $3 not in ('resolved','referred','cancelled') then raise exception 'Invalid hostel incident outcome'; end if;
 update public.hostel_incidents i set status=$3,resolution_notes=nullif($2,''),resolved_by=auth.uid(),resolved_at=case when $3 in ('resolved','cancelled') then now() else null end where i.id=$1 and i.status not in ('resolved','cancelled');
 if not found then raise exception 'Hostel incident is finalized or unavailable'; end if;
end $$;

revoke all on function public.discipline_resolve_incident(uuid,text,text),public.welfare_close_case(uuid,text,text),public.hostel_resolve_incident(uuid,text,text) from public,anon,authenticated;
grant execute on function public.discipline_resolve_incident(uuid,text,text),public.welfare_close_case(uuid,text,text),public.hostel_resolve_incident(uuid,text,text) to authenticated;