# Security model

- No database or R2 credentials in browser code.
- Credentialed CORS is restricted to the configured GitHub Pages origin.
- Opaque sessions use Secure + HttpOnly cookies and server-side revocation.
- Passwords use salted scrypt with versioned algorithm metadata.
- Tenant IDs are resolved from sessions and reinforced by forced PostgreSQL RLS.
- SQL is parameterized through the Neon serverless driver.
- R2 keys are tenant-prefixed and checked against metadata before transfer.
- Accounts Office Staff hard deletion is forbidden by product invariant.
- Audit records avoid secret values.
- Production errors return stable codes rather than SQL messages or stack traces.
