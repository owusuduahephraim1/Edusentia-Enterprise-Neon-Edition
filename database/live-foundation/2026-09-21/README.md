# Live Foundation Clean-Room Install

This directory contains schema-only snapshots of the live Edusentia Supabase master and tenant databases taken read-only on 2026-09-21, plus Neon compatibility layers.

## What this is

- A reproducible historical PostgreSQL schema foundation.
- No application rows are included.
- No secrets, passwords, Supabase service keys, connection strings, or object bytes are included.
- The master and tenant manifests record exact object counts and canonical schema hashes.

## Install choices

Use `install-master-foundation.sh` or `install-tenant-foundation.sh` only when you need the historical public schema by itself.

Use `install-combined-master.sh` or `install-combined-tenant.sh` for the deployable Neon edition. The combined installers add the Neon-native schemas, runtime roles, provider adaptations, certified RPC layer, and the historical auth/R2 bridge.

Both installers refuse to install the historical foundation into a database whose public schema already contains application tables.

## Provider contracts

The clean-room compatibility layer intentionally does not recreate Supabase as a runtime.

- `authn.*` is authoritative for Neon-native authentication.
- Historical `auth.users` is retained only where the restored public schema has foreign keys or certified functions that require it.
- `storage.object_metadata` plus Cloudflare R2 are authoritative for file metadata and bytes.
- Historical `storage.objects` is a compatibility catalog populated from active R2 metadata.
- Supabase Realtime is not required by the certified SQL surface.
- Outbound HTTP must run through the Cloudflare Worker rather than a database `pg_net` dependency.

## Verified clean-room gates

The committed package was installed from its GitHub files into new empty Neon databases.

Master:
- 102 public tables
- 369 public functions
- 247 RLS policies
- 216 user triggers
- 310 indexes
- 584 constraints
- all recorded canonical hashes matched the live source

Tenant:
- 190 public tables
- 678 public functions at the historical foundation stage
- 235 RLS policies
- 444 user triggers
- 719 indexes
- 1,180 constraints
- all recorded canonical hashes matched the live source

The tenant combined overlay then installed through compatibility release `0048h`, followed by `0048i_historical_provider_bridges`.
