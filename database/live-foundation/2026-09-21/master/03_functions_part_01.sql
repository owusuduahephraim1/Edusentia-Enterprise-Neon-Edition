-- Edusentia master foundation: public functions
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

CREATE OR REPLACE FUNCTION public.admin_apply_user_bundle(actor_id uuid, bundle jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(bundle->>'user_id');
  staffrecordid uuid:=public.safe_uuid(bundle->>'staff_record_id');
  role_text text:=btrim(coalesce(bundle->>'role','viewer'));
  item jsonb; classid uuid; subjectid uuid; accesslevel text; previous jsonb;
  resolved_name text:=btrim(coalesce(bundle->>'full_name',''));
  resolved_phone text:=btrim(coalesce(bundle->>'phone',''));
begin
  perform public.admin_validate_user_bundle(actor_id,bundle,true);
  if role_text in ('class_teacher','subject_teacher') then
    select concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),coalesce(nullif(t.phone,''),resolved_phone)
      into resolved_name,resolved_phone from public.teachers t where t.id=staffrecordid and t.deleted_at is null;
  elsif role_text='principal' then
    select concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),coalesce(nullif(h.phone,''),resolved_phone)
      into resolved_name,resolved_phone from public.headteachers h where h.id=staffrecordid and h.deleted_at is null;
  end if;
  select jsonb_build_object(
    'profile',to_jsonb(p),
    'teacher',(select to_jsonb(t) from public.teachers t where t.profile_id=targetid and t.deleted_at is null limit 1),
    'principal',(select to_jsonb(h) from public.headteachers h where h.profile_id=targetid and h.deleted_at is null limit 1),
    'access',coalesce((select jsonb_agg(to_jsonb(a)) from public.user_class_access a where a.user_id=targetid),'[]'::jsonb)
  ) into previous from public.profiles p where p.id=targetid;
  insert into public.profiles(id,full_name,role,active,mfa_required,must_change_password,phone,updated_at)
  values(targetid,resolved_name,role_text::public.app_role,public.safe_boolean(bundle->>'active',true),
    public.safe_boolean(bundle->>'mfa_required',false),public.safe_boolean(bundle->>'must_change_password',false),resolved_phone,now())
  on conflict(id) do update set full_name=excluded.full_name,role=excluded.role,active=excluded.active,
    mfa_required=excluded.mfa_required,must_change_password=excluded.must_change_password,
    phone=excluded.phone,updated_at=now();
  update public.teachers set profile_id=null,updated_at=now()
    where profile_id=targetid and (role_text not in ('class_teacher','subject_teacher') or id<>staffrecordid);
  update public.headteachers set profile_id=null,updated_at=now()
    where profile_id=targetid and (role_text<>'principal' or id<>staffrecordid);
  if role_text in ('class_teacher','subject_teacher') then
    update public.teachers set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  elsif role_text='principal' then
    update public.headteachers set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  end if;
  delete from public.user_class_access where user_id=targetid;
  for item in select value from jsonb_array_elements(coalesce(bundle->'access','[]'::jsonb)) loop
    classid:=public.safe_uuid(item->>'class_id'); subjectid:=public.safe_uuid(item->>'subject_id'); accesslevel:=coalesce(nullif(btrim(item->>'access_level'),''),'view');
    insert into public.user_class_access(user_id,class_id,subject_id,access_level) values(targetid,classid,subjectid,accesslevel);
  end loop;
  if role_text in ('class_teacher','subject_teacher') then
    perform public.sync_teacher_responsibility_access(targetid);
  end if;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(actor_id,'profiles',targetid,case when previous is null then 'ADMIN_CREATE_USER' else 'ADMIN_UPDATE_USER' end,
    previous,jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where p.id=targetid),
      'teacher',(select to_jsonb(t) from public.teachers t where t.profile_id=targetid and t.deleted_at is null limit 1),
      'principal',(select to_jsonb(h) from public.headteachers h where h.profile_id=targetid and h.deleted_at is null limit 1),
      'access',coalesce((select jsonb_agg(to_jsonb(a)) from public.user_class_access a where a.user_id=targetid),'[]'::jsonb)),
    coalesce(nullif(bundle->>'reason',''),'User account management'));
  return jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where p.id=targetid),
    'teacher',(select to_jsonb(t) from public.teachers t where t.profile_id=targetid and t.deleted_at is null limit 1),
    'principal',(select to_jsonb(h) from public.headteachers h where h.profile_id=targetid and h.deleted_at is null limit 1),
    'access',coalesce((select jsonb_agg(to_jsonb(a)) from public.user_class_access a where a.user_id=targetid),'[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_validate_user_bundle(actor_id uuid, bundle jsonb, require_existing_user boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(bundle->>'user_id');
  staffrecordid uuid:=public.safe_uuid(bundle->>'staff_record_id');
  role_text text:=btrim(coalesce(bundle->>'role','viewer'));
  item jsonb; classid uuid; subjectid uuid; accesslevel text; scopekey text;
  seen_scopes text[]:='{}'::text[]; has_class_scope boolean:=false;
begin
  if actor_id is null or not exists(select 1 from public.profiles p where p.id=actor_id and p.active and public.current_app_role_for(p.role)='system_admin') then raise exception 'Access denied' using errcode='42501'; end if;
  if require_existing_user and (targetid is null or not exists(select 1 from auth.users u where u.id=targetid)) then raise exception 'Authentication account was not found'; end if;
  if btrim(coalesce(bundle->>'staff_record_id',''))<>'' and staffrecordid is null then raise exception 'Selected staff record is invalid'; end if;
  if btrim(coalesce(bundle->>'full_name',''))='' then raise exception 'Full name is required'; end if;
  if btrim(coalesce(bundle->>'email',''))='' then raise exception 'Email address is required'; end if;
  if bundle->>'email' !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Email address is invalid'; end if;
  if role_text not in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian') then raise exception 'User role is invalid'; end if;
  if role_text in ('class_teacher','subject_teacher') then
    if staffrecordid is null then raise exception 'Select the corresponding teacher record'; end if;
    if not exists(select 1 from public.teachers t where t.id=staffrecordid and t.deleted_at is null and t.active and (t.profile_id is null or t.profile_id=targetid)) then raise exception 'Selected teacher record is unavailable or already linked'; end if;
  elsif role_text='principal' then
    if staffrecordid is null then raise exception 'Select the corresponding Principal record'; end if;
    if not exists(select 1 from public.headteachers h where h.id=staffrecordid and h.deleted_at is null and h.active and (h.profile_id is null or h.profile_id=targetid)) then raise exception 'Selected Principal record is unavailable or already linked'; end if;
  elsif staffrecordid is not null then
    raise exception 'The selected role does not use a staff record';
  end if;
  if jsonb_typeof(coalesce(bundle->'access','[]'::jsonb))<>'array' then raise exception 'Delegated access must be a list'; end if;
  for item in select value from jsonb_array_elements(coalesce(bundle->'access','[]'::jsonb)) loop
    classid:=public.safe_uuid(item->>'class_id'); subjectid:=public.safe_uuid(item->>'subject_id'); accesslevel:=coalesce(nullif(btrim(item->>'access_level'),''),'view');
    if btrim(coalesce(item->>'class_id',''))<>'' and classid is null then raise exception 'A delegated class identifier is invalid'; end if;
    if btrim(coalesce(item->>'subject_id',''))<>'' and subjectid is null then raise exception 'A delegated subject identifier is invalid'; end if;
    if classid is null or not exists(select 1 from public.classes c where c.id=classid and c.deleted_at is null and c.active) then raise exception 'A delegated class is invalid or inactive'; end if;
    if subjectid is not null and not exists(select 1 from public.class_subjects cs join public.subjects s on s.id=cs.subject_id where cs.class_id=classid and cs.subject_id=subjectid and cs.active and s.active and s.deleted_at is null) then raise exception 'A delegated subject is not actively assigned to the selected class'; end if;
    if accesslevel not in ('view','edit','score','review') then raise exception 'Delegated access level is invalid'; end if;
    if role_text='subject_teacher' and subjectid is null then raise exception 'Subject teacher access must identify a subject'; end if;
    if role_text='subject_teacher' and accesslevel not in ('score','edit','review') then raise exception 'Subject teacher access must permit scoring'; end if;
    if role_text='class_teacher' and subjectid is null and accesslevel not in ('edit','review') then raise exception 'Class teacher access must permit class report editing'; end if;
    if role_text='class_teacher' and subjectid is null and accesslevel in ('edit','review') then has_class_scope:=true; end if;
    scopekey:=classid::text||'|'||coalesce(subjectid::text,'*');
    if scopekey=any(seen_scopes) then raise exception 'The same delegated class or subject access was entered more than once'; end if;
    seen_scopes:=array_append(seen_scopes,scopekey);
  end loop;
  return jsonb_build_object('valid',true,'role',role_text,'staff_record_id',staffrecordid,'access_count',coalesce(jsonb_array_length(bundle->'access'),0));
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
  select backup_retention_days,backup_minimum_copies
  into policy_row
  from public.school_settings
  order by created_at,id
  limit 1;
  return jsonb_build_object(
    'retention_days',coalesce(policy_row.backup_retention_days,7),
    'minimum_copies',coalesce(policy_row.backup_minimum_copies,2),
    'backups',coalesce((
      select jsonb_agg(to_jsonb(b) order by b.created_at desc)
      from (
        select * from public.backup_exports
        order by created_at desc
        limit 20
      ) b
    ),'[]'::jsonb)
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
declare rowj jsonb; reportid uuid; classid uuid; studentid uuid; recipientid uuid; topics text[]:=array[]::text[]; topic text;
begin
  rowj:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if tg_table_name='notifications' then
    recipientid:=public.safe_uuid(rowj->>'recipient_id');
    topics:=array['user:'||recipientid::text];
  elsif tg_table_name='student_reports' then
    reportid:=public.safe_uuid(rowj->>'id'); classid:=public.report_class_id(reportid);
    topics:=array['report:'||reportid::text,'class:'||classid::text,'school:global'];
  elsif tg_table_name in ('subject_results','report_workflow_events','report_revisions','report_publications') then
    reportid:=public.safe_uuid(rowj->>'report_id'); classid:=public.report_class_id(reportid);
    topics:=array['report:'||reportid::text,'class:'||classid::text];
  elsif tg_table_name='assessment_score_entries' then
    select sr.report_id into reportid from public.subject_results sr where sr.id=public.safe_uuid(rowj->>'subject_result_id');
    classid:=public.report_class_id(reportid); topics:=array['report:'||reportid::text,'class:'||classid::text];
  elsif tg_table_name='students' then
    studentid:=public.safe_uuid(rowj->>'id'); topics:=array['student:'||studentid::text,'school:global'];
  elsif tg_table_name='enrollments' then
    studentid:=public.safe_uuid(rowj->>'student_id'); classid:=public.safe_uuid(rowj->>'class_id');
    topics:=array['student:'||studentid::text,'class:'||classid::text,'school:global'];
  elsif tg_table_name='guardian_links' then
    studentid:=public.safe_uuid(rowj->>'student_id'); recipientid:=public.safe_uuid(rowj->>'auth_user_id');
    topics:=array['student:'||studentid::text,'user:'||coalesce(recipientid::text,'')];
  else topics:=array['school:global'];
  end if;
  foreach topic in array topics loop
    if topic is not null and right(topic,1)<>':' then
      begin
        perform realtime.broadcast_changes(topic,tg_op,tg_op,tg_table_name,tg_table_schema,new,old);
      exception when undefined_function or invalid_schema_name then null;
      end;
    end if;
  end loop;
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
declare student_json jsonb;
begin
  select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'gender',s.gender,'date_of_birth',s.date_of_birth,'status',s.status,'archived',s.deleted_at is not null) into student_json from public.students s where s.id=target_student_id;
  if student_json is null then raise exception 'Student not found'; end if;
  return jsonb_build_object(
    'student',student_json,
    'school',(select jsonb_build_object('school_name',school_name,'motto',motto,'address',address,'phone',phone,'email',email,'website',website,'logo_url',logo_url) from public.school_settings limit 1),
    'generated_at',now(),
    'academic_records',coalesce((select jsonb_agg(jsonb_build_object(
      'report_id',r.id,'report_number',r.report_number,'status',r.status,'term_id',r.term_id,'term_name',t.name,'term_sequence',t.sequence,
      'academic_year_id',y.id,'academic_year_name',y.name,'class_id',c.id,'class_name',c.name,
      'days_school_opened',r.days_school_opened,'days_present',r.days_present,'teacher_comment',r.teacher_comment,'head_comment',r.head_comment,
      'average',(select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),
      'subjects',coalesce((select jsonb_agg(jsonb_build_object('subject_id',sb.id,'subject_code',sb.code,'subject_name',sb.name,'total_score',sr.total_score,'grade',sr.grade,'remark',sr.remark,'grade_point',sr.grade_point) order by sb.display_order,sb.name) from public.subject_results sr join public.subjects sb on sb.id=sr.subject_id where sr.report_id=r.id),'[]'::jsonb),
      'published_at',r.published_at
    ) order by y.start_date,t.sequence,c.level_order)
    from public.student_reports r join public.enrollments e on e.id=r.enrollment_id join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id join public.classes c on c.id=e.class_id
    where e.student_id=target_student_id and r.deleted_at is null and r.status in ('approved','published','withdrawn')),'[]'::jsonb),
    'lifecycle',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'event_type',l.event_type,'effective_date',l.effective_date,'from_class_name',fc.name,'to_class_name',tc.name,'destination_school',l.destination_school,'reason',l.reason,'reference',l.reference,'created_at',l.created_at,'actor_name',p.full_name) order by l.effective_date,l.created_at) from public.student_lifecycle_events l left join public.classes fc on fc.id=l.from_class_id left join public.classes tc on tc.id=l.to_class_id left join public.profiles p on p.id=l.created_by where l.student_id=target_student_id),'[]'::jsonb)
  );
end $function$
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
    select 1 from public.student_reports r
    where r.id=target_report_id and r.deleted_at is null
  ) and (
    public.is_system_admin()
    or (
      public.current_app_role() in ('class_teacher','subject_teacher')
      and public.can_create_report_for_class(public.report_class_id(target_report_id))
    )
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
AS $function$ select public.is_system_admin() $function$
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
AS $function$ select public.is_system_admin() $function$
;

CREATE OR REPLACE FUNCTION public.can_manage_teachers()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.is_system_admin() $function$
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
    or exists(
      select 1 from public.student_reports r
      join public.enrollments e on e.id=r.enrollment_id
      join public.guardian_links gl on gl.student_id=e.student_id
      where r.id=target_report_id and r.status='published' and r.deleted_at is null
        and gl.auth_user_id=auth.uid() and gl.can_view_reports
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
  insert into public.privacy_requests(student_id,request_type,requester_name,requester_contact,request_details,due_at,assigned_to)
  values(public.safe_uuid(payload->>'student_id'),payload->>'request_type',btrim(payload->>'requester_name'),coalesce(payload->>'requester_contact',''),btrim(payload->>'request_details'),coalesce(public.safe_timestamptz(payload->>'due_at'),now()+interval '30 days'),public.safe_uuid(payload->>'assigned_to')) returning * into row_data;
  return to_jsonb(row_data);
end $function$
;

CREATE OR REPLACE FUNCTION public.create_workflow_notifications(target_report_id uuid, target_status report_status)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare classid uuid;studentname text;reportno text;recipient uuid;
begin
  select e.class_id,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),coalesce(r.report_number,'')
  into classid,studentname,reportno
  from public.student_reports r join public.enrollments e on e.id=r.enrollment_id join public.students s on s.id=e.student_id
  where r.id=target_report_id;
  if target_status='submitted' then
    for recipient in select p.id from public.profiles p where p.active and public.current_app_role_for(p.role)='principal' loop
      if recipient<>auth.uid() then perform public.create_notification(recipient,'Report awaiting Principal approval',studentname||case when reportno<>'' then ' • '||reportno else '' end,'report_workflow','report',target_report_id,true); end if;
    end loop;
  elsif target_status='returned' then
    for recipient in select distinct user_id from (
      select c.class_teacher_id user_id from public.classes c where c.id=classid and c.class_teacher_id is not null
      union all select cs.teacher_id from public.class_subjects cs where cs.class_id=classid and cs.active and cs.teacher_id is not null
      union all select a.user_id from public.user_class_access a where a.class_id=classid and a.user_id is not null
    ) q loop
      if recipient<>auth.uid() then perform public.create_notification(recipient,'Report returned for correction',studentname||case when reportno<>'' then ' • '||reportno else '' end,'report_workflow','report',target_report_id,true); end if;
    end loop;
  elsif target_status='approved' then
    for recipient in select distinct user_id from (
      select p.id user_id from public.profiles p where p.active and public.current_app_role_for(p.role)='system_admin'
      union all select c.class_teacher_id from public.classes c where c.id=classid and c.class_teacher_id is not null
      union all select cs.teacher_id from public.class_subjects cs where cs.class_id=classid and cs.active and cs.teacher_id is not null
      union all select a.user_id from public.user_class_access a where a.class_id=classid and a.user_id is not null
    ) q loop
      if recipient<>auth.uid() then perform public.create_notification(recipient,'Report approved by Principal',studentname||case when reportno<>'' then ' • '||reportno else '' end,'report_workflow','report',target_report_id,true); end if;
    end loop;
  elsif target_status='published' then
    for recipient in select gl.auth_user_id from public.guardian_links gl join public.enrollments e on e.student_id=gl.student_id join public.student_reports r on r.enrollment_id=e.id
      where r.id=target_report_id and gl.auth_user_id is not null and gl.can_receive_notifications loop
      perform public.create_notification(recipient,'Report card published',studentname||case when reportno<>'' then ' • '||reportno else '' end,'report_published','report',target_report_id,true);
    end loop;
  end if;
end $function$
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
  select case
    when p.role='admin' then 'system_admin'::public.app_role
    when p.role='teacher' then 'class_teacher'::public.app_role
    when p.role='headteacher' then 'principal'::public.app_role
    else p.role
  end
  from public.profiles p
  where p.id=auth.uid() and p.active
    and p.role in ('admin','teacher','headteacher','system_admin','principal','class_teacher','subject_teacher','parent_guardian','platform_super_admin')
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

CREATE OR REPLACE FUNCTION public.delete_report_card_permanently(target_report_id uuid, reason_text text DEFAULT 'Report card permanently deleted'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  related_ids uuid[]:=array[target_report_id];
  extra_ids uuid[];
begin
  if not public.can_delete_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform 1 from public.student_reports
  where id=target_report_id and deleted_at is null
  for update;
  if not found then raise exception 'Report card not found'; end if;
  select coalesce(array_agg(x.id),'{}'::uuid[])
  into extra_ids
  from (
    select ss.id from public.subject_scores ss where ss.report_id=target_report_id
    union all
    select sr.id from public.subject_results sr where sr.report_id=target_report_id
    union all
    select ase.id
    from public.assessment_score_entries ase
    join public.subject_results sr on sr.id=ase.subject_result_id
    where sr.report_id=target_report_id
    union all
    select we.id from public.report_workflow_events we where we.report_id=target_report_id
    union all
    select rr.id from public.report_revisions rr where rr.report_id=target_report_id
    union all
    select rp.id from public.report_publications rp where rp.report_id=target_report_id
  ) x;
  related_ids:=array_cat(related_ids,extra_ids);
  perform set_config('app.report_write','on',true);
  perform set_config('app.audit_suppress','on',true);
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Report card permanently deleted'),true);
  delete from public.notifications
  where entity_type='report' and entity_id=target_report_id;
  delete from public.notification_outbox
  where coalesce(payload::text,'') like '%'||target_report_id::text||'%';
  delete from public.student_reports where id=target_report_id;
  if not found then raise exception 'Report card not found'; end if;
  delete from public.audit_log a
  where a.record_id=any(related_ids)
     or coalesce(a.old_data::text,'') like '%'||target_report_id::text||'%'
     or coalesce(a.new_data::text,'') like '%'||target_report_id::text||'%';
  return true;
end $function$
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

CREATE OR REPLACE FUNCTION public.freeze_report_grading_guide()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_guide jsonb;
begin
  if new.status='submitted' and old.status is distinct from new.status then
    perform public.recalculate_report_grades(new.id);
    v_guide:=public.resolve_report_grading_guide(new.id);
    new.grading_scale_snapshot:=v_guide;
    new.grading_scale_scope:=coalesce(v_guide->'scope','{}'::jsonb);
    new.grading_scale_frozen_at:=now();
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  base_name text:=lower(regexp_replace(coalesce(requested_base,''),'[^a-z0-9]','','g'));
  email_domain text;
  candidate text;
  suffix integer:=1;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles p
    where p.id=actor_id and p.active and public.current_app_role_for(p.role)='system_admin'
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  if auth.uid() is not null and auth.uid()<>actor_id then raise exception 'Access denied' using errcode='42501'; end if;
  select lower(btrim(coalesce(nullif(s.user_email_domain,''),'school.invalid')))
  into email_domain
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;
  email_domain:=coalesce(nullif(email_domain,''),'school.invalid');
  if email_domain !~ '^(?:[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.)+[a-z]{2,63}$' then
    raise exception 'The configured user email domain is invalid';
  end if;
  base_name:=left(coalesce(nullif(base_name,''),'user'),40);
  perform pg_advisory_xact_lock(hashtextextended('school_user_email_'||email_domain||'_'||base_name,0));
  candidate:=base_name||'@'||email_domain;
  while exists(
    select 1 from auth.users u
    where lower(coalesce(u.email,''))=lower(candidate)
      and (target_user_id is null or u.id<>target_user_id)
  ) loop
    suffix:=suffix+1;
    if suffix>99999 then raise exception 'A unique school user email address could not be generated'; end if;
    candidate:=left(base_name,greatest(1,40-length(suffix::text)))||suffix::text||'@'||email_domain;
  end loop;
  return candidate;
end $function$
;

CREATE OR REPLACE FUNCTION public.generate_report_number(target_report_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare prefix text; yname text; seq bigint;
begin
  select coalesce(report_number_prefix,'SCH') into prefix from public.school_settings limit 1;
  select regexp_replace(ay.name::text,'[^0-9A-Za-z]','','g')
  into yname from public.student_reports r join public.terms t on t.id=r.term_id
  join public.academic_years ay on ay.id=t.academic_year_id where r.id=target_report_id;
  select count(*)+1 into seq from public.student_reports where report_number is not null;
  return upper(prefix)||'-'||coalesce(nullif(yname,''),to_char(current_date,'YYYY'))||'-'||lpad(seq::text,6,'0');
end $function$
;

CREATE OR REPLACE FUNCTION public.generate_school_identifier(identifier_kind text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare kind text:=lower(btrim(coalesce(identifier_kind,'')));candidate text;attempt integer:=0;
begin
  if auth.uid() is null or not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  if kind not in ('student','teacher','principal','headteacher') then raise exception 'Identifier type is invalid'; end if;
  loop
    attempt:=attempt+1;
    candidate:='NIS'||lpad((floor(random()*100000000))::bigint::text,8,'0');
    if not exists(select 1 from public.students s where lower(s.admission_no::text)=lower(candidate))
       and not exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(candidate))
       and not exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(candidate)) then
      return candidate;
    end if;
    if attempt>=250 then raise exception 'Unable to generate a unique school identifier'; end if;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.generate_staff_id_card_number(target_academic_year_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare prefix text;year_code text;candidate text;seq bigint;attempt integer:=0;
begin select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'RCE'),'[^0-9A-Za-z]','','g')) into prefix from public.school_settings limit 1;select regexp_replace(name::text,'[^0-9A-Za-z]','','g') into year_code from public.academic_years where id=target_academic_year_id and deleted_at is null;if year_code is null then raise exception 'Academic year not found';end if;loop attempt:=attempt+1;if attempt>1000 then raise exception 'Unable to allocate a unique staff ID card number';end if;seq:=nextval('public.staff_id_card_number_seq');candidate:=coalesce(nullif(prefix,''),'RCE')||'-STAFF-'||year_code||'-'||lpad(seq::text,6,'0');exit when not exists(select 1 from public.staff_id_cards where card_number=candidate);end loop;return candidate;end$function$
;

