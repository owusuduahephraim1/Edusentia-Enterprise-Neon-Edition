begin;

alter table platform.tenant_control
  add column if not exists student_capacity_reason text not null default '';

create or replace function platform.issue_admin_setup_token(
  p_tenant_id uuid,p_actor uuid,p_token_hash text,p_expires_at timestamptz
) returns jsonb
language plpgsql security definer set search_path=platform,app,authn,pg_catalog as $$
declare t platform.tenant_control%rowtype; v_user uuid; v_email text;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then
    raise exception 'unauthorised' using errcode='42501';
  end if;
  if p_expires_at<=now() or p_expires_at>now()+interval '24 hours' then
    raise exception 'invalid_setup_expiry' using errcode='22023';
  end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;
  if not found or t.status not in('provisioning','active','suspended') then
    raise exception 'tenant_not_ready' using errcode='55000';
  end if;
  select u.id,u.email into v_user,v_email
    from authn.users u
    join app.tenant_memberships m on m.user_id=u.id and m.tenant_id=p_tenant_id
   where lower(u.email)=lower(t.admin_email) and m.role='system_admin' and m.status='active'
   limit 1;
  if v_user is null then raise exception 'school_admin_not_ready' using errcode='55000'; end if;
  update platform.tenant_admin_setup_tokens
     set used_at=coalesce(used_at,now())
   where tenant_id=p_tenant_id and user_id=v_user and used_at is null;
  insert into platform.tenant_admin_setup_tokens(tenant_id,user_id,token_hash,created_by,expires_at)
  values(p_tenant_id,v_user,p_token_hash,p_actor,p_expires_at);
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details)
  values(p_tenant_id,t.registration_id,'admin_setup_link_issued',p_actor,jsonb_build_object('admin_email',v_email,'expires_at',p_expires_at));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
  values(p_actor,'platform.tenant.admin_setup_link_issued','tenant',p_tenant_id::text,jsonb_build_object('admin_email',v_email,'expires_at',p_expires_at));
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'tenant_code',t.tenant_code,'school_name',t.school_name,'admin_email',v_email,'expires_at',p_expires_at);
end$$;

create or replace function platform.inspect_admin_setup_token(p_token_hash text)
returns table(tenant_id uuid,user_id uuid,tenant_code text,school_name text,admin_email text,display_name text,expires_at timestamptz)
language sql security definer set search_path=platform,app,authn,pg_catalog as $$
select tok.tenant_id,tok.user_id,tc.tenant_code,tc.school_name,u.email,u.display_name,tok.expires_at
  from platform.tenant_admin_setup_tokens tok
  join platform.tenant_control tc on tc.tenant_id=tok.tenant_id
  join authn.users u on u.id=tok.user_id
  join app.tenant_memberships m on m.tenant_id=tok.tenant_id and m.user_id=tok.user_id
 where tok.token_hash=p_token_hash and tok.used_at is null and tok.expires_at>now()
   and m.role='system_admin' and m.status='active'
 limit 1
$$;

create or replace function platform.complete_admin_setup(
  p_token_hash text,p_password_hash text,p_password_salt text
) returns jsonb
language plpgsql security definer set search_path=platform,app,authn,pg_catalog as $$
declare tok platform.tenant_admin_setup_tokens%rowtype; tc platform.tenant_control%rowtype; v_email text;
begin
  select * into tok from platform.tenant_admin_setup_tokens
   where token_hash=p_token_hash and used_at is null and expires_at>now()
   for update;
  if not found then raise exception 'setup_token_invalid_or_expired' using errcode='42501'; end if;
  if not exists(
    select 1 from app.tenant_memberships
    where tenant_id=tok.tenant_id and user_id=tok.user_id and role='system_admin' and status='active' and mfa_required=true
  ) then raise exception 'school_admin_membership_invalid' using errcode='42501'; end if;
  select * into tc from platform.tenant_control where tenant_id=tok.tenant_id;
  select email into v_email from authn.users where id=tok.user_id and disabled_at is null;
  if v_email is null then raise exception 'school_admin_unavailable' using errcode='42501'; end if;
  insert into authn.password_credentials(user_id,password_hash,password_salt,algorithm,password_changed_at,failed_attempts,locked_until)
  values(tok.user_id,p_password_hash,p_password_salt,'scrypt-n32768-r8-p1',now(),0,null)
  on conflict(user_id) do update set
    password_hash=excluded.password_hash,password_salt=excluded.password_salt,algorithm=excluded.algorithm,
    password_changed_at=now(),failed_attempts=0,locked_until=null;
  update platform.tenant_admin_setup_tokens set used_at=now() where id=tok.id;
  update authn.sessions set revoked_at=coalesce(revoked_at,now()) where user_id=tok.user_id and tenant_id=tok.tenant_id;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details)
  values(tok.tenant_id,tc.registration_id,'admin_setup_completed',tok.user_id,jsonb_build_object('admin_email',v_email));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
  values(tok.user_id,'tenant.admin.initial_password_set','tenant',tok.tenant_id::text,jsonb_build_object('admin_email',v_email));
  return jsonb_build_object('ok',true,'tenant_id',tok.tenant_id,'tenant_code',tc.tenant_code,'school_name',tc.school_name,'admin_email',v_email,'mfa_required',true);
end$$;

revoke all on function platform.issue_admin_setup_token(uuid,uuid,text,timestamptz) from public;
revoke all on function platform.inspect_admin_setup_token(text) from public;
revoke all on function platform.complete_admin_setup(text,text,text) from public;
revoke all on platform.tenant_admin_setup_tokens from edusentia_worker_runtime;
grant execute on function
  platform.issue_admin_setup_token(uuid,uuid,text,timestamptz),
  platform.inspect_admin_setup_token(text),
  platform.complete_admin_setup(text,text,text)
to edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0019_tenant_admin_setup_handoff') on conflict do nothing;
update app.release_identity set schema_version='0019' where edition='Edusentia Enterprise Neon Edition';

commit;
