# Edusentia Enterprise Neon Edition

A fresh, independent Edusentia Enterprise edition designed natively for Neon PostgreSQL, Cloudflare Workers, Cloudflare R2 and GitHub Pages.

This repository is **not a Supabase migration**. The r42 stable product is used as the functional, UX and business-rule reference. Supabase is not part of the production runtime.

## Runtime architecture

```text
GitHub Pages frontend
        |
        | HTTPS + credentialed session cookie
        v
Cloudflare Worker API
        |                  \
        |                   \
        v                    v
Neon PostgreSQL        Cloudflare R2
```

## Baseline references

- Supplied local blueprint: `Edusentia-Enterprise-r42-v17-STABLE-20260913`
- Current stable product/source reference: `Edusentia-Enterprise-r42-v18-STABLE-20260919`
- Certified r42-v18 source commit: `a181e18e0ca044db756193209b5b089cd03efb0f`
- Current tenant runtime contract inspected from the live stable system: `r41-v2-auth-continuity-20260912`
- r42-v18 Accounts Office Staff retention correction is a required invariant.

## New edition identity

- Product: `Edusentia Enterprise Neon Edition`
- Initial release line: `neon-v1.0.0`
- Neon project: `Edusentia-Enterprise-Neon-Edition`
- Neon database: `edusentia`
- Frontend: GitHub Pages repository URL only
- API: Cloudflare Workers `workers.dev` URL
- Objects: Cloudflare R2 only
- Custom domain: none
- CNAME: forbidden

See `docs/ARCHITECTURE.md` and `docs/ARCHITECTURE_INVENTORY.md`.