CREATE OR REPLACE FUNCTION public.generate_student_id_card_number(target_academic_year_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare prefix text;year_code text;candidate text;seq bigint;attempt integer:=0; begin select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'RCE'),'[^0-9A-Za-z]','','g')) into prefix from public.school_settings limit 1; select regexp_replace(name::text,'[^0-9A-Za-z]','','g') into year_code from public.academic_years where id=target_academic_year_id and deleted_at is null; if year_code is null then raise exception 'Academic year not found';end if;year_code:=coalesce(nullif(year_code,''),upper(substr(replace(target_academic_year_id::text,'-',''),1,8))); loop attempt:=attempt+1;if attempt>1000 then raise exception 'Unable to allocate a unique ID card number';end if; seq:=nextval('public.student_id_card_number_seq');candidate:=coalesce(nullif(prefix,''),'RCE')||'-ID-'||year_code||'-'||lpad(seq::text,6,'0'); exit when not exists(select 1 from public.student_id_cards where card_number=candidate); end loop; return candidate; end$function$
;

CREATE OR REPLACE FUNCTION public.generate_subject_code(subject_name text, exclude_subject_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleaned text:=upper(regexp_replace(btrim(coalesce(subject_name,'')),'[^[:alnum:] ]+',' ','g'));
  meaningful text[];
  all_words text[];
  selected_words text[];
  token text;
  prefix text:='';
  candidate text;
  attempt integer:=0;
begin
  if auth.uid() is null or not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(cleaned)='' then raise exception 'Subject name is required'; end if;
  select coalesce(array_agg(word order by ord),'{}'::text[]) into all_words
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'';
  select coalesce(array_agg(word order by ord),'{}'::text[]) into meaningful
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'' and word not in ('AND','OF','THE','FOR','IN','TO');
  selected_words:=case when cardinality(meaningful)>0 then meaningful else all_words end;
  if cardinality(selected_words)=1 then
    prefix:=left(regexp_replace(selected_words[1],'[^A-Z0-9]','','g'),3);
  else
    foreach token in array selected_words loop
      prefix:=prefix||left(token,1);
      exit when length(prefix)>=4;
    end loop;
  end if;
  if prefix='' then prefix:='SUB'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nis_subject_code_'||prefix,0));
  loop
    attempt:=attempt+1;
    candidate:=prefix||lpad(floor(random()*10000)::integer::text,4,'0');
    if not exists(
      select 1 from public.subjects s
      where lower(s.code::text)=lower(candidate)
        and (exclude_subject_id is null or s.id<>exclude_subject_id)
    ) then return candidate; end if;
    if attempt>=250 then raise exception 'A unique subject code could not be generated'; end if;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.get_academic_configuration()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'academic_years',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc nulls last) from public.academic_years x where x.deleted_at is null),'[]'::jsonb),
    'terms',coalesce((select jsonb_agg(to_jsonb(x) order by x.academic_year_id,x.sequence) from public.terms x where x.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(to_jsonb(x) order by x.level_order,x.name) from public.classes x where x.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.name) from public.subjects x where x.deleted_at is null),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(jsonb_build_object(
      'id',cs.id,'class_id',cs.class_id,'class_name',c.name,'subject_id',cs.subject_id,'subject_name',s.name,
      'teacher_id',cs.teacher_id,'teacher_name',p.full_name,'active',cs.active
    ) order by c.level_order,c.name,s.display_order,s.name)
      from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id
      left join public.profiles p on p.id=cs.teacher_id),'[]'::jsonb),
    'grading_scales',coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.min_mark desc) from public.grading_scales x where x.deleted_at is null),'[]'::jsonb),
    'assessment_schemes',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'academic_year_id',s.academic_year_id,'term_id',s.term_id,
      'class_id',s.class_id,'subject_id',s.subject_id,'active',s.active,
      'components',coalesce((select jsonb_agg(to_jsonb(c) order by c.display_order,c.name)
        from public.assessment_components c where c.scheme_id=s.id),'[]'::jsonb),
      'total_weight',(select coalesce(sum(c.weight),0) from public.assessment_components c where c.scheme_id=s.id)
    ) order by lower(s.name)) from public.assessment_schemes s where s.deleted_at is null),'[]'::jsonb),
    'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role))
      order by lower(p.full_name),p.id) from public.profiles p where p.active),'[]'::jsonb),
    'teacher_records',coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,
      'profile_id',t.profile_id,
      'staff_no',t.staff_no,
      'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
      'label',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)
        ||' • '||t.staff_no::text
        ||case when t.profile_id is null then ' • No linked account' else '' end,
      'active',t.active
    ) order by lower(concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)),t.staff_no::text)
      from public.teachers t
      where t.deleted_at is null and t.active and t.employment_status='active'),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_bootstrap_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  p jsonb;
  v_current_role text;
  current_year uuid;
  v_license jsonb;
  v_write_allowed boolean:=false;
  v_read_allowed boolean:=false;
  v_has_emergency boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_current_role:=public.current_app_role()::text;
  if v_current_role is null or v_current_role not in ('platform_super_admin','system_admin','principal','class_teacher','subject_teacher','parent_guardian') then
    raise exception 'Active supported profile not found' using errcode='42501';
  end if;
  v_license:=public.license_snapshot_for_role(v_current_role);
  v_write_allowed:=coalesce((v_license->>'write_allowed')::boolean,false);
  v_read_allowed:=coalesce((v_license->>'read_allowed')::boolean,false);
  if v_current_role<>'platform_super_admin' then v_has_emergency:=public.has_any_active_emergency_delegation(auth.uid()); end if;
  if v_current_role<>'platform_super_admin' and not v_read_allowed then
    insert into public.license_verification_logs(license_id,actor_id,actor_role,computed_status,access_mode,details)
    values(public.safe_uuid(v_license->>'license_id'),auth.uid(),v_current_role,coalesce(v_license->>'computed_status','unknown'),coalesce(v_license->>'access_mode','locked'),v_license);
    raise exception 'PLATFORM_ACCESS_LOCKED: %',coalesce(nullif(v_license->>'warning',''),'Access has been restricted by the platform licence administrator.') using errcode='42501';
  end if;
  if v_current_role<>'platform_super_admin' and v_write_allowed then
    current_year:=public.sync_current_academic_year_status();
    update public.profiles set last_seen_at=now() where id=auth.uid();
  elsif v_current_role='platform_super_admin' then
    update public.profiles set last_seen_at=now() where id=auth.uid();
  end if;
  select jsonb_build_object(
    'id',pr.id,'full_name',pr.full_name,'role',v_current_role,'active',pr.active,
    'mfa_required',case when v_current_role='platform_super_admin' then true else pr.mfa_required end,
    'must_change_password',pr.must_change_password,'phone',pr.phone
  ) into p from public.profiles pr where pr.id=auth.uid() and pr.active;
  if not exists(
    select 1 from public.license_verification_logs v
    where v.actor_id=auth.uid()
      and v.computed_status=coalesce(v_license->>'computed_status','unknown')
      and v.access_mode=coalesce(v_license->>'access_mode','unknown')
      and v.created_at>now()-interval '15 minutes'
  ) then
    insert into public.license_verification_logs(license_id,actor_id,actor_role,computed_status,access_mode,details)
    values(public.safe_uuid(v_license->>'license_id'),auth.uid(),v_current_role,coalesce(v_license->>'computed_status','unknown'),coalesce(v_license->>'access_mode','unknown'),
      jsonb_build_object('write_allowed',v_write_allowed,'read_allowed',v_read_allowed));
  end if;
  return jsonb_build_object(
    'profile',p,
    'school',case when v_current_role='platform_super_admin'
      then (select jsonb_build_object('id',s.id,'school_name',s.school_name,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour) from public.school_settings s limit 1)
      else (select to_jsonb(s) from public.school_settings s limit 1) end,
    'academic_years',case when v_current_role='platform_super_admin' then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(y) order by y.start_date desc nulls last,y.name) from public.academic_years y where y.deleted_at is null),'[]'::jsonb) end,
    'terms',case when v_current_role='platform_super_admin' then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(t) order by t.sequence) from public.terms t where t.deleted_at is null),'[]'::jsonb) end,
    'classes',case when v_current_role in ('platform_super_admin','parent_guardian') then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(c) order by c.level_order,c.name) from public.classes c where c.deleted_at is null and (v_current_role in ('system_admin','principal') or public.can_access_class(c.id,false))),'[]'::jsonb) end,
    'subjects',case when v_current_role in ('platform_super_admin','parent_guardian') then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(s) order by s.display_order,s.name) from public.subjects s where s.deleted_at is null and s.active),'[]'::jsonb) end,
    'license',v_license,
    'permissions',jsonb_build_object(
      'manage_licenses',v_current_role='platform_super_admin',
      'manage_users',v_current_role='system_admin' and v_write_allowed,
      'manage_teachers',v_current_role='system_admin' and v_write_allowed,
      'manage_headteachers',v_current_role='system_admin' and v_write_allowed,
      'manage_academics',v_current_role='system_admin' and v_write_allowed,
      'manage_students',v_current_role='system_admin' and v_write_allowed,
      'manage_emergency_delegations',v_current_role='system_admin' and v_write_allowed,
      'acknowledge_emergency_delegations',v_current_role='principal' and v_write_allowed,
      'remove_students',v_current_role='system_admin' and v_write_allowed,
      'create_reports',(v_current_role in ('class_teacher','subject_teacher') or (v_current_role='system_admin' and v_has_emergency)) and v_write_allowed,
      'import_scores',(v_current_role in ('class_teacher','subject_teacher') or (v_current_role='system_admin' and v_has_emergency)) and v_write_allowed,
      'approve_reports',v_current_role='principal' and v_write_allowed,
      'publish_reports',v_current_role in ('system_admin','class_teacher') and v_write_allowed,
      'bulk_submit_reports',v_current_role='class_teacher' and v_write_allowed,
      'bulk_approve_reports',v_current_role='principal' and v_write_allowed,
      'bulk_publish_reports',v_current_role in ('system_admin','class_teacher') and v_write_allowed,
      'remove_reports',v_current_role in ('system_admin','class_teacher','subject_teacher') and v_write_allowed,
      'restore_reports',v_current_role='system_admin' and v_write_allowed,
      'view_audit',v_current_role='system_admin',
      'run_backup',v_current_role='system_admin',
      'parent_portal',v_current_role='parent_guardian'
    ),
    'topics',case when v_current_role='platform_super_admin' then '[]'::jsonb else to_jsonb(public.my_realtime_topics()) end
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_certificate_batch(target_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.license_read_allowed() or not public.has_role(array['system_admin','principal']) then raise exception 'Certificate access denied' using errcode='42501'; end if;
  return (select jsonb_build_object(
    'batch',jsonb_build_object('id',b.id,'certificate_type',b.certificate_type,'type_label',public.certificate_type_label(b.certificate_type),'academic_year_id',b.academic_year_id,'academic_year_name',ay.name,'term_id',b.term_id,'term_name',t.name,'class_id',b.class_id,'class_name',c.name,'award_category_name',ac.name,'title',b.title,'custom_citation',b.custom_citation,'notes',b.notes,'status',b.status,'review_note',b.review_note,'prepared_by_name',pp.full_name,'approved_by_name',pa.full_name,'issued_by_name',pi.full_name,'created_at',b.created_at,'submitted_at',b.submitted_at,'approved_at',b.approved_at,'issued_at',b.issued_at),
    'template',to_jsonb(ct),
    'certificates',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'recipient_kind',x.recipient_kind,'student_id',x.student_id,'teacher_id',x.teacher_id,'source_report_id',x.source_report_id,'certificate_number',x.certificate_number,'verification_token',x.verification_token,'revision_no',x.revision_no,'supersedes_certificate_id',x.supersedes_certificate_id,'recipient_name',x.recipient_name,'recipient_identifier',x.recipient_identifier,'current_class_name',x.current_class_name,'destination_class_name',x.destination_class_name,'academic_year_name',x.academic_year_name,'certificate_title',x.certificate_title,'award_category_name',x.award_category_name,'statement_text',x.statement_text,'issue_date',x.issue_date,'status',x.status,'snapshot',x.snapshot,'pdf_storage_path',x.pdf_storage_path,'pdf_sha256',x.pdf_sha256,'revocation_reason',x.revocation_reason,'replacement_reason',x.replacement_reason,'issued_at',x.issued_at) order by x.recipient_name,x.revision_no) from public.certificates x where x.batch_id=b.id),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'certificate_id',e.certificate_id,'event_type',e.event_type,'actor_name',p.full_name,'reason',e.reason,'details',e.details,'created_at',e.created_at) order by e.created_at desc) from public.certificate_events e left join public.profiles p on p.id=e.actor_id where e.batch_id=b.id),'[]'::jsonb),
    'principal',(select jsonb_build_object('full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'signature_path',h.signature_path,'signature_updated_at',h.signature_updated_at) from public.headteachers h where h.deleted_at is null and h.active and h.employment_status='active' order by case when h.profile_id=b.approved_by then 0 else 1 end,h.created_at limit 1),
    'school',(select to_jsonb(s) from public.school_settings s limit 1)
  ) from public.certificate_batches b join public.academic_years ay on ay.id=b.academic_year_id left join public.terms t on t.id=b.term_id left join public.classes c on c.id=b.class_id left join public.teacher_award_categories ac on ac.id=b.teacher_award_category_id join public.certificate_templates ct on ct.id=b.template_id left join public.profiles pp on pp.id=b.prepared_by left join public.profiles pa on pa.id=b.approved_by left join public.profiles pi on pi.id=b.issued_by where b.id=target_batch_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.get_certificate_console(target_academic_year_id uuid DEFAULT NULL::uuid, target_certificate_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.license_read_allowed() or not public.has_role(array['system_admin','principal']) then raise exception 'Certificate access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'templates',coalesce((select jsonb_agg(to_jsonb(t) order by t.certificate_type) from public.certificate_templates t),'[]'::jsonb),
    'award_categories',coalesce((select jsonb_agg(to_jsonb(a) order by a.name) from public.teacher_award_categories a where a.active),'[]'::jsonb),
    'settings',(select jsonb_build_object('completion_class_id',s.certificate_completion_class_id,'footer_text',s.certificate_footer_text) from public.school_settings s limit 1),
    'batches',coalesce((select jsonb_agg(jsonb_build_object(
      'id',b.id,'certificate_type',b.certificate_type,'type_label',public.certificate_type_label(b.certificate_type),
      'academic_year_id',b.academic_year_id,'academic_year_name',ay.name,'term_id',b.term_id,'term_name',t.name,
      'class_id',b.class_id,'class_name',c.name,'award_category_id',b.teacher_award_category_id,'award_category_name',ac.name,
      'title',b.title,'status',b.status,'notes',b.notes,'review_note',b.review_note,
      'prepared_by_name',pp.full_name,'approved_by_name',pa.full_name,'issued_by_name',pi.full_name,
      'recipient_count',(select count(*) from public.certificates x where x.batch_id=b.id),
      'issued_count',(select count(*) from public.certificates x where x.batch_id=b.id and x.status='issued'),
      'created_at',b.created_at,'submitted_at',b.submitted_at,'approved_at',b.approved_at,'issued_at',b.issued_at
    ) order by b.created_at desc) from public.certificate_batches b
      join public.academic_years ay on ay.id=b.academic_year_id
      left join public.terms t on t.id=b.term_id left join public.classes c on c.id=b.class_id
      left join public.teacher_award_categories ac on ac.id=b.teacher_award_category_id
      left join public.profiles pp on pp.id=b.prepared_by left join public.profiles pa on pa.id=b.approved_by left join public.profiles pi on pi.id=b.issued_by
      where (target_academic_year_id is null or b.academic_year_id=target_academic_year_id)
        and (coalesce(target_certificate_type,'')='' or b.certificate_type=target_certificate_type)
    ),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_class_attendance_register(target_term_id uuid, target_class_id uuid, target_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare target_year_id uuid;term_start date;term_end date;register_row public.class_attendance_registers%rowtype;
begin
  if not public.is_assigned_class_teacher(target_class_id) then raise exception 'You can mark attendance only for your assigned class' using errcode='42501'; end if;
  if target_term_id is null or target_date is null then raise exception 'Term and attendance date are required'; end if;
  select t.academic_year_id,t.start_date,t.end_date into target_year_id,term_start,term_end
  from public.terms t where t.id=target_term_id and t.deleted_at is null;
  if target_year_id is null then raise exception 'Term is unavailable'; end if;
  if term_start is not null and target_date<term_start then raise exception 'Attendance date is before the selected term'; end if;
  if term_end is not null and target_date>term_end then raise exception 'Attendance date is after the selected term'; end if;
  select * into register_row from public.class_attendance_registers r
  where r.term_id=target_term_id and r.class_id=target_class_id and r.attendance_date=target_date;
  return jsonb_build_object(
    'register',case when register_row.id is null then null else to_jsonb(register_row) end,
    'term',jsonb_build_object('id',target_term_id,'start_date',term_start,'end_date',term_end,'academic_year_id',target_year_id),
    'class',(select jsonb_build_object('id',c.id,'name',c.name) from public.classes c where c.id=target_class_id),
    'days_school_opened',(select count(*) from public.class_attendance_registers r where r.term_id=target_term_id and r.class_id=target_class_id),
    'students',coalesce((
      select jsonb_agg(jsonb_build_object(
        'enrollment_id',e.id,'student_id',s.id,'admission_no',s.admission_no,
        'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
        'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'roll_number',e.roll_number,
        'attendance_status',coalesce(a.attendance_status,'present'),
        'days_present',counts.days_present,
        'days_school_opened',counts.days_school_opened
      ) order by lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text)
      from public.enrollments e
      join public.students s on s.id=e.student_id and s.deleted_at is null and s.status='active'
      left join public.student_attendance_entries a on a.register_id=register_row.id and a.enrollment_id=e.id
      cross join lateral public.attendance_counts_for_enrollment(e.id,target_term_id) counts
      where e.academic_year_id=target_year_id
        and e.class_id=target_class_id
        and e.deleted_at is null
    ),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_class_timetable_console(target_academic_year_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 if target_academic_year_id is null or target_class_id is null then raise exception 'Academic year and class are required';end if;
 if not public.can_view_class_timetable(target_class_id) then raise exception 'You are not allowed to view this class timetable' using errcode='42501';end if;
 perform public.require_license_feature('timetable');
 return jsonb_build_object(
  'academic_year',(select to_jsonb(y) from public.academic_years y where y.id=target_academic_year_id and y.deleted_at is null),
  'class',(select to_jsonb(c) from public.classes c where c.id=target_class_id and c.deleted_at is null),
  'entries',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',e.id,'academic_year_id',e.academic_year_id,'class_id',e.class_id,'day_of_week',e.day_of_week,
      'period_start',e.period_start,'period_end',e.period_end,'subject_id',e.subject_id,'subject_name',s.name,
      'teacher_id',e.teacher_id,'teacher_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),
      'notes',e.notes,'active',e.active,'updated_at',e.updated_at
    ) order by array_position(array['Monday','Tuesday','Wednesday','Thursday','Friday'],e.day_of_week),e.period_start)
    from public.class_timetable_entries e
    join public.subjects s on s.id=e.subject_id
    join public.teachers t on t.id=e.teacher_id
    where e.academic_year_id=target_academic_year_id
      and e.class_id=target_class_id
      and e.active
      and e.day_of_week in ('Monday','Tuesday','Wednesday','Thursday','Friday')
  ),'[]'::jsonb),
  'teachers',case when public.is_system_admin() then coalesce((
    select jsonb_agg(jsonb_build_object('id',t.id,'name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'staff_no',t.staff_no) order by t.last_name,t.first_name)
    from public.teachers t where t.deleted_at is null and t.active and t.employment_status='active'
  ),'[]'::jsonb) else '[]'::jsonb end,
  'subjects',coalesce((
    select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'code',s.code) order by s.display_order,s.name)
    from public.subjects s where s.deleted_at is null and s.active
  ),'[]'::jsonb),
  'can_manage',public.is_system_admin()
 );
end$function$
;

CREATE OR REPLACE FUNCTION public.get_compliance_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'retention_policies',coalesce((select jsonb_agg(to_jsonb(p) order by p.data_category) from public.data_retention_policies p),'[]'::jsonb),
    'privacy_requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'student_id',r.student_id,'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'request_type',r.request_type,'requester_name',r.requester_name,'requester_contact',r.requester_contact,'request_details',r.request_details,'status',r.status,'due_at',r.due_at,'outcome',r.outcome,'created_at',r.created_at,'completed_at',r.completed_at) order by r.created_at desc) from public.privacy_requests r left join public.students s on s.id=r.student_id),'[]'::jsonb),
    'security_events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'event_type',e.event_type,'severity',e.severity,'source',e.source,'message',e.message,'details',e.details,'status',e.status,'created_at',e.created_at,'actor_name',p.full_name,'resolution_note',e.resolution_note) order by e.created_at desc) from public.security_events e left join public.profiles p on p.id=e.actor_id where e.created_at>=now()-interval '180 days' limit 500),'[]'::jsonb),
    'verification_runs',coalesce((select jsonb_agg(to_jsonb(v) order by v.verified_at desc) from public.security_verification_runs v),'[]'::jsonb),
    'open_privacy_requests',(select count(*) from public.privacy_requests where status in ('open','in_review')),
    'overdue_privacy_requests',(select count(*) from public.privacy_requests where status in ('open','in_review') and due_at<now()),
    'open_high_security_events',(select count(*) from public.security_events where status='open' and severity in ('high','critical'))
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_current_principal_signature()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select jsonb_build_object(
    'headteacher_id',h.id,
    'profile_id',h.profile_id,
    'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
    'contact',h.phone,
    'signature_path',h.signature_path,
    'signature_updated_at',h.signature_updated_at
  )
  into result
  from public.headteachers h
  where h.deleted_at is null
    and h.active
    and h.employment_status='active'
  order by
    case when btrim(coalesce(h.signature_path,''))<>'' then 0 else 1 end,
    h.updated_at desc,
    h.created_at desc
  limit 1;
  return coalesce(
    result,
    jsonb_build_object(
      'full_name',coalesce((select s.head_name from public.school_settings s order by s.created_at limit 1),'Principal'),
      'signature_path',''
    )
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare termid uuid;
begin
  termid:=target_term_id;
  if termid is null then select id into termid from public.terms where is_active and deleted_at is null limit 1; end if;
  return jsonb_build_object(
    'active_students',(select count(*) from public.students s where s.status='active' and s.deleted_at is null and public.can_view_student(s.id)),
    'active_classes',(select count(*) from public.classes c where c.active and c.deleted_at is null and (public.is_records_manager() or public.can_access_class(c.id,false))),
    'reports',(select count(*) from public.student_reports r where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id)),
    'published',(select count(*) from public.student_reports r where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)),
    'by_status',coalesce((select jsonb_object_agg(status,count_value) from (
      select r.status::text status,count(*) count_value from public.student_reports r
      where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id) group by r.status
    ) q),'{}'::jsonb),
    'class_performance',coalesce((select jsonb_agg(to_jsonb(q) order by q.class_name) from (
      select c.id class_id,c.name class_name,round(avg(sr.total_score),2) average
      from public.subject_results sr
      join public.student_reports r on r.id=sr.report_id
      join public.enrollments e on e.id=r.enrollment_id
      join public.classes c on c.id=e.class_id
      where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)
      group by c.id,c.name
    ) q),'[]'::jsonb),
    'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        c.name class_name,t.name term_name,
        round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r
      join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id
      join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id
      left join public.subject_results sr on sr.report_id=r.id
      where r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,s.id,c.id,t.id order by r.updated_at desc limit 8
    ) q),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_emergency_delegation_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare actor_role text:=public.current_app_role()::text;
