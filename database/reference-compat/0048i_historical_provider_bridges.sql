-- Edusentia Enterprise Neon Edition
-- Historical provider bridge for clean-room live-schema installations.
-- Keeps the Neon-native authn.* and storage.object_metadata models authoritative
-- while maintaining the narrow auth.users and storage.objects contracts expected
-- by the certified historical public schema.
begin;

do $auth_bridge_install$
declare k "char";
begin
  select c.relkind into k
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='auth' and c.relname='users';

  -- Earlier Neon-only installs expose auth.users as a view over authn.users and
  -- therefore already stay synchronized. The trigger bridge is needed only when
  -- clean-room restoration provides the historical auth.users table.
  if k='r' then
    execute $ddl$
      create or replace function authn.sync_historical_auth_user()
      returns trigger
      language plpgsql
      security definer
      set search_path=authn,auth,pg_catalog
      as $fn$
      begin
        if tg_op='DELETE' then
          delete from auth.users where id=old.id;
          return old;
        end if;

        insert into auth.users(
          id,role,email,phone,raw_user_meta_data,raw_app_meta_data,
          created_at,updated_at,banned_until,deleted_at
        )
        values(
          new.id,'authenticated',new.email,new.phone,
          coalesce(new.raw_user_meta_data,'{}'::jsonb),
          coalesce(new.raw_app_meta_data,'{}'::jsonb),
          new.created_at,new.updated_at,new.disabled_at,new.disabled_at
        )
        on conflict(id) do update set
          role='authenticated',
          email=excluded.email,
          phone=excluded.phone,
          raw_user_meta_data=excluded.raw_user_meta_data,
          raw_app_meta_data=excluded.raw_app_meta_data,
          updated_at=excluded.updated_at,
          banned_until=excluded.banned_until,
          deleted_at=excluded.deleted_at;
        return new;
      end
      $fn$
    $ddl$;

    execute 'drop trigger if exists sync_historical_auth_user on authn.users';
    execute 'create trigger sync_historical_auth_user after insert or update or delete on authn.users for each row execute function authn.sync_historical_auth_user()';

    insert into auth.users(
      id,role,email,phone,raw_user_meta_data,raw_app_meta_data,
      created_at,updated_at,banned_until,deleted_at
    )
    select
      u.id,'authenticated',u.email,u.phone,
      coalesce(u.raw_user_meta_data,'{}'::jsonb),
      coalesce(u.raw_app_meta_data,'{}'::jsonb),
      u.created_at,u.updated_at,u.disabled_at,u.disabled_at
    from authn.users u
    on conflict(id) do update set
      role='authenticated',
      email=excluded.email,
      phone=excluded.phone,
      raw_user_meta_data=excluded.raw_user_meta_data,
      raw_app_meta_data=excluded.raw_app_meta_data,
      updated_at=excluded.updated_at,
      banned_until=excluded.banned_until,
      deleted_at=excluded.deleted_at;
  end if;
end
$auth_bridge_install$;

do $storage_bridge_install$
declare k "char";
begin
  select c.relkind into k
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='storage' and c.relname='objects';

  if k='r' and to_regclass('storage.object_metadata') is not null then
    execute $ddl$
      create or replace function storage.sync_historical_storage_object()
      returns trigger
      language plpgsql
      security definer
      set search_path=storage,pg_catalog
      as $fn$
      declare
        bucket text;
        legacy_name text;
      begin
        if tg_op='DELETE' then
          delete from storage.objects
           where id=old.id
              or metadata->>'r2_key'=old.object_key;
          return old;
        end if;

        if tg_op='UPDATE' and old.object_key is distinct from new.object_key then
          delete from storage.objects
           where id=old.id
              or metadata->>'r2_key'=old.object_key;
        end if;

        bucket:=split_part(new.object_key,'/',3);
        legacy_name:=regexp_replace(new.object_key,'^tenants/[^/]+/[^/]+/','');

        if new.object_key !~ '^tenants/[^/]+/[^/]+/.+' or bucket='' or legacy_name='' then
          return new;
        end if;

        if new.status<>'active' then
          delete from storage.objects
           where id=new.id
              or metadata->>'r2_key'=new.object_key;
          return new;
        end if;

        insert into storage.buckets(id,name,owner,public,created_at,updated_at)
        values(bucket,bucket,new.created_by,false,now(),now())
        on conflict(id) do update set updated_at=now();

        insert into storage.objects(
          id,bucket_id,name,owner,created_at,updated_at,last_accessed_at,
          metadata,user_metadata,version,owner_id
        )
        values(
          new.id,bucket,legacy_name,new.created_by,new.created_at,
          coalesce(new.stored_at,new.created_at),coalesce(new.stored_at,new.created_at),
          jsonb_build_object(
            'size',new.size_bytes,
            'mimetype',new.content_type,
            'r2_key',new.object_key,
            'status',new.status
          ),
          jsonb_build_object('original_name',new.original_name),
          null,
          case when new.created_by is null then null else new.created_by::text end
        )
        on conflict(id) do update set
          bucket_id=excluded.bucket_id,
          name=excluded.name,
          owner=excluded.owner,
          updated_at=excluded.updated_at,
          last_accessed_at=excluded.last_accessed_at,
          metadata=excluded.metadata,
          user_metadata=excluded.user_metadata,
          owner_id=excluded.owner_id;
        return new;
      end
      $fn$
    $ddl$;

    execute 'drop trigger if exists sync_historical_storage_object on storage.object_metadata';
    execute 'create trigger sync_historical_storage_object after insert or update or delete on storage.object_metadata for each row execute function storage.sync_historical_storage_object()';

    -- Backfill active R2 metadata without inventing object bytes.
    insert into storage.buckets(id,name,owner,public,created_at,updated_at)
    select distinct
      split_part(m.object_key,'/',3),
      split_part(m.object_key,'/',3),
      m.created_by,false,now(),now()
    from storage.object_metadata m
    where m.status='active'
      and m.object_key ~ '^tenants/[^/]+/[^/]+/.+'
    on conflict(id) do update set updated_at=now();

    insert into storage.objects(
      id,bucket_id,name,owner,created_at,updated_at,last_accessed_at,
      metadata,user_metadata,version,owner_id
    )
    select
      m.id,
      split_part(m.object_key,'/',3),
      regexp_replace(m.object_key,'^tenants/[^/]+/[^/]+/',''),
      m.created_by,m.created_at,coalesce(m.stored_at,m.created_at),coalesce(m.stored_at,m.created_at),
      jsonb_build_object('size',m.size_bytes,'mimetype',m.content_type,'r2_key',m.object_key,'status',m.status),
      jsonb_build_object('original_name',m.original_name),
      null,
      case when m.created_by is null then null else m.created_by::text end
    from storage.object_metadata m
    where m.status='active'
      and m.object_key ~ '^tenants/[^/]+/[^/]+/.+'
    on conflict(id) do update set
      bucket_id=excluded.bucket_id,
      name=excluded.name,
      owner=excluded.owner,
      updated_at=excluded.updated_at,
      last_accessed_at=excluded.last_accessed_at,
      metadata=excluded.metadata,
      user_metadata=excluded.user_metadata,
      owner_id=excluded.owner_id;
  end if;
end
$storage_bridge_install$;

insert into app.schema_migrations(version)
values ('0048i_historical_provider_bridges')
on conflict do nothing;

commit;
