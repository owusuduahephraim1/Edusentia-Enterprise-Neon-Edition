-- Edusentia tenant foundation: public functions
-- Read-only schema snapshot from the live Edusentia Supabase tenant.
-- Snapshot date: 2026-09-21. Contains schema only, no application data or secrets.
SET search_path TO public, extensions, pg_catalog;

SET check_function_bodies=off;

CREATE OR REPLACE FUNCTION public.library_require_access(require_write boolean DEFAULT false, required_capability text DEFAULT 'view'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb; v_license jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_access:=public.library_actor_access();
  if not coalesce((v_access->>'authorized')::boolean,false) then raise exception 'Library management access is not allowed for this user' using errcode='42501'; end if;
  if required_capability is not null and not (v_access->'capabilities' ? required_capability) then raise exception 'Library capability % is required',required_capability using errcode='42501'; end if;
  v_license:=public.license_access_for_actor(auth.uid());
  if not coalesce((v_license->>'read_allowed')::boolean,false) then raise exception 'Library access is unavailable while the school licence is locked' using errcode='42501'; end if;
  if require_write and not coalesce((v_license->>'write_allowed')::boolean,false) then raise exception 'Library changes are unavailable while the school licence is read-only' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return v_access;
end $function$

CREATE OR REPLACE FUNCTION public.library_return_copy(target_loan_id uuid, return_condition_status text DEFAULT 'good'::text, return_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_loan public.library_loans; v_next public.library_reservations; v_copy_status text;
begin
  perform public.library_require_access(true,'circulate');
  select * into v_loan from public.library_loans where id=target_loan_id and status='issued' and returned_at is null for update;
  if v_loan.id is null then raise exception 'Active library loan not found'; end if;
  if return_condition_status not in ('new','good','fair','poor','damaged','lost') then raise exception 'Invalid return condition'; end if;
  update public.library_loans set returned_at=now(),returned_by=auth.uid(),return_condition=return_condition_status,notes=case when return_notes is null then notes else concat_ws(E'\n',notes,return_notes) end,status=case when return_condition_status='lost' then 'lost' else 'returned' end where id=v_loan.id returning * into v_loan;
  if return_condition_status='lost' then v_copy_status:='lost';
  elsif return_condition_status='damaged' then v_copy_status:='damaged';
  else
    select * into v_next from public.library_reservations where book_id=(select book_id from public.library_copies where id=v_loan.copy_id) and status='waiting' order by reserved_at limit 1 for update;
    v_copy_status:=case when v_next.id is null then 'available' else 'reserved' end;
  end if;
  update public.library_copies set condition_status=case when return_condition_status='lost' then condition_status else return_condition_status end,circulation_status=v_copy_status where id=v_loan.copy_id;
  if v_next.id is not null and v_copy_status='reserved' then update public.library_reservations set status='ready',ready_at=now(),expires_at=now()+interval '3 days' where id=v_next.id; end if;
  insert into public.library_inventory_events(copy_id,event_type,details,actor_id) values(v_loan.copy_id,'loan_returned',jsonb_build_object('loan_id',v_loan.id,'condition',return_condition_status,'copy_status',v_copy_status),auth.uid());
  return to_jsonb(v_loan);
end $function$

CREATE OR REPLACE FUNCTION public.library_save_book(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_row public.library_books;
begin
  perform public.library_require_access(true,'catalog_write');
  v_id:=nullif(payload->>'id','')::uuid;
  if v_id is null then
    insert into public.library_books(isbn,title,subtitle,author,additional_authors,publisher,publication_year,edition,category,subject,language,description,cover_url,active,created_by)
    values(nullif(btrim(payload->>'isbn'),''),coalesce(nullif(btrim(payload->>'title'),''),'Untitled'),nullif(btrim(payload->>'subtitle'),''),coalesce(nullif(btrim(payload->>'author'),''),'Unknown'),nullif(btrim(payload->>'additional_authors'),''),nullif(btrim(payload->>'publisher'),''),nullif(payload->>'publication_year','')::integer,nullif(btrim(payload->>'edition'),''),nullif(btrim(payload->>'category'),''),nullif(btrim(payload->>'subject'),''),coalesce(nullif(btrim(payload->>'language'),''),'English'),nullif(btrim(payload->>'description'),''),nullif(btrim(payload->>'cover_url'),''),coalesce((payload->>'active')::boolean,true),auth.uid()) returning * into v_row;
  else
    update public.library_books set isbn=case when payload?'isbn' then nullif(btrim(payload->>'isbn'),'') else isbn end,title=coalesce(nullif(btrim(payload->>'title'),''),title),subtitle=case when payload?'subtitle' then nullif(btrim(payload->>'subtitle'),'') else subtitle end,author=coalesce(nullif(btrim(payload->>'author'),''),author),additional_authors=case when payload?'additional_authors' then nullif(btrim(payload->>'additional_authors'),'') else additional_authors end,publisher=case when payload?'publisher' then nullif(btrim(payload->>'publisher'),'') else publisher end,publication_year=case when payload?'publication_year' then nullif(payload->>'publication_year','')::integer else publication_year end,edition=case when payload?'edition' then nullif(btrim(payload->>'edition'),'') else edition end,category=case when payload?'category' then nullif(btrim(payload->>'category'),'') else category end,subject=case when payload?'subject' then nullif(btrim(payload->>'subject'),'') else subject end,language=coalesce(nullif(btrim(payload->>'language'),''),language),description=case when payload?'description' then nullif(btrim(payload->>'description'),'') else description end,cover_url=case when payload?'cover_url' then nullif(btrim(payload->>'cover_url'),'') else cover_url end,active=coalesce((payload->>'active')::boolean,active) where id=v_id and deleted_at is null returning * into v_row;
    if v_row.id is null then raise exception 'Library title not found'; end if;
  end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.library_save_copy(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_id uuid; v_book uuid; v_accession text; v_row public.library_copies;
begin
  perform public.library_require_access(true,'catalog_write');
  v_id:=nullif(payload->>'id','')::uuid; v_book:=nullif(payload->>'book_id','')::uuid;
  if v_id is null then
    if v_book is null then raise exception 'Book is required'; end if;
    v_accession:=coalesce(nullif(btrim(payload->>'accession_no'),''),public.library_generate_accession_no());
    insert into public.library_copies(book_id,accession_no,barcode,shelf_location,acquisition_date,acquisition_cost,source,condition_status,circulation_status,notes,active,created_by)
    values(v_book,v_accession,coalesce(nullif(btrim(payload->>'barcode'),''),v_accession),nullif(btrim(payload->>'shelf_location'),''),nullif(payload->>'acquisition_date','')::date,nullif(payload->>'acquisition_cost','')::numeric,nullif(btrim(payload->>'source'),''),coalesce(nullif(payload->>'condition_status',''),'good'),'available',nullif(btrim(payload->>'notes'),''),true,auth.uid()) returning * into v_row;
  else
    update public.library_copies c set barcode=case when payload?'barcode' then nullif(btrim(payload->>'barcode'),'') else c.barcode end,shelf_location=case when payload?'shelf_location' then nullif(btrim(payload->>'shelf_location'),'') else c.shelf_location end,acquisition_date=case when payload?'acquisition_date' then nullif(payload->>'acquisition_date','')::date else c.acquisition_date end,acquisition_cost=case when payload?'acquisition_cost' then nullif(payload->>'acquisition_cost','')::numeric else c.acquisition_cost end,source=case when payload?'source' then nullif(btrim(payload->>'source'),'') else c.source end,condition_status=coalesce(nullif(payload->>'condition_status',''),c.condition_status),notes=case when payload?'notes' then nullif(btrim(payload->>'notes'),'') else c.notes end,active=coalesce((payload->>'active')::boolean,c.active) where c.id=v_id and c.deleted_at is null returning * into v_row;
    if v_row.id is null then raise exception 'Library copy not found'; end if;
  end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.library_save_staff_access(target_profile_id uuid, target_library_role text, target_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.library_staff_access;
begin
  perform public.library_require_access(true,'manage_access');
  if target_library_role not in ('librarian','assistant') then raise exception 'Library role must be librarian or assistant'; end if;
  if not exists(select 1 from public.profiles where id=target_profile_id and active) then raise exception 'Active staff profile not found'; end if;
  if not exists(select 1 from public.hr_staff_members where profile_id=target_profile_id and deleted_at is null and active) then raise exception 'Active HR staff record is required before library appointment'; end if;
  insert into public.library_staff_access(profile_id,library_role,active,appointed_by) values(target_profile_id,target_library_role,target_active,auth.uid()) on conflict(profile_id) do update set library_role=excluded.library_role,active=excluded.active,appointed_by=auth.uid(),appointed_at=case when public.library_staff_access.active is distinct from excluded.active or public.library_staff_access.library_role is distinct from excluded.library_role then now() else public.library_staff_access.appointed_at end returning * into v_row;
  if target_active then update public.profiles set mfa_required=true where id=target_profile_id; end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.library_session()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_access jsonb; v_license jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('authorized',false); end if;
  v_access:=public.library_actor_access();
  v_license:=public.license_access_for_actor(auth.uid());
  return v_access||jsonb_build_object('read_allowed',coalesce((v_license->>'read_allowed')::boolean,false),'write_allowed',coalesce((v_license->>'write_allowed')::boolean,false));
end $function$

CREATE OR REPLACE FUNCTION public.library_settings_get()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.library_settings;
begin
  perform public.library_require_access(false,'manage_settings');
  select * into v_row from public.library_settings limit 1;
  if v_row.id is null then raise exception 'Library settings are not initialized'; end if;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.library_staff_access_register()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
begin
  perform public.library_require_access(false,'manage_access');
  return jsonb_build_object('staff',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'profile_id',a.profile_id,'full_name',p.full_name,'app_role',public.current_app_role_for(p.role)::text,'library_role',a.library_role,'active',a.active,'mfa_required',p.mfa_required,'appointed_at',a.appointed_at) order by p.full_name) from public.library_staff_access a join public.profiles p on p.id=a.profile_id),'[]'::jsonb),'candidates',coalesce((select jsonb_agg(jsonb_build_object('profile_id',h.profile_id,'staff_no',h.staff_no,'full_name',btrim(concat_ws(' ',h.first_name,nullif(h.middle_name,''),nullif(h.last_name,''))),'department',h.department,'job_title',h.job_title,'app_role',public.current_app_role_for(p.role)::text) order by h.last_name,h.first_name) from public.hr_staff_members h join public.profiles p on p.id=h.profile_id where h.deleted_at is null and h.active and h.profile_id is not null and p.active and public.current_app_role_for(p.role)::text not in ('system_admin','principal','platform_super_admin','student','parent_guardian')),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.library_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin new.updated_at:=now(); return new; end $function$

CREATE OR REPLACE FUNCTION public.library_update_settings(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare v_row public.library_settings;
begin
  perform public.library_require_access(true,'manage_settings');
  update public.library_settings set student_loan_days=coalesce(nullif(payload->>'student_loan_days','')::integer,student_loan_days),staff_loan_days=coalesce(nullif(payload->>'staff_loan_days','')::integer,staff_loan_days),student_max_loans=coalesce(nullif(payload->>'student_max_loans','')::integer,student_max_loans),staff_max_loans=coalesce(nullif(payload->>'staff_max_loans','')::integer,staff_max_loans),renewal_days=coalesce(nullif(payload->>'renewal_days','')::integer,renewal_days),max_renewals=coalesce(nullif(payload->>'max_renewals','')::integer,max_renewals),overdue_grace_days=coalesce(nullif(payload->>'overdue_grace_days','')::integer,overdue_grace_days) returning * into v_row;
  return to_jsonb(v_row);
end $function$

CREATE OR REPLACE FUNCTION public.license_access_for_actor(actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare actor_role text;
begin
  select public.current_app_role_for(p.role) into actor_role
  from public.profiles p where p.id=actor_id and p.active;
  if actor_role is null then
    return jsonb_build_object('read_allowed',false,'write_allowed',false,'access_mode','locked');
  end if;
  return public.license_snapshot_for_role(actor_role);
end $function$

CREATE OR REPLACE FUNCTION public.license_effective_entitlement()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l public.school_licenses%rowtype;p public.license_plans%rowtype;o public.license_entitlement_overrides%rowtype;plan_json jsonb;
begin
  select * into l from public.school_licenses order by created_at limit 1;
  if l.id is null then return '{}'::jsonb; end if;
  if l.entitlement_snapshot<>'{}'::jsonb then return l.entitlement_snapshot; end if;
  select * into p from public.license_plans where id=l.plan_id;
  plan_json:=jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'description',p.description,
    'billing_cycle',p.billing_cycle,'revision',p.revision,'max_students',p.max_students,
    'max_teachers',p.max_teachers,'max_system_admins',p.max_system_admins,'max_guardians',p.max_guardians,
    'max_storage_mb',p.max_storage_mb,'support_level',p.support_level,'feature_flags',p.feature_flags);
  select * into o from public.license_entitlement_overrides where license_id=l.id and active order by created_at desc limit 1;
  if o.id is not null then
    plan_json:=jsonb_set(plan_json,'{feature_flags}',coalesce(plan_json->'feature_flags','{}'::jsonb)||o.feature_overrides,true);
    if o.max_students is not null then plan_json:=jsonb_set(plan_json,'{max_students}',to_jsonb(o.max_students),true); end if;
    if o.max_teachers is not null then plan_json:=jsonb_set(plan_json,'{max_teachers}',to_jsonb(o.max_teachers),true); end if;
    if o.max_system_admins is not null then plan_json:=jsonb_set(plan_json,'{max_system_admins}',to_jsonb(o.max_system_admins),true); end if;
    if o.max_guardians is not null then plan_json:=jsonb_set(plan_json,'{max_guardians}',to_jsonb(o.max_guardians),true); end if;
    if o.max_storage_mb is not null then plan_json:=jsonb_set(plan_json,'{max_storage_mb}',to_jsonb(o.max_storage_mb),true); end if;
  end if;
  return jsonb_build_object('schema','rce-license-entitlement/v1','plan',plan_json,
    'license',jsonb_build_object('license_reference',l.license_reference,'status',l.status,'issued_on',l.issued_on,
      'activated_at',l.activated_at,'expires_at',l.expires_at,'grace_ends_at',l.grace_ends_at),
    'binding',jsonb_build_object('package_id',l.package_id,'installation_id',l.installation_id,
      'tenant_code',l.tenant_code,'authorized_domains',l.authorized_domains,'project_ref',l.project_ref));
end $function$

CREATE OR REPLACE FUNCTION public.license_feature_enabled(feature_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare clean_code text:=lower(btrim(coalesce(feature_code,''))); value jsonb; core_value jsonb; id_value jsonb;
begin
 value:=public.license_effective_entitlement()#>array['plan','feature_flags',clean_code];
 if jsonb_typeof(value)='boolean' then return value='true'::jsonb;end if;
 core_value:=public.license_effective_entitlement()#>array['plan','feature_flags','core_records'];
 if clean_code in ('id_cards','timetable','school_prospectus') then return jsonb_typeof(core_value)='boolean' and core_value='true'::jsonb;end if;
 if clean_code='staff_id_cards' then id_value:=public.license_effective_entitlement()#>array['plan','feature_flags','id_cards'];return (jsonb_typeof(id_value)='boolean' and id_value='true'::jsonb) or (jsonb_typeof(id_value) is null and jsonb_typeof(core_value)='boolean' and core_value='true'::jsonb);end if;
 return false;
end$function$

CREATE OR REPLACE FUNCTION public.license_feature_for_table(table_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select case
    when table_name in ('class_attendance_registers','student_attendance_entries') then 'attendance'
    when table_name in ('assessment_components','assessment_schemes','assessment_score_entries','grading_scales') then 'assessment'
    when table_name in ('student_reports','subject_results','subject_scores','report_publications','report_revisions','report_workflow_events','report_correction_events','report_correction_requests') then 'report_cards'
    when table_name in ('transcript_issuances','student_lifecycle_events') then 'academic_history'
    when table_name in ('certificates','certificate_batches','certificate_events','teacher_award_categories') then 'certificates'
    when table_name in ('report_card_templates','certificate_templates') then 'uploaded_templates'
    when table_name in ('import_batches','import_errors') then 'bulk_workflow'
    when table_name in ('backup_exports','backup_storage_objects','recovery_test_runs') then 'manual_backup'
    when table_name in ('notification_outbox','notifications') then 'notifications'
    when table_name in ('privacy_requests','data_retention_policies','security_events','security_verification_runs','audit_log','client_error_events','system_maintenance_log','emergency_academic_delegations','emergency_academic_delegation_events','academic_period_controls') then 'governance'
    else 'core_records' end
$function$

CREATE OR REPLACE FUNCTION public.license_read_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when auth.role() in ('service_role','supabase_admin') or auth.role() is null then true
    else coalesce((public.license_snapshot_for_role(public.current_app_role()::text)->>'read_allowed')::boolean,false)
  end
$function$

CREATE OR REPLACE FUNCTION public.license_snapshot_for_role(target_role text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_role text:=coalesce(nullif(target_role,''),public.current_app_role()::text,'');l public.school_licenses%rowtype;
  lock_row public.platform_access_locks%rowtype;e jsonb;p jsonb;computed text;mode text:='full';r boolean:=true;w boolean:=true;
  v_now timestamptz:=now();days_left integer;warning text:='';binding_ok boolean:=true;authority_ok boolean:=true;
begin
  select * into l from public.school_licenses order by created_at limit 1;
  if l.id is null then return jsonb_build_object('configured',false,'computed_status','unlicensed','access_mode','locked','read_allowed',v_role='platform_super_admin','write_allowed',false,'access_locked',true,'warning','No platform licence is configured.'); end if;
  e:=public.license_effective_entitlement();p:=coalesce(e->'plan','{}'::jsonb);
  select * into lock_row from public.platform_access_locks x where x.active and x.starts_at<=v_now and (x.ends_at is null or x.ends_at>v_now)
    and (x.lock_scope in ('platform','school') or (x.lock_scope='system_admin' and v_role='system_admin'))
    order by case x.lock_mode when 'deny' then 2 else 1 end desc,x.created_at desc limit 1;
  computed:=l.status;
  if computed='active' then
    if l.activated_at is null or l.activated_at>v_now then computed:='pending_activation';
    elsif l.expires_at is not null and l.expires_at<v_now then computed:=case when l.grace_ends_at is not null and l.grace_ends_at>=v_now then 'grace_period' else 'expired' end; end if;
  elsif computed='grace_period' and l.grace_ends_at is not null and l.grace_ends_at<v_now then computed:='expired'; end if;
  if l.expires_at is not null then days_left:=floor(extract(epoch from(l.expires_at-v_now))/86400)::integer; end if;
  if l.package_id is not null and v_role<>'platform_super_admin' then
    authority_ok:=l.authority_last_success_at is not null and l.authority_last_success_at>=v_now-interval '72 hours'
      and l.authority_status in ('active','unreachable');
    binding_ok:=l.signature_status='verified' and authority_ok and (auth.uid() is null or exists(select 1 from public.license_binding_sessions s where s.license_id=l.id and s.actor_id=auth.uid() and s.expires_at>v_now));
  end if;
  if v_role='platform_super_admin' then mode:='platform_control';r:=false;w:=false;
  elsif l.signature_status='invalid' then mode:='locked';r:=false;w:=false;warning:='The installed licence signature is invalid.';
  elsif l.package_id is not null and l.authority_status='revoked' then mode:='locked';r:=false;w:=false;warning:='The generated package licence has been revoked by the platform authority.';
  elsif l.package_id is not null and not authority_ok then mode:='read_only';w:=false;warning:='The central licence authority could not confirm this package within the 72-hour verification window.';
  elsif l.package_id is not null and not binding_ok then mode:='read_only';w:=false;warning:='The generated package licence or installation binding has not been verified.';
  elsif computed='revoked' then mode:='locked';r:=false;w:=false;warning:=coalesce(nullif(l.compliance_reason,''),'The platform licence has been revoked.');
  elsif lock_row.id is not null and lock_row.lock_mode='deny' then mode:='locked';r:=false;w:=false;warning:=lock_row.reason;
  elsif computed in ('pending_activation','expired','suspended') then mode:='read_only';w:=false;warning:=case computed when 'pending_activation' then 'The licence is awaiting activation. The system is read-only.' when 'expired' then 'The licence has expired. Existing records remain read-only.' else coalesce(nullif(l.compliance_reason,''),'The licence is suspended.') end;
  elsif lock_row.id is not null and lock_row.lock_mode='read_only' then mode:='read_only';w:=false;warning:=lock_row.reason;
  elsif computed='grace_period' then warning:='The licence is in its grace period.';
  elsif computed='active' and days_left between 0 and 30 then warning:='The licence expires in '||days_left||' day'||case when days_left=1 then '' else 's' end||'.'; end if;
  return jsonb_build_object('configured',true,'license_id',l.id,'license_reference',l.license_reference,'stored_status',l.status,
    'computed_status',computed,'issued_on',l.issued_on,'activated_at',l.activated_at,'expires_at',l.expires_at,'grace_ends_at',l.grace_ends_at,
    'compliance_reason',l.compliance_reason,'plan',p,'entitlement_schema',e->>'schema','package_id',l.package_id,
    'installation_id',l.installation_id,'tenant_code',l.tenant_code,'project_ref',l.project_ref,'authorized_domains',l.authorized_domains,
    'signature_status',l.signature_status,'signature_algorithm',l.signature_algorithm,'signature_key_id',l.signature_key_id,
    'signature_verified_at',l.signature_verified_at,'authority_status',l.authority_status,'authority_checked_at',l.authority_checked_at,'authority_last_success_at',l.authority_last_success_at,'authority_verified',authority_ok,'binding_verified',binding_ok,'access_mode',mode,'read_allowed',r,'write_allowed',w,
    'access_locked',mode='locked','access_lock_status',coalesce(lock_row.lock_scope||':'||lock_row.lock_mode,'unlocked'),
    'active_lock',case when lock_row.id is null then null else jsonb_build_object('id',lock_row.id,'scope',lock_row.lock_scope,'mode',lock_row.lock_mode,'reason',lock_row.reason,'starts_at',lock_row.starts_at,'ends_at',lock_row.ends_at) end,
    'days_remaining',days_left,'warning',warning);
end $function$

CREATE OR REPLACE FUNCTION public.license_write_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when auth.role() in ('service_role','supabase_admin') or auth.role() is null then true
    else coalesce((public.license_snapshot_for_role(public.current_app_role()::text)->>'write_allowed')::boolean,false)
  end
$function$

CREATE OR REPLACE FUNCTION public.list_academic_period_controls()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then raise exception 'Access denied' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(public.term_control_snapshot(t.id) order by y.start_date desc nulls last,t.sequence)
    from public.terms t join public.academic_years y on y.id=t.academic_year_id where t.deleted_at is null),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.list_audit_archive_entries_v1(target_archive_id uuid, page_number integer DEFAULT 1, page_size integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  safe_page integer:=greatest(coalesce(page_number,1),1);
  safe_size integer:=least(greatest(coalesce(page_size,25),1),100);
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if target_archive_id is null then raise exception 'Archive id is required'; end if;
  return (
    with matching as (
      select e.*,p.full_name actor_name,p.role::text actor_role
      from public.audit_log_archive_entries e
      left join public.profiles p on p.id=e.actor_id
      where e.archive_id=target_archive_id
    ), counts as (select count(*)::bigint total from matching)
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.original_created_at desc,q.original_event_id desc) from (
        select * from matching order by original_created_at desc,original_event_id desc limit safe_size offset (safe_page-1)*safe_size
      ) q),'[]'::jsonb),
      'total',(select total from counts),
      'page',safe_page,
      'page_size',safe_size,
      'pages',greatest(1,ceil((select total from counts)::numeric/safe_size)::integer)
    )
  );
end
$function$

CREATE OR REPLACE FUNCTION public.list_audit_archives_v1(page_number integer DEFAULT 1, page_size integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  safe_page integer:=greatest(coalesce(page_number,1),1);
  safe_size integer:=least(greatest(coalesce(page_size,25),1),100);
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return (
    with matching as (
      select a.*,p.full_name created_by_name,p.role::text created_by_role
      from public.audit_log_archives a
      left join public.profiles p on p.id=a.created_by
    ), counts as (select count(*)::bigint total from matching)
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc) from (
        select * from matching order by created_at desc,id desc limit safe_size offset (safe_page-1)*safe_size
      ) q),'[]'::jsonb),
      'total',(select total from counts),
      'page',safe_page,
      'page_size',safe_size,
      'pages',greatest(1,ceil((select total from counts)::numeric/safe_size)::integer)
    )
  );
