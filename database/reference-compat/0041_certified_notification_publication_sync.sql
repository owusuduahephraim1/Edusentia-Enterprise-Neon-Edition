-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function body extracted read-only with pg_get_functiondef.
-- Internal helper only; Worker calls transition_report_status(), never this helper directly.

begin;

CREATE OR REPLACE FUNCTION public.create_workflow_notifications(target_report_id uuid, target_status report_status)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  classid uuid;
  studentname text;
  reportno text;
  studentprofile uuid;
  recipient uuid;
begin
  select e.class_id,
         concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
         coalesce(r.report_number,''),
         s.profile_id
  into classid,studentname,reportno,studentprofile
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  join public.students s on s.id=e.student_id
  where r.id=target_report_id;

  if target_status='submitted' then
    for recipient in
      select p.id
      from public.profiles p
      where p.active and public.current_app_role_for(p.role)='principal'
    loop
      if recipient<>auth.uid() then
        perform public.create_notification(
          recipient,
          'Report awaiting Principal approval',
          studentname||case when reportno<>'' then ' • '||reportno else '' end,
          'report_workflow','report',target_report_id,true
        );
      end if;
    end loop;

  elsif target_status='returned' then
    for recipient in
      select distinct user_id from (
        select c.class_teacher_id user_id
        from public.classes c
        where c.id=classid and c.class_teacher_id is not null
        union all
        select cs.teacher_id
        from public.class_subjects cs
        where cs.class_id=classid and cs.active and cs.teacher_id is not null
        union all
        select a.user_id
        from public.user_class_access a
        where a.class_id=classid and a.user_id is not null
      ) q
    loop
      if recipient<>auth.uid() then
        perform public.create_notification(
          recipient,
          'Report returned for correction',
          studentname||case when reportno<>'' then ' • '||reportno else '' end,
          'report_workflow','report',target_report_id,true
        );
      end if;
    end loop;

  elsif target_status='approved' then
    for recipient in
      select distinct user_id from (
        select p.id user_id
        from public.profiles p
        where p.active and public.current_app_role_for(p.role)='system_admin'
        union all
        select c.class_teacher_id
        from public.classes c
        where c.id=classid and c.class_teacher_id is not null
        union all
        select cs.teacher_id
        from public.class_subjects cs
        where cs.class_id=classid and cs.active and cs.teacher_id is not null
        union all
        select a.user_id
        from public.user_class_access a
        where a.class_id=classid and a.user_id is not null
      ) q
    loop
      if recipient<>auth.uid() then
        perform public.create_notification(
          recipient,
          'Report approved by Principal',
          studentname||case when reportno<>'' then ' • '||reportno else '' end,
          'report_workflow','report',target_report_id,true
        );
      end if;
    end loop;

  elsif target_status='published' then
    for recipient in
      select distinct gl.auth_user_id
      from public.guardian_links gl
      join public.enrollments e on e.student_id=gl.student_id
      join public.student_reports r on r.enrollment_id=e.id
      where r.id=target_report_id
        and gl.auth_user_id is not null
        and gl.can_receive_notifications
    loop
      perform public.create_notification(
        recipient,
        'Report card published',
        studentname||case when reportno<>'' then ' • '||reportno else '' end,
        'report_published','report',target_report_id,true
      );
    end loop;

    if studentprofile is not null
       and not exists (
         select 1
         from public.guardian_links gl
         join public.enrollments e on e.student_id=gl.student_id
         join public.student_reports r on r.enrollment_id=e.id
         where r.id=target_report_id
           and gl.auth_user_id=studentprofile
           and gl.can_receive_notifications
       ) then
      perform public.create_notification(
        studentprofile,
        'Report card published',
        studentname||case when reportno<>'' then ' • '||reportno else '' end,
        'report_published','report',target_report_id,true
      );
    end if;
  end if;
end
$function$;

revoke all on function public.create_workflow_notifications(uuid,public.report_status) from public;
revoke all on function public.create_workflow_notifications(uuid,public.report_status) from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0041_certified_notification_publication_sync')
on conflict do nothing;

update app.release_identity
set schema_version='0041'
where edition='Edusentia Enterprise Neon Edition';

commit;
