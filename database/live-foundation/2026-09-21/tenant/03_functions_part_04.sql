-- Edusentia tenant foundation: public functions
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

SET check_function_bodies=off;

CREATE OR REPLACE FUNCTION public.save_teacher(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=public.safe_uuid(payload->>'id');profileid uuid:=public.safe_uuid(payload->>'profile_id');staff text:=upper(btrim(coalesce(payload->>'staff_no','')));emis text:=upper(btrim(coalesce(payload->>'emis_code','')));current_updated timestamptz;expected_updated timestamptz:=public.safe_timestamptz(payload->>'updated_at');joined date:=public.safe_date(payload->>'date_joined');dob date:=public.safe_date(payload->>'date_of_birth');employment text:=coalesce(nullif(btrim(payload->>'employment_status'),''),'active');gender_value text:=coalesce(nullif(btrim(payload->>'gender'),''),'Other');qualification_value text:=btrim(coalesce(payload->>'qualification',''));linked_role text;affected integer;legacy_qualification text;
begin
  if auth.uid() is null or not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501';end if;
  if btrim(coalesce(payload->>'id',''))<>'' and tid is null then raise exception 'Teacher record identifier is invalid';end if;if btrim(coalesce(payload->>'profile_id',''))<>'' and profileid is null then raise exception 'Linked user account is invalid';end if;
  if btrim(coalesce(payload->>'date_joined',''))<>'' and joined is null then raise exception 'Date joined is invalid';end if;if btrim(coalesce(payload->>'date_of_birth',''))<>'' and dob is null then raise exception 'Date of birth is invalid';end if;
  if btrim(coalesce(payload->>'first_name',''))='' or btrim(coalesce(payload->>'last_name',''))='' then raise exception 'First name and last name are required';end if;if gender_value not in ('Male','Female','Other') then raise exception 'Gender selection is invalid';end if;
  if btrim(coalesce(payload->>'email',''))<>'' and payload->>'email' !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Teacher email address is invalid';end if;if employment not in ('active','leave','suspended','resigned','retired') then raise exception 'Employment status is invalid';end if;
  if joined>current_date then raise exception 'Date joined cannot be in the future';end if;if dob>current_date then raise exception 'Date of birth cannot be in the future';end if;if joined is not null and dob is not null and joined<=dob then raise exception 'Date joined must be after date of birth';end if;
  if tid is not null then select updated_at,qualification into current_updated,legacy_qualification from public.teachers where id=tid and deleted_at is null for update;if not found then raise exception 'Teacher record not found';end if;if expected_updated is not null and current_updated is distinct from expected_updated then raise exception 'Teacher record changed by another user' using errcode='40001';end if;end if;
  if qualification_value<>'' and qualification_value not in ('PhD','MSc Degree','Bachelor Degree','HND','Diploma','SHS') and (tid is null or qualification_value is distinct from legacy_qualification) then raise exception 'Qualification must be selected from the approved qualification list';end if;
  if tid is null and (staff='' or exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff))) then staff:=public.generate_school_identifier('teacher');end if;if staff='' then staff:=public.generate_school_identifier('teacher');end if;
  if exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff) and (tid is null or t.id<>tid)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff)) then raise exception 'Staff number already exists';end if;
  if emis<>'' and exists(select 1 from public.teachers t where t.deleted_at is null and lower(coalesce(t.emis_code::text,''))=lower(emis) and (tid is null or t.id<>tid)) then raise exception 'EMIS code already exists';end if;
  if profileid is not null then select public.current_app_role_for(p.role) into linked_role from public.profiles p where p.id=profileid and p.active;if linked_role is null then raise exception 'Selected user account is unavailable';end if;if linked_role not in ('class_teacher','subject_teacher') then raise exception 'Selected user account does not have a teacher role';end if;if exists(select 1 from public.teachers t where t.profile_id=profileid and t.deleted_at is null and (tid is null or t.id<>tid)) or exists(select 1 from public.headteachers h where h.profile_id=profileid and h.deleted_at is null) then raise exception 'This user account is already linked to another staff record';end if;end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Teacher record update'),true);
  if tid is null then
    insert into public.teachers(profile_id,staff_no,emis_code,first_name,middle_name,last_name,gender,date_of_birth,phone,email,address,qualification,specialization,date_joined,employment_status,notes,active,created_by,updated_at)
    values(profileid,staff,nullif(emis,'')::citext,btrim(payload->>'first_name'),btrim(coalesce(payload->>'middle_name','')),btrim(payload->>'last_name'),gender_value,dob,btrim(coalesce(payload->>'phone','')),nullif(btrim(coalesce(payload->>'email','')),'')::citext,btrim(coalesce(payload->>'address','')),qualification_value,btrim(coalesce(payload->>'specialization','')),joined,employment,btrim(coalesce(payload->>'notes','')),public.safe_boolean(payload->>'active',true),auth.uid(),now()) returning id into tid;
  else
    update public.teachers set profile_id=profileid,staff_no=staff,emis_code=nullif(emis,'')::citext,first_name=btrim(payload->>'first_name'),middle_name=btrim(coalesce(payload->>'middle_name','')),last_name=btrim(payload->>'last_name'),gender=gender_value,date_of_birth=dob,phone=btrim(coalesce(payload->>'phone','')),email=nullif(btrim(coalesce(payload->>'email','')),'')::citext,address=btrim(coalesce(payload->>'address','')),qualification=qualification_value,specialization=btrim(coalesce(payload->>'specialization','')),date_joined=joined,employment_status=employment,notes=btrim(coalesce(payload->>'notes','')),active=public.safe_boolean(payload->>'active',true),updated_at=now() where id=tid and deleted_at is null;
    get diagnostics affected=row_count;if affected<>1 then raise exception 'Teacher record was not updated';end if;
  end if;
  return public.get_teacher_record(tid);
exception when unique_violation then raise exception 'Staff number, EMIS code, or linked user account is already in use';
end$function$

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
end $function$

