-- Edusentia Enterprise Neon Edition — certified provider-bound RPC adaptation.
-- Certified source baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Provider adaptations:
--   Supabase Storage object catalog -> storage.object_metadata + Cloudflare R2 object keys
--   local legacy licence storage -> app.tenant_licenses + platform.license_plans
--   auth.users -> authn.users
--   pgcrypto digest resolves through the function search_path (public or extensions)
begin;

alter table app.tenant_licenses
  add column if not exists metadata jsonb not null default '{}'::jsonb;


-- Certified issue_student_transcript(target_student_id uuid, purpose_text text) with pgcrypto schema adaptation.
CREATE OR REPLACE FUNCTION public.issue_student_transcript(target_student_id uuid, purpose_text text DEFAULT 'Academic transcript'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  issued public.transcript_issuances;
  transcript_snapshot jsonb;
  transcript_no text;
  checksum_text text;
  periods integer;
  latest_year text;
  latest_term_text text;
  latest_class_text text;
  school_prefix text;
begin
  if public.current_app_role() not in ('system_admin','principal') then
    raise exception 'Only the System Administrator or Principal can issue a transcript' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'The current licence does not permit transcript issuance' using errcode='42501';
  end if;

  transcript_snapshot:=public.build_student_transcript_snapshot(target_student_id);
  periods:=coalesce((transcript_snapshot->'summary'->>'academic_period_count')::integer,0);
  if periods<1 then
    raise exception 'No published academic results are available for official transcript issuance' using errcode='22023';
  end if;

  select upper(coalesce(nullif(split_part(ss.tenant_code,'-',1),''),'SCH'))
    into school_prefix
  from public.school_settings ss
  order by ss.created_at,ss.id
  limit 1;
  school_prefix:=coalesce(nullif(regexp_replace(school_prefix,'[^A-Z0-9]','','g'),''),'SCH');
  transcript_no:=school_prefix||'-TR-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.transcript_number_seq')::text,6,'0');
  checksum_text:=encode(digest(convert_to(transcript_snapshot::text,'UTF8'),'sha256'),'hex');
  latest_year:=coalesce(transcript_snapshot->'summary'->>'latest_academic_year','');
  latest_term_text:=coalesce(transcript_snapshot->'summary'->>'latest_term','');
  latest_class_text:=coalesce(transcript_snapshot->'summary'->>'latest_class','');

  update public.transcript_issuances
    set status='superseded'
  where student_id=target_student_id and status='valid';

  insert into public.transcript_issuances(
    student_id,transcript_number,purpose,snapshot,snapshot_checksum,academic_period_count,
    latest_academic_year,latest_term,latest_class,template_version
  ) values(
    target_student_id,transcript_no,left(coalesce(nullif(btrim(purpose_text),''),'Academic transcript'),250),
    transcript_snapshot,checksum_text,periods,latest_year,latest_term_text,latest_class_text,'professional-transcript-v1'
  ) returning * into issued;

  insert into public.audit_log(actor_id,table_name,record_id,action,new_data,reason)
  values(
    auth.uid(),'transcript_issuances',issued.id,'ISSUE',
    jsonb_build_object(
      'transcript_number',issued.transcript_number,
      'student_id',issued.student_id,
      'purpose',issued.purpose,
      'academic_period_count',issued.academic_period_count,
      'latest_academic_year',issued.latest_academic_year,
      'latest_term',issued.latest_term,
      'template_version',issued.template_version,
      'snapshot_checksum',issued.snapshot_checksum
    ),issued.purpose
  );

  return jsonb_build_object(
    'id',issued.id,'transcript_number',issued.transcript_number,'verification_token',issued.verification_token,
    'purpose',issued.purpose,'status',issued.status,'issued_at',issued.issued_at,
    'snapshot_checksum',issued.snapshot_checksum,'academic_period_count',issued.academic_period_count,
    'latest_academic_year',issued.latest_academic_year,'latest_term',issued.latest_term,
    'latest_class',issued.latest_class,'template_version',issued.template_version,'snapshot',issued.snapshot
  );
end
$function$;
revoke all on function public.issue_student_transcript(target_student_id uuid, purpose_text text) from public;
grant execute on function public.issue_student_transcript(target_student_id uuid, purpose_text text) to edusentia_worker_runtime;

