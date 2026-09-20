begin;

create table if not exists platform.login_directory(
  email_normalized text not null,
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  tenant_code text not null,
  database_name text not null,
  role_hint text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(email_normalized,tenant_id)
);
create index if not exists platform_login_directory_email_idx on platform.login_directory(email_normalized) where active;

create table if not exists platform.tenant_admin_handoff_tokens(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants(id) on delete cascade,
  token_hash text not null unique,
  purpose text not null check(purpose in('initial_setup','password_recovery','password_and_mfa_recovery')),
  admin_email text not null,
  created_by uuid references authn.users(id) on delete set null,
  recovery_request_id uuid references platform.access_recovery_requests(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
create index if not exists platform_tenant_admin_handoff_active_idx on platform.tenant_admin_handoff_tokens(token_hash,expires_at) where used_at is null;

create or replace function platform.mark_isolated_tenant_ready(p_tenant_id uuid,p_actor uuid,p_database_name text,p_release_code text,p_release_manifest text)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare t platform.tenant_control%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if p_database_name !~ '^edusentia_[a-z0-9_]{3,50}$' then raise exception 'invalid_tenant_database_name' using errcode='22023'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;
  if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  if t.status='denied' then raise exception 'denied_school_cannot_be_activated' using errcode='55000'; end if;
  update platform.tenant_control set database_name=p_database_name,database_state='isolated_ready',status='active',license_status='active',runtime_version=p_release_code,schema_version='0020',release_status='current',release_manifest_sha256=coalesce(p_release_manifest,''),release_foundation_version='Edusentia-Enterprise-r42-v18-STABLE-20260919',release_source_schema_version=20,release_migration_count=20,release_worker_function_count=2,release_checked_at=now(),activated_at=coalesce(activated_at,now()),updated_at=now() where tenant_id=p_tenant_id;
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
  update app.tenants set status='active',updated_at=now() where id=p_tenant_id;
  update app.tenant_licenses set status='active',updated_at=now() where tenant_id=p_tenant_id;
  update platform.school_registrations set status='active',updated_at=now() where id=t.registration_id;
  update platform.provisioning_jobs set status='ready',stage='ready',completed_at=coalesce(completed_at,now()),updated_at=now() where tenant_id=p_tenant_id and status<>'cancelled';
  insert into platform.login_directory(email_normalized,tenant_id,tenant_code,database_name,role_hint,active)
  values(lower(t.admin_email),p_tenant_id,t.tenant_code,p_database_name,'system_admin',true)
  on conflict(email_normalized,tenant_id) do update set tenant_code=excluded.tenant_code,database_name=excluded.database_name,role_hint=excluded.role_hint,active=true,updated_at=now();
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'isolated_tenant_ready',p_actor,jsonb_build_object('database_name',p_database_name,'release_code',p_release_code));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.tenant.isolated_ready','tenant',p_tenant_id::text,jsonb_build_object('database_name',p_database_name,'release_code',p_release_code));
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'tenant_code',t.tenant_code,'database_name',p_database_name,'admin_email',t.admin_email,'status','active');
end$$;

create or replace function platform.resolve_login_route(p_email text,p_tenant_code text default null)
returns table(tenant_id uuid,tenant_code text,school_name text,database_name text,admin_email text,institution_type text)
language sql stable security definer set search_path=platform,pg_catalog as $$
select tc.tenant_id,tc.tenant_code,tc.school_name,tc.database_name,tc.admin_email,tc.institution_type
from platform.login_directory d join platform.tenant_control tc on tc.tenant_id=d.tenant_id
where d.email_normalized=lower(trim(p_email)) and d.active and tc.status='active' and tc.database_state='isolated_ready'
  and (nullif(trim(p_tenant_code),'') is null or upper(tc.tenant_code)=upper(trim(p_tenant_code)))
order by tc.tenant_code
$$;

create or replace function platform.issue_tenant_admin_handoff(p_tenant_id uuid,p_actor uuid,p_token_hash text,p_purpose text,p_expires_at timestamptz,p_recovery_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare t platform.tenant_control%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if p_purpose not in('initial_setup','password_recovery','password_and_mfa_recovery') then raise exception 'invalid_handoff_purpose' using errcode='22023'; end if;
  if p_expires_at<=now() or p_expires_at>now()+interval '24 hours' then raise exception 'invalid_setup_expiry' using errcode='22023'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;
  if not found or t.database_state<>'isolated_ready' then raise exception 'tenant_not_ready' using errcode='55000'; end if;
  update platform.tenant_admin_handoff_tokens set used_at=coalesce(used_at,now()) where tenant_id=p_tenant_id and used_at is null;
  insert into platform.tenant_admin_handoff_tokens(tenant_id,token_hash,purpose,admin_email,created_by,recovery_request_id,expires_at) values(p_tenant_id,p_token_hash,p_purpose,lower(t.admin_email),p_actor,p_recovery_request_id,p_expires_at);
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'admin_handoff_link_issued',p_actor,jsonb_build_object('purpose',p_purpose,'admin_email',t.admin_email,'expires_at',p_expires_at));
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'tenant_code',t.tenant_code,'school_name',t.school_name,'admin_email',t.admin_email,'database_name',t.database_name,'purpose',p_purpose,'expires_at',p_expires_at);
end$$;

