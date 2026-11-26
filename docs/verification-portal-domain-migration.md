# Official public verification domain migration

Target: `verify.edusentia.com`, independently hosted from the school administration app.

## Current safeguards

- The existing GitHub Pages `?staffcard=`, `?idcard=`, `?verify=`,
  `?certificate=`, and `?transcript=` routes remain operational.
- The new portal displays only token-bound public card/document verification data.
  It has no administrative login, session, dashboard, or protected file service.
- Only two public API GET endpoints permit CORS from the new verification origin;
  it is never added to the credentialed application-origin allowlist.
- The pre-existing Edusentia application continues serving `verify-card.html`.
- New QR codes are **not switched to verify.edusentia.com yet**. Switch only
  after the independent portal has a successful deployment and active HTTPS,
  and after checking all five verification link formats.

## 1. Create the parallel public Pages project

Cloudflare Dashboard > Workers & Pages > Create application > Continue to Pages
> Connect to Git > GitHub repository
`owusuduahephraim1/Edusentia-Enterprise-Neon-Edition`.

| Field | Value |
|---|---|
| Project name | `edusentia-verify` |
| Production branch | `main` |
| Framework preset | `None` |
| Build command | `node scripts/build-verification-site.mjs` |
| Build output directory | `dist/verification` |
| Root directory (advanced) | empty (repository root) |
| Additional build environment variables | none |

The script copies the tested verification UI, uses `api.edusentia.com`,
publishes `index.html` and `verify-card.html`, and adds strict security
headers. It does **not** copy the school management application.

## 2. Test the temporary public URL

Visit `https://edusentia-verify.pages.dev/`. It should explain how to scan
a document without opening a login page. An issued QR token should show the
issuing institution and its actual current validity status. Invalid tokens
should show "not verified"; they must never show "valid."

Use `?staffcard=<uuid>&school=<code>`,
`?idcard=<uuid>&school=<code>`,
`?verify=<uuid>&school=<code>`,
`?certificate=<uuid>&school=<code>`, or
`?transcript=<uuid>&school=<code>` where the issuing records exist.
Pre-existing UUID-only links are also supported by the Worker.

## 3. Add the actual verification hostname

Select **Workers & Pages > edusentia-verify > Custom domains >
Set up a custom domain** and enter `verify.edusentia.com`. Confirm the
Cloudflare-proposed CNAME to `edusentia-verify.pages.dev`, and check the
custom domain becomes **Active** with HTTPS enabled.

Do not add the hostname to the application Pages project
`edusentia-app`. Do not add it to Turnstile: the verification portal does
not present a Turnstile sign-in or registration form.

Do not add a manual duplicate DNS record.

## 4. Production validation and later QR migration

Confirm the portal and API can serve all five read-only verification modes.
Check invalid, revoked, replaced, expired and current records in addition
to an actually issued card/document. Keep the original GitHub and
`workers.dev` URLs unchanged.

**Only after that**: modify the QR generator and the school's official
Verification base URL to use the new portal. Preserve old printed QR
links permanently or until each printed document has expired or been replaced.

The public Edusentia marketing website (`edusentia.com` and
`www.edusentia.com`) is a separate future project.
