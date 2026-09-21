-- Edusentia Enterprise Neon Edition — certified identity RPC adaptation.
-- Certified source: a181e18e0ca044db756193209b5b089cd03efb0f
-- Provider adaptation: Supabase auth.users reads map to Neon-native authn.users;
-- readiness ACL checks target the fixed Cloudflare Worker runtime role.

begin;

-- generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid)
CREATE OR REPLACE FUNCTION public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'authn', 'extensions'
AS $function$
declare
  base_name text:=lower(regexp_replace(coalesce(requested_base,''),'[^a-z0-9]','','g'));
  email_domain text:=public.canonical_school_email_domain();
  candidate text;
  suffix integer:=1;
begin
  if actor_id is null or not exists(
    select 1 from public.profiles p
    where p.id=actor_id
      and p.active
      and public.current_app_role_for(p.role)='system_admin'
  ) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if auth.uid() is not null and auth.uid()<>actor_id then
    raise exception 'Access denied' using errcode='42501';
  end if;

  base_name:=left(coalesce(nullif(base_name,''),'user'),40);
  perform pg_advisory_xact_lock(
    hashtextextended('school_user_email_'||email_domain||'_'||base_name,0)
  );
  candidate:=base_name||'@'||email_domain;

  while exists(
    select 1 from authn.users u
    where lower(coalesce(u.email,''))=lower(candidate)
      and (target_user_id is null or u.id<>target_user_id)
  ) loop
    suffix:=suffix+1;
    if suffix>99999 then
      raise exception 'A unique school user email address could not be generated';
    end if;
    candidate:=left(base_name,greatest(1,40-length(suffix::text)))||
      suffix::text||'@'||email_domain;
  end loop;
  return candidate;
end
$function$;
revoke all on function public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid) from public;
grant execute on function public.generate_nip_user_email(actor_id uuid, requested_base text, target_user_id uuid) to edusentia_worker_runtime;

-- get_emergency_delegation_console()
CREATE OR REPLACE FUNCTION public.get_emergency_delegation_console()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'authn', 'extensions'
AS $function$
declare actor_role text:=public.current_app_role()::text;
begin
  if actor_role not in ('system_admin','principal') then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'delegations',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select d.*,c.name class_name,t.name term_name,y.name academic_year_name,s.name subject_name,
        dp.full_name delegate_name,public.current_app_role_for(dp.role)::text delegate_role,
        op.full_name original_teacher_name,cp.full_name created_by_name,ap.full_name acknowledged_by_name,rp.full_name revoked_by_name,
        case when d.status='revoked' then 'revoked'
          when now()<d.valid_from then 'scheduled'
          when now()>=d.valid_until then 'expired'
          else 'active' end computed_status
      from public.emergency_academic_delegations d
      join public.classes c on c.id=d.class_id
      join public.terms t on t.id=d.term_id
      join public.academic_years y on y.id=d.academic_year_id
      left join public.subjects s on s.id=d.subject_id
      join public.profiles dp on dp.id=d.delegate_user_id
      left join public.profiles op on op.id=d.original_teacher_id
      left join public.profiles cp on cp.id=d.created_by
      left join public.profiles ap on ap.id=d.principal_acknowledged_by
      left join public.profiles rp on rp.id=d.revoked_by
      order by d.created_at desc limit 300
    ) q),'[]'::jsonb),
    'eligible_users',coalesce((select jsonb_agg(to_jsonb(q) order by lower(q.full_name),q.email) from (
      select p.id,p.full_name,au.email::text,public.current_app_role_for(p.role)::text role,t.staff_no
      from public.profiles p
      left join authn.users au on au.id=p.id
      left join public.teachers t on t.profile_id=p.id and t.deleted_at is null
      where p.active and public.current_app_role_for(p.role)::text in ('system_admin','class_teacher','subject_teacher')
    ) q),'[]'::jsonb),
    'class_subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.level_order,q.class_name,q.subject_order,q.subject_name) from (
      select cs.class_id,c.name class_name,c.level_order,cs.subject_id,s.name subject_name,s.code subject_code,s.display_order subject_order,
        cs.teacher_id,p.full_name assigned_teacher_name
      from public.class_subjects cs
      join public.classes c on c.id=cs.class_id
      join public.subjects s on s.id=cs.subject_id
      left join public.profiles p on p.id=cs.teacher_id
      where cs.active and c.active and c.deleted_at is null and s.active and s.deleted_at is null
    ) q),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (
      select e.id,e.delegation_id,e.event_type,e.actor_id,e.report_id,e.subject_id,e.event_reason,e.event_data,e.created_at,
        p.full_name actor_name,s.name subject_name
      from public.emergency_academic_delegation_events e
      left join public.profiles p on p.id=e.actor_id
      left join public.subjects s on s.id=e.subject_id
      order by e.created_at desc limit 300
    ) q),'[]'::jsonb)
  );
