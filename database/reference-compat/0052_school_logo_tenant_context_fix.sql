-- Repair PostgreSQL 42702 ambiguity in the official school-logo mutation.
-- The previous function declared a PL/pgSQL variable named tenant_id and later
-- compared storage.object_metadata.tenant_id against tenant_id, which PostgreSQL
-- rejects as ambiguous at runtime.
begin;

create or replace function public.set_school_logo_reference(target_logo_url text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','storage','pg_catalog','extensions'
as $function$
declare
  v_tenant_id uuid:=app.current_tenant_id();
  school_id uuid;
  clean_logo text:=btrim(coalesce(target_logo_url,''));
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required' using errcode='42501';
  end if;
  if not public.is_system_admin() then
    raise exception 'Only the School System Administrator can change the official school logo' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit school logo changes' using errcode='42501';
  end if;

  select id into school_id
  from public.school_settings
  order by created_at,id
  limit 1
  for update;

  if school_id is null then
    raise exception 'School identity is unavailable' using errcode='P0002';
  end if;

  if clean_logo='assets/school-logo.png' then
    null;
  elsif clean_logo like ('tenants/'||v_tenant_id::text||'/school-branding/%') and clean_logo not like '%..%' then
    if not exists(
      select 1
      from storage.object_metadata m
      where m.tenant_id=v_tenant_id
        and m.object_key=clean_logo
        and m.status='active'
        and lower(m.content_type)='image/png'
    ) then
      raise exception 'The uploaded school logo was not found in protected R2 storage' using errcode='22023';
    end if;
  else
    raise exception 'Invalid school logo reference' using errcode='22023';
  end if;

  update public.school_settings
  set logo_url=clean_logo,
      updated_at=now()
  where id=school_id;

  return jsonb_build_object(
    'saved',true,
    'school_id',school_id,
    'logo_url',clean_logo,
    'message','Official school logo saved for future school documents.'
  );
end
$function$;

revoke all on function public.set_school_logo_reference(text) from public;
grant execute on function public.set_school_logo_reference(text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0052_school_logo_tenant_context_fix')
on conflict do nothing;

commit;
