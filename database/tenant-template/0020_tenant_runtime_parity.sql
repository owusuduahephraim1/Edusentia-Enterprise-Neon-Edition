begin;

alter table authn.mfa_totp_factors
  add column if not exists friendly_name text not null default 'Authenticator';
drop index if exists authn.mfa_totp_one_verified_active_uidx;
create index if not exists mfa_totp_user_active_idx
  on authn.mfa_totp_factors(user_id,verified_at desc)
  where disabled_at is null;


alter table platform.license_plans
  add column if not exists description text not null default '',
  add column if not exists billing_cycle text not null default 'annual',
  add column if not exists price_amount numeric,
  add column if not exists currency text not null default 'USD',
  add column if not exists feature_flags jsonb not null default '{}'::jsonb,
  add column if not exists sort_order integer not null default 100;

insert into platform.license_plans(code,name,active,limits,description,billing_cycle,price_amount,currency,feature_flags,sort_order)
values
('starter','Starter',true,'{"max_students":300,"max_teachers":30,"max_system_admins":2,"max_guardians":600,"max_storage_mb":2048}'::jsonb,'Core academic operations for a small school.','annual',null,'USD','{"payroll":false,"analytics":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"custom_branding":false,"finance_exports":false,"financial_holds":false,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":false,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,10),
('professional','Professional',true,'{"max_students":1000,"max_teachers":100,"max_system_admins":5,"max_guardians":2000,"max_storage_mb":10240}'::jsonb,'Expanded capacity, automation, templates, communication, and scheduled continuity.','annual',null,'USD','{"payroll":false,"analytics":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"custom_branding":false,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":false,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,20),
('enterprise','Enterprise School',true,'{}'::jsonb,'Unlimited school capacity and the complete implemented school feature set.','custom',null,'USD','{"payroll":true,"analytics":true,"assessment":true,"attendance":true,"governance":true,"certificates":true,"core_records":true,"finance_fees":true,"integrations":false,"report_cards":true,"bulk_workflow":true,"manual_backup":true,"notifications":true,"custom_branding":true,"finance_exports":true,"financial_holds":true,"academic_history":true,"priority_support":true,"scheduled_backup":true,"payroll_statutory":true,"advanced_analytics":false,"finance_statements":true,"uploaded_templates":true}'::jsonb,30)
on conflict(code) do update set name=excluded.name,active=excluded.active,limits=excluded.limits,description=excluded.description,billing_cycle=excluded.billing_cycle,price_amount=excluded.price_amount,currency=excluded.currency,feature_flags=excluded.feature_flags,sort_order=excluded.sort_order;

insert into platform.license_feature_catalog(code,name,description,default_enabled) values
('academic_history','Academic history','Lifecycle records, cumulative history, and transcript issuance.',true),
('advanced_analytics','Advanced analytics','Reserved for a future separately implemented analytics module. It is not available in v7.3.0.',false),
('analytics','Analytics','Performance, attendance, and completion insights.',true),
('assessment','Assessment entry','Assessment schemes, components, scores, grading, and workflow.',true),
('attendance','Attendance','Class registers and term attendance totals.',true),
('bulk_workflow','Bulk workflows','Bulk imports, transitions, and batch operations.',false),
('certificates','Certificates','Certificate templates, batches, issuance, and verification.',true),
('core_records','Core records','School, student, staff, class, term, and enrolment records.',true),
('custom_branding','Custom branding','Custom identity, logos, colours, and package branding.',false),
('finance_exports','Finance Excel Exports','Filtered Finance and fee registers exported in spreadsheet-compatible format.',false),
('finance_fees','Finance Fees','Term fee configuration, student fee obligations, payment collection, balances and receipts.',true),
('finance_statements','Finance Statements','Student and parent fee statements, payment history and class fee status views.',true),
('financial_holds','Financial Holds','Configurable financial-clearance restrictions on selected published academic outputs without altering grades.',false),
('governance','Governance','Privacy, retention, audit, security, and recovery controls.',true),
('id_cards','Student ID Card Generator','Professional front-and-back CR80 student ID cards with QR verification, lifecycle control, and printable/downloadable output.',true),
('integrations','Integrations','Reserved for future approved external integrations. It is not available in v7.3.0.',false),
('manual_backup','Manual backups','System Administrator initiated encrypted backups.',true),
('notifications','Notifications','Queued operational and academic notifications.',false),
('payroll','Payroll','Salary grades, teacher payroll profiles, monthly payroll, salary payment history and payslips.',false),
('payroll_statutory','Payroll Statutory Rules','Effective-dated SSNIT, tax, loan and other statutory payroll deduction rules.',false),
('priority_support','Priority support','External platform-owner support entitlement; it does not unlock a local software module.',false),
('report_cards','Report cards','Generate, approve, publish, store, and verify report cards.',true),
('scheduled_backup','Scheduled backups','Automated encrypted backup execution.',false),
('school_prospectus','School Prospectus Management','Academic-year school fees, requirements, transportation and policy prospectus management with revision history and professional PDF output.',true),
('staff_id_cards','Staff ID Card Generator','Professional front-and-back CR80 staff ID cards for teachers and principals with QR verification and lifecycle control.',true),
('timetable','Class Timetable','Class timetable scheduling with subject and teacher assignment, conflict protection, and teacher read-only views.',true),
('uploaded_templates','Uploaded templates','Custom PDF and DOCX report-card and certificate templates.',false)
on conflict(code) do update set name=excluded.name,description=excluded.description,default_enabled=excluded.default_enabled;

insert into app.release_identity(edition,version,source_baseline,source_commit,schema_version,api_version,frontend_version,worker_version)
values('Edusentia Enterprise Neon Tenant Runtime','neon-v1.0.0-r42-parity','Edusentia-Enterprise-r42-v18-STABLE-20260919','a181e18e0ca044db756193209b5b089cd03efb0f','0020','v1','neon-v1.0.0-r42-parity','neon-v1.0.0-r42-parity')
on conflict(edition) do update set version=excluded.version,source_baseline=excluded.source_baseline,source_commit=excluded.source_commit,schema_version=excluded.schema_version,api_version=excluded.api_version,frontend_version=excluded.frontend_version,worker_version=excluded.worker_version;

create or replace function app.platform_initialize_tenant(
  p_tenant_id uuid,p_tenant_code text,p_school_name text,p_institution_type text,p_admin_email text,p_admin_display_name text,p_plan_code text,p_starts_at timestamptz,p_expires_at timestamptz
) returns jsonb
language plpgsql security definer
set search_path=app,authn,platform,pg_catalog as $$
declare v_plan_id uuid; v_user_id uuid;
begin
  if p_tenant_id is null then raise exception 'tenant_id_required' using errcode='22023'; end if;
  if p_tenant_code !~ '^[A-Z]{3}-[0-9]{6}$' then raise exception 'invalid_tenant_code' using errcode='22023'; end if;
  if p_expires_at<=p_starts_at then raise exception 'invalid_licence_window' using errcode='22023'; end if;
  select id into v_plan_id from platform.license_plans where code=lower(trim(p_plan_code)) and active;
  if v_plan_id is null then raise exception 'plan_not_found' using errcode='P0002'; end if;

  insert into app.tenants(id,code,name,institution_type,status)
  values(p_tenant_id,upper(trim(p_tenant_code)),trim(p_school_name),trim(p_institution_type),'active')
  on conflict(id) do update set code=excluded.code,name=excluded.name,institution_type=excluded.institution_type,status='active',updated_at=now();

  perform set_config('app.tenant_id',p_tenant_id::text,true);
  -- No authenticated actor exists yet. Keep auth.uid() null while the certified
  -- compatibility trigger creates the first profile and its audit row.
  perform set_config('app.user_id','',true);
  perform set_config('app.role','system_admin',true);
  perform set_config('app.aal','2',true);

  insert into app.school_settings(tenant_id,legal_name,short_name,email)
  values(p_tenant_id,trim(p_school_name),trim(p_school_name),lower(trim(p_admin_email)))
  on conflict(tenant_id) do update set legal_name=excluded.legal_name,short_name=excluded.short_name,email=excluded.email,updated_at=now();

  select id into v_user_id from authn.users where lower(email)=lower(trim(p_admin_email)) limit 1;
  if v_user_id is null then
    insert into authn.users(email,display_name) values(lower(trim(p_admin_email)),coalesce(nullif(trim(p_admin_display_name),''),'System Administrator')) returning id into v_user_id;
  else
    update authn.users set display_name=coalesce(nullif(trim(p_admin_display_name),''),display_name),disabled_at=null where id=v_user_id;
  end if;

  -- Switch request context to the real school administrator after identity creation.
  perform set_config('app.user_id',v_user_id::text,true);

  insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required)
  values(p_tenant_id,v_user_id,'system_admin','active',true)
  on conflict(tenant_id,user_id) do update set role='system_admin',status='active',mfa_required=true;

  insert into app.tenant_licenses(tenant_id,plan_id,status,starts_at,expires_at)
  values(p_tenant_id,v_plan_id,'active',p_starts_at,p_expires_at)
  on conflict(tenant_id) do update set plan_id=excluded.plan_id,status='active',starts_at=excluded.starts_at,expires_at=excluded.expires_at,updated_at=now();

  insert into app.license_events(tenant_id,event_type,actor_id,metadata)
  values(p_tenant_id,'isolated_tenant_initialized',v_user_id,jsonb_build_object('plan_code',lower(trim(p_plan_code)),'tenant_code',upper(trim(p_tenant_code))));

  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'tenant_code',upper(trim(p_tenant_code)),'admin_user_id',v_user_id,'admin_email',lower(trim(p_admin_email)),'plan_code',lower(trim(p_plan_code)));
