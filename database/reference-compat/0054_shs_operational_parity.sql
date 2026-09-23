begin;

-- Neon-native Senior High operational parity.
-- Preserves the live blueprint SHS Programme workflow without exposing direct
-- browser access to the compatibility tables.

create or replace function public.neon_shs_academic_console()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','app','auth','pg_catalog','extensions'
as $function$
declare
  institution text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode='42501';
  end if;
  if public.current_app_role()::text not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not public.license_read_allowed() then
    raise exception 'The current licence does not permit academic access' using errcode='42501';
  end if;
  perform public.require_license_feature('core_records');

  select coalesce(s.institution_type,'basic_jhs')
    into institution
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;

  if coalesce(institution,'basic_jhs') <> 'senior_high' then
    raise exception 'Senior High programme management is available only to Senior High schools'
      using errcode='42501';
  end if;

  return jsonb_build_object(
    'programmes',coalesce((
      select jsonb_agg(to_jsonb(p) order by lower(p.name),lower(p.code))
      from public.academic_programmes p
      where p.institution_scope='senior_high'
    ),'[]'::jsonb),
    'levels',coalesce((
      select jsonb_agg(to_jsonb(l) order by l.level_order,lower(l.name),lower(l.code))
      from public.academic_levels l
      where l.institution_scope='senior_high'
    ),'[]'::jsonb),
    'subjects',coalesce((
      select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'code',s.code,'active',s.active)
        order by lower(s.name),lower(s.code::text))
      from public.subjects s
      where s.active=true
    ),'[]'::jsonb),
    'years',coalesce((
      select jsonb_agg(jsonb_build_object('id',y.id,'name',y.name,'start_date',y.start_date,'end_date',y.end_date)
        order by y.start_date desc nulls last,lower(y.name::text))
      from public.academic_years y
      where y.deleted_at is null
    ),'[]'::jsonb),
    'students',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'admission_no',s.admission_no,'first_name',s.first_name,
        'middle_name',s.middle_name,'last_name',s.last_name,'status',s.status
      ) order by lower(s.last_name),lower(s.first_name),s.admission_no::text)
      from public.students s
      where s.deleted_at is null
    ),'[]'::jsonb),
    'enrollments',coalesce((
      select jsonb_agg(to_jsonb(e) order by e.created_at desc,e.id)
      from public.student_programme_enrollments e
      where exists(
        select 1 from public.academic_programmes p
        where p.id=e.programme_id and p.institution_scope='senior_high'
      )
    ),'[]'::jsonb),
    'mappings',coalesce((
      select jsonb_agg(to_jsonb(m) order by m.display_order,m.created_at,m.id)
      from public.shs_programme_subjects m
      where exists(
        select 1 from public.academic_programmes p
        where p.id=m.programme_id and p.institution_scope='senior_high'
      )
    ),'[]'::jsonb)
  );
end
$function$;

