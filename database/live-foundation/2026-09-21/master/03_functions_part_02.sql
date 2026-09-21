-- Edusentia master foundation: public functions
-- Read-only schema snapshot from the live Edusentia Supabase master.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

SET check_function_bodies=off;

CREATE OR REPLACE FUNCTION public.platform_package_signing_key_repair(target_envelope jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_catalog', 'extensions'
AS $function$
declare
  current_secret_id uuid;
  current_payload jsonb;
  repaired_payload jsonb;
  key_id_value text:=coalesce(target_envelope->>'key_id','');
  fingerprint_value text:=coalesce(target_envelope->>'public_fingerprint','');
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for package signing key repair' using errcode='42501';
  end if;
  if target_envelope is null or jsonb_typeof(target_envelope)<>'object' then
    raise exception 'Package signing repair envelope must be a JSON object' using errcode='22023';
  end if;
  if coalesce((target_envelope->>'version')::integer,0)<>1 then
    raise exception 'Package signing repair envelope version is invalid' using errcode='22023';
  end if;
  if jsonb_typeof(target_envelope->'private_jwk')<>'object'
     or target_envelope->'private_jwk'->>'kty'<>'EC'
     or target_envelope->'private_jwk'->>'crv'<>'P-256'
     or coalesce(target_envelope->'private_jwk'->>'x','')=''
     or coalesce(target_envelope->'private_jwk'->>'y','')=''
     or coalesce(target_envelope->'private_jwk'->>'d','')='' then
    raise exception 'Package signing repair private JWK must be EC P-256' using errcode='22023';
  end if;
  if jsonb_typeof(target_envelope->'public_jwk')<>'object'
     or target_envelope->'public_jwk'->>'kty'<>'EC'
     or target_envelope->'public_jwk'->>'crv'<>'P-256'
     or coalesce(target_envelope->'public_jwk'->>'x','')<>coalesce(target_envelope->'private_jwk'->>'x','')
     or coalesce(target_envelope->'public_jwk'->>'y','')<>coalesce(target_envelope->'private_jwk'->>'y','')
     or target_envelope->'public_jwk' ? 'd' then
    raise exception 'Package signing repair public JWK does not match its private JWK' using errcode='22023';
  end if;
  if key_id_value !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$'
     or fingerprint_value !~ '^[0-9a-f]{64}$' then
    raise exception 'Package signing repair metadata is invalid' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('rce_package_signing_key_v1',0));
  select id,decrypted_secret::jsonb
    into current_secret_id,current_payload
  from vault.decrypted_secrets
  where name='rce_package_signing_key_v1'
  order by updated_at desc
  limit 1;
  if current_secret_id is null or current_payload is null then
    raise exception 'The encrypted package signing private key is unavailable. Use the documented recovery procedure.' using errcode='55000';
  end if;
  if coalesce(current_payload->'private_jwk'->>'kty','')<>coalesce(target_envelope->'private_jwk'->>'kty','')
     or coalesce(current_payload->'private_jwk'->>'crv','')<>coalesce(target_envelope->'private_jwk'->>'crv','')
     or coalesce(current_payload->'private_jwk'->>'x','')<>coalesce(target_envelope->'private_jwk'->>'x','')
     or coalesce(current_payload->'private_jwk'->>'y','')<>coalesce(target_envelope->'private_jwk'->>'y','')
     or coalesce(current_payload->'private_jwk'->>'d','')<>coalesce(target_envelope->'private_jwk'->>'d','') then
    raise exception 'Package signing repair refused because the private key would change' using errcode='55000';
  end if;
  perform vault.update_secret(
    current_secret_id,
    target_envelope::text,
    'rce_package_signing_key_v1',
    'Report Card Enterprise package signing private JWK. Metadata reconciled in place without rotating the private key.'
  );
  insert into public.platform_package_signing_identity(singleton,key_id,public_fingerprint,updated_at)
  values(true,key_id_value,fingerprint_value,now())
  on conflict(singleton) do update
    set key_id=excluded.key_id,
        public_fingerprint=excluded.public_fingerprint,
        updated_at=excluded.updated_at;
  select decrypted_secret::jsonb
    into repaired_payload
  from vault.decrypted_secrets
  where id=current_secret_id;
  if repaired_payload is null
     or coalesce(repaired_payload->'private_jwk'->>'d','')<>coalesce(target_envelope->'private_jwk'->>'d','')
     or coalesce(repaired_payload->>'key_id','')<>key_id_value
     or coalesce(repaired_payload->>'public_fingerprint','')<>fingerprint_value then
    raise exception 'Package signing metadata repair could not be verified in Vault' using errcode='55000';
  end if;
  return repaired_payload || jsonb_build_object(
    'configured',true,
    'recovery_required',false,
    'metadata_repair_required',false,
    'repaired',true
  );
end
$function$

