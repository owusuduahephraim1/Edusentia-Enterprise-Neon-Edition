begin;

create or replace function platform.school_prefix(input_school_name text)
returns text language plpgsql immutable set search_path=pg_catalog as $$
declare cleaned text := upper(btrim(regexp_replace(coalesce(input_school_name,''),'[^A-Za-z]+',' ','g')));
words text[]; result text;
begin
  if cleaned='' then raise exception 'school_name_required' using errcode='22023'; end if;
  words:=regexp_split_to_array(cleaned,E'\\s+');
  if cardinality(words)>=3 then result:=left(words[1],1)||left(words[2],1)||left(words[3],1);
  elsif cardinality(words)=2 then result:=left(words[1],2)||left(words[2],1);
  else result:=left(words[1],3); end if;
  result:=left(result||'XXX',3);
  if result !~ '^[A-Z]{3}$' then raise exception 'invalid_school_prefix' using errcode='22023'; end if;
  return result;
end$$;
create or replace function platform.slugify(input_text text)
returns text language sql immutable set search_path=pg_catalog as $$select trim(both '-' from regexp_replace(lower(coalesce(input_text,'')),'[^a-z0-9]+','-','g'))$$;
create or replace function platform.account_base(input_text text)
returns text language plpgsql immutable set search_path=pg_catalog as $$
declare cleaned text[]; part text; titles text[]:=array['mr','mrs','ms','miss','madam','master','dr','doctor','rev','reverend','prof','professor','principal','headmaster','headmistress'];
begin
  cleaned:=regexp_split_to_array(lower(regexp_replace(coalesce(input_text,''),'[^A-Za-z0-9]+',' ','g')),E'\\s+');
  foreach part in array cleaned loop part:=regexp_replace(part,'[^a-z0-9]','','g'); if part<>'' and not(part=any(titles)) then return left(part,40); end if; end loop;
  return 'admin';
end$$;
create or replace function platform.next_tenant_code(input_school_name text)
returns text language plpgsql security definer set search_path=platform,pg_catalog as $$
declare prefix text; sequence_number bigint;
begin prefix:=platform.school_prefix(input_school_name);sequence_number:=nextval('platform.tenant_code_seq');return prefix||'-'||lpad(sequence_number::text,6,'0');end$$;

create or replace function platform.bootstrap_first_super_admin(p_email text,p_display_name text,p_password_hash text,p_password_salt text)
returns jsonb language plpgsql security definer set search_path=platform,authn,pg_catalog as $$
declare v_user uuid;
begin
  if exists(select 1 from platform.admins limit 1) then raise exception 'platform_bootstrap_closed' using errcode='42501'; end if;
  if p_email is null or position('@' in p_email)<2 then raise exception 'invalid_email' using errcode='22023'; end if;
  if exists(select 1 from authn.users where lower(email)=lower(trim(p_email))) then raise exception 'email_already_exists' using errcode='23505'; end if;
  insert into authn.users(email,display_name) values(lower(trim(p_email)),trim(p_display_name)) returning id into v_user;
  insert into authn.password_credentials(user_id,password_hash,password_salt) values(v_user,p_password_hash,p_password_salt);
  insert into platform.admins(user_id,role,active,mfa_required) values(v_user,'platform_super_admin',true,true);
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(v_user,'platform.bootstrap.first_super_admin','platform_admin',v_user::text,'{}'::jsonb);
  return jsonb_build_object('user_id',v_user,'role','platform_super_admin','mfa_required',true);
end$$;
create or replace function platform.lookup_admin_login(p_email text)
returns table(user_id uuid,email text,display_name text,disabled_at timestamptz,password_hash text,password_salt text,role text,active boolean,mfa_required boolean)
language sql security definer set search_path=platform,authn,pg_catalog as $$
select u.id,u.email,u.display_name,u.disabled_at,p.password_hash,p.password_salt,a.role,a.active,a.mfa_required
from authn.users u join authn.password_credentials p on p.user_id=u.id join platform.admins a on a.user_id=u.id
where lower(u.email)=lower(trim(p_email)) limit 1
$$;

