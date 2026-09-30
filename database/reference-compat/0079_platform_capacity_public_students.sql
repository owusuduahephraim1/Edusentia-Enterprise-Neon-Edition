-- Repair Platform Super Administrator capacity telemetry to count the certified
-- public student directory instead of the legacy app.students table.
begin;

create or replace function app.platform_capacity_snapshot(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=app,platform,pg_catalog
as $fn$
declare
  active_count integer;
  total_count integer;
  base_limit integer;
  override_limit integer;
  effective_limit integer;
  state text;
  blocked boolean;
begin
  perform set_config('app.tenant_id',p_tenant_id::text,true);
  perform set_config('app.user_id',p_tenant_id::text,true);
  perform set_config('app.role','system_admin',true);
  perform set_config('app.aal','2',true);

  select
    count(*) filter(where status='active' and deleted_at is null),
    count(*) filter(where deleted_at is null)
    into active_count,total_count
  from public.students;

  select
    nullif(lp.limits->>'max_students','')::integer,
    nullif(tl.limits_override->>'max_students','')::integer
    into base_limit,override_limit
  from app.tenant_licenses tl
  left join platform.license_plans lp on lp.id=tl.plan_id
  where tl.tenant_id=p_tenant_id
  limit 1;

  effective_limit:=coalesce(override_limit,base_limit);

  if effective_limit is null then
    state:='unlimited';
    blocked:=false;
  elsif active_count>effective_limit then
    state:='over_limit';
    blocked:=true;
  elsif active_count=effective_limit then
    state:='at_limit';
    blocked:=true;
  elsif effective_limit>0 and active_count::numeric/effective_limit>=0.8 then
    state:='near_limit';
    blocked:=false;
  else
    state:='available';
    blocked:=false;
  end if;

  return jsonb_build_object(
    'ok',true,
    'base_limit',base_limit,
    'effective_limit',effective_limit,
    'active',active_count,
    'total',total_count,
    'status',state,
    'admissions_blocked',blocked,
    'checked_at',now()
  );
end
$fn$;

create or replace function app.platform_health_snapshot(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=app,authn,pg_catalog
as $fn$
declare
  v_active_students bigint;
  v_total_students bigint;
  v_active_users bigint;
  v_schema text;
  v_release text;
begin
  perform set_config('app.tenant_id',p_tenant_id::text,true);
  perform set_config('app.user_id',p_tenant_id::text,true);
  perform set_config('app.role','system_admin',true);
  perform set_config('app.aal','2',true);

  select
    count(*) filter(where status='active' and deleted_at is null),
    count(*) filter(where deleted_at is null)
    into v_active_students,v_total_students
  from public.students;

  select count(*) into v_active_users
  from app.tenant_memberships
  where tenant_id=p_tenant_id and status='active';

  select schema_version,version
    into v_schema,v_release
  from app.release_identity
  where edition='Edusentia Enterprise Neon Tenant Runtime'
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'tenant_id',p_tenant_id,
    'database',current_database(),
    'active_students',v_active_students,
    'total_students',v_total_students,
    'active_users',v_active_users,
    'schema_version',coalesce(v_schema,''),
    'runtime_version',coalesce(v_release,''),
    'checked_at',now()
  );
end
$fn$;

insert into app.schema_migrations(version)
values ('0079_platform_capacity_public_students')
on conflict do nothing;

commit;