end $function$;
revoke all on function public.get_emergency_delegation_console() from public;
grant execute on function public.get_emergency_delegation_console() to edusentia_worker_runtime;

-- list_guardian_portal_accounts(search_text text)
CREATE OR REPLACE FUNCTION public.list_guardian_portal_accounts(search_text text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'authn', 'extensions'
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
    left join authn.users u on u.id=p.id
    where p.active and public.current_app_role_for(p.role)='parent_guardian'
      and (coalesce(search_text,'')='' or p.full_name ilike '%'||search_text||'%'
        or coalesce(u.email,'') ilike '%'||search_text||'%' or p.phone ilike '%'||search_text||'%')
  ),'[]'::jsonb);
end $function$;
revoke all on function public.list_guardian_portal_accounts(search_text text) from public;
grant execute on function public.list_guardian_portal_accounts(search_text text) to edusentia_worker_runtime;

-- validate_operational_readiness()
CREATE OR REPLACE FUNCTION public.validate_operational_readiness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'authn', 'extensions'
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
    'missing_auth_profiles',(select count(*) from authn.users u left join public.profiles p on p.id=u.id where p.id is null),
    'active_period_errors',(
      (select greatest(count(*)-1,0) from public.academic_years where is_active and deleted_at is null)
      +(select greatest(count(*)-1,0) from public.terms where is_active and deleted_at is null)
      +(select count(*) from public.terms t left join public.academic_years y on y.id=t.academic_year_id where t.is_active and t.deleted_at is null and (y.id is null or not y.is_active or y.deleted_at is not null))
    ),
    'subject_total_mismatches',(select count(*) from public.subject_results sr where abs(sr.total_score-coalesce((select sum(se.weighted_score) from public.assessment_score_entries se where se.subject_result_id=sr.id),0))>0.01)
  );
  privilege_state:=jsonb_build_object(
    'identifier_rpc',has_function_privilege('edusentia_worker_runtime','public.generate_school_identifier(text)','EXECUTE'),
    'student_rpc',has_function_privilege('edusentia_worker_runtime','public.save_student(jsonb)','EXECUTE'),
    'teacher_rpc',has_function_privilege('edusentia_worker_runtime','public.save_teacher(jsonb)','EXECUTE'),
    'headteacher_rpc',has_function_privilege('edusentia_worker_runtime','public.save_headteacher(jsonb)','EXECUTE'),
    'academic_rpc',has_function_privilege('edusentia_worker_runtime','public.save_academic_entity(text,jsonb)','EXECUTE'),
    'assessment_rpc',has_function_privilege('edusentia_worker_runtime','public.save_assessment_scheme(jsonb)','EXECUTE'),
    'report_rpc',has_function_privilege('edusentia_worker_runtime','public.save_report_card(jsonb,integer)','EXECUTE'),
    'student_direct_write_blocked',not has_table_privilege('edusentia_worker_runtime','public.students','INSERT') and not has_table_privilege('edusentia_worker_runtime','public.students','UPDATE') and not has_table_privilege('edusentia_worker_runtime','public.students','DELETE'),
    'teacher_direct_write_blocked',not has_table_privilege('edusentia_worker_runtime','public.teachers','INSERT') and not has_table_privilege('edusentia_worker_runtime','public.teachers','UPDATE') and not has_table_privilege('edusentia_worker_runtime','public.teachers','DELETE'),
    'headteacher_direct_write_blocked',not has_table_privilege('edusentia_worker_runtime','public.headteachers','INSERT') and not has_table_privilege('edusentia_worker_runtime','public.headteachers','UPDATE') and not has_table_privilege('edusentia_worker_runtime','public.headteachers','DELETE'),
    'profile_direct_write_blocked',not has_table_privilege('edusentia_worker_runtime','public.profiles','INSERT') and not has_table_privilege('edusentia_worker_runtime','public.profiles','UPDATE') and not has_table_privilege('edusentia_worker_runtime','public.profiles','DELETE')
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
end $function$;
revoke all on function public.validate_operational_readiness() from public;
grant execute on function public.validate_operational_readiness() to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0047_certified_identity_rpc_neon')
on conflict do nothing;
update app.release_identity set schema_version='0047' where edition='Edusentia Enterprise Neon Edition';
commit;
