#!/usr/bin/env bash
set -euo pipefail
: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL is required}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')")" != "0" ]; then
  echo "Refusing clean-room tenant install: public schema is not empty." >&2
  exit 1
fi
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$DIR/00_neon_provider_compat.sql"
for f in "$DIR"/tenant/[0-9][0-9]_*.sql; do
  echo "==> $f"
  psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
done
echo "Tenant live foundation installed."
