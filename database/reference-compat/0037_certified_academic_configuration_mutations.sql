-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function bodies extracted read-only with pg_get_functiondef.

begin;

CREATE OR REPLACE FUNCTION public.save_academic_entity(entity_type text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(payload->>'id');
  affected integer;
  startdate date:=public.safe_date(payload->>'start_date');
  enddate date:=public.safe_date(payload->>'end_date');
  nextdate date:=public.safe_date(payload->>'next_term_begins');
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id');
  teacherid uuid:=public.safe_uuid(payload->>'class_teacher_id');
  teacherrecordid uuid:=public.safe_uuid(payload->>'class_teacher_record_id');
  seq integer:=public.safe_integer(payload->>'sequence');
  orderno integer;
  subjectcode text;
  existingcode text;
  recordname text:=regexp_replace(btrim(coalesce(payload->>'name','')),'[[:space:]]+',' ','g');
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Academic record identifier is invalid'; end if;
  if btrim(coalesce(payload->>'start_date',''))<>'' and startdate is null then raise exception 'Start date is invalid'; end if;
  if btrim(coalesce(payload->>'end_date',''))<>'' and enddate is null then raise exception 'End date is invalid'; end if;
  if btrim(coalesce(payload->>'next_term_begins',''))<>'' and nextdate is null then raise exception 'Next term date is invalid'; end if;
  if btrim(coalesce(payload->>'academic_year_id',''))<>'' and yearid is null then raise exception 'Academic year identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_teacher_id',''))<>'' and teacherid is null then raise exception 'Class teacher account identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_teacher_record_id',''))<>'' and teacherrecordid is null then raise exception 'Class teacher record identifier is invalid'; end if;
  if startdate is not null and enddate is not null and startdate>enddate then raise exception 'Start date cannot be after end date'; end if;
  if nextdate is not null and enddate is not null and nextdate<enddate then raise exception 'Next term date cannot be before the term end date'; end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Academic record update'),true);
  if entity_type='academic_years' then
    if recordname='' then raise exception 'Academic year name is required'; end if;
    if targetid is null then
      select y.id into targetid
      from public.academic_years y
      where lower(y.name::text)=lower(recordname) and y.deleted_at is not null
      order by y.updated_at desc,y.created_at desc limit 1 for update;
      if targetid is null then
        insert into public.academic_years(name,start_date,end_date)
        values(recordname,startdate,enddate) returning id into targetid;
      else
        update public.academic_years
        set name=recordname,start_date=startdate,end_date=enddate,is_active=false,deleted_at=null,updated_at=now()
        where id=targetid;
      end if;
    else
      update public.academic_years
      set name=recordname,start_date=startdate,end_date=enddate,updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  elsif entity_type='terms' then
    if yearid is null or not exists(select 1 from public.academic_years y where y.id=yearid and y.deleted_at is null) then raise exception 'Academic year is invalid'; end if;
    if recordname='' then raise exception 'Term name is required'; end if;
    if seq is null or seq not between 1 and 6 then raise exception 'Term sequence must be between 1 and 6'; end if;
    if targetid is null then
      select t.id into targetid
      from public.terms t
      where t.academic_year_id=yearid and t.deleted_at is not null
        and (lower(t.name::text)=lower(recordname) or t.sequence=seq)
      order by ((lower(t.name::text)=lower(recordname)) and t.sequence=seq) desc,t.updated_at desc,t.created_at desc
      limit 1 for update;
      if targetid is null then
        insert into public.terms(academic_year_id,name,sequence,start_date,end_date,next_term_begins)
        values(yearid,recordname,seq,startdate,enddate,nextdate) returning id into targetid;
      else
        update public.terms
        set academic_year_id=yearid,name=recordname,sequence=seq,start_date=startdate,end_date=enddate,
          next_term_begins=nextdate,is_active=false,deleted_at=null,updated_at=now()
        where id=targetid;
      end if;
    else
      update public.terms
      set academic_year_id=yearid,name=recordname,sequence=seq,start_date=startdate,end_date=enddate,
        next_term_begins=nextdate,updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  elsif entity_type='classes' then
    if recordname='' then raise exception 'Class name is required'; end if;
    orderno:=coalesce(public.safe_integer(payload->>'level_order'),0);
    if teacherrecordid is not null then
      select t.profile_id
      into teacherid
      from public.teachers t
      where t.id=teacherrecordid
        and t.deleted_at is null
        and t.active
        and t.employment_status='active';
      if not found then raise exception 'Selected class teacher record is inactive or unavailable'; end if;
    elsif teacherid is not null then
      select t.id
      into teacherrecordid
      from public.teachers t
      where t.profile_id=teacherid
        and t.deleted_at is null
        and t.active
        and t.employment_status='active'
      order by t.updated_at desc
      limit 1;
    end if;
    if teacherid is not null and not exists(
      select 1 from public.profiles p
      where p.id=teacherid
        and p.active
        and public.current_app_role_for(p.role) in ('class_teacher','subject_teacher')
    ) then
      teacherid:=null;
    end if;
    if targetid is null then
      select c.id into targetid
      from public.classes c
      where lower(c.name::text)=lower(recordname) and c.deleted_at is not null
      order by c.updated_at desc,c.created_at desc limit 1 for update;
      if targetid is null then
        insert into public.classes(name,level_order,class_teacher_record_id,class_teacher_id,active)
        values(recordname,orderno,teacherrecordid,teacherid,public.safe_boolean(payload->>'active',true))
        returning id into targetid;
      else
        update public.classes
        set name=recordname,
            level_order=orderno,
            class_teacher_record_id=teacherrecordid,
            class_teacher_id=teacherid,
            active=public.safe_boolean(payload->>'active',true),
            deleted_at=null,
            updated_at=now()
        where id=targetid;
      end if;
    else
      update public.classes
      set name=recordname,
          level_order=orderno,
          class_teacher_record_id=teacherrecordid,
          class_teacher_id=teacherid,
          active=public.safe_boolean(payload->>'active',true),
          updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  elsif entity_type='subjects' then
    if recordname='' then raise exception 'Subject name is required'; end if;
    orderno:=coalesce(public.safe_integer(payload->>'display_order'),0);
    subjectcode:=upper(btrim(coalesce(payload->>'code','')));
    if targetid is null then
      select s.id,s.code::text into targetid,existingcode
      from public.subjects s
      where lower(s.name::text)=lower(recordname) and s.deleted_at is not null
      order by s.updated_at desc,s.created_at desc limit 1 for update;
      if targetid is null then
        if subjectcode='' or exists(select 1 from public.subjects s where lower(s.code::text)=lower(subjectcode)) then
          subjectcode:=public.generate_subject_code(recordname,null);
        end if;
        insert into public.subjects(code,name,display_order,active)
        values(subjectcode,recordname,orderno,public.safe_boolean(payload->>'active',true)) returning id into targetid;
      else
        subjectcode:=coalesce(nullif(subjectcode,''),existingcode);
        if exists(select 1 from public.subjects s where lower(s.code::text)=lower(subjectcode) and s.id<>targetid) then
          subjectcode:=public.generate_subject_code(recordname,targetid);
        end if;
        update public.subjects
        set code=subjectcode,name=recordname,display_order=orderno,
          active=public.safe_boolean(payload->>'active',true),deleted_at=null,updated_at=now()
        where id=targetid;
      end if;
    else
      select s.code::text into existingcode
      from public.subjects s where s.id=targetid and s.deleted_at is null for update;
      if not found then raise exception 'Subject not found'; end if;
      subjectcode:=coalesce(nullif(subjectcode,''),existingcode);
      if exists(select 1 from public.subjects s where lower(s.code::text)=lower(subjectcode) and s.id<>targetid) then
        subjectcode:=public.generate_subject_code(recordname,targetid);
      end if;
      update public.subjects
      set code=subjectcode,name=recordname,display_order=orderno,
        active=public.safe_boolean(payload->>'active',true),updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  else
    raise exception 'Unsupported academic record type';
  end if;
  get diagnostics affected=row_count;
  if targetid is null or affected=0 then raise exception 'Academic record was not saved'; end if;
  return public.get_academic_configuration();
