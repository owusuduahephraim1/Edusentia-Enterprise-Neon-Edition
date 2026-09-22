-- Permanent Audit Trail reset controls for the certified tenant runtime.
-- Only the System Administrator at verified MFA assurance may invoke them.
-- The deleted audit rows are not copied into audit archives. A minimal
-- maintenance-log entry records that a destructive reset occurred.
begin;

create or replace function public.reset_audit_log(confirmation_text text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  confirmation text:=upper(btrim(coalesce(confirmation_text,'')));
  reset_scope text;
  active_deleted integer:=0;
  archive_entries_deleted integer:=0;
  archive_batches_deleted integer:=0;
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can permanently reset audit history' using errcode='42501';
  end if;

  perform public.require_sensitive_access();

  reset_scope:=case confirmation
    when 'RESET ACTIVE AUDIT' then 'active'
    when 'DELETE ALL AUDIT ARCHIVES' then 'archives'
    when 'RESET ALL AUDIT HISTORY' then 'all'
    else null
  end;

  if reset_scope is null then
    raise exception 'Confirmation text is invalid';
  end if;

  perform pg_advisory_xact_lock(hashtext('rce-school-audit-permanent-reset'));

  if reset_scope in ('active','all') then
    lock table public.audit_log in access exclusive mode;
    select count(*)::integer into active_deleted from public.audit_log;
    truncate table public.audit_log restart identity;
  end if;

  if reset_scope in ('archives','all') then
    lock table public.audit_log_archive_entries in access exclusive mode;
    lock table public.audit_log_archives in access exclusive mode;

    select count(*)::integer into archive_entries_deleted
    from public.audit_log_archive_entries;

    select count(*)::integer into archive_batches_deleted
    from public.audit_log_archives;

    delete from public.audit_log_archive_entries;
    delete from public.audit_log_archives;
  end if;

  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details)
  values(
    auth.uid(),
    'PERMANENT_RESET_AUDIT_HISTORY',
    active_deleted+archive_entries_deleted,
    jsonb_build_object(
      'scope',reset_scope,
      'active_events_deleted',active_deleted,
      'archive_entries_deleted',archive_entries_deleted,
      'archive_batches_deleted',archive_batches_deleted,
      'confirmed_at',now()
    )
  );

  return jsonb_build_object(
    'ok',true,
    'scope',reset_scope,
    'active_events_deleted',active_deleted,
    'archive_entries_deleted',archive_entries_deleted,
    'archive_batches_deleted',archive_batches_deleted,
    'deleted_total',active_deleted+archive_entries_deleted,
    'reset_at',now()
  );
end
$function$;

revoke all on function public.reset_audit_log(text) from public;
grant execute on function public.reset_audit_log(text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0049y_audit_permanent_reset')
on conflict do nothing;

commit;
