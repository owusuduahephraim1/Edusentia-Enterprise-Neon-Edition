begin;

-- Upgrade-safe continuation of the additive package-distribution subsystem.
-- 0025b may already be recorded on persistent control databases; this distinct
-- migration adds encrypted private-key persistence without changing the
-- certified control schema identity (0025).
alter table platform.package_signing_keys
  add column if not exists private_jwk_ciphertext text not null default '';

insert into app.schema_migrations(version)
values ('0025c_platform_package_signing_continuity')
on conflict do nothing;

commit;