end
$function$

CREATE OR REPLACE FUNCTION public.list_audit_events(target_table text DEFAULT NULL::text, target_record_id uuid DEFAULT NULL::uuid, page_number integer DEFAULT 1, page_size integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return (
    with matching as (
      select a.*,p.full_name actor_name from public.audit_log a left join public.profiles p on p.id=a.actor_id
      where (target_table is null or a.table_name=target_table) and (target_record_id is null or a.record_id=target_record_id)
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
        select * from matching order by created_at desc limit least(greatest(page_size,1),100) offset greatest(page_number-1,0)*least(greatest(page_size,1),100)
      ) q),'[]'::jsonb),
      'total',(select count(*) from matching)
    )
  );
end $function$

CREATE OR REPLACE FUNCTION public.list_audit_events_v2(target_table text DEFAULT NULL::text, target_action text DEFAULT NULL::text, target_actor_id uuid DEFAULT NULL::uuid, target_record_id uuid DEFAULT NULL::uuid, page_number integer DEFAULT 1, page_size integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  safe_page integer:=greatest(coalesce(page_number,1),1);
  safe_size integer:=least(greatest(coalesce(page_size,25),1),100);
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return (
    with matching as (
      select a.*,p.full_name actor_name,p.role::text actor_role
      from public.audit_log a
      left join public.profiles p on p.id=a.actor_id
      where (target_table is null or a.table_name=target_table)
        and (target_action is null or a.action=target_action)
        and (target_actor_id is null or a.actor_id=target_actor_id)
        and (target_record_id is null or a.record_id=target_record_id)
    ), counts as (
      select count(*)::bigint total from matching
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc) from (
        select * from matching order by created_at desc,id desc limit safe_size offset (safe_page-1)*safe_size
      ) q),'[]'::jsonb),
      'total',(select total from counts),
      'page',safe_page,
      'page_size',safe_size,
      'pages',greatest(1,ceil((select total from counts)::numeric/safe_size)::integer),
      'tables',coalesce((select jsonb_agg(x.table_name order by x.table_name) from (select distinct table_name from public.audit_log) x),'[]'::jsonb),
      'actions',coalesce((select jsonb_agg(x.action order by x.action) from (select distinct action from public.audit_log) x),'[]'::jsonb)
    )
  );
