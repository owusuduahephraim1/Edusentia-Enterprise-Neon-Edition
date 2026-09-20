-- Certified source commit: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source blob SHA: 556e6eee5b7a65caeee33c2bb4c4c11ddab1cf90
-- Archive table contracts were extracted read-only from certified production.
-- Neon adaptation changes SQL privilege targets only.

begin;

create table if not exists public.audit_log_archives(
  id uuid primary key default gen_random_uuid(),
  archive_scope text not null check(archive_scope in('selected','full')),
  reason text not null default '',
  event_count bigint not null default 0 check(event_count>=0),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_log_archive_entries(
  archive_id uuid not null references public.audit_log_archives(id) on delete cascade,
  original_event_id bigint not null,
  actor_id uuid,
  table_name text not null,
  record_id uuid,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  reason text not null default '',
  original_created_at timestamptz not null,
  primary key(archive_id,original_event_id)
);

create index if not exists audit_log_archives_created_at_idx
  on public.audit_log_archives(created_at desc);
create index if not exists audit_log_archive_entries_original_created_at_idx
  on public.audit_log_archive_entries(original_created_at desc);

alter table public.audit_log_archives enable row level security;
alter table public.audit_log_archive_entries enable row level security;

revoke all on table public.audit_log_archives from public;
revoke all on table public.audit_log_archive_entries from public;
revoke all on table public.audit_log_archives from edusentia_worker_runtime;
revoke all on table public.audit_log_archive_entries from edusentia_worker_runtime;

-- Edusentia Enterprise r40
-- Audit Trail hardening, pagination, and retained archive access.
-- Production NIS tenant migration applied 26 Aug 2026.

-- Force tenant clients through MFA-guarded SECURITY DEFINER RPCs. The core UI
-- does not require direct table SELECT and direct access would bypass
-- require_sensitive_access().
revoke all on table public.audit_log from edusentia_worker_runtime;
revoke all on table public.audit_log from public;

comment on table public.audit_log is
  'Protected audit trail. Authenticated clients must use guarded audit RPCs; direct table reads are revoked so MFA-sensitive access cannot be bypassed.';

create or replace function public.list_audit_events_v2(
  target_table text default null,
  target_action text default null,
  target_actor_id uuid default null,
  target_record_id uuid default null,
  page_number integer default 1,
  page_size integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  safe_page integer:=greatest(coalesce(page_number,1),1);
  safe_size integer:=least(greatest(coalesce(page_size,25),1),100);
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  return (
    with matching as (
      select a.*,p.full_name actor_name,p.role::text actor_role
      from public.audit_log a
      left join public.profiles p on p.id=a.actor_id
      where (target_table is null or a.table_name=target_table)
        and (target_action is null or a.action=target_action)
        and (target_actor_id is null or a.actor_id=target_actor_id)
        and (target_record_id is null or a.record_id=target_record_id)
    ), counts as (
      select count(*)::bigint total from matching
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc) from (
        select * from matching
        order by created_at desc,id desc
        limit safe_size offset (safe_page-1)*safe_size
      ) q),'[]'::jsonb),
      'total',(select total from counts),
      'page',safe_page,
      'page_size',safe_size,
      'pages',greatest(1,ceil((select total from counts)::numeric/safe_size)::integer),
      'tables',coalesce((select jsonb_agg(x.table_name order by x.table_name) from (select distinct table_name from public.audit_log) x),'[]'::jsonb),
      'actions',coalesce((select jsonb_agg(x.action order by x.action) from (select distinct action from public.audit_log) x),'[]'::jsonb)
    )
  );
end
$function$;

create or replace function public.list_audit_archives_v1(
  page_number integer default 1,
  page_size integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  safe_page integer:=greatest(coalesce(page_number,1),1);
  safe_size integer:=least(greatest(coalesce(page_size,25),1),100);
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  return (
    with matching as (
      select a.*,p.full_name created_by_name,p.role::text created_by_role
      from public.audit_log_archives a
      left join public.profiles p on p.id=a.created_by
    ), counts as (
      select count(*)::bigint total from matching
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc) from (
        select * from matching
        order by created_at desc,id desc
        limit safe_size offset (safe_page-1)*safe_size
      ) q),'[]'::jsonb),
      'total',(select total from counts),
      'page',safe_page,
      'page_size',safe_size,
      'pages',greatest(1,ceil((select total from counts)::numeric/safe_size)::integer)
    )
  );
end
$function$;

create or replace function public.list_audit_archive_entries_v1(
  target_archive_id uuid,
  page_number integer default 1,
  page_size integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  safe_page integer:=greatest(coalesce(page_number,1),1);
  safe_size integer:=least(greatest(coalesce(page_size,25),1),100);
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if target_archive_id is null then
    raise exception 'Archive id is required';
  end if;

  return (
    with matching as (
      select e.*,p.full_name actor_name,p.role::text actor_role
      from public.audit_log_archive_entries e
      left join public.profiles p on p.id=e.actor_id
      where e.archive_id=target_archive_id
    ), counts as (
      select count(*)::bigint total from matching
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.original_created_at desc,q.original_event_id desc) from (
        select * from matching
        order by original_created_at desc,original_event_id desc
        limit safe_size offset (safe_page-1)*safe_size
      ) q),'[]'::jsonb),
      'total',(select total from counts),
      'page',safe_page,
      'page_size',safe_size,
      'pages',greatest(1,ceil((select total from counts)::numeric/safe_size)::integer)
    )
  );
end
$function$;






revoke all on function public.list_audit_events_v2(text,text,uuid,uuid,integer,integer) from public;
revoke all on function public.list_audit_archives_v1(integer,integer) from public;
revoke all on function public.list_audit_archive_entries_v1(uuid,integer,integer) from public;

revoke all on function public.list_audit_events_v2(text,text,uuid,uuid,integer,integer) from edusentia_worker_runtime;
revoke all on function public.list_audit_archives_v1(integer,integer) from edusentia_worker_runtime;
revoke all on function public.list_audit_archive_entries_v1(uuid,integer,integer) from edusentia_worker_runtime;

grant execute on function public.list_audit_events_v2(text,text,uuid,uuid,integer,integer)
  to edusentia_worker_runtime;
grant execute on function public.list_audit_archives_v1(integer,integer)
  to edusentia_worker_runtime;
grant execute on function public.list_audit_archive_entries_v1(uuid,integer,integer)
  to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0040_certified_audit_trail_v1')
on conflict do nothing;

update app.release_identity
set schema_version='0040'
where edition='Edusentia Enterprise Neon Edition';

commit;
