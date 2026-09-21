-- Neon compatibility prelude for the historical Edusentia public schema.
-- This supplies only provider contracts referenced by Edusentia SQL. It is not a Supabase runtime.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS vault;
CREATE SCHEMA IF NOT EXISTS net;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  instance_id uuid,
  aud varchar(255),
  role varchar(255),
  email varchar(255),
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  invited_at timestamptz,
  confirmation_token varchar(255),
  confirmation_sent_at timestamptz,
  recovery_token varchar(255),
  recovery_sent_at timestamptz,
  email_change_token_new varchar(255),
  email_change varchar(255),
  email_change_sent_at timestamptz,
  last_sign_in_at timestamptz,
  raw_app_meta_data jsonb DEFAULT '{}'::jsonb,
  raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
  is_super_admin boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  phone text,
  phone_confirmed_at timestamptz,
  phone_change text DEFAULT '',
  phone_change_token varchar(255) DEFAULT '',
  phone_change_sent_at timestamptz,
  email_change_token_current varchar(255) DEFAULT '',
  email_change_confirm_status smallint DEFAULT 0,
  banned_until timestamptz,
  reauthentication_token varchar(255) DEFAULT '',
  reauthentication_sent_at timestamptz,
  is_sso_user boolean DEFAULT false NOT NULL,
  deleted_at timestamptz,
  is_anonymous boolean DEFAULT false NOT NULL
);

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)
$$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid,
    NULLIF(auth.jwt()->>'sub','')::uuid,
    NULLIF(current_setting('app.current_user_id',true),'')::uuid,
    NULLIF(current_setting('app.user_id',true),'')::uuid
  )
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role',true),''),
    NULLIF(auth.jwt()->>'role',''),
    NULLIF(current_setting('app.auth_role',true),''),
    CASE WHEN auth.uid() IS NULL THEN 'service_role' ELSE 'authenticated' END
  )
$$;

CREATE TABLE IF NOT EXISTS storage.buckets(
  id text PRIMARY KEY,name text NOT NULL UNIQUE,owner uuid,public boolean DEFAULT false,
  file_size_limit bigint,allowed_mime_types text[],created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS storage.objects(
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets(id) ON DELETE CASCADE,
  name text NOT NULL,owner uuid,created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),
  last_accessed_at timestamptz DEFAULT now(),metadata jsonb,user_metadata jsonb,version text,owner_id text
);
CREATE UNIQUE INDEX IF NOT EXISTS storage_objects_bucket_name_uq ON storage.objects(bucket_id,name);
CREATE OR REPLACE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN strpos($1,'/')=0 THEN ARRAY[]::text[] ELSE string_to_array(regexp_replace($1,'/[^/]*$',''),'/') END
$$;

CREATE TABLE IF NOT EXISTS vault.secrets(
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  name text UNIQUE,description text NOT NULL DEFAULT '',key_id uuid,
  secret_ciphertext bytea NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE VIEW vault.decrypted_secrets AS
SELECT id,name,description,key_id,created_at,updated_at,
       CASE WHEN COALESCE(current_setting('app.vault_key',true),'')=''
            THEN NULL::text
            ELSE extensions.pgp_sym_decrypt(secret_ciphertext,current_setting('app.vault_key',true))
       END AS decrypted_secret
FROM vault.secrets;

CREATE OR REPLACE FUNCTION vault.create_secret(
  new_secret text,new_name text DEFAULT NULL,new_description text DEFAULT '',new_key_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=vault,extensions,pg_catalog AS $$
DECLARE k text; v_id uuid;
BEGIN
  k:=current_setting('app.vault_key',true);
  IF COALESCE(k,'')='' THEN RAISE EXCEPTION 'app.vault_key is not configured'; END IF;
  INSERT INTO vault.secrets(name,description,key_id,secret_ciphertext)
  VALUES(new_name,COALESCE(new_description,''),new_key_id,extensions.pgp_sym_encrypt(new_secret,k))
  ON CONFLICT(name) DO UPDATE SET description=excluded.description,key_id=excluded.key_id,
    secret_ciphertext=excluded.secret_ciphertext,updated_at=now()
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION vault.update_secret(
  secret_id uuid,new_secret text DEFAULT NULL,new_name text DEFAULT NULL,new_description text DEFAULT NULL,new_key_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=vault,extensions,pg_catalog AS $$
DECLARE k text;
BEGIN
  k:=current_setting('app.vault_key',true);
  IF new_secret IS NOT NULL AND COALESCE(k,'')='' THEN RAISE EXCEPTION 'app.vault_key is not configured'; END IF;
  UPDATE vault.secrets SET
    name=COALESCE(new_name,name),
    description=COALESCE(new_description,description),
    key_id=COALESCE(new_key_id,key_id),
    secret_ciphertext=CASE WHEN new_secret IS NULL THEN secret_ciphertext ELSE extensions.pgp_sym_encrypt(new_secret,k) END,
    updated_at=now()
  WHERE id=secret_id;
END $$;

CREATE OR REPLACE FUNCTION net.http_post(
  url text,body jsonb DEFAULT '{}'::jsonb,params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb,timeout_milliseconds integer DEFAULT 5000
) RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'net.http_post is not provided by Neon; route outbound HTTP through the Edusentia Cloudflare Worker';
END $$;

COMMENT ON SCHEMA public IS 'standard public schema';
SET search_path TO public, extensions, pg_catalog;
