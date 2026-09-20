-- Certified source commit: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source blob SHA: 85f7d1b444396208c876d6209152cf079784a0b1
-- Neon adaptation: SQL ACL targets only. Business authorization logic is unchanged.

-- Edusentia Enterprise r40 — Student Management / Enrolment Lifecycle hardening
--
-- Enforces the same System Administrator + AAL2 boundary for student identity,
-- import, promotion, archive/restore and identifier-management operations.
-- No student, enrolment, guardian, report or portal data is created by this migration.

create or replace function public.is_records_manager()
returns boolean
language sql
stable
security definer
set search_path to 'public','extensions'
as $$
  select public.has_role(array['system_admin']) and public.current_aal()='aal2'
$$;

create or replace function public.can_manage_student(target_student_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path to 'public','extensions'
as $$
  select public.is_records_manager()
$$;

-- Defense in depth for every student-row mutation reached through a trusted
-- SECURITY DEFINER workflow. Service-role restore/user-management operations
-- remain available, while browser-authenticated changes require System Admin AAL2.
create or replace function public.enforce_student_management_aal2_write()
returns trigger
language plpgsql
security definer
set search_path to 'public','extensions'
as $$
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
$$;

drop trigger if exists students_sensitive_access_guard on public.students;
create trigger students_sensitive_access_guard
before insert or update or delete on public.students
for each row execute function public.enforce_student_management_aal2_write();

-- Identifier issuance consumes a persistent sequence, so it is sensitive even
-- before the resulting identifier is attached to a record.
create or replace function public.generate_school_identifier(identifier_kind text)
returns text
language plpgsql
security definer
set search_path to 'public','extensions'
as $$
declare
  kind text:=lower(btrim(coalesce(identifier_kind,'')));
  root text;
  serial_number bigint;
  candidate text;
begin
  if auth.uid() is null or not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  if kind not in ('student','teacher','principal','headteacher') then
    raise exception 'Identifier type is invalid' using errcode='22023';
  end if;

  select upper(btrim(s.identifier_root)) into root
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;

  if coalesce(root,'') !~ '^[A-Z]{3}[0-9]{6}$' then
    raise exception 'The school identifier root is not configured correctly';
  end if;

  if kind='student' then
    loop
      serial_number:=nextval('public.student_identifier_seq');
      if serial_number>999999 then raise exception 'The student identifier sequence is exhausted'; end if;
      candidate:=root||'-STU-'||lpad(serial_number::text,6,'0');
      exit when not exists(select 1 from public.students s where lower(s.admission_no::text)=lower(candidate));
    end loop;
  else
    loop
      serial_number:=nextval('public.staff_identifier_seq');
      if serial_number>999999 then raise exception 'The staff identifier sequence is exhausted'; end if;
      candidate:=root||'-STF-'||lpad(serial_number::text,6,'0');
      exit when not exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(candidate))
        and not exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(candidate));
    end loop;
  end if;

  return candidate;
end
$$;

-- CSV preview/validation exposes student admission data and feeds the protected
-- import workflow, so keep it inside the same sensitive-access boundary.
create or replace function public.validate_student_import(rows jsonb, target_academic_year_id uuid, target_class_id uuid, filename text default '')
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $$
declare item jsonb;rowno integer:=0;valid_rows jsonb:='[]'::jsonb;errors jsonb:='[]'::jsonb;admission text;gender_text text;
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can validate student imports' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if jsonb_typeof(coalesce(rows,'[]'::jsonb))<>'array' then raise exception 'Rows must be a list'; end if;
  for item in select value from jsonb_array_elements(rows) loop
    rowno:=rowno+1; admission:=btrim(coalesce(item->>'admission_no','')); gender_text:=initcap(lower(btrim(coalesce(item->>'gender',''))));
    if admission='' or btrim(coalesce(item->>'first_name',''))='' or btrim(coalesce(item->>'last_name',''))='' then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Admission number, first name, and last name are required','payload',item));
    elsif gender_text not in ('Male','Female','Other') then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Gender must be Male, Female, or Other','payload',item));
    elsif exists(select 1 from public.students where lower(admission_no::text)=lower(admission) and deleted_at is null) then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Admission number already exists','payload',item));
    elsif exists(select 1 from jsonb_array_elements(rows) x where lower(btrim(x->>'admission_no'))=lower(admission) group by lower(btrim(x->>'admission_no')) having count(*)>1) then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Duplicate admission number in import file','payload',item));
    else
      valid_rows:=valid_rows||jsonb_build_array(item||jsonb_build_object('academic_year_id',target_academic_year_id,'class_id',target_class_id,'gender',gender_text));
    end if;
  end loop;
  return jsonb_build_object('filename',filename,'total',jsonb_array_length(rows),'valid_count',jsonb_array_length(valid_rows),'invalid_count',jsonb_array_length(errors),'valid_rows',valid_rows,'errors',errors);
end
$$;

-- Promotion cutoff changes can recalculate Term 3 promotion outcomes and can
-- create/withdraw automatic target-year enrolments through the internal helper.
create or replace function public.save_promotion_cutoff(target_score integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $$
declare
  item record;
  processed integer:=0;
  settings_id uuid;
  sync_enrollment boolean;
begin
  if not public.is_records_manager() then
    raise exception 'Only the System Administrator with MFA verification can change the promotion cutoff score' using errcode='42501';
  end if;
  if target_score is null or target_score<40 or target_score>60 then
    raise exception 'Promotion cutoff score must be between 40 and 60';
  end if;
  perform set_config('app.change_reason','Term 3 automatic-promotion cutoff updated',true);
  select s.id into settings_id
  from public.school_settings s
  order by s.created_at,s.id
  limit 1
  for update;
  if settings_id is null then
    insert into public.school_settings(promotion_cutoff_score,updated_at)
    values(target_score,now())
    returning id into settings_id;
  else
    update public.school_settings
    set promotion_cutoff_score=target_score,
        updated_at=now()
    where id=settings_id;
  end if;
  for item in
    select r.id,r.status::text as status
    from public.student_reports r
    join public.terms t on t.id=r.term_id
    where r.deleted_at is null
      and t.deleted_at is null
      and public.is_term_three(t.sequence,t.name::text)
  loop
    select item.status in ('approved','published') or exists(
      select 1 from public.enrollments e
      where e.promotion_source_report_id=item.id
        and e.enrollment_origin='automatic_promotion'
        and e.deleted_at is null
    ) into sync_enrollment;
    perform public.refresh_report_promotion(item.id,sync_enrollment);
    processed:=processed+1;
  end loop;
  return jsonb_build_object(
    'promotion_cutoff_score',target_score,
    'reports_recalculated',processed,
    'settings_id',settings_id
  );
end
$$;

revoke all on function public.enforce_student_management_aal2_write() from public,edusentia_worker_runtime;
revoke all on function public.save_promotion_cutoff(integer) from public;
grant execute on function public.validate_student_import(jsonb,uuid,uuid,text) to edusentia_worker_runtime;
grant execute on function public.generate_school_identifier(text) to edusentia_worker_runtime;
grant execute on function public.save_promotion_cutoff(integer) to edusentia_worker_runtime;


insert into app.schema_migrations(version)
values ('0034_certified_student_management_hardening')
on conflict do nothing;

update app.release_identity
set schema_version='0034'
where edition='Edusentia Enterprise Neon Edition';