-- Certified verify_transcript(token uuid) with pgcrypto schema adaptation.
CREATE OR REPLACE FUNCTION public.verify_transcript(token uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case when i.id is null then jsonb_build_object('valid',false,'found',false)
  else jsonb_build_object(
    'found',true,
    'valid',i.status='valid' and i.snapshot_checksum=encode(digest(convert_to(i.snapshot::text,'UTF8'),'sha256'),'hex'),
    'integrity_valid',i.snapshot_checksum=encode(digest(convert_to(i.snapshot::text,'UTF8'),'sha256'),'hex'),
    'status',i.status,
    'transcript_number',i.transcript_number,
    'issued_at',i.issued_at,
    'purpose',i.purpose,
    'student_name',i.snapshot->'student'->>'full_name',
    'admission_no',i.snapshot->'student'->>'admission_no',
    'school_name',i.snapshot->'school'->>'school_name',
    'record_count',i.academic_period_count,
    'cumulative_average',i.snapshot->'summary'->>'cumulative_average',
    'latest_academic_year',i.latest_academic_year,
    'latest_term',i.latest_term,
    'latest_class',i.latest_class,
    'template_version',i.template_version,
    'snapshot_checksum',i.snapshot_checksum,
    'revoked_at',i.revoked_at,
    'revocation_reason',case when i.status='revoked' then i.revocation_reason else '' end
  ) end
  from (select token verification_token) x
  left join public.transcript_issuances i on i.verification_token=x.verification_token
$function$;
revoke all on function public.verify_transcript(token uuid) from public;
grant execute on function public.verify_transcript(token uuid) to edusentia_worker_runtime;


create or replace function public.get_school_license_capacity_console()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public','app','platform','storage','pg_catalog'
as $capacity$
declare
  actor_role text:=coalesce(public.current_app_role()::text,'');
  snapshot jsonb;
  entitlement jsonb;
  plan_data jsonb;
  students_count bigint:=0;
  teachers_count bigint:=0;
  admins_count bigint:=0;
  guardians_count bigint:=0;
  published_reports_count bigint:=0;
  storage_bytes bigint:=0;
  storage_mb numeric:=0;
  storage_breakdown jsonb:='[]'::jsonb;
  verification_rows jsonb:='[]'::jsonb;
  tenant uuid:=app.current_tenant_id();
begin
  if actor_role<>'system_admin' then
    raise exception 'School System Administrator access required' using errcode='42501';
  end if;
  snapshot:=public.license_snapshot_for_role('system_admin');
  entitlement:=public.license_effective_entitlement();
  plan_data:=coalesce(entitlement->'plan',snapshot->'plan','{}'::jsonb);

  select count(*) into students_count from public.students where status='active' and deleted_at is null;
  select count(*) into teachers_count from public.teachers where active and deleted_at is null;
  select count(*) into admins_count from public.profiles where active and public.current_app_role_for(role)::text='system_admin';
  select count(*) into guardians_count from public.profiles where active and public.current_app_role_for(role)::text='parent_guardian';
  select count(*) into published_reports_count from public.student_reports where status='published';

  select coalesce(sum(size_bytes),0)::bigint
    into storage_bytes
  from storage.object_metadata
  where tenant_id=tenant and status='active';
  storage_mb:=round(storage_bytes/1048576.0,2);

  select coalesce(jsonb_agg(jsonb_build_object(
      'bucket_id',bucket_id,'object_count',object_count,'bytes',bucket_bytes,
      'storage_mb',round(bucket_bytes/1048576.0,2)
    ) order by bucket_id),'[]'::jsonb)
  into storage_breakdown
  from (
    select split_part(object_key,'/',3) bucket_id,
           count(*)::bigint object_count,
           coalesce(sum(size_bytes),0)::bigint bucket_bytes
    from storage.object_metadata
    where tenant_id=tenant and status='active'
    group by split_part(object_key,'/',3)
  ) bucket_usage;

  select coalesce(jsonb_agg(jsonb_build_object(
      'created_at',created_at,
      'computed_status',coalesce(metadata->>'computed_status',event_type),
      'access_mode',coalesce(metadata->>'access_mode',''),
      'verification_source','neon_control_plane'
    ) order by created_at desc),'[]'::jsonb)
  into verification_rows
  from (
    select event_type,metadata,created_at
    from app.license_events
    where tenant_id=tenant
    order by created_at desc limit 20
  ) verification_history;

  return jsonb_build_object(
    'read_only',true,'generated_at',now(),
    'school',(select jsonb_build_object('id',id,'school_name',school_name,'logo_url',logo_url,'email',email,'phone',phone) from public.school_settings limit 1),
    'snapshot',snapshot,'plan',plan_data,
    'capacity',jsonb_build_array(
      jsonb_build_object('key','students','label','Active students','unit','records','used',students_count,'limit',nullif(plan_data->>'max_students','')::bigint),
      jsonb_build_object('key','teachers','label','Active teachers','unit','records','used',teachers_count,'limit',nullif(plan_data->>'max_teachers','')::bigint),
      jsonb_build_object('key','system_admins','label','System Administrators','unit','accounts','used',admins_count,'limit',nullif(plan_data->>'max_system_admins','')::bigint),
      jsonb_build_object('key','guardians','label','Guardians','unit','accounts','used',guardians_count,'limit',nullif(plan_data->>'max_guardians','')::bigint),
      jsonb_build_object('key','storage','label','School Storage','unit','MB','used',storage_mb,'limit',nullif(plan_data->>'max_storage_mb','')::numeric)
    ),
    'usage',jsonb_build_object(
      'active_students',students_count,'active_teachers',teachers_count,'active_system_admins',admins_count,
      'active_guardians',guardians_count,'published_reports',published_reports_count,
      'storage_bytes',storage_bytes,'storage_mb',storage_mb
    ),
    'storage_buckets',storage_breakdown,
    'feature_flags',coalesce(plan_data->'feature_flags','{}'::jsonb),
    'verification_history',verification_rows
  );
end
$capacity$;

create or replace function public.get_platform_license_console()
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','platform','storage','authn','pg_catalog'
as $console$
declare
  s jsonb;
  tenant uuid:=app.current_tenant_id();
  storage_mb numeric:=0;
begin
  perform public.require_platform_super_admin();
  s:=public.license_snapshot_for_role('system_admin');

  select round(coalesce(sum(size_bytes),0)/1048576.0,2)
    into storage_mb
  from storage.object_metadata
  where tenant_id=tenant and status='active';

  return jsonb_build_object(
    'school',(select jsonb_build_object('id',x.id,'school_name',x.school_name,'logo_url',x.logo_url,'email',x.email,'phone',x.phone) from public.school_settings x limit 1),
    'snapshot',s,
    'license',(select to_jsonb(l) from app.tenant_licenses l where l.tenant_id=tenant limit 1),
    'plans',coalesce((select jsonb_agg(to_jsonb(p) order by p.active desc,p.sort_order,p.name) from platform.license_plans p),'[]'::jsonb),
    'feature_catalog',coalesce((select jsonb_agg(to_jsonb(f)||jsonb_build_object('category','General','active',true) order by f.name) from platform.license_feature_catalog f),'[]'::jsonb),
    'plan_revisions','[]'::jsonb,
    'active_override',(select jsonb_build_object('feature_overrides',l.feature_overrides,'limits_override',l.limits_override,'updated_at',l.updated_at) from app.tenant_licenses l where l.tenant_id=tenant and (l.feature_overrides<>'{}'::jsonb or l.limits_override<>'{}'::jsonb) limit 1),
    'distribution_authority',(select to_jsonb(a) from public.platform_distribution_authorities a where a.actor_id=auth.uid() limit 1),
    'distribution_authorities',coalesce((select jsonb_agg(to_jsonb(q) order by lower(q.full_name)) from (
      select a.*,p.full_name from public.platform_distribution_authorities a join public.profiles p on p.id=a.actor_id
    ) q),'[]'::jsonb),
    'usage',jsonb_build_object(
      'active_students',(select count(*) from public.students x where x.status='active' and x.deleted_at is null),
      'active_teachers',(select count(*) from public.teachers x where x.active and x.deleted_at is null),
      'active_system_admins',(select count(*) from public.profiles x where x.active and public.current_app_role_for(x.role)::text='system_admin'),
      'active_guardians',(select count(*) from public.profiles x where x.active and public.current_app_role_for(x.role)::text='parent_guardian'),
      'storage_mb',storage_mb,
      'published_reports',(select count(*) from public.student_reports x where x.status='published')
    ),
    'active_locks',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.platform_access_locks x where x.active and (x.ends_at is null or x.ends_at>now())),'[]'::jsonb),
    'recent_events',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select e.*,coalesce(p.full_name,'System') actor_name
      from app.license_events e left join public.profiles p on p.id=e.actor_id
      where e.tenant_id=tenant order by e.created_at desc limit 200
    ) q),'[]'::jsonb),
    'verification_history','[]'::jsonb,
    'archives','[]'::jsonb,
    'platform_admins',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'full_name',p.full_name,'email',u.email,'active',p.active,
      'mfa_required',p.mfa_required,'last_seen_at',p.last_seen_at,'created_at',p.created_at
    ) order by lower(p.full_name))
    from public.profiles p left join authn.users u on u.id=p.id
    where public.current_app_role_for(p.role)::text='platform_super_admin'),'[]'::jsonb)
  );
