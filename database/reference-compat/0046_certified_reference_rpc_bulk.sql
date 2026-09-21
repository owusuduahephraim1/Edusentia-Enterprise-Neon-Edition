-- Edusentia Enterprise Neon Edition — certified reference RPC bulk parity.
-- Certified source: nduah385/Edusentia-Enterprise @ a181e18e0ca044db756193209b5b089cd03efb0f
-- Source of definitions: read-only certified Nipe tenant PostgreSQL metadata.
-- Scope: 108 provider-neutral certified RPCs. Supabase Storage/network/auth-table dependent RPCs are adapted separately.

begin;

-- academic_analytics(target_term_id uuid, target_class_id uuid)
CREATE OR REPLACE FUNCTION public.academic_analytics(target_term_id uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.require_license_feature('analytics');
  return public.academic_analytics_v729(target_term_id,target_class_id);
end $function$;
revoke all on function public.academic_analytics(target_term_id uuid, target_class_id uuid) from public;
grant execute on function public.academic_analytics(target_term_id uuid, target_class_id uuid) to edusentia_worker_runtime;

-- acknowledge_emergency_academic_delegation(target_delegation_id uuid, note_text text)
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
end $function$;
revoke all on function public.acknowledge_emergency_academic_delegation(target_delegation_id uuid, note_text text) from public;
grant execute on function public.acknowledge_emergency_academic_delegation(target_delegation_id uuid, note_text text) to edusentia_worker_runtime;

-- archive_school_prospectus(target_prospectus_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.archive_school_prospectus(target_prospectus_id uuid, reason_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare row public.school_prospectuses%rowtype;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can archive school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;update public.school_prospectuses set status='archived',updated_by=auth.uid(),updated_at=now() where id=target_prospectus_id returning * into row;if row.id is null then raise exception 'Prospectus not found';end if;return public.build_school_prospectus_snapshot(row.id);end$function$;
revoke all on function public.archive_school_prospectus(target_prospectus_id uuid, reason_text text) from public;
grant execute on function public.archive_school_prospectus(target_prospectus_id uuid, reason_text text) to edusentia_worker_runtime;

-- archive_student(target_student_id uuid, reason_text text)
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
end $function$;
revoke all on function public.archive_student(target_student_id uuid, reason_text text) from public;
grant execute on function public.archive_student(target_student_id uuid, reason_text text) to edusentia_worker_runtime;

-- backup_dashboard()
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
end $function$;
revoke all on function public.backup_dashboard() from public;
grant execute on function public.backup_dashboard() to edusentia_worker_runtime;

-- bulk_generate_missing_reports(target_term_id uuid, target_class_id uuid, preview_only boolean)
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
end $function$;
revoke all on function public.bulk_generate_missing_reports(target_term_id uuid, target_class_id uuid, preview_only boolean) from public;
grant execute on function public.bulk_generate_missing_reports(target_term_id uuid, target_class_id uuid, preview_only boolean) to edusentia_worker_runtime;

-- bulk_promote_all_classes(source_academic_year_id uuid, target_academic_year_id uuid)
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
end $function$;
revoke all on function public.bulk_promote_all_classes(source_academic_year_id uuid, target_academic_year_id uuid) from public;
grant execute on function public.bulk_promote_all_classes(source_academic_year_id uuid, target_academic_year_id uuid) to edusentia_worker_runtime;

-- bulk_promote_class(source_academic_year_id uuid, source_class_id uuid, target_academic_year_id uuid, target_class_id uuid)
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
end $function$;
revoke all on function public.bulk_promote_class(source_academic_year_id uuid, source_class_id uuid, target_academic_year_id uuid, target_class_id uuid) from public;
grant execute on function public.bulk_promote_class(source_academic_year_id uuid, source_class_id uuid, target_academic_year_id uuid, target_class_id uuid) to edusentia_worker_runtime;

-- bulk_transition_class_reports(target_term_id uuid, target_class_id uuid, target_status report_status, comment_text text)
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
end $function$;
revoke all on function public.bulk_transition_class_reports(target_term_id uuid, target_class_id uuid, target_status report_status, comment_text text) from public;
grant execute on function public.bulk_transition_class_reports(target_term_id uuid, target_class_id uuid, target_status report_status, comment_text text) to edusentia_worker_runtime;

-- clear_section_history(scope_text text, reason_text text, confirmation_text text)
CREATE OR REPLACE FUNCTION public.clear_section_history(scope_text text, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare v_scope text:=lower(btrim(coalesce(scope_text,'')));v_reason text:=btrim(coalesce(reason_text,''));v_deleted integer:=0;v_secondary_deleted integer:=0;v_skipped integer:=0;v_preserved integer:=0;v_result jsonb;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can permanently clear section history' using errcode='42501';end if;if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required to permanently clear history' using errcode='42501';end if;if upper(btrim(coalesce(confirmation_text,'')))<>'CLEAR HISTORY' then raise exception 'Type CLEAR HISTORY exactly to confirm permanent history removal' using errcode='22023';end if;if length(v_reason)<5 then raise exception 'A reset reason of at least five characters is required' using errcode='22023';end if;case v_scope when 'report_corrections' then select count(*) into v_secondary_deleted from public.report_correction_events e where exists(select 1 from public.report_correction_requests r where r.id=e.request_id and r.status in ('rejected','cancelled','applied'));delete from public.report_correction_requests where status in ('rejected','cancelled','applied');get diagnostics v_deleted=row_count;select count(*) into v_preserved from public.report_correction_requests where status in ('pending','approved');v_result:=jsonb_build_object('scope',v_scope,'requests_deleted',v_deleted,'events_deleted',v_secondary_deleted,'active_requests_preserved',v_preserved);when 'recovery_rehearsals' then delete from public.recovery_test_runs where status in ('passed','failed','cancelled');get diagnostics v_deleted=row_count;select count(*) into v_preserved from public.recovery_test_runs where status not in ('passed','failed','cancelled');v_result:=jsonb_build_object('scope',v_scope,'rehearsals_deleted',v_deleted,'active_rehearsals_preserved',v_preserved);when 'backup_restore' then delete from public.school_restore_jobs where status in ('completed','failed','cancelled');get diagnostics v_deleted=row_count;select count(*) into v_skipped from public.backup_exports b where b.status='failed' and not(coalesce(b.storage_bytes,0)=0 and coalesce(b.storage_path,'')='' and coalesce(b.manifest_path,'')='' and coalesce(b.database_path,'')='' and not exists(select 1 from public.backup_storage_objects o where o.backup_export_id=b.id) and not exists(select 1 from public.recovery_test_runs rr where rr.backup_export_id=b.id and rr.status='processing') and not exists(select 1 from public.school_restore_jobs sj where sj.pre_restore_backup_id=b.id and sj.status not in ('completed','failed','cancelled')));delete from public.backup_exports b where b.status='failed' and coalesce(b.storage_bytes,0)=0 and coalesce(b.storage_path,'')='' and coalesce(b.manifest_path,'')='' and coalesce(b.database_path,'')='' and not exists(select 1 from public.backup_storage_objects o where o.backup_export_id=b.id) and not exists(select 1 from public.recovery_test_runs rr where rr.backup_export_id=b.id and rr.status='processing') and not exists(select 1 from public.school_restore_jobs sj where sj.pre_restore_backup_id=b.id and sj.status not in ('completed','failed','cancelled'));get diagnostics v_secondary_deleted=row_count;select count(*) into v_preserved from public.backup_exports where status<>'failed';v_result:=jsonb_build_object('scope',v_scope,'restore_jobs_deleted',v_deleted,'safe_failed_backup_rows_deleted',v_secondary_deleted,'failed_backup_rows_skipped_for_payload_safety',v_skipped,'completed_or_active_backup_assets_preserved',v_preserved);else raise exception 'Unsupported history scope: %',coalesce(scope_text,'') using errcode='22023';end case;if to_regclass('public.system_maintenance_log') is not null then insert into public.system_maintenance_log(actor_id,operation,affected_rows,details,created_at) values(auth.uid(),'HISTORY_RESET',greatest(v_deleted,0)+greatest(v_secondary_deleted,0),jsonb_build_object('release','r30','scope',v_scope,'reason',v_reason,'result',v_result,'operational_data_deleted',false,'successful_backup_assets_deleted',false),now());end if;return v_result||jsonb_build_object('cleared_at',now(),'reason',v_reason);end$function$;
revoke all on function public.clear_section_history(scope_text text, reason_text text, confirmation_text text) from public;
grant execute on function public.clear_section_history(scope_text text, reason_text text, confirmation_text text) to edusentia_worker_runtime;

-- copy_school_prospectus(target_source_id uuid, target_academic_year_id uuid)
CREATE OR REPLACE FUNCTION public.copy_school_prospectus(target_source_id uuid, target_academic_year_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare source public.school_prospectuses%rowtype;new_id uuid;sec record;new_sec uuid;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can copy school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select * into source from public.school_prospectuses where id=target_source_id;if source.id is null then raise exception 'Source prospectus not found';end if;if not exists(select 1 from public.academic_years where id=target_academic_year_id and deleted_at is null) then raise exception 'Target academic year not found';end if;if exists(select 1 from public.school_prospectuses where academic_year_id=target_academic_year_id and class_range=source.class_range) then raise exception 'A prospectus already exists for this class range in the target academic year';end if;insert into public.school_prospectuses(academic_year_id,class_range,title,currency_code,status,effective_date,revision_no,general_notes,created_by,updated_by) values(target_academic_year_id,source.class_range,source.title,source.currency_code,'draft',null,0,source.general_notes,auth.uid(),auth.uid()) returning id into new_id;for sec in select * from public.school_prospectus_sections where prospectus_id=source.id order by display_order,id loop insert into public.school_prospectus_sections(prospectus_id,section_type,title,instructions,display_order,created_by,updated_by) values(new_id,sec.section_type,sec.title,sec.instructions,sec.display_order,auth.uid(),auth.uid()) returning id into new_sec;insert into public.school_prospectus_items(section_id,item_name,description,amount,charge_basis,quantity,unit,calculation_units,include_in_total,required,notes,display_order,created_by,updated_by) select new_sec,item_name,description,amount,charge_basis,quantity,unit,calculation_units,include_in_total,required,notes,display_order,auth.uid(),auth.uid() from public.school_prospectus_items where section_id=sec.id order by display_order,id;end loop;return public.build_school_prospectus_snapshot(new_id);end$function$;
revoke all on function public.copy_school_prospectus(target_source_id uuid, target_academic_year_id uuid) from public;
grant execute on function public.copy_school_prospectus(target_source_id uuid, target_academic_year_id uuid) to edusentia_worker_runtime;

-- create_certificate_batch(payload jsonb, recipient_ids uuid[])
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
end $function$;
revoke all on function public.create_certificate_batch(payload jsonb, recipient_ids uuid[]) from public;
grant execute on function public.create_certificate_batch(payload jsonb, recipient_ids uuid[]) to edusentia_worker_runtime;

-- create_certificate_replacement_draft(target_certificate_id uuid, reason_text text, replacement_statement text)
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
end $function$;
revoke all on function public.create_certificate_replacement_draft(target_certificate_id uuid, reason_text text, replacement_statement text) from public;
grant execute on function public.create_certificate_replacement_draft(target_certificate_id uuid, reason_text text, replacement_statement text) to edusentia_worker_runtime;

-- create_emergency_academic_delegation(payload jsonb)
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
end $function$;
revoke all on function public.create_emergency_academic_delegation(payload jsonb) from public;
grant execute on function public.create_emergency_academic_delegation(payload jsonb) to edusentia_worker_runtime;

-- create_privacy_request(payload jsonb)
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
end $function$;
revoke all on function public.create_privacy_request(payload jsonb) from public;
grant execute on function public.create_privacy_request(payload jsonb) to edusentia_worker_runtime;

-- delete_audit_events(event_ids bigint[])
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
$function$;
revoke all on function public.delete_audit_events(event_ids bigint[]) from public;
grant execute on function public.delete_audit_events(event_ids bigint[]) to edusentia_worker_runtime;

-- delete_certificate_permanently(target_certificate_id uuid, reason_text text)
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
end $function$;
revoke all on function public.delete_certificate_permanently(target_certificate_id uuid, reason_text text) from public;
grant execute on function public.delete_certificate_permanently(target_certificate_id uuid, reason_text text) to edusentia_worker_runtime;

-- delete_class_subject_assignment(target_id uuid, reason_text text)
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
end $function$;
revoke all on function public.delete_class_subject_assignment(target_id uuid, reason_text text) from public;
grant execute on function public.delete_class_subject_assignment(target_id uuid, reason_text text) to edusentia_worker_runtime;

-- delete_class_timetable_entry(target_entry_id uuid)
CREATE OR REPLACE FUNCTION public.delete_class_timetable_entry(target_entry_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage class timetables' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('timetable');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit timetable changes' using errcode='42501';end if;delete from public.class_timetable_entries where id=target_entry_id;if not found then raise exception 'Timetable entry not found';end if;end$function$;
revoke all on function public.delete_class_timetable_entry(target_entry_id uuid) from public;
grant execute on function public.delete_class_timetable_entry(target_entry_id uuid) to edusentia_worker_runtime;

-- delete_notifications(notification_ids uuid[])
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
end $function$;
revoke all on function public.delete_notifications(notification_ids uuid[]) from public;
grant execute on function public.delete_notifications(notification_ids uuid[]) to edusentia_worker_runtime;

-- delete_school_prospectus(target_prospectus_id uuid)
CREATE OR REPLACE FUNCTION public.delete_school_prospectus(target_prospectus_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare p public.school_prospectuses%rowtype;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can delete draft school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select * into p from public.school_prospectuses where id=target_prospectus_id for update;if p.id is null then raise exception 'Prospectus not found';end if;if p.status<>'draft' or p.revision_no>0 or exists(select 1 from public.school_prospectus_revisions where prospectus_id=p.id) then raise exception 'Only a never-published draft prospectus can be deleted. Archive published prospectuses instead.';end if;delete from public.school_prospectuses where id=p.id;end$function$;
revoke all on function public.delete_school_prospectus(target_prospectus_id uuid) from public;
grant execute on function public.delete_school_prospectus(target_prospectus_id uuid) to edusentia_worker_runtime;

-- delete_school_prospectus_item(target_item_id uuid)
CREATE OR REPLACE FUNCTION public.delete_school_prospectus_item(target_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare pid uuid;status_value text;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can remove prospectus items' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select s.prospectus_id,p.status into pid,status_value from public.school_prospectus_items i join public.school_prospectus_sections s on s.id=i.section_id join public.school_prospectuses p on p.id=s.prospectus_id where i.id=target_item_id for update of p;if pid is null then raise exception 'Prospectus item not found';end if;if status_value='archived' then raise exception 'Archived prospectuses cannot be edited';end if;delete from public.school_prospectus_items where id=target_item_id;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;end$function$;
revoke all on function public.delete_school_prospectus_item(target_item_id uuid) from public;
grant execute on function public.delete_school_prospectus_item(target_item_id uuid) to edusentia_worker_runtime;

-- delete_school_prospectus_section(target_section_id uuid)
CREATE OR REPLACE FUNCTION public.delete_school_prospectus_section(target_section_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare pid uuid;status_value text;begin if not public.is_system_admin() then raise exception 'Only the System Administrator can remove prospectus sections' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;select s.prospectus_id,p.status into pid,status_value from public.school_prospectus_sections s join public.school_prospectuses p on p.id=s.prospectus_id where s.id=target_section_id for update of p;if pid is null then raise exception 'Prospectus section not found';end if;if status_value='archived' then raise exception 'Archived prospectuses cannot be edited';end if;delete from public.school_prospectus_sections where id=target_section_id;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;end$function$;
revoke all on function public.delete_school_prospectus_section(target_section_id uuid) from public;
grant execute on function public.delete_school_prospectus_section(target_section_id uuid) to edusentia_worker_runtime;

-- delete_staff_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text)
CREATE OR REPLACE FUNCTION public.delete_staff_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c public.staff_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,''));sid uuid;
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can permanently delete staff ID card records' using errcode='42501';end if;if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required for permanent ID card deletion' using errcode='42501';end if;perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card changes' using errcode='42501';end if;if upper(btrim(coalesce(confirmation_text,'')))<>'DELETE' then raise exception 'Type DELETE exactly to confirm permanent removal';end if;if length(reason)<5 then raise exception 'A deletion reason of at least five characters is required';end if;select * into c from public.staff_id_cards where id=target_card_id and status in ('revoked','replaced') for update;if c.id is null then raise exception 'Only a revoked or replaced staff ID card can be permanently deleted';end if;sid:=coalesce(c.teacher_id,c.headteacher_id);insert into public.id_card_deletion_tombstones(card_kind,card_number,verification_token,previous_status,deleted_by,deletion_reason,details) values('staff',c.card_number,c.verification_token,c.status,auth.uid(),reason,jsonb_build_object('revision',c.revision_no,'staff_type',c.staff_type,'deleted_record_id',c.id)) on conflict(card_kind,card_number) do nothing;perform public.record_staff_id_card_event(c.id,c.staff_type,sid,'permanently_deleted',jsonb_build_object('card_number',c.card_number,'previous_status',c.status,'reason',reason));delete from public.staff_id_cards where id=c.id;return jsonb_build_object('deleted',true,'card_number',c.card_number,'status','permanently_removed');end$function$;
revoke all on function public.delete_staff_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) from public;
grant execute on function public.delete_staff_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) to edusentia_worker_runtime;

-- delete_student_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text)
CREATE OR REPLACE FUNCTION public.delete_student_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c public.student_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,''));
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can permanently delete ID card records' using errcode='42501';end if;if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required for permanent ID card deletion' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if upper(btrim(coalesce(confirmation_text,'')))<>'DELETE' then raise exception 'Type DELETE exactly to confirm permanent removal';end if;if length(reason)<5 then raise exception 'A deletion reason of at least five characters is required';end if;select * into c from public.student_id_cards where id=target_card_id and status in ('revoked','replaced') for update;if c.id is null then raise exception 'Only a revoked or replaced student ID card can be permanently deleted';end if;insert into public.id_card_deletion_tombstones(card_kind,card_number,verification_token,previous_status,deleted_by,deletion_reason,details) values('student',c.card_number,c.verification_token,c.status,auth.uid(),reason,jsonb_build_object('revision',c.revision_no,'deleted_record_id',c.id)) on conflict(card_kind,card_number) do nothing;perform public.record_id_card_event(c.id,c.student_id,'permanently_deleted',jsonb_build_object('card_number',c.card_number,'previous_status',c.status,'reason',reason));delete from public.student_id_cards where id=c.id;return jsonb_build_object('deleted',true,'card_number',c.card_number,'status','permanently_removed');end$function$;
revoke all on function public.delete_student_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) from public;
grant execute on function public.delete_student_id_card_permanently(target_card_id uuid, reason_text text, confirmation_text text) to edusentia_worker_runtime;

-- delete_transcript_issuance_permanently(target_issuance_id uuid, reason_text text, confirmation_text text)
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
end $function$;
revoke all on function public.delete_transcript_issuance_permanently(target_issuance_id uuid, reason_text text, confirmation_text text) from public;
grant execute on function public.delete_transcript_issuance_permanently(target_issuance_id uuid, reason_text text, confirmation_text text) to edusentia_worker_runtime;

-- get_certificate_batch(target_batch_id uuid)
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
end $function$;
revoke all on function public.get_certificate_batch(target_batch_id uuid) from public;
grant execute on function public.get_certificate_batch(target_batch_id uuid) to edusentia_worker_runtime;

