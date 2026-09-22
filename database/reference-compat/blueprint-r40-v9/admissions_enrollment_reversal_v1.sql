begin;

-- Admissions/student lifecycle reconciliation.
-- A removed/withdrawn student remains historically linked to the application,
-- but the application becomes operationally editable again as not_enrolled.

alter table public.admissions_applications
  drop constraint if exists admissions_applications_status_check;

alter table public.admissions_applications
  add constraint admissions_applications_status_check
  check (status = any (array[
    'draft'::text,
    'submitted'::text,
    'under_review'::text,
    'waitlisted'::text,
    'offered'::text,
    'accepted'::text,
    'rejected'::text,
    'withdrawn'::text,
    'enrolled'::text,
    'not_enrolled'::text
  ]));

create or replace function public.admissions_application_register(
  search_text text default null,
  status_filter text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path='public','pg_catalog','extensions'
as $$
begin
  perform public.student_services_require_access('admissions','read');
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q.created_at desc)
    from (
      select
        a.id,
        a.student_id,
        a.application_no,
        concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) applicant,
        a.gender,
        a.date_of_birth,
        a.guardian_name,
        a.guardian_phone,
        a.guardian_email,
        a.status,
        a.source,
        a.created_at,
        c.name class_name,
        y.name academic_year,
        s.status::text student_status,
        s.deleted_at student_deleted_at,
        coalesce(s.id is not null and s.deleted_at is null and s.status <> 'withdrawn'::public.student_status,false) student_link_active,
        (select o.id from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_id,
        (select o.status from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_status
      from public.admissions_applications a
      left join public.classes c on c.id=a.applying_class_id
      left join public.academic_years y on y.id=a.target_academic_year_id
      left join public.students s on s.id=a.student_id
      where
        ((status_filter is null and a.status <> 'withdrawn') or a.status=status_filter)
        and (
          search_text is null
          or concat_ws(' ',a.application_no,a.first_name,a.middle_name,a.last_name,a.guardian_name,a.guardian_phone,a.guardian_email)
             ilike '%'||search_text||'%'
        )
      order by a.created_at desc
      limit 300
    ) q
  ),'[]'::jsonb);
end $$;

create or replace function public.admissions_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path='public','pg_catalog','extensions'
as $$
begin
  perform public.student_services_require_access('admissions','read');
  return jsonb_build_object(
    'metrics',jsonb_build_object(
      'total',(select count(*) from public.admissions_applications where status <> 'withdrawn'),
      'submitted',(select count(*) from public.admissions_applications where status in ('submitted','under_review')),
      'waitlisted',(select count(*) from public.admissions_applications where status='waitlisted'),
      'offered',(select count(*) from public.admissions_applications where status='offered'),
      'accepted',(select count(*) from public.admissions_applications where status='accepted'),
      'enrolled',(select count(*) from public.admissions_applications where status='enrolled'),
      'not_enrolled',(select count(*) from public.admissions_applications where status='not_enrolled')
    ),
    'recent',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at desc)
      from (
        select
          a.id,
          a.application_no,
          concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) applicant,
          a.status,
          a.created_at,
          c.name class_name,
          y.name academic_year
        from public.admissions_applications a
        left join public.classes c on c.id=a.applying_class_id
        left join public.academic_years y on y.id=a.target_academic_year_id
        where a.status <> 'withdrawn'
        order by a.created_at desc
        limit 15
      ) q
    ),'[]'::jsonb)
  );
end $$;

