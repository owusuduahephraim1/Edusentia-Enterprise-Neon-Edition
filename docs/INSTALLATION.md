# Fresh installation

1. Create a new Neon project and empty `edusentia` database.
2. Create a non-owner PostgreSQL role named `edusentia_runtime`.
3. Apply `database/migrations/*.sql` in lexical order as the database owner.
4. Apply `database/seeds/0001_permissions.sql`.
5. Create a private Cloudflare R2 bucket named `edusentia-enterprise-neon` (or adjust the Worker binding).
6. Configure Worker secrets: `DATABASE_URL`, `SESSION_PEPPER`, `BOOTSTRAP_ADMIN_SECRET` and optional `TURNSTILE_SECRET`.
7. Set `APP_ORIGIN` to the exact GitHub Pages origin and deploy the Worker.
8. Set `frontend/config.js` `apiBaseUrl` to the Worker `workers.dev` URL.
9. Enable GitHub Pages from GitHub Actions and deploy `frontend/`.
10. Bootstrap the first administrator through the protected one-time bootstrap process, then rotate/remove the bootstrap secret.
11. Run database, API, CORS, R2, tenant-isolation and browser smoke tests.

There is no prerequisite Supabase installation and no data import step.
