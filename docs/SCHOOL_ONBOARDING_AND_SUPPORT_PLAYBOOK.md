# Edusentia Enterprise: School onboarding and support operations

**Internal operating procedure, draft for owner approval.**
Do not publish as a signed service agreement. No response times, prices or uninterrupted-availability promises are contractually approved.

## Before accepting a paid school tenant

1. **Customer verification:** confirm legal institution name, campus address, authorised signatory, school administrator and emergency contact. Do not accept parent/student data until agreement and privacy review are approved.
2. **Scope:** select Basic/JHS or SHS configuration, modules, staff roles, enrolment capacity, fee/plan period and excluded features. Quote commercial terms explicitly before collecting payment.
3. **Processing arrangement:** record controller/processor responsibilities, lawful data-sharing basis, child/student safeguards, retention and access rights, approved subprocessor/cloud locations and international transfers, in an executed agreement reviewed by counsel.
4. **Security:** require System Administrator MFA, school-approved user-role map, recovery code custody, restricted import privileges and a documented process for staff departures.
5. **Provisioning:** create the tenant using the existing authorised Edusentia workflow, not direct SQL or cloning a live tenant. Verify school identity and logo, timezone Africa/Accra if applicable, academic year, terms, classes, subjects, teachers and school settings.
6. **Migration:** use a minimal, validated import with a test subset. Obtain written approval for source files and data accuracy. Never email spreadsheets containing student information to an unverified inbox.
7. **Training:** provide separate school administrator, Principal, classroom teacher and accounts office training, with role-specific tasks and safe document-issuance procedures.
8. **Acceptance tests:** school owner checks login/MFA, student creation, assessments, markbook, report approvals, certificates, transcript workflows, licence/renewal, public verification, backup, and account recovery for their contracted features.
9. **Backup before go-live:** record a verified full school backup, object manifest, checksums, signing keys stewardship and a successful separate restore drill or a documented approved exception.
10. **Signoff:** obtain school authorisation confirming UAT evidence, privacy policy communication, training and named support contacts. Record go-live date and unresolved risks.

## Proposed service support structure

Channels already advertised in the app:
- Protected in-product workflows for password resets, administration and tenant operations.
- Public platform WhatsApp: https://wa.me/233240240898 (not a channel for passwords, recovery codes or raw student data).
- Existing publicly listed general support email in the app can continue until the dedicated domain email is actually configured.
- Proposed addresses info@edusentia.com and support@edusentia.com must **not** be advertised as active until receiving and sending tests pass.

Classify and route incidents without promising unapproved SLAs:

| Severity | Example | Immediate internal action | Release communication |
|---|---|---|---|
| P1 Critical | Multi-tenant data exposure, verified compromise, complete school platform outage | Contain, page authorized response team, freeze unsafe operations, preserve audit evidence | Notify affected schools via verified contacts after assessment and counsel guidance |
| P2 High | School unable to submit/report marks or issue documents during critical period | Escalate to technical owner, isolate affected module, provide safe workaround if available | Give school a factual impact/update statement |
| P3 Normal | One user's recoverable error, non-critical feature regression | Reproduce, assess business impact, file tracked defect | Acknowledge with reference number |
| P4 Improvement | Cosmetic issue, enhancement or training question | Prioritise in backlog | Provide documentation or training |

**Proposed internal targets (not customer commitments):** detect and acknowledge P1 urgently; start P1 investigation immediately upon confirmation. Define actual response windows and coverage hours only after staffing, monitoring and service contract approval.

### Support intake minimum

Ticket ID, school tenant code, reporter role, impacted workflow, time in UTC, error/request ID, scope, business impact, reproduction steps, consent for accessing records (if needed), owner and resolution status. Mask tokens and personal details. Never require users to share MFA secrets.

### Incident response

- Detect: monitoring, support tickets, audit and Worker logs.
- Triage: identify affected tenants, confidentiality/integrity/availability impact and severity.
- Contain: revoke compromised sessions/credentials or disable affected feature through protected administration, with approval and logs.
- Investigate: preserve timestamped logs and exact repository commit/Neon migration IDs; compare against the certified Supabase reference before altering Neon logic.
- Recover: validate rollback or replacement in staging before deploying. Document customer-facing impact.
- Notify: perform regulator, data-subject and customer notification assessment under applicable law and signed agreements; legal owner determines content and timing.
- Review: root cause, corrective action, prevention test and follow-up owner.

## Backup and restore dry-run (must use isolated resources)

1. Verify a recent **completed + verified** tenant full backup, manifest, encryption and signature metadata. Confirm which R2 objects are included.
2. Confirm a separately controlled off-site copy with documented custody, object retention and tamper detection.
3. Create a disposable isolated Neon recovery branch and private R2 test prefix with access restrictions; do not attach production public hostnames.
4. Restore a **copy** of the backup there, not into a live tenant. Validate tables, referential integrity, student/report counts, a few object hashes, audit/event history and role restrictions without publishing private data.
5. Record duration, available recovery point and discrepancies. Do not claim any RPO/RTO until observed and approved.
6. Delete temporary recovery resources only after recovery owner authorises disposal and retention requirements are checked.

## Acceptance sign-off

| Role | Name | Date | Result | Evidence reference |
|---|---|---|---|---|
| Product / owner | To assign | | Pending | |
| School authorised signatory | To assign | | Pending | |
| IT and security | To assign | | Pending | |
| Privacy/legal reviewer | To assign | | Pending | |
| Support owner | To assign | | Pending | |

## Business email activation checklist

- Choose either Cloudflare Email Routing to a verified receiving mailbox, or a full outbound-capable mailbox provider.
- Do not enable routing until the intended destination inbox owner explicitly confirms it.
- Add the provider-specified MX and authentication records; verify SPF uniqueness, DKIM alignment and initial DMARC policy.
- Send inbound test messages from two independent origins, confirm replies from the selected business address, and check spam folders.
- Turn on mailbox MFA, recovery identity controls and admin audit logs.
- Only then update the website footer and protected support page with the active domain aliases.

Official reference: https://developers.cloudflare.com/email-service/get-started/route-emails/

## Customer legal package (draft structure, not executed terms)

**School subscription order:** legal names, module scope, plan capacity, permitted users, renewal term, invoice/tax handling, payment and late-payment policy, suspension/continuity, school support channels, termination and data export.

**Data processing addendum:** nature and purpose of processing, categories of students/guardians/staff, controller/processor allocation, documented instructions, confidentiality and access, technical and organizational safeguards, subprocessors, international transfer safeguards, data-subject requests, incident assistance, audit evidence, return/deletion on exit, retention, and breach notification coordination. Confirm actual locations/providers and legal basis before signing.

**Service schedule:** support hours, severity definitions, acknowledgment targets, maintenance windows, uptime measurement/exclusions, disaster recovery targets supported by tested evidence, change notification, escalation owner.

**Privacy notice:** detailed authenticated-app data inventory and processing details, school contact and platform contact, student/guardian rights, retention, disclosure and international transfers. The public website notice is not a substitute.

Obtain review by qualified Ghana counsel and confirm the applicable Ghana Data Protection Commission registration status before live onboarding of additional schools.
