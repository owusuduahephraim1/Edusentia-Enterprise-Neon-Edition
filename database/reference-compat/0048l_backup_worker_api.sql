-- Least-privilege Cloudflare Worker API for certified encrypted backup/restore on Neon + R2.
begin;

-- Complete the backup metadata surface on older parity/template databases. The
-- live clean-room snapshot already has these columns, so every clause is safe
-- to replay and preserves historical data.
alter table public.backup_exports
  add column if not exists backup_key text not null default '',
  add column if not exists schema_version text not null default '7.4.0',
  add column if not exists backup_type text not null default 'full',
  add column if not exists manifest_path text not null default '',
  add column if not exists database_path text not null default '',
  add column if not exists storage_object_counts jsonb not null default '{}'::jsonb,
  add column if not exists storage_bytes bigint not null default 0,
  add column if not exists encrypted boolean not null default true,
  add column if not exists encryption_key_hint text not null default '',
  add column if not exists started_at timestamptz not null default now(),
  add column if not exists completed_at timestamptz,
  add column if not exists expires_at timestamptz,
  add column if not exists error_message text not null default '',
  add column if not exists verification_status text not null default 'not_tested',
  add column if not exists verification_checked_at timestamptz,
  add column if not exists verification_notes text not null default '',
  add column if not exists offsite_copied_at timestamptz,
  add column if not exists offsite_copy_note text not null default '';

create table if not exists public.backup_storage_objects(
  id uuid primary key default gen_random_uuid(),
  backup_export_id uuid not null references public.backup_exports(id) on delete cascade,
  source_bucket text not null,
  source_path text not null,
  backup_path text not null,
  content_type text not null default 'application/octet-stream',
  original_size bigint not null default 0,
  encrypted_size bigint not null default 0,
  checksum text not null default '',
  status text not null default 'completed',
  error_message text not null default '',
  created_at timestamptz not null default now()
);

create or replace function public.backup_worker_read_table(
  target_table text,
  target_offset integer default 0,
  target_limit integer default 1000
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
    'license_plans','school_licenses','platform_access_locks','license_events','license_verification_logs',
    'license_feature_catalog','license_plan_revisions','license_entitlement_overrides','license_binding_sessions',
    'platform_distribution_authorities','platform_audit_archives','platform_package_templates','platform_package_artifacts',
    'platform_package_events','platform_package_reconciliation','notifications','notification_outbox','import_batches',
    'import_errors','audit_log','audit_log_archives','audit_log_archive_entries','client_error_events',
    'system_maintenance_log','backup_exports','backup_storage_objects'
  ];
  result jsonb;
begin
  if not (target_table=any(allowed)) then
    raise exception 'backup table is not allowlisted' using errcode='42501';
  end if;
  if target_offset<0 or target_limit<1 or target_limit>1000 then
    raise exception 'invalid backup page request' using errcode='22023';
  end if;
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from (select * from public.%I offset $1 limit $2) t',
    target_table
  ) into result using target_offset,target_limit;
  return coalesce(result,'[]'::jsonb);
end
$fn$;

