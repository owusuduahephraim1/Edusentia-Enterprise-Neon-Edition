-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Missing report-assignment scope helpers extracted read-only with pg_get_functiondef.
-- Internal prerequisites for 0044; no browser/Worker route is exposed.

begin;

CREATE OR REPLACE FUNCTION public.is_assigned_class_teacher(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role()='class_teacher'
    and exists(
      select 1 from public.classes c
      where c.id=target_class_id
        and c.class_teacher_id=auth.uid()
        and c.active
        and c.deleted_at is null
    )
$function$;

CREATE OR REPLACE FUNCTION public.can_create_report_for_class_term(target_class_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_manage_class_report_fields_for_term(target_class_id,target_term_id)
    or exists(
      select 1 from public.class_subjects cs
      where cs.class_id=target_class_id and cs.active
        and public.can_score_class_subject_for_term(target_class_id,cs.subject_id,target_term_id)
    )
$function$;

revoke all on function public.is_assigned_class_teacher(uuid) from public;
revoke all on function public.is_assigned_class_teacher(uuid) from edusentia_worker_runtime;
revoke all on function public.can_create_report_for_class_term(uuid,uuid) from public;
revoke all on function public.can_create_report_for_class_term(uuid,uuid) from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0043b_certified_report_assignment_scope')
on conflict do nothing;

commit;
