-- Edusentia tenant foundation: public functions
-- Read-only schema snapshot from live Edusentia Supabase.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;
SET check_function_bodies=off;

CREATE OR REPLACE FUNCTION public.academic_analytics(target_term_id uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.require_license_feature('analytics');
  return public.academic_analytics_v729(target_term_id,target_class_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.academic_analytics_v729(target_term_id uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then raise exception 'Access denied' using errcode='42501'; end if;
  if target_class_id is not null and public.current_app_role() not in ('system_admin','principal') and not public.can_access_class(target_class_id,false) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'term_id',target_term_id,'class_id',target_class_id,
    'summary',jsonb_build_object(
      'students',(select count(distinct e.student_id) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=target_term_id and e.active and e.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'reports',(select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'average',(select round(avg(sr.total_score),2) from public.subject_results sr join public.student_reports r on r.id=sr.report_id join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'attendance_rate',(select round(100.0*sum(r.days_present)/nullif(sum(r.days_school_opened),0),2) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'published',(select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.status='published' and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id))
    ),
    'subjects',coalesce((select jsonb_agg(jsonb_build_object('subject_id',s.id,'subject_code',s.code,'subject_name',s.name,'average',q.average,'highest',q.highest,'lowest',q.lowest,'scored',q.scored) order by s.display_order,s.name)
      from public.subjects s join lateral (select round(avg(sr.total_score),2) average,max(sr.total_score) highest,min(sr.total_score) lowest,count(*) scored from public.subject_results sr join public.student_reports r on r.id=sr.report_id join public.enrollments e on e.id=r.enrollment_id where sr.subject_id=s.id and r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)) q on q.scored>0 where s.active and s.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'average',q.average,'attendance_rate',q.attendance_rate,'students',q.students,'published',q.published) order by c.level_order,c.name)
      from public.classes c join lateral (select round(avg(sr.total_score),2) average,round(100.0*sum(distinct r.days_present)/nullif(sum(distinct r.days_school_opened),0),2) attendance_rate,count(distinct e.student_id) students,count(distinct r.id) filter(where r.status='published') published from public.enrollments e left join public.student_reports r on r.enrollment_id=e.id and r.term_id=target_term_id and r.deleted_at is null left join public.subject_results sr on sr.report_id=r.id where e.class_id=c.id and e.active and e.deleted_at is null and e.academic_year_id=(select academic_year_id from public.terms where id=target_term_id)) q on q.students>0 where c.active and c.deleted_at is null and (target_class_id is null or c.id=target_class_id) and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(c.id,false))),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.academic_configuration_readiness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  target_year_id uuid;
  target_year_name text;
  target_year_start date;
  target_year_end date;
  term_count integer:=0;
  last_term_end date;
  term_gap_days integer:=0;
  enrolled_class_count integer:=0;
  zero_subject_count integer:=0;
  no_class_teacher_count integer:=0;
  grading_issue_count integer:=0;
  scheme_issue_count integer:=0;
  active_scheme_count integer:=0;
  zero_subject_classes jsonb:='[]'::jsonb;
  no_class_teacher_classes jsonb:='[]'::jsonb;
  grading_issues jsonb:='[]'::jsonb;
  scheme_issues jsonb:='[]'::jsonb;
  blocking_count integer:=0;
  warning_count integer:=0;
begin
  if not public.is_academic_manager() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select y.id,y.name::text,y.start_date,y.end_date
  into target_year_id,target_year_name,target_year_start,target_year_end
  from public.academic_years y
  where y.deleted_at is null
    and (
      (y.start_date is not null and y.start_date<=current_date and (y.end_date is null or y.end_date>=current_date))
      or y.start_date>current_date
    )
  order by
    case when y.start_date<=current_date and (y.end_date is null or y.end_date>=current_date) then 0 else 1 end,
    y.start_date
  limit 1;

  if target_year_id is null then
    return jsonb_build_object(
      'ready',false,'status','attention','blocking_count',1,'warning_count',0,
      'target_academic_year',null,'term_count',0,'term_coverage_gap_days',null,
      'enrolled_class_count',0,'classes_without_subjects','[]'::jsonb,
      'classes_without_class_teacher','[]'::jsonb,
      'grading_issues','[]'::jsonb,'assessment_scheme_issues','[]'::jsonb,
      'message','No current or upcoming academic year is configured.'
    );
  end if;

  select count(*)::int,max(t.end_date)
  into term_count,last_term_end
  from public.terms t
  where t.academic_year_id=target_year_id and t.deleted_at is null;

  if target_year_end is not null and last_term_end is not null and last_term_end<target_year_end then
    term_gap_days:=target_year_end-last_term_end;
  end if;

  with enrolled_classes as (
    select c.id,c.name::text,c.level_order,c.class_teacher_id,
      count(distinct e.id)::int as enrollment_count,
      count(distinct cs.id) filter(where cs.active)::int as subject_count
    from public.enrollments e
    join public.classes c on c.id=e.class_id and c.deleted_at is null and c.active
    left join public.class_subjects cs on cs.class_id=c.id and cs.active
    where e.academic_year_id=target_year_id and e.active and e.deleted_at is null
    group by c.id,c.name,c.level_order,c.class_teacher_id
  )
  select
    count(*)::int,
    count(*) filter(where subject_count=0)::int,
    count(*) filter(where class_teacher_id is null)::int,
    coalesce(jsonb_agg(jsonb_build_object('class_id',id,'class_name',name,'enrollments',enrollment_count)
      order by level_order) filter(where subject_count=0),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('class_id',id,'class_name',name,'enrollments',enrollment_count)
      order by level_order) filter(where class_teacher_id is null),'[]'::jsonb)
  into enrolled_class_count,zero_subject_count,no_class_teacher_count,zero_subject_classes,no_class_teacher_classes
  from enrolled_classes;

  with bands as (
    select g.id,g.academic_year_id,g.class_id,g.subject_id,g.min_mark,g.max_mark,
      lead(g.min_mark) over(
        partition by g.academic_year_id,g.class_id,g.subject_id
        order by g.min_mark
      ) as next_min
    from public.grading_scales g
    where g.deleted_at is null
  ), scope_summary as (
    select academic_year_id,class_id,subject_id,
      min(min_mark) as first_min,max(max_mark) as last_max,
      count(*) filter(where next_min is not null and next_min-max_mark>0.01)::int as internal_gaps
    from bands
    group by academic_year_id,class_id,subject_id
  ), problems as (
    select s.*,ay.name::text as academic_year_name,c.name::text as class_name,sb.name::text as subject_name
    from scope_summary s
    left join public.academic_years ay on ay.id=s.academic_year_id
    left join public.classes c on c.id=s.class_id
    left join public.subjects sb on sb.id=s.subject_id
    where s.first_min>0 or s.last_max<100 or s.internal_gaps>0
  )
  select count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object(
      'academic_year',academic_year_name,'class_name',class_name,'subject_name',subject_name,
      'first_min',first_min,'last_max',last_max,'internal_gaps',internal_gaps
    )),'[]'::jsonb)
  into grading_issue_count,grading_issues
  from problems;

  select count(*)::int into active_scheme_count
  from public.assessment_schemes s
  where s.deleted_at is null and s.active;

  with problems as (
    select s.id,s.name::text as name,count(c.id)::int as component_count,coalesce(sum(c.weight),0) as total_weight
    from public.assessment_schemes s
    left join public.assessment_components c on c.scheme_id=s.id
    where s.deleted_at is null and s.active
    group by s.id,s.name
    having count(c.id)=0 or abs(coalesce(sum(c.weight),0)-100)>0.01
  )
  select count(*)::int,
    coalesce(jsonb_agg(jsonb_build_object('scheme_id',id,'name',name,'components',component_count,'total_weight',total_weight)),'[]'::jsonb)
  into scheme_issue_count,scheme_issues
  from problems;

  blocking_count:=zero_subject_count+grading_issue_count+scheme_issue_count;
  if term_count=0 then blocking_count:=blocking_count+1; end if;
  if active_scheme_count=0 then blocking_count:=blocking_count+1; end if;

  warning_count:=no_class_teacher_count;
  if term_gap_days>21 then warning_count:=warning_count+1; end if;

  return jsonb_build_object(
    'ready',blocking_count=0,
    'status',case when blocking_count=0 and warning_count=0 then 'ready' else 'attention' end,
    'blocking_count',blocking_count,
    'warning_count',warning_count,
    'checked_at',now(),
    'target_academic_year',jsonb_build_object(
      'id',target_year_id,'name',target_year_name,'start_date',target_year_start,'end_date',target_year_end
    ),
    'term_count',term_count,
    'last_term_end',last_term_end,
    'term_coverage_gap_days',term_gap_days,
    'enrolled_class_count',enrolled_class_count,
    'classes_without_subjects',zero_subject_classes,
    'classes_without_class_teacher',no_class_teacher_classes,
    'grading_issues',grading_issues,
    'assessment_scheme_issues',scheme_issues,
    'active_assessment_schemes',active_scheme_count
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.academic_year_auto_status_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if pg_trigger_depth()>1 then return null; end if;
  perform public.sync_current_academic_year_status();
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.acknowledge_emergency_academic_delegation(target_delegation_id uuid, note_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare currentrow public.emergency_academic_delegations%rowtype;note_value text:=btrim(coalesce(note_text,''));
begin
  if public.current_app_role()<>'principal' then raise exception 'Only the Principal can acknowledge an emergency delegation' using errcode='42501'; end if;
  if not public.license_write_allowed() then raise exception 'The current licence does not permit this change' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  select * into currentrow from public.emergency_academic_delegations where id=target_delegation_id for update;
  if currentrow.id is null then raise exception 'Delegation not found' using errcode='P0002'; end if;
  if currentrow.principal_acknowledged_at is not null then return public.get_emergency_delegation_console(); end if;
  update public.emergency_academic_delegations
  set principal_acknowledged_at=now(),principal_acknowledged_by=auth.uid(),principal_acknowledgement_note=note_value
  where id=target_delegation_id returning * into currentrow;
  insert into public.emergency_academic_delegation_events(delegation_id,event_type,actor_id,event_reason,event_data)
  values(currentrow.id,'principal_acknowledged',auth.uid(),coalesce(nullif(note_value,''),'Principal acknowledgement'),to_jsonb(currentrow));
  perform public.create_notification(currentrow.created_by,'Principal acknowledged emergency delegation',
    'The Principal has reviewed the temporary academic delegation.',
    'emergency_academic_delegation','emergency_academic_delegation',currentrow.id,false);
  return public.get_emergency_delegation_console();
end $function$
;

CREATE OR REPLACE FUNCTION public.active_emergency_delegation_ids(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean DEFAULT false, require_class_fields boolean DEFAULT false, target_user_id uuid DEFAULT auth.uid())
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(array_agg(d.id order by d.valid_until,d.created_at),'{}'::uuid[])
  from public.emergency_academic_delegations d
  join public.profiles p on p.id=d.delegate_user_id and p.active
  join public.terms t on t.id=d.term_id and t.deleted_at is null
  join public.academic_years y on y.id=d.academic_year_id and y.deleted_at is null
  join public.classes c on c.id=d.class_id and c.active and c.deleted_at is null
  where d.delegate_user_id=target_user_id
    and d.class_id=target_class_id
    and d.term_id=target_term_id
    and t.academic_year_id=d.academic_year_id
    and d.status='active'
    and now()>=d.valid_from
    and now()<d.valid_until
    and (not require_score_entry or d.allow_score_entry)
    and (not require_class_fields or d.allow_class_report_fields)
    and (
      target_subject_id is null
      or d.subject_id is null
      or d.subject_id=target_subject_id
    )
$function$
;

CREATE OR REPLACE FUNCTION public.admin_accounts_staff_directory(search_text text DEFAULT ''::text, include_inactive boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object('rows',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',a.id,'profile_id',a.profile_id,'staff_no',a.staff_no,'full_name',a.full_name,'phone',a.phone,'email',a.email,
      'contact_address',a.contact_address,'job_title',a.job_title,'active',a.active,'deleted_at',a.deleted_at,
      'portal_email',u.email,'portal_active',p.active,'last_seen_at',p.last_seen_at
    ) order by lower(a.full_name),a.staff_no::text)
    from public.accounts_office_staff a
    left join public.profiles p on p.id=a.profile_id
    left join auth.users u on u.id=a.profile_id
    where (include_inactive or (a.active and a.deleted_at is null))
      and (coalesce(search_text,'')='' or concat_ws(' ',a.full_name,a.staff_no::text,a.phone,a.email,a.contact_address) ilike '%'||search_text||'%')
  ),'[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_apply_user_bundle(actor_id uuid, bundle jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(bundle->>'user_id');staffrecordid uuid:=public.safe_uuid(bundle->>'staff_record_id');role_text text:=btrim(coalesce(bundle->>'role','viewer'));
  item jsonb;classid uuid;subjectid uuid;accesslevel text;previous jsonb;resolved_name text:=btrim(coalesce(bundle->>'full_name',''));resolved_phone text:=btrim(coalesce(bundle->>'phone',''));
begin
  perform public.admin_validate_user_bundle(actor_id,bundle,true);
  if role_text in ('class_teacher','subject_teacher') then select concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),coalesce(nullif(t.phone,''),resolved_phone) into resolved_name,resolved_phone from public.teachers t where t.id=staffrecordid and t.deleted_at is null;
  elsif role_text='principal' then select concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),coalesce(nullif(h.phone,''),resolved_phone) into resolved_name,resolved_phone from public.headteachers h where h.id=staffrecordid and h.deleted_at is null;
  elsif role_text='accountant' then select a.full_name,coalesce(nullif(a.phone,''),resolved_phone) into resolved_name,resolved_phone from public.accounts_office_staff a where a.id=staffrecordid and a.deleted_at is null;
  elsif role_text='student' then select concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) into resolved_name from public.students s where s.id=staffrecordid and s.deleted_at is null;
  end if;
  select jsonb_build_object('profile',to_jsonb(p),'teacher',(select to_jsonb(t) from public.teachers t where t.profile_id=targetid and t.deleted_at is null limit 1),'principal',(select to_jsonb(h) from public.headteachers h where h.profile_id=targetid and h.deleted_at is null limit 1),'accountant',(select to_jsonb(a) from public.accounts_office_staff a where a.profile_id=targetid and a.deleted_at is null limit 1),'student',(select to_jsonb(s) from public.students s where s.profile_id=targetid and s.deleted_at is null limit 1),'access',coalesce((select jsonb_agg(to_jsonb(x)) from public.user_class_access x where x.user_id=targetid),'[]'::jsonb)) into previous from public.profiles p where p.id=targetid;
  insert into public.profiles(id,full_name,role,active,mfa_required,must_change_password,phone,updated_at)
  values(targetid,resolved_name,role_text::public.app_role,public.safe_boolean(bundle->>'active',true),public.safe_boolean(bundle->>'mfa_required',false),public.safe_boolean(bundle->>'must_change_password',false),resolved_phone,now())
  on conflict(id) do update set full_name=excluded.full_name,role=excluded.role,active=excluded.active,mfa_required=excluded.mfa_required,must_change_password=excluded.must_change_password,phone=excluded.phone,updated_at=now();
  update public.teachers set profile_id=null,updated_at=now() where profile_id=targetid and (role_text not in ('class_teacher','subject_teacher') or id<>staffrecordid);
  update public.headteachers set profile_id=null,updated_at=now() where profile_id=targetid and (role_text<>'principal' or id<>staffrecordid);
  update public.accounts_office_staff set profile_id=null where profile_id=targetid and (role_text<>'accountant' or id<>staffrecordid);
  update public.students set profile_id=null,updated_at=now() where profile_id=targetid and (role_text<>'student' or id<>staffrecordid);
  if role_text in ('class_teacher','subject_teacher') then update public.teachers set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  elsif role_text='principal' then update public.headteachers set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  elsif role_text='accountant' then update public.accounts_office_staff set profile_id=targetid,finance_role='accountant',job_title='Accountant' where id=staffrecordid and deleted_at is null;
  elsif role_text='student' then update public.students set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  end if;
  delete from public.user_class_access where user_id=targetid;
  for item in select value from jsonb_array_elements(coalesce(bundle->'access','[]'::jsonb)) loop classid:=public.safe_uuid(item->>'class_id');subjectid:=public.safe_uuid(item->>'subject_id');accesslevel:=coalesce(nullif(btrim(item->>'access_level'),''),'view');insert into public.user_class_access(user_id,class_id,subject_id,access_level) values(targetid,classid,subjectid,accesslevel);end loop;
  if role_text in ('class_teacher','subject_teacher') then perform public.sync_teacher_responsibility_access(targetid); end if;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(actor_id,'profiles',targetid,case when previous is null then 'ADMIN_CREATE_USER' else 'ADMIN_UPDATE_USER' end,previous,jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where p.id=targetid),'teacher',(select to_jsonb(t) from public.teachers t where t.profile_id=targetid and t.deleted_at is null limit 1),'principal',(select to_jsonb(h) from public.headteachers h where h.profile_id=targetid and h.deleted_at is null limit 1),'accountant',(select to_jsonb(a) from public.accounts_office_staff a where a.profile_id=targetid and a.deleted_at is null limit 1),'student',(select to_jsonb(s) from public.students s where s.profile_id=targetid and s.deleted_at is null limit 1),'access',coalesce((select jsonb_agg(to_jsonb(x)) from public.user_class_access x where x.user_id=targetid),'[]'::jsonb)),coalesce(nullif(bundle->>'reason',''),'User account management'));
  return jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where p.id=targetid),'accountant',(select to_jsonb(a) from public.accounts_office_staff a where a.profile_id=targetid and a.deleted_at is null limit 1),'student',(select to_jsonb(s) from public.students s where s.profile_id=targetid and s.deleted_at is null limit 1));
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_deactivate_accounts_staff(target_staff_id uuid, reason_text text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare linked uuid;l jsonb;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  l:=public.license_snapshot_for_role('system_admin');
  if coalesce((l->>'write_allowed')::boolean,false)<>true then raise exception 'The current licence is read-only' using errcode='42501'; end if;
  select profile_id into linked from public.accounts_office_staff where id=target_staff_id and deleted_at is null;
  if not found then raise exception 'Accounts Office staff record was not found'; end if;
  update public.accounts_office_staff set active=false,deleted_at=now() where id=target_staff_id;
  if linked is not null then update public.profiles set active=false,updated_at=now() where id=linked and public.current_app_role_for(role)='accountant'; end if;
  insert into public.audit_log(actor_id,table_name,record_id,action,reason) values(auth.uid(),'accounts_office_staff',target_staff_id,'ACCOUNTANT_DIRECTORY_DEACTIVATE',coalesce(nullif(reason_text,''),'Accountant directory record deactivated'));
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_finance_test_payment_cleanup_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rows_json jsonb;
begin
  if auth.uid() is null or coalesce(public.current_app_role()::text,'') <> 'system_admin' then
    raise exception 'System Administrator access required' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb)
  into rows_json
  from (
    select
      tx.id transaction_id,
      tx.receipt_no,
      tx.credit_amount amount,
      tx.payment_method method,
      tx.payment_reference reference,
      tx.transaction_date,
      tx.created_at,
      tx.student_id,
      concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student,
      s.admission_no,
      string_agg(distinct y.name::text,', ' order by y.name::text) academic_year,
      string_agg(distinct t.name::text,', ' order by t.name::text) term,
      string_agg(distinct c.name::text,', ' order by c.name::text) class_name,
      coalesce(nullif(p.full_name,''),'Unknown user') recorded_by,
      coalesce(p.role::text,'') recorded_by_role,
      exists(select 1 from public.finance_fee_transactions rv where rv.reversal_of_id=tx.id) reversed,
      public.finance_student_outstanding(tx.student_id) current_outstanding
    from public.finance_fee_transactions tx
    join public.students s on s.id=tx.student_id
    left join public.profiles p on p.id=tx.created_by
    join public.finance_fee_allocations al on al.transaction_id=tx.id
    join public.finance_fee_account_balances b on b.id=al.account_id
    join public.academic_years y on y.id=b.academic_year_id
    join public.terms t on t.id=b.term_id
    join public.classes c on c.id=b.class_id
    where tx.entry_type='payment'
    group by tx.id,tx.receipt_no,tx.credit_amount,tx.payment_method,tx.payment_reference,tx.transaction_date,tx.created_at,tx.student_id,
             s.first_name,s.middle_name,s.last_name,s.admission_no,p.full_name,p.role
  ) q;

  return jsonb_build_object('rows',rows_json);
end
$function$
;

CREATE OR REPLACE FUNCTION public.admin_guardian_account_records()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',sg.id,
        'auth_user_id',linked.auth_user_id,
        'linked_account_count',linked.linked_account_count,
        'portal_email',au.email,
        'full_name',sg.full_name,
        'relationship',sg.relationship,
        'phone',sg.phone,
        'email',sg.email,
        'address',sg.address,
        'is_primary',sg.is_primary,
        'children',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'student_id',s.id,
              'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
              'admission_no',s.admission_no,
              'class_id',ce.class_id,
              'class_name',ce.class_name
            )
            order by lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text
          )
          from public.guardian_links gl2
          join public.students s on s.id=gl2.student_id and s.deleted_at is null and s.status='active'
          left join lateral (
            select e.class_id,c.name::text as class_name
            from public.enrollments e
            join public.classes c on c.id=e.class_id and c.deleted_at is null
            join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
            where e.student_id=s.id and e.deleted_at is null
            order by y.is_active desc,e.active desc,y.start_date desc,e.updated_at desc
            limit 1
          ) ce on true
          where gl2.guardian_id=sg.id
        ),'[]'::jsonb)
      )
      order by lower(sg.full_name),lower(coalesce(sg.phone,'')),sg.id
    )
    from public.student_guardians sg
    left join lateral (
      select
        min(gl.auth_user_id::text)::uuid as auth_user_id,
        count(distinct gl.auth_user_id)::integer as linked_account_count
      from public.guardian_links gl
      where gl.guardian_id=sg.id and gl.auth_user_id is not null
    ) linked on true
    left join auth.users au on au.id=linked.auth_user_id
    where exists (
      select 1
      from public.guardian_links gl3
      join public.students s3 on s3.id=gl3.student_id and s3.deleted_at is null and s3.status='active'
      where gl3.guardian_id=sg.id
    )
  ),'[]'::jsonb);
end
$function$
;

