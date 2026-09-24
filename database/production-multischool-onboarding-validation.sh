#!/usr/bin/env bash
set -euo pipefail
: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

MASTER_URL="$BOOTSTRAP_DATABASE_URL"
TEMPLATE_DB="${TENANT_TEMPLATE_DATABASE:-edusentia_tenant_template}"
RUN_TOKEN="${GITHUB_RUN_ID:-local}_${GITHUB_RUN_ATTEMPT:-1}"
RUN_TOKEN="${RUN_TOKEN//-/_}"
SCHOOL_NAME="Edusentia Validation School ${RUN_TOKEN}"
CONTACT_NAME="Synthetic Validation Administrator"
CONTACT_EMAIL="validation_${RUN_TOKEN}@synthetic.invalid"
CONTACT_PHONE="+233000000000"
COUNTRY="Ghana"
API_BASE="${EDUSENTIA_API_BASE:-https://edusentia-enterprise-neon-api.edusentia-enterprise-neon.workers.dev}"

echo "Starting production multi-school onboarding validation for: $SCHOOL_NAME"

ACTOR_ID="$(psql "$MASTER_URL" -Atc "select user_id from platform.admins where active and role='platform_super_admin' order by created_at limit 1")"
test -n "$ACTOR_ID"

NIPE_BEFORE="$(psql "$MASTER_URL" -Atc "select coalesce(string_agg(concat_ws('|',tenant_id::text,tenant_code,school_name,coalesce(database_name,''),status,plan_code),E'\n' order by tenant_id::text),'') from platform.tenant_control where lower(school_name) like '%nipe%international%school%';")"

REG_ID="$(psql "$MASTER_URL" -X -qAtc "
select id
from platform.school_registrations
where status in('pending','provisioning','active')
  and metadata->>'purpose'='multi-school onboarding validation'
order by created_at desc
limit 1" | head -n1)"
if [ -z "$REG_ID" ]; then
  REG_ID="$(psql "$MASTER_URL" -X -qAtc "
  insert into platform.school_registrations(
    school_name,contact_name,contact_email,contact_phone,country,requested_plan_code,institution_type,status,metadata
  ) values(
    '$SCHOOL_NAME','$CONTACT_NAME','$CONTACT_EMAIL','$CONTACT_PHONE','$COUNTRY','starter','basic_jhs','pending',
    jsonb_build_object('validation_run','$RUN_TOKEN','purpose','multi-school onboarding validation')
  ) returning id" | head -n1)"
fi
test -n "$REG_ID"

REG_STATUS="$(psql "$MASTER_URL" -Atc "select status from platform.school_registrations where id='$REG_ID'::uuid")"
if [ "$REG_STATUS" = "pending" ]; then
  psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "
  set role edusentia_worker_runtime;
  select platform.configure_initial_license(
    '$REG_ID'::uuid,
    '$ACTOR_ID'::uuid,
    'academic_year',
    '2026/2027',
    '2026-09-01T00:00:00Z'::timestamptz,
    '2027-08-31T23:59:59Z'::timestamptz,
    14
  );" >/dev/null
  psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "set role edusentia_worker_runtime; select platform.approve_registration('$REG_ID'::uuid,'$ACTOR_ID'::uuid);" >/dev/null
fi

TENANT_ID="$(psql "$MASTER_URL" -Atc "select tenant_id from platform.school_registrations where id='$REG_ID'::uuid")"
TENANT_CODE="$(psql "$MASTER_URL" -Atc "select tenant_code from platform.tenant_control where tenant_id='$TENANT_ID'::uuid")"
ADMIN_EMAIL="$(psql "$MASTER_URL" -Atc "select admin_email from platform.tenant_control where tenant_id='$TENANT_ID'::uuid")"
INSTITUTION_TYPE="$(psql "$MASTER_URL" -Atc "select institution_type from platform.tenant_control where tenant_id='$TENANT_ID'::uuid")"
DB_NAME="edusentia_${TENANT_CODE,,}"
DB_NAME="${DB_NAME//-/_}"

test -n "$TENANT_ID"
test -n "$TENANT_CODE"
test -n "$ADMIN_EMAIL"
[[ "$DB_NAME" =~ ^edusentia_[a-z0-9_]{3,50}$ ]]

DB_STATE="$(psql "$MASTER_URL" -Atc "select coalesce(database_state,'') from platform.tenant_control where tenant_id='$TENANT_ID'::uuid")"
DB_EXISTS="$(psql "$MASTER_URL" -Atc "select count(*) from pg_database where datname='$DB_NAME'")"