end$$;

create or replace function authn.platform_set_initial_password_by_email(p_tenant_id uuid,p_admin_email text,p_password_hash text,p_password_salt text)
returns jsonb
language plpgsql security definer
set search_path=authn,app,pg_catalog as $$
declare v_user uuid;
begin
  select u.id into v_user
  from authn.users u join app.tenant_memberships m on m.user_id=u.id and m.tenant_id=p_tenant_id
  where lower(u.email)=lower(trim(p_admin_email)) and m.role='system_admin' and m.status='active' and m.mfa_required=true limit 1;
  if v_user is null then raise exception 'school_admin_not_found' using errcode='P0002'; end if;
  insert into authn.password_credentials(user_id,password_hash,password_salt,algorithm,password_changed_at,failed_attempts,locked_until)
  values(v_user,p_password_hash,p_password_salt,'scrypt-n32768-r8-p1',now(),0,null)
  on conflict(user_id) do update set password_hash=excluded.password_hash,password_salt=excluded.password_salt,algorithm=excluded.algorithm,password_changed_at=now(),failed_attempts=0,locked_until=null;
  update authn.sessions set revoked_at=coalesce(revoked_at,now()) where user_id=v_user and tenant_id=p_tenant_id and revoked_at is null;
  return jsonb_build_object('ok',true,'user_id',v_user,'admin_email',lower(trim(p_admin_email)));