begin
  if actor_role not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'delegations',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select d.*,c.name class_name,t.name term_name,y.name academic_year_name,s.name subject_name,
        dp.full_name delegate_name,public.current_app_role_for(dp.role)::text delegate_role,
        op.full_name original_teacher_name,cp.full_name created_by_name,ap.full_name acknowledged_by_name,rp.full_name revoked_by_name,
        case when d.status='revoked' then 'revoked'
          when now()<d.valid_from then 'scheduled'
          when now()>=d.valid_until then 'expired'
          else 'active' end computed_status
      from public.emergency_academic_delegations d
      join public.classes c on c.id=d.class_id
      join public.terms t on t.id=d.term_id
      join public.academic_years y on y.id=d.academic_year_id
      left join public.subjects s on s.id=d.subject_id
      join public.profiles dp on dp.id=d.delegate_user_id
      left join public.profiles op on op.id=d.original_teacher_id
      left join public.profiles cp on cp.id=d.created_by
      left join public.profiles ap on ap.id=d.principal_acknowledged_by
      left join public.profiles rp on rp.id=d.revoked_by
      order by d.created_at desc limit 300
    ) q),'[]'::jsonb),
    'eligible_users',coalesce((select jsonb_agg(to_jsonb(q) order by lower(q.full_name),q.email) from (
      select p.id,p.full_name,au.email::text,public.current_app_role_for(p.role)::text role,t.staff_no
      from public.profiles p
      left join auth.users au on au.id=p.id
      left join public.teachers t on t.profile_id=p.id and t.deleted_at is null
      where p.active and public.current_app_role_for(p.role)::text in ('system_admin','class_teacher','subject_teacher')
    ) q),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.level_order,q.class_name,q.subject_order,q.subject_name) from (
      select cs.class_id,c.name class_name,c.level_order,cs.subject_id,s.name subject_name,s.code subject_code,s.display_order subject_order,
        cs.teacher_id,p.full_name assigned_teacher_name
      from public.class_subjects cs
      join public.classes c on c.id=cs.class_id
      join public.subjects s on s.id=cs.subject_id
      left join public.profiles p on p.id=cs.teacher_id
      where cs.active and c.active and c.deleted_at is null and s.active and s.deleted_at is null
    ) q),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select e.id,e.delegation_id,e.event_type,e.actor_id,e.report_id,e.subject_id,e.event_reason,e.event_data,e.created_at,
        p.full_name actor_name,s.name subject_name
      from public.emergency_academic_delegation_events e
      left join public.profiles p on p.id=e.actor_id
      left join public.subjects s on s.id=e.subject_id
      order by e.created_at desc limit 300
    ) q),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_headteacher_record(target_headteacher_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.can_manage_headteachers() and not exists(
    select 1 from public.headteachers h where h.id=target_headteacher_id and h.profile_id=auth.uid()
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  return (
    select jsonb_build_object(
      'principal',to_jsonb(h)||jsonb_build_object(
        'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
        'profile_email',au.email,'profile_name',p.full_name,
        'profile_role',case when p.id is null then null else public.current_app_role_for(p.role) end
      )
    )
    from public.headteachers h
    left join public.profiles p on p.id=h.profile_id
    left join auth.users au on au.id=h.profile_id
    where h.id=target_headteacher_id
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_id_card_console(target_academic_year_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, target_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare year_id uuid:=target_academic_year_id;settings_row jsonb;cards_json jsonb;stats_json jsonb; begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage student ID cards' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit ID card access' using errcode='42501';end if; if year_id is null then select id into year_id from public.academic_years where is_active and deleted_at is null order by start_date desc nulls last,created_at desc limit 1;end if; select to_jsonb(x) into settings_row from public.id_card_settings x limit 1; select coalesce(jsonb_agg(to_jsonb(q) order by q.issued_at desc),'[]'::jsonb) into cards_json from (select c.id,c.student_id,c.enrollment_id,c.academic_year_id,c.class_id,c.card_number,c.verification_token,c.revision_no,c.supersedes_card_id,c.status,public.id_card_effective_status(c.status,c.expires_on) computed_status,c.issue_date,c.expires_on,c.snapshot,c.issued_at,c.revoked_at,c.revocation_reason,c.replacement_reason,c.snapshot#>>'{student,full_name}' student_name,c.snapshot#>>'{student,admission_no}' admission_no,c.snapshot#>>'{academic,class_name}' class_name,c.snapshot#>>'{academic,academic_year_name}' academic_year_name from public.student_id_cards c where (year_id is null or c.academic_year_id=year_id) and (target_class_id is null or c.class_id=target_class_id) and (target_status is null or target_status='' or public.id_card_effective_status(c.status,c.expires_on)=target_status) order by c.issued_at desc limit 1500) q; select jsonb_build_object('total',count(*),'active',count(*) filter(where public.id_card_effective_status(status,expires_on)='active'),'expired',count(*) filter(where public.id_card_effective_status(status,expires_on)='expired'),'revoked',count(*) filter(where status='revoked'),'replaced',count(*) filter(where status='replaced')) into stats_json from public.student_id_cards c where (year_id is null or c.academic_year_id=year_id) and (target_class_id is null or c.class_id=target_class_id); return jsonb_build_object('generated_at',now(),'settings',coalesce(settings_row,'{}'::jsonb),'academic_year_id',year_id,'stats',stats_json,'cards',cards_json,'feature_enabled',true); end$function$
;

CREATE OR REPLACE FUNCTION public.get_my_emergency_academic_delegations(target_class_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(q) order by q.valid_until,q.class_name,q.subject_name nulls first),'[]'::jsonb)
  from (
    select d.id,d.delegation_type,d.academic_year_id,d.term_id,d.class_id,d.subject_id,
      d.allow_score_entry,d.allow_class_report_fields,d.valid_from,d.valid_until,d.reason,
      d.principal_acknowledged_at,c.name class_name,t.name term_name,y.name academic_year_name,
      s.name subject_name,op.full_name original_teacher_name,cp.full_name created_by_name
    from public.emergency_academic_delegations d
    join public.classes c on c.id=d.class_id
    join public.terms t on t.id=d.term_id
    join public.academic_years y on y.id=d.academic_year_id
    left join public.subjects s on s.id=d.subject_id
    left join public.profiles op on op.id=d.original_teacher_id
    left join public.profiles cp on cp.id=d.created_by
    where d.delegate_user_id=auth.uid()
      and d.status='active' and now()>=d.valid_from and now()<d.valid_until
      and (target_class_id is null or d.class_id=target_class_id)
      and (target_term_id is null or d.term_id=target_term_id)
  ) q
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_headteacher_signature()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result jsonb;
begin
  if auth.uid() is null or public.current_app_role()<>'principal' then raise exception 'Access denied' using errcode='42501'; end if;
  select jsonb_build_object('linked',true,'headteacher_id',h.id,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'contact',h.phone,'signature_path',h.signature_path,'signature_updated_at',h.signature_updated_at,'updated_at',h.updated_at)
  into result from public.headteachers h where h.profile_id=auth.uid() and h.deleted_at is null and h.active order by h.updated_at desc limit 1;
  return coalesce(result,jsonb_build_object('linked',false,'full_name',(select p.full_name from public.profiles p where p.id=auth.uid()),'signature_path',''));
end $function$
;

CREATE OR REPLACE FUNCTION public.get_my_teacher_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare tid uuid;
begin
  if auth.uid() is null or public.current_app_role() not in ('class_teacher','subject_teacher') then raise exception 'Teacher access required' using errcode='42501';end if;
  select id into tid from public.teachers where profile_id=auth.uid() and deleted_at is null order by active desc,updated_at desc limit 1;
  if tid is null then return jsonb_build_object('linked',false,'teacher',null,'classes','[]'::jsonb,'subjects','[]'::jsonb,'assigned_class_count',0);end if;
  return (select jsonb_build_object(
    'linked',true,
    'teacher',to_jsonb(t)||jsonb_build_object('full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'profile_email',au.email),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb),
    'assigned_class_count',(select count(distinct x.class_id) from (select c.id class_id from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null union select cs.class_id from public.class_subjects cs where cs.teacher_id=t.profile_id and cs.active) x)
  ) from public.teachers t left join auth.users au on au.id=t.profile_id where t.id=tid);
end$function$
;

CREATE OR REPLACE FUNCTION public.get_platform_license_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb;
begin
  perform public.require_platform_super_admin();s:=public.license_snapshot_for_role('system_admin');return jsonb_build_object(
    'school',(select jsonb_build_object('id',x.id,'school_name',x.school_name,'logo_url',x.logo_url,'email',x.email,'phone',x.phone) from public.school_settings x limit 1),
    'snapshot',s,'license',(select to_jsonb(l)-'license_key_hash' from public.school_licenses l order by l.created_at limit 1),
    'plans',coalesce((select jsonb_agg(to_jsonb(p) order by p.active desc,p.name) from public.license_plans p),'[]'::jsonb),
    'feature_catalog',coalesce((select jsonb_agg(to_jsonb(f) order by f.category,f.name) from public.license_feature_catalog f where f.active),'[]'::jsonb),
    'plan_revisions',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from (select * from public.license_plan_revisions order by created_at desc limit 100) r),'[]'::jsonb),
    'active_override',(select to_jsonb(o) from public.license_entitlement_overrides o join public.school_licenses l on l.id=o.license_id where o.active order by o.created_at desc limit 1),
    'distribution_authority',(select to_jsonb(a) from public.platform_distribution_authorities a where a.actor_id=auth.uid() limit 1),
    'distribution_authorities',coalesce((select jsonb_agg(to_jsonb(q) order by lower(q.full_name)) from (select a.*,p.full_name from public.platform_distribution_authorities a join public.profiles p on p.id=a.actor_id) q),'[]'::jsonb),
    'usage',jsonb_build_object('active_students',(select count(*) from public.students x where x.status='active' and x.deleted_at is null),'active_teachers',(select count(*) from public.teachers x where x.active and x.deleted_at is null),'active_system_admins',(select count(*) from public.profiles x where x.active and public.current_app_role_for(x.role)::text='system_admin'),'active_guardians',(select count(*) from public.profiles x where x.active and public.current_app_role_for(x.role)::text='parent_guardian'),'storage_mb',(select round(coalesce(sum(case when coalesce(x.metadata->>'size','')~'^\d+$' then (x.metadata->>'size')::numeric else 0 end),0)/1048576.0,2) from storage.objects x where x.bucket_id in ('student-photos','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs')),'published_reports',(select count(*) from public.student_reports x where x.status='published')),
    'active_locks',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.platform_access_locks x where x.active and (x.ends_at is null or x.ends_at>now())),'[]'::jsonb),
    'recent_events',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select e.*,coalesce(p.full_name,'System') actor_name from public.license_events e left join public.profiles p on p.id=e.actor_id order by e.created_at desc limit 200) q),'[]'::jsonb),
    'verification_history',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select * from public.license_verification_logs order by created_at desc limit 100) q),'[]'::jsonb),
    'archives',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.platform_audit_archives a where a.archive_scope='licensing'),'[]'::jsonb),
    'platform_admins',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'email',u.email,'active',p.active,'mfa_required',p.mfa_required,'last_seen_at',p.last_seen_at,'created_at',p.created_at) order by lower(p.full_name)) from public.profiles p left join auth.users u on u.id=p.id where public.current_app_role_for(p.role)::text='platform_super_admin'),'[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.get_recovery_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'tests',coalesce((select jsonb_agg(to_jsonb(r) order by r.started_at desc) from public.recovery_test_runs r limit 50),'[]'::jsonb),
    'latest_passed',(select max(completed_at) from public.recovery_test_runs where status='passed'),
    'latest_failed',(select max(completed_at) from public.recovery_test_runs where status='failed')
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_report_correction_console(target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'requests',coalesce((select jsonb_agg(jsonb_build_object(
      'id',q.id,'report_id',q.report_id,'status',q.status,'reason',q.reason,'requested_fields',q.requested_fields,
      'requested_by',q.requested_by,'requester_name',rp.full_name,'reviewed_by',q.reviewed_by,'reviewer_name',vp.full_name,
      'review_note',q.review_note,'created_at',q.created_at,'reviewed_at',q.reviewed_at,'applied_at',q.applied_at,
      'report_number',r.report_number,'report_status',r.status,'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
      'class_id',e.class_id,'class_name',c.name,'term_id',r.term_id,'term_name',t.name
    ) order by q.created_at desc)
    from public.report_correction_requests q
    join public.student_reports r on r.id=q.report_id
    join public.enrollments e on e.id=r.enrollment_id
    join public.students s on s.id=e.student_id
    join public.classes c on c.id=e.class_id
    join public.terms t on t.id=r.term_id
    left join public.profiles rp on rp.id=q.requested_by left join public.profiles vp on vp.id=q.reviewed_by
    where (target_term_id is null or r.term_id=target_term_id)
      and (target_class_id is null or e.class_id=target_class_id)
      and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(e.class_id,false))),'[]'::jsonb),
    'pending_count',(select count(*) from public.report_correction_requests q join public.student_reports r on r.id=q.report_id join public.enrollments e on e.id=r.enrollment_id where q.status='pending' and (target_term_id is null or r.term_id=target_term_id) and (target_class_id is null or e.class_id=target_class_id) and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(e.class_id,false)))
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_report_editor(target_report_id uuid DEFAULT NULL::uuid, target_enrollment_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid:=target_report_id; enrollmentid uuid:=target_enrollment_id; termid uuid:=target_term_id; classid uuid; yearid uuid; report_json jsonb; student_json jsonb; canedit boolean; canfields boolean;
begin
  if rid is not null then
    if not public.can_view_report(rid) then raise exception 'Access denied' using errcode='42501'; end if;
    select r.enrollment_id,r.term_id,e.class_id,e.academic_year_id,to_jsonb(r) into enrollmentid,termid,classid,yearid,report_json
    from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.id=rid and r.deleted_at is null;
    if report_json is null then raise exception 'Report not found'; end if;
  else
    select e.class_id,e.academic_year_id into classid,yearid from public.enrollments e where e.id=enrollmentid and e.deleted_at is null;
    if classid is null or not public.can_create_report_for_class_term(classid,termid) then raise exception 'Access denied' using errcode='42501'; end if;
    if not exists(select 1 from public.terms t where t.id=termid and t.academic_year_id=yearid and t.deleted_at is null) then raise exception 'Term and enrolment academic year do not match'; end if;
    select to_jsonb(r) into report_json from public.student_reports r where r.enrollment_id=enrollmentid and r.term_id=termid and r.deleted_at is null;
    if report_json is not null then rid:=(report_json->>'id')::uuid;
    else report_json:=jsonb_build_object('id',null,'enrollment_id',enrollmentid,'term_id',termid,'status','draft','version',0,'days_school_opened',0,'days_present',0,'attitude','','conduct','','interest','','teacher_comment','','head_comment','','promoted_to_class_id',null); end if;
  end if;
  select jsonb_build_object('id',s.id,'admission_no',s.admission_no,'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
    'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'gender',s.gender,'date_of_birth',s.date_of_birth,'photo_url',s.photo_url,
    'class_id',e.class_id,'class_name',c.name,'academic_year_id',e.academic_year_id,'academic_year_name',y.name,'roll_number',e.roll_number,
    'term_name',t.name,'term_sequence',t.sequence,'next_term_begins',t.next_term_begins) into student_json
  from public.enrollments e join public.students s on s.id=e.student_id join public.classes c on c.id=e.class_id join public.academic_years y on y.id=e.academic_year_id join public.terms t on t.id=termid where e.id=enrollmentid;
  canedit:=case when rid is null then public.can_create_report_for_class_term(classid,termid) else public.can_edit_report(rid) end;
  canfields:=(public.can_manage_class_report_fields_for_term(classid,termid) or (rid is not null and public.has_approved_report_correction(rid) and public.can_manage_class_report_fields_scope(classid,termid))) and coalesce(report_json->>'status','draft') in ('draft','returned','withdrawn');
  return jsonb_build_object('report',report_json,'student',student_json,'can_edit',canedit,'can_edit_fields',canfields,
    'allowed_transitions',case when rid is null then '[]'::jsonb else to_jsonb(public.allowed_report_transitions(rid)) end,
    'subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.display_order,q.subject_name) from (
      select sb.id subject_id,sb.code subject_code,sb.name subject_name,sb.display_order,(public.can_score_class_subject_for_term(classid,sb.id,termid) or (rid is not null and public.has_approved_report_correction(rid) and public.can_score_class_subject_scope(classid,sb.id,termid))) and coalesce(report_json->>'status','draft') in ('draft','returned','withdrawn') can_score,
        coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid)) scheme_id,sc.name scheme_name,sr.id result_id,
        coalesce(sr.total_score,0) total_score,coalesce(sr.grade,'') grade,coalesce(sr.remark,'') remark,coalesce(sr.grade_point,0) grade_point,coalesce(sr.teacher_initials,'') teacher_initials,
        coalesce((select jsonb_agg(jsonb_build_object('component_id',ac.id,'name',ac.name,'code',ac.code,'maximum_score',ac.maximum_score,'weight',ac.weight,'required',ac.required,'display_order',ac.display_order,
          'raw_score',coalesce(se.raw_score,0),'weighted_score',coalesce(se.weighted_score,0)) order by ac.display_order,ac.name)
          from public.assessment_components ac left join public.assessment_score_entries se on se.component_id=ac.id and se.subject_result_id=sr.id
          where ac.scheme_id=coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid))),'[]'::jsonb) components
      from public.class_subjects cs join public.subjects sb on sb.id=cs.subject_id left join public.subject_results sr on sr.report_id=rid and sr.subject_id=sb.id
      left join public.assessment_schemes sc on sc.id=coalesce(sr.scheme_id,public.resolve_assessment_scheme(classid,sb.id,yearid,termid))
      where cs.class_id=classid and cs.active and sb.active and sb.deleted_at is null
    ) q),'[]'::jsonb),
    'emergency_delegations',public.get_my_emergency_academic_delegations(classid,termid),
    'workflow',case when rid is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select w.*,p.full_name actor_name from public.report_workflow_events w left join public.profiles p on p.id=w.actor_id where w.report_id=rid) q),'[]'::jsonb) end,
    'publications',case when rid is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(p) order by p.published_at desc) from public.report_publications p where p.report_id=rid),'[]'::jsonb) end);
