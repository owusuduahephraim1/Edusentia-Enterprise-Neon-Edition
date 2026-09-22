create or replace function public.admissions_enroll_application(target_application_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_catalog','extensions' as $$
declare a public.admissions_applications%rowtype;o public.admissions_offers%rowtype;v_student uuid;v_no text;
begin
 perform public.student_services_require_access('admissions','enroll');
 select * into a from public.admissions_applications where id=target_application_id for update;
 if a.id is null or a.status<>'accepted' then raise exception 'Only an accepted application can be enrolled'; end if;
 if a.student_id is not null then raise exception 'Application is already linked to a student'; end if;
 select * into o from public.admissions_offers where application_id=a.id and status='accepted' order by accepted_at desc nulls last,created_at desc limit 1 for update;
 if o.id is null then raise exception 'Accepted offer is required before enrollment'; end if;
 if not exists(select 1 from public.academic_years y where y.id=o.academic_year_id and y.deleted_at is null) then raise exception 'Offer academic year is unavailable'; end if;
 if not exists(select 1 from public.classes c where c.id=o.class_id and c.active and c.deleted_at is null) then raise exception 'Offer class is unavailable'; end if;
 v_no:=public.admissions_next_student_no();
 insert into public.students(admission_no,first_name,middle_name,last_name,gender,date_of_birth,guardian_name,guardian_phone,guardian_email,status)
 values(v_no,a.first_name,coalesce(a.middle_name,''),a.last_name,a.gender,a.date_of_birth,coalesce(a.guardian_name,''),coalesce(a.guardian_phone,''),coalesce(a.guardian_email,''),'active') returning id into v_student;
 insert into public.enrollments(student_id,academic_year_id,class_id,active,enrollment_origin) values(v_student,o.academic_year_id,o.class_id,true,'manual');
 update public.admissions_offers set status='enrolled' where id=o.id;
 update public.admissions_applications set status='enrolled',student_id=v_student,enrolled_at=now() where id=a.id;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','applicant_enrolled','admissions_application',a.id,auth.uid(),jsonb_build_object('student_id',v_student,'admission_no',v_no,'academic_year_id',o.academic_year_id,'class_id',o.class_id));
 return jsonb_build_object('student_id',v_student,'admission_no',v_no,'academic_year_id',o.academic_year_id,'class_id',o.class_id);
end $$;
revoke all on function public.admissions_enroll_application(uuid) from public,anon,authenticated;
grant execute on function public.admissions_enroll_application(uuid) to authenticated;