end
$function$

CREATE OR REPLACE FUNCTION public.list_certificate_eligible_recipients(target_certificate_type text, target_academic_year_id uuid, target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare completion_class uuid;
begin
  if not public.can_manage_certificates() then raise exception 'Only the System Administrator can prepare certificates' using errcode='42501'; end if;
  if target_certificate_type='student_promotion' then
    if target_term_id is null or target_class_id is null then raise exception 'Term and class are required for promotion certificates'; end if;
    if not exists(select 1 from public.terms where id=target_term_id and academic_year_id=target_academic_year_id and sequence=3 and deleted_at is null) then raise exception 'Promotion certificates require Term 3'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'recipient_name',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'identifier',st.admission_no,
      'current_class_name',c.name,'destination_class_name',pc.name,'source_report_id',r.id,
      'already_issued',exists(select 1 from public.certificates x join public.certificate_batches xb on xb.id=x.batch_id where x.student_id=st.id and xb.academic_year_id=target_academic_year_id and xb.certificate_type='student_promotion' and x.status in ('draft','approved','issued'))
    ) order by st.last_name,st.first_name,st.middle_name)
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.students st on st.id=e.student_id join public.classes c on c.id=e.class_id
      join public.classes pc on pc.id=r.promoted_to_class_id
      where r.term_id=target_term_id and e.academic_year_id=target_academic_year_id and e.class_id=target_class_id
        and r.status='published' and r.deleted_at is null and e.deleted_at is null and st.deleted_at is null
    ),'[]'::jsonb);
  elsif target_certificate_type='jhs_completion' then
    select certificate_completion_class_id into completion_class from public.school_settings limit 1;
    if target_class_id is null then raise exception 'Completion class is required'; end if;
    if completion_class is not null and target_class_id<>completion_class then raise exception 'Select the configured JHS 3 completion class'; end if;
    if completion_class is null and not exists(select 1 from public.classes c where c.id=target_class_id and lower(c.name::text) ~ '(basic[[:space:]]*9|jhs[[:space:]]*3|junior[[:space:]]+high.*3)') then raise exception 'The selected class is not configured as JHS 3'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'recipient_name',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'identifier',st.admission_no,
      'current_class_name',c.name,'destination_class_name','','source_report_id',r.id,
      'already_issued',exists(select 1 from public.certificates x join public.certificate_batches xb on xb.id=x.batch_id where x.student_id=st.id and xb.academic_year_id=target_academic_year_id and xb.certificate_type='jhs_completion' and x.status in ('draft','approved','issued'))
    ) order by st.last_name,st.first_name,st.middle_name)
      from public.enrollments e join public.students st on st.id=e.student_id join public.classes c on c.id=e.class_id
      left join lateral(select sr.id from public.student_reports sr join public.terms tr on tr.id=sr.term_id
        where sr.enrollment_id=e.id and sr.status='published' and sr.deleted_at is null
          and (target_term_id is null or sr.term_id=target_term_id)
        order by tr.sequence desc,sr.published_at desc nulls last limit 1) r on true
      where e.academic_year_id=target_academic_year_id and e.class_id=target_class_id and e.deleted_at is null and st.deleted_at is null and r.id is not null
    ),'[]'::jsonb);
  elsif target_certificate_type='teacher_recognition' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,'recipient_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'identifier',t.staff_no,
      'employment_status',t.employment_status,'already_issued',false
    ) order by t.last_name,t.first_name,t.middle_name)
      from public.teachers t where t.deleted_at is null and t.employment_status<>'suspended'
    ),'[]'::jsonb);
  end if;
  raise exception 'Certificate type is invalid';
end $function$

CREATE OR REPLACE FUNCTION public.list_client_health_events(page_size integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare lim integer:=least(greatest(coalesce(page_size,50),1),200);
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'open_faults',(select coalesce(sum(occurrence_count),0) from public.client_error_events where status='open' and severity in ('error','critical')),
      'warnings_24h',(select coalesce(sum(occurrence_count),0) from public.client_error_events where last_seen_at>=now()-interval '24 hours' and severity='warning'),
      'faults_24h',(select coalesce(sum(occurrence_count),0) from public.client_error_events where last_seen_at>=now()-interval '24 hours' and status='open' and severity in ('error','critical'))
    ),
    'events',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'severity',e.severity,'category',e.category,'status',e.status,'message',e.message,
      'source',e.context->>'source','view',e.context->>'view','occurrence_count',e.occurrence_count,
      'first_seen_at',e.first_seen_at,'last_seen_at',e.last_seen_at,'actor_name',p.full_name,
      'resolution_note',e.resolution_note
    ) order by e.last_seen_at desc)
    from (select * from public.client_error_events order by last_seen_at desc limit lim) e
    left join public.profiles p on p.id=e.actor_id),'[]'::jsonb)
  );
end
$function$

CREATE OR REPLACE FUNCTION public.list_guardian_portal_accounts(search_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not (public.is_records_manager() or public.has_role(array['class_teacher'])) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',p.id,'full_name',p.full_name,'email',u.email,'phone',p.phone
    ) order by p.full_name)
    from public.profiles p
    left join auth.users u on u.id=p.id
    where p.active and public.current_app_role_for(p.role)='parent_guardian'
      and (coalesce(search_text,'')='' or p.full_name ilike '%'||search_text||'%'
        or coalesce(u.email,'') ilike '%'||search_text||'%' or p.phone ilike '%'||search_text||'%')
  ),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.list_headteachers(search_text text DEFAULT ''::text, status_filter text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);limit_value integer:=least(greatest(page_size,1),100);
begin
  if not public.can_manage_headteachers() then raise exception 'Access denied' using errcode='42501';end if;if archive_filter not in ('active','archived','all') then archive_filter:='active';end if;
  return (with matching as (
    select h.id,h.profile_id,h.staff_no,h.first_name,h.middle_name,h.last_name,h.gender,h.phone,h.email,h.address,h.qualification,h.date_appointed,h.employment_status,h.notes,h.photo_url,h.active,h.signature_path,h.signature_updated_at,h.deleted_at,h.created_at,h.updated_at,concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name) full_name,p.role profile_role,p.active profile_active,au.email profile_email
    from public.headteachers h left join public.profiles p on p.id=h.profile_id left join auth.users au on au.id=h.profile_id
    where (archive_filter='all' or (archive_filter='active' and h.deleted_at is null) or (archive_filter='archived' and h.deleted_at is not null)) and (coalesce(status_filter,'')='' or h.employment_status=status_filter)
      and (coalesce(search_text,'')='' or h.staff_no::text ilike '%'||search_text||'%' or concat_ws(' ',h.first_name,h.middle_name,h.last_name) ilike '%'||search_text||'%' or coalesce(h.phone,'') ilike '%'||search_text||'%' or coalesce(au.email::text,'') ilike '%'||search_text||'%')
  ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.full_name),x.staff_no::text) from (select * from matching order by lower(full_name),staff_no::text limit limit_value offset offset_value)x),'[]'::jsonb),'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value));
end$function$

CREATE OR REPLACE FUNCTION public.list_id_card_candidates(target_academic_year_id uuid, target_class_id uuid DEFAULT NULL::uuid, search_text text DEFAULT ''::text)
 RETURNS TABLE(student_id uuid, enrollment_id uuid, full_name text, admission_no text, class_id uuid, class_name text, academic_year_id uuid, academic_year_name text, photo_url text, gender text, date_of_birth date, guardian_phone text, active_card_id uuid, active_card_number text, active_card_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin if not public.is_system_admin() then raise exception 'Only the System Administrator can manage student ID cards' using errcode='42501';end if;perform public.require_license_feature('id_cards');if not public.license_read_allowed() then raise exception 'LICENSE_READ_RESTRICTED: The current licence does not permit ID card access' using errcode='42501';end if; return query select st.id,e.id,concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),st.admission_no::text,c.id,c.name::text,y.id,y.name::text,st.photo_url,st.gender,st.date_of_birth,coalesce((select nullif(g.phone,'') from public.guardian_links gl join public.student_guardians g on g.id=gl.guardian_id where gl.student_id=st.id order by g.is_primary desc,gl.created_at limit 1),nullif(st.guardian_phone,''),'') guardian_phone,card.id,card.card_number,case when card.id is null then '' else public.id_card_effective_status(card.status,card.expires_on) end from public.enrollments e join public.students st on st.id=e.student_id and st.deleted_at is null and st.status='active' join public.classes c on c.id=e.class_id and c.deleted_at is null and c.active join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null left join lateral(select x.id,x.card_number,x.status,x.expires_on from public.student_id_cards x where x.student_id=st.id and x.academic_year_id=e.academic_year_id and x.status='active' order by x.issued_at desc limit 1) card on true where e.deleted_at is null and e.active and e.academic_year_id=target_academic_year_id and (target_class_id is null or e.class_id=target_class_id) and (btrim(coalesce(search_text,''))='' or st.admission_no::text ilike '%'||btrim(search_text)||'%' or concat_ws(' ',st.first_name,st.middle_name,st.last_name) ilike '%'||btrim(search_text)||'%') order by c.level_order nulls last,c.name,st.last_name,st.first_name; end$function$

CREATE OR REPLACE FUNCTION public.list_my_attendance_classes(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role()<>'class_teacher' then raise exception 'Only assigned class teachers can use attendance' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'level_order',c.level_order,
      'student_count',(select count(*) from public.enrollments e join public.students s on s.id=e.student_id and s.deleted_at is null and s.status='active'
        where e.class_id=c.id and e.deleted_at is null and (target_term_id is null or e.academic_year_id=(select t.academic_year_id from public.terms t where t.id=target_term_id)))
    ) order by c.level_order,c.name)
    from public.classes c
    where c.class_teacher_id=auth.uid() and c.active and c.deleted_at is null
  ),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.list_my_children_reports()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
 if public.current_app_role()<>'parent_guardian' then raise exception 'Access denied' using errcode='42501'; end if;
 return jsonb_build_object('children',coalesce((select jsonb_agg(jsonb_build_object(
   'id',s.id,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'admission_no',s.admission_no,'class_name',coalesce(c.name,''),'financial_hold',public.finance_student_hold_status(s.id),
   'reports',case when coalesce((public.finance_student_hold_status(s.id)->>'block_grade_details')::boolean,false) then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'report_number',r.report_number,'status',r.status,'term_name',t.name,'academic_year_name',y.name,'average',coalesce((select round(avg(sr.total_score),2) from public.subject_results sr where sr.report_id=r.id),0),'published_at',r.published_at,'publication',case when coalesce((public.finance_student_hold_status(s.id)->>'block_report_pdf')::boolean,false) then null else jsonb_build_object('id',rp.id,'storage_path',rp.storage_path,'checksum',rp.checksum,'page_count',rp.page_count,'published_at',rp.published_at) end) order by y.start_date desc nulls last,t.sequence desc) from public.enrollments er join public.student_reports r on r.enrollment_id=er.id and r.status='published' and r.deleted_at is null join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id join public.report_publications rp on rp.report_id=r.id and rp.revoked_at is null where er.student_id=s.id and er.deleted_at is null),'[]'::jsonb) end
 ) order by s.last_name,s.first_name) from public.guardian_links gl join public.students s on s.id=gl.student_id and s.deleted_at is null left join lateral(select e.class_id from public.enrollments e where e.student_id=s.id and e.active and e.deleted_at is null order by e.updated_at desc limit 1) ce on true left join public.classes c on c.id=ce.class_id where gl.auth_user_id=auth.uid() and gl.can_view_reports),'[]'::jsonb));
end $function$