create or replace function platform.configure_initial_license(p_registration_id uuid,p_actor uuid,p_period_type text,p_period_label text,p_starts_at timestamptz,p_expires_at timestamptz,p_grace_days integer)
returns jsonb language plpgsql security definer set search_path=platform,pg_catalog as $$
declare r platform.school_registrations%rowtype; grace integer;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into r from platform.school_registrations where id=p_registration_id for update;if not found then raise exception 'registration_not_found' using errcode='P0002'; end if;
  if r.status<>'pending' then raise exception 'registration_not_pending' using errcode='55000'; end if;
  if p_period_type not in('academic_term','academic_year') then raise exception 'invalid_licence_period_type' using errcode='22023'; end if;
  if p_period_type='academic_term' and p_period_label not in('Term 1','Term 2','Term 3') then raise exception 'invalid_academic_term_name' using errcode='22023'; end if;
  if p_period_type='academic_year' and p_period_label !~ '^[0-9]{4}/[0-9]{4}$' then raise exception 'invalid_academic_year' using errcode='22023'; end if;
  if p_expires_at<=p_starts_at or p_expires_at<=now() then raise exception 'invalid_licence_window' using errcode='22023'; end if;
  grace:=greatest(0,least(90,coalesce(p_grace_days,14)));
  update platform.school_registrations set initial_license_period_type=p_period_type,initial_license_period_label=p_period_label,initial_license_starts_at=p_starts_at,initial_license_expires_at=p_expires_at,initial_license_grace_days=grace,initial_license_configured_at=now(),initial_license_configured_by=p_actor,updated_at=now() where id=p_registration_id;
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.registration.initial_license_configured','school_registration',p_registration_id::text,jsonb_build_object('period_type',p_period_type,'period_label',p_period_label,'starts_at',p_starts_at,'expires_at',p_expires_at,'grace_days',grace));
  return jsonb_build_object('ok',true,'registration_id',p_registration_id);
end$$;

