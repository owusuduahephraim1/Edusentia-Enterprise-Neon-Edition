begin;

-- Neon-native completion of the certified public-table RLS posture.
-- Browser/API callers never connect directly to these tables. Certified RPCs
-- execute as edusentia_runtime and retain their own authorization checks.
-- The policy below is therefore deliberately limited to the trusted RPC owner.
do $rls$
declare
  t text;
begin
  if not exists(select 1 from pg_roles where rolname='edusentia_runtime') then
    raise exception 'edusentia_runtime role is required for certified RLS enforcement'
      using errcode='42704';
  end if;

  foreach t in array array[
    'terms','classes','profiles','students','subjects','enrollments',
    'academic_years','class_subjects','grading_scales','guardian_links',
    'student_reports','subject_results','student_guardians','user_class_access',
    'assessment_schemes','assessment_components','assessment_score_entries'
  ]
  loop
    execute format('alter table public.%I enable row level security',t);

    if not exists(
      select 1 from pg_policies
      where schemaname='public'
        and tablename=t
        and policyname='neon_certified_runtime_owner'
    ) then
      execute format(
        'create policy neon_certified_runtime_owner on public.%I for all to edusentia_runtime using (true) with check (true)',
        t
      );
    end if;

    execute format('alter table public.%I force row level security',t);
  end loop;
end
$rls$;

insert into app.schema_migrations(version)
values ('0048g_certified_operational_rls_enforcement')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