create or replace function public.admissions_mark_not_enrolled(
  target_application_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_catalog','extensions'
as $$
declare
  v_app public.admissions_applications%rowtype;
  v_reason text:=nullif(btrim(reason),'');
  v_active_student boolean:=false;
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can reopen an enrolled application' using errcode='42501';
  end if;
  perform public.student_services_require_access('admissions','write');
  perform public.require_sensitive_access();

  if v_reason is null or length(v_reason) < 5 then
    raise exception 'A reason of at least 5 characters is required';
  end if;

  select * into v_app
  from public.admissions_applications
  where id=target_application_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;
  if v_app.status='not_enrolled' then
    return jsonb_build_object('updated',false,'application_no',v_app.application_no,'status','not_enrolled');
  end if;
  if v_app.status<>'enrolled' then
    raise exception 'Only an enrolled application can be marked not enrolled';
  end if;

  if v_app.student_id is not null then
    select exists(
      select 1
      from public.students s
      where s.id=v_app.student_id
        and s.deleted_at is null
        and s.status <> 'withdrawn'::public.student_status
    ) into v_active_student;
  end if;

  if v_active_student then
    raise exception 'The linked student is still active. Withdraw or remove the student from Student Directory first.' using errcode='55000';
  end if;

  update public.admissions_applications
  set status='not_enrolled',decided_by=auth.uid(),decided_at=now()
  where id=v_app.id;

  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values(
    'admissions',
    'application_marked_not_enrolled',
    'admissions_application',
    v_app.id,
    auth.uid(),
    jsonb_build_object(
      'application_no',v_app.application_no,
      'student_id',v_app.student_id,
      'previous_status',v_app.status,
      'reason',v_reason
    )
  );

  return jsonb_build_object('updated',true,'application_no',v_app.application_no,'status','not_enrolled');
end $$;

create or replace function public.admissions_delete_application(
  target_application_id uuid,
  reason text default null
)
returns void
language plpgsql
security definer
set search_path='public','pg_catalog','extensions'
as $$
declare
  v_app public.admissions_applications%rowtype;
  v_reason text:=nullif(btrim(reason),'');
  v_active_student boolean:=false;
begin
  perform public.student_services_require_access('admissions','write');

  select * into v_app
  from public.admissions_applications
  where id=target_application_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;
  if v_app.status='enrolled' then
    raise exception 'An enrolled application cannot be deleted';
  end if;
  if v_app.student_id is not null then
    select exists(
      select 1
      from public.students s
      where s.id=v_app.student_id
        and s.deleted_at is null
        and s.status <> 'withdrawn'::public.student_status
    ) into v_active_student;
    if v_active_student then
      raise exception 'An application linked to an active student cannot be deleted';
    end if;
  end if;
  if v_app.status='accepted' then
    raise exception 'An accepted application must be resolved before it can be deleted';
  end if;
  if v_app.status='withdrawn' then
    return;
  end if;

  update public.admissions_offers
  set status='withdrawn',updated_at=now()
  where application_id=target_application_id
    and status in ('offered','accepted');

  update public.admissions_applications
  set
    status='withdrawn',
    decided_by=auth.uid(),
    decided_at=now(),
    internal_notes=case
      when v_reason is null then internal_notes
      when coalesce(internal_notes,'')='' then 'Deleted from applicant register: '||v_reason
      else internal_notes||E'\nDeleted from applicant register: '||v_reason
    end
  where id=target_application_id;

  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values(
    'admissions',
    'application_deleted_from_register',
    'admissions_application',
    target_application_id,
    auth.uid(),
    jsonb_build_object('application_no',v_app.application_no,'previous_status',v_app.status,'reason',v_reason,'historical_student_id',v_app.student_id)
  );
end $$;

create or replace function public.admissions_permanently_remove_application(
  target_application_id uuid,
  confirmation_application_no text,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_catalog','extensions'
as $$
declare
  v_app public.admissions_applications%rowtype;
  v_reason text:=nullif(btrim(reason),'');
  v_confirmation text:=btrim(coalesce(confirmation_application_no,''));
  v_active_student boolean:=false;
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can permanently remove an applicant' using errcode='42501';
  end if;
  perform public.student_services_require_access('admissions','write');
  perform public.require_sensitive_access();

  select * into v_app
  from public.admissions_applications
  where id=target_application_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;
  if v_app.status='enrolled' then
    raise exception 'An enrolled application cannot be permanently removed';
  end if;
  if v_app.student_id is not null then
    select exists(
      select 1
      from public.students s
      where s.id=v_app.student_id
        and s.deleted_at is null
        and s.status <> 'withdrawn'::public.student_status
    ) into v_active_student;
    if v_active_student then
      raise exception 'An application linked to an active student cannot be permanently removed';
    end if;
  end if;
  if v_app.status='accepted' then
    raise exception 'An accepted application cannot be permanently removed';
  end if;
  if v_confirmation <> v_app.application_no then
    raise exception 'Application number confirmation does not match';
  end if;
  if v_reason is null or length(v_reason) < 5 then
    raise exception 'A permanent removal reason of at least 5 characters is required';
  end if;
  if exists(
    select 1
    from public.admissions_documents
    where application_id=target_application_id
      and nullif(btrim(coalesce(storage_path,'')),'') is not null
  ) then
    raise exception 'Stored admission documents must be removed through the protected document workflow before permanent applicant removal';
  end if;

  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values(
    'admissions',
    'application_permanent_removal',
    'admissions_application',
    target_application_id,
    auth.uid(),
    jsonb_build_object('application_no',v_app.application_no,'previous_status',v_app.status,'reason',v_reason,'historical_student_id',v_app.student_id)
  );

  perform set_config('app.student_services_allow_hard_delete','on',true);

  delete from public.admissions_documents where application_id=target_application_id;
  delete from public.admissions_offers where application_id=target_application_id;
  delete from public.admissions_applications where id=target_application_id;

  return jsonb_build_object(
    'removed',true,
    'application_no',v_app.application_no,
    'previous_status',v_app.status
  );
end $$;

create or replace function public.admissions_sync_student_lifecycle()
returns trigger
language plpgsql
security definer
set search_path='public','pg_catalog','extensions'
as $$
begin
  if (new.deleted_at is not null or new.status='withdrawn'::public.student_status)
     and (old.deleted_at is distinct from new.deleted_at or old.status is distinct from new.status) then
    with changed as (
      update public.admissions_applications a
      set status='not_enrolled',decided_by=auth.uid(),decided_at=now()
      where a.student_id=new.id
        and a.status='enrolled'
      returning a.id,a.application_no,a.student_id
    )
    insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
    select
      'admissions',
      'application_not_enrolled_after_student_removal',
      'admissions_application',
      c.id,
      auth.uid(),
      jsonb_build_object(
        'application_no',c.application_no,
        'student_id',c.student_id,
        'student_status',new.status::text,
        'student_deleted_at',new.deleted_at,
        'source','student_directory_sync'
      )
    from changed c;
  elsif new.deleted_at is null
        and new.status='active'::public.student_status
        and (old.deleted_at is not null or old.status='withdrawn'::public.student_status) then
    with changed as (
      update public.admissions_applications a
      set status='enrolled',decided_by=auth.uid(),decided_at=now()
      where a.student_id=new.id
        and a.status='not_enrolled'
      returning a.id,a.application_no,a.student_id
    )
    insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
    select
      'admissions',
      'application_enrolled_after_student_restore',
      'admissions_application',
      c.id,
      auth.uid(),
      jsonb_build_object(
        'application_no',c.application_no,
        'student_id',c.student_id,
        'student_status',new.status::text,
        'source','student_directory_sync'
      )
    from changed c;
  end if;
  return new;
end $$;

drop trigger if exists admissions_student_lifecycle_sync on public.students;
create trigger admissions_student_lifecycle_sync
after update of status,deleted_at on public.students
for each row
execute function public.admissions_sync_student_lifecycle();

revoke all on function public.admissions_mark_not_enrolled(uuid,text) from public,anon,authenticated;
grant execute on function public.admissions_mark_not_enrolled(uuid,text) to authenticated;
revoke all on function public.admissions_sync_student_lifecycle() from public,anon,authenticated;

revoke all on function public.admissions_delete_application(uuid,text) from public,anon,authenticated;
revoke all on function public.admissions_permanently_remove_application(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admissions_delete_application(uuid,text) to authenticated;
grant execute on function public.admissions_permanently_remove_application(uuid,text,text) to authenticated;

revoke all on function public.admissions_application_register(text,text) from public,anon,authenticated;
revoke all on function public.admissions_dashboard() from public,anon,authenticated;
grant execute on function public.admissions_application_register(text,text) to authenticated;
grant execute on function public.admissions_dashboard() to authenticated;

-- Repair existing stale admissions rows, including previously removed students.
with changed as (
  update public.admissions_applications a
  set status='not_enrolled',decided_by=null,decided_at=now()
  from public.students s
  where a.student_id=s.id
    and a.status='enrolled'
    and (s.deleted_at is not null or s.status='withdrawn'::public.student_status)
  returning a.id,a.application_no,a.student_id
)
insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
select
  'admissions',
  'application_not_enrolled_reconciled',
  'admissions_application',
  c.id,
  null,
  jsonb_build_object(
    'application_no',c.application_no,
    'student_id',c.student_id,
    'source','migration_reconciliation'
  )
from changed c;

commit;
