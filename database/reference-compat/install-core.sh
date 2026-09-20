#!/usr/bin/env bash
set -euo pipefail
: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL is required}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if psql "$TARGET_DATABASE_URL" -Atc "select 1 from app.schema_migrations where version='0027_reference_core_part_01' limit 1" | grep -qx 1; then
  test "$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_bootstrap_data'")" -ge 1
  echo "Certified reference core Part 01 is already installed."
  exit 0
fi

cat "$DIR/01_reference_base.part01.b64" "$DIR/01_reference_base.part02.b64" \
  | base64 --decode \
  | gzip --decompress > "$TMP"

EXPECTED_SHA="3d1a8793925c97c490cf819837a0c5effe2af62f76d76a5c59cd4b8df89eaf77"
ACTUAL_SHA="$(sha256sum "$TMP" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "Certified core payload checksum mismatch." >&2
  exit 1
fi

psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$DIR/0000_neon_compat_prelude.sql"
psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$TMP"

psql "$TARGET_DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
insert into app.schema_migrations(version)
values ('0027_reference_core_part_01')
on conflict do nothing;
update app.release_identity
   set schema_version='0027'
 where edition='Edusentia Enterprise Neon Edition';
SQL

test "$(psql "$TARGET_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")" = "0027"
test "$(psql "$TARGET_DATABASE_URL" -Atc "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_bootstrap_data'")" -ge 1

echo "Certified reference core Part 01 installed and verified."