CREATE OR REPLACE FUNCTION public.list_notifications(page_number integer DEFAULT 1, page_size integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with matching as (
    select n.* from public.notifications n where n.recipient_id=auth.uid()
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select * from matching order by created_at desc
      limit least(greatest(page_size,1),100)
      offset greatest(page_number-1,0)*least(greatest(page_size,1),100)
    ) q),'[]'::jsonb),
    'total',(select count(*) from matching),
    'unread',(select count(*) from matching where read_at is null)
  )
$function$

CREATE OR REPLACE FUNCTION public.list_profiles_with_access()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
begin
  if not public.is_system_admin() then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  return jsonb_build_object(
    'profiles',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'full_name',p.full_name,'email',au.email,'role',public.current_app_role_for(p.role),
      'active',p.active,'mfa_required',p.mfa_required,'must_change_password',p.must_change_password,'phone',p.phone,'last_seen_at',p.last_seen_at,
      'account_created_at',au.created_at,'email_confirmed_at',au.email_confirmed_at,'last_sign_in_at',au.last_sign_in_at,
      'teacher_id',t.id,'headteacher_id',h.id,'accountant_id',a.id,'student_id',s.id,
      'staff_record_id',coalesce(h.id,t.id,a.id,s.id),'staff_no',coalesce(h.staff_no::text,t.staff_no::text,a.staff_no::text,s.admission_no::text),
      'access',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'class_id',x.class_id,'class_name',c.name,'subject_id',x.subject_id,'subject_name',sub.name,'access_level',x.access_level) order by lower(c.name),lower(sub.name) nulls first) from public.user_class_access x join public.classes c on c.id=x.class_id left join public.subjects sub on sub.id=x.subject_id where x.user_id=p.id),'[]'::jsonb)
    ) order by lower(p.full_name),p.id)
    from public.profiles p left join auth.users au on au.id=p.id
    left join public.teachers t on t.profile_id=p.id and t.deleted_at is null
    left join public.headteachers h on h.profile_id=p.id and h.deleted_at is null
    left join public.accounts_office_staff a on a.profile_id=p.id and a.deleted_at is null
    left join public.students s on s.profile_id=p.id and s.deleted_at is null
    where public.current_app_role_for(p.role) in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian','accountant','student')),'[]'::jsonb),
    'teacher_records',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'profile_id',t.profile_id,'staff_no',t.staff_no,'first_name',t.first_name,'middle_name',t.middle_name,'last_name',t.last_name,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'label',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)||' • '||t.staff_no::text,'phone',t.phone,'email',t.email,'active',t.active) order by lower(concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)),t.staff_no::text) from public.teachers t where t.deleted_at is null and t.active),'[]'::jsonb),
    'headteacher_records',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'profile_id',h.profile_id,'staff_no',h.staff_no,'first_name',h.first_name,'middle_name',h.middle_name,'last_name',h.last_name,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'label',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)||' • '||h.staff_no::text,'phone',h.phone,'email',h.email,'active',h.active) order by lower(concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)),h.staff_no::text) from public.headteachers h where h.deleted_at is null and h.active),'[]'::jsonb),
    'accountant_records',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'profile_id',a.profile_id,'staff_no',a.staff_no,'full_name',a.full_name,'label',a.full_name||' • '||a.staff_no::text,'phone',a.phone,'email',a.email,'contact_address',a.contact_address,'active',a.active) order by lower(a.full_name),a.staff_no::text) from public.accounts_office_staff a where a.deleted_at is null and a.active),'[]'::jsonb),
    'student_records',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'profile_id',s.profile_id,'admission_no',s.admission_no,'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),'label',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)||' • '||s.admission_no::text,'class_id',e.class_id,'class_name',c.name,'active',s.status='active') order by c.level_order,s.last_name,s.first_name) from public.students s left join lateral(select x.class_id from public.enrollments x where x.student_id=s.id and x.active and x.deleted_at is null order by x.updated_at desc limit 1)e on true left join public.classes c on c.id=e.class_id where s.deleted_at is null and s.status='active'),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(to_jsonb(c) order by c.level_order,c.name) from public.classes c where c.deleted_at is null),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(sub) order by sub.display_order,sub.name) from public.subjects sub where sub.deleted_at is null),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'class_id',cs.class_id,'subject_id',cs.subject_id,'teacher_id',cs.teacher_id,'active',cs.active)) from public.class_subjects cs),'[]'::jsonb)
  );
end $function$

CREATE OR REPLACE FUNCTION public.list_report_card_templates()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by
      case t.range_key when 'early_years' then 1 when 'basic_1_6' then 2 else 3 end
    )
    from public.report_card_templates t
    where t.active
  ),'[]'::jsonb);
end $function$

CREATE OR REPLACE FUNCTION public.list_report_cards(target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, target_status report_status DEFAULT NULL::report_status, search_text text DEFAULT ''::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
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
      select r.id,r.report_number,r.status,r.version,r.updated_at,r.published_at,
        e.student_id,e.class_id,r.term_id,s.admission_no,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        s.photo_url,c.name class_name,t.name term_name,y.name academic_year_name,
        round(coalesce(avg(sr.total_score),0),2) average,
        count(sr.id) subject_count
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id join public.academic_years y on y.id=t.academic_year_id
      left join public.subject_results sr on sr.report_id=r.id
      where r.deleted_at is null and public.can_view_report(r.id)
        and (target_term_id is null or r.term_id=target_term_id)
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or r.status=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
      group by r.id,e.id,s.id,c.id,t.id,y.id
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from (
        select * from matching order by updated_at desc limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end $function$

CREATE OR REPLACE FUNCTION public.list_report_cards_v6(target_term_id uuid DEFAULT NULL::uuid, target_class_id uuid DEFAULT NULL::uuid, target_status report_status DEFAULT NULL::report_status, search_text text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);
declare limit_value integer:=least(greatest(page_size,1),100);
begin
  if archive_filter not in ('active','archived','all') then archive_filter:='active'; end if;
  if archive_filter<>'active' and not (public.is_academic_manager() or public.has_role(array['class_teacher'])) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return (
    with matching as (
      select r.id,r.report_number,r.status,r.archived_status,r.version,r.updated_at,r.published_at,r.deleted_at,
        (r.deleted_at is not null) archived,e.student_id,e.class_id,r.term_id,s.admission_no,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        s.photo_url,c.name class_name,t.name term_name,y.name academic_year_name,
        round(coalesce(avg(sr.total_score),0),2) average,count(sr.id) subject_count
      from public.student_reports r
      join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id
      join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id
      join public.academic_years y on y.id=t.academic_year_id
      left join public.subject_results sr on sr.report_id=r.id
      where public.can_view_report(r.id)
        and (archive_filter='all' or (archive_filter='active' and r.deleted_at is null)
          or (archive_filter='archived' and r.deleted_at is not null))
        and (target_term_id is null or r.term_id=target_term_id)
        and (target_class_id is null or e.class_id=target_class_id)
        and (target_status is null or coalesce(r.archived_status,r.status)=target_status)
        and (coalesce(search_text,'')='' or s.admission_no::text ilike '%'||search_text||'%'
          or coalesce(r.report_number::text,'') ilike '%'||search_text||'%'
          or concat_ws(' ',s.first_name,s.middle_name,s.last_name) ilike '%'||search_text||'%')
      group by r.id,e.id,s.id,c.id,t.id,y.id
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc) from (
        select * from matching order by updated_at desc limit limit_value offset offset_value
      ) x),'[]'::jsonb),
      'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value
    )
  );
end $function$

CREATE OR REPLACE FUNCTION public.list_report_pdf_paths(target_report_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.can_delete_report(target_report_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  return coalesce(
    (select array_agg(distinct p.storage_path order by p.storage_path)
     from public.report_publications p
     where p.report_id=target_report_id and btrim(coalesce(p.storage_path,''))<>''),
    '{}'::text[]
  );
end $function$

CREATE OR REPLACE FUNCTION public.list_staff_id_card_candidates(target_staff_type text DEFAULT NULL::text, search_text text DEFAULT ''::text)
 RETURNS TABLE(staff_key text, staff_type text, staff_id uuid, full_name text, staff_no text, secondary_id text, role_label text, photo_url text, qualification text, active_card_id uuid, active_card_number text, active_card_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare kind text:=lower(btrim(coalesce(target_staff_type,'')));
begin
  if not public.is_system_admin() then
    raise exception 'Only the System Administrator can list staff ID card candidates' using errcode='42501';
  end if;
  perform public.require_license_feature('staff_id_cards');
  if kind not in ('','teacher','principal') then raise exception 'Invalid staff type filter'; end if;

  return query
  select q.staff_key,q.staff_type,q.staff_id,q.full_name,q.staff_no,q.secondary_id,q.role_label,q.photo_url,q.qualification,q.active_card_id,q.active_card_number,q.active_card_status
  from (
    select
      'teacher:'||t.id::text as staff_key,
      'teacher'::text as staff_type,
      t.id as staff_id,
      concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name)::text as full_name,
      t.staff_no::text as staff_no,
      coalesce(t.emis_code::text,'') as secondary_id,
      'Teacher'::text as role_label,
      t.photo_url::text as photo_url,
      t.qualification::text as qualification,
      card.id as active_card_id,
      card.card_number::text as active_card_number,
      case when card.id is null then '' else public.id_card_effective_status(card.status,card.expires_on) end::text as active_card_status
    from public.teachers t
    left join lateral (
      select c.id,c.card_number,c.status,c.expires_on
      from public.staff_id_cards c
      where c.teacher_id=t.id and c.status='active'
      order by c.issued_at desc
      limit 1
    ) card on true
    where t.deleted_at is null
      and t.active
      and t.employment_status='active'
      and kind in ('','teacher')
      and (
        btrim(coalesce(search_text,''))=''
        or t.staff_no::text ilike '%'||btrim(search_text)||'%'
        or coalesce(t.emis_code::text,'') ilike '%'||btrim(search_text)||'%'
        or concat_ws(' ',t.first_name,t.middle_name,t.last_name) ilike '%'||btrim(search_text)||'%'
      )

    union all

    select
      'principal:'||h.id::text as staff_key,
      'principal'::text as staff_type,
      h.id as staff_id,
      concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name)::text as full_name,
      h.staff_no::text as staff_no,
      ''::text as secondary_id,
      'Principal'::text as role_label,
      h.photo_url::text as photo_url,
      h.qualification::text as qualification,
      card.id as active_card_id,
      card.card_number::text as active_card_number,
      case when card.id is null then '' else public.id_card_effective_status(card.status,card.expires_on) end::text as active_card_status
    from public.headteachers h
    left join lateral (
      select c.id,c.card_number,c.status,c.expires_on
      from public.staff_id_cards c
      where c.headteacher_id=h.id and c.status='active'
      order by c.issued_at desc
      limit 1
    ) card on true
    where h.deleted_at is null
      and h.active
      and h.employment_status='active'
      and kind in ('','principal')
      and (
        btrim(coalesce(search_text,''))=''
        or h.staff_no::text ilike '%'||btrim(search_text)||'%'
        or concat_ws(' ',h.first_name,h.middle_name,h.last_name) ilike '%'||btrim(search_text)||'%'
      )
  ) q
  order by q.role_label,lower(q.full_name),q.staff_no;
end$function$

CREATE OR REPLACE FUNCTION public.list_teachers(search_text text DEFAULT ''::text, status_filter text DEFAULT ''::text, archive_filter text DEFAULT 'active'::text, page_number integer DEFAULT 1, page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare offset_value integer:=greatest(page_number-1,0)*least(greatest(page_size,1),100);limit_value integer:=least(greatest(page_size,1),100);
begin
  if not public.can_manage_teachers() then raise exception 'Access denied' using errcode='42501';end if;if archive_filter not in ('active','archived','all') then archive_filter:='active';end if;
  return (with matching as (
    select t.id,t.profile_id,t.staff_no,t.emis_code,t.first_name,t.middle_name,t.last_name,t.gender,t.date_of_birth,t.phone,t.email,t.address,t.qualification,t.specialization,t.date_joined,t.employment_status,t.notes,t.photo_url,t.active,t.deleted_at,t.created_at,t.updated_at,concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name) full_name,p.role profile_role,p.active profile_active,au.email profile_email,
      coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.level_order,c.name) from public.classes c where c.class_teacher_id=t.profile_id and c.deleted_at is null),'[]'::jsonb) class_assignments,
      coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'subject_id',s.id,'subject_name',s.name) order by c.level_order,c.name,s.display_order,s.name) from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id where cs.teacher_id=t.profile_id and cs.active and c.deleted_at is null and s.deleted_at is null),'[]'::jsonb) subject_assignments
    from public.teachers t left join public.profiles p on p.id=t.profile_id left join auth.users au on au.id=t.profile_id
    where (archive_filter='all' or (archive_filter='active' and t.deleted_at is null) or (archive_filter='archived' and t.deleted_at is not null)) and (coalesce(status_filter,'')='' or t.employment_status=status_filter)
      and (coalesce(search_text,'')='' or t.staff_no::text ilike '%'||search_text||'%' or coalesce(t.emis_code::text,'') ilike '%'||search_text||'%' or concat_ws(' ',t.first_name,t.middle_name,t.last_name) ilike '%'||search_text||'%' or coalesce(t.email::text,'') ilike '%'||search_text||'%' or coalesce(t.phone,'') ilike '%'||search_text||'%')
  ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.last_name,x.first_name) from (select * from matching order by last_name,first_name limit limit_value offset offset_value)x),'[]'::jsonb),'total',(select count(*) from matching),'page',greatest(page_number,1),'page_size',limit_value,'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',public.current_app_role_for(p.role),'email',au.email) order by p.full_name) from public.profiles p left join auth.users au on au.id=p.id where p.active and public.current_app_role_for(p.role) in ('class_teacher','subject_teacher')),'[]'::jsonb)));
