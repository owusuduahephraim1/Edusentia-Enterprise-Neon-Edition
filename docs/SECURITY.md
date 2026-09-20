# Security model

- No database or R2 credentials in browser code.
- Credentialed CORS is restricted to the configured GitHub Pages origin.
- Opaque sessions use Secure + HttpOnly cookies and server-side revocation.
- Passwords use salted scrypt with versioned algorithm metadata.
- Tenant IDs are resolved from sessions and reinforced by forced PostgreSQL RLS.
- The deployed Worker uses `edusentia_worker_runtime`, a SQL-created role with no `BYPASSRLS`, `CREATEROLE`, `CREATEDB`, or inherited Neon superuser membership. The Neon-managed deployment credential is never used by the live Worker.
- SQL is parameterized through the Neon serverless driver.
- R2 keys are tenant-prefixed and checked against metadata before transfer.
- Accounts Office Staff hard deletion is forbidden by product invariant.
- Audit records avoid secret values.
- Production errors return stable codes rather than SQL messages or stack traces.
