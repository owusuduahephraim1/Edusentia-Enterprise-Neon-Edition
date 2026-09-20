begin;

alter table authn.mfa_totp_factors
  add column if not exists friendly_name text not null default 'Authenticator';

drop index if exists authn.mfa_totp_one_verified_active_uidx;
create index if not exists mfa_totp_user_active_idx
  on authn.mfa_totp_factors(user_id,verified_at desc)
  where disabled_at is null;

insert into app.schema_migrations(version) values ('0023_multi_authenticator_mfa') on conflict do nothing;
update app.release_identity set schema_version='0023'
 where edition='Edusentia Enterprise Neon Edition';

commit;