end$function$

CREATE OR REPLACE FUNCTION public.log_client_error(message_text text, stack_text text DEFAULT ''::text, context_data jsonb DEFAULT '{}'::jsonb, user_agent_text text DEFAULT ''::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  eventid bigint;
  msg text:=left(btrim(coalesce(message_text,'')),4000);
  ctx jsonb:=coalesce(context_data,'{}'::jsonb);
  src text:=left(coalesce(context_data->>'source',''),120);
  vw text:=left(coalesce(context_data->>'view',''),120);
  sev text:='error';
  cat text:='application';
  fp text;
  recent_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if msg='' then msg:='Unspecified client error'; end if;

  if pg_column_size(ctx)>8192 then
    ctx:=jsonb_strip_nulls(jsonb_build_object('source',nullif(src,''),'view',nullif(vw,''),'truncated',true));
  end if;

  if msg='Attendance date is before the selected term' or msg='invalid account details' or msg='activation_code_invalid_or_expired' then
    sev:='warning';cat:='validation';
  elsif msg ilike 'JWT issued at future%' then
    sev:='warning';cat:='auth_clock_skew';
  elsif msg ilike 'permission denied%' or msg ilike 'Access denied%' then
    sev:='error';cat:='authorization';
  elsif msg ilike '%Failed to fetch%' then
    sev:='error';cat:='network';
  end if;

  fp:=encode(extensions.digest(convert_to(lower(msg)||'|'||src||'|'||vw||'|'||auth.uid()::text,'UTF8'),'sha256'),'hex');

  select count(*) into recent_count
  from public.client_error_events
  where actor_id=auth.uid() and last_seen_at>=now()-interval '1 minute';
  if recent_count>=20 then
    select id into eventid from public.client_error_events where actor_id=auth.uid() order by last_seen_at desc limit 1;
    return eventid;
  end if;

  select id into eventid
  from public.client_error_events
  where actor_id=auth.uid() and fingerprint=fp and status='open' and last_seen_at>=now()-interval '5 minutes'
  order by last_seen_at desc limit 1
  for update;

  if eventid is not null then
    update public.client_error_events
      set occurrence_count=occurrence_count+1,last_seen_at=now(),severity=sev,category=cat,
          context=ctx,user_agent=left(coalesce(user_agent_text,''),1000),
          stack=case when coalesce(stack,'')='' then left(coalesce(stack_text,''),12000) else stack end
    where id=eventid;
    return eventid;
  end if;

  insert into public.client_error_events(actor_id,message,stack,context,user_agent,severity,category,status,occurrence_count,first_seen_at,last_seen_at,fingerprint)
  values(auth.uid(),msg,left(coalesce(stack_text,''),12000),ctx,left(coalesce(user_agent_text,''),1000),sev,cat,'open',1,now(),now(),fp)
  returning id into eventid;
  return eventid;
end
$function$

CREATE OR REPLACE FUNCTION public.maintain_client_error_events()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare deleted_count integer:=0;
begin
  if auth.uid() is not null then
    if public.current_app_role()<>'system_admin' then raise exception 'Access denied' using errcode='42501'; end if;
    perform public.require_sensitive_access();
  end if;
  delete from public.client_error_events
  where status in ('resolved','ignored') and last_seen_at<now()-interval '2 years';
  get diagnostics deleted_count=row_count;
  return jsonb_build_object('deleted',deleted_count,'retention_years',2,'checked_at',now());
end
$function$

CREATE OR REPLACE FUNCTION public.mark_backup_offsite_copy(target_backup_id uuid, target_note text DEFAULT 'Encrypted backup package copied off-site'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare result_row public.backup_exports;
begin
  if not public.is_system_admin() then
    raise exception 'Access denied' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  update public.backup_exports
  set offsite_copied_at=now(),
      offsite_copy_note=left(coalesce(nullif(btrim(target_note),''),'Encrypted backup package copied off-site'),500)
  where id=target_backup_id and status='completed'
  returning * into result_row;
  if result_row.id is null then raise exception 'Completed backup not found'; end if;
  return to_jsonb(result_row);
end $function$

CREATE OR REPLACE FUNCTION public.mark_notifications_read(notification_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare changed integer;
begin
  update public.notifications set read_at=coalesce(read_at,now())
  where recipient_id=auth.uid() and (notification_ids is null or id=any(notification_ids));
  get diagnostics changed=row_count;
  return changed;
end $function$

CREATE OR REPLACE FUNCTION public.mark_report_correction_applied(target_report_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  update public.report_correction_requests set status='applied',applied_at=now(),updated_at=now()
  where report_id=target_report_id and status='approved';
  insert into public.report_correction_events(request_id,event_type,event_note)
  select id,'applied','Corrected report republished' from public.report_correction_requests
  where report_id=target_report_id and status='applied' and applied_at>=now()-interval '5 seconds';
end $function$

CREATE OR REPLACE FUNCTION public.my_realtime_topics()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select array(select distinct topic from (
   select 'school:global'::text topic where public.current_app_role() in ('system_admin','principal','accountant')
   union all select 'user:'||auth.uid()::text
   union all select 'class:'||c.id::text from public.classes c where public.can_access_class(c.id,false)
   union all select 'report:'||r.id::text from public.student_reports r where public.can_view_report(r.id)
   union all select 'student:'||gl.student_id::text from public.guardian_links gl where gl.auth_user_id=auth.uid()
   union all select 'student:'||s.id::text from public.students s where s.profile_id=auth.uid() and s.deleted_at is null
 ) q where topic is not null)
$function$

CREATE OR REPLACE FUNCTION public.next_promotion_academic_year(source_year_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  with ordered_years as (
    select
      y.id,
      row_number() over(
        order by
          coalesce(
            y.start_date,
            case
              when y.name::text ~ '^[0-9]{4}'
                then make_date(substring(y.name::text from 1 for 4)::integer,1,1)
              else y.created_at::date
            end
          ),
          y.created_at,
          y.id
      ) as rn
    from public.academic_years y
    where y.deleted_at is null
  ), source_year as (
    select oy.rn from ordered_years oy where oy.id=source_year_id
  )
  select next_year.id
  from ordered_years next_year
  join source_year source on next_year.rn=source.rn+1
  limit 1
$function$

CREATE OR REPLACE FUNCTION public.operations_dashboard(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare tid uuid:=target_term_id;health jsonb;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  if tid is null then select id into tid from public.terms where is_active and deleted_at is null limit 1; end if;
  health:=public.system_health();
  return jsonb_build_object(
    'term_id',tid,'term_control',public.term_control_snapshot(tid),
    'students',(select count(*) from public.students where status='active' and deleted_at is null),
    'reports_expected',(select count(*) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=tid and e.active and e.deleted_at is null),
    'reports_created',(select count(*) from public.student_reports where term_id=tid and deleted_at is null),
    'draft_reports',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status in ('draft','returned')),
    'awaiting_approval',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status in ('submitted','class_reviewed')),
    'approved_unpublished',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status='approved'),
    'published',(select count(*) from public.student_reports where term_id=tid and deleted_at is null and status='published'),
    'published_without_pdf',(select count(*) from public.student_reports r left join public.report_publications p on p.report_id=r.id and p.revoked_at is null where r.term_id=tid and r.status='published' and r.deleted_at is null and coalesce(p.storage_path,'')=''),
    'pending_corrections',(select count(*) from public.report_correction_requests q join public.student_reports r on r.id=q.report_id where r.term_id=tid and q.status='pending'),
    'attendance_classes_today',(select count(distinct class_id) from public.class_attendance_registers where term_id=tid and attendance_date=current_date),
    'active_classes',(select count(*) from public.classes where active and deleted_at is null),
    'pending_notifications',health->'pending_notifications','client_errors_24h',health->'client_errors_24h','client_warnings_24h',health->'client_warnings_24h',
    'open_security_events',health->'open_security_events','critical_security_events',health->'critical_security_events',
    'latest_backup',health->'latest_backup','latest_verified_backup',health->'latest_verified_backup','latest_recovery_test',health->'latest_recovery_test',
    'failed_backups_30d',health->'failed_backups_30d','current_backup_failures',health->'current_backup_failures',
    'cron_failures_24h',health->'cron_failures_24h','operational_state',health->'operational_state','health_reasons',health->'health_reasons',
    'continuity_state',health->'continuity_state','continuity_reasons',health->'continuity_reasons',
    'cron_jobs',case when to_regclass('cron.job') is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('jobid',jobid,'jobname',jobname,'schedule',schedule,'active',active) order by jobname) from cron.job where jobname like 'nis-%' or jobname like 'rce-%'),'[]'::jsonb) end,
    'class_progress',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'enrolled',q.enrolled,'created',q.created,'submitted',q.submitted,'approved',q.approved,'published',q.published) order by c.level_order,c.name)
      from public.classes c cross join lateral (select
        (select count(*) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=tid and e.class_id=c.id and e.active and e.deleted_at is null) enrolled,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null) created,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status in ('submitted','class_reviewed')) submitted,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status='approved') approved,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=tid and e.class_id=c.id and r.deleted_at is null and r.status='published') published
      ) q where c.active and c.deleted_at is null),'[]'::jsonb)
  );
end
$function$

