create or replace function public.admissions_reference_data()
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
  if public.student_services_has_access('admissions','read') then
    perform public.student_services_require_access('admissions','read');
    return public.student_services_reference_data('admissions');
  end if;
  if public.student_services_has_access('hostel','read') then
    perform public.student_services_require_access('hostel','read');
    return public.student_services_reference_data('hostel');
  end if;
  raise exception 'Student Services access denied' using errcode='42501';
end $$;
revoke all on function public.admissions_reference_data() from public,anon,authenticated;
grant execute on function public.admissions_reference_data() to authenticated;