-- get_certificate_console(target_academic_year_id uuid, target_certificate_type text)
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
end $function$;
revoke all on function public.get_certificate_console(target_academic_year_id uuid, target_certificate_type text) from public;
grant execute on function public.get_certificate_console(target_academic_year_id uuid, target_certificate_type text) to edusentia_worker_runtime;

-- get_class_attendance_register(target_term_id uuid, target_class_id uuid, target_date date)
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
end $function$;
revoke all on function public.get_class_attendance_register(target_term_id uuid, target_class_id uuid, target_date date) from public;
grant execute on function public.get_class_attendance_register(target_term_id uuid, target_class_id uuid, target_date date) to edusentia_worker_runtime;

-- get_compliance_console()
CREATE OR REPLACE FUNCTION public.get_compliance_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'retention_policies',coalesce((select jsonb_agg(to_jsonb(p) order by p.data_category) from public.data_retention_policies p),'[]'::jsonb),
    'privacy_requests',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'student_id',r.student_id,'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
        'request_type',r.request_type,'requester_name',r.requester_name,'requester_contact',r.requester_contact,
        'request_details',r.request_details,'status',r.status,'due_at',r.due_at,'outcome',r.outcome,
        'created_at',r.created_at,'completed_at',r.completed_at) order by r.created_at desc)
      from (select * from public.privacy_requests order by created_at desc limit 500) r
      left join public.students s on s.id=r.student_id
    ),'[]'::jsonb),
    'security_events',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'event_type',e.event_type,'severity',e.severity,'source',e.source,'message',e.message,
        'details',e.details,'status',e.status,'created_at',e.created_at,'actor_name',p.full_name,'resolution_note',e.resolution_note)
        order by e.created_at desc)
      from (select * from public.security_events where created_at>=now()-interval '180 days' order by created_at desc limit 500) e
      left join public.profiles p on p.id=e.actor_id
    ),'[]'::jsonb),
    'verification_runs',coalesce((select jsonb_agg(to_jsonb(v) order by v.verified_at desc) from (select * from public.security_verification_runs order by verified_at desc limit 100) v),'[]'::jsonb),
    'open_privacy_requests',(select count(*) from public.privacy_requests where status in ('open','in_review')),
    'overdue_privacy_requests',(select count(*) from public.privacy_requests where status in ('open','in_review') and due_at<now()),
    'open_high_security_events',(select count(*) from public.security_events where status='open' and severity in ('high','critical'))
  );
end $function$;
revoke all on function public.get_compliance_console() from public;
grant execute on function public.get_compliance_console() to edusentia_worker_runtime;

-- get_current_principal_signature()
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
end $function$;
revoke all on function public.get_current_principal_signature() from public;
grant execute on function public.get_current_principal_signature() to edusentia_worker_runtime;

-- get_id_card_console(target_academic_year_id uuid, target_class_id uuid, target_status text)
CREATE OR REPLACE FUNCTION public.get_id_card_console(target_academic_year_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, target_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare year_id uuid:=target_academic_year_id;settings_row jsonb;cards_json jsonb;stats_json jsonb; begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage student ID cards' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit ID card access' using errcode='42501';end if; if year_id is null then select id into year_id from public.academic_years where is_active and deleted_at is null order by start_date desc nulls last,created_at desc limit 1;end if; select to_jsonb(x) into settings_row from public.id_card_settings x limit 1; select coalesce(jsonb_agg(to_jsonb(q) order by q.issued_at desc),'[]'::jsonb) into cards_json from (select c.id,c.student_id,c.enrollment_id,c.academic_year_id,c.class_id,c.card_number,c.verification_token,c.revision_no,c.supersedes_card_id,c.status,public.id_card_effective_status(c.status,c.expires_on) computed_status,c.issue_date,c.expires_on,c.snapshot,c.issued_at,c.revoked_at,c.revocation_reason,c.replacement_reason,c.snapshot#>>'{student,full_name}' student_name,c.snapshot#>>'{student,admission_no}' admission_no,c.snapshot#>>'{academic,class_name}' class_name,c.snapshot#>>'{academic,academic_year_name}' academic_year_name from public.student_id_cards c where (year_id is null or c.academic_year_id=year_id) and (target_class_id is null or c.class_id=target_class_id) and (target_status is null or target_status='' or public.id_card_effective_status(c.status,c.expires_on)=target_status) order by c.issued_at desc limit 1500) q; select jsonb_build_object('total',count(*),'active',count(*) filter(where public.id_card_effective_status(status,expires_on)='active'),'expired',count(*) filter(where public.id_card_effective_status(status,expires_on)='expired'),'revoked',count(*) filter(where status='revoked'),'replaced',count(*) filter(where status='replaced')) into stats_json from public.student_id_cards c where (year_id is null or c.academic_year_id=year_id) and (target_class_id is null or c.class_id=target_class_id); return jsonb_build_object('generated_at',now(),'settings',coalesce(settings_row,'{}'::jsonb),'academic_year_id',year_id,'stats',stats_json,'cards',cards_json,'feature_enabled',true); end$function$;
revoke all on function public.get_id_card_console(target_academic_year_id uuid, target_class_id uuid, target_status text) from public;
grant execute on function public.get_id_card_console(target_academic_year_id uuid, target_class_id uuid, target_status text) to edusentia_worker_runtime;

-- get_recovery_console()
CREATE OR REPLACE FUNCTION public.get_recovery_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'tests',coalesce((select jsonb_agg(to_jsonb(r) order by r.started_at desc) from (select * from public.recovery_test_runs order by started_at desc limit 50) r),'[]'::jsonb),
    'latest_passed',(select max(completed_at) from public.recovery_test_runs where status='passed'),
    'latest_failed',(select max(completed_at) from public.recovery_test_runs where status='failed')
  );
end $function$;
revoke all on function public.get_recovery_console() from public;
grant execute on function public.get_recovery_console() to edusentia_worker_runtime;

-- get_report_correction_console(target_term_id uuid, target_class_id uuid)
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
end $function$;
revoke all on function public.get_report_correction_console(target_term_id uuid, target_class_id uuid) from public;
grant execute on function public.get_report_correction_console(target_term_id uuid, target_class_id uuid) to edusentia_worker_runtime;

-- get_report_grading_guide(target_report_id uuid, target_enrollment_id uuid, target_term_id uuid)
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
end $function$;
revoke all on function public.get_report_grading_guide(target_report_id uuid, target_enrollment_id uuid, target_term_id uuid) from public;
grant execute on function public.get_report_grading_guide(target_report_id uuid, target_enrollment_id uuid, target_term_id uuid) to edusentia_worker_runtime;

-- get_school_prospectus_console(target_academic_year_id uuid)
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
end$function$;
revoke all on function public.get_school_prospectus_console(target_academic_year_id uuid) from public;
grant execute on function public.get_school_prospectus_console(target_academic_year_id uuid) to edusentia_worker_runtime;

-- get_staff_id_card_console(target_staff_type text, target_status text)
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
end$function$;
revoke all on function public.get_staff_id_card_console(target_staff_type text, target_status text) from public;
grant execute on function public.get_staff_id_card_console(target_staff_type text, target_status text) to edusentia_worker_runtime;

-- get_student_academic_history(target_student_id uuid)
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
    'current_issuance',coalesce((
      select jsonb_build_object(
        'id',i.id,'transcript_number',i.transcript_number,'verification_token',i.verification_token,
        'purpose',i.purpose,'status',i.status,'issued_at',i.issued_at,'issuer_name',p.full_name,
        'snapshot_checksum',i.snapshot_checksum,'academic_period_count',i.academic_period_count,
        'latest_academic_year',i.latest_academic_year,'latest_term',i.latest_term,'latest_class',i.latest_class,
        'template_version',i.template_version,'snapshot',i.snapshot
      )
      from public.transcript_issuances i
      left join public.profiles p on p.id=i.issued_by
      where i.student_id=target_student_id and i.status='valid'
      order by i.issued_at desc
      limit 1
    ),'null'::jsonb),
    'issuances',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'transcript_number',i.transcript_number,'verification_token',i.verification_token,
        'purpose',i.purpose,'status',i.status,'issued_at',i.issued_at,'issuer_name',p.full_name,
        'snapshot_checksum',i.snapshot_checksum,'academic_period_count',i.academic_period_count,
        'latest_academic_year',i.latest_academic_year,'latest_term',i.latest_term,'latest_class',i.latest_class,
        'template_version',i.template_version,'revoked_at',i.revoked_at,'revocation_reason',i.revocation_reason
      ) order by i.issued_at desc)
      from public.transcript_issuances i
      left join public.profiles p on p.id=i.issued_by
      where i.student_id=target_student_id
    ),'[]'::jsonb)
  );
end
$function$;
revoke all on function public.get_student_academic_history(target_student_id uuid) from public;
grant execute on function public.get_student_academic_history(target_student_id uuid) to edusentia_worker_runtime;

-- get_student_record_v5(target_student_id uuid)
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
end $function$;
revoke all on function public.get_student_record_v5(target_student_id uuid) from public;
grant execute on function public.get_student_record_v5(target_student_id uuid) to edusentia_worker_runtime;

-- id_card_photo_reference_count(target_student_id uuid, target_photo_path text)
CREATE OR REPLACE FUNCTION public.id_card_photo_reference_count(target_student_id uuid, target_photo_path text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare result integer:=0;clean_path text:=btrim(coalesce(target_photo_path,'')); begin if auth.uid() is null or not public.can_manage_student(target_student_id) then raise exception 'Access denied' using errcode='42501';end if; if clean_path='' then return 0;end if; select count(*)::integer into result from public.student_id_cards where student_id=target_student_id and snapshot#>>'{student,photo_url}'=clean_path; return coalesce(result,0); end$function$;
revoke all on function public.id_card_photo_reference_count(target_student_id uuid, target_photo_path text) from public;
grant execute on function public.id_card_photo_reference_count(target_student_id uuid, target_photo_path text) to edusentia_worker_runtime;

-- id_card_principal_signature_path_is_referenced(target_signature_path text)
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
$function$;
revoke all on function public.id_card_principal_signature_path_is_referenced(target_signature_path text) from public;
grant execute on function public.id_card_principal_signature_path_is_referenced(target_signature_path text) to edusentia_worker_runtime;

-- issue_certificate_batch(target_batch_id uuid, target_issue_date date)
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
end $function$;
revoke all on function public.issue_certificate_batch(target_batch_id uuid, target_issue_date date) from public;
grant execute on function public.issue_certificate_batch(target_batch_id uuid, target_issue_date date) to edusentia_worker_runtime;

-- issue_staff_id_cards(target_academic_year_id uuid, target_staff_keys text[], target_issue_date date, target_expires_on date)
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
end$function$;
revoke all on function public.issue_staff_id_cards(target_academic_year_id uuid, target_staff_keys text[], target_issue_date date, target_expires_on date) from public;
grant execute on function public.issue_staff_id_cards(target_academic_year_id uuid, target_staff_keys text[], target_issue_date date, target_expires_on date) to edusentia_worker_runtime;

-- issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date, target_expires_on date)
CREATE OR REPLACE FUNCTION public.issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare sid uuid;e public.enrollments%rowtype;cfg public.id_card_settings%rowtype;card_id uuid;card_number text;token uuid;expires date:=target_expires_on;created jsonb:='[]'::jsonb;skipped jsonb:='[]'::jsonb;snap jsonb;existing public.student_id_cards%rowtype; begin if not public.is_system_admin() then raise exception 'Only the System Administrator can issue student ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card issuance' using errcode='42501';end if;if target_academic_year_id is null or target_class_id is null then raise exception 'Academic year and class are required';end if;if target_issue_date is null then raise exception 'ID card issue date is required';end if;if coalesce(array_length(target_student_ids,1),0)=0 then raise exception 'Select at least one student';end if; perform pg_advisory_xact_lock(hashtext('rce-id-card-issue-'||target_academic_year_id::text||'-'||target_class_id::text));insert into public.id_card_settings default values on conflict do nothing;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.validity_months,12)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'ID card expiry date cannot be before the issue date';end if; foreach sid in array target_student_ids loop select * into e from public.enrollments where student_id=sid and academic_year_id=target_academic_year_id and class_id=target_class_id and active and deleted_at is null limit 1;if e.id is null then raise exception 'Selected student % is not actively enrolled in the selected class and academic year',sid;end if; select * into existing from public.student_id_cards where student_id=sid and academic_year_id=target_academic_year_id and status='active' order by issued_at desc limit 1 for update; if existing.id is not null then skipped:=skipped||jsonb_build_array(jsonb_build_object('student_id',sid,'card_id',existing.id,'card_number',existing.card_number,'reason','active_card_exists'));continue;end if; card_number:=public.generate_student_id_card_number(target_academic_year_id);token:=gen_random_uuid();snap:=public.build_student_id_card_snapshot(sid,e.id,card_number,token,target_issue_date,expires); insert into public.student_id_cards(student_id,enrollment_id,academic_year_id,class_id,card_number,verification_token,issue_date,expires_on,snapshot,issued_by) values(sid,e.id,target_academic_year_id,target_class_id,card_number,token,target_issue_date,expires,snap,auth.uid()) returning id into card_id;perform public.record_id_card_event(card_id,sid,'issued',jsonb_build_object('card_number',card_number,'academic_year_id',target_academic_year_id,'class_id',target_class_id,'expires_on',expires));created:=created||jsonb_build_array(jsonb_build_object('card_id',card_id,'student_id',sid,'card_number',card_number,'verification_token',token));existing:=null; end loop; return jsonb_build_object('created',created,'created_count',jsonb_array_length(created),'skipped',skipped,'skipped_count',jsonb_array_length(skipped),'issue_date',target_issue_date,'expires_on',expires); end$function$;
revoke all on function public.issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date, target_expires_on date) from public;
grant execute on function public.issue_student_id_cards(target_academic_year_id uuid, target_class_id uuid, target_student_ids uuid[], target_issue_date date, target_expires_on date) to edusentia_worker_runtime;

-- list_academic_period_controls()
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
end $function$;
revoke all on function public.list_academic_period_controls() from public;
grant execute on function public.list_academic_period_controls() to edusentia_worker_runtime;

-- list_certificate_eligible_recipients(target_certificate_type text, target_academic_year_id uuid, target_term_id uuid, target_class_id uuid)
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
end $function$;
revoke all on function public.list_certificate_eligible_recipients(target_certificate_type text, target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) from public;
grant execute on function public.list_certificate_eligible_recipients(target_certificate_type text, target_academic_year_id uuid, target_term_id uuid, target_class_id uuid) to edusentia_worker_runtime;

-- list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid, search_text text)
CREATE OR REPLACE FUNCTION public.list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid DEFAULT NULL::uuid, search_text text DEFAULT ''::text)
 RETURNS TABLE(student_id uuid, enrollment_id uuid, full_name text, admission_no text, class_id uuid, class_name text, academic_year_id uuid, academic_year_name text, photo_url text, gender text, date_of_birth date, guardian_phone text, active_card_id uuid, active_card_number text, active_card_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage student ID cards' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit ID card access' using errcode='42501';end if; return query select st.id,e.id,concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),st.admission_no::text,c.id,c.name::text,y.id,y.name::text,st.photo_url,st.gender,st.date_of_birth,coalesce((select nullif(g.phone,'') from public.guardian_links gl join public.student_guardians g on g.id=gl.guardian_id where gl.student_id=st.id order by g.is_primary desc,gl.created_at limit 1),nullif(st.guardian_phone,''),'') guardian_phone,card.id,card.card_number,case when card.id is null then '' else public.id_card_effective_status(card.status,card.expires_on) end from public.enrollments e join public.students st on st.id=e.student_id and st.deleted_at is null and st.status='active' join public.classes c on c.id=e.class_id and c.deleted_at is null and c.active join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null left join lateral(select x.id,x.card_number,x.status,x.expires_on from public.student_id_cards x where x.student_id=st.id and x.academic_year_id=e.academic_year_id and x.status='active' order by x.issued_at desc limit 1) card on true where e.deleted_at is null and e.active and e.academic_year_id=target_academic_year_id and (target_class_id is null or e.class_id=target_class_id) and (btrim(coalesce(search_text,''))='' or st.admission_no::text ilike '%'||btrim(search_text)||'%' or concat_ws(' ',st.first_name,st.middle_name,st.last_name) ilike '%'||btrim(search_text)||'%') order by c.level_order nulls last,c.name,st.last_name,st.first_name; end$function$;
revoke all on function public.list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid, search_text text) from public;
grant execute on function public.list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid, search_text text) to edusentia_worker_runtime;

-- list_my_children_reports()
CREATE OR REPLACE FUNCTION public.list_my_children_reports()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 if public.current_app_role()<>'parent_guardian' then raise exception 'Access denied' using errcode='42501'; end if;
 return jsonb_build_object('children',coalesce((select jsonb_agg(jsonb_build_object(
   'id',s.id,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'class_name',coalesce(c.name,''),'financial_hold',public.finance_student_hold_status(s.id),
   'reports',case when coalesce((public.finance_student_hold_status(s.id)->>'block_grade_details')::boolean,false) then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'report_number',r.report_number,'status',r.status,'term_name',t.name,'academic_year_name',y.name,'average',coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0),'published_at',r.published_at,'publication',case when coalesce((public.finance_student_hold_status(s.id)->>'block_report_pdf')::boolean,false) then null else jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at) end) order by y.start_date desc nulls last,t.sequence desc) from public.enrollments er join public.student_reports r on r.enrollment_id=er.id and r.status='published' and r.deleted_at is null join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id join public.report_publications rp on rp.report_id=r.id and rp.revoked_at is null where er.student_id=s.id and er.deleted_at is null),'[]'::jsonb) end
 ) order by s.last_name,s.first_name) from public.guardian_links gl join public.students s on s.id=gl.student_id and s.deleted_at is null left join lateral(select e.class_id from public.enrollments e where e.student_id=s.id and e.active and e.deleted_at is null order by e.updated_at desc limit 1) ce on true left join public.classes c on c.id=ce.class_id where gl.auth_user_id=auth.uid() and gl.can_view_reports),'[]'::jsonb));
end $function$;
revoke all on function public.list_my_children_reports() from public;
grant execute on function public.list_my_children_reports() to edusentia_worker_runtime;

-- list_report_card_templates()
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
end $function$;
revoke all on function public.list_report_card_templates() from public;
grant execute on function public.list_report_card_templates() to edusentia_worker_runtime;

-- list_report_cards_v6(target_term_id uuid, target_class_id uuid, target_status report_status, search_text text, archive_filter text, page_number integer, page_size integer)
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
end $function$;
revoke all on function public.list_report_cards_v6(target_term_id uuid, target_class_id uuid, target_status report_status, search_text text, archive_filter text, page_number integer, page_size integer) from public;
grant execute on function public.list_report_cards_v6(target_term_id uuid, target_class_id uuid, target_status report_status, search_text text, archive_filter text, page_number integer, page_size integer) to edusentia_worker_runtime;

-- list_staff_id_card_candidates(target_staff_type text, search_text text)
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
end$function$;
revoke all on function public.list_staff_id_card_candidates(target_staff_type text, search_text text) from public;
grant execute on function public.list_staff_id_card_candidates(target_staff_type text, search_text text) to edusentia_worker_runtime;

-- mark_backup_offsite_copy(target_backup_id uuid, target_note text)
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
end $function$;
revoke all on function public.mark_backup_offsite_copy(target_backup_id uuid, target_note text) from public;
grant execute on function public.mark_backup_offsite_copy(target_backup_id uuid, target_note text) to edusentia_worker_runtime;