create or replace function public.backup_worker_auth_users()
returns jsonb
language sql
security definer
set search_path=authn,pg_catalog
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',u.id,
    'email',u.email,
    'phone',u.phone,
    'user_metadata',coalesce(u.raw_user_meta_data,'{}'::jsonb),
    'app_metadata',coalesce(u.raw_app_meta_data,'{}'::jsonb),
    'created_at',u.created_at,
    'updated_at',u.updated_at,
    'last_sign_in_at',null,
    'banned_until',u.disabled_at
  ) order by u.created_at,u.id),'[]'::jsonb)
  from authn.users u
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
begin
  if target_mode not in ('manual','scheduled') then
    raise exception 'invalid backup mode' using errcode='22023';
  end if;

  update public.backup_exports
     set status='failed',
         error_message='Previous backup did not complete within two hours',
         completed_at=now()
   where status='processing'
     and backup_type='full'
     and started_at<now()-interval '2 hours';

  if exists(
    select 1 from public.backup_exports
     where status='processing'
       and backup_type='full'
       and started_at>=now()-interval '2 hours'
  ) then
    raise exception 'A full backup is already processing' using errcode='55000';
  end if;

  backup_key:=to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24-MI-SS-MS')
              ||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,8);

  insert into public.backup_exports(
    storage_path,checksum,status,row_counts,initiated_by,backup_key,schema_version,backup_type,
    manifest_path,database_path,storage_object_counts,storage_bytes,encrypted,started_at,
    expires_at,error_message,verification_status,verification_notes
  )
  values(
    '','', 'processing','{}'::jsonb,target_actor,backup_key,'7.4.0','full',
    '','', '{}'::jsonb,0,true,now(),null,'','not_tested',
    case when target_mode='scheduled' then 'Scheduled full backup' else 'Manual full backup' end
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
     set status='failed',completed_at=now(),error_message=left(coalesce(target_error,''),2000)
   where id=target_backup and status='processing'
$fn$;

create or replace function public.backup_worker_get(target_backup uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare result public.backup_exports%rowtype;
begin
  if target_backup is null then
    select * into result
      from public.backup_exports
     where status='completed' and backup_type='full'
     order by created_at desc limit 1;
  else
    select * into result from public.backup_exports where id=target_backup limit 1;
  end if;
  if result.id is null then return null; end if;
  return to_jsonb(result);
end
$fn$;

create or replace function public.backup_worker_inventory(target_backup uuid)
returns jsonb
language sql
security definer
set search_path=public,pg_catalog
as $fn$
  select coalesce(jsonb_agg(to_jsonb(o) order by o.source_bucket,o.source_path),'[]'::jsonb)
    from public.backup_storage_objects o
   where o.backup_export_id=target_backup and o.status='completed'
$fn$;

create or replace function public.backup_worker_set_verification(
  target_backup uuid,target_status text,target_notes text
)
returns void
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
begin
  if target_status not in ('not_tested','passed','failed') then
    raise exception 'invalid verification status' using errcode='22023';
  end if;
  update public.backup_exports
     set verification_status=target_status,
         verification_checked_at=case when target_status='not_tested' then null else now() end,
         verification_notes=left(coalesce(target_notes,''),4000)
   where id=target_backup;
end
$fn$;

create or replace function public.backup_worker_restore_job(target_job uuid,target_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare result public.school_restore_jobs%rowtype;
begin
  select * into result
    from public.school_restore_jobs
   where id=target_job and initiated_by=target_actor
   limit 1;
  if result.id is null then return null; end if;
  return to_jsonb(result);
end
$fn$;

create or replace function public.backup_worker_set_restore_prebackup(
  target_job uuid,target_actor uuid,target_backup uuid
)
returns void
language sql
security definer
set search_path=public,pg_catalog
as $fn$
  update public.school_restore_jobs
     set pre_restore_backup_id=target_backup,updated_at=now()
   where id=target_job and initiated_by=target_actor
$fn$;

create or replace function public.backup_worker_register_r2_object(
  target_tenant uuid,target_key text,target_name text,target_content_type text,
  target_size bigint,target_actor uuid
)
returns uuid
language plpgsql
security definer
set search_path=storage,pg_catalog
as $fn$
declare object_id uuid;
begin
  if target_key not like 'tenants/'||target_tenant::text||'/%' then
    raise exception 'invalid R2 tenant scope' using errcode='42501';
  end if;
  insert into storage.object_metadata(
    tenant_id,object_key,original_name,content_type,size_bytes,created_by,status,stored_at
  )
  values(
    target_tenant,target_key,left(coalesce(target_name,'backup-object'),512),
    coalesce(nullif(target_content_type,''),'application/octet-stream'),
    greatest(target_size,0),target_actor,'active',now()
  )
  on conflict(tenant_id,object_key) do update set
    original_name=excluded.original_name,
    content_type=excluded.content_type,
    size_bytes=excluded.size_bytes,
    created_by=coalesce(storage.object_metadata.created_by,excluded.created_by),
    status='active',stored_at=now(),deleted_at=null
  returning id into object_id;
  return object_id;
end
$fn$;

create or replace function public.backup_worker_mark_r2_deleted(target_tenant uuid,target_key text)
returns void
language sql
security definer
set search_path=storage,pg_catalog
as $fn$
  update storage.object_metadata
     set status='deleted',deleted_at=now()
   where tenant_id=target_tenant and object_key=target_key
$fn$;

revoke all on function public.backup_worker_read_table(text,integer,integer) from public;
revoke all on function public.backup_worker_auth_users() from public;
revoke all on function public.backup_worker_create(uuid,text) from public;
revoke all on function public.backup_worker_record_object(uuid,text,text,text,text,bigint,bigint,text) from public;
revoke all on function public.backup_worker_complete(uuid,text,text,jsonb,text,text,jsonb,bigint,text) from public;
revoke all on function public.backup_worker_fail(uuid,text) from public;
revoke all on function public.backup_worker_get(uuid) from public;
revoke all on function public.backup_worker_inventory(uuid) from public;
revoke all on function public.backup_worker_set_verification(uuid,text,text) from public;
revoke all on function public.backup_worker_restore_job(uuid,uuid) from public;
revoke all on function public.backup_worker_set_restore_prebackup(uuid,uuid,uuid) from public;
revoke all on function public.backup_worker_register_r2_object(uuid,text,text,text,bigint,uuid) from public;
revoke all on function public.backup_worker_mark_r2_deleted(uuid,text) from public;

grant execute on function public.backup_worker_read_table(text,integer,integer) to edusentia_worker_runtime;
grant execute on function public.backup_worker_auth_users() to edusentia_worker_runtime;
grant execute on function public.backup_worker_create(uuid,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_record_object(uuid,text,text,text,text,bigint,bigint,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_complete(uuid,text,text,jsonb,text,text,jsonb,bigint,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_fail(uuid,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_get(uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_inventory(uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_set_verification(uuid,text,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_restore_job(uuid,uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_set_restore_prebackup(uuid,uuid,uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_register_r2_object(uuid,text,text,text,bigint,uuid) to edusentia_worker_runtime;
grant execute on function public.backup_worker_mark_r2_deleted(uuid,text) to edusentia_worker_runtime;

grant execute on function public.license_snapshot_for_role(text) to edusentia_worker_runtime;
grant execute on function public.license_feature_enabled(text) to edusentia_worker_runtime;

-- Historical Supabase releases exposed these restore helpers before the Neon
-- worker bridge existed. Some certified clean-room snapshots do not contain
-- them at all, so grant only the helpers that are actually present.
do $restore_helper_grants$
declare signature text;
begin
  foreach signature in array array[
    'public.school_restore_begin(text,text,text,bigint,uuid)',
    'public.school_restore_set_status(uuid,text,text,text)',
    'public.school_restore_clear_operational_data(uuid)',
    'public.school_restore_apply_table(uuid,text,jsonb)',
    'public.school_restore_complete(uuid,jsonb,jsonb,integer,integer,text,text,text,text,text)'
  ]
  loop
    if to_regprocedure(signature) is not null then
      execute format('grant execute on function %s to edusentia_worker_runtime',signature);
    end if;
  end loop;
end
$restore_helper_grants$;

insert into app.schema_migrations(version)
values ('0048l_backup_worker_api')
on conflict do nothing;

commit;
