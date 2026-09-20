#!/usr/bin/env bash
set -euo pipefail
: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

shopt -s nullglob
migrations=(database/migrations/*.sql)
if [ "${#migrations[@]}" -eq 0 ]; then
  echo "No master migrations were found." >&2
  exit 1
fi

printf 'Applying %s master migrations in lexical order.\n' "${#migrations[@]}"
for migration in "${migrations[@]}"; do
  echo "==> $migration"
  psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done

EXPECTED="$(basename "${migrations[-1]}" .sql | cut -d_ -f1)"
ACTUAL="$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "Master schema verification failed. Expected $EXPECTED, received $ACTUAL." >&2
  exit 1
fi

echo "Master Neon schema is current at $ACTUAL."
