#!/usr/bin/env bash
set -euo pipefail
: "${TARGET_DATABASE_URL:?TARGET_DATABASE_URL is required}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

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

echo "Certified reference core Part 01 installed."
