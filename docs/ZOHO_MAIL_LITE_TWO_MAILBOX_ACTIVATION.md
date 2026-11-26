# Edusentia Enterprise: Zoho Mail Lite production activation runbook

**Prepared:** 26 November 2026
**Status:** READY FOR ACCOUNT SETUP; NO MAILBOXES OR MAIL DNS RECORDS HAVE BEEN CREATED.
**Organization:** Edusentia Enterprise (confirm registered legal billing entity and authorized administrator)
**Domain:** edusentia.com
**DNS authority:** Cloudflare
**Proposed provider:** Zoho Mail, Mail Lite, 5 GB per user
**Accounts required:** 2 paid user mailboxes

## Provider choice and cost

Zoho Mail Lite supports hosted custom-domain email with separate sending and receiving mailboxes, an administrator console, custom domains, SPF/DKIM/DMARC configuration and two-factor authentication. For an initial two-account operation, it avoids paying for a full office productivity suite. The public US pricing page cited a US$1 per user per month equivalent for the 5 GB tier, billed annually. That is a **planning estimate** of US$24 per year for two seats, excluding country-specific checkout pricing, taxes, exchange rates and renewals. Accept only the price and billing term confirmed in the owner's actual Zoho checkout.

Alternatives: Google Workspace Business Starter provides a larger collaboration/storage bundle at materially higher per-user cost; Microsoft 365 Business Basic is appropriate when the team will use Microsoft 365 mail, Teams and Office web apps. Do not purchase either unless collaboration requirements justify the higher cost.

Provider pricing: https://www.zoho.com/mail/zohomail-pricing.html
Zoho Mail Cloudflare instructions: https://www.zoho.com/mail/help/adminconsole/cloudflare.html

## Account design

| Address | Account type | Display name | Purpose | Initial owner |
|---|---|---|---|---|
| info@edusentia.com | Paid user mailbox 1 | Edusentia Business Enquiries | Sales, demonstrations, onboarding, quotations | Assign authorized staff |
| support@edusentia.com | Paid user mailbox 2 | Edusentia Technical Support | Customer support, school admin support, incident routing | Assign authorized staff |

- Create **two real user mailboxes**, not aliases pointing to one personal inbox.
- Choose an authorized company owner as the Zoho organization Super Administrator and configure recovery and MFA. Zoho's setup may require the first administrator to hold a mailbox seat; check the actual plan before assuming a free extra administrator account.
- Use unique passwords and TOTP/passkey/security methods supported by the provider. Never share credentials, recovery codes, domain-verification tokens, private school records or mail backup keys in GitHub.
- Assign per-user access. Do not share one password for both mailboxes. Enable admin alerting and inspect suspicious login logs.
- Optional later: create dmarc@edusentia.com as a **verified alias** of a controlled business mailbox for DMARC aggregate reports. This is not a requested third paid mailbox and must not be advertised as a service address.

## Existing Cloudflare records to preserve

The previously observed domain zone has:
- edusentia.com CNAME edusentia-main.pages.dev (proxied; apex flattening)
- www.edusentia.com CNAME edusentia-main.pages.dev (proxied)
- app.edusentia.com CNAME edusentia-app.pages.dev (proxied)
- verify.edusentia.com CNAME edusentia-verify.pages.dev (proxied)
- api.edusentia.com Worker edusentia-enterprise-neon-api

**Do not remove or edit any of these website, authentication, verification or API records.**

On 26 Nov 2026, a public DNS audit found no root MX, no root SPF TXT and no _dmarc TXT. Recheck the live zone before any change. Cloudflare's root-domain CNAME flattening permits the existing apex website to remain while separate MX/TXT email records are added.

## Setup stages, in exact order

### Stage A: Create and verify Zoho organization (requires the owner)