CREATE OR REPLACE FUNCTION public.performance_comment_suggestions(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare avg_mark numeric:=0; result_count integer:=0; strongest text:=''; weakest text:='';
declare student_name text:='The student'; first_name text:='The student'; gender_value text:='Other';
declare opened integer:=0; present integer:=0; attendance numeric:=0; promoted_name text:='';
declare teacher_text text; head_text text; pronoun text:='They'; possessive text:='their'; average_text text;
begin
  if not public.can_view_report(target_report_id) then raise exception 'Access denied' using errcode='42501'; end if;
  select concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),s.first_name,s.gender,
    r.days_school_opened,r.days_present,coalesce(pc.name,'')
  into student_name,first_name,gender_value,opened,present,promoted_name
  from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
  join public.students s on s.id=e.student_id left join public.classes pc on pc.id=r.promoted_to_class_id
  where r.id=target_report_id;
  select count(*),coalesce(round(avg(sr.total_score),2),0) into result_count,avg_mark
  from public.subject_results sr where sr.report_id=target_report_id;
  select s.name into strongest from public.subject_results sr join public.subjects s on s.id=sr.subject_id
  where sr.report_id=target_report_id order by sr.total_score desc,s.display_order,s.name limit 1;
  select s.name into weakest from public.subject_results sr join public.subjects s on s.id=sr.subject_id
  where sr.report_id=target_report_id order by sr.total_score asc,s.display_order,s.name limit 1;
  if gender_value='Male' then pronoun:='He';possessive:='his';
  elsif gender_value='Female' then pronoun:='She';possessive:='her'; end if;
  average_text:=to_char(avg_mark,'FM990D0');
  attendance:=case when opened>0 then round(present::numeric/opened*100,1) else 0 end;
  if result_count=0 then
    teacher_text:=first_name||'''s assessment record is incomplete and requires all subject results.';
    head_text:='Complete the outstanding assessment records before final approval.';
  elsif avg_mark>=85 then
    teacher_text:=first_name||' has demonstrated outstanding academic performance with an average of '||average_text||'%. '||pronoun||' showed exceptional strength in '||coalesce(strongest,'the assessed subjects')||'. Maintain this excellent standard.';
    head_text:='Excellent performance. Continue to pursue excellence and remain a positive example to others.';
  elsif avg_mark>=75 then
    teacher_text:=first_name||' has achieved a very good academic performance with an average of '||average_text||'%. '||pronoun||' performed especially well in '||coalesce(strongest,'the assessed subjects')||' and should continue working consistently.';
    head_text:='Very good performance. Keep working diligently and aim for an even higher standard next term.';
  elsif avg_mark>=65 then
    teacher_text:=first_name||' has made good academic progress with an average of '||average_text||'%. '||pronoun||' showed strength in '||coalesce(strongest,'several subjects')||' and should give additional attention to '||coalesce(weakest,'weaker areas')||'.';
    head_text:='Good progress. Maintain steady effort and improve the areas that require greater attention.';
  elsif avg_mark>=50 then
    teacher_text:=first_name||' has produced a satisfactory performance with an average of '||average_text||'%. More regular revision, active class participation, and focused practice in '||coalesce(weakest,'the weaker subjects')||' will improve future results.';
    head_text:='Satisfactory performance. Greater consistency and focused study are required for stronger achievement.';
  elsif avg_mark>=40 then
    teacher_text:=first_name||' has shown a fair performance with an average of '||average_text||'%. '||pronoun||' needs sustained support, regular practice, and closer attention to '||coalesce(weakest,'the weaker subjects')||'.';
    head_text:='There is potential for improvement. Work closely with teachers and maintain a disciplined study routine.';
  else
    teacher_text:=first_name||' needs substantial academic improvement. The current average is '||average_text||'%, and immediate support is required, particularly in '||coalesce(weakest,'the weaker subjects')||'.';
    head_text:='Considerable improvement is required. Consistent effort, supervision, and remedial support should begin immediately.';
  end if;
  if opened>0 and attendance<85 then
    teacher_text:=teacher_text||' Attendance also requires improvement ('||present||' of '||opened||' days present).';
  elsif opened>0 and attendance>=95 then
    teacher_text:=teacher_text||' '||pronoun||' maintained excellent attendance.';
  end if;
  if promoted_name<>'' then head_text:=head_text||' Promotion: '||promoted_name||'.'; end if;
  return jsonb_build_object('average',avg_mark,'teacher_comment',teacher_text,'head_comment',head_text,
    'strongest_subject',strongest,'weakest_subject',weakest,'attendance_rate',attendance,'student_name',student_name);
end $function$

CREATE OR REPLACE FUNCTION public.platform_clear_license_history(reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  reason text:=btrim(coalesce(reason_text,''));
  event_total bigint;
  verification_total bigint;
  archive_total bigint;
begin
  perform public.require_platform_super_admin();
  if length(reason)<5 then
    raise exception 'A clear history-reset reason is required' using errcode='22023';
  end if;
  if upper(btrim(coalesce(confirmation_text,'')))<>'CLEAR ALL' then
    raise exception 'Type CLEAR ALL exactly to confirm permanent history removal' using errcode='22023';
  end if;
  select count(*) into event_total from public.license_events;
  select count(*) into verification_total from public.license_verification_logs;
  select count(*) into archive_total from public.platform_audit_archives where archive_scope='licensing';
  delete from public.platform_audit_archives where archive_scope='licensing';
  execute 'truncate table public.license_verification_logs, public.license_events restart identity';
  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details,created_at)
  values(
    auth.uid(),
    'LICENCE_COMPLIANCE_HISTORY_RESET',
    event_total+verification_total+archive_total,
    jsonb_build_object(
      'reason',reason,
      'license_events_removed',event_total,
      'verification_logs_removed',verification_total,
      'licensing_archives_removed',archive_total
    ),
    now()
  );
  return public.get_platform_license_console();
end
$function$

CREATE OR REPLACE FUNCTION public.platform_clear_package_history(reason_text text, actor_id_value uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  reason text:=btrim(coalesce(reason_text,''));
  event_total bigint;
  archive_total bigint;
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for package history reset' using errcode='42501';
  end if;
  if actor_id_value is null or not exists(
    select 1 from public.profiles p
    where p.id=actor_id_value
      and p.active
      and public.current_app_role_for(p.role)::text='platform_super_admin'
  ) then
    raise exception 'Active Platform Super Administrator is required' using errcode='42501';
  end if;
  if length(reason)<5 then
    raise exception 'A clear package-history reason is required' using errcode='22023';
  end if;
  select count(*) into event_total from public.platform_package_events;
  select count(*) into archive_total from public.platform_audit_archives where archive_scope='packages';
  delete from public.platform_audit_archives where archive_scope='packages';
  execute 'truncate table public.platform_package_events restart identity';
  insert into public.system_maintenance_log(actor_id,operation,affected_rows,details,created_at)
  values(
    actor_id_value,
    'PACKAGE_SECURITY_HISTORY_RESET',
    event_total+archive_total,
    jsonb_build_object(
      'reason',reason,
      'package_events_removed',event_total,
      'package_archives_removed',archive_total,
      'safe_update_compatible',true
    ),
    now()
  );
  return jsonb_build_object(
    'cleared',true,
    'package_events_removed',event_total,
    'package_archives_removed',archive_total
  );
end
$function$

CREATE OR REPLACE FUNCTION public.platform_finalize_package_replacement(target_artifact_id uuid, target_actor_id uuid, reason_text text, confirmation_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  replacement public.platform_package_artifacts%rowtype;
  previous public.platform_package_artifacts%rowtype;
  actor_role text:='';
  clean_reason text:=btrim(coalesce(reason_text,''));
  finalized_at timestamptz:=now();
  replacement_metadata jsonb;
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for replacement finalization'
      using errcode='42501';
  end if;
  if upper(btrim(coalesce(confirmation_text,'')))<>'ACTIVATE' then
    raise exception 'Type ACTIVATE exactly to finalize the replacement'
      using errcode='22023';
  end if;
  if length(clean_reason)<5 then
    raise exception 'A replacement finalization reason is required'
      using errcode='22023';
  end if;

  select public.current_app_role_for(p.role)::text
  into actor_role
  from public.profiles p
  where p.id=target_actor_id and p.active;
  if actor_role<>'platform_super_admin' then
    raise exception 'An active Platform Super Administrator is required'
      using errcode='42501';
  end if;

  select * into replacement
  from public.platform_package_artifacts
  where id=target_artifact_id
  for update;
  if replacement.id is null then
    raise exception 'Replacement package was not found' using errcode='P0002';
  end if;
  if replacement.supersedes_artifact_id is null
     or replacement.status<>'ready'
     or replacement.deletion_state<>'none' then
    raise exception 'Select a ready renewal or upgrade package'
      using errcode='22023';
  end if;
  if replacement.authority_last_checked_at is null
     or replacement.authority_last_checked_at<finalized_at-interval '24 hours' then
    raise exception 'The replacement package has not completed a successful school authority check within the last 24 hours'
      using errcode='42501';
  end if;

  select * into previous
  from public.platform_package_artifacts
  where id=replacement.supersedes_artifact_id
  for update;
  if previous.id is null then
    raise exception 'The superseded package record was not found' using errcode='P0002';
  end if;
  if previous.status<>'ready' or previous.deletion_state<>'none' then
    raise exception 'The previous package is no longer in a finalizable ready state'
      using errcode='40001';
  end if;
  if previous.superseded_by_artifact_id is not null
     and previous.superseded_by_artifact_id<>replacement.id then
    raise exception 'The previous package already has a different finalized replacement'
      using errcode='23505';
  end if;

  update public.platform_package_artifacts
  set status='revoked',
      revoked_at=finalized_at,
      revoked_by=target_actor_id,
      revocation_reason='Superseded by '||replacement.filename||': '||clean_reason,
      superseded_by_artifact_id=replacement.id,
      superseded_at=finalized_at,
      supersession_reason=clean_reason
  where id=previous.id;

  replacement_metadata:=jsonb_set(
    coalesce(replacement.metadata,'{}'::jsonb),
    '{lifecycle}',
    coalesce(replacement.metadata->'lifecycle','{}'::jsonb)||jsonb_build_object(
      'finalized_at',finalized_at,
      'finalized_by',target_actor_id,
      'finalization_reason',clean_reason
    ),
    true
  );
  update public.platform_package_artifacts
  set metadata=replacement_metadata
  where id=replacement.id
  returning * into replacement;

  insert into public.platform_package_events(
    event_type,actor_id,artifact_id,event_reason,event_data
  ) values(
    'package_replacement_finalized',target_actor_id,replacement.id,clean_reason,
    jsonb_build_object(
      'superseded_artifact_id',previous.id,
      'superseded_package_id',previous.package_id,
      'replacement_package_id',replacement.package_id,
      'authority_last_checked_at',replacement.authority_last_checked_at,
      'finalized_at',finalized_at
    )
  );

  return jsonb_build_object(
    'finalized',true,
    'replacement',to_jsonb(replacement),
    'superseded',(
      select to_jsonb(a)
      from public.platform_package_artifacts a
      where a.id=previous.id
    )
  );
end
$function$

CREATE OR REPLACE FUNCTION public.platform_package_session()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a public.platform_distribution_authorities%rowtype;s jsonb;
begin
  perform public.require_platform_super_admin();
  if exists(select 1 from public.school_licenses where package_id is not null) then
    raise exception 'Generated school installations cannot act as package distributors' using errcode='42501';
  end if;
  select * into a from public.platform_distribution_authorities where actor_id=auth.uid() and active;
  if a.id is null then raise exception 'Active Platform Distributor authority is required; Enterprise School licensing alone does not grant package access' using errcode='42501';end if;
  s:=public.license_snapshot_for_role('platform_super_admin');return jsonb_build_object('authorised',true,'actor_id',auth.uid(),'actor_role','platform_super_admin','aal',public.current_aal(),'distributor_id',a.id,'distributor_code',a.distributor_code,'can_generate',a.can_generate,'can_revoke',a.can_revoke,'plan_code',s#>>'{plan,code}');
end $function$

CREATE OR REPLACE FUNCTION public.platform_package_signing_key_install(target_envelope jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_catalog', 'extensions'
AS $function$
declare
  payload jsonb;
  registry record;
  secret_id uuid;
  key_id_value text:=coalesce(target_envelope->>'key_id','');
  fingerprint_value text:=coalesce(target_envelope->>'public_fingerprint','');
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for package signing key installation' using errcode='42501';
  end if;
  if target_envelope is null or jsonb_typeof(target_envelope)<>'object' then
    raise exception 'Package signing key envelope must be a JSON object' using errcode='22023';
  end if;
  if coalesce((target_envelope->>'version')::integer,0)<>1 then
    raise exception 'Package signing key envelope version is invalid' using errcode='22023';
  end if;
  if jsonb_typeof(target_envelope->'private_jwk')<>'object'
     or target_envelope->'private_jwk'->>'kty'<>'EC'
     or target_envelope->'private_jwk'->>'crv'<>'P-256'
     or coalesce(target_envelope->'private_jwk'->>'x','')=''
     or coalesce(target_envelope->'private_jwk'->>'y','')=''
     or coalesce(target_envelope->'private_jwk'->>'d','')='' then
    raise exception 'Package signing private JWK must be EC P-256' using errcode='22023';
  end if;
  if jsonb_typeof(target_envelope->'public_jwk')<>'object'
     or target_envelope->'public_jwk'->>'kty'<>'EC'
     or target_envelope->'public_jwk'->>'crv'<>'P-256'
     or coalesce(target_envelope->'public_jwk'->>'x','')<>coalesce(target_envelope->'private_jwk'->>'x','')
     or coalesce(target_envelope->'public_jwk'->>'y','')<>coalesce(target_envelope->'private_jwk'->>'y','')
     or target_envelope->'public_jwk' ? 'd' then
    raise exception 'Package signing public JWK does not match its private JWK' using errcode='22023';
  end if;
  if key_id_value !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$' then
    raise exception 'Package signing key ID is invalid' using errcode='22023';
  end if;
  if fingerprint_value !~ '^[0-9a-f]{64}$' then
    raise exception 'Package signing public-key fingerprint is invalid' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('rce_package_signing_key_v1',0));
  select singleton,key_id,public_fingerprint,created_at,updated_at
    into registry
  from public.platform_package_signing_identity
  where singleton=true;
  select decrypted_secret::jsonb
    into payload
  from vault.decrypted_secrets
  where name='rce_package_signing_key_v1'
  order by updated_at desc
  limit 1;
  if payload is not null then
    if coalesce(payload->>'key_id','') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$'
       or coalesce(payload->>'public_fingerprint','') !~ '^[0-9a-f]{64}$' then
      raise exception 'Stored package signing key metadata is invalid' using errcode='22023';
    end if;
    if registry.key_id is null then
      insert into public.platform_package_signing_identity(singleton,key_id,public_fingerprint)
      values(true,payload->>'key_id',payload->>'public_fingerprint')
      on conflict(singleton) do nothing;
    elsif registry.key_id<>payload->>'key_id' or registry.public_fingerprint<>payload->>'public_fingerprint' then
      raise exception 'Package signing identity registry does not match the encrypted Vault key' using errcode='55000';
    end if;
    -- Another first-use request may have installed the authoritative key while
    -- this request waited for the advisory lock. Return that key so all callers
    -- converge on one identity instead of failing or creating split identities.
    return payload || jsonb_build_object('configured',true,'recovery_required',false);
  end if;
  if registry.key_id is not null
     and (registry.key_id<>key_id_value or registry.public_fingerprint<>fingerprint_value) then
    raise exception 'The encrypted package signing key is missing, but its permanent identity registry exists. Restore the matching private JWK instead of creating a new signing identity.' using errcode='55000';
  end if;
  select vault.create_secret(
    target_envelope::text,
    'rce_package_signing_key_v1',
    'Report Card Enterprise package signing private JWK. Created once and retained for package verification continuity.'
  ) into secret_id;
  insert into public.platform_package_signing_identity(singleton,key_id,public_fingerprint,updated_at)
  values(true,key_id_value,fingerprint_value,now())
  on conflict(singleton) do update
    set updated_at=excluded.updated_at
    where public.platform_package_signing_identity.key_id=excluded.key_id
      and public.platform_package_signing_identity.public_fingerprint=excluded.public_fingerprint;
  select decrypted_secret::jsonb
    into payload
  from vault.decrypted_secrets
  where id=secret_id;
  if payload is null then
    raise exception 'Package signing key was created but could not be verified in Vault' using errcode='55000';
  end if;
  return payload || jsonb_build_object('configured',true,'recovery_required',false);
end
$function$

CREATE OR REPLACE FUNCTION public.platform_package_signing_key_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_catalog', 'extensions'
AS $function$
declare
  payload jsonb;
  registry record;
  payload_key_id text;
  payload_fingerprint text;
  metadata_repair_required boolean:=false;
begin
  if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then
    raise exception 'Service role required for package signing key access' using errcode='42501';
  end if;
  select singleton,key_id,public_fingerprint,created_at,updated_at
    into registry
  from public.platform_package_signing_identity
  where singleton=true;
  select decrypted_secret::jsonb
    into payload
  from vault.decrypted_secrets
  where name='rce_package_signing_key_v1'
  order by updated_at desc
  limit 1;
  if payload is null then
    if registry.key_id is not null then
      return jsonb_build_object(
        'configured',false,
        'recovery_required',true,
        'expected_key_id',registry.key_id,
        'expected_public_fingerprint',registry.public_fingerprint
      );
    end if;
    return jsonb_build_object('configured',false,'recovery_required',false);
  end if;
  if jsonb_typeof(payload->'private_jwk')<>'object'
     or payload->'private_jwk'->>'kty'<>'EC'
     or payload->'private_jwk'->>'crv'<>'P-256'
     or coalesce(payload->'private_jwk'->>'x','')=''
     or coalesce(payload->'private_jwk'->>'y','')=''
     or coalesce(payload->'private_jwk'->>'d','')='' then
    raise exception 'Stored package signing private JWK is invalid' using errcode='22023';
  end if;
  payload_key_id:=coalesce(payload->>'key_id','');
  payload_fingerprint:=coalesce(payload->>'public_fingerprint','');
  metadata_repair_required:=
    payload_key_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,79}$'
    or payload_fingerprint !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(payload->'public_jwk')<>'object'
    or coalesce(payload->'public_jwk'->>'x','')<>coalesce(payload->'private_jwk'->>'x','')
    or coalesce(payload->'public_jwk'->>'y','')<>coalesce(payload->'private_jwk'->>'y','')
    or payload->'public_jwk' ? 'd'
    or (registry.key_id is not null and registry.key_id<>payload_key_id)
    or (registry.public_fingerprint is not null and registry.public_fingerprint<>payload_fingerprint);
  return payload || jsonb_build_object(
    'configured',true,
    'recovery_required',false,
    'metadata_repair_required',metadata_repair_required,
    'registered_key_id',registry.key_id,
    'registered_public_fingerprint',registry.public_fingerprint
  );
exception
  when invalid_text_representation then
    raise exception 'Stored package signing key is invalid JSON' using errcode='22023';
end
$function$

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

CREATE OR REPLACE FUNCTION public.platform_release_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault', 'pg_catalog', 'extensions'
AS $function$ declare missing_items text[]:=array[]::text[]; signing_secret_count bigint:=0; active_template_count bigint:=0; begin if coalesce(auth.role(),'') not in ('service_role','supabase_admin') then raise exception 'Service role required for platform release health' using errcode='42501'; end if; if to_regclass('public.platform_package_templates') is null then missing_items:=array_append(missing_items,'platform_package_templates'); end if; if to_regclass('public.platform_package_artifacts') is null then missing_items:=array_append(missing_items,'platform_package_artifacts'); end if; if to_regclass('public.platform_package_events') is null then missing_items:=array_append(missing_items,'platform_package_events'); end if; if to_regclass('public.platform_package_signing_identity') is null then missing_items:=array_append(missing_items,'platform_package_signing_identity'); end if; if to_regclass('public.license_plans') is null then missing_items:=array_append(missing_items,'license_plans'); end if; if to_regprocedure('public.platform_package_session()') is null then missing_items:=array_append(missing_items,'platform_package_session()'); end if; if to_regprocedure('public.platform_package_signing_key_read()') is null then missing_items:=array_append(missing_items,'platform_package_signing_key_read()'); end if; if to_regprocedure('public.platform_package_signing_key_install(jsonb)') is null then missing_items:=array_append(missing_items,'platform_package_signing_key_install(jsonb)'); end if; if to_regprocedure('public.platform_package_signing_key_repair(jsonb)') is null then missing_items:=array_append(missing_items,'platform_package_signing_key_repair(jsonb)'); end if; if to_regprocedure('public.platform_clear_package_history(text,uuid)') is null then missing_items:=array_append(missing_items,'platform_clear_package_history(text,uuid)'); end if; if to_regprocedure('public.platform_clear_license_history(text,text)') is null then missing_items:=array_append(missing_items,'platform_clear_license_history(text,text)'); end if; if to_regprocedure('public.get_school_license_capacity_console()') is null then missing_items:=array_append(missing_items,'get_school_license_capacity_console()'); end if; if to_regprocedure('public.platform_finalize_package_replacement(uuid,uuid,text,text)') is null then missing_items:=array_append(missing_items,'platform_finalize_package_replacement(uuid,uuid,text,text)'); end if; if to_regprocedure('public.report_promotion_canonical(uuid)') is null then missing_items:=array_append(missing_items,'report_promotion_canonical(uuid)'); end if; if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='platform_package_artifacts' and column_name='supersedes_artifact_id') then missing_items:=array_append(missing_items,'platform_package_artifacts.supersedes_artifact_id'); end if; if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='platform_package_artifacts' and column_name='lifecycle_action') then missing_items:=array_append(missing_items,'platform_package_artifacts.lifecycle_action'); end if; if not exists(select 1 from pg_extension where extname='supabase_vault') then missing_items:=array_append(missing_items,'supabase_vault extension'); else select count(*) into signing_secret_count from vault.secrets where name='rce_package_signing_key_v1'; end if; if to_regclass('public.platform_package_templates') is not null then select count(*) into active_template_count from public.platform_package_templates where active; end if; return jsonb_build_object( 'ready',cardinality(missing_items)=0, 'version','7.4.0', 'release_revision','print-quality-promotion-consistency-r10-candidate', 'missing',to_jsonb(missing_items), 'signing_secret_present',signing_secret_count=1, 'signing_secret_count',signing_secret_count, 'active_template_count',active_template_count, 'checked_at',now() ); end $function$

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

CREATE OR REPLACE FUNCTION public.protect_profile_historical_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if coalesce(current_setting('app.allow_historical_profile_delete',true),'')='on' then
    return old;
  end if;
  if exists(select 1 from public.audit_log a where a.actor_id=old.id) then
    raise exception 'This account has historical audit activity and cannot be permanently deleted. Deactivate the account instead.' using errcode='23503';
  end if;
  return old;
end
$function$

CREATE OR REPLACE FUNCTION public.protect_profile_security_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  -- Platform and school administrators are privileged identities. MFA is a
  -- database invariant, not a browser preference.
  if public.current_app_role_for(new.role) in ('platform_super_admin','system_admin') then
    new.mfa_required:=true;
  end if;

  if auth.role()='authenticated'
     and (old.role='platform_super_admin'::public.app_role or new.role='platform_super_admin'::public.app_role)
     and (new.role is distinct from old.role
       or new.active is distinct from old.active
       or new.mfa_required is distinct from old.mfa_required
       or new.must_change_password is distinct from old.must_change_password) then
    raise exception 'Platform Super Administrator security fields require the protected setup path' using errcode='42501';
  end if;

  -- Browser account owners may never change their own security-control fields.
  if auth.role()='authenticated' and auth.uid()=old.id then
    if new.role is distinct from old.role
       or new.active is distinct from old.active
       or new.mfa_required is distinct from old.mfa_required
       or new.must_change_password is distinct from old.must_change_password then
      raise exception 'Profile security fields cannot be changed by the account owner' using errcode='42501';
    end if;
  end if;
  return new;
end
$function$

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
declare
  eid bigint;
  sev text:=lower(coalesce(severity_text,'info'));
  event_name text:=left(lower(btrim(coalesce(event_type_text,'unknown'))),100);
  msg text:=left(coalesce(message_text,'Security event'),1000);
  src text:=left(coalesce(source_text,'application'),100);
  jwt_role text:=coalesce(current_setting('request.jwt.claim.role',true),'');
  app_role text:=coalesce(public.current_app_role()::text,'');
  recent_id bigint;
begin
  if auth.uid() is null and jwt_role<>'service_role' then raise exception 'Authentication required' using errcode='42501'; end if;
  if octet_length(coalesce(details_data,'{}'::jsonb)::text)>8000 then raise exception 'Security-event details are too large'; end if;

  if jwt_role<>'service_role' then
    if app_role not in ('system_admin','principal') then
      if event_name<>'authorization_denied' then raise exception 'Unsupported client security event' using errcode='42501'; end if;
      sev:='warning'; src:='web_client';
    elsif sev not in ('info','warning','high','critical') then
      sev:='warning';
    end if;
    if (select count(*) from public.security_events where actor_id=auth.uid() and created_at>now()-interval '5 minutes')>=20 then
      raise exception 'Security event rate limit exceeded' using errcode='42901';
    end if;
    select id into recent_id from public.security_events
      where actor_id=auth.uid() and event_type=event_name and message=msg and created_at>now()-interval '60 seconds'
      order by created_at desc limit 1;
    if recent_id is not null then return recent_id; end if;
  else
    if sev not in ('info','warning','high','critical') then sev:='warning'; end if;
  end if;

  insert into public.security_events(actor_id,event_type,severity,source,message,details)
  values(auth.uid(),event_name,sev,src,msg,coalesce(details_data,'{}'::jsonb)) returning id into eid;
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
 SET search_path TO 'public', 'storage', 'extensions'
AS $function$
declare publicationid uuid;
begin
  if not public.can_manage_report_pdf(target_report_id) then
    raise exception 'Only an authorized publisher with required MFA can register the official PDF' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not exists(select 1 from public.student_reports where id=target_report_id and status='published' and deleted_at is null) then
    raise exception 'Only a Principal-approved published report can receive an official PDF';
  end if;
  if btrim(coalesce(target_storage_path,''))='' or target_storage_path not like target_report_id::text||'/%' or target_storage_path like '%..%' then
    raise exception 'Official report PDF path is invalid';
  end if;
  if btrim(coalesce(target_checksum,'')) !~ '^[0-9A-Fa-f]{64}$' then
    raise exception 'Official report PDF checksum must be a SHA-256 digest';
  end if;
  if target_page_count is null or target_page_count<1 or target_page_count>200 then
    raise exception 'Official report PDF page count is invalid';
  end if;
  if not exists(
    select 1 from storage.objects o
    where o.bucket_id='report-pdfs' and o.name=target_storage_path
  ) then
    raise exception 'Uploaded official report PDF object was not found';
  end if;

  update public.report_publications
    set storage_path=target_storage_path,
        checksum=lower(target_checksum),
        page_count=target_page_count
  where report_id=target_report_id and revoked_at is null
  returning id into publicationid;
  if publicationid is null then raise exception 'Active publication not found'; end if;
  return (select to_jsonb(p) from public.report_publications p where p.id=publicationid);
end
$function$

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
declare
  required boolean:=false;
  profile_role public.app_role;
  configured boolean:=false;
begin
  select p.role,coalesce(p.mfa_required,false)
  into profile_role,configured
  from public.profiles p
  where p.id=auth.uid() and p.active;

  if profile_role is null then
    raise exception 'Active profile required' using errcode='42501';
  end if;

  required:=configured or public.current_app_role_for(profile_role) in ('system_admin','platform_super_admin');
  if required and public.current_aal()<>'aal2' then
    raise exception 'Multi-factor authentication is required' using errcode='42501';
  end if;
end
$function$

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
declare row_data public.security_events; prior public.security_events;
begin
  if public.current_app_role() not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if target_status not in ('acknowledged','resolved','false_positive') then raise exception 'Invalid resolution status'; end if;
  select * into prior from public.security_events where id=target_event_id for update;
  if prior.id is null then raise exception 'Security event not found'; end if;
  update public.security_events set status=target_status,acknowledged_by=auth.uid(),acknowledged_at=now(),resolution_note=left(coalesce(resolution_text,''),1000) where id=target_event_id returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'security_events',null,'SECURITY_EVENT_STATUS_CHANGED',
    jsonb_build_object('security_event_id',prior.id,'status',prior.status),
    jsonb_build_object('security_event_id',row_data.id,'event_type',row_data.event_type,'severity',row_data.severity,'status',row_data.status),
    'A security-event workflow status was changed. Event details remain in the security-event record.');
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
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then raise exception 'The current licence does not permit this change' using errcode='42501'; end if;
  if length(btrim(coalesce(reason_text,'')))<5 then raise exception 'Revocation reason is required'; end if;

  update public.transcript_issuances
  set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revocation_reason=left(btrim(reason_text),500)
  where id=target_issuance_id and status='valid'
  returning * into issued;
  if issued.id is null then raise exception 'Active transcript issuance not found'; end if;

  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(
    auth.uid(),'transcript_issuances',issued.id,'REVOKE',
    jsonb_build_object('transcript_number',issued.transcript_number,'status','valid'),
    jsonb_build_object('transcript_number',issued.transcript_number,'status','revoked','revoked_at',issued.revoked_at),
    issued.revocation_reason
  );
  return to_jsonb(issued)-'snapshot';
end
$function$

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
declare settings_id uuid; old_retention integer; old_minimum integer;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can change backup policy' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if target_retention_days is null or target_retention_days<7 or target_retention_days>365 then raise exception 'Backup retention must be between 7 and 365 days'; end if;
  if target_minimum_copies is null or target_minimum_copies<2 or target_minimum_copies>90 then raise exception 'Minimum retained backups must be between 2 and 90'; end if;
  select id,backup_retention_days,backup_minimum_copies into settings_id,old_retention,old_minimum from public.school_settings order by created_at,id limit 1 for update;
  if settings_id is null then
    insert into public.school_settings(backup_retention_days,backup_minimum_copies,updated_at) values(target_retention_days,target_minimum_copies,now()) returning id into settings_id;
  else
    update public.school_settings set backup_retention_days=target_retention_days,backup_minimum_copies=target_minimum_copies,updated_at=now() where id=settings_id;
  end if;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'school_settings',settings_id,'BACKUP_POLICY_CHANGED',
    jsonb_build_object('retention_days',old_retention,'minimum_copies',old_minimum),
    jsonb_build_object('retention_days',target_retention_days,'minimum_copies',target_minimum_copies),
    'System Administrator changed backup retention policy.');
  return jsonb_build_object('backup_retention_days',target_retention_days,'backup_minimum_copies',target_minimum_copies,'settings_id',settings_id);
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
  assigned_profile_id uuid; selected_teacher_profile_id uuid;
  row public.class_timetable_entries%rowtype;
begin
  if not public.is_system_admin() then raise exception 'Only the System Administrator can manage class timetables' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  perform public.require_license_feature('timetable');
  if not public.license_write_allowed() then raise exception 'LICENSE_WRITE_RESTRICTED: The current licence does not permit timetable changes' using errcode='42501'; end if;
  if yearid is null or classid is null or subjectid is null or teacherid is null then raise exception 'Academic year, class, subject, and teacher are required'; end if;
  if day_value not in ('Monday','Tuesday','Wednesday','Thursday','Friday') then raise exception 'Timetable day must be Monday to Friday'; end if;
  begin start_value:=(payload->>'period_start')::time;end_value:=(payload->>'period_end')::time;exception when others then raise exception 'Period start and end times are invalid';end;
  if end_value<=start_value then raise exception 'Period end time must be after start time'; end if;
  if not exists(select 1 from public.academic_years where id=yearid and deleted_at is null) then raise exception 'Academic year not found'; end if;
  if not exists(select 1 from public.classes where id=classid and deleted_at is null and active) then raise exception 'Class not found'; end if;
  if not exists(select 1 from public.subjects where id=subjectid and deleted_at is null and active) then raise exception 'Subject not found'; end if;
  select profile_id into selected_teacher_profile_id from public.teachers where id=teacherid and deleted_at is null and active and employment_status='active';
  if selected_teacher_profile_id is null then raise exception 'Teacher not found or not active'; end if;
  select cs.teacher_id into assigned_profile_id from public.class_subjects cs where cs.class_id=classid and cs.subject_id=subjectid and cs.active limit 1;
  if assigned_profile_id is null then raise exception 'The selected subject is not actively assigned to this class'; end if;
  if assigned_profile_id<>selected_teacher_profile_id then raise exception 'The selected teacher is not the assigned teacher for this class subject'; end if;
  if eid is not null then
    select updated_at into current_updated from public.class_timetable_entries where id=eid and active for update;
    if current_updated is null then raise exception 'Timetable period not found'; end if;
    if expected_updated is not null and current_updated<>expected_updated then raise exception 'This timetable period changed in another session. Reload and try again.'; end if;
  end if;
  if exists(select 1 from public.class_timetable_entries x where x.active and x.academic_year_id=yearid and x.class_id=classid and x.day_of_week=day_value and (eid is null or x.id<>eid) and x.period_start<end_value and x.period_end>start_value) then raise exception 'This class already has an overlapping timetable period'; end if;
  if exists(select 1 from public.class_timetable_entries x where x.active and x.academic_year_id=yearid and x.teacher_id=teacherid and x.day_of_week=day_value and (eid is null or x.id<>eid) and x.period_start<end_value and x.period_end>start_value) then raise exception 'The selected teacher already has another class during this time'; end if;
  if eid is null then
    insert into public.class_timetable_entries(academic_year_id,class_id,day_of_week,period_start,period_end,subject_id,teacher_id,notes,created_by)
    values(yearid,classid,day_value,start_value,end_value,subjectid,teacherid,btrim(coalesce(payload->>'notes','')),auth.uid()) returning * into row;
  else
    update public.class_timetable_entries set academic_year_id=yearid,class_id=classid,day_of_week=day_value,period_start=start_value,period_end=end_value,subject_id=subjectid,teacher_id=teacherid,notes=btrim(coalesce(payload->>'notes','')),updated_at=now() where id=eid returning * into row;
  end if;
  return to_jsonb(row);
end
$function$

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
  if not public.is_records_manager() then
    raise exception 'Only the System Administrator with MFA verification can change the promotion cutoff score' using errcode='42501';
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
end
$function$

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
declare row_data public.data_retention_policies; prior public.data_retention_policies; category text:=left(btrim(coalesce(payload->>'data_category','')),160);
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can manage retention policies' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if length(category)<2 then raise exception 'Data category is required'; end if;
  select * into prior from public.data_retention_policies where data_category=category;
  insert into public.data_retention_policies(data_category,retention_years,legal_basis,disposition_action,notes,active,updated_by)
  values(category,nullif(payload->>'retention_years','')::integer,left(coalesce(payload->>'legal_basis',''),1000),coalesce(nullif(payload->>'disposition_action',''),'review'),left(coalesce(payload->>'notes',''),2000),coalesce((payload->>'active')::boolean,true),auth.uid())
  on conflict(data_category) do update set retention_years=excluded.retention_years,legal_basis=excluded.legal_basis,disposition_action=excluded.disposition_action,notes=excluded.notes,active=excluded.active,updated_by=auth.uid(),updated_at=now()
  returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'data_retention_policies',row_data.id,case when prior.id is null then 'RETENTION_POLICY_CREATED' else 'RETENTION_POLICY_UPDATED' end,
    case when prior.id is null then null else jsonb_build_object('retention_years',prior.retention_years,'disposition_action',prior.disposition_action,'active',prior.active) end,
    jsonb_build_object('data_category',row_data.data_category,'retention_years',row_data.retention_years,'disposition_action',row_data.disposition_action,'active',row_data.active),
    'System Administrator changed a data-retention policy.');
  return to_jsonb(row_data);
end $function$

CREATE OR REPLACE FUNCTION public.save_school_identity_settings(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
declare
  v_id uuid;
  v_prefix text;
  v_primary text;
  v_accent text;
  v_font text;
  v_font_size numeric;
begin
  if not public.is_system_admin() then
    raise exception 'Only the School System Administrator can update school identity settings' using errcode='42501';
  end if;
  perform public.require_sensitive_access();
  if not public.license_write_allowed() then
    raise exception 'The current licence is read-only' using errcode='42501';
  end if;

  select id into v_id from public.school_settings order by created_at limit 1 for update;
  if v_id is null then raise exception 'School settings are unavailable'; end if;

  v_prefix:=upper(regexp_replace(coalesce(nullif(btrim(payload->>'report_number_prefix'),''),(select report_number_prefix from public.school_settings where id=v_id)),'[^A-Z0-9]','','g'));
  if length(v_prefix)<2 or length(v_prefix)>12 then raise exception 'Report number prefix must contain 2 to 12 letters or numbers'; end if;

  v_primary:=coalesce(nullif(btrim(payload->>'primary_colour'),''),(select primary_colour from public.school_settings where id=v_id));
  v_accent:=coalesce(nullif(btrim(payload->>'accent_colour'),''),(select accent_colour from public.school_settings where id=v_id));
  v_font:=coalesce(nullif(btrim(payload->>'report_body_font'),''),(select report_body_font from public.school_settings where id=v_id));
  v_font_size:=coalesce(nullif(payload->>'report_body_font_size','')::numeric,(select report_body_font_size from public.school_settings where id=v_id));

  if payload ?| array['primary_colour','accent_colour','report_body_font','report_body_font_size'] then
    if not public.license_feature_enabled('custom_branding') then
      raise exception 'Custom Branding is not enabled for the current licence' using errcode='42501';
    end if;
    if v_primary !~ '^#[0-9A-Fa-f]{6}$' or v_accent !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Brand colours must be six-digit hexadecimal values'; end if;
    if v_font not in ('Times New Roman','Arial','Calibri','Georgia','Verdana','Tahoma') then raise exception 'Unsupported report body font'; end if;
    if v_font_size<8 or v_font_size>16 then raise exception 'Report body font size must be between 8 and 16 points'; end if;
  end if;

  update public.school_settings s set
    school_name=case when payload ? 'school_name' then btrim(coalesce(payload->>'school_name','')) else s.school_name end,
    motto=case when payload ? 'motto' then btrim(coalesce(payload->>'motto','')) else s.motto end,
    address=case when payload ? 'address' then btrim(coalesce(payload->>'address','')) else s.address end,
    phone=case when payload ? 'phone' then btrim(coalesce(payload->>'phone','')) else s.phone end,
    email=case when payload ? 'email' then lower(btrim(coalesce(payload->>'email',''))) else s.email end,
    website=case when payload ? 'website' then btrim(coalesce(payload->>'website','')) else s.website end,
    report_title=case when payload ? 'report_title' then btrim(coalesce(payload->>'report_title','')) else s.report_title end,
    report_footer=case when payload ? 'report_footer' then btrim(coalesce(payload->>'report_footer','')) else s.report_footer end,
    head_name=case when payload ? 'head_name' then btrim(coalesce(payload->>'head_name','')) else s.head_name end,
    timezone=case when payload ? 'timezone' then btrim(coalesce(payload->>'timezone','')) else s.timezone end,
    locale=case when payload ? 'locale' then btrim(coalesce(payload->>'locale','')) else s.locale end,
    report_number_prefix=v_prefix,
    primary_colour=case when payload ? 'primary_colour' then v_primary else s.primary_colour end,
    accent_colour=case when payload ? 'accent_colour' then v_accent else s.accent_colour end,
    report_body_font=case when payload ? 'report_body_font' then v_font else s.report_body_font end,
    report_body_font_size=case when payload ? 'report_body_font_size' then v_font_size else s.report_body_font_size end,
    updated_at=now()
  where s.id=v_id;

  return jsonb_build_object('ok',true,'school_id',v_id);
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
declare row_data public.security_verification_runs; findings_data jsonb:=coalesce(payload->'findings','[]'::jsonb); scope_text text:=left(btrim(coalesce(payload->>'scope','')),1000);
begin
  if public.current_app_role()<>'system_admin' then raise exception 'Only the System Administrator can record security verification' using errcode='42501'; end if;
  perform public.require_sensitive_access();
  if length(scope_text)<3 then raise exception 'Verification scope is required'; end if;
  if jsonb_typeof(findings_data)<>'array' or octet_length(findings_data::text)>20000 then raise exception 'Verification findings must be a bounded JSON array'; end if;
  insert into public.security_verification_runs(standard_name,scope,status,summary,findings,next_review_at)
  values(left(coalesce(nullif(payload->>'standard_name',''),'OWASP ASVS 5.0'),200),scope_text,payload->>'status',left(coalesce(payload->>'summary',''),4000),findings_data,public.safe_timestamptz(payload->>'next_review_at')) returning * into row_data;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(auth.uid(),'security_verification_runs',row_data.id,'SECURITY_VERIFICATION_RECORDED',null,
    jsonb_build_object('standard_name',row_data.standard_name,'status',row_data.status,'scope',row_data.scope,'next_review_at',row_data.next_review_at,'finding_count',jsonb_array_length(row_data.findings)),
    'System Administrator recorded a formal security verification result.');
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

SET check_function_bodies=on;
