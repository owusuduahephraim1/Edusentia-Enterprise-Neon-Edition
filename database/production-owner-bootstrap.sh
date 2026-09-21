#!/usr/bin/env bash
set -euo pipefail
: "${OWNER_DATABASE_URL:?OWNER_DATABASE_URL is required}"

CURRENT_DB="$(psql "$OWNER_DATABASE_URL" -Atc "select current_database()")"
CURRENT_USER="$(psql "$OWNER_DATABASE_URL" -Atc "select current_user")"
test "$CURRENT_DB" = "edusentia" || { echo "Owner bootstrap must target edusentia." >&2; exit 1; }
test "$CURRENT_USER" = "edusentia_owner" || { echo "Owner bootstrap requires edusentia_owner, received $CURRENT_USER." >&2; exit 1; }

BOOTSTRAP_DATABASE_URL="$OWNER_DATABASE_URL" bash database/install-master.sh
psql "$OWNER_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/runtime-role.sql
psql "$OWNER_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/provisioner-role.sql
psql "$OWNER_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/service-login-roles.sql
psql "$OWNER_DATABASE_URL" -v ON_ERROR_STOP=1 -f database/migration-login-role.sql

test "$(psql "$OWNER_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0025"
test "$(psql "$OWNER_DATABASE_URL" -Atc "select version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "neon-v1.0.0-r42"
test "$(psql "$OWNER_DATABASE_URL" -Atc "select count(*)=3 from pg_roles where rolname in('edusentia_worker_login','edusentia_provisioner_login','edusentia_migrator_login') and rolcanlogin and not rolsuper and not rolcreaterole and not rolbypassrls")" = "t"
test "$(psql "$OWNER_DATABASE_URL" -Atc "select count(*)=2 from pg_auth_members m join pg_roles granted on granted.oid=m.roleid join pg_roles member_role on member_role.oid=m.member where member_role.rolname='edusentia_runtime' and granted.rolname in('edusentia_worker_login','edusentia_provisioner_login') and m.admin_option and not m.inherit_option and not m.set_option")" = "t"
test "$(psql "$OWNER_DATABASE_URL" -Atc "select count(*)=2 from pg_auth_members m join pg_roles granted on granted.oid=m.roleid join pg_roles member_role on member_role.oid=m.member where member_role.rolname in('edusentia_worker_login','edusentia_provisioner_login') and granted.rolname in('edusentia_worker_runtime','edusentia_provisioner') and not m.admin_option and m.inherit_option and m.set_option")" = "t"

echo "Production owner bootstrap completed at control schema 0025."