CREATE OR REPLACE FUNCTION public.school_restore_apply_table(target_job uuid, target_table text, target_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare staged integer; expected_stage_count constant integer:=54; current_stage_count integer; begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; staged:=public.school_restore_stage_table(target_job,target_table,target_rows); if target_table='import_errors' then select count(*) into current_stage_count from public.school_restore_stage_tables where job_id=target_job; if current_stage_count<>expected_stage_count then raise exception 'r29 legacy restore staging incomplete: expected % tables, found %',expected_stage_count,current_stage_count; end if; delete from public.id_card_deletion_tombstones where true; perform public.school_restore_commit_staged(target_job); end if; return staged; end$function$

CREATE OR REPLACE FUNCTION public.school_restore_begin(target_filename text, target_path text, target_checksum text, target_size bigint, target_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_id uuid;
begin
 if auth.role() <> 'service_role' then raise exception 'service role required'; end if;
 insert into public.school_restore_jobs(source_filename,import_path,package_checksum,package_size,initiated_by)
 values(left(coalesce(target_filename,''),300),left(coalesce(target_path,''),1000),lower(coalesce(target_checksum,'')),greatest(coalesce(target_size,0),0),target_actor)
 returning id into v_id;
 return v_id;
end$function$

CREATE OR REPLACE FUNCTION public.school_restore_clear_operational_data(target_job uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; delete from public.school_restore_stage_tables where job_id=target_job; update public.school_restore_jobs set status='restoring',restored_table_counts='{}'::jsonb, verification_notes='r29 atomic restore staging initialized; production database has not been cleared.', updated_at=now() where id=target_job; end$function$

CREATE OR REPLACE FUNCTION public.school_restore_commit_staged(target_job uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare insert_tables constant text[]:=array[ 'school_settings','profiles','id_card_settings','id_card_deletion_tombstones','teachers','headteachers','academic_years','terms','classes','subjects','class_subjects','class_timetable_entries','school_prospectuses','school_prospectus_sections','school_prospectus_items','school_prospectus_revisions','user_class_access','students','student_guardians','guardian_links','enrollments','student_id_cards','id_card_events','staff_id_cards','staff_id_card_events','class_attendance_registers','student_attendance_entries','grading_scales','assessment_schemes','assessment_components','student_reports','subject_scores','subject_results','assessment_score_entries','emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls','student_lifecycle_events','transcript_issuances','certificate_templates','teacher_award_categories','certificate_batches','certificates','certificate_events','report_workflow_events','report_revisions','report_publications','report_correction_requests','report_correction_events','report_card_templates','notifications','notification_outbox','import_batches','import_errors' ]; clear_tables constant text[]:=array[ 'school_prospectus_revisions','school_prospectus_items','school_prospectus_sections','school_prospectuses','staff_id_card_events','staff_id_cards','id_card_events','student_id_cards','class_timetable_entries','id_card_settings','certificate_events','certificates','certificate_batches','teacher_award_categories','report_card_templates','certificate_templates','transcript_issuances','report_publications','report_revisions','report_workflow_events','report_correction_events','report_correction_requests','assessment_score_entries','subject_results','subject_scores','student_reports','student_attendance_entries','class_attendance_registers','emergency_academic_delegation_events','emergency_academic_delegations','academic_period_controls','student_lifecycle_events','guardian_links','student_guardians','enrollments','students','user_class_access','class_subjects','assessment_components','assessment_schemes','grading_scales','subjects','classes','terms','academic_years','headteachers','teachers','notifications','notification_outbox','import_errors','import_batches' ]; t text; target_rows jsonb; cols text; sels text; expected integer; actual integer; matched integer; staged_count integer; restored jsonb:='{}'::jsonb; max_card_sequence bigint; protected_identifier_root text; protected_user_email_domain text; protected_verification_base_url text; protected_report_number_prefix text; begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; perform pg_advisory_xact_lock(hashtext('rce-school-restore-r29')); select s.identifier_root,s.user_email_domain,s.verification_base_url,s.report_number_prefix into protected_identifier_root,protected_user_email_domain,protected_verification_base_url,protected_report_number_prefix from public.school_settings s order by s.created_at,s.id limit 1; if protected_identifier_root is null or protected_user_email_domain is null or protected_verification_base_url is null or protected_report_number_prefix is null then raise exception 'Canonical tenant identity is incomplete; restoration is blocked'; end if; if not exists(select 1 from public.school_restore_jobs where id=target_job) then raise exception 'restore job not found'; end if; select count(*) into staged_count from public.school_restore_stage_tables where job_id=target_job and table_name=any(insert_tables); if staged_count<>array_length(insert_tables,1) then raise exception 'restore staging is incomplete: expected % tables, found %',array_length(insert_tables,1),staged_count; end if; perform set_config('app.audit_suppress','on',true); perform set_config('app.report_write','on',true); perform set_config('app.restore_mode','on',true); perform set_config('app.change_reason','Full school restoration r29',true); update public.school_restore_jobs set status='restoring',restored_table_counts='{}'::jsonb,updated_at=now() where id=target_job; foreach t in array clear_tables loop if to_regclass('public.'||t) is not null then execute format('alter table public.%I disable trigger user',t); execute format('delete from public.%I where true',t); execute format('alter table public.%I enable trigger user',t); end if; end loop; foreach t in array insert_tables loop select s.rows,s.row_count into target_rows,expected from public.school_restore_stage_tables s where s.job_id=target_job and s.table_name=t; if target_rows is null or jsonb_typeof(target_rows)<>'array' then raise exception 'restore staging is missing or invalid for %',t; end if; execute format('alter table public.%I disable trigger user',t); if t='school_settings' then if expected>0 then update public.school_settings s set school_name=coalesce(x.school_name,s.school_name),motto=coalesce(x.motto,s.motto),address=coalesce(x.address,s.address),phone=coalesce(x.phone,s.phone),email=coalesce(x.email,s.email),website=coalesce(x.website,s.website),logo_url=coalesce(x.logo_url,s.logo_url),report_title=coalesce(x.report_title,s.report_title),report_footer=coalesce(x.report_footer,s.report_footer),head_name=coalesce(x.head_name,s.head_name),timezone=coalesce(x.timezone,s.timezone),locale=coalesce(x.locale,s.locale),report_number_prefix=protected_report_number_prefix,primary_colour=coalesce(x.primary_colour,s.primary_colour),accent_colour=coalesce(x.accent_colour,s.accent_colour),verification_base_url=protected_verification_base_url,created_at=coalesce(x.created_at,s.created_at),updated_at=coalesce(x.updated_at,s.updated_at),report_body_font=coalesce(x.report_body_font,s.report_body_font),report_body_font_size=coalesce(x.report_body_font_size,s.report_body_font_size),promotion_cutoff_score=coalesce(x.promotion_cutoff_score,s.promotion_cutoff_score),backup_retention_days=coalesce(x.backup_retention_days,s.backup_retention_days),backup_minimum_copies=coalesce(x.backup_minimum_copies,s.backup_minimum_copies),user_email_domain=protected_user_email_domain,certificate_footer_text=coalesce(x.certificate_footer_text,s.certificate_footer_text) from jsonb_to_record(target_rows->0) as x(school_name text,motto text,address text,phone text,email text,website text,logo_url text,report_title text,report_footer text,head_name text,timezone text,locale text,report_number_prefix text,primary_colour text,accent_colour text,verification_base_url text,created_at timestamptz,updated_at timestamptz,report_body_font text,report_body_font_size numeric,promotion_cutoff_score smallint,backup_retention_days integer,backup_minimum_copies integer,user_email_domain text,certificate_footer_text text) where s.id=(select ss.id from public.school_settings ss order by ss.created_at asc,ss.id asc limit 1); end if; else select string_agg(format('%I',a.attname),',' order by a.attnum),string_agg(format('r.%I',a.attname),',' order by a.attnum) into cols,sels from pg_attribute a where a.attrelid=to_regclass('public.'||t) and a.attnum>0 and not a.attisdropped and a.attgenerated='' and a.attidentity<>'a' and not(t='enrollments' and a.attname='promotion_source_report_id'); if cols is null or sels is null then raise exception 'restore column inventory unavailable for %',t; end if; if t='student_id_cards' then execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) r where not exists(select 1 from public.id_card_deletion_tombstones d where d.card_kind=''student'' and (d.card_number=r.card_number or d.verification_token=r.verification_token)) on conflict do nothing',t,cols,sels,t) using target_rows; elsif t='staff_id_cards' then execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) r where not exists(select 1 from public.id_card_deletion_tombstones d where d.card_kind=''staff'' and (d.card_number=r.card_number or d.verification_token=r.verification_token)) on conflict do nothing',t,cols,sels,t) using target_rows; else execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) r on conflict do nothing',t,cols,sels,t) using target_rows; end if; end if; execute format('alter table public.%I enable trigger user',t); if t='profiles' then execute 'select count(*) from public.profiles p join jsonb_to_recordset($1) x(id uuid) on p.id=x.id' into matched using target_rows; if matched<>expected then raise exception 'restore identity verification failed for profiles: expected % staged IDs, matched %',expected,matched; end if; select count(*) into actual from public.profiles; elsif t='id_card_deletion_tombstones' then execute 'select count(*) from jsonb_to_recordset($1) x(card_kind text,card_number text,verification_token uuid) where exists(select 1 from public.id_card_deletion_tombstones d where (d.card_kind=x.card_kind and d.card_number=x.card_number) or d.verification_token=x.verification_token)' into matched using target_rows; if matched<>expected then raise exception 'restore tombstone verification failed: expected % staged tombstones, matched %',expected,matched; end if; select count(*) into actual from public.id_card_deletion_tombstones; else execute format('select count(*) from public.%I',t) into actual; if actual<>expected then raise exception 'restore row-count verification failed for %: expected %, found %',t,expected,actual; end if; end if; restored:=jsonb_set(restored,array[t],to_jsonb(actual),true); end loop; select rows into target_rows from public.school_restore_stage_tables where job_id=target_job and table_name='enrollments'; execute 'alter table public.enrollments disable trigger user'; update public.enrollments e set promotion_source_report_id=x.promotion_source_report_id from jsonb_to_recordset(target_rows) as x(id uuid,promotion_source_report_id uuid) where e.id=x.id and e.promotion_source_report_id is distinct from x.promotion_source_report_id; execute 'alter table public.enrollments enable trigger user'; select rows into target_rows from public.school_restore_stage_tables where job_id=target_job and table_name='school_settings'; if jsonb_array_length(target_rows)>0 then execute 'alter table public.school_settings disable trigger user'; update public.school_settings s set certificate_completion_class_id=x.certificate_completion_class_id from jsonb_to_record(target_rows->0) as x(certificate_completion_class_id uuid) where s.id=(select ss.id from public.school_settings ss order by ss.created_at asc,ss.id asc limit 1); execute 'alter table public.school_settings enable trigger user'; end if; select row_count into expected from public.school_restore_stage_tables where job_id=target_job and table_name='enrollments'; select count(*) into actual from public.enrollments; if actual<>expected then raise exception 'restore row-count verification failed for enrollments after deferred link repair'; end if; select max(substring(card_number from '-([0-9]+)$')::bigint) into max_card_sequence from public.student_id_cards where card_number~'-[0-9]+$'; if max_card_sequence is not null then perform setval('public.student_id_card_number_seq',greatest(max_card_sequence,1),true); end if; select max(substring(card_number from '-([0-9]+)$')::bigint) into max_card_sequence from public.staff_id_cards where card_number~'-[0-9]+$'; if max_card_sequence is not null then perform setval('public.staff_id_card_number_seq',greatest(max_card_sequence,1),true); end if; if not exists(select 1 from public.school_settings s where s.identifier_root is not distinct from protected_identifier_root and s.user_email_domain is not distinct from protected_user_email_domain and s.verification_base_url is not distinct from protected_verification_base_url and s.report_number_prefix is not distinct from protected_report_number_prefix) then raise exception 'Canonical tenant identity changed during restoration; database restore rolled back'; end if; update public.school_restore_jobs set restored_table_counts=restored,verification_notes='r29 atomic database restore committed with foreign-key enforcement and staged row-count verification.',updated_at=now() where id=target_job; delete from public.school_restore_stage_tables where job_id=target_job; return jsonb_build_object('status','database_restored','restored_table_counts',restored); end$function$

CREATE OR REPLACE FUNCTION public.school_restore_complete(target_job uuid, target_expected jsonb, target_storage jsonb, target_auth_expected integer, target_auth_reconciled integer, target_backup_key text, target_schema text, target_school_name text, target_school_code text, target_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; update public.school_restore_jobs set status='completed',expected_table_counts=coalesce(target_expected,'{}'::jsonb),expected_storage_counts=coalesce(target_storage,'{}'::jsonb),restored_storage_counts=coalesce(target_storage,'{}'::jsonb), auth_users_expected=greatest(coalesce(target_auth_expected,0),0),auth_users_reconciled=greatest(coalesce(target_auth_reconciled,0),0), backup_key=left(coalesce(target_backup_key,''),200),source_schema_version=left(coalesce(target_schema,''),50),source_school_name=left(coalesce(target_school_name,''),300),source_school_code=left(coalesce(target_school_code,''),100), verification_notes=left(coalesce(target_notes,''),8000),error_message='',completed_at=now(),updated_at=now() where id=target_job; end$function$

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
end $function$

CREATE OR REPLACE FUNCTION public.school_restore_set_status(target_job uuid, target_status text, target_error text DEFAULT ''::text, target_notes text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; update public.school_restore_jobs set status=target_status,error_message=left(coalesce(target_error,''),4000),verification_notes=left(coalesce(target_notes,''),8000), started_at=case when target_status in ('validating','restoring') then coalesce(started_at,now()) else started_at end, completed_at=case when target_status in ('completed','failed','cancelled') then now() else completed_at end, updated_at=now() where id=target_job; if target_status in ('completed','failed','cancelled') then delete from public.school_restore_stage_tables where job_id=target_job; end if; end$function$

CREATE OR REPLACE FUNCTION public.school_restore_stage_table(target_job uuid, target_table text, target_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare allowed constant text[]:=array[ 'school_settings','profiles','id_card_settings','id_card_deletion_tombstones','teachers','headteachers', 'academic_years','terms','classes','subjects','class_subjects','class_timetable_entries', 'school_prospectuses','school_prospectus_sections','school_prospectus_items','school_prospectus_revisions', 'user_class_access','students','student_guardians','guardian_links','enrollments','student_id_cards','id_card_events', 'staff_id_cards','staff_id_card_events','class_attendance_registers','student_attendance_entries','grading_scales', 'assessment_schemes','assessment_components','student_reports','subject_scores','subject_results','assessment_score_entries', 'emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls', 'report_correction_requests','report_correction_events','student_lifecycle_events','transcript_issuances', 'certificate_templates','teacher_award_categories','certificate_batches','certificates','certificate_events', 'report_workflow_events','report_revisions','report_publications','report_card_templates','notifications','notification_outbox', 'import_batches','import_errors' ]; staged integer; begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; if not(target_table=any(allowed)) then raise exception 'table is not restorable: %',target_table; end if; if jsonb_typeof(target_rows)<>'array' then raise exception 'rows must be an array'; end if; if not exists(select 1 from public.school_restore_jobs where id=target_job) then raise exception 'restore job not found'; end if; staged:=jsonb_array_length(target_rows); insert into public.school_restore_stage_tables(job_id,table_name,rows,row_count,staged_at) values(target_job,target_table,target_rows,staged,now()) on conflict(job_id,table_name) do update set rows=excluded.rows,row_count=excluded.row_count,staged_at=excluded.staged_at; return staged; end$function$

CREATE OR REPLACE FUNCTION public.search_students(search_text text DEFAULT ''::text, target_class_id uuid DEFAULT NULL::uuid, target_status student_status DEFAULT NULL::student_status, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
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
      select s.id,s.admission_no,s.first_name,s.middle_name,s.last_name,s.gender,s.date_of_birth,
        s.photo_url,s.status,s.updated_at,e.id enrollment_id,e.class_id,e.academic_year_id,e.roll_number,
        c.name class_name,y.name academic_year_name,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) display_name
      from public.students s
      left join lateral (
        select en.* from public.enrollments en
        join public.academic_years ay on ay.id=en.academic_year_id and ay.deleted_at is null
        where en.student_id=s.id and en.deleted_at is null
        order by en.active desc,
          coalesce(ay.start_date,ay.end_date,en.created_at::date) desc,
          ay.name::text desc,en.created_at desc limit 1
      ) e on true
      left join public.classes c on c.id=e.class_id
      left join public.academic_years y on y.id=e.academic_year_id
      where s.deleted_at is null
        and (public.current_app_role() in ('system_admin','principal') or (e.id is not null and public.can_access_class(e.class_id,false)))
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or s.status=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x)-'display_name' order by lower(x.display_name),x.admission_no::text) from (
        select * from matching order by lower(display_name),admission_no::text limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),
      'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end $function$

CREATE OR REPLACE FUNCTION public.search_students_v5(search_text text DEFAULT ''::text, target_class_id uuid DEFAULT NULL::uuid, target_status student_status DEFAULT NULL::student_status, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
declare limit_value integer:=least(greatest(page_size,1),100);
begin
  if archive_filter not in ('active','archived','all') then archive_filter:='active'; end if;
  if archive_filter<>'active' and public.current_app_role() not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return (
    with matching as (
      select s.id,s.admission_no,s.first_name,s.middle_name,s.last_name,s.gender,s.date_of_birth,
        s.photo_url,s.status,s.updated_at,s.deleted_at,(s.deleted_at is not null) archived,
        e.id enrollment_id,e.class_id,e.academic_year_id,e.roll_number,
        c.name class_name,y.name academic_year_name,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) display_name
      from public.students s
      left join lateral (
        select en.* from public.enrollments en
        join public.academic_years ay on ay.id=en.academic_year_id and ay.deleted_at is null
        where en.student_id=s.id and en.deleted_at is null
        order by en.active desc,
          coalesce(ay.start_date,ay.end_date,en.created_at::date) desc,
          ay.name::text desc,en.created_at desc limit 1
      ) e on true
      left join public.classes c on c.id=e.class_id
      left join public.academic_years y on y.id=e.academic_year_id
      where (public.current_app_role() in ('system_admin','principal') or (e.id is not null and public.can_access_class(e.class_id,false)))
        and (archive_filter='all'
          or (archive_filter='active' and s.deleted_at is null)
          or (archive_filter='archived' and s.deleted_at is not null))
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or s.status=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x)-'display_name' order by lower(x.display_name),x.admission_no::text) from (
        select * from matching order by lower(display_name),admission_no::text limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end
$function$

CREATE OR REPLACE FUNCTION public.set_active_period(target_academic_year_id uuid, target_term_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  y_start date;
  y_end date;
  t_start date;
  t_end date;
begin
  if not public.is_academic_manager() then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select y.start_date,y.end_date,t.start_date,t.end_date
  into y_start,y_end,t_start,t_end
  from public.academic_years y
  join public.terms t on t.academic_year_id=y.id
  where y.id=target_academic_year_id and y.deleted_at is null
    and t.id=target_term_id and t.deleted_at is null;

  if not found then
    raise exception 'The selected term does not belong to the selected academic year';
  end if;

  if y_start is null or current_date<y_start or (y_end is not null and current_date>y_end)
     or t_start is null or current_date<t_start or (t_end is not null and current_date>t_end) then
    raise exception 'Academic periods are calendar-controlled and cannot be activated before or after their configured dates';
  end if;

  perform set_config('app.change_reason','Calendar-controlled academic period synchronization',true);
  perform public.sync_current_academic_year_status();
  return public.get_bootstrap_data();
end
$function$

CREATE OR REPLACE FUNCTION public.set_headteacher_photo(target_headteacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare h public.headteachers%rowtype;clean_path text:=btrim(coalesce(target_photo_url,''));
begin
  select * into h from public.headteachers where id=target_headteacher_id and deleted_at is null for update;
  if h.id is null then raise exception 'Principal record not found';end if;
  if not(public.is_system_admin() or h.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  perform public.require_sensitive_access();if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';end if;
  if expected_updated_at is not null and h.updated_at is distinct from expected_updated_at then raise exception 'Principal record changed by another user' using errcode='40001';end if;
  if clean_path<>'' and split_part(clean_path,'/',1)<>target_headteacher_id::text then raise exception 'Principal photograph path is invalid';end if;
  update public.headteachers set photo_url=clean_path,updated_at=now() where id=target_headteacher_id returning * into h;
  return jsonb_build_object('headteacher',to_jsonb(h));
end$function$

CREATE OR REPLACE FUNCTION public.set_my_headteacher_signature(target_signature_path text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare hid uuid;current_updated timestamptz;clean_path text:=btrim(coalesce(target_signature_path,''));
begin
  if auth.uid() is null or public.current_app_role()<>'principal' then raise exception 'Access denied' using errcode='42501'; end if;
  select h.id,h.updated_at into hid,current_updated from public.headteachers h where h.profile_id=auth.uid() and h.deleted_at is null and h.active order by h.updated_at desc limit 1 for update;
  if hid is null then raise exception 'No active Principal record is linked to this account'; end if;
  if expected_updated_at is not null and current_updated is distinct from expected_updated_at then raise exception 'Principal record changed. Reload and try again.' using errcode='40001'; end if;
  if clean_path<>'' and clean_path not like auth.uid()::text||'/%' then raise exception 'Signature storage path is invalid'; end if;
  perform set_config('app.change_reason',case when clean_path='' then 'Principal signature removed' else 'Principal signature updated' end,true);
  update public.headteachers set signature_path=clean_path,signature_updated_at=case when clean_path='' then null else now() end,updated_at=now() where id=hid;
  return public.get_my_headteacher_signature();
end $function$

CREATE OR REPLACE FUNCTION public.set_school_logo_reference(target_logo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_catalog', 'extensions'
AS $function$ declare clean text:=btrim(coalesce(target_logo_url,'')); sid uuid; object_path text; begin if not public.is_system_admin() then raise exception 'Only the School System Administrator can change the official school logo' using errcode='42501';end if; perform public.require_sensitive_access(); if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit school logo changes' using errcode='42501';end if; select id into sid from public.school_settings order by created_at,id limit 1 for update; if sid is null then raise exception 'School identity is unavailable';end if; if clean='assets/school-logo.png' then null; elsif clean like 'school-branding:%' then object_path:=substr(clean,length('school-branding:')+1); if object_path='' or object_path not like ('official/'||sid::text||'/%') or object_path !~ '^official/[0-9a-f-]{36}/logo-[A-Za-z0-9._-]+\.png$' then raise exception 'Invalid school logo reference';end if; if not exists(select 1 from storage.objects where bucket_id='school-branding' and name=object_path) then raise exception 'The uploaded school logo was not found in protected Storage';end if; else raise exception 'Invalid school logo reference';end if; update public.school_settings set logo_url=clean,updated_at=now() where id=sid; return jsonb_build_object('saved',true,'logo_url',clean,'message','Official school logo saved for future school documents.'); end$function$

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
end $function$

CREATE OR REPLACE FUNCTION public.set_teacher_photo(target_teacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare t public.teachers%rowtype;clean_path text:=btrim(coalesce(target_photo_url,''));
begin
  select * into t from public.teachers where id=target_teacher_id and deleted_at is null for update;
  if t.id is null then raise exception 'Teacher record not found';end if;
  if not(public.is_system_admin() or t.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  perform public.require_sensitive_access();if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';end if;
  if expected_updated_at is not null and t.updated_at is distinct from expected_updated_at then raise exception 'Teacher record changed by another user' using errcode='40001';end if;
  if clean_path<>'' and split_part(clean_path,'/',1)<>target_teacher_id::text then raise exception 'Teacher photograph path is invalid';end if;
  update public.teachers set photo_url=clean_path,updated_at=now() where id=target_teacher_id returning * into t;
  return public.get_teacher_record(target_teacher_id);
end$function$

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin new.updated_at=now(); return new; end $function$

CREATE OR REPLACE FUNCTION public.staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select public.staff_id_card_photo_reference_count(target_staff_id,target_photo_path)>0
$function$

CREATE OR REPLACE FUNCTION public.staff_id_card_photo_reference_count(target_staff_id uuid, target_photo_path text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select case when auth.uid() is not null and (
   public.is_system_admin()
   or exists(select 1 from public.teachers t where t.id=target_staff_id and t.profile_id=auth.uid() and t.deleted_at is null)
   or exists(select 1 from public.headteachers h where h.id=target_staff_id and h.profile_id=auth.uid() and h.deleted_at is null)
 ) then (select count(*) from public.staff_id_cards c where btrim(coalesce(target_photo_path,''))<>'' and c.snapshot#>>'{staff,id}'=target_staff_id::text and c.snapshot#>>'{staff,photo_url}'=target_photo_path) else 0 end
$function$

CREATE OR REPLACE FUNCTION public.student_services_actor_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_app_role text;
  v_roles jsonb;
  v_license jsonb;
begin
  select public.current_app_role_for(p.role) into v_app_role from public.profiles p where p.id=auth.uid() and p.active;
  if v_app_role is null then raise exception 'Active profile required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(a.service_role order by a.service_role),'[]'::jsonb) into v_roles
  from public.student_services_staff_access a where a.profile_id=auth.uid() and a.active;
  v_license:=public.license_access_for_actor(auth.uid());
  return jsonb_build_object('app_role',v_app_role,'service_roles',v_roles,'license',v_license,'aal',public.current_aal());
end $function$

CREATE OR REPLACE FUNCTION public.student_services_block_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  if current_setting('app.student_services_allow_hard_delete',true)='on' then return old; end if;
  raise exception 'Student Services history cannot be hard deleted; use lifecycle status instead' using errcode='42501';
end $function$

CREATE OR REPLACE FUNCTION public.student_services_has_access(target_domain text, target_action text DEFAULT 'read'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_app_role text;
  v_license jsonb;
  v_roles text[];
  v_allowed boolean:=false;
begin
  select public.current_app_role_for(p.role) into v_app_role from public.profiles p where p.id=auth.uid() and p.active;
  if v_app_role is null then return false; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if coalesce((v_license->>'read_allowed')::boolean,false)=false then return false; end if;
  if target_action not in ('read','write','approve','publish','enroll','configure','summary') then return false; end if;
  if target_action<>'read' and target_action<>'summary' and coalesce((v_license->>'write_allowed')::boolean,false)=false then return false; end if;

  if v_app_role='system_admin' then return true; end if;
  if v_app_role='principal' then
    return case target_domain
      when 'admissions' then target_action in ('read','approve','summary')
      when 'discipline' then target_action in ('read','approve','summary')
      when 'welfare' then target_action in ('read','approve','summary')
      when 'health' then target_action in ('summary')
      when 'communications' then target_action in ('read','approve','summary')
      when 'hostel' then target_action in ('read','approve','summary')
      when 'alumni' then target_action in ('read','summary')
      else false end;
  end if;

  select coalesce(array_agg(a.service_role),array[]::text[]) into v_roles
  from public.student_services_staff_access a where a.profile_id=auth.uid() and a.active;

  if target_domain='admissions' and 'admissions_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','approve','enroll','summary'); end if;
  if target_domain='discipline' and 'welfare_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','approve','summary'); end if;
  if target_domain='welfare' and 'welfare_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','approve','summary'); end if;
  if target_domain='health' and 'clinic_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','summary'); end if;
  if target_domain='communications' and 'communications_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','publish','summary'); end if;
  if target_domain='hostel' and ('hostel_manager'=any(v_roles) or 'house_parent'=any(v_roles)) then
    v_allowed:=target_action in ('read','write','summary') or (target_action='configure' and 'hostel_manager'=any(v_roles));
  end if;
  if target_domain='alumni' and 'alumni_officer'=any(v_roles) then v_allowed:=target_action in ('read','write','summary'); end if;
  return v_allowed;
end $function$

CREATE OR REPLACE FUNCTION public.student_services_reference_data(target_domain text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if target_domain not in ('admissions','discipline','welfare','health','communications','hostel','alumni') then
    raise exception 'Invalid Student Services domain';
  end if;
  perform public.student_services_require_access(target_domain,'read');
  return jsonb_build_object(
    'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',y.id,'name',y.name,'is_active',y.is_active) order by y.start_date desc) from public.academic_years y where y.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'level_order',c.level_order) order by c.level_order,c.name) from public.classes c where c.deleted_at is null and c.active),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.student_services_require_access(target_domain text, target_action text DEFAULT 'read'::text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if not public.student_services_has_access(target_domain,target_action) then raise exception 'Student Services access denied' using errcode='42501'; end if;
  if public.current_aal()<>'aal2' then raise exception 'Multi-factor authentication is required' using errcode='42501'; end if;
end $function$

CREATE OR REPLACE FUNCTION public.student_services_save_staff_access(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;v_profile uuid;v_hr uuid;v_role text;v_active boolean;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage Student Services appointments' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  v_id:=nullif(payload->>'id','')::uuid; v_hr:=(payload->>'hr_staff_id')::uuid; v_role:=payload->>'service_role'; v_active:=coalesce((payload->>'active')::boolean,true);
  if v_role not in ('admissions_officer','welfare_officer','clinic_officer','communications_officer','hostel_manager','house_parent','alumni_officer') then raise exception 'Invalid Student Services role'; end if;
  select h.profile_id into v_profile from public.hr_staff_members h where h.id=v_hr and h.active and h.deleted_at is null;
  if v_profile is null then raise exception 'Selected staff member has no active user profile'; end if;
  if v_id is null then
    insert into public.student_services_staff_access(profile_id,hr_staff_id,service_role,active,appointed_by)
    values(v_profile,v_hr,v_role,v_active,auth.uid())
    on conflict(profile_id,service_role) do update set hr_staff_id=excluded.hr_staff_id,active=excluded.active,appointed_by=auth.uid(),appointed_at=now(),updated_at=now()
    returning id into v_id;
  else
    update public.student_services_staff_access set profile_id=v_profile,hr_staff_id=v_hr,service_role=v_role,active=v_active,appointed_by=auth.uid(),updated_at=now() where id=v_id returning id into v_id;
  end if;
  if v_active then update public.profiles set mfa_required=true where id=v_profile; end if;
  insert into public.student_services_events(domain,event_type,entity_type,entity_id,actor_id,details)
  values('communications','staff_access_saved','student_services_staff_access',v_id,auth.uid(),jsonb_build_object('service_role',v_role,'active',v_active));
  return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.student_services_session()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare c jsonb;
begin
  c:=public.student_services_actor_context();
  return c||jsonb_build_object('capabilities',jsonb_build_object(
    'admissions_read',public.student_services_has_access('admissions','read'),
    'admissions_write',public.student_services_has_access('admissions','write'),
    'admissions_approve',public.student_services_has_access('admissions','approve'),
    'admissions_enroll',public.student_services_has_access('admissions','enroll'),
    'discipline_read',public.student_services_has_access('discipline','read'),
    'discipline_write',public.student_services_has_access('discipline','write'),
    'welfare_read',public.student_services_has_access('welfare','read'),
    'welfare_write',public.student_services_has_access('welfare','write'),
    'health_read',public.student_services_has_access('health','read'),
    'health_write',public.student_services_has_access('health','write'),
    'health_summary',public.student_services_has_access('health','summary'),
    'communications_read',public.student_services_has_access('communications','read'),
    'communications_write',public.student_services_has_access('communications','write'),
    'communications_publish',public.student_services_has_access('communications','publish'),
    'hostel_read',public.student_services_has_access('hostel','read'),
    'hostel_write',public.student_services_has_access('hostel','write'),
    'hostel_configure',public.student_services_has_access('hostel','configure'),
    'alumni_read',public.student_services_has_access('alumni','read'),
    'alumni_write',public.student_services_has_access('alumni','write'),
    'manage_staff',(c->>'app_role')='system_admin'
  ));
end $function$

CREATE OR REPLACE FUNCTION public.student_services_staff_candidates(search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage Student Services appointments' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name) from (
    select h.id hr_staff_id,h.profile_id,h.staff_no,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,h.department,h.job_title
    from public.hr_staff_members h
    where h.active and h.deleted_at is null and h.profile_id is not null
      and (search_text is null or concat_ws(' ',h.first_name,h.middle_name,h.last_name,h.staff_no,h.department,h.job_title) ilike '%'||search_text||'%')
    order by full_name limit 100
  ) q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.student_services_staff_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage Student Services appointments' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name,q.service_role) from (
    select a.id,a.profile_id,a.hr_staff_id,a.service_role,a.active,a.appointed_at,h.staff_no,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,h.department,h.job_title
    from public.student_services_staff_access a join public.hr_staff_members h on h.id=a.hr_staff_id
  ) q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.student_services_student_picker(target_domain text, search_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 if target_domain not in ('discipline','welfare','health','hostel','alumni','communications') then raise exception 'Invalid Student Services domain'; end if;
 perform public.student_services_require_access(target_domain,'read');
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.full_name) from (
  select s.id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) full_name,s.gender,s.status,
   (select c.name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=s.id and e.active and e.deleted_at is null order by e.created_at desc limit 1) class_name
  from public.students s where s.deleted_at is null and s.status='active'
   and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
  order by full_name limit 150
 )q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.student_services_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin new.updated_at=now(); return new; end $function$

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
end $function$

CREATE OR REPLACE FUNCTION public.supersede_transcripts_on_publication_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  target_student uuid;
  issuance_row record;
  change_reason text;
begin
  select e.student_id into target_student
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.id=coalesce(new.report_id,old.report_id);

  if target_student is null then return coalesce(new,old); end if;

  if tg_op='INSERT' then
    change_reason:='A new published academic result changed the current transcript source.';
  elsif old.revoked_at is null and new.revoked_at is not null then
    change_reason:='A published academic result was withdrawn or opened for correction.';
  elsif new.revision_id is distinct from old.revision_id or new.published_at is distinct from old.published_at then
    change_reason:='A published academic result was republished with a new official revision.';
  else
    return new;
  end if;

  for issuance_row in
    update public.transcript_issuances
      set status='superseded'
    where student_id=target_student and status='valid'
    returning id,transcript_number,student_id
  loop
    insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
    values(
      auth.uid(),'transcript_issuances',issuance_row.id,'AUTO_SUPERSEDE',
      jsonb_build_object('transcript_number',issuance_row.transcript_number,'status','valid'),
      jsonb_build_object('transcript_number',issuance_row.transcript_number,'status','superseded'),
      change_reason
    );
  end loop;

  return coalesce(new,old);
end
$function$

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
    and counts.days_school_opened>0;
  get diagnostics affected=row_count;
  return affected;
end $function$

CREATE OR REPLACE FUNCTION public.sync_class_teacher_responsibility_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if tg_op in ('UPDATE','DELETE') and old.class_teacher_id is not null then
    perform public.sync_teacher_responsibility_access(old.class_teacher_id);
  end if;
  if tg_op in ('INSERT','UPDATE') and new.class_teacher_id is not null
     and (tg_op='INSERT' or new.class_teacher_id is distinct from old.class_teacher_id
          or new.active is distinct from old.active
          or new.deleted_at is distinct from old.deleted_at) then
    perform public.sync_teacher_responsibility_access(new.class_teacher_id);
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.sync_current_academic_year_status()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  current_year_id uuid;
  current_term_id uuid;
begin
  select y.id into current_year_id
  from public.academic_years y
  where y.deleted_at is null
    and y.start_date is not null
    and y.start_date<=current_date
    and (y.end_date is null or y.end_date>=current_date)
  order by y.start_date desc,y.created_at desc
  limit 1;

  if current_year_id is not null then
    select t.id into current_term_id
    from public.terms t
    where t.academic_year_id=current_year_id
      and t.deleted_at is null
      and t.start_date is not null
      and t.start_date<=current_date
      and (t.end_date is null or t.end_date>=current_date)
    order by t.start_date desc,t.sequence desc
    limit 1;
  end if;

  update public.terms t
  set is_active=false,updated_at=now()
  where t.deleted_at is null and t.is_active
    and t.id is distinct from current_term_id;

  update public.academic_years y
  set is_active=false,updated_at=now()
  where y.deleted_at is null and y.is_active
    and y.id is distinct from current_year_id;

  if current_year_id is not null then
    update public.academic_years y
    set is_active=true,updated_at=now()
    where y.id=current_year_id and y.deleted_at is null and not y.is_active;
  end if;

  if current_term_id is not null then
    update public.terms t
    set is_active=true,updated_at=now()
    where t.id=current_term_id and t.deleted_at is null and not t.is_active;
  end if;

  return current_year_id;
end
$function$

CREATE OR REPLACE FUNCTION public.sync_license_feature_rpc_privileges()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r record;signature text;enabled boolean;
begin
  if coalesce(auth.role(),'') not in ('','service_role','supabase_admin') and not public.is_platform_super_admin() then raise exception 'Platform licence authority required' using errcode='42501';end if;
  for r in select * from (values
    (array['attendance']::text[],array['get_class_attendance_register','list_my_attendance_classes','save_class_attendance']::text[]),
    (array['assessment']::text[],array['archive_grading_scale','get_report_grading_guide','resolve_grading_guide','save_assessment_scheme','save_grading_scale']::text[]),
    (array['report_cards']::text[],array['bulk_generate_missing_reports','delete_report_card_permanently','get_current_principal_signature','get_my_headteacher_signature','get_report_correction_console','get_report_editor','get_report_headteacher_signature','get_report_revisions','list_my_children_reports','list_report_cards_v6','list_report_pdf_paths','register_report_pdf','report_position','report_promotion_evaluation','report_subject_positions','request_report_correction','review_report_correction','save_promotion_cutoff','save_report_card','save_report_comments','set_my_headteacher_signature','transition_report_status']::text[]),
    (array['academic_history']::text[],array['delete_transcript_issuance_permanently','get_student_academic_history','issue_student_transcript','record_student_lifecycle_event','revoke_student_transcript']::text[]),
    (array['certificates']::text[],array['create_certificate_batch','create_certificate_replacement_draft','delete_certificate_permanently','get_certificate_batch','get_certificate_console','issue_certificate_batch','list_certificate_eligible_recipients','register_certificate_pdf','review_certificate_batch','revoke_certificate','save_certificate_settings','save_teacher_award_category','submit_certificate_batch']::text[]),
    (array['report_cards','uploaded_templates']::text[],array['list_report_card_templates','remove_report_card_template','save_report_card_template']::text[]),
    (array['certificates','uploaded_templates']::text[],array['remove_certificate_template_file','save_certificate_template']::text[]),
    (array['bulk_workflow']::text[],array['bulk_import_students','bulk_promote_all_classes','bulk_promote_class','validate_student_import']::text[]),
    (array['bulk_workflow','assessment']::text[],array['bulk_import_scores','validate_score_import']::text[]),
    (array['bulk_workflow','report_cards']::text[],array['bulk_transition_class_reports']::text[]),
    (array['manual_backup']::text[],array['backup_dashboard','get_recovery_console','mark_backup_offsite_copy','save_backup_policy']::text[]),
    (array['notifications']::text[],array['delete_notifications','list_notifications','mark_notifications_read']::text[]),
    (array['notifications','report_cards']::text[],array['queue_incomplete_report_notifications','run_academic_alerts']::text[]),
    (array['analytics']::text[],array['academic_analytics']::text[])
  ) v(features,names) loop
    select bool_and(public.license_feature_enabled(f)) into enabled from unnest(r.features) f;
    for signature in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=any(r.names) loop
      execute format('revoke execute on function %s from public, anon, authenticated',signature);
      if coalesce(enabled,false) then execute format('grant execute on function %s to authenticated',signature);end if;
    end loop;
  end loop;
end $function$

CREATE OR REPLACE FUNCTION public.sync_pending_promotions_when_year_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.apply_pending_term3_promotions();
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.sync_report_next_term_reopening_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare configured_date date;
begin
  select t.next_term_begins into configured_date
  from public.terms t where t.id=new.term_id;
  if tg_op='INSERT' then
    new.next_term_reopening_date:=configured_date;
  elsif new.term_id is distinct from old.term_id
     or (new.status is distinct from old.status
         and new.status in ('submitted','class_reviewed','approved','published')) then
    new.next_term_reopening_date:=configured_date;
  end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.sync_report_promotion_from_subject_result()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  target_id uuid;
  target_status text;
  sync_target_enrollment boolean:=false;
begin
  if tg_op='DELETE' then target_id:=old.report_id; else target_id:=new.report_id; end if;
  select r.status::text into target_status
  from public.student_reports r
  where r.id=target_id and r.deleted_at is null;
  if target_status is not null then
    select target_status in ('approved','published') or exists(
      select 1 from public.enrollments e
      where e.promotion_source_report_id=target_id
        and e.enrollment_origin='automatic_promotion'
        and e.deleted_at is null
    ) into sync_target_enrollment;
    perform public.refresh_report_promotion(target_id,sync_target_enrollment);
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.sync_subject_teacher_responsibility_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if tg_op in ('UPDATE','DELETE') and old.teacher_id is not null then
    perform public.sync_teacher_responsibility_access(old.teacher_id);
  end if;
  if tg_op in ('INSERT','UPDATE') and new.teacher_id is not null
     and (tg_op='INSERT' or new.teacher_id is distinct from old.teacher_id
          or new.class_id is distinct from old.class_id
          or new.subject_id is distinct from old.subject_id
          or new.active is distinct from old.active) then
    perform public.sync_teacher_responsibility_access(new.teacher_id);
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.sync_teacher_record_class_links()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  old_profile_id uuid;
  new_profile_id uuid;
begin
  old_profile_id:=case when tg_op='INSERT' then null else old.profile_id end;
  new_profile_id:=case
    when tg_op='DELETE' then null
    when new.active and new.deleted_at is null and new.employment_status='active' then new.profile_id
    else null
  end;
  if tg_op='DELETE'
     or not new.active
     or new.deleted_at is not null
     or new.employment_status<>'active' then
    update public.classes
    set class_teacher_record_id=null,
        class_teacher_id=null,
        updated_at=now()
    where class_teacher_record_id=case when tg_op='DELETE' then old.id else new.id end;
  else
    update public.classes
    set class_teacher_id=new_profile_id,
        updated_at=now()
    where class_teacher_record_id=new.id
      and class_teacher_id is distinct from new_profile_id;
  end if;
  if old_profile_id is not null then
    perform public.sync_teacher_responsibility_access(old_profile_id);
  end if;
  if new_profile_id is not null and new_profile_id is distinct from old_profile_id then
    perform public.sync_teacher_responsibility_access(new_profile_id);
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.sync_teacher_responsibility_access(target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  class_scope_count integer:=0;
  subject_scope_count integer:=0;
  target_role text;
begin
  if target_user_id is null then
    return jsonb_build_object('user_id',null,'class_scopes',0,'subject_scopes',0);
  end if;
  select public.current_app_role_for(p.role)
  into target_role
  from public.profiles p
  where p.id=target_user_id and p.active;
  delete from public.user_class_access
  where user_id=target_user_id;
  if target_role not in ('class_teacher','subject_teacher') then
    return jsonb_build_object('user_id',target_user_id,'class_scopes',0,'subject_scopes',0);
  end if;
  insert into public.user_class_access(user_id,class_id,subject_id,access_level)
  select target_user_id,c.id,null,'edit'
  from public.classes c
  where c.class_teacher_id=target_user_id
    and c.active
    and c.deleted_at is null;
  get diagnostics class_scope_count=row_count;
  insert into public.user_class_access(user_id,class_id,subject_id,access_level)
  select target_user_id,cs.class_id,cs.subject_id,'score'
  from public.class_subjects cs
  join public.classes c on c.id=cs.class_id
  join public.subjects s on s.id=cs.subject_id
  where cs.teacher_id=target_user_id
    and cs.active
    and c.active and c.deleted_at is null
    and s.active and s.deleted_at is null
  on conflict do nothing;
  get diagnostics subject_scope_count=row_count;
  return jsonb_build_object(
    'user_id',target_user_id,
    'class_scopes',class_scope_count,
    'subject_scopes',subject_scope_count
  );
end $function$

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
$function$

CREATE OR REPLACE FUNCTION public.tenant_runtime_release_identity()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'release_code',s.runtime_release_code,
    'manifest_sha256',s.runtime_release_manifest_sha256,
    'foundation_version',s.runtime_foundation_version,
    'source_schema_version',s.runtime_release_source_schema_version,
    'migration_count',s.runtime_release_migration_count,
    'edge_function_count',s.runtime_release_edge_function_count,
    'applied_at',s.runtime_release_applied_at
  )
  from public.school_settings s
  order by s.created_at,s.id
  limit 1
$function$

CREATE OR REPLACE FUNCTION public.term_calendar_status_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if pg_trigger_depth()>1 then return null; end if;
  perform public.sync_current_academic_year_status();
  return null;
end
$function$

CREATE OR REPLACE FUNCTION public.term_control_snapshot(target_term_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select jsonb_build_object(
    'term_id',t.id,'term_name',t.name,'academic_year_id',t.academic_year_id,
    'score_entry_deadline',c.score_entry_deadline,'attendance_deadline',c.attendance_deadline,
    'report_submission_deadline',c.report_submission_deadline,
    'principal_approval_deadline',c.principal_approval_deadline,
    'publication_deadline',c.publication_deadline,
    'scores_locked',coalesce(c.scores_locked,false) or (c.score_entry_deadline is not null and now()>c.score_entry_deadline),
    'attendance_locked',coalesce(c.attendance_locked,false) or (c.attendance_deadline is not null and now()>c.attendance_deadline),
    'reports_locked',coalesce(c.reports_locked,false),
    'submission_overdue',c.report_submission_deadline is not null and now()>c.report_submission_deadline,
    'approval_overdue',c.principal_approval_deadline is not null and now()>c.principal_approval_deadline,
    'publication_overdue',c.publication_deadline is not null and now()>c.publication_deadline,
    'lock_reason',coalesce(c.lock_reason,''),'locked_at',c.locked_at
  )
  from public.terms t left join public.academic_period_controls c on c.term_id=t.id
  where t.id=target_term_id and t.deleted_at is null
$function$

CREATE OR REPLACE FUNCTION public.term_phase_writable(target_term_id uuid, target_phase text, target_report_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb;
begin
  if not public.license_write_allowed() then return false; end if;
  s:=public.term_control_snapshot(target_term_id);
  if s is null then return false; end if;
  if target_report_id is not null and public.has_approved_report_correction(target_report_id) then return true; end if;
  if target_phase='scores' then return not coalesce((s->>'scores_locked')::boolean,false) and ((s->>'score_entry_deadline') is null or (s->>'score_entry_deadline')::timestamptz>=now()); end if;
  if target_phase='attendance' then return not coalesce((s->>'attendance_locked')::boolean,false) and ((s->>'attendance_deadline') is null or (s->>'attendance_deadline')::timestamptz>=now()); end if;
  if target_phase='reports' then return not coalesce((s->>'reports_locked')::boolean,false) and ((s->>'report_submission_deadline') is null or (s->>'report_submission_deadline')::timestamptz>=now()); end if;
  return false;
end $function$

CREATE OR REPLACE FUNCTION public.tertiary_grade_for_score(p_score numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r record;
  match_count integer;
begin
  if p_score is null or p_score < 0 or p_score > 100 then
    raise exception 'Score must be between 0 and 100' using errcode='22023';
  end if;
  select count(*) into match_count
  from public.tertiary_grading_scale g
  where g.active=true and p_score between g.minimum_score and g.maximum_score;
  if match_count <> 1 then
    raise exception 'Tertiary grading scale must contain exactly one active band for score %', p_score using errcode='55000';
  end if;
  select g.letter_grade,g.grade_point,g.pass
  into strict r
  from public.tertiary_grading_scale g
  where g.active=true and p_score between g.minimum_score and g.maximum_score
  order by g.display_order,g.minimum_score desc
  limit 1;
  return jsonb_build_object('letter_grade',r.letter_grade,'grade_point',r.grade_point,'pass',r.pass);
end
$function$

CREATE OR REPLACE FUNCTION public.tertiary_grading_scale_readiness()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
with ordered as (
  select id,minimum_score,maximum_score,
         lag(maximum_score) over(order by minimum_score,maximum_score) as previous_maximum
  from public.tertiary_grading_scale
  where active=true
), summary as (
  select count(*)::int as band_count,
         min(minimum_score) as minimum_covered,
         max(maximum_score) as maximum_covered,
         count(*) filter(where previous_maximum is not null and minimum_score <= previous_maximum)::int as overlap_count,
         count(*) filter(where previous_maximum is not null and minimum_score > previous_maximum + 0.01)::int as gap_count
  from ordered
)
select jsonb_build_object(
  'ready',band_count>0 and minimum_covered=0 and maximum_covered=100 and overlap_count=0 and gap_count=0,
  'band_count',band_count,
  'minimum_covered',minimum_covered,
  'maximum_covered',maximum_covered,
  'overlap_count',overlap_count,
  'gap_count',gap_count
) from summary
$function$

CREATE OR REPLACE FUNCTION public.tertiary_programme_completion_readiness(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
with enrollment as (
  select pe.programme_id,p.name as programme_name
  from public.student_programme_enrollments pe
  join public.academic_programmes p on p.id=pe.programme_id
  where pe.student_id=p_student_id and pe.status in ('active','completed') and p.institution_scope='tertiary'
  order by pe.created_at desc limit 1
), totals as (
  select coalesce(sum(r.credit_hours) filter(where r.result_status='published'),0)::numeric as attempted_credits,
         coalesce(sum(r.credit_hours) filter(where r.result_status='published' and r.passed),0)::numeric as earned_credits,
         public.tertiary_student_cgpa(p_student_id) as cgpa
  from public.tertiary_course_results r
  join public.tertiary_course_registrations cr on cr.id=r.course_registration_id
  where cr.student_id=p_student_id
), requirements as (
  select e.programme_id,e.programme_name,coalesce(pr.minimum_credits,0) as minimum_credits,coalesce(pr.minimum_cgpa,0) as minimum_cgpa
  from enrollment e left join public.tertiary_programme_requirements pr on pr.programme_id=e.programme_id
), classification as (
  select dc.name
  from requirements req cross join totals t
  join public.tertiary_degree_classifications dc on dc.active=true and (dc.programme_id is null or dc.programme_id=req.programme_id)
  where t.cgpa between dc.minimum_cgpa and dc.maximum_cgpa
  order by (dc.programme_id is not null) desc,dc.display_order,dc.minimum_cgpa desc limit 1
)
select case when not public.can_read_tertiary_student_record(p_student_id) then jsonb_build_object('allowed',false)
else jsonb_build_object(
  'allowed',true,'programme_id',req.programme_id,'programme_name',req.programme_name,
  'attempted_credits',t.attempted_credits,'earned_credits',t.earned_credits,'cgpa',t.cgpa,
  'minimum_credits',req.minimum_credits,'minimum_cgpa',req.minimum_cgpa,
  'credit_requirement_met',t.earned_credits>=req.minimum_credits,
  'cgpa_requirement_met',coalesce(t.cgpa,0)>=req.minimum_cgpa,
  'completion_ready',t.earned_credits>=req.minimum_credits and coalesce(t.cgpa,0)>=req.minimum_cgpa,
  'classification',(select name from classification)
) end
from requirements req cross join totals t
$function$

CREATE OR REPLACE FUNCTION public.tertiary_save_course_result(p_course_registration_id uuid, p_continuous_assessment_score numeric DEFAULT NULL::numeric, p_examination_score numeric DEFAULT NULL::numeric, p_total_score numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  total_value numeric;
  grade jsonb;
  credit_value numeric;
  result_id uuid;
  current_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not public.can_enter_tertiary_course_result(p_course_registration_id) then raise exception 'Access denied' using errcode='42501'; end if;
  if p_continuous_assessment_score is not null and p_continuous_assessment_score < 0 then raise exception 'Continuous assessment score cannot be negative' using errcode='22023'; end if;
  if p_examination_score is not null and p_examination_score < 0 then raise exception 'Examination score cannot be negative' using errcode='22023'; end if;
  total_value:=coalesce(p_total_score,coalesce(p_continuous_assessment_score,0)+coalesce(p_examination_score,0));
  if total_value < 0 or total_value > 100 then raise exception 'Total score must be between 0 and 100' using errcode='22023'; end if;

  select coalesce(pc.credit_hours_override,c.credit_hours)
  into credit_value
  from public.tertiary_course_registrations cr
  join public.tertiary_course_offerings o on o.id=cr.course_offering_id
  join public.tertiary_courses c on c.id=o.course_id
  left join public.student_programme_enrollments pe on pe.id=cr.programme_enrollment_id
  left join lateral (
    select x.credit_hours_override
    from public.tertiary_programme_courses x
    where x.programme_id=pe.programme_id and x.course_id=o.course_id
      and (x.level_id is null or x.level_id=coalesce(o.level_id,pe.level_id))
    order by (x.level_id is not null) desc,x.period_sequence nulls last
    limit 1
  ) pc on true
  where cr.id=p_course_registration_id;
  if credit_value is null then raise exception 'Course registration not found or course credit is unavailable' using errcode='P0002'; end if;

  grade:=public.tertiary_grade_for_score(total_value);
  select r.id,r.result_status into result_id,current_status
  from public.tertiary_course_results r where r.course_registration_id=p_course_registration_id;
  if current_status in ('approved','published') then raise exception 'Approved or published results cannot be edited directly' using errcode='55000'; end if;

  insert into public.tertiary_course_results(
    course_registration_id,continuous_assessment_score,examination_score,total_score,letter_grade,grade_point,credit_hours,passed,result_status,updated_at
  ) values (
    p_course_registration_id,p_continuous_assessment_score,p_examination_score,total_value,grade->>'letter_grade',(grade->>'grade_point')::numeric,credit_value,(grade->>'pass')::boolean,'draft',now()
  )
  on conflict(course_registration_id) do update set
    continuous_assessment_score=excluded.continuous_assessment_score,
    examination_score=excluded.examination_score,
    total_score=excluded.total_score,
    letter_grade=excluded.letter_grade,
    grade_point=excluded.grade_point,
    credit_hours=excluded.credit_hours,
    passed=excluded.passed,
    result_status='draft',
    approved_by=null,approved_at=null,published_at=null,updated_at=now()
  returning id into result_id;
  return result_id;
end
$function$

CREATE OR REPLACE FUNCTION public.tertiary_set_result_status(p_result_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_status text; target_status text:=lower(btrim(coalesce(p_status,'')));
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not public.can_manage_academic_model() then raise exception 'Access denied' using errcode='42501'; end if;
  if target_status not in ('approved','published','withdrawn','draft') then raise exception 'Invalid result status' using errcode='22023'; end if;
  select result_status into strict current_status from public.tertiary_course_results where id=p_result_id for update;
  if target_status='approved' and current_status<>'draft' then raise exception 'Only draft results can be approved' using errcode='55000'; end if;
  if target_status='published' and current_status<>'approved' then raise exception 'Only approved results can be published' using errcode='55000'; end if;
  if target_status='draft' and current_status<>'withdrawn' then raise exception 'Only withdrawn results can be returned to draft' using errcode='55000'; end if;
  if target_status='withdrawn' and current_status not in ('approved','published') then raise exception 'Only approved or published results can be withdrawn' using errcode='55000'; end if;
  update public.tertiary_course_results set
    result_status=target_status,
    approved_by=case when target_status='approved' then auth.uid() when target_status='draft' then null else approved_by end,
    approved_at=case when target_status='approved' then now() when target_status='draft' then null else approved_at end,
    published_at=case when target_status='published' then now() when target_status in ('draft','withdrawn') then null else published_at end,
    updated_at=now()
  where id=p_result_id;
end
$function$

CREATE OR REPLACE FUNCTION public.tertiary_student_cgpa(p_student_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.tertiary_student_gpa(p_student_id,null,null)
$function$

CREATE OR REPLACE FUNCTION public.tertiary_student_gpa(p_student_id uuid, p_academic_year_id uuid DEFAULT NULL::uuid, p_term_id uuid DEFAULT NULL::uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when not public.can_read_tertiary_student_record(p_student_id) then null
    else (
      select round(sum(r.quality_points) / nullif(sum(r.credit_hours),0),2)
      from public.tertiary_course_results r
      join public.tertiary_course_registrations cr on cr.id=r.course_registration_id
      join public.tertiary_course_offerings o on o.id=cr.course_offering_id
      where cr.student_id=p_student_id
        and r.result_status='published'
        and (p_academic_year_id is null or o.academic_year_id=p_academic_year_id)
        and (p_term_id is null or o.term_id=p_term_id)
    )
  end
$function$

CREATE OR REPLACE FUNCTION public.tertiary_transcript_snapshot(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
with student_row as (
  select s.id,s.admission_no,s.first_name,s.middle_name,s.last_name from public.students s where s.id=p_student_id
), programme as (
  select p.code,p.name,p.award_type,l.name as level_name
  from public.student_programme_enrollments pe
  join public.academic_programmes p on p.id=pe.programme_id
  left join public.academic_levels l on l.id=pe.level_id
  where pe.student_id=p_student_id order by pe.created_at desc limit 1
), records as (
  select ay.name as academic_year,t.name as academic_period,c.code as course_code,c.name as course_name,
         r.credit_hours,r.total_score,r.letter_grade,r.grade_point,r.quality_points,r.passed,r.published_at
  from public.tertiary_course_results r
  join public.tertiary_course_registrations cr on cr.id=r.course_registration_id
  join public.tertiary_course_offerings o on o.id=cr.course_offering_id
  join public.tertiary_courses c on c.id=o.course_id
  join public.academic_years ay on ay.id=o.academic_year_id
  join public.terms t on t.id=o.term_id
  where cr.student_id=p_student_id and r.result_status='published'
  order by ay.start_date,t.sequence,c.code
), identity as (
  select school_name,tenant_code,institution_type,academic_period_model from public.school_settings order by created_at limit 1
)
select case when not public.can_read_tertiary_student_record(p_student_id) then jsonb_build_object('allowed',false)
else jsonb_build_object(
  'allowed',true,'generated_at',now(),'institution',(select to_jsonb(identity) from identity),
  'student',(select jsonb_build_object('id',id,'admission_no',admission_no,'name',concat_ws(' ',first_name,middle_name,last_name)) from student_row),
  'programme',(select to_jsonb(programme) from programme),
  'records',coalesce((select jsonb_agg(to_jsonb(records)) from records),'[]'::jsonb),
  'progress',public.tertiary_programme_completion_readiness(p_student_id)
) end
$function$

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
$function$

CREATE OR REPLACE FUNCTION public.transport_actor_access()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r text; a public.transport_staff_access; h public.hr_staff_members;
begin
  if auth.uid() is null then return jsonb_build_object('authorized',false,'role',null,'hr_staff_id',null,'capabilities','[]'::jsonb); end if;
  r:=public.current_app_role()::text;
  if r='system_admin' then
    return jsonb_build_object('authorized',true,'role','system_admin','hr_staff_id',null,'capabilities',jsonb_build_array('view','fleet_write','route_write','assign_students','trip_operate','maintenance_write','incident_write','manage_access','manage_settings'));
  elsif r='principal' then
    return jsonb_build_object('authorized',true,'role','principal','hr_staff_id',null,'capabilities',jsonb_build_array('view'));
  end if;
  select * into a from public.transport_staff_access where profile_id=auth.uid() and active;
  if a.id is null then return jsonb_build_object('authorized',false,'role',null,'hr_staff_id',null,'capabilities','[]'::jsonb); end if;
  select * into h from public.hr_staff_members where id=a.hr_staff_id and active and deleted_at is null;
  if h.id is null then return jsonb_build_object('authorized',false,'role',null,'hr_staff_id',a.hr_staff_id,'capabilities','[]'::jsonb); end if;
  if a.transport_role='manager' then
    return jsonb_build_object('authorized',true,'role','manager','hr_staff_id',a.hr_staff_id,'capabilities',jsonb_build_array('view','fleet_write','route_write','assign_students','trip_operate','maintenance_write','incident_write','manage_settings'));
  elsif a.transport_role='dispatcher' then
    return jsonb_build_object('authorized',true,'role','dispatcher','hr_staff_id',a.hr_staff_id,'capabilities',jsonb_build_array('view','assign_students','trip_operate','incident_write'));
  elsif a.transport_role='driver' then
    return jsonb_build_object('authorized',true,'role','driver','hr_staff_id',a.hr_staff_id,'capabilities',jsonb_build_array('view','trip_operate','incident_write'));
  elsif a.transport_role='attendant' then
    return jsonb_build_object('authorized',true,'role','attendant','hr_staff_id',a.hr_staff_id,'capabilities',jsonb_build_array('view','trip_operate','incident_write'));
  else
    return jsonb_build_object('authorized',true,'role','maintenance','hr_staff_id',a.hr_staff_id,'capabilities',jsonb_build_array('view','maintenance_write','incident_write'));
  end if;
end $function$

CREATE OR REPLACE FUNCTION public.transport_add_incident(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare i public.transport_incidents; tid uuid:=nullif(payload->>'trip_id','')::uuid; vid uuid:=nullif(payload->>'vehicle_id','')::uuid; did uuid:=nullif(payload->>'driver_id','')::uuid;
begin
  perform public.transport_require_access(true,'incident_write');
  if tid is not null then select vehicle_id,driver_id into vid,did from public.transport_trips where id=tid; end if;
  insert into public.transport_incidents(trip_id,vehicle_id,driver_id,student_id,occurred_at,incident_type,severity,description,action_taken,status,created_by) values(tid,vid,did,nullif(payload->>'student_id','')::uuid,coalesce(nullif(payload->>'occurred_at','')::timestamptz,now()),payload->>'incident_type',coalesce(nullif(payload->>'severity',''),'low'),trim(payload->>'description'),nullif(payload->>'action_taken',''),'open',auth.uid()) returning * into i;
  return to_jsonb(i);
end $function$

CREATE OR REPLACE FUNCTION public.transport_add_maintenance(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare m public.transport_maintenance_records; vid uuid:=nullif(payload->>'vehicle_id','')::uuid;
begin
  perform public.transport_require_access(true,'maintenance_write'); if not exists(select 1 from public.transport_vehicles where id=vid and deleted_at is null) then raise exception 'Vehicle not found' using errcode='23503'; end if;
  insert into public.transport_maintenance_records(vehicle_id,maintenance_type,service_date,odometer_km,vendor,cost,next_due_date,description,created_by) values(vid,payload->>'maintenance_type',coalesce(nullif(payload->>'service_date','')::date,current_date),nullif(payload->>'odometer_km','')::numeric,nullif(payload->>'vendor',''),nullif(payload->>'cost','')::numeric,nullif(payload->>'next_due_date','')::date,trim(payload->>'description'),auth.uid()) returning * into m;
  update public.transport_vehicles set odometer_km=case when m.odometer_km is null then odometer_km else greatest(coalesce(odometer_km,0),m.odometer_km) end,next_service_date=coalesce(m.next_due_date,next_service_date) where id=vid;
  return to_jsonb(m);
end $function$

CREATE OR REPLACE FUNCTION public.transport_assign_student(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a public.transport_student_assignments; sid uuid:=nullif(payload->>'student_id','')::uuid; rid uuid:=nullif(payload->>'route_id','')::uuid; bs uuid:=nullif(payload->>'boarding_stop_id','')::uuid; als uuid:=nullif(payload->>'alighting_stop_id','')::uuid;
begin
  perform public.transport_require_access(true,'assign_students');
  if not exists(select 1 from public.students where id=sid and status='active' and deleted_at is null) then raise exception 'Active student required' using errcode='23503'; end if;
  if not exists(select 1 from public.transport_routes where id=rid and active and deleted_at is null) then raise exception 'Active route required' using errcode='23503'; end if;
  if bs is not null and not exists(select 1 from public.transport_route_stops where route_id=rid and stop_id=bs and active) then raise exception 'Boarding stop must belong to the route' using errcode='23503'; end if;
  if als is not null and not exists(select 1 from public.transport_route_stops where route_id=rid and stop_id=als and active) then raise exception 'Alighting stop must belong to the route' using errcode='23503'; end if;
  insert into public.transport_student_assignments(student_id,route_id,boarding_stop_id,alighting_stop_id,effective_from,effective_to,active,notes,created_by)
  values(sid,rid,bs,als,coalesce(nullif(payload->>'effective_from','')::date,current_date),nullif(payload->>'effective_to','')::date,true,nullif(payload->>'notes',''),auth.uid())
  on conflict(student_id,route_id) where active and effective_to is null do update set boarding_stop_id=excluded.boarding_stop_id,alighting_stop_id=excluded.alighting_stop_id,effective_from=excluded.effective_from,notes=excluded.notes,updated_at=now()
  returning * into a;
  return to_jsonb(a);
end $function$

CREATE OR REPLACE FUNCTION public.transport_assignment_register(target_route_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a_access jsonb; role_name text;
begin
  a_access:=public.transport_require_access(false,'view'); role_name:=a_access->>'role';
  if role_name<>'principal' and not (a_access->'capabilities' ? 'assign_students') then
    raise exception 'Student transport assignment access is not allowed for this role' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'route_id',r.id,'route',r.route_name,'service_type',r.service_type,'boarding_stop_id',bs.id,'boarding_stop',bs.stop_name,'alighting_stop_id',als.id,'alighting_stop',als.stop_name,'effective_from',a.effective_from,'effective_to',a.effective_to,'active',a.active,'notes',a.notes) order by r.route_name,s.first_name,s.last_name) from public.transport_student_assignments a join public.students s on s.id=a.student_id join public.transport_routes r on r.id=a.route_id left join public.transport_stops bs on bs.id=a.boarding_stop_id left join public.transport_stops als on als.id=a.alighting_stop_id where (target_route_id is null or a.route_id=target_route_id)),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.transport_block_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if current_setting('app.transport_allow_hard_delete',true)='on' then return old; end if;
  raise exception 'Transport records cannot be hard deleted; deactivate, cancel or resolve them instead' using errcode='42501';
end $function$

CREATE OR REPLACE FUNCTION public.transport_can_operate_trip(target_trip_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb; role_name text; staff_id uuid;
begin
  a:=public.transport_actor_access(); role_name:=a->>'role'; staff_id:=nullif(a->>'hr_staff_id','')::uuid;
  if role_name in ('system_admin','manager','dispatcher') then return true; end if;
  if role_name='driver' then
    return exists(select 1 from public.transport_trips t join public.transport_drivers d on d.id=t.driver_id where t.id=target_trip_id and d.hr_staff_id=staff_id);
  elsif role_name='attendant' then
    return exists(select 1 from public.transport_trips t where t.id=target_trip_id and t.attendant_hr_staff_id=staff_id);
  end if;
  return false;
end $function$

CREATE OR REPLACE FUNCTION public.transport_cancel_trip(target_trip_id uuid, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare t public.transport_trips;
begin perform public.transport_require_access(true,'trip_operate'); if not public.transport_can_operate_trip(target_trip_id) then raise exception 'Trip is not assigned to this transport staff member' using errcode='42501'; end if; update public.transport_trips set status='cancelled',cancellation_reason=nullif(trim(reason),'') where id=target_trip_id and status in ('scheduled','boarding') returning * into t; if t.id is null then raise exception 'Only scheduled or boarding trips can be cancelled' using errcode='23514'; end if; return to_jsonb(t); end $function$

CREATE OR REPLACE FUNCTION public.transport_complete_trip(target_trip_id uuid, end_odometer_km numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare t public.transport_trips;
begin
  perform public.transport_require_access(true,'trip_operate'); if not public.transport_can_operate_trip(target_trip_id) then raise exception 'Trip is not assigned to this transport staff member' using errcode='42501'; end if;
  if exists(select 1 from public.transport_trip_students where trip_id=target_trip_id and status='boarded') then raise exception 'All boarded students must be marked alighted before trip completion' using errcode='23514'; end if;
  update public.transport_trips set status='completed',actual_arrival=coalesce(actual_arrival,now()),odometer_end_km=coalesce(end_odometer_km,odometer_end_km),completed_by=auth.uid() where id=target_trip_id and status='in_progress' returning * into t;
  if t.id is null then raise exception 'Trip is not in progress' using errcode='23514'; end if;
  if t.odometer_end_km is not null then update public.transport_vehicles set odometer_km=greatest(coalesce(odometer_km,0),t.odometer_end_km) where id=t.vehicle_id; end if;
  return to_jsonb(t);
end $function$

CREATE OR REPLACE FUNCTION public.transport_create_trip(target_route_id uuid, target_service_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r public.transport_routes; v public.transport_vehicles; t public.transport_trips; roster_count integer;
begin
  perform public.transport_require_access(true,'trip_operate');
  select * into r from public.transport_routes where id=target_route_id and active and deleted_at is null for share;
  if r.id is null then raise exception 'Active route not found' using errcode='P0002'; end if;
  if r.default_vehicle_id is null then raise exception 'Route requires a default vehicle before a trip can be created' using errcode='23514'; end if;
  select * into v from public.transport_vehicles where id=r.default_vehicle_id and active and deleted_at is null and status='active' for share;
  if v.id is null then raise exception 'Route vehicle is not active' using errcode='23514'; end if;
  if r.default_driver_id is not null and not exists(select 1 from public.transport_drivers d where d.id=r.default_driver_id and d.active and d.deleted_at is null and d.status='active' and (d.licence_expiry is null or d.licence_expiry>=target_service_date)) then raise exception 'Route driver is not eligible for this service date' using errcode='23514'; end if;
  select count(*) into roster_count from public.transport_student_assignments a join public.students s on s.id=a.student_id where a.route_id=r.id and a.active and a.effective_from<=target_service_date and (a.effective_to is null or a.effective_to>=target_service_date) and s.status='active' and s.deleted_at is null;
  if roster_count>v.seating_capacity then raise exception 'Vehicle capacity exceeded: % assigned students for % seats',roster_count,v.seating_capacity using errcode='23514'; end if;
  insert into public.transport_trips(route_id,vehicle_id,driver_id,attendant_hr_staff_id,service_date,scheduled_departure,scheduled_arrival,status,created_by)
  values(r.id,v.id,r.default_driver_id,r.default_attendant_hr_staff_id,target_service_date,r.scheduled_departure,r.scheduled_arrival,'scheduled',auth.uid()) returning * into t;
  insert into public.transport_trip_students(trip_id,student_id,assignment_id,boarding_stop_id,alighting_stop_id)
  select t.id,a.student_id,a.id,a.boarding_stop_id,a.alighting_stop_id from public.transport_student_assignments a join public.students s on s.id=a.student_id where a.route_id=r.id and a.active and a.effective_from<=target_service_date and (a.effective_to is null or a.effective_to>=target_service_date) and s.status='active' and s.deleted_at is null;
  return jsonb_build_object('trip_id',t.id,'roster_count',roster_count,'capacity',v.seating_capacity);
end $function$

CREATE OR REPLACE FUNCTION public.transport_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare s public.transport_settings; a jsonb; role_name text;
begin
  a:=public.transport_require_access(false,'view'); role_name:=a->>'role';
  select * into s from public.transport_settings limit 1;
  return jsonb_build_object('metrics',jsonb_build_object(
    'vehicles',(select count(*) from public.transport_vehicles where active and deleted_at is null and status<>'retired'),
    'routes',(select count(*) from public.transport_routes where active and deleted_at is null),
    'assigned_students',(select count(distinct student_id) from public.transport_student_assignments where active and (effective_to is null or effective_to>=current_date)),
    'today_trips',(select count(*) from public.transport_trips t where t.service_date=current_date and t.status<>'cancelled' and (role_name not in ('driver','attendant') or public.transport_can_operate_trip(t.id))),
    'open_incidents',(select count(*) from public.transport_incidents where status<>'resolved'),
    'maintenance_due',(select count(*) from public.transport_vehicles where active and deleted_at is null and next_service_date is not null and next_service_date<=current_date+s.maintenance_alert_days),
    'documents_due',(select count(*) from public.transport_vehicles where active and deleted_at is null and ((insurance_expiry is not null and insurance_expiry<=current_date+s.document_alert_days) or (roadworthy_expiry is not null and roadworthy_expiry<=current_date+s.document_alert_days)))
  ),'today',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'route',r.route_name,'route_code',r.route_code,'vehicle',v.fleet_no,'registration_no',v.registration_no,'departure',t.scheduled_departure,'status',t.status,'roster',(select count(*) from public.transport_trip_students ts where ts.trip_id=t.id)) order by t.scheduled_departure) from public.transport_trips t join public.transport_routes r on r.id=t.route_id join public.transport_vehicles v on v.id=t.vehicle_id where t.service_date=current_date and (role_name not in ('driver','attendant') or public.transport_can_operate_trip(t.id))),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.transport_driver_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb; role_name text;
begin
  a:=public.transport_require_access(false,'view'); role_name:=a->>'role';
  if role_name not in ('system_admin','principal','manager') and not (a->'capabilities' ? 'fleet_write') then
    raise exception 'Fleet oversight access is required for the driver register' using errcode='42501';
  end if;
  return jsonb_build_object('drivers',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'hr_staff_id',d.hr_staff_id,'name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'staff_no',h.staff_no,'licence_no',d.licence_no,'licence_class',d.licence_class,'licence_expiry',d.licence_expiry,'status',d.status,'active',d.active,'notes',d.notes) order by h.first_name,h.last_name) from public.transport_drivers d join public.hr_staff_members h on h.id=d.hr_staff_id where d.deleted_at is null),'[]'::jsonb),'candidates',coalesce((select jsonb_agg(jsonb_build_object('hr_staff_id',h.id,'name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'staff_no',h.staff_no,'job_title',h.job_title) order by h.first_name,h.last_name) from public.hr_staff_members h where h.active and h.deleted_at is null),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.transport_end_assignment(target_assignment_id uuid, end_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a public.transport_student_assignments;
begin perform public.transport_require_access(true,'assign_students'); update public.transport_student_assignments set active=false,effective_to=coalesce(end_date,current_date) where id=target_assignment_id and active returning * into a; if a.id is null then raise exception 'Active assignment not found' using errcode='P0002'; end if; return to_jsonb(a); end $function$

CREATE OR REPLACE FUNCTION public.transport_enforce_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if auth.role() in ('service_role','supabase_admin') or auth.role() is null then
    if tg_op='DELETE' then return old; end if; return new;
  end if;
  if not public.license_write_allowed() then
    raise exception 'Transport changes are unavailable while the school licence is read-only' using errcode='42501';
  end if;
  if tg_op='DELETE' then return old; end if; return new;
end $function$

CREATE OR REPLACE FUNCTION public.transport_generate_fleet_no()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare root text:=public.transport_identifier_root(); n bigint; candidate text;
begin
 loop n:=nextval('public.transport_vehicle_seq'); candidate:=root||'-VEH-'||lpad(n::text,4,'0'); exit when not exists(select 1 from public.transport_vehicles where fleet_no=candidate); end loop;
 return candidate;
end $function$

CREATE OR REPLACE FUNCTION public.transport_generate_route_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare root text:=public.transport_identifier_root(); n bigint; candidate text;
begin
 loop n:=nextval('public.transport_route_seq'); candidate:=root||'-RTE-'||lpad(n::text,3,'0'); exit when not exists(select 1 from public.transport_routes where route_code=candidate); end loop;
 return candidate;
end $function$

CREATE OR REPLACE FUNCTION public.transport_generate_stop_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare root text:=public.transport_identifier_root(); n bigint; candidate text;
begin
 loop n:=nextval('public.transport_stop_seq'); candidate:=root||'-STP-'||lpad(n::text,3,'0'); exit when not exists(select 1 from public.transport_stops where stop_code=candidate); end loop;
 return candidate;
end $function$

CREATE OR REPLACE FUNCTION public.transport_identifier_root()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select left(coalesce(nullif(regexp_replace(upper(identifier_root),'[^A-Z0-9]','','g'),''),nullif(regexp_replace(upper(school_name),'[^A-Z]','','g'),''),'SCH'),8)
  from public.school_settings limit 1
$function$

CREATE OR REPLACE FUNCTION public.transport_incident_register(status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb; role_name text;
begin
  a:=public.transport_require_access(false,'view'); role_name:=a->>'role';
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'trip_id',i.trip_id,'vehicle_id',i.vehicle_id,'vehicle',v.fleet_no,'registration_no',v.registration_no,
    'student_id',case when role_name='maintenance' then null else s.id end,
    'student',case when role_name='maintenance' or s.id is null then null else concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) end,
    'driver_id',i.driver_id,'driver',case when dh.id is null then null else concat_ws(' ',dh.first_name,nullif(dh.middle_name,''),dh.last_name) end,
    'occurred_at',i.occurred_at,'incident_type',i.incident_type,'severity',i.severity,'description',i.description,'action_taken',i.action_taken,'status',i.status,'resolved_at',i.resolved_at,'resolution_notes',i.resolution_notes
  ) order by i.occurred_at desc)
  from public.transport_incidents i
  left join public.transport_vehicles v on v.id=i.vehicle_id
  left join public.students s on s.id=i.student_id
  left join public.transport_drivers d on d.id=i.driver_id
  left join public.hr_staff_members dh on dh.id=d.hr_staff_id
  where (status_filter is null or status_filter='' or i.status=status_filter)
    and (
      role_name in ('system_admin','principal','manager','dispatcher')
      or (role_name in ('driver','attendant') and (i.created_by=auth.uid() or (i.trip_id is not null and public.transport_can_operate_trip(i.trip_id))))
      or (role_name='maintenance' and i.incident_type in ('accident','breakdown','safety') and (i.vehicle_id is not null or i.trip_id is not null))
    )
  ),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.transport_maintenance_register(target_vehicle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb; role_name text;
begin
  a:=public.transport_require_access(false,'view'); role_name:=a->>'role';
  if role_name<>'principal' and not (a->'capabilities' ? 'maintenance_write') then
    raise exception 'Fleet maintenance access is not allowed for this role' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'vehicle_id',v.id,'vehicle',v.fleet_no,'registration_no',v.registration_no,'maintenance_type',m.maintenance_type,'service_date',m.service_date,'odometer_km',m.odometer_km,'vendor',m.vendor,'cost',m.cost,'next_due_date',m.next_due_date,'description',m.description) order by m.service_date desc,m.created_at desc) from public.transport_maintenance_records m join public.transport_vehicles v on v.id=m.vehicle_id where target_vehicle_id is null or m.vehicle_id=target_vehicle_id),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.transport_mark_student(target_trip_student_id uuid, target_status text, note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare ts public.transport_trip_students; trip_id uuid; old_status text;
begin
  perform public.transport_require_access(true,'trip_operate');
  select * into ts from public.transport_trip_students where id=target_trip_student_id for update; if ts.id is null then raise exception 'Trip student not found' using errcode='P0002'; end if; trip_id:=ts.trip_id; old_status:=ts.status;
  if not public.transport_can_operate_trip(trip_id) then raise exception 'Trip is not assigned to this transport staff member' using errcode='42501'; end if;
  if not exists(select 1 from public.transport_trips where id=trip_id and status in ('scheduled','boarding','in_progress')) then raise exception 'Trip roster is closed' using errcode='23514'; end if;
  if target_status='boarded' and old_status='pending' then update public.transport_trip_students set status='boarded',boarded_at=now(),boarded_by=auth.uid(),notes=coalesce(note,notes) where id=ts.id returning * into ts;
  elsif target_status='alighted' and old_status='boarded' then update public.transport_trip_students set status='alighted',alighted_at=now(),alighted_by=auth.uid(),notes=coalesce(note,notes) where id=ts.id returning * into ts;
  elsif target_status in ('missed','excused') and old_status='pending' then update public.transport_trip_students set status=target_status,notes=coalesce(note,notes) where id=ts.id returning * into ts;
  else raise exception 'Invalid transport roster transition from % to %',old_status,target_status using errcode='23514'; end if;
  return to_jsonb(ts);
end $function$

CREATE OR REPLACE FUNCTION public.transport_my_account()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r text; lic jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if; r:=public.current_app_role()::text; lic:=public.license_access_for_actor(auth.uid()); if not coalesce((lic->>'read_allowed')::boolean,false) then raise exception 'Transport account unavailable while school licence is locked' using errcode='42501'; end if;
  return jsonb_build_object('role',r,
    'assignments',coalesce((select jsonb_agg(jsonb_build_object('assignment_id',a.id,'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'route_id',rt.id,'route',rt.route_name,'route_code',rt.route_code,'service_type',rt.service_type,'scheduled_departure',rt.scheduled_departure,'boarding_stop',bs.stop_name,'boarding_time',brs.planned_time,'alighting_stop',als.stop_name,'alighting_time',ars.planned_time,'effective_from',a.effective_from,'effective_to',a.effective_to,'active',a.active) order by s.first_name,rt.scheduled_departure) from public.transport_student_assignments a join public.students s on s.id=a.student_id join public.transport_routes rt on rt.id=a.route_id left join public.transport_stops bs on bs.id=a.boarding_stop_id left join public.transport_stops als on als.id=a.alighting_stop_id left join public.transport_route_stops brs on brs.route_id=rt.id and brs.stop_id=a.boarding_stop_id left join public.transport_route_stops ars on ars.route_id=rt.id and ars.stop_id=a.alighting_stop_id where (r='student' and s.profile_id=auth.uid()) or (r='parent_guardian' and exists(select 1 from public.guardian_links gl where gl.auth_user_id=auth.uid() and gl.student_id=s.id))),'[]'::jsonb),
    'recent_trips',coalesce((select jsonb_agg(jsonb_build_object('trip_id',t.id,'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'route',rt.route_name,'service_date',t.service_date,'scheduled_departure',t.scheduled_departure,'trip_status',t.status,'boarding_status',ts.status,'boarded_at',ts.boarded_at,'alighted_at',ts.alighted_at,'vehicle',v.fleet_no,'registration_no',v.registration_no) order by t.service_date desc,t.scheduled_departure desc) from public.transport_trip_students ts join public.transport_trips t on t.id=ts.trip_id join public.transport_routes rt on rt.id=t.route_id join public.transport_vehicles v on v.id=t.vehicle_id join public.students s on s.id=ts.student_id where ((r='student' and s.profile_id=auth.uid()) or (r='parent_guardian' and exists(select 1 from public.guardian_links gl where gl.auth_user_id=auth.uid() and gl.student_id=s.id))) and t.service_date>=current_date-30),'[]'::jsonb),
    'staff_trips',coalesce((select jsonb_agg(jsonb_build_object('trip_id',t.id,'service_date',t.service_date,'route',rt.route_name,'scheduled_departure',t.scheduled_departure,'status',t.status,'vehicle',v.fleet_no) order by t.service_date desc,t.scheduled_departure desc) from public.hr_staff_members h join public.transport_trips t on (exists(select 1 from public.transport_drivers d where d.id=t.driver_id and d.hr_staff_id=h.id) or t.attendant_hr_staff_id=h.id) join public.transport_routes rt on rt.id=t.route_id join public.transport_vehicles v on v.id=t.vehicle_id where h.profile_id=auth.uid() and t.service_date>=current_date-30),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.transport_require_access(require_write boolean DEFAULT false, required_capability text DEFAULT 'view'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb; v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_access:=public.transport_actor_access();
  if not coalesce((v_access->>'authorized')::boolean,false) then raise exception 'Transport management access is not allowed for this user' using errcode='42501'; end if;
  if required_capability is not null and not (v_access->'capabilities' ? required_capability) then raise exception 'Transport capability % is required',required_capability using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Transport access is unavailable while the school licence is locked' using errcode='42501'; end if;
  if require_write and not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Transport changes are unavailable while the school licence is read-only' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return v_access;
end $function$

CREATE OR REPLACE FUNCTION public.transport_resolve_incident(target_incident_id uuid, resolution text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare i public.transport_incidents;
begin perform public.transport_require_access(true,'incident_write'); update public.transport_incidents set status='resolved',resolved_at=now(),resolved_by=auth.uid(),resolution_notes=nullif(trim(resolution),'') where id=target_incident_id and status<>'resolved' returning * into i; if i.id is null then raise exception 'Open incident not found' using errcode='P0002'; end if; return to_jsonb(i); end $function$

CREATE OR REPLACE FUNCTION public.transport_route_detail(target_route_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.transport_require_access(false,'view');
  return jsonb_build_object('route',(select to_jsonb(r) from public.transport_routes r where r.id=target_route_id and r.deleted_at is null),'stops',coalesce((select jsonb_agg(jsonb_build_object('id',rs.id,'stop_id',s.id,'stop_code',s.stop_code,'stop_name',s.stop_name,'address',s.address,'landmark',s.landmark,'stop_order',rs.stop_order,'planned_time',rs.planned_time) order by rs.stop_order) from public.transport_route_stops rs join public.transport_stops s on s.id=rs.stop_id where rs.route_id=target_route_id and rs.active),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.transport_route_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb; can_write boolean;
begin
  a:=public.transport_require_access(false,'view');
  can_write:=coalesce(a->'capabilities' ? 'route_write',false);
  return jsonb_build_object(
    'routes',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'route_code',r.route_code,'route_name',r.route_name,'service_type',r.service_type,'description',r.description,'scheduled_departure',r.scheduled_departure,'scheduled_arrival',r.scheduled_arrival,'active',r.active,'vehicle_id',r.default_vehicle_id,'vehicle',v.fleet_no,'driver_id',r.default_driver_id,'driver',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'attendant_hr_staff_id',r.default_attendant_hr_staff_id,'assigned_students',(select count(*) from public.transport_student_assignments sa where sa.route_id=r.id and sa.active and (sa.effective_to is null or sa.effective_to>=current_date)),'stop_count',(select count(*) from public.transport_route_stops rs where rs.route_id=r.id and rs.active)) order by r.route_name) from public.transport_routes r left join public.transport_vehicles v on v.id=r.default_vehicle_id left join public.transport_drivers d on d.id=r.default_driver_id left join public.hr_staff_members h on h.id=d.hr_staff_id where r.deleted_at is null),'[]'::jsonb),
    'vehicles',case when can_write then coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',fleet_no||' · '||registration_no,'capacity',seating_capacity) order by fleet_no) from public.transport_vehicles where deleted_at is null and active and status='active'),'[]'::jsonb) else '[]'::jsonb end,
    'drivers',case when can_write then coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'label',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'licence_expiry',d.licence_expiry) order by h.first_name,h.last_name) from public.transport_drivers d join public.hr_staff_members h on h.id=d.hr_staff_id where d.deleted_at is null and d.active and d.status='active'),'[]'::jsonb) else '[]'::jsonb end,
    'attendants',case when can_write then coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'label',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)) order by h.first_name,h.last_name) from public.transport_staff_access tsa join public.hr_staff_members h on h.id=tsa.hr_staff_id where tsa.active and tsa.transport_role='attendant' and h.active and h.deleted_at is null),'[]'::jsonb) else '[]'::jsonb end
  );
end $function$

CREATE OR REPLACE FUNCTION public.transport_save_driver(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare d public.transport_drivers; target_id uuid:=nullif(payload->>'id','')::uuid; h_id uuid:=nullif(payload->>'hr_staff_id','')::uuid;
begin
  perform public.transport_require_access(true,'fleet_write');
  if target_id is null then
    if not exists(select 1 from public.hr_staff_members where id=h_id and active and deleted_at is null) then raise exception 'Active HR staff record required' using errcode='23503'; end if;
    insert into public.transport_drivers(hr_staff_id,licence_no,licence_class,licence_expiry,status,notes,active,created_by) values(h_id,upper(trim(payload->>'licence_no')),nullif(payload->>'licence_class',''),nullif(payload->>'licence_expiry','')::date,coalesce(nullif(payload->>'status',''),'active'),nullif(payload->>'notes',''),coalesce(nullif(payload->>'active','')::boolean,true),auth.uid()) returning * into d;
  else
    update public.transport_drivers set licence_no=upper(trim(coalesce(payload->>'licence_no',licence_no))),licence_class=coalesce(payload->>'licence_class',licence_class),licence_expiry=case when payload ? 'licence_expiry' then nullif(payload->>'licence_expiry','')::date else licence_expiry end,status=coalesce(nullif(payload->>'status',''),status),notes=coalesce(payload->>'notes',notes),active=coalesce(nullif(payload->>'active','')::boolean,active) where id=target_id and deleted_at is null returning * into d;
  end if;
  if d.id is null then raise exception 'Driver not found' using errcode='P0002'; end if; return to_jsonb(d);
end $function$

CREATE OR REPLACE FUNCTION public.transport_save_route(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r public.transport_routes; target_id uuid:=nullif(payload->>'id','')::uuid;
begin
  perform public.transport_require_access(true,'route_write');
  if target_id is null then
    insert into public.transport_routes(route_code,route_name,service_type,description,default_vehicle_id,default_driver_id,default_attendant_hr_staff_id,scheduled_departure,scheduled_arrival,active,created_by)
    values(coalesce(nullif(trim(payload->>'route_code'),''),public.transport_generate_route_code()),trim(payload->>'route_name'),payload->>'service_type',nullif(payload->>'description',''),nullif(payload->>'default_vehicle_id','')::uuid,nullif(payload->>'default_driver_id','')::uuid,nullif(payload->>'default_attendant_hr_staff_id','')::uuid,(payload->>'scheduled_departure')::time,nullif(payload->>'scheduled_arrival','')::time,coalesce(nullif(payload->>'active','')::boolean,true),auth.uid()) returning * into r;
  else
    update public.transport_routes set route_name=coalesce(nullif(trim(payload->>'route_name'),''),route_name),service_type=coalesce(nullif(payload->>'service_type',''),service_type),description=coalesce(payload->>'description',description),default_vehicle_id=case when payload ? 'default_vehicle_id' then nullif(payload->>'default_vehicle_id','')::uuid else default_vehicle_id end,default_driver_id=case when payload ? 'default_driver_id' then nullif(payload->>'default_driver_id','')::uuid else default_driver_id end,default_attendant_hr_staff_id=case when payload ? 'default_attendant_hr_staff_id' then nullif(payload->>'default_attendant_hr_staff_id','')::uuid else default_attendant_hr_staff_id end,scheduled_departure=coalesce(nullif(payload->>'scheduled_departure','')::time,scheduled_departure),scheduled_arrival=case when payload ? 'scheduled_arrival' then nullif(payload->>'scheduled_arrival','')::time else scheduled_arrival end,active=coalesce(nullif(payload->>'active','')::boolean,active) where id=target_id and deleted_at is null returning * into r;
  end if;
  if r.id is null then raise exception 'Route not found' using errcode='P0002'; end if; return to_jsonb(r);
end $function$

CREATE OR REPLACE FUNCTION public.transport_save_stop(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare s public.transport_stops; target_id uuid:=nullif(payload->>'id','')::uuid;
begin
  perform public.transport_require_access(true,'route_write');
  if target_id is null then
    insert into public.transport_stops(stop_code,stop_name,address,landmark,latitude,longitude,active,created_by) values(coalesce(nullif(trim(payload->>'stop_code'),''),public.transport_generate_stop_code()),trim(payload->>'stop_name'),nullif(payload->>'address',''),nullif(payload->>'landmark',''),nullif(payload->>'latitude','')::numeric,nullif(payload->>'longitude','')::numeric,coalesce(nullif(payload->>'active','')::boolean,true),auth.uid()) returning * into s;
  else
    update public.transport_stops set stop_name=coalesce(nullif(trim(payload->>'stop_name'),''),stop_name),address=coalesce(payload->>'address',address),landmark=coalesce(payload->>'landmark',landmark),latitude=case when payload ? 'latitude' then nullif(payload->>'latitude','')::numeric else latitude end,longitude=case when payload ? 'longitude' then nullif(payload->>'longitude','')::numeric else longitude end,active=coalesce(nullif(payload->>'active','')::boolean,active) where id=target_id and deleted_at is null returning * into s;
  end if;
  if s.id is null then raise exception 'Stop not found' using errcode='P0002'; end if; return to_jsonb(s);
end $function$

CREATE OR REPLACE FUNCTION public.transport_save_vehicle(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v public.transport_vehicles; target_id uuid:=nullif(payload->>'id','')::uuid;
begin
  perform public.transport_require_access(true,'fleet_write');
  if target_id is null then
    insert into public.transport_vehicles(fleet_no,registration_no,vehicle_type,make,model,manufacture_year,seating_capacity,ownership,status,insurance_expiry,roadworthy_expiry,next_service_date,odometer_km,notes,active,created_by)
    values(coalesce(nullif(trim(payload->>'fleet_no'),''),public.transport_generate_fleet_no()),upper(trim(payload->>'registration_no')),coalesce(nullif(payload->>'vehicle_type',''),'bus'),nullif(payload->>'make',''),nullif(payload->>'model',''),nullif(payload->>'manufacture_year','')::integer,coalesce(nullif(payload->>'seating_capacity','')::integer,1),coalesce(nullif(payload->>'ownership',''),'school'),coalesce(nullif(payload->>'status',''),'active'),nullif(payload->>'insurance_expiry','')::date,nullif(payload->>'roadworthy_expiry','')::date,nullif(payload->>'next_service_date','')::date,nullif(payload->>'odometer_km','')::numeric,nullif(payload->>'notes',''),coalesce(nullif(payload->>'active','')::boolean,true),auth.uid()) returning * into v;
  else
    update public.transport_vehicles set registration_no=upper(trim(coalesce(payload->>'registration_no',registration_no))),vehicle_type=coalesce(nullif(payload->>'vehicle_type',''),vehicle_type),make=coalesce(payload->>'make',make),model=coalesce(payload->>'model',model),manufacture_year=coalesce(nullif(payload->>'manufacture_year','')::integer,manufacture_year),seating_capacity=coalesce(nullif(payload->>'seating_capacity','')::integer,seating_capacity),ownership=coalesce(nullif(payload->>'ownership',''),ownership),status=coalesce(nullif(payload->>'status',''),status),insurance_expiry=case when payload ? 'insurance_expiry' then nullif(payload->>'insurance_expiry','')::date else insurance_expiry end,roadworthy_expiry=case when payload ? 'roadworthy_expiry' then nullif(payload->>'roadworthy_expiry','')::date else roadworthy_expiry end,next_service_date=case when payload ? 'next_service_date' then nullif(payload->>'next_service_date','')::date else next_service_date end,odometer_km=case when payload ? 'odometer_km' then nullif(payload->>'odometer_km','')::numeric else odometer_km end,notes=coalesce(payload->>'notes',notes),active=coalesce(nullif(payload->>'active','')::boolean,active) where id=target_id and deleted_at is null returning * into v;
  end if;
  if v.id is null then raise exception 'Vehicle not found' using errcode='P0002'; end if; return to_jsonb(v);
end $function$

CREATE OR REPLACE FUNCTION public.transport_session()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb; v_license jsonb; r text;
begin
  if auth.uid() is null then return jsonb_build_object('authorized',false); end if;
  v_access:=public.transport_actor_access(); v_license:=public.license_access_for_actor(auth.uid()); r:=public.current_app_role()::text;
  return v_access||jsonb_build_object('app_role',r,'read_allowed',coalesce((v_license->>'read_allowed')::boolean,false),'write_allowed',coalesce((v_license->>'write_allowed')::boolean,false));
end $function$

CREATE OR REPLACE FUNCTION public.transport_set_route_stops(target_route_id uuid, stops jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare item jsonb; sid uuid; ord integer;
begin
  perform public.transport_require_access(true,'route_write');
  if not exists(select 1 from public.transport_routes where id=target_route_id and deleted_at is null) then raise exception 'Route not found' using errcode='P0002'; end if;
  update public.transport_route_stops set active=false where route_id=target_route_id;
  for item in select value from jsonb_array_elements(coalesce(stops,'[]'::jsonb)) loop
    sid:=nullif(item->>'stop_id','')::uuid; ord:=(item->>'stop_order')::integer;
    if not exists(select 1 from public.transport_stops where id=sid and deleted_at is null and active) then raise exception 'Invalid active stop' using errcode='23503'; end if;
    insert into public.transport_route_stops(route_id,stop_id,stop_order,planned_time,active,created_by) values(target_route_id,sid,ord,nullif(item->>'planned_time','')::time,true,auth.uid())
    on conflict(route_id,stop_id) do update set stop_order=excluded.stop_order,planned_time=excluded.planned_time,active=true,updated_at=now();
  end loop;
  return public.transport_route_detail(target_route_id);
end $function$

CREATE OR REPLACE FUNCTION public.transport_set_staff_access(target_hr_staff_id uuid, target_role text, target_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare h public.hr_staff_members; a public.transport_staff_access;
begin
  perform public.transport_require_access(true,'manage_access');
  if target_role not in ('manager','dispatcher','driver','attendant','maintenance') then raise exception 'Invalid transport role' using errcode='22023'; end if;
  select * into h from public.hr_staff_members where id=target_hr_staff_id and active and deleted_at is null and profile_id is not null;
  if h.id is null then raise exception 'Active HR staff with a user profile is required' using errcode='23503'; end if;
  insert into public.transport_staff_access(profile_id,hr_staff_id,transport_role,active,appointed_by)
  values(h.profile_id,h.id,target_role,coalesce(target_active,true),auth.uid())
  on conflict(profile_id) do update set hr_staff_id=excluded.hr_staff_id,transport_role=excluded.transport_role,active=excluded.active,appointed_by=auth.uid(),appointed_at=now(),updated_at=now()
  returning * into a;
  if a.active then update public.profiles set mfa_required=true,updated_at=now() where id=a.profile_id; end if;
  return jsonb_build_object('id',a.id,'profile_id',a.profile_id,'hr_staff_id',a.hr_staff_id,'transport_role',a.transport_role,'active',a.active);
end $function$

CREATE OR REPLACE FUNCTION public.transport_settings_get()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare s public.transport_settings;
begin perform public.transport_require_access(false,'manage_settings'); select * into s from public.transport_settings limit 1; return to_jsonb(s); end $function$

CREATE OR REPLACE FUNCTION public.transport_settings_save(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare s public.transport_settings;
begin
  perform public.transport_require_access(true,'manage_settings'); select * into s from public.transport_settings limit 1 for update;
  update public.transport_settings set
    boarding_open_minutes=coalesce(nullif(payload->>'boarding_open_minutes','')::integer,s.boarding_open_minutes),
    boarding_close_minutes=coalesce(nullif(payload->>'boarding_close_minutes','')::integer,s.boarding_close_minutes),
    maintenance_alert_days=coalesce(nullif(payload->>'maintenance_alert_days','')::integer,s.maintenance_alert_days),
    document_alert_days=coalesce(nullif(payload->>'document_alert_days','')::integer,s.document_alert_days)
  where id=s.id returning * into s;
  return to_jsonb(s);
end $function$

CREATE OR REPLACE FUNCTION public.transport_staff_candidates()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.transport_require_access(false,'manage_access');
  return jsonb_build_object(
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'profile_id',a.profile_id,'hr_staff_id',a.hr_staff_id,'transport_role',a.transport_role,'active',a.active,'name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'staff_no',h.staff_no,'job_title',h.job_title) order by h.first_name,h.last_name) from public.transport_staff_access a join public.hr_staff_members h on h.id=a.hr_staff_id),'[]'::jsonb),
    'candidates',coalesce((select jsonb_agg(jsonb_build_object('hr_staff_id',h.id,'profile_id',h.profile_id,'name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'staff_no',h.staff_no,'job_title',h.job_title,'department',h.department) order by h.first_name,h.last_name) from public.hr_staff_members h where h.active and h.deleted_at is null and h.profile_id is not null),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.transport_start_trip(target_trip_id uuid, start_odometer_km numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare t public.transport_trips;
begin
  perform public.transport_require_access(true,'trip_operate'); if not public.transport_can_operate_trip(target_trip_id) then raise exception 'Trip is not assigned to this transport staff member' using errcode='42501'; end if;
  update public.transport_trips set status='in_progress',actual_departure=coalesce(actual_departure,now()),odometer_start_km=coalesce(start_odometer_km,odometer_start_km),started_by=auth.uid() where id=target_trip_id and status in ('scheduled','boarding') returning * into t;
  if t.id is null then raise exception 'Trip is not available to start' using errcode='23514'; end if; return to_jsonb(t);
end $function$

CREATE OR REPLACE FUNCTION public.transport_stop_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin perform public.transport_require_access(false,'view'); return coalesce((select jsonb_agg(to_jsonb(s) order by s.stop_name) from public.transport_stops s where s.deleted_at is null),'[]'::jsonb); end $function$

CREATE OR REPLACE FUNCTION public.transport_student_search(search_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.transport_require_access(false,'assign_students');
  return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'admission_no',s.admission_no,'name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)) order by s.first_name,s.last_name) from public.students s where s.deleted_at is null and s.status='active' and (coalesce(nullif(search_text,''),'')='' or s.admission_no ilike '%'||search_text||'%' or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%') limit 50),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.transport_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$ begin new.updated_at:=now(); return new; end $function$

CREATE OR REPLACE FUNCTION public.transport_trip_detail(target_trip_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb; role_name text;
begin
  a:=public.transport_require_access(false,'view'); role_name:=a->>'role';
  if role_name in ('driver','attendant') and not public.transport_can_operate_trip(target_trip_id) then
    raise exception 'Trip is not assigned to this transport staff member' using errcode='42501';
  elsif role_name='maintenance' then
    raise exception 'Trip rosters are not available to maintenance staff' using errcode='42501';
  end if;
  return jsonb_build_object('trip',(select jsonb_build_object('id',t.id,'service_date',t.service_date,'status',t.status,'scheduled_departure',t.scheduled_departure,'scheduled_arrival',t.scheduled_arrival,'actual_departure',t.actual_departure,'actual_arrival',t.actual_arrival,'route_id',r.id,'route',r.route_name,'route_code',r.route_code,'vehicle',v.fleet_no,'registration_no',v.registration_no,'capacity',v.seating_capacity,'driver',concat_ws(' ',dh.first_name,nullif(dh.middle_name,''),dh.last_name),'attendant',concat_ws(' ',ah.first_name,nullif(ah.middle_name,''),ah.last_name)) from public.transport_trips t join public.transport_routes r on r.id=t.route_id join public.transport_vehicles v on v.id=t.vehicle_id left join public.transport_drivers d on d.id=t.driver_id left join public.hr_staff_members dh on dh.id=d.hr_staff_id left join public.hr_staff_members ah on ah.id=t.attendant_hr_staff_id where t.id=target_trip_id),'students',coalesce((select jsonb_agg(jsonb_build_object('id',ts.id,'student_id',s.id,'student',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'boarding_stop',bs.stop_name,'alighting_stop',als.stop_name,'status',ts.status,'boarded_at',ts.boarded_at,'alighted_at',ts.alighted_at,'notes',ts.notes) order by coalesce(brs.stop_order,999),s.first_name,s.last_name) from public.transport_trip_students ts join public.students s on s.id=ts.student_id left join public.transport_stops bs on bs.id=ts.boarding_stop_id left join public.transport_stops als on als.id=ts.alighting_stop_id left join public.transport_route_stops brs on brs.route_id=(select route_id from public.transport_trips where id=target_trip_id) and brs.stop_id=ts.boarding_stop_id where ts.trip_id=target_trip_id),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.transport_trip_register(date_from date DEFAULT CURRENT_DATE, date_to date DEFAULT CURRENT_DATE, status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb;
begin
  a:=public.transport_require_access(false,'view');
  return coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'service_date',t.service_date,'route_id',r.id,'route',r.route_name,'route_code',r.route_code,'service_type',r.service_type,'vehicle_id',v.id,'vehicle',v.fleet_no,'registration_no',v.registration_no,'capacity',v.seating_capacity,'driver',concat_ws(' ',dh.first_name,nullif(dh.middle_name,''),dh.last_name),'attendant',concat_ws(' ',ah.first_name,nullif(ah.middle_name,''),ah.last_name),'scheduled_departure',t.scheduled_departure,'actual_departure',t.actual_departure,'actual_arrival',t.actual_arrival,'status',t.status,'roster',(select count(*) from public.transport_trip_students ts where ts.trip_id=t.id),'boarded',(select count(*) from public.transport_trip_students ts where ts.trip_id=t.id and ts.status in ('boarded','alighted')),'missed',(select count(*) from public.transport_trip_students ts where ts.trip_id=t.id and ts.status='missed')) order by t.service_date desc,t.scheduled_departure desc) from public.transport_trips t join public.transport_routes r on r.id=t.route_id join public.transport_vehicles v on v.id=t.vehicle_id left join public.transport_drivers d on d.id=t.driver_id left join public.hr_staff_members dh on dh.id=d.hr_staff_id left join public.hr_staff_members ah on ah.id=t.attendant_hr_staff_id where t.service_date between coalesce(date_from,current_date) and coalesce(date_to,date_from,current_date) and (status_filter is null or status_filter='' or t.status=status_filter) and ((a->>'role') not in ('driver','attendant') or public.transport_can_operate_trip(t.id))),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.transport_vehicle_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare a jsonb; role_name text;
begin
  a:=public.transport_require_access(false,'view'); role_name:=a->>'role';
  if role_name<>'principal' and not (a->'capabilities' ? 'fleet_write') and not (a->'capabilities' ? 'maintenance_write') then
    raise exception 'Fleet register access is not allowed for this transport role' using errcode='42501';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(v) order by v.fleet_no) from public.transport_vehicles v where v.deleted_at is null),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.trigger_sync_license_feature_rpc_privileges()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin perform public.sync_license_feature_rpc_privileges();return null;end $function$

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
end $function$

CREATE OR REPLACE FUNCTION public.user_account_lifecycle_summary()
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
  return jsonb_build_object(
    'accounts',coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id',p.id,
        'role',public.current_app_role_for(p.role),
        'active',p.active,
        'audit_events',(select count(*) from public.audit_log a where a.actor_id=p.id),
        'permanent_delete_allowed',(
          p.id<>auth.uid()
          and not exists(select 1 from public.audit_log a where a.actor_id=p.id)
        ),
        'lifecycle_action',case
          when p.id=auth.uid() then 'current_account'
          when exists(select 1 from public.audit_log a where a.actor_id=p.id) then 'deactivate'
          else 'delete_or_deactivate'
        end
      ) order by lower(p.full_name),p.id)
      from public.profiles p
      where public.current_app_role_for(p.role) in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian','accountant','student')
    ),'[]'::jsonb)
  );
end
$function$

CREATE OR REPLACE FUNCTION public.validate_academic_year_calendar_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if new.deleted_at is null and new.start_date is not null and new.end_date is not null then
    if exists(
      select 1 from public.academic_years y
      where y.id<>new.id and y.deleted_at is null
        and y.start_date is not null and y.end_date is not null
        and daterange(y.start_date,y.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')
    ) then
      raise exception 'Academic year dates cannot overlap another academic year';
    end if;

    if exists(
      select 1 from public.terms t
      where t.academic_year_id=new.id and t.deleted_at is null
        and ((t.start_date is not null and t.start_date<new.start_date)
          or (t.end_date is not null and t.end_date>new.end_date))
    ) then
      raise exception 'Academic year dates cannot exclude an existing term';
    end if;
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.validate_assessment_scheme_weights()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid; total numeric;
begin
  sid:=case when tg_op='DELETE' then old.scheme_id else new.scheme_id end;
  select coalesce(sum(weight),0) into total from public.assessment_components where scheme_id=sid
    and id<>coalesce(case when tg_op='DELETE' then old.id else new.id end,'00000000-0000-0000-0000-000000000000'::uuid);
  if tg_op<>'DELETE' then total:=total+new.weight; end if;
  if total>100.001 then raise exception 'Assessment component weights cannot exceed 100'; end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.validate_class_timetable_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  assigned_profile_id uuid;
  selected_teacher_profile_id uuid;
begin
  if not new.active then return new; end if;

  if new.day_of_week not in ('Monday','Tuesday','Wednesday','Thursday','Friday') then
    raise exception 'Timetable day must be Monday to Friday';
  end if;
  if new.period_end<=new.period_start then
    raise exception 'Period end time must be after start time';
  end if;
  if not exists(select 1 from public.academic_years y where y.id=new.academic_year_id and y.deleted_at is null) then
    raise exception 'Academic year not found';
  end if;
  if not exists(select 1 from public.classes c where c.id=new.class_id and c.deleted_at is null and c.active) then
    raise exception 'Class not found or inactive';
  end if;
  if not exists(select 1 from public.subjects s where s.id=new.subject_id and s.deleted_at is null and s.active) then
    raise exception 'Subject not found or inactive';
  end if;

  select t.profile_id into selected_teacher_profile_id
  from public.teachers t
  where t.id=new.teacher_id and t.deleted_at is null and t.active and t.employment_status='active';
  if selected_teacher_profile_id is null then
    raise exception 'Teacher not found, inactive, or not linked to a teaching account';
  end if;

  select cs.teacher_id into assigned_profile_id
  from public.class_subjects cs
  where cs.class_id=new.class_id and cs.subject_id=new.subject_id and cs.active
  limit 1;
  if assigned_profile_id is null then
    raise exception 'The selected subject is not actively assigned to this class';
  end if;
  if assigned_profile_id<>selected_teacher_profile_id then
    raise exception 'The selected teacher is not the assigned teacher for this class subject';
  end if;

  if exists(
    select 1 from public.class_timetable_entries x
    where x.active and x.academic_year_id=new.academic_year_id and x.class_id=new.class_id
      and x.day_of_week=new.day_of_week and x.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
      and x.period_start<new.period_end and x.period_end>new.period_start
  ) then
    raise exception 'This class already has an overlapping timetable period';
  end if;

  if exists(
    select 1 from public.class_timetable_entries x
    where x.active and x.academic_year_id=new.academic_year_id and x.teacher_id=new.teacher_id
      and x.day_of_week=new.day_of_week and x.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
      and x.period_start<new.period_end and x.period_end>new.period_start
  ) then
    raise exception 'The selected teacher already has another class during this time';
  end if;

  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.validate_grading_scale_overlap()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if exists(
    select 1 from public.grading_scales g
    where g.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
      and g.deleted_at is null
      and g.academic_year_id is not distinct from new.academic_year_id
      and g.class_id is not distinct from new.class_id
      and g.subject_id is not distinct from new.subject_id
      and numrange(g.min_mark,g.max_mark,'[]') && numrange(new.min_mark,new.max_mark,'[]')
  ) then raise exception 'Grading ranges cannot overlap within the same scope'; end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.validate_operational_readiness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  rls_state jsonb; function_state jsonb; duplicate_state jsonb; privilege_state jsonb;
  role_state jsonb; integrity_state jsonb; ready_value boolean;
begin
  if not public.has_role(array['system_admin','principal']) then raise exception 'Access denied' using errcode='42501'; end if;
  select jsonb_object_agg(tablename,rowsecurity) into rls_state from pg_tables where schemaname='public' and tablename in
    ('profiles','teachers','headteachers','students','student_guardians','guardian_links','enrollments','academic_years','terms','classes','subjects','class_subjects','user_class_access','grading_scales','assessment_schemes','assessment_components','student_reports','subject_results','assessment_score_entries');
  function_state:=jsonb_build_object(
    'generate_school_identifier',to_regprocedure('public.generate_school_identifier(text)') is not null,
    'save_student',to_regprocedure('public.save_student(jsonb)') is not null,
    'set_student_photo',to_regprocedure('public.set_student_photo(uuid,text,timestamptz)') is not null,
    'save_teacher',to_regprocedure('public.save_teacher(jsonb)') is not null,
    'save_headteacher',to_regprocedure('public.save_headteacher(jsonb)') is not null,
    'admin_validate_user_bundle',to_regprocedure('public.admin_validate_user_bundle(uuid,jsonb,boolean)') is not null,
    'admin_apply_user_bundle',to_regprocedure('public.admin_apply_user_bundle(uuid,jsonb)') is not null,
    'save_academic_entity',to_regprocedure('public.save_academic_entity(text,jsonb)') is not null,
    'save_class_subject_assignment',to_regprocedure('public.save_class_subject_assignment(jsonb)') is not null,
    'save_grading_scale',to_regprocedure('public.save_grading_scale(jsonb)') is not null,
    'save_assessment_scheme',to_regprocedure('public.save_assessment_scheme(jsonb)') is not null,
    'save_report_card',to_regprocedure('public.save_report_card(jsonb,integer)') is not null,
    'get_role_dashboard',to_regprocedure('public.get_role_dashboard(uuid)') is not null,
    'get_role_workspace',to_regprocedure('public.get_role_workspace()') is not null
  );
  duplicate_state:=jsonb_build_object(
    'admission_numbers',(select count(*) from (select lower(admission_no::text) from public.students group by lower(admission_no::text) having count(*)>1) q),
    'staff_numbers',(select count(*) from (
      select staff_no from (
        select lower(staff_no::text) staff_no from public.teachers
        union all select lower(staff_no::text) from public.headteachers
      ) all_staff group by staff_no having count(*)>1
    ) duplicate_staff),
    'access_scopes',(select count(*) from (select user_id,class_id,coalesce(subject_id,'00000000-0000-0000-0000-000000000000'::uuid) from public.user_class_access group by 1,2,3 having count(*)>1) q),
    'grading_overlaps',(select count(*) from public.grading_scales a join public.grading_scales b on a.id<b.id and a.deleted_at is null and b.deleted_at is null
      and a.academic_year_id is not distinct from b.academic_year_id and a.class_id is not distinct from b.class_id and a.subject_id is not distinct from b.subject_id
      and numrange(a.min_mark,a.max_mark,'[]') && numrange(b.min_mark,b.max_mark,'[]'))
  );
  integrity_state:=jsonb_build_object(
    'assessment_scheme_weights',(select count(*) from (
      select s.id from public.assessment_schemes s left join public.assessment_components c on c.scheme_id=s.id
      where s.deleted_at is null and s.active group by s.id having count(c.id)=0 or abs(coalesce(sum(c.weight),0)-100)>0.01
    ) q),
    'active_enrollment_conflicts',(select count(*) from (
      select e.student_id from public.enrollments e where e.active and e.deleted_at is null group by e.student_id having count(*)>1
    ) q),
    'invalid_teacher_links',(select count(*) from public.teachers t left join public.profiles p on p.id=t.profile_id
      where t.deleted_at is null and t.profile_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role) not in ('class_teacher','subject_teacher'))),
    'invalid_headteacher_links',(select count(*) from public.headteachers h left join public.profiles p on p.id=h.profile_id
      where h.deleted_at is null and h.profile_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role)<>'principal')),
    'duplicate_staff_profile_links',(select count(*) from (
      select profile_id from (
        select profile_id from public.teachers where deleted_at is null and profile_id is not null
        union all select profile_id from public.headteachers where deleted_at is null and profile_id is not null
      ) staff_links group by profile_id having count(*)>1
    ) q),
    'invalid_class_teacher_links',(select count(*) from public.classes c left join public.profiles p on p.id=c.class_teacher_id
      where c.deleted_at is null and c.class_teacher_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role) not in ('principal','academic_admin','class_teacher'))),
    'invalid_subject_teacher_links',(select count(*) from public.class_subjects cs left join public.profiles p on p.id=cs.teacher_id
      where cs.active and cs.teacher_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role) not in ('principal','academic_admin','class_teacher','subject_teacher'))),
    'invalid_guardian_portal_links',(select count(*) from public.guardian_links gl left join public.profiles p on p.id=gl.auth_user_id
      where gl.auth_user_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role)<>'parent_guardian')),
    'missing_auth_profiles',(select count(*) from auth.users u left join public.profiles p on p.id=u.id where p.id is null),
    'active_period_errors',(
      (select greatest(count(*)-1,0) from public.academic_years where is_active and deleted_at is null)
      +(select greatest(count(*)-1,0) from public.terms where is_active and deleted_at is null)
      +(select count(*) from public.terms t left join public.academic_years y on y.id=t.academic_year_id where t.is_active and t.deleted_at is null and (y.id is null or not y.is_active or y.deleted_at is not null))
    ),
    'subject_total_mismatches',(select count(*) from public.subject_results sr where abs(sr.total_score-coalesce((select sum(se.weighted_score) from public.assessment_score_entries se where se.subject_result_id=sr.id),0))>0.01)
  );
  privilege_state:=jsonb_build_object(
    'identifier_rpc',has_function_privilege('authenticated','public.generate_school_identifier(text)','EXECUTE'),
    'student_rpc',has_function_privilege('authenticated','public.save_student(jsonb)','EXECUTE'),
    'teacher_rpc',has_function_privilege('authenticated','public.save_teacher(jsonb)','EXECUTE'),
    'headteacher_rpc',has_function_privilege('authenticated','public.save_headteacher(jsonb)','EXECUTE'),
    'academic_rpc',has_function_privilege('authenticated','public.save_academic_entity(text,jsonb)','EXECUTE'),
    'assessment_rpc',has_function_privilege('authenticated','public.save_assessment_scheme(jsonb)','EXECUTE'),
    'report_rpc',has_function_privilege('authenticated','public.save_report_card(jsonb,integer)','EXECUTE'),
    'student_direct_write_blocked',not has_table_privilege('authenticated','public.students','INSERT') and not has_table_privilege('authenticated','public.students','UPDATE') and not has_table_privilege('authenticated','public.students','DELETE'),
    'teacher_direct_write_blocked',not has_table_privilege('authenticated','public.teachers','INSERT') and not has_table_privilege('authenticated','public.teachers','UPDATE') and not has_table_privilege('authenticated','public.teachers','DELETE'),
    'headteacher_direct_write_blocked',not has_table_privilege('authenticated','public.headteachers','INSERT') and not has_table_privilege('authenticated','public.headteachers','UPDATE') and not has_table_privilege('authenticated','public.headteachers','DELETE'),
    'profile_direct_write_blocked',not has_table_privilege('authenticated','public.profiles','INSERT') and not has_table_privilege('authenticated','public.profiles','UPDATE') and not has_table_privilege('authenticated','public.profiles','DELETE')
  );
  role_state:=jsonb_build_object(
    'system_admin',true,'principal',true,'academic_admin',true,'class_teacher',true,
    'subject_teacher',true,'records_officer',true,'viewer',true,'parent_guardian',true
  );
  ready_value:=not exists(select 1 from jsonb_each_text(function_state) x where x.value<>'true')
    and not exists(select 1 from jsonb_each_text(coalesce(rls_state,'{}'::jsonb)) x where x.value<>'true')
    and not exists(select 1 from jsonb_each_text(privilege_state) x where x.value<>'true')
    and not exists(select 1 from jsonb_each_text(duplicate_state) x where x.value::numeric<>0)
    and not exists(select 1 from jsonb_each_text(integrity_state) x where x.value::numeric<>0);
  return jsonb_build_object('ready',ready_value,'functions',function_state,'rls',coalesce(rls_state,'{}'::jsonb),'privileges',privilege_state,
    'roles',role_state,'duplicates',duplicate_state,'integrity',integrity_state,'checked_at',now());
end $function$

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
end $function$

CREATE OR REPLACE FUNCTION public.validate_student_import(rows jsonb, target_academic_year_id uuid, target_class_id uuid, filename text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$

CREATE OR REPLACE FUNCTION public.validate_term_calendar_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  year_start date;
  year_end date;
  year_deleted timestamptz;
begin
  select y.start_date,y.end_date,y.deleted_at
  into year_start,year_end,year_deleted
  from public.academic_years y
  where y.id=new.academic_year_id;

  if not found or year_deleted is not null then
    raise exception 'Term must belong to an active academic-year record';
  end if;

  if new.deleted_at is null then
    if new.start_date is not null and year_start is not null and new.start_date<year_start then
      raise exception 'Term start date cannot be before the academic year start date';
    end if;
    if new.end_date is not null and year_end is not null and new.end_date>year_end then
      raise exception 'Term end date cannot be after the academic year end date';
    end if;
    if new.start_date is not null and new.end_date is not null and exists(
      select 1 from public.terms t
      where t.academic_year_id=new.academic_year_id
        and t.id<>new.id
        and t.deleted_at is null
        and t.start_date is not null and t.end_date is not null
        and daterange(t.start_date,t.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')
    ) then
      raise exception 'Term dates cannot overlap another term in the same academic year';
    end if;
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.validate_term_reopening_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if new.next_term_begins is not null
     and new.end_date is not null
     and new.next_term_begins<=new.end_date then
    raise exception 'Next-term reopening date must be after the current term end date';
  end if;
  return new;
end $function$

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
$function$

CREATE OR REPLACE FUNCTION public.verify_license_binding(client_origin text, client_project_ref text, client_installation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if auth.role() not in ('service_role','supabase_admin') then
    raise exception 'Direct binding verification is disabled; invoke the license-verifier Edge Function' using errcode='42501';
  end if;
  return jsonb_build_object('authorised',false,'binding_required',true,'deprecated',true);
end $function$

CREATE OR REPLACE FUNCTION public.verify_report(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select case when p.id is null then jsonb_build_object('valid',false) else jsonb_build_object( 'valid',p.revoked_at is null, 'revoked',p.revoked_at is not null, 'published_at',p.published_at,'report_number',r.report_number, 'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name), 'admission_no',s.admission_no,'class_name',c.name,'term_name',t.name,'academic_year',y.name, 'average',(p2.snapshot->'summary'->>'average')::numeric, 'school_name',p2.snapshot->'school'->>'school_name', 'promotion',coalesce(p2.snapshot->'promotion','{}'::jsonb), 'revision',p2.version ) end from (select token verification_token) input left join public.report_publications p on p.verification_token=input.verification_token left join public.student_reports r on r.id=p.report_id left join public.enrollments e on e.id=r.enrollment_id left join public.students s on s.id=e.student_id left join public.classes c on c.id=e.class_id left join public.terms t on t.id=r.term_id left join public.academic_years y on y.id=t.academic_year_id left join public.report_revisions p2 on p2.id=p.revision_id $function$

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
$function$

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
$function$

CREATE OR REPLACE FUNCTION public.verify_transcript(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case when i.id is null then jsonb_build_object('valid',false,'found',false)
  else jsonb_build_object(
    'found',true,
    'valid',i.status='valid' and i.snapshot_checksum=encode(extensions.digest(convert_to(i.snapshot::text,'UTF8'),'sha256'),'hex'),
    'integrity_valid',i.snapshot_checksum=encode(extensions.digest(convert_to(i.snapshot::text,'UTF8'),'sha256'),'hex'),
    'status',i.status,
    'transcript_number',i.transcript_number,
    'issued_at',i.issued_at,
    'purpose',i.purpose,
    'student_name',i.snapshot->'student'->>'full_name',
    'admission_no',i.snapshot->'student'->>'admission_no',
    'school_name',i.snapshot->'school'->>'school_name',
    'record_count',i.academic_period_count,
    'cumulative_average',i.snapshot->'summary'->>'cumulative_average',
    'latest_academic_year',i.latest_academic_year,
    'latest_term',i.latest_term,
    'latest_class',i.latest_class,
    'template_version',i.template_version,
    'snapshot_checksum',i.snapshot_checksum,
    'revoked_at',i.revoked_at,
    'revocation_reason',case when i.status='revoked' then i.revocation_reason else '' end
  ) end
  from (select token verification_token) x
  left join public.transcript_issuances i on i.verification_token=x.verification_token
$function$

CREATE OR REPLACE FUNCTION public.welfare_add_note(target_case_id uuid, note_type text, note_text text, confidential boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('welfare','write');
 if not exists(select 1 from public.welfare_cases where id=target_case_id and status not in ('closed','cancelled')) then raise exception 'Welfare case is closed or unavailable'; end if;
 insert into public.welfare_case_notes(case_id,note_type,note,confidential,created_by) values(target_case_id,note_type,btrim(note_text),coalesce(confidential,true),auth.uid()) returning id into v_id;
 return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.welfare_case_detail(target_case_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_role text;r jsonb;
begin
 perform public.student_services_require_access('welfare','read');
 select public.current_app_role_for(p.role) into v_role from public.profiles p where p.id=auth.uid();
 select to_jsonb(q) into r from (select w.id,w.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,w.category,w.priority,w.summary,case when v_role='principal' then null else w.confidential_notes end confidential_notes,w.status,w.assigned_hr_staff_id,w.guardian_contact_status,w.guardian_contacted_at,w.external_referral,w.opened_at,w.closed_at,w.closure_notes from public.welfare_cases w join public.students s on s.id=w.student_id where w.id=target_case_id)q;
 if r is null then raise exception 'Welfare case not found'; end if;
 if v_role='principal' then return r||jsonb_build_object('notes','[]'::jsonb); end if;
 return r||jsonb_build_object('notes',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at) from public.welfare_case_notes n where n.case_id=target_case_id),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.welfare_case_register(search_text text DEFAULT NULL::text, status_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_role text;
begin
 perform public.student_services_require_access('welfare','read');
 select public.current_app_role_for(p.role) into v_role from public.profiles p where p.id=auth.uid();
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.opened_at desc) from (
  select w.id,w.student_id,s.admission_no,concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,w.category,w.priority,w.summary,w.status,w.guardian_contact_status,w.external_referral,w.opened_at,w.closed_at,
   case when v_role='principal' then null else w.confidential_notes end confidential_notes,
   case when v_role='principal' then 0 else (select count(*) from public.welfare_case_notes n where n.case_id=w.id) end note_count
  from public.welfare_cases w join public.students s on s.id=w.student_id
  where (status_filter is null or w.status=status_filter) and (search_text is null or concat_ws(' ',s.admission_no,s.first_name,s.middle_name,s.last_name,w.category,w.summary) ilike '%'||search_text||'%')
 )q),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.welfare_close_case(target_case_id uuid, closure_notes text, new_status text DEFAULT 'closed'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
 perform public.student_services_require_access('welfare','approve');
 if $3 not in ('closed','cancelled','referred') then raise exception 'Invalid welfare outcome'; end if;
 update public.welfare_cases w set status=$3,closure_notes=nullif($2,''),closed_by=case when $3 in ('closed','cancelled') then auth.uid() else null end,closed_at=case when $3 in ('closed','cancelled') then now() else null end where w.id=$1 and w.status not in ('closed','cancelled');
 if not found then raise exception 'Welfare case is finalized or unavailable'; end if;
end $function$

CREATE OR REPLACE FUNCTION public.welfare_save_case(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid;
begin
 perform public.student_services_require_access('welfare','write');
 v_id:=nullif(payload->>'id','')::uuid;
 if v_id is null then insert into public.welfare_cases(student_id,category,priority,summary,confidential_notes,status,assigned_hr_staff_id,guardian_contact_status,external_referral,opened_by) values((payload->>'student_id')::uuid,btrim(payload->>'category'),coalesce(nullif(payload->>'priority',''),'normal'),btrim(payload->>'summary'),nullif(payload->>'confidential_notes',''),coalesce(nullif(payload->>'status',''),'open'),nullif(payload->>'assigned_hr_staff_id','')::uuid,coalesce(nullif(payload->>'guardian_contact_status',''),'not_required'),nullif(payload->>'external_referral',''),auth.uid()) returning id into v_id;
 else update public.welfare_cases set category=coalesce(nullif(btrim(payload->>'category'),''),category),priority=coalesce(nullif(payload->>'priority',''),priority),summary=coalesce(nullif(btrim(payload->>'summary'),''),summary),confidential_notes=case when payload ? 'confidential_notes' then nullif(payload->>'confidential_notes','') else confidential_notes end,assigned_hr_staff_id=case when payload ? 'assigned_hr_staff_id' then nullif(payload->>'assigned_hr_staff_id','')::uuid else assigned_hr_staff_id end,guardian_contact_status=coalesce(nullif(payload->>'guardian_contact_status',''),guardian_contact_status),guardian_contacted_at=case when payload->>'guardian_contact_status'='contacted' then coalesce(guardian_contacted_at,now()) else guardian_contacted_at end,external_referral=case when payload ? 'external_referral' then nullif(payload->>'external_referral','') else external_referral end where id=v_id and status not in ('closed','cancelled');
 end if; return v_id;
end $function$

SET check_function_bodies=on;
