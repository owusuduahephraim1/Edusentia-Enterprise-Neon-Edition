-- Edusentia Enterprise Neon Edition — certified report PDF integrity + R2 adaptation.
-- Certified source baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source file: tenant-report-pdf-integrity-r40.sql
-- Provider adaptation: Supabase storage.objects is replaced by tenant-scoped storage.object_metadata + Cloudflare R2.
-- Finance adaptation: certified hold policy/override semantics use the Neon-native finance.invoices ledger until the
-- full certified finance overlay supersedes this compatibility implementation.

begin;

create table if not exists public.finance_hold_policy(
  id smallint primary key default 1 constraint finance_hold_policy_id_check check(id=1),
  enabled boolean not null default false,
  minimum_outstanding numeric not null default 0 constraint finance_hold_policy_minimum_outstanding_check check(minimum_outstanding>=0),
  grace_days integer not null default 0 constraint finance_hold_policy_grace_days_check check(grace_days>=0 and grace_days<=365),
  block_grade_details boolean not null default true,
  block_report_pdf boolean not null default true,
  block_transcript boolean not null default false,
  block_certificate boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.finance_hold_policy(id,enabled,minimum_outstanding,grace_days,block_grade_details,block_report_pdf,block_transcript,block_certificate)
values(1,false,0,0,true,true,false,false)
on conflict(id) do nothing;

create table if not exists public.finance_hold_overrides(
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete restrict,
  mode text not null constraint finance_hold_overrides_mode_check check(mode in('force_lock','force_unlock')),
  reason text not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_hold_overrides_check check(ends_at is null or ends_at>starts_at)
);

create index if not exists finance_hold_overrides_student_idx
  on public.finance_hold_overrides(student_id,active,starts_at desc);

alter table public.finance_hold_policy enable row level security;
alter table public.finance_hold_overrides enable row level security;
revoke all on table public.finance_hold_policy from public;
revoke all on table public.finance_hold_overrides from public;
revoke all on table public.finance_hold_policy from edusentia_worker_runtime;
revoke all on table public.finance_hold_overrides from edusentia_worker_runtime;

CREATE OR REPLACE FUNCTION public.finance_feature_enabled(feature_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((public.license_effective_entitlement()->'plan'->'feature_flags'->>feature_code)::boolean,false)
$function$;

create or replace function public.finance_student_outstanding(target_student_id uuid)
returns numeric
language sql
stable
security definer
set search_path to 'public','finance','app','extensions'
as $$
  select coalesce(sum(greatest(i.amount_due-i.amount_paid,0)),0)::numeric
  from finance.invoices i
  where i.tenant_id=app.current_tenant_id()
    and i.student_id=target_student_id
    and i.status<>'void'
$$;

create or replace function public.finance_student_hold_status(target_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','finance','app','extensions'
as $$
declare
  p public.finance_hold_policy%rowtype;
  o public.finance_hold_overrides%rowtype;
  overdue numeric:=0;
  total_due numeric:=0;
  automatic boolean:=false;
  locked boolean:=false;
  reason text:='';
begin
  total_due:=public.finance_student_outstanding(target_student_id);
  select * into p from public.finance_hold_policy where id=1;

  if not public.finance_feature_enabled('financial_holds') then
    return jsonb_build_object(
      'locked',false,'automatic',false,'outstanding',total_due,'overdue',0,'reason','',
      'block_grade_details',false,'block_report_pdf',false,'block_transcript',false,'block_certificate',false
    );
  end if;

  select coalesce(sum(greatest(i.amount_due-i.amount_paid,0)),0)
    into overdue
  from finance.invoices i
  where i.tenant_id=app.current_tenant_id()
    and i.student_id=target_student_id
    and i.status<>'void'
    and greatest(i.amount_due-i.amount_paid,0)>0
    and coalesce(i.due_date,current_date)+(coalesce(p.grace_days,0)||' days')::interval<now();

  automatic:=coalesce(p.enabled,false) and overdue>coalesce(p.minimum_outstanding,0);

  select * into o
  from public.finance_hold_overrides x
  where x.student_id=target_student_id
    and x.active
    and x.starts_at<=now()
    and (x.ends_at is null or x.ends_at>now())
  order by x.created_at desc
  limit 1;

  if o.id is not null then
    locked:=o.mode='force_lock';
    reason:=o.reason;
  else
    locked:=automatic;
    if automatic then reason:='Outstanding school fees require financial clearance.'; end if;
  end if;

  return jsonb_build_object(
    'locked',locked,'automatic',automatic,'outstanding',total_due,'overdue',overdue,'reason',reason,
    'block_grade_details',locked and coalesce(p.block_grade_details,true),
    'block_report_pdf',locked and coalesce(p.block_report_pdf,true),
    'block_transcript',locked and coalesce(p.block_transcript,false),
    'block_certificate',locked and coalesce(p.block_certificate,false)
  );
end
$$;


CREATE OR REPLACE FUNCTION public.can_publish_report(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_system_admin()
    or public.is_assigned_class_teacher(public.report_class_id(target_report_id))
$function$;

CREATE OR REPLACE FUNCTION public.can_view_report_pdf(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_view_report(target_report_id)
    and (
      public.current_app_role()::text in ('system_admin','principal','class_teacher','subject_teacher')
      or not coalesce((public.finance_student_hold_status(public.report_student_id(target_report_id))->>'block_report_pdf')::boolean,false)
    )
$function$;

CREATE OR REPLACE FUNCTION public.can_manage_report_pdf(target_report_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select exists(
    select 1 from public.student_reports r
    where r.id=target_report_id and r.status='published' and r.deleted_at is null
  )
  and public.can_publish_report(target_report_id)
  and exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.active
      and (
        (not coalesce(p.mfa_required,false) and public.current_app_role()::text<>'system_admin')
        or public.current_aal()='aal2'
      )
  )
$function$;

CREATE OR REPLACE FUNCTION public.can_delete_report_pdf_object(target_report_id uuid, target_storage_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.can_manage_report_pdf(target_report_id)
    and not exists(
      select 1 from public.report_publications p
      where p.report_id=target_report_id
        and p.revoked_at is null
        and p.storage_path=target_storage_path
    )
$function$;

CREATE OR REPLACE FUNCTION public.list_report_pdf_paths(target_report_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_delete_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return coalesce(
    (select array_agg(distinct p.storage_path order by p.storage_path)
     from public.report_publications p
     where p.report_id=target_report_id and btrim(coalesce(p.storage_path,''))<>''),
    '{}'::text[]
  );
end $function$;

create or replace function public.register_report_pdf(
  target_report_id uuid,
  target_storage_path text,
  target_checksum text default '',
  target_page_count integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','storage','app','extensions'
as $$
declare
  publicationid uuid;
  expected_prefix text;
begin
  if not public.can_manage_report_pdf(target_report_id) then
    raise exception 'Only an authorized publisher with required MFA can register the official PDF' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  if not exists(
    select 1 from public.student_reports
    where id=target_report_id and status='published' and deleted_at is null
  ) then
    raise exception 'Only a Principal-approved published report can receive an official PDF';
  end if;

  expected_prefix:='tenants/'||app.current_tenant_id()::text||'/report-pdfs/'||target_report_id::text||'/';
  if btrim(coalesce(target_storage_path,''))=''
     or target_storage_path not like expected_prefix||'%'
     or target_storage_path like '%..%' then
    raise exception 'Official report PDF path is invalid';
  end if;

  if btrim(coalesce(target_checksum,'')) !~ '^[0-9A-Fa-f]{64}$' then
    raise exception 'Official report PDF checksum must be a SHA-256 digest';
  end if;
  if target_page_count is null or target_page_count<1 or target_page_count>200 then
    raise exception 'Official report PDF page count is invalid';
  end if;

  if not exists(
    select 1
    from storage.object_metadata o
    where o.tenant_id=app.current_tenant_id()
      and o.object_key=target_storage_path
      and o.status='active'
      and lower(o.content_type)='application/pdf'
  ) then
    raise exception 'Uploaded official report PDF object was not found';
  end if;

  update public.report_publications
     set storage_path=target_storage_path,
         checksum=lower(target_checksum),
         page_count=target_page_count
   where report_id=target_report_id and revoked_at is null
   returning id into publicationid;

  if publicationid is null then raise exception 'Active publication not found'; end if;
  return (select to_jsonb(p) from public.report_publications p where p.id=publicationid);
end
$$;

create or replace function public.get_report_pdf_descriptor(target_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','extensions'
as $
declare result jsonb;
begin
  if not public.can_view_report_pdf(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select jsonb_build_object(
    'report_id',p.report_id,
    'publication_id',p.id,
    'storage_path',p.storage_path,
    'checksum',p.checksum,
    'page_count',p.page_count,
    'published_at',p.published_at
  ) into result
  from public.report_publications p
  where p.report_id=target_report_id
    and p.revoked_at is null
    and btrim(coalesce(p.storage_path,''))<>''
  order by p.published_at desc
  limit 1;
  return coalesce(result,'{}'::jsonb);
end
$;

revoke all on function public.finance_feature_enabled(text) from public;
revoke all on function public.finance_student_outstanding(uuid) from public;
revoke all on function public.finance_student_hold_status(uuid) from public;
revoke all on function public.can_publish_report(uuid) from public;
revoke all on function public.can_view_report_pdf(uuid) from public;
revoke all on function public.can_manage_report_pdf(uuid) from public;
revoke all on function public.can_delete_report_pdf_object(uuid,text) from public;
revoke all on function public.list_report_pdf_paths(uuid) from public;
revoke all on function public.register_report_pdf(uuid,text,text,integer) from public;
revoke all on function public.get_report_pdf_descriptor(uuid) from public;

revoke all on function public.finance_feature_enabled(text) from edusentia_worker_runtime;
revoke all on function public.finance_student_outstanding(uuid) from edusentia_worker_runtime;
revoke all on function public.finance_student_hold_status(uuid) from edusentia_worker_runtime;
revoke all on function public.can_publish_report(uuid) from edusentia_worker_runtime;
revoke all on function public.can_view_report_pdf(uuid) from edusentia_worker_runtime;
revoke all on function public.can_manage_report_pdf(uuid) from edusentia_worker_runtime;
revoke all on function public.can_delete_report_pdf_object(uuid,text) from edusentia_worker_runtime;
revoke all on function public.list_report_pdf_paths(uuid) from edusentia_worker_runtime;
revoke all on function public.register_report_pdf(uuid,text,text,integer) from edusentia_worker_runtime;
revoke all on function public.get_report_pdf_descriptor(uuid) from edusentia_worker_runtime;

-- Worker route helpers: callable only through fixed Worker endpoints, never arbitrary browser SQL.
grant execute on function public.can_view_report_pdf(uuid) to edusentia_worker_runtime;
grant execute on function public.can_manage_report_pdf(uuid) to edusentia_worker_runtime;
grant execute on function public.can_delete_report_pdf_object(uuid,text) to edusentia_worker_runtime;
grant execute on function public.get_report_pdf_descriptor(uuid) to edusentia_worker_runtime;

-- Certified stable frontend RPC surface.
grant execute on function public.list_report_pdf_paths(uuid) to edusentia_worker_runtime;
grant execute on function public.register_report_pdf(uuid,text,text,integer) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0045_certified_report_pdf_integrity_r2')
on conflict do nothing;

update app.release_identity
set schema_version='0045'
where edition='Edusentia Enterprise Neon Edition';

commit;
