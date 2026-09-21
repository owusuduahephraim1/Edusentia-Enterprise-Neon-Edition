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

The accelerated testing build now includes:

- Certified authentication visual shell while retaining Neon tenant-code login, Turnstile, MFA, recovery, and authenticated session handling
- Certified signed-in sidebar, topbar, responsive navigation, profile context, notification center, and refresh state
- Worker-backed Dashboard bootstrap metrics
- Certified Students workspace:
  - active/archive search and class/status filters
  - protected student creation and current enrollment
  - generated school identifiers
  - CSV validation and bulk student import
  - Term 3 promotion cutoff management
- General staff directory
- Certified Academic Configuration for System Administrator + AAL2:
  - academic calendar context
  - readiness state
  - years, classes, subjects, assignments, grading/assessment summaries
  - protected active-period selection
- Certified Teachers workspace:
  - create/edit
  - archive/restore
  - employment state
  - R2-backed photograph paths
- Certified Principal workspace:
  - create/edit
  - archive/restore
  - single-current-Principal database guard
  - R2-backed photograph paths
  - authenticated Principal signature workspace
- Certified Timetable workspace:
  - academic year/class console
  - create/edit timetable periods
  - certified subject-assignment and collision enforcement
- Certified Reports workspace:
  - report editor and assessment component entry
  - optimistic version handling
  - certified workflow transitions
  - safe draft deletion
  - official PDF download
  - guarded R2 PDF upload, SHA-256 registration, and cleanup on failed registration
- Certified Audit workspace:
  - current audit events
  - immutable audit archive batches and entries
- Security workspace for current-account MFA:
  - list factors
  - enroll and verify TOTP authenticators
  - remove authenticators
- Finance workspace:
  - outstanding/received/overdue summary
  - detailed invoice list
  - detailed payment/receipt list
- Consolidated Operations testing console for active Neon domains:
  - admissions
  - attendance
  - discipline
  - welfare
  - student health
  - hostel/boarding
  - payroll
  - communications
  - certificates/documents
  - imports/continuity
- Legacy certified UI source remains isolated outside the production frontend tree
- Retired Inventory, Library, and Transport workspaces remain retired

The accelerated implementation is split into Worker-backed frontend extensions under `frontend/parity-*.js`. No extension has direct database configuration or Supabase runtime access. The latest full Worker Quality Gate for the accelerated contract set is GitHub Actions run `35554602784`, which passed no-Supabase verification, GitHub Pages verification, Worker TypeScript checks, and repository tests.

## Next testing-readiness work

The major certified school workflows are now assembled. Remaining work should focus on testing depth rather than rebuilding the same screens:

1. create a dedicated browser-accessible parity deployment without replacing production `main`, the production Worker, or the production GitHub Pages site
2. seed realistic parity test data and execute end-to-end role journeys across System Administrator, Principal, teacher, and finance roles
3. expand write workflows for the consolidated Operations domains where the certified baseline has stable protected mutation contracts
4. run the full schema smoke, certified reference compatibility, synthetic school lifecycle, R2/report PDF, and browser E2E gates against the final parity build
5. resolve the canonical tenant-template ownership/provisioner handoff before testing new-school provisioning as a production-equivalent flow
6. promote only after the full release checklist is green

Retired Inventory, Library, and Transport workspaces must remain retired.

## Current Neon environment note

The non-primary Neon branch `reference-parity-r42-20260920` is now aligned with the repository release state:

- master/control-plane database `edusentia`: schema `0025`, 25 recorded master migrations
- certified tenant template `edusentia_tenant_template`: tenant runtime schema `0020`, certified compatibility schema `0045`, 37 recorded tenant/template migrations, locked against ordinary connections
- Reference Parity Test School database `edusentia_rpt_000001`: isolated tenant runtime `0020` with certified compatibility `0045`
- Reference Parity Test School control state: `isolated_ready`, runtime `neon-v1.0.0-r42-parity`, healthy, Professional capacity 0/1000
- release gate: ready=true with zero stale health, release drift, schema drift, unhealthy tenants, failed provisioning jobs, invalid active licences, capacity violations, or invalid indexes (re-verified after the accelerated build on 2026-09-21)

A no-compute rollback branch named `backup-reference-parity-r42-pre-0025-20260920` preserves the pre-migration parity state.

The parity-only workflow `.github/workflows/parity-template-install.yml` verifies the branch guard, validates and locks the certified tenant template, and idempotently provisions the Reference Parity Test School database without targeting production `main`.

## Deployment/testing note

The currently public GitHub Pages site and public Cloudflare Worker are still the existing production-oriented deployment. The accelerated `reference-parity-r42` build has not replaced them. A separate parity browser deployment must preserve the project rule that frontend hosting remains GitHub Pages plus Cloudflare Worker services; Cloudflare Pages is not part of this architecture.

## Release rule

Reference files must never be moved back under `frontend/` until their vendor transport has been removed. No production promotion is permitted until the full current release gate passes.
