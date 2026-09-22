create or replace function public.get_my_student_portal_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','extensions'
as $function$
declare
  sid uuid;
  current_enrollment_id uuid;
  current_class_id uuid;
  current_year_id uuid;
  current_roll_number integer;
  current_class_name text;
  current_year_name text;
  current_year_start date;
  current_term_id uuid;
  current_term_name text;
  current_term_sequence smallint;
  h jsonb;
  finance_enabled boolean:=public.license_feature_enabled('finance_statements');
  timetable_enabled boolean:=public.license_feature_enabled('timetable');
  attendance_enabled boolean:=public.license_feature_enabled('attendance');
  notifications_enabled boolean:=public.license_feature_enabled('notifications');
begin
  if public.current_app_role()::text<>'student' then
    raise exception 'Student access required' using errcode='42501';
  end if;

  select s.id into sid
  from public.students s
  where s.profile_id=auth.uid() and s.deleted_at is null
  order by s.updated_at desc
  limit 1;

  if sid is null then
    return jsonb_build_object(
      'linked',false,
      'student',null,
      'account',(select jsonb_build_object(
        'email',coalesce(auth.jwt()->>'email',''),
        'phone',p.phone,
        'mfa_required',p.mfa_required,
        'must_change_password',p.must_change_password,
        'last_seen_at',p.last_seen_at
      ) from public.profiles p where p.id=auth.uid()),
      'features',jsonb_build_object(
        'finance',finance_enabled,
        'timetable',timetable_enabled,
        'attendance',attendance_enabled,
        'notifications',notifications_enabled
      ),
      'fee_statement',null,
      'reports','[]'::jsonb,
      'attendance',null,
      'timetable',null,
      'notifications',jsonb_build_object('unread',0,'total',0,'recent','[]'::jsonb)
    );
  end if;

  select e.id,e.class_id,e.academic_year_id,e.roll_number,c.name::text,y.name::text,y.start_date
  into current_enrollment_id,current_class_id,current_year_id,current_roll_number,current_class_name,current_year_name,current_year_start
  from public.enrollments e
  join public.classes c on c.id=e.class_id and c.deleted_at is null
  join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
  where e.student_id=sid and e.deleted_at is null
  order by y.is_active desc,e.active desc,y.start_date desc,e.updated_at desc
  limit 1;

  if current_year_id is not null then
    select t.id,t.name::text,t.sequence
    into current_term_id,current_term_name,current_term_sequence
    from public.terms t
    where t.academic_year_id=current_year_id and t.deleted_at is null
    order by t.is_active desc,t.sequence desc
    limit 1;
  end if;

  h:=public.finance_student_hold_status(sid);

  return jsonb_build_object(
    'linked',true,
    'student',(select jsonb_build_object(
      'id',s.id,
      'admission_no',s.admission_no,
      'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
      'first_name',s.first_name,
      'middle_name',s.middle_name,
      'last_name',s.last_name,
      'gender',s.gender,
      'date_of_birth',s.date_of_birth,
      'status',s.status,
      'photo_url',s.photo_url,
      'guardian_name',s.guardian_name,
      'guardian_phone',s.guardian_phone,
      'guardian_email',s.guardian_email,
      'enrollment_id',current_enrollment_id,
      'class_id',current_class_id,
      'class_name',coalesce(current_class_name,''),
      'roll_number',current_roll_number,
      'academic_year_id',current_year_id,
      'academic_year_name',coalesce(current_year_name,''),
      'term_id',current_term_id,
      'term_name',coalesce(current_term_name,''),
      'class_teacher',(select concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
        from public.classes c
        left join public.teachers t on t.id=c.class_teacher_record_id and t.deleted_at is null
        where c.id=current_class_id)
    ) from public.students s where s.id=sid),
    'account',(select jsonb_build_object(
      'email',coalesce(auth.jwt()->>'email',''),
      'phone',p.phone,
      'mfa_required',p.mfa_required,
      'must_change_password',p.must_change_password,
      'last_seen_at',p.last_seen_at
    ) from public.profiles p where p.id=auth.uid()),
    'features',jsonb_build_object(
      'finance',finance_enabled,
      'timetable',timetable_enabled,
      'attendance',attendance_enabled,
      'notifications',notifications_enabled
    ),
    'financial_hold',h,
    'fee_statement',case when finance_enabled then public.finance_student_statement(sid) else null end,
    'reports',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'report_number',r.report_number,
        'term_name',t.name,
        'term_sequence',t.sequence,
        'academic_year_name',y.name,
        'academic_year_start',y.start_date,
        'published_at',r.published_at,
        'locked',coalesce((h->>'block_grade_details')::boolean,false),
        'average',case when coalesce((h->>'block_grade_details')::boolean,false) then null else coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0) end,
        'attendance_present',r.attendance_present,
        'attendance_total',r.attendance_total,
        'publication',case when coalesce((h->>'block_report_pdf')::boolean,false) then null else (
          select jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at)
          from public.report_publications rp
          where rp.report_id=r.id and rp.revoked_at is null
          order by rp.published_at desc
          limit 1
        ) end
      ) order by y.start_date desc nulls last,t.sequence desc)
      from public.enrollments e
      join public.student_reports r on r.enrollment_id=e.id and r.status='published' and r.deleted_at is null
      join public.terms t on t.id=r.term_id
      join public.academic_years y on y.id=t.academic_year_id
      where e.student_id=sid and e.deleted_at is null
    ),'[]'::jsonb),
    'attendance',case when attendance_enabled and current_enrollment_id is not null then jsonb_build_object(
      'current',case when current_term_id is null then null else (
        select jsonb_build_object(
          'term_id',current_term_id,
          'term_name',current_term_name,
          'class_name',current_class_name,
          'days_opened',count(distinct r.id),
          'present',count(a.id) filter(where a.attendance_status='present'),
          'late',count(a.id) filter(where a.attendance_status='late'),
          'absent',count(a.id) filter(where a.attendance_status='absent'),
          'excused',count(a.id) filter(where a.attendance_status='excused'),
          'days_present',count(a.id) filter(where a.attendance_status in ('present','late')),
          'percentage',case when count(distinct r.id)>0 then round((count(a.id) filter(where a.attendance_status in ('present','late')))::numeric*100/count(distinct r.id),1) else 0 end
        )
        from public.class_attendance_registers r
        left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=current_enrollment_id
        where r.term_id=current_term_id and r.class_id=current_class_id
      ) end,
      'history',coalesce((
        select jsonb_agg(jsonb_build_object(
          'term_id',q.term_id,
          'term_name',q.term_name,
          'term_sequence',q.term_sequence,
          'academic_year_name',q.academic_year_name,
          'class_name',q.class_name,
          'days_opened',q.days_opened,
          'present',q.present,
          'late',q.late,
          'absent',q.absent,
          'excused',q.excused,
          'days_present',q.days_present,
          'percentage',q.percentage
        ) order by q.year_start desc,q.term_sequence desc)
        from (
          select
            t.id as term_id,
            t.name::text as term_name,
            t.sequence as term_sequence,
            y.name::text as academic_year_name,
            y.start_date as year_start,
            c.name::text as class_name,
            count(distinct r.id)::integer as days_opened,
            count(a.id) filter(where a.attendance_status='present')::integer as present,
            count(a.id) filter(where a.attendance_status='late')::integer as late,
            count(a.id) filter(where a.attendance_status='absent')::integer as absent,
            count(a.id) filter(where a.attendance_status='excused')::integer as excused,
            count(a.id) filter(where a.attendance_status in ('present','late'))::integer as days_present,
            case when count(distinct r.id)>0 then round((count(a.id) filter(where a.attendance_status in ('present','late')))::numeric*100/count(distinct r.id),1) else 0 end as percentage
          from public.enrollments e
          join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
          join public.classes c on c.id=e.class_id and c.deleted_at is null
          join public.terms t on t.academic_year_id=e.academic_year_id and t.deleted_at is null
          left join public.class_attendance_registers r on r.term_id=t.id and r.class_id=e.class_id
          left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=e.id
          where e.student_id=sid and e.deleted_at is null
          group by t.id,t.name,t.sequence,y.name,y.start_date,c.name
        ) q
      ),'[]'::jsonb)
    ) else null end,
    'timetable',case when timetable_enabled and current_year_id is not null and current_class_id is not null then jsonb_build_object(
      'academic_year_id',current_year_id,
      'academic_year_name',current_year_name,
      'class_id',current_class_id,
      'class_name',current_class_name,
      'entries',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',e.id,
          'day_of_week',e.day_of_week,
          'period_start',e.period_start,
          'period_end',e.period_end,
          'subject_id',e.subject_id,
          'subject_name',s.name,
          'teacher_id',e.teacher_id,
          'teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
          'notes',e.notes
        ) order by array_position(array['Monday','Tuesday','Wednesday','Thursday','Friday'],e.day_of_week),e.period_start)
        from public.class_timetable_entries e
        join public.subjects s on s.id=e.subject_id and s.deleted_at is null
        join public.teachers t on t.id=e.teacher_id and t.deleted_at is null
        where e.academic_year_id=current_year_id and e.class_id=current_class_id and e.active
          and e.day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday')
      ),'[]'::jsonb)
    ) else null end,
    'notifications',case when notifications_enabled then jsonb_build_object(
      'unread',(select count(*) from public.notifications n where n.recipient_id=auth.uid() and n.read_at is null),
      'total',(select count(*) from public.notifications n where n.recipient_id=auth.uid()),
      'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
        select n.id,n.title,n.body,n.category,n.entity_type,n.entity_id,n.read_at,n.created_at
        from public.notifications n
        where n.recipient_id=auth.uid()
        order by n.created_at desc
        limit 8
      ) q),'[]'::jsonb)
    ) else jsonb_build_object('unread',0,'total',0,'recent','[]'::jsonb) end
  );
end
$function$;

revoke all on function public.get_my_student_portal_v2() from public;
revoke all on function public.get_my_student_portal_v2() from anon;
grant execute on function public.get_my_student_portal_v2() to authenticated;