end $function$
;

CREATE OR REPLACE FUNCTION public.get_report_grading_guide(target_report_id uuid DEFAULT NULL::uuid, target_enrollment_id uuid DEFAULT NULL::uuid, target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_report public.student_reports;
  v_class_id uuid;
  v_year_id uuid;
  v_snapshot jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if target_report_id is not null then
    if not public.can_view_report(target_report_id) then raise exception 'Access denied' using errcode='42501'; end if;
    select r.* into v_report from public.student_reports r where r.id=target_report_id and r.deleted_at is null;
    if v_report.id is null then raise exception 'Report not found'; end if;
    if v_report.status in ('submitted','class_reviewed','approved','published')
       and jsonb_typeof(v_report.grading_scale_snapshot)='object'
       and jsonb_array_length(coalesce(v_report.grading_scale_snapshot->'rows','[]'::jsonb))>0 then
      return v_report.grading_scale_snapshot;
    end if;
    return public.resolve_report_grading_guide(v_report.id);
  end if;
  if target_enrollment_id is null or target_term_id is null then
    raise exception 'Report, enrolment, or term scope is required';
  end if;
  select e.class_id,e.academic_year_id into v_class_id,v_year_id
  from public.enrollments e
  where e.id=target_enrollment_id and e.deleted_at is null;
  if v_class_id is null then raise exception 'Enrolment not found'; end if;
  if not public.can_create_report_for_class_term(v_class_id,target_term_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.terms t
    where t.id=target_term_id and t.academic_year_id=v_year_id and t.deleted_at is null
  ) then raise exception 'Term and enrolment academic year do not match'; end if;
  return public.resolve_grading_guide(v_year_id,v_class_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.get_report_headteacher_signature(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  result jsonb;
begin
  if auth.uid() is null or not public.can_view_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select jsonb_build_object(
    'headteacher_id',h.id,
    'profile_id',h.profile_id,
    'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
    'contact',h.phone,
    'signature_path',h.signature_path,
    'signature_updated_at',h.signature_updated_at
  )
  into result
  from public.headteachers h
  where h.deleted_at is null
    and h.active
    and h.employment_status='active'
  order by
    case when btrim(coalesce(h.signature_path,''))<>'' then 0 else 1 end,
    h.updated_at desc,
    h.created_at desc
  limit 1;
  return coalesce(
    result,
    jsonb_build_object(
      'full_name',coalesce((select s.head_name from public.school_settings s order by s.created_at limit 1),'Principal'),
      'signature_path',''
    )
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_report_revisions(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_report(target_report_id) then raise exception 'Access denied' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',rr.id,'version',rr.version,'reason',rr.reason,'actor_id',rr.actor_id,
    'actor_name',p.full_name,'created_at',rr.created_at,'snapshot',rr.snapshot
  ) order by rr.version desc)
  from public.report_revisions rr left join public.profiles p on p.id=rr.actor_id
  where rr.report_id=target_report_id),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.get_role_dashboard(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare termid uuid:=target_term_id;
declare v_current_role text:=public.current_app_role()::text;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if termid is null then select id into termid from public.terms where is_active and deleted_at is null limit 1; end if;
  return jsonb_build_object(
    'role',v_current_role,
    'active_students',(select count(*) from public.students s where s.status='active' and s.deleted_at is null and public.can_view_student(s.id)),
    'active_classes',(select count(*) from public.classes c where c.active and c.deleted_at is null and (public.is_records_manager() or public.can_access_class(c.id,false))),
    'active_teachers',case when public.can_manage_teachers() or public.has_role(array['system_admin','principal','academic_admin'])
      then (select count(*) from public.teachers t where t.active and t.deleted_at is null) else 0 end,
    'active_users',case when public.is_system_admin() then (select count(*) from public.profiles p where p.active) else 0 end,
    'reports',(select count(*) from public.student_reports r where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id)),
    'published',(select count(*) from public.student_reports r where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)),
    'draft_returned',(select count(*) from public.student_reports r where r.term_id=termid and r.status in ('draft','returned') and r.deleted_at is null and public.can_view_report(r.id)),
    'pending_review',(select count(*) from public.student_reports r where r.term_id=termid and r.status in ('submitted','class_reviewed','approved') and r.deleted_at is null and public.can_view_report(r.id)),
    'assigned_classes',(select count(distinct c.id) from public.classes c where c.deleted_at is null and c.active and public.can_access_class(c.id,false)),
    'assigned_subjects',(select count(distinct cs.subject_id) from public.class_subjects cs join public.classes c on c.id=cs.class_id
      where cs.active and c.deleted_at is null and (cs.teacher_id=auth.uid() or public.is_academic_manager())),
    'missing_guardians',case when public.is_records_manager() then (
      select count(*) from public.students s where s.deleted_at is null and not exists(
        select 1 from public.guardian_links gl where gl.student_id=s.id
      )
    ) else 0 end,
    'missing_photos',case when public.is_records_manager() then (
      select count(*) from public.students s where s.deleted_at is null and btrim(coalesce(s.photo_url,''))=''
    ) else 0 end,
    'children',case when v_current_role='parent_guardian' then (
      select count(distinct gl.student_id) from public.guardian_links gl where gl.auth_user_id=auth.uid()
    ) else 0 end,
    'unread_notifications',(select count(*) from public.notifications n where n.recipient_id=auth.uid() and n.read_at is null),
    'average',coalesce((select round(avg(sr.total_score),2) from public.subject_results sr
      join public.student_reports r on r.id=sr.report_id
      where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)),0),
    'by_status',coalesce((select jsonb_object_agg(status,count_value) from (
      select r.status::text status,count(*) count_value from public.student_reports r
      where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id) group by r.status
    ) q),'{}'::jsonb),
    'class_performance',coalesce((select jsonb_agg(to_jsonb(q) order by q.class_name) from (
      select c.id class_id,c.name class_name,round(avg(sr.total_score),2) average
      from public.subject_results sr join public.student_reports r on r.id=sr.report_id
      join public.enrollments e on e.id=r.enrollment_id join public.classes c on c.id=e.class_id
      where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)
      group by c.id,c.name
    ) q),'[]'::jsonb),
    'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        c.name class_name,t.name term_name,round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id left join public.subject_results sr on sr.report_id=r.id
      where r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,s.id,c.id,t.id order by r.updated_at desc limit 8
    ) q),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_role_workspace()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare termid uuid; v_current_role text:=public.current_app_role();
begin
  if v_current_role not in ('class_teacher','subject_teacher','system_admin','principal','academic_admin') then return jsonb_build_object('classes','[]'::jsonb,'subjects','[]'::jsonb); end if;
  select id into termid from public.terms where is_active and deleted_at is null limit 1;
  return jsonb_build_object(
    'classes',coalesce((select jsonb_agg(to_jsonb(q) order by q.level_order,q.class_name) from (
      select c.id class_id,c.name class_name,c.level_order,
        (select count(*) from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and s.deleted_at is null) student_count,
        (select count(*) from public.class_subjects cs where cs.class_id=c.id and cs.active) subject_count,
        (select count(*) from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and s.deleted_at is null) expected_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('published','approved')) completed_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('draft','returned')) open_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('submitted','class_reviewed','approved')) review_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status='published') published_reports
      from public.classes c where c.active and c.deleted_at is null and public.can_manage_class_report_fields_for_term(c.id,termid)
    ) q),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.class_name,q.subject_name) from (
      select c.id class_id,c.name class_name,s.id subject_id,s.code subject_code,s.name subject_name,
        (select count(*) from public.enrollments e join public.students st on st.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and st.deleted_at is null) student_count,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('draft','returned')) open_reports,
        (select count(*) from public.subject_results sr join public.student_reports r on r.id=sr.report_id join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and sr.subject_id=s.id and r.term_id=termid and r.deleted_at is null) scored_reports,
        (select count(*) from public.enrollments e join public.students st on st.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and st.deleted_at is null) expected_reports
      from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id
      where cs.active and c.active and c.deleted_at is null and s.active and s.deleted_at is null and public.can_score_class_subject_for_term(c.id,s.id,termid)
    ) q),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_school_license_capacity_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_catalog', 'extensions'
AS $function$ declare actor_role text:=coalesce(public.current_app_role()::text,'');snapshot jsonb;entitlement jsonb;plan_data jsonb;students_count bigint:=0;teachers_count bigint:=0;admins_count bigint:=0;guardians_count bigint:=0;published_reports_count bigint:=0;storage_bytes bigint:=0;storage_mb numeric:=0;storage_breakdown jsonb:='[]'::jsonb;verification_rows jsonb:='[]'::jsonb; begin if actor_role<>'system_admin' then raise exception 'School System Administrator access required' using errcode='42501';end if;snapshot:=public.license_snapshot_for_role('system_admin');entitlement:=public.license_effective_entitlement();plan_data:=coalesce(entitlement->'plan',snapshot->'plan','{}'::jsonb);select count(*) into students_count from public.students where status='active' and deleted_at is null;select count(*) into teachers_count from public.teachers where active and deleted_at is null;select count(*) into admins_count from public.profiles where active and public.current_app_role_for(role)::text='system_admin';select count(*) into guardians_count from public.profiles where active and public.current_app_role_for(role)::text='parent_guardian';select count(*) into published_reports_count from public.student_reports where status='published';select coalesce(sum(case when coalesce(metadata->>'size','')~'^\d+$' then (metadata->>'size')::bigint else 0 end),0) into storage_bytes from storage.objects where bucket_id in ('student-photos','staff-photos','school-branding','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs');storage_mb:=round(storage_bytes/1048576.0,2);select coalesce(jsonb_agg(jsonb_build_object('bucket_id',bucket_id,'object_count',object_count,'bytes',bucket_bytes,'storage_mb',round(bucket_bytes/1048576.0,2)) order by bucket_id),'[]'::jsonb) into storage_breakdown from (select bucket_id,count(*)::bigint object_count,coalesce(sum(case when coalesce(metadata->>'size','')~'^\d+$' then (metadata->>'size')::bigint else 0 end),0)::bigint bucket_bytes from storage.objects where bucket_id in ('student-photos','staff-photos','school-branding','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs') group by bucket_id)bucket_usage;select coalesce(jsonb_agg(jsonb_build_object('created_at',created_at,'computed_status',computed_status,'access_mode',access_mode,'verification_source',verification_source) order by created_at desc),'[]'::jsonb) into verification_rows from (select created_at,computed_status,access_mode,verification_source from public.license_verification_logs order by created_at desc limit 20)verification_history; return jsonb_build_object('read_only',true,'generated_at',now(),'school',(select jsonb_build_object('id',id,'school_name',school_name,'logo_url',logo_url,'email',email,'phone',phone) from public.school_settings limit 1),'snapshot',snapshot,'plan',plan_data,'capacity',jsonb_build_array(jsonb_build_object('key','students','label','Active students','unit','records','used',students_count,'limit',nullif(plan_data->>'max_students','')::bigint),jsonb_build_object('key','teachers','label','Active teachers','unit','records','used',teachers_count,'limit',nullif(plan_data->>'max_teachers','')::bigint),jsonb_build_object('key','system_admins','label','System Administrators','unit','accounts','used',admins_count,'limit',nullif(plan_data->>'max_system_admins','')::bigint),jsonb_build_object('key','guardians','label','Guardians','unit','accounts','used',guardians_count,'limit',nullif(plan_data->>'max_guardians','')::bigint),jsonb_build_object('key','storage','label','School Storage','unit','MB','used',storage_mb,'limit',nullif(plan_data->>'max_storage_mb','')::numeric)),'usage',jsonb_build_object('active_students',students_count,'active_teachers',teachers_count,'active_system_admins',admins_count,'active_guardians',guardians_count,'published_reports',published_reports_count,'storage_bytes',storage_bytes,'storage_mb',storage_mb),'storage_buckets',storage_breakdown,'feature_flags',coalesce(plan_data->'feature_flags','{}'::jsonb),'verification_history',verification_rows); end$function$
;

