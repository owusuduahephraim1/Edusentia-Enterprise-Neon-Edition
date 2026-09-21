-- Neon compatibility override for certified report viewing.
-- Certified source permits System Administrator and Principal to view reports.
-- Guardian access remains published-only and respects finance grade-detail holds.
-- The source-only direct student profile branch is omitted because the Neon
-- certified public.students model has no profile_id identity bridge.

begin;

CREATE OR REPLACE FUNCTION public.can_view_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role() in ('system_admin','principal')
    or public.can_access_class(public.report_class_id(target_report_id),false)
    or exists(
      select 1
      from public.student_reports r
      join public.enrollments e on e.id=r.enrollment_id
      join public.guardian_links gl on gl.student_id=e.student_id
      where r.id=target_report_id
        and r.status='published'
        and r.deleted_at is null
        and gl.auth_user_id=auth.uid()
        and gl.can_view_reports
        and not coalesce(
          (public.finance_student_hold_status(e.student_id)->>'block_grade_details')::boolean,
          false
        )
    )
$function$;

insert into app.schema_migrations(version)
values ('0045b_neon_report_view_compat')
on conflict do nothing;

commit;