create or replace function platform.approve_registration(p_registration_id uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=platform,app,authn,pg_catalog as $$
declare r platform.school_registrations%rowtype; v_tenant uuid:=gen_random_uuid(); v_code text; v_slug text; v_domain text; v_admin_email text; v_plan uuid; v_limit integer;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into r from platform.school_registrations where id=p_registration_id for update;if not found then raise exception 'registration_not_found' using errcode='P0002'; end if;
  if r.tenant_id is not null then return jsonb_build_object('ok',true,'tenant_id',r.tenant_id,'already_approved',true); end if;
  if r.status<>'pending' then raise exception 'registration_not_pending' using errcode='55000'; end if;
  if r.initial_license_configured_at is null or r.initial_license_starts_at is null or r.initial_license_expires_at is null then raise exception 'initial_license_required' using errcode='55000'; end if;
  select id,nullif(limits->>'max_students','')::integer into v_plan,v_limit from platform.license_plans where code='starter' and active limit 1;
  if v_plan is null then raise exception 'starter_plan_unavailable' using errcode='55000'; end if;
  v_code:=platform.next_tenant_code(r.school_name);v_slug:=left(platform.slugify(r.school_name),48)||'-'||right(v_code,6);v_domain:=lower(regexp_replace(v_code,'[^A-Za-z0-9]','','g'))||'.app';v_admin_email:=platform.account_base(r.contact_name)||'@'||v_domain;
  perform set_config('app.tenant_id',v_tenant::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
  insert into app.tenants(id,code,name,institution_type,status) values(v_tenant,v_code,r.school_name,r.institution_type,'provisioning');
  insert into app.school_settings(tenant_id,legal_name,short_name) values(v_tenant,r.school_name,r.school_name);
  insert into app.tenant_licenses(tenant_id,plan_id,status,starts_at,expires_at) values(v_tenant,v_plan,'pending_activation',r.initial_license_starts_at,r.initial_license_expires_at);
  insert into platform.tenant_control(tenant_id,registration_id,tenant_code,school_name,slug,institution_type,admin_email,login_domain,status,plan_code,license_status,license_period_type,license_period_label,license_started_at,license_expires_at,license_grace_days,license_grace_ends_at,student_capacity_base,student_capacity_limit,schema_version)
  values(v_tenant,r.id,v_code,r.school_name,v_slug,r.institution_type,v_admin_email,v_domain,'provisioning','starter','pending_activation',r.initial_license_period_type,r.initial_license_period_label,r.initial_license_starts_at,r.initial_license_expires_at,greatest(0,least(90,coalesce(r.initial_license_grace_days,14))),r.initial_license_expires_at+make_interval(days=>greatest(0,least(90,coalesce(r.initial_license_grace_days,14)))),v_limit,v_limit,'0018');
  update platform.school_registrations set status='provisioning',tenant_id=v_tenant,requested_plan_code='starter',reviewed_at=now(),reviewed_by=p_actor,updated_at=now() where id=r.id;
  insert into platform.provisioning_jobs(tenant_id,idempotency_key,status,stage,blueprint_version) values(v_tenant,'tenant:'||v_tenant::text||':neon-v1.0.0','queued','queued','neon-v1.0.0');
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(v_tenant,r.id,'registration_approved',p_actor,jsonb_build_object('plan_code','starter'));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.registration.approved','tenant',v_tenant::text,jsonb_build_object('registration_id',r.id,'tenant_code',v_code));
  return jsonb_build_object('ok',true,'tenant_id',v_tenant,'tenant_code',v_code,'admin_email',v_admin_email,'status','provisioning');
end$$;

create or replace function platform.deny_registration(p_registration_id uuid,p_actor uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare r platform.school_registrations%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'denial_reason_required' using errcode='22023'; end if;
  select * into r from platform.school_registrations where id=p_registration_id for update;if not found then raise exception 'registration_not_found' using errcode='P0002'; end if;
  if r.status='denied' then return jsonb_build_object('ok',true,'already_denied',true); end if;
  update platform.school_registrations set status='denied',rejection_reason=left(trim(p_reason),500),reviewed_at=now(),reviewed_by=p_actor,updated_at=now() where id=r.id;
  if r.tenant_id is not null then
    perform set_config('app.tenant_id',r.tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
    update app.tenants set status='suspended',updated_at=now() where id=r.tenant_id;update app.tenant_licenses set status='revoked',updated_at=now() where tenant_id=r.tenant_id;
    update platform.tenant_control set status='denied',license_status='revoked',updated_at=now() where tenant_id=r.tenant_id;
    update platform.provisioning_jobs set status='cancelled',stage='denied',last_error='School denied by platform administrator',updated_at=now() where tenant_id=r.tenant_id and status in('queued','running','failed');
  end if;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(r.tenant_id,r.id,'registration_denied',p_actor,jsonb_build_object('reason',left(trim(p_reason),500)));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.registration.denied','school_registration',r.id::text,jsonb_build_object('reason',left(trim(p_reason),500)));
  return jsonb_build_object('ok',true,'status','denied');
end$$;

create or replace function platform.complete_provisioning(p_tenant_id uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=platform,app,authn,pg_catalog as $$
declare t platform.tenant_control%rowtype;r platform.school_registrations%rowtype;v_user uuid;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  if t.status='denied' then raise exception 'denied_school_cannot_be_activated' using errcode='55000'; end if;
  select * into r from platform.school_registrations where id=t.registration_id;
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
  select id into v_user from authn.users where lower(email)=lower(t.admin_email) limit 1;
  if v_user is null then insert into authn.users(email,display_name) values(lower(t.admin_email),coalesce(nullif(trim(r.contact_name),''),'School Administrator')) returning id into v_user; end if;
  insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required) values(p_tenant_id,v_user,'system_admin','active',true) on conflict(tenant_id,user_id) do update set role='system_admin',status='active',mfa_required=true;
  update app.tenants set status='active',updated_at=now() where id=p_tenant_id;update app.tenant_licenses set status='active',updated_at=now() where tenant_id=p_tenant_id;
  update platform.tenant_control set status='active',license_status='active',activated_at=coalesce(activated_at,now()),updated_at=now() where tenant_id=p_tenant_id;
  update platform.school_registrations set status='active',updated_at=now() where id=t.registration_id;
  update platform.provisioning_jobs set status='ready',stage='ready',completed_at=coalesce(completed_at,now()),updated_at=now() where tenant_id=p_tenant_id and status<>'cancelled';
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'tenant_provisioning_completed',p_actor,jsonb_build_object('admin_user_id',v_user,'admin_email',t.admin_email));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.tenant.provisioning_completed','tenant',p_tenant_id::text,jsonb_build_object('admin_user_id',v_user));
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'tenant_code',t.tenant_code,'admin_user_id',v_user,'admin_email',t.admin_email,'status','active');
end$$;

create or replace function platform.resume_provisioning(p_tenant_id uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare t platform.tenant_control%rowtype;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;if t.status='denied' then raise exception 'denied_school_cannot_be_provisioned' using errcode='55000'; end if;
  update platform.provisioning_jobs set status='queued',stage='queued',last_error='',next_attempt_at=now(),updated_at=now() where id=(select id from platform.provisioning_jobs where tenant_id=p_tenant_id order by created_at desc limit 1);
  update platform.tenant_control set status='provisioning',updated_at=now() where tenant_id=p_tenant_id;
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);update app.tenants set status='provisioning',updated_at=now() where id=p_tenant_id;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'provisioning_resumed',p_actor,'{}'::jsonb);return jsonb_build_object('ok',true,'status','queued');
end$$;

create or replace function platform.set_tenant_status(p_tenant_id uuid,p_actor uuid,p_status text)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare t platform.tenant_control%rowtype;mapped text;lic text;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if p_status not in('active','suspended','cancelled','archived') then raise exception 'invalid_status' using errcode='22023'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  if t.status='denied' and p_status='active' then raise exception 'denied_school_cannot_be_activated' using errcode='55000'; end if;
  mapped:=case when p_status='cancelled' then 'archived' else p_status end;lic:=case when p_status='active' then 'active' when p_status='suspended' then 'suspended' else 'revoked' end;
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
  update app.tenants set status=mapped,updated_at=now() where id=p_tenant_id;update app.tenant_licenses set status=lic,updated_at=now() where tenant_id=p_tenant_id;update platform.tenant_control set status=p_status,license_status=lic,updated_at=now() where tenant_id=p_tenant_id;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'tenant_status_changed',p_actor,jsonb_build_object('status',p_status));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.tenant.status_changed','tenant',p_tenant_id::text,jsonb_build_object('status',p_status));
  return jsonb_build_object('ok',true,'status',p_status,'license_status',lic);
