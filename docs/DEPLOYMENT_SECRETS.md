# Deployment Secrets

The Cloudflare deployment workflow reads secrets from this repository only. Secret values must never be committed to source.

## Required

- `CLOUDFLARE_API_TOKEN`: Cloudflare API token with permission to deploy Workers and manage the dedicated R2 bucket.
- `DATABASE_URL` or `NEON_DATABASE_URL`: Neon deployment credential. CI uses this only to maintain and rotate the separate least-privilege `edusentia_worker_runtime` login. The live Worker never receives this deployment credential.
- `AUTH_SECRET` or `SESSION_PEPPER`: high-entropy server-side secret used to derive stored opaque-session token hashes.
- `BOOTSTRAP_ADMIN_SECRET`: high-entropy one-time bootstrap authorization secret.

## Recommended

- `CLOUDFLARE_ACCOUNT_ID`: Cloudflare account ID. Wrangler can sometimes infer the account from the token, but explicitly configuring it removes ambiguity.

## Optional

- `TURNSTILE_SECRET`: Cloudflare Turnstile server secret when Turnstile is enabled.

## Later first-admin bootstrap

The deployment workflow does not create the first tenant or administrator. Keep any initial administrator password in a secret store and submit it only through the protected bootstrap endpoint after the live Worker health check passes.

## Runtime database privilege boundary

The Worker connects as `edusentia_worker_runtime`, which is SQL-created and intentionally has:

- no `BYPASSRLS`
- no `CREATEROLE`
- no `CREATEDB`
- no inherited Neon superuser membership
- no direct read permission on `authn.password_credentials`
- direct access only to the session/user metadata and application tables required by the Worker, with tenant RLS applied to tenant-owned data
