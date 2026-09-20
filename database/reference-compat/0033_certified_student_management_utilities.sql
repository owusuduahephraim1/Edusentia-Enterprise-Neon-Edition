-- Certified source project: zjbdsntgifnwmbhgmyxy
-- Certified source commit baseline: a181e18e0ca044db756193209b5b089cd03efb0f
-- Function bodies extracted read-only with pg_get_functiondef.

begin;

alter table public.school_settings
  add column if not exists promotion_cutoff_score smallint not null default 50,
  add column if not exists tenant_code text not null default 'SCH-000000',
  add column if not exists identifier_root text not null default 'SCH000000',
  add column if not exists institution_type text not null default 'basic_jhs';

do $student_settings_constraints$
begin
  if not exists(select 1 from pg_constraint where conname='school_settings_promotion_cutoff_score_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings
      add constraint school_settings_promotion_cutoff_score_chk
      check(promotion_cutoff_score>=40 and promotion_cutoff_score<=60);
  end if;
  if not exists(select 1 from pg_constraint where conname='school_settings_tenant_code_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings
      add constraint school_settings_tenant_code_chk
      check(tenant_code ~ '^[A-Z]{3}-[0-9]{6}
  if exists(select 1 from pg_constraint where conname='school_settings_tenant_code_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings drop constraint school_settings_tenant_code_chk;
  end if;
  alter table public.school_settings
    add constraint school_settings_tenant_code_chk
    check(tenant_code ~ '^[A-Z]{3}-[0-9]{6}$');
  if exists(select 1 from pg_constraint where conname='school_settings_institution_type_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings drop constraint school_settings_institution_type_chk;
  end if;
  alter table public.school_settings
    add constraint school_settings_institution_type_chk
    check(institution_type in('basic_jhs','senior_high'));
end
$student_settings_constraints$;

alter table public.enrollments
  add column if not exists enrollment_origin text not null default 'manual',
  add column if not exists promotion_source_report_id uuid,
  add column if not exists promotion_applied_at timestamptz;

alter table public.student_reports
  add column if not exists promoted_to_class_id uuid;

do $promotion_lineage_constraints$
begin
  if not exists(select 1 from pg_constraint where conname='enrollments_origin_chk' and conrelid='public.enrollments'::regclass) then
    alter table public.enrollments
      add constraint enrollments_origin_chk
      check(enrollment_origin in('manual','automatic_promotion'));
  end if;
  if not exists(select 1 from pg_constraint where conname='enrollments_promotion_source_report_fk' and conrelid='public.enrollments'::regclass) then
    alter table public.enrollments
      add constraint enrollments_promotion_source_report_fk
      foreign key(promotion_source_report_id) references public.student_reports(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conname='student_reports_promoted_to_class_id_fkey' and conrelid='public.student_reports'::regclass) then
    alter table public.student_reports
      add constraint student_reports_promoted_to_class_id_fkey
      foreign key(promoted_to_class_id) references public.classes(id) on delete set null;
  end if;
end
$promotion_lineage_constraints$;

create sequence if not exists public.student_identifier_seq
  as bigint start with 1 increment by 1 minvalue 1 no maxvalue no cycle cache 1;
create sequence if not exists public.staff_identifier_seq
  as bigint start with 1 increment by 1 minvalue 1 no maxvalue no cycle cache 1;

revoke all on sequence public.student_identifier_seq from public;
revoke all on sequence public.staff_identifier_seq from public;
revoke all on sequence public.student_identifier_seq from edusentia_worker_runtime;
revoke all on sequence public.staff_identifier_seq from edusentia_worker_runtime;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.default_grading_interpretation(grade_text text, remark_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when lower(btrim(coalesce(remark_text,'')))='excellent' or btrim(coalesce(grade_text,''))='1' then 'Outstanding performance. Keep it up!'
    when lower(btrim(coalesce(remark_text,'')))='very good' or btrim(coalesce(grade_text,''))='2' then 'Well above average. You are doing great!'
    when lower(btrim(coalesce(remark_text,'')))='good' or btrim(coalesce(grade_text,''))='3' then 'Good achievement. Continue to work hard.'
    when lower(btrim(coalesce(remark_text,'')))='high average' or btrim(coalesce(grade_text,''))='4' then 'Satisfactory performance. Aim higher.'
    when lower(btrim(coalesce(remark_text,'')))='average' or btrim(coalesce(grade_text,''))='5' then 'Fair performance. More effort needed.'
    when lower(btrim(coalesce(remark_text,'')))='low average' or btrim(coalesce(grade_text,''))='6' then 'Below average. Focus and improvement required.'
    when lower(btrim(coalesce(remark_text,'')))='pass' or btrim(coalesce(grade_text,''))='7' then 'Minimum pass. Consistent effort is essential.'
    when lower(btrim(coalesce(remark_text,''))) in ('weak','week') or btrim(coalesce(grade_text,''))='8' then 'Weak performance. Urgent improvement needed.'
    when lower(btrim(coalesce(remark_text,'')))='needs improvement' or btrim(coalesce(grade_text,''))='9' then 'Unsatisfactory. Serious improvement is required.'
    else left(concat(coalesce(nullif(btrim(remark_text),''),'Performance recorded'),'. Continue working consistently to improve performance.'),180)
  end
$function$;

CREATE OR REPLACE FUNCTION public.generate_subject_code(subject_name text, exclude_subject_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleaned text:=upper(regexp_replace(btrim(coalesce(subject_name,'')),'[^[:alnum:] ]+',' ','g'));
  meaningful text[];
  all_words text[];
  selected_words text[];
  token text;
  prefix text:='';
  candidate text;
  attempt integer:=0;
begin
  if auth.uid() is null or not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(cleaned)='' then raise exception 'Subject name is required'; end if;
  select coalesce(array_agg(word order by ord),'{}'::text[]) into all_words
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'';
  select coalesce(array_agg(word order by ord),'{}'::text[]) into meaningful
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'' and word not in ('AND','OF','THE','FOR','IN','TO');
  selected_words:=case when cardinality(meaningful)>0 then meaningful else all_words end;
  if cardinality(selected_words)=1 then
    prefix:=left(regexp_replace(selected_words[1],'[^A-Z0-9]','','g'),3);
  else
    foreach token in array selected_words loop
      prefix:=prefix||left(token,1);
      exit when length(prefix)>=4;
    end loop;
  end if;
  if prefix='' then prefix:='SUB'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nis_subject_code_'||prefix,0));
  loop
    attempt:=attempt+1;
    candidate:=prefix||lpad(floor(random()*10000)::integer::text,4,'0');
    if not exists(
      select 1 from public.subjects s
      where lower(s.code::text)=lower(candidate)
        and (exclude_subject_id is null or s.id<>exclude_subject_id)
    ) then return candidate; end if;
    if attempt>=250 then raise exception 'A unique subject code could not be generated'; end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.is_term_three(term_sequence integer, term_name text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select coalesce(term_sequence=3,false)
    or lower(regexp_replace(coalesce(term_name,''),'[^a-zA-Z0-9]+','','g'))
       in ('term3','termthree','thirdterm','3rdterm')
$function$;

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
$function$;

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
end $function$;

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
end $function$;


revoke all on function public.safe_uuid(text) from public;
revoke all on function public.safe_date(text) from public;
revoke all on function public.safe_integer(text) from public;
revoke all on function public.safe_numeric(text) from public;
revoke all on function public.safe_boolean(text,boolean) from public;
revoke all on function public.safe_timestamptz(text) from public;
revoke all on function public.default_grading_interpretation(text,text) from public;
revoke all on function public.generate_subject_code(text,uuid) from public;
revoke all on function public.is_term_three(integer,text) from public;
revoke all on function public.next_promotion_academic_year(uuid) from public;
revoke all on function public.report_promotion_evaluation(uuid) from public;
revoke all on function public.refresh_report_promotion(uuid,boolean) from public;

revoke all on function public.safe_uuid(text) from edusentia_worker_runtime;
revoke all on function public.safe_date(text) from edusentia_worker_runtime;
revoke all on function public.safe_integer(text) from edusentia_worker_runtime;
revoke all on function public.safe_numeric(text) from edusentia_worker_runtime;
revoke all on function public.safe_boolean(text,boolean) from edusentia_worker_runtime;
revoke all on function public.safe_timestamptz(text) from edusentia_worker_runtime;
revoke all on function public.default_grading_interpretation(text,text) from edusentia_worker_runtime;
revoke all on function public.generate_subject_code(text,uuid) from edusentia_worker_runtime;
revoke all on function public.is_term_three(integer,text) from edusentia_worker_runtime;
revoke all on function public.next_promotion_academic_year(uuid) from edusentia_worker_runtime;
revoke all on function public.report_promotion_evaluation(uuid) from edusentia_worker_runtime;
revoke all on function public.refresh_report_promotion(uuid,boolean) from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0033_certified_student_management_utilities')
on conflict do nothing;

update app.release_identity
set schema_version='0033'
where edition='Edusentia Enterprise Neon Edition';

commit;
);
  end if;
  if not exists(select 1 from pg_constraint where conname='school_settings_identifier_root_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings
      add constraint school_settings_identifier_root_chk
      check(identifier_root ~ '^[A-Z]{3}[0-9]{6}
  if exists(select 1 from pg_constraint where conname='school_settings_tenant_code_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings drop constraint school_settings_tenant_code_chk;
  end if;
  alter table public.school_settings
    add constraint school_settings_tenant_code_chk
    check(tenant_code ~ '^[A-Z]{3}-[0-9]{6}$');
  if exists(select 1 from pg_constraint where conname='school_settings_institution_type_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings drop constraint school_settings_institution_type_chk;
  end if;
  alter table public.school_settings
    add constraint school_settings_institution_type_chk
    check(institution_type in('basic_jhs','senior_high'));
end
$student_settings_constraints$;

alter table public.enrollments
  add column if not exists enrollment_origin text not null default 'manual',
  add column if not exists promotion_source_report_id uuid,
  add column if not exists promotion_applied_at timestamptz;

alter table public.student_reports
  add column if not exists promoted_to_class_id uuid;

do $promotion_lineage_constraints$
begin
  if not exists(select 1 from pg_constraint where conname='enrollments_origin_chk' and conrelid='public.enrollments'::regclass) then
    alter table public.enrollments
      add constraint enrollments_origin_chk
      check(enrollment_origin in('manual','automatic_promotion'));
  end if;
  if not exists(select 1 from pg_constraint where conname='enrollments_promotion_source_report_fk' and conrelid='public.enrollments'::regclass) then
    alter table public.enrollments
      add constraint enrollments_promotion_source_report_fk
      foreign key(promotion_source_report_id) references public.student_reports(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conname='student_reports_promoted_to_class_id_fkey' and conrelid='public.student_reports'::regclass) then
    alter table public.student_reports
      add constraint student_reports_promoted_to_class_id_fkey
      foreign key(promoted_to_class_id) references public.classes(id) on delete set null;
  end if;
end
$promotion_lineage_constraints$;

create sequence if not exists public.student_identifier_seq
  as bigint start with 1 increment by 1 minvalue 1 no maxvalue no cycle cache 1;
create sequence if not exists public.staff_identifier_seq
  as bigint start with 1 increment by 1 minvalue 1 no maxvalue no cycle cache 1;

revoke all on sequence public.student_identifier_seq from public;
revoke all on sequence public.staff_identifier_seq from public;
revoke all on sequence public.student_identifier_seq from edusentia_worker_runtime;
revoke all on sequence public.staff_identifier_seq from edusentia_worker_runtime;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.default_grading_interpretation(grade_text text, remark_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when lower(btrim(coalesce(remark_text,'')))='excellent' or btrim(coalesce(grade_text,''))='1' then 'Outstanding performance. Keep it up!'
    when lower(btrim(coalesce(remark_text,'')))='very good' or btrim(coalesce(grade_text,''))='2' then 'Well above average. You are doing great!'
    when lower(btrim(coalesce(remark_text,'')))='good' or btrim(coalesce(grade_text,''))='3' then 'Good achievement. Continue to work hard.'
    when lower(btrim(coalesce(remark_text,'')))='high average' or btrim(coalesce(grade_text,''))='4' then 'Satisfactory performance. Aim higher.'
    when lower(btrim(coalesce(remark_text,'')))='average' or btrim(coalesce(grade_text,''))='5' then 'Fair performance. More effort needed.'
    when lower(btrim(coalesce(remark_text,'')))='low average' or btrim(coalesce(grade_text,''))='6' then 'Below average. Focus and improvement required.'
    when lower(btrim(coalesce(remark_text,'')))='pass' or btrim(coalesce(grade_text,''))='7' then 'Minimum pass. Consistent effort is essential.'
    when lower(btrim(coalesce(remark_text,''))) in ('weak','week') or btrim(coalesce(grade_text,''))='8' then 'Weak performance. Urgent improvement needed.'
    when lower(btrim(coalesce(remark_text,'')))='needs improvement' or btrim(coalesce(grade_text,''))='9' then 'Unsatisfactory. Serious improvement is required.'
    else left(concat(coalesce(nullif(btrim(remark_text),''),'Performance recorded'),'. Continue working consistently to improve performance.'),180)
  end
$function$;

CREATE OR REPLACE FUNCTION public.generate_subject_code(subject_name text, exclude_subject_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleaned text:=upper(regexp_replace(btrim(coalesce(subject_name,'')),'[^[:alnum:] ]+',' ','g'));
  meaningful text[];
  all_words text[];
  selected_words text[];
  token text;
  prefix text:='';
  candidate text;
  attempt integer:=0;
begin
  if auth.uid() is null or not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(cleaned)='' then raise exception 'Subject name is required'; end if;
  select coalesce(array_agg(word order by ord),'{}'::text[]) into all_words
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'';
  select coalesce(array_agg(word order by ord),'{}'::text[]) into meaningful
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'' and word not in ('AND','OF','THE','FOR','IN','TO');
  selected_words:=case when cardinality(meaningful)>0 then meaningful else all_words end;
  if cardinality(selected_words)=1 then
    prefix:=left(regexp_replace(selected_words[1],'[^A-Z0-9]','','g'),3);
  else
    foreach token in array selected_words loop
      prefix:=prefix||left(token,1);
      exit when length(prefix)>=4;
    end loop;
  end if;
  if prefix='' then prefix:='SUB'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nis_subject_code_'||prefix,0));
  loop
    attempt:=attempt+1;
    candidate:=prefix||lpad(floor(random()*10000)::integer::text,4,'0');
    if not exists(
      select 1 from public.subjects s
      where lower(s.code::text)=lower(candidate)
        and (exclude_subject_id is null or s.id<>exclude_subject_id)
    ) then return candidate; end if;
    if attempt>=250 then raise exception 'A unique subject code could not be generated'; end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.is_term_three(term_sequence integer, term_name text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select coalesce(term_sequence=3,false)
    or lower(regexp_replace(coalesce(term_name,''),'[^a-zA-Z0-9]+','','g'))
       in ('term3','termthree','thirdterm','3rdterm')
$function$;

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
$function$;

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
end $function$;

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
end $function$;


revoke all on function public.safe_uuid(text) from public;
revoke all on function public.safe_date(text) from public;
revoke all on function public.safe_integer(text) from public;
revoke all on function public.safe_numeric(text) from public;
revoke all on function public.safe_boolean(text,boolean) from public;
revoke all on function public.safe_timestamptz(text) from public;
revoke all on function public.default_grading_interpretation(text,text) from public;
revoke all on function public.generate_subject_code(text,uuid) from public;
revoke all on function public.is_term_three(integer,text) from public;
revoke all on function public.next_promotion_academic_year(uuid) from public;
revoke all on function public.report_promotion_evaluation(uuid) from public;
revoke all on function public.refresh_report_promotion(uuid,boolean) from public;

revoke all on function public.safe_uuid(text) from edusentia_worker_runtime;
revoke all on function public.safe_date(text) from edusentia_worker_runtime;
revoke all on function public.safe_integer(text) from edusentia_worker_runtime;
revoke all on function public.safe_numeric(text) from edusentia_worker_runtime;
revoke all on function public.safe_boolean(text,boolean) from edusentia_worker_runtime;
revoke all on function public.safe_timestamptz(text) from edusentia_worker_runtime;
revoke all on function public.default_grading_interpretation(text,text) from edusentia_worker_runtime;
revoke all on function public.generate_subject_code(text,uuid) from edusentia_worker_runtime;
revoke all on function public.is_term_three(integer,text) from edusentia_worker_runtime;
revoke all on function public.next_promotion_academic_year(uuid) from edusentia_worker_runtime;
revoke all on function public.report_promotion_evaluation(uuid) from edusentia_worker_runtime;
revoke all on function public.refresh_report_promotion(uuid,boolean) from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0033_certified_student_management_utilities')
on conflict do nothing;

update app.release_identity
set schema_version='0033'
where edition='Edusentia Enterprise Neon Edition';

commit;
);
  end if;
  if not exists(select 1 from pg_constraint where conname='school_settings_institution_type_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings
      add constraint school_settings_institution_type_chk
      check(institution_type in('basic_jhs','senior_high'));
  end if;
  if exists(select 1 from pg_constraint where conname='school_settings_tenant_code_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings drop constraint school_settings_tenant_code_chk;
  end if;
  alter table public.school_settings
    add constraint school_settings_tenant_code_chk
    check(tenant_code ~ '^[A-Z]{3}-[0-9]{6}$');
  if exists(select 1 from pg_constraint where conname='school_settings_institution_type_chk' and conrelid='public.school_settings'::regclass) then
    alter table public.school_settings drop constraint school_settings_institution_type_chk;
  end if;
  alter table public.school_settings
    add constraint school_settings_institution_type_chk
    check(institution_type in('basic_jhs','senior_high'));
end
$student_settings_constraints$;

alter table public.enrollments
  add column if not exists enrollment_origin text not null default 'manual',
  add column if not exists promotion_source_report_id uuid,
  add column if not exists promotion_applied_at timestamptz;

alter table public.student_reports
  add column if not exists promoted_to_class_id uuid;

do $promotion_lineage_constraints$
begin
  if not exists(select 1 from pg_constraint where conname='enrollments_origin_chk' and conrelid='public.enrollments'::regclass) then
    alter table public.enrollments
      add constraint enrollments_origin_chk
      check(enrollment_origin in('manual','automatic_promotion'));
  end if;
  if not exists(select 1 from pg_constraint where conname='enrollments_promotion_source_report_fk' and conrelid='public.enrollments'::regclass) then
    alter table public.enrollments
      add constraint enrollments_promotion_source_report_fk
      foreign key(promotion_source_report_id) references public.student_reports(id) on delete set null;
  end if;
  if not exists(select 1 from pg_constraint where conname='student_reports_promoted_to_class_id_fkey' and conrelid='public.student_reports'::regclass) then
    alter table public.student_reports
      add constraint student_reports_promoted_to_class_id_fkey
      foreign key(promoted_to_class_id) references public.classes(id) on delete set null;
  end if;
end
$promotion_lineage_constraints$;

create sequence if not exists public.student_identifier_seq
  as bigint start with 1 increment by 1 minvalue 1 no maxvalue no cycle cache 1;
create sequence if not exists public.staff_identifier_seq
  as bigint start with 1 increment by 1 minvalue 1 no maxvalue no cycle cache 1;

revoke all on sequence public.student_identifier_seq from public;
revoke all on sequence public.staff_identifier_seq from public;
revoke all on sequence public.student_identifier_seq from edusentia_worker_runtime;
revoke all on sequence public.staff_identifier_seq from edusentia_worker_runtime;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.default_grading_interpretation(grade_text text, remark_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select case
    when lower(btrim(coalesce(remark_text,'')))='excellent' or btrim(coalesce(grade_text,''))='1' then 'Outstanding performance. Keep it up!'
    when lower(btrim(coalesce(remark_text,'')))='very good' or btrim(coalesce(grade_text,''))='2' then 'Well above average. You are doing great!'
    when lower(btrim(coalesce(remark_text,'')))='good' or btrim(coalesce(grade_text,''))='3' then 'Good achievement. Continue to work hard.'
    when lower(btrim(coalesce(remark_text,'')))='high average' or btrim(coalesce(grade_text,''))='4' then 'Satisfactory performance. Aim higher.'
    when lower(btrim(coalesce(remark_text,'')))='average' or btrim(coalesce(grade_text,''))='5' then 'Fair performance. More effort needed.'
    when lower(btrim(coalesce(remark_text,'')))='low average' or btrim(coalesce(grade_text,''))='6' then 'Below average. Focus and improvement required.'
    when lower(btrim(coalesce(remark_text,'')))='pass' or btrim(coalesce(grade_text,''))='7' then 'Minimum pass. Consistent effort is essential.'
    when lower(btrim(coalesce(remark_text,''))) in ('weak','week') or btrim(coalesce(grade_text,''))='8' then 'Weak performance. Urgent improvement needed.'
    when lower(btrim(coalesce(remark_text,'')))='needs improvement' or btrim(coalesce(grade_text,''))='9' then 'Unsatisfactory. Serious improvement is required.'
    else left(concat(coalesce(nullif(btrim(remark_text),''),'Performance recorded'),'. Continue working consistently to improve performance.'),180)
  end
$function$;

CREATE OR REPLACE FUNCTION public.generate_subject_code(subject_name text, exclude_subject_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  cleaned text:=upper(regexp_replace(btrim(coalesce(subject_name,'')),'[^[:alnum:] ]+',' ','g'));
  meaningful text[];
  all_words text[];
  selected_words text[];
  token text;
  prefix text:='';
  candidate text;
  attempt integer:=0;
begin
  if auth.uid() is null or not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(cleaned)='' then raise exception 'Subject name is required'; end if;
  select coalesce(array_agg(word order by ord),'{}'::text[]) into all_words
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'';
  select coalesce(array_agg(word order by ord),'{}'::text[]) into meaningful
  from regexp_split_to_table(cleaned,'[[:space:]]+') with ordinality as words(word,ord)
  where btrim(word)<>'' and word not in ('AND','OF','THE','FOR','IN','TO');
  selected_words:=case when cardinality(meaningful)>0 then meaningful else all_words end;
  if cardinality(selected_words)=1 then
    prefix:=left(regexp_replace(selected_words[1],'[^A-Z0-9]','','g'),3);
  else
    foreach token in array selected_words loop
      prefix:=prefix||left(token,1);
      exit when length(prefix)>=4;
    end loop;
  end if;
  if prefix='' then prefix:='SUB'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nis_subject_code_'||prefix,0));
  loop
    attempt:=attempt+1;
    candidate:=prefix||lpad(floor(random()*10000)::integer::text,4,'0');
    if not exists(
      select 1 from public.subjects s
      where lower(s.code::text)=lower(candidate)
        and (exclude_subject_id is null or s.id<>exclude_subject_id)
    ) then return candidate; end if;
    if attempt>=250 then raise exception 'A unique subject code could not be generated'; end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.is_term_three(term_sequence integer, term_name text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$
  select coalesce(term_sequence=3,false)
    or lower(regexp_replace(coalesce(term_name,''),'[^a-zA-Z0-9]+','','g'))
       in ('term3','termthree','thirdterm','3rdterm')
$function$;

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
$function$;

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
end $function$;

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
end $function$;


revoke all on function public.safe_uuid(text) from public;
revoke all on function public.safe_date(text) from public;
revoke all on function public.safe_integer(text) from public;
revoke all on function public.safe_numeric(text) from public;
revoke all on function public.safe_boolean(text,boolean) from public;
revoke all on function public.safe_timestamptz(text) from public;
revoke all on function public.default_grading_interpretation(text,text) from public;
revoke all on function public.generate_subject_code(text,uuid) from public;
revoke all on function public.is_term_three(integer,text) from public;
revoke all on function public.next_promotion_academic_year(uuid) from public;
revoke all on function public.report_promotion_evaluation(uuid) from public;
revoke all on function public.refresh_report_promotion(uuid,boolean) from public;

revoke all on function public.safe_uuid(text) from edusentia_worker_runtime;
revoke all on function public.safe_date(text) from edusentia_worker_runtime;
revoke all on function public.safe_integer(text) from edusentia_worker_runtime;
revoke all on function public.safe_numeric(text) from edusentia_worker_runtime;
revoke all on function public.safe_boolean(text,boolean) from edusentia_worker_runtime;
revoke all on function public.safe_timestamptz(text) from edusentia_worker_runtime;
revoke all on function public.default_grading_interpretation(text,text) from edusentia_worker_runtime;
revoke all on function public.generate_subject_code(text,uuid) from edusentia_worker_runtime;
revoke all on function public.is_term_three(integer,text) from edusentia_worker_runtime;
revoke all on function public.next_promotion_academic_year(uuid) from edusentia_worker_runtime;
revoke all on function public.report_promotion_evaluation(uuid) from edusentia_worker_runtime;
revoke all on function public.refresh_report_promotion(uuid,boolean) from edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0033_certified_student_management_utilities')
on conflict do nothing;

update app.release_identity
set schema_version='0033'
where edition='Edusentia Enterprise Neon Edition';

commit;