end
$console$;

create or replace function public.platform_set_license_override(
  feature_overrides jsonb,
  max_students_value integer,
  max_teachers_value integer,
  max_system_admins_value integer,
  max_guardians_value integer,
  max_storage_mb_value integer,
  reason_text text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','platform','storage','pg_catalog'
as $override$
declare
  tenant uuid:=app.current_tenant_id();
  current_license app.tenant_licenses%rowtype;
  plan_row platform.license_plans%rowtype;
  reason text:=btrim(coalesce(reason_text,''));
  flags jsonb:=coalesce(feature_overrides,'{}'::jsonb)-'platform_package_management';
  limit_overrides jsonb:='{}'::jsonb;
  students_count bigint;
  teachers_count bigint;
  admins_count bigint;
  guardians_count bigint;
  storage_mb numeric;
  limit_value integer;
begin
  perform public.require_platform_super_admin();
  if tenant is null then raise exception 'Tenant context is required' using errcode='42501'; end if;
  if length(reason)<5 then raise exception 'An override reason is required' using errcode='22023'; end if;
  if jsonb_typeof(flags)<>'object' or exists(select 1 from jsonb_each(flags) x where jsonb_typeof(x.value)<>'boolean') then
    raise exception 'Every feature override must be a Boolean value' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_each(flags) x where not exists(select 1 from platform.license_feature_catalog f where f.code=x.key)) then
    raise exception 'Feature overrides contain an unknown feature code' using errcode='22023';
  end if;
  if flags->'core_records'='false'::jsonb or flags->'governance'='false'::jsonb then
    raise exception 'core_records and governance cannot be disabled by an entitlement override' using errcode='22023';
  end if;
  if exists(select 1 from (values(max_students_value),(max_teachers_value),(max_system_admins_value),(max_guardians_value),(max_storage_mb_value)) v(n) where n is not null and n<=0) then
    raise exception 'Override capacities must be positive or unlimited' using errcode='22023';
  end if;

  select * into current_license from app.tenant_licenses where tenant_id=tenant for update;
  if current_license.id is null then raise exception 'Platform licence is not configured' using errcode='22023'; end if;
  select * into plan_row from platform.license_plans where id=current_license.plan_id;

  select count(*) into students_count from public.students where status='active' and deleted_at is null;
  select count(*) into teachers_count from public.teachers where active and deleted_at is null;
  select count(*) into admins_count from public.profiles where active and public.current_app_role_for(role)::text='system_admin';
  select count(*) into guardians_count from public.profiles where active and public.current_app_role_for(role)::text='parent_guardian';
  select round(coalesce(sum(size_bytes),0)/1048576.0,2) into storage_mb
    from storage.object_metadata where tenant_id=tenant and status='active';

  limit_value:=coalesce(max_students_value,nullif(plan_row.limits->>'max_students','')::integer);
  if limit_value is not null and students_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override student capacity is below current usage (%)',students_count using errcode='23514'; end if;
  limit_value:=coalesce(max_teachers_value,nullif(plan_row.limits->>'max_teachers','')::integer);
  if limit_value is not null and teachers_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override teacher capacity is below current usage (%)',teachers_count using errcode='23514'; end if;
  limit_value:=coalesce(max_system_admins_value,nullif(plan_row.limits->>'max_system_admins','')::integer);
  if limit_value is not null and admins_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override System Administrator capacity is below current usage (%)',admins_count using errcode='23514'; end if;
  limit_value:=coalesce(max_guardians_value,nullif(plan_row.limits->>'max_guardians','')::integer);
  if limit_value is not null and guardians_count>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override guardian capacity is below current usage (%)',guardians_count using errcode='23514'; end if;
  limit_value:=coalesce(max_storage_mb_value,nullif(plan_row.limits->>'max_storage_mb','')::integer);
  if limit_value is not null and storage_mb>limit_value then raise exception 'LICENSE_CAPACITY_REACHED: Override Storage capacity is below current usage (% MB)',storage_mb using errcode='23514'; end if;

  limit_overrides:=jsonb_strip_nulls(jsonb_build_object(
    'max_students',max_students_value,
    'max_teachers',max_teachers_value,
    'max_system_admins',max_system_admins_value,
    'max_guardians',max_guardians_value,
    'max_storage_mb',max_storage_mb_value
  ));

  update app.tenant_licenses
     set feature_overrides=flags,
         limits_override=limit_overrides,
         updated_at=now()
   where tenant_id=tenant;

  insert into app.license_events(tenant_id,event_type,actor_id,metadata)
  values(tenant,'entitlement_override_set',auth.uid(),jsonb_build_object(
    'reason',reason,'feature_overrides',flags,'limits_override',limit_overrides
  ));

  return public.get_platform_license_console();