-- operations_dashboard(target_term_id uuid)
CREATE OR REPLACE FUNCTION public.operations_dashboard(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=target_term_id;health jsonb;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if tid is null then select id into tid from public.terms where is_active and deleted_at is null limit 1; end if;
  health:=public.system_health();
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
    'pending_notifications',health->'pending_notifications','client_errors_24h',health->'client_errors_24h','client_warnings_24h',health->'client_warnings_24h',
    'open_security_events',health->'open_security_events','critical_security_events',health->'critical_security_events',
    'latest_backup',health->'latest_backup','latest_verified_backup',health->'latest_verified_backup','latest_recovery_test',health->'latest_recovery_test',
    'failed_backups_30d',health->'failed_backups_30d','current_backup_failures',health->'current_backup_failures',
    'cron_failures_24h',health->'cron_failures_24h','operational_state',health->'operational_state','health_reasons',health->'health_reasons',
    'continuity_state',health->'continuity_state','continuity_reasons',health->'continuity_reasons',
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
end
$function$;
revoke all on function public.operations_dashboard(target_term_id uuid) from public;
grant execute on function public.operations_dashboard(target_term_id uuid) to edusentia_worker_runtime;

-- platform_clear_license_history(reason_text text, confirmation_text text)
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
$function$;
revoke all on function public.platform_clear_license_history(reason_text text, confirmation_text text) from public;
grant execute on function public.platform_clear_license_history(reason_text text, confirmation_text text) to edusentia_worker_runtime;

-- platform_release_access_lock(target_lock_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.platform_release_access_lock(target_lock_id uuid, reason_text text DEFAULT 'Access lock released'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare old_lock public.platform_access_locks%rowtype;license_id_value uuid;
begin
  perform public.require_platform_super_admin();
  select * into old_lock from public.platform_access_locks where id=target_lock_id and active for update;
  if old_lock.id is null then raise exception 'Active access lock not found' using errcode='P0002'; end if;
  update public.platform_access_locks set active=false,released_at=now(),released_by=auth.uid(),release_reason=coalesce(nullif(trim(reason_text),''),'Access lock released'),updated_at=now()
  where id=target_lock_id;
  select id into license_id_value from public.school_licenses order by created_at limit 1;
  insert into public.license_events(license_id,event_type,actor_id,event_reason,old_data)
  values(license_id_value,'access_lock_released',auth.uid(),coalesce(nullif(trim(reason_text),''),'Access lock released'),to_jsonb(old_lock));
  return public.get_platform_license_console();
end $function$;
revoke all on function public.platform_release_access_lock(target_lock_id uuid, reason_text text) from public;
grant execute on function public.platform_release_access_lock(target_lock_id uuid, reason_text text) to edusentia_worker_runtime;

-- platform_set_access_lock(lock_scope_text text, lock_mode_text text, reason_text text, ends_at_value timestamp with time zone)
CREATE OR REPLACE FUNCTION public.platform_set_access_lock(lock_scope_text text, lock_mode_text text, reason_text text, ends_at_value timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare new_lock public.platform_access_locks%rowtype;license_id_value uuid;
begin
  perform public.require_platform_super_admin();
  if lock_scope_text not in ('system_admin','school','platform') then raise exception 'Invalid lock scope' using errcode='22023'; end if;
  if lock_mode_text not in ('read_only','deny') then raise exception 'Invalid lock mode' using errcode='22023'; end if;
  if length(trim(coalesce(reason_text,'')))<5 then raise exception 'A clear lock reason is required' using errcode='22023'; end if;
  if ends_at_value is not null and ends_at_value<=now() then raise exception 'Lock end time must be in the future' using errcode='22023'; end if;
  update public.platform_access_locks set active=false,released_at=now(),released_by=auth.uid(),release_reason='Replaced by a new lock',updated_at=now()
  where active and lock_scope=lock_scope_text;
  insert into public.platform_access_locks(lock_scope,lock_mode,reason,ends_at,created_by)
  values(lock_scope_text,lock_mode_text,trim(reason_text),ends_at_value,auth.uid()) returning * into new_lock;
  select id into license_id_value from public.school_licenses order by created_at limit 1;
  insert into public.license_events(license_id,event_type,actor_id,event_reason,new_data)
  values(license_id_value,'access_lock_applied',auth.uid(),trim(reason_text),to_jsonb(new_lock));
  return public.get_platform_license_console();
end $function$;
revoke all on function public.platform_set_access_lock(lock_scope_text text, lock_mode_text text, reason_text text, ends_at_value timestamp with time zone) from public;
grant execute on function public.platform_set_access_lock(lock_scope_text text, lock_mode_text text, reason_text text, ends_at_value timestamp with time zone) to edusentia_worker_runtime;

-- platform_set_distribution_authority(target_actor_id uuid, active_value boolean, can_generate_value boolean, can_revoke_value boolean, notes_text text)
CREATE OR REPLACE FUNCTION public.platform_set_distribution_authority(target_actor_id uuid, active_value boolean, can_generate_value boolean, can_revoke_value boolean, notes_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare caller public.platform_distribution_authorities%rowtype;code text;
begin
  perform public.require_platform_super_admin();select * into caller from public.platform_distribution_authorities where actor_id=auth.uid() and active and can_revoke;
  if caller.id is null then raise exception 'Active distributor revocation authority is required to manage distributor access' using errcode='42501';end if;
  if not exists(select 1 from public.profiles p where p.id=target_actor_id and p.active and public.current_app_role_for(p.role)::text='platform_super_admin') then raise exception 'Target account must be an active Platform Super Administrator' using errcode='22023';end if;
  if not (active_value and can_generate_value and can_revoke_value)
     and not exists(select 1 from public.platform_distribution_authorities a where a.actor_id<>target_actor_id and a.active and a.can_generate and a.can_revoke) then
    raise exception 'At least one active distributor must retain both generation and revocation authority' using errcode='23514';
  end if;
  code:='DIST-'||upper(substr(replace(target_actor_id::text,'-',''),1,12));
  insert into public.platform_distribution_authorities(actor_id,distributor_code,active,can_generate,can_revoke,notes)
  values(target_actor_id,code,active_value,can_generate_value,can_revoke_value,coalesce(notes_text,''))
  on conflict(actor_id) do update set active=excluded.active,can_generate=excluded.can_generate,can_revoke=excluded.can_revoke,notes=excluded.notes,updated_at=now();
  insert into public.license_events(event_type,actor_id,event_reason,new_data) values('distribution_authority_updated',auth.uid(),coalesce(nullif(btrim(notes_text),''),'Distributor authority updated'),jsonb_build_object('target_actor_id',target_actor_id,'active',active_value,'can_generate',can_generate_value,'can_revoke',can_revoke_value));
  return public.get_platform_license_console();
end $function$;
revoke all on function public.platform_set_distribution_authority(target_actor_id uuid, active_value boolean, can_generate_value boolean, can_revoke_value boolean, notes_text text) from public;
grant execute on function public.platform_set_distribution_authority(target_actor_id uuid, active_value boolean, can_generate_value boolean, can_revoke_value boolean, notes_text text) to edusentia_worker_runtime;

-- platform_update_license(target_plan_id uuid, target_status text, issue_date date, activation_date timestamp with time zone, expiry_date timestamp with time zone, grace_end_date timestamp with time zone, license_reference_text text, notes_text text, compliance_reason_text text)
CREATE OR REPLACE FUNCTION public.platform_update_license(target_plan_id uuid, target_status text, issue_date date, activation_date timestamp with time zone DEFAULT NULL::timestamp with time zone, expiry_date timestamp with time zone DEFAULT NULL::timestamp with time zone, grace_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, license_reference_text text DEFAULT ''::text, notes_text text DEFAULT ''::text, compliance_reason_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cur public.school_licenses%rowtype;updated public.school_licenses%rowtype;p public.license_plans%rowtype;preview jsonb;old_json jsonb;effective_activation timestamptz;
begin
  perform public.require_platform_super_admin();select * into p from public.license_plans where id=target_plan_id and active;if p.id is null then raise exception 'Select an active licence plan' using errcode='22023';end if;
  select * into cur from public.school_licenses order by created_at limit 1 for update;
  if cur.id is null then raise exception 'Platform licence is not configured' using errcode='22023';end if;
  if cur.package_id is not null then raise exception 'Signed generated-package licences cannot be amended locally; issue a replacement package' using errcode='42501';end if;
  if target_status not in ('pending_activation','active','grace_period','expired','suspended','revoked','perpetual') then raise exception 'Invalid licence status' using errcode='22023';end if;
  if issue_date is null or length(btrim(coalesce(license_reference_text,'')))<5 then raise exception 'Issue date and a valid licence reference are required' using errcode='22023';end if;
  if target_status in ('suspended','revoked') and length(btrim(coalesce(compliance_reason_text,'')))<5 then raise exception 'A compliance reason is required' using errcode='22023';end if;
  effective_activation:=case when target_status in ('active','grace_period','perpetual') then coalesce(activation_date,now()) else activation_date end;
  if target_status in ('active','grace_period','perpetual','expired') and issue_date>current_date then raise exception 'Issue date cannot be in the future for this status' using errcode='22023';end if;
  if effective_activation is not null and effective_activation::date<issue_date then raise exception 'Activation date cannot precede issue date' using errcode='22023';end if;
  if target_status in ('active','grace_period','perpetual') and effective_activation>now() then raise exception 'Activation date cannot be in the future for an active licence' using errcode='22023';end if;
  if target_status='perpetual' and not p.perpetual_allowed then raise exception 'The selected plan does not permit perpetual licensing' using errcode='22023';end if;
  if target_status='perpetual' and (expiry_date is not null or grace_end_date is not null) then raise exception 'A perpetual licence cannot have expiry or grace dates' using errcode='22023';end if;
  if target_status<>'perpetual' and p.billing_cycle in ('monthly','annual') and expiry_date is null then raise exception 'This plan requires an expiry date' using errcode='22023';end if;
  if expiry_date is not null and (expiry_date::date<issue_date or (effective_activation is not null and expiry_date<=effective_activation)) then raise exception 'Expiry must be after issue and activation' using errcode='22023';end if;
  if target_status<>'perpetual' and p.billing_cycle in ('monthly','annual') and expiry_date>coalesce(effective_activation,issue_date::timestamptz)+make_interval(days=>p.default_term_days)+interval '1 day' then raise exception 'Expiry exceeds the selected plan term of % days',p.default_term_days using errcode='22023';end if;
  if grace_end_date is not null and (expiry_date is null or grace_end_date<expiry_date or grace_end_date>expiry_date+make_interval(days=>p.grace_days)) then raise exception 'Grace end must be between expiry and the plan grace limit' using errcode='22023';end if;
  if target_status='grace_period' and (expiry_date is null or grace_end_date is null or expiry_date>now() or grace_end_date<now()) then raise exception 'Grace-period status requires a past expiry and a current grace window' using errcode='22023';end if;
  if target_status='expired' and (expiry_date is null or expiry_date>now()) then raise exception 'Expired status requires an expiry date that has passed' using errcode='22023';end if;
  if target_status='active' and expiry_date is not null and expiry_date<=now() then raise exception 'Active status requires a future expiry date' using errcode='22023';end if;
  preview:=public.platform_preview_license_change(target_plan_id);if not (preview->>'compatible')::boolean then raise exception 'LICENSE_DOWNGRADE_BLOCKED: Current usage exceeds the target plan: %',preview->'excess' using errcode='23514';end if;
  old_json:=to_jsonb(cur);
  update public.school_licenses set plan_id=p.id,plan_revision=p.revision,license_reference=btrim(license_reference_text),status=target_status,issued_on=issue_date,activated_at=effective_activation,expires_at=case when target_status='perpetual' then null else expiry_date end,grace_ends_at=case when target_status='perpetual' then null else grace_end_date end,notes=coalesce(notes_text,''),compliance_reason=coalesce(compliance_reason_text,''),
    entitlement_snapshot='{}'::jsonb,entitlement_payload='',entitlement_hash='',entitlement_signature='',signature_algorithm='',signature_key_id='',signature_status='not_required',signature_verified_at=null,package_id=null,installation_id=null,tenant_code='',authorized_domains='{}'::text[],project_ref='',distributor_id=null,authority_url='',authority_token='',authority_status='not_required',authority_checked_at=null,authority_last_success_at=null,updated_by=auth.uid(),updated_at=now() where id=cur.id returning * into updated;
  insert into public.license_events(license_id,event_type,actor_id,event_reason,old_data,new_data) values(updated.id,'license_updated',auth.uid(),coalesce(nullif(compliance_reason_text,''),'Platform licence updated'),old_json-'license_key_hash',to_jsonb(updated)-'license_key_hash');return public.get_platform_license_console();
end $function$;
revoke all on function public.platform_update_license(target_plan_id uuid, target_status text, issue_date date, activation_date timestamp with time zone, expiry_date timestamp with time zone, grace_end_date timestamp with time zone, license_reference_text text, notes_text text, compliance_reason_text text) from public;
grant execute on function public.platform_update_license(target_plan_id uuid, target_status text, issue_date date, activation_date timestamp with time zone, expiry_date timestamp with time zone, grace_end_date timestamp with time zone, license_reference_text text, notes_text text, compliance_reason_text text) to edusentia_worker_runtime;

-- platform_upsert_license_plan(payload jsonb)
CREATE OR REPLACE FUNCTION public.platform_upsert_license_plan(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare pid uuid:=public.safe_uuid(payload->>'id');p public.license_plans%rowtype;preview jsonb;reason text:=btrim(coalesce(payload->>'reason',''));
  plan_code text:=lower(btrim(coalesce(payload->>'code','')));plan_name text:=btrim(coalesce(payload->>'name',''));
  cycle text:=lower(btrim(coalesce(payload->>'billing_cycle','annual')));support text:=lower(btrim(coalesce(payload->>'support_level','standard')));
  flags jsonb:=coalesce(payload->'feature_flags','{}'::jsonb)-'platform_package_management';term_days integer;grace_value integer;
begin
  perform public.require_platform_super_admin();
  if jsonb_typeof(coalesce(payload,'{}'::jsonb))<>'object' then raise exception 'Plan payload must be a JSON object' using errcode='22023';end if;
  if length(reason)<5 then raise exception 'A plan revision reason is required' using errcode='22023';end if;
  if pid is null and plan_code!~'^[a-z][a-z0-9_]{2,39}$' then raise exception 'Plan code must contain 3-40 lowercase letters, numbers, or underscores' using errcode='22023';end if;
  if length(plan_name)<3 or length(plan_name)>100 then raise exception 'Plan name must contain 3-100 characters' using errcode='22023';end if;
  if cycle not in ('monthly','annual','custom') then raise exception 'Billing cycle must be monthly, annual, or custom' using errcode='22023';end if;
  if support not in ('standard','priority','enterprise','custom') then raise exception 'Support level must be standard, priority, enterprise, or custom' using errcode='22023';end if;
  if jsonb_typeof(flags)<>'object' or exists(select 1 from jsonb_each(flags) x where jsonb_typeof(x.value)<>'boolean') then raise exception 'Every plan feature flag must be a Boolean value' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(flags) x where not exists(select 1 from public.license_feature_catalog f where f.code=x.key)) then raise exception 'Feature flags contain an unknown feature code' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(flags) x join public.license_feature_catalog f on f.code=x.key where x.value='true'::jsonb and not f.active) then raise exception 'Inactive features cannot be enabled' using errcode='22023';end if;
  if flags->'core_records' is distinct from 'true'::jsonb or flags->'governance' is distinct from 'true'::jsonb then raise exception 'Every active school plan must include core_records and governance' using errcode='22023';end if;
  if payload ? 'active' and jsonb_typeof(payload->'active')<>'boolean' then raise exception 'Plan active status must be Boolean' using errcode='22023';end if;
  if payload ? 'perpetual_allowed' and jsonb_typeof(payload->'perpetual_allowed')<>'boolean' then raise exception 'Perpetual-allowed status must be Boolean' using errcode='22023';end if;
  term_days:=coalesce(nullif(payload->>'default_term_days','')::integer,365);grace_value:=coalesce(nullif(payload->>'grace_days','')::integer,30);
  if term_days not between 1 and 3660 or grace_value not between 0 and 365 then raise exception 'Plan term or grace period is outside the permitted range' using errcode='22023';end if;
  if exists(select 1 from (values(nullif(payload->>'max_students','')::integer),(nullif(payload->>'max_teachers','')::integer),(nullif(payload->>'max_system_admins','')::integer),(nullif(payload->>'max_guardians','')::integer),(nullif(payload->>'max_storage_mb','')::integer)) v(n) where n is not null and n<=0) then raise exception 'Plan capacities must be positive or unlimited' using errcode='22023';end if;
  if pid is not null and coalesce((payload->>'active')::boolean,true)=false and exists(select 1 from public.school_licenses where plan_id=pid) then raise exception 'A plan assigned to the current licence cannot be deactivated' using errcode='23503';end if;
  if pid is null then
    insert into public.license_plans(code,name,description,billing_cycle,max_students,max_teachers,max_system_admins,max_guardians,max_storage_mb,feature_flags,default_term_days,grace_days,perpetual_allowed,support_level,active,revision)
    values(plan_code,plan_name,coalesce(payload->>'description',''),cycle,nullif(payload->>'max_students','')::integer,nullif(payload->>'max_teachers','')::integer,nullif(payload->>'max_system_admins','')::integer,nullif(payload->>'max_guardians','')::integer,nullif(payload->>'max_storage_mb','')::integer,flags,term_days,grace_value,coalesce((payload->>'perpetual_allowed')::boolean,false),support,coalesce((payload->>'active')::boolean,true),1) returning * into p;
  else
    update public.license_plans set name=plan_name,description=coalesce(payload->>'description',''),billing_cycle=cycle,max_students=nullif(payload->>'max_students','')::integer,max_teachers=nullif(payload->>'max_teachers','')::integer,max_system_admins=nullif(payload->>'max_system_admins','')::integer,max_guardians=nullif(payload->>'max_guardians','')::integer,max_storage_mb=nullif(payload->>'max_storage_mb','')::integer,feature_flags=flags,default_term_days=term_days,grace_days=grace_value,perpetual_allowed=coalesce((payload->>'perpetual_allowed')::boolean,perpetual_allowed),support_level=support,active=coalesce((payload->>'active')::boolean,active),revision=revision+1,updated_at=now() where id=pid returning * into p;
    if p.id is null then raise exception 'Licence plan not found' using errcode='22023';end if;
  end if;
  if exists(select 1 from public.school_licenses l where l.plan_id=p.id) then
    preview:=public.platform_preview_license_change(p.id);
    if not coalesce((preview->>'compatible')::boolean,false) then raise exception 'LICENSE_CAPACITY_REACHED: The revised plan is below current usage: %',preview->'excess' using errcode='23514';end if;
  end if;
  insert into public.license_plan_revisions(plan_id,revision,snapshot,reason,actor_id) values(p.id,p.revision,to_jsonb(p),reason,auth.uid());
  insert into public.license_events(event_type,actor_id,event_reason,new_data) values('plan_revision_created',auth.uid(),reason,to_jsonb(p));return public.get_platform_license_console();
end $function$;
revoke all on function public.platform_upsert_license_plan(payload jsonb) from public;
grant execute on function public.platform_upsert_license_plan(payload jsonb) to edusentia_worker_runtime;

-- publish_school_prospectus(target_prospectus_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.publish_school_prospectus(target_prospectus_id uuid, reason_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare p public.school_prospectuses%rowtype;next_revision integer;snapshot jsonb;reason_value text:=btrim(coalesce(reason_text,''));begin if not public.is_system_admin() then raise exception 'Only the System Administrator can publish school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus publication' using errcode='42501';end if;select * into p from public.school_prospectuses where id=target_prospectus_id for update;if p.id is null then raise exception 'Prospectus not found';end if;if p.status='archived' then raise exception 'Archived prospectuses cannot be published';end if;if not exists(select 1 from public.school_prospectus_sections s join public.school_prospectus_items i on i.section_id=s.id where s.prospectus_id=p.id) then raise exception 'Add at least one prospectus item before publishing';end if;if exists(select 1 from public.school_prospectus_sections s join public.school_prospectus_items i on i.section_id=s.id where s.prospectus_id=p.id and s.section_type in ('main_fees','other_items','transportation') and i.charge_basis not in ('free','optional','informational') and i.amount is null) then raise exception 'Every payable fee or transport item must have an amount before publication';end if;next_revision:=p.revision_no+1;update public.school_prospectuses set status='published',revision_no=next_revision,published_by=auth.uid(),published_at=now(),updated_by=auth.uid(),updated_at=now() where id=p.id;snapshot:=public.build_school_prospectus_snapshot(p.id);insert into public.school_prospectus_revisions(prospectus_id,revision_no,snapshot,reason,published_by) values(p.id,next_revision,snapshot,reason_value,auth.uid());return snapshot;end$function$;
revoke all on function public.publish_school_prospectus(target_prospectus_id uuid, reason_text text) from public;
grant execute on function public.publish_school_prospectus(target_prospectus_id uuid, reason_text text) to edusentia_worker_runtime;

-- queue_incomplete_report_notifications(target_term_id uuid)
CREATE OR REPLACE FUNCTION public.queue_incomplete_report_notifications(target_term_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare queued integer:=0; recipient uuid; item record;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  for item in
    select c.id class_id,c.name class_name,count(e.id) enrolled,
      count(r.id) filter(where r.status in ('submitted','class_reviewed','approved','published')) completed
    from public.classes c
    join public.enrollments e on e.class_id=c.id
    join public.terms t on t.academic_year_id=e.academic_year_id and t.id=target_term_id
    left join public.student_reports r on r.enrollment_id=e.id and r.term_id=t.id and r.deleted_at is null
    where c.active and c.deleted_at is null and e.active and e.deleted_at is null
    group by c.id,c.name
    having count(e.id)>count(r.id) filter(where r.status in ('submitted','class_reviewed','approved','published'))
  loop
    for recipient in
      select distinct user_id from (
        select c.class_teacher_id user_id from public.classes c where c.id=item.class_id and c.class_teacher_id is not null
        union all select cs.teacher_id from public.class_subjects cs where cs.class_id=item.class_id and cs.teacher_id is not null and cs.active
      ) q
    loop
      perform public.create_notification(recipient,'Incomplete report cards',
        item.class_name||' • '||(item.enrolled-item.completed)||' remaining','report_deadline','term',target_term_id,true);
      queued:=queued+1;
    end loop;
  end loop;
  return queued;
end $function$;
revoke all on function public.queue_incomplete_report_notifications(target_term_id uuid) from public;
grant execute on function public.queue_incomplete_report_notifications(target_term_id uuid) to edusentia_worker_runtime;

-- record_security_event(event_type_text text, severity_text text, message_text text, details_data jsonb, source_text text)
CREATE OR REPLACE FUNCTION public.record_security_event(event_type_text text, severity_text text, message_text text, details_data jsonb DEFAULT '{}'::jsonb, source_text text DEFAULT 'application'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  eid bigint;
  sev text:=lower(coalesce(severity_text,'info'));
  event_name text:=left(lower(btrim(coalesce(event_type_text,'unknown'))),100);
  msg text:=left(coalesce(message_text,'Security event'),1000);
  src text:=left(coalesce(source_text,'application'),100);
  jwt_role text:=coalesce(current_setting('request.jwt.claim.role',true),'');
  app_role text:=coalesce(public.current_app_role()::text,'');
  recent_id bigint;
begin
  if auth.uid() is null and jwt_role<>'service_role' then raise exception 'Authentication required' using errcode='42501'; end if;
  if octet_length(coalesce(details_data,'{}'::jsonb)::text)>8000 then raise exception 'Security-event details are too large'; end if;

  if jwt_role<>'service_role' then
    if app_role not in ('system_admin','principal') then
      if event_name<>'authorization_denied' then raise exception 'Unsupported client security event' using errcode='42501'; end if;
      sev:='warning'; src:='web_client';
    elsif sev not in ('info','warning','high','critical') then
      sev:='warning';
    end if;
    if (select count(*) from public.security_events where actor_id=auth.uid() and created_at>now()-interval '5 minutes')>=20 then
      raise exception 'Security event rate limit exceeded' using errcode='42901';
    end if;
    select id into recent_id from public.security_events
      where actor_id=auth.uid() and event_type=event_name and message=msg and created_at>now()-interval '60 seconds'
      order by created_at desc limit 1;
    if recent_id is not null then return recent_id; end if;
  else
    if sev not in ('info','warning','high','critical') then sev:='warning'; end if;
  end if;

  insert into public.security_events(actor_id,event_type,severity,source,message,details)
  values(auth.uid(),event_name,sev,src,msg,coalesce(details_data,'{}'::jsonb)) returning id into eid;
  return eid;
end $function$;
revoke all on function public.record_security_event(event_type_text text, severity_text text, message_text text, details_data jsonb, source_text text) from public;
grant execute on function public.record_security_event(event_type_text text, severity_text text, message_text text, details_data jsonb, source_text text) to edusentia_worker_runtime;

-- record_student_lifecycle_event(payload jsonb)
CREATE OR REPLACE FUNCTION public.record_student_lifecycle_event(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid:=public.safe_uuid(payload->>'student_id');etype text:=lower(coalesce(payload->>'event_type','')); evt public.student_lifecycle_events; current_class uuid;
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can manage student lifecycle records' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if etype not in ('transfer_in','transfer_out','withdrawn','graduated','inactive','reactivated','archived') then raise exception 'Invalid lifecycle event'; end if;
  if length(btrim(coalesce(payload->>'reason','')))<5 then raise exception 'A reason of at least 5 characters is required'; end if;
  select e.class_id into current_class from public.enrollments e where e.student_id=sid and e.active and e.deleted_at is null order by e.created_at desc limit 1;
  insert into public.student_lifecycle_events(student_id,event_type,effective_date,from_class_id,to_class_id,destination_school,reason,reference)
  values(sid,etype,coalesce(public.safe_date(payload->>'effective_date'),current_date),coalesce(public.safe_uuid(payload->>'from_class_id'),current_class),public.safe_uuid(payload->>'to_class_id'),left(coalesce(payload->>'destination_school',''),250),btrim(payload->>'reason'),left(coalesce(payload->>'reference',''),250)) returning * into evt;
  if etype in ('transfer_out','withdrawn','archived') then
    update public.students set status='withdrawn',updated_at=now() where id=sid;
    update public.enrollments set active=false,updated_at=now() where student_id=sid and active and deleted_at is null;
  elsif etype='graduated' then
    update public.students set status='graduated',updated_at=now() where id=sid;
    update public.enrollments set active=false,updated_at=now() where student_id=sid and active and deleted_at is null;
  elsif etype='inactive' then
    update public.students set status='suspended',updated_at=now() where id=sid;
  elsif etype in ('reactivated','transfer_in') then
    update public.students set status='active',updated_at=now() where id=sid;
  end if;
  return to_jsonb(evt);
end $function$;
revoke all on function public.record_student_lifecycle_event(payload jsonb) from public;
grant execute on function public.record_student_lifecycle_event(payload jsonb) to edusentia_worker_runtime;

-- register_certificate_pdf(target_certificate_id uuid, target_storage_path text, target_checksum text)
CREATE OR REPLACE FUNCTION public.register_certificate_pdf(target_certificate_id uuid, target_storage_path text, target_checksum text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificates;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can store certificate PDFs' using errcode='42501'; end if;
  if btrim(coalesce(target_storage_path,''))='' or target_storage_path !~ '^[a-z_]+/[A-Za-z0-9._/-]+[.]pdf$' then raise exception 'Certificate PDF path is invalid'; end if;
  update public.certificates set pdf_storage_path=btrim(target_storage_path),pdf_sha256=lower(btrim(coalesce(target_checksum,''))),updated_at=now() where id=target_certificate_id and status='issued' returning * into updated;
  if updated.id is null then raise exception 'Issued certificate not found'; end if;
  perform public.record_certificate_event(updated.batch_id,updated.id,'pdf_registered','',jsonb_build_object('storage_path',updated.pdf_storage_path,'sha256',updated.pdf_sha256));
  return jsonb_build_object('certificate_id',updated.id,'storage_path',updated.pdf_storage_path,'checksum',updated.pdf_sha256);
end $function$;
revoke all on function public.register_certificate_pdf(target_certificate_id uuid, target_storage_path text, target_checksum text) from public;
grant execute on function public.register_certificate_pdf(target_certificate_id uuid, target_storage_path text, target_checksum text) to edusentia_worker_runtime;

-- remove_certificate_template_file(target_certificate_type text)
CREATE OR REPLACE FUNCTION public.remove_certificate_template_file(target_certificate_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result public.certificate_templates; archived_path text; archived_name text;
begin
  if not public.can_manage_certificates() then
    raise exception 'Only the System Administrator can remove certificate template designs' using errcode='42501';
  end if;
  if target_certificate_type not in ('student_promotion','jhs_completion','teacher_recognition') then
    raise exception 'Certificate type is invalid';
  end if;
  select storage_path,original_name into archived_path,archived_name
  from public.certificate_templates
  where certificate_type=target_certificate_type and active
  order by updated_at desc limit 1;
  update public.certificate_templates
  set storage_path='',original_name='',mime_type='',file_size=0,checksum='',version=version+1,uploaded_by=null,updated_at=now()
  where certificate_type=target_certificate_type and active
  returning * into result;
  if result.id is null then raise exception 'Active certificate template not found'; end if;
  perform public.record_certificate_event(
    null,null,'certificate_template_design_removed','',
    jsonb_build_object('certificate_type',target_certificate_type,'archived_storage_path',coalesce(archived_path,''),'archived_original_name',coalesce(archived_name,''),'version',result.version)
  );
  return to_jsonb(result);
end $function$;
revoke all on function public.remove_certificate_template_file(target_certificate_type text) from public;
grant execute on function public.remove_certificate_template_file(target_certificate_type text) to edusentia_worker_runtime;

-- remove_report_card_template(target_range_key text)
CREATE OR REPLACE FUNCTION public.remove_report_card_template(target_range_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result public.report_card_templates;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  if target_range_key not in ('early_years','basic_1_6','basic_7_9') then raise exception 'Invalid report-card class range'; end if;
  delete from public.report_card_templates where range_key=target_range_key returning * into result;
  return case when result.range_key is null then '{}'::jsonb else to_jsonb(result) end;
end $function$;
revoke all on function public.remove_report_card_template(target_range_key text) from public;
grant execute on function public.remove_report_card_template(target_range_key text) to edusentia_worker_runtime;

-- replace_staff_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date)
CREATE OR REPLACE FUNCTION public.replace_staff_id_card(target_card_id uuid, reason_text text, target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare source public.staff_id_cards%rowtype;cfg public.id_card_settings%rowtype;new_id uuid;new_number text;new_token uuid;expires date:=target_expires_on;new_snapshot jsonb;reason text:=btrim(coalesce(reason_text,''));sid uuid;
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can replace staff ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A replacement reason of at least five characters is required';end if;select * into source from public.staff_id_cards where id=target_card_id and status='active' for update;if source.id is null then raise exception 'Only an active staff ID card can be replaced';end if;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.staff_validity_months,24)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'Staff ID card expiry date cannot be before issue date';end if;sid:=coalesce(source.teacher_id,source.headteacher_id);update public.staff_id_cards set status='replaced',replacement_reason=reason,updated_at=now() where id=source.id;new_number:=public.generate_staff_id_card_number(source.academic_year_id);new_token:=gen_random_uuid();new_snapshot:=public.build_staff_id_card_snapshot(source.staff_type,sid,source.academic_year_id,new_number,new_token,target_issue_date,expires);insert into public.staff_id_cards(staff_type,teacher_id,headteacher_id,academic_year_id,card_number,verification_token,revision_no,supersedes_card_id,status,issue_date,expires_on,snapshot,issued_by,replacement_reason) values(source.staff_type,source.teacher_id,source.headteacher_id,source.academic_year_id,new_number,new_token,source.revision_no+1,source.id,'active',target_issue_date,expires,new_snapshot,auth.uid(),reason) returning id into new_id;perform public.record_staff_id_card_event(source.id,source.staff_type,sid,'replaced',jsonb_build_object('replacement_card_id',new_id,'reason',reason));perform public.record_staff_id_card_event(new_id,source.staff_type,sid,'replacement_issued',jsonb_build_object('supersedes_card_id',source.id,'reason',reason));return jsonb_build_object('card_id',new_id,'card_number',new_number,'verification_token',new_token,'status','active','supersedes_card_id',source.id);end$function$;
revoke all on function public.replace_staff_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) from public;
grant execute on function public.replace_staff_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) to edusentia_worker_runtime;

-- replace_student_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date)
CREATE OR REPLACE FUNCTION public.replace_student_id_card(target_card_id uuid, reason_text text, target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare source public.student_id_cards%rowtype;cfg public.id_card_settings%rowtype;new_id uuid;new_number text;new_token uuid;expires date:=target_expires_on;new_snapshot jsonb;reason text:=btrim(coalesce(reason_text,'')); begin if not public.is_system_admin() then raise exception 'Only the System Administrator can replace student ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A replacement reason of at least five characters is required';end if;if target_issue_date is null then raise exception 'ID card issue date is required';end if;perform pg_advisory_xact_lock(hashtext('rce-id-card-replace-'||target_card_id::text));insert into public.id_card_settings default values on conflict do nothing;select * into source from public.student_id_cards where id=target_card_id and status='active' for update;if source.id is null then raise exception 'Only an active ID card can be replaced';end if;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.validity_months,12)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'ID card expiry date cannot be before the issue date';end if;update public.student_id_cards set status='replaced',replacement_reason=reason,updated_at=now() where id=source.id;new_number:=public.generate_student_id_card_number(source.academic_year_id);new_token:=gen_random_uuid();new_snapshot:=public.build_student_id_card_snapshot(source.student_id,source.enrollment_id,new_number,new_token,target_issue_date,expires);insert into public.student_id_cards(student_id,enrollment_id,academic_year_id,class_id,card_number,verification_token,revision_no,supersedes_card_id,status,issue_date,expires_on,snapshot,issued_by,replacement_reason) values(source.student_id,source.enrollment_id,source.academic_year_id,source.class_id,new_number,new_token,source.revision_no+1,source.id,'active',target_issue_date,expires,new_snapshot,auth.uid(),reason) returning id into new_id;perform public.record_id_card_event(source.id,source.student_id,'replaced',jsonb_build_object('replacement_card_id',new_id,'reason',reason));perform public.record_id_card_event(new_id,source.student_id,'replacement_issued',jsonb_build_object('supersedes_card_id',source.id,'reason',reason));return jsonb_build_object('card_id',new_id,'card_number',new_number,'verification_token',new_token,'status','active','supersedes_card_id',source.id);end$function$;
revoke all on function public.replace_student_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) from public;
grant execute on function public.replace_student_id_card(target_card_id uuid, reason_text text, target_issue_date date, target_expires_on date) to edusentia_worker_runtime;

-- report_position(target_report_id uuid)
CREATE OR REPLACE FUNCTION public.report_position(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with target as (
    select e.class_id,r.term_id,round(coalesce(avg(sr.total_score),0),2) average
    from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
    left join public.subject_results sr on sr.report_id=r.id
    where r.id=target_report_id group by e.class_id,r.term_id
  ), ranked as (
    select r.id,round(coalesce(avg(sr.total_score),0),2) average,
      dense_rank() over(order by avg(sr.total_score) desc nulls last) position
    from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
    left join public.subject_results sr on sr.report_id=r.id
    join target t on t.class_id=e.class_id and t.term_id=r.term_id
    where r.deleted_at is null and r.status in ('approved','published')
    group by r.id
  )
  select jsonb_build_object('position',coalesce((select position from ranked where id=target_report_id),0),
    'class_size',(select count(*) from ranked))
$function$;
revoke all on function public.report_position(target_report_id uuid) from public;
grant execute on function public.report_position(target_report_id uuid) to edusentia_worker_runtime;

-- report_promotion_canonical(target_report_id uuid)
CREATE OR REPLACE FUNCTION public.report_promotion_canonical(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare v_evaluation jsonb; v_snapshot_promotion jsonb; v_status text; v_version integer; v_promoted_class_id uuid; v_promoted_class_name text; v_student_id uuid; v_target_enrollment_id uuid; v_target_year_id uuid; v_target_year_name text; v_is_final boolean:=false; begin if auth.uid() is not null and not public.can_view_report(target_report_id) then raise exception 'Access denied' using errcode='42501'; end if; select r.status::text,r.version,r.promoted_to_class_id,e.student_id into v_status,v_version,v_promoted_class_id,v_student_id from public.student_reports r join public.enrollments e on e.id=r.enrollment_id and e.deleted_at is null where r.id=target_report_id and r.deleted_at is null; if v_status is null then raise exception 'Report not found'; end if; v_is_final:=v_status in ('approved','published'); if v_is_final then select rr.snapshot->'promotion' into v_snapshot_promotion from public.report_revisions rr where rr.report_id=target_report_id and rr.version=v_version and jsonb_typeof(rr.snapshot->'promotion')='object' limit 1; if v_snapshot_promotion is not null then return v_snapshot_promotion || jsonb_build_object( 'canonical',true, 'finalized',true, 'canonical_source','finalized_report_snapshot', 'resolution_status','resolved' ); end if; end if; v_evaluation:=public.report_promotion_evaluation(target_report_id); if v_is_final and v_promoted_class_id is not null then select c.name::text into v_promoted_class_name from public.classes c where c.id=v_promoted_class_id; select en.id,en.academic_year_id,ay.name::text into v_target_enrollment_id,v_target_year_id,v_target_year_name from public.enrollments en left join public.academic_years ay on ay.id=en.academic_year_id where en.student_id=v_student_id and en.promotion_source_report_id=target_report_id and en.enrollment_origin='automatic_promotion' order by en.promotion_applied_at desc nulls last,en.updated_at desc,en.id limit 1; v_evaluation:=v_evaluation || jsonb_build_object( 'passed',true, 'eligible',true, 'next_class_id',v_promoted_class_id, 'next_class_name',coalesce(v_promoted_class_name,v_evaluation->>'next_class_name',''), 'next_class_configured',true, 'target_enrollment_id',coalesce(v_target_enrollment_id,public.safe_uuid(v_evaluation->>'target_enrollment_id')), 'target_academic_year_id',coalesce(v_target_year_id,public.safe_uuid(v_evaluation->>'target_academic_year_id')), 'target_academic_year_name',coalesce(v_target_year_name,v_evaluation->>'target_academic_year_name',''), 'promotion_applied',true, 'canonical',true, 'finalized',true, 'canonical_source','persisted_promotion_transition', 'resolution_status','resolved' ); else v_evaluation:=v_evaluation || jsonb_build_object( 'next_class_configured',(v_evaluation->>'next_class_id') is not null, 'canonical',v_is_final, 'finalized',v_is_final, 'canonical_source',case when v_is_final then 'server_final_evaluation' else 'server_live_evaluation' end, 'resolution_status','resolved' ); end if; return v_evaluation; end $function$;
revoke all on function public.report_promotion_canonical(target_report_id uuid) from public;
grant execute on function public.report_promotion_canonical(target_report_id uuid) to edusentia_worker_runtime;

-- report_subject_positions(target_report_id uuid)
CREATE OR REPLACE FUNCTION public.report_subject_positions(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  target_class_id uuid;
  target_term_id uuid;
  result jsonb;
begin
  if auth.uid() is null or not public.can_view_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select e.class_id,r.term_id
  into target_class_id,target_term_id
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id
    and r.deleted_at is null
    and e.deleted_at is null;
  if target_class_id is null or target_term_id is null then
    raise exception 'Report not found';
  end if;
  with ranked as (
    select
      sr.report_id,
      sr.subject_id,
      sr.total_score,
      dense_rank() over(
        partition by sr.subject_id
        order by sr.total_score desc
      ) as subject_position,
      count(*) over(partition by sr.subject_id) as participant_count
    from public.subject_results sr
    join public.student_reports r on r.id=sr.report_id
    join public.enrollments e on e.id=r.enrollment_id
    where r.term_id=target_term_id
      and e.class_id=target_class_id
      and r.deleted_at is null
      and e.deleted_at is null
      and r.status<>'withdrawn'
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'subject_id',ranked.subject_id,
        'total_score',ranked.total_score,
        'position',ranked.subject_position,
        'participants',ranked.participant_count
      )
      order by subjects.display_order,subjects.name
    ),
    '[]'::jsonb
  )
  into result
  from ranked
  join public.subjects subjects on subjects.id=ranked.subject_id
  where ranked.report_id=target_report_id;
  return result;
end $function$;
revoke all on function public.report_subject_positions(target_report_id uuid) from public;
grant execute on function public.report_subject_positions(target_report_id uuid) to edusentia_worker_runtime;

-- request_report_correction(target_report_id uuid, reason_text text, requested_fields jsonb)
CREATE OR REPLACE FUNCTION public.request_report_correction(target_report_id uuid, reason_text text, requested_fields jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid; current_version integer; current_status public.report_status; req public.report_correction_requests; classid uuid; recipient uuid;
begin
  if public.current_app_role() not in ('system_admin','class_teacher','subject_teacher') then raise exception 'Only an assigned teacher or the System Administrator can request a correction' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<10 then raise exception 'A correction reason of at least 10 characters is required'; end if;
  select r.id,r.version,r.status,e.class_id into rid,current_version,current_status,classid
  from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id and r.deleted_at is null;
  if rid is null or current_status not in ('approved','published') then raise exception 'Only an approved or published report can receive a correction request'; end if;
  if exists(select 1 from public.report_correction_requests where report_id=target_report_id and status in ('pending','approved')) then raise exception 'This report already has an active correction request'; end if;
  if public.current_app_role()<>'system_admin' and not public.can_access_class(classid,false) then raise exception 'Access denied' using errcode='42501'; end if;
  insert into public.report_correction_requests(report_id,requested_by,reason,requested_fields,original_report_version,original_revision_id,original_publication_id)
  values(target_report_id,auth.uid(),btrim(reason_text),coalesce(requested_fields,'[]'::jsonb),current_version,
    (select id from public.report_revisions where report_id=target_report_id order by version desc limit 1),
    (select id from public.report_publications where report_id=target_report_id and revoked_at is null order by published_at desc limit 1))
  returning * into req;
  insert into public.report_correction_events(request_id,event_type,event_note,event_data)
  values(req.id,'requested',req.reason,jsonb_build_object('requested_fields',req.requested_fields,'report_version',current_version));
  for recipient in select p.id from public.profiles p where p.active and public.current_app_role_for(p.role)::text='principal' loop
    perform public.create_notification(recipient,'Report correction approval required',req.reason,'report_correction','report',target_report_id,true);
  end loop;
  return to_jsonb(req);
end $function$;
revoke all on function public.request_report_correction(target_report_id uuid, reason_text text, requested_fields jsonb) from public;
grant execute on function public.request_report_correction(target_report_id uuid, reason_text text, requested_fields jsonb) to edusentia_worker_runtime;

-- reset_audit_log(confirmation_text text)
CREATE OR REPLACE FUNCTION public.reset_audit_log(confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  changed integer;
  archive_id uuid;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can archive the audit trail' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if upper(btrim(coalesce(confirmation_text,''))) not in ('ARCHIVE AUDIT LOG','RESET AUDIT LOG') then
    raise exception 'Type ARCHIVE AUDIT LOG to confirm';
  end if;
  perform pg_advisory_xact_lock(hashtext('rce-school-audit-archive'));
  lock table public.audit_log in access exclusive mode;
  select count(*)::integer into changed from public.audit_log;
  insert into public.audit_log_archives(archive_scope,reason,event_count,created_by)
  values('full','Full audit log archived from the active console',changed,auth.uid())
  returning id into archive_id;
  insert into public.audit_log_archive_entries(
    archive_id,original_event_id,actor_id,table_name,record_id,action,old_data,new_data,reason,original_created_at
  )
  select archive_id,a.id,a.actor_id,a.table_name,a.record_id,a.action,a.old_data,a.new_data,a.reason,a.created_at
  from public.audit_log a;
  truncate table public.audit_log restart identity;
  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details)
  values(auth.uid(),'ARCHIVE_AUDIT_LOG',changed,jsonb_build_object('archive_id',archive_id,'confirmation','ARCHIVE AUDIT LOG'));
  return jsonb_build_object('deleted',changed,'archived',changed,'archive_id',archive_id,'archived_at',now());
end
$function$;
revoke all on function public.reset_audit_log(confirmation_text text) from public;
grant execute on function public.reset_audit_log(confirmation_text text) to edusentia_worker_runtime;

-- resolve_grading_guide(target_academic_year_id uuid, target_class_id uuid)
CREATE OR REPLACE FUNCTION public.resolve_grading_guide(target_academic_year_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_year_scope uuid;
  v_class_scope uuid;
  v_subject_scope uuid;
  v_year_name text;
  v_class_name text;
  v_subject_name text;
  v_rows jsonb;
  v_exceptions jsonb;
  v_scope_label text;
begin
  if target_academic_year_id is null or target_class_id is null then
    raise exception 'Academic year and class are required to resolve the grading guide';
  end if;
  select q.academic_year_id,q.class_id
  into v_year_scope,v_class_scope
  from (
    select g.academic_year_id,g.class_id,max(g.updated_at) latest_update
    from public.grading_scales g
    where g.deleted_at is null
      and g.subject_id is null
      and (g.academic_year_id is null or g.academic_year_id=target_academic_year_id)
      and (g.class_id is null or g.class_id=target_class_id)
    group by g.academic_year_id,g.class_id
  ) q
  order by
    ((q.academic_year_id is not null)::integer+(q.class_id is not null)::integer) desc,
    (q.class_id is not null)::integer desc,
    (q.academic_year_id is not null)::integer desc,
    q.latest_update desc
  limit 1;
  if not found then
    select q.academic_year_id,q.class_id,q.subject_id
    into v_year_scope,v_class_scope,v_subject_scope
    from (
      select g.academic_year_id,g.class_id,g.subject_id,max(g.updated_at) latest_update
      from public.grading_scales g
      join public.class_subjects cs on cs.class_id=target_class_id and cs.subject_id=g.subject_id and cs.active
      where g.deleted_at is null
        and g.subject_id is not null
        and (g.academic_year_id is null or g.academic_year_id=target_academic_year_id)
        and (g.class_id is null or g.class_id=target_class_id)
      group by g.academic_year_id,g.class_id,g.subject_id
    ) q
    order by
      ((q.academic_year_id is not null)::integer+(q.class_id is not null)::integer) desc,
      (q.class_id is not null)::integer desc,
      (q.academic_year_id is not null)::integer desc,
      q.latest_update desc
    limit 1;
    if not found then
      raise exception 'No grading scale is configured for the selected academic year and class';
    end if;
  end if;
  select ay.name::text into v_year_name from public.academic_years ay where ay.id=target_academic_year_id;
  select c.name::text into v_class_name from public.classes c where c.id=target_class_id;
  select sb.name::text into v_subject_name from public.subjects sb where sb.id=v_subject_scope;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',g.id,
    'grade',g.grade,
    'min_mark',g.min_mark,
    'max_mark',g.max_mark,
    'remark',g.remark,
    'interpretation',coalesce(nullif(btrim(g.interpretation),''),public.default_grading_interpretation(g.grade,g.remark)),
    'grade_point',g.grade_point,
    'display_order',g.display_order
  ) order by g.display_order,g.min_mark desc,g.max_mark desc),'[]'::jsonb)
  into v_rows
  from public.grading_scales g
  where g.deleted_at is null
    and g.subject_id is not distinct from v_subject_scope
    and g.academic_year_id is not distinct from v_year_scope
    and g.class_id is not distinct from v_class_scope;
  if jsonb_array_length(v_rows)=0 then
    raise exception 'The selected grading guide contains no active ranges';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_id',q.subject_id,
    'subject_name',q.subject_name
  ) order by q.subject_name),'[]'::jsonb)
  into v_exceptions
  from (
    select distinct s.id subject_id,s.name::text subject_name
    from public.class_subjects cs
    join public.subjects s on s.id=cs.subject_id
    where cs.class_id=target_class_id
      and cs.active
      and s.active
      and s.deleted_at is null
      and exists(
        select 1 from public.grading_scales gx
        where gx.deleted_at is null
          and gx.subject_id=s.id
          and (gx.academic_year_id is null or gx.academic_year_id=target_academic_year_id)
          and (gx.class_id is null or gx.class_id=target_class_id)
      )
  ) q;
  v_scope_label:=concat_ws(' • ',
    case when v_class_scope is not null then coalesce(v_class_name,'Selected class') else 'All classes' end,
    case when v_year_scope is not null then coalesce(v_year_name,'Selected academic year') else 'All academic years' end,
    case when v_subject_scope is not null then concat('Representative subject: ',coalesce(v_subject_name,'Configured subject')) else null end
  );
  return jsonb_build_object(
    'version',1,
    'generated_at',now(),
    'scope',jsonb_build_object(
      'academic_year_id',v_year_scope,
      'class_id',v_class_scope,
      'academic_year_name',case when v_year_scope is not null then v_year_name else null end,
      'class_name',case when v_class_scope is not null then v_class_name else null end,
      'label',v_scope_label
    ),
    'rows',v_rows,
    'subject_exceptions',v_exceptions
  );
end $function$;
revoke all on function public.resolve_grading_guide(target_academic_year_id uuid, target_class_id uuid) from public;
grant execute on function public.resolve_grading_guide(target_academic_year_id uuid, target_class_id uuid) to edusentia_worker_runtime;

-- resolve_security_event(target_event_id bigint, target_status text, resolution_text text)
CREATE OR REPLACE FUNCTION public.resolve_security_event(target_event_id bigint, target_status text, resolution_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.security_events; prior public.security_events;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if target_status not in ('acknowledged','resolved','false_positive') then raise exception 'Invalid resolution status'; end if;
  select * into prior from public.security_events where id=target_event_id for update;
  if prior.id is null then raise exception 'Security event not found'; end if;
  update public.security_events set status=target_status,acknowledged_by=auth.uid(),acknowledged_at=now(),resolution_note=left(coalesce(resolution_text,''),1000) where id=target_event_id returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'security_events',null,'SECURITY_EVENT_STATUS_CHANGED',
    jsonb_build_object('security_event_id',prior.id,'status',prior.status),
    jsonb_build_object('security_event_id',row_data.id,'event_type',row_data.event_type,'severity',row_data.severity,'status',row_data.status),
    'A security-event workflow status was changed. Event details remain in the security-event record.');
  return to_jsonb(row_data);
end $function$;
revoke all on function public.resolve_security_event(target_event_id bigint, target_status text, resolution_text text) from public;
grant execute on function public.resolve_security_event(target_event_id bigint, target_status text, resolution_text text) to edusentia_worker_runtime;

-- restore_student(target_student_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.restore_student(target_student_id uuid, reason_text text DEFAULT 'Student restored'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare latest_enrollment uuid;
begin
  if not public.is_records_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  perform 1 from public.students where id=target_student_id and deleted_at is not null for update;
  if not found then raise exception 'Archived student record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Student restored'),true);
  update public.students set status='active',deleted_at=null,updated_at=now() where id=target_student_id;
  select e.id into latest_enrollment from public.enrollments e join public.academic_years y on y.id=e.academic_year_id
  where e.student_id=target_student_id and e.deleted_at is null
  order by y.is_active desc,y.start_date desc nulls last,e.created_at desc limit 1;
  if latest_enrollment is not null then
    update public.enrollments set active=(id=latest_enrollment),updated_at=now()
    where student_id=target_student_id and deleted_at is null;
  end if;
  return true;
end $function$;
revoke all on function public.restore_student(target_student_id uuid, reason_text text) from public;
grant execute on function public.restore_student(target_student_id uuid, reason_text text) to edusentia_worker_runtime;

-- review_certificate_batch(target_batch_id uuid, decision text, review_note_text text)
CREATE OR REPLACE FUNCTION public.review_certificate_batch(target_batch_id uuid, decision text, review_note_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificate_batches; new_status text;
begin
  if not public.can_review_certificates() then raise exception 'Only the Principal can review certificates' using errcode='42501'; end if;
  if lower(decision) not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  new_status:=lower(decision);
  update public.certificate_batches set status=new_status,approved_by=case when new_status='approved' then auth.uid() else null end,approved_at=case when new_status='approved' then now() else null end,review_note=btrim(coalesce(review_note_text,'')),updated_at=now() where id=target_batch_id and status='submitted' returning * into updated;
  if updated.id is null then raise exception 'Only a submitted batch can be reviewed'; end if;
  update public.certificates set status=case when new_status='approved' then 'approved' else 'rejected' end,approved_by=case when new_status='approved' then auth.uid() else null end,approved_at=case when new_status='approved' then now() else null end,updated_at=now() where batch_id=target_batch_id and status='draft';
  perform public.record_certificate_event(target_batch_id,null,'principal_'||new_status,review_note_text);
  perform public.create_notification(updated.prepared_by,'Certificate batch '||new_status,updated.title||' was '||new_status||' by the Principal.','certificate_review','certificate_batch',target_batch_id,false);
  return jsonb_build_object('batch_id',updated.id,'status',updated.status);
end $function$;
revoke all on function public.review_certificate_batch(target_batch_id uuid, decision text, review_note_text text) from public;
grant execute on function public.review_certificate_batch(target_batch_id uuid, decision text, review_note_text text) to edusentia_worker_runtime;

-- review_report_correction(target_request_id uuid, decision text, review_note_text text)
CREATE OR REPLACE FUNCTION public.review_report_correction(target_request_id uuid, decision text, review_note_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare req public.report_correction_requests; current_status public.report_status; new_version integer; revisionid uuid; requester uuid;
begin
  if public.current_app_role()<>'principal' then raise exception 'Only the Principal can approve or reject report corrections' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if lower(decision) not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  select * into req from public.report_correction_requests where id=target_request_id for update;
  if req.id is null or req.status<>'pending' then raise exception 'Pending correction request not found'; end if;
  if lower(decision)='rejected' then
    update public.report_correction_requests set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=left(coalesce(review_note_text,''),1000),updated_at=now() where id=req.id returning * into req;
    insert into public.report_correction_events(request_id,event_type,event_note) values(req.id,'rejected',req.review_note);
  else
    select status into current_status from public.student_reports where id=req.report_id and deleted_at is null for update;
    if current_status not in ('approved','published') then raise exception 'The report is no longer eligible for correction'; end if;
    perform set_config('app.report_write','on',true);
    perform set_config('app.change_reason','Approved report correction: '||req.reason,true);
    update public.report_publications set revoked_at=now(),revoked_by=auth.uid() where report_id=req.report_id and revoked_at is null;
    update public.student_reports set status='returned',version=version+1,updated_at=now() where id=req.report_id returning version into new_version;
    insert into public.report_workflow_events(report_id,from_status,to_status,comment,actor_id)
    values(req.report_id,current_status,'returned','Correction approved: '||req.reason,auth.uid());
    insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
    values(req.report_id,new_version,public.build_report_snapshot(req.report_id),'Correction approved: '||req.reason,auth.uid())
    on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now()
    returning id into revisionid;
    update public.report_correction_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_note=left(coalesce(review_note_text,''),1000),correction_revision_id=revisionid,updated_at=now() where id=req.id returning * into req;
    insert into public.report_correction_events(request_id,event_type,event_note,event_data)
    values(req.id,'approved',req.review_note,jsonb_build_object('returned_report_version',new_version,'revision_id',revisionid));
    perform public.create_workflow_notifications(req.report_id,'returned');
  end if;
  requester:=req.requested_by;
  if requester is not null and requester<>auth.uid() then
    perform public.create_notification(requester,'Report correction '||req.status,coalesce(nullif(req.review_note,''),req.reason),'report_correction','report',req.report_id,true);
  end if;
  return to_jsonb(req);
end $function$;
revoke all on function public.review_report_correction(target_request_id uuid, decision text, review_note_text text) from public;
grant execute on function public.review_report_correction(target_request_id uuid, decision text, review_note_text text) to edusentia_worker_runtime;

-- revoke_certificate(target_certificate_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.revoke_certificate(target_certificate_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificates;
begin
  if not public.license_write_allowed() or not public.has_role(array['system_admin','principal']) then raise exception 'Only the System Administrator or Principal can revoke a certificate' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<5 then raise exception 'A revocation reason of at least five characters is required'; end if;
  update public.certificates set status='revoked',revocation_reason=btrim(reason_text),revoked_by=auth.uid(),revoked_at=now(),updated_at=now() where id=target_certificate_id and status='issued' returning * into updated;
  if updated.id is null then raise exception 'Only an issued certificate can be revoked'; end if;
  perform public.record_certificate_event(updated.batch_id,updated.id,'revoked',reason_text);
  return jsonb_build_object('certificate_id',updated.id,'status',updated.status);
end $function$;
revoke all on function public.revoke_certificate(target_certificate_id uuid, reason_text text) from public;
grant execute on function public.revoke_certificate(target_certificate_id uuid, reason_text text) to edusentia_worker_runtime;

-- revoke_emergency_academic_delegation(target_delegation_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.revoke_emergency_academic_delegation(target_delegation_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare currentrow public.emergency_academic_delegations%rowtype;reason_value text:=btrim(coalesce(reason_text,''));
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can revoke an emergency delegation' using errcode='42501'; end if;
  if not public.license_write_allowed() then raise exception 'The current licence does not permit this change' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if length(reason_value)<5 then raise exception 'A revocation reason of at least 5 characters is required' using errcode='22023'; end if;
  select * into currentrow from public.emergency_academic_delegations where id=target_delegation_id and status='active' for update;
  if currentrow.id is null then raise exception 'Active delegation not found' using errcode='P0002'; end if;
  update public.emergency_academic_delegations
  set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revocation_reason=reason_value
  where id=target_delegation_id returning * into currentrow;
  insert into public.emergency_academic_delegation_events(delegation_id,event_type,actor_id,event_reason,event_data)
  values(currentrow.id,'revoked',auth.uid(),reason_value,to_jsonb(currentrow));
  perform public.create_notification(currentrow.delegate_user_id,'Temporary academic access revoked',
    'Your emergency academic delegation has been revoked. Reason: '||reason_value,
    'emergency_academic_delegation','emergency_academic_delegation',currentrow.id,true);
  return public.get_emergency_delegation_console();
end $function$;
revoke all on function public.revoke_emergency_academic_delegation(target_delegation_id uuid, reason_text text) from public;
grant execute on function public.revoke_emergency_academic_delegation(target_delegation_id uuid, reason_text text) to edusentia_worker_runtime;

-- revoke_staff_id_card(target_card_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.revoke_staff_id_card(target_card_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c public.staff_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,''));sid uuid;
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can revoke staff ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A revocation reason of at least five characters is required';end if;update public.staff_id_cards set status='revoked',revoked_by=auth.uid(),revoked_at=now(),revocation_reason=reason,updated_at=now() where id=target_card_id and status='active' returning * into c;if c.id is null then raise exception 'Only an active staff ID card can be revoked';end if;sid:=coalesce(c.teacher_id,c.headteacher_id);perform public.record_staff_id_card_event(c.id,c.staff_type,sid,'revoked',jsonb_build_object('reason',reason));return jsonb_build_object('card_id',c.id,'status','revoked','card_number',c.card_number);end$function$;
revoke all on function public.revoke_staff_id_card(target_card_id uuid, reason_text text) from public;
grant execute on function public.revoke_staff_id_card(target_card_id uuid, reason_text text) to edusentia_worker_runtime;

-- revoke_student_id_card(target_card_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.revoke_student_id_card(target_card_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare updated public.student_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,'')); begin if not public.is_system_admin() then raise exception 'Only the System Administrator can revoke student ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A revocation reason of at least five characters is required';end if;update public.student_id_cards set status='revoked',revoked_by=auth.uid(),revoked_at=now(),revocation_reason=reason,updated_at=now() where id=target_card_id and status='active' returning * into updated;if updated.id is null then raise exception 'Only an active ID card can be revoked';end if;perform public.record_id_card_event(updated.id,updated.student_id,'revoked',jsonb_build_object('reason',reason));return jsonb_build_object('card_id',updated.id,'status','revoked','card_number',updated.card_number);end$function$;
revoke all on function public.revoke_student_id_card(target_card_id uuid, reason_text text) from public;
grant execute on function public.revoke_student_id_card(target_card_id uuid, reason_text text) to edusentia_worker_runtime;

-- revoke_student_transcript(target_issuance_id uuid, reason_text text)
CREATE OR REPLACE FUNCTION public.revoke_student_transcript(target_issuance_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare issued public.transcript_issuances;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then raise exception 'The current licence does not permit this change' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<5 then raise exception 'Revocation reason is required'; end if;

  update public.transcript_issuances
  set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revocation_reason=left(btrim(reason_text),500)
  where id=target_issuance_id and status='valid'
  returning * into issued;
  if issued.id is null then raise exception 'Active transcript issuance not found'; end if;

  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(
    auth.uid(),'transcript_issuances',issued.id,'REVOKE',
    jsonb_build_object('transcript_number',issued.transcript_number,'status','valid'),
    jsonb_build_object('transcript_number',issued.transcript_number,'status','revoked','revoked_at',issued.revoked_at),
    issued.revocation_reason
  );
  return to_jsonb(issued)-'snapshot';
end
$function$;
revoke all on function public.revoke_student_transcript(target_issuance_id uuid, reason_text text) from public;
grant execute on function public.revoke_student_transcript(target_issuance_id uuid, reason_text text) to edusentia_worker_runtime;

-- run_academic_alerts(target_term_id uuid)
CREATE OR REPLACE FUNCTION public.run_academic_alerts(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=target_term_id; control jsonb; queued integer:=0; recipient uuid; rowitem record; title_text text; body_text text;
begin
  if auth.uid() is not null and public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if tid is null then select id into tid from public.terms where is_active and deleted_at is null limit 1; end if;
  control:=public.term_control_snapshot(tid);
  for rowitem in
    select c.id class_id,c.name class_name,c.class_teacher_id,
      count(e.id) enrolled,count(r.id) filter(where r.id is not null) reports_created,
      count(r.id) filter(where r.status in ('draft','returned')) draft_count,
      count(r.id) filter(where r.status in ('submitted','class_reviewed')) pending_approval,
      count(r.id) filter(where r.status='approved') approved_count
    from public.classes c
    left join public.enrollments e on e.class_id=c.id and e.active and e.deleted_at is null and e.academic_year_id=(select academic_year_id from public.terms where id=tid)
    left join public.student_reports r on r.enrollment_id=e.id and r.term_id=tid and r.deleted_at is null
    where c.active and c.deleted_at is null group by c.id,c.name,c.class_teacher_id
  loop
    if rowitem.class_teacher_id is not null and (rowitem.reports_created<rowitem.enrolled or rowitem.draft_count>0) then
      title_text:='Incomplete reports: '||rowitem.class_name;
      body_text:=format('%s of %s reports created; %s remain in draft or correction.',rowitem.reports_created,rowitem.enrolled,rowitem.draft_count);
      if not exists(select 1 from public.notifications where recipient_id=rowitem.class_teacher_id and title=title_text and created_at>=now()-interval '20 hours') then
        perform public.create_notification(rowitem.class_teacher_id,title_text,body_text,'academic_deadline','term',tid,true); queued:=queued+1;
      end if;
    end if;
    if rowitem.pending_approval>0 then
      for recipient in select p.id from public.profiles p where p.active and public.current_app_role_for(p.role)::text='principal' loop
        title_text:='Reports awaiting approval: '||rowitem.class_name;
        body_text:=rowitem.pending_approval||' report(s) are awaiting Principal approval.';
        if not exists(select 1 from public.notifications where recipient_id=recipient and title=title_text and created_at>=now()-interval '20 hours') then
          perform public.create_notification(recipient,title_text,body_text,'academic_deadline','term',tid,true); queued:=queued+1;
        end if;
      end loop;
    end if;
    if rowitem.approved_count>0 and rowitem.class_teacher_id is not null then
      title_text:='Approved reports awaiting publication: '||rowitem.class_name;
      body_text:=rowitem.approved_count||' approved report(s) are ready for publication.';
      if not exists(select 1 from public.notifications where recipient_id=rowitem.class_teacher_id and title=title_text and created_at>=now()-interval '20 hours') then
        perform public.create_notification(rowitem.class_teacher_id,title_text,body_text,'academic_deadline','term',tid,true); queued:=queued+1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('queued',queued,'term_id',tid,'control',control);
end $function$;
revoke all on function public.run_academic_alerts(target_term_id uuid) from public;
grant execute on function public.run_academic_alerts(target_term_id uuid) to edusentia_worker_runtime;

-- save_academic_period_control(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_academic_period_control(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=public.safe_uuid(payload->>'term_id'); result_row public.academic_period_controls;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Only the System Administrator or Principal can manage academic-period controls' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then raise exception 'The platform is read-only' using errcode='42501'; end if;
  if tid is null or not exists(select 1 from public.terms where id=tid and deleted_at is null) then raise exception 'Valid term is required'; end if;
  insert into public.academic_period_controls(
    term_id,score_entry_deadline,attendance_deadline,report_submission_deadline,
    principal_approval_deadline,publication_deadline,scores_locked,attendance_locked,reports_locked,
    lock_reason,locked_by,locked_at,updated_by
  ) values(
    tid,public.safe_timestamptz(payload->>'score_entry_deadline'),public.safe_timestamptz(payload->>'attendance_deadline'),
    public.safe_timestamptz(payload->>'report_submission_deadline'),public.safe_timestamptz(payload->>'principal_approval_deadline'),
    public.safe_timestamptz(payload->>'publication_deadline'),coalesce((payload->>'scores_locked')::boolean,false),
    coalesce((payload->>'attendance_locked')::boolean,false),coalesce((payload->>'reports_locked')::boolean,false),
    left(coalesce(payload->>'lock_reason',''),500),
    case when coalesce((payload->>'scores_locked')::boolean,false) or coalesce((payload->>'attendance_locked')::boolean,false) or coalesce((payload->>'reports_locked')::boolean,false) then auth.uid() else null end,
    case when coalesce((payload->>'scores_locked')::boolean,false) or coalesce((payload->>'attendance_locked')::boolean,false) or coalesce((payload->>'reports_locked')::boolean,false) then now() else null end,
    auth.uid()
  )
  on conflict(term_id) do update set
    score_entry_deadline=excluded.score_entry_deadline,attendance_deadline=excluded.attendance_deadline,
    report_submission_deadline=excluded.report_submission_deadline,principal_approval_deadline=excluded.principal_approval_deadline,
    publication_deadline=excluded.publication_deadline,scores_locked=excluded.scores_locked,
    attendance_locked=excluded.attendance_locked,reports_locked=excluded.reports_locked,
    lock_reason=excluded.lock_reason,locked_by=excluded.locked_by,locked_at=excluded.locked_at,
    updated_by=auth.uid(),updated_at=now()
  returning * into result_row;
  insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason)
  values(auth.uid(),'academic_period_controls',tid,'UPSERT',to_jsonb(result_row),coalesce(nullif(result_row.lock_reason,''),'Academic period control updated'));
  return public.term_control_snapshot(tid);
end $function$;
revoke all on function public.save_academic_period_control(payload jsonb) from public;
grant execute on function public.save_academic_period_control(payload jsonb) to edusentia_worker_runtime;

-- save_backup_policy(target_retention_days integer, target_minimum_copies integer)
CREATE OR REPLACE FUNCTION public.save_backup_policy(target_retention_days integer, target_minimum_copies integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare settings_id uuid; old_retention integer; old_minimum integer;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can change backup policy' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if target_retention_days is null or target_retention_days<7 or target_retention_days>365 then raise exception 'Backup retention must be between 7 and 365 days'; end if;
  if target_minimum_copies is null or target_minimum_copies<2 or target_minimum_copies>90 then raise exception 'Minimum retained backups must be between 2 and 90'; end if;
  select id,backup_retention_days,backup_minimum_copies into settings_id,old_retention,old_minimum from public.school_settings order by created_at,id limit 1 for update;
  if settings_id is null then
    insert into public.school_settings(backup_retention_days,backup_minimum_copies,updated_at) values(target_retention_days,target_minimum_copies,now()) returning id into settings_id;
  else
    update public.school_settings set backup_retention_days=target_retention_days,backup_minimum_copies=target_minimum_copies,updated_at=now() where id=settings_id;
  end if;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'school_settings',settings_id,'BACKUP_POLICY_CHANGED',
    jsonb_build_object('retention_days',old_retention,'minimum_copies',old_minimum),
    jsonb_build_object('retention_days',target_retention_days,'minimum_copies',target_minimum_copies),
    'System Administrator changed backup retention policy.');
  return jsonb_build_object('backup_retention_days',target_retention_days,'backup_minimum_copies',target_minimum_copies,'settings_id',settings_id);
end $function$;
revoke all on function public.save_backup_policy(target_retention_days integer, target_minimum_copies integer) from public;
grant execute on function public.save_backup_policy(target_retention_days integer, target_minimum_copies integer) to edusentia_worker_runtime;

-- save_certificate_settings(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_certificate_settings(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare completion_class uuid:=public.safe_uuid(payload->>'completion_class_id'); result public.school_settings;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can manage certificate settings' using errcode='42501'; end if;
  if completion_class is not null and not exists(select 1 from public.classes where id=completion_class and active and deleted_at is null) then raise exception 'Completion class is invalid'; end if;
  update public.school_settings set certificate_completion_class_id=completion_class,certificate_footer_text=btrim(coalesce(payload->>'footer_text',certificate_footer_text)),updated_at=now() where id=(select id from public.school_settings order by created_at limit 1) returning * into result;
  if result.id is null then raise exception 'School settings not found'; end if;
  return jsonb_build_object('completion_class_id',result.certificate_completion_class_id,'footer_text',result.certificate_footer_text);
end $function$;
revoke all on function public.save_certificate_settings(payload jsonb) from public;
grant execute on function public.save_certificate_settings(payload jsonb) to edusentia_worker_runtime;

-- save_certificate_template(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_certificate_template(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  tid uuid:=public.safe_uuid(payload->>'id');
  ctype text:=btrim(coalesce(payload->>'certificate_type',''));
  result public.certificate_templates;
  has_file_payload boolean:=payload ? 'storage_path';
  new_storage_path text:=btrim(coalesce(payload->>'storage_path',''));
  new_original_name text:=btrim(coalesce(payload->>'original_name',''));
  new_mime_type text:=btrim(coalesce(payload->>'mime_type',''));
  new_file_size bigint:=coalesce(nullif(payload->>'file_size','')::bigint,0);
  new_checksum text:=lower(btrim(coalesce(payload->>'checksum','')));
begin
  if not public.can_manage_certificates() then
    raise exception 'Only the System Administrator can manage certificate templates' using errcode='42501';
  end if;
  if ctype not in ('student_promotion','jhs_completion','teacher_recognition') then
    raise exception 'Certificate type is invalid';
  end if;
  if btrim(coalesce(payload->>'title',''))='' or btrim(coalesce(payload->>'statement_template',''))='' then
    raise exception 'Certificate title and statement are required';
  end if;
  if length(btrim(payload->>'title'))>120 or length(btrim(payload->>'statement_template'))>800 then
    raise exception 'Certificate title or statement is too long';
  end if;
  if has_file_payload then
    if new_storage_path='' or new_storage_path not like ctype||'/%' then raise exception 'Certificate template storage path is invalid'; end if;
    if new_original_name='' or length(new_original_name)>255 then raise exception 'Certificate template filename is invalid'; end if;
    if new_mime_type not in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception 'Unsupported certificate template file type'; end if;
    if new_file_size<=0 or new_file_size>20971520 then raise exception 'Certificate template must be between 1 byte and 20 MB'; end if;
    if length(new_checksum)>128 then raise exception 'Certificate template checksum is invalid'; end if;
  end if;
  update public.certificate_templates
  set active=false,updated_at=now()
  where certificate_type=ctype and active and (tid is null or id<>tid);
  if tid is null then
    insert into public.certificate_templates(
      certificate_type,name,title,subtitle,statement_template,footer_text,primary_colour,accent_colour,active,
      storage_path,original_name,mime_type,file_size,checksum,version,uploaded_by
    )
    values(
      ctype,coalesce(nullif(btrim(payload->>'name'),''),public.certificate_type_label(ctype)),
      btrim(payload->>'title'),btrim(coalesce(payload->>'subtitle','')),btrim(payload->>'statement_template'),
      btrim(coalesce(payload->>'footer_text','')),coalesce(nullif(payload->>'primary_colour',''),'#0a2f73'),
      coalesce(nullif(payload->>'accent_colour',''),'#f1b51c'),true,
      case when has_file_payload then new_storage_path else '' end,
      case when has_file_payload then new_original_name else '' end,
      case when has_file_payload then new_mime_type else '' end,
      case when has_file_payload then new_file_size else 0 end,
      case when has_file_payload then new_checksum else '' end,
      1,case when has_file_payload then auth.uid() else null end
    )
    returning * into result;
  else
    update public.certificate_templates
    set name=coalesce(nullif(btrim(payload->>'name'),''),name),
        title=btrim(payload->>'title'),
        subtitle=btrim(coalesce(payload->>'subtitle','')),
        statement_template=btrim(payload->>'statement_template'),
        footer_text=btrim(coalesce(payload->>'footer_text','')),
        primary_colour=coalesce(nullif(payload->>'primary_colour',''),primary_colour),
        accent_colour=coalesce(nullif(payload->>'accent_colour',''),accent_colour),
        active=true,
        storage_path=case when has_file_payload then new_storage_path else storage_path end,
        original_name=case when has_file_payload then new_original_name else original_name end,
        mime_type=case when has_file_payload then new_mime_type else mime_type end,
        file_size=case when has_file_payload then new_file_size else file_size end,
        checksum=case when has_file_payload then new_checksum else checksum end,
        version=case when has_file_payload then version+1 else version end,
        uploaded_by=case when has_file_payload then auth.uid() else uploaded_by end,
        updated_at=now()
    where id=tid
    returning * into result;
  end if;
  if result.id is null then raise exception 'Certificate template not found'; end if;
  if has_file_payload then
    perform public.record_certificate_event(
      null,null,'certificate_template_design_uploaded','',
      jsonb_build_object(
        'certificate_type',ctype,'storage_path',result.storage_path,'original_name',result.original_name,
        'mime_type',result.mime_type,'file_size',result.file_size,'checksum',result.checksum,'version',result.version
      )
    );
  end if;
  return to_jsonb(result);
end $function$;
revoke all on function public.save_certificate_template(payload jsonb) from public;
grant execute on function public.save_certificate_template(payload jsonb) to edusentia_worker_runtime;

-- save_class_attendance(target_term_id uuid, target_class_id uuid, target_date date, entries jsonb, notes_text text)
CREATE OR REPLACE FUNCTION public.save_class_attendance(target_term_id uuid, target_class_id uuid, target_date date, entries jsonb, notes_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare target_year_id uuid;term_start date;term_end date;target_register_id uuid;expected_count integer;provided_count integer;distinct_count integer;invalid_count integer;
begin
  if not public.is_assigned_class_teacher(target_class_id) then raise exception 'You can mark attendance only for your assigned class' using errcode='42501'; end if;
  if not public.term_phase_writable(target_term_id,'attendance',null) then raise exception 'Attendance is locked for the selected term' using errcode='42501'; end if;
  if target_term_id is null or target_date is null then raise exception 'Term and attendance date are required'; end if;
  if entries is null or jsonb_typeof(entries)<>'array' then raise exception 'Attendance entries must be supplied as a list'; end if;
  select t.academic_year_id,t.start_date,t.end_date into target_year_id,term_start,term_end from public.terms t where t.id=target_term_id and t.deleted_at is null;
  if target_year_id is null then raise exception 'Term is unavailable'; end if;
  if term_start is not null and target_date<term_start then raise exception 'Attendance date is before the selected term'; end if;
  if term_end is not null and target_date>term_end then raise exception 'Attendance date is after the selected term'; end if;
  if target_date>current_date then raise exception 'Attendance cannot be marked for a future date'; end if;
  select count(*) into expected_count from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null and s.status='active' where e.academic_year_id=target_year_id and e.class_id=target_class_id and e.deleted_at is null and e.active;
  if expected_count=0 then raise exception 'No students are enrolled in this class for the selected term'; end if;
  select count(*),count(distinct public.safe_uuid(item->>'enrollment_id')) into provided_count,distinct_count from jsonb_array_elements(entries) item;
  if provided_count<>expected_count or distinct_count<>provided_count then raise exception 'Attendance must include each student exactly once'; end if;
  select count(*) into invalid_count from jsonb_array_elements(entries) item
  left join public.enrollments e on e.id=public.safe_uuid(item->>'enrollment_id') left join public.students s on s.id=e.student_id
  where public.safe_uuid(item->>'enrollment_id') is null or coalesce(item->>'attendance_status','') not in ('present','absent','late','excused')
    or e.id is null or e.deleted_at is not null or not e.active or e.academic_year_id<>target_year_id or e.class_id<>target_class_id
    or s.id is null or s.deleted_at is not null or s.status<>'active';
  if invalid_count>0 then raise exception 'One or more attendance entries are invalid or outside the assigned class'; end if;
  perform set_config('app.change_reason','Class attendance marked',true);
  insert into public.class_attendance_registers(term_id,class_id,attendance_date,marked_by,notes,updated_at)
  values(target_term_id,target_class_id,target_date,auth.uid(),coalesce(notes_text,''),now())
  on conflict(term_id,class_id,attendance_date) do update set marked_by=auth.uid(),notes=excluded.notes,updated_at=now()
  returning id into target_register_id;
  insert into public.student_attendance_entries(register_id,enrollment_id,attendance_status,updated_at)
  select target_register_id,public.safe_uuid(item->>'enrollment_id'),item->>'attendance_status',now() from jsonb_array_elements(entries) item
  on conflict(register_id,enrollment_id) do update set attendance_status=excluded.attendance_status,updated_at=now();
  delete from public.student_attendance_entries a where a.register_id=target_register_id and not exists(select 1 from jsonb_array_elements(entries) item where public.safe_uuid(item->>'enrollment_id')=a.enrollment_id);
  perform public.sync_attendance_reports(target_term_id,target_class_id);
  return public.get_class_attendance_register(target_term_id,target_class_id,target_date);
end $function$;
revoke all on function public.save_class_attendance(target_term_id uuid, target_class_id uuid, target_date date, entries jsonb, notes_text text) from public;
grant execute on function public.save_class_attendance(target_term_id uuid, target_class_id uuid, target_date date, entries jsonb, notes_text text) to edusentia_worker_runtime;

-- save_id_card_settings(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_id_card_settings(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.id_card_settings%rowtype;template text:=lower(btrim(coalesce(payload->>'template_code','modern')));months integer:=coalesce(nullif(payload->>'validity_months','')::integer,12);staff_months integer:=coalesce(nullif(payload->>'staff_validity_months','')::integer,24);message text:=btrim(coalesce(payload->>'back_message',''));
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can configure ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if template not in ('classic','modern','minimal') then raise exception 'Unsupported ID card template';end if;if months not between 1 and 60 or staff_months not between 1 and 60 then raise exception 'ID card validity must be between 1 and 60 months';end if;if length(message)>500 then raise exception 'ID card back message is too long';end if;
 update public.id_card_settings set template_code=template,card_title=left(coalesce(nullif(btrim(payload->>'card_title'),''),'STUDENT ID CARD'),80),staff_card_title=left(coalesce(nullif(btrim(payload->>'staff_card_title'),''),'STAFF ID CARD'),80),validity_months=months,staff_validity_months=staff_months,show_date_of_birth=coalesce((payload->>'show_date_of_birth')::boolean,false),show_gender=coalesce((payload->>'show_gender')::boolean,false),show_guardian_phone=coalesce((payload->>'show_guardian_phone')::boolean,false),show_school_address=coalesce((payload->>'show_school_address')::boolean,true),show_school_phone=coalesce((payload->>'show_school_phone')::boolean,true),show_school_email=coalesce((payload->>'show_school_email')::boolean,true),show_principal_signature=coalesce((payload->>'show_principal_signature')::boolean,true),show_principal_name=coalesce((payload->>'show_principal_name')::boolean,true),show_principal_title=coalesce((payload->>'show_principal_title')::boolean,true),back_message=coalesce(nullif(message,''),'This card remains the property of the school. If found, please return it to the school administration.'),updated_by=auth.uid(),updated_at=now() where id=(select id from public.id_card_settings limit 1) returning * into updated;
 if updated.id is null then insert into public.id_card_settings(template_code,card_title,staff_card_title,validity_months,staff_validity_months,show_date_of_birth,show_gender,show_guardian_phone,show_school_address,show_school_phone,show_school_email,show_principal_signature,show_principal_name,show_principal_title,back_message,updated_by) values(template,left(coalesce(nullif(btrim(payload->>'card_title'),''),'STUDENT ID CARD'),80),left(coalesce(nullif(btrim(payload->>'staff_card_title'),''),'STAFF ID CARD'),80),months,staff_months,coalesce((payload->>'show_date_of_birth')::boolean,false),coalesce((payload->>'show_gender')::boolean,false),coalesce((payload->>'show_guardian_phone')::boolean,false),coalesce((payload->>'show_school_address')::boolean,true),coalesce((payload->>'show_school_phone')::boolean,true),coalesce((payload->>'show_school_email')::boolean,true),coalesce((payload->>'show_principal_signature')::boolean,true),coalesce((payload->>'show_principal_name')::boolean,true),coalesce((payload->>'show_principal_title')::boolean,true),coalesce(nullif(message,''),'This card remains the property of the school. If found, please return it to the school administration.'),auth.uid()) returning * into updated;end if;return to_jsonb(updated);
end$function$;
revoke all on function public.save_id_card_settings(payload jsonb) from public;
grant execute on function public.save_id_card_settings(payload jsonb) to edusentia_worker_runtime;

-- save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text)
CREATE OR REPLACE FUNCTION public.save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result public.report_card_templates;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  if target_range_key not in ('early_years','basic_1_6','basic_7_9') then raise exception 'Invalid report-card class range'; end if;
  if coalesce(btrim(target_storage_path),'')='' or target_storage_path not like target_range_key||'/%' then raise exception 'Invalid template storage path'; end if;
  if coalesce(btrim(target_original_name),'')='' or length(target_original_name)>255 then raise exception 'Invalid template file name'; end if;
  if target_mime_type not in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception 'Unsupported template file type'; end if;
  if coalesce(target_file_size,0)<=0 or target_file_size>20971520 then raise exception 'Template file must be between 1 byte and 20 MB'; end if;
  if coalesce(length(target_checksum),0)>128 then raise exception 'Invalid template checksum'; end if;
  insert into public.report_card_templates(
    range_key,storage_path,original_name,mime_type,file_size,checksum,version,active,uploaded_by
  ) values(
    target_range_key,btrim(target_storage_path),btrim(target_original_name),target_mime_type,target_file_size,coalesce(target_checksum,''),1,true,auth.uid()
  )
  on conflict(range_key) do update set
    storage_path=excluded.storage_path,
    original_name=excluded.original_name,
    mime_type=excluded.mime_type,
    file_size=excluded.file_size,
    checksum=excluded.checksum,
    version=public.report_card_templates.version+1,
    active=true,
    uploaded_by=auth.uid(),
    updated_at=now()
  returning * into result;
  return to_jsonb(result);
end $function$;
revoke all on function public.save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text) from public;
grant execute on function public.save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text) to edusentia_worker_runtime;

-- save_report_comments(target_report_id uuid, teacher_comment_text text, head_comment_text text, expected_version integer)
CREATE OR REPLACE FUNCTION public.save_report_comments(target_report_id uuid, teacher_comment_text text DEFAULT NULL::text, head_comment_text text DEFAULT NULL::text, expected_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_version integer;current_status public.report_status;can_teacher boolean;can_principal boolean;
begin
  select version,status into current_version,current_status from public.student_reports where id=target_report_id and deleted_at is null for update;
  if current_status is null then raise exception 'Report not found'; end if;
  if expected_version is not null and expected_version<>current_version then raise exception 'This report was changed by another user. Refresh before saving comments.' using errcode='40001'; end if;
  if current_status in ('published','withdrawn') then raise exception 'Published report comments are locked'; end if;
  can_teacher:=current_status in ('draft','returned') and public.can_manage_class_report_fields(public.report_class_id(target_report_id));
  can_principal:=current_status in ('submitted','class_reviewed','approved') and public.current_app_role()='principal';
  if teacher_comment_text is not null and not can_teacher then raise exception 'Only the assigned Class Teacher can save the class teacher comment' using errcode='42501'; end if;
  if head_comment_text is not null and not can_principal then raise exception 'Only the Principal can save the Principal comment' using errcode='42501'; end if;
  if teacher_comment_text is null and head_comment_text is null then raise exception 'No comment change supplied'; end if;
  if can_principal then perform public.require_sensitive_access(); end if;
  perform set_config('app.report_write','on',true);
  perform set_config('app.change_reason','Report comments updated',true);
  update public.student_reports set
    teacher_comment=case when teacher_comment_text is not null then teacher_comment_text else teacher_comment end,
    head_comment=case when head_comment_text is not null then head_comment_text else head_comment end,
    version=version+1,updated_at=now()
  where id=target_report_id;
  insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
  values(target_report_id,(select version from public.student_reports where id=target_report_id),public.build_report_snapshot(target_report_id),'Report comments updated',auth.uid())
  on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now();
  return public.get_report_editor(target_report_id,null,null);
end $function$;
revoke all on function public.save_report_comments(target_report_id uuid, teacher_comment_text text, head_comment_text text, expected_version integer) from public;
grant execute on function public.save_report_comments(target_report_id uuid, teacher_comment_text text, head_comment_text text, expected_version integer) to edusentia_worker_runtime;

-- save_retention_policy(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_retention_policy(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.data_retention_policies; prior public.data_retention_policies; category text:=left(btrim(coalesce(payload->>'data_category','')),160);
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can manage retention policies' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if length(category)<2 then raise exception 'Data category is required'; end if;
  select * into prior from public.data_retention_policies where data_category=category;
  insert into public.data_retention_policies(data_category,retention_years,legal_basis,disposition_action,notes,active,updated_by)
  values(category,nullif(payload->>'retention_years','')::integer,left(coalesce(payload->>'legal_basis',''),1000),coalesce(nullif(payload->>'disposition_action',''),'review'),left(coalesce(payload->>'notes',''),2000),coalesce((payload->>'active')::boolean,true),auth.uid())
  on conflict(data_category) do update set retention_years=excluded.retention_years,legal_basis=excluded.legal_basis,disposition_action=excluded.disposition_action,notes=excluded.notes,active=excluded.active,updated_by=auth.uid(),updated_at=now()
  returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'data_retention_policies',row_data.id,case when prior.id is null then 'RETENTION_POLICY_CREATED' else 'RETENTION_POLICY_UPDATED' end,
    case when prior.id is null then null else jsonb_build_object('retention_years',prior.retention_years,'disposition_action',prior.disposition_action,'active',prior.active) end,
    jsonb_build_object('data_category',row_data.data_category,'retention_years',row_data.retention_years,'disposition_action',row_data.disposition_action,'active',row_data.active),
    'System Administrator changed a data-retention policy.');
  return to_jsonb(row_data);
end $function$;
revoke all on function public.save_retention_policy(payload jsonb) from public;
grant execute on function public.save_retention_policy(payload jsonb) to edusentia_worker_runtime;

-- save_school_prospectus(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_school_prospectus(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare pid uuid:=public.safe_uuid(payload->>'id');yearid uuid:=public.safe_uuid(payload->>'academic_year_id');range_code text:=lower(btrim(coalesce(payload->>'class_range','')));title_value text:=btrim(coalesce(payload->>'title','School Prospectus'));currency_value text:=upper(btrim(coalesce(payload->>'currency_code','GHS')));effective date;notes_value text:=btrim(coalesce(payload->>'general_notes',''));expected timestamptz:=public.safe_timestamptz(payload->>'updated_at');current_row public.school_prospectuses%rowtype;result public.school_prospectuses%rowtype;
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can manage school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;
 if yearid is null or not exists(select 1 from public.academic_years where id=yearid and deleted_at is null) then raise exception 'Select a valid academic year';end if;if range_code not in ('early_years','basic_1_6','basic_7_9') then raise exception 'Select a valid prospectus class range';end if;if title_value='' or length(title_value)>180 then raise exception 'Prospectus title is required and must be 180 characters or fewer';end if;if currency_value!~'^[A-Z]{3}$' then raise exception 'Currency must use a three-letter code such as GHS';end if;if length(notes_value)>5000 then raise exception 'General notes are too long';end if;begin effective:=nullif(payload->>'effective_date','')::date;exception when others then raise exception 'Effective date is invalid';end;
 if pid is null then insert into public.school_prospectuses(academic_year_id,class_range,title,currency_code,effective_date,general_notes,created_by,updated_by) values(yearid,range_code,title_value,currency_value,effective,notes_value,auth.uid(),auth.uid()) returning * into result;insert into public.school_prospectus_sections(prospectus_id,section_type,title,display_order,created_by,updated_by) values(result.id,'main_fees','Main Fees',10,auth.uid(),auth.uid()),(result.id,'other_items','Other Items (One-off / Per Term)',20,auth.uid(),auth.uid()),(result.id,'parent_provided','To Be Provided by Parent',30,auth.uid(),auth.uid()),(result.id,'transportation','Transportation',40,auth.uid(),auth.uid()),(result.id,'policies','Important Policy Notes',50,auth.uid(),auth.uid());
 else select * into current_row from public.school_prospectuses where id=pid for update;if current_row.id is null then raise exception 'Prospectus not found';end if;if current_row.status='archived' then raise exception 'Archived prospectuses cannot be edited. Copy it to a new academic year instead.';end if;if expected is not null and current_row.updated_at is distinct from expected then raise exception 'This prospectus changed in another session. Reload and try again.' using errcode='40001';end if;update public.school_prospectuses set academic_year_id=yearid,class_range=range_code,title=title_value,currency_code=currency_value,effective_date=effective,general_notes=notes_value,status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid returning * into result;end if;
 return public.build_school_prospectus_snapshot(result.id);
end$function$;
revoke all on function public.save_school_prospectus(payload jsonb) from public;
grant execute on function public.save_school_prospectus(payload jsonb) to edusentia_worker_runtime;

-- save_school_prospectus_item(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_school_prospectus_item(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare iid uuid:=public.safe_uuid(payload->>'id');sid uuid:=public.safe_uuid(payload->>'section_id');kind text:=lower(btrim(coalesce(payload->>'charge_basis','per_term')));name_value text:=btrim(coalesce(payload->>'item_name',''));description_value text:=btrim(coalesce(payload->>'description',''));unit_value text:=btrim(coalesce(payload->>'unit',''));notes_value text:=btrim(coalesce(payload->>'notes',''));amount_value numeric;quantity_value numeric;units_value numeric;sort_value integer:=coalesce(nullif(payload->>'display_order','')::integer,100);include_value boolean:=coalesce((payload->>'include_in_total')::boolean,true);required_value boolean:=coalesce((payload->>'required')::boolean,true);pid uuid;section_kind text;status_value text;row public.school_prospectus_items%rowtype;
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can manage prospectus items' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;if sid is null then raise exception 'Prospectus section is required';end if;select s.prospectus_id,s.section_type,p.status into pid,section_kind,status_value from public.school_prospectus_sections s join public.school_prospectuses p on p.id=s.prospectus_id where s.id=sid for update of p;if pid is null then raise exception 'Prospectus section not found';end if;if status_value='archived' then raise exception 'Archived prospectuses cannot be edited';end if;if kind not in ('free','one_off','per_day','per_week','per_month','per_term','per_academic_year','per_occurrence','optional','parent_provides','informational') then raise exception 'Invalid charging basis';end if;if name_value='' or length(name_value)>220 then raise exception 'Item name is required and must be 220 characters or fewer';end if;if length(description_value)>2000 or length(notes_value)>2000 then raise exception 'Prospectus item description or notes are too long';end if;
 begin amount_value:=nullif(payload->>'amount','')::numeric;quantity_value:=nullif(payload->>'quantity','')::numeric;units_value:=nullif(payload->>'calculation_units','')::numeric;exception when others then raise exception 'Amount, quantity, or calculation units are invalid';end;if amount_value is not null and amount_value<0 then raise exception 'Amount cannot be negative';end if;if quantity_value is not null and quantity_value<=0 then raise exception 'Quantity must be greater than zero';end if;if units_value is not null and units_value<=0 then raise exception 'Calculation units must be greater than zero';end if;if section_kind in ('main_fees','other_items','transportation') and kind not in ('free','optional','informational') and amount_value is null then raise exception 'Enter an amount or mark the item Free/Optional';end if;if kind in ('free','parent_provides','informational') then include_value:=false;if kind='free' then amount_value:=null;end if;end if;if kind in ('per_day','per_week','per_month','per_occurrence') and units_value is null then include_value:=false;end if;
 if iid is null then insert into public.school_prospectus_items(section_id,item_name,description,amount,charge_basis,quantity,unit,calculation_units,include_in_total,required,notes,display_order,created_by,updated_by) values(sid,name_value,description_value,amount_value,kind,quantity_value,unit_value,units_value,include_value,required_value,notes_value,sort_value,auth.uid(),auth.uid()) returning * into row;else update public.school_prospectus_items set section_id=sid,item_name=name_value,description=description_value,amount=amount_value,charge_basis=kind,quantity=quantity_value,unit=unit_value,calculation_units=units_value,include_in_total=include_value,required=required_value,notes=notes_value,display_order=sort_value,updated_by=auth.uid(),updated_at=now() where id=iid returning * into row;if row.id is null then raise exception 'Prospectus item not found';end if;end if;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;return to_jsonb(row);
end$function$;
revoke all on function public.save_school_prospectus_item(payload jsonb) from public;
grant execute on function public.save_school_prospectus_item(payload jsonb) to edusentia_worker_runtime;

-- save_school_prospectus_section(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_school_prospectus_section(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid:=public.safe_uuid(payload->>'id');pid uuid:=public.safe_uuid(payload->>'prospectus_id');kind text:=lower(btrim(coalesce(payload->>'section_type','custom')));title_value text:=btrim(coalesce(payload->>'title',''));instructions_value text:=btrim(coalesce(payload->>'instructions',''));sort_value integer:=coalesce(nullif(payload->>'display_order','')::integer,100);p public.school_prospectuses%rowtype;row public.school_prospectus_sections%rowtype;
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can manage prospectus sections' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;if pid is null then raise exception 'Prospectus is required';end if;select * into p from public.school_prospectuses where id=pid for update;if p.id is null then raise exception 'Prospectus not found';end if;if p.status='archived' then raise exception 'Archived prospectuses cannot be edited';end if;if kind not in ('main_fees','other_items','parent_provided','transportation','policies','custom') then raise exception 'Invalid prospectus section type';end if;if title_value='' or length(title_value)>180 then raise exception 'Section title is required';end if;if length(instructions_value)>3000 then raise exception 'Section instructions are too long';end if;
 if sid is null then insert into public.school_prospectus_sections(prospectus_id,section_type,title,instructions,display_order,created_by,updated_by) values(pid,kind,title_value,instructions_value,sort_value,auth.uid(),auth.uid()) returning * into row;else update public.school_prospectus_sections set section_type=kind,title=title_value,instructions=instructions_value,display_order=sort_value,updated_by=auth.uid(),updated_at=now() where id=sid and prospectus_id=pid returning * into row;if row.id is null then raise exception 'Prospectus section not found';end if;end if;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;return to_jsonb(row);
end$function$;
revoke all on function public.save_school_prospectus_section(payload jsonb) from public;
grant execute on function public.save_school_prospectus_section(payload jsonb) to edusentia_worker_runtime;

-- save_security_verification(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_security_verification(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.security_verification_runs; findings_data jsonb:=coalesce(payload->'findings','[]'::jsonb); scope_text text:=left(btrim(coalesce(payload->>'scope','')),1000);
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can record security verification' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if length(scope_text)<3 then raise exception 'Verification scope is required'; end if;
  if jsonb_typeof(findings_data)<>'array' or octet_length(findings_data::text)>20000 then raise exception 'Verification findings must be a bounded JSON array'; end if;
  insert into public.security_verification_runs(standard_name,scope,status,summary,findings,next_review_at)
  values(left(coalesce(nullif(payload->>'standard_name',''),'OWASP ASVS 5.0'),200),scope_text,payload->>'status',left(coalesce(payload->>'summary',''),4000),findings_data,public.safe_timestamptz(payload->>'next_review_at')) returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'security_verification_runs',row_data.id,'SECURITY_VERIFICATION_RECORDED',null,
    jsonb_build_object('standard_name',row_data.standard_name,'status',row_data.status,'scope',row_data.scope,'next_review_at',row_data.next_review_at,'finding_count',jsonb_array_length(row_data.findings)),
    'System Administrator recorded a formal security verification result.');
  return to_jsonb(row_data);
end $function$;
revoke all on function public.save_security_verification(payload jsonb) from public;
grant execute on function public.save_security_verification(payload jsonb) to edusentia_worker_runtime;

-- save_teacher_award_category(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_teacher_award_category(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cid uuid:=public.safe_uuid(payload->>'id'); result public.teacher_award_categories;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can manage award categories' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'name',''))='' then raise exception 'Award category name is required'; end if;
  if cid is null then
    insert into public.teacher_award_categories(code,name,default_citation,active)
    values(upper(regexp_replace(btrim(payload->>'name'),'[^A-Za-z0-9]+','_','g')),btrim(payload->>'name'),btrim(coalesce(payload->>'default_citation','')),coalesce((payload->>'active')::boolean,true)) returning * into result;
  else
    update public.teacher_award_categories set name=btrim(payload->>'name'),default_citation=btrim(coalesce(payload->>'default_citation','')),active=coalesce((payload->>'active')::boolean,active),updated_at=now() where id=cid returning * into result;
  end if;
  return to_jsonb(result);
end $function$;
revoke all on function public.save_teacher_award_category(payload jsonb) from public;
grant execute on function public.save_teacher_award_category(payload jsonb) to edusentia_worker_runtime;

-- school_restore_dashboard()
CREATE OR REPLACE FUNCTION public.school_restore_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.created_at desc) from (select * from public.school_restore_jobs order by created_at desc limit 100) j),'[]'::jsonb),
    'active',coalesce((select to_jsonb(j) from public.school_restore_jobs j where status in ('upload_pending','uploaded','validating','restoring') order by created_at desc limit 1),'null'::jsonb)
  );
end $function$;
revoke all on function public.school_restore_dashboard() from public;
grant execute on function public.school_restore_dashboard() to edusentia_worker_runtime;

-- set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone)
CREATE OR REPLACE FUNCTION public.set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_updated timestamptz; affected integer;
begin
  if auth.uid() is null or not public.can_manage_student(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(target_photo_url,''))='' or target_photo_url not like target_student_id::text||'/%' then raise exception 'Student photograph path is invalid'; end if;
  select updated_at into current_updated from public.students where id=target_student_id and deleted_at is null for update;
  if not found then raise exception 'Student record not found'; end if;
  if expected_updated_at is not null and current_updated is distinct from expected_updated_at then raise exception 'Student record changed by another user' using errcode='40001'; end if;
  perform set_config('app.change_reason','Student photograph updated',true);
  update public.students set photo_url=target_photo_url,updated_at=now() where id=target_student_id and deleted_at is null;
  get diagnostics affected=row_count; if affected<>1 then raise exception 'Student photograph was not saved'; end if;
  return public.get_student_record_v5(target_student_id);
end $function$;
revoke all on function public.set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) from public;
grant execute on function public.set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone) to edusentia_worker_runtime;

-- staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text)
CREATE OR REPLACE FUNCTION public.staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select public.staff_id_card_photo_reference_count(target_staff_id,target_photo_path)>0
$function$;
revoke all on function public.staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text) from public;
grant execute on function public.staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text) to edusentia_worker_runtime;

-- submit_certificate_batch(target_batch_id uuid)
CREATE OR REPLACE FUNCTION public.submit_certificate_batch(target_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificate_batches; principal_id uuid;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can submit certificates' using errcode='42501'; end if;
  update public.certificate_batches set status='submitted',submitted_by=auth.uid(),submitted_at=now(),review_note='',updated_at=now() where id=target_batch_id and status in ('draft','rejected') returning * into updated;
  if updated.id is null then raise exception 'Only a draft or rejected batch can be submitted'; end if;
  if not exists(select 1 from public.certificates where batch_id=target_batch_id and status in ('draft','rejected')) then raise exception 'The batch has no certificates to submit'; end if;
  update public.certificates set status='draft',updated_at=now() where batch_id=target_batch_id and status='rejected';
  perform public.record_certificate_event(target_batch_id,null,'submitted_for_principal_approval');
  for principal_id in select id from public.profiles where active and public.current_app_role_for(role)::text='principal' loop
    perform public.create_notification(principal_id,'Certificates awaiting approval',updated.title||' contains certificates requiring Principal review.','certificate_approval','certificate_batch',target_batch_id,false);
  end loop;
  return jsonb_build_object('batch_id',updated.id,'status',updated.status);
end $function$;
revoke all on function public.submit_certificate_batch(target_batch_id uuid) from public;
grant execute on function public.submit_certificate_batch(target_batch_id uuid) to edusentia_worker_runtime;

-- system_health()
CREATE OR REPLACE FUNCTION public.system_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  latest_success timestamptz;
  latest_verified timestamptz;
  latest_recovery timestamptz;
  latest_offsite timestamptz;
  latest_full_status text;
  latest_full_created timestamptz;
  hist_failed integer:=0;
  current_failed integer:=0;
  client_faults integer:=0;
  client_faults_1h integer:=0;
  client_warnings integer:=0;
  client_events integer:=0;
  pending integer:=0;
  stale_pending integer:=0;
  retrying integer:=0;
  critical_security integer:=0;
  open_security integer:=0;
  missing_pdfs integer:=0;
  cron_failures integer:=0;
  reasons text[]:=array[]::text[];
  continuity_reasons text[]:=array[]::text[];
  op_state text:='healthy';
  continuity_state text:='healthy';
begin
  if public.current_app_role() not in ('system_admin','principal','academic_admin') then raise exception 'Access denied' using errcode='42501'; end if;

  select max(coalesce(completed_at,created_at)) into latest_success from public.backup_exports where status='completed' and backup_type='full';
  select max(verification_checked_at) into latest_verified from public.backup_exports where verification_status='passed';
  select max(completed_at) into latest_recovery from public.recovery_test_runs where status='passed';
  select max(offsite_copied_at) into latest_offsite from public.backup_exports;
  select status,created_at into latest_full_status,latest_full_created from public.backup_exports where backup_type='full' order by created_at desc limit 1;
  select count(*) into hist_failed from public.backup_exports where status='failed' and created_at>=now()-interval '30 days';
  select count(*) into current_failed from public.backup_exports where status='failed' and backup_type='full' and created_at>coalesce(latest_success,'-infinity'::timestamptz);

  select coalesce(sum(occurrence_count),0)::integer into client_faults from public.client_error_events where last_seen_at>=now()-interval '24 hours' and status='open' and severity in ('error','critical');
  select coalesce(sum(occurrence_count),0)::integer into client_faults_1h from public.client_error_events where last_seen_at>=now()-interval '1 hour' and status='open' and severity in ('error','critical');
  select coalesce(sum(occurrence_count),0)::integer into client_warnings from public.client_error_events where last_seen_at>=now()-interval '24 hours' and severity='warning';
  select coalesce(sum(occurrence_count),0)::integer into client_events from public.client_error_events where last_seen_at>=now()-interval '24 hours';

  select count(*),count(*) filter(where attempts>0),count(*) filter(where created_at<now()-interval '15 minutes')
    into pending,retrying,stale_pending from public.notification_outbox where processed_at is null;
  select count(*) into open_security from public.security_events where status='open';
  select count(*) into critical_security from public.security_events where status='open' and severity='critical';
  select count(*) into missing_pdfs from public.report_publications where revoked_at is null and storage_path='';
  if to_regclass('cron.job_run_details') is not null then
    select count(*) into cron_failures from cron.job_run_details r join cron.job j on j.jobid=r.jobid
    where r.start_time>=now()-interval '24 hours' and r.status<>'succeeded' and (j.jobname like 'rce-%' or j.jobname like 'nis-%');
  end if;

  if latest_success is null or latest_success<now()-interval '36 hours' then reasons:=array_append(reasons,'Full backup is stale or unavailable.'); end if;
  if latest_full_status='failed' and current_failed>0 then reasons:=array_append(reasons,'The latest full backup attempt failed and has not yet been superseded by a successful backup.'); end if;
  if latest_verified is null or latest_verified<now()-interval '8 days' then reasons:=array_append(reasons,'Verified backup evidence is older than the weekly verification window.'); end if;
  if latest_recovery is null or latest_recovery<now()-interval '8 days' then reasons:=array_append(reasons,'Recovery rehearsal evidence is older than the weekly recovery window.'); end if;
  if critical_security>0 then reasons:=array_append(reasons,'A critical security event is open.'); end if;
  if missing_pdfs>0 then reasons:=array_append(reasons,'One or more active published reports are missing an official PDF.'); end if;
  if stale_pending>0 then reasons:=array_append(reasons,'Notification delivery has items pending for more than 15 minutes.'); end if;
  if cron_failures>0 then reasons:=array_append(reasons,'A scheduled maintenance job failed within the last 24 hours.'); end if;
  if client_faults_1h>0 then reasons:=array_append(reasons,'An actionable client fault was recorded within the last hour.'); end if;
  if cardinality(reasons)>0 then op_state:='attention'; end if;

  if latest_offsite is null then continuity_reasons:=array_append(continuity_reasons,'No separate off-site backup copy has been confirmed.'); end if;
  if cardinality(continuity_reasons)>0 then continuity_state:='attention'; end if;

  return jsonb_build_object(
    'database_time',now(),
    'operational_state',op_state,'health_reasons',to_jsonb(reasons),
    'continuity_state',continuity_state,'continuity_reasons',to_jsonb(continuity_reasons),
    'active_users',(select count(*) from public.profiles where active),
    'active_teachers',(select count(*) from public.teachers where active and deleted_at is null),
    'active_students',(select count(*) from public.students where status='active' and deleted_at is null),
    'pending_notifications',pending,'notification_retrying',retrying,'stale_pending_notifications',stale_pending,
    'client_errors_24h',client_faults,'client_warnings_24h',client_warnings,'client_events_24h',client_events,
    'latest_backup',latest_success,'latest_full_backup_status',latest_full_status,'latest_full_backup_created_at',latest_full_created,
    'latest_verified_backup',latest_verified,'latest_recovery_test',latest_recovery,
    'failed_backups_30d',hist_failed,'current_backup_failures',current_failed,
    'unverified_completed_backups',(select count(*) from public.backup_exports where status='completed' and verification_status<>'passed'),
    'latest_offsite_copy',latest_offsite,'open_security_events',open_security,'critical_security_events',critical_security,
    'cron_failures_24h',cron_failures,
    'incomplete_schemes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'weight',q.total_weight)) from (
      select scheme_id,sum(weight) total_weight from public.assessment_components group by scheme_id having abs(sum(weight)-100)>0.01
    ) q join public.assessment_schemes s on s.id=q.scheme_id),'[]'::jsonb),
    'published_without_pdf',missing_pdfs
  );
end
$function$;
revoke all on function public.system_health() from public;
grant execute on function public.system_health() to edusentia_worker_runtime;

-- update_privacy_request(target_request_id uuid, target_status text, outcome_text text)
CREATE OR REPLACE FUNCTION public.update_privacy_request(target_request_id uuid, target_status text, outcome_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.privacy_requests; prior public.privacy_requests;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if target_status not in ('open','in_review','approved','rejected','completed','cancelled') then raise exception 'Invalid privacy-request status'; end if;
  select * into prior from public.privacy_requests where id=target_request_id for update;
  if prior.id is null then raise exception 'Privacy request not found'; end if;
  update public.privacy_requests set status=target_status,outcome=left(coalesce(outcome_text,''),2000),completed_by=case when target_status in ('completed','rejected','cancelled') then auth.uid() else completed_by end,completed_at=case when target_status in ('completed','rejected','cancelled') then now() else completed_at end,updated_at=now() where id=target_request_id returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'privacy_requests',row_data.id,'PRIVACY_REQUEST_STATUS_CHANGED',
    jsonb_build_object('status',prior.status),jsonb_build_object('status',row_data.status,'outcome_recorded',length(btrim(coalesce(outcome_text,'')))>0),
    'Privacy-request workflow status was changed. Outcome text is not duplicated into the Audit Trail.');
  return to_jsonb(row_data);
end $function$;
revoke all on function public.update_privacy_request(target_request_id uuid, target_status text, outcome_text text) from public;
grant execute on function public.update_privacy_request(target_request_id uuid, target_status text, outcome_text text) to edusentia_worker_runtime;

-- validate_score_import(target_term_id uuid, target_class_id uuid, rows jsonb, filename text)
CREATE OR REPLACE FUNCTION public.validate_score_import(target_term_id uuid, target_class_id uuid, rows jsonb, filename text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare item jsonb;rowno integer:=0;valid_rows jsonb:='[]'::jsonb;errors jsonb:='[]'::jsonb;yearid uuid;enrollmentid uuid;subjectid uuid;schemeid uuid;componentid uuid;maxscore numeric;raw numeric;
begin
  if not public.can_create_report_for_class_term(target_class_id,target_term_id) then raise exception 'Access denied' using errcode='42501'; end if;
  if not public.term_phase_writable(target_term_id,'scores',null) then raise exception 'Score entry is locked for the selected term'; end if;
  select academic_year_id into yearid from public.terms where id=target_term_id and deleted_at is null;
  for item in select value from jsonb_array_elements(coalesce(rows,'[]'::jsonb)) loop
    rowno:=rowno+1; enrollmentid:=null;subjectid:=null;schemeid:=null;componentid:=null;maxscore:=null;raw:=null;
    begin
      if btrim(coalesce(item->>'admission_no',''))='' or btrim(coalesce(item->>'subject_code',''))='' or btrim(coalesce(item->>'component_code',''))='' then raise exception 'Admission number, subject code, and component code are required'; end if;
      select e.id into strict enrollmentid from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=target_class_id and e.academic_year_id=yearid and e.active and e.deleted_at is null and s.deleted_at is null and lower(s.admission_no::text)=lower(btrim(item->>'admission_no'));
      select sb.id into subjectid from public.subjects sb join public.class_subjects cs on cs.subject_id=sb.id and cs.class_id=target_class_id and cs.active where lower(sb.code::text)=lower(btrim(item->>'subject_code')) and sb.active and sb.deleted_at is null;
      if subjectid is null then raise exception 'Subject code is not assigned to the selected class'; end if;
      if not public.can_score_class_subject_for_term(target_class_id,subjectid,target_term_id) then raise exception 'Not authorised for this subject'; end if;
      schemeid:=public.resolve_assessment_scheme(target_class_id,subjectid,yearid,target_term_id); if schemeid is null then raise exception 'Assessment scheme not configured'; end if;
      select ac.id,ac.maximum_score into componentid,maxscore from public.assessment_components ac where ac.scheme_id=schemeid and lower(ac.code::text)=lower(btrim(item->>'component_code'));
      if componentid is null then raise exception 'Assessment component code not found'; end if;
      raw:=public.safe_numeric(item->>'raw_score'); if raw is null then raise exception 'Raw score is invalid'; end if;
      if raw<0 or raw>maxscore then raise exception 'Raw score is outside the component maximum'; end if;
      valid_rows:=valid_rows||jsonb_build_array(item);
    exception when others then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message',sqlerrm,'payload',item));
    end;
  end loop;
  return jsonb_build_object('filename',filename,'total',jsonb_array_length(coalesce(rows,'[]'::jsonb)),'valid_count',jsonb_array_length(valid_rows),'invalid_count',jsonb_array_length(errors),'valid_rows',valid_rows,'errors',errors);
end $function$;
revoke all on function public.validate_score_import(target_term_id uuid, target_class_id uuid, rows jsonb, filename text) from public;
grant execute on function public.validate_score_import(target_term_id uuid, target_class_id uuid, rows jsonb, filename text) to edusentia_worker_runtime;

-- verify_certificate(token uuid)
CREATE OR REPLACE FUNCTION public.verify_certificate(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((select jsonb_build_object(
    'found',true,'valid',c.status='issued','status',c.status,'certificate_number',c.certificate_number,
    'certificate_type',b.certificate_type,'certificate_type_label',public.certificate_type_label(b.certificate_type),
    'certificate_title',c.certificate_title,'recipient_name',c.recipient_name,'recipient_identifier',c.recipient_identifier,
    'academic_year',c.academic_year_name,'class_name',c.current_class_name,'promoted_to',c.destination_class_name,
    'award_category',c.award_category_name,'statement',c.statement_text,'issue_date',c.issue_date,'issued_at',c.issued_at,
    'school_name',(select s.school_name from public.school_settings s limit 1),
    'revocation_reason',case when c.status='revoked' then c.revocation_reason else '' end,
    'superseded_by',(select newer.certificate_number from public.certificates newer where newer.supersedes_certificate_id=c.id and newer.status='issued' order by newer.issued_at desc limit 1)
  ) from public.certificates c join public.certificate_batches b on b.id=c.batch_id where c.verification_token=token),jsonb_build_object('found',false,'valid',false,'status','not_found'))
$function$;
revoke all on function public.verify_certificate(token uuid) from public;
grant execute on function public.verify_certificate(token uuid) to edusentia_worker_runtime;

-- verify_staff_id_card(token uuid)
CREATE OR REPLACE FUNCTION public.verify_staff_id_card(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select coalesce(
  (select jsonb_build_object('found',true,'valid',public.id_card_effective_status(c.status,c.expires_on)='active','status',public.id_card_effective_status(c.status,c.expires_on),'card_number',c.card_number,'staff_name',c.snapshot#>>'{staff,full_name}','staff_no',c.snapshot#>>'{staff,staff_no}','staff_role',c.snapshot#>>'{staff,role}','school_name',c.snapshot#>>'{school,school_name}','academic_year',c.snapshot#>>'{academic,academic_year_name}','issue_date',c.issue_date,'expires_on',c.expires_on,'revision',c.revision_no,'replacement_card_number',(select n.card_number from public.staff_id_cards n where n.supersedes_card_id=c.id order by n.issued_at desc limit 1)) from public.staff_id_cards c where c.verification_token=token),
  (select jsonb_build_object('found',true,'valid',false,'status','permanently_removed','card_number',t.card_number) from public.id_card_deletion_tombstones t where t.card_kind='staff' and t.verification_token=token),
  jsonb_build_object('found',false,'valid',false,'status','not_found'))
$function$;
revoke all on function public.verify_staff_id_card(token uuid) from public;
grant execute on function public.verify_staff_id_card(token uuid) to edusentia_worker_runtime;

-- verify_student_id_card(token uuid)
CREATE OR REPLACE FUNCTION public.verify_student_id_card(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select coalesce(
  (select jsonb_build_object('found',true,'valid',public.id_card_effective_status(c.status,c.expires_on)='active','status',public.id_card_effective_status(c.status,c.expires_on),'card_number',c.card_number,'student_name',c.snapshot#>>'{student,full_name}','admission_no',c.snapshot#>>'{student,admission_no}','class_name',c.snapshot#>>'{academic,class_name}','academic_year',c.snapshot#>>'{academic,academic_year_name}','school_name',c.snapshot#>>'{school,school_name}','issue_date',c.issue_date,'expires_on',c.expires_on,'revision',c.revision_no,'replacement_card_number',(select n.card_number from public.student_id_cards n where n.supersedes_card_id=c.id order by n.issued_at desc limit 1)) from public.student_id_cards c where c.verification_token=token),
  (select jsonb_build_object('found',true,'valid',false,'status','permanently_removed','card_number',t.card_number) from public.id_card_deletion_tombstones t where t.card_kind='student' and t.verification_token=token),
  jsonb_build_object('found',false,'valid',false,'status','not_found'))
$function$;
revoke all on function public.verify_student_id_card(token uuid) from public;
grant execute on function public.verify_student_id_card(token uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0046_certified_reference_rpc_bulk')
on conflict do nothing;

update app.release_identity
   set schema_version='0046'
 where edition='Edusentia Enterprise Neon Edition';

commit;
