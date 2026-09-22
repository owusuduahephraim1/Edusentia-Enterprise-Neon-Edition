-- Certified System Administrator school-logo parity for the Neon isolated tenant runtime.
-- Accepts only tenant-scoped R2 object keys and keeps both the compatibility school settings
-- record and the Neon tenant metadata in sync.
begin;

-- Reconciliation runs as edusentia_runtime, the existing certified function
-- owner; this preserves the established isolated-tenant runtime ACL boundary.
-- owner and the fixed tenant migration identity. Fail closed if an unexpected
-- owner is ever encountered rather than broadening the function's authority.
do $ownership$
declare
  existing_owner text;
begin
  select pg_get_userbyid(p.proowner)
  into existing_owner
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='set_school_logo_reference'
    and pg_get_function_identity_arguments(p.oid)='target_logo_url text'
  limit 1;

  if existing_owner is not null and existing_owner<>current_user then
    raise exception 'Unexpected owner % for public.set_school_logo_reference(text)',existing_owner;
  end if;
end
$ownership$;

create or replace function public.set_school_logo_reference(target_logo_url text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','pg_catalog'
as $function$
declare
  tenant_id uuid:=app.current_tenant_id();
  current_role text:=app.current_role();
  current_aal smallint:=app.current_aal();
  school_id uuid;
begin
  if tenant_id is null then
    raise exception 'Tenant context is required' using errcode='42501';
  end if;
  if current_role<>'system_admin' then
    raise exception 'Only the School System Administrator can update the official school logo' using errcode='42501';
  end if;
  if current_aal<2 then
    raise exception 'A verified MFA session is required to update the official school logo' using errcode='42501';
  end if;
  if coalesce(btrim(target_logo_url),'')='' then
    raise exception 'The school logo reference is required';
  end if;
  if target_logo_url not like ('tenants/'||tenant_id::text||'/school-branding/%') then
    raise exception 'The school logo must use the tenant school-branding storage scope' using errcode='42501';
  end if;
  if not exists(
    select 1
    from app.tenant_licenses tl
    where tl.tenant_id=tenant_id
      and tl.status='active'
      and (tl.starts_at is null or tl.starts_at<=now())
      and (tl.expires_at is null or tl.expires_at>=now())
  ) then
    raise exception 'The current licence does not allow school-setting changes' using errcode='42501';
  end if;

  select id into school_id
  from public.school_settings
  order by created_at
  limit 1
  for update;

  if school_id is null then
    raise exception 'School settings are unavailable';
  end if;

  update public.school_settings
  set logo_url=target_logo_url,
      updated_at=now()
  where id=school_id;

  update app.tenants
  set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{logo_url}',to_jsonb(target_logo_url),true),
      updated_at=now()
  where id=tenant_id;

  return jsonb_build_object(
    'ok',true,
    'school_id',school_id,
    'logo_url',target_logo_url
  );
end
$function$;

revoke all on function public.set_school_logo_reference(text) from public;
grant execute on function public.set_school_logo_reference(text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0049w_school_identity_logo_parity')
on conflict do nothing;

commit;