end
$override$;

create or replace function public.set_school_logo_reference(target_logo_url text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','storage','app','pg_catalog'
as $logo$
declare
  clean text:=btrim(coalesce(target_logo_url,''));
  sid uuid;
  object_key text;
  tenant uuid:=app.current_tenant_id();
  prefix text;
begin
  if not public.is_system_admin() then
    raise exception 'Only the School System Administrator can change the official school logo' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit school logo changes' using errcode='42501';
  end if;
  select id into sid from public.school_settings order by created_at,id limit 1 for update;
  if sid is null then raise exception 'School identity is unavailable'; end if;

  if clean='assets/school-logo.png' then
    object_key:=null;
  else
    if clean like 'school-branding:%' then
      object_key:=substr(clean,length('school-branding:')+1);
    elsif clean like ('tenants/'||tenant::text||'/school-branding/%') then
      object_key:=clean;
      clean:='school-branding:'||object_key;
    else
      raise exception 'Invalid school logo reference';
    end if;
    prefix:='tenants/'||tenant::text||'/school-branding/';
    if object_key='' or object_key not like prefix||'%' or object_key like '%..%' then
      raise exception 'Invalid school logo reference';
    end if;
    if not exists(
      select 1 from storage.object_metadata
      where tenant_id=tenant and object_key=set_school_logo_reference.object_key
        and status='active' and lower(content_type)='image/png'
    ) then
      raise exception 'The uploaded school logo was not found in protected Storage';
    end if;
  end if;

  update public.school_settings set logo_url=clean,updated_at=now() where id=sid;
  return jsonb_build_object('saved',true,'logo_url',clean,'message','Official school logo saved for future school documents.');
end
$logo$;


create or replace function public.platform_set_access_lock(
  lock_scope_text text,lock_mode_text text,reason_text text,ends_at_value timestamptz default null
) returns jsonb
language plpgsql security definer
set search_path to 'public','app','pg_catalog'
as $lock$
declare new_lock public.platform_access_locks%rowtype; tenant uuid:=app.current_tenant_id();
begin
  perform public.require_platform_super_admin();
  if lock_scope_text not in ('system_admin','school','platform') then raise exception 'Invalid lock scope' using errcode='22023'; end if;
  if lock_mode_text not in ('read_only','deny') then raise exception 'Invalid lock mode' using errcode='22023'; end if;
  if length(trim(coalesce(reason_text,'')))<5 then raise exception 'A clear lock reason is required' using errcode='22023'; end if;
  if ends_at_value is not null and ends_at_value<=now() then raise exception 'Lock end time must be in the future' using errcode='22023'; end if;

  update public.platform_access_locks
     set active=false,released_at=now(),released_by=auth.uid(),
         release_reason='Replaced by a new lock',updated_at=now()
   where active and lock_scope=lock_scope_text;

  insert into public.platform_access_locks(lock_scope,lock_mode,reason,ends_at,created_by)
  values(lock_scope_text,lock_mode_text,trim(reason_text),ends_at_value,auth.uid())
  returning * into new_lock;

  insert into app.license_events(tenant_id,event_type,actor_id,metadata)
  values(tenant,'access_lock_applied',auth.uid(),jsonb_build_object(
    'reason',trim(reason_text),'lock',to_jsonb(new_lock)
  ));

  return public.get_platform_license_console();
end
$lock$;

create or replace function public.platform_release_access_lock(
  target_lock_id uuid,reason_text text default 'Access lock released'
) returns jsonb
language plpgsql security definer
set search_path to 'public','app','pg_catalog'
as $release$
declare old_lock public.platform_access_locks%rowtype; tenant uuid:=app.current_tenant_id();
begin
  perform public.require_platform_super_admin();
  select * into old_lock
  from public.platform_access_locks
  where id=target_lock_id and active
  for update;

  if old_lock.id is null then raise exception 'Active access lock not found' using errcode='P0002'; end if;

  update public.platform_access_locks
     set active=false,released_at=now(),released_by=auth.uid(),
         release_reason=coalesce(nullif(trim(reason_text),''),'Access lock released'),
         updated_at=now()
   where id=target_lock_id;

  insert into app.license_events(tenant_id,event_type,actor_id,metadata)
  values(tenant,'access_lock_released',auth.uid(),jsonb_build_object(
    'reason',coalesce(nullif(trim(reason_text),''),'Access lock released'),
    'old_lock',to_jsonb(old_lock)
  ));

  return public.get_platform_license_console();
end
$release$;

create or replace function public.platform_set_distribution_authority(
  target_actor_id uuid,active_value boolean,can_generate_value boolean,
  can_revoke_value boolean,notes_text text default ''
) returns jsonb
language plpgsql security definer
set search_path to 'public','app','pg_catalog'
as $distribution$
declare caller public.platform_distribution_authorities%rowtype; code text; tenant uuid:=app.current_tenant_id();
begin
  perform public.require_platform_super_admin();

  select * into caller
  from public.platform_distribution_authorities
  where actor_id=auth.uid() and active and can_revoke;

  if caller.id is null and exists(select 1 from public.platform_distribution_authorities) then
    raise exception 'Active distributor revocation authority is required to manage distributor access' using errcode='42501';
  end if;

  if not exists(
    select 1 from public.profiles p
    where p.id=target_actor_id and p.active
      and public.current_app_role_for(p.role)::text='platform_super_admin'
  ) then
    raise exception 'Target account must be an active Platform Super Administrator' using errcode='22023';
  end if;

  if not (active_value and can_generate_value and can_revoke_value)
     and exists(select 1 from public.platform_distribution_authorities)
     and not exists(
       select 1 from public.platform_distribution_authorities a
       where a.actor_id<>target_actor_id and a.active and a.can_generate and a.can_revoke
     ) then
    raise exception 'At least one active distributor must retain both generation and revocation authority' using errcode='23514';
  end if;

  code:='DIST-'||upper(substr(replace(target_actor_id::text,'-',''),1,12));

  insert into public.platform_distribution_authorities(
    actor_id,distributor_code,active,can_generate,can_revoke,notes
  ) values(
    target_actor_id,code,active_value,can_generate_value,can_revoke_value,coalesce(notes_text,'')
  )
  on conflict(actor_id) do update
    set active=excluded.active,
        can_generate=excluded.can_generate,
        can_revoke=excluded.can_revoke,
        notes=excluded.notes,
        updated_at=now();

  insert into app.license_events(tenant_id,event_type,actor_id,metadata)
  values(tenant,'distribution_authority_updated',auth.uid(),jsonb_build_object(
    'reason',coalesce(nullif(btrim(notes_text),''),'Distributor authority updated'),
    'target_actor_id',target_actor_id,'active',active_value,
    'can_generate',can_generate_value,'can_revoke',can_revoke_value
  ));

  return public.get_platform_license_console();
end
$distribution$;

create or replace function public.platform_clear_license_history(
  reason_text text,confirmation_text text
) returns jsonb
language plpgsql security definer
set search_path to 'public','app','pg_catalog'
as $clear$
declare reason text:=btrim(coalesce(reason_text,'')); event_total bigint; tenant uuid:=app.current_tenant_id();
begin
  perform public.require_platform_super_admin();
  if length(reason)<5 then raise exception 'A clear history-reset reason is required' using errcode='22023'; end if;
  if upper(btrim(coalesce(confirmation_text,'')))<>'CLEAR ALL' then
    raise exception 'Type CLEAR ALL exactly to confirm permanent history removal' using errcode='22023';
  end if;

  select count(*) into event_total from app.license_events where tenant_id=tenant;
  delete from app.license_events where tenant_id=tenant;

  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details,created_at)
  values(auth.uid(),'LICENCE_COMPLIANCE_HISTORY_RESET',event_total,
    jsonb_build_object('reason',reason,'license_events_removed',event_total),now());

  return public.get_platform_license_console();
