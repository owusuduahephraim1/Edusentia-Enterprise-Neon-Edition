# Architecture inventory

## Sources inspected

1. Supplied immutable r42-v17 ZIP blueprint.
2. Current stable private source repository, whose r42-v18 certified application commit is `a181e18e0ca044db756193209b5b089cd03efb0f`.
3. Live stable Supabase master control plane and Nipe tenant project, read as behavioral/schema references only.
4. Fresh-build contract supplied with this task.

## r42-v18 delta over supplied ZIP

The current stable source is 28 commits ahead of the r42-v17 certified source. The important product invariants include:

- Accounts Office Staff is archive/deactivate-only. Hard deletion is prohibited.
- Teacher profile subject assignments are compacted/deduplicated without losing class assignment data.
- R2 backup-download resilience is updated.
- The authoritative stable identity is r42-v18 while internal master and tenant release identities remain independent.

## Functional domains discovered

Platform/tenancy; authentication and MFA; school settings; users/access; students and guardians; staff and HR; academics, classes, subjects and timetables; attendance; assessment; report workflows, transcripts and certificates; admissions; finance, fees, receipts and payroll; student services; notifications; privacy/compliance; audit/security; backups/recovery; ID cards; R2 file storage; licensing/release governance; PWA/offline continuity.

## Runtime replacement boundaries

- Browser-to-Supabase database calls become explicit Worker API operations.
- Supabase Auth becomes native Edusentia authentication persisted in Neon and represented by opaque HttpOnly sessions.
- Supabase RLS guarantees become Worker authorization plus Neon RLS using server-established request context.
- Supabase Edge Functions become Worker routes/services, scheduled Workers, database functions or R2 operations according to responsibility.
- Supabase Storage is not used. All application objects are Cloudflare R2 objects with Neon metadata.
- Supabase Realtime is replaced only where a concrete feature requires it; polling/SSE is preferred over unnecessary socket complexity.
