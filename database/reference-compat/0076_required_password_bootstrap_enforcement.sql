-- Preserve the certified Supabase first-login password-change contract in Neon.
-- get_bootstrap_data() must expose profiles.must_change_password so the shell
-- can block workspace entry while a temporary password is still active.
begin;

create or replace function public.get_bootstrap_data()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare result jsonb; p jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  update public.profiles set last_seen_at=now() where id=auth.uid();
  select to_jsonb(x) into p from (
    select id,full_name,public.current_app_role() role,active,mfa_required,must_change_password,phone
    from public.profiles where id=auth.uid()
  ) x;
  if p is null then raise exception 'Active profile not found' using errcode='42501'; end if;
  select jsonb_build_object(
    'profile',p,
    'school',(select to_jsonb(s) from public.school_settings s limit 1),
    'academic_years',coalesce((select jsonb_agg(to_jsonb(y) order by y.start_date desc nulls last,y.name)
      from public.academic_years y where y.deleted_at is null),'[]'::jsonb),
    'terms',coalesce((select jsonb_agg(to_jsonb(t) order by t.sequence)
      from public.terms t where t.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(to_jsonb(c) order by c.level_order,c.name)
      from public.classes c where c.deleted_at is null and (public.is_records_manager() or public.can_access_class(c.id,false))),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(s) order by s.display_order,s.name)
      from public.subjects s where s.deleted_at is null and s.active),'[]'::jsonb),
    'permissions',jsonb_build_object(
      'manage_users',public.is_system_admin(),
      'manage_academics',public.is_academic_manager(),
      'manage_students',public.is_records_manager() or public.has_role(array['class_teacher']),
      'approve_reports',public.has_role(array['system_admin','headteacher']),
      'publish_reports',public.has_role(array['system_admin','headteacher']),
      'view_audit',public.has_role(array['system_admin','headteacher','academic_admin']),
      'run_backup',public.is_system_admin(),
      'parent_portal',public.has_role(array['parent_guardian'])
    ),
    'topics',to_jsonb(public.my_realtime_topics())
  ) into result;
  return result;
end
$function$;

insert into app.schema_migrations(version)
values ('0076_required_password_bootstrap_enforcement')
on conflict do nothing;

commit;
