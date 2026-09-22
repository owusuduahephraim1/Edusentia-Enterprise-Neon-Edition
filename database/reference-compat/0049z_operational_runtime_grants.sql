-- Final operational parity revalidation: migration inventory and existing-tenant upgrader.
-- Operational parity certification trigger: existing-tenant upgrade verified.
-- Edusentia Neon operational parity runtime grants.
begin;

do $integrity$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.finance_payroll_profiles'::regclass
      and conname='finance_payroll_profiles_hr_staff_member_id_fkey'
  ) then
    alter table public.finance_payroll_profiles
      add constraint finance_payroll_profiles_hr_staff_member_id_fkey
      foreign key (hr_staff_member_id) references public.hr_staff_members(id) on delete restrict;
  end if;
end
$integrity$;

do $grant$
declare r record;
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (
        p.proname like 'finance_%'
        or p.proname like 'hr_%'
        or p.proname like 'student_services_%'
        or p.proname like 'admissions_%'
        or p.proname like 'discipline_%'
        or p.proname like 'welfare_%'
        or p.proname like 'health_%'
        or p.proname like 'communications_%'
        or p.proname like 'hostel_%'
        or p.proname like 'alumni_%'
        or p.proname like 'admin_%accounts_staff%'
        or p.proname in ('get_my_student_portal','get_my_student_portal_v2')
      )
  loop
    execute format('revoke all on function %s from public',r.signature);
    execute format('grant execute on function %s to edusentia_worker_runtime',r.signature);
  end loop;
end
$grant$;

insert into app.schema_migrations(version)
values ('0049_operational_blueprint_parity')
on conflict do nothing;

commit;
