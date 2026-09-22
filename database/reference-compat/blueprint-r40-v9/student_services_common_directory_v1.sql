create or replace function public.student_services_student_picker(target_domain text,search_text text default null)
returns jsonb language plpgsql stable security definer set search_path='public','pg_catalog','extensions' as $$
begin
 if target_domain not in ('discipline','welfare','health','hostel','alumni','communications') then raise exception 'Invalid Student Services domain'; end if;
 perform public.student_services_require_access(target_domain,'read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name) from (
  select s.id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) full_name,s.gender,s.status,
   (select c.name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=s.id and e.active and e.deleted_at is null order by e.created_at desc limit 1) class_name
  from public.students s where s.deleted_at is null and s.status='active'
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
  order by full_name limit 150
 )q),'[]'::jsonb);
end $$;
revoke all on function public.student_services_student_picker(text,text) from public,anon,authenticated;
grant execute on function public.student_services_student_picker(text,text) to authenticated;