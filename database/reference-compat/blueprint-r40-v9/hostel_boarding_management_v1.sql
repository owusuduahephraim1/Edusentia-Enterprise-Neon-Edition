begin;

create table public.hostel_houses (
 id uuid primary key default gen_random_uuid(),
 house_code text not null unique,
 house_name text not null,
 gender_policy text not null default 'mixed' check(gender_policy in ('male','female','mixed')),
 capacity integer check(capacity is null or capacity>0),
 house_parent_hr_staff_id uuid references public.hr_staff_members(id) on delete set null,
 active boolean not null default true,
 notes text,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.hostel_rooms (
 id uuid primary key default gen_random_uuid(),
 house_id uuid not null references public.hostel_houses(id) on delete restrict,
 room_code text not null,
 room_name text,
 floor_label text,
 capacity integer not null check(capacity>0),
 active boolean not null default true,
 notes text,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(house_id,room_code)
);

create table public.hostel_beds (
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.hostel_rooms(id) on delete restrict,
 bed_code text not null,
 status text not null default 'available' check(status in ('available','occupied','maintenance','inactive')),
 notes text,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(room_id,bed_code)
);

create table public.hostel_allocations (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete restrict,
 academic_year_id uuid not null references public.academic_years(id) on delete restrict,
 bed_id uuid not null references public.hostel_beds(id) on delete restrict,
 start_date date not null default current_date,
 end_date date,
 status text not null default 'active' check(status in ('active','ended','cancelled')),
 boarding_type text not null default 'full_boarding' check(boarding_type in ('full_boarding','weekly_boarding','temporary')),
 guardian_consent_reference text,
 allocated_by uuid references public.profiles(id) on delete set null,
 ended_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index hostel_one_active_bed_allocation_idx on public.hostel_allocations(bed_id) where status='active';
create unique index hostel_one_active_student_allocation_idx on public.hostel_allocations(student_id) where status='active';

create table public.hostel_movements (
 id uuid primary key default gen_random_uuid(),
 allocation_id uuid not null references public.hostel_allocations(id) on delete restrict,
 student_id uuid not null references public.students(id) on delete restrict,
 movement_type text not null check(movement_type in ('check_in','check_out','weekend_leave','return_from_leave','temporary_exit','return','other')),
 occurred_at timestamptz not null default now(),
 expected_return_at timestamptz,
 actual_return_at timestamptz,
 destination text,
 guardian_or_escort text,
 guardian_contact text,
 reason text,
 recorded_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now()
);

create table public.hostel_incidents (
 id uuid primary key default gen_random_uuid(),
 allocation_id uuid references public.hostel_allocations(id) on delete restrict,
 student_id uuid not null references public.students(id) on delete restrict,
 occurred_at timestamptz not null default now(),
 incident_type text not null,
 severity text not null default 'medium' check(severity in ('low','medium','high','critical')),
 summary text not null,
 details text,
 status text not null default 'open' check(status in ('open','under_review','resolved','referred','cancelled')),
 guardian_notified boolean not null default false,
 guardian_notified_at timestamptz,
 reported_by uuid references public.profiles(id) on delete set null,
 resolved_by uuid references public.profiles(id) on delete set null,
 resolved_at timestamptz,
 resolution_notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create index hostel_houses_parent_idx on public.hostel_houses(house_parent_hr_staff_id);
create index hostel_houses_created_by_idx on public.hostel_houses(created_by);
create index hostel_rooms_house_idx on public.hostel_rooms(house_id,active);
create index hostel_rooms_created_by_idx on public.hostel_rooms(created_by);
create index hostel_beds_room_status_idx on public.hostel_beds(room_id,status);
create index hostel_beds_created_by_idx on public.hostel_beds(created_by);
create index hostel_alloc_student_year_idx on public.hostel_allocations(student_id,academic_year_id,status);
create index hostel_alloc_year_idx on public.hostel_allocations(academic_year_id,status);
create index hostel_alloc_allocated_by_idx on public.hostel_allocations(allocated_by);
create index hostel_alloc_ended_by_idx on public.hostel_allocations(ended_by);
create index hostel_movements_student_time_idx on public.hostel_movements(student_id,occurred_at desc);
create index hostel_movements_allocation_idx on public.hostel_movements(allocation_id,occurred_at desc);
create index hostel_movements_recorded_by_idx on public.hostel_movements(recorded_by);
create index hostel_incidents_student_time_idx on public.hostel_incidents(student_id,occurred_at desc);
create index hostel_incidents_status_idx on public.hostel_incidents(status,severity,occurred_at desc);
create index hostel_incidents_allocation_idx on public.hostel_incidents(allocation_id);
create index hostel_incidents_reported_by_idx on public.hostel_incidents(reported_by);
create index hostel_incidents_resolved_by_idx on public.hostel_incidents(resolved_by);

alter table public.hostel_houses enable row level security;
alter table public.hostel_rooms enable row level security;
alter table public.hostel_beds enable row level security;
alter table public.hostel_allocations enable row level security;
alter table public.hostel_movements enable row level security;
alter table public.hostel_incidents enable row level security;
revoke all on table public.hostel_houses,public.hostel_rooms,public.hostel_beds,public.hostel_allocations,public.hostel_movements,public.hostel_incidents from public,anon,authenticated;
grant all on table public.hostel_houses,public.hostel_rooms,public.hostel_beds,public.hostel_allocations,public.hostel_movements,public.hostel_incidents to service_role;

create trigger hostel_house_touch before update on public.hostel_houses for each row execute function public.student_services_touch_updated_at();
create trigger hostel_room_touch before update on public.hostel_rooms for each row execute function public.student_services_touch_updated_at();
create trigger hostel_bed_touch before update on public.hostel_beds for each row execute function public.student_services_touch_updated_at();
create trigger hostel_alloc_touch before update on public.hostel_allocations for each row execute function public.student_services_touch_updated_at();
create trigger hostel_incident_touch before update on public.hostel_incidents for each row execute function public.student_services_touch_updated_at();
create trigger hostel_house_audit after insert or update or delete on public.hostel_houses for each row execute function public.audit_row_change();
create trigger hostel_room_audit after insert or update or delete on public.hostel_rooms for each row execute function public.audit_row_change();
create trigger hostel_bed_audit after insert or update or delete on public.hostel_beds for each row execute function public.audit_row_change();
create trigger hostel_alloc_audit after insert or update or delete on public.hostel_allocations for each row execute function public.audit_row_change();
create trigger hostel_movement_audit after insert or update or delete on public.hostel_movements for each row execute function public.audit_row_change();
create trigger hostel_incident_audit after insert or update or delete on public.hostel_incidents for each row execute function public.audit_row_change();
create trigger hostel_house_no_delete before delete on public.hostel_houses for each row execute function public.student_services_block_delete();
create trigger hostel_room_no_delete before delete on public.hostel_rooms for each row execute function public.student_services_block_delete();
create trigger hostel_bed_no_delete before delete on public.hostel_beds for each row execute function public.student_services_block_delete();
create trigger hostel_alloc_no_delete before delete on public.hostel_allocations for each row execute function public.student_services_block_delete();
create trigger hostel_movement_no_delete before delete on public.hostel_movements for each row execute function public.student_services_block_delete();
create trigger hostel_incident_no_delete before delete on public.hostel_incidents for each row execute function public.student_services_block_delete();

create or replace function public.hostel_dashboard()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('hostel','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'houses',(select count(*) from public.hostel_houses where active),
  'rooms',(select count(*) from public.hostel_rooms where active),
  'beds',(select count(*) from public.hostel_beds where status<>'inactive'),
  'occupied',(select count(*) from public.hostel_allocations where status='active'),
  'available',(select count(*) from public.hostel_beds b where b.status='available' and not exists(select 1 from public.hostel_allocations a where a.bed_id=b.id and a.status='active')),
  'students_out',(select count(distinct m.student_id) from public.hostel_movements m join public.hostel_allocations a on a.id=m.allocation_id where a.status='active' and m.movement_type in ('check_out','weekend_leave','temporary_exit') and not exists(select 1 from public.hostel_movements r where r.allocation_id=m.allocation_id and r.occurred_at>m.occurred_at and r.movement_type in ('check_in','return_from_leave','return'))),
  'open_incidents',(select count(*) from public.hostel_incidents where status in ('open','under_review','referred'))
 ));
end $$;

create or replace function public.hostel_register()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('hostel','read');
 return jsonb_build_object(
  'houses',coalesce((select jsonb_agg(to_jsonb(q) order by q.house_name) from (select h.*,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) house_parent_name,(select count(*) from public.hostel_rooms r where r.house_id=h.id and r.active) room_count,(select count(*) from public.hostel_allocations a join public.hostel_beds b on b.id=a.bed_id join public.hostel_rooms r on r.id=b.room_id where r.house_id=h.id and a.status='active') occupied_count from public.hostel_houses h left join public.hr_staff_members s on s.id=h.house_parent_hr_staff_id)q),'[]'::jsonb),
  'rooms',coalesce((select jsonb_agg(to_jsonb(q) order by q.house_name,q.room_code) from (select r.*,h.house_name,(select count(*) from public.hostel_beds b where b.room_id=r.id) bed_count,(select count(*) from public.hostel_allocations a join public.hostel_beds b on b.id=a.bed_id where b.room_id=r.id and a.status='active') occupied_count from public.hostel_rooms r join public.hostel_houses h on h.id=r.house_id)q),'[]'::jsonb),
  'beds',coalesce((select jsonb_agg(to_jsonb(q) order by q.house_name,q.room_code,q.bed_code) from (select b.*,r.room_code,h.house_name,exists(select 1 from public.hostel_allocations a where a.bed_id=b.id and a.status='active') occupied from public.hostel_beds b join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id)q),'[]'::jsonb)
 );
end $$;

create or replace function public.hostel_save_house(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','configure');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.hostel_houses(house_code,house_name,gender_policy,capacity,house_parent_hr_staff_id,active,notes,created_by) values(upper(btrim(payload->>'house_code')),btrim(payload->>'house_name'),coalesce(nullif(payload->>'gender_policy',''),'mixed'),nullif(payload->>'capacity','')::integer,nullif(payload->>'house_parent_hr_staff_id','')::uuid,coalesce((payload->>'active')::boolean,true),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.hostel_houses set house_name=coalesce(nullif(btrim(payload->>'house_name'),''),house_name),gender_policy=coalesce(nullif(payload->>'gender_policy',''),gender_policy),capacity=case when payload ? 'capacity' then nullif(payload->>'capacity','')::integer else capacity end,house_parent_hr_staff_id=case when payload ? 'house_parent_hr_staff_id' then nullif(payload->>'house_parent_hr_staff_id','')::uuid else house_parent_hr_staff_id end,active=coalesce((payload->>'active')::boolean,active),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $$;

create or replace function public.hostel_save_room(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','configure');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.hostel_rooms(house_id,room_code,room_name,floor_label,capacity,active,notes,created_by) values((payload->>'house_id')::uuid,upper(btrim(payload->>'room_code')),nullif(payload->>'room_name',''),nullif(payload->>'floor_label',''),(payload->>'capacity')::integer,coalesce((payload->>'active')::boolean,true),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.hostel_rooms set room_name=case when payload ? 'room_name' then nullif(payload->>'room_name','') else room_name end,floor_label=case when payload ? 'floor_label' then nullif(payload->>'floor_label','') else floor_label end,capacity=coalesce(nullif(payload->>'capacity','')::integer,capacity),active=coalesce((payload->>'active')::boolean,active),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $$;

create or replace function public.hostel_save_bed(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','configure');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.hostel_beds(room_id,bed_code,status,notes,created_by) values((payload->>'room_id')::uuid,upper(btrim(payload->>'bed_code')),coalesce(nullif(payload->>'status',''),'available'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.hostel_beds set status=coalesce(nullif(payload->>'status',''),status),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $$;

create or replace function public.hostel_allocation_register(search_text text default null,status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('hostel','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
  select a.id,a.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,a.academic_year_id,y.name academic_year,a.bed_id,b.bed_code,r.room_code,h.house_name,a.start_date,a.end_date,a.status,a.boarding_type,a.created_at
  from public.hostel_allocations a join public.students s on s.id=a.student_id join public.academic_years y on y.id=a.academic_year_id join public.hostel_beds b on b.id=a.bed_id join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id
  where (status_filter is null or a.status=status_filter) and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,h.house_name,r.room_code,b.bed_code) ilike '%'||search_text||'%')
 )q),'[]'::jsonb);
end $$;

create or replace function public.hostel_allocate_student(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;v_gender text;v_policy text;v_bed_status text;
begin
 perform public.student_services_require_access('hostel','write');
 select s.gender into v_gender from public.students s where s.id=(payload->>'student_id')::uuid and s.deleted_at is null and s.status='active';
 select h.gender_policy,b.status into v_policy,v_bed_status from public.hostel_beds b join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id where b.id=(payload->>'bed_id')::uuid and b.status<>'inactive' and r.active and h.active;
 if v_gender is null or v_policy is null then raise exception 'Student or bed unavailable'; end if;
 if v_bed_status not in ('available','occupied') then raise exception 'Bed is not available for allocation'; end if;
 if (v_policy='male' and v_gender<>'Male') or (v_policy='female' and v_gender<>'Female') then raise exception 'Student does not match house gender policy'; end if;
 if exists(select 1 from public.hostel_allocations where student_id=(payload->>'student_id')::uuid and status='active') then raise exception 'Student already has an active hostel allocation'; end if;
 if exists(select 1 from public.hostel_allocations where bed_id=(payload->>'bed_id')::uuid and status='active') then raise exception 'Bed is already occupied'; end if;
 insert into public.hostel_allocations(student_id,academic_year_id,bed_id,start_date,boarding_type,guardian_consent_reference,allocated_by) values((payload->>'student_id')::uuid,(payload->>'academic_year_id')::uuid,(payload->>'bed_id')::uuid,coalesce(nullif(payload->>'start_date','')::date,current_date),coalesce(nullif(payload->>'boarding_type',''),'full_boarding'),nullif(payload->>'guardian_consent_reference',''),auth.uid()) returning id into v_id;
 update public.hostel_beds set status='occupied' where id=(payload->>'bed_id')::uuid;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('hostel','student_allocated','hostel_allocation',v_id,auth.uid(),jsonb_build_object('student_id',payload->>'student_id','bed_id',payload->>'bed_id'));
 return v_id;
end $$;

create or replace function public.hostel_end_allocation(target_allocation_id uuid,end_reason text default null)
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_bed uuid;
begin
 perform public.student_services_require_access('hostel','write');
 select bed_id into v_bed from public.hostel_allocations where id=target_allocation_id and status='active' for update;
 if v_bed is null then raise exception 'Active allocation not found'; end if;
 update public.hostel_allocations set status='ended',end_date=current_date,ended_by=auth.uid(),updated_at=now() where id=target_allocation_id;
 update public.hostel_beds set status='available' where id=v_bed and status='occupied';
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('hostel','allocation_ended','hostel_allocation',target_allocation_id,auth.uid(),jsonb_build_object('reason',end_reason));
end $$;

create or replace function public.hostel_record_movement(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;v_student uuid;
begin
 perform public.student_services_require_access('hostel','write');
 select student_id into v_student from public.hostel_allocations where id=(payload->>'allocation_id')::uuid and status='active';
 if v_student is null then raise exception 'Active hostel allocation required'; end if;
 insert into public.hostel_movements(allocation_id,student_id,movement_type,occurred_at,expected_return_at,actual_return_at,destination,guardian_or_escort,guardian_contact,reason,recorded_by)
 values((payload->>'allocation_id')::uuid,v_student,payload->>'movement_type',coalesce(nullif(payload->>'occurred_at','')::timestamptz,now()),nullif(payload->>'expected_return_at','')::timestamptz,nullif(payload->>'actual_return_at','')::timestamptz,nullif(payload->>'destination',''),nullif(payload->>'guardian_or_escort',''),nullif(payload->>'guardian_contact',''),nullif(payload->>'reason',''),auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.hostel_movement_register(target_allocation_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('hostel','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (select m.*,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name from public.hostel_movements m join public.students s on s.id=m.student_id where target_allocation_id is null or m.allocation_id=target_allocation_id order by m.occurred_at desc limit 300)q),'[]'::jsonb);
end $$;

create or replace function public.hostel_save_incident(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('hostel','write');
 insert into public.hostel_incidents(allocation_id,student_id,occurred_at,incident_type,severity,summary,details,guardian_notified,guardian_notified_at,reported_by)
 values(nullif(payload->>'allocation_id','')::uuid,(payload->>'student_id')::uuid,coalesce(nullif(payload->>'occurred_at','')::timestamptz,now()),btrim(payload->>'incident_type'),coalesce(nullif(payload->>'severity',''),'medium'),btrim(payload->>'summary'),nullif(payload->>'details',''),coalesce((payload->>'guardian_notified')::boolean,false),case when coalesce((payload->>'guardian_notified')::boolean,false) then now() end,auth.uid()) returning id into v_id;
 return v_id;
end $$;

create or replace function public.hostel_incident_register(status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('hostel','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (select i.*,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name from public.hostel_incidents i join public.students s on s.id=i.student_id where status_filter is null or i.status=status_filter)q),'[]'::jsonb);
end $$;

create or replace function public.hostel_resolve_incident(target_incident_id uuid,resolution_notes text,new_status text default 'resolved')
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('hostel','write');
 if new_status not in ('resolved','referred','cancelled') then raise exception 'Invalid hostel incident outcome'; end if;
 update public.hostel_incidents set status=new_status,resolution_notes=nullif(resolution_notes,''),resolved_by=auth.uid(),resolved_at=case when new_status in ('resolved','cancelled') then now() else null end where id=target_incident_id and status not in ('resolved','cancelled');
 if not found then raise exception 'Hostel incident is finalized or unavailable'; end if;
end $$;

create or replace function public.hostel_my_children_boarding()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.student_name) from (
  select a.id allocation_id,a.student_id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,y.name academic_year,h.house_name,r.room_code,b.bed_code,a.boarding_type,a.start_date,
   (select jsonb_build_object('movement_type',m.movement_type,'occurred_at',m.occurred_at,'expected_return_at',m.expected_return_at,'destination',m.destination) from public.hostel_movements m where m.allocation_id=a.id order by m.occurred_at desc limit 1) latest_movement
  from public.guardian_links g join public.hostel_allocations a on a.student_id=g.student_id and a.status='active' join public.students s on s.id=a.student_id join public.academic_years y on y.id=a.academic_year_id join public.hostel_beds b on b.id=a.bed_id join public.hostel_rooms r on r.id=b.room_id join public.hostel_houses h on h.id=r.house_id
  where g.auth_user_id=auth.uid() and g.can_view_reports
 )q),'[]'::jsonb);
end $$;

revoke all on function public.hostel_dashboard(),public.hostel_register(),public.hostel_save_house(jsonb),public.hostel_save_room(jsonb),public.hostel_save_bed(jsonb),public.hostel_allocation_register(text,text),public.hostel_allocate_student(jsonb),public.hostel_end_allocation(uuid,text),public.hostel_record_movement(jsonb),public.hostel_movement_register(uuid),public.hostel_save_incident(jsonb),public.hostel_incident_register(text),public.hostel_resolve_incident(uuid,text,text),public.hostel_my_children_boarding() from public,anon,authenticated;
grant execute on function public.hostel_dashboard(),public.hostel_register(),public.hostel_save_house(jsonb),public.hostel_save_room(jsonb),public.hostel_save_bed(jsonb),public.hostel_allocation_register(text,text),public.hostel_allocate_student(jsonb),public.hostel_end_allocation(uuid,text),public.hostel_record_movement(jsonb),public.hostel_movement_register(uuid),public.hostel_save_incident(jsonb),public.hostel_incident_register(text),public.hostel_resolve_incident(uuid,text,text),public.hostel_my_children_boarding() to authenticated;

commit;