CREATE OR REPLACE FUNCTION public.get_school_prospectus_console(target_academic_year_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare yearid uuid:=target_academic_year_id; rows jsonb;
begin
 if not public.is_system_admin() then raise exception 'School System Administrator access required' using errcode='42501';end if;perform public.require_license_feature('school_prospectus');
 if yearid is null then select id into yearid from public.academic_years where deleted_at is null order by is_current desc,coalesce(start_date,'1900-01-01') desc,created_at desc limit 1;end if;
 select coalesce(jsonb_agg(public.build_school_prospectus_snapshot(p.id)||jsonb_build_object('revision_history',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'revision_no',r.revision_no,'reason',r.reason,'published_at',r.published_at) order by r.revision_no desc) from public.school_prospectus_revisions r where r.prospectus_id=p.id),'[]'::jsonb)) order by p.class_range),'[]'::jsonb) into rows from public.school_prospectuses p where p.academic_year_id=yearid;
 return jsonb_build_object('academic_year_id',yearid,'prospectuses',rows,'can_manage',true,'generated_at',now());
end$function$
;

CREATE OR REPLACE FUNCTION public.get_staff_id_card_console(target_staff_type text DEFAULT NULL::text, target_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare settings_row jsonb;cards_json jsonb;stats_json jsonb;kind text:=lower(btrim(coalesce(target_staff_type,'')));
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage staff ID cards' using errcode='42501';end if;perform public.require_license_feature('staff_id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit staff ID card access' using errcode='42501';end if;if kind not in ('','teacher','principal') then raise exception 'Invalid staff type filter';end if;select to_jsonb(x) into settings_row from public.id_card_settings x limit 1;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.issued_at desc),'[]'::jsonb) into cards_json from (select c.id,c.staff_type,c.teacher_id,c.headteacher_id,c.academic_year_id,c.card_number,c.verification_token,c.revision_no,c.supersedes_card_id,c.status,public.id_card_effective_status(c.status,c.expires_on) computed_status,c.issue_date,c.expires_on,c.snapshot,c.issued_at,c.revoked_at,c.revocation_reason,c.replacement_reason,c.snapshot#>>'{staff,full_name}' staff_name,c.snapshot#>>'{staff,staff_no}' staff_no,c.snapshot#>>'{staff,role}' staff_role,c.snapshot#>>'{academic,academic_year_name}' academic_year_name from public.staff_id_cards c where (kind='' or c.staff_type=kind) and (target_status is null or target_status='' or public.id_card_effective_status(c.status,c.expires_on)=target_status) order by c.issued_at desc limit 1500)q;
  select jsonb_build_object('total',count(*),'active',count(*) filter(where public.id_card_effective_status(status,expires_on)='active'),'expired',count(*) filter(where public.id_card_effective_status(status,expires_on)='expired'),'revoked',count(*) filter(where status='revoked'),'replaced',count(*) filter(where status='replaced')) into stats_json from public.staff_id_cards c where kind='' or c.staff_type=kind;
  return jsonb_build_object('generated_at',now(),'settings',coalesce(settings_row,'{}'::jsonb),'stats',stats_json,'cards',cards_json,'feature_enabled',true);
end$function$
;

CREATE OR REPLACE FUNCTION public.get_student_academic_history(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_student_history(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'transcript',public.build_student_transcript_snapshot(target_student_id),
    'issuances',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'verification_token',i.verification_token,'purpose',i.purpose,'status',i.status,'issued_at',i.issued_at,'issuer_name',p.full_name,'revoked_at',i.revoked_at,'revocation_reason',i.revocation_reason) order by i.issued_at desc) from public.transcript_issuances i left join public.profiles p on p.id=i.issued_by where i.student_id=target_student_id),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_student_record(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_student(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'student',(select to_jsonb(s) from public.students s where s.id=target_student_id and s.deleted_at is null),
    'enrollments',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc nulls last) from (
      select e.*,c.name class_name,y.name academic_year_name,y.start_date
      from public.enrollments e join public.classes c on c.id=e.class_id
      join public.academic_years y on y.id=e.academic_year_id
      where e.student_id=target_student_id and e.deleted_at is null
    ) q),'[]'::jsonb),
    'guardians',coalesce((select jsonb_agg(to_jsonb(q) order by q.is_primary desc,q.full_name) from (
      select g.*,gl.auth_user_id,gl.can_view_reports,gl.can_receive_notifications,gl.verified_at
      from public.student_guardians g join public.guardian_links gl on gl.guardian_id=g.id
      where gl.student_id=target_student_id
    ) q),'[]'::jsonb),
    'reports',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc,q.sequence desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,t.name term_name,t.sequence,
        y.name academic_year_name,y.start_date,c.name class_name,
        round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id
      join public.classes c on c.id=e.class_id left join public.subject_results sr on sr.report_id=r.id
      where e.student_id=target_student_id and r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,t.id,y.id,c.id
    ) q),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_student_record_v5(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_view_student(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'student',(select to_jsonb(s)||(jsonb_build_object('archived',s.deleted_at is not null)) from public.students s where s.id=target_student_id),
    'enrollments',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc nulls last) from (
      select e.*,c.name class_name,y.name academic_year_name,y.start_date
      from public.enrollments e join public.classes c on c.id=e.class_id
      join public.academic_years y on y.id=e.academic_year_id
      where e.student_id=target_student_id and e.deleted_at is null
        and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(e.class_id,false))
    ) q),'[]'::jsonb),
    'guardians',coalesce((select jsonb_agg(to_jsonb(q) order by q.is_primary desc,lower(q.full_name)) from (
      select g.*,gl.auth_user_id,gl.can_view_reports,gl.can_receive_notifications,gl.verified_at
      from public.student_guardians g join public.guardian_links gl on gl.guardian_id=g.id
      where gl.student_id=target_student_id
    ) q),'[]'::jsonb),
    'reports',coalesce((select jsonb_agg(to_jsonb(q) order by q.start_date desc,q.sequence desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,t.name term_name,t.sequence,
        y.name academic_year_name,y.start_date,c.name class_name,
        round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id
      join public.classes c on c.id=e.class_id left join public.subject_results sr on sr.report_id=r.id
      where e.student_id=target_student_id and r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,t.id,y.id,c.id
    ) q),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.get_teacher_record(target_teacher_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.can_manage_teachers() and not exists(select 1 from public.teachers t where t.id=target_teacher_id and t.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  return (select jsonb_build_object('teacher',to_jsonb(t)||jsonb_build_object('full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'profile_email',au.email,'profile_name',p.full_name,'profile_role',case when p.id is null then null else public.current_app_role_for(p.role) end),'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb),'subjects',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb)) from public.teachers t left join public.profiles p on p.id=t.profile_id left join auth.users au on au.id=t.profile_id where t.id=target_teacher_id);
end$function$
;

CREATE OR REPLACE FUNCTION public.grade_for_mark(mark numeric, target_academic_year_id uuid, target_class_id uuid, target_subject_id uuid)
 RETURNS TABLE(grade text, remark text, grade_point numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select g.grade,g.remark,g.grade_point
  from public.grading_scales g
  where g.deleted_at is null and mark between g.min_mark and g.max_mark
    and (g.academic_year_id is null or g.academic_year_id=target_academic_year_id)
    and (g.class_id is null or g.class_id=target_class_id)
    and (g.subject_id is null or g.subject_id=target_subject_id)
  order by
    (g.subject_id is not null)::int desc,
    (g.class_id is not null)::int desc,
    (g.academic_year_id is not null)::int desc,
    g.display_order
  limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  requested_role text:=lower(coalesce(new.raw_app_meta_data->>'role',new.raw_user_meta_data->>'role',''));
  initial_role public.app_role;
  initial_active boolean:=true;
begin
  if not exists(select 1 from public.profiles) then
    initial_role:='system_admin'::public.app_role;
  elsif requested_role in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian') then
    initial_role:=requested_role::public.app_role;
  else
    initial_role:='parent_guardian'::public.app_role;
    initial_active:=false;
  end if;
  insert into public.profiles(id,full_name,role,active,mfa_required,phone)
  values(
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'),''),split_part(coalesce(new.email,''),'@',1),'User'),
    initial_role,
    initial_active,
    initial_role in ('system_admin','principal'),
    ''
  ) on conflict(id) do nothing;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.has_active_emergency_delegation(target_class_id uuid, target_subject_id uuid, target_term_id uuid, require_score_entry boolean DEFAULT false, require_class_fields boolean DEFAULT false, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select cardinality(public.active_emergency_delegation_ids(
    target_class_id,target_subject_id,target_term_id,
    require_score_entry,require_class_fields,target_user_id
  ))>0
$function$
;

CREATE OR REPLACE FUNCTION public.has_any_active_emergency_delegation(target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1
    from public.emergency_academic_delegations d
    join public.profiles p on p.id=d.delegate_user_id and p.active
    where d.delegate_user_id=target_user_id
      and d.status='active'
      and now()>=d.valid_from
      and now()<d.valid_until
  )
$function$
;

CREATE OR REPLACE FUNCTION public.has_approved_report_correction(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.report_correction_requests r
    where r.report_id=target_report_id and r.status='approved'
      and r.reviewed_at>=now()-interval '180 days'
  )
$function$
;

CREATE OR REPLACE FUNCTION public.has_role(allowed text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(public.current_app_role()::text=any(allowed),false)
$function$
;

CREATE OR REPLACE FUNCTION public.id_card_effective_status(target_status text, target_expires_on date)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$ select case when target_status='active' and target_expires_on<current_date then 'expired' else target_status end $function$
;

CREATE OR REPLACE FUNCTION public.id_card_photo_path_is_referenced(target_student_id uuid, target_photo_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare clean_path text:=btrim(coalesce(target_photo_path,'')); begin if auth.uid() is null or not public.can_manage_student(target_student_id) then return true;end if; if target_student_id is null or clean_path='' then return true;end if; return exists(select 1 from public.student_id_cards where student_id=target_student_id and snapshot#>>'{student,photo_url}'=clean_path); end$function$
;

CREATE OR REPLACE FUNCTION public.id_card_photo_reference_count(target_student_id uuid, target_photo_path text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare result integer:=0;clean_path text:=btrim(coalesce(target_photo_path,'')); begin if auth.uid() is null or not public.can_manage_student(target_student_id) then raise exception 'Access denied' using errcode='42501';end if; if clean_path='' then return 0;end if; select count(*)::integer into result from public.student_id_cards where student_id=target_student_id and snapshot#>>'{student,photo_url}'=clean_path; return coalesce(result,0); end$function$
;

CREATE OR REPLACE FUNCTION public.id_card_principal_signature_path_is_referenced(target_signature_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select auth.uid() is not null and (public.is_system_admin() or public.current_app_role()='principal') and btrim(coalesce(target_signature_path,''))<>'' and (
  exists(select 1 from public.student_id_cards c where c.snapshot#>>'{principal,signature_path}'=target_signature_path)
  or exists(select 1 from public.staff_id_cards c where c.snapshot#>>'{principal,signature_path}'=target_signature_path)
 )
$function$
;

CREATE OR REPLACE FUNCTION public.is_academic_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.has_role(array['system_admin']) $function$
;

CREATE OR REPLACE FUNCTION public.is_assigned_class_teacher(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role()='class_teacher'
    and exists(
      select 1 from public.classes c
      where c.id=target_class_id
        and c.class_teacher_id=auth.uid()
        and c.active
        and c.deleted_at is null
    )
$function$
;

CREATE OR REPLACE FUNCTION public.is_official_class_teacher_for_class(target_class_id uuid, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.classes c
    where c.id=target_class_id and c.class_teacher_id=target_user_id
      and c.active and c.deleted_at is null
  )
$function$
;

CREATE OR REPLACE FUNCTION public.is_official_subject_teacher_for_class(target_class_id uuid, target_subject_id uuid, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.class_subjects cs
    join public.classes c on c.id=cs.class_id
    join public.subjects s on s.id=cs.subject_id
    where cs.class_id=target_class_id and cs.subject_id=target_subject_id
      and cs.teacher_id=target_user_id and cs.active
      and c.active and c.deleted_at is null
      and s.active and s.deleted_at is null
  )
$function$
;

CREATE OR REPLACE FUNCTION public.is_platform_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(public.current_app_role()::text='platform_super_admin',false)
$function$
;

CREATE OR REPLACE FUNCTION public.is_records_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.has_role(array['system_admin']) $function$
;

CREATE OR REPLACE FUNCTION public.is_system_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.has_role(array['system_admin']) $function$
;

CREATE OR REPLACE FUNCTION public.is_term_three(term_sequence integer, term_name text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select coalesce(term_sequence=3,false)
    or lower(regexp_replace(coalesce(term_name,''),'[^a-zA-Z0-9]+','','g'))
       in ('term3','termthree','thirdterm','3rdterm')
$function$
;

CREATE OR REPLACE FUNCTION public.issue_certificate_batch(target_batch_id uuid, target_issue_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare batch_row public.certificate_batches; item record; school public.school_settings; principal record; year_code text; cert_number text; issued_count integer:=0;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can issue approved certificates' using errcode='42501'; end if;
  select * into batch_row from public.certificate_batches where id=target_batch_id for update;
  if batch_row.id is null or batch_row.status<>'approved' then raise exception 'Only an approved certificate batch can be issued'; end if;
  if target_issue_date is null or target_issue_date>current_date then raise exception 'Certificate issue date cannot be in the future'; end if;
  if not exists(select 1 from public.certificates where batch_id=target_batch_id and status='approved') then raise exception 'The approved batch contains no issuable certificates'; end if;
  select * into school from public.school_settings limit 1;
  select h.id,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,h.signature_path into principal from public.headteachers h where h.deleted_at is null and h.active and h.employment_status='active' and btrim(coalesce(h.signature_path,''))<>'' order by case when h.profile_id=batch_row.approved_by then 0 else 1 end,h.created_at limit 1;
  if principal.id is null then raise exception 'An active Principal signature is required before certificates can be issued'; end if;
  select regexp_replace(name::text,'[^0-9]+','','g') into year_code from public.academic_years where id=batch_row.academic_year_id;
  if year_code='' then year_code:=extract(year from target_issue_date)::text; end if;
  for item in select * from public.certificates where batch_id=target_batch_id and status='approved' order by recipient_name for update loop
    cert_number:=upper(coalesce(nullif(school.report_number_prefix,''),'RCE'))||'/'||left(year_code,9)||'/'||public.certificate_type_code(batch_row.certificate_type)||'/'||lpad(nextval('public.certificate_number_seq')::text,6,'0');
    update public.certificates set certificate_number=cert_number,issue_date=coalesce(target_issue_date,current_date),status='issued',issued_by=auth.uid(),issued_at=now(),snapshot=snapshot||jsonb_build_object('school',to_jsonb(school),'principal',jsonb_build_object('full_name',principal.full_name,'signature_path',principal.signature_path),'certificate_number',cert_number,'issue_date',coalesce(target_issue_date,current_date),'verification_token',verification_token),updated_at=now() where id=item.id;
    if item.supersedes_certificate_id is not null then
      update public.certificates set status='superseded',updated_at=now() where id=item.supersedes_certificate_id and status='issued';
      perform public.record_certificate_event(target_batch_id,item.supersedes_certificate_id,'superseded','Replaced by '||cert_number,jsonb_build_object('replacement_certificate_id',item.id));
    end if;
    perform public.record_certificate_event(target_batch_id,item.id,'issued','',jsonb_build_object('certificate_number',cert_number));
    issued_count:=issued_count+1;
  end loop;
  update public.certificate_batches set status='issued',issued_by=auth.uid(),issued_at=now(),updated_at=now() where id=target_batch_id;
  return jsonb_build_object('batch_id',target_batch_id,'status','issued','issued_count',issued_count,'certificates',(select jsonb_agg(jsonb_build_object('id',id,'certificate_number',certificate_number,'recipient_name',recipient_name,'verification_token',verification_token) order by recipient_name) from public.certificates where batch_id=target_batch_id and status='issued'));
end $function$
;

CREATE OR REPLACE FUNCTION public.issue_staff_id_cards(target_academic_year_id uuid, target_staff_keys text[], target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare key text;parts text[];kind text;sid uuid;cfg public.id_card_settings%rowtype;card_id uuid;card_number text;token uuid;expires date:=target_expires_on;created jsonb:='[]'::jsonb;skipped jsonb:='[]'::jsonb;snap jsonb;existing uuid;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can issue staff ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card issuance' using errcode='42501';end if;if target_academic_year_id is null then raise exception 'Academic year is required';end if;if target_issue_date is null then raise exception 'Issue date is required';end if;if coalesce(array_length(target_staff_keys,1),0)=0 then raise exception 'Select at least one staff member';end if;insert into public.id_card_settings default values on conflict do nothing;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.staff_validity_months,24)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'Staff ID card expiry date cannot be before issue date';end if;
  foreach key in array target_staff_keys loop parts:=string_to_array(key,':');kind:=coalesce(parts[1],'');sid:=public.safe_uuid(coalesce(parts[2],''));if kind not in ('teacher','principal') or sid is null then raise exception 'Invalid staff selection';end if;perform pg_advisory_xact_lock(hashtext('rce-staff-id-'||kind||'-'||sid::text));existing:=null;if kind='teacher' then select id into existing from public.staff_id_cards where teacher_id=sid and status='active' order by issued_at desc limit 1 for update;else select id into existing from public.staff_id_cards where headteacher_id=sid and status='active' order by issued_at desc limit 1 for update;end if;if existing is not null then skipped:=skipped||jsonb_build_array(jsonb_build_object('staff_key',key,'reason','active_card_exists'));continue;end if;card_number:=public.generate_staff_id_card_number(target_academic_year_id);token:=gen_random_uuid();snap:=public.build_staff_id_card_snapshot(kind,sid,target_academic_year_id,card_number,token,target_issue_date,expires);insert into public.staff_id_cards(staff_type,teacher_id,headteacher_id,academic_year_id,card_number,verification_token,issue_date,expires_on,snapshot,issued_by) values(kind,case when kind='teacher' then sid else null end,case when kind='principal' then sid else null end,target_academic_year_id,card_number,token,target_issue_date,expires,snap,auth.uid()) returning id into card_id;perform public.record_staff_id_card_event(card_id,kind,sid,'issued',jsonb_build_object('card_number',card_number,'academic_year_id',target_academic_year_id,'expires_on',expires));created:=created||jsonb_build_array(jsonb_build_object('card_id',card_id,'staff_key',key,'card_number',card_number,'verification_token',token));end loop;
  return jsonb_build_object('created',created,'created_count',jsonb_array_length(created),'skipped',skipped,'skipped_count',jsonb_array_length(skipped),'issue_date',target_issue_date,'expires_on',expires);
end$function$
;

CREATE OR REPLACE FUNCTION public.issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare sid uuid;e public.enrollments%rowtype;cfg public.id_card_settings%rowtype;card_id uuid;card_number text;token uuid;expires date:=target_expires_on;created jsonb:='[]'::jsonb;skipped jsonb:='[]'::jsonb;snap jsonb;existing public.student_id_cards%rowtype; begin if not public.is_system_admin() then raise exception 'Only the System Administrator can issue student ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card issuance' using errcode='42501';end if;if target_academic_year_id is null or target_class_id is null then raise exception 'Academic year and class are required';end if;if target_issue_date is null then raise exception 'ID card issue date is required';end if;if coalesce(array_length(target_student_ids,1),0)=0 then raise exception 'Select at least one student';end if; perform pg_advisory_xact_lock(hashtext('rce-id-card-issue-'||target_academic_year_id::text||'-'||target_class_id::text));insert into public.id_card_settings default values on conflict do nothing;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.validity_months,12)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'ID card expiry date cannot be before the issue date';end if; foreach sid in array target_student_ids loop select * into e from public.enrollments where student_id=sid and academic_year_id=target_academic_year_id and class_id=target_class_id and active and deleted_at is null limit 1;if e.id is null then raise exception 'Selected student % is not actively enrolled in the selected class and academic year',sid;end if; select * into existing from public.student_id_cards where student_id=sid and academic_year_id=target_academic_year_id and status='active' order by issued_at desc limit 1 for update; if existing.id is not null then skipped:=skipped||jsonb_build_array(jsonb_build_object('student_id',sid,'card_id',existing.id,'card_number',existing.card_number,'reason','active_card_exists'));continue;end if; card_number:=public.generate_student_id_card_number(target_academic_year_id);token:=gen_random_uuid();snap:=public.build_student_id_card_snapshot(sid,e.id,card_number,token,target_issue_date,expires); insert into public.student_id_cards(student_id,enrollment_id,academic_year_id,class_id,card_number,verification_token,issue_date,expires_on,snapshot,issued_by) values(sid,e.id,target_academic_year_id,target_class_id,card_number,token,target_issue_date,expires,snap,auth.uid()) returning id into card_id;perform public.record_id_card_event(card_id,sid,'issued',jsonb_build_object('card_number',card_number,'academic_year_id',target_academic_year_id,'class_id',target_class_id,'expires_on',expires));created:=created||jsonb_build_array(jsonb_build_object('card_id',card_id,'student_id',sid,'card_number',card_number,'verification_token',token));existing:=null; end loop; return jsonb_build_object('created',created,'created_count',jsonb_array_length(created),'skipped',skipped,'skipped_count',jsonb_array_length(skipped),'issue_date',target_issue_date,'expires_on',expires); end$function$
;

CREATE OR REPLACE FUNCTION public.issue_student_transcript(target_student_id uuid, purpose_text text DEFAULT 'Academic transcript'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare issued public.transcript_issuances;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Only the System Administrator or Principal can issue a transcript' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  update public.transcript_issuances set status='superseded' where student_id=target_student_id and status='valid';
  insert into public.transcript_issuances(student_id,purpose,snapshot)
  values(target_student_id,left(coalesce(nullif(btrim(purpose_text),''),'Academic transcript'),250),public.build_student_transcript_snapshot(target_student_id)) returning * into issued;
  insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason) values(auth.uid(),'transcript_issuances',issued.id,'ISSUE',to_jsonb(issued)-'snapshot',issued.purpose);
  return jsonb_build_object('id',issued.id,'verification_token',issued.verification_token,'purpose',issued.purpose,'status',issued.status,'issued_at',issued.issued_at,'snapshot',issued.snapshot);
end $function$
;

CREATE OR REPLACE FUNCTION public.license_access_for_actor(actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare actor_role text;
begin
  select public.current_app_role_for(p.role) into actor_role
  from public.profiles p where p.id=actor_id and p.active;
  if actor_role is null then
    return jsonb_build_object('read_allowed',false,'write_allowed',false,'access_mode','locked');
  end if;
  return public.license_snapshot_for_role(actor_role);
end $function$
;

CREATE OR REPLACE FUNCTION public.license_effective_entitlement()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l public.school_licenses%rowtype;p public.license_plans%rowtype;o public.license_entitlement_overrides%rowtype;plan_json jsonb;
begin
  select * into l from public.school_licenses order by created_at limit 1;
  if l.id is null then return '{}'::jsonb; end if;
  if l.entitlement_snapshot<>'{}'::jsonb then return l.entitlement_snapshot; end if;
  select * into p from public.license_plans where id=l.plan_id;
  plan_json:=jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'description',p.description,
    'billing_cycle',p.billing_cycle,'revision',p.revision,'max_students',p.max_students,
    'max_teachers',p.max_teachers,'max_system_admins',p.max_system_admins,'max_guardians',p.max_guardians,
    'max_storage_mb',p.max_storage_mb,'support_level',p.support_level,'feature_flags',p.feature_flags);
  select * into o from public.license_entitlement_overrides where license_id=l.id and active order by created_at desc limit 1;
  if o.id is not null then
    plan_json:=jsonb_set(plan_json,'{feature_flags}',coalesce(plan_json->'feature_flags','{}'::jsonb)||o.feature_overrides,true);
    if o.max_students is not null then plan_json:=jsonb_set(plan_json,'{max_students}',to_jsonb(o.max_students),true); end if;
    if o.max_teachers is not null then plan_json:=jsonb_set(plan_json,'{max_teachers}',to_jsonb(o.max_teachers),true); end if;
    if o.max_system_admins is not null then plan_json:=jsonb_set(plan_json,'{max_system_admins}',to_jsonb(o.max_system_admins),true); end if;
    if o.max_guardians is not null then plan_json:=jsonb_set(plan_json,'{max_guardians}',to_jsonb(o.max_guardians),true); end if;
    if o.max_storage_mb is not null then plan_json:=jsonb_set(plan_json,'{max_storage_mb}',to_jsonb(o.max_storage_mb),true); end if;
  end if;
  return jsonb_build_object('schema','rce-license-entitlement/v1','plan',plan_json,
    'license',jsonb_build_object('license_reference',l.license_reference,'status',l.status,'issued_on',l.issued_on,
      'activated_at',l.activated_at,'expires_at',l.expires_at,'grace_ends_at',l.grace_ends_at),
    'binding',jsonb_build_object('package_id',l.package_id,'installation_id',l.installation_id,
      'tenant_code',l.tenant_code,'authorized_domains',l.authorized_domains,'project_ref',l.project_ref));
end $function$
;

CREATE OR REPLACE FUNCTION public.license_feature_enabled(feature_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare clean_code text:=lower(btrim(coalesce(feature_code,''))); value jsonb; core_value jsonb; id_value jsonb;
begin
 value:=public.license_effective_entitlement()#>array['plan','feature_flags',clean_code];
 if jsonb_typeof(value)='boolean' then return value='true'::jsonb;end if;
 core_value:=public.license_effective_entitlement()#>array['plan','feature_flags','core_records'];
 if clean_code in ('id_cards','timetable','school_prospectus') then return jsonb_typeof(core_value)='boolean' and core_value='true'::jsonb;end if;
 if clean_code='staff_id_cards' then id_value:=public.license_effective_entitlement()#>array['plan','feature_flags','id_cards'];return (jsonb_typeof(id_value)='boolean' and id_value='true'::jsonb) or (jsonb_typeof(id_value) is null and jsonb_typeof(core_value)='boolean' and core_value='true'::jsonb);end if;
 return false;
end$function$
;

CREATE OR REPLACE FUNCTION public.license_feature_for_table(table_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select case
    when table_name in ('class_attendance_registers','student_attendance_entries') then 'attendance'
    when table_name in ('assessment_components','assessment_schemes','assessment_score_entries','grading_scales') then 'assessment'
    when table_name in ('student_reports','subject_results','subject_scores','report_publications','report_revisions','report_workflow_events','report_correction_events','report_correction_requests') then 'report_cards'
    when table_name in ('transcript_issuances','student_lifecycle_events') then 'academic_history'
    when table_name in ('certificates','certificate_batches','certificate_events','teacher_award_categories') then 'certificates'
    when table_name in ('report_card_templates','certificate_templates') then 'uploaded_templates'
    when table_name in ('import_batches','import_errors') then 'bulk_workflow'
    when table_name in ('backup_exports','backup_storage_objects','recovery_test_runs') then 'manual_backup'
    when table_name in ('notification_outbox','notifications') then 'notifications'
    when table_name in ('privacy_requests','data_retention_policies','security_events','security_verification_runs','audit_log','client_error_events','system_maintenance_log','emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls') then 'governance'
    else 'core_records' end
$function$
;

CREATE OR REPLACE FUNCTION public.license_read_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when auth.role() in ('service_role','supabase_admin') or auth.role() is null then true
    else coalesce((public.license_snapshot_for_role(public.current_app_role()::text)->>'read_allowed')::boolean,false)
  end
$function$
;

CREATE OR REPLACE FUNCTION public.license_snapshot_for_role(target_role text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_role text:=coalesce(nullif(target_role,''),public.current_app_role()::text,'');l public.school_licenses%rowtype;
  lock_row public.platform_access_locks%rowtype;e jsonb;p jsonb;computed text;mode text:='full';r boolean:=true;w boolean:=true;
  v_now timestamptz:=now();days_left integer;warning text:='';binding_ok boolean:=true;authority_ok boolean:=true;
begin
  select * into l from public.school_licenses order by created_at limit 1;
  if l.id is null then return jsonb_build_object('configured',false,'computed_status','unlicensed','access_mode','locked','read_allowed',v_role='platform_super_admin','write_allowed',false,'access_locked',true,'warning','No platform licence is configured.'); end if;
  e:=public.license_effective_entitlement();p:=coalesce(e->'plan','{}'::jsonb);
  select * into lock_row from public.platform_access_locks x where x.active and x.starts_at<=v_now and (x.ends_at is null or x.ends_at>v_now)
    and (x.lock_scope in ('platform','school') or (x.lock_scope='system_admin' and v_role='system_admin'))
    order by case x.lock_mode when 'deny' then 2 else 1 end desc,x.created_at desc limit 1;
  computed:=l.status;
  if computed='active' then
    if l.activated_at is null or l.activated_at>v_now then computed:='pending_activation';
    elsif l.expires_at is not null and l.expires_at<v_now then computed:=case when l.grace_ends_at is not null and l.grace_ends_at>=v_now then 'grace_period' else 'expired' end; end if;
  elsif computed='grace_period' and l.grace_ends_at is not null and l.grace_ends_at<v_now then computed:='expired'; end if;
  if l.expires_at is not null then days_left:=floor(extract(epoch from(l.expires_at-v_now))/86400)::integer; end if;
  if l.package_id is not null and v_role<>'platform_super_admin' then
    authority_ok:=l.authority_last_success_at is not null and l.authority_last_success_at>=v_now-interval '72 hours'
      and l.authority_status in ('active','unreachable');
    binding_ok:=l.signature_status='verified' and authority_ok and (auth.uid() is null or exists(select 1 from public.license_binding_sessions s where s.license_id=l.id and s.actor_id=auth.uid() and s.expires_at>v_now));
  end if;
  if v_role='platform_super_admin' then mode:='platform_control';r:=false;w:=false;
  elsif l.signature_status='invalid' then mode:='locked';r:=false;w:=false;warning:='The installed licence signature is invalid.';
  elsif l.package_id is not null and l.authority_status='revoked' then mode:='locked';r:=false;w:=false;warning:='The generated package licence has been revoked by the platform authority.';
  elsif l.package_id is not null and not authority_ok then mode:='read_only';w:=false;warning:='The central licence authority could not confirm this package within the 72-hour verification window.';
  elsif l.package_id is not null and not binding_ok then mode:='read_only';w:=false;warning:='The generated package licence or installation binding has not been verified.';
  elsif computed='revoked' then mode:='locked';r:=false;w:=false;warning:=coalesce(nullif(l.compliance_reason,''),'The platform licence has been revoked.');
  elsif lock_row.id is not null and lock_row.lock_mode='deny' then mode:='locked';r:=false;w:=false;warning:=lock_row.reason;
  elsif computed in ('pending_activation','expired','suspended') then mode:='read_only';w:=false;warning:=case computed when 'pending_activation' then 'The licence is awaiting activation. The system is read-only.' when 'expired' then 'The licence has expired. Existing records remain read-only.' else coalesce(nullif(l.compliance_reason,''),'The licence is suspended.') end;
  elsif lock_row.id is not null and lock_row.lock_mode='read_only' then mode:='read_only';w:=false;warning:=lock_row.reason;
  elsif computed='grace_period' then warning:='The licence is in its grace period.';
  elsif computed='active' and days_left between 0 and 30 then warning:='The licence expires in '||days_left||' day'||case when days_left=1 then '' else 's' end||'.'; end if;
  return jsonb_build_object('configured',true,'license_id',l.id,'license_reference',l.license_reference,'stored_status',l.status,
    'computed_status',computed,'issued_on',l.issued_on,'activated_at',l.activated_at,'expires_at',l.expires_at,'grace_ends_at',l.grace_ends_at,
    'compliance_reason',l.compliance_reason,'plan',p,'entitlement_schema',e->>'schema','package_id',l.package_id,
    'installation_id',l.installation_id,'tenant_code',l.tenant_code,'project_ref',l.project_ref,'authorized_domains',l.authorized_domains,
    'signature_status',l.signature_status,'signature_algorithm',l.signature_algorithm,'signature_key_id',l.signature_key_id,
    'signature_verified_at',l.signature_verified_at,'authority_status',l.authority_status,'authority_checked_at',l.authority_checked_at,'authority_last_success_at',l.authority_last_success_at,'authority_verified',authority_ok,'binding_verified',binding_ok,'access_mode',mode,'read_allowed',r,'write_allowed',w,
    'access_locked',mode='locked','access_lock_status',coalesce(lock_row.lock_scope||':'||lock_row.lock_mode,'unlocked'),
    'active_lock',case when lock_row.id is null then null else jsonb_build_object('id',lock_row.id,'scope',lock_row.lock_scope,'mode',lock_row.lock_mode,'reason',lock_row.reason,'starts_at',lock_row.starts_at,'ends_at',lock_row.ends_at) end,
    'days_remaining',days_left,'warning',warning);
end $function$
;

CREATE OR REPLACE FUNCTION public.license_write_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when auth.role() in ('service_role','supabase_admin') or auth.role() is null then true
    else coalesce((public.license_snapshot_for_role(public.current_app_role()::text)->>'write_allowed')::boolean,false)
  end
$function$
;

CREATE OR REPLACE FUNCTION public.list_academic_period_controls()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then raise exception 'Access denied' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(public.term_control_snapshot(t.id) order by y.start_date desc nulls last,t.sequence)
    from public.terms t join public.academic_years y on y.id=t.academic_year_id where t.deleted_at is null),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.list_audit_events(target_table text DEFAULT NULL::text, target_record_id uuid DEFAULT NULL::uuid, page_number integer DEFAULT 1, page_size integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return (
    with matching as (
      select a.*,p.full_name actor_name from public.audit_log a left join public.profiles p on p.id=a.actor_id
      where (target_table is null or a.table_name=target_table) and (target_record_id is null or a.record_id=target_record_id)
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
        select * from matching order by created_at desc limit least(greatest(page_size,1),100) offset greatest(page_number-1,0)*least(greatest(page_size,1),100)
      ) q),'[]'::jsonb),
      'total',(select count(*) from matching)
    )
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.list_certificate_eligible_recipients(target_certificate_type text, target_academic_year_id uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare completion_class uuid;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can prepare certificates' using errcode='42501'; end if;
  if target_certificate_type='student_promotion' then
    if target_term_id is null or target_class_id is null then raise exception 'Term and class are required for promotion certificates'; end if;
    if not exists(select 1 from public.terms where id=target_term_id and academic_year_id=target_academic_year_id and sequence=3 and deleted_at is null) then raise exception 'Promotion certificates require Term 3'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'recipient_name',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'identifier',st.admission_no,
      'current_class_name',c.name,'destination_class_name',pc.name,'source_report_id',r.id,
      'already_issued',exists(select 1 from public.certificates x join public.certificate_batches xb on xb.id=x.batch_id where x.student_id=st.id and xb.academic_year_id=target_academic_year_id and xb.certificate_type='student_promotion' and x.status in ('draft','approved','issued'))
    ) order by st.last_name,st.first_name,st.middle_name)
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.students st on st.id=e.student_id join public.classes c on c.id=e.class_id
      join public.classes pc on pc.id=r.promoted_to_class_id
      where r.term_id=target_term_id and e.academic_year_id=target_academic_year_id and e.class_id=target_class_id
        and r.status='published' and r.deleted_at is null and e.deleted_at is null and st.deleted_at is null
    ),'[]'::jsonb);
  elsif target_certificate_type='jhs_completion' then
    select certificate_completion_class_id into completion_class from public.school_settings limit 1;
    if target_class_id is null then raise exception 'Completion class is required'; end if;
    if completion_class is not null and target_class_id<>completion_class then raise exception 'Select the configured JHS 3 completion class'; end if;
    if completion_class is null and not exists(select 1 from public.classes c where c.id=target_class_id and lower(c.name::text) ~ '(basic[[:space:]]*9|jhs[[:space:]]*3|junior[[:space:]]+high.*3)') then raise exception 'The selected class is not configured as JHS 3'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'recipient_name',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'identifier',st.admission_no,
      'current_class_name',c.name,'destination_class_name','','source_report_id',r.id,
      'already_issued',exists(select 1 from public.certificates x join public.certificate_batches xb on xb.id=x.batch_id where x.student_id=st.id and xb.academic_year_id=target_academic_year_id and xb.certificate_type='jhs_completion' and x.status in ('draft','approved','issued'))
    ) order by st.last_name,st.first_name,st.middle_name)
      from public.enrollments e join public.students st on st.id=e.student_id join public.classes c on c.id=e.class_id
      left join lateral(select sr.id from public.student_reports sr join public.terms tr on tr.id=sr.term_id
        where sr.enrollment_id=e.id and sr.status='published' and sr.deleted_at is null
          and (target_term_id is null or sr.term_id=target_term_id)
        order by tr.sequence desc,sr.published_at desc nulls last limit 1) r on true
      where e.academic_year_id=target_academic_year_id and e.class_id=target_class_id and e.deleted_at is null and st.deleted_at is null and r.id is not null
    ),'[]'::jsonb);
  elsif target_certificate_type='teacher_recognition' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,'recipient_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'identifier',t.staff_no,
      'employment_status',t.employment_status,'already_issued',false
    ) order by t.last_name,t.first_name,t.middle_name)
      from public.teachers t where t.deleted_at is null and t.employment_status<>'suspended'
    ),'[]'::jsonb);
  end if;
  raise exception 'Certificate type is invalid';
end $function$
;

CREATE OR REPLACE FUNCTION public.list_guardian_portal_accounts(search_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not (public.is_records_manager() or public.has_role(array['class_teacher'])) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',p.id,'full_name',p.full_name,'email',u.email,'phone',p.phone
    ) order by p.full_name)
    from public.profiles p
    left join auth.users u on u.id=p.id
    where p.active and public.current_app_role_for(p.role)='parent_guardian'
      and (coalesce(search_text,'')='' or p.full_name ilike '%'||search_text||'%'
        or coalesce(u.email,'') ilike '%'||search_text||'%' or p.phone ilike '%'||search_text||'%')
  ),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.list_headteachers(search_text text DEFAULT ''::text, status_filter text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);limit_value integer:=least(greatest(page_size,1),100);
begin
  if not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501';end if;if archive_filter not in ('active','archived','all') then archive_filter:='active';end if;
  return (with matching as (
    select h.id,h.profile_id,h.staff_no,h.first_name,h.middle_name,h.last_name,h.gender,h.phone,h.email,h.address,h.qualification,h.date_appointed,h.employment_status,h.notes,h.photo_url,h.active,h.signature_path,h.signature_updated_at,h.deleted_at,h.created_at,h.updated_at,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,p.role profile_role,p.active profile_active,au.email profile_email
    from public.headteachers h left join public.profiles p on p.id=h.profile_id left join auth.users au on au.id=h.profile_id
    where (archive_filter='all' or (archive_filter='active' and h.deleted_at is null) or (archive_filter='archived' and h.deleted_at is not null)) and (coalesce(status_filter,'')='' or h.employment_status=status_filter)
      and (coalesce(search_text,'')='' or h.staff_no::text ilike '%'||search_text||'%' or concat_ws(' ',h.first_name,h.middle_name,h.last_name) ilike '%'||search_text||'%' or coalesce(h.phone,'') ilike '%'||search_text||'%' or coalesce(au.email::text,'') ilike '%'||search_text||'%')
  ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.full_name),x.staff_no::text) from (select * from matching order by lower(full_name),staff_no::text limit limit_value offset offset_value)x),'[]'::jsonb),'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value));
