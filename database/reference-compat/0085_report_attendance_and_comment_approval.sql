-- Report-card attendance and role-specific comment safeguards. Supabase reference remains unchanged.
-- Reconciled on existing and new Neon tenant databases.
BEGIN;

CREATE OR REPLACE FUNCTION public.attendance_counts_for_enrollment(target_enrollment_id uuid, target_term_id uuid)
 RETURNS TABLE(days_school_opened integer, days_present integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select count(distinct r.id) filter(where exists(select 1 from public.student_attendance_entries logged where logged.register_id=r.id))::integer,
    count(a.id) filter(where a.attendance_status in ('present','late'))::integer
  from public.enrollments e
  join public.class_attendance_registers r on r.class_id=e.class_id and r.term_id=target_term_id
  left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=e.id
  where e.id=target_enrollment_id
$function$
;

CREATE OR REPLACE FUNCTION public.sync_attendance_reports(target_term_id uuid, target_class_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare affected integer:=0;
begin
  perform set_config('app.report_write','on',true);
  update public.student_reports r
  set days_school_opened=counts.days_school_opened,
      days_present=least(counts.days_present,counts.days_school_opened),
      updated_at=now()
  from public.enrollments e
  cross join lateral public.attendance_counts_for_enrollment(e.id,target_term_id) counts
  where r.enrollment_id=e.id
    and r.term_id=target_term_id
    and e.class_id=target_class_id
    and r.deleted_at is null
    and r.status in ('draft','returned','submitted','class_reviewed');
  get diagnostics affected=row_count;
  return affected;
end $function$
;

CREATE OR REPLACE FUNCTION public.get_report_editor(target_report_id uuid DEFAULT NULL::uuid, target_enrollment_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  rid uuid:=target_report_id;
  enrollmentid uuid:=target_enrollment_id;
  termid uuid:=target_term_id;
  classid uuid;
  yearid uuid;
  report_json jsonb;
  student_json jsonb;
  canedit boolean;
  canfields boolean;
begin
  if rid is not null then
    if not public.can_view_report_internal(rid) then raise exception 'Access denied' using errcode='42501'; end if;
    select r.enrollment_id,r.term_id,e.class_id,e.academic_year_id,to_jsonb(r)
      into enrollmentid,termid,classid,yearid,report_json
    from public.student_reports r
    join public.enrollments e on e.id=r.enrollment_id
    where r.id=rid and r.deleted_at is null;
    if report_json is null then raise exception 'Report not found'; end if;
  else
    if public.current_app_role()::text not in ('system_admin','principal','class_teacher','subject_teacher') then
      raise exception 'Access denied' using errcode='42501';
    end if;
    select e.class_id,e.academic_year_id into classid,yearid
    from public.enrollments e where e.id=enrollmentid and e.deleted_at is null;
    if classid is null or not public.can_create_report_for_class_term(classid,termid) then raise exception 'Access denied' using errcode='42501'; end if;
    if not exists(select 1 from public.terms t where t.id=termid and t.academic_year_id=yearid and t.deleted_at is null) then
      raise exception 'Term and enrolment academic year do not match';
    end if;
    select to_jsonb(r) into report_json from public.student_reports r
    where r.enrollment_id=enrollmentid and r.term_id=termid and r.deleted_at is null;
    if report_json is not null then rid:=(report_json->>'id')::uuid;
    else
      report_json:=jsonb_build_object('id',null,'enrollment_id',enrollmentid,'term_id',termid,'status','draft','version',0,
        'days_school_opened',0,'days_present',0,'attitude','','conduct','','interest','','teacher_comment','','head_comment','',
        'promoted_to_class_id',null);
    end if;
  end if;

  select jsonb_build_object(
    'id',s.id,'admission_no',s.admission_no,'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
    'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'gender',s.gender,'date_of_birth',s.date_of_birth,'photo_url',s.photo_url,
    'class_id',e.class_id,'class_name',c.name,'academic_year_id',e.academic_year_id,'academic_year_name',y.name,'roll_number',e.roll_number,
    'term_name',t.name,'term_sequence',t.sequence,'next_term_begins',t.next_term_begins
  ) into student_json
  from public.enrollments e
  join public.students s on s.id=e.student_id
  join public.classes c on c.id=e.class_id
  join public.academic_years y on y.id=e.academic_year_id
  join public.terms t on t.id=termid
  where e.id=enrollmentid;

  canedit:=case when rid is null then public.can_create_report_for_class_term(classid,termid) else public.can_edit_report(rid) end;
  canfields:=(public.can_manage_class_report_fields_for_term(classid,termid)
    or (rid is not null and public.has_approved_report_correction(rid) and public.can_manage_class_report_fields_scope(classid,termid)))
    and coalesce(report_json->>'status','draft') in ('draft','returned','withdrawn');

  if coalesce(report_json->>'status','draft') in ('draft','returned','submitted','class_reviewed') then
    report_json := report_json || (
      select jsonb_build_object('days_school_opened',ac.days_school_opened,'days_present',least(ac.days_present,ac.days_school_opened))
      from public.attendance_counts_for_enrollment(enrollmentid,termid) ac
    );
  end if;

  return jsonb_build_object(
    'can_edit_teacher_comment',canfields and public.current_app_role()='class_teacher',
    'can_edit_principal_comment',rid is not null and public.current_app_role()='principal' and coalesce(report_json->>'status','draft') in ('submitted','class_reviewed','approved'),
    'report',report_json,
    'student',student_json,
    'can_edit',canedit,
    'can_edit_fields',canfields,
    'allowed_transitions',case when rid is null then '[]'::jsonb else to_jsonb(public.allowed_report_transitions(rid)) end,
    'subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.display_order,q.subject_name) from (
      select sb.id subject_id,sb.code subject_code,sb.name subject_name,sb.display_order,
        (public.can_score_class_subject_for_term(classid,sb.id,termid)
          or (rid is not null and public.has_approved_report_correction(rid) and public.can_score_class_subject_scope(classid,sb.id,termid)))
          and coalesce(report_json->>'status','draft') in ('draft','returned','withdrawn') can_score,
        coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid)) scheme_id,
        sc.name scheme_name,sr.id result_id,
        coalesce(sr.total_score,0) total_score,coalesce(sr.grade,'') grade,coalesce(sr.remark,'') remark,
        coalesce(sr.grade_point,0) grade_point,coalesce(sr.teacher_initials,'') teacher_initials,
        coalesce((select jsonb_agg(jsonb_build_object(
          'component_id',ac.id,'name',ac.name,'code',ac.code,'maximum_score',ac.maximum_score,
          'weight',ac.weight,'required',ac.required,'display_order',ac.display_order,
          'raw_score',coalesce(se.raw_score,0),'weighted_score',coalesce(se.weighted_score,0)
        ) order by ac.display_order,ac.name)
        from public.assessment_components ac
        left join public.assessment_score_entries se on se.component_id=ac.id and se.subject_result_id=sr.id
        where ac.scheme_id=coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid))),'[]'::jsonb) components
      from public.class_subjects cs
      join public.subjects sb on sb.id=cs.subject_id
      left join public.subject_results sr on sr.report_id=rid and sr.subject_id=sb.id
      left join public.assessment_schemes sc on sc.id=coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid))
      where cs.class_id=classid and cs.active and sb.active and sb.deleted_at is null
    ) q),'[]'::jsonb),
    'emergency_delegations',public.get_my_emergency_academic_delegations(classid,termid),
    'workflow',case when rid is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select w.*,p.full_name actor_name from public.report_workflow_events w
      left join public.profiles p on p.id=w.actor_id where w.report_id=rid
    ) q),'[]'::jsonb) end,
    'publications',case when rid is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(p) order by p.published_at desc)
      from public.report_publications p where p.report_id=rid),'[]'::jsonb) end
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.save_report_card(payload jsonb, expected_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid:=nullif(payload->>'report_id','')::uuid;
declare enrollmentid uuid:=(payload->>'enrollment_id')::uuid;
declare termid uuid:=(payload->>'term_id')::uuid;
declare current_version integer; current_status public.report_status; classid uuid; yearid uuid;
declare subject_item jsonb; component_item jsonb; resultid uuid; schemeid uuid; subjectid uuid;
declare report_fields jsonb:=coalesce(payload->'fields','{}'::jsonb);
declare opened_count integer:=0; present_count integer:=0; canreportfields boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select e.class_id,e.academic_year_id into classid,yearid from public.enrollments e
    where e.id=enrollmentid and e.deleted_at is null;
  if classid is null or not public.can_access_class(classid,true) then raise exception 'Access denied' using errcode='42501'; end if;
  if not exists(select 1 from public.terms t where t.id=termid and t.academic_year_id=yearid and t.deleted_at is null)
    then raise exception 'Term and enrolment academic year do not match'; end if;
  select ac.days_school_opened,least(ac.days_present,ac.days_school_opened)
    into opened_count,present_count
    from public.attendance_counts_for_enrollment(enrollmentid,termid) ac;
  opened_count:=coalesce(opened_count,0);
  present_count:=coalesce(present_count,0);
  canreportfields:=public.can_manage_class_report_fields_for_term(classid,termid)
    or (rid is not null and public.has_approved_report_correction(rid)
        and public.can_manage_class_report_fields_scope(classid,termid));
  if report_fields <> '{}'::jsonb and not canreportfields then
    raise exception 'Only the assigned Class Teacher may save report profile fields' using errcode='42501';
  end if;
  if btrim(coalesce(report_fields->>'head_comment',''))<>'' then
    raise exception 'Principal comment must be saved by the Principal after submission' using errcode='42501';
  end if;
  perform set_config('app.report_write','on',true);
  perform set_config('app.change_reason',coalesce(payload->>'reason','Report card save'),true);
  perform pg_advisory_xact_lock(hashtext(enrollmentid::text),hashtext(termid::text));
  if rid is null then
    select id,version,status into rid,current_version,current_status
    from public.student_reports where enrollment_id=enrollmentid and term_id=termid and deleted_at is null for update;
  else
    select version,status into current_version,current_status
    from public.student_reports where id=rid and enrollment_id=enrollmentid and term_id=termid and deleted_at is null for update;
  end if;
  if rid is null then
    insert into public.student_reports(
      enrollment_id,term_id,days_school_opened,days_present,attitude,conduct,interest,
      teacher_comment,head_comment,promoted_to_class_id,status,version,created_by
    ) values(
      enrollmentid,termid,opened_count,
      present_count,coalesce(report_fields->>'attitude',''),
      coalesce(report_fields->>'conduct',''),coalesce(report_fields->>'interest',''),
      coalesce(report_fields->>'teacher_comment',''),'',
      nullif(report_fields->>'promoted_to_class_id','')::uuid,'draft',1,auth.uid()
    ) returning id,version,status into rid,current_version,current_status;
  else
    if expected_version is not null and expected_version<>current_version then
      raise exception 'This report was changed by another user. Refresh before saving.'
        using errcode='40001',detail='expected='||expected_version||',actual='||current_version;
    end if;
    if current_status not in ('draft','returned') then raise exception 'This report is locked by the approval workflow'; end if;
    if not public.can_edit_report(rid) then raise exception 'Access denied' using errcode='42501'; end if;
    update public.student_reports set
      days_school_opened=opened_count,
      days_present=present_count,
      attitude=case when canreportfields then coalesce(report_fields->>'attitude',attitude) else attitude end,
      conduct=case when canreportfields then coalesce(report_fields->>'conduct',conduct) else conduct end,
      interest=case when canreportfields then coalesce(report_fields->>'interest',interest) else interest end,
      teacher_comment=case when canreportfields then coalesce(report_fields->>'teacher_comment',teacher_comment) else teacher_comment end,
      head_comment=head_comment,
      promoted_to_class_id=case when canreportfields and report_fields ? 'promoted_to_class_id'
        then nullif(report_fields->>'promoted_to_class_id','')::uuid else promoted_to_class_id end,
      version=version+1,updated_at=now()
    where id=rid returning version,status into current_version,current_status;
  end if;
  for subject_item in select value from jsonb_array_elements(coalesce(payload->'subjects','[]'::jsonb))
  loop
    subjectid:=(subject_item->>'subject_id')::uuid;
    if not public.can_score_subject(rid,subjectid) then
      if exists(select 1 from public.subject_results where report_id=rid and subject_id=subjectid) then continue; end if;
      raise exception 'You are not authorised to score one or more subjects' using errcode='42501';
    end if;
    schemeid:=nullif(subject_item->>'scheme_id','')::uuid;
    if schemeid is null then schemeid:=public.resolve_assessment_scheme(classid,subjectid,yearid,termid); end if;
    if schemeid is null then raise exception 'No assessment scheme is configured for a subject'; end if;
    if abs((select coalesce(sum(weight),0) from public.assessment_components where scheme_id=schemeid)-100)>0.01
      then raise exception 'Assessment scheme weights must total 100'; end if;
    insert into public.subject_results(report_id,subject_id,scheme_id,teacher_initials,created_by)
    values(rid,subjectid,schemeid,coalesce(subject_item->>'teacher_initials',''),auth.uid())
    on conflict(report_id,subject_id) do update set scheme_id=excluded.scheme_id,
      teacher_initials=excluded.teacher_initials,updated_at=now()
    returning id into resultid;
    delete from public.assessment_score_entries e
    where e.subject_result_id=resultid
      and not exists(
        select 1 from jsonb_array_elements(coalesce(subject_item->'components','[]'::jsonb)) x
        where (x->>'component_id')::uuid=e.component_id
      );
    for component_item in select value from jsonb_array_elements(coalesce(subject_item->'components','[]'::jsonb))
    loop
      insert into public.assessment_score_entries(subject_result_id,component_id,raw_score,created_by)
      values(resultid,(component_item->>'component_id')::uuid,coalesce((component_item->>'raw_score')::numeric,0),auth.uid())
      on conflict(subject_result_id,component_id) do update set raw_score=excluded.raw_score,updated_at=now();
    end loop;
    perform public.refresh_subject_result(resultid);
  end loop;
  update public.student_reports
  set report_number=coalesce(report_number,public.generate_report_number(rid)),updated_at=now()
  where id=rid;
  insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
  values(rid,(select version from public.student_reports where id=rid),public.build_report_snapshot(rid),
    coalesce(payload->>'reason','Saved'),auth.uid())
  on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,
    actor_id=excluded.actor_id,created_at=now();
  return public.get_report_editor(rid,null,null);
end $function$
;

CREATE OR REPLACE FUNCTION public.transition_report_status(target_report_id uuid, target_status report_status, comment_text text DEFAULT ''::text, expected_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  current_status public.report_status;
  current_version integer;
  allowed public.report_status[];
  revisionid uuid;
  ts timestamptz:=now();
begin
  select status,version into current_status,current_version
  from public.student_reports
  where id=target_report_id and deleted_at is null
  for update;
  if current_status is null then raise exception 'Report not found'; end if;
  if expected_version is not null and current_version<>expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if not public.report_transition_deadline_allowed(target_report_id,target_status) then
    raise exception 'The report workflow deadline has passed or the selected term is locked' using errcode='42501';
  end if;
  allowed:=public.allowed_report_transitions(target_report_id);
  if not target_status=any(allowed) then
    raise exception 'Transition from % to % is not allowed',current_status,target_status using errcode='42501';
  end if;

  if target_status='approved' and not exists (
    select 1 from public.student_reports r where r.id=target_report_id and btrim(coalesce(r.head_comment,''))<>''
  ) then
    raise exception 'Principal comment must be reviewed and saved before approving this report' using errcode='23514';
  end if;
  if target_status in ('approved','published','returned','withdrawn') then
    perform public.require_sensitive_access();
  end if;

  if target_status='submitted' then
    if not exists(select 1 from public.student_reports r where r.id=target_report_id and btrim(coalesce(r.teacher_comment,''))<>'') then
      raise exception 'Class teacher comment must be reviewed and saved before submission' using errcode='23514';
    end if;
    if exists(
      select 1 from public.class_subjects cs
      join public.student_reports r on r.id=target_report_id
      left join public.subject_results sr on sr.report_id=r.id and sr.subject_id=cs.subject_id
      where cs.class_id=public.report_class_id(target_report_id) and cs.active and sr.id is null
    ) then raise exception 'All assigned subjects must be completed before submission'; end if;
    if exists(
      select 1 from public.subject_results sr
      join public.assessment_components ac on ac.scheme_id=sr.scheme_id and ac.required
      left join public.assessment_score_entries se on se.subject_result_id=sr.id and se.component_id=ac.id
      where sr.report_id=target_report_id and se.id is null
    ) then raise exception 'Required assessment scores are incomplete'; end if;
  end if;

  perform set_config('app.report_write','on',true);
  perform set_config('app.change_reason',coalesce(nullif(comment_text,''),replace(target_status::text,'_',' ')),true);

  if target_status='returned' and current_status='published' then
    update public.report_publications
      set revoked_at=ts,revoked_by=auth.uid()
    where report_id=target_report_id and revoked_at is null;
  end if;

  update public.student_reports set
    status=target_status,
    version=version+1,
    submitted_at=case when target_status='submitted' then ts else submitted_at end,
    submitted_by=case when target_status='submitted' then auth.uid() else submitted_by end,
    reviewed_at=case when target_status='class_reviewed' then ts else reviewed_at end,
    reviewed_by=case when target_status='class_reviewed' then auth.uid() else reviewed_by end,
    approved_at=case when target_status='approved' then ts else approved_at end,
    approved_by=case when target_status='approved' then auth.uid() else approved_by end,
    published_at=case when target_status='published' then ts else published_at end,
    published_by=case when target_status='published' then auth.uid() else published_by end,
    withdrawn_at=case when target_status='withdrawn' then ts else withdrawn_at end,
    updated_at=ts
  where id=target_report_id
  returning version into current_version;

  insert into public.report_workflow_events(report_id,from_status,to_status,comment,actor_id)
  values(target_report_id,current_status,target_status,coalesce(comment_text,''),auth.uid());

  insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
  values(target_report_id,current_version,public.build_report_snapshot(target_report_id),
    coalesce(nullif(comment_text,''),replace(target_status::text,'_',' ')),auth.uid())
  on conflict(report_id,version) do update
    set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now()
  returning id into revisionid;

  if target_status='published' then
    insert into public.report_publications(report_id,revision_id,published_by)
    values(target_report_id,revisionid,auth.uid())
    on conflict(report_id) where revoked_at is null do update
      set revision_id=excluded.revision_id,published_by=excluded.published_by,published_at=now();
    perform public.mark_report_correction_applied(target_report_id);
  elsif target_status='withdrawn' then
    update public.report_publications set revoked_at=ts,revoked_by=auth.uid()
    where report_id=target_report_id and revoked_at is null;
  end if;

  perform public.create_workflow_notifications(target_report_id,target_status);
  return public.get_report_editor(target_report_id,null,null);
end
$function$
;

COMMIT;
