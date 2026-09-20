begin;

-- Neon-native compatibility surface for the certified Edusentia tenant SQL.
-- This is not Supabase runtime. Browser/API authentication remains implemented
-- by Cloudflare Workers and authn.*. These helpers let certified business SQL
-- resolve the same request identity semantics inside an isolated school DB.

create schema if not exists auth;

alter table authn.users
  add column if not exists raw_user_meta_data jsonb not null default '{}'::jsonb,
  add column if not exists raw_app_meta_data jsonb not null default '{}'::jsonb;

create or replace function auth.uid()
returns uuid
language sql
stable
as $$select app.current_user_id()$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select case
    when nullif(current_setting('app.auth_role',true),'') is not null
      then current_setting('app.auth_role',true)
    when app.current_user_id() is not null then 'authenticated'
    else 'service_role'
  end
$$;

create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'sub',app.current_user_id(),
    'role',auth.role(),
    'aal',case when app.current_aal()>=2 then 'aal2' else 'aal1' end,
    'app_role',app.current_role()
  )
$$;

insert into app.schema_migrations(version)
values ('0026_reference_compat_prelude')
on conflict do nothing;

update app.release_identity
   set schema_version='0026'
 where edition='Edusentia Enterprise Neon Edition';

commit;
