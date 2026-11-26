#!/usr/bin/env bash
# Read-only, aggregate tenant backup metadata assessment.
# This does not start backups, restore databases, or list private object paths.
set -Eeuo pipefail
printf '%s\n' '## Edusentia tenant backup freshness (read-only)' >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
if [[ -z "${SOURCE_DATABASE_URL:-}" ]]; then
  echo "::warning::NEON_DATABASE_URL / DATABASE_URL secret unavailable; backup freshness cannot be assessed."
  printf '%s\n' '- Result: INCONCLUSIVE (no database connection secret)' >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
  exit 0
fi
if ! command -v psql >/dev/null; then
  echo "::warning::PostgreSQL client missing; backup freshness check skipped."
  exit 0
fi
MASTER_URL="$(node --input-type=module -e 'const u=new URL(process.env.SOURCE_DATABASE_URL);u.pathname="/edusentia";process.stdout.write(u.toString())')"
echo "::add-mask::$MASTER_URL"
if ! TENANTS="$(psql "$MASTER_URL" -X -qAt -v ON_ERROR_STOP=1 -c "select database_name from platform.tenant_control where database_state='isolated_ready' and database_name ~ '^[a-zA-Z0-9_-]+$' order by created_at limit 150" 2>/dev/null)"; then
  echo "::warning::Cannot read platform tenant control; backup freshness remains inconclusive."
  printf '%s\n' '- Result: INCONCLUSIVE (database authentication or permissions)' >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
  exit 0
fi
checked=0
missing=0
stale=0
healthy=0
while IFS= read -r DB_NAME; do
  [[ -n "$DB_NAME" ]] || continue
  checked=$((checked+1))
  TENANT_URL="$(MASTER_URL="$MASTER_URL" DB_NAME="$DB_NAME" node --input-type=module -e 'const u=new URL(process.env.MASTER_URL);u.pathname="/"+process.env.DB_NAME;process.stdout.write(u.toString())')"
  echo "::add-mask::$TENANT_URL"
  SQL="select coalesce((select extract(epoch from now()-max(completed_at))::bigint from public.backup_exports where backup_type='full' and status='completed' and verification_status='verified'),-1)::text;"
  if ! AGE="$(psql "$TENANT_URL" -X -qAt -v ON_ERROR_STOP=1 -c "$SQL" 2>/dev/null)"; then
    missing=$((missing+1))
    echo "::warning::Tenant #$checked backup metadata cannot be read."
    continue
  fi
  AGE="$(printf '%s' "$AGE" | tr -dc '0-9-')"
  if [[ ! "$AGE" =~ ^-?[0-9]+$ ]] || (( AGE < 0 )); then
    missing=$((missing+1))
    echo "::warning::Tenant #$checked has no verifiable completed full backup."
  elif (( AGE > 172800 )); then
    stale=$((stale+1))
    echo "::warning::Tenant #$checked last verified full backup is older than provisional 48-hour freshness target."
  else
    healthy=$((healthy+1))
  fi
done <<< "$TENANTS"
{
  echo "- Tenant databases evaluated: $checked"
  echo "- Full verified backup age <= 48 hours (provisional target): $healthy"
  echo "- Older than 48 hours: $stale"
  echo "- Missing/inaccessible verified backup: $missing"
  echo "- Off-site independent backup: NOT VERIFIED by this audit"
  echo "- Restore integrity drill: NOT VERIFIED by this audit"
  echo "- The 48-hour check is a provisional alert threshold, not a contracted recovery point objective."
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
if (( checked == 0 ));then
  echo "::warning::No isolated tenant databases could be enumerated."
fi
# This assessment intentionally warns without triggering a backup or blocking the website.