create or replace function public.neon_shs_academic_insert(entity_type text, payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','auth','pg_catalog','extensions'
as $function$
declare
  kind text:=lower(btrim(coalesce(entity_type,'')));
  institution text;
  result jsonb;
  programme_id uuid;
  level_id uuid;
  subject_id uuid;
  student_id uuid;
  academic_year_id uuid;
  status_text text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode='42501';
  end if;
  if public.current_app_role()::text not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not public.license_write_allowed() then
    raise exception 'The current licence is read-only' using errcode='42501';
  end if;
  perform public.require_license_feature('core_records');

  select coalesce(s.institution_type,'basic_jhs')
    into institution
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;
  if coalesce(institution,'basic_jhs') <> 'senior_high' then
    raise exception 'Senior High programme management is available only to Senior High schools'
      using errcode='42501';
  end if;

  if kind='programme' then
    insert into public.academic_programmes(
      code,name,institution_scope,award_type,duration_years,description,active
    ) values(
      upper(btrim(coalesce(payload->>'code',''))),
      btrim(coalesce(payload->>'name','')),
      'senior_high',
      btrim(coalesce(payload->>'award_type','')),
      nullif(btrim(coalesce(payload->>'duration_years','')),'')::numeric,
      btrim(coalesce(payload->>'description','')),
      coalesce((payload->>'active')::boolean,true)
    )
    returning to_jsonb(academic_programmes.*) into result;
    if coalesce(result->>'code','')='' or coalesce(result->>'name','')='' then
      raise exception 'Programme code and name are required' using errcode='22023';
    end if;

  elsif kind='level' then
    programme_id:=(payload->>'programme_id')::uuid;
    if not exists(select 1 from public.academic_programmes p where p.id=programme_id and p.institution_scope='senior_high') then
      raise exception 'Select a valid Senior High programme' using errcode='22023';
    end if;
    insert into public.academic_levels(programme_id,code,name,institution_scope,level_order,active)
    values(
      programme_id,
      upper(btrim(coalesce(payload->>'code',''))),
      btrim(coalesce(payload->>'name','')),
      'senior_high',
      (payload->>'level_order')::integer,
      coalesce((payload->>'active')::boolean,true)
    )
    returning to_jsonb(academic_levels.*) into result;

  elsif kind='mapping' then
    programme_id:=(payload->>'programme_id')::uuid;
    level_id:=nullif(payload->>'level_id','')::uuid;
    subject_id:=(payload->>'subject_id')::uuid;
    if not exists(select 1 from public.academic_programmes p where p.id=programme_id and p.institution_scope='senior_high') then
      raise exception 'Select a valid Senior High programme' using errcode='22023';
    end if;
    if level_id is not null and not exists(
      select 1 from public.academic_levels l
      where l.id=level_id and l.programme_id=programme_id and l.institution_scope='senior_high'
    ) then
      raise exception 'The selected level does not belong to this programme' using errcode='22023';
    end if;
    if not exists(select 1 from public.subjects s where s.id=subject_id and s.active=true) then
      raise exception 'Select an active subject' using errcode='22023';
    end if;
    if coalesce(payload->>'subject_category','') not in ('core','elective','optional') then
      raise exception 'Invalid subject category' using errcode='22023';
    end if;
    insert into public.shs_programme_subjects(
      programme_id,level_id,subject_id,subject_category,required,display_order
    ) values(
      programme_id,level_id,subject_id,payload->>'subject_category',
      coalesce((payload->>'required')::boolean,true),
      coalesce(nullif(payload->>'display_order','')::integer,0)
    )
    returning to_jsonb(shs_programme_subjects.*) into result;

  elsif kind='enrollment' then
    student_id:=(payload->>'student_id')::uuid;
    programme_id:=(payload->>'programme_id')::uuid;
    academic_year_id:=(payload->>'academic_year_id')::uuid;
    level_id:=nullif(payload->>'level_id','')::uuid;
    status_text:=coalesce(nullif(payload->>'status',''),'active');
    if status_text not in ('active','completed','withdrawn','deferred','suspended') then
      raise exception 'Invalid programme enrollment status' using errcode='22023';
    end if;
    if not exists(select 1 from public.students s where s.id=student_id and s.deleted_at is null) then
      raise exception 'Select a valid student' using errcode='22023';
    end if;
    if not exists(select 1 from public.academic_programmes p where p.id=programme_id and p.institution_scope='senior_high') then
      raise exception 'Select a valid Senior High programme' using errcode='22023';
    end if;
    if not exists(select 1 from public.academic_years y where y.id=academic_year_id and y.deleted_at is null) then
      raise exception 'Select a valid academic year' using errcode='22023';
    end if;
    if level_id is not null and not exists(
      select 1 from public.academic_levels l
      where l.id=level_id and l.programme_id=programme_id and l.institution_scope='senior_high'
    ) then
      raise exception 'The selected level does not belong to this programme' using errcode='22023';
    end if;
    insert into public.student_programme_enrollments(
      student_id,programme_id,academic_year_id,level_id,status,started_on
    ) values(
      student_id,programme_id,academic_year_id,level_id,status_text,
      nullif(payload->>'started_on','')::date
    )
    returning to_jsonb(student_programme_enrollments.*) into result;

  else
    raise exception 'Unsupported Senior High academic entity' using errcode='22023';
  end if;

  return result;
end
$function$;

create or replace function public.neon_shs_academic_remove(entity_type text, target_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public','app','auth','pg_catalog','extensions'
as $function$
declare
  kind text:=lower(btrim(coalesce(entity_type,'')));
  institution text;
  affected integer:=0;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode='42501';
  end if;
  if public.current_app_role()::text not in ('system_admin','principal') then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if not public.license_write_allowed() then
    raise exception 'The current licence is read-only' using errcode='42501';
  end if;
  perform public.require_license_feature('core_records');

  select coalesce(s.institution_type,'basic_jhs')
    into institution
  from public.school_settings s
  order by s.created_at,s.id
  limit 1;
  if coalesce(institution,'basic_jhs') <> 'senior_high' then
    raise exception 'Senior High programme management is available only to Senior High schools'
      using errcode='42501';
  end if;

  if kind='programme' then
    delete from public.academic_programmes p
    where p.id=target_id and p.institution_scope='senior_high';
  elsif kind='level' then
    delete from public.academic_levels l
    where l.id=target_id and l.institution_scope='senior_high';
  elsif kind='mapping' then
    delete from public.shs_programme_subjects m
    where m.id=target_id
      and exists(select 1 from public.academic_programmes p where p.id=m.programme_id and p.institution_scope='senior_high');
  elsif kind='enrollment' then
    delete from public.student_programme_enrollments e
    where e.id=target_id
      and exists(select 1 from public.academic_programmes p where p.id=e.programme_id and p.institution_scope='senior_high');
  else
    raise exception 'Unsupported Senior High academic entity' using errcode='22023';
  end if;

  get diagnostics affected = row_count;
  return affected=1;
end
$function$;

revoke all on function public.neon_shs_academic_console() from public;
revoke all on function public.neon_shs_academic_insert(text,jsonb) from public;
revoke all on function public.neon_shs_academic_remove(text,uuid) from public;
grant execute on function public.neon_shs_academic_console() to edusentia_worker_runtime;
grant execute on function public.neon_shs_academic_insert(text,jsonb) to edusentia_worker_runtime;
grant execute on function public.neon_shs_academic_remove(text,uuid) to edusentia_worker_runtime;

insert into app.schema_migrations(version)
values ('0054_shs_operational_parity')
on conflict do nothing;

commit;
