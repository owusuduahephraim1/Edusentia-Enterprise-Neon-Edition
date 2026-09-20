# Neon Edition architecture

## Decision: shared multi-tenant Neon database

The old stable system used separately provisioned tenant backends. The Neon Edition instead uses one properly partitioned, shared PostgreSQL schema with a mandatory `tenant_id` on tenant-owned rows. This changes infrastructure, not business behavior.

Isolation is enforced at three layers:

1. Worker resolves tenant from the authenticated server-side session, never from a browser-supplied tenant ID.
2. Worker parameterizes all SQL and sets PostgreSQL request context (`app.tenant_id`, `app.user_id`, role and assurance level).
3. PostgreSQL RLS uses the request context for `USING` and `WITH CHECK`, with `FORCE ROW LEVEL SECURITY` on tenant tables. The Worker uses a non-owner runtime role.

## Authentication

Passwords are stored only as salted scrypt hashes. Sessions use a random opaque token in a Secure, HttpOnly cookie; only a SHA-256 token digest combined with a server-side pepper is persisted. Sessions have explicit expiry and revocation. MFA tables and assurance level are modeled from the beginning so high-risk workflows can require AAL2.

Cloudflare Workers does not expose Node's Argon2 APIs, so the first release uses an audited scrypt implementation with bounded memory parameters. This can later be upgraded with versioned credential rehashing without changing the user model.

## Storage

R2 is the only object store. Object keys are tenant-prefixed. Every object has Neon metadata including tenant, creator, content type, authorized size and lifecycle status. The browser never receives R2 credentials. Upload and download operations are authorized through the Worker.

## GitHub Pages

The frontend is fully static and repository-path-safe. There is no `CNAME`, no custom DNS and no database secret in the build. The only environment-specific browser value is the public Worker API URL.

## Cross-site session compatibility

Because the GitHub Pages origin and `workers.dev` API are different sites, the session cookie is `Secure`, `HttpOnly`, `SameSite=None` and `Partitioned`. Unsafe methods additionally require the exact configured GitHub Pages `Origin`, and JSON APIs require explicit content types.
