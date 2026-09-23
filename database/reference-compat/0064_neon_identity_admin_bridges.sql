-- Production rollout marker: identity bridge quality gate verified.
begin;

-- Secure Neon-native identity administration bridges.
-- The browser never receives database credentials. The Cloudflare Worker uses
-- the least-privilege edusentia_worker_runtime role, while these SECURITY
-- DEFINER functions perform only the protected identity mutations that the
-- working Supabase service-role implementation performs.

create or replace function public.neon_identity_create_auth_user(
  actor_id uuid,
  tenant_id uuid,
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
  if tenant_id is null or tenant_id is distinct from app.current_tenant_id() then
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
    tenant_id,target_user_id,target_role,
    case when coalesce(target_active,true) then 'active' else 'suspended' end,
    coalesce(target_mfa_required,false)
  )
  on conflict(tenant_id,user_id) do update set
    role=excluded.role,status=excluded.status,mfa_required=excluded.mfa_required;

  return jsonb_build_object('id',target_user_id,'email',lower(btrim(target_email)));
end
$function$;

create or replace function public.neon_identity_update_auth_user(
  actor_id uuid,
  tenant_id uuid,
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
  if tenant_id is null or tenant_id is distinct from app.current_tenant_id() then
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
    tenant_id,target_user_id,target_role,
    case when coalesce(target_active,true) then 'active' else 'suspended' end,
    coalesce(target_mfa_required,false)
  )
  on conflict(tenant_id,user_id) do update set
    role=excluded.role,status=excluded.status,mfa_required=excluded.mfa_required;

  return true;
end
$function$;

create or replace function public.neon_identity_link_guardian(
  actor_id uuid,
  target_guardian_id uuid,
  target_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path='public','authn','app','audit','pg_catalog'
as $function$
declare affected integer;
begin
  if actor_id is null or actor_id<>auth.uid() or not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();

  update public.guardian_links
  set auth_user_id=target_user_id
  where guardian_id=target_guardian_id;

  get diagnostics affected=row_count;
  if affected<1 then
    raise exception 'Parent or Guardian record is not linked to a student' using errcode='P0002';
  end if;
  return true;
end
$function$;

create or replace function public.neon_identity_reset_password(
  actor_id uuid,
  tenant_id uuid,
  target_user_id uuid,
  target_password_hash text,
  target_password_salt text,
  target_password_algorithm text,
  target_must_change_password boolean
)
returns boolean
language plpgsql
security definer
set search_path='public','authn','app','audit','pg_catalog'
as $function$
declare actor_role text;
begin
  if actor_id is null or actor_id<>auth.uid() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if tenant_id is null or tenant_id is distinct from app.current_tenant_id() then
    raise exception 'Tenant context mismatch' using errcode='42501';
  end if;

  actor_role:=public.current_app_role()::text;
  if actor_id<>target_user_id then
    if actor_role<>'system_admin' then
      raise exception 'Access denied' using errcode='42501';
    end if;
    perform public.require_sensitive_access();
  elsif not exists(select 1 from public.profiles p where p.id=actor_id and p.active) then
    raise exception 'User profile not found' using errcode='P0002';
  end if;

  if not exists(select 1 from authn.users u where u.id=target_user_id) then
    raise exception 'Authentication account was not found' using errcode='P0002';
  end if;

  insert into authn.password_credentials(
    user_id,password_hash,password_salt,algorithm,password_changed_at,failed_attempts,locked_until
  ) values(
    target_user_id,target_password_hash,target_password_salt,target_password_algorithm,now(),0,null
  )
  on conflict(user_id) do update set
    password_hash=excluded.password_hash,
    password_salt=excluded.password_salt,
    algorithm=excluded.algorithm,
    password_changed_at=now(),
    failed_attempts=0,
    locked_until=null;

  update authn.users
  set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||
      jsonb_build_object('must_change_password',coalesce(target_must_change_password,false)),
      updated_at=now()
  where id=target_user_id;

  update public.profiles
  set must_change_password=coalesce(target_must_change_password,false),updated_at=now()
  where id=target_user_id;

  perform audit.record_auth_event(
    tenant_id,actor_id,'auth.password.admin_reset',
    jsonb_build_object('target_user_id',target_user_id,'must_change_password',coalesce(target_must_change_password,false))
  );

  return true;
end
$function$;

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
declare target_role text; target_active boolean; other_admins integer;
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

  select public.current_app_role_for(p.role)::text,p.active
  into target_role,target_active
  from public.profiles p where p.id=target_user_id;

  if not found then
    raise exception 'User profile not found' using errcode='P0002';
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
    jsonb_build_object('target_user_id',target_user_id,'reason',coalesce(reason_text,''))
  );

  delete from authn.users where id=target_user_id;
  if not found then
    raise exception 'Authentication account was not found' using errcode='P0002';
  end if;
  return true;
end
$function$;

revoke all on function public.neon_identity_create_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean,text,text,text) from public;
revoke all on function public.neon_identity_update_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean) from public;
revoke all on function public.neon_identity_link_guardian(uuid,uuid,uuid) from public;
revoke all on function public.neon_identity_reset_password(uuid,uuid,uuid,text,text,text,boolean) from public;
revoke all on function public.neon_identity_delete_auth_user(uuid,uuid,uuid,text) from public;

grant execute on function public.neon_identity_create_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean,text,text,text) to edusentia_worker_runtime;
grant execute on function public.neon_identity_update_auth_user(uuid,uuid,uuid,text,text,text,boolean,text,boolean,boolean) to edusentia_worker_runtime;
grant execute on function public.neon_identity_link_guardian(uuid,uuid,uuid) to edusentia_worker_runtime;
grant execute on function public.neon_identity_reset_password(uuid,uuid,uuid,text,text,text,boolean) to edusentia_worker_runtime;
grant execute on function public.neon_identity_delete_auth_user(uuid,uuid,uuid,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0064_neon_identity_admin_bridges')
on conflict do nothing;

commit;