end$$;

create or replace function authn.platform_reset_mfa_by_email(p_tenant_id uuid,p_admin_email text)
returns jsonb
language plpgsql security definer
set search_path=authn,app,pg_catalog as $$
declare v_user uuid;
begin
  select u.id into v_user
  from authn.users u join app.tenant_memberships m on m.user_id=u.id and m.tenant_id=p_tenant_id
  where lower(u.email)=lower(trim(p_admin_email)) and m.role='system_admin' and m.status='active' and m.mfa_required=true limit 1;
  if v_user is null then raise exception 'school_admin_not_found' using errcode='P0002'; end if;
  update authn.mfa_totp_factors set disabled_at=coalesce(disabled_at,now()) where user_id=v_user and disabled_at is null;
  delete from authn.mfa_recovery_codes where user_id=v_user;
  update authn.login_challenges set used_at=coalesce(used_at,now()) where user_id=v_user and used_at is null;
  update authn.sessions set revoked_at=coalesce(revoked_at,now()) where user_id=v_user and tenant_id=p_tenant_id and revoked_at is null;
  return jsonb_build_object('ok',true,'user_id',v_user,'mfa_reset',true);
end$$;

create or replace function app.platform_health_snapshot(p_tenant_id uuid)
returns jsonb
language plpgsql security definer
set search_path=app,authn,pg_catalog as $$
declare v_active_students bigint;v_total_students bigint;v_active_users bigint;v_schema text;v_release text;
begin
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_tenant_id::text,true);perform set_config('app.role','system_admin',true);perform set_config('app.aal','2',true);
  select count(*) filter(where status='active' and archived_at is null),count(*) filter(where archived_at is null)
    into v_active_students,v_total_students from app.students where tenant_id=p_tenant_id;
  select count(*) into v_active_users from app.tenant_memberships where tenant_id=p_tenant_id and status='active';
  select schema_version,version into v_schema,v_release from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1;
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'database',current_database(),'active_students',v_active_students,'total_students',v_total_students,'active_users',v_active_users,'schema_version',coalesce(v_schema,''),'runtime_version',coalesce(v_release,''),'checked_at',now());
end$$;