exception when unique_violation then
  if entity_type='academic_years' then raise exception 'An academic year with this name already exists';
  elsif entity_type='terms' then raise exception 'A term with this name or sequence already exists in the selected academic year';
  elsif entity_type='classes' then raise exception 'A class with this name already exists';
  elsif entity_type='subjects' then raise exception 'A subject with this name or code already exists';
  else raise exception 'An academic record already uses these details';
  end if;
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.save_grading_scale(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(payload->>'id');
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id');
  classid uuid:=public.safe_uuid(payload->>'class_id');
  subjectid uuid:=public.safe_uuid(payload->>'subject_id');
  minmark numeric:=public.safe_numeric(payload->>'min_mark');
  maxmark numeric:=public.safe_numeric(payload->>'max_mark');
  pointvalue numeric:=coalesce(public.safe_numeric(payload->>'grade_point'),0);
  orderno integer:=coalesce(public.safe_integer(payload->>'display_order'),0);
  interpretation_text text:=btrim(coalesce(payload->>'interpretation',''));
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Grading scale identifier is invalid'; end if;
  if btrim(coalesce(payload->>'academic_year_id',''))<>'' and yearid is null then raise exception 'Academic year identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_id',''))<>'' and classid is null then raise exception 'Class identifier is invalid'; end if;
  if btrim(coalesce(payload->>'subject_id',''))<>'' and subjectid is null then raise exception 'Subject identifier is invalid'; end if;
  if btrim(coalesce(payload->>'grade',''))='' or btrim(coalesce(payload->>'remark',''))='' then raise exception 'Grade and remark are required'; end if;
  if minmark is null or maxmark is null or minmark<0 or maxmark>100 or minmark>maxmark then raise exception 'Grade range is invalid'; end if;
  if length(interpretation_text)>180 then raise exception 'The interpretation must not exceed 180 characters'; end if;
  if interpretation_text='' then interpretation_text:=public.default_grading_interpretation(payload->>'grade',payload->>'remark'); end if;
  if yearid is not null and not exists(select 1 from public.academic_years where id=yearid and deleted_at is null) then raise exception 'Academic year is invalid'; end if;
  if classid is not null and not exists(select 1 from public.classes where id=classid and deleted_at is null) then raise exception 'Class is invalid'; end if;
  if subjectid is not null and not exists(select 1 from public.subjects where id=subjectid and deleted_at is null) then raise exception 'Subject is invalid'; end if;
  if exists(
    select 1 from public.grading_scales g
    where g.deleted_at is null and (targetid is null or g.id<>targetid)
      and g.academic_year_id is not distinct from yearid
      and g.class_id is not distinct from classid
      and g.subject_id is not distinct from subjectid
      and numrange(g.min_mark,g.max_mark,'[]') && numrange(minmark,maxmark,'[]')
  ) then raise exception 'Grade ranges cannot overlap within the same scope'; end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Grading scale update'),true);
  if targetid is null then
    insert into public.grading_scales(
      academic_year_id,class_id,subject_id,min_mark,max_mark,grade,remark,interpretation,
      grade_point,display_order,deleted_at,updated_at
    ) values(
      yearid,classid,subjectid,minmark,maxmark,upper(btrim(payload->>'grade')),
      btrim(payload->>'remark'),interpretation_text,pointvalue,orderno,null,now()
    ) returning id into targetid;
  else
    update public.grading_scales
    set academic_year_id=yearid,class_id=classid,subject_id=subjectid,
        min_mark=minmark,max_mark=maxmark,grade=upper(btrim(payload->>'grade')),
        remark=btrim(payload->>'remark'),interpretation=interpretation_text,
        grade_point=pointvalue,display_order=orderno,deleted_at=null,updated_at=now()
    where id=targetid;
    if not found then raise exception 'Grading scale not found'; end if;
  end if;
  return public.get_academic_configuration();
