-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function bodies extracted read-only with pg_get_functiondef.
-- Neon adaptation: Supabase auth.users is represented by a narrow read-only
-- compatibility view over authn.users; Supabase Realtime broadcasting is not recreated.

begin;

do $auth_users_compat$
declare relkind "char";
begin
  select c.relkind into relkind
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='auth' and c.relname='users';

  if relkind is null then
    execute $view$
      create view auth.users as
      select id,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at
      from authn.users
    $view$;
  elsif relkind<>'v' then
    raise exception 'auth.users compatibility relation has unexpected kind %',relkind;
  end if;
end
$auth_users_compat$;

revoke all on table auth.users from public;
revoke all on table auth.users from edusentia_worker_runtime;

alter table public.classes
  add column if not exists class_teacher_record_id uuid;

do $class_teacher_record_fk$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='classes_class_teacher_record_id_fkey'
      and conrelid='public.classes'::regclass
  ) then
    alter table public.classes
      add constraint classes_class_teacher_record_id_fkey
      foreign key(class_teacher_record_id) references public.teachers(id) on delete set null;
  end if;
end
$class_teacher_record_fk$;

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
$function$;

CREATE OR REPLACE FUNCTION public.enforce_licensed_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_snapshot jsonb;
  v_feature text;
  v_limit integer;
  v_count integer;
  v_becoming_active boolean:=false;
  v_new jsonb;
  v_old jsonb;
  v_record_id uuid;
  v_new_deleted_at text;
  v_old_deleted_at text;
begin
  if auth.role() in ('service_role','supabase_admin') or auth.role() is null then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  -- Append-only operational evidence must remain recordable when a school is
  -- read-only or when a Platform Super Administrator has platform-control
  -- access. Direct browser DML is revoked below, so these rows are written only
  -- by trusted SECURITY DEFINER functions and database audit triggers.
  if tg_table_name in ('audit_log','client_error_events','security_events','system_maintenance_log') then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  v_snapshot:=public.license_snapshot_for_role(public.current_app_role()::text);
  if not coalesce((v_snapshot->>'write_allowed')::boolean,false) then
    raise exception 'LICENSE_WRITE_RESTRICTED: %',
      coalesce(nullif(v_snapshot->>'warning',''),'The current licence does not permit changes.')
      using errcode='42501';
  end if;
  v_feature:=public.license_feature_for_table(tg_table_name);
  perform public.require_license_feature(v_feature);
  if tg_table_name='report_card_templates' then
    perform public.require_license_feature('report_cards');
  elsif tg_table_name='certificate_templates' then
    perform public.require_license_feature('certificates');
  end if;
  if tg_op<>'DELETE' then v_new:=to_jsonb(new); end if;
  if tg_op<>'INSERT' then v_old:=to_jsonb(old); end if;
  if tg_table_name='students' and tg_op in ('INSERT','UPDATE') then
    v_record_id:=public.safe_uuid(v_new->>'id');
    v_new_deleted_at:=nullif(v_new->>'deleted_at','');
    v_old_deleted_at:=nullif(v_old->>'deleted_at','');
    if v_new->>'status'='active' and v_new_deleted_at is null then
      if tg_op='INSERT' then
        v_becoming_active:=true;
      else
        v_becoming_active:=(v_old->>'status') is distinct from (v_new->>'status')
          or v_old_deleted_at is distinct from v_new_deleted_at;
      end if;
    end if;
    if v_becoming_active then
      perform pg_advisory_xact_lock(hashtext('rce-license-students'));
      v_limit:=nullif(v_snapshot#>>'{plan,max_students}','')::integer;
      if v_limit is not null then
        select count(*) into v_count
        from public.students s
        where s.status='active' and s.deleted_at is null
          and (tg_op='INSERT' or s.id is distinct from v_record_id);
        if v_count>=v_limit then
          raise exception 'LICENSE_CAPACITY_REACHED: The plan permits a maximum of % active students',v_limit
            using errcode='23514';
        end if;
      end if;
    end if;
  elsif tg_table_name='teachers' and tg_op in ('INSERT','UPDATE') then
    v_record_id:=public.safe_uuid(v_new->>'id');
    v_new_deleted_at:=nullif(v_new->>'deleted_at','');
    v_old_deleted_at:=nullif(v_old->>'deleted_at','');
    if coalesce((v_new->>'active')::boolean,false) and v_new_deleted_at is null then
      if tg_op='INSERT' then
        v_becoming_active:=true;
      else
        v_becoming_active:=coalesce((v_old->>'active')::boolean,false)
            is distinct from coalesce((v_new->>'active')::boolean,false)
          or v_old_deleted_at is distinct from v_new_deleted_at;
      end if;
    end if;
    if v_becoming_active then
      perform pg_advisory_xact_lock(hashtext('rce-license-teachers'));
      v_limit:=nullif(v_snapshot#>>'{plan,max_teachers}','')::integer;
      if v_limit is not null then
        select count(*) into v_count
        from public.teachers t
        where t.active and t.deleted_at is null
          and (tg_op='INSERT' or t.id is distinct from v_record_id);
        if v_count>=v_limit then
          raise exception 'LICENSE_CAPACITY_REACHED: The plan permits a maximum of % active teachers',v_limit
            using errcode='23514';
        end if;
      end if;
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $function$;

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
end $function$;

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
end $function$;

revoke all on function public.license_feature_for_table(text) from public;
revoke all on function public.enforce_licensed_write() from public;
revoke all on function public.sync_teacher_responsibility_access(uuid) from public;
revoke all on function public.sync_teacher_record_class_links() from public;

revoke all on function public.license_feature_for_table(text) from edusentia_worker_runtime;
revoke all on function public.enforce_licensed_write() from edusentia_worker_runtime;
revoke all on function public.sync_teacher_responsibility_access(uuid) from edusentia_worker_runtime;
revoke all on function public.sync_teacher_record_class_links() from edusentia_worker_runtime;

drop trigger if exists teachers_audit on public.teachers;
create trigger teachers_audit
after insert or update or delete on public.teachers
for each row execute function public.audit_row_change();

drop trigger if exists headteachers_audit on public.headteachers;
create trigger headteachers_audit
after insert or update or delete on public.headteachers
for each row execute function public.audit_row_change();

drop trigger if exists teachers_license_write_guard on public.teachers;
create trigger teachers_license_write_guard
before insert or update or delete on public.teachers
for each row execute function public.enforce_licensed_write();

drop trigger if exists headteachers_license_write_guard on public.headteachers;
create trigger headteachers_license_write_guard
before insert or update or delete on public.headteachers
for each row execute function public.enforce_licensed_write();

drop trigger if exists sync_teacher_record_class_links_trigger on public.teachers;
create trigger sync_teacher_record_class_links_trigger
after insert or delete or update of profile_id,active,deleted_at,employment_status on public.teachers
for each row execute function public.sync_teacher_record_class_links();

insert into app.schema_migrations(version)
values ('0036_certified_staff_runtime_guards')
on conflict do nothing;

update app.release_identity
set schema_version='0036'
where edition='Edusentia Enterprise Neon Edition';

commit;
