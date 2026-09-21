-- Neon-native MFA recovery generation metadata for certified recovery semantics.
begin;

alter table authn.mfa_recovery_codes
  add column if not exists generation_id uuid,
  add column if not exists expires_at timestamptz;

with generations as (
  select user_id,gen_random_uuid() generation_id
  from authn.mfa_recovery_codes
  group by user_id
)
update authn.mfa_recovery_codes c
   set generation_id=g.generation_id,
       expires_at=coalesce(c.expires_at,c.created_at+interval '365 days')
  from generations g
 where c.user_id=g.user_id
   and (c.generation_id is null or c.expires_at is null);

alter table authn.mfa_recovery_codes
  alter column generation_id set default gen_random_uuid(),
  alter column generation_id set not null,
  alter column expires_at set default (now()+interval '365 days'),
  alter column expires_at set not null;

create index if not exists authn_mfa_recovery_active_generation_idx
  on authn.mfa_recovery_codes(user_id,generation_id,created_at desc)
  where used_at is null;

create index if not exists authn_mfa_recovery_expiry_idx
  on authn.mfa_recovery_codes(user_id,expires_at)
  where used_at is null;

insert into app.schema_migrations(version)
values ('0048k_mfa_recovery_compat')
on conflict do nothing;

commit;
