begin;

create sequence public.admissions_application_seq start with 1 increment by 1;
create sequence public.admissions_student_number_seq start with 1 increment by 1;

create table public.admissions_applications (
 id uuid primary key default gen_random_uuid(),
 application_no text not null unique,
 first_name text not null,
 middle_name text,
 last_name text not null,
 gender text not null check(gender in ('Male','Female','Other')),
 date_of_birth date,
 guardian_name text not null,
 guardian_phone text,
 guardian_email text,
 address text,
 previous_school text,
 target_academic_year_id uuid references public.academic_years(id) on delete restrict,
 applying_class_id uuid references public.classes(id) on delete restrict,
 status text not null default 'draft' check(status in ('draft','submitted','under_review','waitlisted','offered','accepted','rejected','withdrawn','enrolled')),
 source text not null default 'school_entry' check(source in ('school_entry','online','import','referral')),
 applicant_notes text,
 internal_notes text,
 submitted_at timestamptz,
 reviewed_by uuid references public.profiles(id) on delete set null,
 reviewed_at timestamptz,
 decided_by uuid references public.profiles(id) on delete set null,
 decided_at timestamptz,
 student_id uuid references public.students(id) on delete restrict,
 enrolled_at timestamptz,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table public.admissions_offers (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.admissions_applications(id) on delete restrict,
 academic_year_id uuid not null references public.academic_years(id) on delete restrict,
 class_id uuid not null references public.classes(id) on delete restrict,
 status text not null default 'offered' check(status in ('offered','accepted','declined','expired','withdrawn','enrolled')),
 offer_date date not null default current_date,
 expires_at date,
 conditions text,
 decision_notes text,
 accepted_at timestamptz,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index admissions_one_live_offer_idx on public.admissions_offers(application_id) where status in ('offered','accepted');

create table public.admissions_documents (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.admissions_applications(id) on delete restrict,
 document_type text not null,
 document_name text not null,
 storage_path text,
 verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected','not_required')),
 verified_by uuid references public.profiles(id) on delete set null,
 verified_at timestamptz,
 notes text,
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create index admissions_applications_status_idx on public.admissions_applications(status,created_at desc);
create index admissions_applications_year_class_idx on public.admissions_applications(target_academic_year_id,applying_class_id,status);
create index admissions_applications_student_idx on public.admissions_applications(student_id) where student_id is not null;
create index admissions_applications_created_by_idx on public.admissions_applications(created_by);
create index admissions_applications_reviewed_by_idx on public.admissions_applications(reviewed_by);
create index admissions_applications_decided_by_idx on public.admissions_applications(decided_by);
create index admissions_offers_application_idx on public.admissions_offers(application_id,created_at desc);
create index admissions_offers_year_class_idx on public.admissions_offers(academic_year_id,class_id,status);
create index admissions_offers_created_by_idx on public.admissions_offers(created_by);
create index admissions_documents_application_idx on public.admissions_documents(application_id,created_at desc);
create index admissions_documents_verified_by_idx on public.admissions_documents(verified_by);
create index admissions_documents_created_by_idx on public.admissions_documents(created_by);

alter table public.admissions_applications enable row level security;
alter table public.admissions_offers enable row level security;
alter table public.admissions_documents enable row level security;
revoke all on table public.admissions_applications,public.admissions_offers,public.admissions_documents from public,anon,authenticated;
grant all on table public.admissions_applications,public.admissions_offers,public.admissions_documents to service_role;
revoke all on sequence public.admissions_application_seq,public.admissions_student_number_seq from public,anon,authenticated;
grant usage,select on sequence public.admissions_application_seq,public.admissions_student_number_seq to service_role;

create trigger admissions_app_touch before update on public.admissions_applications for each row execute function public.student_services_touch_updated_at();
create trigger admissions_offer_touch before update on public.admissions_offers for each row execute function public.student_services_touch_updated_at();
create trigger admissions_doc_touch before update on public.admissions_documents for each row execute function public.student_services_touch_updated_at();
create trigger admissions_app_audit after insert or update or delete on public.admissions_applications for each row execute function public.audit_row_change();
create trigger admissions_offer_audit after insert or update or delete on public.admissions_offers for each row execute function public.audit_row_change();
create trigger admissions_doc_audit after insert or update or delete on public.admissions_documents for each row execute function public.audit_row_change();
create trigger admissions_app_no_delete before delete on public.admissions_applications for each row execute function public.student_services_block_delete();
create trigger admissions_offer_no_delete before delete on public.admissions_offers for each row execute function public.student_services_block_delete();
create trigger admissions_doc_no_delete before delete on public.admissions_documents for each row execute function public.student_services_block_delete();

create or replace function public.admissions_next_application_no()
returns text language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare p text; n bigint; c text;
begin
 select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'APP'),'[^0-9A-Za-z]','','g')) into p from public.school_settings limit 1;
 n:=nextval('public.admissions_application_seq');
 c:=p||'-APP-'||lpad(n::text,6,'0');
 return c;