create or replace function app.platform_apply_license(
  p_tenant_id uuid,p_actor uuid,p_plan_code text,p_starts_at timestamptz,p_expires_at timestamptz,p_grace_days integer,p_period_type text,p_period_label text
) returns jsonb
language plpgsql security definer
set search_path=app,platform,pg_catalog as $apply_license$
declare v_plan uuid;v_limit integer;grace integer;
begin
  if not exists(select 1 from app.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor and role='system_admin' and status='active') then raise exception 'system_admin_required' using errcode='42501'; end if;
  select id,nullif(limits->>'max_students','')::integer into v_plan,v_limit from platform.license_plans where code=p_plan_code and active;
  if v_plan is null then raise exception 'plan_not_found' using errcode='P0002'; end if;
  if p_expires_at<=p_starts_at then raise exception 'invalid_licence_window' using errcode='22023'; end if;
  grace:=greatest(0,least(90,coalesce(p_grace_days,14)));
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_actor::text,true);perform set_config('app.role','system_admin',true);perform set_config('app.aal','2',true);
  update app.tenant_licenses set plan_id=v_plan,status='active',starts_at=p_starts_at,expires_at=p_expires_at,updated_at=now() where tenant_id=p_tenant_id;
  insert into app.license_events(tenant_id,event_type,actor_id,metadata) values(p_tenant_id,'licence_authorization_redeemed',p_actor,jsonb_build_object('plan_code',p_plan_code,'period_type',p_period_type,'period_label',p_period_label,'grace_days',grace));
  return jsonb_build_object('ok',true,'plan_code',p_plan_code,'student_capacity_base',v_limit,'expires_at',p_expires_at,'grace_days',grace);
end
$apply_license$;

create or replace function app.platform_capacity_snapshot(p_tenant_id uuid)
returns jsonb
language plpgsql security definer
set search_path=app,platform,pg_catalog as $capacity_snapshot$
declare active_count integer;total_count integer;base_limit integer;override_limit integer;effective_limit integer;state text;blocked boolean;
begin
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_tenant_id::text,true);perform set_config('app.role','system_admin',true);perform set_config('app.aal','2',true);
  select count(*) filter(where status='active' and archived_at is null),count(*) filter(where archived_at is null) into active_count,total_count from app.students where tenant_id=p_tenant_id;
  select nullif(lp.limits->>'max_students','')::integer,nullif(tl.limits_override->>'max_students','')::integer into base_limit,override_limit
  from app.tenant_licenses tl left join platform.license_plans lp on lp.id=tl.plan_id where tl.tenant_id=p_tenant_id limit 1;
  effective_limit:=coalesce(override_limit,base_limit);
  if effective_limit is null then state:='unlimited';blocked:=false;
  elsif active_count>effective_limit then state:='over_limit';blocked:=true;
  elsif active_count=effective_limit then state:='at_limit';blocked:=true;
  elsif effective_limit>0 and active_count::numeric/effective_limit>=0.8 then state:='near_limit';blocked:=false;
  else state:='available';blocked:=false;end if;
  return jsonb_build_object('ok',true,'base_limit',base_limit,'effective_limit',effective_limit,'active',active_count,'total',total_count,'status',state,'admissions_blocked',blocked,'checked_at',now());
end
$capacity_snapshot$;

create or replace function app.platform_set_student_capacity(p_tenant_id uuid,p_limit integer)
returns jsonb
language plpgsql security definer
set search_path=app,pg_catalog as $set_student_capacity$
declare overrides jsonb;
begin
  if p_limit is not null and (p_limit<1 or p_limit>1000000) then raise exception 'student_capacity_out_of_range' using errcode='22023'; end if;
  perform set_config('app.tenant_id',p_tenant_id::text,true);perform set_config('app.user_id',p_tenant_id::text,true);perform set_config('app.role','system_admin',true);perform set_config('app.aal','2',true);
  select coalesce(limits_override,'{}'::jsonb) into overrides from app.tenant_licenses where tenant_id=p_tenant_id for update;
  if p_limit is null then overrides:=overrides-'max_students';else overrides:=jsonb_set(overrides,'{max_students}',to_jsonb(p_limit),true);end if;
  update app.tenant_licenses set limits_override=overrides,updated_at=now() where tenant_id=p_tenant_id;
  return app.platform_capacity_snapshot(p_tenant_id);
end
$set_student_capacity$;

revoke all on function app.platform_initialize_tenant(uuid,text,text,text,text,text,text,timestamptz,timestamptz) from public;
revoke all on function authn.platform_set_initial_password_by_email(uuid,text,text,text) from public;
revoke all on function authn.platform_reset_mfa_by_email(uuid,text) from public;
revoke all on function app.platform_health_snapshot(uuid) from public;
revoke all on function app.platform_apply_license(uuid,uuid,text,timestamptz,timestamptz,integer,text,text) from public;
revoke all on function app.platform_capacity_snapshot(uuid) from public;
revoke all on function app.platform_set_student_capacity(uuid,integer) from public;

grant execute on function app.platform_initialize_tenant(uuid,text,text,text,text,text,text,timestamptz,timestamptz),authn.platform_set_initial_password_by_email(uuid,text,text,text),authn.platform_reset_mfa_by_email(uuid,text),app.platform_health_snapshot(uuid),app.platform_apply_license(uuid,uuid,text,timestamptz,timestamptz,integer,text,text),app.platform_capacity_snapshot(uuid),app.platform_set_student_capacity(uuid,integer) to edusentia_worker_runtime;

commit;
