#!/usr/bin/env bash
set -euo pipefail
: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL is required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIVE="$ROOT/database/live-foundation/2026-09-21"

bash "$LIVE/install-master-foundation.sh"

for migration in "$ROOT"/database/migrations/*.sql; do
  echo "==> $migration"
  psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done

psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/reference-compat/0048i_historical_provider_bridges.sql"

test "$(psql "$TARGET_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0025"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'")" = "102"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'")" = "369"

echo "Combined master clean-room install verified."
