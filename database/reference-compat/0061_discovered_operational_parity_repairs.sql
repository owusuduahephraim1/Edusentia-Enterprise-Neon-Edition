-- Production parity repairs discovered through live Neon verification.
-- 1. Restore the certified report archive-status column required by list_report_cards_v6.
-- 2. Move Users & Access guardian-directory reads behind a SECURITY DEFINER bridge,
--    avoiding direct Worker reads through certified RLS helper policies.
-- 3. Remove the hard dependency on Supabase pg_cron from Operations while preserving
--    an empty/dynamic cron snapshot on Neon.
begin;

alter table public.student_reports
  add column if not exists archived_status public.report_status;

create or replace function public.neon_guardian_account_records()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','app','authn','extensions','pg_catalog'
as $function$
begin
  if public.current_app_role()::text<>'system_admin' then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',sg.id,
      'auth_user_id',linked.auth_user_id,
      'linked_account_count',linked.linked_account_count,
      'portal_email',au.email,
      'full_name',sg.full_name,
      'relationship',sg.relationship,
      'phone',sg.phone,
      'email',sg.email,
      'address',sg.address,
      'is_primary',sg.is_primary,
      'children',coalesce(children.children,'[]'::jsonb)
    ) order by lower(sg.full_name),lower(coalesce(sg.phone,'')),sg.id)
    from public.student_guardians sg
    left join lateral (
      select min(gl.auth_user_id::text)::uuid auth_user_id,
             count(distinct gl.auth_user_id)::integer linked_account_count
      from public.guardian_links gl
      where gl.guardian_id=sg.id and gl.auth_user_id is not null
    ) linked on true
    left join authn.users au on au.id=linked.auth_user_id
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'student_id',s.id,
          'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
          'admission_no',s.admission_no,
          'class_id',ce.class_id,
          'class_name',ce.class_name
        )
        order by lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text
      ) children
      from public.guardian_links gl2
      join public.students s
        on s.id=gl2.student_id and s.deleted_at is null and s.status='active'
      left join lateral (
        select e.class_id,c.name::text class_name
        from public.enrollments e
        join public.classes c on c.id=e.class_id and c.deleted_at is null
        join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
        where e.student_id=s.id and e.deleted_at is null
        order by y.is_active desc,e.active desc,y.start_date desc,e.updated_at desc
        limit 1
      ) ce on true
      where gl2.guardian_id=sg.id
    ) children on true
    where exists(
      select 1
      from public.guardian_links gl3
      join public.students s3
        on s3.id=gl3.student_id and s3.deleted_at is null and s3.status='active'
      where gl3.guardian_id=sg.id
    )
  ),'[]'::jsonb);
end
$function$;

create or replace function public.neon_cron_jobs_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_catalog'
as $function$
declare
  result jsonb:='[]'::jsonb;
begin
  if to_regclass('cron.job') is null then
    return result;
  end if;

  begin
    execute $sql$
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'jobid',jobid,
            'jobname',jobname,
            'schedule',schedule,
            'active',active
          )
          order by jobname
        ),
        '[]'::jsonb
      )
      from cron.job
      where jobname like 'nis-%' or jobname like 'rce-%'
    $sql$
    into result;
  exception
    when undefined_table or insufficient_privilege then
      result:='[]'::jsonb;
  end;

  return coalesce(result,'[]'::jsonb);
end
$function$;

create or replace function public.operations_dashboard(target_term_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','extensions'
as $function$
declare
  tid uuid:=target_term_id;
  health jsonb;
begin
  if public.current_app_role() not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;

  if tid is null then
    select id into tid
    from public.terms
    where is_active and deleted_at is null
    limit 1;
  end if;

  health:=public.system_health();

  return jsonb_build_object(
    'term_id',tid,
    'term_control',public.term_control_snapshot(tid),
    'students',(select count(*) from public.students where status='active' and deleted_at is null),
    'reports_expected',(select count(*) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=tid and e.active and e.deleted_at is null),
    'reports_created',(select count(*) from public.student_reports where term_id=tid and deleted_at is null),
    'draft_reports',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status in ('draft','returned')),
    'awaiting_approval',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status in ('submitted','class_reviewed')),
    'approved_unpublished',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status='approved'),
    'published',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status='published'),
    'published_without_pdf',(select count(*) from public.student_reports r left join public.report_publications p on p.report_id=r.id and p.revoked_at is null where r.term_id=tid and r.status='published' and r.deleted_at is null and coalesce(p.storage_path,'')=''),
    'pending_corrections',(select count(*) from public.report_correction_requests q join public.student_reports r on r.id=q.report_id where r.term_id=tid and q.status='pending'),
    'attendance_classes_today',(select count(distinct class_id) from public.class_attendance_registers where term_id=tid and attendance_date=current_date),
    'active_classes',(select count(*) from public.classes where active and deleted_at is null),
    'pending_notifications',health->'pending_notifications',
    'client_errors_24h',health->'client_errors_24h',
    'client_warnings_24h',health->'client_warnings_24h',
    'open_security_events',health->'open_security_events',
    'critical_security_events',health->'critical_security_events',
    'latest_backup',health->'latest_backup',
    'latest_verified_backup',health->'latest_verified_backup',
    'latest_recovery_test',health->'latest_recovery_test',
    'failed_backups_30d',health->'failed_backups_30d',
    'current_backup_failures',health->'current_backup_failures',
    'cron_failures_24h',health->'cron_failures_24h',
    'operational_state',health->'operational_state',
    'health_reasons',health->'health_reasons',
    'continuity_state',health->'continuity_state',
    'continuity_reasons',health->'continuity_reasons',
    'cron_jobs',public.neon_cron_jobs_snapshot(),
    'class_progress',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'class_id',c.id,
          'class_name',c.name,
          'enrolled',q.enrolled,
          'created',q.created,
          'submitted',q.submitted,
          'approved',q.approved,
          'published',q.published
        )
        order by c.level_order,c.name
      )
      from public.classes c
      cross join lateral (
        select
          (select count(*) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=tid and e.class_id=c.id and e.active and e.deleted_at is null) enrolled,
          (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null) created,
          (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status in ('submitted','class_reviewed')) submitted,
          (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status='approved') approved,
          (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status='published') published
      ) q
      where c.active and c.deleted_at is null
    ),'[]'::jsonb)
  );
end
$function$;

revoke all on function public.neon_guardian_account_records() from public;
revoke all on function public.neon_cron_jobs_snapshot() from public;
revoke all on function public.operations_dashboard(uuid) from public;

grant execute on function public.neon_guardian_account_records() to edusentia_worker_runtime;
grant execute on function public.operations_dashboard(uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0061_discovered_operational_parity_repairs')
on conflict do nothing;

commit;
