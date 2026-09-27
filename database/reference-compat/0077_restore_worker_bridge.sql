-- Complete the Neon-native restore bridge used by worker/src/restore-service.ts.
-- The Supabase edition already exposes the full restore workflow. Neon keeps
-- the same protected UX while implementing the mutation boundary with
-- SECURITY DEFINER functions scoped to the authenticated System Administrator.
begin;

create or replace function public.backup_worker_require_restore_context(target_actor uuid default null)
returns uuid
language plpgsql
security definer
set search_path=public,app,auth,pg_catalog
as $fn$
declare
  actor uuid:=auth.uid();
  app_role text:=coalesce(current_setting('app.role',true),'');
  aal integer:=coalesce(nullif(current_setting('app.aal',true),''),'0')::integer;
begin
  if actor is null then
    raise exception 'Authentication is required' using errcode='42501';
  end if;
  if app_role<>'system_admin' or aal<2 then
    raise exception 'A verified System Administrator session is required' using errcode='42501';
  end if;
  if target_actor is not null and target_actor<>actor then
    raise exception 'Restore actor does not match the authenticated session' using errcode='42501';
  end if;
  return actor;
end
$fn$;

create or replace function public.school_restore_begin(
  target_filename text,
  target_import_path text,
  target_checksum text,
  target_size bigint,
  target_actor uuid
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  actor uuid;
  job_id uuid;
  clean_filename text:=btrim(coalesce(target_filename,''));
  clean_path text:=btrim(coalesce(target_import_path,''));
  clean_checksum text:=lower(btrim(coalesce(target_checksum,'')));
begin
  actor:=public.backup_worker_require_restore_context(target_actor);

  if clean_filename='' or clean_filename !~* '\\.zip$' then
    raise exception 'A valid backup ZIP filename is required' using errcode='22023';
  end if;
  if clean_path='' or clean_path !~ '^restore-imports/[0-9a-f-]{36}\\.zip$' then
    raise exception 'Restore import path is invalid' using errcode='22023';
  end if;
  if clean_checksum !~ '^[a-f0-9]{64}$' then
    raise exception 'Restore package checksum is invalid' using errcode='22023';
  end if;
  if coalesce(target_size,0)<1 or target_size>524288000 then
    raise exception 'Restore package size is invalid' using errcode='22023';
  end if;
  if exists(
    select 1 from public.school_restore_jobs
    where status in ('validating','restoring')
  ) then
    raise exception 'Another school restore is already in progress' using errcode='55000';
  end if;

  insert into public.school_restore_jobs(
    status,source_filename,import_path,package_checksum,package_size,
    initiated_by,error_message,verification_notes,created_at,updated_at
  )
  values(
    'upload_pending',left(clean_filename,512),clean_path,clean_checksum,target_size,
    actor,'','Restore upload authorization created.',now(),now()
  )
  returning id into job_id;

  return job_id;
end
$fn$;

create or replace function public.school_restore_set_status(
  target_job uuid,
  target_status text,
  target_error text,
  target_notes text
)
returns boolean
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  actor uuid;
  clean_status text:=lower(btrim(coalesce(target_status,'')));
begin
  actor:=public.backup_worker_require_restore_context(null);

  if clean_status not in ('upload_pending','uploaded','validating','restoring','completed','failed','cancelled') then
    raise exception 'Restore status is invalid' using errcode='22023';
  end if;

  update public.school_restore_jobs
     set status=clean_status,
         started_at=case when clean_status='restoring' then coalesce(started_at,now()) else started_at end,
         completed_at=case when clean_status in ('completed','failed','cancelled') then now() else completed_at end,
         error_message=left(coalesce(target_error,''),2000),
         verification_notes=left(coalesce(target_notes,''),8000),
         updated_at=now()
   where id=target_job
     and initiated_by=actor;

  if not found then
    raise exception 'Restore job not found' using errcode='P0002';
  end if;
  return true;
end
$fn$;

create or replace function public.school_restore_clear_operational_data(target_job uuid)
returns integer
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  actor uuid;
  allowed constant text[]:=array[
    'profiles','teachers','headteachers','academic_years','terms','classes','school_settings',
    'id_card_settings','id_card_deletion_tombstones','subjects','class_subjects','class_timetable_entries',
    'school_prospectuses','school_prospectus_sections','school_prospectus_items','school_prospectus_revisions',
    'user_class_access','students','student_guardians','guardian_links','enrollments','student_id_cards',
    'id_card_events','staff_id_cards','staff_id_card_events','class_attendance_registers',
    'student_attendance_entries','grading_scales','assessment_schemes','assessment_components',
    'student_reports','subject_scores','subject_results','assessment_score_entries',
    'emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls',
    'report_correction_requests','report_correction_events','student_lifecycle_events','transcript_issuances',
    'certificate_templates','teacher_award_categories','certificate_batches','certificates','certificate_events',
    'report_workflow_events','report_revisions','report_publications','report_card_templates','notifications',
    'notification_outbox','import_batches','import_errors'
  ];
  rec record;
  has_rows boolean;
  affected integer;
  total_affected integer:=0;
begin
  actor:=public.backup_worker_require_restore_context(null);

  if not exists(
    select 1 from public.school_restore_jobs
     where id=target_job and initiated_by=actor and status='validating'
  ) then
    raise exception 'Restore job is not ready to replace school data' using errcode='55000';
  end if;

  -- Newer operational modules can have RESTRICT/NO ACTION foreign keys into
  -- the certified core restore surface. Never erase those modules silently.
  -- The only derived exception is the class admission-number allocator, which
  -- is reconstructed lazily from restored students/classes.
  for rec in
    select sn.nspname source_schema,src.relname source_table
      from pg_constraint con
      join pg_class src on src.oid=con.conrelid
      join pg_namespace sn on sn.oid=src.relnamespace
      join pg_class tgt on tgt.oid=con.confrelid
      join pg_namespace tn on tn.oid=tgt.relnamespace
     where con.contype='f'
       and tn.nspname='public'
       and tgt.relname=any(allowed)
       and not (sn.nspname='public' and src.relname=any(allowed))
       and con.confdeltype in ('a','r')
       and not (sn.nspname='public' and src.relname='student_admission_sequences')
     group by sn.nspname,src.relname
  loop
    execute format('select exists(select 1 from %I.%I limit 1)',rec.source_schema,rec.source_table)
       into has_rows;
    if has_rows then
      raise exception 'Restore cannot replace certified core data while dependent operational table %.% contains records. Create a current full-system backup/restore package first.',
        rec.source_schema,rec.source_table using errcode='55000';
    end if;
  end loop;

  if to_regclass('public.student_admission_sequences') is not null then
    delete from public.student_admission_sequences;
  end if;

  -- Delete in reverse restore order so child rows disappear before parents.
  for rec in
    select table_name
      from unnest(allowed) with ordinality as x(table_name,ord)
     order by ord desc
  loop
    if to_regclass(format('public.%I',rec.table_name)) is null then
      continue;
    end if;

    if rec.table_name='profiles' then
      execute 'delete from public.profiles where id<>$1' using actor;
    else
      execute format('delete from public.%I',rec.table_name);
    end if;
    get diagnostics affected=row_count;
    total_affected:=total_affected+affected;
  end loop;

  update public.school_restore_jobs
     set status='restoring',
         started_at=coalesce(started_at,now()),
         error_message='',
         verification_notes='Validated package and pre-restore safety backup. Replacing certified school data.',
         updated_at=now()
   where id=target_job and initiated_by=actor;

  if not found then
    raise exception 'Restore job not found' using errcode='P0002';
  end if;

  return total_affected;
end
$fn$;

create or replace function public.school_restore_apply_table(
  target_job uuid,
  target_table text,
  target_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  actor uuid;
  allowed constant text[]:=array[
    'profiles','teachers','headteachers','academic_years','terms','classes','school_settings',
    'id_card_settings','id_card_deletion_tombstones','subjects','class_subjects','class_timetable_entries',
    'school_prospectuses','school_prospectus_sections','school_prospectus_items','school_prospectus_revisions',
    'user_class_access','students','student_guardians','guardian_links','enrollments','student_id_cards',
    'id_card_events','staff_id_cards','staff_id_card_events','class_attendance_registers',
    'student_attendance_entries','grading_scales','assessment_schemes','assessment_components',
    'student_reports','subject_scores','subject_results','assessment_score_entries',
    'emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls',
    'report_correction_requests','report_correction_events','student_lifecycle_events','transcript_issuances',
    'certificate_templates','teacher_award_categories','certificate_batches','certificates','certificate_events',
    'report_workflow_events','report_revisions','report_publications','report_card_templates','notifications',
    'notification_outbox','import_batches','import_errors'
  ];
  clean_table text:=lower(btrim(coalesce(target_table,'')));
  column_list text;
  update_list text;
  has_identity boolean:=false;
  statement text;
  affected integer:=0;
  identity_rec record;
  identity_seq text;
  max_identity bigint;
  has_identity_rows boolean;
begin
  actor:=public.backup_worker_require_restore_context(null);

  if clean_table='' or not (clean_table=any(allowed)) then
    raise exception 'Restore table is not allowlisted' using errcode='42501';
  end if;
  if jsonb_typeof(target_rows) is distinct from 'array' then
    raise exception 'Restore table payload must be a JSON array' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.school_restore_jobs
     where id=target_job and initiated_by=actor and status='restoring'
  ) then
    raise exception 'Restore job is not in restoring state' using errcode='55000';
  end if;
  if to_regclass(format('public.%I',clean_table)) is null then
    raise exception 'Restore table does not exist: %',clean_table using errcode='P0002';
  end if;

  select string_agg(format('%I',a.attname),',' order by a.attnum),
         bool_or(a.attidentity<>'')
    into column_list,has_identity
    from pg_attribute a
    join pg_class c on c.oid=a.attrelid
    join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public'
     and c.relname=clean_table
     and a.attnum>0
     and not a.attisdropped
     and a.attgenerated='';

  if coalesce(column_list,'')='' then
    raise exception 'Restore table has no writable columns: %',clean_table using errcode='55000';
  end if;

  if clean_table='profiles' then
    select string_agg(format('%I=excluded.%I',a.attname,a.attname),',' order by a.attnum)
      into update_list
      from pg_attribute a
      join pg_class c on c.oid=a.attrelid
      join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public'
       and c.relname=clean_table
       and a.attnum>0
       and not a.attisdropped
       and a.attgenerated=''
       and a.attname<>'id';
  end if;

  statement:=format(
    'insert into public.%I (%s)%s select %s from jsonb_populate_recordset(null::public.%I,$1) as r%s',
    clean_table,
    column_list,
    case when has_identity then ' overriding system value' else '' end,
    column_list,
    clean_table,
    case when clean_table='profiles' then format(' on conflict (id) do update set %s',update_list) else '' end
  );
  execute statement using target_rows;
  get diagnostics affected=row_count;

  -- Keep identity sequences aligned with explicit IDs restored from the package.
  for identity_rec in
    select a.attname
      from pg_attribute a
      join pg_class c on c.oid=a.attrelid
      join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname=clean_table
       and a.attnum>0 and not a.attisdropped and a.attidentity<>''
  loop
    identity_seq:=pg_get_serial_sequence(format('public.%I',clean_table),identity_rec.attname);
    if identity_seq is not null then
      execute format('select max(%I)::bigint,count(*)>0 from public.%I',identity_rec.attname,clean_table)
        into max_identity,has_identity_rows;
      perform setval(identity_seq::regclass,greatest(coalesce(max_identity,1),1),coalesce(has_identity_rows,false));
    end if;
  end loop;

  update public.school_restore_jobs
     set restored_table_counts=jsonb_set(
           coalesce(restored_table_counts,'{}'::jsonb),
           array[clean_table],
           to_jsonb(affected),
           true
         ),
         updated_at=now()
   where id=target_job and initiated_by=actor;

  return affected;
end
$fn$;

create or replace function public.school_restore_complete(
  target_job uuid,
  target_expected_table_counts jsonb,
  target_storage_counts jsonb,
  target_auth_expected integer,
  target_auth_reconciled integer,
  target_backup_key text,
  target_schema_version text,
  target_school_name text,
  target_school_code text,
  target_notes text
)
returns boolean
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  actor uuid;
  job public.school_restore_jobs%rowtype;
  item record;
  expected_count bigint;
begin
  actor:=public.backup_worker_require_restore_context(null);

  select * into job
    from public.school_restore_jobs
   where id=target_job and initiated_by=actor
   for update;

  if job.id is null then
    raise exception 'Restore job not found' using errcode='P0002';
  end if;
  if job.status<>'restoring' then
    raise exception 'Restore job is not in restoring state' using errcode='55000';
  end if;
  if jsonb_typeof(target_expected_table_counts) is distinct from 'object'
     or jsonb_typeof(target_storage_counts) is distinct from 'object' then
    raise exception 'Restore verification inventories are invalid' using errcode='22023';
  end if;

  for item in select key,value from jsonb_each_text(coalesce(job.restored_table_counts,'{}'::jsonb))
  loop
    expected_count:=coalesce(nullif(target_expected_table_counts->>item.key,'')::bigint,-1);
    if expected_count<0 or expected_count<>item.value::bigint then
      raise exception 'Restore row-count verification failed for %: expected %, restored %',
        item.key,expected_count,item.value using errcode='55000';
    end if;
  end loop;

  update public.school_restore_jobs
     set status='completed',
         expected_table_counts=coalesce(target_expected_table_counts,'{}'::jsonb),
         expected_storage_counts=coalesce(target_storage_counts,'{}'::jsonb),
         restored_storage_counts=coalesce(target_storage_counts,'{}'::jsonb),
         auth_users_expected=greatest(coalesce(target_auth_expected,0),0),
         auth_users_reconciled=greatest(coalesce(target_auth_reconciled,0),0),
         backup_key=left(coalesce(target_backup_key,''),512),
         source_schema_version=left(coalesce(target_schema_version,''),80),
         source_school_name=left(coalesce(target_school_name,''),300),
         source_school_code=left(coalesce(target_school_code,''),80),
         error_message='',
         verification_notes=left(coalesce(target_notes,''),8000),
         completed_at=now(),
         updated_at=now()
   where id=target_job and initiated_by=actor;

  return true;
end
$fn$;

revoke all on function public.backup_worker_require_restore_context(uuid) from public;
revoke all on function public.school_restore_begin(text,text,text,bigint,uuid) from public;
revoke all on function public.school_restore_set_status(uuid,text,text,text) from public;
revoke all on function public.school_restore_clear_operational_data(uuid) from public;
revoke all on function public.school_restore_apply_table(uuid,text,jsonb) from public;
revoke all on function public.school_restore_complete(uuid,jsonb,jsonb,integer,integer,text,text,text,text,text) from public;

grant execute on function public.backup_worker_require_restore_context(uuid) to edusentia_worker_runtime;
grant execute on function public.school_restore_begin(text,text,text,bigint,uuid) to edusentia_worker_runtime;
grant execute on function public.school_restore_set_status(uuid,text,text,text) to edusentia_worker_runtime;
grant execute on function public.school_restore_clear_operational_data(uuid) to edusentia_worker_runtime;
grant execute on function public.school_restore_apply_table(uuid,text,jsonb) to edusentia_worker_runtime;
grant execute on function public.school_restore_complete(uuid,jsonb,jsonb,integer,integer,text,text,text,text,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0077_restore_worker_bridge')
on conflict do nothing;

commit;