end$function$
;

CREATE OR REPLACE FUNCTION public.list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid DEFAULT NULL::uuid, search_text text DEFAULT ''::text)
 RETURNS TABLE(student_id uuid, enrollment_id uuid, full_name text, admission_no text, class_id uuid, class_name text, academic_year_id uuid, academic_year_name text, photo_url text, gender text, date_of_birth date, guardian_phone text, active_card_id uuid, active_card_number text, active_card_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage student ID cards' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit ID card access' using errcode='42501';end if; return query select st.id,e.id,concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),st.admission_no::text,c.id,c.name::text,y.id,y.name::text,st.photo_url,st.gender,st.date_of_birth,coalesce((select nullif(g.phone,'') from public.guardian_links gl join public.student_guardians g on g.id=gl.guardian_id where gl.student_id=st.id order by g.is_primary desc,gl.created_at limit 1),nullif(st.guardian_phone,''),'') guardian_phone,card.id,card.card_number,case when card.id is null then '' else public.id_card_effective_status(card.status,card.expires_on) end from public.enrollments e join public.students st on st.id=e.student_id and st.deleted_at is null and st.status='active' join public.classes c on c.id=e.class_id and c.deleted_at is null and c.active join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null left join lateral(select x.id,x.card_number,x.status,x.expires_on from public.student_id_cards x where x.student_id=st.id and x.academic_year_id=e.academic_year_id and x.status='active' order by x.issued_at desc limit 1) card on true where e.deleted_at is null and e.active and e.academic_year_id=target_academic_year_id and (target_class_id is null or e.class_id=target_class_id) and (btrim(coalesce(search_text,''))='' or st.admission_no::text ilike '%'||btrim(search_text)||'%' or concat_ws(' ',st.first_name,st.middle_name,st.last_name) ilike '%'||btrim(search_text)||'%') order by c.level_order nulls last,c.name,st.last_name,st.first_name; end$function$
