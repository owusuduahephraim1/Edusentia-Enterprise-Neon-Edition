# Security model

- No database or R2 credentials in browser code.
- Credentialed CORS is restricted to the configured GitHub Pages origin.
- Opaque sessions use Secure + HttpOnly cookies and server-side revocation.\n- MFA-required memberships cannot obtain an authenticated session until TOTP or a one-time recovery code completes an assurance-level-2 challenge. TOTP secrets are AES-GCM encrypted at rest with domain-separated key material derived from the server-side session secret.
- Passwords use salted scrypt with versioned algorithm metadata.
- Tenant IDs are resolved from sessions and reinforced by forced PostgreSQL RLS.
- The deployed Worker uses `edusentia_worker_runtime`, a SQL-created role with no `BYPASSRLS`, `CREATEROLE`, `CREATEDB`, or inherited Neon superuser membership. The Neon-managed deployment credential is never used by the live Worker.
- SQL is parameterized through the Neon serverless driver.
- R2 keys are tenant-prefixed and checked against metadata before transfer.
- Accounts Office Staff hard deletion is forbidden by product invariant.
- Audit records avoid secret values.
- Production errors return stable codes rather than SQL messages or stack traces.

- Platform Super Administrator authority is separated from tenant memberships. Platform operators use dedicated platform sessions, require TOTP AAL2, and are never granted a school `system_admin` membership merely by holding platform authority.
- Registration approval, licensing, tenant lifecycle, provisioning, student-capacity controls, and platform audit events are enforced through protected control-plane tables/functions rather than browser-side role flags.

- School System Administrator onboarding uses a short-lived one-time administrator setup token. Only a domain-separated hash is stored in Neon; the plaintext token is delivered in the setup link and removed from the browser address bar after page load.
- The Worker has no direct privilege on `authn.password_credentials` or `platform.tenant_admin_setup_tokens`. Password creation and setup-token consumption occur only through restricted `SECURITY DEFINER` functions.
