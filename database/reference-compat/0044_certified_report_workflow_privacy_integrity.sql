-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source file blob SHA: cc6a8defc3c83f8ade43872a465ce9706f8c4463
-- Function bodies extracted read-only with pg_get_functiondef.
-- Requires 0043 certified report-governance prerequisites.

begin;

CREATE OR REPLACE FUNCTION public.can_view_report_internal(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select auth.uid() is not null
    and public.current_app_role()::text in ('system_admin','principal','class_teacher','subject_teacher')
    and public.can_view_report(target_report_id)
$function$;

CREATE OR REPLACE FUNCTION public.get_report_revisions(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_report_internal(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',rr.id,'version',rr.version,'reason',rr.reason,'actor_id',rr.actor_id,
    'actor_name',p.full_name,'created_at',rr.created_at,'snapshot',rr.snapshot
  ) order by rr.version desc)
  from public.report_revisions rr left join public.profiles p on p.id=rr.actor_id
  where rr.report_id=target_report_id),'[]'::jsonb);
end
$function$;

CREATE OR REPLACE FUNCTION public.get_report_headteacher_signature(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result jsonb;
begin
  if not public.can_view_report_internal(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select jsonb_build_object(
    'headteacher_id',h.id,
    'profile_id',h.profile_id,
    'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
    'contact',h.phone,
    'signature_path',h.signature_path,
    'signature_updated_at',h.signature_updated_at
  ) into result
  from public.headteachers h
  where h.deleted_at is null and h.active and h.employment_status='active'
  order by case when btrim(coalesce(h.signature_path,''))<>'' then 0 else 1 end,
           h.updated_at desc,h.created_at desc
  limit 1;
  return coalesce(result,jsonb_build_object(
    'full_name',coalesce((select s.head_name from public.school_settings s order by s.created_at limit 1),'Principal'),
    'signature_path',''
  ));
end
$function$;

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

  return jsonb_build_object(
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
$function$;

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
$function$;

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
$function$;

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

  if target_status in ('approved','published','returned','withdrawn') then
    perform public.require_sensitive_access();
  end if;

  if target_status='submitted' then
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
$function$;

revoke all on function public.can_view_report_internal(uuid) from public;
revoke all on function public.get_report_revisions(uuid) from public;
revoke all on function public.get_report_headteacher_signature(uuid) from public;
revoke all on function public.get_report_editor(uuid,uuid,uuid) from public;
revoke all on function public.can_delete_report(uuid) from public;
revoke all on function public.delete_report_card_permanently(uuid,text) from public;
revoke all on function public.transition_report_status(uuid,public.report_status,text,integer) from public;

revoke all on function public.can_view_report_internal(uuid) from edusentia_worker_runtime;
revoke all on function public.get_report_revisions(uuid) from edusentia_worker_runtime;
revoke all on function public.get_report_headteacher_signature(uuid) from edusentia_worker_runtime;
revoke all on function public.get_report_editor(uuid,uuid,uuid) from edusentia_worker_runtime;
revoke all on function public.can_delete_report(uuid) from edusentia_worker_runtime;
revoke all on function public.delete_report_card_permanently(uuid,text) from edusentia_worker_runtime;
revoke all on function public.transition_report_status(uuid,public.report_status,text,integer) from edusentia_worker_runtime;

grant execute on function public.get_report_revisions(uuid)
  to edusentia_worker_runtime;
grant execute on function public.get_report_headteacher_signature(uuid)
  to edusentia_worker_runtime;
grant execute on function public.get_report_editor(uuid,uuid,uuid)
  to edusentia_worker_runtime;
grant execute on function public.delete_report_card_permanently(uuid,text)
  to edusentia_worker_runtime;
grant execute on function public.transition_report_status(uuid,public.report_status,text,integer)
  to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0044_certified_report_workflow_privacy_integrity')
on conflict do nothing;

update app.release_identity
set schema_version='0044'
where edition='Edusentia Enterprise Neon Edition';

commit;
