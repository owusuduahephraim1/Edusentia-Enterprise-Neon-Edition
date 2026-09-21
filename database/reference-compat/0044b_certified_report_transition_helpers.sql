-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function bodies extracted read-only with pg_get_functiondef.
-- Restores certified report workflow helpers referenced by 0044.

begin;

CREATE OR REPLACE FUNCTION public.can_submit_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_assigned_class_teacher(public.report_class_id(target_report_id))
    and exists(
      select 1 from public.student_reports r
      where r.id=target_report_id
        and r.deleted_at is null
        and r.status in ('draft','returned')
    )
$function$;

CREATE OR REPLACE FUNCTION public.allowed_report_transitions(target_report_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  current_status public.report_status;
  result text[] := '{}'::text[];
begin
  select r.status into current_status
  from public.student_reports r
  where r.id=target_report_id and r.deleted_at is null;
  if current_status is null then return result; end if;
  if current_status in ('draft','returned') and public.can_submit_report(target_report_id) then
    result := array_append(result,'submitted');
  end if;
  if current_status in ('submitted','class_reviewed') and public.current_app_role()='principal' then
    result := array_append(result,'approved');
  end if;
  if current_status in ('submitted','class_reviewed','approved','published')
     and public.current_app_role()='principal' then
    result := array_append(result,'returned');
  end if;
  if current_status='approved' and public.can_publish_report(target_report_id) then
    result := array_append(result,'published');
  end if;
  if current_status='published' and public.is_system_admin() then
    result := array_append(result,'withdrawn');
  end if;
  return result;
end
$function$;

revoke all on function public.can_submit_report(uuid) from public;
revoke all on function public.allowed_report_transitions(uuid) from public;
revoke all on function public.can_submit_report(uuid) from edusentia_worker_runtime;
revoke all on function public.allowed_report_transitions(uuid) from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0044b_certified_report_transition_helpers')
on conflict do nothing;

commit;
