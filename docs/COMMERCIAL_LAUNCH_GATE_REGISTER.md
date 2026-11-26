# Edusentia Enterprise: commercial launch gate register

**Status:** 26 November 2026. **Owner:** Edusentia operator (assignment pending). **Nature:** Internal release checklist; NOT a legal certification or warranty.

## Release decision

Public marketing website: **live**.
Private school platform: **live for configured tenant(s)**.
Third-party school onboarding and paid production commitments: **conditional**, pending the controls and agreements below.
Do not publish prices, guarantees, data protection certifications, or claimed recovery targets before evidence is verified and the owner approves them.

| ID | Gate | Evidence / baseline | Current decision | Completion criteria |
|---|---|---|---|---|
| WEB-01 | Apex and www HTTPS | Both hosted public pages were externally fetched with Edusentia branding | Passed (technical) | Continue read-only monitoring |
| WEB-02 | App and QR verifier | Existing live subdomains and earlier functional user confirmation | Operational, continue monitoring | Role-based acceptance tests and exceptions documented |
| WEB-03 | Mobile, accessibility and public links | Responsive website CI checks and public links | Partially validated | Manual mobile keyboard, screen-reader, and browser acceptance |
| MAIL-01 | Receiving mailbox | On 26 Nov 2026 MX records absent | Blocking | Select inbox provider/forward destination; configure and independently test two inbound messages |
| MAIL-02 | Sending authentication | SPF/DMARC absent; DKIM provider unspecified | Blocking | One correctly scoped SPF, valid DKIM selector(s), DMARC, test aligned sent and reply messages |
| BKP-01 | Production database snapshot | Neon manual snapshot: edusentia-pre-public-domain-launch-2026-11-26, ID snap-soft-tooth-b5rcofnx | Created | Retention and restoration viability checked separately |
| BKP-02 | Verified encrypted full tenant backup | Prior tenant backup UI last verified September 27, 2026; no live SQL access from connected Neon tool | Unverified | Fresh full export, signature/checksum verification and manifest covering database + protected R2 objects |
| BKP-03 | Independently protected off-site copy | Existing backup process does not alone prove independent off-site storage | Unverified | Off-site location, encryption/key custody, immutable/retention policy, integrity evidence |
| BKP-04 | Isolated restore drill | No successful documented drill in this audit | Blocking for enterprise recovery claim | Isolated Neon branch and private R2 test prefix, restore with controlled access, counts/hashes/integrity tests and signoff |
| SEC-01 | MFA / role least privilege | Code supports role and MFA protections | Feature present; not fully audited | Review actual admin accounts, MFA recovery, privilege changes and terminated-user access |
| SEC-02 | Domain control | Cloudflare DNS and HTTPS operating | Partially verified | Record registrar auto-renewal, account MFA, DNSSEC, domain/transfer lock and backup owner |
| SEC-03 | Incident communications | Public WhatsApp support available; dedicated mail not active | Limited | Assign primary/secondary on-call owners, severity routing, customer notice templates, escalation contacts |
| LEGAL-01 | Ghana DPC registration & processing roles | Registration status not inspected | Requires owner/legal confirmation | Verify applicable controller/processor registration with Ghana DPC, documented certificates and renewal |
| LEGAL-02 | School SaaS contract and DPA | Product terms in app are operational summaries, not reviewed commercial agreement | Blocking | Legal review and executed school subscription, processing terms and subprocessor notice |
| LEGAL-03 | Privacy, children's records, cross-border processing | Static marketing privacy notice is published | Partial | Review detailed app notice, international processing/storage, retention, access rights, breach response |
| FIN-01 | Plans, pricing and billing | Internal licensing functionality exists; no approved external price list | Pending | Approve GHS price schedule, billing period, taxes, refunds, trials, plan capacity and invoice workflow |
| OPS-01 | Customer onboarding and support | Product includes onboarding/authorization workflows | Requires pilot signoff | Pilot with data-import review, designated school admin, access audit, staff training, acceptance checklist |

## Regulatory due diligence (Ghana)

Edusentia operates with school, guardian, staff, and minor-student information. The operator and each school must determine whether they act as controller, processor or both for each processing activity, with a written allocation of responsibilities reviewed by Ghana-qualified counsel.

Official Ghana Data Protection Commission resources:
- https://dpc.gov.gh/for-organisations/
- https://dpc.gov.gh/compliance/
- https://app.dpc.gov.gh/
- Data Protection Act, 2012 (Act 843): https://ghalii.org/akn/gh/act/2012/843/eng%402012-05-18

Registration and obligations depend on actual operations and the law; no registration or legal compliance is asserted here. The DPC states registration obligations for relevant data controllers/processors. Before expanding school onboarding, verify organization status directly through the DPC rather than relying on marketing statements.

## Evidence register

Capture, with secrets redacted:
- Cloudflare custom domains: active status, certificate validity, registrar auto-renew settings, DNSSEC, and access ownership.
- GitHub Actions run for Production Readiness Health Check; warnings for mail readiness and aggregate backup metadata.
- Latest authenticated School Admin Backup & Restore screen: full verified timestamp, manifest verification, object counts and off-site copy record.
- Screenshot or audit record of disposable restore, not live school data or backup keys.
- DPC registration verification, approved subscription/DPA documents and school onboarding acceptance.

## Launch decision method

1. Every gate owner signs "Pass", "Exception with remediation and expiry", or "Blocked".
2. No one should mark mail, off-site restore, DPC registration, payment or support SLA as passed without evidence.
3. For unresolved critical issues, restrict onboarding to supervised demonstrations with no real student data; do not present pilot functionality as independently certified.
4. Review readiness weekly during the launch period and after a production incident.

## Source of truth and parity

The Supabase reference includes a full-school backup-and-restore workflow with encrypted continuity packages, verification states, and protected restore steps in reference/certified-ui/app.js. The Neon Edition implements corresponding functionality in worker/src/backup-service.ts, worker/src/restore-service.ts and its versioned SQL. **Code presence does not establish that the latest production backup is verified or recoverable.** Preserve the editions as separate implementations and test with isolated branches.

## Notes

- The provisional 48-hour freshness warning in the monitoring workflow is not a contractually agreed recovery point objective.
- Neon branch history retention currently reports 86,400 seconds. Snapshot retention and any time-to-restore promise must be verified with the actual plan.
- Public pages edusentia.com/privacy.html and edusentia.com/security.html are product/marketing statements and must not be treated as the complete school processing agreement.
