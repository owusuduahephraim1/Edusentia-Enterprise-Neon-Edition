-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function body extracted read-only with pg_get_functiondef.
-- Read-only academic-history parity: principals may view archived student history.
-- Destructive records-management functions remain unchanged and System-Admin governed.

begin;

CREATE OR REPLACE FUNCTION public.search_students_v5(search_text text DEFAULT ''::text, target_class_id uuid DEFAULT NULL::uuid, target_status student_status DEFAULT NULL::student_status, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
declare limit_value integer:=least(greatest(page_size,1),100);
begin
  if archive_filter not in ('active','archived','all') then archive_filter:='active'; end if;
  if archive_filter<>'active' and public.current_app_role() not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return (
    with matching as (
      select s.id,s.admission_no,s.first_name,s.middle_name,s.last_name,s.gender,s.date_of_birth,
        s.photo_url,s.status,s.updated_at,s.deleted_at,(s.deleted_at is not null) archived,
        e.id enrollment_id,e.class_id,e.academic_year_id,e.roll_number,
        c.name class_name,y.name academic_year_name,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) display_name
      from public.students s
      left join lateral (
        select en.* from public.enrollments en
        join public.academic_years ay on ay.id=en.academic_year_id and ay.deleted_at is null
        where en.student_id=s.id and en.deleted_at is null
        order by en.active desc,
          coalesce(ay.start_date,ay.end_date,en.created_at::date) desc,
          ay.name::text desc,en.created_at desc limit 1
      ) e on true
      left join public.classes c on c.id=e.class_id
      left join public.academic_years y on y.id=e.academic_year_id
      where (public.current_app_role() in ('system_admin','principal') or (e.id is not null and public.can_access_class(e.class_id,false)))
        and (archive_filter='all'
          or (archive_filter='active' and s.deleted_at is null)
          or (archive_filter='archived' and s.deleted_at is not null))
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or s.status=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x)-'display_name' order by lower(x.display_name),x.admission_no::text) from (
        select * from matching order by lower(display_name),admission_no::text limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end
$function$;

revoke all on function public.search_students_v5(text,uuid,public.student_status,text,integer,integer) from public;
revoke all on function public.search_students_v5(text,uuid,public.student_status,text,integer,integer) from edusentia_worker_runtime;
grant execute on function public.search_students_v5(text,uuid,public.student_status,text,integer,integer)
  to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0042_certified_principal_academic_history_read')
on conflict do nothing;

update app.release_identity
set schema_version='0042'
where edition='Edusentia Enterprise Neon Edition';

commit;
