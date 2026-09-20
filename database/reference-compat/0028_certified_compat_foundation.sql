begin;

-- Certified compatibility foundation derived from the stable r42 source line.
-- Legacy Supabase auth/licence semantics are mapped onto the Neon-native
-- authn.*, app.tenant_licenses and platform.license_plans model.

create or replace function public.is_platform_super_admin()
returns boolean
language sql
stable security definer
set search_path=public,app,pg_catalog
as $is_platform_super_admin$
  select coalesce(public.current_app_role()::text='platform_super_admin',false)
$is_platform_super_admin$;

create or replace function public.license_effective_entitlement()
returns jsonb
language plpgsql
stable security definer
set search_path=public,app,platform,pg_catalog
as $license_effective_entitlement$
declare
  v_tenant uuid:=app.current_tenant_id();
  l app.tenant_licenses%rowtype;
  p platform.license_plans%rowtype;
  effective_features jsonb;
  effective_limits jsonb;
begin
  if v_tenant is null then
    select tenant_id into v_tenant from app.tenant_licenses order by updated_at desc limit 1;
  end if;
  if v_tenant is null then return '{}'::jsonb; end if;

  select * into l from app.tenant_licenses where tenant_id=v_tenant limit 1;
  if l.id is null then return '{}'::jsonb; end if;
  select * into p from platform.license_plans where id=l.plan_id;

  effective_features:=coalesce(p.feature_flags,'{}'::jsonb)||coalesce(l.feature_overrides,'{}'::jsonb);
  effective_limits:=coalesce(p.limits,'{}'::jsonb)||coalesce(l.limits_override,'{}'::jsonb);

  return jsonb_build_object(
    'schema','rce-license-entitlement/v1',
    'plan',jsonb_build_object(
      'id',p.id,'code',p.code,'name',p.name,'description',p.description,
      'billing_cycle',p.billing_cycle,'feature_flags',effective_features,
      'max_students',effective_limits->'max_students',
      'max_teachers',effective_limits->'max_teachers',
      'max_system_admins',effective_limits->'max_system_admins',
      'max_guardians',effective_limits->'max_guardians',
      'max_storage_mb',effective_limits->'max_storage_mb'
    ),
    'license',jsonb_build_object(
      'license_reference',l.id::text,
      'status',l.status,
      'issued_on',l.starts_at,
      'activated_at',l.starts_at,
      'expires_at',l.expires_at,
      'grace_ends_at',null
    ),
    'binding',jsonb_build_object(
      'tenant_code',(select code from app.tenants where id=v_tenant),
      'tenant_id',v_tenant
    )
  );
end
$license_effective_entitlement$;

create or replace function public.license_snapshot_for_role(target_role text default null)
returns jsonb
language plpgsql
stable security definer
set search_path=public,app,platform,pg_catalog
as $license_snapshot_for_role$
declare
  v_role text:=coalesce(nullif(target_role,''),public.current_app_role()::text,'');
  v_tenant uuid:=app.current_tenant_id();
  l app.tenant_licenses%rowtype;
  p platform.license_plans%rowtype;
  e jsonb;
  plan_json jsonb;
  computed text;
  mode text:='full';
  r boolean:=true;
  w boolean:=true;
  v_now timestamptz:=now();
  days_left integer;
  warning text:='';
