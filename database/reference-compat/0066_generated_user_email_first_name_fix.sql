-- Neon Edition generated school user email repair.
-- Fixes uppercase first-letter loss in the certified email generator by
-- lowercasing the requested base before removing non [a-z0-9] characters.
begin;

create or replace function public.generate_nip_user_email(
  actor_id uuid,
  requested_base text,
  target_user_id uuid default null::uuid
)
returns text
language plpgsql
security definer
set search_path to 'pg_catalog','public','authn','extensions'
as $function$
declare
  base_name text:=regexp_replace(lower(coalesce(requested_base,'')),'[^a-z0-9]','','g');
  email_domain text:=public.canonical_school_email_domain();
  candidate text;
  suffix integer:=1;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles p
    where p.id=actor_id
      and p.active
      and public.current_app_role_for(p.role)='system_admin'
  ) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if auth.uid() is not null and auth.uid()<>actor_id then
    raise exception 'Access denied' using errcode='42501';
  end if;

  base_name:=left(coalesce(nullif(base_name,''),'user'),40);
  perform pg_advisory_xact_lock(
    hashtextextended('school_user_email_'||email_domain||'_'||base_name,0)
  );
  candidate:=base_name||'@'||email_domain;

  while exists(
    select 1 from authn.users u
    where lower(coalesce(u.email,''))=lower(candidate)
      and (target_user_id is null or u.id<>target_user_id)
  ) loop
    suffix:=suffix+1;
    if suffix>99999 then
      raise exception 'A unique school user email address could not be generated';
    end if;
    candidate:=left(base_name,greatest(1,40-length(suffix::text)))||
      suffix::text||'@'||email_domain;
  end loop;
  return candidate;
end
$function$;

revoke all on function public.generate_nip_user_email(uuid,text,uuid) from public;
grant execute on function public.generate_nip_user_email(uuid,text,uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0066_generated_user_email_first_name_fix')
on conflict do nothing;

commit;
