#!/usr/bin/env bash
set -euo pipefail
: "${BOOTSTRAP_DATABASE_URL:?BOOTSTRAP_DATABASE_URL is required}"

shopt -s nullglob
migrations=(database/migrations/*.sql)
if [ "${#migrations[@]}" -eq 0 ]; then
  echo "No master migrations were found." >&2
  exit 1
fi

printf 'Reconciling %s master migrations in lexical order.\n' "${#migrations[@]}"
for migration in "${migrations[@]}"; do
  version="$(basename "$migration" .sql)"
  installed="0"
  if [ "$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select to_regclass('app.schema_migrations') is not null")" = "t" ]; then
    installed="$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select count(*) from app.schema_migrations where version='$version'")"
  fi

  if [ "$installed" = "1" ]; then
    echo "==> $migration already installed; skipping"
    continue
  fi

  echo "==> applying $migration"
  psql "$BOOTSTRAP_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done

EXPECTED="$(basename "${migrations[-1]}" .sql | sed -E 's/^([0-9]+).*/\\1/')"
ACTUAL="$(psql "$BOOTSTRAP_DATABASE_URL" -Atc "select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1")"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "Master schema verification failed. Expected $EXPECTED, received $ACTUAL." >&2
  exit 1
fi

echo "Master Neon schema is current at $ACTUAL."
