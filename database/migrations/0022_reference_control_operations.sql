begin;

create or replace function platform.resolve_public_school(p_code text)
returns table(tenant_code text,school_name text,short_name text,institution_type text,status text)
language sql stable security definer set search_path=platform,app,pg_catalog as $$
select tc.tenant_code,tc.school_name,coalesce(nullif(ss.short_name,''),tc.school_name),tc.institution_type,tc.status
from platform.tenant_control tc left join app.school_settings ss on ss.tenant_id=tc.tenant_id
where upper(tc.tenant_code)=upper(trim(p_code)) and tc.status in('active','suspended','provisioning') limit 1
$$;

create or replace function platform.submit_access_recovery(p_identifier text,p_contact_email text,p_recovery_type text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare t platform.tenant_control%rowtype;r platform.school_registrations%rowtype;existing_id uuid;
begin
  if p_recovery_type not in('password','mfa','both') then raise exception 'invalid_recovery_type' using errcode='22023'; end if;
  select * into t from platform.tenant_control where upper(tenant_code)=upper(trim(p_identifier)) or lower(admin_email)=lower(trim(p_identifier)) order by created_at desc limit 1;
  if not found then return jsonb_build_object('accepted',true); end if;
  select * into r from platform.school_registrations where id=t.registration_id;
  if not found or lower(trim(r.contact_email))<>lower(trim(p_contact_email)) then return jsonb_build_object('accepted',true); end if;
  select id into existing_id from platform.access_recovery_requests where tenant_id=t.tenant_id and status in('pending','processing') limit 1;
  if existing_id is null then
    insert into platform.access_recovery_requests(tenant_id,registration_id,recovery_type,requester_contact_email,status,metadata)
    values(t.tenant_id,t.registration_id,p_recovery_type,lower(trim(p_contact_email)),'pending',jsonb_build_object('identifier',trim(p_identifier),'school_name',t.school_name,'tenant_code',t.tenant_code));
  else
    update platform.access_recovery_requests set recovery_type=p_recovery_type,requester_contact_email=lower(trim(p_contact_email)),status='pending',requested_at=now(),metadata=metadata||jsonb_build_object('identifier',trim(p_identifier)) where id=existing_id;
  end if;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,details) values(t.tenant_id,t.registration_id,'administrator_access_recovery_requested',jsonb_build_object('recovery_type',p_recovery_type));
  return jsonb_build_object('accepted',true);
end$$;

create or replace function platform.deny_access_recovery(p_request_id uuid,p_actor uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare r platform.access_recovery_requests%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'denial_reason_required' using errcode='22023'; end if;
  select * into r from platform.access_recovery_requests where id=p_request_id for update;
  if not found then raise exception 'recovery_request_not_found' using errcode='P0002'; end if;
  if r.status not in('pending','processing') then raise exception 'recovery_request_not_open' using errcode='55000'; end if;
  update platform.access_recovery_requests set status='denied',reviewed_at=now(),reviewed_by=p_actor,resolution_notes=left(trim(p_reason),500) where id=p_request_id;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(r.tenant_id,r.registration_id,'administrator_access_recovery_denied',p_actor,jsonb_build_object('recovery_type',r.recovery_type,'reason',left(trim(p_reason),500)));
  return jsonb_build_object('ok',true,'status','denied');
end$$;

create or replace function platform.issue_plan_authorization(
 p_tenant_id uuid,p_actor uuid,p_plan_code text,p_period_type text,p_period_label text,p_starts_at timestamptz,p_expires_at timestamptz,p_grace_days integer,p_code_hash text,p_code_hint text,p_valid_until timestamptz,p_reason text
) returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare t platform.tenant_control%rowtype;current_plan platform.license_plans%rowtype;next_plan platform.license_plans%rowtype;auth_type text;auth_id uuid;grace integer;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'licence_authorization_reason_required' using errcode='22023'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;
  if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  if t.status not in('active','suspended') or t.database_state<>'isolated_ready' then raise exception 'tenant_must_be_provisioned_before_licence_authorization' using errcode='55000'; end if;
  select * into current_plan from platform.license_plans where code=t.plan_code and active;
  select * into next_plan from platform.license_plans where code=lower(trim(p_plan_code)) and active;
  if current_plan.id is null or next_plan.id is null then raise exception 'plan_not_found' using errcode='P0002'; end if;
  if next_plan.sort_order<current_plan.sort_order then raise exception 'select_the_current_or_a_higher_active_plan' using errcode='22023'; end if;
  if p_period_type not in('academic_term','academic_year') or p_expires_at<=p_starts_at then raise exception 'invalid_licence_window' using errcode='22023'; end if;
  if p_valid_until<=now() or p_valid_until>now()+interval '7 days' then raise exception 'invalid_authorization_expiry' using errcode='22023'; end if;
  update platform.plan_authorizations set status='expired',updated_at=now() where tenant_id=p_tenant_id and status='issued' and expires_at<=now();
  if exists(select 1 from platform.plan_authorizations where tenant_id=p_tenant_id and status in('issued','redeemed_pending_activation')) then raise exception 'revoke_or_complete_the_existing_licence_code' using errcode='55000'; end if;
  grace:=greatest(0,least(90,coalesce(p_grace_days,14)));auth_type:=case when next_plan.code=current_plan.code then 'renewal' else 'plan_upgrade' end;
  insert into platform.plan_authorizations(tenant_id,code_hash,code_hint,authorization_type,from_plan_code,to_plan_code,status,reason,issued_by,expires_at,license_period_type,license_period_label,license_starts_at,license_expires_at,license_grace_days,metadata)
  values(p_tenant_id,p_code_hash,p_code_hint,auth_type,current_plan.code,next_plan.code,'issued',left(trim(p_reason),500),p_actor,p_valid_until,p_period_type,p_period_label,p_starts_at,p_expires_at,grace,jsonb_build_object('school_name',t.school_name,'tenant_code',t.tenant_code)) returning id into auth_id;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'licence_authorization_code_issued',p_actor,jsonb_build_object('authorization_id',auth_id,'authorization_type',auth_type,'from_plan_code',current_plan.code,'to_plan_code',next_plan.code,'code_expires_at',p_valid_until));
  return jsonb_build_object('ok',true,'authorization_id',auth_id,'authorization_type',auth_type,'from_plan_code',current_plan.code,'to_plan_code',next_plan.code,'expires_at',p_valid_until);