if [ "$DB_STATE" != "isolated_ready" ]; then
  psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "
  set role edusentia_worker_runtime;
  update platform.provisioning_jobs
  set status='running',stage='database_create',attempts=attempts+1,started_at=coalesce(started_at,now()),updated_at=now(),last_error=''
  where tenant_id='$TENANT_ID'::uuid and status<>'cancelled';
  update platform.tenant_control
  set database_name='$DB_NAME',database_state='creating',updated_at=now()
  where tenant_id='$TENANT_ID'::uuid;
  " >/dev/null

  if [ "$DB_EXISTS" = "0" ]; then
    psql "$MASTER_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
set role edusentia_provisioner;
create database "$DB_NAME" owner edusentia_provisioner template "$TEMPLATE_DB";
revoke connect on database "$DB_NAME" from public;
grant connect on database "$DB_NAME" to edusentia_worker_runtime;
grant connect on database "$DB_NAME" to edusentia_runtime;
SQL
  fi
fi

TENANT_URL="$(MASTER_URL="$MASTER_URL" DB_NAME="$DB_NAME" node --input-type=module -e 'const u=new URL(process.env.MASTER_URL);u.pathname="/"+process.env.DB_NAME;process.stdout.write(u.toString())')"
echo "::add-mask::$TENANT_URL"

if [ "$DB_STATE" != "isolated_ready" ]; then
  psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "
  set role edusentia_worker_runtime;
  update platform.provisioning_jobs set stage='tenant_initialize',updated_at=now()
  where tenant_id='$TENANT_ID'::uuid and status='running';
  " >/dev/null

  TENANT_ALREADY_INITIALIZED="$(psql "$TENANT_URL" -Atc "select count(*) from app.tenants where id='$TENANT_ID'::uuid")"
  if [ "$TENANT_ALREADY_INITIALIZED" = "0" ]; then
    psql "$TENANT_URL" -v ON_ERROR_STOP=1 -c "
    select app.platform_initialize_tenant(
      '$TENANT_ID'::uuid,
      '$TENANT_CODE',
      '$(psql "$MASTER_URL" -Atc "select school_name from platform.tenant_control where tenant_id='$TENANT_ID'::uuid")',
      '$INSTITUTION_TYPE',
      '$ADMIN_EMAIL',
      '$(psql "$MASTER_URL" -Atc "select contact_name from platform.school_registrations where id='$REG_ID'::uuid")',
      'starter',
      '2026-09-01T00:00:00Z'::timestamptz,
      '2027-08-31T23:59:59Z'::timestamptz
    );" >/dev/null
  fi

  test "$(psql "$TENANT_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "0020"
  test "$(psql "$TENANT_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1")" = "neon-v1.0.0-r42"
  test "$(psql "$TENANT_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0048"
  test "$(psql "$TENANT_URL" -Atc "select to_regprocedure('public.get_bootstrap_data()') is not null")" = "t"

  psql "$MASTER_URL" -v ON_ERROR_STOP=1 -c "
  set role edusentia_worker_runtime;
  update platform.provisioning_jobs set stage='release_verify',updated_at=now()
  where tenant_id='$TENANT_ID'::uuid and status='running';
  select platform.mark_isolated_tenant_ready(
    '$TENANT_ID'::uuid,
    '$ACTOR_ID'::uuid,
    '$DB_NAME',
    'neon-v1.0.0-r42',
    ''
  );" >/dev/null
fi

test "$(psql "$MASTER_URL" -Atc "select status='active' and database_state='isolated_ready' and license_status='active' from platform.tenant_control where tenant_id='$TENANT_ID'::uuid")" = "t"
test "$(psql "$MASTER_URL" -X -qAtc "set role edusentia_worker_runtime; select count(*)=1 from platform.resolve_login_route('$ADMIN_EMAIL','$TENANT_CODE')" | tail -n1)" = "t"
test "$(psql "$MASTER_URL" -Atc "select count(*)=1 from platform.provisioning_jobs where tenant_id='$TENANT_ID'::uuid and status='ready' and stage='ready'")" = "t"

ADMIN_ID="$(psql "$TENANT_URL" -Atc "select id from authn.users where lower(email)=lower('$ADMIN_EMAIL') limit 1")"
test -n "$ADMIN_ID"

BOOTSTRAP_OK="$(psql "$TENANT_URL" -X -qAtc "
begin;
set local role edusentia_worker_runtime;
select app.set_request_context('$TENANT_ID'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint);
select public.get_bootstrap_data() is not null;
rollback;" | tail -1)"
test "$BOOTSTRAP_OK" = "t"