begin
  if v_tenant is null then
    select tenant_id into v_tenant from app.tenant_licenses order by updated_at desc limit 1;
  end if;
  if v_tenant is null then
    return jsonb_build_object(
      'configured',false,'computed_status','unlicensed','access_mode','locked',
      'read_allowed',false,'write_allowed',false,'access_locked',true,
      'warning','No platform licence is configured.'
    );
  end if;

  select * into l from app.tenant_licenses where tenant_id=v_tenant limit 1;
  if l.id is null then
    return jsonb_build_object(
      'configured',false,'computed_status','unlicensed','access_mode','locked',
      'read_allowed',false,'write_allowed',false,'access_locked',true,
      'warning','No platform licence is configured.'
    );
  end if;

  select * into p from platform.license_plans where id=l.plan_id;
  e:=public.license_effective_entitlement();
  plan_json:=coalesce(e->'plan','{}'::jsonb);
  computed:=lower(coalesce(l.status,'active'));

  if computed='active' then
    if l.starts_at>v_now then
      computed:='pending_activation';
    elsif l.expires_at is not null and l.expires_at<v_now then
      computed:='expired';
    end if;
  end if;

  if l.expires_at is not null then
    days_left:=floor(extract(epoch from(l.expires_at-v_now))/86400)::integer;
  end if;

  if v_role='platform_super_admin' then
    mode:='platform_control'; r:=false; w:=false;
  elsif computed='revoked' then
    mode:='locked'; r:=false; w:=false; warning:='The platform licence has been revoked.';
  elsif computed in ('pending_activation','expired','suspended') then
    mode:='read_only'; w:=false;
    warning:=case computed
      when 'pending_activation' then 'The licence is awaiting activation. The system is read-only.'
      when 'expired' then 'The licence has expired. Existing records remain read-only.'
      else 'The licence is suspended.'
    end;
  elsif computed='active' and days_left between 0 and 30 then
    warning:='The licence expires in '||days_left||' day'||case when days_left=1 then '' else 's' end||'.';
  end if;

  return jsonb_build_object(
    'configured',true,
    'license_id',l.id,
    'license_reference',l.id::text,
    'stored_status',l.status,
    'computed_status',computed,
    'issued_on',l.starts_at,
    'activated_at',l.starts_at,
    'expires_at',l.expires_at,
    'grace_ends_at',null,
    'plan',plan_json,
    'entitlement_schema',e->>'schema',
    'tenant_id',v_tenant,
    'access_mode',mode,
    'read_allowed',r,
    'write_allowed',w,
    'access_locked',mode='locked',
    'days_remaining',days_left,
    'warning',warning
  );
end
$license_snapshot_for_role$;

create or replace function public.license_read_allowed()
returns boolean
language sql
stable security definer
set search_path=public,pg_catalog
as $license_read_allowed$
  select coalesce((public.license_snapshot_for_role(public.current_app_role()::text)->>'read_allowed')::boolean,false)
$license_read_allowed$;

create or replace function public.license_write_allowed()
returns boolean
language sql
stable security definer
set search_path=public,pg_catalog
as $license_write_allowed$
  select coalesce((public.license_snapshot_for_role(public.current_app_role()::text)->>'write_allowed')::boolean,false)
$license_write_allowed$;

create or replace function public.license_feature_enabled(feature_code text)
returns boolean
language plpgsql
stable security definer
set search_path=public,pg_catalog
as $license_feature_enabled$
declare
  clean_code text:=lower(btrim(coalesce(feature_code,'')));
  value jsonb;
  core_value jsonb;
  id_value jsonb;
  entitlement jsonb:=public.license_effective_entitlement();
begin
  value:=entitlement#>array['plan','feature_flags',clean_code];
  if jsonb_typeof(value)='boolean' then return value='true'::jsonb; end if;
  core_value:=entitlement#>array['plan','feature_flags','core_records'];
  if clean_code in ('id_cards','timetable','school_prospectus') then
    return jsonb_typeof(core_value)='boolean' and core_value='true'::jsonb;
  end if;
  if clean_code='staff_id_cards' then
    id_value:=entitlement#>array['plan','feature_flags','id_cards'];
    return (jsonb_typeof(id_value)='boolean' and id_value='true'::jsonb)
      or (jsonb_typeof(id_value) is null and jsonb_typeof(core_value)='boolean' and core_value='true'::jsonb);
  end if;
  return false;
end
$license_feature_enabled$;

