# Edusentia Enterprise: Public domain, email and recovery launch

Operational status: 2026-11-26. This is a readiness and configuration record, not a statement that all controls have passed.

## Domain separation

| Hostname | Purpose | Hosting |
|---|---|---|
| edusentia.com | Public product website (live HTTPS confirmed 26 Nov 2026) | Independent Cloudflare Pages project: edusentia-main |
| www.edusentia.com | Redirect to main public site | Same Pages project |
| app.edusentia.com | Authenticated school operations | Existing edusentia-app Cloudflare Pages |
| verify.edusentia.com | Live school-document verification | Existing edusentia-verify Cloudflare Pages |
| api.edusentia.com | Worker API | Existing worker, unchanged |

Public website files are in public-site/. The deploy workflow at .github/workflows/deploy-public-site.yml stages two already-approved brand assets from frontend/assets/, validates static site files, then creates or reuses a separate Cloudflare Pages project. The workflow attempts to attach apex and www. Domain registration and TLS may remain pending after API acceptance.

Acceptance: both apex and www served the Edusentia homepage over HTTPS on 26 Nov 2026. A canonical redirect from www to apex is not yet independently demonstrated; check it separately. Continue mobile accessibility, asset, sitemap, robots and security-header checks. Check app.edusentia.com and verify.edusentia.com remain intact. The static site does not include a form, marketing cookies, third-party trackers, or student record APIs.

## Domain email: recipient choice still needed

Repeated domain audit on 26 Nov 2026 found no MX records, no root SPF TXT record, and no DMARC TXT record. Do not publish untested mailto links as active contact addresses.

Option A: Cloudflare Email Routing for incoming messages (forwarding only).

1. In Cloudflare Email Routing, add and verify an Edusentia-authorized destination inbox.
2. Enable Email Routing and create explicit aliases: info@edusentia.com, support@edusentia.com and optionally sales@edusentia.com.
3. Verify Cloudflare-managed MX records and send inbound test messages.
4. Cloudflare Email Routing does not automatically provide a sending mailbox. Configure a supported mail host or authenticated outbound service separately.

Option B: Choose Microsoft 365, Google Workspace, Zoho Mail or another approved business mailbox provider. Use that provider's exact MX, SPF and DKIM records, not generic guesses. Avoid mixed MX records.

After choosing the sending provider, publish one SPF policy with only permitted senders, enable provider-specific DKIM and begin DMARC in monitoring mode before progressively moving to quarantine or reject. Test send, receive, replies and spam filtering. Enable mailbox MFA and recovery ownership. Update the public website contact address only after these tests.

Required owner input: verified forwarding destination or mailbox provider. No private email address has been guessed or silently chosen.

## Backup, Neon and storage recovery

A manual production Neon snapshot was created on 2026-11-26:
- Name: edusentia-pre-public-domain-launch-2026-11-26
- Snapshot ID: snap-soft-tooth-b5rcofnx
- Source: main branch

A Neon snapshot is not an independent off-site encrypted backup and does not include all Cloudflare R2 objects. The Neon project exposed history retention of 86,400 seconds (24 hours) during inspection. Verify billing-plan recovery settings.

The existing backup-diagnostic workflow documents tenant backups, encryption, R2 objects, manifest checks and recovery staging. Full production backup recency was not independently confirmed. A school dashboard screenshot showed a last verified backup dated 2026-09-27, which does not establish a current backup on 2026-11-26.

Recovery acceptance requires:
1. Recent verified encrypted database backup and R2 object export, independently copied to permitted off-site storage.
2. Integrity checking of manifest signatures and backup checksums.
3. A non-destructive restore into a disposable Neon branch and private R2 prefix.
4. Verification of restored table consistency, representative objects and authorization controls.
5. Documented recovery-time and recovery-point objectives, alerting, retention and authorized recovery contacts.

Do not run restore against a live school database. Audit logs should never reveal student records, credentials or private object URLs.

## Remaining production launch gates

| Gate | State |
|---|---|
| App and public verification domains | Previously tested operational |
| Edusentia main website and www DNS/TLS | Both hostnames were reachable over HTTPS on 26 Nov 2026 |
| Manual Neon recovery snapshot | Created |
| Tenant database plus R2 off-site restore drill | Not completed |
| Business mail aliases, MX, SPF, DKIM, DMARC | Await verified destination and provider |
| Registrar renewal, transfer lock, DNSSEC | Requires authorized registrar review |
| SaaS privacy, school data-processing agreements and commercial terms | Requires owner/legal approval |

The website's privacy page covers only the public static site. School data-processing terms must be reviewed separately before broad commercial onboarding.

## Current operational work

The read-only production health workflow is .github/workflows/production-readiness-health.yml. Launch signoffs and evidence are in docs/COMMERCIAL_LAUNCH_GATE_REGISTER.md, and school onboarding, privacy/legal review and incident response guidance are in docs/SCHOOL_ONBOARDING_AND_SUPPORT_PLAYBOOK.md. This monitor reports mail and backup warnings but does not create mailboxes, perform off-site backups, or restore databases.