1. Open https://www.zoho.com/mail/zohomail-pricing.html and choose **Mail Lite 5 GB** with the confirmed two-user subscription, subject to actual Ghana checkout terms. Purchase/authorization remains the owner's decision.
2. Sign up under the approved organization identity and choose the appropriate Zoho account region/data center. Record the selected region in internal compliance inventory because school email may contain personal information.
3. In https://mailadmin.zoho.com/ open Domains > Add Domain and enter **edusentia.com** (do not buy or transfer the existing domain).
4. Zoho provides a unique DNS verification TXT record or CNAME. Enter only the exact host and value from that Zoho admin screen in Cloudflare DNS. CNAME verification records must be **DNS only** (grey cloud). TXT records are DNS records, not proxied.
5. Click Verify in Zoho and retain a screenshot showing domain verified with secret values concealed.

### Stage B: Provision the two independent mailboxes

6. Add info@edusentia.com, then support@edusentia.com, as separate paid user mailboxes in Zoho's Users section.
7. Set unique recovery ownership, MFA and role controls for each mailbox. Add a recovery method and test it without exposing recovery codes.
8. Confirm that the addresses are both listed and active in the Zoho admin console **before** changing MX. Do not use an unverified personal email as a forwarding destination.
9. Review whether Zoho's default policies restrict external sending or receiving; configure only what is needed for authorized school business.

### Stage C: DNS records in Cloudflare, based on YOUR Zoho Admin Console

The table below is a **configuration blueprint**, not a final DNS change request. Zoho states that MX and SPF hosts can differ by data center. Therefore DO NOT publish generic US Zoho records without matching the chosen account's domain setup page.

| Order | DNS type | Cloudflare name | Value/source | Proxy / notes |
|---|---|---|---|---|
| 1 | TXT or CNAME | Exact Zoho verification host | Exact Zoho-generated verification value | Verification CNAME: DNS only |
| 2 | MX | @ | First exact Zoho MX server | Priority supplied by Zoho; not proxied |
| 3 | MX | @ | Second exact Zoho MX server | Priority supplied by Zoho; not proxied |
| 4 | MX | @ | Third MX if Zoho provides one | Priority supplied by Zoho; not proxied |
| 5 | TXT | @ | One SPF record generated/recommended by Zoho for the region and all authorized senders | Exactly one v=spf1 root TXT |
| 6 | TXT (or specified record) | Zoho selector._domainkey, exactly as generated | DKIM public key or designated DNS target | Prefer 2048-bit signing if supported; DNS only |
| 7 | TXT | _dmarc | Monitor-only policy after confirming outbound senders | Start p=none; enable reviewed reports before moving toward quarantine/reject |

- Zoho's *generic* US MX example is mx.zoho.com (priority 10), mx2.zoho.com (20), mx3.zoho.com (50). These are **illustrative only**; obtain account-region values under Tools & Configurations.
- Zoho documentation has different illustrative SPF includes across help articles (e.g. include:zoho.com vs include:zohomail.com). Treat the live **Admin Console DNS Mapping** page as authoritative, inventory all other legitimate Edusentia senders, then publish exactly **one** consolidated SPF record.
- If Edusentia uses transactional emails from another vendor later, authenticate that sender separately, ideally on a distinct sending subdomain, rather than silently allowing spoofing or adding multiple root SPF records.
- Generate a Zoho DKIM selector within Domains > Email Configuration > DKIM and publish its **exact host/key**; verify and enable signing in Zoho.
- Initial DMARC example (no reports): TXT, name _dmarc, value "v=DMARC1; p=none; adkim=r; aspf=r; pct=100". Prefer adding "rua=mailto:dmarc@edusentia.com" **only after** that alias has been created, authorized and shown to receive reports. Do not use a nonexistent reports inbox.
- Begin DMARC with p=none while testing legitimate sending sources, then progress to quarantine/reject based on aligned SPF/DKIM and review of real delivery data. Never claim p=none stops all spoofing.
- In Cloudflare, do not create duplicate MX from Cloudflare Email Routing. Choose Zoho **alone** for inbound MX. Do not add any new A record for webmail unless specifically configured by Zoho.
- TTL Auto is acceptable; allow DNS propagation and validate in Zoho.