CREATE OR REPLACE FUNCTION public.platform_preview_license_change(target_plan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare p public.license_plans%rowtype;students_count bigint;teachers_count bigint;admins_count bigint;guardians_count bigint;storage_bytes bigint;storage_mb numeric;
begin
  perform public.require_platform_super_admin();select * into p from public.license_plans where id=target_plan_id;
  if p.id is null then raise exception 'Licence plan not found' using errcode='22023';end if;
  select count(*) into students_count from public.students where status='active' and deleted_at is null;
  select count(*) into teachers_count from public.teachers where active and deleted_at is null;
  select count(*) into admins_count from public.profiles where active and public.current_app_role_for(role)::text='system_admin';
  select count(*) into guardians_count from public.profiles where active and public.current_app_role_for(role)::text='parent_guardian';
  select coalesce(sum(case when coalesce(metadata->>'size','')~'^\d+$' then (metadata->>'size')::bigint else 0 end),0) into storage_bytes from storage.objects where bucket_id in ('student-photos','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs');
  storage_mb:=round(storage_bytes/1048576.0,2);
  return jsonb_build_object('plan',to_jsonb(p),'usage',jsonb_build_object('active_students',students_count,'active_teachers',teachers_count,'active_system_admins',admins_count,'active_guardians',guardians_count,'storage_mb',storage_mb),
    'compatible',(p.max_students is null or students_count<=p.max_students) and (p.max_teachers is null or teachers_count<=p.max_teachers) and (p.max_system_admins is null or admins_count<=p.max_system_admins) and (p.max_guardians is null or guardians_count<=p.max_guardians) and (p.max_storage_mb is null or storage_mb<=p.max_storage_mb),
    'excess',jsonb_build_object('students',greatest(students_count-coalesce(p.max_students,students_count),0),'teachers',greatest(teachers_count-coalesce(p.max_teachers,teachers_count),0),'system_admins',greatest(admins_count-coalesce(p.max_system_admins,admins_count),0),'guardians',greatest(guardians_count-coalesce(p.max_guardians,guardians_count),0),'storage_mb',greatest(storage_mb-coalesce(p.max_storage_mb,storage_mb),0)));
end $function$

CREATE OR REPLACE FUNCTION public.platform_record_package_download(target_artifact_id uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result_count bigint;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service-role package download recording is required' using errcode='42501';end if;
  update public.platform_package_artifacts
     set last_downloaded_at=now(),download_count=coalesce(download_count,0)+1
   where id=target_artifact_id and status='ready' and deletion_state='none'
   returning download_count into result_count;
  if result_count is null then raise exception 'Package is unavailable, revoked, or pending deletion' using errcode='22023';end if;
  return result_count;
end $function$

CREATE OR REPLACE FUNCTION public.platform_register_package_template(target_package_version text, target_storage_path text, target_sha256 text, target_file_size bigint, target_required_files jsonb, target_uploaded_by uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare new_template public.platform_package_templates%rowtype;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service-role package registration is required' using errcode='42501';end if;
  if btrim(coalesce(target_package_version,''))='' or btrim(coalesce(target_storage_path,''))='' then raise exception 'Package version and Storage path are required' using errcode='22023';end if;
  if coalesce(target_sha256,'')!~'^[a-f0-9]{64}$' or coalesce(target_file_size,0)<=0 then raise exception 'Package template integrity metadata is invalid' using errcode='22023';end if;
  if target_uploaded_by is null or not exists(select 1 from public.profiles p where p.id=target_uploaded_by and p.active and public.current_app_role_for(p.role)::text='platform_super_admin') then raise exception 'Active Platform Super Administrator is required' using errcode='42501';end if;
  perform pg_advisory_xact_lock(hashtext('rce-platform-package-template-registration'));
  update public.platform_package_templates set active=false,updated_at=now() where active;
  insert into public.platform_package_templates(package_version,storage_path,sha256,file_size,required_files,active,uploaded_by)
  values(btrim(target_package_version),btrim(target_storage_path),lower(target_sha256),target_file_size,coalesce(target_required_files,'[]'::jsonb),true,target_uploaded_by) returning * into new_template;
  insert into public.platform_package_events(event_type,actor_id,template_id,event_data)
  values('template_installed',target_uploaded_by,new_template.id,jsonb_build_object('storage_path',new_template.storage_path,'sha256',new_template.sha256,'bytes',new_template.file_size,'package_version',new_template.package_version));
  return to_jsonb(new_template);
end $function$

CREATE OR REPLACE FUNCTION public.platform_release_access_lock(target_lock_id uuid, reason_text text DEFAULT 'Access lock released'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare old_lock public.platform_access_locks%rowtype;license_id_value uuid;
begin
  perform public.require_platform_super_admin();
  select * into old_lock from public.platform_access_locks where id=target_lock_id and active for update;
  if old_lock.id is null then raise exception 'Active access lock not found' using errcode='P0002'; end if;
  update public.platform_access_locks set active=false,released_at=now(),released_by=auth.uid(),release_reason=coalesce(nullif(trim(reason_text),''),'Access lock released'),updated_at=now()
  where id=target_lock_id;
  select id into license_id_value from public.school_licenses order by created_at limit 1;
  insert into public.license_events(license_id,event_type,actor_id,event_reason,old_data)
  values(license_id_value,'access_lock_released',auth.uid(),coalesce(nullif(trim(reason_text),''),'Access lock released'),to_jsonb(old_lock));
  return public.get_platform_license_console();
end $function$

CREATE OR REPLACE FUNCTION public.platform_release_gate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions', 'pg_temp'
AS $function$
declare
  v_platform_release public.platform_release_catalog%rowtype;
  v_tenant_release public.saas_tenant_releases%rowtype;
  v_platform_active_release_count bigint := 0;
  v_tenant_active_release_count bigint := 0;
  v_active_tenants bigint := 0;
  v_missing_project bigint := 0;
  v_stale_health bigint := 0;
  v_release_drift bigint := 0;
  v_schema_drift bigint := 0;
  v_unhealthy bigint := 0;
  v_failed_jobs bigint := 0;
  v_invalid_licences bigint := 0;
  v_capacity_violations bigint := 0;
  v_invalid_indexes bigint := 0;
  v_target_schema text := '';
  v_ready boolean := false;
begin
  select count(*) into v_platform_active_release_count
  from public.platform_release_catalog where status='active';
  select * into v_platform_release
  from public.platform_release_catalog where status='active' limit 1;

  select count(*) into v_tenant_active_release_count
  from public.saas_tenant_releases where status='active';
  select * into v_tenant_release
  from public.saas_tenant_releases where status='active' limit 1;

  if v_tenant_active_release_count=1 then
    select migration_version into v_target_schema
    from public.saas_tenant_release_migrations
    where release_code=v_tenant_release.release_code
      and ordinal=v_tenant_release.migration_count;
  end if;

  select count(*) into v_active_tenants
  from public.saas_tenants where status='active';

  select count(*) into v_missing_project
  from public.saas_tenants
  where status='active'
    and (coalesce(project_ref,'')='' or coalesce(project_url,'')='');

  select count(*) into v_stale_health
  from public.saas_tenants
  where status='active'
    and (last_health_checked_at is null or last_health_checked_at < now()-interval '2 hours');

  select count(*) into v_release_drift
  from public.saas_tenants
  where status='active'
    and (
      v_tenant_active_release_count<>1
      or coalesce(runtime_version,'')<>coalesce(v_tenant_release.release_code,'')
      or coalesce(release_manifest_sha256,'')<>coalesce(v_tenant_release.manifest_sha256,'')
      or coalesce(release_foundation_version,'')<>coalesce(v_tenant_release.baseline_blueprint_version,'')
      or coalesce(release_source_schema_version,-1)<>coalesce(v_tenant_release.source_schema_version,-1)
    );

  select count(*) into v_schema_drift
  from public.saas_tenants
  where status='active'
    and (coalesce(schema_migration_version,'')='' or coalesce(schema_migration_version,'')<coalesce(v_target_schema,''));

  select count(*) into v_unhealthy
  from public.saas_tenants
  where status='active'
    and (last_health_status<>'healthy' or release_status in ('drifted','schema_drift','unhealthy'));

  select count(*) into v_failed_jobs
  from public.saas_provisioning_jobs where status='failed';

  select count(*) into v_invalid_licences
  from public.saas_tenants
  where status='active'
    and (license_status not in ('active','grace_period')
      or license_expires_at is null
      or (license_grace_ends_at is not null and license_grace_ends_at<license_expires_at));

  select count(*) into v_capacity_violations
  from public.saas_tenants
  where status='active'
    and student_capacity_limit is not null
    and student_active_count>student_capacity_limit;

  select count(*) into v_invalid_indexes from pg_index where not indisvalid;

  v_ready := v_platform_active_release_count=1
    and v_tenant_active_release_count=1
    and coalesce(v_target_schema,'')<>''
    and v_missing_project=0
    and v_stale_health=0
    and v_release_drift=0
    and v_schema_drift=0
    and v_unhealthy=0
    and v_failed_jobs=0
    and v_invalid_licences=0
    and v_capacity_violations=0
    and v_invalid_indexes=0;

  return jsonb_build_object(
    'ready',v_ready,
    'release_version',coalesce(v_platform_release.release_version,''),
    'git_sha',coalesce(v_platform_release.git_sha,''),
    'tenant_release_code',coalesce(v_tenant_release.release_code,''),
    'tenant_release_manifest_sha256',coalesce(v_tenant_release.manifest_sha256,''),
    'tenant_foundation_version',coalesce(v_tenant_release.baseline_blueprint_version,''),
    'target_tenant_schema',coalesce(v_target_schema,''),
    'checked_at',now(),
    'checks',jsonb_build_object(
      'active_release_count',v_platform_active_release_count,
      'active_tenant_release_count',v_tenant_active_release_count,
      'active_tenants',v_active_tenants,
      'active_tenants_missing_project',v_missing_project,
      'stale_tenant_health',v_stale_health,
      'tenant_release_drift',v_release_drift,
      'tenant_schema_drift',v_schema_drift,
      'unhealthy_tenants',v_unhealthy,
      'failed_provisioning_jobs',v_failed_jobs,
      'invalid_active_licences',v_invalid_licences,
      'student_capacity_violations',v_capacity_violations,
      'invalid_indexes',v_invalid_indexes
    )
  );
end
$function$

CREATE OR REPLACE FUNCTION public.platform_release_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_catalog', 'extensions'
AS $function$
declare
  missing_items text[]:=array[]::text[];
  signing_secret_count bigint:=0;
  active_template_count bigint:=0;
  gate jsonb;
  active_release text:='';
begin
  if to_regclass('public.platform_package_templates') is null then missing_items:=array_append(missing_items,'platform_package_templates'); end if;
  if to_regclass('public.platform_package_artifacts') is null then missing_items:=array_append(missing_items,'platform_package_artifacts'); end if;
  if to_regclass('public.platform_package_events') is null then missing_items:=array_append(missing_items,'platform_package_events'); end if;
  if to_regclass('public.platform_package_signing_identity') is null then missing_items:=array_append(missing_items,'platform_package_signing_identity'); end if;
  if to_regclass('public.license_plans') is null then missing_items:=array_append(missing_items,'license_plans'); end if;
  if to_regclass('public.platform_release_catalog') is null then missing_items:=array_append(missing_items,'platform_release_catalog'); end if;
  if to_regprocedure('public.platform_package_session()') is null then missing_items:=array_append(missing_items,'platform_package_session()'); end if;
  if to_regprocedure('public.platform_package_signing_key_read()') is null then missing_items:=array_append(missing_items,'platform_package_signing_key_read()'); end if;
  if to_regprocedure('public.platform_clear_package_history(text,uuid)') is null then missing_items:=array_append(missing_items,'platform_clear_package_history(text,uuid)'); end if;
  if to_regprocedure('public.platform_clear_license_history(text,text)') is null then missing_items:=array_append(missing_items,'platform_clear_license_history(text,text)'); end if;
  if to_regprocedure('public.get_school_license_capacity_console()') is null then missing_items:=array_append(missing_items,'get_school_license_capacity_console()'); end if;
  if not exists(select 1 from pg_extension where extname='supabase_vault') then missing_items:=array_append(missing_items,'supabase_vault extension'); else select count(*) into signing_secret_count from vault.secrets where name='rce_package_signing_key_v1'; end if;
  if to_regclass('public.platform_package_templates') is not null then select count(*) into active_template_count from public.platform_package_templates where active; end if;
  select release_version into active_release from public.platform_release_catalog where status='active' limit 1;
  gate := public.platform_release_gate();
  return jsonb_build_object('ready',cardinality(missing_items)=0 and coalesce((gate->>'ready')::boolean,false),'version','7.4.0','release_revision',active_release,'missing',to_jsonb(missing_items),'signing_secret_present',signing_secret_count=1,'signing_secret_count',signing_secret_count,'active_template_count',active_template_count,'release_gate',gate,'checked_at',now());
end $function$

CREATE OR REPLACE FUNCTION public.platform_set_access_lock(lock_scope_text text, lock_mode_text text, reason_text text, ends_at_value timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare new_lock public.platform_access_locks%rowtype;license_id_value uuid;
begin
  perform public.require_platform_super_admin();
  if lock_scope_text not in ('system_admin','school','platform') then raise exception 'Invalid lock scope' using errcode='22023'; end if;
  if lock_mode_text not in ('read_only','deny') then raise exception 'Invalid lock mode' using errcode='22023'; end if;
  if length(trim(coalesce(reason_text,'')))<5 then raise exception 'A clear lock reason is required' using errcode='22023'; end if;
  if ends_at_value is not null and ends_at_value<=now() then raise exception 'Lock end time must be in the future' using errcode='22023'; end if;
  update public.platform_access_locks set active=false,released_at=now(),released_by=auth.uid(),release_reason='Replaced by a new lock',updated_at=now()
  where active and lock_scope=lock_scope_text;
  insert into public.platform_access_locks(lock_scope,lock_mode,reason,ends_at,created_by)
  values(lock_scope_text,lock_mode_text,trim(reason_text),ends_at_value,auth.uid()) returning * into new_lock;
  select id into license_id_value from public.school_licenses order by created_at limit 1;
  insert into public.license_events(license_id,event_type,actor_id,event_reason,new_data)
  values(license_id_value,'access_lock_applied',auth.uid(),trim(reason_text),to_jsonb(new_lock));
  return public.get_platform_license_console();
end $function$

CREATE OR REPLACE FUNCTION public.platform_set_distribution_authority(target_actor_id uuid, active_value boolean, can_generate_value boolean, can_revoke_value boolean, notes_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare caller public.platform_distribution_authorities%rowtype;code text;
begin
  perform public.require_platform_super_admin();select * into caller from public.platform_distribution_authorities where actor_id=auth.uid() and active and can_revoke;
  if caller.id is null then raise exception 'Active distributor revocation authority is required to manage distributor access' using errcode='42501';end if;
  if not exists(select 1 from public.profiles p where p.id=target_actor_id and p.active and public.current_app_role_for(p.role)::text='platform_super_admin') then raise exception 'Target account must be an active Platform Super Administrator' using errcode='22023';end if;
  if not (active_value and can_generate_value and can_revoke_value)
     and not exists(select 1 from public.platform_distribution_authorities a where a.actor_id<>target_actor_id and a.active and a.can_generate and a.can_revoke) then
    raise exception 'At least one active distributor must retain both generation and revocation authority' using errcode='23514';
  end if;
  code:='DIST-'||upper(substr(replace(target_actor_id::text,'-',''),1,12));
  insert into public.platform_distribution_authorities(actor_id,distributor_code,active,can_generate,can_revoke,notes)
  values(target_actor_id,code,active_value,can_generate_value,can_revoke_value,coalesce(notes_text,''))
  on conflict(actor_id) do update set active=excluded.active,can_generate=excluded.can_generate,can_revoke=excluded.can_revoke,notes=excluded.notes,updated_at=now();
  insert into public.license_events(event_type,actor_id,event_reason,new_data) values('distribution_authority_updated',auth.uid(),coalesce(nullif(btrim(notes_text),''),'Distributor authority updated'),jsonb_build_object('target_actor_id',target_actor_id,'active',active_value,'can_generate',can_generate_value,'can_revoke',can_revoke_value));
  return public.get_platform_license_console();
end $function$

CREATE OR REPLACE FUNCTION public.platform_set_license_override(feature_overrides jsonb, max_students_value integer, max_teachers_value integer, max_system_admins_value integer, max_guardians_value integer, max_storage_mb_value integer, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l public.school_licenses%rowtype;p public.license_plans%rowtype;reason text:=btrim(coalesce(reason_text,''));flags jsonb:=coalesce(feature_overrides,'{}'::jsonb)-'platform_package_management';
  students_count bigint;teachers_count bigint;admins_count bigint;guardians_count bigint;storage_mb numeric;limit_value integer;
begin
  perform public.require_platform_super_admin();if length(reason)<5 then raise exception 'An override reason is required' using errcode='22023';end if;
  if jsonb_typeof(flags)<>'object' or exists(select 1 from jsonb_each(flags) x where jsonb_typeof(x.value)<>'boolean') then raise exception 'Every feature override must be a Boolean value' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(flags) x where not exists(select 1 from public.license_feature_catalog f where f.code=x.key)) then raise exception 'Feature overrides contain an unknown feature code' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(flags) x join public.license_feature_catalog f on f.code=x.key where x.value='true'::jsonb and not f.active) then raise exception 'Inactive features cannot be enabled by an override' using errcode='22023';end if;
  if flags->'core_records'='false'::jsonb or flags->'governance'='false'::jsonb then raise exception 'core_records and governance cannot be disabled by an entitlement override' using errcode='22023';end if;
  if exists(select 1 from (values(max_students_value),(max_teachers_value),(max_system_admins_value),(max_guardians_value),(max_storage_mb_value)) v(n) where n is not null and n<=0) then raise exception 'Override capacities must be positive or unlimited' using errcode='22023';end if;
  select * into l from public.school_licenses order by created_at limit 1 for update;
  if l.id is null then raise exception 'Platform licence is not configured' using errcode='22023';end if;
  if l.package_id is not null then raise exception 'Signed generated-package entitlements cannot be changed locally; issue a replacement package' using errcode='42501';end if;
  select * into p from public.license_plans where id=l.plan_id;
  select count(*) into students_count from public.students where status='active' and deleted_at is null;
  select count(*) into teachers_count from public.teachers where active and deleted_at is null;
  select count(*) into admins_count from public.profiles where active and public.current_app_role_for(role)::text='system_admin';
  select count(*) into guardians_count from public.profiles where active and public.current_app_role_for(role)::text='parent_guardian';
  select round(coalesce(sum(case when coalesce(metadata->>'size','')~'^\d+$' then (metadata->>'size')::numeric else 0 end),0)/1048576.0,2) into storage_mb from storage.objects where bucket_id in ('student-photos','report-pdfs','system-backups','headteacher-signatures','report-card-templates','certificate-templates','certificate-pdfs');
  limit_value:=coalesce(max_students_value,p.max_students);if limit_value is not null and students_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override student capacity is below current usage (%)',students_count using errcode='23514';end if;
  limit_value:=coalesce(max_teachers_value,p.max_teachers);if limit_value is not null and teachers_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override teacher capacity is below current usage (%)',teachers_count using errcode='23514';end if;
  limit_value:=coalesce(max_system_admins_value,p.max_system_admins);if limit_value is not null and admins_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override System Administrator capacity is below current usage (%)',admins_count using errcode='23514';end if;
  limit_value:=coalesce(max_guardians_value,p.max_guardians);if limit_value is not null and guardians_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override guardian capacity is below current usage (%)',guardians_count using errcode='23514';end if;
  limit_value:=coalesce(max_storage_mb_value,p.max_storage_mb);if limit_value is not null and storage_mb>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override Storage capacity is below current usage (% MB)',storage_mb using errcode='23514';end if;
  update public.license_entitlement_overrides set active=false,revoked_by=auth.uid(),revoked_at=now(),revocation_reason='Superseded by a new override' where license_id=l.id and active;
  insert into public.license_entitlement_overrides(license_id,feature_overrides,max_students,max_teachers,max_system_admins,max_guardians,max_storage_mb,reason,created_by)
    values(l.id,flags,max_students_value,max_teachers_value,max_system_admins_value,max_guardians_value,max_storage_mb_value,reason,auth.uid());
  insert into public.license_events(license_id,event_type,actor_id,event_reason,new_data) values(l.id,'entitlement_override_set',auth.uid(),reason,jsonb_build_object('feature_overrides',flags,'max_students',max_students_value,'max_teachers',max_teachers_value,'max_system_admins',max_system_admins_value,'max_guardians',max_guardians_value,'max_storage_mb',max_storage_mb_value));return public.get_platform_license_console();
end $function$

CREATE OR REPLACE FUNCTION public.platform_update_license(target_plan_id uuid, target_status text, issue_date date, activation_date timestamp with time zone DEFAULT NULL::timestamp with time zone, expiry_date timestamp with time zone DEFAULT NULL::timestamp with time zone, grace_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, license_reference_text text DEFAULT ''::text, notes_text text DEFAULT ''::text, compliance_reason_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cur public.school_licenses%rowtype;updated public.school_licenses%rowtype;p public.license_plans%rowtype;preview jsonb;old_json jsonb;effective_activation timestamptz;
begin
  perform public.require_platform_super_admin();select * into p from public.license_plans where id=target_plan_id and active;if p.id is null then raise exception 'Select an active licence plan' using errcode='22023';end if;
  select * into cur from public.school_licenses order by created_at limit 1 for update;
  if cur.id is null then raise exception 'Platform licence is not configured' using errcode='22023';end if;
  if cur.package_id is not null then raise exception 'Signed generated-package licences cannot be amended locally; issue a replacement package' using errcode='42501';end if;
  if target_status not in ('pending_activation','active','grace_period','expired','suspended','revoked','perpetual') then raise exception 'Invalid licence status' using errcode='22023';end if;
  if issue_date is null or length(btrim(coalesce(license_reference_text,'')))<5 then raise exception 'Issue date and a valid licence reference are required' using errcode='22023';end if;
  if target_status in ('suspended','revoked') and length(btrim(coalesce(compliance_reason_text,'')))<5 then raise exception 'A compliance reason is required' using errcode='22023';end if;
  effective_activation:=case when target_status in ('active','grace_period','perpetual') then coalesce(activation_date,now()) else activation_date end;
  if target_status in ('active','grace_period','perpetual','expired') and issue_date>current_date then raise exception 'Issue date cannot be in the future for this status' using errcode='22023';end if;
  if effective_activation is not null and effective_activation::date<issue_date then raise exception 'Activation date cannot precede issue date' using errcode='22023';end if;
  if target_status in ('active','grace_period','perpetual') and effective_activation>now() then raise exception 'Activation date cannot be in the future for an active licence' using errcode='22023';end if;
  if target_status='perpetual' and not p.perpetual_allowed then raise exception 'The selected plan does not permit perpetual licensing' using errcode='22023';end if;
  if target_status='perpetual' and (expiry_date is not null or grace_end_date is not null) then raise exception 'A perpetual licence cannot have expiry or grace dates' using errcode='22023';end if;
  if target_status<>'perpetual' and p.billing_cycle in ('monthly','annual') and expiry_date is null then raise exception 'This plan requires an expiry date' using errcode='22023';end if;
  if expiry_date is not null and (expiry_date::date<issue_date or (effective_activation is not null and expiry_date<=effective_activation)) then raise exception 'Expiry must be after issue and activation' using errcode='22023';end if;
  if target_status<>'perpetual' and p.billing_cycle in ('monthly','annual') and expiry_date>coalesce(effective_activation,issue_date::timestamptz)+make_interval(days=>p.default_term_days)+interval '1 day' then raise exception 'Expiry exceeds the selected plan term of % days',p.default_term_days using errcode='22023';end if;
  if grace_end_date is not null and (expiry_date is null or grace_end_date<expiry_date or grace_end_date>expiry_date+make_interval(days=>p.grace_days)) then raise exception 'Grace end must be between expiry and the plan grace limit' using errcode='22023';end if;
  if target_status='grace_period' and (expiry_date is null or grace_end_date is null or expiry_date>now() or grace_end_date<now()) then raise exception 'Grace-period status requires a past expiry and a current grace window' using errcode='22023';end if;
  if target_status='expired' and (expiry_date is null or expiry_date>now()) then raise exception 'Expired status requires an expiry date that has passed' using errcode='22023';end if;
  if target_status='active' and expiry_date is not null and expiry_date<=now() then raise exception 'Active status requires a future expiry date' using errcode='22023';end if;
  preview:=public.platform_preview_license_change(target_plan_id);if not (preview->>'compatible')::boolean then raise exception 'LICENSE_DOWNGRADE_BLOCKED: Current usage exceeds the target plan: %',preview->'excess' using errcode='23514';end if;
  old_json:=to_jsonb(cur);
  update public.school_licenses set plan_id=p.id,plan_revision=p.revision,license_reference=btrim(license_reference_text),status=target_status,issued_on=issue_date,activated_at=effective_activation,expires_at=case when target_status='perpetual' then null else expiry_date end,grace_ends_at=case when target_status='perpetual' then null else grace_end_date end,notes=coalesce(notes_text,''),compliance_reason=coalesce(compliance_reason_text,''),
    entitlement_snapshot='{}'::jsonb,entitlement_payload='',entitlement_hash='',entitlement_signature='',signature_algorithm='',signature_key_id='',signature_status='not_required',signature_verified_at=null,package_id=null,installation_id=null,tenant_code='',authorized_domains='{}'::text[],project_ref='',distributor_id=null,authority_url='',authority_token='',authority_status='not_required',authority_checked_at=null,authority_last_success_at=null,updated_by=auth.uid(),updated_at=now() where id=cur.id returning * into updated;
  insert into public.license_events(license_id,event_type,actor_id,event_reason,old_data,new_data) values(updated.id,'license_updated',auth.uid(),coalesce(nullif(compliance_reason_text,''),'Platform licence updated'),old_json-'license_key_hash',to_jsonb(updated)-'license_key_hash');return public.get_platform_license_console();
end $function$

CREATE OR REPLACE FUNCTION public.platform_upsert_license_plan(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare pid uuid:=public.safe_uuid(payload->>'id');p public.license_plans%rowtype;preview jsonb;reason text:=btrim(coalesce(payload->>'reason',''));
  plan_code text:=lower(btrim(coalesce(payload->>'code','')));plan_name text:=btrim(coalesce(payload->>'name',''));
  cycle text:=lower(btrim(coalesce(payload->>'billing_cycle','annual')));support text:=lower(btrim(coalesce(payload->>'support_level','standard')));
  flags jsonb:=coalesce(payload->'feature_flags','{}'::jsonb)-'platform_package_management';term_days integer;grace_value integer;
begin
  perform public.require_platform_super_admin();
  if jsonb_typeof(coalesce(payload,'{}'::jsonb))<>'object' then raise exception 'Plan payload must be a JSON object' using errcode='22023';end if;
  if length(reason)<5 then raise exception 'A plan revision reason is required' using errcode='22023';end if;
  if pid is null and plan_code!~'^[a-z][a-z0-9_]{2,39}$' then raise exception 'Plan code must contain 3-40 lowercase letters, numbers, or underscores' using errcode='22023';end if;
  if length(plan_name)<3 or length(plan_name)>100 then raise exception 'Plan name must contain 3-100 characters' using errcode='22023';end if;
  if cycle not in ('monthly','annual','custom') then raise exception 'Billing cycle must be monthly, annual, or custom' using errcode='22023';end if;
  if support not in ('standard','priority','enterprise','custom') then raise exception 'Support level must be standard, priority, enterprise, or custom' using errcode='22023';end if;
  if jsonb_typeof(flags)<>'object' or exists(select 1 from jsonb_each(flags) x where jsonb_typeof(x.value)<>'boolean') then raise exception 'Every plan feature flag must be a Boolean value' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(flags) x where not exists(select 1 from public.license_feature_catalog f where f.code=x.key)) then raise exception 'Feature flags contain an unknown feature code' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(flags) x join public.license_feature_catalog f on f.code=x.key where x.value='true'::jsonb and not f.active) then raise exception 'Inactive features cannot be enabled' using errcode='22023';end if;
  if flags->'core_records' is distinct from 'true'::jsonb or flags->'governance' is distinct from 'true'::jsonb then raise exception 'Every active school plan must include core_records and governance' using errcode='22023';end if;
  if payload ? 'active' and jsonb_typeof(payload->'active')<>'boolean' then raise exception 'Plan active status must be Boolean' using errcode='22023';end if;
  if payload ? 'perpetual_allowed' and jsonb_typeof(payload->'perpetual_allowed')<>'boolean' then raise exception 'Perpetual-allowed status must be Boolean' using errcode='22023';end if;
  term_days:=coalesce(nullif(payload->>'default_term_days','')::integer,365);grace_value:=coalesce(nullif(payload->>'grace_days','')::integer,30);
  if term_days not between 1 and 3660 or grace_value not between 0 and 365 then raise exception 'Plan term or grace period is outside the permitted range' using errcode='22023';end if;
  if exists(select 1 from (values(nullif(payload->>'max_students','')::integer),(nullif(payload->>'max_teachers','')::integer),(nullif(payload->>'max_system_admins','')::integer),(nullif(payload->>'max_guardians','')::integer),(nullif(payload->>'max_storage_mb','')::integer)) v(n) where n is not null and n<=0) then raise exception 'Plan capacities must be positive or unlimited' using errcode='22023';end if;
  if pid is not null and coalesce((payload->>'active')::boolean,true)=false and exists(select 1 from public.school_licenses where plan_id=pid) then raise exception 'A plan assigned to the current licence cannot be deactivated' using errcode='23503';end if;
  if pid is null then
    insert into public.license_plans(code,name,description,billing_cycle,max_students,max_teachers,max_system_admins,max_guardians,max_storage_mb,feature_flags,default_term_days,grace_days,perpetual_allowed,support_level,active,revision)
    values(plan_code,plan_name,coalesce(payload->>'description',''),cycle,nullif(payload->>'max_students','')::integer,nullif(payload->>'max_teachers','')::integer,nullif(payload->>'max_system_admins','')::integer,nullif(payload->>'max_guardians','')::integer,nullif(payload->>'max_storage_mb','')::integer,flags,term_days,grace_value,coalesce((payload->>'perpetual_allowed')::boolean,false),support,coalesce((payload->>'active')::boolean,true),1) returning * into p;
  else
    update public.license_plans set name=plan_name,description=coalesce(payload->>'description',''),billing_cycle=cycle,max_students=nullif(payload->>'max_students','')::integer,max_teachers=nullif(payload->>'max_teachers','')::integer,max_system_admins=nullif(payload->>'max_system_admins','')::integer,max_guardians=nullif(payload->>'max_guardians','')::integer,max_storage_mb=nullif(payload->>'max_storage_mb','')::integer,feature_flags=flags,default_term_days=term_days,grace_days=grace_value,perpetual_allowed=coalesce((payload->>'perpetual_allowed')::boolean,perpetual_allowed),support_level=support,active=coalesce((payload->>'active')::boolean,active),revision=revision+1,updated_at=now() where id=pid returning * into p;
    if p.id is null then raise exception 'Licence plan not found' using errcode='22023';end if;
  end if;
  if exists(select 1 from public.school_licenses l where l.plan_id=p.id) then
    preview:=public.platform_preview_license_change(p.id);
    if not coalesce((preview->>'compatible')::boolean,false) then raise exception 'LICENSE_CAPACITY_REACHED: The revised plan is below current usage: %',preview->'excess' using errcode='23514';end if;
  end if;
  insert into public.license_plan_revisions(plan_id,revision,snapshot,reason,actor_id) values(p.id,p.revision,to_jsonb(p),reason,auth.uid());
  insert into public.license_events(event_type,actor_id,event_reason,new_data) values('plan_revision_created',auth.uid(),reason,to_jsonb(p));return public.get_platform_license_console();
end $function$

CREATE OR REPLACE FUNCTION public.prepare_score_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare maximum numeric; component_weight numeric; rid uuid; reportid uuid; subjectid uuid;
begin
  select c.maximum_score,c.weight,sr.id,sr.report_id,sr.subject_id
  into maximum,component_weight,rid,reportid,subjectid
  from public.assessment_components c
  join public.subject_results sr on sr.id=new.subject_result_id
  where c.id=new.component_id and c.scheme_id=sr.scheme_id;
  if maximum is null then raise exception 'Assessment component does not belong to the selected scheme'; end if;
  if new.raw_score>maximum then raise exception 'Score exceeds the configured maximum'; end if;
  if auth.uid() is not null and not public.can_score_subject(reportid,subjectid) then
    raise exception 'You are not authorised to score this subject' using errcode='42501';
  end if;
  new.weighted_score:=round((new.raw_score/maximum)*component_weight,2);
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.prevent_license_history_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if auth.role() in ('service_role','supabase_admin') or auth.role() is null then
    return case when tg_op='DELETE' then old else new end;
  end if;
  raise exception 'Licensing history is append-only' using errcode='42501';
end $function$

CREATE OR REPLACE FUNCTION public.prospectus_class_range_label(value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$select case value when 'early_years' then 'Creche to Kindergarten' when 'basic_1_6' then 'Basic 1 to Basic 6' when 'basic_7_9' then 'Basic 7 to Basic 9' else value end$function$

CREATE OR REPLACE FUNCTION public.protect_profile_security_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if new.role='platform_super_admin'::public.app_role then
    new.mfa_required:=true;
  end if;
  -- A school browser session must never create, demote, deactivate, or weaken a
  -- Platform Super Administrator. Provisioning is deliberately limited to the
  -- protected SQL setup path, where auth.role() is not an authenticated user.
  if auth.role()='authenticated'
     and (old.role='platform_super_admin'::public.app_role or new.role='platform_super_admin'::public.app_role)
     and (new.role is distinct from old.role
       or new.active is distinct from old.active
       or new.mfa_required is distinct from old.mfa_required
       or new.must_change_password is distinct from old.must_change_password) then
    raise exception 'Platform Super Administrator security fields require the protected setup path' using errcode='42501';
  end if;
  -- Browser users may update ordinary personal details only. Role, activation,
  -- MFA policy and forced-password state are controlled by trusted admin paths.
  if auth.role()='authenticated' and auth.uid()=old.id then
    if new.role is distinct from old.role
       or new.active is distinct from old.active
       or new.mfa_required is distinct from old.mfa_required
       or new.must_change_password is distinct from old.must_change_password then
      raise exception 'Profile security fields cannot be changed by the account owner' using errcode='42501';
    end if;
  end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.protect_report_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if current_setting('app.report_write',true)<>'on' and auth.uid() is not null then
    raise exception 'Report records must be changed through the report workflow' using errcode='42501';
  end if;
  return coalesce(new,old);
end $function$

CREATE OR REPLACE FUNCTION public.protect_security_event_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if auth.role() in ('service_role','supabase_admin') or auth.role() is null then return old; end if;
  raise exception 'Security events cannot be deleted through the application' using errcode='42501';
end $function$

CREATE OR REPLACE FUNCTION public.publish_school_prospectus(target_prospectus_id uuid, reason_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$declare p public.school_prospectuses%rowtype;next_revision integer;snapshot jsonb;reason_value text:=btrim(coalesce(reason_text,''));begin if not public.is_system_admin() then raise exception 'Only the System Administrator can publish school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus publication' using errcode='42501';end if;select * into p from public.school_prospectuses where id=target_prospectus_id for update;if p.id is null then raise exception 'Prospectus not found';end if;if p.status='archived' then raise exception 'Archived prospectuses cannot be published';end if;if not exists(select 1 from public.school_prospectus_sections s join public.school_prospectus_items i on i.section_id=s.id where s.prospectus_id=p.id) then raise exception 'Add at least one prospectus item before publishing';end if;if exists(select 1 from public.school_prospectus_sections s join public.school_prospectus_items i on i.section_id=s.id where s.prospectus_id=p.id and s.section_type in ('main_fees','other_items','transportation') and i.charge_basis not in ('free','optional','informational') and i.amount is null) then raise exception 'Every payable fee or transport item must have an amount before publication';end if;next_revision:=p.revision_no+1;update public.school_prospectuses set status='published',revision_no=next_revision,published_by=auth.uid(),published_at=now(),updated_by=auth.uid(),updated_at=now() where id=p.id;snapshot:=public.build_school_prospectus_snapshot(p.id);insert into public.school_prospectus_revisions(prospectus_id,revision_no,snapshot,reason,published_by) values(p.id,next_revision,snapshot,reason_value,auth.uid());return snapshot;end$function$

CREATE OR REPLACE FUNCTION public.queue_incomplete_report_notifications(target_term_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare queued integer:=0; recipient uuid; item record;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  for item in
    select c.id class_id,c.name class_name,count(e.id) enrolled,
      count(r.id) filter(where r.status in ('submitted','class_reviewed','approved','published')) completed
    from public.classes c
    join public.enrollments e on e.class_id=c.id
    join public.terms t on t.academic_year_id=e.academic_year_id and t.id=target_term_id
    left join public.student_reports r on r.enrollment_id=e.id and r.term_id=t.id and r.deleted_at is null
    where c.active and c.deleted_at is null and e.active and e.deleted_at is null
    group by c.id,c.name
    having count(e.id)>count(r.id) filter(where r.status in ('submitted','class_reviewed','approved','published'))
  loop
    for recipient in
      select distinct user_id from (
        select c.class_teacher_id user_id from public.classes c where c.id=item.class_id and c.class_teacher_id is not null
        union all select cs.teacher_id from public.class_subjects cs where cs.class_id=item.class_id and cs.teacher_id is not null and cs.active
      ) q
    loop
      perform public.create_notification(recipient,'Incomplete report cards',
        item.class_name||' • '||(item.enrolled-item.completed)||' remaining','report_deadline','term',target_term_id,true);
      queued:=queued+1;
    end loop;
  end loop;
  return queued;
end $function$

CREATE OR REPLACE FUNCTION public.queue_tenant_policy_reconcile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  project_url text;
  cron_secret text;
begin
  if new.project_ref is null
     or new.project_url is null
     or new.status not in ('active','suspended') then
    return new;
  end if;

  if tg_op='UPDATE'
     and new.status is not distinct from old.status
     and new.plan_code is not distinct from old.plan_code
     and new.license_status is not distinct from old.license_status
     and new.license_expires_at is not distinct from old.license_expires_at
     and new.license_grace_days is not distinct from old.license_grace_days
     and new.license_grace_ends_at is not distinct from old.license_grace_ends_at then
    return new;
  end if;

  select decrypted_secret into project_url
  from vault.decrypted_secrets
  where name='rce_project_url'
  limit 1;

  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name='rce_cron_secret'
  limit 1;

  if coalesce(project_url,'')='' or coalesce(cron_secret,'')='' then
    raise warning 'Tenant policy reconciliation was not queued because control-plane Vault configuration is incomplete.';
    return new;
  end if;

  perform net.http_post(
    url := rtrim(project_url,'/') || '/functions/v1/tenant-policy-reconciler',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',cron_secret),
    body := jsonb_build_object('source','tenant_state_change','tenant_id',new.id),
    timeout_milliseconds := 120000
  );
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.rce_finalized_storage_object_size(target_metadata jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  raw_size text;
begin
  raw_size:=nullif(target_metadata->>'size','');
  if raw_size is null or raw_size !~ '^[0-9]+$' then
    return null;
  end if;
  begin
    return raw_size::bigint;
  exception when numeric_value_out_of_range then
    return null;
  end;
end
$function$

CREATE OR REPLACE FUNCTION public.recalculate_report_grades(target_report_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_year_id uuid;
  v_class_id uuid;
  v_previous_report_write text:=coalesce(current_setting('app.report_write',true),'');
begin
  select e.academic_year_id,e.class_id into v_year_id,v_class_id
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id and r.deleted_at is null;
  if v_class_id is null then raise exception 'Report not found'; end if;
  if exists(
    select 1
    from public.subject_results sr
    where sr.report_id=target_report_id
      and not exists(
        select 1 from public.grade_for_mark(sr.total_score,v_year_id,v_class_id,sr.subject_id)
      )
  ) then
    raise exception 'One or more subject scores are not covered by the configured grading scales';
  end if;
  -- The protected subject_results table may only be changed through controlled
  -- workflow functions. Keep the bypass transaction-local and internal.
  perform set_config('app.report_write','on',true);
  with computed as (
    select sr.id,g.grade,g.remark,g.grade_point
    from public.subject_results sr
    cross join lateral public.grade_for_mark(sr.total_score,v_year_id,v_class_id,sr.subject_id) g
    where sr.report_id=target_report_id
  )
  update public.subject_results sr
  set grade=c.grade,
      remark=c.remark,
      grade_point=c.grade_point,
      updated_at=now()
  from computed c
  where sr.id=c.id;
  -- Restore the caller's workflow guard state so this helper cannot make a
  -- direct client-side student_reports update bypass the protected workflow.
  perform set_config('app.report_write',v_previous_report_write,true);
end $function$

CREATE OR REPLACE FUNCTION public.record_backup_export(target_storage_path text, target_checksum text DEFAULT ''::text, target_row_counts jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare bid uuid;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  insert into public.backup_exports(
    storage_path,checksum,status,row_counts,initiated_by,backup_key,schema_version,
    backup_type,manifest_path,database_path,encrypted,started_at,completed_at,error_message
  )
  values(
    target_storage_path,coalesce(target_checksum,''),'completed',coalesce(target_row_counts,'{}'::jsonb),auth.uid(),
    gen_random_uuid()::text,'legacy','database',target_storage_path,target_storage_path,false,now(),now(),''
  )
  returning id into bid;
  return (select to_jsonb(b) from public.backup_exports b where b.id=bid);
end $function$

CREATE OR REPLACE FUNCTION public.record_certificate_event(target_batch_id uuid, target_certificate_id uuid, event_name text, reason_text text DEFAULT ''::text, details_data jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin
  insert into public.certificate_events(batch_id,certificate_id,event_type,reason,details)
  values(target_batch_id,target_certificate_id,event_name,btrim(coalesce(reason_text,'')),coalesce(details_data,'{}'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.record_id_card_event(target_card_id uuid, target_student_id uuid, target_event_type text, target_details jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin insert into public.id_card_events(card_id,student_id,event_type,actor_id,details) values(target_card_id,target_student_id,left(btrim(coalesce(target_event_type,'')),80),auth.uid(),coalesce(target_details,'{}'::jsonb));end$function$

CREATE OR REPLACE FUNCTION public.record_license_authority_verification(expected_hash text, authority_state text, details jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l public.school_licenses%rowtype;state text:=lower(btrim(coalesce(authority_state,'')));
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
  if state not in ('active','revoked','unreachable') then raise exception 'Invalid authority verification state' using errcode='22023';end if;
  select * into l from public.school_licenses order by created_at limit 1 for update;
  if l.id is null or l.package_id is null then raise exception 'Generated package licence is not configured' using errcode='22023';end if;
  if l.entitlement_hash<>expected_hash then raise exception 'Entitlement hash mismatch' using errcode='22023';end if;
  update public.school_licenses set authority_status=state,authority_checked_at=now(),
    authority_last_success_at=case when state='active' then now() else authority_last_success_at end,updated_at=now() where id=l.id;
  insert into public.license_verification_logs(license_id,actor_role,computed_status,access_mode,verification_source,details)
    values(l.id,'service_role',state,case when state='active' then 'full' when state='revoked' then 'locked' else 'read_only' end,'central_authority',coalesce(details,'{}'::jsonb));
  insert into public.license_events(license_id,event_type,event_reason,new_data)
    values(l.id,'central_authority_'||state,'Central authority status: '||state,coalesce(details,'{}'::jsonb));
  return jsonb_build_object('authority_status',state,'checked_at',now(),'last_success_at',case when state='active' then now() else l.authority_last_success_at end);
end $function$

CREATE OR REPLACE FUNCTION public.record_license_binding_verification(target_actor_id uuid, verified_origin_host text, verified_project_ref text, verified_installation_id uuid, details jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  l public.school_licenses%rowtype;
  host text:=lower(btrim(coalesce(verified_origin_host,'')));
  project_value text:=lower(btrim(coalesce(verified_project_ref,'')));
  expires_value timestamptz:=now()+interval '24 hours';
  binding_mode text;
begin
  if auth.role() not in ('service_role','supabase_admin') then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if target_actor_id is null or not exists(
    select 1 from public.profiles p where p.id=target_actor_id and p.active
  ) then
    raise exception 'The binding actor is missing or inactive' using errcode='22023';
  end if;
  select * into l from public.school_licenses order by created_at limit 1 for update;
  if l.id is null or l.package_id is null then
    raise exception 'Generated package licence is not configured' using errcode='22023';
  end if;
  if l.signature_status<>'verified' then
    raise exception 'Generated package licence signature has not been verified' using errcode='42501';
  end if;
  if l.authority_status='revoked' then
    raise exception 'Generated package licence has been revoked by the platform authority' using errcode='42501';
  end if;
  if l.authority_status not in ('active','unreachable')
     or l.authority_last_success_at is null
     or l.authority_last_success_at<now()-interval '72 hours' then
    raise exception 'Central licence authority verification is required' using errcode='42501';
  end if;
  if verified_installation_id is distinct from l.installation_id then
    raise exception 'Installation identifier does not match the licence' using errcode='42501';
  end if;
  if project_value='' or project_value<>lower(btrim(l.project_ref)) then
    raise exception 'Supabase project binding does not match the licence' using errcode='42501';
  end if;
  if host='' then
    raise exception 'A verified browser origin host is required' using errcode='42501';
  end if;
  binding_mode:=case when cardinality(coalesce(l.authorized_domains,'{}'::text[]))>0 then 'host_locked' else 'project_bound_only' end;
  if binding_mode='host_locked'
     and host not in ('localhost','127.0.0.1','::1','[::1]')
     and not exists(
       select 1 from unnest(l.authorized_domains) d where lower(btrim(d))=host
     ) then
    raise exception 'This website domain is not authorised by the licence' using errcode='42501';
  end if;
  insert into public.license_binding_sessions(license_id,actor_id,origin_host,project_ref,installation_id,verified_at,expires_at)
  values(l.id,target_actor_id,host,project_value,verified_installation_id,now(),expires_value)
  on conflict(license_id,actor_id) do update set
    origin_host=excluded.origin_host,project_ref=excluded.project_ref,
    installation_id=excluded.installation_id,verified_at=excluded.verified_at,expires_at=excluded.expires_at;
  insert into public.license_verification_logs(license_id,actor_role,computed_status,access_mode,verification_source,details)
  values(
    l.id,'service_role','binding_verified','full','edge_origin_binding',
    coalesce(details,'{}'::jsonb)||jsonb_build_object(
      'actor_id',target_actor_id,'origin_host',host,'project_ref',project_value,
      'installation_id',verified_installation_id,'domain_binding_mode',binding_mode
    )
  );
  return jsonb_build_object(
    'authorised',true,'binding_required',true,'domain_binding_mode',binding_mode,
    'actor_id',target_actor_id,'origin_host',host,'expires_at',expires_value
  );
end $function$

CREATE OR REPLACE FUNCTION public.record_license_signature_verification(expected_hash text, key_id text, verified boolean, details jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l public.school_licenses%rowtype;
begin
  if auth.role() not in ('service_role','supabase_admin') then raise exception 'Service role required' using errcode='42501'; end if;
  select * into l from public.school_licenses order by created_at limit 1 for update;
  if l.id is null or l.entitlement_hash<>lower(btrim(expected_hash)) or l.signature_key_id<>btrim(key_id) then raise exception 'Licence verification metadata mismatch' using errcode='22023'; end if;
  update public.school_licenses set signature_status=case when verified then 'verified' else 'invalid' end,
    signature_verified_at=case when verified then now() else null end,updated_at=now() where id=l.id;
  insert into public.license_verification_logs(license_id,actor_role,computed_status,access_mode,verification_source,details)
  values(l.id,'service_role',case when verified then 'verified' else 'invalid' end,case when verified then 'full' else 'locked' end,'ecdsa_p256',coalesce(details,'{}'::jsonb));
  return jsonb_build_object('verified',verified,'license_id',l.id,'package_id',l.package_id);
end $function$

CREATE OR REPLACE FUNCTION public.record_security_event(event_type_text text, severity_text text, message_text text, details_data jsonb DEFAULT '{}'::jsonb, source_text text DEFAULT 'application'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare eid bigint; sev text:=lower(coalesce(severity_text,'info'));
begin
  if auth.uid() is null and coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception 'Authentication required' using errcode='42501'; end if;
  if sev not in ('info','warning','high','critical') then sev:='warning'; end if;
  insert into public.security_events(actor_id,event_type,severity,source,message,details)
  values(auth.uid(),left(coalesce(event_type_text,'unknown'),100),sev,left(coalesce(source_text,'application'),100),left(coalesce(message_text,'Security event'),1000),coalesce(details_data,'{}'::jsonb)) returning id into eid;
  return eid;
end $function$

CREATE OR REPLACE FUNCTION public.record_staff_id_card_event(target_card_id uuid, target_staff_type text, target_staff_id uuid, event_name text, event_details jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin insert into public.staff_id_card_events(card_id,staff_type,staff_record_id,event_type,actor_id,details) values(target_card_id,target_staff_type,target_staff_id,event_name,auth.uid(),coalesce(event_details,'{}'::jsonb));end$function$

CREATE OR REPLACE FUNCTION public.record_student_lifecycle_event(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid:=public.safe_uuid(payload->>'student_id');etype text:=lower(coalesce(payload->>'event_type','')); evt public.student_lifecycle_events; current_class uuid;
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can manage student lifecycle records' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if etype not in ('transfer_in','transfer_out','withdrawn','graduated','inactive','reactivated','archived') then raise exception 'Invalid lifecycle event'; end if;
  if length(btrim(coalesce(payload->>'reason','')))<5 then raise exception 'A reason of at least 5 characters is required'; end if;
  select e.class_id into current_class from public.enrollments e where e.student_id=sid and e.active and e.deleted_at is null order by e.created_at desc limit 1;
  insert into public.student_lifecycle_events(student_id,event_type,effective_date,from_class_id,to_class_id,destination_school,reason,reference)
  values(sid,etype,coalesce(public.safe_date(payload->>'effective_date'),current_date),coalesce(public.safe_uuid(payload->>'from_class_id'),current_class),public.safe_uuid(payload->>'to_class_id'),left(coalesce(payload->>'destination_school',''),250),btrim(payload->>'reason'),left(coalesce(payload->>'reference',''),250)) returning * into evt;
  if etype in ('transfer_out','withdrawn','archived') then
    update public.students set status='withdrawn',updated_at=now() where id=sid;
    update public.enrollments set active=false,updated_at=now() where student_id=sid and active and deleted_at is null;
  elsif etype='graduated' then
    update public.students set status='graduated',updated_at=now() where id=sid;
    update public.enrollments set active=false,updated_at=now() where student_id=sid and active and deleted_at is null;
  elsif etype='inactive' then
    update public.students set status='suspended',updated_at=now() where id=sid;
  elsif etype in ('reactivated','transfer_in') then
    update public.students set status='active',updated_at=now() where id=sid;
  end if;
  return to_jsonb(evt);
end $function$

CREATE OR REPLACE FUNCTION public.refresh_report_promotion(target_report_id uuid, create_target_enrollment boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  evaluation jsonb;
  eligible_for_promotion boolean;
  should_apply_enrollment boolean;
  next_class_id uuid;
  target_year_id uuid;
  source_student_id uuid;
  source_enrollment_id uuid;
  enrollment_created boolean:=false;
  enrollment_withdrawn boolean:=false;
begin
  evaluation:=public.report_promotion_evaluation(target_report_id);
  eligible_for_promotion:=coalesce((evaluation->>'eligible')::boolean,false);
  should_apply_enrollment:=coalesce((evaluation->>'can_create_enrollment')::boolean,false);
  next_class_id:=public.safe_uuid(evaluation->>'next_class_id');
  target_year_id:=public.safe_uuid(evaluation->>'target_academic_year_id');
  select e.student_id,e.id into source_student_id,source_enrollment_id
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id and e.deleted_at is null
  where r.id=target_report_id and r.deleted_at is null;
  perform set_config('app.report_write','on',true);
  update public.student_reports
  set promoted_to_class_id=case when should_apply_enrollment then next_class_id else null end,
      updated_at=now()
  where id=target_report_id and deleted_at is null;
  if create_target_enrollment and source_student_id is not null and target_year_id is not null then
    if should_apply_enrollment then
      insert into public.enrollments(
        student_id,academic_year_id,class_id,active,deleted_at,updated_at,
        enrollment_origin,promotion_source_report_id,promotion_applied_at
      )
      values(
        source_student_id,target_year_id,next_class_id,true,null,now(),
        'automatic_promotion',target_report_id,now()
      )
      on conflict(student_id,academic_year_id) do update
        set class_id=excluded.class_id,
            active=true,
            deleted_at=null,
            updated_at=now(),
            enrollment_origin='automatic_promotion',
            promotion_source_report_id=target_report_id,
            promotion_applied_at=now();
      update public.enrollments
      set active=false,updated_at=now()
      where student_id=source_student_id
        and deleted_at is null
        and id<>coalesce((select id from public.enrollments where student_id=source_student_id and academic_year_id=target_year_id and deleted_at is null limit 1),'00000000-0000-0000-0000-000000000000'::uuid);
      enrollment_created:=true;
    else
      update public.enrollments as target_enrollment
      set active=false,
          deleted_at=now(),
          updated_at=now(),
          promotion_applied_at=null
      where target_enrollment.student_id=source_student_id
        and target_enrollment.academic_year_id=target_year_id
        and target_enrollment.enrollment_origin='automatic_promotion'
        and target_enrollment.promotion_source_report_id=target_report_id
        and target_enrollment.deleted_at is null;
      enrollment_withdrawn:=found;
      if source_enrollment_id is not null then
        update public.enrollments
        set active=true,updated_at=now()
        where id=source_enrollment_id and deleted_at is null;
      end if;
    end if;
  end if;
  return evaluation||jsonb_build_object(
    'eligible',eligible_for_promotion,
    'promoted_to_class_id',case when should_apply_enrollment then next_class_id else null end,
    'enrollment_created_or_updated',enrollment_created,
    'enrollment_withdrawn',enrollment_withdrawn,
    'promotion_applied',case
      when enrollment_created then true
      when enrollment_withdrawn then false
      else coalesce((evaluation->>'promotion_applied')::boolean,false)
    end
  );
end $function$

CREATE OR REPLACE FUNCTION public.refresh_subject_result(target_result_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare total_value numeric; ay uuid; cid uuid; sid uuid; g record;
begin
  select coalesce(sum(e.weighted_score),0) into total_value
  from public.assessment_score_entries e where e.subject_result_id=target_result_id;
  select en.academic_year_id,en.class_id,sr.subject_id into ay,cid,sid
  from public.subject_results sr
  join public.student_reports r on r.id=sr.report_id
  join public.enrollments en on en.id=r.enrollment_id
  where sr.id=target_result_id;
  select * into g from public.grade_for_mark(total_value,ay,cid,sid);
  update public.subject_results
  set total_score=round(total_value,2),grade=coalesce(g.grade,''),
      remark=coalesce(g.remark,''),grade_point=coalesce(g.grade_point,0),updated_at=now()
  where id=target_result_id;
end $function$

CREATE OR REPLACE FUNCTION public.register_certificate_pdf(target_certificate_id uuid, target_storage_path text, target_checksum text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificates;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can store certificate PDFs' using errcode='42501'; end if;
  if btrim(coalesce(target_storage_path,''))='' or target_storage_path !~ '^[a-z_]+/[A-Za-z0-9._/-]+[.]pdf$' then raise exception 'Certificate PDF path is invalid'; end if;
  update public.certificates set pdf_storage_path=btrim(target_storage_path),pdf_sha256=lower(btrim(coalesce(target_checksum,''))),updated_at=now() where id=target_certificate_id and status='issued' returning * into updated;
  if updated.id is null then raise exception 'Issued certificate not found'; end if;
  perform public.record_certificate_event(updated.batch_id,updated.id,'pdf_registered','',jsonb_build_object('storage_path',updated.pdf_storage_path,'sha256',updated.pdf_sha256));
  return jsonb_build_object('certificate_id',updated.id,'storage_path',updated.pdf_storage_path,'checksum',updated.pdf_sha256);
end $function$

CREATE OR REPLACE FUNCTION public.register_report_pdf(target_report_id uuid, target_storage_path text, target_checksum text DEFAULT ''::text, target_page_count integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare publicationid uuid;
begin
  if not public.can_publish_report(target_report_id) then raise exception 'Only an assigned teacher or the System Administrator can create the official PDF' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.student_reports where id=target_report_id and status='published' and deleted_at is null) then raise exception 'Only a Principal-approved published report can receive an official PDF'; end if;
  update public.report_publications set storage_path=target_storage_path,checksum=coalesce(target_checksum,''),page_count=greatest(target_page_count,1)
  where report_id=target_report_id and revoked_at is null returning id into publicationid;
  if publicationid is null then raise exception 'Active publication not found'; end if;
  return (select to_jsonb(p) from public.report_publications p where p.id=publicationid);
end $function$

CREATE OR REPLACE FUNCTION public.remove_certificate_template_file(target_certificate_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result public.certificate_templates; archived_path text; archived_name text;
begin
  if not public.can_manage_certificates() then
    raise exception 'Only the System Administrator can remove certificate template designs' using errcode='42501';
  end if;
  if target_certificate_type not in ('student_promotion','jhs_completion','teacher_recognition') then
    raise exception 'Certificate type is invalid';
  end if;
  select storage_path,original_name into archived_path,archived_name
  from public.certificate_templates
  where certificate_type=target_certificate_type and active
  order by updated_at desc limit 1;
  update public.certificate_templates
  set storage_path='',original_name='',mime_type='',file_size=0,checksum='',version=version+1,uploaded_by=null,updated_at=now()
  where certificate_type=target_certificate_type and active
  returning * into result;
  if result.id is null then raise exception 'Active certificate template not found'; end if;
  perform public.record_certificate_event(
    null,null,'certificate_template_design_removed','',
    jsonb_build_object('certificate_type',target_certificate_type,'archived_storage_path',coalesce(archived_path,''),'archived_original_name',coalesce(archived_name,''),'version',result.version)
  );
  return to_jsonb(result);
end $function$

CREATE OR REPLACE FUNCTION public.remove_report_card_template(target_range_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result public.report_card_templates;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  if target_range_key not in ('early_years','basic_1_6','basic_7_9') then raise exception 'Invalid report-card class range'; end if;
  delete from public.report_card_templates where range_key=target_range_key returning * into result;
  return case when result.range_key is null then '{}'::jsonb else to_jsonb(result) end;
end $function$

CREATE OR REPLACE FUNCTION public.replace_staff_id_card(target_card_id uuid, reason_text text, target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare source public.staff_id_cards%rowtype;cfg public.id_card_settings%rowtype;new_id uuid;new_number text;new_token uuid;expires date:=target_expires_on;new_snapshot jsonb;reason text:=btrim(coalesce(reason_text,''));sid uuid;
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can replace staff ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A replacement reason of at least five characters is required';end if;select * into source from public.staff_id_cards where id=target_card_id and status='active' for update;if source.id is null then raise exception 'Only an active staff ID card can be replaced';end if;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.staff_validity_months,24)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'Staff ID card expiry date cannot be before issue date';end if;sid:=coalesce(source.teacher_id,source.headteacher_id);update public.staff_id_cards set status='replaced',replacement_reason=reason,updated_at=now() where id=source.id;new_number:=public.generate_staff_id_card_number(source.academic_year_id);new_token:=gen_random_uuid();new_snapshot:=public.build_staff_id_card_snapshot(source.staff_type,sid,source.academic_year_id,new_number,new_token,target_issue_date,expires);insert into public.staff_id_cards(staff_type,teacher_id,headteacher_id,academic_year_id,card_number,verification_token,revision_no,supersedes_card_id,status,issue_date,expires_on,snapshot,issued_by,replacement_reason) values(source.staff_type,source.teacher_id,source.headteacher_id,source.academic_year_id,new_number,new_token,source.revision_no+1,source.id,'active',target_issue_date,expires,new_snapshot,auth.uid(),reason) returning id into new_id;perform public.record_staff_id_card_event(source.id,source.staff_type,sid,'replaced',jsonb_build_object('replacement_card_id',new_id,'reason',reason));perform public.record_staff_id_card_event(new_id,source.staff_type,sid,'replacement_issued',jsonb_build_object('supersedes_card_id',source.id,'reason',reason));return jsonb_build_object('card_id',new_id,'card_number',new_number,'verification_token',new_token,'status','active','supersedes_card_id',source.id);end$function$

CREATE OR REPLACE FUNCTION public.replace_student_id_card(target_card_id uuid, reason_text text, target_issue_date date DEFAULT CURRENT_DATE, target_expires_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare source public.student_id_cards%rowtype;cfg public.id_card_settings%rowtype;new_id uuid;new_number text;new_token uuid;expires date:=target_expires_on;new_snapshot jsonb;reason text:=btrim(coalesce(reason_text,'')); begin if not public.is_system_admin() then raise exception 'Only the System Administrator can replace student ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A replacement reason of at least five characters is required';end if;if target_issue_date is null then raise exception 'ID card issue date is required';end if;perform pg_advisory_xact_lock(hashtext('rce-id-card-replace-'||target_card_id::text));insert into public.id_card_settings default values on conflict do nothing;select * into source from public.student_id_cards where id=target_card_id and status='active' for update;if source.id is null then raise exception 'Only an active ID card can be replaced';end if;select * into cfg from public.id_card_settings limit 1;if expires is null then expires:=(target_issue_date+(coalesce(cfg.validity_months,12)||' months')::interval)::date;end if;if expires<target_issue_date then raise exception 'ID card expiry date cannot be before the issue date';end if;update public.student_id_cards set status='replaced',replacement_reason=reason,updated_at=now() where id=source.id;new_number:=public.generate_student_id_card_number(source.academic_year_id);new_token:=gen_random_uuid();new_snapshot:=public.build_student_id_card_snapshot(source.student_id,source.enrollment_id,new_number,new_token,target_issue_date,expires);insert into public.student_id_cards(student_id,enrollment_id,academic_year_id,class_id,card_number,verification_token,revision_no,supersedes_card_id,status,issue_date,expires_on,snapshot,issued_by,replacement_reason) values(source.student_id,source.enrollment_id,source.academic_year_id,source.class_id,new_number,new_token,source.revision_no+1,source.id,'active',target_issue_date,expires,new_snapshot,auth.uid(),reason) returning id into new_id;perform public.record_id_card_event(source.id,source.student_id,'replaced',jsonb_build_object('replacement_card_id',new_id,'reason',reason));perform public.record_id_card_event(new_id,source.student_id,'replacement_issued',jsonb_build_object('supersedes_card_id',source.id,'reason',reason));return jsonb_build_object('card_id',new_id,'card_number',new_number,'verification_token',new_token,'status','active','supersedes_card_id',source.id);end$function$

CREATE OR REPLACE FUNCTION public.report_class_id(target_report_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select e.class_id
  from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id
$function$

CREATE OR REPLACE FUNCTION public.report_position(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with target as (
    select e.class_id,r.term_id,round(coalesce(avg(sr.total_score),0),2) average
    from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
    left join public.subject_results sr on sr.report_id=r.id
    where r.id=target_report_id group by e.class_id,r.term_id
  ), ranked as (
    select r.id,round(coalesce(avg(sr.total_score),0),2) average,
      dense_rank() over(order by avg(sr.total_score) desc nulls last) position
    from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
    left join public.subject_results sr on sr.report_id=r.id
    join target t on t.class_id=e.class_id and t.term_id=r.term_id
    where r.deleted_at is null and r.status in ('approved','published')
    group by r.id
  )
  select jsonb_build_object('position',coalesce((select position from ranked where id=target_report_id),0),
    'class_size',(select count(*) from ranked))
$function$

CREATE OR REPLACE FUNCTION public.report_promotion_canonical(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare v_evaluation jsonb; v_snapshot_promotion jsonb; v_status text; v_version integer; v_promoted_class_id uuid; v_promoted_class_name text; v_student_id uuid; v_target_enrollment_id uuid; v_target_year_id uuid; v_target_year_name text; v_is_final boolean:=false; begin if auth.uid() is not null and not public.can_view_report(target_report_id) then raise exception 'Access denied' using errcode='42501'; end if; select r.status::text,r.version,r.promoted_to_class_id,e.student_id into v_status,v_version,v_promoted_class_id,v_student_id from public.student_reports r join public.enrollments e on e.id=r.enrollment_id and e.deleted_at is null where r.id=target_report_id and r.deleted_at is null; if v_status is null then raise exception 'Report not found'; end if; v_is_final:=v_status in ('approved','published'); if v_is_final then select rr.snapshot->'promotion' into v_snapshot_promotion from public.report_revisions rr where rr.report_id=target_report_id and rr.version=v_version and jsonb_typeof(rr.snapshot->'promotion')='object' limit 1; if v_snapshot_promotion is not null then return v_snapshot_promotion || jsonb_build_object( 'canonical',true, 'finalized',true, 'canonical_source','finalized_report_snapshot', 'resolution_status','resolved' ); end if; end if; v_evaluation:=public.report_promotion_evaluation(target_report_id); if v_is_final and v_promoted_class_id is not null then select c.name::text into v_promoted_class_name from public.classes c where c.id=v_promoted_class_id; select en.id,en.academic_year_id,ay.name::text into v_target_enrollment_id,v_target_year_id,v_target_year_name from public.enrollments en left join public.academic_years ay on ay.id=en.academic_year_id where en.student_id=v_student_id and en.promotion_source_report_id=target_report_id and en.enrollment_origin='automatic_promotion' order by en.promotion_applied_at desc nulls last,en.updated_at desc,en.id limit 1; v_evaluation:=v_evaluation || jsonb_build_object( 'passed',true, 'eligible',true, 'next_class_id',v_promoted_class_id, 'next_class_name',coalesce(v_promoted_class_name,v_evaluation->>'next_class_name',''), 'next_class_configured',true, 'target_enrollment_id',coalesce(v_target_enrollment_id,public.safe_uuid(v_evaluation->>'target_enrollment_id')), 'target_academic_year_id',coalesce(v_target_year_id,public.safe_uuid(v_evaluation->>'target_academic_year_id')), 'target_academic_year_name',coalesce(v_target_year_name,v_evaluation->>'target_academic_year_name',''), 'promotion_applied',true, 'canonical',true, 'finalized',true, 'canonical_source','persisted_promotion_transition', 'resolution_status','resolved' ); else v_evaluation:=v_evaluation || jsonb_build_object( 'next_class_configured',(v_evaluation->>'next_class_id') is not null, 'canonical',v_is_final, 'finalized',v_is_final, 'canonical_source',case when v_is_final then 'server_final_evaluation' else 'server_live_evaluation' end, 'resolution_status','resolved' ); end if; return v_evaluation; end $function$

CREATE OR REPLACE FUNCTION public.report_promotion_evaluation(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  report_term_sequence integer;
  report_term_name text;
  report_status text;
  source_class_id uuid;
  source_class_name text;
  source_class_level integer;
  source_year_id uuid;
  source_year_name text;
  source_student_id uuid;
  next_class_id uuid;
  next_class_name text;
  target_year_id uuid;
  target_year_name text;
  target_enrollment_id uuid;
  target_enrollment_class_id uuid;
  target_enrollment_active boolean:=false;
  assigned_subjects integer:=0;
  completed_subjects integer:=0;
  average_score numeric(7,2):=0;
  cutoff_score integer:=50;
  is_complete boolean:=false;
  is_term_three boolean:=false;
  has_passed boolean:=false;
  governance_approved boolean:=false;
  promotion_applied boolean:=false;
begin
  if auth.uid() is not null and not public.can_view_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select
    t.sequence,
    t.name::text,
    r.status::text,
    e.class_id,
    c.name::text,
    c.level_order,
    e.academic_year_id,
    y.name::text,
    e.student_id
  into
    report_term_sequence,
    report_term_name,
    report_status,
    source_class_id,
    source_class_name,
    source_class_level,
    source_year_id,
    source_year_name,
    source_student_id
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id and e.deleted_at is null
  join public.classes c on c.id=e.class_id and c.deleted_at is null
  join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
  join public.terms t on t.id=r.term_id and t.deleted_at is null
  where r.id=target_report_id and r.deleted_at is null;
  if source_class_id is null then raise exception 'Report not found'; end if;
  select coalesce(s.promotion_cutoff_score,50)
  into cutoff_score
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;
  select
    count(*)::integer,
    count(sr.id)::integer,
    coalesce(round(avg(sr.total_score) filter(where sr.id is not null),2),0)
  into assigned_subjects,completed_subjects,average_score
  from public.class_subjects cs
  join public.subjects sb on sb.id=cs.subject_id and sb.active and sb.deleted_at is null
  left join public.subject_results sr
    on sr.report_id=target_report_id and sr.subject_id=cs.subject_id
  where cs.class_id=source_class_id and cs.active;
  is_term_three:=public.is_term_three(report_term_sequence,report_term_name);
  is_complete:=assigned_subjects>0 and completed_subjects=assigned_subjects;
  has_passed:=is_term_three and is_complete and average_score>=cutoff_score;
  governance_approved:=report_status in ('approved','published');
  select c.id,c.name::text
  into next_class_id,next_class_name
  from public.classes c
  where c.active and c.deleted_at is null and c.level_order>source_class_level
  order by c.level_order,c.name
  limit 1;
  target_year_id:=public.next_promotion_academic_year(source_year_id);
  if target_year_id is not null then
    select y.name::text into target_year_name
    from public.academic_years y
    where y.id=target_year_id and y.deleted_at is null;
    select e.id,e.class_id,e.active
    into target_enrollment_id,target_enrollment_class_id,target_enrollment_active
    from public.enrollments e
    where e.student_id=source_student_id
      and e.academic_year_id=target_year_id
      and e.deleted_at is null
    limit 1;
  end if;
  promotion_applied:=has_passed
    and governance_approved
    and target_enrollment_id is not null
    and target_enrollment_active
    and target_enrollment_class_id=next_class_id;
  return jsonb_build_object(
    'report_id',target_report_id,
    'report_status',report_status,
    'term_sequence',report_term_sequence,
    'term_name',report_term_name,
    'term3',is_term_three,
    'complete',is_complete,
    'assigned_subjects',assigned_subjects,
    'completed_subjects',completed_subjects,
    'average',average_score,
    'cutoff',cutoff_score,
    'passed',has_passed,
    'eligible',has_passed and next_class_id is not null,
    'governance_approved',governance_approved,
    'approval_required',has_passed and not governance_approved,
    'source_class_id',source_class_id,
    'source_class_name',source_class_name,
    'source_academic_year_id',source_year_id,
    'source_academic_year_name',source_year_name,
    'next_class_id',next_class_id,
    'next_class_name',next_class_name,
    'target_academic_year_id',target_year_id,
    'target_academic_year_name',target_year_name,
    'target_enrollment_id',target_enrollment_id,
    'target_enrollment_class_id',target_enrollment_class_id,
    'promotion_applied',promotion_applied,
    'can_create_enrollment',has_passed and governance_approved and next_class_id is not null and target_year_id is not null
  );
end $function$

CREATE OR REPLACE FUNCTION public.report_student_id(target_report_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select e.student_id
  from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id
$function$

CREATE OR REPLACE FUNCTION public.report_subject_positions(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  target_class_id uuid;
  target_term_id uuid;
  result jsonb;
begin
  if auth.uid() is null or not public.can_view_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  select e.class_id,r.term_id
  into target_class_id,target_term_id
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id
    and r.deleted_at is null
    and e.deleted_at is null;
  if target_class_id is null or target_term_id is null then
    raise exception 'Report not found';
  end if;
  with ranked as (
    select
      sr.report_id,
      sr.subject_id,
      sr.total_score,
      dense_rank() over(
        partition by sr.subject_id
        order by sr.total_score desc
      ) as subject_position,
      count(*) over(partition by sr.subject_id) as participant_count
    from public.subject_results sr
    join public.student_reports r on r.id=sr.report_id
    join public.enrollments e on e.id=r.enrollment_id
    where r.term_id=target_term_id
      and e.class_id=target_class_id
      and r.deleted_at is null
      and e.deleted_at is null
      and r.status<>'withdrawn'
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'subject_id',ranked.subject_id,
        'total_score',ranked.total_score,
        'position',ranked.subject_position,
        'participants',ranked.participant_count
      )
      order by subjects.display_order,subjects.name
    ),
    '[]'::jsonb
  )
  into result
  from ranked
  join public.subjects subjects on subjects.id=ranked.subject_id
  where ranked.report_id=target_report_id;
  return result;
end $function$

CREATE OR REPLACE FUNCTION public.report_transition_deadline_allowed(target_report_id uuid, target_status report_status)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb; deadline_value timestamptz;
begin
  if public.has_approved_report_correction(target_report_id) then return true; end if;
  s:=public.term_control_snapshot((select term_id from public.student_reports where id=target_report_id));
  if s is null or coalesce((s->>'reports_locked')::boolean,false) then return false; end if;
  if target_status in ('submitted','class_reviewed','returned') then deadline_value:=public.safe_timestamptz(s->>'report_submission_deadline');
  elsif target_status='approved' then deadline_value:=public.safe_timestamptz(s->>'principal_approval_deadline');
  elsif target_status in ('published','withdrawn') then deadline_value:=public.safe_timestamptz(s->>'publication_deadline');
  end if;
  return deadline_value is null or deadline_value>=now();
end $function$

CREATE OR REPLACE FUNCTION public.request_report_correction(target_report_id uuid, reason_text text, requested_fields jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare rid uuid; current_version integer; current_status public.report_status; req public.report_correction_requests; classid uuid; recipient uuid;
begin
  if public.current_app_role() not in ('system_admin','class_teacher','subject_teacher') then raise exception 'Only an assigned teacher or the System Administrator can request a correction' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<10 then raise exception 'A correction reason of at least 10 characters is required'; end if;
  select r.id,r.version,r.status,e.class_id into rid,current_version,current_status,classid
  from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id and r.deleted_at is null;
  if rid is null or current_status not in ('approved','published') then raise exception 'Only an approved or published report can receive a correction request'; end if;
  if exists(select 1 from public.report_correction_requests where report_id=target_report_id and status in ('pending','approved')) then raise exception 'This report already has an active correction request'; end if;
  if public.current_app_role()<>'system_admin' and not public.can_access_class(classid,false) then raise exception 'Access denied' using errcode='42501'; end if;
  insert into public.report_correction_requests(report_id,requested_by,reason,requested_fields,original_report_version,original_revision_id,original_publication_id)
  values(target_report_id,auth.uid(),btrim(reason_text),coalesce(requested_fields,'[]'::jsonb),current_version,
    (select id from public.report_revisions where report_id=target_report_id order by version desc limit 1),
    (select id from public.report_publications where report_id=target_report_id and revoked_at is null order by published_at desc limit 1))
  returning * into req;
  insert into public.report_correction_events(request_id,event_type,event_note,event_data)
  values(req.id,'requested',req.reason,jsonb_build_object('requested_fields',req.requested_fields,'report_version',current_version));
  for recipient in select p.id from public.profiles p where p.active and public.current_app_role_for(p.role)::text='principal' loop
    perform public.create_notification(recipient,'Report correction approval required',req.reason,'report_correction','report',target_report_id,true);
  end loop;
  return to_jsonb(req);
end $function$

CREATE OR REPLACE FUNCTION public.require_license_feature(feature_code text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.license_feature_enabled(feature_code) then
    raise exception 'LICENSE_FEATURE_NOT_INCLUDED: The current plan does not include %',replace(feature_code,'_',' ') using errcode='42501';
  end if;
end $function$

CREATE OR REPLACE FUNCTION public.require_platform_super_admin()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_platform_super_admin() then
    raise exception 'Platform Super Administrator access required' using errcode='42501';
  end if;
  if public.current_aal()<>'aal2' then
    raise exception 'Multi-factor authentication is required for platform licensing actions' using errcode='42501';
  end if;
end $function$

CREATE OR REPLACE FUNCTION public.require_sensitive_access()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare required boolean;
begin
  select coalesce(mfa_required,false) into required from public.profiles where id=auth.uid();
  if required and public.current_aal()<>'aal2' then
    raise exception 'Multi-factor authentication is required' using errcode='42501';
  end if;
end $function$

CREATE OR REPLACE FUNCTION public.reset_audit_log(confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  changed integer;
  archive_id uuid;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can archive the audit trail' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if upper(btrim(coalesce(confirmation_text,''))) not in ('ARCHIVE AUDIT LOG','RESET AUDIT LOG') then
    raise exception 'Type ARCHIVE AUDIT LOG to confirm';
  end if;
  perform pg_advisory_xact_lock(hashtext('rce-school-audit-archive'));
  lock table public.audit_log in access exclusive mode;
  select count(*)::integer into changed from public.audit_log;
  insert into public.audit_log_archives(archive_scope,reason,event_count,created_by)
  values('full','Full audit log archived from the active console',changed,auth.uid())
  returning id into archive_id;
  insert into public.audit_log_archive_entries(
    archive_id,original_event_id,actor_id,table_name,record_id,action,old_data,new_data,reason,original_created_at
  )
  select archive_id,a.id,a.actor_id,a.table_name,a.record_id,a.action,a.old_data,a.new_data,a.reason,a.created_at
  from public.audit_log a;
  truncate table public.audit_log restart identity;
  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details)
  values(auth.uid(),'ARCHIVE_AUDIT_LOG',changed,jsonb_build_object('archive_id',archive_id,'confirmation','ARCHIVE AUDIT LOG'));
  return jsonb_build_object('deleted',changed,'archived',changed,'archive_id',archive_id,'archived_at',now());
end
$function$

CREATE OR REPLACE FUNCTION public.resolve_assessment_scheme(target_class_id uuid, target_subject_id uuid, target_academic_year_id uuid, target_term_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select s.id from public.assessment_schemes s
  where s.active and s.deleted_at is null
    and (s.class_id is null or s.class_id=target_class_id)
    and (s.subject_id is null or s.subject_id=target_subject_id)
    and (s.academic_year_id is null or s.academic_year_id=target_academic_year_id)
    and (s.term_id is null or s.term_id=target_term_id)
  order by
    (s.term_id is not null)::int desc,
    (s.subject_id is not null)::int desc,
    (s.class_id is not null)::int desc,
    (s.academic_year_id is not null)::int desc,
    s.created_at desc
  limit 1
$function$

CREATE OR REPLACE FUNCTION public.resolve_grading_guide(target_academic_year_id uuid, target_class_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_year_scope uuid;
  v_class_scope uuid;
  v_subject_scope uuid;
  v_year_name text;
  v_class_name text;
  v_subject_name text;
  v_rows jsonb;
  v_exceptions jsonb;
  v_scope_label text;
begin
  if target_academic_year_id is null or target_class_id is null then
    raise exception 'Academic year and class are required to resolve the grading guide';
  end if;
  select q.academic_year_id,q.class_id
  into v_year_scope,v_class_scope
  from (
    select g.academic_year_id,g.class_id,max(g.updated_at) latest_update
    from public.grading_scales g
    where g.deleted_at is null
      and g.subject_id is null
      and (g.academic_year_id is null or g.academic_year_id=target_academic_year_id)
      and (g.class_id is null or g.class_id=target_class_id)
    group by g.academic_year_id,g.class_id
  ) q
  order by
    ((q.academic_year_id is not null)::integer+(q.class_id is not null)::integer) desc,
    (q.class_id is not null)::integer desc,
    (q.academic_year_id is not null)::integer desc,
    q.latest_update desc
  limit 1;
  if not found then
    select q.academic_year_id,q.class_id,q.subject_id
    into v_year_scope,v_class_scope,v_subject_scope
    from (
      select g.academic_year_id,g.class_id,g.subject_id,max(g.updated_at) latest_update
      from public.grading_scales g
      join public.class_subjects cs on cs.class_id=target_class_id and cs.subject_id=g.subject_id and cs.active
      where g.deleted_at is null
        and g.subject_id is not null
        and (g.academic_year_id is null or g.academic_year_id=target_academic_year_id)
        and (g.class_id is null or g.class_id=target_class_id)
      group by g.academic_year_id,g.class_id,g.subject_id
    ) q
    order by
      ((q.academic_year_id is not null)::integer+(q.class_id is not null)::integer) desc,
      (q.class_id is not null)::integer desc,
      (q.academic_year_id is not null)::integer desc,
      q.latest_update desc
    limit 1;
    if not found then
      raise exception 'No grading scale is configured for the selected academic year and class';
    end if;
  end if;
  select ay.name::text into v_year_name from public.academic_years ay where ay.id=target_academic_year_id;
  select c.name::text into v_class_name from public.classes c where c.id=target_class_id;
  select sb.name::text into v_subject_name from public.subjects sb where sb.id=v_subject_scope;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',g.id,
    'grade',g.grade,
    'min_mark',g.min_mark,
    'max_mark',g.max_mark,
    'remark',g.remark,
    'interpretation',coalesce(nullif(btrim(g.interpretation),''),public.default_grading_interpretation(g.grade,g.remark)),
    'grade_point',g.grade_point,
    'display_order',g.display_order
  ) order by g.display_order,g.min_mark desc,g.max_mark desc),'[]'::jsonb)
  into v_rows
  from public.grading_scales g
  where g.deleted_at is null
    and g.subject_id is not distinct from v_subject_scope
    and g.academic_year_id is not distinct from v_year_scope
    and g.class_id is not distinct from v_class_scope;
  if jsonb_array_length(v_rows)=0 then
    raise exception 'The selected grading guide contains no active ranges';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_id',q.subject_id,
    'subject_name',q.subject_name
  ) order by q.subject_name),'[]'::jsonb)
  into v_exceptions
  from (
    select distinct s.id subject_id,s.name::text subject_name
    from public.class_subjects cs
    join public.subjects s on s.id=cs.subject_id
    where cs.class_id=target_class_id
      and cs.active
      and s.active
      and s.deleted_at is null
      and exists(
        select 1 from public.grading_scales gx
        where gx.deleted_at is null
          and gx.subject_id=s.id
          and (gx.academic_year_id is null or gx.academic_year_id=target_academic_year_id)
          and (gx.class_id is null or gx.class_id=target_class_id)
      )
  ) q;
  v_scope_label:=concat_ws(' • ',
    case when v_class_scope is not null then coalesce(v_class_name,'Selected class') else 'All classes' end,
    case when v_year_scope is not null then coalesce(v_year_name,'Selected academic year') else 'All academic years' end,
    case when v_subject_scope is not null then concat('Representative subject: ',coalesce(v_subject_name,'Configured subject')) else null end
  );
  return jsonb_build_object(
    'version',1,
    'generated_at',now(),
    'scope',jsonb_build_object(
      'academic_year_id',v_year_scope,
      'class_id',v_class_scope,
      'academic_year_name',case when v_year_scope is not null then v_year_name else null end,
      'class_name',case when v_class_scope is not null then v_class_name else null end,
      'label',v_scope_label
    ),
    'rows',v_rows,
    'subject_exceptions',v_exceptions
  );
end $function$

CREATE OR REPLACE FUNCTION public.resolve_report_grading_guide(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.resolve_grading_guide(e.academic_year_id,e.class_id)
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id and r.deleted_at is null
$function$

CREATE OR REPLACE FUNCTION public.resolve_security_event(target_event_id bigint, target_status text, resolution_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.security_events;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if target_status not in ('acknowledged','resolved','false_positive') then raise exception 'Invalid resolution status'; end if;
  update public.security_events set status=target_status,acknowledged_by=auth.uid(),acknowledged_at=now(),resolution_note=left(coalesce(resolution_text,''),1000) where id=target_event_id returning * into row_data;
  if row_data.id is null then raise exception 'Security event not found'; end if;
  return to_jsonb(row_data);
end $function$

CREATE OR REPLACE FUNCTION public.restore_headteacher(target_headteacher_id uuid, reason_text text DEFAULT 'Principal restored'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.headteachers where id=target_headteacher_id and deleted_at is not null for update) then raise exception 'Archived Principal record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Principal restored'),true);
  update public.headteachers set active=true,employment_status='active',deleted_at=null,updated_at=now() where id=target_headteacher_id;
  update public.school_settings
  set head_name=(
    select concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)
    from public.headteachers h
    where h.id=target_headteacher_id
  ),
      updated_at=now()
  where id=(select id from public.school_settings order by created_at,id limit 1);
  return true;
exception when unique_violation then raise exception 'The Principal record cannot be restored because its staff number or linked account is already in use';
end $function$

CREATE OR REPLACE FUNCTION public.restore_report_card(target_report_id uuid, reason_text text DEFAULT 'Report card restored'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare previous_status public.report_status; target_enrollment_id uuid; target_term_id uuid;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  select archived_status,enrollment_id,term_id into previous_status,target_enrollment_id,target_term_id from public.student_reports
  where id=target_report_id and deleted_at is not null for update;
  if not found then raise exception 'Removed report card not found'; end if;
  perform pg_advisory_xact_lock(hashtext(target_enrollment_id::text),hashtext(target_term_id::text));
  if exists(
    select 1 from public.student_reports r
    where r.enrollment_id=target_enrollment_id and r.term_id=target_term_id
      and r.deleted_at is null and r.id<>target_report_id
  ) then
    raise exception 'A current report already exists for this student and term. Remove the current report before restoring this archived report.';
  end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Report card restored'),true);
  update public.student_reports set
    status=case when previous_status in ('published','withdrawn') then 'approved'::public.report_status
                else coalesce(previous_status,'draft'::public.report_status) end,
    archived_status=null,deleted_at=null,version=version+1,updated_at=now()
  where id=target_report_id;
  return true;
end $function$

CREATE OR REPLACE FUNCTION public.restore_student(target_student_id uuid, reason_text text DEFAULT 'Student restored'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare latest_enrollment uuid;
begin
  if not public.is_records_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  perform 1 from public.students where id=target_student_id and deleted_at is not null for update;
  if not found then raise exception 'Archived student record not found'; end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Student restored'),true);
  update public.students set status='active',deleted_at=null,updated_at=now() where id=target_student_id;
  select e.id into latest_enrollment from public.enrollments e join public.academic_years y on y.id=e.academic_year_id
  where e.student_id=target_student_id and e.deleted_at is null
  order by y.is_active desc,y.start_date desc nulls last,e.created_at desc limit 1;
  if latest_enrollment is not null then
    update public.enrollments set active=(id=latest_enrollment),updated_at=now()
    where student_id=target_student_id and deleted_at is null;
  end if;
  return true;
end $function$

CREATE OR REPLACE FUNCTION public.restore_teacher(target_teacher_id uuid, reason_text text DEFAULT 'Teacher restored'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.teachers where id=target_teacher_id and deleted_at is not null) then
    raise exception 'Archived teacher record not found';
  end if;
  perform set_config('app.change_reason',coalesce(nullif(reason_text,''),'Teacher restored'),true);
  update public.teachers set active=true,employment_status='active',deleted_at=null,updated_at=now()
  where id=target_teacher_id;
  return true;
end $function$

CREATE OR REPLACE FUNCTION public.review_certificate_batch(target_batch_id uuid, decision text, review_note_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificate_batches; new_status text;
begin
  if not public.can_review_certificates() then raise exception 'Only the Principal can review certificates' using errcode='42501'; end if;
  if lower(decision) not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  new_status:=lower(decision);
  update public.certificate_batches set status=new_status,approved_by=case when new_status='approved' then auth.uid() else null end,approved_at=case when new_status='approved' then now() else null end,review_note=btrim(coalesce(review_note_text,'')),updated_at=now() where id=target_batch_id and status='submitted' returning * into updated;
  if updated.id is null then raise exception 'Only a submitted batch can be reviewed'; end if;
  update public.certificates set status=case when new_status='approved' then 'approved' else 'rejected' end,approved_by=case when new_status='approved' then auth.uid() else null end,approved_at=case when new_status='approved' then now() else null end,updated_at=now() where batch_id=target_batch_id and status='draft';
  perform public.record_certificate_event(target_batch_id,null,'principal_'||new_status,review_note_text);
  perform public.create_notification(updated.prepared_by,'Certificate batch '||new_status,updated.title||' was '||new_status||' by the Principal.','certificate_review','certificate_batch',target_batch_id,false);
  return jsonb_build_object('batch_id',updated.id,'status',updated.status);
end $function$

CREATE OR REPLACE FUNCTION public.review_report_correction(target_request_id uuid, decision text, review_note_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare req public.report_correction_requests; current_status public.report_status; new_version integer; revisionid uuid; requester uuid;
begin
  if public.current_app_role()<>'principal' then raise exception 'Only the Principal can approve or reject report corrections' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if lower(decision) not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  select * into req from public.report_correction_requests where id=target_request_id for update;
  if req.id is null or req.status<>'pending' then raise exception 'Pending correction request not found'; end if;
  if lower(decision)='rejected' then
    update public.report_correction_requests set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=left(coalesce(review_note_text,''),1000),updated_at=now() where id=req.id returning * into req;
    insert into public.report_correction_events(request_id,event_type,event_note) values(req.id,'rejected',req.review_note);
  else
    select status into current_status from public.student_reports where id=req.report_id and deleted_at is null for update;
    if current_status not in ('approved','published') then raise exception 'The report is no longer eligible for correction'; end if;
    perform set_config('app.report_write','on',true);
    perform set_config('app.change_reason','Approved report correction: '||req.reason,true);
    update public.report_publications set revoked_at=now(),revoked_by=auth.uid() where report_id=req.report_id and revoked_at is null;
    update public.student_reports set status='returned',version=version+1,updated_at=now() where id=req.report_id returning version into new_version;
    insert into public.report_workflow_events(report_id,from_status,to_status,comment,actor_id)
    values(req.report_id,current_status,'returned','Correction approved: '||req.reason,auth.uid());
    insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
    values(req.report_id,new_version,public.build_report_snapshot(req.report_id),'Correction approved: '||req.reason,auth.uid())
    on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now()
    returning id into revisionid;
    update public.report_correction_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_note=left(coalesce(review_note_text,''),1000),correction_revision_id=revisionid,updated_at=now() where id=req.id returning * into req;
    insert into public.report_correction_events(request_id,event_type,event_note,event_data)
    values(req.id,'approved',req.review_note,jsonb_build_object('returned_report_version',new_version,'revision_id',revisionid));
    perform public.create_workflow_notifications(req.report_id,'returned');
  end if;
  requester:=req.requested_by;
  if requester is not null and requester<>auth.uid() then
    perform public.create_notification(requester,'Report correction '||req.status,coalesce(nullif(req.review_note,''),req.reason),'report_correction','report',req.report_id,true);
  end if;
  return to_jsonb(req);
end $function$

CREATE OR REPLACE FUNCTION public.revoke_certificate(target_certificate_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificates;
begin
  if not public.license_write_allowed() or not public.has_role(array['system_admin','principal']) then raise exception 'Only the System Administrator or Principal can revoke a certificate' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<5 then raise exception 'A revocation reason of at least five characters is required'; end if;
  update public.certificates set status='revoked',revocation_reason=btrim(reason_text),revoked_by=auth.uid(),revoked_at=now(),updated_at=now() where id=target_certificate_id and status='issued' returning * into updated;
  if updated.id is null then raise exception 'Only an issued certificate can be revoked'; end if;
  perform public.record_certificate_event(updated.batch_id,updated.id,'revoked',reason_text);
  return jsonb_build_object('certificate_id',updated.id,'status',updated.status);
end $function$

CREATE OR REPLACE FUNCTION public.revoke_emergency_academic_delegation(target_delegation_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare currentrow public.emergency_academic_delegations%rowtype;reason_value text:=btrim(coalesce(reason_text,''));
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can revoke an emergency delegation' using errcode='42501'; end if;
  if not public.license_write_allowed() then raise exception 'The current licence does not permit this change' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if length(reason_value)<5 then raise exception 'A revocation reason of at least 5 characters is required' using errcode='22023'; end if;
  select * into currentrow from public.emergency_academic_delegations where id=target_delegation_id and status='active' for update;
  if currentrow.id is null then raise exception 'Active delegation not found' using errcode='P0002'; end if;
  update public.emergency_academic_delegations
  set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revocation_reason=reason_value
  where id=target_delegation_id returning * into currentrow;
  insert into public.emergency_academic_delegation_events(delegation_id,event_type,actor_id,event_reason,event_data)
  values(currentrow.id,'revoked',auth.uid(),reason_value,to_jsonb(currentrow));
  perform public.create_notification(currentrow.delegate_user_id,'Temporary academic access revoked',
    'Your emergency academic delegation has been revoked. Reason: '||reason_value,
    'emergency_academic_delegation','emergency_academic_delegation',currentrow.id,true);
  return public.get_emergency_delegation_console();
end $function$

CREATE OR REPLACE FUNCTION public.revoke_staff_id_card(target_card_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare c public.staff_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,''));sid uuid;
begin if not public.is_system_admin() then raise exception 'Only the System Administrator can revoke staff ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('staff_id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A revocation reason of at least five characters is required';end if;update public.staff_id_cards set status='revoked',revoked_by=auth.uid(),revoked_at=now(),revocation_reason=reason,updated_at=now() where id=target_card_id and status='active' returning * into c;if c.id is null then raise exception 'Only an active staff ID card can be revoked';end if;sid:=coalesce(c.teacher_id,c.headteacher_id);perform public.record_staff_id_card_event(c.id,c.staff_type,sid,'revoked',jsonb_build_object('reason',reason));return jsonb_build_object('card_id',c.id,'status','revoked','card_number',c.card_number);end$function$

CREATE OR REPLACE FUNCTION public.revoke_student_id_card(target_card_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare updated public.student_id_cards%rowtype;reason text:=btrim(coalesce(reason_text,'')); begin if not public.is_system_admin() then raise exception 'Only the System Administrator can revoke student ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if length(reason)<5 then raise exception 'A revocation reason of at least five characters is required';end if;update public.student_id_cards set status='revoked',revoked_by=auth.uid(),revoked_at=now(),revocation_reason=reason,updated_at=now() where id=target_card_id and status='active' returning * into updated;if updated.id is null then raise exception 'Only an active ID card can be revoked';end if;perform public.record_id_card_event(updated.id,updated.student_id,'revoked',jsonb_build_object('reason',reason));return jsonb_build_object('card_id',updated.id,'status','revoked','card_number',updated.card_number);end$function$

CREATE OR REPLACE FUNCTION public.revoke_student_transcript(target_issuance_id uuid, reason_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare issued public.transcript_issuances;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<5 then raise exception 'Revocation reason is required'; end if;
  update public.transcript_issuances set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revocation_reason=left(btrim(reason_text),500)
  where id=target_issuance_id and status<>'revoked' returning * into issued;
  if issued.id is null then raise exception 'Active transcript issuance not found'; end if;
  return to_jsonb(issued)-'snapshot';
end $function$

CREATE OR REPLACE FUNCTION public.run_academic_alerts(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=target_term_id; control jsonb; queued integer:=0; recipient uuid; rowitem record; title_text text; body_text text;
begin
  if auth.uid() is not null and public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if tid is null then select id into tid from public.terms where is_active and deleted_at is null limit 1; end if;
  control:=public.term_control_snapshot(tid);
  for rowitem in
    select c.id class_id,c.name class_name,c.class_teacher_id,
      count(e.id) enrolled,count(r.id) filter(where r.id is not null) reports_created,
      count(r.id) filter(where r.status in ('draft','returned')) draft_count,
      count(r.id) filter(where r.status in ('submitted','class_reviewed')) pending_approval,
      count(r.id) filter(where r.status='approved') approved_count
    from public.classes c
    left join public.enrollments e on e.class_id=c.id and e.active and e.deleted_at is null and e.academic_year_id=(select academic_year_id from public.terms where id=tid)
    left join public.student_reports r on r.enrollment_id=e.id and r.term_id=tid and r.deleted_at is null
    where c.active and c.deleted_at is null group by c.id,c.name,c.class_teacher_id
  loop
    if rowitem.class_teacher_id is not null and (rowitem.reports_created<rowitem.enrolled or rowitem.draft_count>0) then
      title_text:='Incomplete reports: '||rowitem.class_name;
      body_text:=format('%s of %s reports created; %s remain in draft or correction.',rowitem.reports_created,rowitem.enrolled,rowitem.draft_count);
      if not exists(select 1 from public.notifications where recipient_id=rowitem.class_teacher_id and title=title_text and created_at>=now()-interval '20 hours') then
        perform public.create_notification(rowitem.class_teacher_id,title_text,body_text,'academic_deadline','term',tid,true); queued:=queued+1;
      end if;
    end if;
    if rowitem.pending_approval>0 then
      for recipient in select p.id from public.profiles p where p.active and public.current_app_role_for(p.role)::text='principal' loop
        title_text:='Reports awaiting approval: '||rowitem.class_name;
        body_text:=rowitem.pending_approval||' report(s) are awaiting Principal approval.';
        if not exists(select 1 from public.notifications where recipient_id=recipient and title=title_text and created_at>=now()-interval '20 hours') then
          perform public.create_notification(recipient,title_text,body_text,'academic_deadline','term',tid,true); queued:=queued+1;
        end if;
      end loop;
    end if;
    if rowitem.approved_count>0 and rowitem.class_teacher_id is not null then
      title_text:='Approved reports awaiting publication: '||rowitem.class_name;
      body_text:=rowitem.approved_count||' approved report(s) are ready for publication.';
      if not exists(select 1 from public.notifications where recipient_id=rowitem.class_teacher_id and title=title_text and created_at>=now()-interval '20 hours') then
        perform public.create_notification(rowitem.class_teacher_id,title_text,body_text,'academic_deadline','term',tid,true); queued:=queued+1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('queued',queued,'term_id',tid,'control',control);
end $function$

CREATE OR REPLACE FUNCTION public.saas_active_tenant_release()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case when r.release_code is null then null else jsonb_build_object(
    'release_code', r.release_code,
    'baseline_blueprint_version', r.baseline_blueprint_version,
    'manifest_sha256', r.manifest_sha256,
    'migration_count', r.migration_count,
    'edge_function_count', r.edge_function_count,
    'activated_at', r.activated_at
  ) end
  from (select * from public.saas_tenant_releases where status='active' order by activated_at desc nulls last limit 1) r;
$function$

CREATE OR REPLACE FUNCTION public.saas_apply_initial_license_period()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r record;
begin
  if tg_op='INSERT' and new.registration_id is not null then
    select initial_license_period_type,initial_license_period_label,
           initial_license_starts_at,initial_license_expires_at,initial_license_grace_days
    into r
    from public.school_registrations
    where id=new.registration_id;
    if r.initial_license_expires_at is not null then
      new.license_period_type=r.initial_license_period_type;
      new.license_period_label=r.initial_license_period_label;
      new.license_started_at=r.initial_license_starts_at;
      new.license_expires_at=r.initial_license_expires_at;
      new.license_grace_days=coalesce(r.initial_license_grace_days,14);
      new.license_grace_ends_at=r.initial_license_expires_at+make_interval(days=>coalesce(r.initial_license_grace_days,14));
      new.license_period_locked=true;
    end if;
  elsif tg_op='UPDATE'
        and old.status='provisioning'
        and new.status='active'
        and old.license_period_locked then
    new.license_period_type=old.license_period_type;
    new.license_period_label=old.license_period_label;
    new.license_started_at=old.license_started_at;
    new.license_expires_at=old.license_expires_at;
    new.license_grace_days=old.license_grace_days;
    new.license_grace_ends_at=old.license_grace_ends_at;
    new.license_period_locked=false;
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_claim_plan_upgrade(target_tenant_id uuid, target_code_hash text, target_actor_id uuid, expected_project_ref text, expected_current_plan text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  t public.saas_tenants%rowtype;
  c public.saas_plan_upgrade_codes%rowtype;
  p public.saas_plans%rowtype;
  current_sort integer;
  result jsonb;
begin
  if auth.role()<>'service_role' then
    raise exception 'Service-role authorization required' using errcode='42501';
  end if;
  if target_actor_id is null or target_code_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid licence authorization claim' using errcode='22023';
  end if;

  select * into t from public.saas_tenants where id=target_tenant_id for update;
  if t.id is null
     or t.status not in ('active','suspended')
     or t.license_status not in ('active','grace_period','expired','suspended') then
    raise exception 'Tenant workspace is not eligible for licence activation' using errcode='42501';
  end if;

  select * into c
  from public.saas_plan_upgrade_codes
  where tenant_id=t.id and code_hash=target_code_hash
  for update;
  if c.id is null then
    raise exception 'Activation code is invalid' using errcode='42501';
  end if;
  if lower(t.project_ref)<>lower(btrim(expected_project_ref)) then
    raise exception 'Tenant project binding changed; request a new code' using errcode='40001';
  end if;
  if c.status='issued' and c.expires_at<=now() then
    update public.saas_plan_upgrade_codes set status='expired',updated_at=now() where id=c.id;
    raise exception 'Activation code has expired' using errcode='42501';
  end if;
  if c.status in ('revoked','expired') then
    raise exception 'Activation code is no longer valid' using errcode='42501';
  end if;

  select * into p from public.saas_plans where code=c.to_plan_code and active;
  select sort_order into current_sort from public.saas_plans where code=t.plan_code;
  if p.code is null then
    raise exception 'Authorized plan is unavailable' using errcode='22023';
  end if;
  if c.authorization_type='renewal' then
    if lower(c.to_plan_code::text)<>lower(t.plan_code::text) then
      raise exception 'Renewal code does not match the current plan' using errcode='22023';
    end if;
  elsif coalesce(p.sort_order,0)<=coalesce(current_sort,0)
        and c.status not in ('redeemed_pending_activation','activated') then
    raise exception 'Activation code does not authorize a valid plan change' using errcode='22023';
  end if;

  result=jsonb_build_object(
    'authorization_id',c.id,
    'authorization_type',c.authorization_type,
    'from_plan_code',c.from_plan_code,
    'to_plan_code',c.to_plan_code,
    'target_plan',to_jsonb(p),
    'code_expires_at',c.expires_at,
    'license_period_type',c.license_period_type,
    'license_period_label',c.license_period_label,
    'license_starts_at',c.license_starts_at,
    'license_expires_at',c.license_expires_at,
    'license_grace_days',c.license_grace_days,
    'reason',c.reason
  );

  if c.status='activated' then
    if lower(t.plan_code::text)<>lower(c.to_plan_code::text) then
      raise exception 'Activated authorization does not match the tenant plan' using errcode='40001';
    end if;
    return result||jsonb_build_object('already_activated',true);
  end if;
  if c.status='redeemed_pending_activation'
     and c.redeemed_by_tenant_user=target_actor_id
     and lower(btrim(expected_current_plan)) in (lower(c.from_plan_code::text),lower(c.to_plan_code::text)) then
    return result||jsonb_build_object('local_activation_pending_finalization',true);
  end if;
  if lower(t.plan_code::text)<>lower(btrim(expected_current_plan))
     or lower(c.from_plan_code::text)<>lower(t.plan_code::text) then
    raise exception 'Tenant plan changed after this code was issued; request a new code' using errcode='40001';
  end if;
  if c.status='redeemed_pending_activation' and c.redeemed_by_tenant_user<>target_actor_id then
    raise exception 'Activation code has already been claimed' using errcode='42501';
  end if;
  if c.status='issued' then
    update public.saas_plan_upgrade_codes
    set status='redeemed_pending_activation',
        redeemed_at=now(),
        redeemed_by_tenant_user=target_actor_id,
        updated_at=now()
    where id=c.id and status='issued';
  end if;
  return result;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_enforce_starter_registration()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  new.requested_plan_code := 'starter';
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_finalize_plan_upgrade(target_tenant_id uuid, target_authorization_id uuid, target_actor_id uuid, expected_project_ref text, activated_plan_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  t public.saas_tenants%rowtype;
  c public.saas_plan_upgrade_codes%rowtype;
  new_start timestamptz;
  new_expiry timestamptz;
  new_grace_days integer;
  new_grace_end timestamptz;
  new_period_type text;
  new_period_label text;
  event_name text;
begin
  if auth.role()<>'service_role' then
    raise exception 'Service-role authorization required' using errcode='42501';
  end if;
  select * into t from public.saas_tenants where id=target_tenant_id for update;
  select * into c from public.saas_plan_upgrade_codes
    where id=target_authorization_id and tenant_id=target_tenant_id for update;
  if t.id is null or c.id is null then
    raise exception 'Licence finalization record not found' using errcode='P0002';
  end if;
  if lower(t.project_ref)<>lower(btrim(expected_project_ref))
     or lower(c.to_plan_code::text)<>lower(btrim(activated_plan_code)) then
    raise exception 'Licence finalization binding mismatch' using errcode='42501';
  end if;
  if c.status='activated' then
    return jsonb_build_object(
      'authorization_id',c.id,'activated',true,'already_activated',true,
      'plan_code',t.plan_code,'license_started_at',t.license_started_at,
      'license_expires_at',t.license_expires_at,'license_grace_ends_at',t.license_grace_ends_at
    );
  end if;
  if c.status<>'redeemed_pending_activation' or c.redeemed_by_tenant_user<>target_actor_id then
    raise exception 'Licence authorization is not awaiting this activation' using errcode='42501';
  end if;

  new_start=coalesce(c.license_starts_at,t.license_started_at,now());
  new_expiry=coalesce(c.license_expires_at,t.license_expires_at);
  new_grace_days=coalesce(c.license_grace_days,t.license_grace_days,30);
  new_grace_end=case when new_expiry is null then null else new_expiry+make_interval(days=>new_grace_days) end;
  new_period_type=case when c.license_period_type='preserve' then t.license_period_type else c.license_period_type end;
  new_period_label=case when c.license_period_type='preserve' then t.license_period_label else c.license_period_label end;
  event_name=case when c.authorization_type='renewal' then 'license_renewal_activated' else 'plan_upgrade_activated' end;

  update public.saas_tenants
  set plan_code=c.to_plan_code,
      license_status='active',
      license_started_at=new_start,
      license_expires_at=new_expiry,
      license_period_type=new_period_type,
      license_period_label=new_period_label,
      license_grace_days=new_grace_days,
      license_grace_ends_at=new_grace_end,
      license_last_renewed_at=case when c.authorization_type='renewal' then now() else license_last_renewed_at end,
      updated_at=now()
  where id=t.id;

  update public.saas_plan_upgrade_codes
  set status='activated',activated_at=now(),updated_at=now()
  where id=c.id;

  insert into public.saas_tenant_events(tenant_id,registration_id,event_type,actor_id,details)
  values(t.id,t.registration_id,event_name,null,jsonb_build_object(
    'authorization_id',c.id,
    'tenant_user_id',target_actor_id,
    'authorization_type',c.authorization_type,
    'from_plan_code',c.from_plan_code,
    'to_plan_code',c.to_plan_code,
    'license_period_type',new_period_type,
    'license_period_label',new_period_label,
    'license_starts_at',new_start,
    'license_expires_at',new_expiry,
    'license_grace_ends_at',new_grace_end
  ));

  return jsonb_build_object(
    'authorization_id',c.id,'activated',true,'authorization_type',c.authorization_type,
    'plan_code',c.to_plan_code,'activated_at',now(),'license_period_type',new_period_type,
    'license_period_label',new_period_label,'license_started_at',new_start,
    'license_expires_at',new_expiry,'license_grace_ends_at',new_grace_end
  );
end
$function$

CREATE OR REPLACE FUNCTION public.saas_finalize_school_deletion(target_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  job public.saas_school_deletion_jobs%rowtype;
  deleted_registration uuid;
  deleted_tenant uuid;
begin
  select * into job
  from public.saas_school_deletion_jobs
  where id=target_job_id
  for update;
  if not found then
    raise exception 'Deletion job not found';
  end if;
  if job.status='completed' then
    return jsonb_build_object('completed',true,'already_completed',true);
  end if;

  deleted_registration:=job.registration_id;
  deleted_tenant:=job.tenant_id;

  delete from public.saas_tenant_events
  where (deleted_tenant is not null and tenant_id=deleted_tenant)
     or (deleted_registration is not null and registration_id=deleted_registration);

  if deleted_registration is not null then
    update public.school_registrations
    set tenant_id=null
    where id=deleted_registration;
  end if;

  if deleted_tenant is not null then
    delete from public.saas_tenants where id=deleted_tenant;
  end if;
  if deleted_registration is not null then
    delete from public.school_registrations where id=deleted_registration;
  end if;

  update public.saas_school_deletion_jobs
  set status='completed',
      stage='completed',
      registration_id=null,
      tenant_id=null,
      tenant_code=null,
      project_ref='',
      reason='',
      metadata=jsonb_build_object(
        'operational_records_removed',true,
        'completed_by',job.actor_id
      ),
      last_error='',
      completed_at=now(),
      updated_at=now()
  where id=target_job_id;

  return jsonb_build_object(
    'completed',true,
    'registration_removed',deleted_registration is not null,
    'tenant_removed',deleted_tenant is not null
  );
end
$function$

CREATE OR REPLACE FUNCTION public.saas_guard_tenant_release_child()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  release_code_value text;
  release_status text;
begin
  release_code_value:=case when tg_op='DELETE' then old.release_code else new.release_code end;
  select status into release_status from public.saas_tenant_releases where release_code=release_code_value;
  if release_status in ('active','retired') then
    raise exception 'Migration and Edge Function sources for activated tenant releases are immutable' using errcode='55000';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_guard_tenant_release_definition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if tg_op='DELETE' then
    if old.status in ('active','retired') then
      raise exception 'Activated tenant releases cannot be deleted' using errcode='55000';
    end if;
    return old;
  end if;

  if old.status in ('active','retired') then
    if new.release_code is distinct from old.release_code
       or new.baseline_blueprint_version is distinct from old.baseline_blueprint_version
       or new.manifest_sha256 is distinct from old.manifest_sha256
       or new.migration_count is distinct from old.migration_count
       or new.edge_function_count is distinct from old.edge_function_count
       or new.source_schema_version is distinct from old.source_schema_version
       or new.source_reference is distinct from old.source_reference
       or new.metadata is distinct from old.metadata
       or new.notes is distinct from old.notes
       or new.capture_nonce is distinct from old.capture_nonce
       or new.created_at is distinct from old.created_at
       or new.activated_at is distinct from old.activated_at then
      raise exception 'Activated tenant release definitions are immutable' using errcode='55000';
    end if;
    if old.status='retired' and new.status<>'retired' then
      raise exception 'Retired tenant releases cannot be reactivated' using errcode='55000';
    end if;
    if old.status='active' and new.status not in ('active','retired') then
      raise exception 'An active tenant release may only remain active or become retired' using errcode='55000';
    end if;
  end if;
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_login_domain_for_code(input_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select lower(regexp_replace(coalesce(input_code,''),'[^a-zA-Z0-9]','','g')) || '.app'
$function$

CREATE OR REPLACE FUNCTION public.saas_next_tenant_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  raise exception 'A registered school name is required to allocate a tenant code'
    using errcode = '22023';
end
$function$

CREATE OR REPLACE FUNCTION public.saas_next_tenant_code(input_school_name text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  prefix text;
  sequence_number bigint;
begin
  prefix := public.saas_school_prefix(input_school_name);
  sequence_number := nextval('public.saas_tenant_code_seq');
  return prefix || '-' || lpad(sequence_number::text, 6, '0');
end
$function$

CREATE OR REPLACE FUNCTION public.saas_pin_provisioning_job_release()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  release_info jsonb;
begin
  release_info:=public.saas_tenant_release_preflight();
  new.blueprint_version:=release_info->>'foundation_version';
  new.idempotency_key:='tenant:'||new.tenant_id::text||':'||(release_info->>'release_code');
  new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object(
    'release_code',release_info->>'release_code',
    'release_manifest_sha256',release_info->>'manifest_sha256',
    'foundation_version',release_info->>'foundation_version',
    'release_migration_count',(release_info->>'migration_count')::integer,
    'release_edge_function_count',(release_info->>'edge_function_count')::integer
  );
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_prepare_tenant_provisioning_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.school_registrations%rowtype;
  release_info jsonb;
  grace_days integer;
begin
  if new.registration_id is null or coalesce(new.status,'')<>'provisioning' then
    return new;
  end if;

  select * into strict r from public.school_registrations where id=new.registration_id;
  if r.initial_license_configured_at is null
     or r.initial_license_starts_at is null
     or r.initial_license_expires_at is null
     or nullif(btrim(r.initial_license_period_type),'') is null
     or nullif(btrim(r.initial_license_period_label),'') is null then
    raise exception 'Initial licence period must be configured before tenant approval' using errcode='55000';
  end if;
  if r.initial_license_expires_at<=r.initial_license_starts_at then
    raise exception 'Initial licence expiry must be after its start date' using errcode='22023';
  end if;
  if r.initial_license_expires_at<=now() then
    raise exception 'Initial licence expiry must be in the future' using errcode='22023';
  end if;

  release_info:=public.saas_tenant_release_preflight();
  grace_days:=greatest(0,least(90,coalesce(r.initial_license_grace_days,0)));

  new.institution_type:=coalesce(nullif(btrim(r.institution_type),''),'basic_jhs');
  new.license_started_at:=r.initial_license_starts_at;
  new.license_expires_at:=r.initial_license_expires_at;
  new.license_period_type:=r.initial_license_period_type;
  new.license_period_label:=r.initial_license_period_label;
  new.license_grace_days:=grace_days;
  new.license_grace_ends_at:=r.initial_license_expires_at+make_interval(days=>grace_days);
  new.license_period_locked:=false;
  new.runtime_version:=coalesce(nullif(new.runtime_version,''),release_info->>'release_code');
  new.release_status:='queued';
  return new;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_refresh_draft_tenant_release(target_release_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  r public.saas_tenant_releases%rowtype;
  mc integer;
  fc integer;
  mh text;
begin
  select * into strict r from public.saas_tenant_releases where release_code=target_release_code for update;
  if r.status<>'draft' then
    raise exception 'Only draft tenant releases may be refreshed' using errcode='55000';
  end if;
  select count(*) into mc from public.saas_tenant_release_migrations where release_code=target_release_code;
  select count(*) into fc from public.saas_tenant_release_edge_functions where release_code=target_release_code;
  mh:=public.saas_tenant_release_manifest_sha256(target_release_code);
  update public.saas_tenant_releases
     set migration_count=mc,edge_function_count=fc,manifest_sha256=mh
   where release_code=target_release_code;
  return jsonb_build_object('release_code',target_release_code,'migration_count',mc,'edge_function_count',fc,'manifest_sha256',mh);
end
$function$

CREATE OR REPLACE FUNCTION public.saas_school_prefix(input_school_name text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleaned text := upper(btrim(regexp_replace(coalesce(input_school_name, ''), '[^A-Za-z]+', ' ', 'g')));
  words text[];
  result text;
begin
  if cleaned = '' then
    raise exception 'A school name is required to generate its tenant identity'
      using errcode = '22023';
  end if;

  words := regexp_split_to_array(cleaned, E'\\s+');

  if cardinality(words) >= 3 then
    result := left(words[1], 1) || left(words[2], 1) || left(words[3], 1);
  elsif cardinality(words) = 2 then
    result := left(words[1], 2) || left(words[2], 1);
  else
    result := left(words[1], 3);
  end if;

  result := left(result || 'XXX', 3);
  if result !~ '^[A-Z]{3}$' then
    raise exception 'The school name cannot produce a valid three-letter prefix'
      using errcode = '22023';
  end if;
  return result;
end
$function$

CREATE OR REPLACE FUNCTION public.saas_slugify(input_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select trim(both '-' from regexp_replace(lower(coalesce(input_text,'')),'[^a-z0-9]+','-','g'))
$function$

CREATE OR REPLACE FUNCTION public.saas_tenant_release_manifest_sha256(target_release_code text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  r public.saas_tenant_releases%rowtype;
  migration_manifest text;
  function_manifest text;
begin
  select * into strict r from public.saas_tenant_releases where release_code=target_release_code;
  select coalesce(string_agg(ordinal::text||'|'||migration_version||'|'||migration_name||'|'||sha256,E'\n' order by ordinal),'')
    into migration_manifest
  from public.saas_tenant_release_migrations where release_code=target_release_code;
  select coalesce(string_agg(ordinal::text||'|'||function_slug||'|'||verify_jwt::text||'|'||entrypoint_path||'|'||sha256,E'\n' order by ordinal),'')
    into function_manifest
  from public.saas_tenant_release_edge_functions where release_code=target_release_code;
  return encode(extensions.digest(convert_to(
    'release='||r.release_code||E'\n'||
    'foundation='||r.baseline_blueprint_version||E'\n'||
    'source_schema_version='||r.source_schema_version::text||E'\n'||
    'migrations='||migration_manifest||E'\n'||
    'functions='||function_manifest,
    'UTF8'),'sha256'),'hex');
end
$function$

CREATE OR REPLACE FUNCTION public.saas_tenant_release_preflight()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  active_code text;
  release_count integer;
begin
  select count(*),min(release_code) into release_count,active_code from public.saas_tenant_releases where status='active';
  if release_count<>1 then
    raise exception 'Exactly one active tenant release is required; found %',release_count using errcode='55000';
  end if;
  return public.saas_tenant_release_preflight_for(active_code);
end
$function$

CREATE OR REPLACE FUNCTION public.saas_tenant_release_preflight_for(target_release_code text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.saas_validate_tenant_release(target_release_code,false)
$function$

CREATE OR REPLACE FUNCTION public.saas_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin new.updated_at=now(); return new; end $function$

CREATE OR REPLACE FUNCTION public.saas_validate_tenant_release(target_release_code text, allow_draft boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  r public.saas_tenant_releases%rowtype;
  stored_migrations integer;
  stored_functions integer;
  bad_migration_hashes integer;
  bad_function_hashes integer;
  empty_migration_sources integer;
  empty_function_sources integer;
  min_migration_ordinal integer;
  max_migration_ordinal integer;
  min_function_ordinal integer;
  max_function_ordinal integer;
  computed_manifest text;
begin
  select * into strict r from public.saas_tenant_releases where release_code=target_release_code;
  if r.status='draft' and not allow_draft then
    raise exception 'Tenant release % is not activated',target_release_code using errcode='55000';
  end if;
  if r.status not in ('draft','active','retired') then
    raise exception 'Tenant release % has unsupported status %',target_release_code,r.status using errcode='55000';
  end if;
  if r.baseline_blueprint_version<>'7.4.0-r39' then
    raise exception 'Unsupported tenant foundation version %',r.baseline_blueprint_version using errcode='55000';
  end if;
  if r.source_schema_version<>1 then
    raise exception 'Unsupported tenant release source schema version %',r.source_schema_version using errcode='55000';
  end if;

  select count(*),
         count(*) filter(where nullif(btrim(sql_text),'') is null),
         count(*) filter(where sha256<>encode(extensions.digest(convert_to(sql_text,'UTF8'),'sha256'),'hex')),
         min(ordinal),max(ordinal)
    into stored_migrations,empty_migration_sources,bad_migration_hashes,min_migration_ordinal,max_migration_ordinal
  from public.saas_tenant_release_migrations where release_code=r.release_code;

  select count(*),
         count(*) filter(where nullif(btrim(source_text),'') is null),
         count(*) filter(where sha256<>encode(extensions.digest(convert_to(source_text,'UTF8'),'sha256'),'hex')),
         min(ordinal),max(ordinal)
    into stored_functions,empty_function_sources,bad_function_hashes,min_function_ordinal,max_function_ordinal
  from public.saas_tenant_release_edge_functions where release_code=r.release_code;

  if stored_migrations<=0 or stored_functions<=0 then
    raise exception 'Tenant release % must contain migration and function sources',r.release_code using errcode='55000';
  end if;
  if stored_migrations<>r.migration_count or stored_functions<>r.edge_function_count then
    raise exception 'Tenant release inventory count mismatch for %: migrations %/% functions %/%',r.release_code,stored_migrations,r.migration_count,stored_functions,r.edge_function_count using errcode='55000';
  end if;
  if min_migration_ordinal<>1 or max_migration_ordinal<>stored_migrations or min_function_ordinal<>1 or max_function_ordinal<>stored_functions then
    raise exception 'Tenant release % contains non-contiguous inventory ordinals',r.release_code using errcode='55000';
  end if;
  if empty_migration_sources<>0 or empty_function_sources<>0 then
    raise exception 'Tenant release % contains empty source payloads',r.release_code using errcode='55000';
  end if;
  if bad_migration_hashes<>0 or bad_function_hashes<>0 then
    raise exception 'Tenant release % failed SHA-256 source verification',r.release_code using errcode='55000';
  end if;
  computed_manifest:=public.saas_tenant_release_manifest_sha256(r.release_code);
  if r.manifest_sha256 is distinct from computed_manifest then
    raise exception 'Tenant release % manifest mismatch',r.release_code using errcode='55000';
  end if;

  return jsonb_build_object(
    'ready',true,
    'release_code',r.release_code,
    'status',r.status,
    'foundation_version',r.baseline_blueprint_version,
    'migration_count',stored_migrations,
    'edge_function_count',stored_functions,
    'manifest_sha256',computed_manifest,
    'source_schema_version',r.source_schema_version,
    'source_reference',r.source_reference,
    'metadata',r.metadata
  );
end
$function$

CREATE OR REPLACE FUNCTION public.safe_boolean(value text, default_value boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if value is null or btrim(value)='' then return default_value; end if;
  if lower(btrim(value)) in ('true','t','1','yes','y','on') then return true; end if;
  if lower(btrim(value)) in ('false','f','0','no','n','off') then return false; end if;
  return default_value;
end $function$

CREATE OR REPLACE FUNCTION public.safe_date(value text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if value is null or btrim(value)='' then return null; end if;
  return btrim(value)::date;
exception when invalid_datetime_format or datetime_field_overflow then
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.safe_integer(value text)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if value is null or btrim(value)='' then return null; end if;
  return btrim(value)::integer;
exception when invalid_text_representation or numeric_value_out_of_range then
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.safe_numeric(value text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if value is null or btrim(value)='' then return null; end if;
  return btrim(value)::numeric;
exception when invalid_text_representation or numeric_value_out_of_range then
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.safe_timestamptz(value text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if value is null or btrim(value)='' then return null; end if;
  return btrim(value)::timestamptz;
exception when invalid_datetime_format or datetime_field_overflow then
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.safe_uuid(value text)
 RETURNS uuid
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  if value is null or btrim(value) = '' then return null; end if;
  return btrim(value)::uuid;
exception when invalid_text_representation then
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.save_academic_entity(entity_type text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(payload->>'id');
  affected integer;
  startdate date:=public.safe_date(payload->>'start_date');
  enddate date:=public.safe_date(payload->>'end_date');
  nextdate date:=public.safe_date(payload->>'next_term_begins');
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id');
  teacherid uuid:=public.safe_uuid(payload->>'class_teacher_id');
  teacherrecordid uuid:=public.safe_uuid(payload->>'class_teacher_record_id');
  seq integer:=public.safe_integer(payload->>'sequence');
  orderno integer;
  subjectcode text;
  existingcode text;
  recordname text:=regexp_replace(btrim(coalesce(payload->>'name','')),'[[:space:]]+',' ','g');
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Academic record identifier is invalid'; end if;
  if btrim(coalesce(payload->>'start_date',''))<>'' and startdate is null then raise exception 'Start date is invalid'; end if;
  if btrim(coalesce(payload->>'end_date',''))<>'' and enddate is null then raise exception 'End date is invalid'; end if;
  if btrim(coalesce(payload->>'next_term_begins',''))<>'' and nextdate is null then raise exception 'Next term date is invalid'; end if;
  if btrim(coalesce(payload->>'academic_year_id',''))<>'' and yearid is null then raise exception 'Academic year identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_teacher_id',''))<>'' and teacherid is null then raise exception 'Class teacher account identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_teacher_record_id',''))<>'' and teacherrecordid is null then raise exception 'Class teacher record identifier is invalid'; end if;
  if startdate is not null and enddate is not null and startdate>enddate then raise exception 'Start date cannot be after end date'; end if;
  if nextdate is not null and enddate is not null and nextdate<enddate then raise exception 'Next term date cannot be before the term end date'; end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Academic record update'),true);
  if entity_type='academic_years' then
    if recordname='' then raise exception 'Academic year name is required'; end if;
    if targetid is null then
      select y.id into targetid
      from public.academic_years y
      where lower(y.name::text)=lower(recordname) and y.deleted_at is not null
      order by y.updated_at desc,y.created_at desc limit 1 for update;
      if targetid is null then
        insert into public.academic_years(name,start_date,end_date)
        values(recordname,startdate,enddate) returning id into targetid;
      else
        update public.academic_years
        set name=recordname,start_date=startdate,end_date=enddate,is_active=false,deleted_at=null,updated_at=now()
        where id=targetid;
      end if;
    else
      update public.academic_years
      set name=recordname,start_date=startdate,end_date=enddate,updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  elsif entity_type='terms' then
    if yearid is null or not exists(select 1 from public.academic_years y where y.id=yearid and y.deleted_at is null) then raise exception 'Academic year is invalid'; end if;
    if recordname='' then raise exception 'Term name is required'; end if;
    if seq is null or seq not between 1 and 6 then raise exception 'Term sequence must be between 1 and 6'; end if;
    if targetid is null then
      select t.id into targetid
      from public.terms t
      where t.academic_year_id=yearid and t.deleted_at is not null
        and (lower(t.name::text)=lower(recordname) or t.sequence=seq)
      order by ((lower(t.name::text)=lower(recordname)) and t.sequence=seq) desc,t.updated_at desc,t.created_at desc
      limit 1 for update;
      if targetid is null then
        insert into public.terms(academic_year_id,name,sequence,start_date,end_date,next_term_begins)
        values(yearid,recordname,seq,startdate,enddate,nextdate) returning id into targetid;
      else
        update public.terms
        set academic_year_id=yearid,name=recordname,sequence=seq,start_date=startdate,end_date=enddate,
          next_term_begins=nextdate,is_active=false,deleted_at=null,updated_at=now()
        where id=targetid;
      end if;
    else
      update public.terms
      set academic_year_id=yearid,name=recordname,sequence=seq,start_date=startdate,end_date=enddate,
        next_term_begins=nextdate,updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  elsif entity_type='classes' then
    if recordname='' then raise exception 'Class name is required'; end if;
    orderno:=coalesce(public.safe_integer(payload->>'level_order'),0);
    if teacherrecordid is not null then
      select t.profile_id
      into teacherid
      from public.teachers t
      where t.id=teacherrecordid
        and t.deleted_at is null
        and t.active
        and t.employment_status='active';
      if not found then raise exception 'Selected class teacher record is inactive or unavailable'; end if;
    elsif teacherid is not null then
      select t.id
      into teacherrecordid
      from public.teachers t
      where t.profile_id=teacherid
        and t.deleted_at is null
        and t.active
        and t.employment_status='active'
      order by t.updated_at desc
      limit 1;
    end if;
    if teacherid is not null and not exists(
      select 1 from public.profiles p
      where p.id=teacherid
        and p.active
        and public.current_app_role_for(p.role) in ('class_teacher','subject_teacher')
    ) then
      teacherid:=null;
    end if;
    if targetid is null then
      select c.id into targetid
      from public.classes c
      where lower(c.name::text)=lower(recordname) and c.deleted_at is not null
      order by c.updated_at desc,c.created_at desc limit 1 for update;
      if targetid is null then
        insert into public.classes(name,level_order,class_teacher_record_id,class_teacher_id,active)
        values(recordname,orderno,teacherrecordid,teacherid,public.safe_boolean(payload->>'active',true))
        returning id into targetid;
      else
        update public.classes
        set name=recordname,
            level_order=orderno,
            class_teacher_record_id=teacherrecordid,
            class_teacher_id=teacherid,
            active=public.safe_boolean(payload->>'active',true),
            deleted_at=null,
            updated_at=now()
        where id=targetid;
      end if;
    else
      update public.classes
      set name=recordname,
          level_order=orderno,
          class_teacher_record_id=teacherrecordid,
          class_teacher_id=teacherid,
          active=public.safe_boolean(payload->>'active',true),
          updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  elsif entity_type='subjects' then
    if recordname='' then raise exception 'Subject name is required'; end if;
    orderno:=coalesce(public.safe_integer(payload->>'display_order'),0);
    subjectcode:=upper(btrim(coalesce(payload->>'code','')));
    if targetid is null then
      select s.id,s.code::text into targetid,existingcode
      from public.subjects s
      where lower(s.name::text)=lower(recordname) and s.deleted_at is not null
      order by s.updated_at desc,s.created_at desc limit 1 for update;
      if targetid is null then
        if subjectcode='' or exists(select 1 from public.subjects s where lower(s.code::text)=lower(subjectcode)) then
          subjectcode:=public.generate_subject_code(recordname,null);
        end if;
        insert into public.subjects(code,name,display_order,active)
        values(subjectcode,recordname,orderno,public.safe_boolean(payload->>'active',true)) returning id into targetid;
      else
        subjectcode:=coalesce(nullif(subjectcode,''),existingcode);
        if exists(select 1 from public.subjects s where lower(s.code::text)=lower(subjectcode) and s.id<>targetid) then
          subjectcode:=public.generate_subject_code(recordname,targetid);
        end if;
        update public.subjects
        set code=subjectcode,name=recordname,display_order=orderno,
          active=public.safe_boolean(payload->>'active',true),deleted_at=null,updated_at=now()
        where id=targetid;
      end if;
    else
      select s.code::text into existingcode
      from public.subjects s where s.id=targetid and s.deleted_at is null for update;
      if not found then raise exception 'Subject not found'; end if;
      subjectcode:=coalesce(nullif(subjectcode,''),existingcode);
      if exists(select 1 from public.subjects s where lower(s.code::text)=lower(subjectcode) and s.id<>targetid) then
        subjectcode:=public.generate_subject_code(recordname,targetid);
      end if;
      update public.subjects
      set code=subjectcode,name=recordname,display_order=orderno,
        active=public.safe_boolean(payload->>'active',true),updated_at=now()
      where id=targetid and deleted_at is null;
    end if;
  else
    raise exception 'Unsupported academic record type';
  end if;
  get diagnostics affected=row_count;
  if targetid is null or affected=0 then raise exception 'Academic record was not saved'; end if;
  return public.get_academic_configuration();
exception when unique_violation then
  if entity_type='academic_years' then raise exception 'An academic year with this name already exists';
  elsif entity_type='terms' then raise exception 'A term with this name or sequence already exists in the selected academic year';
  elsif entity_type='classes' then raise exception 'A class with this name already exists';
  elsif entity_type='subjects' then raise exception 'A subject with this name or code already exists';
  else raise exception 'An academic record already uses these details';
  end if;
end $function$

CREATE OR REPLACE FUNCTION public.save_academic_period_control(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=public.safe_uuid(payload->>'term_id'); result_row public.academic_period_controls;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Only the System Administrator or Principal can manage academic-period controls' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then raise exception 'The platform is read-only' using errcode='42501'; end if;
  if tid is null or not exists(select 1 from public.terms where id=tid and deleted_at is null) then raise exception 'Valid term is required'; end if;
  insert into public.academic_period_controls(
    term_id,score_entry_deadline,attendance_deadline,report_submission_deadline,
    principal_approval_deadline,publication_deadline,scores_locked,attendance_locked,reports_locked,
    lock_reason,locked_by,locked_at,updated_by
  ) values(
    tid,public.safe_timestamptz(payload->>'score_entry_deadline'),public.safe_timestamptz(payload->>'attendance_deadline'),
    public.safe_timestamptz(payload->>'report_submission_deadline'),public.safe_timestamptz(payload->>'principal_approval_deadline'),
    public.safe_timestamptz(payload->>'publication_deadline'),coalesce((payload->>'scores_locked')::boolean,false),
    coalesce((payload->>'attendance_locked')::boolean,false),coalesce((payload->>'reports_locked')::boolean,false),
    left(coalesce(payload->>'lock_reason',''),500),
    case when coalesce((payload->>'scores_locked')::boolean,false) or coalesce((payload->>'attendance_locked')::boolean,false) or coalesce((payload->>'reports_locked')::boolean,false) then auth.uid() else null end,
    case when coalesce((payload->>'scores_locked')::boolean,false) or coalesce((payload->>'attendance_locked')::boolean,false) or coalesce((payload->>'reports_locked')::boolean,false) then now() else null end,
    auth.uid()
  )
  on conflict(term_id) do update set
    score_entry_deadline=excluded.score_entry_deadline,attendance_deadline=excluded.attendance_deadline,
    report_submission_deadline=excluded.report_submission_deadline,principal_approval_deadline=excluded.principal_approval_deadline,
    publication_deadline=excluded.publication_deadline,scores_locked=excluded.scores_locked,
    attendance_locked=excluded.attendance_locked,reports_locked=excluded.reports_locked,
    lock_reason=excluded.lock_reason,locked_by=excluded.locked_by,locked_at=excluded.locked_at,
    updated_by=auth.uid(),updated_at=now()
  returning * into result_row;
  insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason)
  values(auth.uid(),'academic_period_controls',tid,'UPSERT',to_jsonb(result_row),coalesce(nullif(result_row.lock_reason,''),'Academic period control updated'));
  return public.term_control_snapshot(tid);
end $function$

CREATE OR REPLACE FUNCTION public.save_assessment_scheme(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  sid uuid:=public.safe_uuid(payload->>'id'); item jsonb; staged_item jsonb; staged jsonb:='[]'::jsonb;
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id'); termid uuid:=public.safe_uuid(payload->>'term_id');
  classid uuid:=public.safe_uuid(payload->>'class_id'); subjectid uuid:=public.safe_uuid(payload->>'subject_id');
  componentid uuid; existing_component public.assessment_components%rowtype;
  weight_total numeric:=0; maxscore numeric; weightvalue numeric; orderno integer; requiredvalue boolean;
  component_code text; component_name text; seen_codes text[]:='{}'::text[]; seen_ids uuid[]:='{}'::uuid[];
  kept_ids uuid[]:='{}'::uuid[]; affected integer; scheme_in_use boolean:=false;
  old_yearid uuid; old_termid uuid; old_classid uuid; old_subjectid uuid; current_count integer; staged_count integer;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and sid is null then raise exception 'Assessment scheme identifier is invalid'; end if;
  if btrim(coalesce(payload->>'academic_year_id',''))<>'' and yearid is null then raise exception 'Academic year identifier is invalid'; end if;
  if btrim(coalesce(payload->>'term_id',''))<>'' and termid is null then raise exception 'Term identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_id',''))<>'' and classid is null then raise exception 'Class identifier is invalid'; end if;
  if btrim(coalesce(payload->>'subject_id',''))<>'' and subjectid is null then raise exception 'Subject identifier is invalid'; end if;
  if btrim(coalesce(payload->>'name',''))='' then raise exception 'Assessment scheme name is required'; end if;
  if jsonb_typeof(coalesce(payload->'components','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(payload->'components','[]'::jsonb))=0 then raise exception 'At least one assessment component is required'; end if;
  if yearid is not null and not exists(select 1 from public.academic_years y where y.id=yearid and y.deleted_at is null) then raise exception 'Academic year is invalid'; end if;
  if termid is not null and not exists(select 1 from public.terms t where t.id=termid and t.deleted_at is null and (yearid is null or t.academic_year_id=yearid)) then raise exception 'Term is invalid or does not belong to the selected academic year'; end if;
  if classid is not null and not exists(select 1 from public.classes c where c.id=classid and c.deleted_at is null and c.active) then raise exception 'Class is invalid or inactive'; end if;
  if subjectid is not null and not exists(select 1 from public.subjects sb where sb.id=subjectid and sb.deleted_at is null and sb.active) then raise exception 'Subject is invalid or inactive'; end if;
  if sid is not null then
    select academic_year_id,term_id,class_id,subject_id into old_yearid,old_termid,old_classid,old_subjectid
    from public.assessment_schemes where id=sid and deleted_at is null for update;
    if not found then raise exception 'Assessment scheme not found'; end if;
    scheme_in_use:=exists(select 1 from public.subject_results sr where sr.scheme_id=sid);
    if scheme_in_use and (old_yearid is distinct from yearid or old_termid is distinct from termid or old_classid is distinct from classid or old_subjectid is distinct from subjectid) then
      raise exception 'An assessment scheme already used in reports cannot change its academic scope';
    end if;
  end if;
  for item in select value from jsonb_array_elements(payload->'components') loop
    component_name:=btrim(coalesce(item->>'name','')); component_code:=upper(btrim(coalesce(item->>'code','')));
    maxscore:=public.safe_numeric(item->>'maximum_score'); weightvalue:=public.safe_numeric(item->>'weight');
    orderno:=coalesce(public.safe_integer(item->>'display_order'),0); requiredvalue:=public.safe_boolean(item->>'required',true);
    componentid:=public.safe_uuid(item->>'id');
    if btrim(coalesce(item->>'id',''))<>'' and componentid is null then raise exception 'Assessment component identifier is invalid'; end if;
    if component_name='' or component_code='' then raise exception 'Every assessment component requires a name and code'; end if;
    if maxscore is null or maxscore<=0 then raise exception 'Assessment component maximum score must be greater than zero'; end if;
    if weightvalue is null or weightvalue<=0 or weightvalue>100 then raise exception 'Assessment component weight is invalid'; end if;
    if component_code=any(seen_codes) then raise exception 'Assessment component codes must be unique within a scheme'; end if;
    if componentid is not null then
      if sid is null then raise exception 'A new assessment scheme cannot contain an existing component identifier'; end if;
      select * into existing_component from public.assessment_components c where c.id=componentid and c.scheme_id=sid;
      if not found then raise exception 'Assessment component does not belong to the selected scheme'; end if;
    elsif sid is not null then
      select c.id into componentid from public.assessment_components c where c.scheme_id=sid and lower(c.code::text)=lower(component_code) limit 1;
    end if;
    if componentid is not null and componentid=any(seen_ids) then raise exception 'The same assessment component was entered more than once'; end if;
    if componentid is not null then
      seen_ids:=array_append(seen_ids,componentid); kept_ids:=array_append(kept_ids,componentid);
      select * into existing_component from public.assessment_components c where c.id=componentid;
      if exists(select 1 from public.assessment_score_entries se where se.component_id=componentid and se.raw_score>maxscore) then
        raise exception 'Maximum score cannot be lower than an existing student score for component %',existing_component.name;
      end if;
      if scheme_in_use and (
        lower(existing_component.code::text)<>lower(component_code) or existing_component.maximum_score is distinct from maxscore
        or existing_component.weight is distinct from weightvalue or existing_component.required is distinct from requiredvalue
      ) then raise exception 'A component already used in reports cannot change its code, maximum score, weight, or required status'; end if;
    elsif scheme_in_use then
      raise exception 'New components cannot be added to an assessment scheme already used in reports';
    end if;
    seen_codes:=array_append(seen_codes,component_code); weight_total:=weight_total+weightvalue;
    staged:=staged||jsonb_build_array(item||jsonb_build_object(
      '_resolved_id',case when componentid is null then null else componentid::text end,
      '_name',component_name,'_code',component_code,'_maximum_score',maxscore,'_weight',weightvalue,
      '_display_order',orderno,'_required',requiredvalue
    ));
  end loop;
  if abs(weight_total-100)>0.01 then raise exception 'Assessment component weights must total 100'; end if;
  if sid is not null and scheme_in_use then
    select count(*) into current_count from public.assessment_components where scheme_id=sid;
    staged_count:=jsonb_array_length(staged);
    if current_count<>staged_count or exists(select 1 from public.assessment_components c where c.scheme_id=sid and not(c.id=any(kept_ids))) then
      raise exception 'Components already used in reports cannot be removed';
    end if;
  end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Assessment scheme update'),true);
  if sid is null then
    insert into public.assessment_schemes(name,academic_year_id,term_id,class_id,subject_id,active,created_by,deleted_at,updated_at)
    values(btrim(payload->>'name'),yearid,termid,classid,subjectid,public.safe_boolean(payload->>'active',true),auth.uid(),null,now()) returning id into sid;
  else
    update public.assessment_schemes set name=btrim(payload->>'name'),academic_year_id=yearid,term_id=termid,class_id=classid,
      subject_id=subjectid,active=public.safe_boolean(payload->>'active',true),deleted_at=null,updated_at=now() where id=sid;
    get diagnostics affected=row_count; if affected<>1 then raise exception 'Assessment scheme not found'; end if;
  end if;
  if exists(
    select 1 from public.assessment_components c where c.scheme_id=sid and not(c.id=any(kept_ids))
      and exists(select 1 from public.assessment_score_entries se where se.component_id=c.id)
  ) then raise exception 'A component with saved student scores cannot be removed'; end if;
  delete from public.assessment_components c where c.scheme_id=sid and not(c.id=any(kept_ids));
  -- Free existing component codes inside the transaction so code renames and swaps remain atomic.
  update public.assessment_components c
  set code=('__NIS_TMP_'||replace(c.id::text,'-',''))::citext,updated_at=now()
  where c.scheme_id=sid and c.id=any(kept_ids);
  -- Apply decreases first so the weight guard never sees an intermediate total above 100.
  for staged_item in select value from jsonb_array_elements(staged) loop
    componentid:=public.safe_uuid(staged_item->>'_resolved_id');
    if componentid is not null then
      weightvalue:=public.safe_numeric(staged_item->>'_weight');
      update public.assessment_components set weight=weightvalue,updated_at=now()
      where id=componentid and weight>weightvalue;
    end if;
  end loop;
  -- Insert new components while the total is below or equal to its final validated value.
  for staged_item in select value from jsonb_array_elements(staged) loop
    componentid:=public.safe_uuid(staged_item->>'_resolved_id');
    if componentid is null then
      insert into public.assessment_components(scheme_id,name,code,maximum_score,weight,display_order,required,updated_at)
      values(sid,staged_item->>'_name',(staged_item->>'_code')::citext,public.safe_numeric(staged_item->>'_maximum_score'),
        public.safe_numeric(staged_item->>'_weight'),coalesce(public.safe_integer(staged_item->>'_display_order'),0),
        public.safe_boolean(staged_item->>'_required',true),now());
    end if;
  end loop;
  -- Finish existing component updates, including increases, after all reductions and removals.
  for staged_item in select value from jsonb_array_elements(staged) loop
    componentid:=public.safe_uuid(staged_item->>'_resolved_id');
    if componentid is not null then
      update public.assessment_components set name=staged_item->>'_name',code=(staged_item->>'_code')::citext,
        maximum_score=public.safe_numeric(staged_item->>'_maximum_score'),weight=public.safe_numeric(staged_item->>'_weight'),
        display_order=coalesce(public.safe_integer(staged_item->>'_display_order'),0),
        required=public.safe_boolean(staged_item->>'_required',true),updated_at=now()
      where id=componentid and scheme_id=sid;
      get diagnostics affected=row_count; if affected<>1 then raise exception 'Assessment component was not updated'; end if;
    end if;
  end loop;
  if abs((select coalesce(sum(c.weight),0) from public.assessment_components c where c.scheme_id=sid)-100)>0.01 then
    raise exception 'Assessment component weights must total 100';
  end if;
  return public.get_academic_configuration();
exception when unique_violation then raise exception 'An assessment scheme or component code already exists in this scope';
end $function$

CREATE OR REPLACE FUNCTION public.save_backup_policy(target_retention_days integer, target_minimum_copies integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare settings_id uuid;
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can change backup policy' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if target_retention_days is null or target_retention_days<7 or target_retention_days>365 then
    raise exception 'Backup retention must be between 7 and 365 days';
  end if;
  if target_minimum_copies is null or target_minimum_copies<2 or target_minimum_copies>90 then
    raise exception 'Minimum retained backups must be between 2 and 90';
  end if;
  select id into settings_id
  from public.school_settings
  order by created_at,id
  limit 1
  for update;
  if settings_id is null then
    insert into public.school_settings(backup_retention_days,backup_minimum_copies,updated_at)
    values(target_retention_days,target_minimum_copies,now())
    returning id into settings_id;
  else
    update public.school_settings
    set backup_retention_days=target_retention_days,
        backup_minimum_copies=target_minimum_copies,
        updated_at=now()
    where id=settings_id;
  end if;
  return jsonb_build_object(
    'backup_retention_days',target_retention_days,
    'backup_minimum_copies',target_minimum_copies,
    'settings_id',settings_id
  );
end $function$

CREATE OR REPLACE FUNCTION public.save_certificate_settings(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare completion_class uuid:=public.safe_uuid(payload->>'completion_class_id'); result public.school_settings;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can manage certificate settings' using errcode='42501'; end if;
  if completion_class is not null and not exists(select 1 from public.classes where id=completion_class and active and deleted_at is null) then raise exception 'Completion class is invalid'; end if;
  update public.school_settings set certificate_completion_class_id=completion_class,certificate_footer_text=btrim(coalesce(payload->>'footer_text',certificate_footer_text)),updated_at=now() where id=(select id from public.school_settings order by created_at limit 1) returning * into result;
  if result.id is null then raise exception 'School settings not found'; end if;
  return jsonb_build_object('completion_class_id',result.certificate_completion_class_id,'footer_text',result.certificate_footer_text);
end $function$

CREATE OR REPLACE FUNCTION public.save_certificate_template(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  tid uuid:=public.safe_uuid(payload->>'id');
  ctype text:=btrim(coalesce(payload->>'certificate_type',''));
  result public.certificate_templates;
  has_file_payload boolean:=payload ? 'storage_path';
  new_storage_path text:=btrim(coalesce(payload->>'storage_path',''));
  new_original_name text:=btrim(coalesce(payload->>'original_name',''));
  new_mime_type text:=btrim(coalesce(payload->>'mime_type',''));
  new_file_size bigint:=coalesce(nullif(payload->>'file_size','')::bigint,0);
  new_checksum text:=lower(btrim(coalesce(payload->>'checksum','')));
begin
  if not public.can_manage_certificates() then
    raise exception 'Only the System Administrator can manage certificate templates' using errcode='42501';
  end if;
  if ctype not in ('student_promotion','jhs_completion','teacher_recognition') then
    raise exception 'Certificate type is invalid';
  end if;
  if btrim(coalesce(payload->>'title',''))='' or btrim(coalesce(payload->>'statement_template',''))='' then
    raise exception 'Certificate title and statement are required';
  end if;
  if length(btrim(payload->>'title'))>120 or length(btrim(payload->>'statement_template'))>800 then
    raise exception 'Certificate title or statement is too long';
  end if;
  if has_file_payload then
    if new_storage_path='' or new_storage_path not like ctype||'/%' then raise exception 'Certificate template storage path is invalid'; end if;
    if new_original_name='' or length(new_original_name)>255 then raise exception 'Certificate template filename is invalid'; end if;
    if new_mime_type not in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception 'Unsupported certificate template file type'; end if;
    if new_file_size<=0 or new_file_size>20971520 then raise exception 'Certificate template must be between 1 byte and 20 MB'; end if;
    if length(new_checksum)>128 then raise exception 'Certificate template checksum is invalid'; end if;
  end if;
  update public.certificate_templates
  set active=false,updated_at=now()
  where certificate_type=ctype and active and (tid is null or id<>tid);
  if tid is null then
    insert into public.certificate_templates(
      certificate_type,name,title,subtitle,statement_template,footer_text,primary_colour,accent_colour,active,
      storage_path,original_name,mime_type,file_size,checksum,version,uploaded_by
    )
    values(
      ctype,coalesce(nullif(btrim(payload->>'name'),''),public.certificate_type_label(ctype)),
      btrim(payload->>'title'),btrim(coalesce(payload->>'subtitle','')),btrim(payload->>'statement_template'),
      btrim(coalesce(payload->>'footer_text','')),coalesce(nullif(payload->>'primary_colour',''),'#0a2f73'),
      coalesce(nullif(payload->>'accent_colour',''),'#f1b51c'),true,
      case when has_file_payload then new_storage_path else '' end,
      case when has_file_payload then new_original_name else '' end,
      case when has_file_payload then new_mime_type else '' end,
      case when has_file_payload then new_file_size else 0 end,
      case when has_file_payload then new_checksum else '' end,
      1,case when has_file_payload then auth.uid() else null end
    )
    returning * into result;
  else
    update public.certificate_templates
    set name=coalesce(nullif(btrim(payload->>'name'),''),name),
        title=btrim(payload->>'title'),
        subtitle=btrim(coalesce(payload->>'subtitle','')),
        statement_template=btrim(payload->>'statement_template'),
        footer_text=btrim(coalesce(payload->>'footer_text','')),
        primary_colour=coalesce(nullif(payload->>'primary_colour',''),primary_colour),
        accent_colour=coalesce(nullif(payload->>'accent_colour',''),accent_colour),
        active=true,
        storage_path=case when has_file_payload then new_storage_path else storage_path end,
        original_name=case when has_file_payload then new_original_name else original_name end,
        mime_type=case when has_file_payload then new_mime_type else mime_type end,
        file_size=case when has_file_payload then new_file_size else file_size end,
        checksum=case when has_file_payload then new_checksum else checksum end,
        version=case when has_file_payload then version+1 else version end,
        uploaded_by=case when has_file_payload then auth.uid() else uploaded_by end,
        updated_at=now()
    where id=tid
    returning * into result;
  end if;
  if result.id is null then raise exception 'Certificate template not found'; end if;
  if has_file_payload then
    perform public.record_certificate_event(
      null,null,'certificate_template_design_uploaded','',
      jsonb_build_object(
        'certificate_type',ctype,'storage_path',result.storage_path,'original_name',result.original_name,
        'mime_type',result.mime_type,'file_size',result.file_size,'checksum',result.checksum,'version',result.version
      )
    );
  end if;
  return to_jsonb(result);
end $function$

CREATE OR REPLACE FUNCTION public.save_class_attendance(target_term_id uuid, target_class_id uuid, target_date date, entries jsonb, notes_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare target_year_id uuid;term_start date;term_end date;target_register_id uuid;expected_count integer;provided_count integer;distinct_count integer;invalid_count integer;
begin
  if not public.is_assigned_class_teacher(target_class_id) then raise exception 'You can mark attendance only for your assigned class' using errcode='42501'; end if;
  if not public.term_phase_writable(target_term_id,'attendance',null) then raise exception 'Attendance is locked for the selected term' using errcode='42501'; end if;
  if target_term_id is null or target_date is null then raise exception 'Term and attendance date are required'; end if;
  if entries is null or jsonb_typeof(entries)<>'array' then raise exception 'Attendance entries must be supplied as a list'; end if;
  select t.academic_year_id,t.start_date,t.end_date into target_year_id,term_start,term_end from public.terms t where t.id=target_term_id and t.deleted_at is null;
  if target_year_id is null then raise exception 'Term is unavailable'; end if;
  if term_start is not null and target_date<term_start then raise exception 'Attendance date is before the selected term'; end if;
  if term_end is not null and target_date>term_end then raise exception 'Attendance date is after the selected term'; end if;
  if target_date>current_date then raise exception 'Attendance cannot be marked for a future date'; end if;
  select count(*) into expected_count from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null and s.status='active' where e.academic_year_id=target_year_id and e.class_id=target_class_id and e.deleted_at is null and e.active;
  if expected_count=0 then raise exception 'No students are enrolled in this class for the selected term'; end if;
  select count(*),count(distinct public.safe_uuid(item->>'enrollment_id')) into provided_count,distinct_count from jsonb_array_elements(entries) item;
  if provided_count<>expected_count or distinct_count<>provided_count then raise exception 'Attendance must include each student exactly once'; end if;
  select count(*) into invalid_count from jsonb_array_elements(entries) item
  left join public.enrollments e on e.id=public.safe_uuid(item->>'enrollment_id') left join public.students s on s.id=e.student_id
  where public.safe_uuid(item->>'enrollment_id') is null or coalesce(item->>'attendance_status','') not in ('present','absent','late','excused')
    or e.id is null or e.deleted_at is not null or not e.active or e.academic_year_id<>target_year_id or e.class_id<>target_class_id
    or s.id is null or s.deleted_at is not null or s.status<>'active';
  if invalid_count>0 then raise exception 'One or more attendance entries are invalid or outside the assigned class'; end if;
  perform set_config('app.change_reason','Class attendance marked',true);
  insert into public.class_attendance_registers(term_id,class_id,attendance_date,marked_by,notes,updated_at)
  values(target_term_id,target_class_id,target_date,auth.uid(),coalesce(notes_text,''),now())
  on conflict(term_id,class_id,attendance_date) do update set marked_by=auth.uid(),notes=excluded.notes,updated_at=now()
  returning id into target_register_id;
  insert into public.student_attendance_entries(register_id,enrollment_id,attendance_status,updated_at)
  select target_register_id,public.safe_uuid(item->>'enrollment_id'),item->>'attendance_status',now() from jsonb_array_elements(entries) item
  on conflict(register_id,enrollment_id) do update set attendance_status=excluded.attendance_status,updated_at=now();
  delete from public.student_attendance_entries a where a.register_id=target_register_id and not exists(select 1 from jsonb_array_elements(entries) item where public.safe_uuid(item->>'enrollment_id')=a.enrollment_id);
  perform public.sync_attendance_reports(target_term_id,target_class_id);
  return public.get_class_attendance_register(target_term_id,target_class_id,target_date);
end $function$

CREATE OR REPLACE FUNCTION public.save_class_subject_assignment(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare targetid uuid:=public.safe_uuid(payload->>'id'); classid uuid:=public.safe_uuid(payload->>'class_id'); subjectid uuid:=public.safe_uuid(payload->>'subject_id'); teacherid uuid:=public.safe_uuid(payload->>'teacher_id');
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Subject assignment identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_id',''))<>'' and classid is null then raise exception 'Class identifier is invalid'; end if;
  if btrim(coalesce(payload->>'subject_id',''))<>'' and subjectid is null then raise exception 'Subject identifier is invalid'; end if;
  if btrim(coalesce(payload->>'teacher_id',''))<>'' and teacherid is null then raise exception 'Teacher identifier is invalid'; end if;
  if classid is null or not exists(select 1 from public.classes where id=classid and deleted_at is null and active) then raise exception 'Selected class is invalid or inactive'; end if;
  if subjectid is null or not exists(select 1 from public.subjects where id=subjectid and deleted_at is null and active) then raise exception 'Selected subject is invalid or inactive'; end if;
  if teacherid is not null and not exists(select 1 from public.profiles p where p.id=teacherid and p.active and public.current_app_role_for(p.role) in ('principal','academic_admin','class_teacher','subject_teacher')) then raise exception 'Selected teacher account is invalid'; end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Class subject assignment update'),true);
  if targetid is null then
    insert into public.class_subjects(class_id,subject_id,teacher_id,active,updated_at) values(classid,subjectid,teacherid,public.safe_boolean(payload->>'active',true),now())
    on conflict(class_id,subject_id) do update set teacher_id=excluded.teacher_id,active=excluded.active,updated_at=now() returning id into targetid;
  else
    update public.class_subjects set class_id=classid,subject_id=subjectid,teacher_id=teacherid,active=public.safe_boolean(payload->>'active',true),updated_at=now() where id=targetid;
    if not found then raise exception 'Subject assignment not found'; end if;
  end if;
  return public.get_academic_configuration();
exception when unique_violation then raise exception 'This subject is already assigned to the selected class';
end $function$

CREATE OR REPLACE FUNCTION public.save_class_subject_assignments_batch(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(payload->>'id');
  teacherid uuid:=public.safe_uuid(payload->>'teacher_id');
  activevalue boolean:=public.safe_boolean(payload->>'active',true);
  selections jsonb:=coalesce(payload->'selections','[]'::jsonb);
  item jsonb;
  classid uuid;
  subjectid uuid;
  pairkey text;
  seenpairs text[]:='{}'::text[];
  previous_teacher uuid;
  old_class uuid;
  old_subject uuid;
  old_teacher uuid;
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Subject assignment identifier is invalid'; end if;
  if btrim(coalesce(payload->>'teacher_id',''))<>'' and teacherid is null then raise exception 'Teacher identifier is invalid'; end if;
  if teacherid is null or not exists(
    select 1 from public.profiles p
    where p.id=teacherid and p.active
      and public.current_app_role_for(p.role) in ('class_teacher','subject_teacher')
  ) then raise exception 'Select an active Class Teacher or Subject Teacher account'; end if;
  if jsonb_typeof(selections)<>'array' or jsonb_array_length(selections)=0 then
    raise exception 'Select at least one class and subject';
  end if;
  if jsonb_array_length(selections)>500 then raise exception 'Too many assignments were selected'; end if;
  if targetid is not null then
    select class_id,subject_id,teacher_id into old_class,old_subject,old_teacher
    from public.class_subjects where id=targetid for update;
    if not found then raise exception 'Subject assignment not found'; end if;
  end if;
  for item in select value from jsonb_array_elements(selections) loop
    classid:=public.safe_uuid(item->>'class_id');
    subjectid:=public.safe_uuid(item->>'subject_id');
    if classid is null or not exists(select 1 from public.classes c where c.id=classid and c.deleted_at is null and c.active) then
      raise exception 'A selected class is invalid or inactive';
    end if;
    if subjectid is null or not exists(select 1 from public.subjects s where s.id=subjectid and s.deleted_at is null and s.active) then
      raise exception 'A selected subject is invalid or inactive';
    end if;
    pairkey:=classid::text||'|'||subjectid::text;
    if pairkey=any(seenpairs) then raise exception 'The same class and subject were selected more than once'; end if;
    seenpairs:=array_append(seenpairs,pairkey);
  end loop;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Class-subject assignment batch update'),true);
  if targetid is not null then
    delete from public.class_subjects where id=targetid;
  end if;
  for item in select value from jsonb_array_elements(selections) loop
    classid:=public.safe_uuid(item->>'class_id');
    subjectid:=public.safe_uuid(item->>'subject_id');
    select cs.teacher_id into previous_teacher
    from public.class_subjects cs
    where cs.class_id=classid and cs.subject_id=subjectid
    for update;
    insert into public.class_subjects(class_id,subject_id,teacher_id,active,updated_at)
    values(classid,subjectid,teacherid,activevalue,now())
    on conflict(class_id,subject_id) do update set
      teacher_id=excluded.teacher_id,
      active=excluded.active,
      updated_at=now();
    if previous_teacher is not null and previous_teacher is distinct from teacherid then
      delete from public.user_class_access
      where user_id=previous_teacher and class_id=classid and subject_id=subjectid;
    end if;
    if activevalue then
      insert into public.user_class_access(user_id,class_id,subject_id,access_level)
      values(teacherid,classid,subjectid,'score')
      on conflict do nothing;
    else
      delete from public.user_class_access
      where user_id=teacherid and class_id=classid and subject_id=subjectid;
    end if;
  end loop;
  if old_teacher is not null and old_class is not null and old_subject is not null
     and not exists(
       select 1 from public.class_subjects cs
       where cs.class_id=old_class and cs.subject_id=old_subject
         and cs.teacher_id=old_teacher and cs.active
     ) then
    delete from public.user_class_access
    where user_id=old_teacher and class_id=old_class and subject_id=old_subject;
  end if;
  return public.get_academic_configuration();
end $function$

CREATE OR REPLACE FUNCTION public.save_class_timetable_entry(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
 eid uuid:=public.safe_uuid(payload->>'id');
 yearid uuid:=public.safe_uuid(payload->>'academic_year_id');
 classid uuid:=public.safe_uuid(payload->>'class_id');
 subjectid uuid:=public.safe_uuid(payload->>'subject_id');
 teacherid uuid:=public.safe_uuid(payload->>'teacher_id');
 day_value text:=initcap(lower(btrim(coalesce(payload->>'day_of_week',''))));
 start_value time;end_value time;current_updated timestamptz;
 expected_updated timestamptz:=public.safe_timestamptz(payload->>'updated_at');
 row public.class_timetable_entries%rowtype;
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can manage class timetables' using errcode='42501';end if;
 perform public.require_sensitive_access();perform public.require_license_feature('timetable');
 if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit timetable changes' using errcode='42501';end if;
 if yearid is null or classid is null or subjectid is null or teacherid is null then raise exception 'Academic year, class, subject, and teacher are required';end if;
 if day_value not in ('Monday','Tuesday','Wednesday','Thursday','Friday') then raise exception 'Timetable day must be Monday to Friday';end if;
 begin start_value:=(payload->>'period_start')::time;end_value:=(payload->>'period_end')::time;exception when others then raise exception 'Period start and end times are invalid';end;
 if end_value<=start_value then raise exception 'Period end time must be after start time';end if;
 if not exists(select 1 from public.academic_years where id=yearid and deleted_at is null) then raise exception 'Academic year not found';end if;
 if not exists(select 1 from public.classes where id=classid and deleted_at is null and active) then raise exception 'Class not found';end if;
 if not exists(select 1 from public.subjects where id=subjectid and deleted_at is null and active) then raise exception 'Subject not found';end if;
 if not exists(select 1 from public.teachers where id=teacherid and deleted_at is null and active and employment_status='active') then raise exception 'Teacher not found or not active';end if;
 if eid is not null then select updated_at into current_updated from public.class_timetable_entries where id=eid and active for update;if current_updated is null then raise exception 'Timetable period not found';end if;if expected_updated is not null and current_updated<>expected_updated then raise exception 'This timetable period changed in another session. Reload and try again.';end if;end if;
 if exists(select 1 from public.class_timetable_entries x where x.active and x.academic_year_id=yearid and x.class_id=classid and x.day_of_week=day_value and (eid is null or x.id<>eid) and x.period_start<end_value and x.period_end>start_value) then raise exception 'This class already has an overlapping timetable period';end if;
 if exists(select 1 from public.class_timetable_entries x where x.active and x.academic_year_id=yearid and x.teacher_id=teacherid and x.day_of_week=day_value and (eid is null or x.id<>eid) and x.period_start<end_value and x.period_end>start_value) then raise exception 'The selected teacher already has another class during this time';end if;
 if eid is null then
  insert into public.class_timetable_entries(academic_year_id,class_id,day_of_week,period_start,period_end,subject_id,teacher_id,notes,created_by)
  values(yearid,classid,day_value,start_value,end_value,subjectid,teacherid,btrim(coalesce(payload->>'notes','')),auth.uid()) returning * into row;
 else
  update public.class_timetable_entries set academic_year_id=yearid,class_id=classid,day_of_week=day_value,period_start=start_value,period_end=end_value,subject_id=subjectid,teacher_id=teacherid,notes=btrim(coalesce(payload->>'notes','')),updated_at=now() where id=eid returning * into row;
 end if;
 return to_jsonb(row);
end$function$

CREATE OR REPLACE FUNCTION public.save_grading_scale(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(payload->>'id');
  yearid uuid:=public.safe_uuid(payload->>'academic_year_id');
  classid uuid:=public.safe_uuid(payload->>'class_id');
  subjectid uuid:=public.safe_uuid(payload->>'subject_id');
  minmark numeric:=public.safe_numeric(payload->>'min_mark');
  maxmark numeric:=public.safe_numeric(payload->>'max_mark');
  pointvalue numeric:=coalesce(public.safe_numeric(payload->>'grade_point'),0);
  orderno integer:=coalesce(public.safe_integer(payload->>'display_order'),0);
  interpretation_text text:=btrim(coalesce(payload->>'interpretation',''));
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Grading scale identifier is invalid'; end if;
  if btrim(coalesce(payload->>'academic_year_id',''))<>'' and yearid is null then raise exception 'Academic year identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_id',''))<>'' and classid is null then raise exception 'Class identifier is invalid'; end if;
  if btrim(coalesce(payload->>'subject_id',''))<>'' and subjectid is null then raise exception 'Subject identifier is invalid'; end if;
  if btrim(coalesce(payload->>'grade',''))='' or btrim(coalesce(payload->>'remark',''))='' then raise exception 'Grade and remark are required'; end if;
  if minmark is null or maxmark is null or minmark<0 or maxmark>100 or minmark>maxmark then raise exception 'Grade range is invalid'; end if;
  if length(interpretation_text)>180 then raise exception 'The interpretation must not exceed 180 characters'; end if;
  if interpretation_text='' then interpretation_text:=public.default_grading_interpretation(payload->>'grade',payload->>'remark'); end if;
  if yearid is not null and not exists(select 1 from public.academic_years where id=yearid and deleted_at is null) then raise exception 'Academic year is invalid'; end if;
  if classid is not null and not exists(select 1 from public.classes where id=classid and deleted_at is null) then raise exception 'Class is invalid'; end if;
  if subjectid is not null and not exists(select 1 from public.subjects where id=subjectid and deleted_at is null) then raise exception 'Subject is invalid'; end if;
  if exists(
    select 1 from public.grading_scales g
    where g.deleted_at is null and (targetid is null or g.id<>targetid)
      and g.academic_year_id is not distinct from yearid
      and g.class_id is not distinct from classid
      and g.subject_id is not distinct from subjectid
      and numrange(g.min_mark,g.max_mark,'[]') && numrange(minmark,maxmark,'[]')
  ) then raise exception 'Grade ranges cannot overlap within the same scope'; end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Grading scale update'),true);
  if targetid is null then
    insert into public.grading_scales(
      academic_year_id,class_id,subject_id,min_mark,max_mark,grade,remark,interpretation,
      grade_point,display_order,deleted_at,updated_at
    ) values(
      yearid,classid,subjectid,minmark,maxmark,upper(btrim(payload->>'grade')),
      btrim(payload->>'remark'),interpretation_text,pointvalue,orderno,null,now()
    ) returning id into targetid;
  else
    update public.grading_scales
    set academic_year_id=yearid,class_id=classid,subject_id=subjectid,
        min_mark=minmark,max_mark=maxmark,grade=upper(btrim(payload->>'grade')),
        remark=btrim(payload->>'remark'),interpretation=interpretation_text,
        grade_point=pointvalue,display_order=orderno,deleted_at=null,updated_at=now()
    where id=targetid;
    if not found then raise exception 'Grading scale not found'; end if;
  end if;
  return public.get_academic_configuration();
exception when unique_violation then
  raise exception 'This grading scope already contains the selected grade';
end $function$

CREATE OR REPLACE FUNCTION public.save_headteacher(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  hid uuid:=public.safe_uuid(payload->>'id');
  profileid uuid:=public.safe_uuid(payload->>'profile_id');
  staff text:=upper(btrim(coalesce(payload->>'staff_no','')));
  full_name_value text:=regexp_replace(btrim(coalesce(payload->>'full_name','')),'[[:space:]]+',' ','g');
  contact_value text:=btrim(coalesce(payload->>'contact',payload->>'phone',''));
  name_parts text[];
  first_name_value text;
  last_name_value text:='';
  current_updated timestamptz;
  expected_updated timestamptz:=public.safe_timestamptz(payload->>'updated_at');
  linked_role text;
  affected integer;
begin
  if auth.uid() is null or not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and hid is null then raise exception 'Principal record identifier is invalid'; end if;
  if btrim(coalesce(payload->>'profile_id',''))<>'' and profileid is null then raise exception 'Linked user account is invalid'; end if;
  if full_name_value='' then raise exception 'Principal full name is required'; end if;
  if contact_value='' then raise exception 'Principal contact is required'; end if;
  name_parts:=regexp_split_to_array(full_name_value,'[[:space:]]+');
  first_name_value:=name_parts[1];
  if cardinality(name_parts)>1 then last_name_value:=array_to_string(name_parts[2:cardinality(name_parts)],' '); end if;
  if hid is not null then
    select updated_at into current_updated from public.headteachers where id=hid and deleted_at is null for update;
    if not found then raise exception 'Principal record not found'; end if;
    if expected_updated is not null and current_updated is distinct from expected_updated then raise exception 'Principal record changed by another user' using errcode='40001'; end if;
  end if;
  if hid is null and (staff='' or exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff))) then staff:=public.generate_school_identifier('principal'); end if;
  if staff='' then staff:=public.generate_school_identifier('principal'); end if;
  if exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff) and (hid is null or h.id<>hid)) then raise exception 'Staff number already exists'; end if;
  if profileid is not null then
    select public.current_app_role_for(p.role) into linked_role from public.profiles p where p.id=profileid and p.active;
    if linked_role is null then raise exception 'Selected user account is unavailable'; end if;
    if linked_role<>'principal' then raise exception 'Selected user account is not a Principal account'; end if;
    if exists(select 1 from public.headteachers h where h.profile_id=profileid and h.deleted_at is null and (hid is null or h.id<>hid)) or exists(select 1 from public.teachers t where t.profile_id=profileid and t.deleted_at is null) then raise exception 'This user account is already linked to another staff record'; end if;
  end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Principal record update'),true);
  if hid is null then
    insert into public.headteachers(profile_id,staff_no,first_name,middle_name,last_name,phone,employment_status,active,created_by,updated_at)
    values(profileid,staff,first_name_value,'',last_name_value,contact_value,'active',true,auth.uid(),now()) returning id into hid;
  else
    update public.headteachers set profile_id=profileid,staff_no=staff,first_name=first_name_value,middle_name='',last_name=last_name_value,phone=contact_value,employment_status='active',active=true,updated_at=now()
    where id=hid and deleted_at is null;
    get diagnostics affected=row_count;
    if affected<>1 then raise exception 'Principal record was not updated'; end if;
  end if;
  update public.school_settings
  set head_name=full_name_value,
      updated_at=now()
  where id=(select id from public.school_settings order by created_at,id limit 1);
  return public.get_headteacher_record(hid);
exception when unique_violation then
  raise exception 'Staff number or linked user account is already in use';
end $function$

CREATE OR REPLACE FUNCTION public.save_id_card_settings(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.id_card_settings%rowtype;template text:=lower(btrim(coalesce(payload->>'template_code','modern')));months integer:=coalesce(nullif(payload->>'validity_months','')::integer,12);staff_months integer:=coalesce(nullif(payload->>'staff_validity_months','')::integer,24);message text:=btrim(coalesce(payload->>'back_message',''));
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can configure ID cards' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('id_cards');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit ID card changes' using errcode='42501';end if;if template not in ('classic','modern','minimal') then raise exception 'Unsupported ID card template';end if;if months not between 1 and 60 or staff_months not between 1 and 60 then raise exception 'ID card validity must be between 1 and 60 months';end if;if length(message)>500 then raise exception 'ID card back message is too long';end if;
 update public.id_card_settings set template_code=template,card_title=left(coalesce(nullif(btrim(payload->>'card_title'),''),'STUDENT ID CARD'),80),staff_card_title=left(coalesce(nullif(btrim(payload->>'staff_card_title'),''),'STAFF ID CARD'),80),validity_months=months,staff_validity_months=staff_months,show_date_of_birth=coalesce((payload->>'show_date_of_birth')::boolean,false),show_gender=coalesce((payload->>'show_gender')::boolean,false),show_guardian_phone=coalesce((payload->>'show_guardian_phone')::boolean,false),show_school_address=coalesce((payload->>'show_school_address')::boolean,true),show_school_phone=coalesce((payload->>'show_school_phone')::boolean,true),show_school_email=coalesce((payload->>'show_school_email')::boolean,true),show_principal_signature=coalesce((payload->>'show_principal_signature')::boolean,true),show_principal_name=coalesce((payload->>'show_principal_name')::boolean,true),show_principal_title=coalesce((payload->>'show_principal_title')::boolean,true),back_message=coalesce(nullif(message,''),'This card remains the property of the school. If found, please return it to the school administration.'),updated_by=auth.uid(),updated_at=now() where id=(select id from public.id_card_settings limit 1) returning * into updated;
 if updated.id is null then insert into public.id_card_settings(template_code,card_title,staff_card_title,validity_months,staff_validity_months,show_date_of_birth,show_gender,show_guardian_phone,show_school_address,show_school_phone,show_school_email,show_principal_signature,show_principal_name,show_principal_title,back_message,updated_by) values(template,left(coalesce(nullif(btrim(payload->>'card_title'),''),'STUDENT ID CARD'),80),left(coalesce(nullif(btrim(payload->>'staff_card_title'),''),'STAFF ID CARD'),80),months,staff_months,coalesce((payload->>'show_date_of_birth')::boolean,false),coalesce((payload->>'show_gender')::boolean,false),coalesce((payload->>'show_guardian_phone')::boolean,false),coalesce((payload->>'show_school_address')::boolean,true),coalesce((payload->>'show_school_phone')::boolean,true),coalesce((payload->>'show_school_email')::boolean,true),coalesce((payload->>'show_principal_signature')::boolean,true),coalesce((payload->>'show_principal_name')::boolean,true),coalesce((payload->>'show_principal_title')::boolean,true),coalesce(nullif(message,''),'This card remains the property of the school. If found, please return it to the school administration.'),auth.uid()) returning * into updated;end if;return to_jsonb(updated);
end$function$

CREATE OR REPLACE FUNCTION public.save_profile_access(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare userid uuid:=(payload->>'user_id')::uuid; accessitem jsonb;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if userid=auth.uid() and coalesce((payload->>'active')::boolean,true)=false then
    raise exception 'You cannot deactivate your own account';
  end if;
  perform set_config('app.change_reason',coalesce(payload->>'reason','User access update'),true);
  update public.profiles set full_name=coalesce(payload->>'full_name',full_name),
    role=coalesce(nullif(payload->>'role','')::public.app_role,role),
    active=coalesce((payload->>'active')::boolean,active),
    mfa_required=coalesce((payload->>'mfa_required')::boolean,mfa_required),
    phone=coalesce(payload->>'phone',phone)
  where id=userid;
  if payload ? 'access' then
    delete from public.user_class_access where user_id=userid;
    for accessitem in select value from jsonb_array_elements(coalesce(payload->'access','[]'::jsonb))
    loop
      insert into public.user_class_access(user_id,class_id,subject_id,access_level)
      values(userid,(accessitem->>'class_id')::uuid,nullif(accessitem->>'subject_id','')::uuid,
        coalesce(accessitem->>'access_level','view'))
      on conflict do nothing;
    end loop;
  end if;
  return public.list_profiles_with_access();
end $function$

CREATE OR REPLACE FUNCTION public.save_promotion_cutoff(target_score integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  item record;
  processed integer:=0;
  settings_id uuid;
  sync_enrollment boolean;
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can change the promotion cutoff score' using errcode='42501';
  end if;
  if target_score is null or target_score<40 or target_score>60 then
    raise exception 'Promotion cutoff score must be between 40 and 60';
  end if;
  perform set_config('app.change_reason','Term 3 automatic-promotion cutoff updated',true);
  select s.id into settings_id
  from public.school_settings s
  order by s.created_at,s.id
  limit 1
  for update;
  if settings_id is null then
    insert into public.school_settings(promotion_cutoff_score,updated_at)
    values(target_score,now())
    returning id into settings_id;
  else
    update public.school_settings
    set promotion_cutoff_score=target_score,
        updated_at=now()
    where id=settings_id;
  end if;
  for item in
    select r.id,r.status::text as status
    from public.student_reports r
    join public.terms t on t.id=r.term_id
    where r.deleted_at is null
      and t.deleted_at is null
      and public.is_term_three(t.sequence,t.name::text)
  loop
    select item.status in ('approved','published') or exists(
      select 1 from public.enrollments e
      where e.promotion_source_report_id=item.id
        and e.enrollment_origin='automatic_promotion'
        and e.deleted_at is null
    ) into sync_enrollment;
    perform public.refresh_report_promotion(item.id,sync_enrollment);
    processed:=processed+1;
  end loop;
  return jsonb_build_object(
    'promotion_cutoff_score',target_score,
    'reports_recalculated',processed,
    'settings_id',settings_id
  );
end $function$

CREATE OR REPLACE FUNCTION public.save_report_card(payload jsonb, expected_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  rid uuid:=public.safe_uuid(payload->>'report_id'); enrollmentid uuid:=public.safe_uuid(payload->>'enrollment_id'); termid uuid:=public.safe_uuid(payload->>'term_id');
  current_version integer; current_status public.report_status; classid uuid; yearid uuid; subject_item jsonb; component_item jsonb;
  resultid uuid; schemeid uuid; subjectid uuid; componentid uuid; promotedid uuid; report_fields jsonb:=coalesce(payload->'fields','{}'::jsonb);
  report_created boolean:=false; field_changed boolean:=false; subject_changed boolean:=false; opened integer; present integer;
  scorevalue numeric; maxscore numeric; seen_subjects uuid[]:='{}'::uuid[];
  before_snapshot jsonb; after_snapshot jsonb; delegationid uuid; delegation_ids uuid[]:='{}'::uuid[]; correction_allowed boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(payload->'subjects','[]'::jsonb))<>'array' then raise exception 'Report subjects must be a list'; end if;
  if btrim(coalesce(payload->>'report_id',''))<>'' and rid is null then raise exception 'Report identifier is invalid'; end if;
  if enrollmentid is null or termid is null then raise exception 'Student enrolment and term are required'; end if;
  select e.class_id,e.academic_year_id into classid,yearid from public.enrollments e where e.id=enrollmentid and e.deleted_at is null;
  if classid is null then raise exception 'Access denied' using errcode='42501'; end if;
  if not exists(select 1 from public.terms t where t.id=termid and t.academic_year_id=yearid and t.deleted_at is null) then raise exception 'Term and enrolment academic year do not match'; end if;
  perform set_config('app.report_write','on',true); perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Report card save'),true);
  perform pg_advisory_xact_lock(hashtext(enrollmentid::text),hashtext(termid::text));
  if rid is null then select id,version,status into rid,current_version,current_status from public.student_reports where enrollment_id=enrollmentid and term_id=termid and deleted_at is null for update;
  else select version,status into current_version,current_status from public.student_reports where id=rid and enrollment_id=enrollmentid and term_id=termid and deleted_at is null for update; end if;
  correction_allowed:=rid is not null and public.has_approved_report_correction(rid);
  if not public.can_create_report_for_class_term(classid,termid)
     and not (correction_allowed and public.can_create_report_scope(classid,termid)) then
    raise exception 'Access denied or the selected academic phase is locked' using errcode='42501';
  end if;
  if rid is not null then before_snapshot:=public.build_report_snapshot(rid); end if;
  if rid is null then
    insert into public.student_reports(enrollment_id,term_id,status,version,created_by) values(enrollmentid,termid,'draft',1,auth.uid()) returning id,version,status into rid,current_version,current_status;
    report_created:=true;
  else
    if expected_version is not null and expected_version<>current_version then raise exception 'This report was changed by another user. Refresh before saving.' using errcode='40001'; end if;
    if current_status not in ('draft','returned','withdrawn') then raise exception 'This report is locked by the approval workflow'; end if;
  end if;
  if report_fields<>'{}'::jsonb then
    if not public.can_manage_class_report_fields_for_term(classid,termid) and not (correction_allowed and public.can_manage_class_report_fields_scope(classid,termid)) then raise exception 'You are not authorised to edit class report details' using errcode='42501'; end if;
    opened:=public.safe_integer(report_fields->>'days_school_opened'); present:=public.safe_integer(report_fields->>'days_present');
    if btrim(coalesce(report_fields->>'days_school_opened',''))<>'' and opened is null then raise exception 'Days school opened is invalid'; end if;
    if btrim(coalesce(report_fields->>'days_present',''))<>'' and present is null then raise exception 'Days present is invalid'; end if;
    opened:=coalesce(opened,0); present:=coalesce(present,0);
    if opened<0 or present<0 or present>opened then raise exception 'Attendance values are invalid'; end if;
    promotedid:=public.safe_uuid(report_fields->>'promoted_to_class_id');
    if btrim(coalesce(report_fields->>'promoted_to_class_id',''))<>'' and promotedid is null then raise exception 'Promotion class is invalid'; end if;
    if promotedid is not null and not exists(select 1 from public.classes c where c.id=promotedid and c.active and c.deleted_at is null) then raise exception 'Promotion class is unavailable'; end if;
    update public.student_reports set days_school_opened=opened,days_present=present,attitude=coalesce(report_fields->>'attitude',''),conduct=coalesce(report_fields->>'conduct',''),
      interest=coalesce(report_fields->>'interest',''),teacher_comment=coalesce(report_fields->>'teacher_comment',''),
      head_comment=case when public.has_role(array['system_admin','principal']) then coalesce(report_fields->>'head_comment',head_comment) else head_comment end,
      promoted_to_class_id=promotedid,updated_at=now() where id=rid;
    field_changed:=true;
    if not public.is_official_class_teacher_for_class(classid) then
      delegation_ids:=delegation_ids||public.active_emergency_delegation_ids(classid,null,termid,false,true,auth.uid());
    end if;
  end if;
  for subject_item in select value from jsonb_array_elements(coalesce(payload->'subjects','[]'::jsonb)) loop
    subjectid:=public.safe_uuid(subject_item->>'subject_id');
    if subjectid is null then raise exception 'A report subject identifier is invalid'; end if;
    if subjectid=any(seen_subjects) then raise exception 'A report subject was supplied more than once'; end if;
    seen_subjects:=array_append(seen_subjects,subjectid);
    if not exists(select 1 from public.class_subjects cs where cs.class_id=classid and cs.subject_id=subjectid and cs.active) then raise exception 'A report subject is not assigned to this class'; end if;
    if not public.can_score_class_subject_for_term(classid,subjectid,termid) and not (correction_allowed and public.can_score_class_subject_scope(classid,subjectid,termid)) then raise exception 'You are not authorised to score one or more subjects' using errcode='42501'; end if;
    if not public.is_official_subject_teacher_for_class(classid,subjectid) then
      delegation_ids:=delegation_ids||public.active_emergency_delegation_ids(classid,subjectid,termid,true,false,auth.uid());
    end if;
    schemeid:=public.safe_uuid(subject_item->>'scheme_id');
    if btrim(coalesce(subject_item->>'scheme_id',''))<>'' and schemeid is null then raise exception 'Assessment scheme identifier is invalid'; end if;
    if schemeid is null then schemeid:=public.resolve_assessment_scheme(classid,subjectid,yearid,termid); end if;
    if schemeid is null then raise exception 'No assessment scheme is configured for a subject'; end if;
    if not exists(select 1 from public.assessment_schemes sc where sc.id=schemeid and sc.active
      and (sc.academic_year_id is null or sc.academic_year_id=yearid) and (sc.term_id is null or sc.term_id=termid)
      and (sc.class_id is null or sc.class_id=classid) and (sc.subject_id is null or sc.subject_id=subjectid)) then raise exception 'Assessment scheme does not match the report subject'; end if;
    if abs((select coalesce(sum(weight),0) from public.assessment_components where scheme_id=schemeid)-100)>0.01 then raise exception 'Assessment scheme weights must total 100'; end if;
    if jsonb_typeof(coalesce(subject_item->'components','[]'::jsonb))<>'array' then raise exception 'Assessment components must be a list'; end if;
    insert into public.subject_results(report_id,subject_id,scheme_id,teacher_initials,created_by)
    values(rid,subjectid,schemeid,btrim(coalesce(subject_item->>'teacher_initials','')),auth.uid())
    on conflict(report_id,subject_id) do update set scheme_id=excluded.scheme_id,teacher_initials=excluded.teacher_initials,updated_at=now() returning id into resultid;
    delete from public.assessment_score_entries e where e.subject_result_id=resultid and not exists(
      select 1 from jsonb_array_elements(coalesce(subject_item->'components','[]'::jsonb)) x where public.safe_uuid(x->>'component_id')=e.component_id);
    for component_item in select value from jsonb_array_elements(coalesce(subject_item->'components','[]'::jsonb)) loop
      componentid:=public.safe_uuid(component_item->>'component_id'); scorevalue:=public.safe_numeric(component_item->>'raw_score');
      if componentid is null then raise exception 'An assessment component identifier is invalid'; end if;
      select ac.maximum_score into maxscore from public.assessment_components ac where ac.id=componentid and ac.scheme_id=schemeid;
      if maxscore is null then raise exception 'An assessment component is invalid'; end if;
      if btrim(coalesce(component_item->>'raw_score',''))<>'' and scorevalue is null then raise exception 'An assessment score is invalid'; end if;
      scorevalue:=coalesce(scorevalue,0);
      if scorevalue<0 or scorevalue>maxscore then raise exception 'An assessment score is outside its allowed range'; end if;
      insert into public.assessment_score_entries(subject_result_id,component_id,raw_score,created_by)
      values(resultid,componentid,scorevalue,auth.uid())
      on conflict(subject_result_id,component_id) do update set raw_score=excluded.raw_score,updated_at=now();
    end loop;
    perform public.refresh_subject_result(resultid); subject_changed:=true;
  end loop;
  if not field_changed and not subject_changed then raise exception 'No authorised report changes were supplied'; end if;
  if not report_created then update public.student_reports set version=version+1,updated_at=now() where id=rid returning version into current_version;
  else select version into current_version from public.student_reports where id=rid; end if;
  update public.student_reports set report_number=coalesce(report_number,public.generate_report_number(rid)),updated_at=now() where id=rid;
  after_snapshot:=public.build_report_snapshot(rid);
  insert into public.report_revisions(report_id,version,snapshot,reason,actor_id) values(rid,current_version,after_snapshot,coalesce(nullif(payload->>'reason',''),'Saved'),auth.uid())
    on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now();
  for delegationid in select distinct x from unnest(delegation_ids) x where x is not null loop
    insert into public.emergency_academic_delegation_events(delegation_id,event_type,actor_id,report_id,event_reason,event_data)
    values(delegationid,'report_saved',auth.uid(),rid,coalesce(nullif(payload->>'reason',''),'Report saved under emergency delegation'),
      jsonb_build_object('before',before_snapshot,'after',after_snapshot,'changed_subject_ids',to_jsonb(seen_subjects),'class_fields_changed',field_changed));
  end loop;
  return public.get_report_editor(rid,null,null);
end $function$

CREATE OR REPLACE FUNCTION public.save_report_card_template(target_range_key text, target_storage_path text, target_original_name text, target_mime_type text, target_file_size bigint, target_checksum text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result public.report_card_templates;
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  if target_range_key not in ('early_years','basic_1_6','basic_7_9') then raise exception 'Invalid report-card class range'; end if;
  if coalesce(btrim(target_storage_path),'')='' or target_storage_path not like target_range_key||'/%' then raise exception 'Invalid template storage path'; end if;
  if coalesce(btrim(target_original_name),'')='' or length(target_original_name)>255 then raise exception 'Invalid template file name'; end if;
  if target_mime_type not in ('application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception 'Unsupported template file type'; end if;
  if coalesce(target_file_size,0)<=0 or target_file_size>20971520 then raise exception 'Template file must be between 1 byte and 20 MB'; end if;
  if coalesce(length(target_checksum),0)>128 then raise exception 'Invalid template checksum'; end if;
  insert into public.report_card_templates(
    range_key,storage_path,original_name,mime_type,file_size,checksum,version,active,uploaded_by
  ) values(
    target_range_key,btrim(target_storage_path),btrim(target_original_name),target_mime_type,target_file_size,coalesce(target_checksum,''),1,true,auth.uid()
  )
  on conflict(range_key) do update set
    storage_path=excluded.storage_path,
    original_name=excluded.original_name,
    mime_type=excluded.mime_type,
    file_size=excluded.file_size,
    checksum=excluded.checksum,
    version=public.report_card_templates.version+1,
    active=true,
    uploaded_by=auth.uid(),
    updated_at=now()
  returning * into result;
  return to_jsonb(result);
end $function$

CREATE OR REPLACE FUNCTION public.save_report_comments(target_report_id uuid, teacher_comment_text text DEFAULT NULL::text, head_comment_text text DEFAULT NULL::text, expected_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_version integer;current_status public.report_status;can_teacher boolean;can_principal boolean;
begin
  select version,status into current_version,current_status from public.student_reports where id=target_report_id and deleted_at is null for update;
  if current_status is null then raise exception 'Report not found'; end if;
  if expected_version is not null and expected_version<>current_version then raise exception 'This report was changed by another user. Refresh before saving comments.' using errcode='40001'; end if;
  if current_status in ('published','withdrawn') then raise exception 'Published report comments are locked'; end if;
  can_teacher:=current_status in ('draft','returned') and public.can_manage_class_report_fields(public.report_class_id(target_report_id));
  can_principal:=current_status in ('submitted','class_reviewed','approved') and public.current_app_role()='principal';
  if teacher_comment_text is not null and not can_teacher then raise exception 'Only the assigned Class Teacher can save the class teacher comment' using errcode='42501'; end if;
  if head_comment_text is not null and not can_principal then raise exception 'Only the Principal can save the Principal comment' using errcode='42501'; end if;
  if teacher_comment_text is null and head_comment_text is null then raise exception 'No comment change supplied'; end if;
  if can_principal then perform public.require_sensitive_access(); end if;
  perform set_config('app.report_write','on',true);
  perform set_config('app.change_reason','Report comments updated',true);
  update public.student_reports set
    teacher_comment=case when teacher_comment_text is not null then teacher_comment_text else teacher_comment end,
    head_comment=case when head_comment_text is not null then head_comment_text else head_comment end,
    version=version+1,updated_at=now()
  where id=target_report_id;
  insert into public.report_revisions(report_id,version,snapshot,reason,actor_id)
  values(target_report_id,(select version from public.student_reports where id=target_report_id),public.build_report_snapshot(target_report_id),'Report comments updated',auth.uid())
  on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now();
  return public.get_report_editor(target_report_id,null,null);
end $function$

CREATE OR REPLACE FUNCTION public.save_retention_policy(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.data_retention_policies;
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can manage retention policies' using errcode='42501'; end if;
  insert into public.data_retention_policies(data_category,retention_years,legal_basis,disposition_action,notes,active,updated_by)
  values(btrim(payload->>'data_category'),nullif(payload->>'retention_years','')::integer,coalesce(payload->>'legal_basis',''),coalesce(nullif(payload->>'disposition_action',''),'review'),coalesce(payload->>'notes',''),coalesce((payload->>'active')::boolean,true),auth.uid())
  on conflict(data_category) do update set retention_years=excluded.retention_years,legal_basis=excluded.legal_basis,disposition_action=excluded.disposition_action,notes=excluded.notes,active=excluded.active,updated_by=auth.uid(),updated_at=now()
  returning * into row_data;
  return to_jsonb(row_data);
end $function$

CREATE OR REPLACE FUNCTION public.save_school_prospectus(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare pid uuid:=public.safe_uuid(payload->>'id');yearid uuid:=public.safe_uuid(payload->>'academic_year_id');range_code text:=lower(btrim(coalesce(payload->>'class_range','')));title_value text:=btrim(coalesce(payload->>'title','School Prospectus'));currency_value text:=upper(btrim(coalesce(payload->>'currency_code','GHS')));effective date;notes_value text:=btrim(coalesce(payload->>'general_notes',''));expected timestamptz:=public.safe_timestamptz(payload->>'updated_at');current_row public.school_prospectuses%rowtype;result public.school_prospectuses%rowtype;
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can manage school prospectuses' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;
 if yearid is null or not exists(select 1 from public.academic_years where id=yearid and deleted_at is null) then raise exception 'Select a valid academic year';end if;if range_code not in ('early_years','basic_1_6','basic_7_9') then raise exception 'Select a valid prospectus class range';end if;if title_value='' or length(title_value)>180 then raise exception 'Prospectus title is required and must be 180 characters or fewer';end if;if currency_value!~'^[A-Z]{3}$' then raise exception 'Currency must use a three-letter code such as GHS';end if;if length(notes_value)>5000 then raise exception 'General notes are too long';end if;begin effective:=nullif(payload->>'effective_date','')::date;exception when others then raise exception 'Effective date is invalid';end;
 if pid is null then insert into public.school_prospectuses(academic_year_id,class_range,title,currency_code,effective_date,general_notes,created_by,updated_by) values(yearid,range_code,title_value,currency_value,effective,notes_value,auth.uid(),auth.uid()) returning * into result;insert into public.school_prospectus_sections(prospectus_id,section_type,title,display_order,created_by,updated_by) values(result.id,'main_fees','Main Fees',10,auth.uid(),auth.uid()),(result.id,'other_items','Other Items (One-off / Per Term)',20,auth.uid(),auth.uid()),(result.id,'parent_provided','To Be Provided by Parent',30,auth.uid(),auth.uid()),(result.id,'transportation','Transportation',40,auth.uid(),auth.uid()),(result.id,'policies','Important Policy Notes',50,auth.uid(),auth.uid());
 else select * into current_row from public.school_prospectuses where id=pid for update;if current_row.id is null then raise exception 'Prospectus not found';end if;if current_row.status='archived' then raise exception 'Archived prospectuses cannot be edited. Copy it to a new academic year instead.';end if;if expected is not null and current_row.updated_at is distinct from expected then raise exception 'This prospectus changed in another session. Reload and try again.' using errcode='40001';end if;update public.school_prospectuses set academic_year_id=yearid,class_range=range_code,title=title_value,currency_code=currency_value,effective_date=effective,general_notes=notes_value,status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid returning * into result;end if;
 return public.build_school_prospectus_snapshot(result.id);
end$function$

CREATE OR REPLACE FUNCTION public.save_school_prospectus_item(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare iid uuid:=public.safe_uuid(payload->>'id');sid uuid:=public.safe_uuid(payload->>'section_id');kind text:=lower(btrim(coalesce(payload->>'charge_basis','per_term')));name_value text:=btrim(coalesce(payload->>'item_name',''));description_value text:=btrim(coalesce(payload->>'description',''));unit_value text:=btrim(coalesce(payload->>'unit',''));notes_value text:=btrim(coalesce(payload->>'notes',''));amount_value numeric;quantity_value numeric;units_value numeric;sort_value integer:=coalesce(nullif(payload->>'display_order','')::integer,100);include_value boolean:=coalesce((payload->>'include_in_total')::boolean,true);required_value boolean:=coalesce((payload->>'required')::boolean,true);pid uuid;section_kind text;status_value text;row public.school_prospectus_items%rowtype;
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can manage prospectus items' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;if sid is null then raise exception 'Prospectus section is required';end if;select s.prospectus_id,s.section_type,p.status into pid,section_kind,status_value from public.school_prospectus_sections s join public.school_prospectuses p on p.id=s.prospectus_id where s.id=sid for update of p;if pid is null then raise exception 'Prospectus section not found';end if;if status_value='archived' then raise exception 'Archived prospectuses cannot be edited';end if;if kind not in ('free','one_off','per_day','per_week','per_month','per_term','per_academic_year','per_occurrence','optional','parent_provides','informational') then raise exception 'Invalid charging basis';end if;if name_value='' or length(name_value)>220 then raise exception 'Item name is required and must be 220 characters or fewer';end if;if length(description_value)>2000 or length(notes_value)>2000 then raise exception 'Prospectus item description or notes are too long';end if;
 begin amount_value:=nullif(payload->>'amount','')::numeric;quantity_value:=nullif(payload->>'quantity','')::numeric;units_value:=nullif(payload->>'calculation_units','')::numeric;exception when others then raise exception 'Amount, quantity, or calculation units are invalid';end;if amount_value is not null and amount_value<0 then raise exception 'Amount cannot be negative';end if;if quantity_value is not null and quantity_value<=0 then raise exception 'Quantity must be greater than zero';end if;if units_value is not null and units_value<=0 then raise exception 'Calculation units must be greater than zero';end if;if section_kind in ('main_fees','other_items','transportation') and kind not in ('free','optional','informational') and amount_value is null then raise exception 'Enter an amount or mark the item Free/Optional';end if;if kind in ('free','parent_provides','informational') then include_value:=false;if kind='free' then amount_value:=null;end if;end if;if kind in ('per_day','per_week','per_month','per_occurrence') and units_value is null then include_value:=false;end if;
 if iid is null then insert into public.school_prospectus_items(section_id,item_name,description,amount,charge_basis,quantity,unit,calculation_units,include_in_total,required,notes,display_order,created_by,updated_by) values(sid,name_value,description_value,amount_value,kind,quantity_value,unit_value,units_value,include_value,required_value,notes_value,sort_value,auth.uid(),auth.uid()) returning * into row;else update public.school_prospectus_items set section_id=sid,item_name=name_value,description=description_value,amount=amount_value,charge_basis=kind,quantity=quantity_value,unit=unit_value,calculation_units=units_value,include_in_total=include_value,required=required_value,notes=notes_value,display_order=sort_value,updated_by=auth.uid(),updated_at=now() where id=iid returning * into row;if row.id is null then raise exception 'Prospectus item not found';end if;end if;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;return to_jsonb(row);
end$function$

CREATE OR REPLACE FUNCTION public.save_school_prospectus_section(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid:=public.safe_uuid(payload->>'id');pid uuid:=public.safe_uuid(payload->>'prospectus_id');kind text:=lower(btrim(coalesce(payload->>'section_type','custom')));title_value text:=btrim(coalesce(payload->>'title',''));instructions_value text:=btrim(coalesce(payload->>'instructions',''));sort_value integer:=coalesce(nullif(payload->>'display_order','')::integer,100);p public.school_prospectuses%rowtype;row public.school_prospectus_sections%rowtype;
begin
 if not public.is_system_admin() then raise exception 'Only the System Administrator can manage prospectus sections' using errcode='42501';end if;perform public.require_sensitive_access();perform public.require_license_feature('school_prospectus');if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit prospectus changes' using errcode='42501';end if;if pid is null then raise exception 'Prospectus is required';end if;select * into p from public.school_prospectuses where id=pid for update;if p.id is null then raise exception 'Prospectus not found';end if;if p.status='archived' then raise exception 'Archived prospectuses cannot be edited';end if;if kind not in ('main_fees','other_items','parent_provided','transportation','policies','custom') then raise exception 'Invalid prospectus section type';end if;if title_value='' or length(title_value)>180 then raise exception 'Section title is required';end if;if length(instructions_value)>3000 then raise exception 'Section instructions are too long';end if;
 if sid is null then insert into public.school_prospectus_sections(prospectus_id,section_type,title,instructions,display_order,created_by,updated_by) values(pid,kind,title_value,instructions_value,sort_value,auth.uid(),auth.uid()) returning * into row;else update public.school_prospectus_sections set section_type=kind,title=title_value,instructions=instructions_value,display_order=sort_value,updated_by=auth.uid(),updated_at=now() where id=sid and prospectus_id=pid returning * into row;if row.id is null then raise exception 'Prospectus section not found';end if;end if;update public.school_prospectuses set status=case when status='published' then 'draft' else status end,updated_by=auth.uid(),updated_at=now() where id=pid;return to_jsonb(row);
end$function$

CREATE OR REPLACE FUNCTION public.save_security_verification(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.security_verification_runs;
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can record security verification' using errcode='42501'; end if;
  insert into public.security_verification_runs(standard_name,scope,status,summary,findings,next_review_at)
  values(coalesce(nullif(payload->>'standard_name',''),'OWASP ASVS 5.0'),btrim(payload->>'scope'),payload->>'status',coalesce(payload->>'summary',''),coalesce(payload->'findings','[]'::jsonb),public.safe_timestamptz(payload->>'next_review_at')) returning * into row_data;
  return to_jsonb(row_data);
end $function$

CREATE OR REPLACE FUNCTION public.save_student(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  sid uuid; eid uuid; gid uuid; classid uuid; yearid uuid; guardian_auth_id uuid;
  student_data jsonb:=coalesce(payload->'student','{}'::jsonb);
  enrollment_data jsonb:=coalesce(payload->'enrollment','{}'::jsonb);
  guardian_data jsonb:=coalesce(payload->'guardian','{}'::jsonb);
  current_updated timestamptz; expected_updated timestamptz; birthdate date; rollno integer;
  requested_active boolean:=public.safe_boolean(enrollment_data->>'active',true);
  gender_value text:=coalesce(nullif(btrim(student_data->>'gender'),''),'Other');
  status_value text:=coalesce(nullif(btrim(student_data->>'status'),''),'active');
  admission text:=upper(btrim(coalesce(student_data->>'admission_no','')));
  affected integer:=0;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not public.is_system_admin() then raise exception 'Only the System Administrator can create or edit student records' using errcode='42501'; end if;
  sid:=public.safe_uuid(student_data->>'id'); classid:=public.safe_uuid(enrollment_data->>'class_id');
  yearid:=public.safe_uuid(enrollment_data->>'academic_year_id'); guardian_auth_id:=public.safe_uuid(guardian_data->>'auth_user_id');
  expected_updated:=public.safe_timestamptz(student_data->>'updated_at'); birthdate:=public.safe_date(student_data->>'date_of_birth');
  rollno:=public.safe_integer(enrollment_data->>'roll_number');
  if btrim(coalesce(student_data->>'id',''))<>'' and sid is null then raise exception 'Student record identifier is invalid'; end if;
  if btrim(coalesce(enrollment_data->>'class_id',''))<>'' and classid is null then raise exception 'Selected class is invalid'; end if;
  if btrim(coalesce(enrollment_data->>'academic_year_id',''))<>'' and yearid is null then raise exception 'Selected academic year is invalid'; end if;
  if btrim(coalesce(guardian_data->>'auth_user_id',''))<>'' and guardian_auth_id is null then raise exception 'Selected guardian portal account is invalid'; end if;
  if btrim(coalesce(student_data->>'date_of_birth',''))<>'' and birthdate is null then raise exception 'Date of birth is invalid'; end if;
  if btrim(coalesce(enrollment_data->>'roll_number',''))<>'' and rollno is null then raise exception 'Roll number is invalid'; end if;
  if btrim(coalesce(student_data->>'first_name',''))='' or btrim(coalesce(student_data->>'last_name',''))='' then raise exception 'First name and last name are required'; end if;
  if gender_value not in ('Male','Female','Other') then raise exception 'Gender selection is invalid'; end if;
  if status_value not in ('active','graduated','withdrawn','suspended') then raise exception 'Student status is invalid'; end if;
  if btrim(coalesce(guardian_data->>'email',''))<>'' and guardian_data->>'email' !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Guardian email address is invalid'; end if;
  if birthdate>current_date then raise exception 'Date of birth cannot be in the future'; end if;
  if rollno is not null and rollno<1 then raise exception 'Roll number must be greater than zero'; end if;
  if (classid is null)<>(yearid is null) then raise exception 'Academic year and class must be selected together'; end if;
  if sid is null then
    if admission='' or exists(select 1 from public.students s where lower(s.admission_no::text)=lower(admission)) then admission:=public.generate_school_identifier('student'); end if;
  else
    if not public.can_manage_student(sid) then raise exception 'Access denied' using errcode='42501'; end if;
    select updated_at into current_updated from public.students where id=sid and deleted_at is null for update;
    if not found then raise exception 'Student record not found'; end if;
    if expected_updated is not null and current_updated is distinct from expected_updated then raise exception 'Student record changed by another user' using errcode='40001'; end if;
    if admission='' then raise exception 'Admission number is required'; end if;
  end if;
  if classid is not null then
    if not exists(select 1 from public.classes c where c.id=classid and c.active and c.deleted_at is null) then raise exception 'Selected class is not active'; end if;
    if not exists(select 1 from public.academic_years y where y.id=yearid and y.deleted_at is null) then raise exception 'Selected academic year is unavailable'; end if;
  end if;
  if exists(select 1 from public.students s where lower(s.admission_no::text)=lower(admission) and (sid is null or s.id<>sid)) then raise exception 'Admission number already exists'; end if;
  if rollno is not null and exists(select 1 from public.enrollments e where e.academic_year_id=yearid and e.class_id=classid and e.roll_number=rollno and e.deleted_at is null and (sid is null or e.student_id<>sid)) then raise exception 'Roll number is already assigned in the selected class'; end if;
  if guardian_auth_id is not null and not exists(select 1 from public.profiles p where p.id=guardian_auth_id and p.active and public.current_app_role_for(p.role)='parent_guardian') then raise exception 'Selected portal account is not an active parent or guardian account'; end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Student record update'),true);
  if sid is null then
    insert into public.students(admission_no,first_name,middle_name,last_name,gender,date_of_birth,guardian_name,guardian_phone,guardian_email,photo_url,status,updated_at)
    values(admission,btrim(student_data->>'first_name'),btrim(coalesce(student_data->>'middle_name','')),btrim(student_data->>'last_name'),
      gender_value,birthdate,btrim(coalesce(guardian_data->>'full_name','')),btrim(coalesce(guardian_data->>'phone','')),
      btrim(coalesce(guardian_data->>'email','')),coalesce(student_data->>'photo_url',''),status_value::public.student_status,now()) returning id into sid;
  else
    update public.students set admission_no=admission,first_name=btrim(student_data->>'first_name'),
      middle_name=btrim(coalesce(student_data->>'middle_name','')),last_name=btrim(student_data->>'last_name'),gender=gender_value,
      date_of_birth=birthdate,guardian_name=btrim(coalesce(guardian_data->>'full_name',guardian_name)),
      guardian_phone=btrim(coalesce(guardian_data->>'phone',guardian_phone)),guardian_email=btrim(coalesce(guardian_data->>'email',guardian_email)),
      photo_url=coalesce(student_data->>'photo_url',photo_url),status=status_value::public.student_status,updated_at=now()
    where id=sid and deleted_at is null;
    get diagnostics affected=row_count; if affected<>1 then raise exception 'Student record was not updated'; end if;
  end if;
  if classid is not null then
    insert into public.enrollments(student_id,academic_year_id,class_id,roll_number,active,deleted_at,updated_at)
    values(sid,yearid,classid,rollno,requested_active,null,now())
    on conflict(student_id,academic_year_id) do update set class_id=excluded.class_id,roll_number=excluded.roll_number,
      active=excluded.active,deleted_at=null,updated_at=now() returning id into eid;
    if requested_active then update public.enrollments set active=(id=eid),updated_at=now() where student_id=sid and deleted_at is null; end if;
  end if;
  if btrim(coalesce(guardian_data->>'full_name',''))<>'' then
    gid:=public.safe_uuid(guardian_data->>'id');
    if btrim(coalesce(guardian_data->>'id',''))<>'' and gid is null then raise exception 'Guardian record identifier is invalid'; end if;
    if gid is null then
      insert into public.student_guardians(full_name,relationship,phone,email,address,is_primary,updated_at)
      values(btrim(guardian_data->>'full_name'),coalesce(nullif(btrim(guardian_data->>'relationship'),''),'Guardian'),
        btrim(coalesce(guardian_data->>'phone','')),nullif(btrim(coalesce(guardian_data->>'email','')),'')::citext,
        btrim(coalesce(guardian_data->>'address','')),public.safe_boolean(guardian_data->>'is_primary',true),now()) returning id into gid;
    else
      if not exists(select 1 from public.guardian_links gl where gl.guardian_id=gid and gl.student_id=sid) then raise exception 'Guardian record does not belong to this student'; end if;
      update public.student_guardians set full_name=btrim(guardian_data->>'full_name'),relationship=coalesce(nullif(btrim(guardian_data->>'relationship'),''),'Guardian'),
        phone=btrim(coalesce(guardian_data->>'phone','')),email=nullif(btrim(coalesce(guardian_data->>'email','')),'')::citext,
        address=btrim(coalesce(guardian_data->>'address','')),is_primary=public.safe_boolean(guardian_data->>'is_primary',false),updated_at=now() where id=gid;
    end if;
    insert into public.guardian_links(guardian_id,student_id,auth_user_id,can_view_reports,can_receive_notifications)
    values(gid,sid,guardian_auth_id,public.safe_boolean(guardian_data->>'can_view_reports',true),public.safe_boolean(guardian_data->>'can_receive_notifications',true))
    on conflict(guardian_id,student_id) do update set auth_user_id=excluded.auth_user_id,can_view_reports=excluded.can_view_reports,
      can_receive_notifications=excluded.can_receive_notifications;
  end if;
  return public.get_student_record_v5(sid);
exception when unique_violation then raise exception 'A student, enrolment, roll number, or guardian link already uses these details';
end $function$

CREATE OR REPLACE FUNCTION public.save_teacher(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=public.safe_uuid(payload->>'id');profileid uuid:=public.safe_uuid(payload->>'profile_id');staff text:=upper(btrim(coalesce(payload->>'staff_no','')));emis text:=upper(btrim(coalesce(payload->>'emis_code','')));current_updated timestamptz;expected_updated timestamptz:=public.safe_timestamptz(payload->>'updated_at');joined date:=public.safe_date(payload->>'date_joined');dob date:=public.safe_date(payload->>'date_of_birth');employment text:=coalesce(nullif(btrim(payload->>'employment_status'),''),'active');gender_value text:=coalesce(nullif(btrim(payload->>'gender'),''),'Other');qualification_value text:=btrim(coalesce(payload->>'qualification',''));linked_role text;affected integer;legacy_qualification text;
begin
  if auth.uid() is null or not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501';end if;
  if btrim(coalesce(payload->>'id',''))<>'' and tid is null then raise exception 'Teacher record identifier is invalid';end if;if btrim(coalesce(payload->>'profile_id',''))<>'' and profileid is null then raise exception 'Linked user account is invalid';end if;
  if btrim(coalesce(payload->>'date_joined',''))<>'' and joined is null then raise exception 'Date joined is invalid';end if;if btrim(coalesce(payload->>'date_of_birth',''))<>'' and dob is null then raise exception 'Date of birth is invalid';end if;
  if btrim(coalesce(payload->>'first_name',''))='' or btrim(coalesce(payload->>'last_name',''))='' then raise exception 'First name and last name are required';end if;if gender_value not in ('Male','Female','Other') then raise exception 'Gender selection is invalid';end if;
  if btrim(coalesce(payload->>'email',''))<>'' and payload->>'email' !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Teacher email address is invalid';end if;if employment not in ('active','leave','suspended','resigned','retired') then raise exception 'Employment status is invalid';end if;
  if joined>current_date then raise exception 'Date joined cannot be in the future';end if;if dob>current_date then raise exception 'Date of birth cannot be in the future';end if;if joined is not null and dob is not null and joined<=dob then raise exception 'Date joined must be after date of birth';end if;
  if tid is not null then select updated_at,qualification into current_updated,legacy_qualification from public.teachers where id=tid and deleted_at is null for update;if not found then raise exception 'Teacher record not found';end if;if expected_updated is not null and current_updated is distinct from expected_updated then raise exception 'Teacher record changed by another user' using errcode='40001';end if;end if;
  if qualification_value<>'' and qualification_value not in ('PhD','MSc Degree','Bachelor Degree','HND','Diploma','SHS') and (tid is null or qualification_value is distinct from legacy_qualification) then raise exception 'Qualification must be selected from the approved qualification list';end if;
  if tid is null and (staff='' or exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff))) then staff:=public.generate_school_identifier('teacher');end if;if staff='' then staff:=public.generate_school_identifier('teacher');end if;
  if exists(select 1 from public.teachers t where lower(t.staff_no::text)=lower(staff) and (tid is null or t.id<>tid)) or exists(select 1 from public.headteachers h where lower(h.staff_no::text)=lower(staff)) then raise exception 'Staff number already exists';end if;
  if emis<>'' and exists(select 1 from public.teachers t where t.deleted_at is null and lower(coalesce(t.emis_code::text,''))=lower(emis) and (tid is null or t.id<>tid)) then raise exception 'EMIS code already exists';end if;
  if profileid is not null then select public.current_app_role_for(p.role) into linked_role from public.profiles p where p.id=profileid and p.active;if linked_role is null then raise exception 'Selected user account is unavailable';end if;if linked_role not in ('class_teacher','subject_teacher') then raise exception 'Selected user account does not have a teacher role';end if;if exists(select 1 from public.teachers t where t.profile_id=profileid and t.deleted_at is null and (tid is null or t.id<>tid)) or exists(select 1 from public.headteachers h where h.profile_id=profileid and h.deleted_at is null) then raise exception 'This user account is already linked to another staff record';end if;end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Teacher record update'),true);
  if tid is null then
    insert into public.teachers(profile_id,staff_no,emis_code,first_name,middle_name,last_name,gender,date_of_birth,phone,email,address,qualification,specialization,date_joined,employment_status,notes,active,created_by,updated_at)
    values(profileid,staff,nullif(emis,'')::citext,btrim(payload->>'first_name'),btrim(coalesce(payload->>'middle_name','')),btrim(payload->>'last_name'),gender_value,dob,btrim(coalesce(payload->>'phone','')),nullif(btrim(coalesce(payload->>'email','')),'')::citext,btrim(coalesce(payload->>'address','')),qualification_value,btrim(coalesce(payload->>'specialization','')),joined,employment,btrim(coalesce(payload->>'notes','')),public.safe_boolean(payload->>'active',true),auth.uid(),now()) returning id into tid;
  else
    update public.teachers set profile_id=profileid,staff_no=staff,emis_code=nullif(emis,'')::citext,first_name=btrim(payload->>'first_name'),middle_name=btrim(coalesce(payload->>'middle_name','')),last_name=btrim(payload->>'last_name'),gender=gender_value,date_of_birth=dob,phone=btrim(coalesce(payload->>'phone','')),email=nullif(btrim(coalesce(payload->>'email','')),'')::citext,address=btrim(coalesce(payload->>'address','')),qualification=qualification_value,specialization=btrim(coalesce(payload->>'specialization','')),date_joined=joined,employment_status=employment,notes=btrim(coalesce(payload->>'notes','')),active=public.safe_boolean(payload->>'active',true),updated_at=now() where id=tid and deleted_at is null;
    get diagnostics affected=row_count;if affected<>1 then raise exception 'Teacher record was not updated';end if;
  end if;
  return public.get_teacher_record(tid);
exception when unique_violation then raise exception 'Staff number, EMIS code, or linked user account is already in use';
end$function$

CREATE OR REPLACE FUNCTION public.save_teacher_award_category(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cid uuid:=public.safe_uuid(payload->>'id'); result public.teacher_award_categories;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can manage award categories' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'name',''))='' then raise exception 'Award category name is required'; end if;
  if cid is null then
    insert into public.teacher_award_categories(code,name,default_citation,active)
    values(upper(regexp_replace(btrim(payload->>'name'),'[^A-Za-z0-9]+','_','g')),btrim(payload->>'name'),btrim(coalesce(payload->>'default_citation','')),coalesce((payload->>'active')::boolean,true)) returning * into result;
  else
    update public.teacher_award_categories set name=btrim(payload->>'name'),default_citation=btrim(coalesce(payload->>'default_citation','')),active=coalesce((payload->>'active')::boolean,active),updated_at=now() where id=cid returning * into result;
  end if;
  return to_jsonb(result);
end $function$

CREATE OR REPLACE FUNCTION public.school_restore_apply_table(target_job uuid, target_table text, target_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare staged integer; expected_stage_count constant integer:=54; current_stage_count integer; begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; staged:=public.school_restore_stage_table(target_job,target_table,target_rows); if target_table='import_errors' then select count(*) into current_stage_count from public.school_restore_stage_tables where job_id=target_job; if current_stage_count<>expected_stage_count then raise exception 'r29 legacy restore staging incomplete: expected % tables, found %',expected_stage_count,current_stage_count; end if; delete from public.id_card_deletion_tombstones where true; perform public.school_restore_commit_staged(target_job); end if; return staged; end$function$

CREATE OR REPLACE FUNCTION public.school_restore_begin(target_filename text, target_path text, target_checksum text, target_size bigint, target_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_id uuid;
begin
 if auth.role() <> 'service_role' then raise exception 'service role required'; end if;
 insert into public.school_restore_jobs(source_filename,import_path,package_checksum,package_size,initiated_by)
 values(left(coalesce(target_filename,''),300),left(coalesce(target_path,''),1000),lower(coalesce(target_checksum,'')),greatest(coalesce(target_size,0),0),target_actor)
 returning id into v_id;
 return v_id;
end$function$

CREATE OR REPLACE FUNCTION public.school_restore_clear_operational_data(target_job uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; delete from public.school_restore_stage_tables where job_id=target_job; update public.school_restore_jobs set status='restoring',restored_table_counts='{}'::jsonb, verification_notes='r29 atomic restore staging initialized; production database has not been cleared.', updated_at=now() where id=target_job; end$function$

CREATE OR REPLACE FUNCTION public.school_restore_commit_staged(target_job uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare insert_tables constant text[]:=array[ 'school_settings','profiles','id_card_settings','id_card_deletion_tombstones','teachers','headteachers','academic_years','terms','classes','subjects','class_subjects','class_timetable_entries','school_prospectuses','school_prospectus_sections','school_prospectus_items','school_prospectus_revisions','user_class_access','students','student_guardians','guardian_links','enrollments','student_id_cards','id_card_events','staff_id_cards','staff_id_card_events','class_attendance_registers','student_attendance_entries','grading_scales','assessment_schemes','assessment_components','student_reports','subject_scores','subject_results','assessment_score_entries','emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls','student_lifecycle_events','transcript_issuances','certificate_templates','teacher_award_categories','certificate_batches','certificates','certificate_events','report_workflow_events','report_revisions','report_publications','report_correction_requests','report_correction_events','report_card_templates','notifications','notification_outbox','import_batches','import_errors' ]; clear_tables constant text[]:=array[ 'school_prospectus_revisions','school_prospectus_items','school_prospectus_sections','school_prospectuses','staff_id_card_events','staff_id_cards','id_card_events','student_id_cards','class_timetable_entries','id_card_settings','certificate_events','certificates','certificate_batches','teacher_award_categories','report_card_templates','certificate_templates','transcript_issuances','report_publications','report_revisions','report_workflow_events','report_correction_events','report_correction_requests','assessment_score_entries','subject_results','subject_scores','student_reports','student_attendance_entries','class_attendance_registers','emergency_academic_delegation_events','emergency_academic_delegations','academic_period_controls','student_lifecycle_events','guardian_links','student_guardians','enrollments','students','user_class_access','class_subjects','assessment_components','assessment_schemes','grading_scales','subjects','classes','terms','academic_years','headteachers','teachers','notifications','notification_outbox','import_errors','import_batches' ]; t text; target_rows jsonb; cols text; sels text; expected integer; actual integer; matched integer; staged_count integer; restored jsonb:='{}'::jsonb; max_card_sequence bigint; begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; perform pg_advisory_xact_lock(hashtext('rce-school-restore-r29')); if not exists(select 1 from public.school_restore_jobs where id=target_job) then raise exception 'restore job not found'; end if; select count(*) into staged_count from public.school_restore_stage_tables where job_id=target_job and table_name=any(insert_tables); if staged_count<>array_length(insert_tables,1) then raise exception 'restore staging is incomplete: expected % tables, found %',array_length(insert_tables,1),staged_count; end if; perform set_config('app.audit_suppress','on',true); perform set_config('app.report_write','on',true); perform set_config('app.restore_mode','on',true); perform set_config('app.change_reason','Full school restoration r29',true); update public.school_restore_jobs set status='restoring',restored_table_counts='{}'::jsonb,updated_at=now() where id=target_job; foreach t in array clear_tables loop if to_regclass('public.'||t) is not null then execute format('alter table public.%I disable trigger user',t); execute format('delete from public.%I where true',t); execute format('alter table public.%I enable trigger user',t); end if; end loop; foreach t in array insert_tables loop select s.rows,s.row_count into target_rows,expected from public.school_restore_stage_tables s where s.job_id=target_job and s.table_name=t; if target_rows is null or jsonb_typeof(target_rows)<>'array' then raise exception 'restore staging is missing or invalid for %',t; end if; execute format('alter table public.%I disable trigger user',t); if t='school_settings' then if expected>0 then update public.school_settings s set school_name=coalesce(x.school_name,s.school_name),motto=coalesce(x.motto,s.motto),address=coalesce(x.address,s.address),phone=coalesce(x.phone,s.phone),email=coalesce(x.email,s.email),website=coalesce(x.website,s.website),logo_url=coalesce(x.logo_url,s.logo_url),report_title=coalesce(x.report_title,s.report_title),report_footer=coalesce(x.report_footer,s.report_footer),head_name=coalesce(x.head_name,s.head_name),timezone=coalesce(x.timezone,s.timezone),locale=coalesce(x.locale,s.locale),report_number_prefix=coalesce(x.report_number_prefix,s.report_number_prefix),primary_colour=coalesce(x.primary_colour,s.primary_colour),accent_colour=coalesce(x.accent_colour,s.accent_colour),verification_base_url=coalesce(x.verification_base_url,s.verification_base_url),created_at=coalesce(x.created_at,s.created_at),updated_at=coalesce(x.updated_at,s.updated_at),report_body_font=coalesce(x.report_body_font,s.report_body_font),report_body_font_size=coalesce(x.report_body_font_size,s.report_body_font_size),promotion_cutoff_score=coalesce(x.promotion_cutoff_score,s.promotion_cutoff_score),backup_retention_days=coalesce(x.backup_retention_days,s.backup_retention_days),backup_minimum_copies=coalesce(x.backup_minimum_copies,s.backup_minimum_copies),user_email_domain=coalesce(x.user_email_domain,s.user_email_domain),certificate_footer_text=coalesce(x.certificate_footer_text,s.certificate_footer_text) from jsonb_to_record(target_rows->0) as x(school_name text,motto text,address text,phone text,email text,website text,logo_url text,report_title text,report_footer text,head_name text,timezone text,locale text,report_number_prefix text,primary_colour text,accent_colour text,verification_base_url text,created_at timestamptz,updated_at timestamptz,report_body_font text,report_body_font_size numeric,promotion_cutoff_score smallint,backup_retention_days integer,backup_minimum_copies integer,user_email_domain text,certificate_footer_text text) where s.id=(select ss.id from public.school_settings ss order by ss.created_at asc,ss.id asc limit 1); end if; else select string_agg(format('%I',a.attname),',' order by a.attnum),string_agg(format('r.%I',a.attname),',' order by a.attnum) into cols,sels from pg_attribute a where a.attrelid=to_regclass('public.'||t) and a.attnum>0 and not a.attisdropped and a.attgenerated='' and a.attidentity<>'a' and not(t='enrollments' and a.attname='promotion_source_report_id'); if cols is null or sels is null then raise exception 'restore column inventory unavailable for %',t; end if; if t='student_id_cards' then execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) r where not exists(select 1 from public.id_card_deletion_tombstones d where d.card_kind=''student'' and (d.card_number=r.card_number or d.verification_token=r.verification_token)) on conflict do nothing',t,cols,sels,t) using target_rows; elsif t='staff_id_cards' then execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) r where not exists(select 1 from public.id_card_deletion_tombstones d where d.card_kind=''staff'' and (d.card_number=r.card_number or d.verification_token=r.verification_token)) on conflict do nothing',t,cols,sels,t) using target_rows; else execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) r on conflict do nothing',t,cols,sels,t) using target_rows; end if; end if; execute format('alter table public.%I enable trigger user',t); if t='profiles' then execute 'select count(*) from public.profiles p join jsonb_to_recordset($1) x(id uuid) on p.id=x.id' into matched using target_rows; if matched<>expected then raise exception 'restore identity verification failed for profiles: expected % staged IDs, matched %',expected,matched; end if; select count(*) into actual from public.profiles; elsif t='id_card_deletion_tombstones' then execute 'select count(*) from jsonb_to_recordset($1) x(card_kind text,card_number text,verification_token uuid) where exists(select 1 from public.id_card_deletion_tombstones d where (d.card_kind=x.card_kind and d.card_number=x.card_number) or d.verification_token=x.verification_token)' into matched using target_rows; if matched<>expected then raise exception 'restore tombstone verification failed: expected % staged tombstones, matched %',expected,matched; end if; select count(*) into actual from public.id_card_deletion_tombstones; else execute format('select count(*) from public.%I',t) into actual; if actual<>expected then raise exception 'restore row-count verification failed for %: expected %, found %',t,expected,actual; end if; end if; restored:=jsonb_set(restored,array[t],to_jsonb(actual),true); end loop; select rows into target_rows from public.school_restore_stage_tables where job_id=target_job and table_name='enrollments'; execute 'alter table public.enrollments disable trigger user'; update public.enrollments e set promotion_source_report_id=x.promotion_source_report_id from jsonb_to_recordset(target_rows) as x(id uuid,promotion_source_report_id uuid) where e.id=x.id and e.promotion_source_report_id is distinct from x.promotion_source_report_id; execute 'alter table public.enrollments enable trigger user'; select rows into target_rows from public.school_restore_stage_tables where job_id=target_job and table_name='school_settings'; if jsonb_array_length(target_rows)>0 then execute 'alter table public.school_settings disable trigger user'; update public.school_settings s set certificate_completion_class_id=x.certificate_completion_class_id from jsonb_to_record(target_rows->0) as x(certificate_completion_class_id uuid) where s.id=(select ss.id from public.school_settings ss order by ss.created_at asc,ss.id asc limit 1); execute 'alter table public.school_settings enable trigger user'; end if; select row_count into expected from public.school_restore_stage_tables where job_id=target_job and table_name='enrollments'; select count(*) into actual from public.enrollments; if actual<>expected then raise exception 'restore row-count verification failed for enrollments after deferred link repair'; end if; select max(substring(card_number from '-([0-9]+)$')::bigint) into max_card_sequence from public.student_id_cards where card_number~'-[0-9]+$'; if max_card_sequence is not null then perform setval('public.student_id_card_number_seq',greatest(max_card_sequence,1),true); end if; select max(substring(card_number from '-([0-9]+)$')::bigint) into max_card_sequence from public.staff_id_cards where card_number~'-[0-9]+$'; if max_card_sequence is not null then perform setval('public.staff_id_card_number_seq',greatest(max_card_sequence,1),true); end if; update public.school_restore_jobs set restored_table_counts=restored,verification_notes='r29 atomic database restore committed with foreign-key enforcement and staged row-count verification.',updated_at=now() where id=target_job; delete from public.school_restore_stage_tables where job_id=target_job; return jsonb_build_object('status','database_restored','restored_table_counts',restored); end$function$

CREATE OR REPLACE FUNCTION public.school_restore_complete(target_job uuid, target_expected jsonb, target_storage jsonb, target_auth_expected integer, target_auth_reconciled integer, target_backup_key text, target_schema text, target_school_name text, target_school_code text, target_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; update public.school_restore_jobs set status='completed',expected_table_counts=coalesce(target_expected,'{}'::jsonb),expected_storage_counts=coalesce(target_storage,'{}'::jsonb),restored_storage_counts=coalesce(target_storage,'{}'::jsonb), auth_users_expected=greatest(coalesce(target_auth_expected,0),0),auth_users_reconciled=greatest(coalesce(target_auth_reconciled,0),0), backup_key=left(coalesce(target_backup_key,''),200),source_schema_version=left(coalesce(target_schema,''),50),source_school_name=left(coalesce(target_school_name,''),300),source_school_code=left(coalesce(target_school_code,''),100), verification_notes=left(coalesce(target_notes,''),8000),error_message='',completed_at=now(),updated_at=now() where id=target_job; end$function$

CREATE OR REPLACE FUNCTION public.school_restore_dashboard()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select jsonb_build_object(
  'jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.created_at desc) from (select * from public.school_restore_jobs order by created_at desc limit 25) j),'[]'::jsonb),
  'active',coalesce((select to_jsonb(j) from public.school_restore_jobs j where status in ('upload_pending','uploaded','validating','restoring') order by created_at desc limit 1),'null'::jsonb)
 )
 where public.current_app_role()::text='system_admin';
$function$

CREATE OR REPLACE FUNCTION public.school_restore_set_status(target_job uuid, target_status text, target_error text DEFAULT ''::text, target_notes text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; update public.school_restore_jobs set status=target_status,error_message=left(coalesce(target_error,''),4000),verification_notes=left(coalesce(target_notes,''),8000), started_at=case when target_status in ('validating','restoring') then coalesce(started_at,now()) else started_at end, completed_at=case when target_status in ('completed','failed','cancelled') then now() else completed_at end, updated_at=now() where id=target_job; if target_status in ('completed','failed','cancelled') then delete from public.school_restore_stage_tables where job_id=target_job; end if; end$function$

CREATE OR REPLACE FUNCTION public.school_restore_stage_table(target_job uuid, target_table text, target_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare allowed constant text[]:=array[ 'school_settings','profiles','id_card_settings','id_card_deletion_tombstones','teachers','headteachers', 'academic_years','terms','classes','subjects','class_subjects','class_timetable_entries', 'school_prospectuses','school_prospectus_sections','school_prospectus_items','school_prospectus_revisions', 'user_class_access','students','student_guardians','guardian_links','enrollments','student_id_cards','id_card_events', 'staff_id_cards','staff_id_card_events','class_attendance_registers','student_attendance_entries','grading_scales', 'assessment_schemes','assessment_components','student_reports','subject_scores','subject_results','assessment_score_entries', 'emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls', 'report_correction_requests','report_correction_events','student_lifecycle_events','transcript_issuances', 'certificate_templates','teacher_award_categories','certificate_batches','certificates','certificate_events', 'report_workflow_events','report_revisions','report_publications','report_card_templates','notifications','notification_outbox', 'import_batches','import_errors' ]; staged integer; begin if auth.role()<>'service_role' then raise exception 'service role required'; end if; if not(target_table=any(allowed)) then raise exception 'table is not restorable: %',target_table; end if; if jsonb_typeof(target_rows)<>'array' then raise exception 'rows must be an array'; end if; if not exists(select 1 from public.school_restore_jobs where id=target_job) then raise exception 'restore job not found'; end if; staged:=jsonb_array_length(target_rows); insert into public.school_restore_stage_tables(job_id,table_name,rows,row_count,staged_at) values(target_job,target_table,target_rows,staged,now()) on conflict(job_id,table_name) do update set rows=excluded.rows,row_count=excluded.row_count,staged_at=excluded.staged_at; return staged; end$function$

CREATE OR REPLACE FUNCTION public.search_students(search_text text DEFAULT ''::text, target_class_id uuid DEFAULT NULL::uuid, target_status student_status DEFAULT NULL::student_status, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
declare limit_value integer:=least(greatest(page_size,1),100);
begin
  return (
    with matching as (
      select s.id,s.admission_no,s.first_name,s.middle_name,s.last_name,s.gender,s.date_of_birth,
        s.photo_url,s.status,s.updated_at,e.id enrollment_id,e.class_id,e.academic_year_id,e.roll_number,
        c.name class_name,y.name academic_year_name,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) display_name
      from public.students s
      left join lateral (
        select en.* from public.enrollments en
        join public.academic_years ay on ay.id=en.academic_year_id and ay.deleted_at is null
        where en.student_id=s.id and en.deleted_at is null
        order by en.active desc,
          coalesce(ay.start_date,ay.end_date,en.created_at::date) desc,
          ay.name::text desc,en.created_at desc limit 1
      ) e on true
      left join public.classes c on c.id=e.class_id
      left join public.academic_years y on y.id=e.academic_year_id
      where s.deleted_at is null
        and (public.current_app_role() in ('system_admin','principal') or (e.id is not null and public.can_access_class(e.class_id,false)))
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or s.status=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x)-'display_name' order by lower(x.display_name),x.admission_no::text) from (
        select * from matching order by lower(display_name),admission_no::text limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),
      'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end $function$

CREATE OR REPLACE FUNCTION public.search_students_v5(search_text text DEFAULT ''::text, target_class_id uuid DEFAULT NULL::uuid, target_status student_status DEFAULT NULL::student_status, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
  limit_value integer:=least(greatest(page_size,1),100);
begin
  if archive_filter not in ('active','archived','all') then
    archive_filter:='active';
  end if;

  if archive_filter<>'active'
     and coalesce(public.current_app_role()::text,'') not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;

  return (
    with matching as (
      select
        s.id,s.admission_no,s.first_name,s.middle_name,s.last_name,s.gender,s.date_of_birth,
        s.photo_url,s.status,s.updated_at,s.deleted_at,(s.deleted_at is not null) archived,
        e.id enrollment_id,e.class_id,e.academic_year_id,e.roll_number,
        c.name class_name,y.name academic_year_name,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) display_name
      from public.students s
      left join lateral (
        select en.*
        from public.enrollments en
        join public.academic_years ay
          on ay.id=en.academic_year_id
         and ay.deleted_at is null
        where en.student_id=s.id
          and en.deleted_at is null
        order by
          en.active desc,
          coalesce(ay.start_date,ay.end_date,en.created_at::date) desc,
          ay.name::text desc,
          en.created_at desc
        limit 1
      ) e on true
      left join public.classes c on c.id=e.class_id
      left join public.academic_years y on y.id=e.academic_year_id
      where (
          public.current_app_role() in ('system_admin','principal')
          or (e.id is not null and public.can_access_class(e.class_id,false))
        )
        and (
          archive_filter='all'
          or (archive_filter='active' and s.deleted_at is null)
          or (archive_filter='archived' and s.deleted_at is not null)
        )
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or s.status=target_status)
        and (
          coalesce(search_text,'')=''
          or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%'
        )
    )
    select jsonb_build_object(
      'rows',
      coalesce((
        select jsonb_agg(
          to_jsonb(x)-'display_name'
          order by lower(x.display_name),x.admission_no::text
        )
        from (
          select *
          from matching
          order by lower(display_name),admission_no::text
          limit limit_value
          offset offset_value
        ) x
      ),'[]'::jsonb),
      'total',(select count(*) from matching),
      'page',greatest(page_number,1),
      'page_size',limit_value
    )
  );
end
$function$

CREATE OR REPLACE FUNCTION public.set_active_period(target_academic_year_id uuid, target_term_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if not exists(select 1 from public.terms where id=target_term_id and academic_year_id=target_academic_year_id and deleted_at is null)
    then raise exception 'The selected term does not belong to the selected academic year'; end if;
  perform set_config('app.change_reason','Active academic period update',true);
  update public.terms set is_active=false where is_active;
  update public.academic_years set is_active=false where is_active;
  update public.academic_years set is_active=true where id=target_academic_year_id and deleted_at is null;
  update public.terms set is_active=true where id=target_term_id and deleted_at is null;
  return public.get_bootstrap_data();
end $function$

CREATE OR REPLACE FUNCTION public.set_headteacher_photo(target_headteacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare h public.headteachers%rowtype;clean_path text:=btrim(coalesce(target_photo_url,''));
begin
  select * into h from public.headteachers where id=target_headteacher_id and deleted_at is null for update;
  if h.id is null then raise exception 'Principal record not found';end if;
  if not(public.is_system_admin() or h.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  perform public.require_sensitive_access();if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';end if;
  if expected_updated_at is not null and h.updated_at is distinct from expected_updated_at then raise exception 'Principal record changed by another user' using errcode='40001';end if;
  if clean_path<>'' and split_part(clean_path,'/',1)<>target_headteacher_id::text then raise exception 'Principal photograph path is invalid';end if;
  update public.headteachers set photo_url=clean_path,updated_at=now() where id=target_headteacher_id returning * into h;
  return jsonb_build_object('headteacher',to_jsonb(h));
end$function$

CREATE OR REPLACE FUNCTION public.set_my_headteacher_signature(target_signature_path text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare hid uuid;current_updated timestamptz;clean_path text:=btrim(coalesce(target_signature_path,''));
begin
  if auth.uid() is null or public.current_app_role()<>'principal' then raise exception 'Access denied' using errcode='42501'; end if;
  select h.id,h.updated_at into hid,current_updated from public.headteachers h where h.profile_id=auth.uid() and h.deleted_at is null and h.active order by h.updated_at desc limit 1 for update;
  if hid is null then raise exception 'No active Principal record is linked to this account'; end if;
  if expected_updated_at is not null and current_updated is distinct from expected_updated_at then raise exception 'Principal record changed. Reload and try again.' using errcode='40001'; end if;
  if clean_path<>'' and clean_path not like auth.uid()::text||'/%' then raise exception 'Signature storage path is invalid'; end if;
  perform set_config('app.change_reason',case when clean_path='' then 'Principal signature removed' else 'Principal signature updated' end,true);
  update public.headteachers set signature_path=clean_path,signature_updated_at=case when clean_path='' then null else now() end,updated_at=now() where id=hid;
  return public.get_my_headteacher_signature();
end $function$

CREATE OR REPLACE FUNCTION public.set_school_logo_reference(target_logo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_catalog', 'extensions'
AS $function$ declare clean text:=btrim(coalesce(target_logo_url,'')); sid uuid; object_path text; begin if not public.is_system_admin() then raise exception 'Only the School System Administrator can change the official school logo' using errcode='42501';end if; perform public.require_sensitive_access(); if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit school logo changes' using errcode='42501';end if; select id into sid from public.school_settings order by created_at,id limit 1 for update; if sid is null then raise exception 'School identity is unavailable';end if; if clean='assets/school-logo.png' then null; elsif clean like 'school-branding:%' then object_path:=substr(clean,length('school-branding:')+1); if object_path='' or object_path not like ('official/'||sid::text||'/%') or object_path !~ '^official/[0-9a-f-]{36}/logo-[A-Za-z0-9._-]+\.png$' then raise exception 'Invalid school logo reference';end if; if not exists(select 1 from storage.objects where bucket_id='school-branding' and name=object_path) then raise exception 'The uploaded school logo was not found in protected Storage';end if; else raise exception 'Invalid school logo reference';end if; update public.school_settings set logo_url=clean,updated_at=now() where id=sid; return jsonb_build_object('saved',true,'logo_url',clean,'message','Official school logo saved for future school documents.'); end$function$

CREATE OR REPLACE FUNCTION public.set_student_photo(target_student_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_updated timestamptz; affected integer;
begin
  if auth.uid() is null or not public.can_manage_student(target_student_id) then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(target_photo_url,''))='' or target_photo_url not like target_student_id::text||'/%' then raise exception 'Student photograph path is invalid'; end if;
  select updated_at into current_updated from public.students where id=target_student_id and deleted_at is null for update;
  if not found then raise exception 'Student record not found'; end if;
  if expected_updated_at is not null and current_updated is distinct from expected_updated_at then raise exception 'Student record changed by another user' using errcode='40001'; end if;
  perform set_config('app.change_reason','Student photograph updated',true);
  update public.students set photo_url=target_photo_url,updated_at=now() where id=target_student_id and deleted_at is null;
  get diagnostics affected=row_count; if affected<>1 then raise exception 'Student photograph was not saved'; end if;
  return public.get_student_record_v5(target_student_id);
end $function$

CREATE OR REPLACE FUNCTION public.set_teacher_photo(target_teacher_id uuid, target_photo_url text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare t public.teachers%rowtype;clean_path text:=btrim(coalesce(target_photo_url,''));
begin
  select * into t from public.teachers where id=target_teacher_id and deleted_at is null for update;
  if t.id is null then raise exception 'Teacher record not found';end if;
  if not(public.is_system_admin() or t.profile_id=auth.uid()) then raise exception 'Access denied' using errcode='42501';end if;
  perform public.require_sensitive_access();if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit staff profile changes' using errcode='42501';end if;
  if expected_updated_at is not null and t.updated_at is distinct from expected_updated_at then raise exception 'Teacher record changed by another user' using errcode='40001';end if;
  if clean_path<>'' and split_part(clean_path,'/',1)<>target_teacher_id::text then raise exception 'Teacher photograph path is invalid';end if;
  update public.teachers set photo_url=clean_path,updated_at=now() where id=target_teacher_id returning * into t;
  return public.get_teacher_record(target_teacher_id);
end$function$

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin new.updated_at=now(); return new; end $function$

CREATE OR REPLACE FUNCTION public.staff_id_card_photo_path_is_referenced(target_staff_id uuid, target_photo_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select public.staff_id_card_photo_reference_count(target_staff_id,target_photo_path)>0
$function$

CREATE OR REPLACE FUNCTION public.staff_id_card_photo_reference_count(target_staff_id uuid, target_photo_path text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select case when auth.uid() is not null and (
   public.is_system_admin()
   or exists(select 1 from public.teachers t where t.id=target_staff_id and t.profile_id=auth.uid() and t.deleted_at is null)
   or exists(select 1 from public.headteachers h where h.id=target_staff_id and h.profile_id=auth.uid() and h.deleted_at is null)
 ) then (select count(*) from public.staff_id_cards c where btrim(coalesce(target_photo_path,''))<>'' and c.snapshot#>>'{staff,id}'=target_staff_id::text and c.snapshot#>>'{staff,photo_url}'=target_photo_path) else 0 end
$function$

CREATE OR REPLACE FUNCTION public.submit_certificate_batch(target_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare updated public.certificate_batches; principal_id uuid;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can submit certificates' using errcode='42501'; end if;
  update public.certificate_batches set status='submitted',submitted_by=auth.uid(),submitted_at=now(),review_note='',updated_at=now() where id=target_batch_id and status in ('draft','rejected') returning * into updated;
  if updated.id is null then raise exception 'Only a draft or rejected batch can be submitted'; end if;
  if not exists(select 1 from public.certificates where batch_id=target_batch_id and status in ('draft','rejected')) then raise exception 'The batch has no certificates to submit'; end if;
  update public.certificates set status='draft',updated_at=now() where batch_id=target_batch_id and status='rejected';
  perform public.record_certificate_event(target_batch_id,null,'submitted_for_principal_approval');
  for principal_id in select id from public.profiles where active and public.current_app_role_for(role)::text='principal' loop
    perform public.create_notification(principal_id,'Certificates awaiting approval',updated.title||' contains certificates requiring Principal review.','certificate_approval','certificate_batch',target_batch_id,false);
  end loop;
  return jsonb_build_object('batch_id',updated.id,'status',updated.status);
end $function$

CREATE OR REPLACE FUNCTION public.sync_attendance_reports(target_term_id uuid, target_class_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare affected integer:=0;
begin
  perform set_config('app.report_write','on',true);
  update public.student_reports r
  set days_school_opened=counts.days_school_opened,
      days_present=least(counts.days_present,counts.days_school_opened),
      updated_at=now()
  from public.enrollments e
  cross join lateral public.attendance_counts_for_enrollment(e.id,target_term_id) counts
  where r.enrollment_id=e.id
    and r.term_id=target_term_id
    and e.class_id=target_class_id
    and r.deleted_at is null
    and counts.days_school_opened>0;
  get diagnostics affected=row_count;
  return affected;
end $function$

CREATE OR REPLACE FUNCTION public.sync_class_teacher_responsibility_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if tg_op in ('UPDATE','DELETE') and old.class_teacher_id is not null then
    perform public.sync_teacher_responsibility_access(old.class_teacher_id);
  end if;
  if tg_op in ('INSERT','UPDATE') and new.class_teacher_id is not null
     and (tg_op='INSERT' or new.class_teacher_id is distinct from old.class_teacher_id
          or new.active is distinct from old.active
          or new.deleted_at is distinct from old.deleted_at) then
    perform public.sync_teacher_responsibility_access(new.class_teacher_id);
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.sync_current_academic_year_status()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_year_id uuid;
begin
  select y.id into current_year_id
  from public.academic_years y
  where y.deleted_at is null
    and y.start_date is not null
    and y.start_date<=current_date
    and (y.end_date is null or y.end_date>=current_date)
  order by y.start_date desc,y.created_at desc
  limit 1;
  -- Deactivate the previous year first so the one-active-year unique index
  -- cannot conflict while the current year is activated.
  update public.academic_years y
  set is_active=false,updated_at=now()
  where y.deleted_at is null
    and y.is_active
    and y.id is distinct from current_year_id;
  if current_year_id is not null then
    update public.academic_years y
    set is_active=true,updated_at=now()
    where y.id=current_year_id
      and y.deleted_at is null
      and not y.is_active;
  end if;
  return current_year_id;
end $function$

CREATE OR REPLACE FUNCTION public.sync_license_feature_rpc_privileges()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare r record;signature text;enabled boolean;
begin
  if coalesce(auth.role(),'') not in ('','service_role','supabase_admin') and not public.is_platform_super_admin() then raise exception 'Platform licence authority required' using errcode='42501';end if;
  for r in select * from (values
    (array['attendance']::text[],array['get_class_attendance_register','list_my_attendance_classes','save_class_attendance']::text[]),
    (array['assessment']::text[],array['archive_grading_scale','get_report_grading_guide','resolve_grading_guide','save_assessment_scheme','save_grading_scale']::text[]),
    (array['report_cards']::text[],array['bulk_generate_missing_reports','delete_report_card_permanently','get_current_principal_signature','get_my_headteacher_signature','get_report_correction_console','get_report_editor','get_report_headteacher_signature','get_report_revisions','list_my_children_reports','list_report_cards_v6','list_report_pdf_paths','register_report_pdf','report_position','report_promotion_evaluation','report_subject_positions','request_report_correction','review_report_correction','save_promotion_cutoff','save_report_card','save_report_comments','set_my_headteacher_signature','transition_report_status']::text[]),
    (array['academic_history']::text[],array['delete_transcript_issuance_permanently','get_student_academic_history','issue_student_transcript','record_student_lifecycle_event','revoke_student_transcript']::text[]),
    (array['certificates']::text[],array['create_certificate_batch','create_certificate_replacement_draft','delete_certificate_permanently','get_certificate_batch','get_certificate_console','issue_certificate_batch','list_certificate_eligible_recipients','register_certificate_pdf','review_certificate_batch','revoke_certificate','save_certificate_settings','save_teacher_award_category','submit_certificate_batch']::text[]),
    (array['report_cards','uploaded_templates']::text[],array['list_report_card_templates','remove_report_card_template','save_report_card_template']::text[]),
    (array['certificates','uploaded_templates']::text[],array['remove_certificate_template_file','save_certificate_template']::text[]),
    (array['bulk_workflow']::text[],array['bulk_import_students','bulk_promote_all_classes','bulk_promote_class','validate_student_import']::text[]),
    (array['bulk_workflow','assessment']::text[],array['bulk_import_scores','validate_score_import']::text[]),
    (array['bulk_workflow','report_cards']::text[],array['bulk_transition_class_reports']::text[]),
    (array['manual_backup']::text[],array['backup_dashboard','get_recovery_console','mark_backup_offsite_copy','save_backup_policy']::text[]),
    (array['notifications']::text[],array['delete_notifications','list_notifications','mark_notifications_read']::text[]),
    (array['notifications','report_cards']::text[],array['queue_incomplete_report_notifications','run_academic_alerts']::text[]),
    (array['analytics']::text[],array['academic_analytics']::text[])
  ) v(features,names) loop
    select bool_and(public.license_feature_enabled(f)) into enabled from unnest(r.features) f;
    for signature in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=any(r.names) loop
      execute format('revoke execute on function %s from public, anon, authenticated',signature);
      if coalesce(enabled,false) then execute format('grant execute on function %s to authenticated',signature);end if;
    end loop;
  end loop;
end $function$

CREATE OR REPLACE FUNCTION public.sync_pending_promotions_when_year_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.apply_pending_term3_promotions();
  return null;
end $function$

CREATE OR REPLACE FUNCTION public.sync_report_next_term_reopening_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare configured_date date;
begin
  select t.next_term_begins into configured_date
  from public.terms t where t.id=new.term_id;
  if tg_op='INSERT' then
    new.next_term_reopening_date:=configured_date;
  elsif new.term_id is distinct from old.term_id
     or (new.status is distinct from old.status
         and new.status in ('submitted','class_reviewed','approved','published')) then
    new.next_term_reopening_date:=configured_date;
  end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.sync_report_promotion_from_subject_result()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  target_id uuid;
  target_status text;
  sync_target_enrollment boolean:=false;
begin
  if tg_op='DELETE' then target_id:=old.report_id; else target_id:=new.report_id; end if;
  select r.status::text into target_status
  from public.student_reports r
  where r.id=target_id and r.deleted_at is null;
  if target_status is not null then
    select target_status in ('approved','published') or exists(
      select 1 from public.enrollments e
      where e.promotion_source_report_id=target_id
        and e.enrollment_origin='automatic_promotion'
        and e.deleted_at is null
    ) into sync_target_enrollment;
    perform public.refresh_report_promotion(target_id,sync_target_enrollment);
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.sync_subject_teacher_responsibility_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if tg_op in ('UPDATE','DELETE') and old.teacher_id is not null then
    perform public.sync_teacher_responsibility_access(old.teacher_id);
  end if;
  if tg_op in ('INSERT','UPDATE') and new.teacher_id is not null
     and (tg_op='INSERT' or new.teacher_id is distinct from old.teacher_id
          or new.class_id is distinct from old.class_id
          or new.subject_id is distinct from old.subject_id
          or new.active is distinct from old.active) then
    perform public.sync_teacher_responsibility_access(new.teacher_id);
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.sync_teacher_record_class_links()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  old_profile_id uuid;
  new_profile_id uuid;
begin
  old_profile_id:=case when tg_op='INSERT' then null else old.profile_id end;
  new_profile_id:=case
    when tg_op='DELETE' then null
    when new.active and new.deleted_at is null and new.employment_status='active' then new.profile_id
    else null
  end;
  if tg_op='DELETE'
     or not new.active
     or new.deleted_at is not null
     or new.employment_status<>'active' then
    update public.classes
    set class_teacher_record_id=null,
        class_teacher_id=null,
        updated_at=now()
    where class_teacher_record_id=case when tg_op='DELETE' then old.id else new.id end;
  else
    update public.classes
    set class_teacher_id=new_profile_id,
        updated_at=now()
    where class_teacher_record_id=new.id
      and class_teacher_id is distinct from new_profile_id;
  end if;
  if old_profile_id is not null then
    perform public.sync_teacher_responsibility_access(old_profile_id);
  end if;
  if new_profile_id is not null and new_profile_id is distinct from old_profile_id then
    perform public.sync_teacher_responsibility_access(new_profile_id);
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.sync_teacher_responsibility_access(target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  class_scope_count integer:=0;
  subject_scope_count integer:=0;
  target_role text;
begin
  if target_user_id is null then
    return jsonb_build_object('user_id',null,'class_scopes',0,'subject_scopes',0);
  end if;
  select public.current_app_role_for(p.role)
  into target_role
  from public.profiles p
  where p.id=target_user_id and p.active;
  delete from public.user_class_access
  where user_id=target_user_id;
  if target_role not in ('class_teacher','subject_teacher') then
    return jsonb_build_object('user_id',target_user_id,'class_scopes',0,'subject_scopes',0);
  end if;
  insert into public.user_class_access(user_id,class_id,subject_id,access_level)
  select target_user_id,c.id,null,'edit'
  from public.classes c
  where c.class_teacher_id=target_user_id
    and c.active
    and c.deleted_at is null;
  get diagnostics class_scope_count=row_count;
  insert into public.user_class_access(user_id,class_id,subject_id,access_level)
  select target_user_id,cs.class_id,cs.subject_id,'score'
  from public.class_subjects cs
  join public.classes c on c.id=cs.class_id
  join public.subjects s on s.id=cs.subject_id
  where cs.teacher_id=target_user_id
    and cs.active
    and c.active and c.deleted_at is null
    and s.active and s.deleted_at is null
  on conflict do nothing;
  get diagnostics subject_scope_count=row_count;
  return jsonb_build_object(
    'user_id',target_user_id,
    'class_scopes',class_scope_count,
    'subject_scopes',subject_scope_count
  );
end $function$

CREATE OR REPLACE FUNCTION public.system_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.has_role(array['system_admin','headteacher','academic_admin']) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return jsonb_build_object(
    'database_time',now(),
    'active_users',(select count(*) from public.profiles where active),
    'active_teachers',(select count(*) from public.teachers where active and deleted_at is null),
    'active_students',(select count(*) from public.students where status='active' and deleted_at is null),
    'pending_notifications',(select count(*) from public.notification_outbox where processed_at is null),
    'client_errors_24h',(select count(*) from public.client_error_events where created_at>=now()-interval '24 hours'),
    'latest_backup',(select max(coalesce(completed_at,created_at)) from public.backup_exports where status='completed' and backup_type='full'),
    'latest_verified_backup',(select max(verification_checked_at) from public.backup_exports where verification_status='passed'),
    'failed_backups_30d',(select count(*) from public.backup_exports where status='failed' and created_at>=now()-interval '30 days'),
    'unverified_completed_backups',(select count(*) from public.backup_exports where status='completed' and verification_status<>'passed'),
    'latest_offsite_copy',(select max(offsite_copied_at) from public.backup_exports),
    'incomplete_schemes',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'weight',q.total_weight)) from (
      select scheme_id,sum(weight) total_weight from public.assessment_components group by scheme_id having abs(sum(weight)-100)>0.01
    ) q join public.assessment_schemes s on s.id=q.scheme_id),'[]'::jsonb),
    'published_without_pdf',(select count(*) from public.report_publications where revoked_at is null and storage_path='')
  );
end $function$

CREATE OR REPLACE FUNCTION public.term_control_snapshot(target_term_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select jsonb_build_object(
    'term_id',t.id,'term_name',t.name,'academic_year_id',t.academic_year_id,
    'score_entry_deadline',c.score_entry_deadline,'attendance_deadline',c.attendance_deadline,
    'report_submission_deadline',c.report_submission_deadline,
    'principal_approval_deadline',c.principal_approval_deadline,
    'publication_deadline',c.publication_deadline,
    'scores_locked',coalesce(c.scores_locked,false) or (c.score_entry_deadline is not null and now()>c.score_entry_deadline),
    'attendance_locked',coalesce(c.attendance_locked,false) or (c.attendance_deadline is not null and now()>c.attendance_deadline),
    'reports_locked',coalesce(c.reports_locked,false),
    'submission_overdue',c.report_submission_deadline is not null and now()>c.report_submission_deadline,
    'approval_overdue',c.principal_approval_deadline is not null and now()>c.principal_approval_deadline,
    'publication_overdue',c.publication_deadline is not null and now()>c.publication_deadline,
    'lock_reason',coalesce(c.lock_reason,''),'locked_at',c.locked_at
  )
  from public.terms t left join public.academic_period_controls c on c.term_id=t.id
  where t.id=target_term_id and t.deleted_at is null
$function$

CREATE OR REPLACE FUNCTION public.term_phase_writable(target_term_id uuid, target_phase text, target_report_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s jsonb;
begin
  if not public.license_write_allowed() then return false; end if;
  s:=public.term_control_snapshot(target_term_id);
  if s is null then return false; end if;
  if target_report_id is not null and public.has_approved_report_correction(target_report_id) then return true; end if;
  if target_phase='scores' then return not coalesce((s->>'scores_locked')::boolean,false) and ((s->>'score_entry_deadline') is null or (s->>'score_entry_deadline')::timestamptz>=now()); end if;
  if target_phase='attendance' then return not coalesce((s->>'attendance_locked')::boolean,false) and ((s->>'attendance_deadline') is null or (s->>'attendance_deadline')::timestamptz>=now()); end if;
  if target_phase='reports' then return not coalesce((s->>'reports_locked')::boolean,false) and ((s->>'report_submission_deadline') is null or (s->>'report_submission_deadline')::timestamptz>=now()); end if;
  return false;
end $function$

CREATE OR REPLACE FUNCTION public.transition_report_status(target_report_id uuid, target_status report_status, comment_text text DEFAULT ''::text, expected_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare current_status public.report_status;current_version integer;allowed public.report_status[];revisionid uuid;ts timestamptz:=now();
begin
  select status,version into current_status,current_version from public.student_reports where id=target_report_id and deleted_at is null for update;
  if current_status is null then raise exception 'Report not found'; end if;
  if expected_version is not null and current_version<>expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if not public.report_transition_deadline_allowed(target_report_id,target_status) then raise exception 'The report workflow deadline has passed or the selected term is locked' using errcode='42501'; end if;
  allowed:=public.allowed_report_transitions(target_report_id);
  if not target_status=any(allowed) then raise exception 'Transition from % to % is not allowed',current_status,target_status using errcode='42501'; end if;
  if target_status='submitted' then
    if exists(select 1 from public.class_subjects cs join public.student_reports r on r.id=target_report_id left join public.subject_results sr on sr.report_id=r.id and sr.subject_id=cs.subject_id where cs.class_id=public.report_class_id(target_report_id) and cs.active and sr.id is null) then raise exception 'All assigned subjects must be completed before submission'; end if;
    if exists(select 1 from public.subject_results sr join public.assessment_components ac on ac.scheme_id=sr.scheme_id and ac.required left join public.assessment_score_entries se on se.subject_result_id=sr.id and se.component_id=ac.id where sr.report_id=target_report_id and se.id is null) then raise exception 'Required assessment scores are incomplete'; end if;
  end if;
  perform set_config('app.report_write','on',true); perform set_config('app.change_reason',coalesce(nullif(comment_text,''),replace(target_status::text,'_',' ')),true);
  update public.student_reports set status=target_status,version=version+1,
    submitted_at=case when target_status='submitted' then ts else submitted_at end,
    submitted_by=case when target_status='submitted' then auth.uid() else submitted_by end,
    reviewed_at=case when target_status='class_reviewed' then ts else reviewed_at end,
    reviewed_by=case when target_status='class_reviewed' then auth.uid() else reviewed_by end,
    approved_at=case when target_status='approved' then ts else approved_at end,
    approved_by=case when target_status='approved' then auth.uid() else approved_by end,
    published_at=case when target_status='published' then ts else published_at end,
    published_by=case when target_status='published' then auth.uid() else published_by end,
    withdrawn_at=case when target_status='withdrawn' then ts else withdrawn_at end,updated_at=ts
  where id=target_report_id returning version into current_version;
  insert into public.report_workflow_events(report_id,from_status,to_status,comment,actor_id) values(target_report_id,current_status,target_status,coalesce(comment_text,''),auth.uid());
  insert into public.report_revisions(report_id,version,snapshot,reason,actor_id) values(target_report_id,current_version,public.build_report_snapshot(target_report_id),coalesce(nullif(comment_text,''),replace(target_status::text,'_',' ')),auth.uid()) on conflict(report_id,version) do update set snapshot=excluded.snapshot,reason=excluded.reason,actor_id=excluded.actor_id,created_at=now() returning id into revisionid;
  if target_status='published' then
    insert into public.report_publications(report_id,revision_id,published_by) values(target_report_id,revisionid,auth.uid()) on conflict(report_id) where revoked_at is null do update set revision_id=excluded.revision_id,published_by=excluded.published_by,published_at=now();
    perform public.mark_report_correction_applied(target_report_id);
  elsif target_status='withdrawn' then update public.report_publications set revoked_at=ts,revoked_by=auth.uid() where report_id=target_report_id and revoked_at is null; end if;
  perform public.create_workflow_notifications(target_report_id,target_status);
  return public.get_report_editor(target_report_id,null,null);
end $function$

CREATE OR REPLACE FUNCTION public.trigger_sync_license_feature_rpc_privileges()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin perform public.sync_license_feature_rpc_privileges();return null;end $function$

CREATE OR REPLACE FUNCTION public.update_privacy_request(target_request_id uuid, target_status text, outcome_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare row_data public.privacy_requests;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if target_status not in ('open','in_review','approved','rejected','completed','cancelled') then raise exception 'Invalid privacy-request status'; end if;
  update public.privacy_requests set status=target_status,outcome=left(coalesce(outcome_text,''),2000),completed_by=case when target_status in ('completed','rejected','cancelled') then auth.uid() else completed_by end,completed_at=case when target_status in ('completed','rejected','cancelled') then now() else completed_at end,updated_at=now() where id=target_request_id returning * into row_data;
  if row_data.id is null then raise exception 'Privacy request not found'; end if;
  return to_jsonb(row_data);
end $function$

CREATE OR REPLACE FUNCTION public.validate_assessment_scheme_weights()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare sid uuid; total numeric;
begin
  sid:=case when tg_op='DELETE' then old.scheme_id else new.scheme_id end;
  select coalesce(sum(weight),0) into total from public.assessment_components where scheme_id=sid
    and id<>coalesce(case when tg_op='DELETE' then old.id else new.id end,'00000000-0000-0000-0000-000000000000'::uuid);
  if tg_op<>'DELETE' then total:=total+new.weight; end if;
  if total>100.001 then raise exception 'Assessment component weights cannot exceed 100'; end if;
  return case when tg_op='DELETE' then old else new end;
end $function$

CREATE OR REPLACE FUNCTION public.validate_grading_scale_overlap()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if exists(
    select 1 from public.grading_scales g
    where g.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
      and g.deleted_at is null
      and g.academic_year_id is not distinct from new.academic_year_id
      and g.class_id is not distinct from new.class_id
      and g.subject_id is not distinct from new.subject_id
      and numrange(g.min_mark,g.max_mark,'[]') && numrange(new.min_mark,new.max_mark,'[]')
  ) then raise exception 'Grading ranges cannot overlap within the same scope'; end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.validate_operational_readiness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  rls_state jsonb; function_state jsonb; duplicate_state jsonb; privilege_state jsonb;
  role_state jsonb; integrity_state jsonb; ready_value boolean;
begin
  if not public.has_role(array['system_admin','principal']) then raise exception 'Access denied' using errcode='42501'; end if;
  select jsonb_object_agg(tablename,rowsecurity) into rls_state from pg_tables where schemaname='public' and tablename in
    ('profiles','teachers','headteachers','students','student_guardians','guardian_links','enrollments','academic_years','terms','classes','subjects','class_subjects','user_class_access','grading_scales','assessment_schemes','assessment_components','student_reports','subject_results','assessment_score_entries');
  function_state:=jsonb_build_object(
    'generate_school_identifier',to_regprocedure('public.generate_school_identifier(text)') is not null,
    'save_student',to_regprocedure('public.save_student(jsonb)') is not null,
    'set_student_photo',to_regprocedure('public.set_student_photo(uuid,text,timestamptz)') is not null,
    'save_teacher',to_regprocedure('public.save_teacher(jsonb)') is not null,
    'save_headteacher',to_regprocedure('public.save_headteacher(jsonb)') is not null,
    'admin_validate_user_bundle',to_regprocedure('public.admin_validate_user_bundle(uuid,jsonb,boolean)') is not null,
    'admin_apply_user_bundle',to_regprocedure('public.admin_apply_user_bundle(uuid,jsonb)') is not null,
    'save_academic_entity',to_regprocedure('public.save_academic_entity(text,jsonb)') is not null,
    'save_class_subject_assignment',to_regprocedure('public.save_class_subject_assignment(jsonb)') is not null,
    'save_grading_scale',to_regprocedure('public.save_grading_scale(jsonb)') is not null,
    'save_assessment_scheme',to_regprocedure('public.save_assessment_scheme(jsonb)') is not null,
    'save_report_card',to_regprocedure('public.save_report_card(jsonb,integer)') is not null,
    'get_role_dashboard',to_regprocedure('public.get_role_dashboard(uuid)') is not null,
    'get_role_workspace',to_regprocedure('public.get_role_workspace()') is not null
  );
  duplicate_state:=jsonb_build_object(
    'admission_numbers',(select count(*) from (select lower(admission_no::text) from public.students group by lower(admission_no::text) having count(*)>1) q),
    'staff_numbers',(select count(*) from (
      select staff_no from (
        select lower(staff_no::text) staff_no from public.teachers
        union all select lower(staff_no::text) from public.headteachers
      ) all_staff group by staff_no having count(*)>1
    ) duplicate_staff),
    'access_scopes',(select count(*) from (select user_id,class_id,coalesce(subject_id,'00000000-0000-0000-0000-000000000000'::uuid) from public.user_class_access group by 1,2,3 having count(*)>1) q),
    'grading_overlaps',(select count(*) from public.grading_scales a join public.grading_scales b on a.id<b.id and a.deleted_at is null and b.deleted_at is null
      and a.academic_year_id is not distinct from b.academic_year_id and a.class_id is not distinct from b.class_id and a.subject_id is not distinct from b.subject_id
      and numrange(a.min_mark,a.max_mark,'[]') && numrange(b.min_mark,b.max_mark,'[]'))
  );
  integrity_state:=jsonb_build_object(
    'assessment_scheme_weights',(select count(*) from (
      select s.id from public.assessment_schemes s left join public.assessment_components c on c.scheme_id=s.id
      where s.deleted_at is null and s.active group by s.id having count(c.id)=0 or abs(coalesce(sum(c.weight),0)-100)>0.01
    ) q),
    'active_enrollment_conflicts',(select count(*) from (
      select e.student_id from public.enrollments e where e.active and e.deleted_at is null group by e.student_id having count(*)>1
    ) q),
    'invalid_teacher_links',(select count(*) from public.teachers t left join public.profiles p on p.id=t.profile_id
      where t.deleted_at is null and t.profile_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role) not in ('class_teacher','subject_teacher'))),
    'invalid_headteacher_links',(select count(*) from public.headteachers h left join public.profiles p on p.id=h.profile_id
      where h.deleted_at is null and h.profile_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role)<>'principal')),
    'duplicate_staff_profile_links',(select count(*) from (
      select profile_id from (
        select profile_id from public.teachers where deleted_at is null and profile_id is not null
        union all select profile_id from public.headteachers where deleted_at is null and profile_id is not null
      ) staff_links group by profile_id having count(*)>1
    ) q),
    'invalid_class_teacher_links',(select count(*) from public.classes c left join public.profiles p on p.id=c.class_teacher_id
      where c.deleted_at is null and c.class_teacher_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role) not in ('principal','academic_admin','class_teacher'))),
    'invalid_subject_teacher_links',(select count(*) from public.class_subjects cs left join public.profiles p on p.id=cs.teacher_id
      where cs.active and cs.teacher_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role) not in ('principal','academic_admin','class_teacher','subject_teacher'))),
    'invalid_guardian_portal_links',(select count(*) from public.guardian_links gl left join public.profiles p on p.id=gl.auth_user_id
      where gl.auth_user_id is not null and (p.id is null or not p.active or public.current_app_role_for(p.role)<>'parent_guardian')),
    'missing_auth_profiles',(select count(*) from auth.users u left join public.profiles p on p.id=u.id where p.id is null),
    'active_period_errors',(
      (select greatest(count(*)-1,0) from public.academic_years where is_active and deleted_at is null)
      +(select greatest(count(*)-1,0) from public.terms where is_active and deleted_at is null)
      +(select count(*) from public.terms t left join public.academic_years y on y.id=t.academic_year_id where t.is_active and t.deleted_at is null and (y.id is null or not y.is_active or y.deleted_at is not null))
    ),
    'subject_total_mismatches',(select count(*) from public.subject_results sr where abs(sr.total_score-coalesce((select sum(se.weighted_score) from public.assessment_score_entries se where se.subject_result_id=sr.id),0))>0.01)
  );
  privilege_state:=jsonb_build_object(
    'identifier_rpc',has_function_privilege('authenticated','public.generate_school_identifier(text)','EXECUTE'),
    'student_rpc',has_function_privilege('authenticated','public.save_student(jsonb)','EXECUTE'),
    'teacher_rpc',has_function_privilege('authenticated','public.save_teacher(jsonb)','EXECUTE'),
    'headteacher_rpc',has_function_privilege('authenticated','public.save_headteacher(jsonb)','EXECUTE'),
    'academic_rpc',has_function_privilege('authenticated','public.save_academic_entity(text,jsonb)','EXECUTE'),
    'assessment_rpc',has_function_privilege('authenticated','public.save_assessment_scheme(jsonb)','EXECUTE'),
    'report_rpc',has_function_privilege('authenticated','public.save_report_card(jsonb,integer)','EXECUTE'),
    'student_direct_write_blocked',not has_table_privilege('authenticated','public.students','INSERT') and not has_table_privilege('authenticated','public.students','UPDATE') and not has_table_privilege('authenticated','public.students','DELETE'),
    'teacher_direct_write_blocked',not has_table_privilege('authenticated','public.teachers','INSERT') and not has_table_privilege('authenticated','public.teachers','UPDATE') and not has_table_privilege('authenticated','public.teachers','DELETE'),
    'headteacher_direct_write_blocked',not has_table_privilege('authenticated','public.headteachers','INSERT') and not has_table_privilege('authenticated','public.headteachers','UPDATE') and not has_table_privilege('authenticated','public.headteachers','DELETE'),
    'profile_direct_write_blocked',not has_table_privilege('authenticated','public.profiles','INSERT') and not has_table_privilege('authenticated','public.profiles','UPDATE') and not has_table_privilege('authenticated','public.profiles','DELETE')
  );
  role_state:=jsonb_build_object(
    'system_admin',true,'principal',true,'academic_admin',true,'class_teacher',true,
    'subject_teacher',true,'records_officer',true,'viewer',true,'parent_guardian',true
  );
  ready_value:=not exists(select 1 from jsonb_each_text(function_state) x where x.value<>'true')
    and not exists(select 1 from jsonb_each_text(coalesce(rls_state,'{}'::jsonb)) x where x.value<>'true')
    and not exists(select 1 from jsonb_each_text(privilege_state) x where x.value<>'true')
    and not exists(select 1 from jsonb_each_text(duplicate_state) x where x.value::numeric<>0)
    and not exists(select 1 from jsonb_each_text(integrity_state) x where x.value::numeric<>0);
  return jsonb_build_object('ready',ready_value,'functions',function_state,'rls',coalesce(rls_state,'{}'::jsonb),'privileges',privilege_state,
    'roles',role_state,'duplicates',duplicate_state,'integrity',integrity_state,'checked_at',now());
end $function$

CREATE OR REPLACE FUNCTION public.validate_score_import(target_term_id uuid, target_class_id uuid, rows jsonb, filename text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare item jsonb;rowno integer:=0;valid_rows jsonb:='[]'::jsonb;errors jsonb:='[]'::jsonb;yearid uuid;enrollmentid uuid;subjectid uuid;schemeid uuid;componentid uuid;maxscore numeric;raw numeric;
begin
  if not public.can_create_report_for_class_term(target_class_id,target_term_id) then raise exception 'Access denied' using errcode='42501'; end if;
  if not public.term_phase_writable(target_term_id,'scores',null) then raise exception 'Score entry is locked for the selected term'; end if;
  select academic_year_id into yearid from public.terms where id=target_term_id and deleted_at is null;
  for item in select value from jsonb_array_elements(coalesce(rows,'[]'::jsonb)) loop
    rowno:=rowno+1; enrollmentid:=null;subjectid:=null;schemeid:=null;componentid:=null;maxscore:=null;raw:=null;
    begin
      if btrim(coalesce(item->>'admission_no',''))='' or btrim(coalesce(item->>'subject_code',''))='' or btrim(coalesce(item->>'component_code',''))='' then raise exception 'Admission number, subject code, and component code are required'; end if;
      select e.id into strict enrollmentid from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=target_class_id and e.academic_year_id=yearid and e.active and e.deleted_at is null and s.deleted_at is null and lower(s.admission_no::text)=lower(btrim(item->>'admission_no'));
      select sb.id into subjectid from public.subjects sb join public.class_subjects cs on cs.subject_id=sb.id and cs.class_id=target_class_id and cs.active where lower(sb.code::text)=lower(btrim(item->>'subject_code')) and sb.active and sb.deleted_at is null;
      if subjectid is null then raise exception 'Subject code is not assigned to the selected class'; end if;
      if not public.can_score_class_subject_for_term(target_class_id,subjectid,target_term_id) then raise exception 'Not authorised for this subject'; end if;
      schemeid:=public.resolve_assessment_scheme(target_class_id,subjectid,yearid,target_term_id); if schemeid is null then raise exception 'Assessment scheme not configured'; end if;
      select ac.id,ac.maximum_score into componentid,maxscore from public.assessment_components ac where ac.scheme_id=schemeid and lower(ac.code::text)=lower(btrim(item->>'component_code'));
      if componentid is null then raise exception 'Assessment component code not found'; end if;
      raw:=public.safe_numeric(item->>'raw_score'); if raw is null then raise exception 'Raw score is invalid'; end if;
      if raw<0 or raw>maxscore then raise exception 'Raw score is outside the component maximum'; end if;
      valid_rows:=valid_rows||jsonb_build_array(item);
    exception when others then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message',sqlerrm,'payload',item));
    end;
  end loop;
  return jsonb_build_object('filename',filename,'total',jsonb_array_length(coalesce(rows,'[]'::jsonb)),'valid_count',jsonb_array_length(valid_rows),'invalid_count',jsonb_array_length(errors),'valid_rows',valid_rows,'errors',errors);
end $function$

CREATE OR REPLACE FUNCTION public.validate_student_import(rows jsonb, target_academic_year_id uuid, target_class_id uuid, filename text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare item jsonb;rowno integer:=0;valid_rows jsonb:='[]'::jsonb;errors jsonb:='[]'::jsonb;admission text;gender_text text;
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can validate student imports' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(rows,'[]'::jsonb))<>'array' then raise exception 'Rows must be a list'; end if;
  for item in select value from jsonb_array_elements(rows) loop
    rowno:=rowno+1; admission:=btrim(coalesce(item->>'admission_no','')); gender_text:=initcap(lower(btrim(coalesce(item->>'gender',''))));
    if admission='' or btrim(coalesce(item->>'first_name',''))='' or btrim(coalesce(item->>'last_name',''))='' then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Admission number, first name, and last name are required','payload',item));
    elsif gender_text not in ('Male','Female','Other') then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Gender must be Male, Female, or Other','payload',item));
    elsif exists(select 1 from public.students where lower(admission_no::text)=lower(admission) and deleted_at is null) then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Admission number already exists','payload',item));
    elsif exists(select 1 from jsonb_array_elements(rows) x where lower(btrim(x->>'admission_no'))=lower(admission) group by lower(btrim(x->>'admission_no')) having count(*)>1) then
      errors:=errors||jsonb_build_array(jsonb_build_object('row_number',rowno,'message','Duplicate admission number in import file','payload',item));
    else
      valid_rows:=valid_rows||jsonb_build_array(item||jsonb_build_object('academic_year_id',target_academic_year_id,'class_id',target_class_id,'gender',gender_text));
    end if;
  end loop;
  return jsonb_build_object('filename',filename,'total',jsonb_array_length(rows),'valid_count',jsonb_array_length(valid_rows),'invalid_count',jsonb_array_length(errors),'valid_rows',valid_rows,'errors',errors);
end $function$

CREATE OR REPLACE FUNCTION public.validate_term_reopening_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if new.next_term_begins is not null
     and new.end_date is not null
     and new.next_term_begins<=new.end_date then
    raise exception 'Next-term reopening date must be after the current term end date';
  end if;
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.verify_certificate(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((select jsonb_build_object(
    'found',true,'valid',c.status='issued','status',c.status,'certificate_number',c.certificate_number,
    'certificate_type',b.certificate_type,'certificate_type_label',public.certificate_type_label(b.certificate_type),
    'certificate_title',c.certificate_title,'recipient_name',c.recipient_name,'recipient_identifier',c.recipient_identifier,
    'academic_year',c.academic_year_name,'class_name',c.current_class_name,'promoted_to',c.destination_class_name,
    'award_category',c.award_category_name,'statement',c.statement_text,'issue_date',c.issue_date,'issued_at',c.issued_at,
    'school_name',(select s.school_name from public.school_settings s limit 1),
    'revocation_reason',case when c.status='revoked' then c.revocation_reason else '' end,
    'superseded_by',(select newer.certificate_number from public.certificates newer where newer.supersedes_certificate_id=c.id and newer.status='issued' order by newer.issued_at desc limit 1)
  ) from public.certificates c join public.certificate_batches b on b.id=c.batch_id where c.verification_token=token),jsonb_build_object('found',false,'valid',false,'status','not_found'))
$function$

CREATE OR REPLACE FUNCTION public.verify_license_binding(client_origin text, client_project_ref text, client_installation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if auth.role() not in ('service_role','supabase_admin') then
    raise exception 'Direct binding verification is disabled; invoke the license-verifier Edge Function' using errcode='42501';
  end if;
  return jsonb_build_object('authorised',false,'binding_required',true,'deprecated',true);
end $function$

CREATE OR REPLACE FUNCTION public.verify_report(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select case when p.id is null then jsonb_build_object('valid',false) else jsonb_build_object( 'valid',p.revoked_at is null, 'revoked',p.revoked_at is not null, 'published_at',p.published_at,'report_number',r.report_number, 'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name), 'admission_no',s.admission_no,'class_name',c.name,'term_name',t.name,'academic_year',y.name, 'average',(p2.snapshot->'summary'->>'average')::numeric, 'school_name',p2.snapshot->'school'->>'school_name', 'promotion',coalesce(p2.snapshot->'promotion','{}'::jsonb), 'revision',p2.version ) end from (select token verification_token) input left join public.report_publications p on p.verification_token=input.verification_token left join public.student_reports r on r.id=p.report_id left join public.enrollments e on e.id=r.enrollment_id left join public.students s on s.id=e.student_id left join public.classes c on c.id=e.class_id left join public.terms t on t.id=r.term_id left join public.academic_years y on y.id=t.academic_year_id left join public.report_revisions p2 on p2.id=p.revision_id $function$

CREATE OR REPLACE FUNCTION public.verify_staff_id_card(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select coalesce(
  (select jsonb_build_object('found',true,'valid',public.id_card_effective_status(c.status,c.expires_on)='active','status',public.id_card_effective_status(c.status,c.expires_on),'card_number',c.card_number,'staff_name',c.snapshot#>>'{staff,full_name}','staff_no',c.snapshot#>>'{staff,staff_no}','staff_role',c.snapshot#>>'{staff,role}','school_name',c.snapshot#>>'{school,school_name}','academic_year',c.snapshot#>>'{academic,academic_year_name}','issue_date',c.issue_date,'expires_on',c.expires_on,'revision',c.revision_no,'replacement_card_number',(select n.card_number from public.staff_id_cards n where n.supersedes_card_id=c.id order by n.issued_at desc limit 1)) from public.staff_id_cards c where c.verification_token=token),
  (select jsonb_build_object('found',true,'valid',false,'status','permanently_removed','card_number',t.card_number) from public.id_card_deletion_tombstones t where t.card_kind='staff' and t.verification_token=token),
  jsonb_build_object('found',false,'valid',false,'status','not_found'))
$function$

CREATE OR REPLACE FUNCTION public.verify_student_id_card(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select coalesce(
  (select jsonb_build_object('found',true,'valid',public.id_card_effective_status(c.status,c.expires_on)='active','status',public.id_card_effective_status(c.status,c.expires_on),'card_number',c.card_number,'student_name',c.snapshot#>>'{student,full_name}','admission_no',c.snapshot#>>'{student,admission_no}','class_name',c.snapshot#>>'{academic,class_name}','academic_year',c.snapshot#>>'{academic,academic_year_name}','school_name',c.snapshot#>>'{school,school_name}','issue_date',c.issue_date,'expires_on',c.expires_on,'revision',c.revision_no,'replacement_card_number',(select n.card_number from public.student_id_cards n where n.supersedes_card_id=c.id order by n.issued_at desc limit 1)) from public.student_id_cards c where c.verification_token=token),
  (select jsonb_build_object('found',true,'valid',false,'status','permanently_removed','card_number',t.card_number) from public.id_card_deletion_tombstones t where t.card_kind='student' and t.verification_token=token),
  jsonb_build_object('found',false,'valid',false,'status','not_found'))
$function$

CREATE OR REPLACE FUNCTION public.verify_transcript(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case when i.id is null then jsonb_build_object('valid',false)
  else jsonb_build_object(
    'valid',i.status='valid','status',i.status,'issued_at',i.issued_at,'purpose',i.purpose,
    'student_name',i.snapshot->'student'->>'full_name','admission_no',i.snapshot->'student'->>'admission_no',
    'school_name',i.snapshot->'school'->>'school_name','record_count',jsonb_array_length(coalesce(i.snapshot->'academic_records','[]'::jsonb)),
    'revoked_at',i.revoked_at,'revocation_reason',case when i.status='revoked' then i.revocation_reason else '' end
  ) end
  from (select token verification_token) x left join public.transcript_issuances i on i.verification_token=x.verification_token
$function$

SET check_function_bodies=on;
