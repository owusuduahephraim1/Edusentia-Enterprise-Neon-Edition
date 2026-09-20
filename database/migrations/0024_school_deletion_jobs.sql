begin;

create table if not exists platform.school_deletion_jobs(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  registration_id uuid,
  tenant_code text not null,
  school_name text not null,
  database_name text not null,
  requested_by uuid not null references authn.users(id) on delete restrict,
  reason text not null,
  status text not null default 'queued' check(status in('queued','running','failed','completed','cancelled')),
  database_deleted_at timestamptz,
  r2_deleted_at timestamptz,
  master_deleted_at timestamptz,
  last_error text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);
create unique index if not exists platform_school_deletion_open_uidx on platform.school_deletion_jobs(tenant_id) where status in('queued','running','failed');
create index if not exists platform_school_deletion_created_idx on platform.school_deletion_jobs(created_at desc);

create or replace function platform.prepare_school_deletion(p_tenant_id uuid,p_actor uuid,p_confirmation text,p_reason text)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare t platform.tenant_control%rowtype;job platform.school_deletion_jobs%rowtype;expected text;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<8 then raise exception 'deletion_reason_too_short' using errcode='22023'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;
  if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  if t.database_state<>'isolated_ready' or t.database_name='' then raise exception 'tenant_database_not_ready' using errcode='55000'; end if;
  expected:='DELETE '||t.tenant_code;
  if trim(coalesce(p_confirmation,''))<>expected then raise exception 'deletion_confirmation_mismatch' using errcode='22023'; end if;
  select * into job from platform.school_deletion_jobs where tenant_id=p_tenant_id and status in('queued','running','failed') order by created_at desc limit 1;
  if found then
    update platform.school_deletion_jobs set status='queued',last_error='',updated_at=now(),reason=left(trim(p_reason),1000) where id=job.id returning * into job;
  else
    insert into platform.school_deletion_jobs(tenant_id,registration_id,tenant_code,school_name,database_name,requested_by,reason,status)
    values(t.tenant_id,t.registration_id,t.tenant_code,t.school_name,t.database_name,p_actor,left(trim(p_reason),1000),'queued') returning * into job;
  end if;
  update platform.tenant_control set status='suspended',license_status='revoked',updated_at=now() where tenant_id=p_tenant_id;
  update platform.login_directory set active=false,updated_at=now() where tenant_id=p_tenant_id;
  update platform.tenant_admin_handoff_tokens set used_at=coalesce(used_at,now()) where tenant_id=p_tenant_id and used_at is null;
  update platform.plan_authorizations set status='revoked',revoked_at=coalesce(revoked_at,now()),revoked_by=coalesce(revoked_by,p_actor),revoke_reason=case when revoke_reason='' then 'School deletion initiated' else revoke_reason end,updated_at=now() where tenant_id=p_tenant_id and status='issued';
  update platform.provisioning_jobs set status='cancelled',stage='school_deletion',updated_at=now() where tenant_id=p_tenant_id and status in('queued','running','failed');
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
  values(p_actor,'platform.school.deletion_prepared','tenant',p_tenant_id::text,jsonb_build_object('tenant_code',t.tenant_code,'school_name',t.school_name,'database_name',t.database_name,'reason',left(trim(p_reason),1000)));
  return jsonb_build_object('ok',true,'job_id',job.id,'tenant_id',t.tenant_id,'tenant_code',t.tenant_code,'school_name',t.school_name,'database_name',t.database_name,'status','queued');
end$$;

create or replace function platform.mark_school_deletion_stage(p_job_id uuid,p_actor uuid,p_stage text,p_error text default '')
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if not exists(select 1 from platform.school_deletion_jobs where id=p_job_id) then raise exception 'deletion_job_not_found' using errcode='P0002'; end if;
  if p_stage='running' then update platform.school_deletion_jobs set status='running',started_at=coalesce(started_at,now()),last_error='',updated_at=now() where id=p_job_id;
  elsif p_stage='database_deleted' then update platform.school_deletion_jobs set status='running',database_deleted_at=coalesce(database_deleted_at,now()),last_error='',updated_at=now() where id=p_job_id;
  elsif p_stage='r2_deleted' then update platform.school_deletion_jobs set status='running',r2_deleted_at=coalesce(r2_deleted_at,now()),last_error='',updated_at=now() where id=p_job_id;
  elsif p_stage='failed' then update platform.school_deletion_jobs set status='failed',last_error=left(coalesce(p_error,''),2000),updated_at=now() where id=p_job_id;
  else raise exception 'invalid_deletion_stage' using errcode='22023'; end if;
  return jsonb_build_object('ok',true,'job_id',p_job_id,'stage',p_stage);
end$$;

create or replace function platform.finalize_school_deletion(p_job_id uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare j platform.school_deletion_jobs%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into j from platform.school_deletion_jobs where id=p_job_id for update;
  if not found then raise exception 'deletion_job_not_found' using errcode='P0002'; end if;
  if j.database_deleted_at is null or j.r2_deleted_at is null then raise exception 'deletion_external_cleanup_incomplete' using errcode='55000'; end if;
  delete from platform.login_directory where tenant_id=j.tenant_id;
  delete from platform.tenant_admin_handoff_tokens where tenant_id=j.tenant_id;
  delete from platform.plan_authorization_attempts where tenant_id=j.tenant_id;
  delete from platform.plan_authorizations where tenant_id=j.tenant_id;
  delete from platform.tenant_health where tenant_id=j.tenant_id;
  delete from platform.access_recovery_requests where tenant_id=j.tenant_id;
  delete from platform.provisioning_jobs where tenant_id=j.tenant_id;
  delete from platform.tenant_events where tenant_id=j.tenant_id;
  delete from app.tenants where id=j.tenant_id;
  if j.registration_id is not null then delete from platform.school_registrations where id=j.registration_id; end if;
  update platform.school_deletion_jobs set status='completed',master_deleted_at=now(),completed_at=now(),last_error='',updated_at=now() where id=p_job_id;
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
  values(p_actor,'platform.school.deletion_completed','tenant',j.tenant_id::text,jsonb_build_object('tenant_code',j.tenant_code,'school_name',j.school_name,'database_name',j.database_name,'reason',j.reason,'job_id',j.id));
  return jsonb_build_object('ok',true,'deleted',true,'job_id',j.id,'tenant_id',j.tenant_id,'tenant_code',j.tenant_code,'school_name',j.school_name);
end$$;

revoke all on function platform.prepare_school_deletion(uuid,uuid,text,text) from public;
revoke all on function platform.mark_school_deletion_stage(uuid,uuid,text,text) from public;
revoke all on function platform.finalize_school_deletion(uuid,uuid) from public;
grant select,insert,update on platform.school_deletion_jobs to edusentia_worker_runtime;
grant execute on function platform.prepare_school_deletion(uuid,uuid,text,text),platform.mark_school_deletion_stage(uuid,uuid,text,text),platform.finalize_school_deletion(uuid,uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0024_school_deletion_jobs') on conflict do nothing;
update app.release_identity set schema_version='0024' where edition='Edusentia Enterprise Neon Edition';
commit;