### Stage D: End-to-end acceptance (do not skip)

1. In Zoho Admin Console, domain verification, MX, SPF and DKIM must show healthy/verified.
2. Send a message **from an external Gmail account to info@edusentia.com**; confirm exact arrival timestamp, subject and correct recipient.
3. Send a message **from an external Outlook/Hotmail account to support@edusentia.com**; verify receipt.
4. From info@edusentia.com, reply to Gmail and send a fresh message to an unrelated external recipient.
5. From support@edusentia.com, reply to Outlook and send a fresh message.
6. On received outbound messages, inspect message headers: SPF or DKIM **alignment** should pass DMARC; check that DKIM signing domain matches the business domain and no unwanted spoofing appears.
7. Check sent, spam, bounce, blocked and quarantine folders. Test attachments, mobile client login and MFA recovery.
8. Re-run GitHub Actions > Production Readiness Health Check; MX, SPF, DMARC should appear configured in DNS. **The monitoring checks alone do not prove DKIM, alignment, actual delivery or mailbox ownership.**
9. Only after successful tests update the website footer, privacy/support contact pages, Edusentia marketing enquiries and system notification templates. Such updates require a separate approved release.
10. Preserve clear internal evidence (screenshots/log summaries redacted of personal and secret data), and record mailbox administrators, billing renewal date, storage/retention policy and support escalations.

## Security, privacy and operational controls

- Sensitive student, child, health, examination, identity or guardian information should not be exchanged through ordinary email without a documented school-approved secure process.
- Keep mailbox MFA and administrator account recovery independent of the public website infrastructure.
- Review Ghana Data Protection Commission obligations and Zoho data processing/residency/subprocessor agreements before operationally processing school personal data.
- Confirm mail-account retention, mailbox backup/export and legal hold needs. Mailbox hosting alone does not establish tested data restoration.
- Establish separate payment invoices, billing notifications and administrator ownership before paid annual renewal.

## Public website update decision

Do not change the current public site copy ("Business email setup is in progress") until independent send and receive tests pass. When ready, update:
- public-site/index.html footer with active mailto: links
- public-site/privacy.html contact description
- public-site/security.html as appropriate
- frontend/support.html and frontend/privacy.html, subject to owner review
- docs/COMMERCIAL_LAUNCH_GATE_REGISTER.md (MAIL-01/MAIL-02 evidence)

## Activation status as of 26 November 2026

| Item | State |
|---|---|
| Zoho provider selection and 2-seat plan | Recommended, not purchased |
| Zoho tenant/account created | NOT CONFIRMED |
| Domain ownership verified at Zoho | NOT CONFIRMED |
| info@edusentia.com mailbox created | NOT CONFIRMED |
| support@edusentia.com mailbox created | NOT CONFIRMED |
| MX/SPF/DKIM/DMARC installed | NOT CONFIGURED |
| Test send/receive from both addresses | NOT TESTED |
| Edusentia website published email links | Deliberately NOT PUBLISHED |
| Existing app, verifier, API and public website DNS | PRESERVE UNCHANGED |

## Official sources

- https://www.zoho.com/mail/zohomail-pricing.html
- https://www.zoho.com/mail/help/adminconsole/email-hosting-setup.html
- https://www.zoho.com/mail/help/adminconsole/cloudflare.html
- https://www.zoho.com/mail/help/adminconsole/configure-email-delivery.html
- https://www.zoho.com/mail/help/adminconsole/spf-configuration.html
- https://www.zoho.com/mail/help/adminconsole/dmarc-policy.html
- https://www.zoho.com/mail/help/adminconsole/security.html
- https://developers.cloudflare.com/dns/manage-dns-records/how-to/email-records/

**Required authorized owner step:** choose and activate the two paid Zoho Mail Lite mailboxes, then provide a screenshot of the Zoho Admin Console's domain DNS mapping with sensitive codes masked. From that we can validate the exact region-specific DNS entries before applying anything to Cloudflare.
