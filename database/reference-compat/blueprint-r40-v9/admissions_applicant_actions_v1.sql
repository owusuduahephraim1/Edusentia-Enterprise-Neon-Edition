begin;

-- Applicant register action hardening.
-- Delete is a reversible lifecycle withdrawal; permanent removal is System Administrator only.

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
        (select o.id from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_id,
        (select o.status from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_status
      from public.admissions_applications a
      left join public.classes c on c.id=a.applying_class_id
      left join public.academic_years y on y.id=a.target_academic_year_id
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
      'enrolled',(select count(*) from public.admissions_applications where status='enrolled')
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
begin
  perform public.student_services_require_access('admissions','write');

  select * into v_app
  from public.admissions_applications
  where id=target_application_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;
  if v_app.student_id is not null or v_app.status='enrolled' then
    raise exception 'An enrolled or student-linked application cannot be deleted';
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
    jsonb_build_object('application_no',v_app.application_no,'previous_status',v_app.status,'reason',v_reason)
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
  if v_app.student_id is not null or v_app.status='enrolled' then
    raise exception 'An enrolled or student-linked application cannot be permanently removed';
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
    jsonb_build_object('application_no',v_app.application_no,'previous_status',v_app.status,'reason',v_reason)
  );

  -- Direct table deletes remain blocked for ordinary callers. This transaction-local
  -- override is used only by this guarded SECURITY DEFINER operation.
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

revoke all on function public.admissions_delete_application(uuid,text) from public,anon,authenticated;
revoke all on function public.admissions_permanently_remove_application(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admissions_delete_application(uuid,text) to authenticated;
grant execute on function public.admissions_permanently_remove_application(uuid,text,text) to authenticated;

-- Reassert authenticated access to the replaced read functions.
revoke all on function public.admissions_application_register(text,text) from public,anon,authenticated;
revoke all on function public.admissions_dashboard() from public,anon,authenticated;
grant execute on function public.admissions_application_register(text,text) to authenticated;
grant execute on function public.admissions_dashboard() to authenticated;

commit;