end
$clear$;

create or replace function public.platform_update_license(
  target_plan_id uuid,target_status text,issue_date date,
  activation_date timestamptz default null,
  expiry_date timestamptz default null,
  grace_end_date timestamptz default null,
  license_reference_text text default '',
  notes_text text default '',
  compliance_reason_text text default ''
) returns jsonb
language plpgsql security definer
set search_path to 'public','app','platform','pg_catalog'
as $update_license$
declare
  tenant uuid:=app.current_tenant_id();
  cur app.tenant_licenses%rowtype;
  p platform.license_plans%rowtype;
  preview jsonb;
  effective_activation timestamptz;
  default_term_days integer;
  grace_days integer;
  perpetual_allowed boolean;
  old_json jsonb;
  new_json jsonb;
begin
  perform public.require_platform_super_admin();

  select * into p from platform.license_plans where id=target_plan_id and active;
  if p.id is null then raise exception 'Select an active licence plan' using errcode='22023'; end if;

  select * into cur from app.tenant_licenses where tenant_id=tenant for update;
  if cur.id is null then raise exception 'Platform licence is not configured' using errcode='22023'; end if;

  if target_status not in ('pending_activation','active','grace_period','expired','suspended','revoked','perpetual') then
    raise exception 'Invalid licence status' using errcode='22023';
  end if;
  if issue_date is null or length(btrim(coalesce(license_reference_text,'')))<5 then
    raise exception 'Issue date and a valid licence reference are required' using errcode='22023';
  end if;
  if target_status in ('suspended','revoked') and length(btrim(coalesce(compliance_reason_text,'')))<5 then
    raise exception 'A compliance reason is required' using errcode='22023';
  end if;

  default_term_days:=coalesce(nullif(p.limits->>'default_term_days','')::integer,365);
  grace_days:=coalesce(nullif(p.limits->>'grace_days','')::integer,30);
  perpetual_allowed:=coalesce((p.limits->>'perpetual_allowed')::boolean,false);
  effective_activation:=case
    when target_status in ('active','grace_period','perpetual') then coalesce(activation_date,now())
    else activation_date
  end;

  if target_status in ('active','grace_period','perpetual','expired') and issue_date>current_date then
    raise exception 'Issue date cannot be in the future for this status' using errcode='22023';
  end if;
  if effective_activation is not null and effective_activation::date<issue_date then
    raise exception 'Activation date cannot precede issue date' using errcode='22023';
  end if;
  if target_status in ('active','grace_period','perpetual') and effective_activation>now() then
    raise exception 'Activation date cannot be in the future for an active licence' using errcode='22023';
  end if;
  if target_status='perpetual' and not perpetual_allowed then
    raise exception 'The selected plan does not permit perpetual licensing' using errcode='22023';
  end if;
  if target_status='perpetual' and (expiry_date is not null or grace_end_date is not null) then
    raise exception 'A perpetual licence cannot have expiry or grace dates' using errcode='22023';
  end if;
  if target_status<>'perpetual' and p.billing_cycle in ('monthly','annual') and expiry_date is null then
    raise exception 'This plan requires an expiry date' using errcode='22023';
  end if;
  if expiry_date is not null and (
    expiry_date::date<issue_date or
    (effective_activation is not null and expiry_date<=effective_activation)
  ) then
    raise exception 'Expiry must be after issue and activation' using errcode='22023';
  end if;
  if target_status<>'perpetual'
     and p.billing_cycle in ('monthly','annual')
     and expiry_date>coalesce(effective_activation,issue_date::timestamptz)+make_interval(days=>default_term_days)+interval '1 day' then
    raise exception 'Expiry exceeds the selected plan term of % days',default_term_days using errcode='22023';
  end if;
  if grace_end_date is not null and (
    expiry_date is null or grace_end_date<expiry_date or grace_end_date>expiry_date+make_interval(days=>grace_days)
  ) then
    raise exception 'Grace end must be between expiry and the plan grace limit' using errcode='22023';
  end if;
  if target_status='grace_period' and (
    expiry_date is null or grace_end_date is null or expiry_date>now() or grace_end_date<now()
  ) then
    raise exception 'Grace-period status requires a past expiry and a current grace window' using errcode='22023';
  end if;
  if target_status='expired' and (expiry_date is null or expiry_date>now()) then
    raise exception 'Expired status requires an expiry date that has passed' using errcode='22023';
  end if;
  if target_status='active' and expiry_date is not null and expiry_date<=now() then
    raise exception 'Active status requires a future expiry date' using errcode='22023';
  end if;

  preview:=public.platform_preview_license_change(target_plan_id);
  if not coalesce((preview->>'compatible')::boolean,false) then
    raise exception 'LICENSE_DOWNGRADE_BLOCKED: Current usage exceeds the target plan: %',preview->'excess' using errcode='23514';
  end if;

  old_json:=to_jsonb(cur);
  update app.tenant_licenses as licensed
     set plan_id=p.id,
         status=target_status,
         starts_at=coalesce(effective_activation,issue_date::timestamptz),
         expires_at=case when target_status='perpetual' then null else expiry_date end,
         metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
           'issued_on',issue_date,
           'activated_at',effective_activation,
           'grace_ends_at',case when target_status='perpetual' then null else grace_end_date end,
           'license_reference',btrim(license_reference_text),
           'notes',coalesce(notes_text,''),
           'compliance_reason',coalesce(compliance_reason_text,'')
         ),
         updated_at=now()
   where licensed.tenant_id=tenant
   returning to_jsonb(licensed) into new_json;

  insert into app.license_events(tenant_id,event_type,actor_id,metadata)
  values(tenant,'license_updated',auth.uid(),jsonb_build_object(
    'reason',coalesce(nullif(compliance_reason_text,''),'Platform licence updated'),
    'old_data',old_json,'new_data',new_json
  ));

  return public.get_platform_license_console();