end $$;

create or replace function public.admissions_next_student_no()
returns text language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare p text; n bigint; c text; tries integer:=0;
begin
 select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),nullif(identifier_root,''),'STD'),'[^0-9A-Za-z]','','g')) into p from public.school_settings limit 1;
 loop
   tries:=tries+1; if tries>1000 then raise exception 'Unable to allocate admission number'; end if;
   n:=nextval('public.admissions_student_number_seq'); c:=p||lpad(n::text,8,'0');
   exit when not exists(select 1 from public.students where admission_no=c);
 end loop;
 return c;
end $$;

create or replace function public.admissions_reference_data()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('admissions','read');
 return jsonb_build_object(
  'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',y.id,'name',y.name,'is_active',y.is_active) order by y.start_date desc) from public.academic_years y where y.deleted_at is null),'[]'::jsonb),
  'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'level_order',c.level_order) order by c.level_order,c.name) from public.classes c where c.deleted_at is null and c.active),'[]'::jsonb)
 );
end $$;

create or replace function public.admissions_dashboard()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('admissions','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'total',(select count(*) from public.admissions_applications),
  'submitted',(select count(*) from public.admissions_applications where status in ('submitted','under_review')),
  'waitlisted',(select count(*) from public.admissions_applications where status='waitlisted'),
  'offered',(select count(*) from public.admissions_applications where status='offered'),
  'accepted',(select count(*) from public.admissions_applications where status='accepted'),
  'enrolled',(select count(*) from public.admissions_applications where status='enrolled')
 ),'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
   select a.id,a.application_no,concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) applicant,a.status,a.created_at,c.name class_name,y.name academic_year
   from public.admissions_applications a left join public.classes c on c.id=a.applying_class_id left join public.academic_years y on y.id=a.target_academic_year_id
   order by a.created_at desc limit 15
 )q),'[]'::jsonb));
end $$;

create or replace function public.admissions_application_register(search_text text default null,status_filter text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('admissions','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
  select a.id,a.application_no,concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) applicant,a.gender,a.date_of_birth,a.guardian_name,a.guardian_phone,a.guardian_email,a.status,a.source,a.created_at,c.name class_name,y.name academic_year,
    (select o.id from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_id,
    (select o.status from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_status
  from public.admissions_applications a left join public.classes c on c.id=a.applying_class_id left join public.academic_years y on y.id=a.target_academic_year_id
  where (status_filter is null or a.status=status_filter)
   and (search_text is null or concat_ws(' ',a.application_no,a.first_name,a.middle_name,a.last_name,a.guardian_name,a.guardian_phone,a.guardian_email) ilike '%'||search_text||'%')
  order by a.created_at desc limit 300
 )q),'[]'::jsonb);
end $$;

create or replace function public.admissions_application_detail(target_application_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
declare a jsonb;
begin
 perform public.student_services_require_access('admissions','read');
 select to_jsonb(q) into a from (select * from public.admissions_applications where id=target_application_id)q;
 if a is null then raise exception 'Application not found'; end if;
 return a||jsonb_build_object(
  'offers',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select o.*,c.name class_name,y.name academic_year from public.admissions_offers o join public.classes c on c.id=o.class_id join public.academic_years y on y.id=o.academic_year_id where o.application_id=target_application_id)q),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from public.admissions_documents d where d.application_id=target_application_id),'[]'::jsonb)
 );
end $$;