end$$;

create or replace function platform.refresh_tenant_capacity(p_tenant_id uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare t platform.tenant_control%rowtype;active_count integer;total_count integer;base_limit integer;custom_limit integer;effective_limit integer;state text;blocked boolean;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
  select count(*) filter(where status='active' and archived_at is null),count(*) filter(where archived_at is null) into active_count,total_count from app.students where tenant_id=p_tenant_id;
  select nullif(limits->>'max_students','')::integer into base_limit from platform.license_plans where code=t.plan_code;select nullif(limits_override->>'max_students','')::integer into custom_limit from app.tenant_licenses where tenant_id=p_tenant_id;effective_limit:=coalesce(custom_limit,base_limit);
  if effective_limit is null then state:='unlimited';blocked:=false;elsif active_count>effective_limit then state:='over_limit';blocked:=true;elsif active_count=effective_limit then state:='at_limit';blocked:=true;elsif effective_limit>0 and active_count::numeric/effective_limit>=0.8 then state:='near_limit';blocked:=false;else state:='available';blocked:=false;end if;
  update platform.tenant_control set student_capacity_base=base_limit,student_capacity_limit=effective_limit,student_active_count=active_count,student_total_count=total_count,student_capacity_status=state,student_admissions_blocked=blocked,student_capacity_checked_at=now(),updated_at=now() where tenant_id=p_tenant_id;
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'student_capacity_synced',p_actor,jsonb_build_object('active',active_count,'total',total_count,'limit',effective_limit,'status',state));
  return jsonb_build_object('ok',true,'base_limit',base_limit,'effective_limit',effective_limit,'active',active_count,'total',total_count,'status',state,'admissions_blocked',blocked);
end$$;

create or replace function platform.set_student_capacity(p_tenant_id uuid,p_actor uuid,p_limit integer,p_reason text)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare t platform.tenant_control%rowtype;overrides jsonb;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  if p_limit is not null and (p_limit<1 or p_limit>1000000) then raise exception 'student_capacity_out_of_range' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'capacity_reason_required' using errcode='22023'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
  select coalesce(limits_override,'{}'::jsonb) into overrides from app.tenant_licenses where tenant_id=p_tenant_id for update;if p_limit is null then overrides:=overrides-'max_students';else overrides:=jsonb_set(overrides,'{max_students}',to_jsonb(p_limit),true);end if;
  update app.tenant_licenses set limits_override=overrides,updated_at=now() where tenant_id=p_tenant_id;update platform.tenant_control set student_capacity_reason=left(trim(p_reason),500),updated_at=now() where tenant_id=p_tenant_id;
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.tenant.capacity_override','tenant',p_tenant_id::text,jsonb_build_object('limit',p_limit,'reason',left(trim(p_reason),500)));return platform.refresh_tenant_capacity(p_tenant_id,p_actor);
end$$;

