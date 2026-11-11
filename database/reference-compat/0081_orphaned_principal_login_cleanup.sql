-- Safely remove tenant login identities even when a linked staff profile was
-- already removed. The authn.users row and tenant membership remain the
-- authoritative proof that the login belongs to this tenant.
begin;

create or replace function public.neon_identity_delete_auth_user(
  actor_id uuid,
  tenant_id uuid,
  target_user_id uuid,
  reason_text text default ''
)
returns boolean
language plpgsql
security definer
set search_path='public','authn','app','audit','pg_catalog'
as $function$
declare
  target_role text;
  target_active boolean;
  other_admins integer;
  has_profile boolean;
  has_membership boolean;
  is_accounts_office boolean;
begin
  if actor_id is null or actor_id<>auth.uid() or not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if tenant_id is null or tenant_id is distinct from app.current_tenant_id() then
    raise exception 'Tenant context mismatch' using errcode='42501';
  end if;
  if target_user_id=actor_id then
    raise exception 'You cannot delete your current account' using errcode='22023';
  end if;

  select
    coalesce(public.current_app_role_for(p.role)::text,m.role,u.raw_app_meta_data->>'role'),
    coalesce(p.active,m.status='active',u.disabled_at is null),
    p.id is not null,
    m.user_id is not null,
    exists(select 1 from public.accounts_office_staff a where a.profile_id=u.id)
  into target_role,target_active,has_profile,has_membership,is_accounts_office
  from authn.users u
  left join public.profiles p on p.id=u.id
  left join app.tenant_memberships m on m.user_id=u.id and m.tenant_id=$2
  where u.id=target_user_id
  limit 1;

  if not found then
    raise exception 'Authentication account was not found' using errcode='P0002';
  end if;
  if not coalesce(has_profile,false) and not coalesce(has_membership,false) and target_role is distinct from 'principal' then
    raise exception 'User account is not linked to this school' using errcode='42501';
  end if;

  if coalesce(is_accounts_office,false) or target_role='accountant' then
    raise exception 'Accounts Office Staff accounts must be archived, not permanently deleted' using errcode='23514';
  end if;

  if target_active and target_role='system_admin' then
    select count(*)::integer into other_admins
    from public.profiles p
    where p.active and public.current_app_role_for(p.role)::text='system_admin' and p.id<>target_user_id;
    if coalesce(other_admins,0)<1 then
      raise exception 'At least one active School System Administrator must remain' using errcode='23514';
    end if;
  end if;

  perform audit.record_auth_event(
    tenant_id,actor_id,'auth.user.delete',
    jsonb_build_object(
      'target_user_id',target_user_id,
      'reason',coalesce(reason_text,''),
      'orphaned_profile',not coalesce(has_profile,false)
    )
  );

  delete from authn.users where id=target_user_id;
  if not found then
    raise exception 'Authentication account was not found' using errcode='P0002';
  end if;
  return true;
end
$function$;

revoke all on function public.neon_identity_delete_auth_user(uuid,uuid,uuid,text) from public;
grant execute on function public.neon_identity_delete_auth_user(uuid,uuid,uuid,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0081_orphaned_principal_login_cleanup')
on conflict do nothing;

commit;
