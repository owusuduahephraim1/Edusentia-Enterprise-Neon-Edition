# Supabase replacement matrix

| Legacy capability | Neon Edition native implementation |
|---|---|
| Supabase Auth | `authn.users`, password credentials, sessions, MFA + Worker auth routes |
| Browser PostgREST queries | Explicit Worker API routes with parameterized SQL |
| Supabase RPC | Worker services or PostgreSQL functions based on transaction/security needs |
| RLS based on Supabase JWT helpers | Neon RLS based on server-set request context |
| Edge Functions | Cloudflare Worker routes/services and scheduled Workers |
| Supabase Storage | Cloudflare R2 + `storage.object_metadata` |
| Realtime | SSE/polling only for workflows that require freshness |
| Tenant Supabase projects | Shared tenant-scoped Neon schema with forced RLS |
| Service role | Non-owner `edusentia_runtime` PostgreSQL role with least privilege |
| Supabase config in browser | `EDS_MASTER_CONFIG.apiBaseUrl` public configuration only |
