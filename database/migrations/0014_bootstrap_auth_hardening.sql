begin;

create or replace function authn.bootstrap_first_admin(
  p_tenant_code text,
  p_tenant_name text,
  p_institution_type text,
  p_email text,
  p_display_name text,
  p_password_hash text,
  p_password_salt text
) returns jsonb
language plpgsql
security definer
set search_path=authn,app,pg_catalog
as $$
declare
  v_tenant uuid;
  v_user uuid;
begin
  if exists(select 1 from authn.users limit 1) or exists(select 1 from app.tenants limit 1) then
    raise exception 'bootstrap_closed' using errcode='42501';
  end if;
  if p_tenant_code is null or p_tenant_code !~ '^[A-Z0-9][A-Z0-9_-]{2,31}$' then
    raise exception 'invalid_tenant_code' using errcode='22023';
  end if;
  if p_email is null or position('@' in p_email)<2 then
    raise exception 'invalid_email' using errcode='22023';
  end if;

  insert into app.tenants(code,name,institution_type,status)
  values(upper(trim(p_tenant_code)),trim(p_tenant_name),coalesce(nullif(trim(p_institution_type),''),'basic_jhs'),'active')
  returning id into v_tenant;

  insert into authn.users(email,display_name)
  values(lower(trim(p_email)),trim(p_display_name))
  returning id into v_user;

  insert into authn.password_credentials(user_id,password_hash,password_salt)
  values(v_user,p_password_hash,p_password_salt);

  insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required)
  values(v_tenant,v_user,'system_admin','active',true);

  perform set_config('app.tenant_id',v_tenant::text,true);
  perform set_config('app.user_id',v_user::text,true);
  perform set_config('app.role','system_admin',true);
  perform set_config('app.aal','1',true);

  insert into app.school_settings(tenant_id,legal_name,short_name)
  values(v_tenant,trim(p_tenant_name),trim(p_tenant_name));

  return jsonb_build_object('tenant_id',v_tenant,'user_id',v_user);
end$$;

revoke all on function authn.bootstrap_first_admin(text,text,text,text,text,text,text) from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='edusentia_runtime') then
    revoke all on authn.password_credentials,authn.mfa_totp_factors,authn.mfa_recovery_codes from edusentia_runtime;
    revoke insert,update,delete on authn.users from edusentia_runtime;
    grant select on authn.users to edusentia_runtime;
    grant select,insert,update,delete on authn.sessions to edusentia_runtime;
    grant execute on function authn.lookup_login(text,text) to edusentia_runtime;
    grant execute on function authn.bootstrap_first_admin(text,text,text,text,text,text,text) to edusentia_runtime;
  end if;
end$$;

insert into app.schema_migrations(version) values ('0014_bootstrap_auth_hardening') on conflict do nothing;
update app.release_identity set schema_version='0014' where edition='Edusentia Enterprise Neon Edition';

commit;