create or replace function public.admissions_save_application(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;v_status text;v_no text;
begin
 perform public.student_services_require_access('admissions','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
   v_no:=public.admissions_next_application_no();
   insert into public.admissions_applications(application_no,first_name,middle_name,last_name,gender,date_of_birth,guardian_name,guardian_phone,guardian_email,address,previous_school,target_academic_year_id,applying_class_id,status,source,applicant_notes,internal_notes,submitted_at,created_by)
   values(v_no,btrim(payload->>'first_name'),nullif(btrim(payload->>'middle_name'),''),btrim(payload->>'last_name'),payload->>'gender',nullif(payload->>'date_of_birth','')::date,btrim(payload->>'guardian_name'),nullif(btrim(payload->>'guardian_phone'),''),nullif(lower(btrim(payload->>'guardian_email')),''),nullif(btrim(payload->>'address'),''),nullif(btrim(payload->>'previous_school'),''),nullif(payload->>'target_academic_year_id','')::uuid,nullif(payload->>'applying_class_id','')::uuid,coalesce(nullif(payload->>'status',''),'draft'),coalesce(nullif(payload->>'source',''),'school_entry'),nullif(payload->>'applicant_notes',''),nullif(payload->>'internal_notes',''),case when coalesce(payload->>'status','draft')='submitted' then now() end,auth.uid()) returning id into v_id;
 else
   select status into v_status from public.admissions_applications where id=v_id for update;
   if v_status in ('accepted','rejected','withdrawn','enrolled') then raise exception 'Finalized application cannot be edited'; end if;
   update public.admissions_applications set first_name=coalesce(nullif(btrim(payload->>'first_name'),''),first_name),middle_name=case when payload ? 'middle_name' then nullif(btrim(payload->>'middle_name'),'') else middle_name end,last_name=coalesce(nullif(btrim(payload->>'last_name'),''),last_name),gender=coalesce(nullif(payload->>'gender',''),gender),date_of_birth=case when payload ? 'date_of_birth' then nullif(payload->>'date_of_birth','')::date else date_of_birth end,guardian_name=coalesce(nullif(btrim(payload->>'guardian_name'),''),guardian_name),guardian_phone=case when payload ? 'guardian_phone' then nullif(btrim(payload->>'guardian_phone'),'') else guardian_phone end,guardian_email=case when payload ? 'guardian_email' then nullif(lower(btrim(payload->>'guardian_email')),'') else guardian_email end,address=case when payload ? 'address' then nullif(btrim(payload->>'address'),'') else address end,previous_school=case when payload ? 'previous_school' then nullif(btrim(payload->>'previous_school'),'') else previous_school end,target_academic_year_id=case when payload ? 'target_academic_year_id' then nullif(payload->>'target_academic_year_id','')::uuid else target_academic_year_id end,applying_class_id=case when payload ? 'applying_class_id' then nullif(payload->>'applying_class_id','')::uuid else applying_class_id end,source=coalesce(nullif(payload->>'source',''),source),applicant_notes=case when payload ? 'applicant_notes' then nullif(payload->>'applicant_notes','') else applicant_notes end,internal_notes=case when payload ? 'internal_notes' then nullif(payload->>'internal_notes','') else internal_notes end where id=v_id;
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','application_saved','admissions_application',v_id,auth.uid(),'{}');
 return v_id;
end $$;

create or replace function public.admissions_submit_application(target_application_id uuid)
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
begin
 perform public.student_services_require_access('admissions','write');
 update public.admissions_applications set status='submitted',submitted_at=coalesce(submitted_at,now()) where id=target_application_id and status='draft';
 if not found then raise exception 'Only a draft application can be submitted'; end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','application_submitted','admissions_application',target_application_id,auth.uid(),'{}');
end $$;

create or replace function public.admissions_decide_application(target_application_id uuid,decision text,offered_academic_year_id uuid default null,offered_class_id uuid default null,decision_notes text default null,offer_expires_at date default null)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_offer uuid;v_status text;
begin
 perform public.student_services_require_access('admissions','approve');
 if decision not in ('under_review','waitlisted','offered','rejected','withdrawn') then raise exception 'Invalid admissions decision'; end if;
 select status into v_status from public.admissions_applications where id=target_application_id for update;
 if v_status is null or v_status in ('accepted','rejected','withdrawn','enrolled') then raise exception 'Application cannot be decided in its current state'; end if;
 if decision='offered' then
   if offered_academic_year_id is null or offered_class_id is null then raise exception 'Offer requires academic year and class'; end if;
   update public.admissions_offers set status='withdrawn',updated_at=now() where application_id=target_application_id and status='offered';
   insert into public.admissions_offers(application_id,academic_year_id,class_id,status,expires_at,decision_notes,created_by) values(target_application_id,offered_academic_year_id,offered_class_id,'offered',offer_expires_at,decision_notes,auth.uid()) returning id into v_offer;
   update public.admissions_applications set status='offered',target_academic_year_id=offered_academic_year_id,applying_class_id=offered_class_id,decided_by=auth.uid(),decided_at=now() where id=target_application_id;
 else
   update public.admissions_applications set status=decision,reviewed_by=auth.uid(),reviewed_at=now(),decided_by=case when decision in ('rejected','withdrawn') then auth.uid() else decided_by end,decided_at=case when decision in ('rejected','withdrawn') then now() else decided_at end,internal_notes=coalesce(decision_notes,internal_notes) where id=target_application_id;
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','application_decision','admissions_application',target_application_id,auth.uid(),jsonb_build_object('decision',decision,'offer_id',v_offer));
 return v_offer;
end $$;

create or replace function public.admissions_accept_offer(target_offer_id uuid)
returns void language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_app uuid;v_exp date;
begin
 perform public.student_services_require_access('admissions','approve');
 select application_id,expires_at into v_app,v_exp from public.admissions_offers where id=target_offer_id and status='offered' for update;
 if v_app is null then raise exception 'Open offer not found'; end if;
 if v_exp is not null and v_exp<current_date then update public.admissions_offers set status='expired' where id=target_offer_id; raise exception 'Offer has expired'; end if;
 update public.admissions_offers set status='accepted',accepted_at=now() where id=target_offer_id;
 update public.admissions_applications set status='accepted',decided_by=auth.uid(),decided_at=now() where id=v_app;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','offer_accepted','admissions_offer',target_offer_id,auth.uid(),jsonb_build_object('application_id',v_app));
end $$;

create or replace function public.admissions_enroll_application(target_application_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare a public.admissions_applications%rowtype;o public.admissions_offers%rowtype;v_student uuid;v_no text;
begin
 perform public.student_services_require_access('admissions','enroll');
 select * into a from public.admissions_applications where id=target_application_id for update;
 if a.id is null or a.status<>'accepted' then raise exception 'Only an accepted application can be enrolled'; end if;
 if a.student_id is not null then raise exception 'Application is already linked to a student'; end if;
 select * into o from public.admissions_offers where application_id=a.id and status='accepted' order by accepted_at desc nulls last,created_at desc limit 1 for update;
 if o.id is null then raise exception 'Accepted offer is required before enrollment'; end if;
 if not exists(select 1 from public.academic_years y where y.id=o.academic_year_id and y.deleted_at is null) then raise exception 'Offer academic year is unavailable'; end if;
 if not exists(select 1 from public.classes c where c.id=o.class_id and c.active and c.deleted_at is null) then raise exception 'Offer class is unavailable'; end if;
 v_no:=public.admissions_next_student_no();
 insert into public.students(admission_no,first_name,middle_name,last_name,gender,date_of_birth,guardian_name,guardian_phone,guardian_email,status)
 values(v_no,a.first_name,a.middle_name,a.last_name,a.gender,a.date_of_birth,a.guardian_name,a.guardian_phone,a.guardian_email,'active') returning id into v_student;
 insert into public.enrollments(student_id,academic_year_id,class_id,active,enrollment_origin) values(v_student,o.academic_year_id,o.class_id,true,'manual');
 update public.admissions_offers set status='enrolled' where id=o.id;
 update public.admissions_applications set status='enrolled',student_id=v_student,enrolled_at=now() where id=a.id;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','applicant_enrolled','admissions_application',a.id,auth.uid(),jsonb_build_object('student_id',v_student,'admission_no',v_no,'academic_year_id',o.academic_year_id,'class_id',o.class_id));
 return jsonb_build_object('student_id',v_student,'admission_no',v_no,'academic_year_id',o.academic_year_id,'class_id',o.class_id);
end $$;

create or replace function public.admissions_save_document(payload jsonb)
returns uuid language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare v_id uuid;
begin
 perform public.student_services_require_access('admissions','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.admissions_documents(application_id,document_type,document_name,storage_path,verification_status,notes,created_by) values((payload->>'application_id')::uuid,btrim(payload->>'document_type'),btrim(payload->>'document_name'),nullif(payload->>'storage_path',''),coalesce(nullif(payload->>'verification_status',''),'pending'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.admissions_documents set document_type=coalesce(nullif(btrim(payload->>'document_type'),''),document_type),document_name=coalesce(nullif(btrim(payload->>'document_name'),''),document_name),storage_path=case when payload ? 'storage_path' then nullif(payload->>'storage_path','') else storage_path end,verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when payload->>'verification_status'='verified' then auth.uid() else verified_by end,verified_at=case when payload->>'verification_status'='verified' then now() else verified_at end,notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $$;

revoke all on function public.admissions_next_application_no(),public.admissions_next_student_no(),public.admissions_reference_data(),public.admissions_dashboard(),public.admissions_application_register(text,text),public.admissions_application_detail(uuid),public.admissions_save_application(jsonb),public.admissions_submit_application(uuid),public.admissions_decide_application(uuid,text,uuid,uuid,text,date),public.admissions_accept_offer(uuid),public.admissions_enroll_application(uuid),public.admissions_save_document(jsonb) from public,anon,authenticated;
grant execute on function public.admissions_reference_data(),public.admissions_dashboard(),public.admissions_application_register(text,text),public.admissions_application_detail(uuid),public.admissions_save_application(jsonb),public.admissions_submit_application(uuid),public.admissions_decide_application(uuid,text,uuid,uuid,text,date),public.admissions_accept_offer(uuid),public.admissions_enroll_application(uuid),public.admissions_save_document(jsonb) to authenticated;
grant execute on function public.admissions_next_application_no(),public.admissions_next_student_no() to service_role;

commit;