create or replace function platform.inspect_tenant_admin_handoff(p_token_hash text)
returns table(tenant_id uuid,tenant_code text,school_name text,database_name text,admin_email text,purpose text,expires_at timestamptz)
language sql stable security definer set search_path=platform,pg_catalog as $$
select h.tenant_id,tc.tenant_code,tc.school_name,tc.database_name,h.admin_email,h.purpose,h.expires_at
from platform.tenant_admin_handoff_tokens h join platform.tenant_control tc on tc.tenant_id=h.tenant_id
where h.token_hash=p_token_hash and h.used_at is null and h.expires_at>now() and tc.database_state='isolated_ready'
limit 1
$$;

create or replace function platform.consume_tenant_admin_handoff(p_token_hash text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare h platform.tenant_admin_handoff_tokens%rowtype;t platform.tenant_control%rowtype;
begin
  select * into h from platform.tenant_admin_handoff_tokens where token_hash=p_token_hash and used_at is null and expires_at>now() for update;
  if not found then raise exception 'setup_token_invalid_or_expired' using errcode='42501'; end if;
  select * into t from platform.tenant_control where tenant_id=h.tenant_id;
  update platform.tenant_admin_handoff_tokens set used_at=now() where id=h.id;
  if h.recovery_request_id is not null then update platform.access_recovery_requests set status='completed',reviewed_at=coalesce(reviewed_at,now()),completed_at=now(),resolution_notes='Protected recovery handoff completed' where id=h.recovery_request_id and status in('pending','processing'); end if;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,details) values(h.tenant_id,t.registration_id,'admin_handoff_completed',jsonb_build_object('purpose',h.purpose,'admin_email',h.admin_email));
  return jsonb_build_object('ok',true,'tenant_id',h.tenant_id,'tenant_code',t.tenant_code,'school_name',t.school_name,'database_name',t.database_name,'admin_email',h.admin_email,'purpose',h.purpose);
end$$;

create or replace function platform.claim_access_recovery(p_request_id uuid,p_actor uuid,p_mode text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare r platform.access_recovery_requests%rowtype;t platform.tenant_control%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if p_mode not in('password','mfa','both') then raise exception 'invalid_recovery_mode' using errcode='22023'; end if;
  select * into r from platform.access_recovery_requests where id=p_request_id for update;
  if not found then raise exception 'recovery_request_not_found' using errcode='P0002'; end if;
  if r.status<>'pending' then raise exception 'recovery_request_not_pending' using errcode='55000'; end if;
  if not (p_mode='both' or p_mode=r.recovery_type) then raise exception 'recovery_mode_does_not_cover_request' using errcode='22023'; end if;
  select * into t from platform.tenant_control where tenant_id=r.tenant_id;
  if not found or t.database_state<>'isolated_ready' then raise exception 'tenant_not_ready' using errcode='55000'; end if;
  update platform.access_recovery_requests set status='processing',reviewed_at=now(),reviewed_by=p_actor,resolution_notes='Protected recovery is being applied to the isolated tenant database' where id=p_request_id;
  return jsonb_build_object('ok',true,'request_id',r.id,'tenant_id',t.tenant_id,'tenant_code',t.tenant_code,'school_name',t.school_name,'database_name',t.database_name,'admin_email',t.admin_email,'requested_type',r.recovery_type,'mode',p_mode);
end$$;

create or replace function platform.complete_access_recovery(p_request_id uuid,p_actor uuid,p_mode text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare r platform.access_recovery_requests%rowtype;t platform.tenant_control%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into r from platform.access_recovery_requests where id=p_request_id for update;
  if not found or r.status<>'processing' then raise exception 'recovery_request_not_processing' using errcode='55000'; end if;
  select * into t from platform.tenant_control where tenant_id=r.tenant_id;
  update platform.access_recovery_requests set status='completed',completed_at=now(),resolution_notes='Protected recovery completed in isolated tenant database' where id=p_request_id;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(r.tenant_id,r.registration_id,'administrator_access_recovery_completed',p_actor,jsonb_build_object('mode',p_mode,'admin_email',t.admin_email));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.access_recovery.completed','recovery_request',p_request_id::text,jsonb_build_object('mode',p_mode,'tenant_id',r.tenant_id,'database_name',t.database_name));
  return jsonb_build_object('ok',true,'status','completed','tenant_id',r.tenant_id,'database_name',t.database_name);
end$$;

revoke all on function platform.mark_isolated_tenant_ready(uuid,uuid,text,text,text) from public;
revoke all on function platform.resolve_login_route(text,text) from public;
revoke all on function platform.issue_tenant_admin_handoff(uuid,uuid,text,text,timestamptz,uuid) from public;
revoke all on function platform.inspect_tenant_admin_handoff(text) from public;
revoke all on function platform.consume_tenant_admin_handoff(text) from public;
revoke all on function platform.claim_access_recovery(uuid,uuid,text) from public;
revoke all on function platform.complete_access_recovery(uuid,uuid,text) from public;

grant select,insert,update,delete on platform.login_directory,platform.tenant_admin_handoff_tokens to edusentia_worker_runtime;
grant execute on function platform.mark_isolated_tenant_ready(uuid,uuid,text,text,text),platform.resolve_login_route(text,text),platform.issue_tenant_admin_handoff(uuid,uuid,text,text,timestamptz,uuid),platform.inspect_tenant_admin_handoff(text),platform.consume_tenant_admin_handoff(text),platform.claim_access_recovery(uuid,uuid,text),platform.complete_access_recovery(uuid,uuid,text) to edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0021_isolated_tenant_handoffs') on conflict do nothing;
update app.release_identity set schema_version='0021' where edition='Edusentia Enterprise Neon Edition';

commit;