end
$update_license$;

create or replace function public.platform_upsert_license_plan(payload jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public','app','platform','pg_catalog'
as $upsert_plan$
declare
  pid uuid:=public.safe_uuid(payload->>'id');
  p platform.license_plans%rowtype;
  preview jsonb;
  reason text:=btrim(coalesce(payload->>'reason',''));
  plan_code text:=lower(btrim(coalesce(payload->>'code','')));
  plan_name text:=btrim(coalesce(payload->>'name',''));
  cycle text:=lower(btrim(coalesce(payload->>'billing_cycle','annual')));
  support text:=lower(btrim(coalesce(payload->>'support_level','standard')));
  flags jsonb:=coalesce(payload->'feature_flags','{}'::jsonb)-'platform_package_management';
  term_days integer;
  grace_value integer;
  new_limits jsonb;
  next_revision integer;
begin
  perform public.require_platform_super_admin();

  if jsonb_typeof(coalesce(payload,'{}'::jsonb))<>'object' then
    raise exception 'Plan payload must be a JSON object' using errcode='22023';
  end if;
  if length(reason)<5 then
    raise exception 'A plan revision reason is required' using errcode='22023';
  end if;
  if pid is null and plan_code!~'^[a-z][a-z0-9_]{2,39}$' then
    raise exception 'Plan code must contain 3-40 lowercase letters, numbers, or underscores' using errcode='22023';
  end if;
  if length(plan_name)<3 or length(plan_name)>100 then
    raise exception 'Plan name must contain 3-100 characters' using errcode='22023';
  end if;
  if cycle not in ('monthly','annual','custom') then
    raise exception 'Billing cycle must be monthly, annual, or custom' using errcode='22023';
  end if;
  if support not in ('standard','priority','enterprise','custom') then
    raise exception 'Support level must be standard, priority, enterprise, or custom' using errcode='22023';
  end if;
  if jsonb_typeof(flags)<>'object'
     or exists(select 1 from jsonb_each(flags) x where jsonb_typeof(x.value)<>'boolean') then
    raise exception 'Every plan feature flag must be a Boolean value' using errcode='22023';
  end if;
  if exists(
    select 1 from jsonb_each(flags) x
    where not exists(select 1 from platform.license_feature_catalog f where f.code=x.key)
  ) then
    raise exception 'Feature flags contain an unknown feature code' using errcode='22023';
  end if;
  if flags->'core_records' is distinct from 'true'::jsonb
     or flags->'governance' is distinct from 'true'::jsonb then
    raise exception 'Every active school plan must include core_records and governance' using errcode='22023';
  end if;

  term_days:=coalesce(nullif(payload->>'default_term_days','')::integer,365);
  grace_value:=coalesce(nullif(payload->>'grace_days','')::integer,30);
  if term_days not between 1 and 3660 or grace_value not between 0 and 365 then
    raise exception 'Plan term or grace period is outside the permitted range' using errcode='22023';
  end if;
  if exists(
    select 1
    from (values
      (nullif(payload->>'max_students','')::integer),
      (nullif(payload->>'max_teachers','')::integer),
      (nullif(payload->>'max_system_admins','')::integer),
      (nullif(payload->>'max_guardians','')::integer),
      (nullif(payload->>'max_storage_mb','')::integer)
    ) v(n)
    where n is not null and n<=0
  ) then
    raise exception 'Plan capacities must be positive or unlimited' using errcode='22023';
  end if;

  if pid is not null
     and coalesce((payload->>'active')::boolean,true)=false
     and exists(select 1 from app.tenant_licenses where plan_id=pid) then
    raise exception 'A plan assigned to the current licence cannot be deactivated' using errcode='23503';
  end if;

  select coalesce(nullif(limits->>'revision','')::integer,0)+1
    into next_revision
  from platform.license_plans
  where id=pid;
  next_revision:=coalesce(next_revision,1);

  new_limits:=jsonb_strip_nulls(jsonb_build_object(
    'max_students',nullif(payload->>'max_students','')::integer,
    'max_teachers',nullif(payload->>'max_teachers','')::integer,
    'max_system_admins',nullif(payload->>'max_system_admins','')::integer,
    'max_guardians',nullif(payload->>'max_guardians','')::integer,
    'max_storage_mb',nullif(payload->>'max_storage_mb','')::integer,
    'default_term_days',term_days,
    'grace_days',grace_value,
    'perpetual_allowed',coalesce((payload->>'perpetual_allowed')::boolean,false),
    'support_level',support,
    'revision',next_revision
  ));

  if pid is null then
    insert into platform.license_plans(
      code,name,description,billing_cycle,feature_flags,limits,active,sort_order
    ) values(
      plan_code,plan_name,coalesce(payload->>'description',''),cycle,flags,new_limits,
      coalesce((payload->>'active')::boolean,true),100
    )
    returning * into p;
  else
    update platform.license_plans
       set name=plan_name,
           description=coalesce(payload->>'description',''),
           billing_cycle=cycle,
           feature_flags=flags,
           limits=new_limits,
           active=coalesce((payload->>'active')::boolean,active)
     where id=pid
     returning * into p;
    if p.id is null then raise exception 'Licence plan not found' using errcode='22023'; end if;
  end if;

  if exists(select 1 from app.tenant_licenses l where l.plan_id=p.id) then
    preview:=public.platform_preview_license_change(p.id);
    if not coalesce((preview->>'compatible')::boolean,false) then
      raise exception 'LICENSE_CAPACITY_REACHED: The revised plan is below current usage: %',preview->'excess' using errcode='23514';
    end if;
  end if;

  insert into app.license_events(tenant_id,event_type,actor_id,metadata)
  values(app.current_tenant_id(),'plan_revision_created',auth.uid(),jsonb_build_object(
    'reason',reason,'plan',to_jsonb(p),'revision',next_revision
  ));

  return public.get_platform_license_console();
end
$upsert_plan$;

revoke all on function public.get_school_license_capacity_console() from public;
revoke all on function public.get_platform_license_console() from public;
revoke all on function public.platform_set_license_override(jsonb,integer,integer,integer,integer,integer,text) from public;
revoke all on function public.set_school_logo_reference(text) from public;
revoke all on function public.platform_set_access_lock(text,text,text,timestamptz) from public;
revoke all on function public.platform_release_access_lock(uuid,text) from public;
revoke all on function public.platform_set_distribution_authority(uuid,boolean,boolean,boolean,text) from public;
revoke all on function public.platform_clear_license_history(text,text) from public;
revoke all on function public.platform_update_license(uuid,text,date,timestamptz,timestamptz,timestamptz,text,text,text) from public;
revoke all on function public.platform_upsert_license_plan(jsonb) from public;

grant execute on function public.get_school_license_capacity_console() to edusentia_worker_runtime;
grant execute on function public.get_platform_license_console() to edusentia_worker_runtime;
grant execute on function public.platform_set_license_override(jsonb,integer,integer,integer,integer,integer,text) to edusentia_worker_runtime;
grant execute on function public.set_school_logo_reference(text) to edusentia_worker_runtime;
grant execute on function public.platform_set_access_lock(text,text,text,timestamptz) to edusentia_worker_runtime;
grant execute on function public.platform_release_access_lock(uuid,text) to edusentia_worker_runtime;
grant execute on function public.platform_set_distribution_authority(uuid,boolean,boolean,boolean,text) to edusentia_worker_runtime;
grant execute on function public.platform_clear_license_history(text,text) to edusentia_worker_runtime;
grant execute on function public.platform_update_license(uuid,text,date,timestamptz,timestamptz,timestamptz,text,text,text) to edusentia_worker_runtime;
grant execute on function public.platform_upsert_license_plan(jsonb) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0048_certified_provider_rpc_neon_r2')
on conflict do nothing;
update app.release_identity set schema_version='0048' where edition='Edusentia Enterprise Neon Edition';

commit;
