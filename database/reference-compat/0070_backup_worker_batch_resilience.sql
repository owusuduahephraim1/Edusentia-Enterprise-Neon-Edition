-- Resilient batched backup reader for Cloudflare Worker + Neon tenants.
-- Keeps portable school backup data tenant-local and prevents long sequential
-- database-read chains from exhausting Worker subrequest/runtime budgets.
begin;

alter table public.backup_exports
  add column if not exists heartbeat_at timestamptz;

update public.backup_exports
   set heartbeat_at=coalesce(completed_at,started_at,created_at,now())
 where heartbeat_at is null;

alter table public.backup_exports
  alter column heartbeat_at set default now();

-- A Cloudflare request cannot legitimately remain in the database snapshot
-- phase for ten minutes. Recover abandoned jobs left by interrupted Workers.
update public.backup_exports
   set status='failed',
       completed_at=coalesce(completed_at,now()),
       heartbeat_at=now(),
       error_message=case
         when btrim(coalesce(error_message,''))='' then
           'Backup worker was interrupted before completion. The backup was not published and may be retried safely.'
         else error_message
       end
 where status='processing'
   and coalesce(heartbeat_at,started_at,created_at)<now()-interval '10 minutes';

create or replace function public.backup_worker_read_batch(
  target_backup uuid,
  target_requests jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  allowed constant text[]:=array[
    'school_settings','id_card_settings','id_card_deletion_tombstones','profiles','teachers','headteachers',
    'academic_years','terms','classes','subjects','class_subjects','class_timetable_entries',
    'school_prospectuses','school_prospectus_sections','school_prospectus_items','school_prospectus_revisions',
    'user_class_access','students','student_guardians','guardian_links','enrollments','student_id_cards',
    'id_card_events','staff_id_cards','staff_id_card_events','class_attendance_registers','student_attendance_entries',
    'grading_scales','assessment_schemes','assessment_components','student_reports','subject_scores','subject_results',
    'assessment_score_entries','emergency_academic_delegations','emergency_academic_delegation_events',
    'academic_period_controls','report_correction_requests','report_correction_events','student_lifecycle_events',
    'transcript_issuances','data_retention_policies','privacy_requests','security_events','security_verification_runs',
    'recovery_test_runs','certificate_templates','teacher_award_categories','certificate_batches','certificates',
    'certificate_events','report_workflow_events','report_revisions','report_publications','report_card_templates',
    'notifications','notification_outbox','import_batches','import_errors','audit_log','audit_log_archives',
    'audit_log_archive_entries','client_error_events','system_maintenance_log'
  ];
  request_count integer;
  item jsonb;
  table_name text;
  page_offset integer;
  page_limit integer;
  page_rows jsonb;
  result jsonb:='{}'::jsonb;
begin
  if target_backup is null then
    raise exception 'backup id is required' using errcode='22023';
  end if;
  if jsonb_typeof(target_requests)<>'array' then
    raise exception 'backup batch requests must be an array' using errcode='22023';
  end if;

  request_count:=jsonb_array_length(target_requests);
  if request_count<1 or request_count>16 then
    raise exception 'backup batch must contain between 1 and 16 table requests' using errcode='22023';
  end if;

  if not exists(
    select 1 from public.backup_exports
     where id=target_backup and status='processing'
  ) then
    raise exception 'backup is not processing' using errcode='55000';
  end if;

  for item in select value from jsonb_array_elements(target_requests)
  loop
    table_name:=btrim(coalesce(item->>'table',''));
    if not (table_name=any(allowed)) then
      raise exception 'backup table is not allowlisted: %',table_name using errcode='42501';
    end if;
    if to_regclass(format('public.%I',table_name)) is null then
      raise exception 'backup table is unavailable: %',table_name using errcode='42P01';
    end if;

    page_offset:=coalesce(nullif(item->>'offset','')::integer,0);
    page_limit:=coalesce(nullif(item->>'limit','')::integer,1000);
    if page_offset<0 or page_limit<1 or page_limit>1000 then
      raise exception 'invalid backup page request' using errcode='22023';
    end if;

    execute format(
      'select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb)
         from (select * from public.%I order by ctid offset $1 limit $2) t',
      table_name
    ) into page_rows using page_offset,page_limit;

    result:=result||jsonb_build_object(table_name,coalesce(page_rows,'[]'::jsonb));
  end loop;

  update public.backup_exports
     set heartbeat_at=now()
   where id=target_backup and status='processing';

  return result;
end
$fn$;

create or replace function public.backup_worker_create(target_actor uuid,target_mode text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path=public,extensions,pg_catalog
as $fn$
declare
  result public.backup_exports%rowtype;
  backup_key text;
  stored_mode text;
begin
  if target_mode not in ('manual','scheduled','pre_restore') then
    raise exception 'invalid backup mode' using errcode='22023';
  end if;
  stored_mode:=target_mode;

  update public.backup_exports
     set status='failed',
         error_message='Previous backup worker was interrupted before completion. Safe retry is allowed.',
         completed_at=now(),
         heartbeat_at=now()
   where status='processing'
     and backup_type='full'
     and coalesce(heartbeat_at,started_at,created_at)<now()-interval '30 minutes';

  if exists(
    select 1 from public.backup_exports
     where status='processing'
       and backup_type='full'
       and coalesce(heartbeat_at,started_at,created_at)>=now()-interval '30 minutes'
  ) then
    raise exception 'A full backup is already processing' using errcode='55000';
  end if;

  backup_key:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24-MI-SS-MS')
              ||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,8);

  insert into public.backup_exports(
    storage_path,checksum,status,row_counts,initiated_by,backup_key,schema_version,backup_type,
    manifest_path,database_path,storage_object_counts,storage_bytes,encrypted,started_at,
    expires_at,error_message,verification_status,verification_notes,trigger_mode,heartbeat_at
  )
  values(
    '','', 'processing','{}'::jsonb,target_actor,backup_key,'7.4.0','full',
    '','', '{}'::jsonb,0,true,now(),null,'','not_tested',
    case
      when stored_mode='scheduled' then 'Scheduled full backup'
      when stored_mode='pre_restore' then 'Automatic pre-restore safety backup'
      else 'Manual full backup'
    end,
    stored_mode,now()
  )
  returning * into result;

  return to_jsonb(result);
end
$fn$;

create or replace function public.backup_worker_record_object(
  target_backup uuid,
  target_source_bucket text,
  target_source_path text,
  target_backup_path text,
  target_content_type text,
  target_original_size bigint,
  target_encrypted_size bigint,
  target_checksum text
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare result_id uuid;
begin
  insert into public.backup_storage_objects(
    backup_export_id,source_bucket,source_path,backup_path,content_type,
    original_size,encrypted_size,checksum,status,error_message
  )
  values(
    target_backup,target_source_bucket,target_source_path,target_backup_path,
    coalesce(nullif(target_content_type,''),'application/octet-stream'),
    greatest(target_original_size,0),greatest(target_encrypted_size,0),
    lower(target_checksum),'completed',''
  )
  returning id into result_id;

  update public.backup_exports
     set heartbeat_at=now()
   where id=target_backup and status='processing';

  return result_id;
end
$fn$;

create or replace function public.backup_worker_complete(
  target_backup uuid,
  target_storage_path text,
  target_checksum text,
  target_row_counts jsonb,
  target_manifest_path text,
  target_database_path text,
  target_storage_counts jsonb,
  target_storage_bytes bigint,
  target_key_hint text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  retention_days integer;
  result public.backup_exports%rowtype;
begin
  select least(3650,greatest(1,coalesce(backup_retention_days,30)))
    into retention_days
    from public.school_settings
   order by created_at
   limit 1;
  retention_days:=coalesce(retention_days,30);

  update public.backup_exports
     set storage_path=target_storage_path,
         checksum=lower(target_checksum),
         status='completed',
         row_counts=coalesce(target_row_counts,'{}'::jsonb),
         manifest_path=target_manifest_path,
         database_path=target_database_path,
         storage_object_counts=coalesce(target_storage_counts,'{}'::jsonb),
         storage_bytes=greatest(target_storage_bytes,0),
         encrypted=true,
         encryption_key_hint=target_key_hint,
         completed_at=now(),
         heartbeat_at=now(),
         expires_at=now()+make_interval(days=>retention_days),
         error_message=''
   where id=target_backup
     and status='processing'
  returning * into result;
  if result.id is null then raise exception 'Backup is not processing' using errcode='55000'; end if;
  return to_jsonb(result);
end
$fn$;

create or replace function public.backup_worker_fail(target_backup uuid,target_error text)
returns void
language sql
security definer
set search_path=public,pg_catalog
as $fn$
  update public.backup_exports
     set status='failed',
         completed_at=now(),
         heartbeat_at=now(),
         error_message=left(coalesce(target_error,''),2000)
   where id=target_backup and status='processing'
$fn$;

create or replace function public.backup_worker_reconcile_stale_backups()
returns integer
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare changed integer;
begin
  update public.backup_exports
     set status='failed',
         error_message='Backup worker heartbeat expired before completion. Safe retry is allowed.',
         completed_at=now(),
         heartbeat_at=now()
   where status='processing'
     and backup_type='full'
     and coalesce(heartbeat_at,started_at,created_at)<now()-interval '30 minutes';
  get diagnostics changed=row_count;
  return changed;
end
$fn$;

revoke all on function public.backup_worker_read_batch(uuid,jsonb) from public;
revoke all on function public.backup_worker_create(uuid,text) from public;
revoke all on function public.backup_worker_record_object(uuid,text,text,text,text,bigint,bigint,text) from public;
revoke all on function public.backup_worker_complete(uuid,text,text,jsonb,text,text,jsonb,bigint,text) from public;
revoke all on function public.backup_worker_fail(uuid,text) from public;
revoke all on function public.backup_worker_reconcile_stale_backups() from public;

grant execute on function public.backup_worker_read_batch(uuid,jsonb) to edusentia_worker_runtime;
grant execute on function public.backup_worker_create(uuid,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_record_object(uuid,text,text,text,text,bigint,bigint,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_complete(uuid,text,text,jsonb,text,text,jsonb,bigint,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_fail(uuid,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_reconcile_stale_backups() to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0070_backup_worker_batch_resilience')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
