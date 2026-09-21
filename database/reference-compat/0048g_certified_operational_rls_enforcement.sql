begin;

-- Complete the certified public-table RLS posture required by the reference
-- operational-readiness contract. Refuse to force RLS on a table unless its
-- certified policy surface is present.
do $$
declare
  t text;
  policy_count integer;
begin
  foreach t in array array[
    'terms','classes','profiles','students','subjects','enrollments',
    'academic_years','class_subjects','grading_scales','guardian_links',
    'student_reports','subject_results','student_guardians','user_class_access',
    'assessment_schemes','assessment_components','assessment_score_entries'
  ]
  loop
    select count(*) into policy_count
    from pg_policies
    where schemaname='public' and tablename=t;

    if policy_count=0 then
      raise exception 'Certified RLS policy surface missing for public.%',t
        using errcode='55000';
    end if;

    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
  end loop;
end $$;

insert into app.schema_migrations(version)
values ('0048g_certified_operational_rls_enforcement')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