ACADEMIC_OK="$(psql "$TENANT_URL" -X -qAtc "
begin;
set local role edusentia_worker_runtime;
select app.set_request_context('$TENANT_ID'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint);
select public.save_academic_entity(
  'academic_years',
  jsonb_build_object('name','Validation 2026/2027','start_date','2026-09-01','end_date','2027-08-31')
) is not null;
select public.save_academic_entity(
  'classes',
  jsonb_build_object('name','Validation Basic 1','level_order',1,'active',true)
) is not null;
select public.save_academic_entity(
  'subjects',
  jsonb_build_object('name','Validation English Language','display_order',1,'active',true)
) is not null;
rollback;" | tail -1)"
test "$ACADEMIC_OK" = "t"

READINESS_OK="$(psql "$TENANT_URL" -X -qAtc "
begin;
set local role edusentia_worker_runtime;
select app.set_request_context('$TENANT_ID'::uuid,'$ADMIN_ID'::uuid,'system_admin',2::smallint);
select coalesce((public.validate_operational_readiness()->>'ready')::boolean,false);
rollback;" | tail -1)"
test "$READINESS_OK" = "t"

HEALTH_OK="$(psql "$TENANT_URL" -Atc "select coalesce((app.platform_health_snapshot('$TENANT_ID'::uuid)->>'ok')::boolean,false)")"
test "$HEALTH_OK" = "t"
test "$(psql "$TENANT_URL" -Atc "select (app.platform_capacity_snapshot('$TENANT_ID'::uuid)->>'base_limit')::integer")" = "300"

test "$(psql "$TENANT_URL" -Atc "select (feature_flags->>'uploaded_templates')::boolean=false and (feature_flags->>'id_cards')::boolean=false and (feature_flags->>'finance_fees')::boolean=true from platform.license_plans where code='starter'")" = "t"
test "$(psql "$TENANT_URL" -Atc "select (feature_flags->>'uploaded_templates')::boolean=true and (feature_flags->>'finance_exports')::boolean=true from platform.license_plans where code='professional'")" = "t"
test "$(psql "$TENANT_URL" -Atc "select (feature_flags->>'payroll')::boolean=true and (feature_flags->>'custom_branding')::boolean=true from platform.license_plans where code='enterprise'")" = "t"

WORKER_HEALTH="$(curl -fsS "$API_BASE/api/health")"
WORKER_HEALTH="$WORKER_HEALTH" node --input-type=module -e '
const h=JSON.parse(process.env.WORKER_HEALTH||"{}");
if(!(h.ok===true&&h.database===true&&h.storage===true))process.exit(1);
'

PUBLIC_SCHOOL="$(curl -fsS "$API_BASE/api/public/schools/$TENANT_CODE")"
PUBLIC_SCHOOL="$PUBLIC_SCHOOL" TENANT_CODE="$TENANT_CODE" node --input-type=module -e '
const r=JSON.parse(process.env.PUBLIC_SCHOOL||"{}");
const s=r.school||{};
if(!(r.ok===true&&String(s.tenant_code||s.tenantCode||"").toUpperCase()===process.env.TENANT_CODE))process.exit(1);
'

NIPE_AFTER="$(psql "$MASTER_URL" -Atc "select coalesce(string_agg(concat_ws('|',tenant_id::text,tenant_code,school_name,coalesce(database_name,''),status,plan_code),E'\n' order by tenant_id::text),'') from platform.tenant_control where lower(school_name) like '%nipe%international%school%';")"
test "$NIPE_BEFORE" = "$NIPE_AFTER"

echo "Production multi-school onboarding validation passed."
echo "Tenant ID: $TENANT_ID"
echo "Tenant code: $TENANT_CODE"
echo "Database: $DB_NAME"
echo "Administrator: $ADMIN_EMAIL"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Production multi-school onboarding validation"
    echo ""
    echo "- Result: PASS"
    echo "- School: $SCHOOL_NAME"
    echo "- Tenant code: $TENANT_CODE"
    echo "- Database: $DB_NAME"
    echo "- Plan: Starter"
    echo "- Tenant runtime: neon-v1.0.0-r42 / schema 0020 / compat 0048"
    echo "- Operational readiness: PASS"
    echo "- Worker database + R2 health: PASS"
    echo "- Public school resolution: PASS"
    echo "- Nipe stable identity/control snapshot unchanged: PASS"
    echo ""
    echo "The validation tenant is intentionally retained. No tenant database or school record was deleted."
  } >> "$GITHUB_STEP_SUMMARY"
fi
