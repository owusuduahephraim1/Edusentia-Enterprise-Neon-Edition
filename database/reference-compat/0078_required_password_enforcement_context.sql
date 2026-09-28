-- Preserve the certified Supabase forced-temporary-password contract across Neon RLS boundaries.
-- The Worker runtime must read the signed-in account's password-change state through
-- a SECURITY DEFINER boundary. Direct public.profiles reads can be hidden by role RLS
-- for non-administrator users, which previously allowed temporary passwords to enter
-- the workspace without the mandatory replacement step.
begin;

create or replace function public.required_password_change_state()
returns boolean
language plpgsql
security definer
set search_path=public,authn,auth,pg_catalog
as $fn$
declare
  actor uuid:=auth.uid();
  profile_required boolean;
  metadata_required boolean:=false;
begin
  if actor is null then
    raise exception 'Authentication is required' using errcode='42501';
  end if;

  select
    coalesce(p.must_change_password,false),
    case lower(coalesce(u.raw_user_meta_data->>'must_change_password','false'))
      when 'true' then true
      when 't' then true
      when '1' then true
      when 'yes' then true
      else false
    end
    into profile_required,metadata_required
    from public.profiles p
    left join authn.users u on u.id=p.id
   where p.id=actor
   limit 1;

  if not found then
    raise exception 'User profile not found' using errcode='P0002';
  end if;

  return coalesce(profile_required,false) or coalesce(metadata_required,false);
end
$fn$;

revoke all on function public.required_password_change_state() from public;
grant execute on function public.required_password_change_state() to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0078_required_password_enforcement_context')
on conflict do nothing;

commit;