;

CREATE OR REPLACE FUNCTION public.list_my_attendance_classes(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role()<>'class_teacher' then raise exception 'Only assigned class teachers can use attendance' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'level_order',c.level_order,
      'student_count',(select count(*) from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null and s.status='active'
        where e.class_id=c.id and e.deleted_at is null and (target_term_id is null or e.academic_year_id=(select t.academic_year_id from public.terms t where t.id=target_term_id)))
    ) order by c.level_order,c.name)
    from public.classes c
    where c.class_teacher_id=auth.uid() and c.active and c.deleted_at is null
  ),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.list_my_children_reports()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role()<>'parent_guardian' then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object('children',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',s.id,
      'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
      'admission_no',s.admission_no,
      'class_name',coalesce(c.name,''),
      'reports',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',r.id,'report_number',r.report_number,'status',r.status,'term_name',t.name,'academic_year_name',y.name,
          'average',coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0),
          'published_at',r.published_at,
          'publication',jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at)
        ) order by y.start_date desc nulls last,t.sequence desc)
        from public.enrollments er
        join public.student_reports r on r.enrollment_id=er.id and r.status='published' and r.deleted_at is null
        join public.terms t on t.id=r.term_id
        join public.academic_years y on y.id=t.academic_year_id
        join public.report_publications rp on rp.report_id=r.id and rp.revoked_at is null
        where er.student_id=s.id and er.deleted_at is null
      ),'[]'::jsonb)
    ) order by s.last_name,s.first_name)
    from public.guardian_links gl
    join public.students s on s.id=gl.student_id and s.deleted_at is null
    left join lateral (
      select e.class_id from public.enrollments e where e.student_id=s.id and e.active and e.deleted_at is null order by e.updated_at desc limit 1
    ) ce on true
    left join public.classes c on c.id=ce.class_id
    where gl.auth_user_id=auth.uid() and gl.can_view_reports
  ),'[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.list_notifications(page_number integer DEFAULT 1, page_size integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with matching as (
    select n.* from public.notifications n where n.recipient_id=auth.uid()
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select * from matching order by created_at desc
      limit least(greatest(page_size,1),100)
      offset greatest(page_number-1,0)*least(greatest(page_size,1),100)
    ) q),'[]'::jsonb),
    'total',(select count(*) from matching),
    'unread',(select count(*) from matching where read_at is null)
  )
$function$
;

CREATE OR REPLACE FUNCTION public.list_profiles_with_access()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'profiles',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'full_name',p.full_name,'email',au.email,'role',public.current_app_role_for(p.role),
      'active',p.active,'mfa_required',p.mfa_required,'must_change_password',p.must_change_password,'phone',p.phone,'last_seen_at',p.last_seen_at,
      'account_created_at',au.created_at,'email_confirmed_at',au.email_confirmed_at,'last_sign_in_at',au.last_sign_in_at,
      'teacher_id',t.id,'headteacher_id',h.id,'staff_record_id',coalesce(h.id,t.id),'staff_no',coalesce(h.staff_no,t.staff_no),
      'access',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'class_id',a.class_id,'class_name',c.name,'subject_id',a.subject_id,'subject_name',sub.name,'access_level',a.access_level) order by lower(c.name),lower(sub.name) nulls first)
        from public.user_class_access a join public.classes c on c.id=a.class_id left join public.subjects sub on sub.id=a.subject_id where a.user_id=p.id),'[]'::jsonb)
      ) order by lower(p.full_name),p.id)
      from public.profiles p left join auth.users au on au.id=p.id
      left join public.teachers t on t.profile_id=p.id and t.deleted_at is null
      left join public.headteachers h on h.profile_id=p.id and h.deleted_at is null
      where public.current_app_role_for(p.role) in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian')),'[]'::jsonb),
    'teacher_records',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'profile_id',t.profile_id,'staff_no',t.staff_no,'first_name',t.first_name,'middle_name',t.middle_name,'last_name',t.last_name,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'label',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)||' • '||t.staff_no::text,'phone',t.phone,'email',t.email,'active',t.active)
      order by lower(concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)),t.staff_no::text)
      from public.teachers t where t.deleted_at is null and t.active),'[]'::jsonb),
    'headteacher_records',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'profile_id',h.profile_id,'staff_no',h.staff_no,'first_name',h.first_name,'middle_name',h.middle_name,'last_name',h.last_name,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'label',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)||' • '||h.staff_no::text,'phone',h.phone,'email',h.email,'active',h.active)
      order by lower(concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)),h.staff_no::text)
      from public.headteachers h where h.deleted_at is null and h.active),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(to_jsonb(c) order by c.level_order,c.name) from public.classes c where c.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(sub) order by sub.display_order,sub.name) from public.subjects sub where sub.deleted_at is null),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'class_id',cs.class_id,'subject_id',cs.subject_id,'teacher_id',cs.teacher_id,'active',cs.active)) from public.class_subjects cs),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.list_report_card_templates()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by
      case t.range_key when 'early_years' then 1 when 'basic_1_6' then 2 else 3 end
    )
    from public.report_card_templates t
    where t.active
  ),'[]'::jsonb);
end $function$
;

CREATE OR REPLACE FUNCTION public.list_report_cards(target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, target_status report_status DEFAULT NULL::report_status, search_text text DEFAULT ''::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
declare limit_value integer:=least(greatest(page_size,1),100);
begin
  return (
    with matching as (
      select r.id,r.report_number,r.status,r.version,r.updated_at,r.published_at,
        e.student_id,e.class_id,r.term_id,s.admission_no,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        s.photo_url,c.name class_name,t.name term_name,y.name academic_year_name,
        round(coalesce(avg(sr.total_score),0),2) average,
        count(sr.id) subject_count
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id
      left join public.subject_results sr on sr.report_id=r.id
      where r.deleted_at is null and public.can_view_report(r.id)
        and (target_term_id is null or r.term_id=target_term_id)
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or r.status=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
      group by r.id,e.id,s.id,c.id,t.id,y.id
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from (
        select * from matching order by updated_at desc limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.list_report_cards_v6(target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, target_status report_status DEFAULT NULL::report_status, search_text text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
declare limit_value integer:=least(greatest(page_size,1),100);
begin
  if archive_filter not in ('active','archived','all') then archive_filter:='active'; end if;
  if archive_filter<>'active' and not (public.is_academic_manager() or public.has_role(array['class_teacher'])) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return (
    with matching as (
      select r.id,r.report_number,r.status,r.archived_status,r.version,r.updated_at,r.published_at,r.deleted_at,
        (r.deleted_at is not null) archived,e.student_id,e.class_id,r.term_id,s.admission_no,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        s.photo_url,c.name class_name,t.name term_name,y.name academic_year_name,
        round(coalesce(avg(sr.total_score),0),2) average,count(sr.id) subject_count
      from public.student_reports r
      join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id
      join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id
      join public.academic_years y on y.id=t.academic_year_id
      left join public.subject_results sr on sr.report_id=r.id
      where public.can_view_report(r.id)
        and (archive_filter='all' or (archive_filter='active' and r.deleted_at is null)
          or (archive_filter='archived' and r.deleted_at is not null))
        and (target_term_id is null or r.term_id=target_term_id)
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or coalesce(r.archived_status,r.status)=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or coalesce(r.report_number::text,'') ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
      group by r.id,e.id,s.id,c.id,t.id,y.id
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from (
        select * from matching order by updated_at desc limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.list_report_pdf_paths(target_report_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_delete_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return coalesce(
    (select array_agg(distinct p.storage_path order by p.storage_path)
     from public.report_publications p
     where p.report_id=target_report_id and btrim(coalesce(p.storage_path,''))<>''),
    '{}'::text[]
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.list_staff_id_card_candidates(target_staff_type text DEFAULT NULL::text, search_text text DEFAULT ''::text)
 RETURNS TABLE(staff_key text, staff_type text, staff_id uuid, full_name text, staff_no text, secondary_id text, role_label text, photo_url text, qualification text, active_card_id uuid, active_card_number text, active_card_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare kind text:=lower(btrim(coalesce(target_staff_type,'')));
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can list staff ID card candidates' using errcode='42501';
  end if;
  perform public.require_license_feature('staff_id_cards');
  if kind not in ('','teacher','principal') then raise exception 'Invalid staff type filter'; end if;

  return query
  select q.staff_key,q.staff_type,q.staff_id,q.full_name,q.staff_no,q.secondary_id,q.role_label,q.photo_url,q.qualification,q.active_card_id,q.active_card_number,q.active_card_status
  from (
    select
      'teacher:'||t.id::text as staff_key,
      'teacher'::text as staff_type,
      t.id as staff_id,
      concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)::text as full_name,
      t.staff_no::text as staff_no,
      coalesce(t.emis_code::text,'') as secondary_id,
      'Teacher'::text as role_label,
      t.photo_url::text as photo_url,
      t.qualification::text as qualification,
      card.id as active_card_id,
      card.card_number::text as active_card_number,
      case when card.id is null then '' else public.id_card_effective_status(card.status,card.expires_on) end::text as active_card_status
    from public.teachers t
    left join lateral (
      select c.id,c.card_number,c.status,c.expires_on
      from public.staff_id_cards c
      where c.teacher_id=t.id and c.status='active'
      order by c.issued_at desc
      limit 1
    ) card on true
    where t.deleted_at is null
      and t.active
      and t.employment_status='active'
      and kind in ('','teacher')
      and (
        btrim(coalesce(search_text,''))=''
        or t.staff_no::text ilike '%'||btrim(search_text)||'%'
        or coalesce(t.emis_code::text,'') ilike '%'||btrim(search_text)||'%'
        or concat_ws(' ',t.first_name,t.middle_name,t.last_name) ilike '%'||btrim(search_text)||'%'
      )

    union all

    select
      'principal:'||h.id::text as staff_key,
      'principal'::text as staff_type,
      h.id as staff_id,
      concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)::text as full_name,
      h.staff_no::text as staff_no,
      ''::text as secondary_id,
      'Principal'::text as role_label,
      h.photo_url::text as photo_url,
      h.qualification::text as qualification,
      card.id as active_card_id,
      card.card_number::text as active_card_number,
      case when card.id is null then '' else public.id_card_effective_status(card.status,card.expires_on) end::text as active_card_status
    from public.headteachers h
    left join lateral (
      select c.id,c.card_number,c.status,c.expires_on
      from public.staff_id_cards c
      where c.headteacher_id=h.id and c.status='active'
      order by c.issued_at desc
      limit 1
    ) card on true
    where h.deleted_at is null
      and h.active
      and h.employment_status='active'
      and kind in ('','principal')
      and (
        btrim(coalesce(search_text,''))=''
        or h.staff_no::text ilike '%'||btrim(search_text)||'%'
        or concat_ws(' ',h.first_name,h.middle_name,h.last_name) ilike '%'||btrim(search_text)||'%'
      )
  ) q
  order by q.role_label,lower(q.full_name),q.staff_no;
end$function$
;

CREATE OR REPLACE FUNCTION public.list_teachers(search_text text DEFAULT ''::text, status_filter text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);limit_value integer:=least(greatest(page_size,1),100);
begin
  if not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501';end if;if archive_filter not in ('active','archived','all') then archive_filter:='active';end if;
  return (with matching as (
    select t.id,t.profile_id,t.staff_no,t.emis_code,t.first_name,t.middle_name,t.last_name,t.gender,t.date_of_birth,t.phone,t.email,t.address,t.qualification,t.specialization,t.date_joined,t.employment_status,t.notes,t.photo_url,t.active,t.deleted_at,t.created_at,t.updated_at,concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name) full_name,p.role profile_role,p.active profile_active,au.email profile_email,
      coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb) class_assignments,
      coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb) subject_assignments
    from public.teachers t left join public.profiles p on p.id=t.profile_id left join auth.users au on au.id=t.profile_id
    where (archive_filter='all' or (archive_filter='active' and t.deleted_at is null) or (archive_filter='archived' and t.deleted_at is not null)) and (coalesce(status_filter,'')='' or t.employment_status=status_filter)
      and (coalesce(search_text,'')='' or t.staff_no::text ilike '%'||search_text||'%' or coalesce(t.emis_code::text,'') ilike '%'||search_text||'%' or concat_ws(' ',t.first_name,t.middle_name,t.last_name) ilike '%'||search_text||'%' or coalesce(t.email::text,'') ilike '%'||search_text||'%' or coalesce(t.phone,'') ilike '%'||search_text||'%')
  ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.last_name,x.first_name) from (select * from matching order by last_name,first_name limit limit_value offset offset_value)x),'[]'::jsonb),'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value,'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role),'email',au.email) order by p.full_name) from public.profiles p left join auth.users au on au.id=p.id where p.active and public.current_app_role_for(p.role) in ('class_teacher','subject_teacher')),'[]'::jsonb)));
end$function$
;

