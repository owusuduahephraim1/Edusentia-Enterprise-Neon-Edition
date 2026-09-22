do $migration$
declare
  ddl text;
begin
  if to_regprocedure('public.get_my_student_portal_v2()') is null then
    raise exception 'get_my_student_portal_v2 is not installed';
  end if;

  select pg_get_functiondef('public.get_my_student_portal_v2()'::regprocedure) into ddl;
  ddl := replace(ddl, '''attendance_present'',r.attendance_present', '''attendance_present'',r.days_present');
  ddl := replace(ddl, '''attendance_total'',r.attendance_total', '''attendance_total'',r.days_school_opened');

  if position('r.attendance_present' in ddl) > 0 or position('r.attendance_total' in ddl) > 0 then
    raise exception 'Student Portal attendance compatibility patch did not fully apply';
  end if;

  execute ddl;
end
$migration$;

revoke all on function public.get_my_student_portal_v2() from public;
revoke all on function public.get_my_student_portal_v2() from anon;
grant execute on function public.get_my_student_portal_v2() to authenticated;
