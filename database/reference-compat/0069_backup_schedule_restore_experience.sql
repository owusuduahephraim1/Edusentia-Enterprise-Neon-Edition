-- WhatsApp-style school backup scheduling and recoverable ZIP restore metadata.
-- Additive operational migration: keeps the certified compatibility schema identity at 0048.
begin;

alter table public.school_settings
  add column if not exists backup_schedule_mode text not null default 'off',
  add column if not exists backup_schedule_updated_at timestamptz;

do $constraints$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.school_settings'::regclass
      and conname='school_settings_backup_schedule_mode_check'
  ) then
    alter table public.school_settings
      add constraint school_settings_backup_schedule_mode_check
      check(backup_schedule_mode in ('off','weekly','monthly'));
  end if;
end
$constraints$;

alter table public.backup_exports
  add column if not exists trigger_mode text not null default 'manual';

do $constraints$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.backup_exports'::regclass
      and conname='backup_exports_trigger_mode_check'
  ) then
    alter table public.backup_exports
      add constraint backup_exports_trigger_mode_check
      check(trigger_mode in ('manual','scheduled','pre_restore'));
  end if;
end
$constraints$;

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
    expires_at,error_message,verification_status,verification_notes,trigger_mode
  )
  values(
    '','', 'processing','{}'::jsonb,target_actor,backup_key,'7.4.0','full',
    '','', '{}'::jsonb,0,true,now(),null,'','not_tested',
    case
      when stored_mode='scheduled' then 'Scheduled full backup'
      when stored_mode='pre_restore' then 'Automatic pre-restore safety backup'
      else 'Manual full backup'
    end,
    stored_mode
  )
  returning * into result;

  return to_jsonb(result);
end
$fn$;

create or replace function public.backup_worker_schedule_policy()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_catalog
as $fn$
declare
  configured_mode text:='off';
  configured_at timestamptz;
  latest_scheduled timestamptz;
  next_scheduled timestamptz;
begin
  select coalesce(backup_schedule_mode,'off'),backup_schedule_updated_at
    into configured_mode,configured_at
    from public.school_settings
   order by created_at,id
   limit 1;

  configured_mode:=coalesce(configured_mode,'off');

  select max(coalesce(completed_at,created_at))
    into latest_scheduled
    from public.backup_exports
   where status='completed'
     and backup_type='full'
     and trigger_mode='scheduled';

  if configured_mode='weekly' then
    next_scheduled:=coalesce(latest_scheduled,configured_at,now())+interval '7 days';
  elsif configured_mode='monthly' then
    next_scheduled:=coalesce(latest_scheduled,configured_at,now())+interval '1 month';
  else
    next_scheduled:=null;
  end if;

  return jsonb_build_object(
    'mode',configured_mode,
    'updated_at',configured_at,
    'latest_scheduled_backup_at',latest_scheduled,
    'next_scheduled_backup_at',next_scheduled,
    'due',configured_mode<>'off' and next_scheduled is not null and now()>=next_scheduled
  );
end
$fn$;

create or replace function public.backup_worker_set_schedule_policy(target_mode text,target_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_catalog
as $fn$
declare
  normalized text:=lower(btrim(coalesce(target_mode,'')));
  settings_id uuid;
  previous_mode text;
begin
  if normalized not in ('off','weekly','monthly') then
    raise exception 'Backup schedule must be off, weekly, or monthly' using errcode='22023';
  end if;

  select id,coalesce(backup_schedule_mode,'off')
    into settings_id,previous_mode
    from public.school_settings
   order by created_at,id
   limit 1
   for update;

  if settings_id is null then
    insert into public.school_settings(backup_schedule_mode,backup_schedule_updated_at,updated_at)
    values(normalized,now(),now())
    returning id into settings_id;
  else
    update public.school_settings
       set backup_schedule_mode=normalized,
           backup_schedule_updated_at=now(),
           updated_at=now()
     where id=settings_id;
  end if;

  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(
    target_actor,'school_settings',settings_id,'BACKUP_SCHEDULE_CHANGED',
    jsonb_build_object('schedule_mode',previous_mode),
    jsonb_build_object('schedule_mode',normalized),
    'System Administrator changed automatic backup frequency.'
  );

  return public.backup_worker_schedule_policy();
end
$fn$;

revoke all on function public.backup_worker_create(uuid,text) from public;
revoke all on function public.backup_worker_schedule_policy() from public;
revoke all on function public.backup_worker_set_schedule_policy(text,uuid) from public;

grant execute on function public.backup_worker_create(uuid,text) to edusentia_worker_runtime;
grant execute on function public.backup_worker_schedule_policy() to edusentia_worker_runtime;
grant execute on function public.backup_worker_set_schedule_policy(text,uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0069_backup_schedule_restore_experience')
on conflict do nothing;

update app.release_identity
set schema_version='0048'
where edition='Edusentia Enterprise Neon Edition';

commit;
