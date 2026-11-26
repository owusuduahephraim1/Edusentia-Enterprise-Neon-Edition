-- Certificates: on first batch for a certificate type, initialize the built-in design
-- when no active template exists; never replace an existing active uploaded design.
-- Follows the certified create_certificate_batch workflow and preserves recipient,
-- authorization, eligibility, approval, snapshots and audit behavior.

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
  if v_template.id is null then
    -- The certified PDF renderer supports a built-in design when storage_path is empty.
    -- Keep every existing active uploaded or configured template unchanged.
    -- Serialize same-type fallback creation to avoid duplicate active defaults.
    perform pg_advisory_xact_lock(hashtext('edusentia:certificate:default:' || v_certificate_type));
    select ct.* into v_template
    from public.certificate_templates ct
    where ct.certificate_type=v_certificate_type and ct.active
    order by ct.updated_at desc
    limit 1;
    if v_template.id is null then
      insert into public.certificate_templates
        (certificate_type,name,title,subtitle,statement_template,footer_text,
         primary_colour,accent_colour,active,storage_path,original_name,mime_type,file_size,checksum)
      values
        (v_certificate_type,
         case v_certificate_type
           when 'student_promotion' then 'Official built-in promotion certificate'
           when 'jhs_completion' then 'Official built-in completion certificate'
           else 'Official built-in teacher recognition certificate' end,
         case v_certificate_type
           when 'student_promotion' then 'Certificate of Promotion'
           when 'jhs_completion' then 'Certificate of Completion'
           else 'Certificate of Recognition' end,
         case v_certificate_type
           when 'student_promotion' then 'Academic Advancement'
           when 'jhs_completion' then 'Junior High School'
           else 'Excellence in Education' end,
         case v_certificate_type
           when 'student_promotion' then 'This is to certify that {{recipient_name}} has successfully completed {{current_class}} and is promoted to {{next_class}} for the {{academic_year}} academic year.'
           when 'jhs_completion' then 'This is to certify that {{recipient_name}} has successfully completed {{current_class}} in the {{academic_year}} academic year.'
           else 'This certificate is presented to {{recipient_name}} in recognition of {{award_category}}. {{custom_citation}}' end,
         'Issued by the school administration',
         '#0a2f73','#f1b51c',true,'','','',0,'')
      returning * into v_template;
    end if;
  end if;
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

