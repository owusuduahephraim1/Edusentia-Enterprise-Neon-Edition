# Certified UI parity checkpoint

The certified r42 UI source is stored as reference material under `reference/certified-ui/` so legacy vendor transport cannot enter the GitHub Pages artifact.

## Runtime boundary

The production `frontend/` shell uses:
- `window.EDS_MASTER_CONFIG.apiBaseUrl`
- credentialed Cloudflare Worker requests
- Worker-managed tenant and platform authentication
- Worker-managed MFA
- explicit certified RPC calls
- Cloudflare R2 upload/download routes

The full quality workflow is path-gated on `frontend/**`, so frontend-only changes run the same no-vendor-runtime, Pages, contract, and Worker checks as backend changes.

## Completed parity slices

- Certified authentication visual shell while retaining Neon tenant-code login, Turnstile, MFA, and recovery
- Certified signed-in sidebar, topbar, responsive navigation, profile context, and refresh state
- Worker-backed Dashboard bootstrap metrics
- Student directory, search, and protected student creation
- General staff directory
- Certified Academic configuration for System Administrator + AAL2:
  - academic calendar context
  - configuration readiness
  - academic years, classes, subjects, assignments, and assessment-scheme summaries
  - protected active-period selection
- Certified teacher directory and teacher record creation for System Administrator + AAL2
- Certified Principal appointment directory and record creation for System Administrator + AAL2
- Certified notification count, notification center, and mark-read behavior
- Legacy certified UI source isolated outside the production frontend tree

## Next UI parity work

Continue porting certified behavior from `reference/certified-ui/` without copying legacy transport.

Priority sequence:
1. teacher/Principal record editing, archive/restore, photographs, and Principal signature
2. class timetable console and timetable mutations
3. report editor, report workflow transitions, and R2-backed official PDF behavior
4. richer student lifecycle, import, promotion, and enrollment workflows
5. finance workflows beyond the current summary
6. remaining active certified modules and role-specific workspaces

Retired Inventory, Library, and Transport workspaces must remain retired.

## Current Neon environment note

The non-primary Neon branch `reference-parity-r42-20260920` is still at control-plane schema `0019` while the repository release manifest is `0025`.

The repository migrations `0020` through `0025` were located and reviewed. A no-compute rollback branch named `backup-reference-parity-r42-pre-0025-20260920` was created before any attempted persistent migration. No migration was applied, and the parity control-plane database remains unchanged at `0019`.

Applying `0020` through `0025` contains schema operations such as constraint/index replacement and therefore requires explicit approval before executing against the persistent parity database.

## Release rule

Reference files must never be moved back under `frontend/` until their vendor transport has been removed. No production promotion is permitted until the full current release gate passes.
