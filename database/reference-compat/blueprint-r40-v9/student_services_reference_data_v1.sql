create or replace function public.student_services_reference_data(target_domain text)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
  if target_domain not in ('admissions','discipline','welfare','health','communications','hostel','alumni') then
    raise exception 'Invalid Student Services domain';
  end if;
  perform public.student_services_require_access(target_domain,'read');
  return jsonb_build_object(
    'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',y.id,'name',y.name,'is_active',y.is_active) order by y.start_date desc) from public.academic_years y where y.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'level_order',c.level_order) order by c.level_order,c.name) from public.classes c where c.deleted_at is null and c.active),'[]'::jsonb)
  );
end $$;
revoke all on function public.student_services_reference_data(text) from public,anon,authenticated;
grant execute on function public.student_services_reference_data(text) to authenticated;