create or replace function platform.set_tenant_license(p_tenant_id uuid,p_actor uuid,p_plan_code text,p_period_type text,p_period_label text,p_starts_at timestamptz,p_expires_at timestamptz,p_grace_days integer)
returns jsonb language plpgsql security definer set search_path=platform,app,pg_catalog as $$
declare t platform.tenant_control%rowtype;v_plan uuid;v_limit integer;grace integer;
begin
  if not exists(select 1 from platform.admins where user_id=p_actor and active and role='platform_super_admin' and mfa_required) then raise exception 'unauthorised' using errcode='42501'; end if;
  select * into t from platform.tenant_control where tenant_id=p_tenant_id for update;if not found then raise exception 'tenant_not_found' using errcode='P0002'; end if;
  select id,nullif(limits->>'max_students','')::integer into v_plan,v_limit from platform.license_plans where code=p_plan_code and active;if v_plan is null then raise exception 'plan_not_found' using errcode='P0002'; end if;
  if p_period_type not in('academic_term','academic_year') or p_expires_at<=p_starts_at then raise exception 'invalid_licence_window' using errcode='22023'; end if;grace:=greatest(0,least(90,coalesce(p_grace_days,14)));
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','platform_super_admin',true);perform set_config('app.aal','2',true);
  update app.tenant_licenses set plan_id=v_plan,status='active',starts_at=p_starts_at,expires_at=p_expires_at,updated_at=now() where tenant_id=p_tenant_id;
  update platform.tenant_control set plan_code=p_plan_code,license_status='active',license_period_type=p_period_type,license_period_label=p_period_label,license_started_at=p_starts_at,license_expires_at=p_expires_at,license_grace_days=grace,license_grace_ends_at=p_expires_at+make_interval(days=>grace),student_capacity_base=v_limit,updated_at=now() where tenant_id=p_tenant_id;
  insert into app.license_events(tenant_id,event_type,actor_id,metadata) values(p_tenant_id,'platform_license_authorized',p_actor,jsonb_build_object('plan_code',p_plan_code,'period_type',p_period_type,'period_label',p_period_label,'expires_at',p_expires_at,'grace_days',grace));
  insert into platform.tenant_events(tenant_id,registration_id,event_type,actor_id,details) values(p_tenant_id,t.registration_id,'tenant_license_changed',p_actor,jsonb_build_object('plan_code',p_plan_code,'expires_at',p_expires_at));
  insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(p_actor,'platform.tenant.license_changed','tenant',p_tenant_id::text,jsonb_build_object('plan_code',p_plan_code,'expires_at',p_expires_at));
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'plan_code',p_plan_code,'license_status','active');
end$$;

revoke all on function platform.bootstrap_first_super_admin(text,text,text,text) from public;
revoke all on function platform.lookup_admin_login(text) from public;
revoke all on function platform.next_tenant_code(text) from public;
revoke all on function platform.configure_initial_license(uuid,uuid,text,text,timestamptz,timestamptz,integer) from public;
revoke all on function platform.approve_registration(uuid,uuid) from public;
revoke all on function platform.deny_registration(uuid,uuid,text) from public;
revoke all on function platform.complete_provisioning(uuid,uuid) from public;
revoke all on function platform.resume_provisioning(uuid,uuid) from public;
revoke all on function platform.set_tenant_status(uuid,uuid,text) from public;
revoke all on function platform.refresh_tenant_capacity(uuid,uuid) from public;
revoke all on function platform.set_student_capacity(uuid,uuid,integer,text) from public;
revoke all on function platform.set_tenant_license(uuid,uuid,text,text,text,timestamptz,timestamptz,integer) from public;

grant select on platform.admins,platform.license_plans,platform.license_feature_catalog to edusentia_worker_runtime;
grant select,insert,update,delete on platform.admin_sessions,platform.admin_login_challenges,platform.school_registrations,platform.tenant_control,platform.provisioning_jobs,platform.tenant_events,platform.tenant_health,platform.access_recovery_requests,platform.admin_audit_events,platform.tenant_admin_setup_tokens to edusentia_worker_runtime;
grant usage,select on all sequences in schema platform to edusentia_worker_runtime;
grant execute on function platform.bootstrap_first_super_admin(text,text,text,text),platform.lookup_admin_login(text),platform.configure_initial_license(uuid,uuid,text,text,timestamptz,timestamptz,integer),platform.approve_registration(uuid,uuid),platform.deny_registration(uuid,uuid,text),platform.complete_provisioning(uuid,uuid),platform.resume_provisioning(uuid,uuid),platform.set_tenant_status(uuid,uuid,text),platform.refresh_tenant_capacity(uuid,uuid),platform.set_student_capacity(uuid,uuid,integer,text),platform.set_tenant_license(uuid,uuid,text,text,text,timestamptz,timestamptz,integer) to edusentia_worker_runtime;

insert into app.schema_migrations(version) values ('0018_platform_super_admin_functions') on conflict do nothing;
update app.release_identity set schema_version='0018' where edition='Edusentia Enterprise Neon Edition';
commit;
