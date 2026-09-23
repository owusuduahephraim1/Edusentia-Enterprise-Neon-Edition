begin;

-- Fix the production identity bridge membership upsert.  The original bridge
-- used a PL/pgSQL parameter named tenant_id and ON CONFLICT(tenant_id,user_id),
-- which PostgreSQL treated as an ambiguous reference.  Use a distinct
-- parameter name and the primary-key constraint explicitly.
--
-- Also complete the certified role enum so Accountant and Student accounts can
-- be represented by the same profile model used by the working reference app.

alter type public.app_role add value if not exists 'accountant';
alter type public.app_role add value if not exists 'student';

create or replace function public.neon_identity_create_auth_user(
  actor_id uuid,
  target_tenant_id uuid,
  target_user_id uuid,
  target_email text,
  target_display_name text,
  target_phone text,
  target_active boolean,
  target_role text,
  target_mfa_required boolean,
  target_must_change_password boolean,
  target_password_hash text,
  target_password_salt text,
  target_password_algorithm text
)
returns jsonb
language plpgsql
security definer
set search_path='public','authn','app','audit','pg_catalog'
as $function$
begin
  if actor_id is null or actor_id<>auth.uid() or not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if target_tenant_id is null or target_tenant_id is distinct from app.current_tenant_id() then
    raise exception 'Tenant context mismatch' using errcode='42501';
  end if;
  if target_user_id is null or btrim(coalesce(target_email,''))='' or btrim(coalesce(target_display_name,''))='' then
    raise exception 'User identity is incomplete' using errcode='22023';
  end if;
  if exists(select 1 from authn.users u where u.id=target_user_id) then
    raise exception 'Authentication account already exists' using errcode='23505';
  end if;
  if btrim(coalesce(target_password_hash,''))='' or btrim(coalesce(target_password_salt,''))='' or btrim(coalesce(target_password_algorithm,''))='' then
    raise exception 'Password credential is incomplete' using errcode='22023';
  end if;

  insert into authn.users(
    id,email,display_name,phone,disabled_at,raw_user_meta_data,raw_app_meta_data
  ) values(
    target_user_id,lower(btrim(target_email)),target_display_name,nullif(target_phone,''),
    case when coalesce(target_active,true) then null else now() end,
    jsonb_build_object('full_name',target_display_name,'must_change_password',coalesce(target_must_change_password,false)),
    jsonb_build_object('role',target_role)
  );

  insert into authn.password_credentials(
    user_id,password_hash,password_salt,algorithm,password_changed_at,failed_attempts,locked_until
  ) values(
    target_user_id,target_password_hash,target_password_salt,target_password_algorithm,now(),0,null
  );

  insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required)
  values(
    target_tenant_id,target_user_id,target_role,
    case when coalesce(target_active,true) then 'active' else 'suspended' end,
    coalesce(target_mfa_required,false)
  )
  on conflict on constraint tenant_memberships_pkey do update set
    role=excluded.role,status=excluded.status,mfa_required=excluded.mfa_required;

  return jsonb_build_object('id',target_user_id,'email',lower(btrim(target_email)));
end
$function$;

create or replace function public.neon_identity_update_auth_user(
  actor_id uuid,
  target_tenant_id uuid,
  target_user_id uuid,
  target_email text,
  target_display_name text,
  target_phone text,
  target_active boolean,
  target_role text,
  target_mfa_required boolean,
  target_must_change_password boolean
)
returns boolean
language plpgsql
security definer
set search_path='public','authn','app','audit','pg_catalog'
as $function$
begin
  if actor_id is null or actor_id<>auth.uid() or not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if target_tenant_id is null or target_tenant_id is distinct from app.current_tenant_id() then
    raise exception 'Tenant context mismatch' using errcode='42501';
  end if;

  update authn.users
  set email=lower(btrim(target_email)),
      display_name=target_display_name,
      phone=nullif(target_phone,''),
      disabled_at=case when coalesce(target_active,true) then null else coalesce(disabled_at,now()) end,
      raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||
        jsonb_build_object('full_name',target_display_name,'must_change_password',coalesce(target_must_change_password,false)),
      raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||
        jsonb_build_object('role',target_role),
      updated_at=now()
  where id=target_user_id;

  if not found then
    raise exception 'Authentication account was not found' using errcode='P0002';
  end if;

  insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required)
  values(
    target_tenant_id,target_user_id,target_role,
    case when coalesce(target_active,true) then 'active' else 'suspended' end,
    coalesce(target_mfa_required,false)
  )
  on conflict on constraint tenant_memberships_pkey do update set
    role=excluded.role,status=excluded.status,mfa_required=excluded.mfa_required;

  return true;
end
$function$;

revoke all on function public.neon_identity_create_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean,text,text,text) from public;
revoke all on function public.neon_identity_update_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean) from public;

grant execute on function public.neon_identity_create_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean,text,text,text) to edusentia_worker_runtime;
grant execute on function public.neon_identity_update_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0065_identity_membership_upsert_fix')
on conflict do nothing;

commit;
