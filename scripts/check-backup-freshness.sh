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
unavailable=0
no_completed=0
unverified=0
stale=0
healthy=0
offsite_metadata=0
while IFS= read -r DB_NAME; do
  [[ -n "$DB_NAME" ]] || continue
  checked=$((checked+1))
  TENANT_URL="$(MASTER_URL="$MASTER_URL" DB_NAME="$DB_NAME" node --input-type=module -e 'const u=new URL(process.env.MASTER_URL);u.pathname="/"+process.env.DB_NAME;process.stdout.write(u.toString())')"
  echo "::add-mask::$TENANT_URL"
  # Backup Worker sets verification_status='passed' after manifest and R2 checks.
  # A completed export may still have verification_status='not_tested' or 'failed'.
  SQL="select
    coalesce(extract(epoch from now()-max(completed_at) filter (where status='completed' and verification_status='passed'))::bigint,-1),
    count(*) filter (where status='completed'),
    count(*) filter (where status='completed' and verification_status='passed'),
    count(*) filter (where status='completed' and verification_status='failed'),
    count(*) filter (where status='completed' and offsite_copied_at is not null)
    from public.backup_exports where backup_type='full';"
  if ! DATA="$(psql "$TENANT_URL" -X -qAt -F '|' -v ON_ERROR_STOP=1 -c "$SQL" 2>/dev/null)"; then
    unavailable=$((unavailable+1))
    echo "::warning::Tenant #$checked backup metadata cannot be read; status inconclusive."
    continue
  fi
  IFS='|' read -r AGE COMPLETED PASSED FAILED OFFSITE <<< "$DATA"
  if [[ ! "$AGE" =~ ^-?[0-9]+$ ]] || [[ ! "$COMPLETED" =~ ^[0-9]+$ ]]; then
    unavailable=$((unavailable+1))
    echo "::warning::Tenant #$checked returned unexpected backup summary."
    continue
  fi
  if (( OFFSITE > 0 ));then
    offsite_metadata=$((offsite_metadata+1))
  fi
  if (( COMPLETED == 0 )); then
    no_completed=$((no_completed+1))
    echo "::warning::Tenant #$checked has no completed full backup."
  elif (( AGE < 0 )); then
    unverified=$((unverified+1))
    echo "::warning::Tenant #$checked has completed full backups, but none with successful ('passed') verification."
  elif (( AGE > 172800 )); then
    stale=$((stale+1))
    echo "::warning::Tenant #$checked last successfully verified full backup is older than provisional 48-hour freshness target."
  else
    healthy=$((healthy+1))
  fi
done <<< "$TENANTS"
{
  echo "- Tenant databases evaluated: $checked"
  echo "- Latest verified full backup age <= 48 hours (provisional target): $healthy"
  echo "- Successfully verified backup older than 48 hours: $stale"
  echo "- Completed backups without any successful verification: $unverified"
  echo "- No completed full backup: $no_completed"
  echo "- Inaccessible or inconclusive: $unavailable"
  echo "- Tenants with some off-site copied-at metadata: $offsite_metadata"
  echo "- Independent off-site storage: NOT PROVEN by the copied-at metadata"
  echo "- Restore integrity drill: NOT VERIFIED by this audit"
  echo "- The 48-hour check is a provisional alert threshold, not a contracted recovery point objective."
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
if (( checked == 0 ));then
  echo "::warning::No isolated tenant databases could be enumerated."
fi
# This assessment intentionally warns without triggering a backup or blocking the website.