CREATE OR REPLACE FUNCTION public.log_client_error(message_text text, stack_text text DEFAULT ''::text, context_data jsonb DEFAULT '{}'::jsonb, user_agent_text text DEFAULT ''::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare eventid bigint;
begin
  insert into public.client_error_events(actor_id,message,stack,context,user_agent)
  values(auth.uid(),left(message_text,4000),left(coalesce(stack_text,''),12000),coalesce(context_data,'{}'::jsonb),left(coalesce(user_agent_text,''),1000))
  returning id into eventid;
  return eventid;
end $function$
;

CREATE OR REPLACE FUNCTION public.mark_backup_offsite_copy(target_backup_id uuid, target_note text DEFAULT 'Encrypted backup package copied off-site'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result_row public.backup_exports;
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  update public.backup_exports
  set offsite_copied_at=now(),
      offsite_copy_note=left(coalesce(nullif(btrim(target_note),''),'Encrypted backup package copied off-site'),500)
  where id=target_backup_id and status='completed'
  returning * into result_row;
  if result_row.id is null then raise exception 'Completed backup not found'; end if;
  return to_jsonb(result_row);
end $function$
;

CREATE OR REPLACE FUNCTION public.mark_notifications_read(notification_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare changed integer;
begin
  update public.notifications set read_at=coalesce(read_at,now())
  where recipient_id=auth.uid() and (notification_ids is null or id=any(notification_ids));
  get diagnostics changed=row_count;
  return changed;
end $function$
;

CREATE OR REPLACE FUNCTION public.mark_report_correction_applied(target_report_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  update public.report_correction_requests set status='applied',applied_at=now(),updated_at=now()
  where report_id=target_report_id and status='approved';
  insert into public.report_correction_events(request_id,event_type,event_note)
  select id,'applied','Corrected report republished' from public.report_correction_requests
  where report_id=target_report_id and status='applied' and applied_at>=now()-interval '5 seconds';
end $function$
;

CREATE OR REPLACE FUNCTION public.master_reject_tenant_operational_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  raise exception 'EDUSENTIA_MASTER_ISOLATION: tenant operational data cannot be written in the SaaS master project (table=% operation=%). Use the tenant project instead.', tg_table_name, tg_op
    using errcode = '42501';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.my_realtime_topics()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select array(select distinct topic from (
    select 'school:global'::text topic where public.current_app_role() in ('system_admin','principal')
    union all select 'user:'||auth.uid()::text
    union all select 'class:'||c.id::text from public.classes c where public.can_access_class(c.id,false)
    union all select 'report:'||r.id::text from public.student_reports r where public.can_view_report(r.id)
  ) q where topic is not null)
$function$
;

CREATE OR REPLACE FUNCTION public.next_promotion_academic_year(source_year_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with ordered_years as (
    select
      y.id,
      row_number() over(
        order by
          coalesce(
            y.start_date,
            case
              when y.name::text ~ '^[0-9]{4}'
                then make_date(substring(y.name::text from 1 for 4)::integer,1,1)
              else y.created_at::date
            end
          ),
          y.created_at,
          y.id
      ) as rn
    from public.academic_years y
    where y.deleted_at is null
  ), source_year as (
    select oy.rn from ordered_years oy where oy.id=source_year_id
  )
  select next_year.id
  from ordered_years next_year
  join source_year source on next_year.rn=source.rn+1
  limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.operations_dashboard(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=target_term_id;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if tid is null then select id into tid from public.terms where is_active and deleted_at is null limit 1; end if;
  return jsonb_build_object(
    'term_id',tid,'term_control',public.term_control_snapshot(tid),
    'students',(select count(*) from public.students where status='active' and deleted_at is null),
    'reports_expected',(select count(*) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=tid and e.active and e.deleted_at is null),
    'reports_created',(select count(*) from public.student_reports where term_id=tid and deleted_at is null),
    'draft_reports',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status in ('draft','returned')),
    'awaiting_approval',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status in ('submitted','class_reviewed')),
    'approved_unpublished',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status='approved'),
    'published',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status='published'),
    'published_without_pdf',(select count(*) from public.student_reports r left join public.report_publications p on p.report_id=r.id and p.revoked_at is null where r.term_id=tid and r.status='published' and r.deleted_at is null and coalesce(p.storage_path,'')=''),
    'pending_corrections',(select count(*) from public.report_correction_requests q join public.student_reports r on r.id=q.report_id where r.term_id=tid and q.status='pending'),
    'attendance_classes_today',(select count(distinct class_id) from public.class_attendance_registers where term_id=tid and attendance_date=current_date),
    'active_classes',(select count(*) from public.classes where active and deleted_at is null),
    'pending_notifications',(select count(*) from public.notification_outbox where processed_at is null),
    'client_errors_24h',(select count(*) from public.client_error_events where created_at>=now()-interval '24 hours'),
    'open_security_events',(select count(*) from public.security_events where status='open'),
    'critical_security_events',(select count(*) from public.security_events where status='open' and severity='critical'),
    'latest_backup',(select max(coalesce(completed_at,created_at)) from public.backup_exports where status='completed' and backup_type='full'),
    'latest_verified_backup',(select max(verification_checked_at) from public.backup_exports where verification_status='passed'),
    'latest_recovery_test',(select max(completed_at) from public.recovery_test_runs where status='passed'),
    'failed_backups_30d',(select count(*) from public.backup_exports where status='failed' and created_at>=now()-interval '30 days'),
    'cron_jobs',case when to_regclass('cron.job') is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('jobid',jobid,'jobname',jobname,'schedule',schedule,'active',active) order by jobname) from cron.job where jobname like 'nis-%' or jobname like 'rce-%'),'[]'::jsonb) end,
    'class_progress',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'enrolled',q.enrolled,'created',q.created,'submitted',q.submitted,'approved',q.approved,'published',q.published) order by c.level_order,c.name)
      from public.classes c cross join lateral (select
        (select count(*) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=tid and e.class_id=c.id and e.active and e.deleted_at is null) enrolled,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null) created,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status in ('submitted','class_reviewed')) submitted,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status='approved') approved,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status='published') published
      ) q where c.active and c.deleted_at is null),'[]'::jsonb)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.performance_comment_suggestions(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare avg_mark numeric:=0; result_count integer:=0; strongest text:=''; weakest text:='';
declare student_name text:='The student'; first_name text:='The student'; gender_value text:='Other';
declare opened integer:=0; present integer:=0; attendance numeric:=0; promoted_name text:='';
declare teacher_text text; head_text text; pronoun text:='They'; possessive text:='their'; average_text text;
begin
  if not public.can_view_report(target_report_id) then raise exception 'Access denied' using errcode='42501'; end if;
  select concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),s.first_name,s.gender,
    r.days_school_opened,r.days_present,coalesce(pc.name,'')
  into student_name,first_name,gender_value,opened,present,promoted_name
  from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
  join public.students s on s.id=e.student_id left join public.classes pc on pc.id=r.promoted_to_class_id
  where r.id=target_report_id;
  select count(*),coalesce(round(avg(sr.total_score),2),0) into result_count,avg_mark
  from public.subject_results sr where sr.report_id=target_report_id;
  select s.name into strongest from public.subject_results sr join public.subjects s on s.id=sr.subject_id
  where sr.report_id=target_report_id order by sr.total_score desc,s.display_order,s.name limit 1;
  select s.name into weakest from public.subject_results sr join public.subjects s on s.id=sr.subject_id
  where sr.report_id=target_report_id order by sr.total_score asc,s.display_order,s.name limit 1;
  if gender_value='Male' then pronoun:='He';possessive:='his';
  elsif gender_value='Female' then pronoun:='She';possessive:='her'; end if;
  average_text:=to_char(avg_mark,'FM990D0');
  attendance:=case when opened>0 then round(present::numeric/opened*100,1) else 0 end;
  if result_count=0 then
    teacher_text:=first_name||'''s assessment record is incomplete and requires all subject results.';
    head_text:='Complete the outstanding assessment records before final approval.';
  elsif avg_mark>=85 then
    teacher_text:=first_name||' has demonstrated outstanding academic performance with an average of '||average_text||'%. '||pronoun||' showed exceptional strength in '||coalesce(strongest,'the assessed subjects')||'. Maintain this excellent standard.';
    head_text:='Excellent performance. Continue to pursue excellence and remain a positive example to others.';
  elsif avg_mark>=75 then
    teacher_text:=first_name||' has achieved a very good academic performance with an average of '||average_text||'%. '||pronoun||' performed especially well in '||coalesce(strongest,'the assessed subjects')||' and should continue working consistently.';
    head_text:='Very good performance. Keep working diligently and aim for an even higher standard next term.';
  elsif avg_mark>=65 then
    teacher_text:=first_name||' has made good academic progress with an average of '||average_text||'%. '||pronoun||' showed strength in '||coalesce(strongest,'several subjects')||' and should give additional attention to '||coalesce(weakest,'weaker areas')||'.';
    head_text:='Good progress. Maintain steady effort and improve the areas that require greater attention.';
  elsif avg_mark>=50 then
    teacher_text:=first_name||' has produced a satisfactory performance with an average of '||average_text||'%. More regular revision, active class participation, and focused practice in '||coalesce(weakest,'the weaker subjects')||' will improve future results.';
    head_text:='Satisfactory performance. Greater consistency and focused study are required for stronger achievement.';
  elsif avg_mark>=40 then
    teacher_text:=first_name||' has shown a fair performance with an average of '||average_text||'%. '||pronoun||' needs sustained support, regular practice, and closer attention to '||coalesce(weakest,'the weaker subjects')||'.';
    head_text:='There is potential for improvement. Work closely with teachers and maintain a disciplined study routine.';
  else
    teacher_text:=first_name||' needs substantial academic improvement. The current average is '||average_text||'%, and immediate support is required, particularly in '||coalesce(weakest,'the weaker subjects')||'.';
    head_text:='Considerable improvement is required. Consistent effort, supervision, and remedial support should begin immediately.';
  end if;
  if opened>0 and attendance<85 then
    teacher_text:=teacher_text||' Attendance also requires improvement ('||present||' of '||opened||' days present).';
  elsif opened>0 and attendance>=95 then
    teacher_text:=teacher_text||' '||pronoun||' maintained excellent attendance.';
  end if;
  if promoted_name<>'' then head_text:=head_text||' Promotion: '||promoted_name||'.'; end if;
  return jsonb_build_object('average',avg_mark,'teacher_comment',teacher_text,'head_comment',head_text,
    'strongest_subject',strongest,'weakest_subject',weakest,'attendance_rate',attendance,'student_name',student_name);
end $function$
;

CREATE OR REPLACE FUNCTION public.platform_clear_license_history(reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  reason text:=btrim(coalesce(reason_text,''));
  event_total bigint;
  verification_total bigint;
  archive_total bigint;
begin
  perform public.require_platform_super_admin();
  if length(reason)<5 then
    raise exception 'A clear history-reset reason is required' using errcode='22023';
  end if;
  if upper(btrim(coalesce(confirmation_text,'')))<>'CLEAR ALL' then
    raise exception 'Type CLEAR ALL exactly to confirm permanent history removal' using errcode='22023';
  end if;
  select count(*) into event_total from public.license_events;
  select count(*) into verification_total from public.license_verification_logs;
  select count(*) into archive_total from public.platform_audit_archives where archive_scope='licensing';
  delete from public.platform_audit_archives where archive_scope='licensing';
  execute 'truncate table public.license_verification_logs, public.license_events restart identity';
  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details,created_at)
  values(
    auth.uid(),
    'LICENCE_COMPLIANCE_HISTORY_RESET',
    event_total+verification_total+archive_total,
    jsonb_build_object(
      'reason',reason,
      'license_events_removed',event_total,
      'verification_logs_removed',verification_total,
      'licensing_archives_removed',archive_total
    ),
    now()
  );
  return public.get_platform_license_console();
end
$function$
;

CREATE OR REPLACE FUNCTION public.platform_clear_package_history(reason_text text, actor_id_value uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  reason text:=btrim(coalesce(reason_text,''));
  event_total bigint;
  archive_total bigint;
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for package history reset' using errcode='42501';
  end if;
  if actor_id_value is null or not exists(
    select 1 from public.profiles p
    where p.id=actor_id_value
      and p.active
      and public.current_app_role_for(p.role)::text='platform_super_admin'
  ) then
    raise exception 'Active Platform Super Administrator is required' using errcode='42501';
  end if;
  if length(reason)<5 then
    raise exception 'A clear package-history reason is required' using errcode='22023';
  end if;
  select count(*) into event_total from public.platform_package_events;
  select count(*) into archive_total from public.platform_audit_archives where archive_scope='packages';
  delete from public.platform_audit_archives where archive_scope='packages';
  execute 'truncate table public.platform_package_events restart identity';
  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details,created_at)
  values(
    actor_id_value,
    'PACKAGE_SECURITY_HISTORY_RESET',
    event_total+archive_total,
    jsonb_build_object(
      'reason',reason,
      'package_events_removed',event_total,
      'package_archives_removed',archive_total,
      'safe_update_compatible',true
    ),
    now()
  );
  return jsonb_build_object(
    'cleared',true,
    'package_events_removed',event_total,
    'package_archives_removed',archive_total
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.platform_finalize_package_replacement(target_artifact_id uuid, target_actor_id uuid, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  replacement public.platform_package_artifacts%rowtype;
  previous public.platform_package_artifacts%rowtype;
  actor_role text:='';
  clean_reason text:=btrim(coalesce(reason_text,''));
  finalized_at timestamptz:=now();
  replacement_metadata jsonb;
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for replacement finalization'
      using errcode='42501';
  end if;
  if upper(btrim(coalesce(confirmation_text,'')))<>'ACTIVATE' then
    raise exception 'Type ACTIVATE exactly to finalize the replacement'
      using errcode='22023';
  end if;
  if length(clean_reason)<5 then
    raise exception 'A replacement finalization reason is required'
      using errcode='22023';
  end if;

  select public.current_app_role_for(p.role)::text
  into actor_role
  from public.profiles p
  where p.id=target_actor_id and p.active;
  if actor_role<>'platform_super_admin' then
    raise exception 'An active Platform Super Administrator is required'
      using errcode='42501';
  end if;

  select * into replacement
  from public.platform_package_artifacts
  where id=target_artifact_id
  for update;
  if replacement.id is null then
    raise exception 'Replacement package was not found' using errcode='P0002';
  end if;
  if replacement.supersedes_artifact_id is null
     or replacement.status<>'ready'
     or replacement.deletion_state<>'none' then
    raise exception 'Select a ready renewal or upgrade package'
      using errcode='22023';
  end if;
  if replacement.authority_last_checked_at is null
     or replacement.authority_last_checked_at<finalized_at-interval '24 hours' then
    raise exception 'The replacement package has not completed a successful school authority check within the last 24 hours'
      using errcode='42501';
  end if;

  select * into previous
  from public.platform_package_artifacts
  where id=replacement.supersedes_artifact_id
  for update;
  if previous.id is null then
    raise exception 'The superseded package record was not found' using errcode='P0002';
  end if;
  if previous.status<>'ready' or previous.deletion_state<>'none' then
    raise exception 'The previous package is no longer in a finalizable ready state'
      using errcode='40001';
  end if;
  if previous.superseded_by_artifact_id is not null
     and previous.superseded_by_artifact_id<>replacement.id then
    raise exception 'The previous package already has a different finalized replacement'
      using errcode='23505';
  end if;

  update public.platform_package_artifacts
  set status='revoked',
      revoked_at=finalized_at,
      revoked_by=target_actor_id,
      revocation_reason='Superseded by '||replacement.filename||': '||clean_reason,
      superseded_by_artifact_id=replacement.id,
      superseded_at=finalized_at,
      supersession_reason=clean_reason
  where id=previous.id;

  replacement_metadata:=jsonb_set(
    coalesce(replacement.metadata,'{}'::jsonb),
    '{lifecycle}',
    coalesce(replacement.metadata->'lifecycle','{}'::jsonb)||jsonb_build_object(
      'finalized_at',finalized_at,
      'finalized_by',target_actor_id,
      'finalization_reason',clean_reason
    ),
    true
  );
  update public.platform_package_artifacts
  set metadata=replacement_metadata
  where id=replacement.id
  returning * into replacement;

  insert into public.platform_package_events(
    event_type,actor_id,artifact_id,event_reason,event_data
  ) values(
    'package_replacement_finalized',target_actor_id,replacement.id,clean_reason,
    jsonb_build_object(
      'superseded_artifact_id',previous.id,
      'superseded_package_id',previous.package_id,
      'replacement_package_id',replacement.package_id,
      'authority_last_checked_at',replacement.authority_last_checked_at,
      'finalized_at',finalized_at
    )
  );

  return jsonb_build_object(
    'finalized',true,
    'replacement',to_jsonb(replacement),
    'superseded',(
      select to_jsonb(a)
      from public.platform_package_artifacts a
      where a.id=previous.id
    )
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.platform_package_session()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a public.platform_distribution_authorities%rowtype;s jsonb;
begin
  perform public.require_platform_super_admin();
  if exists(select 1 from public.school_licenses where package_id is not null) then
    raise exception 'Generated school installations cannot act as package distributors' using errcode='42501';
  end if;
  select * into a from public.platform_distribution_authorities where actor_id=auth.uid() and active;
  if a.id is null then raise exception 'Active Platform Distributor authority is required; Enterprise School licensing alone does not grant package access' using errcode='42501';end if;
  s:=public.license_snapshot_for_role('platform_super_admin');return jsonb_build_object('authorised',true,'actor_id',auth.uid(),'actor_role','platform_super_admin','aal',public.current_aal(),'distributor_id',a.id,'distributor_code',a.distributor_code,'can_generate',a.can_generate,'can_revoke',a.can_revoke,'plan_code',s#>>'{plan,code}');
end $function$
;

CREATE OR REPLACE FUNCTION public.platform_package_signing_key_install(target_envelope jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_catalog', 'extensions'
AS $function$
declare
  payload jsonb;
  registry record;
  secret_id uuid;
  key_id_value text:=coalesce(target_envelope->>'key_id','');
  fingerprint_value text:=coalesce(target_envelope->>'public_fingerprint','');
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for package signing key installation' using errcode='42501';
  end if;
  if target_envelope is null or jsonb_typeof(target_envelope)<>'object' then
    raise exception 'Package signing key envelope must be a JSON object' using errcode='22023';
  end if;
  if coalesce((target_envelope->>'version')::integer,0)<>1 then
    raise exception 'Package signing key envelope version is invalid' using errcode='22023';
  end if;
  if jsonb_typeof(target_envelope->'private_jwk')<>'object'
     or target_envelope->'private_jwk'->>'kty'<>'EC'
     or target_envelope->'private_jwk'->>'crv'<>'P-256'
     or coalesce(target_envelope->'private_jwk'->>'x','')=''
     or coalesce(target_envelope->'private_jwk'->>'y','')=''
     or coalesce(target_envelope->'private_jwk'->>'d','')='' then
    raise exception 'Package signing private JWK must be EC P-256' using errcode='22023';
  end if;
  if jsonb_typeof(target_envelope->'public_jwk')<>'object'
     or target_envelope->'public_jwk'->>'kty'<>'EC'
     or target_envelope->'public_jwk'->>'crv'<>'P-256'
     or coalesce(target_envelope->'public_jwk'->>'x','')<>coalesce(target_envelope->'private_jwk'->>'x','')
     or coalesce(target_envelope->'public_jwk'->>'y','')<>coalesce(target_envelope->'private_jwk'->>'y','')
     or target_envelope->'public_jwk' ? 'd' then
    raise exception 'Package signing public JWK does not match its private JWK' using errcode='22023';
  end if;
  if key_id_value !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$' then
    raise exception 'Package signing key ID is invalid' using errcode='22023';
  end if;
  if fingerprint_value !~ '^[0-9a-f]{64}$' then
    raise exception 'Package signing public-key fingerprint is invalid' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('rce_package_signing_key_v1',0));
  select singleton,key_id,public_fingerprint,created_at,updated_at
    into registry
  from public.platform_package_signing_identity
  where singleton=true;
  select decrypted_secret::jsonb
    into payload
  from vault.decrypted_secrets
  where name='rce_package_signing_key_v1'
  order by updated_at desc
  limit 1;
  if payload is not null then
    if coalesce(payload->>'key_id','') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$'
       or coalesce(payload->>'public_fingerprint','') !~ '^[0-9a-f]{64}$' then
      raise exception 'Stored package signing key metadata is invalid' using errcode='22023';
    end if;
    if registry.key_id is null then
      insert into public.platform_package_signing_identity(singleton,key_id,public_fingerprint)
      values(true,payload->>'key_id',payload->>'public_fingerprint')
      on conflict(singleton) do nothing;
    elsif registry.key_id<>payload->>'key_id' or registry.public_fingerprint<>payload->>'public_fingerprint' then
      raise exception 'Package signing identity registry does not match the encrypted Vault key' using errcode='55000';
    end if;
    -- Another first-use request may have installed the authoritative key while
    -- this request waited for the advisory lock. Return that key so all callers
    -- converge on one identity instead of failing or creating split identities.
    return payload || jsonb_build_object('configured',true,'recovery_required',false);
  end if;
  if registry.key_id is not null
     and (registry.key_id<>key_id_value or registry.public_fingerprint<>fingerprint_value) then
    raise exception 'The encrypted package signing key is missing, but its permanent identity registry exists. Restore the matching private JWK instead of creating a new signing identity.' using errcode='55000';
  end if;
  select vault.create_secret(
    target_envelope::text,
    'rce_package_signing_key_v1',
    'Report Card Enterprise package signing private JWK. Created once and retained for package verification continuity.'
  ) into secret_id;
  insert into public.platform_package_signing_identity(singleton,key_id,public_fingerprint,updated_at)
  values(true,key_id_value,fingerprint_value,now())
  on conflict(singleton) do update
    set updated_at=excluded.updated_at
    where public.platform_package_signing_identity.key_id=excluded.key_id
      and public.platform_package_signing_identity.public_fingerprint=excluded.public_fingerprint;
  select decrypted_secret::jsonb
    into payload
  from vault.decrypted_secrets
  where id=secret_id;
  if payload is null then
    raise exception 'Package signing key was created but could not be verified in Vault' using errcode='55000';
  end if;
  return payload || jsonb_build_object('configured',true,'recovery_required',false);
end
$function$
;

CREATE OR REPLACE FUNCTION public.platform_package_signing_key_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_catalog', 'extensions'
AS $function$
declare
  payload jsonb;
  registry record;
  payload_key_id text;
  payload_fingerprint text;
  metadata_repair_required boolean:=false;
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for package signing key access' using errcode='42501';
  end if;
  select singleton,key_id,public_fingerprint,created_at,updated_at
    into registry
  from public.platform_package_signing_identity
  where singleton=true;
  select decrypted_secret::jsonb
    into payload
  from vault.decrypted_secrets
  where name='rce_package_signing_key_v1'
  order by updated_at desc
  limit 1;
  if payload is null then
    if registry.key_id is not null then
      return jsonb_build_object(
        'configured',false,
        'recovery_required',true,
        'expected_key_id',registry.key_id,
        'expected_public_fingerprint',registry.public_fingerprint
      );
    end if;
    return jsonb_build_object('configured',false,'recovery_required',false);
  end if;
  if jsonb_typeof(payload->'private_jwk')<>'object'
     or payload->'private_jwk'->>'kty'<>'EC'
     or payload->'private_jwk'->>'crv'<>'P-256'
     or coalesce(payload->'private_jwk'->>'x','')=''
     or coalesce(payload->'private_jwk'->>'y','')=''
     or coalesce(payload->'private_jwk'->>'d','')='' then
    raise exception 'Stored package signing private JWK is invalid' using errcode='22023';
  end if;
  payload_key_id:=coalesce(payload->>'key_id','');
  payload_fingerprint:=coalesce(payload->>'public_fingerprint','');
  metadata_repair_required:=
    payload_key_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$'
    or payload_fingerprint !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(payload->'public_jwk')<>'object'
    or coalesce(payload->'public_jwk'->>'x','')<>coalesce(payload->'private_jwk'->>'x','')
    or coalesce(payload->'public_jwk'->>'y','')<>coalesce(payload->'private_jwk'->>'y','')
    or payload->'public_jwk' ? 'd'
    or (registry.key_id is not null and registry.key_id<>payload_key_id)
    or (registry.public_fingerprint is not null and registry.public_fingerprint<>payload_fingerprint);
  return payload || jsonb_build_object(
    'configured',true,
    'recovery_required',false,
    'metadata_repair_required',metadata_repair_required,
    'registered_key_id',registry.key_id,
    'registered_public_fingerprint',registry.public_fingerprint
  );
exception
  when invalid_text_representation then
    raise exception 'Stored package signing key is invalid JSON' using errcode='22023';
end
$function$
;

SET check_function_bodies=on;
