# Certified UI reference source

This directory is **reference-only porting material** for the Edusentia Enterprise Neon Edition.

Source baseline:
- Repository: `nduah385/Edusentia-Enterprise`
- Certified branch baseline: `backup/r42-v18-stable-20260919`
- Certified source commit: `a181e18e0ca044db756193209b5b089cd03efb0f`

## Runtime boundary

Nothing in this directory may be imported, served, bundled, cached, or deployed by the Neon Edition runtime.

The source intentionally preserves historical vendor-era code so engineers can compare certified business behavior and UI semantics while porting. Production code lives under `frontend/`, `worker/`, and `database/`, and must continue to pass the no-Supabase runtime gate.

Do not weaken `scripts/verify-no-supabase-runtime.mjs` to accommodate this reference material.

## Porting order

1. Preserve certified shell, navigation, terminology, responsive behavior, and visual assets.
2. Replace authentication, MFA, recovery, and session transport with the existing Worker-managed Neon identity APIs.
3. Replace business RPC access with explicit `EdusentiaApi.certifiedRpc` operations backed by the Worker allowlist and trusted request context.
4. Replace all storage operations with authorized Cloudflare R2 Worker routes and Neon metadata.
5. Port active school domains incrementally, retaining role visibility and certified workflow order.
6. Keep retired Inventory, Library, and Transport workspaces retired.
7. Run the no-Supabase gate, Worker quality gate, schema smoke, reference compatibility smoke, and synthetic school lifecycle tests before any promotion.

This directory is a blueprint, not a compatibility runtime.
