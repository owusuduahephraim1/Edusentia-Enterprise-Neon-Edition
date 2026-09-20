# Certified UI parity checkpoint

The certified r42 UI source is stored as reference material under `reference/certified-ui/` so legacy vendor transport cannot enter the GitHub Pages artifact.

## Current runtime

The production `frontend/` shell already uses:
- `window.EDS_MASTER_CONFIG.apiBaseUrl`
- credentialed Cloudflare Worker requests
- Worker-managed tenant and platform authentication
- Worker-managed MFA
- explicit certified RPC calls
- Cloudflare R2 upload/download routes

## Active parity work

The next UI parity work is to port certified behavior from `reference/certified-ui/` into the production frontend without copying Supabase transport.

Priority sequence:
1. certified application shell and navigation
2. dashboard/bootstrap rendering
3. academic configuration and student workflows
4. teacher/headteacher/timetable workflows
5. report workflow and R2-backed PDF behavior
6. finance and remaining active modules

Each ported slice must use Worker APIs or allowlisted certified RPC operations, preserve tenant routing and AAL requirements, and remain covered by the no-Supabase runtime gate.

## Release rule

Reference files must never be moved back under `frontend/` until their vendor transport has been removed. No production promotion is permitted until the full current release gate passes.