end$$;

create or replace function platform.claim_plan_authorization(p_tenant_id uuid,p_code_hash text,p_actor_subject text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare a platform.plan_authorizations%rowtype;t platform.tenant_control%rowtype;
begin
  select * into a from platform.plan_authorizations where tenant_id=p_tenant_id and code_hash=p_code_hash for update;
  if not found then
    insert into platform.plan_authorization_attempts(tenant_id,outcome,details) values(p_tenant_id,'invalid',jsonb_build_object('actor_subject',p_actor_subject));
    raise exception 'licence_authorization_invalid' using errcode='42501';
  end if;
  if a.status='issued' and a.expires_at<=now() then update platform.plan_authorizations set status='expired',updated_at=now() where id=a.id;a.status:='expired';end if;
  if a.status<>'issued' then
    insert into platform.plan_authorization_attempts(tenant_id,authorization_id,outcome,details) values(p_tenant_id,a.id,'unavailable',jsonb_build_object('actor_subject',p_actor_subject,'status',a.status));
    raise exception 'licence_authorization_unavailable' using errcode='55000';
  end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id and database_state='isolated_ready';
  if not found then raise exception 'tenant_not_ready' using errcode='55000'; end if;
  update platform.plan_authorizations set status='redeemed_pending_activation',redeemed_at=now(),updated_at=now() where id=a.id;
  insert into platform.plan_authorization_attempts(tenant_id,authorization_id,outcome,details) values(p_tenant_id,a.id,'claimed',jsonb_build_object('actor_subject',p_actor_subject));
  return jsonb_build_object('ok',true,'authorization_id',a.id,'database_name',t.database_name,'tenant_code',t.tenant_code,'plan_code',a.to_plan_code,'period_type',a.license_period_type,'period_label',a.license_period_label,'starts_at',a.license_starts_at,'expires_at',a.license_expires_at,'grace_days',a.license_grace_days);
end$$;

create or replace function platform.complete_plan_authorization(p_authorization_id uuid,p_tenant_id uuid,p_actor_subject text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare a platform.plan_authorizations%rowtype;t platform.tenant_control%rowtype;base_limit integer;
begin
  select * into a from platform.plan_authorizations where id=p_authorization_id and tenant_id=p_tenant_id for update;
  if not found or a.status<>'redeemed_pending_activation' then raise exception 'licence_authorization_not_claimed' using errcode='55000'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;
  select nullif(limits->>'max_students','')::integer into base_limit from platform.license_plans where code=a.to_plan_code;
  update platform.plan_authorizations set status='used',used_at=now(),updated_at=now() where id=a.id;
  update platform.tenant_control set plan_code=a.to_plan_code,license_status='active',license_period_type=a.license_period_type,license_period_label=a.license_period_label,license_started_at=a.license_starts_at,license_expires_at=a.license_expires_at,license_grace_days=a.license_grace_days,license_grace_ends_at=a.license_expires_at+make_interval(days=>a.license_grace_days),student_capacity_base=base_limit,license_period_locked=true,updated_at=now() where tenant_id=p_tenant_id;
  insert into platform.plan_authorization_attempts(tenant_id,authorization_id,outcome,details) values(p_tenant_id,a.id,'used',jsonb_build_object('actor_subject',p_actor_subject,'to_plan_code',a.to_plan_code));
  insert into platform.tenant_events(tenant_id,registration_id,event_type,details) values(p_tenant_id,t.registration_id,'licence_authorization_redeemed',jsonb_build_object('authorization_id',a.id,'actor_subject',p_actor_subject,'to_plan_code',a.to_plan_code));
  return jsonb_build_object('ok',true,'authorization_id',a.id,'plan_code',a.to_plan_code,'license_expires_at',a.license_expires_at);
end$$;

create or replace function platform.release_plan_authorization_claim(p_authorization_id uuid,p_tenant_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
begin
  update platform.plan_authorizations set status='issued',redeemed_at=null,updated_at=now(),metadata=metadata||jsonb_build_object('last_activation_error',left(coalesce(p_reason,''),500)) where id=p_authorization_id and tenant_id=p_tenant_id and status='redeemed_pending_activation';
  return jsonb_build_object('ok',true);
end$$;

create or replace function platform.revoke_plan_authorization(p_authorization_id uuid,p_tenant_id uuid,p_actor uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare a platform.plan_authorizations%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'revocation_reason_required' using errcode='22023'; end if;
  select * into a from platform.plan_authorizations where id=p_authorization_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'licence_authorization_not_found' using errcode='P0002'; end if;
  if a.status<>'issued' then raise exception 'only_an_unused_code_can_be_revoked' using errcode='55000'; end if;
  update platform.plan_authorizations set status='revoked',revoked_at=now(),revoked_by=p_actor,revoke_reason=left(trim(p_reason),500),updated_at=now() where id=a.id;
  return jsonb_build_object('ok',true,'authorization_id',a.id,'status','revoked');
end$$;

create or replace function platform.delete_revoked_plan_authorization(p_authorization_id uuid,p_tenant_id uuid,p_actor uuid,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare a platform.plan_authorizations%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if upper(trim(coalesce(p_confirmation,'')))<>'DELETE' then raise exception 'delete_confirmation_required' using errcode='22023'; end if;
  select * into a from platform.plan_authorizations where id=p_authorization_id and tenant_id=p_tenant_id for update;
  if not found then raise exception 'licence_authorization_not_found' using errcode='P0002'; end if;
  if a.status<>'revoked' then raise exception 'only_revoked_authorizations_can_be_deleted' using errcode='55000'; end if;
  delete from platform.plan_authorizations where id=a.id;
  return jsonb_build_object('ok',true,'deleted',true,'authorization_id',a.id);
end$$;

create or replace function platform.release_gate()
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare rel platform.release_catalog%rowtype;trel platform.tenant_releases%rowtype;active_release_count bigint;active_tenant_release_count bigint;active_tenants bigint;stale_health bigint;release_drift bigint;schema_drift bigint;unhealthy bigint;failed_jobs bigint;invalid_licences bigint;capacity_violations bigint;invalid_indexes bigint;ready boolean;
begin
  select count(*) into active_release_count from platform.release_catalog where status='active';select * into rel from platform.release_catalog where status='active' limit 1;
  select count(*) into active_tenant_release_count from platform.tenant_releases where status='active';select * into trel from platform.tenant_releases where status='active' limit 1;
  select count(*) into active_tenants from platform.tenant_control where status='active';
  select count(*) into stale_health from platform.tenant_control where status='active' and (last_health_checked_at is null or last_health_checked_at<now()-interval '2 hours');
  select count(*) into release_drift from platform.tenant_control where status='active' and (active_tenant_release_count<>1 or runtime_version<>coalesce(trel.release_code,'') or release_foundation_version<>coalesce(trel.baseline_blueprint_version,''));
  select count(*) into schema_drift from platform.tenant_control where status='active' and schema_version<>coalesce(rel.tenant_schema_version,'');
  select count(*) into unhealthy from platform.tenant_control where status='active' and (last_health_status<>'healthy' or release_status in('drifted','schema_drift','unhealthy'));
  select count(*) into failed_jobs from platform.provisioning_jobs where status='failed';
  select count(*) into invalid_licences from platform.tenant_control where status='active' and (license_status not in('active','grace_period') or license_expires_at is null);
  select count(*) into capacity_violations from platform.tenant_control where status='active' and student_capacity_limit is not null and student_active_count>student_capacity_limit;
  select count(*) into invalid_indexes from pg_index where not indisvalid;
  ready:=active_release_count=1 and active_tenant_release_count=1 and stale_health=0 and release_drift=0 and schema_drift=0 and unhealthy=0 and failed_jobs=0 and invalid_licences=0 and capacity_violations=0 and invalid_indexes=0;
  return jsonb_build_object('ready',ready,'release_version',coalesce(rel.release_version,''),'git_sha',coalesce(rel.git_sha,''),'tenant_release_code',coalesce(trel.release_code,''),'checked_at',now(),'checks',jsonb_build_object('active_release_count',active_release_count,'active_tenant_release_count',active_tenant_release_count,'active_tenants',active_tenants,'stale_tenant_health',stale_health,'tenant_release_drift',release_drift,'tenant_schema_drift',schema_drift,'unhealthy_tenants',unhealthy,'failed_provisioning_jobs',failed_jobs,'invalid_active_licences',invalid_licences,'student_capacity_violations',capacity_violations,'invalid_indexes',invalid_indexes));
end$$;

create or replace function platform.record_release_gate()
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare g jsonb;
begin
  g:=platform.release_gate();
  insert into platform.release_gate_runs(release_version,ready,checks,checked_at) values(g->>'release_version',coalesce((g->>'ready')::boolean,false),coalesce(g->'checks','{}'::jsonb),coalesce((g->>'checked_at')::timestamptz,now()));
  return g;
end$$;

insert into platform.release_catalog(release_version,git_sha,status,master_schema_version,tenant_schema_version,manifest_sha256,source_baseline,deployed_at,notes)
values('neon-v1.0.0-r42-parity','reference-parity-r42','active','0022','0020','','Edusentia-Enterprise-r42-v18-STABLE-20260919',now(),'Fresh Neon implementation of the certified r42-v18 control-plane blueprint')
on conflict(release_version) do update set git_sha=excluded.git_sha,status='active',master_schema_version=excluded.master_schema_version,tenant_schema_version=excluded.tenant_schema_version,source_baseline=excluded.source_baseline,deployed_at=excluded.deployed_at,notes=excluded.notes,updated_at=now();

insert into platform.tenant_releases(release_code,status,baseline_blueprint_version,manifest_sha256,migration_count,worker_function_count,source_schema_version,source_reference,metadata,notes,activated_at)
values('neon-v1.0.0-r42-parity','active','Edusentia-Enterprise-r42-v18-STABLE-20260919','',20,1,20,'a181e18e0ca044db756193209b5b089cd03efb0f','{"runtime":"Cloudflare Workers + Neon PostgreSQL + R2","tenant_isolation":"dedicated_database"}'::jsonb,'Verified Neon isolated tenant release',now())
on conflict(release_code) do update set status='active',migration_count=excluded.migration_count,worker_function_count=excluded.worker_function_count,source_schema_version=excluded.source_schema_version,source_reference=excluded.source_reference,metadata=excluded.metadata,activated_at=coalesce(platform.tenant_releases.activated_at,excluded.activated_at);

revoke all on function platform.resolve_public_school(text) from public;
revoke all on function platform.submit_access_recovery(text,text,text) from public;
revoke all on function platform.deny_access_recovery(uuid,uuid,text) from public;
revoke all on function platform.issue_plan_authorization(uuid,uuid,text,text,text,timestamptz,timestamptz,integer,text,text,timestamptz,text) from public;
revoke all on function platform.claim_plan_authorization(uuid,text,text) from public;
revoke all on function platform.complete_plan_authorization(uuid,uuid,text) from public;
revoke all on function platform.release_plan_authorization_claim(uuid,uuid,text) from public;
revoke all on function platform.revoke_plan_authorization(uuid,uuid,uuid,text) from public;
revoke all on function platform.delete_revoked_plan_authorization(uuid,uuid,uuid,text) from public;
revoke all on function platform.release_gate() from public;
revoke all on function platform.record_release_gate() from public;

grant execute on function platform.resolve_public_school(text),platform.submit_access_recovery(text,text,text),platform.deny_access_recovery(uuid,uuid,text),platform.issue_plan_authorization(uuid,uuid,text,text,text,timestamptz,timestamptz,integer,text,text,timestamptz,text),platform.claim_plan_authorization(uuid,text,text),platform.complete_plan_authorization(uuid,uuid,text),platform.release_plan_authorization_claim(uuid,uuid,text),platform.revoke_plan_authorization(uuid,uuid,uuid,text),platform.delete_revoked_plan_authorization(uuid,uuid,uuid,text),platform.release_gate(),platform.record_release_gate() to edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0022_reference_control_operations') on conflict do nothing;
update app.release_identity set schema_version='0022' where edition='Edusentia Enterprise Neon Edition';

commit;