exception when unique_violation then
  raise exception 'This grading scope already contains the selected grade';
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.save_assessment_scheme(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  sid uuid:=public.safe_uuid(payload->>'id'); item jsonb; staged_item jsonb; staged jsonb:='[]'::jsonb;
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id'); termid uuid:=public.safe_uuid(payload->>'term_id');
  classid uuid:=public.safe_uuid(payload->>'class_id'); subjectid uuid:=public.safe_uuid(payload->>'subject_id');
  componentid uuid; existing_component public.assessment_components%rowtype;
  weight_total numeric:=0; maxscore numeric; weightvalue numeric; orderno integer; requiredvalue boolean;
  component_code text; component_name text; seen_codes text[]:='{}'::text[]; seen_ids uuid[]:='{}'::uuid[];
  kept_ids uuid[]:='{}'::uuid[]; affected integer; scheme_in_use boolean:=false;
  old_yearid uuid; old_termid uuid; old_classid uuid; old_subjectid uuid; current_count integer; staged_count integer;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and sid is null then raise exception 'Assessment scheme identifier is invalid'; end if;
  if btrim(coalesce(payload->>'academic_year_id',''))<>'' and yearid is null then raise exception 'Academic year identifier is invalid'; end if;
  if btrim(coalesce(payload->>'term_id',''))<>'' and termid is null then raise exception 'Term identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_id',''))<>'' and classid is null then raise exception 'Class identifier is invalid'; end if;
  if btrim(coalesce(payload->>'subject_id',''))<>'' and subjectid is null then raise exception 'Subject identifier is invalid'; end if;
  if btrim(coalesce(payload->>'name',''))='' then raise exception 'Assessment scheme name is required'; end if;
  if jsonb_typeof(coalesce(payload->'components','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(payload->'components','[]'::jsonb))=0 then raise exception 'At least one assessment component is required'; end if;
  if yearid is not null and not exists(select 1 from public.academic_years y where y.id=yearid and y.deleted_at is null) then raise exception 'Academic year is invalid'; end if;
  if termid is not null and not exists(select 1 from public.terms t where t.id=termid and t.deleted_at is null and (yearid is null or t.academic_year_id=yearid)) then raise exception 'Term is invalid or does not belong to the selected academic year'; end if;
  if classid is not null and not exists(select 1 from public.classes c where c.id=classid and c.deleted_at is null and c.active) then raise exception 'Class is invalid or inactive'; end if;
  if subjectid is not null and not exists(select 1 from public.subjects sb where sb.id=subjectid and sb.deleted_at is null and sb.active) then raise exception 'Subject is invalid or inactive'; end if;
  if sid is not null then
    select academic_year_id,term_id,class_id,subject_id into old_yearid,old_termid,old_classid,old_subjectid
    from public.assessment_schemes where id=sid and deleted_at is null for update;
    if not found then raise exception 'Assessment scheme not found'; end if;
    scheme_in_use:=exists(select 1 from public.subject_results sr where sr.scheme_id=sid);
    if scheme_in_use and (old_yearid is distinct from yearid or old_termid is distinct from termid or old_classid is distinct from classid or old_subjectid is distinct from subjectid) then
      raise exception 'An assessment scheme already used in reports cannot change its academic scope';
    end if;
  end if;
  for item in select value from jsonb_array_elements(payload->'components') loop
    component_name:=btrim(coalesce(item->>'name','')); component_code:=upper(btrim(coalesce(item->>'code','')));
    maxscore:=public.safe_numeric(item->>'maximum_score'); weightvalue:=public.safe_numeric(item->>'weight');
    orderno:=coalesce(public.safe_integer(item->>'display_order'),0); requiredvalue:=public.safe_boolean(item->>'required',true);
    componentid:=public.safe_uuid(item->>'id');
    if btrim(coalesce(item->>'id',''))<>'' and componentid is null then raise exception 'Assessment component identifier is invalid'; end if;
    if component_name='' or component_code='' then raise exception 'Every assessment component requires a name and code'; end if;
    if maxscore is null or maxscore<=0 then raise exception 'Assessment component maximum score must be greater than zero'; end if;
    if weightvalue is null or weightvalue<=0 or weightvalue>100 then raise exception 'Assessment component weight is invalid'; end if;
    if component_code=any(seen_codes) then raise exception 'Assessment component codes must be unique within a scheme'; end if;
    if componentid is not null then
      if sid is null then raise exception 'A new assessment scheme cannot contain an existing component identifier'; end if;
      select * into existing_component from public.assessment_components c where c.id=componentid and c.scheme_id=sid;
      if not found then raise exception 'Assessment component does not belong to the selected scheme'; end if;
    elsif sid is not null then
      select c.id into componentid from public.assessment_components c where c.scheme_id=sid and lower(c.code::text)=lower(component_code) limit 1;
    end if;
    if componentid is not null and componentid=any(seen_ids) then raise exception 'The same assessment component was entered more than once'; end if;
    if componentid is not null then
      seen_ids:=array_append(seen_ids,componentid); kept_ids:=array_append(kept_ids,componentid);
      select * into existing_component from public.assessment_components c where c.id=componentid;
      if exists(select 1 from public.assessment_score_entries se where se.component_id=componentid and se.raw_score>maxscore) then
        raise exception 'Maximum score cannot be lower than an existing student score for component %',existing_component.name;
      end if;
      if scheme_in_use and (
        lower(existing_component.code::text)<>lower(component_code) or existing_component.maximum_score is distinct from maxscore
        or existing_component.weight is distinct from weightvalue or existing_component.required is distinct from requiredvalue
      ) then raise exception 'A component already used in reports cannot change its code, maximum score, weight, or required status'; end if;
    elsif scheme_in_use then
      raise exception 'New components cannot be added to an assessment scheme already used in reports';
    end if;
    seen_codes:=array_append(seen_codes,component_code); weight_total:=weight_total+weightvalue;
    staged:=staged||jsonb_build_array(item||jsonb_build_object(
      '_resolved_id',case when componentid is null then null else componentid::text end,
      '_name',component_name,'_code',component_code,'_maximum_score',maxscore,'_weight',weightvalue,
      '_display_order',orderno,'_required',requiredvalue
    ));
  end loop;
  if abs(weight_total-100)>0.01 then raise exception 'Assessment component weights must total 100'; end if;
  if sid is not null and scheme_in_use then
    select count(*) into current_count from public.assessment_components where scheme_id=sid;
    staged_count:=jsonb_array_length(staged);
    if current_count<>staged_count or exists(select 1 from public.assessment_components c where c.scheme_id=sid and not(c.id=any(kept_ids))) then
      raise exception 'Components already used in reports cannot be removed';
    end if;
  end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Assessment scheme update'),true);
  if sid is null then
    insert into public.assessment_schemes(name,academic_year_id,term_id,class_id,subject_id,active,created_by,deleted_at,updated_at)
    values(btrim(payload->>'name'),yearid,termid,classid,subjectid,public.safe_boolean(payload->>'active',true),auth.uid(),null,now()) returning id into sid;
  else
    update public.assessment_schemes set name=btrim(payload->>'name'),academic_year_id=yearid,term_id=termid,class_id=classid,
      subject_id=subjectid,active=public.safe_boolean(payload->>'active',true),deleted_at=null,updated_at=now() where id=sid;
    get diagnostics affected=row_count; if affected<>1 then raise exception 'Assessment scheme not found'; end if;
  end if;
  if exists(
    select 1 from public.assessment_components c where c.scheme_id=sid and not(c.id=any(kept_ids))
      and exists(select 1 from public.assessment_score_entries se where se.component_id=c.id)
  ) then raise exception 'A component with saved student scores cannot be removed'; end if;
  delete from public.assessment_components c where c.scheme_id=sid and not(c.id=any(kept_ids));
  -- Free existing component codes inside the transaction so code renames and swaps remain atomic.
  update public.assessment_components c
  set code=('__NIS_TMP_'||replace(c.id::text,'-',''))::citext,updated_at=now()
  where c.scheme_id=sid and c.id=any(kept_ids);
  -- Apply decreases first so the weight guard never sees an intermediate total above 100.
  for staged_item in select value from jsonb_array_elements(staged) loop
    componentid:=public.safe_uuid(staged_item->>'_resolved_id');
    if componentid is not null then
      weightvalue:=public.safe_numeric(staged_item->>'_weight');
      update public.assessment_components set weight=weightvalue,updated_at=now()
      where id=componentid and weight>weightvalue;
    end if;
  end loop;
  -- Insert new components while the total is below or equal to its final validated value.
  for staged_item in select value from jsonb_array_elements(staged) loop
    componentid:=public.safe_uuid(staged_item->>'_resolved_id');
    if componentid is null then
      insert into public.assessment_components(scheme_id,name,code,maximum_score,weight,display_order,required,updated_at)
      values(sid,staged_item->>'_name',(staged_item->>'_code')::citext,public.safe_numeric(staged_item->>'_maximum_score'),
        public.safe_numeric(staged_item->>'_weight'),coalesce(public.safe_integer(staged_item->>'_display_order'),0),
        public.safe_boolean(staged_item->>'_required',true),now());
    end if;
  end loop;
  -- Finish existing component updates, including increases, after all reductions and removals.
  for staged_item in select value from jsonb_array_elements(staged) loop
    componentid:=public.safe_uuid(staged_item->>'_resolved_id');
    if componentid is not null then
      update public.assessment_components set name=staged_item->>'_name',code=(staged_item->>'_code')::citext,
        maximum_score=public.safe_numeric(staged_item->>'_maximum_score'),weight=public.safe_numeric(staged_item->>'_weight'),
        display_order=coalesce(public.safe_integer(staged_item->>'_display_order'),0),
        required=public.safe_boolean(staged_item->>'_required',true),updated_at=now()
      where id=componentid and scheme_id=sid;
      get diagnostics affected=row_count; if affected<>1 then raise exception 'Assessment component was not updated'; end if;
    end if;
  end loop;
  if abs((select coalesce(sum(c.weight),0) from public.assessment_components c where c.scheme_id=sid)-100)>0.01 then
    raise exception 'Assessment component weights must total 100';
  end if;
  return public.get_academic_configuration();
exception when unique_violation then raise exception 'An assessment scheme or component code already exists in this scope';
end $function$;

CREATE OR REPLACE FUNCTION public.save_class_subject_assignments_batch(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(payload->>'id');
  teacherid uuid:=public.safe_uuid(payload->>'teacher_id');
  activevalue boolean:=public.safe_boolean(payload->>'active',true);
  selections jsonb:=coalesce(payload->'selections','[]'::jsonb);
  item jsonb;
  classid uuid;
  subjectid uuid;
  pairkey text;
  seenpairs text[]:='{}'::text[];
  previous_teacher uuid;
  old_class uuid;
  old_subject uuid;
  old_teacher uuid;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Subject assignment identifier is invalid'; end if;
  if btrim(coalesce(payload->>'teacher_id',''))<>'' and teacherid is null then raise exception 'Teacher identifier is invalid'; end if;
  if teacherid is null or not exists(
    select 1 from public.profiles p
    where p.id=teacherid and p.active
      and public.current_app_role_for(p.role) in ('class_teacher','subject_teacher')
  ) then raise exception 'Select an active Class Teacher or Subject Teacher account'; end if;
  if jsonb_typeof(selections)<>'array' or jsonb_array_length(selections)=0 then
    raise exception 'Select at least one class and subject';
  end if;
  if jsonb_array_length(selections)>500 then raise exception 'Too many assignments were selected'; end if;
  if targetid is not null then
    select class_id,subject_id,teacher_id into old_class,old_subject,old_teacher
    from public.class_subjects where id=targetid for update;
    if not found then raise exception 'Subject assignment not found'; end if;
  end if;
  for item in select value from jsonb_array_elements(selections) loop
    classid:=public.safe_uuid(item->>'class_id');
    subjectid:=public.safe_uuid(item->>'subject_id');
    if classid is null or not exists(select 1 from public.classes c where c.id=classid and c.deleted_at is null and c.active) then
      raise exception 'A selected class is invalid or inactive';
    end if;
    if subjectid is null or not exists(select 1 from public.subjects s where s.id=subjectid and s.deleted_at is null and s.active) then
      raise exception 'A selected subject is invalid or inactive';
    end if;
    pairkey:=classid::text||'|'||subjectid::text;
    if pairkey=any(seenpairs) then raise exception 'The same class and subject were selected more than once'; end if;
    seenpairs:=array_append(seenpairs,pairkey);
  end loop;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Class-subject assignment batch update'),true);
  if targetid is not null then
    delete from public.class_subjects where id=targetid;
  end if;
  for item in select value from jsonb_array_elements(selections) loop
    classid:=public.safe_uuid(item->>'class_id');
    subjectid:=public.safe_uuid(item->>'subject_id');
    select cs.teacher_id into previous_teacher
    from public.class_subjects cs
    where cs.class_id=classid and cs.subject_id=subjectid
    for update;
    insert into public.class_subjects(class_id,subject_id,teacher_id,active,updated_at)
    values(classid,subjectid,teacherid,activevalue,now())
    on conflict(class_id,subject_id) do update set
      teacher_id=excluded.teacher_id,
      active=excluded.active,
      updated_at=now();
    if previous_teacher is not null and previous_teacher is distinct from teacherid then
      delete from public.user_class_access
      where user_id=previous_teacher and class_id=classid and subject_id=subjectid;
    end if;
    if activevalue then
      insert into public.user_class_access(user_id,class_id,subject_id,access_level)
      values(teacherid,classid,subjectid,'score')
      on conflict do nothing;
    else
      delete from public.user_class_access
      where user_id=teacherid and class_id=classid and subject_id=subjectid;
    end if;
  end loop;
  if old_teacher is not null and old_class is not null and old_subject is not null
     and not exists(
       select 1 from public.class_subjects cs
       where cs.class_id=old_class and cs.subject_id=old_subject
         and cs.teacher_id=old_teacher and cs.active
     ) then
    delete from public.user_class_access
    where user_id=old_teacher and class_id=old_class and subject_id=old_subject;
  end if;
  return public.get_academic_configuration();
end $function$;

revoke all on function public.save_academic_entity(text,jsonb) from public;
revoke all on function public.archive_academic_entity(text,uuid,text) from public;
revoke all on function public.save_grading_scale(jsonb) from public;
revoke all on function public.archive_grading_scale(uuid,text) from public;
revoke all on function public.save_assessment_scheme(jsonb) from public;
revoke all on function public.save_class_subject_assignments_batch(jsonb) from public;

revoke all on function public.save_academic_entity(text,jsonb) from edusentia_worker_runtime;
revoke all on function public.archive_academic_entity(text,uuid,text) from edusentia_worker_runtime;
revoke all on function public.save_grading_scale(jsonb) from edusentia_worker_runtime;
revoke all on function public.archive_grading_scale(uuid,text) from edusentia_worker_runtime;
revoke all on function public.save_assessment_scheme(jsonb) from edusentia_worker_runtime;
revoke all on function public.save_class_subject_assignments_batch(jsonb) from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0037_certified_academic_configuration_mutations')
on conflict do nothing;

update app.release_identity
set schema_version='0037'
where edition='Edusentia Enterprise Neon Edition';

commit;
