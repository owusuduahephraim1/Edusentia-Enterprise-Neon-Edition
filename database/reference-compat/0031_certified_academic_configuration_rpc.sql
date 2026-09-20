-- Certified source: Supabase project zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function extracted read-only via pg_get_functiondef.

begin;

CREATE OR REPLACE FUNCTION public.get_academic_configuration()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'academic_years',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc nulls last) from public.academic_years x where x.deleted_at is null),'[]'::jsonb),
    'terms',coalesce((select jsonb_agg(to_jsonb(x) order by x.academic_year_id,x.sequence) from public.terms x where x.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(to_jsonb(x) order by x.level_order,x.name) from public.classes x where x.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.name) from public.subjects x where x.deleted_at is null),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(jsonb_build_object(
      'id',cs.id,'class_id',cs.class_id,'class_name',c.name,'subject_id',cs.subject_id,'subject_name',s.name,
      'teacher_id',cs.teacher_id,'teacher_name',p.full_name,'active',cs.active
    ) order by c.level_order,c.name,s.display_order,s.name)
      from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id
      left join public.profiles p on p.id=cs.teacher_id),'[]'::jsonb),
    'grading_scales',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.min_mark desc) from public.grading_scales x where x.deleted_at is null),'[]'::jsonb),
    'assessment_schemes',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'academic_year_id',s.academic_year_id,'term_id',s.term_id,
      'class_id',s.class_id,'subject_id',s.subject_id,'active',s.active,
      'components',coalesce((select jsonb_agg(to_jsonb(c) order by c.display_order,c.name)
        from public.assessment_components c where c.scheme_id=s.id),'[]'::jsonb),
      'total_weight',(select coalesce(sum(c.weight),0) from public.assessment_components c where c.scheme_id=s.id)
    ) order by lower(s.name)) from public.assessment_schemes s where s.deleted_at is null),'[]'::jsonb),
    'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role))
      order by lower(p.full_name),p.id) from public.profiles p where p.active),'[]'::jsonb),
    'teacher_records',coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,
      'profile_id',t.profile_id,
      'staff_no',t.staff_no,
      'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
      'label',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
        ||' • '||t.staff_no::text
        ||case when t.profile_id is null then ' • No linked account' else '' end,
      'active',t.active
    ) order by lower(concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)),t.staff_no::text)
      from public.teachers t
      where t.deleted_at is null and t.active and t.employment_status='active'),'[]'::jsonb)
  );
end $function$;


revoke all on function public.get_academic_configuration() from public;
grant execute on function public.get_academic_configuration() to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0031_certified_academic_configuration_rpc')
on conflict do nothing;

update app.release_identity
set schema_version='0031'
where edition='Edusentia Enterprise Neon Edition';

commit;
