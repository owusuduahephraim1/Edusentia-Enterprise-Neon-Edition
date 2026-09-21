# Supabase Edge Function to Cloudflare Worker migration matrix

Live inventory was read from the certified Supabase SaaS master and tenant on 2026-09-21. This document tracks behavior, not merely function names.

| Source scope | Supabase function | Neon/Cloudflare replacement | Status |
|---|---|---|---|
| master | admin-user-management | certified RPC layer + Neon identity administration | partial, identity write endpoints remain |
| master | notification-dispatcher | Worker notification dispatcher using Resend | port required |
| master | scheduled-backup | Worker R2 backup/restore service | port required |
| master | license-authority | platform plan authorization SQL + platform routes | covered |
| master | license-verifier | tenant licence activation/status routes | covered |
| master | license-upgrade-manager | platform authorization + tenant activation flow | covered |
| master | platform-package-manager | Worker package/signing service + R2 | port required |
| master | platform-package-gateway | Worker guarded package download | port required |
| master | platform-storage-maintenance | Worker R2 maintenance task | port required |
| master | tenant-registration | `/api/public/school-registration` | covered |
| master | tenant-resolver | public school resolver + login routing | covered |
| master | tenant-admin | platform administration routes | covered |
| master | tenant-provisioner | `worker/src/provisioning.ts` | covered |
| master | saas-plan-upgrade-authority | platform plan authorizations | covered |
| master | saas-licensing-admin | platform licence administration routes | covered |
| master | tenant-policy-reconciler | deterministic Neon migrations/runtime roles | superseded by native design |
| master | auth-security-reconciler | authn/MFA/runtime-role migrations | superseded; live source is a stub |
| master | tenant-health-monitor | tenant health/release checks in platform routes | covered |
| master | platform-health-admin | platform overview and release gate | covered |
| master | tenant-access-recovery | `/api/public/access-recovery` | covered |
| master | tenant-access-admin | platform recovery resolve/deny routes | covered |
| master | tenant-release-registry-ingest | static release identity/migration registry | superseded; live source is a stub |
| master | tenant-release-function-capture | static 172-operation certified registry | superseded; live source is a stub |
| tenant | admin-user-management | certified RPC layer + Neon identity administration | partial, identity write endpoints remain |
| tenant | notification-dispatcher | Worker notification dispatcher using Resend | port required |
| tenant | scheduled-backup | Worker R2 backup/restore service | port required |
| tenant | license-verifier | tenant licence activation/status routes | covered |
| tenant | saas-plan-upgrade | plan authorization activation route | covered |
| tenant | tenant-auth-recovery | platform recovery flow + Neon authn reset | partial |
| tenant | r2-backup-migrator | no migration shim required once R2 is authoritative | superseded; live source is a stub |
| tenant | directory-user-management | certified directory RPCs + Neon identity administration | partial, identity write endpoints remain |
| tenant | backup-download-gateway | guarded R2 backup download route | port required |

The remaining implementation concentration is therefore notification delivery, backup/restore, package signing/download, storage maintenance, and explicit Neon identity administration.