create or replace function public.require_license_feature(feature_code text)
returns void
language plpgsql
stable security definer
set search_path=public,pg_catalog
as $require_license_feature$
begin
  if not public.license_feature_enabled(feature_code) then
    raise exception 'LICENSE_FEATURE_NOT_INCLUDED: The current plan does not include %',replace(feature_code,'_',' ')
      using errcode='42501';
  end if;
end
$require_license_feature$;

create or replace function public.license_access_for_actor(actor_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=public,pg_catalog
as $license_access_for_actor$
declare actor_role text;
begin
  select public.current_app_role_for(p.role) into actor_role
  from public.profiles p where p.id=actor_id and p.active;
  if actor_role is null then
    return jsonb_build_object('read_allowed',false,'write_allowed',false,'access_mode','locked');
  end if;
  return public.license_snapshot_for_role(actor_role);
end
$license_access_for_actor$;

create or replace function public.ensure_current_user_profile()
returns jsonb
language plpgsql
security definer
set search_path=public,authn,pg_catalog
as $ensure_current_user_profile$
declare
  v_target_id uuid:=auth.uid();
  v_email text;
  v_metadata jsonb;
  v_app_metadata jsonb;
  v_requested_role text;
  v_assigned_role public.app_role;
  v_assigned_active boolean:=true;
  v_fallback_name text;
begin
  if v_target_id is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  select u.email,u.raw_user_meta_data,u.raw_app_meta_data
  into v_email,v_metadata,v_app_metadata
  from authn.users u where u.id=v_target_id;
  if not found then
    raise exception 'Authentication account not found' using errcode='42501';
  end if;

  v_metadata:=coalesce(v_metadata,'{}'::jsonb);
  v_app_metadata:=coalesce(v_app_metadata,'{}'::jsonb);
  v_requested_role:=lower(coalesce(v_app_metadata->>'role',v_metadata->>'role',''));
  v_fallback_name:=coalesce(
    nullif(btrim(v_metadata->>'full_name'),''),
    nullif(split_part(coalesce(v_email,''),'@',1),''),
    'User'
  );

  if not exists(select 1 from public.profiles p where p.id=v_target_id) then
    if not exists(
      select 1 from public.profiles p
      where p.active and public.current_app_role_for(p.role)='system_admin'
    ) and v_target_id=(select u.id from authn.users u order by u.created_at,u.id limit 1) then
      v_assigned_role:='system_admin'::public.app_role;
    elsif v_requested_role in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian','accountant','student') then
      v_assigned_role:=v_requested_role::public.app_role;
    else
      v_assigned_role:='parent_guardian'::public.app_role;
      v_assigned_active:=false;
    end if;

    insert into public.profiles(id,full_name,role,active,mfa_required,phone)
    values(
      v_target_id,v_fallback_name,v_assigned_role,v_assigned_active,
      v_assigned_role in ('system_admin','principal'),''
    )
    on conflict(id) do nothing;
  end if;

  update public.profiles p
  set full_name=case when btrim(coalesce(p.full_name,''))='' then v_fallback_name else p.full_name end,
      updated_at=now()
  where p.id=v_target_id
    and btrim(coalesce(p.full_name,''))='';

  return (
    select jsonb_build_object(
      'id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role),
      'active',p.active,'mfa_required',p.mfa_required
    )
    from public.profiles p where p.id=v_target_id
  );
end
$ensure_current_user_profile$;

revoke all on function public.is_platform_super_admin() from public;
revoke all on function public.license_effective_entitlement() from public;
revoke all on function public.license_snapshot_for_role(text) from public;
revoke all on function public.license_read_allowed() from public;
revoke all on function public.license_write_allowed() from public;
revoke all on function public.license_feature_enabled(text) from public;
revoke all on function public.require_license_feature(text) from public;
revoke all on function public.license_access_for_actor(uuid) from public;
revoke all on function public.ensure_current_user_profile() from public;

grant execute on function public.ensure_current_user_profile() to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0028_certified_compat_foundation')
on conflict do nothing;

update app.release_identity
set schema_version='0028'
where edition='Edusentia Enterprise Neon Edition';

commit;
