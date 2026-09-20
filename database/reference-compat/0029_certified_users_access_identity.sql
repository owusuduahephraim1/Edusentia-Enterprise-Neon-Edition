-- Certified source commit: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source blob SHA: 0027ec6febfd05cd412c2391f8861b36910211f8
-- Neon adaptation: SQL ACL targets only. Business authorization logic is unchanged.

-- Edusentia Enterprise — Users & Access / IAM hardening
-- Production-equivalent source for tenant deployments.

update public.profiles
set mfa_required=true, updated_at=now()
where public.current_app_role_for(role) in ('system_admin','platform_super_admin')
  and mfa_required is distinct from true;

create or replace function public.protect_profile_security_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
begin
  if public.current_app_role_for(new.role) in ('platform_super_admin','system_admin') then
    new.mfa_required:=true;
  end if;

  if auth.role()='authenticated'
     and (old.role='platform_super_admin'::public.app_role or new.role='platform_super_admin'::public.app_role)
     and (new.role is distinct from old.role
       or new.active is distinct from old.active
       or new.mfa_required is distinct from old.mfa_required
       or new.must_change_password is distinct from old.must_change_password) then
    raise exception 'Platform Super Administrator security fields require the protected setup path' using errcode='42501';
  end if;

  if auth.role()='authenticated' and auth.uid()=old.id then
    if new.role is distinct from old.role
       or new.active is distinct from old.active
       or new.mfa_required is distinct from old.mfa_required
       or new.must_change_password is distinct from old.must_change_password then
      raise exception 'Profile security fields cannot be changed by the account owner' using errcode='42501';
    end if;
  end if;
  return new;
end
$function$;

alter table public.profiles drop constraint if exists profiles_privileged_mfa_required;
alter table public.profiles
  add constraint profiles_privileged_mfa_required
  check (public.current_app_role_for(role) not in ('system_admin','platform_super_admin') or mfa_required);

create or replace function public.require_sensitive_access()
returns void
language plpgsql
stable security definer
set search_path to 'public','extensions'
as $function$
declare
  required boolean:=false;
  profile_role public.app_role;
  configured boolean:=false;
begin
  select p.role,coalesce(p.mfa_required,false)
  into profile_role,configured
  from public.profiles p
  where p.id=auth.uid() and p.active;

  if profile_role is null then
    raise exception 'Active profile required' using errcode='42501';
  end if;

  required:=configured or public.current_app_role_for(profile_role) in ('system_admin','platform_super_admin');
  if required and public.current_aal()<>'aal2' then
    raise exception 'Multi-factor authentication is required' using errcode='42501';
  end if;
end
$function$;

create or replace function public.protect_profile_historical_identity()
returns trigger
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
begin
  if coalesce(current_setting('app.allow_historical_profile_delete',true),'')='on' then
    return old;
  end if;
  if exists(select 1 from public.audit_log a where a.actor_id=old.id) then
    raise exception 'This account has historical audit activity and cannot be permanently deleted. Deactivate the account instead.' using errcode='23503';
  end if;
  return old;
end
$function$;

drop trigger if exists profiles_preserve_historical_identity on public.profiles;
create trigger profiles_preserve_historical_identity
before delete on public.profiles
for each row execute function public.protect_profile_historical_identity();

do $block$
declare t text; p text;
begin
  foreach t in array array['profiles','user_class_access','guardian_links','student_guardians'] loop
    foreach p in array array[
      'platform_license_select_guard','platform_license_insert_guard','platform_license_update_guard','platform_license_delete_guard','license_feature_select_guard_v730'
    ] loop
      execute format('drop policy if exists %I on public.%I',p,t);
    end loop;
  end loop;
end
$block$;

drop policy if exists guardians_select on public.student_guardians;
create policy guardians_select on public.student_guardians
for select to edusentia_worker_runtime
using (
  public.is_records_manager()
  or exists(
    select 1
    from public.guardian_links gl
    where gl.guardian_id=student_guardians.id
      and (gl.auth_user_id=auth.uid() or public.can_view_student(gl.student_id))
  )
);

revoke all on table public.profiles from public;
revoke all on table public.user_class_access from public;
revoke all on table public.guardian_links from public;
revoke all on table public.student_guardians from public;

revoke insert,update,delete,truncate,references,trigger on table public.profiles from edusentia_worker_runtime;
revoke insert,update,delete,truncate,references,trigger on table public.user_class_access from edusentia_worker_runtime;
revoke insert,update,delete,truncate,references,trigger on table public.guardian_links from edusentia_worker_runtime;
revoke insert,update,delete,truncate,references,trigger on table public.student_guardians from edusentia_worker_runtime;

grant select on table public.profiles to edusentia_worker_runtime;
grant select on table public.user_class_access to edusentia_worker_runtime;
grant select on table public.guardian_links to edusentia_worker_runtime;
grant select on table public.student_guardians to edusentia_worker_runtime;

create or replace function public.user_account_lifecycle_summary()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public','auth','extensions'
as $function$
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'accounts',coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id',p.id,
        'role',public.current_app_role_for(p.role),
        'active',p.active,
        'audit_events',(select count(*) from public.audit_log a where a.actor_id=p.id),
        'permanent_delete_allowed',(
          p.id<>auth.uid()
          and not exists(select 1 from public.audit_log a where a.actor_id=p.id)
        ),
        'lifecycle_action',case
          when p.id=auth.uid() then 'current_account'
          when exists(select 1 from public.audit_log a where a.actor_id=p.id) then 'deactivate'
          else 'delete_or_deactivate'
        end
      ) order by lower(p.full_name),p.id)
      from public.profiles p
      where public.current_app_role_for(p.role) in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian','accountant','student')
    ),'[]'::jsonb)
  );
end
$function$;

revoke all on function public.user_account_lifecycle_summary() from public;
grant execute on function public.user_account_lifecycle_summary() to edusentia_worker_runtime;


insert into app.schema_migrations(version)
values ('0029_certified_users_access_identity')
on conflict do nothing;

update app.release_identity
set schema_version='0029'
where edition='Edusentia Enterprise Neon Edition';