CREATE OR REPLACE FUNCTION public.admin_permanently_delete_test_fee_payment(target_transaction_id uuid, confirmation_receipt text, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  tx public.finance_fee_transactions%rowtype;
  reversal_ids uuid[] := '{}'::uuid[];
  reversal_count integer := 0;
  allocation_count integer := 0;
  recorder_name text := '';
  recorder_role text := '';
  outstanding_after numeric := 0;
begin
  if auth.uid() is null or coalesce(public.current_app_role()::text,'') <> 'system_admin' then
    raise exception 'System Administrator access required' using errcode='42501';
  end if;
  if coalesce(auth.jwt()->>'aal','') <> 'aal2' then
    raise exception 'Multi-factor authentication verification is required for permanent finance deletion' using errcode='42501';
  end if;
  if length(btrim(coalesce(reason_text,''))) < 8 then
    raise exception 'Enter a clear reason for permanently deleting this test payment';
  end if;

  select * into tx
  from public.finance_fee_transactions
  where id=target_transaction_id and entry_type='payment'
  for update;
  if not found then raise exception 'Payment transaction was not found'; end if;
  if btrim(coalesce(confirmation_receipt,'')) <> coalesce(tx.receipt_no,'') then
    raise exception 'Receipt confirmation does not match';
  end if;

  select coalesce(array_agg(id),'{}'::uuid[]),count(*)
  into reversal_ids,reversal_count
  from public.finance_fee_transactions
  where reversal_of_id=tx.id;

  select count(*) into allocation_count
  from public.finance_fee_allocations
  where transaction_id=tx.id or transaction_id=any(reversal_ids);

  select coalesce(nullif(full_name,''),'Unknown user'),coalesce(role::text,'')
  into recorder_name,recorder_role
  from public.profiles
  where id=tx.created_by;

  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,reason)
  values(
    auth.uid(),
    'finance_fee_transactions',
    tx.id,
    'FEE_TEST_PAYMENT_PURGED',
    jsonb_build_object(
      'receipt_no',tx.receipt_no,
      'student_id',tx.student_id,
      'amount',tx.credit_amount,
      'transaction_date',tx.transaction_date,
      'created_at',tx.created_at,
      'payment_method',tx.payment_method,
      'payment_reference',tx.payment_reference,
      'recorded_by',recorder_name,
      'recorded_by_role',recorder_role,
      'linked_reversal_ids',to_jsonb(reversal_ids),
      'linked_reversal_count',reversal_count,
      'allocation_rows_removed',allocation_count
    ),
    btrim(reason_text)
  );

  perform set_config('edusentia.finance_test_purge','on',true);

  delete from public.finance_fee_allocations
  where transaction_id=tx.id or transaction_id=any(reversal_ids);

  delete from public.finance_fee_transactions
  where reversal_of_id=tx.id;

  delete from public.finance_fee_transactions
  where id=tx.id;

  perform set_config('edusentia.finance_test_purge','off',true);

  outstanding_after:=public.finance_student_outstanding(tx.student_id);
  return jsonb_build_object(
    'deleted',true,
    'transaction_id',tx.id,
    'receipt_no',tx.receipt_no,
    'student_id',tx.student_id,
    'amount',tx.credit_amount,
    'reversals_removed',reversal_count,
    'allocations_removed',allocation_count,
    'outstanding_after',outstanding_after
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.admin_remove_accounts_staff_permanently(target_staff_id uuid, reason_text text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  l jsonb;
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  perform public.require_sensitive_access();

  l := public.license_snapshot_for_role('system_admin');
  if coalesce((l->>'write_allowed')::boolean,false) <> true then
    raise exception 'The current licence is read-only' using errcode='42501';
  end if;

  perform 1
  from public.accounts_office_staff
  where id = target_staff_id;

  if not found then
    raise exception 'Accounts Office staff record was not found';
  end if;

  raise exception 'Permanent removal is disabled for Accounts Office Staff. Archive or deactivate the record instead so staff identity and finance audit history remain recoverable.'
    using errcode='42501';
end
$function$
;

CREATE OR REPLACE FUNCTION public.admin_save_accounts_staff(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=public.safe_uuid(payload->>'id');r public.accounts_office_staff%rowtype;staffno text;l jsonb;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  l:=public.license_snapshot_for_role('system_admin');
  if coalesce((l->>'write_allowed')::boolean,false)<>true then raise exception 'The current licence is read-only' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'full_name',''))='' then raise exception 'Full name is required'; end if;
  if rid is null then
    staffno:=public.finance_generate_staff_no();
    insert into public.accounts_office_staff(staff_no,full_name,phone,email,contact_address,job_title,finance_role,active,created_by)
    values(staffno,btrim(payload->>'full_name'),btrim(coalesce(payload->>'phone','')),nullif(btrim(coalesce(payload->>'email','')),''),btrim(coalesce(payload->>'contact_address','')),'Accountant','accountant',coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into r;
    insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'accounts_office_staff',r.id,'ACCOUNTANT_DIRECTORY_CREATE',to_jsonb(r),'Accountant directory record created');
  else
    update public.accounts_office_staff set full_name=btrim(payload->>'full_name'),phone=btrim(coalesce(payload->>'phone','')),email=nullif(btrim(coalesce(payload->>'email','')),''),contact_address=btrim(coalesce(payload->>'contact_address','')),job_title='Accountant',finance_role='accountant',active=coalesce((payload->>'active')::boolean,active),deleted_at=case when coalesce((payload->>'active')::boolean,active) then null else deleted_at end where id=rid returning * into r;
    if r.id is null then raise exception 'Accounts Office staff record was not found'; end if;
    insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'accounts_office_staff',r.id,'ACCOUNTANT_DIRECTORY_UPDATE',to_jsonb(r),'Accountant directory record updated');
  end if;
  return to_jsonb(r);
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_validate_user_bundle(actor_id uuid, bundle jsonb, require_existing_user boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(bundle->>'user_id');staffrecordid uuid:=public.safe_uuid(bundle->>'staff_record_id');role_text text:=btrim(coalesce(bundle->>'role','viewer'));
  item jsonb;classid uuid;subjectid uuid;accesslevel text;scopekey text;seen_scopes text[]:='{}'::text[];has_class_scope boolean:=false;
begin
  if actor_id is null or not exists(select 1 from public.profiles p where p.id=actor_id and p.active and public.current_app_role_for(p.role)='system_admin') then raise exception 'Access denied' using errcode='42501'; end if;
  if require_existing_user and (targetid is null or not exists(select 1 from auth.users u where u.id=targetid)) then raise exception 'Authentication account was not found'; end if;
  if btrim(coalesce(bundle->>'staff_record_id',''))<>'' and staffrecordid is null then raise exception 'Selected directory record is invalid'; end if;
  if btrim(coalesce(bundle->>'full_name',''))='' then raise exception 'Full name is required'; end if;
  if btrim(coalesce(bundle->>'email',''))='' then raise exception 'Email address is required'; end if;
  if bundle->>'email' !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Email address is invalid'; end if;
  if role_text not in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian','accountant','student') then raise exception 'User role is invalid'; end if;
  if role_text in ('class_teacher','subject_teacher') then
    if staffrecordid is null then raise exception 'Select the corresponding teacher record'; end if;
    if not exists(select 1 from public.teachers t where t.id=staffrecordid and t.deleted_at is null and t.active and (t.profile_id is null or t.profile_id=targetid)) then raise exception 'Selected teacher record is unavailable or already linked'; end if;
  elsif role_text='principal' then
    if staffrecordid is null then raise exception 'Select the corresponding Principal record'; end if;
    if not exists(select 1 from public.headteachers h where h.id=staffrecordid and h.deleted_at is null and h.active and (h.profile_id is null or h.profile_id=targetid)) then raise exception 'Selected Principal record is unavailable or already linked'; end if;
  elsif role_text='accountant' then
    if staffrecordid is null then raise exception 'Select the corresponding Accounts Office Staff record'; end if;
    if not exists(select 1 from public.accounts_office_staff a where a.id=staffrecordid and a.deleted_at is null and a.active and (a.profile_id is null or a.profile_id=targetid)) then raise exception 'Selected Accounts Office Staff record is unavailable or already linked'; end if;
  elsif role_text='student' then
    if staffrecordid is null then raise exception 'Select the corresponding Student record'; end if;
    if not exists(select 1 from public.students s where s.id=staffrecordid and s.deleted_at is null and s.status='active' and (s.profile_id is null or s.profile_id=targetid)) then raise exception 'Selected Student record is unavailable or already linked'; end if;
  elsif staffrecordid is not null then raise exception 'The selected role does not use a directory record'; end if;
  if jsonb_typeof(coalesce(bundle->'access','[]'::jsonb))<>'array' then raise exception 'Delegated access must be a list'; end if;
  for item in select value from jsonb_array_elements(coalesce(bundle->'access','[]'::jsonb)) loop
    classid:=public.safe_uuid(item->>'class_id');subjectid:=public.safe_uuid(item->>'subject_id');accesslevel:=coalesce(nullif(btrim(item->>'access_level'),''),'view');
    if classid is null or not exists(select 1 from public.classes c where c.id=classid and c.deleted_at is null and c.active) then raise exception 'A delegated class is invalid or inactive'; end if;
    if subjectid is not null and not exists(select 1 from public.class_subjects cs join public.subjects s on s.id=cs.subject_id where cs.class_id=classid and cs.subject_id=subjectid and cs.active and s.active and s.deleted_at is null) then raise exception 'A delegated subject is not actively assigned to the selected class'; end if;
    if accesslevel not in ('view','edit','score','review') then raise exception 'Delegated access level is invalid'; end if;
    if role_text='subject_teacher' and (subjectid is null or accesslevel not in ('score','edit','review')) then raise exception 'Subject teacher access is invalid'; end if;
    if role_text='class_teacher' and subjectid is null and accesslevel not in ('edit','review') then raise exception 'Class teacher access must permit class report editing'; end if;
    if role_text='class_teacher' and subjectid is null and accesslevel in ('edit','review') then has_class_scope:=true; end if;
    scopekey:=classid::text||'|'||coalesce(subjectid::text,'*');if scopekey=any(seen_scopes) then raise exception 'The same delegated class or subject access was entered more than once'; end if;seen_scopes:=array_append(seen_scopes,scopekey);
  end loop;
  return jsonb_build_object('valid',true,'role',role_text,'staff_record_id',staffrecordid,'access_count',coalesce(jsonb_array_length(bundle->'access'),0));
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_accept_offer(target_offer_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_app uuid;v_exp date;
begin
 perform public.student_services_require_access('admissions','approve');
 select application_id,expires_at into v_app,v_exp from public.admissions_offers where id=target_offer_id and status='offered' for update;
 if v_app is null then raise exception 'Open offer not found'; end if;
 if v_exp is not null and v_exp<current_date then update public.admissions_offers set status='expired' where id=target_offer_id; raise exception 'Offer has expired'; end if;
 update public.admissions_offers set status='accepted',accepted_at=now() where id=target_offer_id;
 update public.admissions_applications set status='accepted',decided_by=auth.uid(),decided_at=now() where id=v_app;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','offer_accepted','admissions_offer',target_offer_id,auth.uid(),jsonb_build_object('application_id',v_app));
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_application_detail(target_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb;
begin
 perform public.student_services_require_access('admissions','read');
 select to_jsonb(q) into a from (select * from public.admissions_applications where id=target_application_id)q;
 if a is null then raise exception 'Application not found'; end if;
 return a||jsonb_build_object(
  'offers',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select o.*,c.name class_name,y.name academic_year from public.admissions_offers o join public.classes c on c.id=o.class_id join public.academic_years y on y.id=o.academic_year_id where o.application_id=target_application_id)q),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from public.admissions_documents d where d.application_id=target_application_id),'[]'::jsonb)
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_application_register(search_text text DEFAULT NULL::text, status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.student_services_require_access('admissions','read');
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q.created_at desc)
    from (
      select
        a.id,
        a.student_id,
        a.application_no,
        concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) applicant,
        a.gender,
        a.date_of_birth,
        a.guardian_name,
        a.guardian_phone,
        a.guardian_email,
        a.status,
        a.source,
        a.created_at,
        c.name class_name,
        y.name academic_year,
        s.status::text student_status,
        s.deleted_at student_deleted_at,
        coalesce(s.id is not null and s.deleted_at is null and s.status <> 'withdrawn'::public.student_status,false) student_link_active,
        (select o.id from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_id,
        (select o.status from public.admissions_offers o where o.application_id=a.id order by o.created_at desc limit 1) latest_offer_status
      from public.admissions_applications a
      left join public.classes c on c.id=a.applying_class_id
      left join public.academic_years y on y.id=a.target_academic_year_id
      left join public.students s on s.id=a.student_id
      where
        ((status_filter is null and a.status <> 'withdrawn') or a.status=status_filter)
        and (
          search_text is null
          or concat_ws(' ',a.application_no,a.first_name,a.middle_name,a.last_name,a.guardian_name,a.guardian_phone,a.guardian_email)
             ilike '%'||search_text||'%'
        )
      order by a.created_at desc
      limit 300
    ) q
  ),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.student_services_require_access('admissions','read');
  return jsonb_build_object(
    'metrics',jsonb_build_object(
      'total',(select count(*) from public.admissions_applications where status <> 'withdrawn'),
      'submitted',(select count(*) from public.admissions_applications where status in ('submitted','under_review')),
      'waitlisted',(select count(*) from public.admissions_applications where status='waitlisted'),
      'offered',(select count(*) from public.admissions_applications where status='offered'),
      'accepted',(select count(*) from public.admissions_applications where status='accepted'),
      'enrolled',(select count(*) from public.admissions_applications where status='enrolled'),
      'not_enrolled',(select count(*) from public.admissions_applications where status='not_enrolled')
    ),
    'recent',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at desc)
      from (
        select
          a.id,
          a.application_no,
          concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) applicant,
          a.status,
          a.created_at,
          c.name class_name,
          y.name academic_year
        from public.admissions_applications a
        left join public.classes c on c.id=a.applying_class_id
        left join public.academic_years y on y.id=a.target_academic_year_id
        where a.status <> 'withdrawn'
        order by a.created_at desc
        limit 15
      ) q
    ),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_decide_application(target_application_id uuid, decision text, offered_academic_year_id uuid DEFAULT NULL::uuid, offered_class_id uuid DEFAULT NULL::uuid, decision_notes text DEFAULT NULL::text, offer_expires_at date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_offer uuid;v_status text;
begin
 perform public.student_services_require_access('admissions','approve');
 if decision not in ('under_review','waitlisted','offered','rejected','withdrawn') then raise exception 'Invalid admissions decision'; end if;
 select status into v_status from public.admissions_applications where id=target_application_id for update;
 if v_status is null or v_status in ('accepted','rejected','withdrawn','enrolled') then raise exception 'Application cannot be decided in its current state'; end if;
 if decision='offered' then
   if offered_academic_year_id is null or offered_class_id is null then raise exception 'Offer requires academic year and class'; end if;
   update public.admissions_offers set status='withdrawn',updated_at=now() where application_id=target_application_id and status='offered';
   insert into public.admissions_offers(application_id,academic_year_id,class_id,status,expires_at,decision_notes,created_by) values(target_application_id,offered_academic_year_id,offered_class_id,'offered',offer_expires_at,decision_notes,auth.uid()) returning id into v_offer;
   update public.admissions_applications set status='offered',target_academic_year_id=offered_academic_year_id,applying_class_id=offered_class_id,decided_by=auth.uid(),decided_at=now() where id=target_application_id;
 else
   update public.admissions_applications set status=decision,reviewed_by=auth.uid(),reviewed_at=now(),decided_by=case when decision in ('rejected','withdrawn') then auth.uid() else decided_by end,decided_at=case when decision in ('rejected','withdrawn') then now() else decided_at end,internal_notes=coalesce(decision_notes,internal_notes) where id=target_application_id;
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','application_decision','admissions_application',target_application_id,auth.uid(),jsonb_build_object('decision',decision,'offer_id',v_offer));
 return v_offer;
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_delete_application(target_application_id uuid, reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_app public.admissions_applications%rowtype;
  v_reason text:=nullif(btrim(reason),'');
  v_active_student boolean:=false;
begin
  perform public.student_services_require_access('admissions','write');

  select * into v_app
  from public.admissions_applications
  where id=target_application_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;
  if v_app.status='enrolled' then
    raise exception 'An enrolled application cannot be deleted';
  end if;
  if v_app.student_id is not null then
    select exists(
      select 1
      from public.students s
      where s.id=v_app.student_id
        and s.deleted_at is null
        and s.status <> 'withdrawn'::public.student_status
    ) into v_active_student;
    if v_active_student then
      raise exception 'An application linked to an active student cannot be deleted';
    end if;
  end if;
  if v_app.status='accepted' then
    raise exception 'An accepted application must be resolved before it can be deleted';
  end if;
  if v_app.status='withdrawn' then
    return;
  end if;

  update public.admissions_offers
  set status='withdrawn',updated_at=now()
  where application_id=target_application_id
    and status in ('offered','accepted');

  update public.admissions_applications
  set
    status='withdrawn',
    decided_by=auth.uid(),
    decided_at=now(),
    internal_notes=case
      when v_reason is null then internal_notes
      when coalesce(internal_notes,'')='' then 'Deleted from applicant register: '||v_reason
      else internal_notes||E'\nDeleted from applicant register: '||v_reason
    end
  where id=target_application_id;

  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values(
    'admissions',
    'application_deleted_from_register',
    'admissions_application',
    target_application_id,
    auth.uid(),
    jsonb_build_object('application_no',v_app.application_no,'previous_status',v_app.status,'reason',v_reason,'historical_student_id',v_app.student_id)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_enroll_application(target_application_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_mark_not_enrolled(target_application_id uuid, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_app public.admissions_applications%rowtype;
  v_reason text:=nullif(btrim(reason),'');
  v_active_student boolean:=false;
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can reopen an enrolled application' using errcode='42501';
  end if;
  perform public.student_services_require_access('admissions','write');
  perform public.require_sensitive_access();

  if v_reason is null or length(v_reason) < 5 then
    raise exception 'A reason of at least 5 characters is required';
  end if;

  select * into v_app
  from public.admissions_applications
  where id=target_application_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;
  if v_app.status='not_enrolled' then
    return jsonb_build_object('updated',false,'application_no',v_app.application_no,'status','not_enrolled');
  end if;
  if v_app.status<>'enrolled' then
    raise exception 'Only an enrolled application can be marked not enrolled';
  end if;

  if v_app.student_id is not null then
    select exists(
      select 1
      from public.students s
      where s.id=v_app.student_id
        and s.deleted_at is null
        and s.status <> 'withdrawn'::public.student_status
    ) into v_active_student;
  end if;

  if v_active_student then
    raise exception 'The linked student is still active. Withdraw or remove the student from Student Directory first.' using errcode='55000';
  end if;

  update public.admissions_applications
  set status='not_enrolled',decided_by=auth.uid(),decided_at=now()
  where id=v_app.id;

  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values(
    'admissions',
    'application_marked_not_enrolled',
    'admissions_application',
    v_app.id,
    auth.uid(),
    jsonb_build_object(
      'application_no',v_app.application_no,
      'student_id',v_app.student_id,
      'previous_status',v_app.status,
      'reason',v_reason
    )
  );

  return jsonb_build_object('updated',true,'application_no',v_app.application_no,'status','not_enrolled');
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_next_application_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare p text; n bigint; c text;
begin
 select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'APP'),'[^0-9A-Za-z]','','g')) into p from public.school_settings limit 1;
 n:=nextval('public.admissions_application_seq');
 c:=p||'-APP-'||lpad(n::text,6,'0');
 return c;
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_next_student_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare p text; n bigint; c text; tries integer:=0;
begin
 select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),nullif(identifier_root,''),'STD'),'[^0-9A-Za-z]','','g')) into p from public.school_settings limit 1;
 loop
   tries:=tries+1; if tries>1000 then raise exception 'Unable to allocate admission number'; end if;
   n:=nextval('public.admissions_student_number_seq'); c:=p||lpad(n::text,8,'0');
   exit when not exists(select 1 from public.students where admission_no=c);
 end loop;
 return c;
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_permanently_remove_application(target_application_id uuid, confirmation_application_no text, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_app public.admissions_applications%rowtype;
  v_reason text:=nullif(btrim(reason),'');
  v_confirmation text:=btrim(coalesce(confirmation_application_no,''));
  v_active_student boolean:=false;
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can permanently remove an applicant' using errcode='42501';
  end if;
  perform public.student_services_require_access('admissions','write');
  perform public.require_sensitive_access();

  select * into v_app
  from public.admissions_applications
  where id=target_application_id
  for update;

  if v_app.id is null then
    raise exception 'Application not found';
  end if;
  if v_app.status='enrolled' then
    raise exception 'An enrolled application cannot be permanently removed';
  end if;
  if v_app.student_id is not null then
    select exists(
      select 1
      from public.students s
      where s.id=v_app.student_id
        and s.deleted_at is null
        and s.status <> 'withdrawn'::public.student_status
    ) into v_active_student;
    if v_active_student then
      raise exception 'An application linked to an active student cannot be permanently removed';
    end if;
  end if;
  if v_app.status='accepted' then
    raise exception 'An accepted application cannot be permanently removed';
  end if;
  if v_confirmation <> v_app.application_no then
    raise exception 'Application number confirmation does not match';
  end if;
  if v_reason is null or length(v_reason) < 5 then
    raise exception 'A permanent removal reason of at least 5 characters is required';
  end if;
  if exists(
    select 1
    from public.admissions_documents
    where application_id=target_application_id
      and nullif(btrim(coalesce(storage_path,'')),'') is not null
  ) then
    raise exception 'Stored admission documents must be removed through the protected document workflow before permanent applicant removal';
  end if;

  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values(
    'admissions',
    'application_permanent_removal',
    'admissions_application',
    target_application_id,
    auth.uid(),
    jsonb_build_object('application_no',v_app.application_no,'previous_status',v_app.status,'reason',v_reason,'historical_student_id',v_app.student_id)
  );

  perform set_config('app.student_services_allow_hard_delete','on',true);

  delete from public.admissions_documents where application_id=target_application_id;
  delete from public.admissions_offers where application_id=target_application_id;
  delete from public.admissions_applications where id=target_application_id;

  return jsonb_build_object(
    'removed',true,
    'application_no',v_app.application_no,
    'previous_status',v_app.status
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_reference_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_save_application(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;v_status text;v_no text;
begin
 perform public.student_services_require_access('admissions','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
   v_no:=public.admissions_next_application_no();
   insert into public.admissions_applications(application_no,first_name,middle_name,last_name,gender,date_of_birth,guardian_name,guardian_phone,guardian_email,address,previous_school,target_academic_year_id,applying_class_id,status,source,applicant_notes,internal_notes,submitted_at,created_by)
   values(v_no,btrim(payload->>'first_name'),nullif(btrim(payload->>'middle_name'),''),btrim(payload->>'last_name'),payload->>'gender',nullif(payload->>'date_of_birth','')::date,btrim(payload->>'guardian_name'),nullif(btrim(payload->>'guardian_phone'),''),nullif(lower(btrim(payload->>'guardian_email')),''),nullif(btrim(payload->>'address'),''),nullif(btrim(payload->>'previous_school'),''),nullif(payload->>'target_academic_year_id','')::uuid,nullif(payload->>'applying_class_id','')::uuid,coalesce(nullif(payload->>'status',''),'draft'),coalesce(nullif(payload->>'source',''),'school_entry'),nullif(payload->>'applicant_notes',''),nullif(payload->>'internal_notes',''),case when coalesce(payload->>'status','draft')='submitted' then now() end,auth.uid()) returning id into v_id;
 else
   select status into v_status from public.admissions_applications where id=v_id for update;
   if v_status in ('accepted','rejected','withdrawn','enrolled') then raise exception 'Finalized application cannot be edited'; end if;
   update public.admissions_applications set first_name=coalesce(nullif(btrim(payload->>'first_name'),''),first_name),middle_name=case when payload ? 'middle_name' then nullif(btrim(payload->>'middle_name'),'') else middle_name end,last_name=coalesce(nullif(btrim(payload->>'last_name'),''),last_name),gender=coalesce(nullif(payload->>'gender',''),gender),date_of_birth=case when payload ? 'date_of_birth' then nullif(payload->>'date_of_birth','')::date else date_of_birth end,guardian_name=coalesce(nullif(btrim(payload->>'guardian_name'),''),guardian_name),guardian_phone=case when payload ? 'guardian_phone' then nullif(btrim(payload->>'guardian_phone'),'') else guardian_phone end,guardian_email=case when payload ? 'guardian_email' then nullif(lower(btrim(payload->>'guardian_email')),'') else guardian_email end,address=case when payload ? 'address' then nullif(btrim(payload->>'address'),'') else address end,previous_school=case when payload ? 'previous_school' then nullif(btrim(payload->>'previous_school'),'') else previous_school end,target_academic_year_id=case when payload ? 'target_academic_year_id' then nullif(payload->>'target_academic_year_id','')::uuid else target_academic_year_id end,applying_class_id=case when payload ? 'applying_class_id' then nullif(payload->>'applying_class_id','')::uuid else applying_class_id end,source=coalesce(nullif(payload->>'source',''),source),applicant_notes=case when payload ? 'applicant_notes' then nullif(payload->>'applicant_notes','') else applicant_notes end,internal_notes=case when payload ? 'internal_notes' then nullif(payload->>'internal_notes','') else internal_notes end where id=v_id;
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','application_saved','admissions_application',v_id,auth.uid(),'{}');
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_save_document(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('admissions','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.admissions_documents(application_id,document_type,document_name,storage_path,verification_status,notes,created_by) values((payload->>'application_id')::uuid,btrim(payload->>'document_type'),btrim(payload->>'document_name'),nullif(payload->>'storage_path',''),coalesce(nullif(payload->>'verification_status',''),'pending'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else update public.admissions_documents set document_type=coalesce(nullif(btrim(payload->>'document_type'),''),document_type),document_name=coalesce(nullif(btrim(payload->>'document_name'),''),document_name),storage_path=case when payload ? 'storage_path' then nullif(payload->>'storage_path','') else storage_path end,verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when payload->>'verification_status'='verified' then auth.uid() else verified_by end,verified_at=case when payload->>'verification_status'='verified' then now() else verified_at end,notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_submit_application(target_application_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('admissions','write');
 update public.admissions_applications set status='submitted',submitted_at=coalesce(submitted_at,now()) where id=target_application_id and status='draft';
 if not found then raise exception 'Only a draft application can be submitted'; end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('admissions','application_submitted','admissions_application',target_application_id,auth.uid(),'{}');
end $function$
;

CREATE OR REPLACE FUNCTION public.admissions_sync_student_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if (new.deleted_at is not null or new.status='withdrawn'::public.student_status)
     and (old.deleted_at is distinct from new.deleted_at or old.status is distinct from new.status) then
    with changed as (
      update public.admissions_applications a
      set status='not_enrolled',decided_by=auth.uid(),decided_at=now()
      where a.student_id=new.id
        and a.status='enrolled'
      returning a.id,a.application_no,a.student_id
    )
    insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
    select
      'admissions',
      'application_not_enrolled_after_student_removal',
      'admissions_application',
      c.id,
      auth.uid(),
      jsonb_build_object(
        'application_no',c.application_no,
        'student_id',c.student_id,
        'student_status',new.status::text,
        'student_deleted_at',new.deleted_at,
        'source','student_directory_sync'
      )
    from changed c;
  elsif new.deleted_at is null
        and new.status='active'::public.student_status
        and (old.deleted_at is not null or old.status='withdrawn'::public.student_status) then
    with changed as (
      update public.admissions_applications a
      set status='enrolled',decided_by=auth.uid(),decided_at=now()
      where a.student_id=new.id
        and a.status='not_enrolled'
      returning a.id,a.application_no,a.student_id
    )
    insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
    select
      'admissions',
      'application_enrolled_after_student_restore',
      'admissions_application',
      c.id,
      auth.uid(),
      jsonb_build_object(
        'application_no',c.application_no,
        'student_id',c.student_id,
        'student_status',new.status::text,
        'source','student_directory_sync'
      )
    from changed c;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.after_score_entry_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.refresh_subject_result(coalesce(new.subject_result_id,old.subject_result_id));
  return coalesce(new,old);
end $function$
;

CREATE OR REPLACE FUNCTION public.allowed_report_transitions(target_report_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  current_status public.report_status;
  result text[] := '{}'::text[];
begin
  select r.status into current_status
  from public.student_reports r
  where r.id=target_report_id and r.deleted_at is null;
  if current_status is null then return result; end if;
  if current_status in ('draft','returned') and public.can_submit_report(target_report_id) then
    result := array_append(result,'submitted');
  end if;
  if current_status in ('submitted','class_reviewed') and public.current_app_role()='principal' then
    result := array_append(result,'approved');
  end if;
  if current_status in ('submitted','class_reviewed','approved','published')
     and public.current_app_role()='principal' then
    result := array_append(result,'returned');
  end if;
  if current_status='approved' and public.can_publish_report(target_report_id) then
    result := array_append(result,'published');
  end if;
  if current_status='published' and public.is_system_admin() then
    result := array_append(result,'withdrawn');
  end if;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_add_engagement(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 insert into public.alumni_engagements(alumni_id,engagement_type,engagement_date,summary,outcome,finance_reference,recorded_by) values((payload->>'alumni_id')::uuid,payload->>'engagement_type',coalesce(nullif(payload->>'engagement_date','')::date,current_date),btrim(payload->>'summary'),nullif(payload->>'outcome',''),nullif(payload->>'finance_reference',''),auth.uid()) returning id into v_id;
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_candidate_register(search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('alumni','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name) from (
  select s.id student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) full_name,s.gender,s.status,
   (select e.academic_year_id from public.enrollments e where e.student_id=s.id order by e.created_at desc limit 1) last_academic_year_id,
   (select e.class_id from public.enrollments e where e.student_id=s.id order by e.created_at desc limit 1) last_class_id
  from public.students s where s.deleted_at is null and s.status='graduated' and not exists(select 1 from public.alumni_records a where a.student_id=s.id)
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
 )q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_create_from_student(target_student_id uuid, graduation_academic_year_id uuid DEFAULT NULL::uuid, final_class_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare s public.students%rowtype;v_year uuid;v_class uuid;v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 select * into s from public.students where id=target_student_id and deleted_at is null for update;
 if s.id is null then raise exception 'Student not found'; end if;
 if exists(select 1 from public.alumni_records where student_id=s.id) then raise exception 'Student already has an alumni record'; end if;
 select coalesce(graduation_academic_year_id,e.academic_year_id),coalesce(final_class_id,e.class_id) into v_year,v_class from public.enrollments e where e.student_id=s.id order by e.created_at desc limit 1;
 if v_year is null then v_year:=graduation_academic_year_id; v_class:=final_class_id; end if;
 insert into public.alumni_records(alumni_code,student_id,former_admission_no,first_name,middle_name,last_name,graduation_academic_year_id,final_class_id,verification_status,created_by)
 values(public.alumni_next_code(),s.id,s.admission_no,s.first_name,nullif(s.middle_name,''),s.last_name,v_year,v_class,'verified',auth.uid()) returning id into v_id;
 update public.alumni_records set verified_by=auth.uid(),verified_at=now() where id=v_id;
 if s.status<>'graduated' then update public.students set status='graduated',updated_at=now() where id=s.id; end if;
 update public.enrollments set active=false,updated_at=now() where student_id=s.id and active;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('alumni','graduate_synced','alumni_record',v_id,auth.uid(),jsonb_build_object('student_id',s.id,'former_admission_no',s.admission_no));
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('alumni','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'alumni',(select count(*) from public.alumni_records where status='active'),
  'verified',(select count(*) from public.alumni_records where verification_status='verified'),
  'contactable',(select count(*) from public.alumni_records where consent_to_contact and status='active'),
  'engagements_90_days',(select count(*) from public.alumni_engagements where engagement_date>=current_date-90),
  'pending_verifications',(select count(*) from public.alumni_verification_requests where status in ('pending','under_review')),
  'graduated_not_synced',(select count(*) from public.students s where s.status='graduated' and s.deleted_at is null and not exists(select 1 from public.alumni_records a where a.student_id=s.id))
 ));
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_my_record()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_student uuid;r jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select id into v_student from public.students where profile_id=auth.uid() and deleted_at is null limit 1;
 if v_student is null then return null; end if;
 select jsonb_build_object('alumni_code',a.alumni_code,'former_admission_no',a.former_admission_no,'name',concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name),'graduation_academic_year_id',a.graduation_academic_year_id,'final_class_id',a.final_class_id,'personal_email',a.personal_email,'phone',a.phone,'location',a.location,'occupation',a.occupation,'employer',a.employer,'further_education',a.further_education,'verification_status',a.verification_status) into r from public.alumni_records a where a.student_id=v_student;
 return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_next_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare p text;n bigint;
begin
 select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'ALU'),'[^0-9A-Za-z]','','g')) into p from public.school_settings limit 1;
 n:=nextval('public.alumni_record_seq'); return p||'-ALU-'||lpad(n::text,7,'0');
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_record_detail(target_alumni_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r jsonb;
begin
 perform public.student_services_require_access('alumni','read');
 select to_jsonb(a) into r from public.alumni_records a where a.id=target_alumni_id;
 if r is null then raise exception 'Alumni record not found'; end if;
 return r||jsonb_build_object(
  'engagements',coalesce((select jsonb_agg(to_jsonb(e) order by e.engagement_date desc,e.created_at desc) from public.alumni_engagements e where e.alumni_id=target_alumni_id),'[]'::jsonb),
  'verification_requests',coalesce((select jsonb_agg(to_jsonb(v) order by v.requested_at desc) from public.alumni_verification_requests v where v.alumni_id=target_alumni_id),'[]'::jsonb)
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_register(search_text text DEFAULT NULL::text, status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('alumni','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.last_name,q.first_name) from (
  select a.id,a.alumni_code,a.student_id,a.former_admission_no,a.first_name,a.middle_name,a.last_name,concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) full_name,a.graduation_academic_year_id,y.name graduation_year,a.final_class_id,c.name final_class,a.personal_email,a.phone,a.location,a.occupation,a.employer,a.consent_to_contact,a.directory_visible,a.verification_status,a.status,a.updated_at
  from public.alumni_records a left join public.academic_years y on y.id=a.graduation_academic_year_id left join public.classes c on c.id=a.final_class_id
  where (status_filter is null or a.status=status_filter) and (search_text is null or concat_ws(' ',a.alumni_code,a.former_admission_no,a.first_name,a.middle_name,a.last_name,a.personal_email,a.phone,a.occupation,a.employer) ilike '%'||search_text||'%')
  order by a.last_name,a.first_name limit 500
 )q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_save_record(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
  insert into public.alumni_records(alumni_code,former_admission_no,first_name,middle_name,last_name,graduation_academic_year_id,final_class_id,personal_email,phone,location,occupation,employer,further_education,consent_to_contact,directory_visible,verification_status,status,notes,created_by)
  values(public.alumni_next_code(),nullif(payload->>'former_admission_no',''),btrim(payload->>'first_name'),nullif(btrim(payload->>'middle_name'),''),btrim(payload->>'last_name'),nullif(payload->>'graduation_academic_year_id','')::uuid,nullif(payload->>'final_class_id','')::uuid,nullif(lower(btrim(payload->>'personal_email')),''),nullif(btrim(payload->>'phone'),''),nullif(payload->>'location',''),nullif(payload->>'occupation',''),nullif(payload->>'employer',''),nullif(payload->>'further_education',''),coalesce((payload->>'consent_to_contact')::boolean,false),coalesce((payload->>'directory_visible')::boolean,false),coalesce(nullif(payload->>'verification_status',''),'unverified'),coalesce(nullif(payload->>'status',''),'active'),nullif(payload->>'notes',''),auth.uid()) returning id into v_id;
 else
  update public.alumni_records set personal_email=case when payload ? 'personal_email' then nullif(lower(btrim(payload->>'personal_email')),'') else personal_email end,phone=case when payload ? 'phone' then nullif(btrim(payload->>'phone'),'') else phone end,location=case when payload ? 'location' then nullif(payload->>'location','') else location end,occupation=case when payload ? 'occupation' then nullif(payload->>'occupation','') else occupation end,employer=case when payload ? 'employer' then nullif(payload->>'employer','') else employer end,further_education=case when payload ? 'further_education' then nullif(payload->>'further_education','') else further_education end,consent_to_contact=coalesce((payload->>'consent_to_contact')::boolean,consent_to_contact),directory_visible=coalesce((payload->>'directory_visible')::boolean,directory_visible),verification_status=coalesce(nullif(payload->>'verification_status',''),verification_status),verified_by=case when payload->>'verification_status'='verified' then auth.uid() else verified_by end,verified_at=case when payload->>'verification_status'='verified' then now() else verified_at end,status=coalesce(nullif(payload->>'status',''),status),notes=case when payload ? 'notes' then nullif(payload->>'notes','') else notes end where id=v_id;
 end if; return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_save_verification_request(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('alumni','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.alumni_verification_requests(alumni_id,request_type,requester_name,requester_email,requester_phone,purpose,status,created_by) values(nullif(payload->>'alumni_id','')::uuid,payload->>'request_type',btrim(payload->>'requester_name'),nullif(payload->>'requester_email',''),nullif(payload->>'requester_phone',''),nullif(payload->>'purpose',''),coalesce(nullif(payload->>'status',''),'pending'),auth.uid()) returning id into v_id;
 else update public.alumni_verification_requests set status=coalesce(nullif(payload->>'status',''),status),outcome_notes=case when payload ? 'outcome_notes' then nullif(payload->>'outcome_notes','') else outcome_notes end,reviewed_by=case when payload->>'status' in ('verified','declined') then auth.uid() else reviewed_by end,reviewed_at=case when payload->>'status' in ('verified','declined') then now() else reviewed_at end where id=v_id;
 end if; return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.alumni_verification_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('alumni','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.requested_at desc) from (select v.*,a.alumni_code,concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) alumni_name from public.alumni_verification_requests v left join public.alumni_records a on a.id=v.alumni_id where status_filter is null or v.status=status_filter)q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.apply_attendance_totals_to_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare opened integer:=0;present integer:=0;
begin
  select c.days_school_opened,c.days_present into opened,present
  from public.attendance_counts_for_enrollment(new.enrollment_id,new.term_id) c;
  if coalesce(opened,0)>0 then
    new.days_school_opened:=opened;
    new.days_present:=least(coalesce(present,0),opened);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.apply_automatic_report_comments()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare suggestions jsonb;
begin
  if new.status<>old.status and new.status in ('submitted','class_reviewed','approved','published') then
    suggestions:=public.performance_comment_suggestions(new.id);
    if btrim(coalesce(new.teacher_comment,''))='' then
      new.teacher_comment:=coalesce(suggestions->>'teacher_comment','');
    end if;
    if new.status in ('approved','published') and btrim(coalesce(new.head_comment,''))='' then
      new.head_comment:=coalesce(suggestions->>'head_comment','');
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.apply_certificate_placeholders(template_text text, context_data jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare result text:=coalesce(template_text,''); item record;
begin
  for item in select key,value from jsonb_each_text(coalesce(context_data,'{}'::jsonb)) loop
    result:=replace(result,'{{'||item.key||'}}',coalesce(item.value,''));
  end loop;
  result:=regexp_replace(result,'[[:space:]]+',' ','g');
  return btrim(result);
end $function$
;

CREATE OR REPLACE FUNCTION public.apply_pending_term3_promotions()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare item record; processed integer:=0;
begin
  for item in
    select r.id
    from public.student_reports r
    join public.terms t on t.id=r.term_id
    where r.deleted_at is null
      and r.status in ('approved','published')
      and public.is_term_three(t.sequence,t.name::text)
      and t.deleted_at is null
  loop
    perform public.refresh_report_promotion(item.id,true);
    processed:=processed+1;
  end loop;
  return processed;
end $function$
;

CREATE OR REPLACE FUNCTION public.apply_promotion_when_report_published()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if new.deleted_at is not null then
    update public.enrollments
    set active=false,deleted_at=now(),updated_at=now(),promotion_applied_at=null
    where promotion_source_report_id=new.id
      and enrollment_origin='automatic_promotion'
      and deleted_at is null;
    return new;
  end if;
  if tg_op='INSERT' or old.status is distinct from new.status or old.deleted_at is distinct from new.deleted_at then
    perform public.refresh_report_promotion(new.id,true);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.archive_academic_entity(entity_type text, target_id uuid, reason_text text DEFAULT 'Academic record archived'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare active_value boolean;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Academic record archived'),true);
  if entity_type in ('academic_year','academic_years') then
    select y.is_active into active_value from public.academic_years y where y.id=target_id and y.deleted_at is null for update;
    if not found then raise exception 'Academic year not found'; end if;
    if active_value then raise exception 'Deactivate this academic year before removing it'; end if;
    if exists(select 1 from public.terms t where t.academic_year_id=target_id and t.deleted_at is null and t.is_active) then raise exception 'Deactivate the academic year term before removing it'; end if;
    if exists(select 1 from public.enrollments e where e.academic_year_id=target_id and e.active and e.deleted_at is null) then raise exception 'This academic year has active student enrolments'; end if;
    if exists(select 1 from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.academic_year_id=target_id and r.deleted_at is null and r.status not in ('published','withdrawn')) then raise exception 'This academic year has unfinished report cards'; end if;
    update public.assessment_schemes set active=false,deleted_at=coalesce(deleted_at,now()),updated_at=now() where academic_year_id=target_id and deleted_at is null;
    update public.grading_scales set deleted_at=coalesce(deleted_at,now()),updated_at=now() where academic_year_id=target_id and deleted_at is null;
    update public.terms set is_active=false,deleted_at=coalesce(deleted_at,now()),updated_at=now() where academic_year_id=target_id and deleted_at is null;
    update public.academic_years set is_active=false,deleted_at=now(),updated_at=now() where id=target_id;
  elsif entity_type in ('term','terms') then
    select t.is_active into active_value from public.terms t where t.id=target_id and t.deleted_at is null for update;
    if not found then raise exception 'Term not found'; end if;
    if active_value then raise exception 'Deactivate this term before removing it'; end if;
    if exists(select 1 from public.student_reports r where r.term_id=target_id and r.deleted_at is null and r.status not in ('published','withdrawn')) then raise exception 'This term has unfinished report cards'; end if;
    update public.assessment_schemes set active=false,deleted_at=coalesce(deleted_at,now()),updated_at=now() where term_id=target_id and deleted_at is null;
    update public.terms set is_active=false,deleted_at=now(),updated_at=now() where id=target_id;
  elsif entity_type='class' then
    if exists(select 1 from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=target_id and e.active and e.deleted_at is null and s.deleted_at is null) then raise exception 'This class has active student enrolments'; end if;
    update public.classes set active=false,deleted_at=now(),updated_at=now() where id=target_id and deleted_at is null;
    if not found then raise exception 'Class not found'; end if;
    update public.class_subjects set active=false,updated_at=now() where class_id=target_id;
  elsif entity_type='subject' then
    if exists(select 1 from public.subject_results sr join public.student_reports r on r.id=sr.report_id where sr.subject_id=target_id and r.deleted_at is null and r.status in ('draft','returned','submitted','class_reviewed','approved')) then raise exception 'This subject is used by an unfinished report card'; end if;
    update public.subjects set active=false,deleted_at=now(),updated_at=now() where id=target_id and deleted_at is null;
    if not found then raise exception 'Subject not found'; end if;
    update public.class_subjects set active=false,updated_at=now() where subject_id=target_id;
  elsif entity_type='assignment' then
    update public.class_subjects set active=false,updated_at=now() where id=target_id;
    if not found then raise exception 'Subject assignment not found'; end if;
  else
    raise exception 'Unsupported academic record type';
  end if;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.archive_grading_scale(target_grade_id uuid, reason_text text DEFAULT 'Grading scale removed'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Grading scale removed'),true);
  update public.grading_scales set deleted_at=now(),updated_at=now() where id=target_grade_id and deleted_at is null;
  if not found then raise exception 'Grading scale not found'; end if;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.archive_headteacher(target_headteacher_id uuid, reason_text text DEFAULT 'Principal archived'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.headteachers where id=target_headteacher_id and deleted_at is null for update) then raise exception 'Principal record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Principal archived'),true);
  update public.headteachers set active=false,
    employment_status=case when employment_status='active' then 'resigned' else employment_status end,
    deleted_at=now(),updated_at=now() where id=target_headteacher_id;
  update public.school_settings
  set head_name=coalesce((
    select concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)
    from public.headteachers h where h.deleted_at is null and h.active and h.employment_status='active'
    order by h.date_appointed desc nulls last,h.created_at desc limit 1
  ),''),
      updated_at=now()
  where id=(select id from public.school_settings order by created_at,id limit 1);
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.archive_report_card(target_report_id uuid, reason_text text DEFAULT 'Report card permanently deleted'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  return public.delete_report_card_permanently(target_report_id,reason_text);
end $function$
;

CREATE OR REPLACE FUNCTION public.archive_school_prospectus(target_prospectus_id uuid, reason_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare row public.school_prospectuses%rowtype;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can archive school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;update public.school_prospectuses set status='archived',updated_by=auth.uid(),updated_at=now() where id=target_prospectus_id returning * into row;if row.id is null then raise exception 'Prospectus not found';end if;return public.build_school_prospectus_snapshot(row.id);end$function$
;

CREATE OR REPLACE FUNCTION public.archive_student(target_student_id uuid, reason_text text DEFAULT 'Student archived'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_records_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  perform 1 from public.students where id=target_student_id and deleted_at is null for update;
  if not found then raise exception 'Student record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Student archived'),true);
  update public.students set status='withdrawn',deleted_at=now(),updated_at=now() where id=target_student_id;
  update public.enrollments set active=false,updated_at=now() where student_id=target_student_id and deleted_at is null;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.archive_teacher(target_teacher_id uuid, reason_text text DEFAULT 'Teacher archived'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare profileid uuid;
begin
  if not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  select profile_id into profileid from public.teachers where id=target_teacher_id and deleted_at is null for update;
  if not found then raise exception 'Teacher record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Teacher archived'),true);
  update public.teachers set active=false,employment_status=case when employment_status='active' then 'resigned' else employment_status end,
    deleted_at=now(),updated_at=now() where id=target_teacher_id;
  if profileid is not null then
    update public.classes set class_teacher_id=null where class_teacher_id=profileid;
    update public.class_subjects set teacher_id=null where teacher_id=profileid;
  end if;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.attendance_counts_for_enrollment(target_enrollment_id uuid, target_term_id uuid)
 RETURNS TABLE(days_school_opened integer, days_present integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select count(r.id)::integer,
    count(a.id) filter(where a.attendance_status in ('present','late'))::integer
  from public.enrollments e
  join public.class_attendance_registers r on r.class_id=e.class_id and r.term_id=target_term_id
  left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=e.id
  where e.id=target_enrollment_id
$function$
;

CREATE OR REPLACE FUNCTION public.audit_backup_export_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare action_name text; reason_text text;
begin
  if tg_op='INSERT' then
    insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
    values(new.initiated_by,'backup_exports',new.id,'BACKUP_STARTED',null,
      jsonb_build_object('status',new.status,'backup_type',new.backup_type,'backup_key',new.backup_key,'encrypted',new.encrypted),
      case when new.initiated_by is null then 'Scheduled encrypted backup started.' else 'System Administrator started an encrypted backup.' end);
    return new;
  end if;
  if new.status is distinct from old.status then
    action_name:=case new.status when 'completed' then 'BACKUP_COMPLETED' when 'failed' then 'BACKUP_FAILED' else 'BACKUP_STATUS_CHANGED' end;
    reason_text:=case new.status when 'completed' then 'Encrypted backup completed.' when 'failed' then 'Encrypted backup failed.' else 'Backup status changed.' end;
    insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
    values(new.initiated_by,'backup_exports',new.id,action_name,
      jsonb_build_object('status',old.status),
      jsonb_build_object('status',new.status,'storage_bytes',new.storage_bytes,'error_message',left(coalesce(new.error_message,''),500)),reason_text);
  end if;
  if new.verification_status is distinct from old.verification_status and new.verification_status in ('passed','failed') then
    insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
    values(new.initiated_by,'backup_exports',new.id,
      case new.verification_status when 'passed' then 'BACKUP_VERIFICATION_PASSED' else 'BACKUP_VERIFICATION_FAILED' end,
      jsonb_build_object('verification_status',old.verification_status),
      jsonb_build_object('verification_status',new.verification_status,'verification_checked_at',new.verification_checked_at,'verification_notes',left(coalesce(new.verification_notes,''),1000)),
      case new.verification_status when 'passed' then 'Encrypted backup integrity verification passed.' else 'Encrypted backup integrity verification failed.' end);
  end if;
  if old.offsite_copied_at is null and new.offsite_copied_at is not null then
    insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
    values(coalesce(auth.uid(),new.initiated_by),'backup_exports',new.id,'BACKUP_OFFSITE_COPY_CONFIRMED',null,
      jsonb_build_object('offsite_copied_at',new.offsite_copied_at,'note',left(coalesce(new.offsite_copy_note,''),500)),
      'System Administrator confirmed a separate protected copy of the encrypted backup package.');
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.audit_row_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_record_id uuid;
  v_old jsonb;
  v_new jsonb;
begin
  if current_setting('app.audit_suppress',true)='on' then return null; end if;
  v_old:=case when tg_op='INSERT' then null else to_jsonb(old) end;
  v_new:=case when tg_op='DELETE' then null else to_jsonb(new) end;
  if tg_table_name='profiles' and tg_op='UPDATE'
     and (v_old-'last_seen_at'-'updated_at')=(v_new-'last_seen_at'-'updated_at') then
    return null;
  end if;
  begin
    v_record_id:=coalesce((v_new->>'id')::uuid,(v_old->>'id')::uuid);
  exception when others then
    v_record_id:=null;
  end;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),tg_table_name,v_record_id,tg_op,v_old,v_new,
    coalesce(current_setting('app.change_reason',true),''));
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.audit_school_restore_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare action_name text; reason_text text;
begin
  if tg_op='INSERT' then
    insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
    values(new.initiated_by,'school_restore_jobs',new.id,'FULL_RESTORE_PREPARED',null,
      jsonb_build_object('status',new.status,'source_filename',new.source_filename,'package_size',new.package_size),
      'System Administrator prepared an encrypted full-school restore package.');
    return new;
  end if;
  if new.status is distinct from old.status and new.status in ('restoring','completed','failed','cancelled') then
    action_name:=case new.status when 'restoring' then 'FULL_RESTORE_STARTED' when 'completed' then 'FULL_RESTORE_COMPLETED' when 'failed' then 'FULL_RESTORE_FAILED' else 'FULL_RESTORE_CANCELLED' end;
    reason_text:=case new.status when 'restoring' then 'Full-school restore entered the protected restore phase.' when 'completed' then 'Full-school restore completed with verification evidence.' when 'failed' then 'Full-school restore failed and retained structured error evidence.' else 'Full-school restore was cancelled before completion.' end;
    insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
    values(new.initiated_by,'school_restore_jobs',new.id,action_name,
      jsonb_build_object('status',old.status),
      jsonb_build_object('status',new.status,'pre_restore_backup_id',new.pre_restore_backup_id,'source_school_name',new.source_school_name,'source_school_code',new.source_school_code,'error_message',left(coalesce(new.error_message,''),1000),'verification_notes',left(coalesce(new.verification_notes,''),1000)),reason_text);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.backup_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare policy_row record;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  select backup_retention_days,backup_minimum_copies into policy_row
  from public.school_settings order by created_at,id limit 1;
  return jsonb_build_object(
    'retention_days',coalesce(policy_row.backup_retention_days,7),
    'minimum_copies',coalesce(policy_row.backup_minimum_copies,2),
    'backups',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc)
      from (select * from public.backup_exports order by created_at desc limit 100) b),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.begin_report_correction(target_report_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_status public.report_status;
begin
  if public.current_app_role()<>'principal' then raise exception 'Only the Principal can return an approved or published report' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  select status into current_status from public.student_reports where id=target_report_id and deleted_at is null for update;
  if current_status not in ('published','approved','class_reviewed','submitted') then raise exception 'A correction cannot be opened from this status'; end if;
  perform set_config('app.report_write','on',true);
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Report returned for correction'),true);
  if current_status='published' then
    update public.report_publications set revoked_at=now(),revoked_by=auth.uid() where report_id=target_report_id and revoked_at is null;
  end if;
  update public.student_reports set status='returned',version=version+1,updated_at=now() where id=target_report_id;
  insert into public.report_workflow_events(report_id,from_status,to_status,comment,actor_id)
  values(target_report_id,current_status,'returned',coalesce(reason_text,''),auth.uid());
  insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
  select id,version,public.build_report_snapshot(id),coalesce(nullif(reason_text,''),'Report returned for correction'),auth.uid() from public.student_reports where id=target_report_id
  on conflict(report_id,version) do nothing;
  perform public.create_workflow_notifications(target_report_id,'returned');
  return public.get_report_editor(target_report_id,null,null);
end $function$
;

CREATE OR REPLACE FUNCTION public.broadcast_application_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'realtime', 'extensions'
AS $function$
declare rowj jsonb; reportid uuid; classid uuid; studentid uuid; recipientid uuid; teacherid uuid; accountid uuid; topics text[]:=array[]::text[]; topic text;
begin
 rowj:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_table_name='notifications' then recipientid:=public.safe_uuid(rowj->>'recipient_id'); topics:=array['user:'||recipientid::text];
 elsif tg_table_name='student_reports' then reportid:=public.safe_uuid(rowj->>'id'); classid:=public.report_class_id(reportid); topics:=array['report:'||reportid::text,'class:'||classid::text,'school:global'];
 elsif tg_table_name in ('subject_results','report_workflow_events','report_revisions','report_publications') then reportid:=public.safe_uuid(rowj->>'report_id'); classid:=public.report_class_id(reportid); topics:=array['report:'||reportid::text,'class:'||classid::text];
 elsif tg_table_name='assessment_score_entries' then select sr.report_id into reportid from public.subject_results sr where sr.id=public.safe_uuid(rowj->>'subject_result_id'); classid:=public.report_class_id(reportid); topics:=array['report:'||reportid::text,'class:'||classid::text];
 elsif tg_table_name='students' then studentid:=public.safe_uuid(rowj->>'id'); topics:=array['student:'||studentid::text,'school:global'];
 elsif tg_table_name='enrollments' then studentid:=public.safe_uuid(rowj->>'student_id'); classid:=public.safe_uuid(rowj->>'class_id'); topics:=array['student:'||studentid::text,'class:'||classid::text,'school:global'];
 elsif tg_table_name='guardian_links' then studentid:=public.safe_uuid(rowj->>'student_id'); recipientid:=public.safe_uuid(rowj->>'auth_user_id'); topics:=array['student:'||studentid::text,'user:'||coalesce(recipientid::text,'')];
 elsif tg_table_name in ('finance_fee_accounts','finance_fee_transactions','finance_hold_overrides') then studentid:=public.safe_uuid(rowj->>'student_id'); topics:=array['student:'||studentid::text,'school:global'];
 elsif tg_table_name='finance_fee_allocations' then accountid:=public.safe_uuid(rowj->>'account_id'); select student_id into studentid from public.finance_fee_accounts where id=accountid; topics:=array['student:'||studentid::text,'school:global'];
 elsif tg_table_name in ('finance_payroll_items') then teacherid:=public.safe_uuid(rowj->>'teacher_id'); select profile_id into recipientid from public.teachers where id=teacherid; topics:=array['user:'||coalesce(recipientid::text,''),'school:global'];
 elsif tg_table_name='finance_payroll_item_lines' then select i.teacher_id into teacherid from public.finance_payroll_items i where i.id=public.safe_uuid(rowj->>'payroll_item_id'); select profile_id into recipientid from public.teachers where id=teacherid; topics:=array['user:'||coalesce(recipientid::text,''),'school:global'];
 else topics:=array['school:global']; end if;
 foreach topic in array topics loop if topic is not null and right(topic,1)<>':' then begin perform realtime.broadcast_changes(topic,tg_op,tg_op,tg_table_name,tg_table_schema,new,old); exception when undefined_function or invalid_schema_name then null; end; end if; end loop;
 return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.build_report_snapshot(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select jsonb_build_object( 'school',(select to_jsonb(s) from public.school_settings s limit 1), 'report',to_jsonb(r), 'student',jsonb_build_object( 'id',st.id,'admission_no',st.admission_no, 'full_name',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name), 'gender',st.gender,'date_of_birth',st.date_of_birth,'photo_url',st.photo_url, 'class_name',c.name,'academic_year',ay.name,'term',t.name,'roll_number',e.roll_number, 'next_term_begins',coalesce(r.next_term_reopening_date,t.next_term_begins), 'next_term_reopening_date',coalesce(r.next_term_reopening_date,t.next_term_begins) ), 'results',coalesce((select jsonb_agg(jsonb_build_object( 'subject_id',sb.id,'subject_code',sb.code,'subject_name',sb.name,'total_score',sr.total_score, 'grade',sr.grade,'remark',sr.remark,'grade_point',sr.grade_point,'teacher_initials',sr.teacher_initials, 'components',coalesce((select jsonb_agg(jsonb_build_object( 'component_id',ac.id,'name',ac.name,'code',ac.code,'maximum_score',ac.maximum_score, 'weight',ac.weight,'raw_score',se.raw_score,'weighted_score',se.weighted_score ) order by ac.display_order,ac.name) from public.assessment_score_entries se join public.assessment_components ac on ac.id=se.component_id where se.subject_result_id=sr.id),'[]'::jsonb) ) order by sb.display_order,sb.name) from public.subject_results sr join public.subjects sb on sb.id=sr.subject_id where sr.report_id=r.id),'[]'::jsonb), 'promotion',public.report_promotion_canonical(r.id), 'summary',jsonb_build_object( 'average',(select round(coalesce(avg(total_score),0),2) from public.subject_results where report_id=r.id), 'aggregate',(select round(coalesce(sum(grade_point),0),2) from public.subject_results where report_id=r.id), 'subjects',(select count(*) from public.subject_results where report_id=r.id) ) ) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id join public.students st on st.id=e.student_id join public.classes c on c.id=e.class_id join public.terms t on t.id=r.term_id join public.academic_years ay on ay.id=t.academic_year_id where r.id=target_report_id $function$
;

CREATE OR REPLACE FUNCTION public.build_school_prospectus_snapshot(target_prospectus_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
select jsonb_build_object(
 'school',(select jsonb_build_object('school_name',s.school_name,'motto',s.motto,'address',s.address,'phone',s.phone,'email',s.email,'website',s.website,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour) from public.school_settings s limit 1),
 'academic_year',jsonb_build_object('id',y.id,'name',y.name),
 'prospectus',jsonb_build_object('id',p.id,'academic_year_id',p.academic_year_id,'class_range',p.class_range,'class_range_label',public.prospectus_class_range_label(p.class_range),'title',p.title,'currency_code',p.currency_code,'status',p.status,'effective_date',p.effective_date,'revision_no',p.revision_no,'general_notes',p.general_notes,'published_at',p.published_at,'created_at',p.created_at,'updated_at',p.updated_at),
 'sections',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'section_type',s.section_type,'title',s.title,'instructions',s.instructions,'display_order',s.display_order,'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'item_name',i.item_name,'description',i.description,'amount',i.amount,'charge_basis',i.charge_basis,'quantity',i.quantity,'unit',i.unit,'calculation_units',i.calculation_units,'include_in_total',i.include_in_total,'required',i.required,'notes',i.notes,'display_order',i.display_order) order by i.display_order,i.item_name,i.id) from public.school_prospectus_items i where i.section_id=s.id),'[]'::jsonb)) order by s.display_order,s.title,s.id) from public.school_prospectus_sections s where s.prospectus_id=p.id),'[]'::jsonb)
) from public.school_prospectuses p join public.academic_years y on y.id=p.academic_year_id where p.id=target_prospectus_id
$function$
;

CREATE OR REPLACE FUNCTION public.build_staff_id_card_snapshot(target_staff_type text, target_staff_id uuid, target_academic_year_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare kind text:=lower(btrim(coalesce(target_staff_type,'')));staff jsonb;y public.academic_years%rowtype;s public.school_settings%rowtype;cfg public.id_card_settings%rowtype;
begin
  if kind='teacher' then select jsonb_build_object('id',t.id,'staff_no',t.staff_no,'emis_code',t.emis_code,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'role','Teacher','qualification',t.qualification,'specialization',t.specialization,'photo_url',t.photo_url) into staff from public.teachers t where t.id=target_staff_id and t.deleted_at is null and t.active;
  elsif kind='principal' then select jsonb_build_object('id',h.id,'staff_no',h.staff_no,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'role','Principal','qualification',h.qualification,'photo_url',h.photo_url) into staff from public.headteachers h where h.id=target_staff_id and h.deleted_at is null and h.active;
  else raise exception 'Unsupported staff type';end if;
  if staff is null then raise exception 'Active staff record not found';end if;select * into y from public.academic_years where id=target_academic_year_id and deleted_at is null;select * into s from public.school_settings limit 1;select * into cfg from public.id_card_settings limit 1;if y.id is null then raise exception 'Academic year not found';end if;if s.id is null or cfg.id is null then raise exception 'School or ID card settings are not configured';end if;
  return jsonb_build_object('schema','rce-staff-id-card/v1','staff_type',kind,'staff',staff,'academic',jsonb_build_object('academic_year_id',y.id,'academic_year_name',y.name),'school',jsonb_build_object('school_name',s.school_name,'motto',s.motto,'address',s.address,'phone',s.phone,'email',s.email,'website',s.website,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour),'principal',public.current_id_card_principal_snapshot(),'card',jsonb_build_object('card_number',target_card_number,'verification_token',target_verification_token,'issue_date',target_issue_date,'expires_on',target_expires_on),'template',to_jsonb(cfg)-'updated_by'-'created_at'-'updated_at');
end$function$
;

CREATE OR REPLACE FUNCTION public.build_student_id_card_snapshot(target_student_id uuid, target_enrollment_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare st public.students%rowtype;e public.enrollments%rowtype;c public.classes%rowtype;y public.academic_years%rowtype;s public.school_settings%rowtype;cfg public.id_card_settings%rowtype;guardian_phone text:='';
begin
  select * into st from public.students where id=target_student_id and deleted_at is null and status='active';if st.id is null then raise exception 'Active student not found';end if;select * into e from public.enrollments where id=target_enrollment_id and student_id=target_student_id and deleted_at is null;if e.id is null then raise exception 'Student enrolment not found';end if;select * into c from public.classes where id=e.class_id;select * into y from public.academic_years where id=e.academic_year_id;select * into s from public.school_settings limit 1;select * into cfg from public.id_card_settings limit 1;if c.id is null or y.id is null then raise exception 'Student enrolment references an unavailable class or academic year';end if;if s.id is null then raise exception 'School settings are not configured';end if;if cfg.id is null then raise exception 'ID card settings are not initialized';end if;
  select coalesce(nullif(g.phone,''),nullif(st.guardian_phone,''),'') into guardian_phone from public.guardian_links gl join public.student_guardians g on g.id=gl.guardian_id where gl.student_id=st.id order by g.is_primary desc,gl.created_at limit 1;if guardian_phone is null then guardian_phone:=coalesce(st.guardian_phone,'');end if;
  return jsonb_build_object('schema','rce-student-id-card/v2','student',jsonb_build_object('id',st.id,'admission_no',st.admission_no,'full_name',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'gender',case when cfg.show_gender then st.gender else null end,'date_of_birth',case when cfg.show_date_of_birth then st.date_of_birth else null end,'photo_url',st.photo_url,'guardian_phone',case when cfg.show_guardian_phone then guardian_phone else '' end),'academic',jsonb_build_object('enrollment_id',e.id,'academic_year_id',y.id,'academic_year_name',y.name,'class_id',c.id,'class_name',c.name),'school',jsonb_build_object('school_name',s.school_name,'motto',s.motto,'address',s.address,'phone',s.phone,'email',s.email,'website',s.website,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour),'principal',public.current_id_card_principal_snapshot(),'card',jsonb_build_object('card_number',target_card_number,'verification_token',target_verification_token,'issue_date',target_issue_date,'expires_on',target_expires_on),'template',to_jsonb(cfg)-'updated_by'-'created_at'-'updated_at');
end$function$
;

CREATE OR REPLACE FUNCTION public.build_student_transcript_snapshot(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  student_json jsonb;
  school_json jsonb;
  principal_json jsonb;
  records_json jsonb;
  lifecycle_json jsonb;
  summary_json jsonb;
  first_record jsonb;
  latest_record jsonb;
  period_count integer:=0;
  subject_count integer:=0;
  cumulative_average numeric:=null;
begin
  if target_student_id is null then
    raise exception 'Student is required' using errcode='22023';
  end if;

  if auth.uid() is not null
     and coalesce(current_setting('request.jwt.claim.role',true),'') not in ('service_role','supabase_admin')
     and not public.can_view_student_history(target_student_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select jsonb_build_object(
    'id',s.id,
    'admission_no',s.admission_no,
    'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
    'gender',s.gender,
    'date_of_birth',s.date_of_birth,
    'date_admitted',coalesce((select min(e.created_at)::date from public.enrollments e where e.student_id=s.id),s.created_at::date),
    'status',s.status,
    'archived',s.deleted_at is not null
  )
  into student_json
  from public.students s
  where s.id=target_student_id;

  if student_json is null then raise exception 'Student not found'; end if;

  select jsonb_build_object(
    'id',ss.id,
    'school_name',ss.school_name,
    'motto',ss.motto,
    'address',ss.address,
    'phone',ss.phone,
    'email',ss.email,
    'website',ss.website,
    'logo_url',ss.logo_url,
    'primary_colour',ss.primary_colour,
    'accent_colour',ss.accent_colour,
    'tenant_code',ss.tenant_code,
    'verification_base_url',ss.verification_base_url,
    'head_name',ss.head_name
  )
  into school_json
  from public.school_settings ss
  order by ss.created_at,ss.id
  limit 1;

  select jsonb_build_object(
    'id',h.id,
    'profile_id',h.profile_id,
    'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
    'title','Principal',
    'signature_path',h.signature_path
  )
  into principal_json
  from public.headteachers h
  where h.active and h.deleted_at is null
  order by h.date_appointed desc nulls last,h.created_at desc,h.id
  limit 1;

  principal_json:=coalesce(principal_json,jsonb_build_object('full_name',coalesce(school_json->>'head_name',''),'title','Principal','signature_path',''));

  with latest_publication_per_term as (
    select distinct on (r.term_id)
      p.id as publication_id,
      p.verification_token as publication_verification_token,
      p.published_at as publication_published_at,
      r.id as report_id,
      r.term_id,
      e.class_id,
      t.academic_year_id,
      rr.id as revision_id,
      rr.version as publication_revision,
      rr.snapshot as published_snapshot
    from public.report_publications p
    join public.student_reports r on r.id=p.report_id
    join public.enrollments e on e.id=r.enrollment_id
    join public.terms t on t.id=r.term_id
    join public.report_revisions rr on rr.id=p.revision_id
    where e.student_id=target_student_id
      and p.revoked_at is null
      and r.deleted_at is null
      and r.status='published'
    order by r.term_id,p.published_at desc,p.id desc
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'report_id',q.report_id,
      'publication_id',q.publication_id,
      'publication_verification_token',q.publication_verification_token,
      'publication_revision',q.publication_revision,
      'report_number',coalesce(q.published_snapshot->'report'->>'report_number',r.report_number::text),
      'status','published',
      'term_id',t.id,
      'term_name',coalesce(q.published_snapshot->'student'->>'term',t.name),
      'term_sequence',t.sequence,
      'term_start_date',t.start_date,
      'term_end_date',t.end_date,
      'academic_year_id',y.id,
      'academic_year_name',coalesce(q.published_snapshot->'student'->>'academic_year',y.name),
      'academic_year_start_date',y.start_date,
      'academic_year_end_date',y.end_date,
      'class_id',c.id,
      'class_name',coalesce(q.published_snapshot->'student'->>'class_name',c.name),
      'days_school_opened',coalesce(nullif(q.published_snapshot->'report'->>'days_school_opened','')::integer,0),
      'days_present',coalesce(nullif(q.published_snapshot->'report'->>'days_present','')::integer,0),
      'teacher_comment',coalesce(q.published_snapshot->'report'->>'teacher_comment',''),
      'head_comment',coalesce(q.published_snapshot->'report'->>'head_comment',''),
      'attitude',coalesce(q.published_snapshot->'report'->>'attitude',''),
      'conduct',coalesce(q.published_snapshot->'report'->>'conduct',''),
      'interest',coalesce(q.published_snapshot->'report'->>'interest',''),
      'average',coalesce(nullif(q.published_snapshot->'summary'->>'average','')::numeric,0),
      'aggregate',coalesce(nullif(q.published_snapshot->'summary'->>'aggregate','')::numeric,0),
      'subjects',coalesce(q.published_snapshot->'results','[]'::jsonb),
      'promotion',coalesce(q.published_snapshot->'promotion','{}'::jsonb),
      'published_at',q.publication_published_at
    )
    order by y.start_date,t.sequence,c.level_order,q.publication_published_at
  ),'[]'::jsonb)
  into records_json
  from latest_publication_per_term q
  join public.student_reports r on r.id=q.report_id
  join public.terms t on t.id=q.term_id
  join public.academic_years y on y.id=q.academic_year_id
  join public.classes c on c.id=q.class_id;

  period_count:=jsonb_array_length(records_json);
  if period_count>0 then
    first_record:=records_json->0;
    latest_record:=records_json->(period_count-1);
    select count(*),round(avg(nullif(subject->>'total_score','')::numeric),2)
      into subject_count,cumulative_average
    from jsonb_array_elements(records_json) record
    cross join lateral jsonb_array_elements(coalesce(record->'subjects','[]'::jsonb)) subject;
  end if;

  summary_json:=jsonb_build_object(
    'academic_period_count',period_count,
    'subject_result_count',coalesce(subject_count,0),
    'cumulative_average',cumulative_average,
    'first_academic_year',coalesce(first_record->>'academic_year_name',''),
    'first_term',coalesce(first_record->>'term_name',''),
    'latest_academic_year',coalesce(latest_record->>'academic_year_name',''),
    'latest_term',coalesce(latest_record->>'term_name',''),
    'latest_class',coalesce(latest_record->>'class_name','')
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',l.id,'event_type',l.event_type,'effective_date',l.effective_date,
    'from_class_name',fc.name,'to_class_name',tc.name,'destination_school',l.destination_school,
    'reason',l.reason,'reference',l.reference,'created_at',l.created_at,'actor_name',p.full_name
  ) order by l.effective_date,l.created_at),'[]'::jsonb)
  into lifecycle_json
  from public.student_lifecycle_events l
  left join public.classes fc on fc.id=l.from_class_id
  left join public.classes tc on tc.id=l.to_class_id
  left join public.profiles p on p.id=l.created_by
  where l.student_id=target_student_id;

  return jsonb_build_object(
    'schema_version','professional-transcript-v1',
    'student',student_json,
    'school',coalesce(school_json,'{}'::jsonb),
    'principal',principal_json,
    'generated_at',now(),
    'source_policy','latest_currently_valid_published_report_per_term',
    'academic_records',records_json,
    'summary',summary_json,
    'lifecycle',lifecycle_json
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.bulk_generate_missing_reports(target_term_id uuid, target_class_id uuid, preview_only boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare yearid uuid; missing_count integer; created_count integer:=0;
begin
  if public.current_app_role() not in ('system_admin','class_teacher') then raise exception 'Access denied' using errcode='42501'; end if;
  if public.current_app_role()='class_teacher' and not public.is_assigned_class_teacher(target_class_id) then raise exception 'Only the assigned class teacher can generate class reports' using errcode='42501'; end if;
  if not public.term_phase_writable(target_term_id,'reports',null) then raise exception 'Report creation is locked for the selected term'; end if;
  select academic_year_id into yearid from public.terms where id=target_term_id and deleted_at is null;
  select count(*) into missing_count from public.enrollments e join public.students s on s.id=e.student_id where e.academic_year_id=yearid and e.class_id=target_class_id and e.active and e.deleted_at is null and s.status='active' and s.deleted_at is null and not exists(select 1 from public.student_reports r where r.enrollment_id=e.id and r.term_id=target_term_id and r.deleted_at is null);
  if not preview_only then
    perform set_config('app.report_write','on',true);
    insert into public.student_reports(enrollment_id,term_id,status,created_by,report_number)
    select e.id,target_term_id,'draft',auth.uid(),null from public.enrollments e join public.students s on s.id=e.student_id
    where e.academic_year_id=yearid and e.class_id=target_class_id and e.active and e.deleted_at is null and s.status='active' and s.deleted_at is null and not exists(select 1 from public.student_reports r where r.enrollment_id=e.id and r.term_id=target_term_id and r.deleted_at is null);
    get diagnostics created_count=row_count;
    update public.student_reports r set report_number=public.generate_report_number(r.id) where r.term_id=target_term_id and r.report_number is null and r.deleted_at is null and exists(select 1 from public.enrollments e where e.id=r.enrollment_id and e.class_id=target_class_id);
  end if;
  return jsonb_build_object('preview',preview_only,'missing_reports',missing_count,'created_reports',created_count,'term_id',target_term_id,'class_id',target_class_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.bulk_import_scores(target_term_id uuid, target_class_id uuid, rows jsonb, filename text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare batchid uuid; rowitem jsonb; rowno integer:=0; ok integer:=0; failed integer:=0;
declare enrollmentid uuid; reportid uuid; subjectid uuid; schemeid uuid; resultid uuid; yearid uuid;
declare componentid uuid; raw numeric; maxscore numeric; current_version integer;
declare before_snapshot jsonb;after_snapshot jsonb;delegation_ids uuid[];delegationid uuid;
begin
  if jsonb_typeof(coalesce(rows,'[]'::jsonb))<>'array' then raise exception 'Score import rows must be a list'; end if;
  select academic_year_id into yearid from public.terms where id=target_term_id and deleted_at is null;
  if yearid is null then raise exception 'Selected term is invalid'; end if;
  if not exists(select 1 from public.classes c where c.id=target_class_id and c.active and c.deleted_at is null) then raise exception 'Selected class is invalid or inactive'; end if;
  if not public.can_create_report_for_class_term(target_class_id,target_term_id) then raise exception 'Access denied' using errcode='42501'; end if;
  insert into public.import_batches(import_type,filename,total_rows,created_by)
  values('scores',filename,jsonb_array_length(rows),auth.uid()) returning id into batchid;
  perform set_config('app.report_write','on',true);
  perform set_config('app.change_reason','Bulk score import',true);
  for rowitem in select value from jsonb_array_elements(rows) loop
    rowno:=rowno+1;
    begin
      if btrim(coalesce(rowitem->>'admission_no',''))='' or btrim(coalesce(rowitem->>'subject_code',''))='' or btrim(coalesce(rowitem->>'component_code',''))='' then
        raise exception 'Admission number, subject code, and component code are required';
      end if;
      select e.id into strict enrollmentid from public.enrollments e join public.students s on s.id=e.student_id
      where e.class_id=target_class_id and e.academic_year_id=yearid and e.deleted_at is null and s.deleted_at is null
        and lower(s.admission_no::text)=lower(btrim(rowitem->>'admission_no'));
      select sb.id into subjectid from public.subjects sb join public.class_subjects cs on cs.subject_id=sb.id and cs.class_id=target_class_id and cs.active
      where lower(sb.code::text)=lower(btrim(rowitem->>'subject_code')) and sb.active and sb.deleted_at is null;
      if subjectid is null then raise exception 'Subject code is not assigned to the selected class'; end if;
      select r.id into reportid from public.student_reports r where r.enrollment_id=enrollmentid and r.term_id=target_term_id and r.deleted_at is null;
      before_snapshot:=case when reportid is null then null else public.build_report_snapshot(reportid) end;
      insert into public.student_reports(enrollment_id,term_id,status,created_by,deleted_at)
      values(enrollmentid,target_term_id,'draft',auth.uid(),null)
      on conflict(enrollment_id,term_id) do update set deleted_at=null
      returning id,version into reportid,current_version;
      if not public.can_score_subject(reportid,subjectid) then raise exception 'Not authorised for subject or report is locked'; end if;
      schemeid:=public.resolve_assessment_scheme(target_class_id,subjectid,yearid,target_term_id);
      if schemeid is null then raise exception 'Assessment scheme not configured'; end if;
      insert into public.subject_results(report_id,subject_id,scheme_id,teacher_initials,created_by)
      values(reportid,subjectid,schemeid,btrim(coalesce(rowitem->>'teacher_initials','')),auth.uid())
      on conflict(report_id,subject_id) do update set scheme_id=excluded.scheme_id,teacher_initials=excluded.teacher_initials,updated_at=now() returning id into resultid;
      select ac.id,ac.maximum_score into componentid,maxscore from public.assessment_components ac
      where ac.scheme_id=schemeid and lower(ac.code::text)=lower(btrim(rowitem->>'component_code'));
      if componentid is null then raise exception 'Assessment component code not found'; end if;
      raw:=public.safe_numeric(rowitem->>'raw_score');
      if raw is null then raise exception 'Raw score is invalid'; end if;
      if raw<0 or raw>maxscore then raise exception 'Raw score is outside the component maximum'; end if;
      insert into public.assessment_score_entries(subject_result_id,component_id,raw_score,created_by)
      values(resultid,componentid,raw,auth.uid())
      on conflict(subject_result_id,component_id) do update set raw_score=excluded.raw_score,updated_at=now();
      perform public.refresh_subject_result(resultid);
      update public.student_reports set report_number=coalesce(report_number,public.generate_report_number(reportid)),version=version+1,updated_at=now()
      where id=reportid returning version into current_version;
      after_snapshot:=public.build_report_snapshot(reportid);
      insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
      values(reportid,current_version,after_snapshot,'Bulk score import',auth.uid())
      on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now();
      if not public.is_official_subject_teacher_for_class(target_class_id,subjectid) then
        delegation_ids:=public.active_emergency_delegation_ids(target_class_id,subjectid,target_term_id,true,false,auth.uid());
        for delegationid in select distinct x from unnest(delegation_ids) x where x is not null loop
          insert into public.emergency_academic_delegation_events(delegation_id,event_type,actor_id,report_id,subject_id,event_reason,event_data)
          values(delegationid,'score_imported',auth.uid(),reportid,subjectid,'Bulk score import under emergency delegation',
            jsonb_build_object('row_number',rowno,'source',filename,'before',before_snapshot,'after',after_snapshot));
        end loop;
      end if;
      ok:=ok+1;
    exception when others then
      failed:=failed+1;
      insert into public.import_errors(batch_id,row_number,payload,error_message) values(batchid,rowno,rowitem,sqlerrm);
    end;
  end loop;
  update public.import_batches set successful_rows=ok,failed_rows=failed,status=case when failed=0 then 'completed' else 'completed_with_errors' end,completed_at=now() where id=batchid;
  return jsonb_build_object('batch_id',batchid,'successful',ok,'failed',failed);
end $function$
;

CREATE OR REPLACE FUNCTION public.bulk_import_students(rows jsonb, filename text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare batchid uuid; rowitem jsonb; rowno integer:=0; ok integer:=0; failed integer:=0;
begin
  if not public.is_records_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  insert into public.import_batches(import_type,filename,total_rows,created_by)
  values('students',filename,jsonb_array_length(coalesce(rows,'[]'::jsonb)),auth.uid()) returning id into batchid;
  for rowitem in select value from jsonb_array_elements(coalesce(rows,'[]'::jsonb))
  loop
    rowno:=rowno+1;
    begin
      perform public.save_student(jsonb_build_object(
        'student',jsonb_build_object(
          'admission_no',rowitem->>'admission_no','first_name',rowitem->>'first_name',
          'middle_name',coalesce(rowitem->>'middle_name',''),'last_name',rowitem->>'last_name',
          'gender',coalesce(rowitem->>'gender','Other'),'date_of_birth',coalesce(rowitem->>'date_of_birth',''),
          'status',coalesce(rowitem->>'status','active'),'photo_url',''
        ),
        'enrollment',jsonb_build_object(
          'academic_year_id',rowitem->>'academic_year_id','class_id',rowitem->>'class_id',
          'roll_number',coalesce(rowitem->>'roll_number',''),'active',true
        ),
        'guardian',jsonb_build_object(
          'full_name',coalesce(rowitem->>'guardian_name',''),'relationship',coalesce(rowitem->>'relationship','Guardian'),
          'phone',coalesce(rowitem->>'guardian_phone',''),'email',coalesce(rowitem->>'guardian_email',''),
          'is_primary',true
        ),
        'reason','Bulk student import'
      ));
      ok:=ok+1;
    exception when others then
      failed:=failed+1;
      insert into public.import_errors(batch_id,row_number,payload,error_message)
      values(batchid,rowno,rowitem,sqlerrm);
    end;
  end loop;
  update public.import_batches set successful_rows=ok,failed_rows=failed,
    status=case when failed=0 then 'completed' else 'completed_with_errors' end,completed_at=now()
  where id=batchid;
  return jsonb_build_object('batch_id',batchid,'successful',ok,'failed',failed);
end $function$
;

CREATE OR REPLACE FUNCTION public.bulk_promote_all_classes(source_academic_year_id uuid, target_academic_year_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  expected_target_year_id uuid;
  resolved_target_year_id uuid;
  target_year_name text;
  class_item record;
  class_result jsonb;
  class_promoted integer:=0;
  class_eligible_pending integer:=0;
  class_not_promoted integer:=0;
  class_incomplete integer:=0;
  class_skipped_status integer:=0;
  class_reports_found integer:=0;
  promoted integer:=0;
  eligible_pending_approval integer:=0;
  not_promoted integer:=0;
  incomplete integer:=0;
  skipped_status integer:=0;
  reports_found integer:=0;
  classes_processed integer:=0;
  classes_with_reports integer:=0;
  classes_skipped integer:=0;
  cutoff integer:=50;
  mappings jsonb:='[]'::jsonb;
begin
  if not public.is_records_manager() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if source_academic_year_id is null then
    raise exception 'Source academic year is required';
  end if;
  if not exists(
    select 1 from public.academic_years y
    where y.id=source_academic_year_id and y.deleted_at is null
  ) then
    raise exception 'Source academic year is unavailable';
  end if;
  expected_target_year_id:=public.next_promotion_academic_year(source_academic_year_id);
  if expected_target_year_id is null then
    raise exception 'No next academic year is configured. Create the next academic year before running promotion.';
  end if;
  if target_academic_year_id is null or target_academic_year_id=source_academic_year_id then
    resolved_target_year_id:=expected_target_year_id;
  elsif target_academic_year_id<>expected_target_year_id then
    raise exception 'Target academic year must be the immediate next configured academic year';
  else
    resolved_target_year_id:=target_academic_year_id;
  end if;
  select y.name::text into target_year_name
  from public.academic_years y
  where y.id=resolved_target_year_id and y.deleted_at is null;
  select coalesce(s.promotion_cutoff_score,50) into cutoff
  from public.school_settings s order by s.created_at,s.id limit 1;
  perform set_config('app.change_reason','Approval-gated Term 3 all-class promotion',true);
  for class_item in
    select
      source_class.id as source_class_id,
      source_class.name as source_class_name,
      next_class.id as target_class_id,
      next_class.name as target_class_name
    from public.classes source_class
    left join lateral(
      select candidate.id,candidate.name
      from public.classes candidate
      where candidate.active
        and candidate.deleted_at is null
        and candidate.level_order>source_class.level_order
      order by candidate.level_order,candidate.name
      limit 1
    ) next_class on true
    where source_class.active
      and source_class.deleted_at is null
    order by source_class.level_order,source_class.name
  loop
    if class_item.target_class_id is null then
      classes_skipped:=classes_skipped+1;
      continue;
    end if;
    class_result:=public.bulk_promote_class(
      source_academic_year_id,
      class_item.source_class_id,
      resolved_target_year_id,
      class_item.target_class_id
    );
    class_promoted:=coalesce((class_result->>'promoted')::integer,0);
    class_eligible_pending:=coalesce((class_result->>'eligible_pending_approval')::integer,0);
    class_not_promoted:=coalesce((class_result->>'not_promoted')::integer,0);
    class_incomplete:=coalesce((class_result->>'incomplete')::integer,0);
    class_skipped_status:=coalesce((class_result->>'skipped_status')::integer,0);
    class_reports_found:=coalesce((class_result->>'reports_found')::integer,0);
    promoted:=promoted+class_promoted;
    eligible_pending_approval:=eligible_pending_approval+class_eligible_pending;
    not_promoted:=not_promoted+class_not_promoted;
    incomplete:=incomplete+class_incomplete;
    skipped_status:=skipped_status+class_skipped_status;
    reports_found:=reports_found+class_reports_found;
    classes_processed:=classes_processed+1;
    if class_reports_found>0 then classes_with_reports:=classes_with_reports+1; end if;
    mappings:=mappings||jsonb_build_array(jsonb_build_object(
      'source_class_id',class_item.source_class_id,
      'source_class_name',class_item.source_class_name,
      'target_class_id',class_item.target_class_id,
      'target_class_name',class_item.target_class_name,
      'reports_found',class_reports_found,
      'promoted',class_promoted,
      'eligible_pending_approval',class_eligible_pending,
      'not_promoted',class_not_promoted,
      'incomplete',class_incomplete,
      'skipped_status',class_skipped_status
    ));
  end loop;
  if classes_processed=0 then raise exception 'No eligible class mapping is configured'; end if;
  return jsonb_build_object(
    'classes_processed',classes_processed,
    'classes_with_reports',classes_with_reports,
    'classes_skipped',classes_skipped,
    'reports_found',reports_found,
    'promoted',promoted,
    'eligible_pending_approval',eligible_pending_approval,
    'not_promoted',not_promoted,
    'incomplete',incomplete,
    'skipped_status',skipped_status,
    'cutoff',cutoff,
    'target_academic_year_id',resolved_target_year_id,
    'target_academic_year_name',target_year_name,
    'mappings',mappings
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.bulk_promote_class(source_academic_year_id uuid, source_class_id uuid, target_academic_year_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  next_class_id uuid;
  expected_target_year_id uuid;
  resolved_target_year_id uuid;
  target_year_name text;
  item record;
  evaluation jsonb;
  promoted integer:=0;
  eligible_pending_approval integer:=0;
  not_promoted integer:=0;
  incomplete integer:=0;
  skipped_status integer:=0;
  cutoff integer:=50;
  reports_found integer:=0;
begin
  if not public.is_records_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if source_academic_year_id is null or source_class_id is null then
    raise exception 'Source academic year and source class are required';
  end if;
  if not exists(
    select 1 from public.academic_years y
    where y.id=source_academic_year_id and y.deleted_at is null
  ) then
    raise exception 'Source academic year is unavailable';
  end if;
  expected_target_year_id:=public.next_promotion_academic_year(source_academic_year_id);
  if expected_target_year_id is null then
    raise exception 'No next academic year is configured. Create the next academic year before running promotion.';
  end if;
  if target_academic_year_id is null or target_academic_year_id=source_academic_year_id then
    resolved_target_year_id:=expected_target_year_id;
  elsif target_academic_year_id<>expected_target_year_id then
    raise exception 'Target academic year must be the immediate next configured academic year';
  else
    resolved_target_year_id:=target_academic_year_id;
  end if;
  select y.name::text into target_year_name
  from public.academic_years y
  where y.id=resolved_target_year_id and y.deleted_at is null;
  select c2.id into next_class_id
  from public.classes c1
  join public.classes c2 on c2.level_order>c1.level_order and c2.active and c2.deleted_at is null
  where c1.id=source_class_id and c1.active and c1.deleted_at is null
  order by c2.level_order,c2.name
  limit 1;
  if next_class_id is null then raise exception 'No next class is configured for the selected source class'; end if;
  if target_class_id is null then target_class_id:=next_class_id; end if;
  if target_class_id<>next_class_id then raise exception 'The target class must be the next class in the configured academic order'; end if;
  select coalesce(s.promotion_cutoff_score,50) into cutoff
  from public.school_settings s order by s.created_at,s.id limit 1;
  select count(*)::integer into skipped_status
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id and e.deleted_at is null
  join public.terms t on t.id=r.term_id and t.deleted_at is null
  where e.academic_year_id=source_academic_year_id
    and e.class_id=source_class_id
    and r.deleted_at is null
    and public.is_term_three(t.sequence,t.name::text)
    and r.status in ('returned','withdrawn');
  perform set_config('app.change_reason','Approval-gated Term 3 performance-based class promotion',true);
  for item in
    select r.id,e.student_id,r.status::text as status
    from public.student_reports r
    join public.enrollments e on e.id=r.enrollment_id and e.deleted_at is null
    join public.terms t on t.id=r.term_id and t.deleted_at is null
    join public.students s on s.id=e.student_id and s.deleted_at is null and s.status='active'
    where e.academic_year_id=source_academic_year_id
      and e.class_id=source_class_id
      and r.deleted_at is null
      and r.status in ('draft','submitted','class_reviewed','approved','published')
      and public.is_term_three(t.sequence,t.name::text)
  loop
    reports_found:=reports_found+1;
    evaluation:=public.refresh_report_promotion(item.id,true);
    if not coalesce((evaluation->>'complete')::boolean,false) then
      incomplete:=incomplete+1;
    elsif not coalesce((evaluation->>'passed')::boolean,false) then
      not_promoted:=not_promoted+1;
    elsif coalesce((evaluation->>'promotion_applied')::boolean,false) then
      promoted:=promoted+1;
    else
      eligible_pending_approval:=eligible_pending_approval+1;
    end if;
  end loop;
  return jsonb_build_object(
    'reports_found',reports_found,
    'promoted',promoted,
    'eligible_pending_approval',eligible_pending_approval,
    'not_promoted',not_promoted,
    'incomplete',incomplete,
    'skipped_status',skipped_status,
    'cutoff',cutoff,
    'target_class_id',target_class_id,
    'target_academic_year_id',resolved_target_year_id,
    'target_academic_year_name',target_year_name
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.bulk_transition_class_reports(target_term_id uuid, target_class_id uuid, target_status report_status, comment_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  source_statuses public.report_status[];
  report_row record;
  class_name_text text;
  term_name_text text;
  target_year_id uuid;
  total_reports integer := 0;
  candidate_reports integer := 0;
  transitioned_reports integer := 0;
  failed_reports integer := 0;
  already_target_status integer := 0;
  other_status_reports integer := 0;
  missing_reports integer := 0;
  transitioned_ids jsonb := '[]'::jsonb;
  failures jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if target_term_id is null or target_class_id is null then raise exception 'A term and class must be selected'; end if;
  select c.name into class_name_text
  from public.classes c
  where c.id=target_class_id and c.active and c.deleted_at is null;
  if class_name_text is null then raise exception 'The selected class is unavailable'; end if;
  select t.name,t.academic_year_id into term_name_text,target_year_id
  from public.terms t
  where t.id=target_term_id and t.deleted_at is null;
  if term_name_text is null then raise exception 'The selected term is unavailable'; end if;
  case target_status
    when 'submitted' then
      if not public.is_assigned_class_teacher(target_class_id) then
        raise exception 'Only the assigned class teacher can submit reports for this class' using errcode='42501';
      end if;
      source_statuses := array['draft','returned']::public.report_status[];
    when 'approved' then
      if public.current_app_role()<>'principal' then
        raise exception 'Only the Principal can approve reports' using errcode='42501';
      end if;
      perform public.require_sensitive_access();
      source_statuses := array['submitted','class_reviewed']::public.report_status[];
    when 'published' then
      if not (public.is_system_admin() or public.is_assigned_class_teacher(target_class_id)) then
        raise exception 'Only the assigned class teacher or System Administrator can publish reports for this class' using errcode='42501';
      end if;
      perform public.require_sensitive_access();
      source_statuses := array['approved']::public.report_status[];
    else
      raise exception 'Bulk workflow supports submit, approve, or publish only';
  end case;
  select count(*) into total_reports
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.term_id=target_term_id
    and e.class_id=target_class_id
    and r.deleted_at is null
    and e.deleted_at is null;
  select count(*) into already_target_status
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.term_id=target_term_id
    and e.class_id=target_class_id
    and r.deleted_at is null
    and e.deleted_at is null
    and r.status=target_status;
  select count(*) into missing_reports
  from public.enrollments e
  join public.students s on s.id=e.student_id and s.deleted_at is null
  where e.academic_year_id=target_year_id
    and e.class_id=target_class_id
    and e.deleted_at is null
    and not exists(
      select 1 from public.student_reports r
      where r.enrollment_id=e.id
        and r.term_id=target_term_id
        and r.deleted_at is null
    );
  for report_row in
    select r.id,r.version,r.report_number,r.status,
      concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name
    from public.student_reports r
    join public.enrollments e on e.id=r.enrollment_id
    join public.students s on s.id=e.student_id
    where r.term_id=target_term_id
      and e.class_id=target_class_id
      and r.deleted_at is null
      and e.deleted_at is null
      and r.status=any(source_statuses)
    order by lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text
  loop
    candidate_reports := candidate_reports+1;
    begin
      perform public.transition_report_status(
        report_row.id,
        target_status,
        coalesce(nullif(btrim(comment_text),''),'Bulk class workflow transition'),
        report_row.version
      );
      transitioned_reports := transitioned_reports+1;
      transitioned_ids := transitioned_ids || jsonb_build_array(report_row.id);
    exception when others then
      failed_reports := failed_reports+1;
      failures := failures || jsonb_build_array(jsonb_build_object(
        'report_id',report_row.id,
        'report_number',report_row.report_number,
        'student_name',report_row.student_name,
        'from_status',report_row.status,
        'error',sqlerrm
      ));
    end;
  end loop;
  other_status_reports := greatest(total_reports-candidate_reports-already_target_status,0);
  return jsonb_build_object(
    'class_id',target_class_id,
    'class_name',class_name_text,
    'term_id',target_term_id,
    'term_name',term_name_text,
    'target_status',target_status,
    'total_reports',total_reports,
    'candidate_reports',candidate_reports,
    'transitioned_reports',transitioned_reports,
    'failed_reports',failed_reports,
    'already_target_status',already_target_status,
    'other_status_reports',other_status_reports,
    'missing_reports',missing_reports,
    'transitioned_report_ids',transitioned_ids,
    'failures',failures
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.can_access_class(target_class_id uuid, require_write boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when public.current_app_role() in ('system_admin','principal') then not require_write
    when public.current_app_role() in ('class_teacher','subject_teacher') then
      public.is_official_class_teacher_for_class(target_class_id)
      or exists(
        select 1 from public.class_subjects cs
        join public.classes c on c.id=cs.class_id
        join public.subjects s on s.id=cs.subject_id
        where cs.class_id=target_class_id and cs.teacher_id=auth.uid() and cs.active
          and c.active and c.deleted_at is null and s.active and s.deleted_at is null
      )
      or (
        not require_write and exists(
          select 1 from public.emergency_academic_delegations d
          where d.delegate_user_id=auth.uid() and d.class_id=target_class_id
            and d.status='active' and now()>=d.valid_from and now()<d.valid_until
        )
      )
    else false
  end
$function$
;

CREATE OR REPLACE FUNCTION public.can_create_report_for_class(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_manage_class_report_fields(target_class_id)
    or exists(
      select 1 from public.class_subjects cs
      where cs.class_id=target_class_id and cs.active
        and public.can_score_class_subject(target_class_id,cs.subject_id)
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_create_report_for_class_term(target_class_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_manage_class_report_fields_for_term(target_class_id,target_term_id)
    or exists(
      select 1 from public.class_subjects cs
      where cs.class_id=target_class_id and cs.active
        and public.can_score_class_subject_for_term(target_class_id,cs.subject_id,target_term_id)
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_create_report_scope(target_class_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_manage_class_report_fields_scope(target_class_id,target_term_id)
    or exists(select 1 from public.class_subjects cs where cs.class_id=target_class_id and cs.active and public.can_score_class_subject_scope(target_class_id,cs.subject_id,target_term_id))
$function$
;

CREATE OR REPLACE FUNCTION public.can_delete_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1
    from public.student_reports r
    where r.id=target_report_id
      and r.deleted_at is null
      and r.status in ('draft','returned')
      and r.approved_at is null
      and r.published_at is null
      and not exists(select 1 from public.report_publications rp where rp.report_id=r.id)
      and (
        public.is_academic_manager()
        or public.is_assigned_class_teacher(public.report_class_id(r.id))
      )
  )
$function$
;

CREATE OR REPLACE FUNCTION public.can_delete_report_pdf_object(target_report_id uuid, target_storage_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_manage_report_pdf(target_report_id)
    and not exists(
      select 1 from public.report_publications p
      where p.report_id=target_report_id
        and p.revoked_at is null
        and p.storage_path=target_storage_path
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_edit_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
    where r.id=target_report_id and r.deleted_at is null and r.status in ('draft','returned','withdrawn')
      and (public.can_create_report_for_class_term(e.class_id,r.term_id)
        or (public.has_approved_report_correction(r.id) and public.can_create_report_scope(e.class_id,r.term_id)))
  )
$function$
;

CREATE OR REPLACE FUNCTION public.can_enter_tertiary_course_result(p_course_registration_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.license_write_allowed()
    and (
      public.has_role(array['system_admin','principal'])
      or (
        public.has_role(array['class_teacher','subject_teacher'])
        and exists(
          select 1
          from public.tertiary_course_registrations cr
          join public.tertiary_course_offerings o on o.id=cr.course_offering_id
          where cr.id=p_course_registration_id
            and o.lecturer_profile_id=auth.uid()
            and cr.status in ('registered','completed')
            and o.status in ('open','closed','completed')
        )
      )
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_academic_model()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select auth.uid() is not null
    and public.license_write_allowed()
    and public.has_role(array['system_admin','principal'])
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_certificates()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.license_write_allowed() and public.is_system_admin() $function$
;

CREATE OR REPLACE FUNCTION public.can_manage_class_report_fields(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_official_class_teacher_for_class(target_class_id)
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_class_report_fields_for_term(target_class_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.term_phase_writable(target_term_id,'reports',null) and public.can_manage_class_report_fields_scope(target_class_id,target_term_id)
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_class_report_fields_scope(target_class_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_official_class_teacher_for_class(target_class_id,auth.uid())
    or public.has_active_emergency_delegation(target_class_id,null,target_term_id,false,true,auth.uid())
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_headteachers()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_system_admin() and public.current_aal()='aal2'
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_report_pdf(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.student_reports r
    where r.id=target_report_id and r.status='published' and r.deleted_at is null
  )
  and public.can_publish_report(target_report_id)
  and exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.active
      and (
        (not coalesce(p.mfa_required,false) and public.current_app_role()::text<>'system_admin')
        or public.current_aal()='aal2'
      )
  )
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_staff_photo(target_staff_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select auth.uid() is not null and public.license_write_allowed() and (
   public.current_app_role()='system_admin'
   or exists(select 1 from public.teachers t where t.id=target_staff_id and t.profile_id=auth.uid() and t.deleted_at is null)
   or exists(select 1 from public.headteachers h where h.id=target_staff_id and h.profile_id=auth.uid() and h.deleted_at is null)
 )
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_student(target_student_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_records_manager()
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_teachers()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_system_admin() and public.current_aal()='aal2'
$function$
;

CREATE OR REPLACE FUNCTION public.can_modify_certificate_template_object(target_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_manage_certificates()
    and coalesce(btrim(target_path),'')<>''
    and not exists(
      select 1 from public.certificate_templates t where t.storage_path=target_path
    )
    and not exists(
      select 1 from public.certificates c
      where c.snapshot->'template'->>'storage_path'=target_path
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_publish_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_system_admin()
    or public.is_assigned_class_teacher(public.report_class_id(target_report_id))
$function$
;

CREATE OR REPLACE FUNCTION public.can_read_principal_signature()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select auth.uid() is not null
    and public.license_read_allowed()
    and coalesce(public.current_app_role()::text,'') in (
      'system_admin',
      'principal',
      'academic_admin',
      'class_teacher',
      'subject_teacher',
      'records_officer',
      'viewer',
      'parent_guardian'
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_read_student_academic_record(p_student_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select auth.uid() is not null
    and public.license_read_allowed()
    and (
      public.has_role(array['system_admin','principal','class_teacher','subject_teacher'])
      or exists(select 1 from public.students s where s.id=p_student_id and s.profile_id=auth.uid())
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_read_tertiary_student_record(p_student_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select auth.uid() is not null
    and public.license_read_allowed()
    and (
      public.has_role(array['system_admin','principal'])
      or exists(select 1 from public.students s where s.id=p_student_id and s.profile_id=auth.uid())
      or (
        public.has_role(array['class_teacher','subject_teacher'])
        and exists(
          select 1
          from public.tertiary_course_registrations cr
          join public.tertiary_course_offerings o on o.id=cr.course_offering_id
          where cr.student_id=p_student_id
            and o.lecturer_profile_id=auth.uid()
            and cr.status in ('registered','completed')
        )
      )
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_remove_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.student_reports r
    where r.id=target_report_id and r.deleted_at is null and (
      public.is_academic_manager()
      or (
        public.has_role(array['class_teacher'])
        and r.status in ('draft','returned')
        and public.can_access_class(public.report_class_id(r.id),true)
      )
    )
  )
$function$
;

CREATE OR REPLACE FUNCTION public.can_review_certificates()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.license_write_allowed() and public.has_role(array['principal']) $function$
;

CREATE OR REPLACE FUNCTION public.can_score_class_subject(target_class_id uuid, target_subject_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_official_subject_teacher_for_class(target_class_id,target_subject_id)
$function$
;

CREATE OR REPLACE FUNCTION public.can_score_class_subject_for_term(target_class_id uuid, target_subject_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.term_phase_writable(target_term_id,'scores',null) and public.can_score_class_subject_scope(target_class_id,target_subject_id,target_term_id)
$function$
;

CREATE OR REPLACE FUNCTION public.can_score_class_subject_scope(target_class_id uuid, target_subject_id uuid, target_term_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_official_subject_teacher_for_class(target_class_id,target_subject_id,auth.uid())
    or public.is_official_class_teacher_for_class(target_class_id,auth.uid())
    or public.has_active_emergency_delegation(target_class_id,target_subject_id,target_term_id,true,false,auth.uid())
$function$
;

CREATE OR REPLACE FUNCTION public.can_score_subject(target_report_id uuid, target_subject_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1
    from public.student_reports r
    join public.enrollments e on e.id=r.enrollment_id
    where r.id=target_report_id and r.deleted_at is null
      and r.status in ('draft','returned','withdrawn')
      and public.can_score_class_subject_for_term(e.class_id,target_subject_id,r.term_id)
  )
$function$
;

CREATE OR REPLACE FUNCTION public.can_submit_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_assigned_class_teacher(public.report_class_id(target_report_id))
    and exists(
      select 1 from public.student_reports r
      where r.id=target_report_id
        and r.deleted_at is null
        and r.status in ('draft','returned')
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_class_timetable(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select public.current_app_role() in ('system_admin','principal') or (public.current_app_role() in ('class_teacher','subject_teacher') and public.can_access_class(target_class_id,false))
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role() in ('system_admin','principal')
    or public.can_access_class(public.report_class_id(target_report_id),false)
    or exists(select 1 from public.student_reports r join public.enrollments e on e.id=r.enrollment_id join public.guardian_links gl on gl.student_id=e.student_id where r.id=target_report_id and r.status='published' and r.deleted_at is null and gl.auth_user_id=auth.uid() and gl.can_view_reports and not coalesce((public.finance_student_hold_status(e.student_id)->>'block_grade_details')::boolean,false))
    or exists(select 1 from public.student_reports r join public.enrollments e on e.id=r.enrollment_id join public.students s on s.id=e.student_id where r.id=target_report_id and r.status='published' and r.deleted_at is null and s.profile_id=auth.uid() and not coalesce((public.finance_student_hold_status(e.student_id)->>'block_grade_details')::boolean,false))
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_report_internal(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select auth.uid() is not null
    and public.current_app_role()::text in ('system_admin','principal','class_teacher','subject_teacher')
    and public.can_view_report(target_report_id)
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_report_pdf(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_view_report(target_report_id)
    and (
      public.current_app_role()::text in ('system_admin','principal','class_teacher','subject_teacher')
      or not coalesce((public.finance_student_hold_status(public.report_student_id(target_report_id))->>'block_report_pdf')::boolean,false)
    )
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_staff_photo(target_staff_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select auth.uid() is not null and (
   public.current_app_role() in ('system_admin','principal')
   or exists(select 1 from public.teachers t where t.id=target_staff_id and t.profile_id=auth.uid() and t.deleted_at is null)
   or exists(select 1 from public.headteachers h where h.id=target_staff_id and h.profile_id=auth.uid() and h.deleted_at is null)
 )
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_student(target_student_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when public.current_app_role() in ('system_admin','principal') then true
    when public.current_app_role() in ('class_teacher','subject_teacher') then exists(
      select 1
      from public.enrollments e
      join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
      where e.id=(
        select current_e.id
        from public.enrollments current_e
        join public.academic_years current_y on current_y.id=current_e.academic_year_id and current_y.deleted_at is null
        where current_e.student_id=target_student_id
          and current_e.deleted_at is null
        order by current_e.active desc,
          coalesce(current_y.start_date,current_y.end_date,current_e.created_at::date) desc,
          current_y.name::text desc,
          current_e.created_at desc
        limit 1
      )
      and public.can_access_class(e.class_id,false)
    )
    else false
  end
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_student_history(target_student_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role() in ('system_admin','principal')
    or public.can_view_student(target_student_id)
    or exists(select 1 from public.guardian_links g where g.student_id=target_student_id and g.auth_user_id=auth.uid() and g.can_view_reports)
$function$
;

CREATE OR REPLACE FUNCTION public.canonical_school_email_domain()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
  select lower(public.canonical_school_identity_prefix()) || '.app'
$function$
;

CREATE OR REPLACE FUNCTION public.canonical_school_identity_prefix()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  prefix_value text;
begin
  select regexp_replace(upper(coalesce(nullif(l.tenant_code,''),'')),'[^A-Z0-9]','','g')
  into prefix_value
  from public.school_licenses l
  order by l.updated_at desc,l.id
  limit 1;

  if coalesce(prefix_value,'')='' then
    select regexp_replace(upper(coalesce(nullif(s.report_number_prefix,''),'SCH')),'[^A-Z0-9]','','g')
    into prefix_value
    from public.school_settings s
    order by s.created_at,s.id
    limit 1;
  end if;

  return left(coalesce(nullif(prefix_value,''),'SCH'),16);
end
$function$
;

CREATE OR REPLACE FUNCTION public.certificate_type_code(target_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ select case target_type when 'student_promotion' then 'PROM' when 'jhs_completion' then 'COMP' when 'teacher_recognition' then 'STAFF' else 'CERT' end $function$
;

CREATE OR REPLACE FUNCTION public.certificate_type_label(target_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ select case target_type when 'student_promotion' then 'Student Promotion' when 'jhs_completion' then 'JHS 3 Completion' when 'teacher_recognition' then 'Teacher Recognition' else 'Certificate' end $function$
;

CREATE OR REPLACE FUNCTION public.claim_notification_jobs(target_batch_size integer DEFAULT 50, target_worker_id text DEFAULT NULL::text)
 RETURNS SETOF notification_outbox
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare worker text:=coalesce(nullif(btrim(target_worker_id),''),gen_random_uuid()::text);
begin
  if current_user not in ('postgres','service_role','supabase_admin')
     and coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return query
  with candidates as (
    select o.id
    from public.notification_outbox o
    where o.processed_at is null
      and o.attempts<6
      and o.next_attempt_at<=now()
      and (o.locked_at is null or o.locked_at<now()-interval '15 minutes')
    order by o.created_at
    for update skip locked
    limit least(greatest(coalesce(target_batch_size,50),1),200)
  )
  update public.notification_outbox o
  set locked_at=now(),locked_by=worker
  from candidates c
  where o.id=c.id
  returning o.*;
end $function$
;

CREATE OR REPLACE FUNCTION public.clear_section_history(scope_text text, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare v_scope text:=lower(btrim(coalesce(scope_text,'')));v_reason text:=btrim(coalesce(reason_text,''));v_deleted integer:=0;v_secondary_deleted integer:=0;v_skipped integer:=0;v_preserved integer:=0;v_result jsonb;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can permanently clear section history' using errcode='42501';end if;if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required to permanently clear history' using errcode='42501';end if;if upper(btrim(coalesce(confirmation_text,'')))<>'CLEAR HISTORY' then raise exception 'Type CLEAR HISTORY exactly to confirm permanent history removal' using errcode='22023';end if;if length(v_reason)<5 then raise exception 'A reset reason of at least five characters is required' using errcode='22023';end if;case v_scope when 'report_corrections' then select count(*) into v_secondary_deleted from public.report_correction_events e where exists(select 1 from public.report_correction_requests r where r.id=e.request_id and r.status in ('rejected','cancelled','applied'));delete from public.report_correction_requests where status in ('rejected','cancelled','applied');get diagnostics v_deleted=row_count;select count(*) into v_preserved from public.report_correction_requests where status in ('pending','approved');v_result:=jsonb_build_object('scope',v_scope,'requests_deleted',v_deleted,'events_deleted',v_secondary_deleted,'active_requests_preserved',v_preserved);when 'recovery_rehearsals' then delete from public.recovery_test_runs where status in ('passed','failed','cancelled');get diagnostics v_deleted=row_count;select count(*) into v_preserved from public.recovery_test_runs where status not in ('passed','failed','cancelled');v_result:=jsonb_build_object('scope',v_scope,'rehearsals_deleted',v_deleted,'active_rehearsals_preserved',v_preserved);when 'backup_restore' then delete from public.school_restore_jobs where status in ('completed','failed','cancelled');get diagnostics v_deleted=row_count;select count(*) into v_skipped from public.backup_exports b where b.status='failed' and not(coalesce(b.storage_bytes,0)=0 and coalesce(b.storage_path,'')='' and coalesce(b.manifest_path,'')='' and coalesce(b.database_path,'')='' and not exists(select 1 from public.backup_storage_objects o where o.backup_export_id=b.id) and not exists(select 1 from public.recovery_test_runs rr where rr.backup_export_id=b.id and rr.status='processing') and not exists(select 1 from public.school_restore_jobs sj where sj.pre_restore_backup_id=b.id and sj.status not in ('completed','failed','cancelled')));delete from public.backup_exports b where b.status='failed' and coalesce(b.storage_bytes,0)=0 and coalesce(b.storage_path,'')='' and coalesce(b.manifest_path,'')='' and coalesce(b.database_path,'')='' and not exists(select 1 from public.backup_storage_objects o where o.backup_export_id=b.id) and not exists(select 1 from public.recovery_test_runs rr where rr.backup_export_id=b.id and rr.status='processing') and not exists(select 1 from public.school_restore_jobs sj where sj.pre_restore_backup_id=b.id and sj.status not in ('completed','failed','cancelled'));get diagnostics v_secondary_deleted=row_count;select count(*) into v_preserved from public.backup_exports where status<>'failed';v_result:=jsonb_build_object('scope',v_scope,'restore_jobs_deleted',v_deleted,'safe_failed_backup_rows_deleted',v_secondary_deleted,'failed_backup_rows_skipped_for_payload_safety',v_skipped,'completed_or_active_backup_assets_preserved',v_preserved);else raise exception 'Unsupported history scope: %',coalesce(scope_text,'') using errcode='22023';end case;if to_regclass('public.system_maintenance_log') is not null then insert into public.system_maintenance_log(actor_id,operation,affected_rows,details,created_at) values(auth.uid(),'HISTORY_RESET',greatest(v_deleted,0)+greatest(v_secondary_deleted,0),jsonb_build_object('release','r30','scope',v_scope,'reason',v_reason,'result',v_result,'operational_data_deleted',false,'successful_backup_assets_deleted',false),now());end if;return v_result||jsonb_build_object('cleared_at',now(),'reason',v_reason);end$function$
;

CREATE OR REPLACE FUNCTION public.communications_campaign_options()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('communications','read');
 return jsonb_build_object(
  'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.active and c.deleted_at is null),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'template_name',t.template_name,'subject_template',t.subject_template,'body_template',t.body_template,'category',t.category) order by t.template_name) from public.communication_templates t where t.active),'[]'::jsonb)
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_campaign_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('communications','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
  select c.id,c.title,c.category,c.audience_type,c.audience_class_id,cl.name class_name,c.channels,c.status,c.scheduled_at,c.published_at,c.created_at,
   (select count(*) from public.communication_deliveries d where d.campaign_id=c.id) delivery_count,
   (select count(*) from public.communication_deliveries d where d.campaign_id=c.id and d.status='failed') failed_count
  from public.communication_campaigns c left join public.classes cl on cl.id=c.audience_class_id
  where status_filter is null or c.status=status_filter
 )q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_create_thread(subject_text text, participant_profile_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;p uuid;
begin
 perform public.student_services_require_access('communications','write');
 if participant_profile_ids is null or cardinality(participant_profile_ids)=0 then raise exception 'Select at least one participant'; end if;
 insert into public.communication_threads(subject,created_by) values(btrim(subject_text),auth.uid()) returning id into v_id;
 insert into public.communication_thread_participants(thread_id,profile_id,participant_role) values(v_id,auth.uid(),'owner') on conflict do nothing;
 foreach p in array participant_profile_ids loop insert into public.communication_thread_participants(thread_id,profile_id,participant_role) select v_id,p,'member' where exists(select 1 from public.profiles x where x.id=p and x.active) on conflict do nothing; end loop;
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('communications','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'draft_campaigns',(select count(*) from public.communication_campaigns where status='draft'),
  'scheduled_campaigns',(select count(*) from public.communication_campaigns where status='scheduled'),
  'published_30_days',(select count(*) from public.communication_campaigns where status='published' and published_at>=now()-interval '30 days'),
  'queued_deliveries',(select count(*) from public.communication_deliveries where status='queued'),
  'failed_deliveries',(select count(*) from public.communication_deliveries where status='failed'),
  'open_threads',(select count(*) from public.communication_threads where status='open')
 ));
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_delivery_register(target_campaign_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('communications','read');
 return coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from public.communication_deliveries d where d.campaign_id=target_campaign_id),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_my_threads()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from (
  select t.id,t.subject,t.status,t.updated_at,(select count(*) from public.communication_messages m where m.thread_id=t.id) message_count,
   (select m.body from public.communication_messages m where m.thread_id=t.id order by m.created_at desc limit 1) last_message
  from public.communication_threads t join public.communication_thread_participants p on p.thread_id=t.id where p.profile_id=auth.uid()
 )q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_publish_campaign(target_campaign_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare c public.communication_campaigns%rowtype;ch text;r record;v_delivery uuid;v_outbox uuid;v_count integer:=0;
begin
 perform public.student_services_require_access('communications','publish');
 select * into c from public.communication_campaigns where id=target_campaign_id for update;
 if c.id is null or c.status not in ('draft','scheduled') then raise exception 'Campaign is not publishable'; end if;
 delete from public.communication_deliveries where campaign_id=c.id and status='queued';
 for r in
  with targets as (
   select distinct p.id profile_id,null::uuid student_id,p.full_name recipient_name,null::text recipient_email,p.phone recipient_phone
   from public.profiles p where c.audience_type='selected_profiles' and p.id=any(c.audience_profile_ids) and p.active
   union all
   select distinct h.profile_id,null::uuid,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),h.email,h.phone from public.hr_staff_members h where c.audience_type='all_staff' and h.active and h.deleted_at is null and h.profile_id is not null
   union all
   select distinct s.profile_id,s.id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),nullif(s.guardian_email,''),nullif(s.guardian_phone,'') from public.students s where c.audience_type='all_students' and s.deleted_at is null and s.status='active' and s.profile_id is not null
   union all
   select distinct g.auth_user_id,s.id,coalesce(p.full_name,s.guardian_name),nullif(s.guardian_email,''),coalesce(nullif(p.phone,''),nullif(s.guardian_phone,'')) from public.guardian_links g join public.students s on s.id=g.student_id left join public.profiles p on p.id=g.auth_user_id where c.audience_type='all_guardians' and g.auth_user_id is not null and g.can_receive_notifications
   union all
   select distinct s.profile_id,s.id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),nullif(s.guardian_email,''),nullif(s.guardian_phone,'') from public.enrollments e join public.students s on s.id=e.student_id where c.audience_type='class_students' and e.class_id=c.audience_class_id and e.active and e.deleted_at is null and s.profile_id is not null
   union all
   select distinct g.auth_user_id,s.id,coalesce(p.full_name,s.guardian_name),nullif(s.guardian_email,''),coalesce(nullif(p.phone,''),nullif(s.guardian_phone,'')) from public.enrollments e join public.students s on s.id=e.student_id join public.guardian_links g on g.student_id=s.id left join public.profiles p on p.id=g.auth_user_id where c.audience_type='class_guardians' and e.class_id=c.audience_class_id and e.active and e.deleted_at is null and g.auth_user_id is not null and g.can_receive_notifications
  ) select * from targets
 loop
  foreach ch in array c.channels loop
   if ch='in_app' and r.profile_id is not null then
    insert into public.notifications(recipient_id,title,body,category,entity_type,entity_id) values(r.profile_id,c.title,c.body,c.category,'communication_campaign',c.id);
    insert into public.communication_deliveries(campaign_id,recipient_profile_id,student_id,recipient_name,recipient_email,recipient_phone,channel,status,sent_at) values(c.id,r.profile_id,r.student_id,r.recipient_name,r.recipient_email,r.recipient_phone,ch,'sent',now()) returning id into v_delivery;
    v_count:=v_count+1;
   elsif ch in ('email','sms','push') then
    if (ch='email' and coalesce(r.recipient_email,'')='') or (ch='sms' and coalesce(r.recipient_phone,'')='') or (ch='push' and r.profile_id is null) then
      insert into public.communication_deliveries(campaign_id,recipient_profile_id,student_id,recipient_name,recipient_email,recipient_phone,channel,status,error_message) values(c.id,r.profile_id,r.student_id,r.recipient_name,r.recipient_email,r.recipient_phone,ch,'skipped','Recipient channel unavailable');
    else
      insert into public.notification_outbox(recipient_id,recipient_email,channel,template_key,payload) values(r.profile_id,case when ch='email' then r.recipient_email else null end,ch,'student_services_campaign',jsonb_build_object('title',c.title,'body',c.body,'category',c.category,'campaign_id',c.id,'recipient_phone',r.recipient_phone)) returning id into v_outbox;
      insert into public.communication_deliveries(campaign_id,recipient_profile_id,student_id,recipient_name,recipient_email,recipient_phone,channel,status,outbox_id) values(c.id,r.profile_id,r.student_id,r.recipient_name,r.recipient_email,r.recipient_phone,ch,'queued',v_outbox);
      v_count:=v_count+1;
    end if;
   end if;
  end loop;
 end loop;
 update public.communication_campaigns set status='published',published_at=now() where id=c.id;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('communications','campaign_published','communication_campaign',c.id,auth.uid(),jsonb_build_object('queued_or_sent',v_count));
 return jsonb_build_object('campaign_id',c.id,'queued_or_sent',v_count);
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_save_campaign(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;v_channels text[];v_profiles uuid[];
begin
 perform public.student_services_require_access('communications','write');
 v_id:=nullif(payload->>'id','')::uuid;
 select coalesce(array_agg(value),array['in_app']::text[]) into v_channels from jsonb_array_elements_text(coalesce(payload->'channels','["in_app"]'::jsonb));
 select coalesce(array_agg(value::uuid),array[]::uuid[]) into v_profiles from jsonb_array_elements_text(coalesce(payload->'audience_profile_ids','[]'::jsonb));
 if v_id is null then insert into public.communication_campaigns(title,body,category,audience_type,audience_class_id,audience_profile_ids,channels,status,scheduled_at,created_by) values(btrim(payload->>'title'),btrim(payload->>'body'),coalesce(nullif(payload->>'category',''),'general'),payload->>'audience_type',nullif(payload->>'audience_class_id','')::uuid,v_profiles,v_channels,coalesce(nullif(payload->>'status',''),'draft'),nullif(payload->>'scheduled_at','')::timestamptz,auth.uid()) returning id into v_id;
 else update public.communication_campaigns set title=coalesce(nullif(btrim(payload->>'title'),''),title),body=coalesce(nullif(btrim(payload->>'body'),''),body),category=coalesce(nullif(payload->>'category',''),category),audience_type=coalesce(nullif(payload->>'audience_type',''),audience_type),audience_class_id=case when payload ? 'audience_class_id' then nullif(payload->>'audience_class_id','')::uuid else audience_class_id end,audience_profile_ids=case when payload ? 'audience_profile_ids' then v_profiles else audience_profile_ids end,channels=case when payload ? 'channels' then v_channels else channels end,scheduled_at=case when payload ? 'scheduled_at' then nullif(payload->>'scheduled_at','')::timestamptz else scheduled_at end where id=v_id and status in ('draft','scheduled');
 end if; return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_save_template(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('communications','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.communication_templates(template_name,subject_template,body_template,category,active,created_by) values(btrim(payload->>'template_name'),nullif(payload->>'subject_template',''),btrim(payload->>'body_template'),coalesce(nullif(payload->>'category',''),'general'),coalesce((payload->>'active')::boolean,true),auth.uid()) returning id into v_id;
 else update public.communication_templates set template_name=coalesce(nullif(btrim(payload->>'template_name'),''),template_name),subject_template=case when payload ? 'subject_template' then nullif(payload->>'subject_template','') else subject_template end,body_template=coalesce(nullif(btrim(payload->>'body_template'),''),body_template),category=coalesce(nullif(payload->>'category',''),category),active=coalesce((payload->>'active')::boolean,active) where id=v_id;
 end if; return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_send_message(target_thread_id uuid, message_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.communication_thread_participants p join public.communication_threads t on t.id=p.thread_id where p.thread_id=target_thread_id and p.profile_id=auth.uid() and t.status='open') then raise exception 'Thread access denied' using errcode='42501'; end if;
 insert into public.communication_messages(thread_id,sender_profile_id,body) values(target_thread_id,auth.uid(),btrim(message_body)) returning id into v_id;
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.communications_thread_messages(target_thread_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 if auth.uid() is null or not exists(select 1 from public.communication_thread_participants where thread_id=target_thread_id and profile_id=auth.uid()) then raise exception 'Thread access denied' using errcode='42501'; end if;
 update public.communication_thread_participants set last_read_at=now() where thread_id=target_thread_id and profile_id=auth.uid();
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at) from (select m.id,m.thread_id,m.sender_profile_id,p.full_name sender_name,m.body,m.created_at,m.edited_at from public.communication_messages m left join public.profiles p on p.id=m.sender_profile_id where m.thread_id=target_thread_id)q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.complete_notification_job(target_job_id uuid, target_worker_id text, target_success boolean, target_error text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare changed integer;
begin
  if current_user not in ('postgres','service_role','supabase_admin')
     and coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if target_success then
    update public.notification_outbox
    set processed_at=now(),attempts=attempts+1,last_error='',locked_at=null,locked_by=null
    where id=target_job_id and processed_at is null and locked_by=target_worker_id;
  else
    update public.notification_outbox
    set attempts=attempts+1,
        next_attempt_at=now()+(power(2,least(attempts+1,8))::text||' minutes')::interval,
        last_error=left(coalesce(target_error,''),2000),locked_at=null,locked_by=null
    where id=target_job_id and processed_at is null and locked_by=target_worker_id;
  end if;
  get diagnostics changed=row_count;
  return changed=1;
end $function$
;

CREATE OR REPLACE FUNCTION public.complete_required_password_change()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare previous_value boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select must_change_password into previous_value from public.profiles where id=auth.uid() for update;
  if not found then raise exception 'Active profile not found' using errcode='42501'; end if;
  update public.profiles
  set must_change_password=false,updated_at=now()
  where id=auth.uid();
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'profiles',auth.uid(),'PASSWORD_CHANGE_COMPLETED',
    jsonb_build_object('must_change_password',coalesce(previous_value,false)),
    jsonb_build_object('must_change_password',false),
    'Required password change completed');
  return jsonb_build_object('completed',true);
end $function$
;

CREATE OR REPLACE FUNCTION public.control_plane_health_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_release text := '';
  v_schema text := '';
  v_active_students bigint := 0;
  v_latest_backup timestamptz;
  v_latest_verified timestamptz;
  v_failed_backups bigint := 0;
  v_unverified_backups bigint := 0;
  v_client_errors bigint := 0;
  v_pending_notifications bigint := 0;
  v_published_without_pdf bigint := 0;
  v_active_period_errors bigint := 0;
  v_orphan_enrollments bigint := 0;
  v_orphan_reports bigint := 0;
  v_orphan_results bigint := 0;
  v_orphan_score_entries bigint := 0;
  v_invalid_indexes bigint := 0;
  v_license_status text := '';
  v_license_expires timestamptz;
  v_license_grace timestamptz;
  v_ready boolean := false;
  v_backup_fresh boolean := false;
  v_verification_fresh boolean := false;
begin
  -- Authorization is enforced by explicit EXECUTE grants. Modern sb_secret_ keys
  -- map to service-level database privileges without a legacy JWT role claim.
  select release_version into v_release from public.system_release_state where singleton=true;
  select coalesce(max(version),'') into v_schema from supabase_migrations.schema_migrations;
  select count(*) into v_active_students from public.students where deleted_at is null and status='active';
  select max(coalesce(completed_at,created_at)) into v_latest_backup from public.backup_exports where status='completed' and backup_type='full';
  select max(verification_checked_at) into v_latest_verified from public.backup_exports where verification_status='passed';
  select count(*) into v_failed_backups
  from public.backup_exports
  where status='failed'
    and created_at>=now()-interval '30 days'
    and created_at > coalesce(
      (select max(created_at) from public.backup_exports where status='completed' and backup_type='full' and verification_status='passed'),
      '-infinity'::timestamptz
    );
  select count(*) into v_unverified_backups from public.backup_exports where status='completed' and verification_status<>'passed';
  select count(*) into v_client_errors from public.client_error_events where created_at>=now()-interval '24 hours';
  select count(*) into v_pending_notifications from public.notification_outbox where processed_at is null;
  select count(*) into v_published_without_pdf from public.report_publications where revoked_at is null and storage_path='';
  select
    (select greatest(count(*)-1,0) from public.academic_years where is_active and deleted_at is null)
    +(select greatest(count(*)-1,0) from public.terms where is_active and deleted_at is null)
    +(select count(*) from public.terms t left join public.academic_years y on y.id=t.academic_year_id where t.is_active and t.deleted_at is null and (y.id is null or not y.is_active or y.deleted_at is not null))
  into v_active_period_errors;
  select count(*) into v_orphan_enrollments from public.enrollments e left join public.students s on s.id=e.student_id left join public.classes c on c.id=e.class_id left join public.academic_years y on y.id=e.academic_year_id where s.id is null or c.id is null or y.id is null;
  select count(*) into v_orphan_reports from public.student_reports r left join public.enrollments e on e.id=r.enrollment_id left join public.students s on s.id=e.student_id where e.id is null or s.id is null;
  select count(*) into v_orphan_results from public.subject_results sr left join public.student_reports r on r.id=sr.report_id left join public.subjects s on s.id=sr.subject_id where r.id is null or s.id is null;
  select count(*) into v_orphan_score_entries from public.assessment_score_entries se left join public.subject_results sr on sr.id=se.subject_result_id where sr.id is null;
  select count(*) into v_invalid_indexes from pg_index where not indisvalid;
  select status,expires_at,grace_ends_at into v_license_status,v_license_expires,v_license_grace from public.school_licenses order by created_at desc limit 1;
  v_backup_fresh := v_latest_backup is not null and v_latest_backup >= now()-interval '36 hours';
  v_verification_fresh := v_latest_verified is not null and v_latest_verified >= now()-interval '8 days';
  v_ready := coalesce(v_release,'')<>'' and coalesce(v_schema,'')<>'' and v_backup_fresh and v_verification_fresh and v_failed_backups=0 and v_active_period_errors=0 and v_orphan_enrollments=0 and v_orphan_reports=0 and v_orphan_results=0 and v_orphan_score_entries=0 and v_invalid_indexes=0 and coalesce(v_license_status,'') in ('active','grace_period');
  return jsonb_build_object(
    'ready',v_ready,'release_version',v_release,'schema_migration_version',v_schema,'checked_at',now(),'active_students',v_active_students,
    'backup',jsonb_build_object('latest_full',v_latest_backup,'latest_verified',v_latest_verified,'backup_fresh',v_backup_fresh,'verification_fresh',v_verification_fresh,'failed_30d',v_failed_backups,'completed_unverified',v_unverified_backups),
    'operations',jsonb_build_object('client_errors_24h',v_client_errors,'pending_notifications',v_pending_notifications,'published_without_pdf',v_published_without_pdf),
    'integrity',jsonb_build_object('active_period_errors',v_active_period_errors,'orphan_enrollments',v_orphan_enrollments,'orphan_reports',v_orphan_reports,'orphan_subject_results',v_orphan_results,'orphan_score_entries',v_orphan_score_entries,'invalid_indexes',v_invalid_indexes),
    'license',jsonb_build_object('status',v_license_status,'expires_at',v_license_expires,'grace_ends_at',v_license_grace)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.copy_school_prospectus(target_source_id uuid, target_academic_year_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare source public.school_prospectuses%rowtype;new_id uuid;sec record;new_sec uuid;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can copy school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select * into source from public.school_prospectuses where id=target_source_id;if source.id is null then raise exception 'Source prospectus not found';end if;if not exists(select 1 from public.academic_years where id=target_academic_year_id and deleted_at is null) then raise exception 'Target academic year not found';end if;if exists(select 1 from public.school_prospectuses where academic_year_id=target_academic_year_id and class_range=source.class_range) then raise exception 'A prospectus already exists for this class range in the target academic year';end if;insert into public.school_prospectuses(academic_year_id,class_range,title,currency_code,status,effective_date,revision_no,general_notes,created_by,updated_by) values(target_academic_year_id,source.class_range,source.title,source.currency_code,'draft',null,0,source.general_notes,auth.uid(),auth.uid()) returning id into new_id;for sec in select * from public.school_prospectus_sections where prospectus_id=source.id order by display_order,id loop insert into public.school_prospectus_sections(prospectus_id,section_type,title,instructions,display_order,created_by,updated_by) values(new_id,sec.section_type,sec.title,sec.instructions,sec.display_order,auth.uid(),auth.uid()) returning id into new_sec;insert into public.school_prospectus_items(section_id,item_name,description,amount,charge_basis,quantity,unit,calculation_units,include_in_total,required,notes,display_order,created_by,updated_by) select new_sec,item_name,description,amount,charge_basis,quantity,unit,calculation_units,include_in_total,required,notes,display_order,auth.uid(),auth.uid() from public.school_prospectus_items where section_id=sec.id order by display_order,id;end loop;return public.build_school_prospectus_snapshot(new_id);end$function$
;

CREATE OR REPLACE FUNCTION public.create_certificate_batch(payload jsonb, recipient_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_certificate_type text:=btrim(coalesce(payload->>'certificate_type',''));
  v_academic_year_id uuid:=public.safe_uuid(payload->>'academic_year_id');
  v_term_id uuid:=public.safe_uuid(payload->>'term_id');
  v_class_id uuid:=public.safe_uuid(payload->>'class_id');
  v_category_id uuid:=public.safe_uuid(payload->>'award_category_id');
  v_template public.certificate_templates;
  v_batch_id uuid;
  v_recipient_id uuid;
  v_context jsonb;
  v_recipient record;
  v_school_name text;
  v_year_name text;
  v_category_name text:='';
  v_citation text:=btrim(coalesce(payload->>'custom_citation',''));
  v_inserted_count integer:=0;
begin
  if not public.can_manage_certificates() then
    raise exception 'Only the System Administrator can prepare certificates' using errcode='42501';
  end if;
  if v_certificate_type not in ('student_promotion','jhs_completion','teacher_recognition') or v_academic_year_id is null then
    raise exception 'Certificate type and academic year are required';
  end if;
  if coalesce(array_length(recipient_ids,1),0)=0 then
    raise exception 'Select at least one eligible certificate recipient';
  end if;
  if length(v_citation)>350 then
    raise exception 'The personalised teacher citation is too long';
  end if;
  if v_certificate_type='student_promotion' then
    if v_term_id is null or v_class_id is null then
      raise exception 'Term and class are required for promotion certificates';
    end if;
    if not exists(
      select 1 from public.terms t
      where t.id=v_term_id and t.academic_year_id=v_academic_year_id and t.sequence=3 and t.deleted_at is null
    ) then
      raise exception 'Promotion certificates require Term 3 in the selected academic year';
    end if;
  elsif v_certificate_type='jhs_completion' then
    if v_class_id is null then raise exception 'Completion class is required'; end if;
    if v_term_id is not null and not exists(
      select 1 from public.terms t
      where t.id=v_term_id and t.academic_year_id=v_academic_year_id and t.deleted_at is null
    ) then
      raise exception 'The selected completion term does not belong to the academic year';
    end if;
    if exists(select 1 from public.school_settings s where s.certificate_completion_class_id is not null)
       and not exists(select 1 from public.school_settings s where s.certificate_completion_class_id=v_class_id) then
      raise exception 'Select the configured JHS 3 completion class';
    end if;
    if not exists(select 1 from public.school_settings s where s.certificate_completion_class_id is not null)
       and not exists(
         select 1 from public.classes c
         where c.id=v_class_id and lower(c.name::text) ~ '(basic[[:space:]]*9|jhs[[:space:]]*3|junior[[:space:]]+high.*3)'
       ) then
      raise exception 'The selected class is not configured as JHS 3';
    end if;
  end if;
  select ct.* into v_template
  from public.certificate_templates ct
  where ct.certificate_type=v_certificate_type and ct.active
  order by ct.updated_at desc
  limit 1;
  if v_template.id is null then raise exception 'An active certificate template is required'; end if;
  select s.school_name into v_school_name from public.school_settings s order by s.created_at limit 1;
  select ay.name::text into v_year_name
  from public.academic_years ay
  where ay.id=v_academic_year_id and ay.deleted_at is null;
  if v_year_name is null then raise exception 'Academic year not found'; end if;
  if v_certificate_type='teacher_recognition' then
    select a.name,a.default_citation into v_category_name,v_citation
    from public.teacher_award_categories a
    where a.id=v_category_id and a.active;
    if v_category_name is null then raise exception 'Select an active teacher award category'; end if;
    if btrim(coalesce(payload->>'custom_citation',''))<>'' then
      v_citation:=btrim(payload->>'custom_citation');
    end if;
  end if;
  insert into public.certificate_batches(
    certificate_type,academic_year_id,term_id,class_id,teacher_award_category_id,template_id,title,custom_citation,notes
  ) values(
    v_certificate_type,v_academic_year_id,v_term_id,v_class_id,v_category_id,v_template.id,v_template.title,v_citation,btrim(coalesce(payload->>'notes',''))
  ) returning id into v_batch_id;
  foreach v_recipient_id in array recipient_ids loop
    if v_certificate_type='student_promotion' then
      select
        st.id as student_id,
        concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name) as recipient_name,
        st.admission_no::text as identifier,
        c.name::text as current_class_name,
        pc.name::text as destination_class_name,
        r.id as report_id
      into v_recipient
      from public.student_reports r
      join public.enrollments e on e.id=r.enrollment_id
      join public.students st on st.id=e.student_id
      join public.classes c on c.id=e.class_id
      join public.classes pc on pc.id=r.promoted_to_class_id
      join public.terms tr on tr.id=r.term_id
      where st.id=v_recipient_id
        and r.term_id=v_term_id
        and e.academic_year_id=v_academic_year_id
        and e.class_id=v_class_id
        and tr.sequence=3
        and r.status='published'
        and r.deleted_at is null
        and e.deleted_at is null
        and st.deleted_at is null
      limit 1;
      if v_recipient.student_id is null then raise exception 'A selected student is not eligible for a promotion certificate'; end if;
      if exists(
        select 1
        from public.certificates x
        join public.certificate_batches cb on cb.id=x.batch_id
        where x.student_id=v_recipient_id
          and cb.academic_year_id=v_academic_year_id
          and cb.certificate_type=v_certificate_type
          and x.status in ('draft','approved','issued')
      ) then
        raise exception 'A promotion certificate already exists for %',v_recipient.recipient_name;
      end if;
      v_context:=jsonb_build_object(
        'recipient_name',v_recipient.recipient_name,'current_class',v_recipient.current_class_name,
        'next_class',v_recipient.destination_class_name,'academic_year',v_year_name,
        'school_name',v_school_name,'award_category','','custom_citation',''
      );
      insert into public.certificates(
        batch_id,recipient_kind,student_id,source_report_id,recipient_name,recipient_identifier,current_class_name,
        destination_class_name,academic_year_name,certificate_title,statement_text,snapshot
      ) values(
        v_batch_id,'student',v_recipient.student_id,v_recipient.report_id,v_recipient.recipient_name,v_recipient.identifier,
        v_recipient.current_class_name,v_recipient.destination_class_name,v_year_name,v_template.title,
        public.apply_certificate_placeholders(v_template.statement_template,v_context),
        jsonb_build_object('eligibility','published_term3_promotion','context',v_context,'template',to_jsonb(v_template))
      );
    elsif v_certificate_type='jhs_completion' then
      select
        st.id as student_id,
        concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name) as recipient_name,
        st.admission_no::text as identifier,
        c.name::text as current_class_name,
        sr.id as report_id
      into v_recipient
      from public.enrollments e
      join public.students st on st.id=e.student_id
      join public.classes c on c.id=e.class_id
      left join lateral(
        select r.id
        from public.student_reports r
        where r.enrollment_id=e.id
          and r.status='published'
          and r.deleted_at is null
          and (v_term_id is null or r.term_id=v_term_id)
        order by r.published_at desc nulls last
        limit 1
      ) sr on true
      where st.id=v_recipient_id
        and e.academic_year_id=v_academic_year_id
        and e.class_id=v_class_id
        and e.deleted_at is null
        and st.deleted_at is null
        and sr.id is not null
      limit 1;
      if v_recipient.student_id is null then raise exception 'A selected student is not eligible for a JHS completion certificate'; end if;
      if exists(
        select 1
        from public.certificates x
        join public.certificate_batches cb on cb.id=x.batch_id
        where x.student_id=v_recipient_id
          and cb.academic_year_id=v_academic_year_id
          and cb.certificate_type=v_certificate_type
          and x.status in ('draft','approved','issued')
      ) then
        raise exception 'A completion certificate already exists for %',v_recipient.recipient_name;
      end if;
      v_context:=jsonb_build_object(
        'recipient_name',v_recipient.recipient_name,'current_class',v_recipient.current_class_name,
        'next_class','','academic_year',v_year_name,'school_name',v_school_name,
        'award_category','','custom_citation',''
      );
      insert into public.certificates(
        batch_id,recipient_kind,student_id,source_report_id,recipient_name,recipient_identifier,current_class_name,
        academic_year_name,certificate_title,statement_text,snapshot
      ) values(
        v_batch_id,'student',v_recipient.student_id,v_recipient.report_id,v_recipient.recipient_name,v_recipient.identifier,
        v_recipient.current_class_name,v_year_name,v_template.title,
        public.apply_certificate_placeholders(v_template.statement_template,v_context),
        jsonb_build_object('eligibility','published_jhs_completion_record','context',v_context,'template',to_jsonb(v_template))
      );
    else
      select
        t.id as teacher_id,
        concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name) as recipient_name,
        t.staff_no::text as identifier
      into v_recipient
      from public.teachers t
      where t.id=v_recipient_id and t.deleted_at is null and t.employment_status<>'suspended';
      if v_recipient.teacher_id is null then raise exception 'A selected teacher is not eligible for recognition'; end if;
      v_context:=jsonb_build_object(
        'recipient_name',v_recipient.recipient_name,'current_class','','next_class','',
        'academic_year',v_year_name,'school_name',v_school_name,
        'award_category',v_category_name,'custom_citation',v_citation
      );
      insert into public.certificates(
        batch_id,recipient_kind,teacher_id,recipient_name,recipient_identifier,academic_year_name,
        certificate_title,award_category_name,statement_text,snapshot
      ) values(
        v_batch_id,'teacher',v_recipient.teacher_id,v_recipient.recipient_name,v_recipient.identifier,v_year_name,
        v_template.title,v_category_name,public.apply_certificate_placeholders(v_template.statement_template,v_context),
        jsonb_build_object('eligibility','staff_recognition','context',v_context,'template',to_jsonb(v_template))
      );
    end if;
    v_inserted_count:=v_inserted_count+1;
  end loop;
  perform public.record_certificate_event(
    v_batch_id,null,'batch_created','',jsonb_build_object('certificate_type',v_certificate_type,'recipient_count',v_inserted_count)
  );
  return jsonb_build_object('batch_id',v_batch_id,'recipient_count',v_inserted_count,'status','draft');
end $function$
;

CREATE OR REPLACE FUNCTION public.create_certificate_replacement_draft(target_certificate_id uuid, reason_text text, replacement_statement text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare source public.certificates; source_batch public.certificate_batches; new_batch_id uuid; new_certificate_id uuid;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can prepare a replacement certificate' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<5 then raise exception 'A replacement reason of at least five characters is required'; end if;
  select * into source from public.certificates where id=target_certificate_id and status in ('issued','revoked');
  if source.id is null then raise exception 'Only an issued or revoked certificate can be replaced'; end if;
  select * into source_batch from public.certificate_batches where id=source.batch_id;
  insert into public.certificate_batches(certificate_type,academic_year_id,term_id,class_id,teacher_award_category_id,template_id,title,custom_citation,notes)
  values(source_batch.certificate_type,source_batch.academic_year_id,source_batch.term_id,source_batch.class_id,source_batch.teacher_award_category_id,source_batch.template_id,source_batch.title,source_batch.custom_citation,'Replacement: '||btrim(reason_text)) returning id into new_batch_id;
  insert into public.certificates(batch_id,recipient_kind,student_id,teacher_id,source_report_id,revision_no,supersedes_certificate_id,recipient_name,recipient_identifier,current_class_name,destination_class_name,academic_year_name,certificate_title,award_category_name,statement_text,status,snapshot,replacement_reason)
  values(new_batch_id,source.recipient_kind,source.student_id,source.teacher_id,source.source_report_id,source.revision_no+1,source.id,source.recipient_name,source.recipient_identifier,source.current_class_name,source.destination_class_name,source.academic_year_name,source.certificate_title,source.award_category_name,coalesce(nullif(btrim(replacement_statement),''),source.statement_text),'draft',source.snapshot,btrim(reason_text)) returning id into new_certificate_id;
  perform public.record_certificate_event(new_batch_id,new_certificate_id,'replacement_draft_created',reason_text,jsonb_build_object('replaces_certificate_id',source.id));
  return jsonb_build_object('batch_id',new_batch_id,'certificate_id',new_certificate_id,'status','draft');
end $function$
;

CREATE OR REPLACE FUNCTION public.create_emergency_academic_delegation(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  dtype text:=coalesce(nullif(btrim(payload->>'delegation_type'),''),'replacement_teacher');
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id');
  termid uuid:=public.safe_uuid(payload->>'term_id');
  classid uuid:=public.safe_uuid(payload->>'class_id');
  subjectid uuid:=public.safe_uuid(payload->>'subject_id');
  delegateid uuid:=public.safe_uuid(payload->>'delegate_user_id');
  allow_scores boolean:=coalesce(public.safe_boolean(payload->>'allow_score_entry',true),true);
  allow_fields boolean:=coalesce(public.safe_boolean(payload->>'allow_class_report_fields',false),false);
  begins timestamptz:=coalesce(public.safe_timestamptz(payload->>'valid_from'),now());
  ends timestamptz:=public.safe_timestamptz(payload->>'valid_until');
  reason_text text:=btrim(coalesce(payload->>'reason',''));
  delegate_role text;
  originalid uuid;
  newrow public.emergency_academic_delegations%rowtype;
  recipient uuid;
  class_name_value text;
  subject_name_value text;
  delegate_name_value text;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can create emergency academic delegations' using errcode='42501'; end if;
  if not public.license_write_allowed() then raise exception 'The current licence does not permit this change' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if dtype not in ('replacement_teacher','system_admin_override') then raise exception 'Delegation type is invalid' using errcode='22023'; end if;
  if yearid is null or termid is null or classid is null or delegateid is null then raise exception 'Academic year, term, class, and delegate are required' using errcode='22023'; end if;
  if ends is null or ends<=begins then raise exception 'Delegation expiry must be after its start time' using errcode='22023'; end if;
  if ends>begins+interval '120 days' then raise exception 'A delegation cannot exceed 120 days' using errcode='22023'; end if;
  if length(reason_text)<10 then raise exception 'Provide a clear reason of at least 10 characters' using errcode='22023'; end if;
  if not allow_scores and not allow_fields then raise exception 'Select at least one delegated capability' using errcode='22023'; end if;
  if subjectid is not null and allow_fields then raise exception 'Class report fields require an all-subject class delegation' using errcode='22023'; end if;
  if not exists(select 1 from public.terms t where t.id=termid and t.academic_year_id=yearid and t.deleted_at is null) then raise exception 'Term and academic year do not match' using errcode='22023'; end if;
  if not exists(select 1 from public.classes c where c.id=classid and c.active and c.deleted_at is null) then raise exception 'Selected class is unavailable' using errcode='22023'; end if;
  if subjectid is not null and not exists(select 1 from public.class_subjects cs where cs.class_id=classid and cs.subject_id=subjectid and cs.active) then raise exception 'Selected subject is not assigned to the class' using errcode='22023'; end if;
  select public.current_app_role_for(p.role)::text into delegate_role from public.profiles p where p.id=delegateid and p.active;
  if delegate_role is null then raise exception 'Delegate account is unavailable' using errcode='22023'; end if;
  if dtype='replacement_teacher' and delegate_role not in ('class_teacher','subject_teacher') then raise exception 'A replacement delegate must be an active teacher' using errcode='22023'; end if;
  if dtype='system_admin_override' and delegate_role<>'system_admin' then raise exception 'Emergency administrator entry must be assigned to an active System Administrator' using errcode='22023'; end if;
  if subjectid is null then
    select c.class_teacher_id into originalid from public.classes c where c.id=classid;
  else
    select cs.teacher_id into originalid from public.class_subjects cs where cs.class_id=classid and cs.subject_id=subjectid and cs.active;
  end if;
  perform pg_advisory_xact_lock(hashtext(delegateid::text),hashtext(classid::text||':'||termid::text));
  if exists(
    select 1 from public.emergency_academic_delegations d
    where d.delegate_user_id=delegateid and d.class_id=classid and d.term_id=termid
      and d.status='active'
      and (d.subject_id is null or subjectid is null or d.subject_id=subjectid)
      and tstzrange(d.valid_from,d.valid_until,'[)') && tstzrange(begins,ends,'[)')
  ) then raise exception 'An overlapping active delegation already exists for this user and scope' using errcode='23505'; end if;
  insert into public.emergency_academic_delegations(
    delegation_type,academic_year_id,term_id,class_id,subject_id,original_teacher_id,delegate_user_id,
    allow_score_entry,allow_class_report_fields,valid_from,valid_until,reason,created_by
  ) values(dtype,yearid,termid,classid,subjectid,originalid,delegateid,allow_scores,allow_fields,begins,ends,reason_text,auth.uid())
  returning * into newrow;
  insert into public.emergency_academic_delegation_events(delegation_id,event_type,actor_id,event_reason,event_data)
  values(newrow.id,'created',auth.uid(),reason_text,to_jsonb(newrow));
  select c.name into class_name_value from public.classes c where c.id=classid;
  select s.name into subject_name_value from public.subjects s where s.id=subjectid;
  select p.full_name into delegate_name_value from public.profiles p where p.id=delegateid;
  for recipient in select p.id from public.profiles p where p.active and public.current_app_role_for(p.role)::text='principal' loop
    perform public.create_notification(recipient,'Emergency academic delegation created',
      format('%s has been granted temporary %s access for %s%s until %s. Reason: %s',delegate_name_value,
        case when dtype='system_admin_override' then 'System Administrator report-entry' else 'replacement-teacher' end,
        class_name_value,case when subject_name_value is null then '' else ' / '||subject_name_value end,
        to_char(ends,'YYYY-MM-DD HH24:MI TZ'),reason_text),
      'emergency_academic_delegation','emergency_academic_delegation',newrow.id,true);
  end loop;
  if delegateid<>auth.uid() then
    perform public.create_notification(delegateid,'Temporary academic access assigned',
      format('You have temporary report-entry access for %s%s until %s. Reason: %s',class_name_value,
        case when subject_name_value is null then '' else ' / '||subject_name_value end,
        to_char(ends,'YYYY-MM-DD HH24:MI TZ'),reason_text),
      'emergency_academic_delegation','emergency_academic_delegation',newrow.id,true);
  end if;
  return public.get_emergency_delegation_console();
end $function$
;

CREATE OR REPLACE FUNCTION public.create_notification(target_recipient uuid, target_title text, target_body text DEFAULT ''::text, target_category text DEFAULT 'system'::text, target_entity_type text DEFAULT ''::text, target_entity_id uuid DEFAULT NULL::uuid, queue_email boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare nid uuid; email_address citext;
begin
  insert into public.notifications(recipient_id,title,body,category,entity_type,entity_id)
  values(target_recipient,target_title,target_body,target_category,target_entity_type,target_entity_id)
  returning id into nid;
  if queue_email then
    select email::citext into email_address from auth.users where id=target_recipient;
    if email_address is not null then
      insert into public.notification_outbox(recipient_id,recipient_email,channel,template_key,payload)
      values(target_recipient,email_address,'email',target_category,
        jsonb_build_object('title',target_title,'body',target_body,'entity_type',target_entity_type,'entity_id',target_entity_id));
    end if;
  end if;
  return nid;
end $function$
;

CREATE OR REPLACE FUNCTION public.create_privacy_request(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.privacy_requests;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if length(btrim(coalesce(payload->>'requester_name','')))<2 then raise exception 'Requester name is required'; end if;
  insert into public.privacy_requests(student_id,request_type,requester_name,requester_contact,request_details,due_at,assigned_to)
  values(public.safe_uuid(payload->>'student_id'),payload->>'request_type',left(btrim(payload->>'requester_name'),200),left(coalesce(payload->>'requester_contact',''),300),left(btrim(payload->>'request_details'),4000),coalesce(public.safe_timestamptz(payload->>'due_at'),now()+interval '30 days'),public.safe_uuid(payload->>'assigned_to')) returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'privacy_requests',row_data.id,'PRIVACY_REQUEST_CREATED',null,
    jsonb_build_object('request_type',row_data.request_type,'student_id',row_data.student_id,'status',row_data.status,'due_at',row_data.due_at),
    'A privacy-rights request was registered. Sensitive requester contact/details remain only in the privacy-request record.');
  return to_jsonb(row_data);
end $function$
;

CREATE OR REPLACE FUNCTION public.create_workflow_notifications(target_report_id uuid, target_status report_status)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  classid uuid;
  studentname text;
  reportno text;
  studentprofile uuid;
  recipient uuid;
begin
  select e.class_id,
         concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
         coalesce(r.report_number,''),
         s.profile_id
  into classid,studentname,reportno,studentprofile
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  join public.students s on s.id=e.student_id
  where r.id=target_report_id;

  if target_status='submitted' then
    for recipient in
      select p.id
      from public.profiles p
      where p.active and public.current_app_role_for(p.role)='principal'
    loop
      if recipient<>auth.uid() then
        perform public.create_notification(
          recipient,
          'Report awaiting Principal approval',
          studentname||case when reportno<>'' then ' • '||reportno else '' end,
          'report_workflow','report',target_report_id,true
        );
      end if;
    end loop;

  elsif target_status='returned' then
    for recipient in
      select distinct user_id from (
        select c.class_teacher_id user_id
        from public.classes c
        where c.id=classid and c.class_teacher_id is not null
        union all
        select cs.teacher_id
        from public.class_subjects cs
        where cs.class_id=classid and cs.active and cs.teacher_id is not null
        union all
        select a.user_id
        from public.user_class_access a
        where a.class_id=classid and a.user_id is not null
      ) q
    loop
      if recipient<>auth.uid() then
        perform public.create_notification(
          recipient,
          'Report returned for correction',
          studentname||case when reportno<>'' then ' • '||reportno else '' end,
          'report_workflow','report',target_report_id,true
        );
      end if;
    end loop;

  elsif target_status='approved' then
    for recipient in
      select distinct user_id from (
        select p.id user_id
        from public.profiles p
        where p.active and public.current_app_role_for(p.role)='system_admin'
        union all
        select c.class_teacher_id
        from public.classes c
        where c.id=classid and c.class_teacher_id is not null
        union all
        select cs.teacher_id
        from public.class_subjects cs
        where cs.class_id=classid and cs.active and cs.teacher_id is not null
        union all
        select a.user_id
        from public.user_class_access a
        where a.class_id=classid and a.user_id is not null
      ) q
    loop
      if recipient<>auth.uid() then
        perform public.create_notification(
          recipient,
          'Report approved by Principal',
          studentname||case when reportno<>'' then ' • '||reportno else '' end,
          'report_workflow','report',target_report_id,true
        );
      end if;
    end loop;

  elsif target_status='published' then
    for recipient in
      select distinct gl.auth_user_id
      from public.guardian_links gl
      join public.enrollments e on e.student_id=gl.student_id
      join public.student_reports r on r.enrollment_id=e.id
      where r.id=target_report_id
        and gl.auth_user_id is not null
        and gl.can_receive_notifications
    loop
      perform public.create_notification(
        recipient,
        'Report card published',
        studentname||case when reportno<>'' then ' • '||reportno else '' end,
        'report_published','report',target_report_id,true
      );
    end loop;

    if studentprofile is not null
       and not exists (
         select 1
         from public.guardian_links gl
         join public.enrollments e on e.student_id=gl.student_id
         join public.student_reports r on r.enrollment_id=e.id
         where r.id=target_report_id
           and gl.auth_user_id=studentprofile
           and gl.can_receive_notifications
       ) then
      perform public.create_notification(
        studentprofile,
        'Report card published',
        studentname||case when reportno<>'' then ' • '||reportno else '' end,
        'report_published','report',target_report_id,true
      );
    end if;
  end if;
end
$function$
;

CREATE OR REPLACE FUNCTION public.current_aal()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ select coalesce(auth.jwt()->>'aal','aal1') $function$
;

CREATE OR REPLACE FUNCTION public.current_app_role()
 RETURNS app_role
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role_for(p.role)::public.app_role
  from public.profiles p
  where p.id=auth.uid() and p.active
    and p.role in ('admin','teacher','headteacher','system_admin','principal','class_teacher','subject_teacher','parent_guardian','platform_super_admin','accounts_office','accountant','student')
$function$
;

CREATE OR REPLACE FUNCTION public.current_app_role_for(input_role app_role)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select case
    when input_role='admin' then 'system_admin'
    when input_role='teacher' then 'class_teacher'
    when input_role='headteacher' then 'principal'
    when input_role='accounts_office' then 'accountant'
    else input_role::text
  end
$function$
;

CREATE OR REPLACE FUNCTION public.current_id_card_principal_snapshot()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select coalesce((select jsonb_build_object('id',h.id,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'title','Principal','signature_path',coalesce(h.signature_path,'')) from public.headteachers h where h.deleted_at is null and h.active and h.employment_status='active' order by case when btrim(coalesce(h.signature_path,''))<>'' then 0 else 1 end,h.updated_at desc,h.created_at desc limit 1),jsonb_build_object('full_name',coalesce((select head_name from public.school_settings limit 1),'Principal'),'title','Principal','signature_path',''))
$function$
;

CREATE OR REPLACE FUNCTION public.default_grading_interpretation(grade_text text, remark_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when lower(btrim(coalesce(remark_text,'')))='excellent' or btrim(coalesce(grade_text,''))='1' then 'Outstanding performance. Keep it up!'
    when lower(btrim(coalesce(remark_text,'')))='very good' or btrim(coalesce(grade_text,''))='2' then 'Well above average. You are doing great!'
    when lower(btrim(coalesce(remark_text,'')))='good' or btrim(coalesce(grade_text,''))='3' then 'Good achievement. Continue to work hard.'
    when lower(btrim(coalesce(remark_text,'')))='high average' or btrim(coalesce(grade_text,''))='4' then 'Satisfactory performance. Aim higher.'
    when lower(btrim(coalesce(remark_text,'')))='average' or btrim(coalesce(grade_text,''))='5' then 'Fair performance. More effort needed.'
    when lower(btrim(coalesce(remark_text,'')))='low average' or btrim(coalesce(grade_text,''))='6' then 'Below average. Focus and improvement required.'
    when lower(btrim(coalesce(remark_text,'')))='pass' or btrim(coalesce(grade_text,''))='7' then 'Minimum pass. Consistent effort is essential.'
    when lower(btrim(coalesce(remark_text,''))) in ('weak','week') or btrim(coalesce(grade_text,''))='8' then 'Weak performance. Urgent improvement needed.'
    when lower(btrim(coalesce(remark_text,'')))='needs improvement' or btrim(coalesce(grade_text,''))='9' then 'Unsatisfactory. Serious improvement is required.'
    else left(concat(coalesce(nullif(btrim(remark_text),''),'Performance recorded'),'. Continue working consistently to improve performance.'),180)
  end
$function$
;

CREATE OR REPLACE FUNCTION public.delete_audit_events(event_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  changed integer;
  archive_id uuid;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can archive audit events' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if event_ids is null or cardinality(event_ids)=0 then raise exception 'Select at least one audit event'; end if;
  perform pg_advisory_xact_lock(hashtext('rce-school-audit-archive'));
  select count(*)::integer into changed from public.audit_log where id=any(event_ids);
  if changed=0 then return 0; end if;
  insert into public.audit_log_archives(archive_scope,reason,event_count,created_by)
  values('selected','Selected audit events archived from the active console',changed,auth.uid())
  returning id into archive_id;
  insert into public.audit_log_archive_entries(
    archive_id,original_event_id,actor_id,table_name,record_id,action,old_data,new_data,reason,original_created_at
  )
  select archive_id,a.id,a.actor_id,a.table_name,a.record_id,a.action,a.old_data,a.new_data,a.reason,a.created_at
  from public.audit_log a where a.id=any(event_ids);
  delete from public.audit_log where id=any(event_ids);
  get diagnostics changed=row_count;
  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details)
  values(auth.uid(),'ARCHIVE_AUDIT_EVENTS',changed,jsonb_build_object('archive_id',archive_id,'event_ids',event_ids));
  return changed;
end
$function$
;

CREATE OR REPLACE FUNCTION public.delete_certificate_permanently(target_certificate_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_certificate public.certificates;
  v_batch public.certificate_batches;
  v_reason text:=btrim(coalesce(reason_text,''));
  v_batch_deleted boolean:=false;
begin
  if not public.can_manage_certificates() then
    raise exception 'Only the System Administrator can permanently delete certificates' using errcode='42501';
  end if;
  if length(v_reason)<5 then
    raise exception 'A permanent deletion reason of at least five characters is required';
  end if;
  select c.* into v_certificate
  from public.certificates c
  where c.id=target_certificate_id
  for update;
  if v_certificate.id is null then
    raise exception 'Certificate not found';
  end if;
  select b.* into v_batch
  from public.certificate_batches b
  where b.id=v_certificate.batch_id
  for update;
  insert into public.audit_log(
    actor_id,table_name,record_id,action,old_data,new_data,reason
  ) values(
    auth.uid(),'certificates',v_certificate.id,'PERMANENT_DELETE',
    jsonb_build_object(
      'batch_id',v_certificate.batch_id,
      'certificate_number',v_certificate.certificate_number,
      'recipient_name',v_certificate.recipient_name,
      'recipient_identifier',v_certificate.recipient_identifier,
      'certificate_title',v_certificate.certificate_title,
      'academic_year_name',v_certificate.academic_year_name,
      'status',v_certificate.status,
      'pdf_storage_path',v_certificate.pdf_storage_path,
      'verification_token',v_certificate.verification_token,
      'revision_no',v_certificate.revision_no
    ),
    null,
    v_reason
  );
  delete from public.certificate_events e
  where e.certificate_id=v_certificate.id;
  delete from public.certificates c
  where c.id=v_certificate.id;
  if not exists(
    select 1 from public.certificates c where c.batch_id=v_certificate.batch_id
  ) then
    delete from public.certificate_events e where e.batch_id=v_certificate.batch_id;
    delete from public.certificate_batches b where b.id=v_certificate.batch_id;
    v_batch_deleted:=true;
  end if;
  return jsonb_build_object(
    'certificate_id',v_certificate.id,
    'batch_id',v_certificate.batch_id,
    'batch_deleted',v_batch_deleted,
    'storage_path',coalesce(v_certificate.pdf_storage_path,''),
    'certificate_number',coalesce(v_certificate.certificate_number::text,''),
    'status','deleted'
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.delete_class_subject_assignment(target_id uuid, reason_text text DEFAULT 'Class subject assignment permanently deleted'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  target_class_id uuid;
  target_subject_id uuid;
  active_value boolean;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  select cs.class_id,cs.subject_id,cs.active
  into target_class_id,target_subject_id,active_value
  from public.class_subjects cs
  where cs.id=target_id
  for update;
  if not found then raise exception 'Subject assignment not found'; end if;
  if active_value then raise exception 'Remove the active subject assignment before deleting it'; end if;
  if exists(
    select 1
    from public.subject_results sr
    join public.student_reports r on r.id=sr.report_id
    join public.enrollments e on e.id=r.enrollment_id
    where e.class_id=target_class_id
      and sr.subject_id=target_subject_id
      and r.deleted_at is null
      and r.status not in ('published','withdrawn')
  ) then raise exception 'This assignment is connected to unfinished report cards'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Class subject assignment permanently deleted'),true);
  delete from public.user_class_access a
  where a.class_id=target_class_id and a.subject_id=target_subject_id;
  delete from public.class_subjects cs where cs.id=target_id;
  if not found then raise exception 'Subject assignment was not deleted'; end if;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.delete_class_timetable_entry(target_entry_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage class timetables' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('timetable');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit timetable changes' using errcode='42501';end if;delete from public.class_timetable_entries where id=target_entry_id;if not found then raise exception 'Timetable entry not found';end if;end$function$
;

CREATE OR REPLACE FUNCTION public.delete_notifications(notification_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare changed integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  delete from public.notifications where recipient_id=auth.uid() and (notification_ids is null or id=any(notification_ids));
  get diagnostics changed=row_count;
  return changed;
end $function$
;

CREATE OR REPLACE FUNCTION public.delete_report_card_permanently(target_report_id uuid, reason_text text DEFAULT 'Draft report card permanently deleted'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  report_number_text text;
  report_status_text text;
  student_id_value uuid;
  enrollment_id_value uuid;
begin
  if not public.can_delete_report(target_report_id) then
    raise exception 'Only a never-approved, never-published draft/returned report may be permanently deleted' using errcode='42501';
  end if;

  select r.report_number::text,r.status::text,r.enrollment_id,e.student_id
    into report_number_text,report_status_text,enrollment_id_value,student_id_value
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id and r.deleted_at is null
  for update of r;
  if not found then raise exception 'Report card not found'; end if;

  perform set_config('app.report_write','on',true);
  perform set_config('app.audit_suppress','on',true);
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Draft report card permanently deleted'),true);

  delete from public.notifications where entity_type='report' and entity_id=target_report_id;
  delete from public.notification_outbox where coalesce(payload::text,'') like '%'||target_report_id::text||'%';
  delete from public.student_reports where id=target_report_id;
  if not found then raise exception 'Report card not found'; end if;

  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(
    auth.uid(),'student_reports',target_report_id,'REPORT_DRAFT_PERMANENTLY_DELETED',
    jsonb_build_object('report_number',report_number_text,'status',report_status_text,'student_id',student_id_value,'enrollment_id',enrollment_id_value),
    null,
    coalesce(nullif(reason_text,''),'Draft report card permanently deleted')
  );
  return true;
end
$function$
;

CREATE OR REPLACE FUNCTION public.delete_school_prospectus(target_prospectus_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare p public.school_prospectuses%rowtype;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can delete draft school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select * into p from public.school_prospectuses where id=target_prospectus_id for update;if p.id is null then raise exception 'Prospectus not found';end if;if p.status<>'draft' or p.revision_no>0 or exists(select 1 from public.school_prospectus_revisions where prospectus_id=p.id) then raise exception 'Only a never-published draft prospectus can be deleted. Archive published prospectuses instead.';end if;delete from public.school_prospectuses where id=p.id;end$function$
;

CREATE OR REPLACE FUNCTION public.delete_school_prospectus_item(target_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare pid uuid;status_value text;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can remove prospectus items' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select s.prospectus_id,p.status into pid,status_value from public.school_prospectus_items i join public.school_prospectus_sections s on s.id=i.section_id join public.school_prospectuses p on p.id=s.prospectus_id where i.id=target_item_id for update of p;if pid is null then raise exception 'Prospectus item not found';end if;if status_value='archived' then raise exception 'Archived prospectuses cannot be edited';end if;delete from public.school_prospectus_items where id=target_item_id;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;end$function$
;

CREATE OR REPLACE FUNCTION public.delete_school_prospectus_section(target_section_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare pid uuid;status_value text;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can remove prospectus sections' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select s.prospectus_id,p.status into pid,status_value from public.school_prospectus_sections s join public.school_prospectuses p on p.id=s.prospectus_id where s.id=target_section_id for update of p;if pid is null then raise exception 'Prospectus section not found';end if;if status_value='archived' then raise exception 'Archived prospectuses cannot be edited';end if;delete from public.school_prospectus_sections where id=target_section_id;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;end$function$
;

CREATE OR REPLACE FUNCTION public.delete_staff_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c public.staff_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,''));sid uuid;
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can permanently delete staff ID card records' using errcode='42501';end if;if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required for permanent ID card deletion' using errcode='42501';end if;perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card changes' using errcode='42501';end if;if upper(btrim(coalesce(confirmation_text,'')))<>'DELETE' then raise exception 'Type DELETE exactly to confirm permanent removal';end if;if length(reason)<5 then raise exception 'A deletion reason of at least five characters is required';end if;select * into c from public.staff_id_cards where id=target_card_id and status in ('revoked','replaced') for update;if c.id is null then raise exception 'Only a revoked or replaced staff ID card can be permanently deleted';end if;sid:=coalesce(c.teacher_id,c.headteacher_id);insert into public.id_card_deletion_tombstones(card_kind,card_number,verification_token,previous_status,deleted_by,deletion_reason,details) values('staff',c.card_number,c.verification_token,c.status,auth.uid(),reason,jsonb_build_object('revision',c.revision_no,'staff_type',c.staff_type,'deleted_record_id',c.id)) on conflict(card_kind,card_number) do nothing;perform public.record_staff_id_card_event(c.id,c.staff_type,sid,'permanently_deleted',jsonb_build_object('card_number',c.card_number,'previous_status',c.status,'reason',reason));delete from public.staff_id_cards where id=c.id;return jsonb_build_object('deleted',true,'card_number',c.card_number,'status','permanently_removed');end$function$
;

CREATE OR REPLACE FUNCTION public.delete_student_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c public.student_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,''));
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can permanently delete ID card records' using errcode='42501';end if;if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required for permanent ID card deletion' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if upper(btrim(coalesce(confirmation_text,'')))<>'DELETE' then raise exception 'Type DELETE exactly to confirm permanent removal';end if;if length(reason)<5 then raise exception 'A deletion reason of at least five characters is required';end if;select * into c from public.student_id_cards where id=target_card_id and status in ('revoked','replaced') for update;if c.id is null then raise exception 'Only a revoked or replaced student ID card can be permanently deleted';end if;insert into public.id_card_deletion_tombstones(card_kind,card_number,verification_token,previous_status,deleted_by,deletion_reason,details) values('student',c.card_number,c.verification_token,c.status,auth.uid(),reason,jsonb_build_object('revision',c.revision_no,'deleted_record_id',c.id)) on conflict(card_kind,card_number) do nothing;perform public.record_id_card_event(c.id,c.student_id,'permanently_deleted',jsonb_build_object('card_number',c.card_number,'previous_status',c.status,'reason',reason));delete from public.student_id_cards where id=c.id;return jsonb_build_object('deleted',true,'card_number',c.card_number,'status','permanently_removed');end$function$
;

CREATE OR REPLACE FUNCTION public.delete_transcript_issuance_permanently(target_issuance_id uuid, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_issuance public.transcript_issuances%rowtype;
  v_reason text:=btrim(coalesce(reason_text,''));
  v_confirmation text:=btrim(coalesce(confirmation_text,''));
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can permanently delete transcript issuances' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'The current licence does not permit this change' using errcode='42501';
  end if;
  if target_issuance_id is null then
    raise exception 'Transcript issuance is required' using errcode='22023';
  end if;
  if length(v_reason)<5 then
    raise exception 'A permanent deletion reason of at least five characters is required' using errcode='22023';
  end if;
  if v_confirmation<>'DELETE' then
    raise exception 'Type DELETE exactly to confirm permanent transcript issuance removal' using errcode='22023';
  end if;
  select i.* into v_issuance
  from public.transcript_issuances i
  where i.id=target_issuance_id
  for update;
  if v_issuance.id is null then
    raise exception 'Transcript issuance not found' using errcode='P0002';
  end if;
  insert into public.audit_log(
    actor_id,table_name,record_id,action,old_data,new_data,reason
  ) values(
    auth.uid(),'transcript_issuances',v_issuance.id,'PERMANENT_DELETE',
    jsonb_build_object(
      'student_id',v_issuance.student_id,
      'purpose',v_issuance.purpose,
      'status',v_issuance.status,
      'issued_by',v_issuance.issued_by,
      'issued_at',v_issuance.issued_at,
      'revoked_by',v_issuance.revoked_by,
      'revoked_at',v_issuance.revoked_at,
      'revocation_reason',v_issuance.revocation_reason
    ),
    null,
    left(v_reason,500)
  );
  delete from public.transcript_issuances i
  where i.id=v_issuance.id;
  if found then
    return jsonb_build_object(
      'id',v_issuance.id,
      'student_id',v_issuance.student_id,
      'status','deleted'
    );
  end if;
  raise exception 'Transcript issuance could not be deleted';
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_acknowledge_incident(target_incident_id uuid, acknowledgement_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_student uuid;v_id uuid;v_name text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select i.student_id into v_student from public.discipline_incidents i where i.id=target_incident_id and i.guardian_visible and exists(select 1 from public.guardian_links g where g.student_id=i.student_id and g.auth_user_id=auth.uid() and g.can_view_reports);
 if v_student is null then raise exception 'Incident not available to this guardian' using errcode='42501'; end if;
 select full_name into v_name from public.profiles where id=auth.uid();
 insert into public.discipline_guardian_acknowledgements(incident_id,student_id,guardian_user_id,guardian_name,acknowledgement_note) values(target_incident_id,v_student,auth.uid(),v_name,nullif(acknowledgement_note,'')) on conflict(incident_id,guardian_user_id) do update set acknowledgement_note=excluded.acknowledgement_note,acknowledged_at=now() returning id into v_id;
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_add_action(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('discipline','write');
 if not exists(select 1 from public.discipline_incidents where id=(payload->>'incident_id')::uuid and status not in ('resolved','cancelled')) then raise exception 'Incident is finalized or unavailable'; end if;
 insert into public.discipline_actions(incident_id,action_type,action_notes,starts_at,ends_at,status,assigned_hr_staff_id,created_by)
 values((payload->>'incident_id')::uuid,payload->>'action_type',btrim(payload->>'action_notes'),nullif(payload->>'starts_at','')::timestamptz,nullif(payload->>'ends_at','')::timestamptz,coalesce(nullif(payload->>'status',''),'active'),nullif(payload->>'assigned_hr_staff_id','')::uuid,auth.uid()) returning id into v_id;
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('discipline','read');
 return jsonb_build_object('metrics',jsonb_build_object(
  'open_incidents',(select count(*) from public.discipline_incidents where status in ('open','under_review','referred')),
  'critical_open',(select count(*) from public.discipline_incidents where status in ('open','under_review','referred') and severity='critical'),
  'guardian_pending',(select count(*) from public.discipline_incidents where guardian_visible and guardian_notified_at is null and status<>'cancelled'),
  'open_welfare',(select count(*) from public.welfare_cases where status in ('open','monitoring','referred')),
  'urgent_welfare',(select count(*) from public.welfare_cases where status in ('open','monitoring','referred') and priority='urgent')
 ));
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_incident_detail(target_incident_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r jsonb;
begin
 perform public.student_services_require_access('discipline','read');
 select to_jsonb(q) into r from (select i.*,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name from public.discipline_incidents i join public.students s on s.id=i.student_id where i.id=target_incident_id)q;
 if r is null then raise exception 'Incident not found'; end if;
 return r||jsonb_build_object(
  'actions',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at) from public.discipline_actions a where a.incident_id=target_incident_id),'[]'::jsonb),
  'acknowledgements',coalesce((select jsonb_agg(to_jsonb(g) order by g.acknowledged_at) from public.discipline_guardian_acknowledgements g where g.incident_id=target_incident_id),'[]'::jsonb)
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_incident_register(search_text text DEFAULT NULL::text, status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('discipline','read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (
  select i.id,i.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,i.occurred_at,i.incident_type,i.severity,i.location,i.summary,i.status,i.guardian_visible,i.guardian_notified_at,i.resolved_at,
   (select count(*) from public.discipline_actions a where a.incident_id=i.id) action_count,
   (select count(*) from public.discipline_guardian_acknowledgements g where g.incident_id=i.id) acknowledgement_count
  from public.discipline_incidents i join public.students s on s.id=i.student_id
  where (status_filter is null or i.status=status_filter)
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,i.incident_type,i.summary) ilike '%'||search_text||'%')
  order by i.occurred_at desc limit 300
 )q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_my_children_incidents()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.occurred_at desc) from (
  select i.id,i.student_id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,i.occurred_at,i.incident_type,i.severity,i.summary,i.status,i.guardian_notified_at,
   exists(select 1 from public.discipline_guardian_acknowledgements a where a.incident_id=i.id and a.guardian_user_id=auth.uid()) acknowledged
  from public.discipline_incidents i join public.students s on s.id=i.student_id
  where i.guardian_visible and exists(select 1 from public.guardian_links g where g.student_id=i.student_id and g.auth_user_id=auth.uid() and g.can_view_reports)
 )q),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_notify_guardian(target_incident_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_student uuid;v_summary text;v_count integer:=0;
begin
 perform public.student_services_require_access('discipline','write');
 select student_id,summary into v_student,v_summary from public.discipline_incidents where id=target_incident_id and guardian_visible and status<>'cancelled' for update;
 if v_student is null then raise exception 'Incident is not available for guardian notification'; end if;
 insert into public.notifications(recipient_id,title,body,category,entity_type,entity_id)
 select distinct g.auth_user_id,'Student welfare/discipline update',v_summary,'discipline','discipline_incident',target_incident_id
 from public.guardian_links g where g.student_id=v_student and g.auth_user_id is not null and g.can_receive_notifications
 on conflict do nothing;
 get diagnostics v_count=row_count;
 update public.discipline_incidents set guardian_notified_at=now() where id=target_incident_id;
 return v_count;
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_resolve_incident(target_incident_id uuid, resolution_notes text, new_status text DEFAULT 'resolved'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('discipline','approve');
 if $3 not in ('resolved','referred','cancelled') then raise exception 'Invalid incident outcome'; end if;
 update public.discipline_incidents i set status=$3,resolution_notes=nullif($2,''),resolved_by=auth.uid(),resolved_at=case when $3 in ('resolved','cancelled') then now() else null end where i.id=$1 and i.status not in ('resolved','cancelled');
 if not found then raise exception 'Incident is finalized or unavailable'; end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('discipline','incident_outcome','discipline_incident',$1,auth.uid(),jsonb_build_object('status',$3));
end $function$
;

CREATE OR REPLACE FUNCTION public.discipline_save_incident(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('discipline','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then
  insert into public.discipline_incidents(student_id,occurred_at,incident_type,severity,location,summary,details,status,guardian_visible,reported_by)
  values((payload->>'student_id')::uuid,coalesce(nullif(payload->>'occurred_at','')::timestamptz,now()),btrim(payload->>'incident_type'),coalesce(nullif(payload->>'severity',''),'medium'),nullif(btrim(payload->>'location'),''),btrim(payload->>'summary'),nullif(payload->>'details',''),coalesce(nullif(payload->>'status',''),'open'),coalesce((payload->>'guardian_visible')::boolean,false),auth.uid()) returning id into v_id;
 else
  update public.discipline_incidents set incident_type=coalesce(nullif(btrim(payload->>'incident_type'),''),incident_type),severity=coalesce(nullif(payload->>'severity',''),severity),location=case when payload ? 'location' then nullif(btrim(payload->>'location'),'') else location end,summary=coalesce(nullif(btrim(payload->>'summary'),''),summary),details=case when payload ? 'details' then nullif(payload->>'details','') else details end,guardian_visible=coalesce((payload->>'guardian_visible')::boolean,guardian_visible) where id=v_id and status not in ('resolved','cancelled');
  if not found then raise exception 'Incident is finalized or unavailable'; end if;
 end if;
 insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details) values('discipline','incident_saved','discipline_incident',v_id,auth.uid(),'{}');
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.enforce_custom_branding_entitlement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if auth.uid() is null or auth.role() in ('service_role','supabase_admin') or public.is_platform_super_admin() then return new;end if; if (new.primary_colour is distinct from old.primary_colour or new.accent_colour is distinct from old.accent_colour or new.report_body_font is distinct from old.report_body_font or new.report_body_font_size is distinct from old.report_body_font_size) and not public.license_feature_enabled('custom_branding') then raise exception 'LICENSE_FEATURE_NOT_INCLUDED: The current plan does not include custom branding' using errcode='42501';end if; return new; end$function$
;

CREATE OR REPLACE FUNCTION public.enforce_licensed_storage_capacity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_catalog', 'extensions'
AS $function$ declare v_snapshot jsonb;v_limit_mb bigint;v_new_bytes bigint;v_used_bytes numeric:=0;v_limit_bytes numeric; begin if new.bucket_id not in ('student-photos','staff-photos','school-branding','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs') then return new;end if;v_snapshot:=public.license_snapshot_for_role('system_admin');if not coalesce((v_snapshot->>'write_allowed')::boolean,false) then raise exception 'LICENSE_WRITE_RESTRICTED: %',coalesce(nullif(v_snapshot->>'warning',''),'The current licence does not permit Storage changes.') using errcode='42501';end if;v_limit_mb:=nullif(v_snapshot#>>'{plan,max_storage_mb}','')::bigint;if v_limit_mb is null then return new;end if;v_new_bytes:=public.rce_finalized_storage_object_size(new.metadata);if v_new_bytes is null then return new;end if;perform pg_advisory_xact_lock(hashtext('rce-license-storage'));select coalesce(sum(public.rce_finalized_storage_object_size(o.metadata)),0) into v_used_bytes from storage.objects o where o.bucket_id in ('student-photos','staff-photos','school-branding','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs') and not(o.bucket_id=new.bucket_id and o.name=new.name) and (new.id is null or o.id is distinct from new.id);v_limit_bytes:=v_limit_mb::numeric*1048576;if v_used_bytes+v_new_bytes::numeric>v_limit_bytes then raise exception 'LICENSE_CAPACITY_REACHED: The plan permits a maximum of % MB of school Storage',v_limit_mb using errcode='23514';end if;return new; end$function$
;

CREATE OR REPLACE FUNCTION public.enforce_licensed_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_snapshot jsonb;
  v_feature text;
  v_limit integer;
  v_count integer;
  v_becoming_active boolean:=false;
  v_new jsonb;
  v_old jsonb;
  v_record_id uuid;
  v_new_deleted_at text;
  v_old_deleted_at text;
begin
  if auth.role() in ('service_role','supabase_admin') or auth.role() is null then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  -- Append-only operational evidence must remain recordable when a school is
  -- read-only or when a Platform Super Administrator has platform-control
  -- access. Direct browser DML is revoked below, so these rows are written only
  -- by trusted SECURITY DEFINER functions and database audit triggers.
  if tg_table_name in ('audit_log','client_error_events','security_events','system_maintenance_log') then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  v_snapshot:=public.license_snapshot_for_role(public.current_app_role()::text);
  if not coalesce((v_snapshot->>'write_allowed')::boolean,false) then
    raise exception 'LICENSE_WRITE_RESTRICTED: %',
      coalesce(nullif(v_snapshot->>'warning',''),'The current licence does not permit changes.')
      using errcode='42501';
  end if;
  v_feature:=public.license_feature_for_table(tg_table_name);
  perform public.require_license_feature(v_feature);
  if tg_table_name='report_card_templates' then
    perform public.require_license_feature('report_cards');
  elsif tg_table_name='certificate_templates' then
    perform public.require_license_feature('certificates');
  end if;
  if tg_op<>'DELETE' then v_new:=to_jsonb(new); end if;
  if tg_op<>'INSERT' then v_old:=to_jsonb(old); end if;
  if tg_table_name='students' and tg_op in ('INSERT','UPDATE') then
    v_record_id:=public.safe_uuid(v_new->>'id');
    v_new_deleted_at:=nullif(v_new->>'deleted_at','');
    v_old_deleted_at:=nullif(v_old->>'deleted_at','');
    if v_new->>'status'='active' and v_new_deleted_at is null then
      if tg_op='INSERT' then
        v_becoming_active:=true;
      else
        v_becoming_active:=(v_old->>'status') is distinct from (v_new->>'status')
          or v_old_deleted_at is distinct from v_new_deleted_at;
      end if;
    end if;
    if v_becoming_active then
      perform pg_advisory_xact_lock(hashtext('rce-license-students'));
      v_limit:=nullif(v_snapshot#>>'{plan,max_students}','')::integer;
      if v_limit is not null then
        select count(*) into v_count
        from public.students s
        where s.status='active' and s.deleted_at is null
          and (tg_op='INSERT' or s.id is distinct from v_record_id);
        if v_count>=v_limit then
          raise exception 'LICENSE_CAPACITY_REACHED: The plan permits a maximum of % active students',v_limit
            using errcode='23514';
        end if;
      end if;
    end if;
  elsif tg_table_name='teachers' and tg_op in ('INSERT','UPDATE') then
    v_record_id:=public.safe_uuid(v_new->>'id');
    v_new_deleted_at:=nullif(v_new->>'deleted_at','');
    v_old_deleted_at:=nullif(v_old->>'deleted_at','');
    if coalesce((v_new->>'active')::boolean,false) and v_new_deleted_at is null then
      if tg_op='INSERT' then
        v_becoming_active:=true;
      else
        v_becoming_active:=coalesce((v_old->>'active')::boolean,false)
            is distinct from coalesce((v_new->>'active')::boolean,false)
          or v_old_deleted_at is distinct from v_new_deleted_at;
      end if;
    end if;
    if v_becoming_active then
      perform pg_advisory_xact_lock(hashtext('rce-license-teachers'));
      v_limit:=nullif(v_snapshot#>>'{plan,max_teachers}','')::integer;
      if v_limit is not null then
        select count(*) into v_count
        from public.teachers t
        where t.active and t.deleted_at is null
          and (tg_op='INSERT' or t.id is distinct from v_record_id);
        if v_count>=v_limit then
          raise exception 'LICENSE_CAPACITY_REACHED: The plan permits a maximum of % active teachers',v_limit
            using errcode='23514';
        end if;
      end if;
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.enforce_single_current_principal()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if new.deleted_at is null and new.active and new.employment_status='active' then
    if exists(
      select 1 from public.headteachers h
      where h.deleted_at is null
        and h.active
        and h.employment_status='active'
        and h.id<>new.id
    ) then
      raise exception 'Another active Principal appointment already exists';
    end if;
  end if;
  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.enforce_student_management_aal2_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if auth.role() in ('service_role','supabase_admin') or auth.role() is null then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if public.current_app_role()::text<>'system_admin' then
    raise exception 'Only the System Administrator can modify student identity records' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  if tg_op='DELETE' then return old; end if;
  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.enforce_system_admin_capacity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare e jsonb;l public.school_licenses%rowtype;lim integer;used_count integer;new_role text;old_role text:='';becoming_admin boolean:=false;becoming_guardian boolean:=false;initial_generated_admin boolean:=false;computed text;v_now timestamptz:=now();
begin
  if auth.role() is null or auth.role()='supabase_admin' then return new; end if;
  new_role:=public.current_app_role_for(new.role)::text;if tg_op='UPDATE' then old_role:=public.current_app_role_for(old.role)::text;end if;
  becoming_admin:=new.active and new_role='system_admin' and (tg_op='INSERT' or not old.active or old_role<>'system_admin');
  becoming_guardian:=new.active and new_role='parent_guardian' and (tg_op='INSERT' or not old.active or old_role<>'parent_guardian');
  if becoming_admin or becoming_guardian then
    perform pg_advisory_xact_lock(hashtext('rce-license-profile-capacity'));
    select * into l from public.school_licenses order by created_at limit 1;
    if l.id is null then raise exception 'LICENSE_WRITE_RESTRICTED: No platform licence is configured' using errcode='42501';end if;
    initial_generated_admin:=becoming_admin and l.package_id is not null
      and not exists(select 1 from public.profiles x where x.active and public.current_app_role_for(x.role)::text='system_admin' and (tg_op='INSERT' or x.id<>new.id));
    computed:=l.status;
    if computed='active' then
      if l.activated_at is null or l.activated_at>v_now then computed:='pending_activation';
      elsif l.expires_at is not null and l.expires_at<v_now then computed:=case when l.grace_ends_at is not null and l.grace_ends_at>=v_now then 'grace_period' else 'expired' end;end if;
    elsif computed='grace_period' and l.grace_ends_at is not null and l.grace_ends_at<v_now then computed:='expired';end if;
    if computed not in ('active','grace_period','perpetual') and not initial_generated_admin then raise exception 'LICENSE_WRITE_RESTRICTED: The licence does not permit user creation' using errcode='42501';end if;
    if l.package_id is not null and not initial_generated_admin and (l.signature_status<>'verified' or l.authority_status not in ('active','unreachable') or l.authority_last_success_at is null or l.authority_last_success_at<v_now-interval '72 hours') then raise exception 'LICENSE_WRITE_RESTRICTED: Generated package verification is required' using errcode='42501';end if;
    e:=public.license_effective_entitlement();
    if becoming_admin then
      lim:=nullif(e#>>'{plan,max_system_admins}','')::integer;
      if lim is not null then select count(*) into used_count from public.profiles x where x.active and public.current_app_role_for(x.role)::text='system_admin' and (tg_op='INSERT' or x.id<>new.id);if used_count>=lim then raise exception 'LICENSE_CAPACITY_REACHED: The plan permits a maximum of % active System Administrators',lim using errcode='23514';end if;end if;
    end if;
    if becoming_guardian then
      lim:=nullif(e#>>'{plan,max_guardians}','')::integer;
      if lim is not null then select count(*) into used_count from public.profiles x where x.active and public.current_app_role_for(x.role)::text='parent_guardian' and (tg_op='INSERT' or x.id<>new.id);if used_count>=lim then raise exception 'LICENSE_CAPACITY_REACHED: The plan permits a maximum of % active guardians',lim using errcode='23514';end if;end if;
    end if;
  end if;return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.ensure_current_user_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  v_target_id uuid:=auth.uid();
  v_email text;
  v_metadata jsonb;
  v_app_metadata jsonb;
  v_requested_role text;
  v_assigned_role public.app_role;
  v_assigned_active boolean:=true;
  v_fallback_name text;
begin
  if v_target_id is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  select u.email,u.raw_user_meta_data,u.raw_app_meta_data
  into v_email,v_metadata,v_app_metadata
  from auth.users u where u.id=v_target_id;
  if not found then
    raise exception 'Authentication account not found' using errcode='42501';
  end if;
  v_metadata:=coalesce(v_metadata,'{}'::jsonb);
  v_app_metadata:=coalesce(v_app_metadata,'{}'::jsonb);
  v_requested_role:=lower(coalesce(v_app_metadata->>'role',v_metadata->>'role',''));
  v_fallback_name:=coalesce(
    nullif(btrim(v_metadata->>'full_name'),''),
    nullif(split_part(coalesce(v_email,''),'@',1),''),
    'User'
  );
  if not exists(select 1 from public.profiles p where p.id=v_target_id) then
    if not exists(
         select 1 from public.profiles p
         where p.active and public.current_app_role_for(p.role)='system_admin'
       ) and v_target_id=(select u.id from auth.users u order by u.created_at,u.id limit 1) then
      v_assigned_role:='system_admin'::public.app_role;
    elsif v_requested_role in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian') then
      v_assigned_role:=v_requested_role::public.app_role;
    else
      v_assigned_role:='parent_guardian'::public.app_role;
      v_assigned_active:=false;
    end if;
    insert into public.profiles(id,full_name,role,active,mfa_required,phone)
    values(v_target_id,v_fallback_name,v_assigned_role,v_assigned_active,
      v_assigned_role in ('system_admin','principal'),'')
    on conflict(id) do nothing;
  end if;
  update public.profiles p set
    full_name=case when btrim(coalesce(p.full_name,''))='' then v_fallback_name else p.full_name end,
    role=case
      when p.role='headteacher' then 'principal'::public.app_role
      when p.role='admin' then 'system_admin'::public.app_role
      when p.role='teacher' then 'class_teacher'::public.app_role
      when p.role in ('academic_admin','records_officer','viewer') then 'parent_guardian'::public.app_role
      else p.role end,
    active=case when p.role in ('academic_admin','records_officer','viewer') then false else p.active end,
    updated_at=now()
  where p.id=v_target_id
    and (
      btrim(coalesce(p.full_name,''))=''
      or p.role in ('headteacher','admin','teacher','academic_admin','records_officer','viewer')
    );
  return (
    select jsonb_build_object(
      'id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role),
      'active',p.active,'mfa_required',p.mfa_required
    )
    from public.profiles p where p.id=v_target_id
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.export_backup_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'schema_version','6.7.0',
    'generated_at',now(),
    'school_settings',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.school_settings x),
    'profiles',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.profiles x),
    'teachers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.teachers x),
    'headteachers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.headteachers x),
    'academic_years',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.academic_years x),
    'terms',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.terms x),
    'classes',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.classes x),
    'subjects',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.subjects x),
    'class_subjects',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.class_subjects x),
    'user_class_access',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.user_class_access x),
    'students',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.students x),
    'student_guardians',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.student_guardians x),
    'guardian_links',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.guardian_links x),
    'enrollments',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.enrollments x),
    'grading_scales',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.grading_scales x),
    'assessment_schemes',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.assessment_schemes x),
    'assessment_components',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.assessment_components x),
    'student_reports',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.student_reports x),
    'subject_scores',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.subject_scores x),
    'subject_results',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.subject_results x),
    'assessment_score_entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.assessment_score_entries x),
    'report_workflow_events',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.report_workflow_events x),
    'report_revisions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.report_revisions x),
    'report_publications',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.report_publications x),
    'report_card_templates',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.report_card_templates x),
    'notifications',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.notifications x),
    'notification_outbox',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.notification_outbox x),
    'import_batches',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.import_batches x),
    'import_errors',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.import_errors x),
    'audit_log',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.audit_log x),
    'client_error_events',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.client_error_events x),
    'system_maintenance_log',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.system_maintenance_log x),
    'backup_exports',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.backup_exports x),
    'backup_storage_objects',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.backup_storage_objects x)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_accounts_console(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('finance_fees',false);
 return jsonb_build_object(
  'metrics',jsonb_build_object(
    'expected',coalesce((select sum(b.term_fee_amount+greatest(b.debit_adjustments,0)) from public.finance_fee_account_balances b where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),0),
    'collected',coalesce((select sum(b.amount_paid) from public.finance_fee_account_balances b where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),0),
    'outstanding',coalesce((select sum(greatest(b.balance,0)) from public.finance_fee_account_balances b where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),0),
    'fully_paid',(select count(*) from public.finance_fee_account_balances b where b.status in ('fully_paid','credit') and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),
    'partial_paid',(select count(*) from public.finance_fee_account_balances b where b.status='partial_paid' and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),
    'unpaid',(select count(*) from public.finance_fee_account_balances b where b.status='unpaid' and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id))
  ),
  'fee_groups',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',g.id,'code',g.code,'name',g.name,'sort_order',g.sort_order,'active',g.active,
      'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'level_order',c.level_order) order by m.sort_order,c.level_order,c.name)
                          from public.finance_fee_group_classes m join public.classes c on c.id=m.class_id
                          where m.fee_group_id=g.id),'[]'::jsonb)
    ) order by g.sort_order,g.name)
    from public.finance_fee_groups g where g.active
  ),'[]'::jsonb),
  'schedules',coalesce((
    select jsonb_agg(to_jsonb(q)-'year_start'-'term_sequence'-'sort_order' order by q.year_start desc,q.term_sequence,q.sort_order,q.display_name)
    from (
      select (array_agg(s.id order by c.level_order,c.name))[1] id,
             s.academic_year_id,s.term_id,s.fee_group_id,g.name fee_group_name,
             null::uuid class_id,g.name display_name,g.name class_name,
             string_agg(c.name,', ' order by c.level_order,c.name) member_classes,
             s.amount,s.due_date,s.description,bool_and(s.active) active,
             y.name academic_year_name,t.name term_name,y.start_date year_start,t.sequence term_sequence,g.sort_order
      from public.finance_fee_schedules s
      join public.finance_fee_groups g on g.id=s.fee_group_id
      join public.classes c on c.id=s.class_id
      join public.academic_years y on y.id=s.academic_year_id
      join public.terms t on t.id=s.term_id
      where s.fee_group_id is not null
      group by s.academic_year_id,s.term_id,s.fee_group_id,g.name,g.sort_order,s.amount,s.due_date,s.description,y.name,t.name,y.start_date,t.sequence
      union all
      select s.id,s.academic_year_id,s.term_id,null::uuid,null::text,c.id,c.name,c.name,c.name,s.amount,s.due_date,s.description,s.active,y.name,t.name,y.start_date,t.sequence,c.level_order
      from public.finance_fee_schedules s
      join public.classes c on c.id=s.class_id
      join public.academic_years y on y.id=s.academic_year_id
      join public.terms t on t.id=s.term_id
      where s.fee_group_id is null
    ) q
  ),'[]'::jsonb),
  'statements',coalesce((select jsonb_agg(jsonb_build_object('account_id',b.id,'student_id',st.id,'student',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'admission_no',st.admission_no,'class_id',c.id,'class_name',c.name,'academic_year_id',y.id,'academic_year_name',y.name,'term_id',t.id,'term_name',t.name,'due',b.term_fee_amount,'paid',b.amount_paid,'balance',b.balance,'status',b.status,'method',(select x.payment_method from public.finance_fee_transactions x join public.finance_fee_allocations a on a.transaction_id=x.id where a.account_id=b.id and x.entry_type='payment' order by x.created_at desc limit 1),'hold',public.finance_student_hold_status(st.id)) order by c.level_order,st.last_name,st.first_name) from public.finance_fee_account_balances b join public.students st on st.id=b.student_id join public.classes c on c.id=b.class_id join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id) and (target_term_id is null or b.term_id=target_term_id) and (target_class_id is null or b.class_id=target_class_id)),'[]'::jsonb),
  'hold_policy',(select to_jsonb(p) from public.finance_hold_policy p where id=1),
  'staff',case when public.current_app_role()='system_admin' then coalesce((select jsonb_agg(to_jsonb(a) order by lower(a.full_name)) from public.accounts_office_staff a where a.deleted_at is null),'[]'::jsonb) else '[]'::jsonb end
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_approve_payroll(target_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.finance_payroll_runs%rowtype;
begin perform public.finance_require_access('payroll',true); select * into r from public.finance_payroll_runs where id=target_run_id; if r.id is null or r.status<>'calculated' then raise exception 'Only calculated payroll can be approved'; end if; update public.finance_payroll_runs set status='approved',approved_by=auth.uid(),approved_at=now() where id=target_run_id returning * into r; return to_jsonb(r); end $function$
;

CREATE OR REPLACE FUNCTION public.finance_calculate_payroll(target_year integer, target_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare runrow public.finance_payroll_runs%rowtype; p record; item public.finance_payroll_items%rowtype; d date:=make_date(target_year,target_month,1); base numeric; allowances numeric; deductions numeric; ssnit numeric; taxv numeric; gross numeric; taxable numeric; loan_total numeric; rule record; loan record; ratev numeric; cnt int:=0;
begin
 perform public.finance_require_access('payroll',true);
 if target_year not between 2000 and 2200 or target_month not between 1 and 12 then raise exception 'Payroll period is invalid'; end if;
 insert into public.finance_payroll_runs(payroll_year,payroll_month,status,created_by) values(target_year,target_month,'draft',auth.uid()) on conflict(payroll_year,payroll_month) do update set updated_at=now() returning * into runrow;
 if runrow.status in ('approved','paid','locked') then raise exception 'Approved or paid payroll cannot be recalculated'; end if;
 for p in select pp.*,t.first_name,t.middle_name,t.last_name,g.basic_salary grade_salary from public.finance_payroll_profiles pp join public.teachers t on t.id=pp.teacher_id and t.active and t.deleted_at is null left join public.finance_salary_grades g on g.id=pp.salary_grade_id where pp.active loop
   base:=coalesce(p.basic_salary_override,p.grade_salary,0); allowances:=0; deductions:=0;
   for rule in select * from public.finance_payroll_rules where active and effective_from<=d and (effective_to is null or effective_to>=d) and rule_type in ('allowance','deduction') order by rule_code loop
     ratev:=base*public.finance_effective_rate(rule.rate)+coalesce(rule.fixed_amount,0);
     if rule.rule_type='allowance' then allowances:=allowances+ratev; else deductions:=deductions+ratev; end if;
   end loop;
   gross:=round(base+allowances,2);
   select round(gross*public.finance_effective_rate(r.rate)+coalesce(r.fixed_amount,0),2) into ssnit from public.finance_payroll_rules r where r.rule_type='ssnit_employee' and r.active and r.effective_from<=d and (r.effective_to is null or r.effective_to>=d) order by r.effective_from desc,r.created_at desc limit 1; ssnit:=coalesce(ssnit,0);
   taxable:=greatest(gross-ssnit,0); taxv:=public.finance_compute_tax(taxable,d); loan_total:=0;
   for loan in select l.*,public.finance_loan_balance(l.id) remaining from public.finance_teacher_loans l where l.teacher_id=p.teacher_id and l.status='active' and l.start_date<=d loop loan_total:=loan_total+least(loan.monthly_deduction,loan.remaining); end loop;
   insert into public.finance_payroll_items(run_id,teacher_id,payroll_profile_id,basic_salary,allowances,ssnit_employee,tax_amount,loan_deductions,other_deductions,gross_salary,total_deductions,net_salary,payment_status)
   values(runrow.id,p.teacher_id,p.id,base,round(allowances,2),ssnit,taxv,round(loan_total,2),round(deductions,2),gross,round(ssnit+taxv+loan_total+deductions,2),greatest(round(gross-(ssnit+taxv+loan_total+deductions),2),0),'unpaid')
   on conflict(run_id,teacher_id) do update set payroll_profile_id=excluded.payroll_profile_id,basic_salary=excluded.basic_salary,allowances=excluded.allowances,ssnit_employee=excluded.ssnit_employee,tax_amount=excluded.tax_amount,loan_deductions=excluded.loan_deductions,other_deductions=excluded.other_deductions,gross_salary=excluded.gross_salary,total_deductions=excluded.total_deductions,net_salary=excluded.net_salary,updated_at=now() returning * into item;
   delete from public.finance_payroll_item_lines where payroll_item_id=item.id;
   for rule in select * from public.finance_payroll_rules where active and effective_from<=d and (effective_to is null or effective_to>=d) and rule_type in ('allowance','deduction') order by rule_code loop ratev:=round(base*public.finance_effective_rate(rule.rate)+coalesce(rule.fixed_amount,0),2); if ratev>0 then insert into public.finance_payroll_item_lines(payroll_item_id,line_type,description,amount,source_key,created_by) values(item.id,rule.rule_type,rule.name,ratev,'rule:'||rule.id::text,auth.uid()); end if; end loop;
   if ssnit>0 then insert into public.finance_payroll_item_lines(payroll_item_id,line_type,description,amount,source_key,created_by) values(item.id,'ssnit','SSNIT employee contribution',ssnit,'ssnit',auth.uid()); end if;
   if taxv>0 then insert into public.finance_payroll_item_lines(payroll_item_id,line_type,description,amount,source_key,created_by) values(item.id,'tax','Income tax',taxv,'tax',auth.uid()); end if;
   for loan in select l.*,public.finance_loan_balance(l.id) remaining from public.finance_teacher_loans l where l.teacher_id=p.teacher_id and l.status='active' and l.start_date<=d loop ratev:=least(loan.monthly_deduction,loan.remaining); if ratev>0 then insert into public.finance_payroll_item_lines(payroll_item_id,loan_id,line_type,description,amount,source_key,created_by) values(item.id,loan.id,'loan','School loan '||loan.reference_no::text,ratev,'loan:'||loan.id::text,auth.uid()); end if; end loop;
   cnt:=cnt+1;
 end loop;
 update public.finance_payroll_runs set status='calculated',updated_at=now() where id=runrow.id returning * into runrow;
 insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'finance_payroll_runs',runrow.id,'PAYROLL_CALCULATED',jsonb_build_object('year',target_year,'month',target_month,'items',cnt),'Monthly payroll calculated');
 return jsonb_build_object('run',to_jsonb(runrow),'item_count',cnt);
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_class_fee_statement(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('finance_statements',false,array['accountant']);
 if target_academic_year_id is null or target_term_id is null or target_class_id is null then raise exception 'Academic year, term and class are required'; end if;
 return jsonb_build_object(
  'academic_year',(select name from public.academic_years where id=target_academic_year_id),
  'term',(select name from public.terms where id=target_term_id),
  'class',(select name from public.classes where id=target_class_id),
  'rows',coalesce((select jsonb_agg(jsonb_build_object(
    'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,
    'account_id',b.id,'due',coalesce(b.term_fee_amount,0),'paid',coalesce(b.amount_paid,0),'balance',coalesce(b.balance,0),
    'status',coalesce(b.status,case when fs.id is null then 'not_configured' else 'unpaid' end),'balance_remaining',coalesce(b.balance_remaining,false),
    'hold',public.finance_student_hold_status(s.id)
  ) order by s.last_name,s.first_name)
  from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null
  left join public.finance_fee_account_balances b on b.student_id=s.id and b.term_id=target_term_id
  left join public.finance_fee_schedules fs on fs.academic_year_id=target_academic_year_id and fs.term_id=target_term_id and fs.class_id=target_class_id and fs.active
  where e.academic_year_id=target_academic_year_id and e.class_id=target_class_id and e.active and e.deleted_at is null),'[]'::jsonb)
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_clear_guardian_contact_history()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleared_count integer:=0;
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  with deleted as (
    delete from public.finance_guardian_contact_events
    where true
    returning 1
  )
  select count(*)::integer into cleared_count from deleted;

  return jsonb_build_object(
    'cleared',cleared_count,
    'cleared_at',now()
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_clear_hold_override(target_student_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin perform public.finance_require_access('financial_holds',true); perform public.finance_require_capability('financial_hold'); if btrim(coalesce(reason_text,''))='' then raise exception 'A reason is required'; end if; update public.finance_hold_overrides set active=false,updated_at=now() where student_id=target_student_id and active; insert into public.audit_log(actor_id,table_name,record_id,action,reason) values(auth.uid(),'finance_hold_overrides',target_student_id,'FINANCIAL_HOLD_OVERRIDE_CLEARED',reason_text); return public.finance_student_hold_status(target_student_id); end $function$
;

CREATE OR REPLACE FUNCTION public.finance_compute_tax(taxable_amount numeric, target_date date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r public.finance_payroll_rules%rowtype; bracket jsonb; lower_bound numeric; upper_bound numeric; rate_value numeric; portion numeric; total numeric:=0;
begin
  if coalesce(taxable_amount,0)<=0 then return 0; end if;
  select * into r from public.finance_payroll_rules
   where rule_type='tax' and active and effective_from<=target_date and (effective_to is null or effective_to>=target_date)
   order by effective_from desc,created_at desc limit 1;
  if r.id is null then return 0; end if;
  if jsonb_typeof(r.rule_json->'brackets')='array' then
    for bracket in select value from jsonb_array_elements(r.rule_json->'brackets') loop
      lower_bound:=greatest(coalesce((bracket->>'from')::numeric,0),0);
      upper_bound:=case when nullif(bracket->>'to','') is null then null else (bracket->>'to')::numeric end;
      rate_value:=public.finance_effective_rate(coalesce((bracket->>'rate')::numeric,0));
      if taxable_amount>lower_bound then
        portion:=case when upper_bound is null then taxable_amount-lower_bound else greatest(least(taxable_amount,upper_bound)-lower_bound,0) end;
        total:=total+portion*rate_value;
      end if;
    end loop;
    total:=total+coalesce(r.fixed_amount,0);
  else
    total:=taxable_amount*public.finance_effective_rate(r.rate)+coalesce(r.fixed_amount,0);
  end if;
  return round(greatest(total,0),2);
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_deactivate_accounts_staff(target_staff_id uuid, reason_text text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare linked uuid;
begin
 perform public.finance_require_access('finance_fees',true,array['system_admin']);
 select profile_id into linked from public.accounts_office_staff where id=target_staff_id and deleted_at is null;
 if not found then raise exception 'Accounts Office staff record was not found'; end if;
 update public.accounts_office_staff set active=false,deleted_at=now() where id=target_staff_id;
 if linked is not null then update public.profiles set active=false,updated_at=now() where id=linked and role='accounts_office'; end if;
 insert into public.audit_log(actor_id,table_name,record_id,action,reason) values(auth.uid(),'accounts_office_staff',target_staff_id,'FINANCE_STAFF_DEACTIVATED',coalesce(nullif(reason_text,''),'Accounts Office staff deactivated'));
 return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_effective_rate(raw_rate numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$ select case when raw_rate is null then 0 when raw_rate>1 then raw_rate/100 else raw_rate end $function$
;

CREATE OR REPLACE FUNCTION public.finance_feature_enabled(feature_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((public.license_effective_entitlement()->'plan'->'feature_flags'->>feature_code)::boolean,false)
$function$
;

CREATE OR REPLACE FUNCTION public.finance_generate_invoice_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin
  select coalesce(
    nullif(upper(split_part(coalesce(tenant_code,''),'-',1)),''),
    nullif(regexp_replace(upper(coalesce(identifier_root,'')),'[^A-Z].*$','','g'),''),
    'SCH'
  ) into root
  from public.school_settings
  limit 1;
  n:=nextval('public.finance_invoice_seq');
  return root||'-INV-'||extract(year from current_date)::int||'-'||lpad(n::text,6,'0');
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_generate_payroll_number()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin select coalesce(nullif(identifier_root,''),regexp_replace(upper(school_name),'[^A-Z]','','g'),'SCH') into root from public.school_settings limit 1; n:=nextval('public.finance_payroll_no_seq'); return left(root,8)||'-PAY-'||lpad(n::text,6,'0'); end $function$
;

CREATE OR REPLACE FUNCTION public.finance_generate_receipt_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin
  select coalesce(
    nullif(upper(split_part(coalesce(tenant_code,''),'-',1)),''),
    nullif(regexp_replace(upper(coalesce(identifier_root,'')),'[^A-Z].*$','','g'),''),
    'SCH'
  ) into root
  from public.school_settings
  limit 1;
  n:=nextval('public.finance_receipt_seq');
  return root||'-RCP-'||extract(year from current_date)::int||'-'||lpad(n::text,6,'0');
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_generate_staff_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare root text; n bigint;
begin select coalesce(nullif(identifier_root,''),regexp_replace(upper(school_name),'[^A-Z]','','g'),'SCH') into root from public.school_settings limit 1; n:=nextval('public.accounts_office_staff_no_seq'); return left(root,8)||'AOS'||lpad(n::text,6,'0'); end $function$
;

CREATE OR REPLACE FUNCTION public.finance_guardian_contact_history(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, search_text text DEFAULT NULL::text, page_number integer DEFAULT 1, page_size integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  page_no integer:=greatest(coalesce(page_number,1),1);
  size_no integer:=least(greatest(coalesce(page_size,100),1),200);
  query_value text:=lower(trim(coalesce(search_text,'')));
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  return jsonb_build_object(
    'total',(
      select count(*)
      from public.finance_guardian_contact_events e
      where (target_academic_year_id is null or e.academic_year_id=target_academic_year_id)
        and (target_term_id is null or e.term_id=target_term_id)
        and (query_value='' or lower(concat_ws(' ',e.guardian_name,e.guardian_phone,e.guardian_email,e.channel,e.message_text)) like '%'||query_value||'%')
    ),
    'rows',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at desc)
      from (
        select
          e.id,e.guardian_key,e.guardian_name,e.guardian_phone,e.guardian_email,
          e.channel,e.action_state,e.academic_year_id,y.name::text as academic_year_name,
          e.term_id,t.name::text as term_name,e.class_id,c.name::text as class_name,
          e.child_count,e.total_outstanding,e.children,e.message_text,e.created_at,
          coalesce(p.full_name,'Accountant') as actor_name
        from public.finance_guardian_contact_events e
        left join public.academic_years y on y.id=e.academic_year_id
        left join public.terms t on t.id=e.term_id
        left join public.classes c on c.id=e.class_id
        left join public.profiles p on p.id=e.created_by
        where (target_academic_year_id is null or e.academic_year_id=target_academic_year_id)
          and (target_term_id is null or e.term_id=target_term_id)
          and (query_value='' or lower(concat_ws(' ',e.guardian_name,e.guardian_phone,e.guardian_email,e.channel,e.message_text)) like '%'||query_value||'%')
        order by e.created_at desc
        limit size_no offset (page_no-1)*size_no
      ) q
    ),'[]'::jsonb)
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_guardian_follow_up(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, status_filter text DEFAULT 'outstanding'::text, search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  yid uuid;
  tid uuid;
  filter_value text:=lower(trim(coalesce(status_filter,'outstanding')));
  query_value text:=lower(trim(coalesce(search_text,'')));
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  if filter_value not in ('outstanding','partial_paid','unpaid','fully_paid','all') then
    raise exception 'Invalid payment status filter';
  end if;

  select y.id into yid
  from public.academic_years y
  where y.deleted_at is null
    and (target_academic_year_id is null or y.id=target_academic_year_id)
  order by case when y.id=target_academic_year_id then 0 else 1 end,y.is_active desc,y.start_date desc
  limit 1;

  if yid is null then
    return jsonb_build_object(
      'period',jsonb_build_object('academic_year_id',null,'academic_year_name',null,'term_id',null,'term_name',null),
      'metrics',jsonb_build_object('guardians',0,'children',0,'outstanding',0,'missing_phone',0,'missing_guardian_contact',0),
      'rows','[]'::jsonb
    );
  end if;

  select t.id into tid
  from public.terms t
  where t.academic_year_id=yid and t.deleted_at is null
    and (target_term_id is null or t.id=target_term_id)
  order by case when t.id=target_term_id then 0 else 1 end,t.is_active desc,t.sequence desc
  limit 1;

  return (
    with selected_enrollments as (
      select distinct on (e.student_id)
        e.student_id,e.class_id,e.academic_year_id,e.active,e.updated_at
      from public.enrollments e
      where e.academic_year_id=yid
        and e.deleted_at is null
        and (target_class_id is null or e.class_id=target_class_id)
      order by e.student_id,e.active desc,e.updated_at desc
    ),
    per_student as (
      select
        s.id as student_id,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) as student_name,
        s.admission_no::text as admission_no,
        nullif(trim(s.guardian_name),'') as guardian_name,
        nullif(trim(s.guardian_phone),'') as guardian_phone,
        nullif(trim(s.guardian_email),'') as guardian_email,
        c.id as class_id,
        c.name::text as class_name,
        c.level_order,
        coalesce(sum(b.term_fee_amount),0)::numeric as due,
        coalesce(sum(b.amount_paid),0)::numeric as paid,
        coalesce(sum(b.balance),0)::numeric as balance,
        case
          when count(b.id)=0 then 'not_configured'
          when coalesce(sum(b.balance),0)<=0 then 'fully_paid'
          when coalesce(sum(b.amount_paid),0)>0 then 'partial_paid'
          else 'unpaid'
        end as account_status
      from selected_enrollments e
      join public.students s on s.id=e.student_id and s.deleted_at is null
      join public.classes c on c.id=e.class_id and c.deleted_at is null
      left join public.finance_fee_account_balances b
        on b.student_id=s.id
       and b.academic_year_id=yid
       and b.term_id=tid
       and b.class_id=e.class_id
      group by s.id,s.first_name,s.middle_name,s.last_name,s.admission_no,s.guardian_name,s.guardian_phone,s.guardian_email,c.id,c.name,c.level_order
    ),
    tagged as (
      select p.*,
        case
          when regexp_replace(coalesce(p.guardian_phone,''),'[^0-9]','','g')<>'' then 'phone:'||regexp_replace(p.guardian_phone,'[^0-9]','','g')
          when nullif(lower(trim(coalesce(p.guardian_email,''))),'') is not null then 'email:'||lower(trim(p.guardian_email))
          else 'name:'||lower(trim(coalesce(p.guardian_name,'Parent / Guardian')))
        end as guardian_key
      from per_student p
      where p.guardian_name is not null or p.guardian_phone is not null or p.guardian_email is not null
    ),
    grouped as (
      select
        guardian_key,
        coalesce(max(guardian_name),'Parent / Guardian') as guardian_name,
        max(guardian_phone) as guardian_phone,
        max(guardian_email) as guardian_email,
        count(*)::integer as child_count,
        sum(greatest(balance,0))::numeric as total_outstanding,
        sum(due)::numeric as total_due,
        sum(paid)::numeric as total_paid,
        bool_or(balance>0) as has_outstanding,
        bool_or(account_status='partial_paid') as has_partial,
        bool_or(account_status='unpaid') as has_unpaid,
        bool_or(account_status='fully_paid') as has_fully_paid,
        bool_or(account_status='not_configured') as has_not_configured,
        lower(concat_ws(' ',
          coalesce(max(guardian_name),''),
          coalesce(max(guardian_phone),''),
          coalesce(max(guardian_email),''),
          string_agg(student_name||' '||coalesce(admission_no,'')||' '||class_name,' ')
        )) as search_blob,
        jsonb_agg(jsonb_build_object(
          'student_id',student_id,
          'student',student_name,
          'admission_no',admission_no,
          'class_id',class_id,
          'class_name',class_name,
          'due',due,
          'paid',paid,
          'balance',balance,
          'status',account_status
        ) order by level_order,student_name) as children
      from tagged
      group by guardian_key
    ),
    filtered as (
      select g.*,
        case
          when g.total_outstanding>0 then 'outstanding'
          when g.has_fully_paid then 'fully_paid'
          when g.has_not_configured then 'not_configured'
          else 'clear'
        end as group_status,
        (select e.created_at from public.finance_guardian_contact_events e where e.guardian_key=g.guardian_key order by e.created_at desc limit 1) as last_contact_at,
        (select e.channel from public.finance_guardian_contact_events e where e.guardian_key=g.guardian_key order by e.created_at desc limit 1) as last_contact_channel
      from grouped g
      where (query_value='' or g.search_blob like '%'||query_value||'%')
        and (
          filter_value='all'
          or (filter_value='outstanding' and g.has_outstanding)
          or (filter_value='partial_paid' and g.has_partial)
          or (filter_value='unpaid' and g.has_unpaid)
          or (filter_value='fully_paid' and g.has_fully_paid and not g.has_outstanding)
        )
    )
    select jsonb_build_object(
      'period',jsonb_build_object(
        'academic_year_id',yid,
        'academic_year_name',(select y.name::text from public.academic_years y where y.id=yid),
        'term_id',tid,
        'term_name',(select t.name::text from public.terms t where t.id=tid),
        'class_id',target_class_id,
        'class_name',(select c.name::text from public.classes c where c.id=target_class_id)
      ),
      'metrics',jsonb_build_object(
        'guardians',coalesce((select count(*) from filtered),0),
        'children',coalesce((select sum(child_count) from filtered),0),
        'outstanding',coalesce((select sum(total_outstanding) from filtered),0),
        'missing_phone',coalesce((select count(*) from filtered where guardian_phone is null),0),
        'missing_guardian_contact',coalesce((select count(*) from per_student where guardian_name is null and guardian_phone is null and guardian_email is null),0)
      ),
      'rows',coalesce((
        select jsonb_agg(jsonb_build_object(
          'guardian_key',f.guardian_key,
          'guardian_name',f.guardian_name,
          'guardian_phone',f.guardian_phone,
          'guardian_email',f.guardian_email,
          'child_count',f.child_count,
          'total_due',f.total_due,
          'total_paid',f.total_paid,
          'total_outstanding',f.total_outstanding,
          'status',f.group_status,
          'last_contact_at',f.last_contact_at,
          'last_contact_channel',f.last_contact_channel,
          'children',f.children
        ) order by f.total_outstanding desc,lower(f.guardian_name))
        from filtered f
      ),'[]'::jsonb)
    )
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_immutable_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if tg_op='DELETE'
     and current_setting('edusentia.finance_test_purge',true)='on'
     and auth.uid() is not null
     and coalesce(public.current_app_role()::text,'')='system_admin' then
    return old;
  end if;
  raise exception 'Posted finance ledger rows are immutable. Use a reversal or adjustment.' using errcode='42501';
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_invoice_detail(target_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r text:=public.current_app_role()::text;
  inv public.finance_fee_invoices%rowtype;
  allowed boolean:=false;
begin
  select * into inv from public.finance_fee_invoices where id=target_invoice_id;
  if inv.id is null then raise exception 'Invoice was not found'; end if;

  if r in ('accountant','system_admin') then
    perform public.finance_require_access('finance_statements',false,array['accountant','system_admin']);
    allowed:=true;
  elsif r='parent_guardian' then
    allowed:=exists(select 1 from public.guardian_links where auth_user_id=auth.uid() and student_id=inv.student_id);
  elsif r='student' then
    allowed:=exists(select 1 from public.students where id=inv.student_id and profile_id=auth.uid() and deleted_at is null);
  end if;
  if not allowed then raise exception 'Access denied' using errcode='42501'; end if;

  return jsonb_build_object(
    'school',coalesce((select jsonb_build_object('school_name',school_name,'motto',motto,'address',address,'phone',phone,'email',email,'website',website,'logo_url',logo_url,'tenant_code',tenant_code,'report_footer',report_footer) from public.school_settings limit 1),'{}'::jsonb),
    'invoice',jsonb_build_object('id',inv.id,'invoice_no',inv.invoice_no,'issued_at',inv.issued_at,'description',inv.description,'issued_amount',inv.issued_amount,'due_date',inv.due_date),
    'student',(select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)) from public.students s where s.id=inv.student_id),
    'account',(select jsonb_build_object('academic_year_name',y.name,'term_name',t.name,'class_name',c.name,'paid',b.amount_paid,'balance',b.balance,'status',b.status)
               from public.finance_fee_account_balances b join public.academic_years y on y.id=b.academic_year_id join public.terms t on t.id=b.term_id join public.classes c on c.id=b.class_id where b.id=inv.account_id),
    'allocations',coalesce((select jsonb_agg(jsonb_build_object('transaction_id',x.id,'entry_type',x.entry_type,'receipt_no',x.receipt_no,'transaction_date',x.transaction_date,'method',x.payment_method,'reference',x.payment_reference,'amount',a.amount,'notes',x.notes) order by x.transaction_date,x.created_at)
                            from public.finance_fee_allocations a join public.finance_fee_transactions x on x.id=a.transaction_id where a.account_id=inv.account_id),'[]'::jsonb)
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_invoice_register(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.finance_require_access('finance_fees',false,array['accountant','system_admin']);
  return jsonb_build_object(
    'rows',coalesce((
      select jsonb_agg(jsonb_build_object(
        'invoice_id',i.id,
        'invoice_no',i.invoice_no,
        'issued_at',i.issued_at,
        'description',i.description,
        'student_id',s.id,
        'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'admission_no',s.admission_no,
        'academic_year_id',b.academic_year_id,
        'academic_year_name',y.name,
        'term_id',b.term_id,
        'term_name',t.name,
        'class_id',b.class_id,
        'class_name',c.name,
        'issued_amount',i.issued_amount,
        'due_date',i.due_date,
        'paid',b.amount_paid,
        'balance',b.balance,
        'status',b.status
      ) order by y.start_date desc,t.sequence desc,c.level_order,c.name,s.last_name,s.first_name)
      from public.finance_fee_invoices i
      join public.finance_fee_account_balances b on b.id=i.account_id
      join public.students s on s.id=i.student_id
      join public.academic_years y on y.id=b.academic_year_id
      join public.terms t on t.id=b.term_id
      join public.classes c on c.id=b.class_id
      where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id)
        and (target_term_id is null or b.term_id=target_term_id)
        and (target_class_id is null or b.class_id=target_class_id)
    ),'[]'::jsonb)
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_loan_balance(target_loan_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select greatest(l.principal_amount-coalesce((select sum(pl.amount) from public.finance_payroll_item_lines pl join public.finance_payroll_items pi on pi.id=pl.payroll_item_id where pl.loan_id=l.id and pl.line_type='loan' and pi.payment_status='paid'),0),0)::numeric
 from public.finance_teacher_loans l where l.id=target_loan_id
$function$
;

CREATE OR REPLACE FUNCTION public.finance_lock_payroll(target_run_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin perform public.finance_require_access('payroll',true); if not exists(select 1 from public.finance_payroll_runs where id=target_run_id and status='paid') then raise exception 'Only fully paid payroll can be locked'; end if; update public.finance_payroll_runs set status='locked',updated_at=now() where id=target_run_id; return true; end $function$
;

CREATE OR REPLACE FUNCTION public.finance_log_guardian_contact(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  channel_value text:=lower(trim(coalesce(payload->>'channel','')));
  state_value text:=lower(trim(coalesce(payload->>'action_state','opened')));
  event_id uuid;
  guardian_name_value text:=trim(coalesce(payload->>'guardian_name',''));
begin
  perform public.finance_require_access('finance_statements',false,array['accountant']);

  if channel_value not in ('sms','whatsapp','call','copy') then
    raise exception 'Invalid contact channel';
  end if;
  if state_value not in ('opened','copied') then
    raise exception 'Invalid contact action state';
  end if;
  if nullif(trim(coalesce(payload->>'guardian_key','')),'') is null then
    raise exception 'Guardian reference is required';
  end if;
  if guardian_name_value='' then guardian_name_value:='Parent / Guardian'; end if;

  insert into public.finance_guardian_contact_events(
    guardian_key,guardian_name,guardian_phone,guardian_email,channel,action_state,
    academic_year_id,term_id,class_id,child_count,total_outstanding,children,message_text,created_by
  ) values (
    trim(payload->>'guardian_key'),
    guardian_name_value,
    nullif(trim(coalesce(payload->>'guardian_phone','')),''),
    nullif(trim(coalesce(payload->>'guardian_email','')),''),
    channel_value,
    state_value,
    nullif(payload->>'academic_year_id','')::uuid,
    nullif(payload->>'term_id','')::uuid,
    nullif(payload->>'class_id','')::uuid,
    greatest(coalesce((payload->>'child_count')::integer,0),0),
    coalesce((payload->>'total_outstanding')::numeric,0),
    case when jsonb_typeof(payload->'children')='array' then payload->'children' else '[]'::jsonb end,
    nullif(left(coalesce(payload->>'message_text',''),4000),''),
    auth.uid()
  ) returning id into event_id;

  return jsonb_build_object('id',event_id,'recorded',true,'created_at',now());
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_mark_salary_paid(target_item_id uuid, payment_reference_text text, payment_date_value date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare i public.finance_payroll_items%rowtype; r public.finance_payroll_runs%rowtype;
begin
  perform public.finance_require_payroll_access(true);
  if btrim(coalesce(payment_reference_text,''))='' then raise exception 'A salary payment reference is required'; end if;
  select * into i from public.finance_payroll_items where id=target_item_id;
  if i.id is null then raise exception 'Payroll item was not found'; end if;
  select * into r from public.finance_payroll_runs where id=i.run_id;
  if r.status not in ('approved','paid') then raise exception 'Payroll must be approved before salary payment'; end if;
  if i.payment_status='paid' then return to_jsonb(i); end if;
  update public.finance_payroll_items
  set payment_status='paid',paid_at=(coalesce(payment_date_value,current_date)::timestamp at time zone 'UTC'),payment_reference=btrim(payment_reference_text),updated_at=now()
  where id=target_item_id returning * into i;
  if not exists(select 1 from public.finance_payroll_items where run_id=i.run_id and payment_status<>'paid') then
    update public.finance_payroll_runs set status='paid',pay_date=coalesce(payment_date_value,current_date),updated_at=now() where id=i.run_id;
  end if;
  update public.finance_teacher_loans l set status='settled',updated_at=now()
  where l.teacher_id=i.teacher_id and l.status='active' and public.finance_loan_balance(l.id)<=0;
  insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason)
  values(auth.uid(),'finance_payroll_items',i.id,'SALARY_PAYMENT_RECORDED',jsonb_build_object('payment_reference',i.payment_reference,'paid_at',i.paid_at,'net_salary',i.net_salary),'Monthly salary payment recorded');
  return to_jsonb(i);
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_my_children_fees()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 if public.current_app_role()<>'parent_guardian' then raise exception 'Parent or guardian access required' using errcode='42501'; end if;
 if not public.finance_feature_enabled('finance_statements') then return jsonb_build_object('children','[]'::jsonb); end if;
 return jsonb_build_object('children',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'class_name',coalesce(c.name,''),'statement',public.finance_student_statement(s.id)) order by s.last_name,s.first_name) from public.guardian_links gl join public.students s on s.id=gl.student_id and s.deleted_at is null left join lateral(select e.class_id from public.enrollments e where e.student_id=s.id and e.active and e.deleted_at is null order by e.updated_at desc limit 1) ce on true left join public.classes c on c.id=ce.class_id where gl.auth_user_id=auth.uid()),'[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_my_invoices()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r text:=public.current_app_role()::text;
begin
  if r not in ('parent_guardian','student') then raise exception 'Student or parent/guardian access required' using errcode='42501'; end if;
  if not public.finance_feature_enabled('finance_statements') then return jsonb_build_object('invoices','[]'::jsonb); end if;
  return jsonb_build_object(
    'invoices',coalesce((
      select jsonb_agg(jsonb_build_object(
        'invoice_id',i.id,'invoice_no',i.invoice_no,'issued_at',i.issued_at,'description',i.description,
        'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,
        'academic_year_name',y.name,'term_name',t.name,'class_name',c.name,
        'issued_amount',i.issued_amount,'due_date',i.due_date,'paid',b.amount_paid,'balance',b.balance,'status',b.status
      ) order by y.start_date desc,t.sequence desc,s.last_name,s.first_name)
      from public.finance_fee_invoices i
      join public.finance_fee_account_balances b on b.id=i.account_id
      join public.students s on s.id=i.student_id
      join public.academic_years y on y.id=i.academic_year_id
      join public.terms t on t.id=i.term_id
      join public.classes c on c.id=i.class_id
      where (r='student' and s.profile_id=auth.uid() and s.deleted_at is null)
         or (r='parent_guardian' and exists(select 1 from public.guardian_links gl where gl.auth_user_id=auth.uid() and gl.student_id=s.id))
    ),'[]'::jsonb)
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.finance_payment_candidates(target_academic_year_id uuid, target_term_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('finance_fees',false,array['accountant']);
 return jsonb_build_object('students',coalesce((select jsonb_agg(jsonb_build_object('student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'account_id',b.id,'term_fee',coalesce(b.term_fee_amount,0),'paid',coalesce(b.amount_paid,0),'balance',coalesce(b.balance,0),'status',coalesce(b.status,'not_configured'),'total_outstanding',public.finance_student_outstanding(s.id)) order by s.last_name,s.first_name)
 from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null left join public.finance_fee_account_balances b on b.student_id=s.id and b.term_id=target_term_id where e.academic_year_id=target_academic_year_id and e.class_id=target_class_id and e.active and e.deleted_at is null),'[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_payment_register(target_academic_year_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rows_json jsonb; school_json jsonb;
begin
 perform public.finance_require_access('finance_fees',false,array['accountant']);
 select coalesce((
   with eligible as (
     select distinct tx.id
     from public.finance_fee_transactions tx
     join public.finance_fee_allocations al on al.transaction_id=tx.id
     join public.finance_fee_account_balances b on b.id=al.account_id
     where tx.entry_type='payment'
       and (target_academic_year_id is null or b.academic_year_id=target_academic_year_id)
       and (target_term_id is null or b.term_id=target_term_id)
       and (target_class_id is null or b.class_id=target_class_id)
   ), receipt_rows as (
     select tx.id transaction_id,tx.receipt_no,tx.credit_amount transaction_amount,tx.student_id,
       concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student,s.admission_no,
       string_agg(distinct c.name::text,', ' order by c.name::text) class_name,
       string_agg(distinct y.name::text,', ' order by y.name::text) academic_year_name,
       string_agg(distinct t.name::text,', ' order by t.name::text) term_name,
       coalesce(sum(b.term_fee_amount),0) due,
       coalesce(sum(al.amount),0) allocated_paid,
       public.finance_student_outstanding(s.id) balance,
       case when public.finance_student_outstanding(s.id)<=0 then 'fully_paid' else 'partial_paid' end status,
       tx.payment_method method,tx.payment_reference reference,tx.transaction_date,
       coalesce(nullif(p.full_name,''),'Accounts Office') received_by,
       'accountant'::text received_by_role,
       coalesce(nullif(p.full_name,''),'System Administrator') recorded_by,
       coalesce(p.role::text,'system_admin') recorded_by_role,
       exists(select 1 from public.finance_fee_transactions rv where rv.reversal_of_id=tx.id) reversed,
       tx.created_at
     from eligible e
     join public.finance_fee_transactions tx on tx.id=e.id
     join public.students s on s.id=tx.student_id
     left join public.profiles p on p.id=tx.created_by
     join public.finance_fee_allocations al on al.transaction_id=tx.id
     join public.finance_fee_account_balances b on b.id=al.account_id
     join public.classes c on c.id=b.class_id
     join public.academic_years y on y.id=b.academic_year_id
     join public.terms t on t.id=b.term_id
     group by tx.id,tx.receipt_no,tx.credit_amount,tx.student_id,s.id,s.first_name,s.middle_name,s.last_name,s.admission_no,tx.payment_method,tx.payment_reference,tx.transaction_date,p.full_name,p.role,tx.created_at
   )
   select jsonb_agg(to_jsonb(r) order by r.transaction_date desc,r.created_at desc,r.student)
   from receipt_rows r
 ),'[]'::jsonb) into rows_json;
 select jsonb_build_object(
   'school_name',school_name,'motto',motto,'address',address,'phone',phone,'email',email,'website',website,
   'logo_url',logo_url,'tenant_code',tenant_code,'head_name',head_name,'report_footer',report_footer
 ) into school_json from public.school_settings limit 1;
 return jsonb_build_object('rows',rows_json,'school',coalesce(school_json,'{}'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_payroll_console(target_year integer DEFAULT NULL::integer, target_month integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 perform public.finance_require_access('payroll',false);
 return jsonb_build_object(
  'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'staff_no',t.staff_no,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'has_payroll_profile',exists(select 1 from public.finance_payroll_profiles p where p.teacher_id=t.id)) order by t.last_name,t.first_name) from public.teachers t where t.active and t.deleted_at is null),'[]'::jsonb),
  'salary_grades',coalesce((select jsonb_agg(to_jsonb(g) order by lower(g.code::text)) from public.finance_salary_grades g),'[]'::jsonb),
  'profiles',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no,'grade_code',g.code,'grade_salary',g.basic_salary) order by t.last_name,t.first_name) from public.finance_payroll_profiles p join public.teachers t on t.id=p.teacher_id left join public.finance_salary_grades g on g.id=p.salary_grade_id),'[]'::jsonb),
  'rules',case when public.finance_feature_enabled('payroll_statutory') then coalesce((select jsonb_agg(to_jsonb(r) order by r.rule_type,r.effective_from desc) from public.finance_payroll_rules r),'[]'::jsonb) else '[]'::jsonb end,
  'loans',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'remaining_balance',public.finance_loan_balance(l.id)) order by l.created_at desc) from public.finance_teacher_loans l join public.teachers t on t.id=l.teacher_id),'[]'::jsonb),
  'runs',coalesce((select jsonb_agg(to_jsonb(r) order by r.payroll_year desc,r.payroll_month desc) from public.finance_payroll_runs r where (target_year is null or r.payroll_year=target_year) and (target_month is null or r.payroll_month=target_month)),'[]'::jsonb),
  'items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no,'payroll_number',p.payroll_number,'year',r.payroll_year,'month',r.payroll_month,'run_status',r.status,'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.line_type,l.description) from public.finance_payroll_item_lines l where l.payroll_item_id=i.id),'[]'::jsonb)) order by t.last_name,t.first_name) from public.finance_payroll_items i join public.finance_payroll_runs r on r.id=i.run_id join public.teachers t on t.id=i.teacher_id left join public.finance_payroll_profiles p on p.id=i.payroll_profile_id where (target_year is null or r.payroll_year=target_year) and (target_month is null or r.payroll_month=target_month)),'[]'::jsonb)
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.finance_portal_account_candidates()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
 if public.current_app_role()<>'system_admin' then raise exception 'Access denied' using errcode='42501'; end if;
 perform public.finance_require_access('finance_fees',false,array['system_admin']);
 return jsonb_build_object(
   'accounts_staff',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('portal_email',u.email,'portal_active',p.active,'must_change_password',p.must_change_password) order by lower(a.full_name)) from public.accounts_office_staff a left join public.profiles p on p.id=a.profile_id left join auth.users u on u.id=a.profile_id where a.deleted_at is null),'[]'::jsonb),
   'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'profile_id',s.profile_id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'class_id',e.class_id,'class_name',c.name,'portal_email',u.email,'portal_active',p.active,'must_change_password',p.must_change_password) order by c.level_order,s.last_name,s.first_name) from public.students s left join lateral(select x.class_id from public.enrollments x where x.student_id=s.id and x.active and x.deleted_at is null order by x.updated_at desc limit 1)e on true left join public.classes c on c.id=e.class_id left join public.profiles p on p.id=s.profile_id left join auth.users u on u.id=s.profile_id where s.deleted_at is null and s.status='active'),'[]'::jsonb)
 );
end $function$
;

SET check_function_bodies=on;
