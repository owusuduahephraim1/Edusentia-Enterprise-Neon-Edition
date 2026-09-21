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

## Live parity browser testing environment

The accelerated `reference-parity-r42` build now has a separate browser-accessible parity environment:

- test URL: `https://edusentia-enterprise-neon-parity-test.edusentia-enterprise-neon.workers.dev/`
- API health: `ok=true`, database healthy, storage healthy
- product version: `neon-v1.0.0-r42-parity-test`
- frontend environment: `parity-testing`
- database target: non-primary Neon branch `reference-parity-r42-20260920`
- master/control database: `edusentia`, schema `0025`
- Reference Parity Test School database: `edusentia_rpt_000001`, runtime `0020`, certified compatibility `0045`
- storage: isolated Cloudflare R2 bucket `edusentia-enterprise-neon-parity-test`
- Turnstile: Cloudflare test site key only in the parity harness; production Turnstile validation remains strict
- successful deployment run: GitHub Actions `35556241733`
- successful full backend smokes on the parity branch:
  - Neon Schema Smoke Test `35554699044`
  - Reference Tenant Compatibility Smoke `35554701202`
  - Synthetic School Lifecycle Smoke `35554703328`
- certified authentication hero asset is vendored directly under `frontend/assets/edusentia-auth-learning.webp`; its Git blob is byte-identical to certified source commit `a181e18e0ca044db756193209b5b089cd03efb0f`

The parity deployment rotates only the non-primary branch `edusentia_worker_runtime` login credential during deployment, masks it immediately, installs it directly into the parity Worker secret store, and does not persist it in GitHub. The workflow verifies the parity hostname, master schema `0025`, release gate, runtime role, and database identity before deployment.

Production remains isolated and unchanged:

- primary Neon branch `main`: schema `0019`, 19 master migrations
- production Worker: healthy on `neon-v1.0.0`
- production GitHub Pages site and production Worker are not replaced by the parity harness
- Cloudflare Pages is not used

## Release rule

Reference files must never be moved back under `frontend/` until their vendor transport has been removed. No production promotion is permitted until the full current release gate passes.
