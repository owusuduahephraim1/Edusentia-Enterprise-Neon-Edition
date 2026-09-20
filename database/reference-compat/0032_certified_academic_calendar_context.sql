-- Certified source commit: a181e18e0ca044db756193209b5b089cd03efb0f
-- Certified source blob SHA: 0057a212a862d2b5baabbace3e5b4adb47c052ba
-- Neon adaptation: SQL ACL targets only. Business logic is unchanged.

create or replace function public.get_academic_calendar_context()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','extensions'
as $function$
declare
  y_id uuid := null;
  y_name text := null;
  y_start_date date := null;
  y_end_date date := null;

  t_id uuid := null;
  t_name text := null;
  t_sequence smallint := null;
  t_start_date date := null;
  t_end_date date := null;

  n_term_id uuid := null;
  n_term_name text := null;
  n_term_sequence smallint := null;
  n_term_start_date date := null;
  n_term_end_date date := null;
  n_academic_year_id uuid := null;
  n_academic_year_name text := null;
  n_academic_year_start_date date := null;
  n_academic_year_end_date date := null;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  select ay.id, ay.name::text, ay.start_date, ay.end_date
  into y_id, y_name, y_start_date, y_end_date
  from public.academic_years ay
  where ay.deleted_at is null
    and ay.start_date is not null
    and ay.start_date <= current_date
    and (ay.end_date is null or ay.end_date >= current_date)
  order by ay.start_date desc, ay.created_at desc
  limit 1;

  if y_id is not null then
    select tm.id, tm.name::text, tm.sequence, tm.start_date, tm.end_date
    into t_id, t_name, t_sequence, t_start_date, t_end_date
    from public.terms tm
    where tm.deleted_at is null
      and tm.academic_year_id = y_id
      and tm.start_date is not null
      and tm.start_date <= current_date
      and (tm.end_date is null or tm.end_date >= current_date)
    order by tm.start_date desc, tm.sequence desc
    limit 1;
  end if;

  select tm.id,
         tm.name::text,
         tm.sequence,
         tm.start_date,
         tm.end_date,
         ay.id,
         ay.name::text,
         ay.start_date,
         ay.end_date
  into n_term_id,
       n_term_name,
       n_term_sequence,
       n_term_start_date,
       n_term_end_date,
       n_academic_year_id,
       n_academic_year_name,
       n_academic_year_start_date,
       n_academic_year_end_date
  from public.terms tm
  join public.academic_years ay
    on ay.id = tm.academic_year_id
   and ay.deleted_at is null
  where tm.deleted_at is null
    and tm.start_date is not null
    and tm.start_date > current_date
  order by tm.start_date asc, tm.sequence asc
  limit 1;

  return jsonb_build_object(
    'today', current_date,
    'active', y_id is not null,
    'academic_year', case when y_id is null then null else jsonb_build_object(
      'id', y_id,
      'name', y_name,
      'start_date', y_start_date,
      'end_date', y_end_date
    ) end,
    'term', case when t_id is null then null else jsonb_build_object(
      'id', t_id,
      'name', t_name,
      'sequence', t_sequence,
      'start_date', t_start_date,
      'end_date', t_end_date
    ) end,
    'next_period', case when n_term_id is null then null else jsonb_build_object(
      'academic_year_id', n_academic_year_id,
      'academic_year_name', n_academic_year_name,
      'academic_year_start_date', n_academic_year_start_date,
      'academic_year_end_date', n_academic_year_end_date,
      'term_id', n_term_id,
      'term_name', n_term_name,
      'term_sequence', n_term_sequence,
      'term_start_date', n_term_start_date,
      'term_end_date', n_term_end_date
    ) end
  );
end
$function$;

revoke all on function public.get_academic_calendar_context() from public;
revoke all on function public.get_academic_calendar_context() from public;
grant execute on function public.get_academic_calendar_context() to edusentia_worker_runtime;


insert into app.schema_migrations(version)
values ('0032_certified_academic_calendar_context')
on conflict do nothing;

update app.release_identity
set schema_version='0032'
where edition='Edusentia Enterprise Neon Edition';
