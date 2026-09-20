begin;
-- Tenant business tables use forced RLS. Authentication bootstrap tables that are read
-- through tightly controlled SECURITY DEFINER functions use ordinary RLS so the table
-- owner can service those functions while the runtime role remains policy-bound.
do $$declare r record; begin
  for r in
    select n.nspname schema_name,c.relname table_name
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid and a.attname='tenant_id'
    where c.relkind='r'
      and n.nspname in('app','academics','finance','storage','audit')
      and not (n.nspname='app' and c.relname='tenant_memberships')
      and not (n.nspname='audit' and c.relname='events')
  loop
    execute format('alter table %I.%I enable row level security',r.schema_name,r.table_name);
    execute format('alter table %I.%I force row level security',r.schema_name,r.table_name);
    if not exists(select 1 from pg_policies where schemaname=r.schema_name and tablename=r.table_name and policyname='tenant_isolation') then
      execute format('create policy tenant_isolation on %I.%I using (tenant_id = app.current_tenant_id()) with check (tenant_id = app.current_tenant_id())',r.schema_name,r.table_name);
    end if;
  end loop;
end$$;

alter table app.tenants enable row level security;
do $$begin if not exists(select 1 from pg_policies where schemaname='app' and tablename='tenants' and policyname='tenant_context') then create policy tenant_context on app.tenants using (id=app.current_tenant_id()) with check (id=app.current_tenant_id()); end if; end$$;

alter table app.tenant_memberships enable row level security;
do $$begin if not exists(select 1 from pg_policies where schemaname='app' and tablename='tenant_memberships' and policyname='tenant_isolation') then create policy tenant_isolation on app.tenant_memberships using (tenant_id=app.current_tenant_id()) with check (tenant_id=app.current_tenant_id()); end if; end$$;

alter table audit.events enable row level security;
do $$begin if not exists(select 1 from pg_policies where schemaname='audit' and tablename='events' and policyname='tenant_isolation') then create policy tenant_isolation on audit.events using (tenant_id=app.current_tenant_id()) with check (tenant_id=app.current_tenant_id()); end if; end$$;

-- The runtime role is infrastructure-managed and intentionally is not a table owner.
do $$begin if exists(select 1 from pg_roles where rolname='edusentia_runtime') then
  grant usage on schema app,authn,academics,finance,storage,audit to edusentia_runtime;
  grant select,insert,update,delete on all tables in schema app,authn,academics,finance,storage,audit to edusentia_runtime;
  grant usage,select on all sequences in schema app,authn,academics,finance,storage,audit to edusentia_runtime;
  grant execute on all functions in schema app,audit to edusentia_runtime;
  grant execute on function authn.lookup_login(text,text) to edusentia_runtime;
  alter default privileges in schema app grant select,insert,update,delete on tables to edusentia_runtime;
  alter default privileges in schema academics grant select,insert,update,delete on tables to edusentia_runtime;
  alter default privileges in schema finance grant select,insert,update,delete on tables to edusentia_runtime;
  alter default privileges in schema storage grant select,insert,update,delete on tables to edusentia_runtime;
  alter default privileges in schema audit grant select,insert,update,delete on tables to edusentia_runtime;
end if; end$$;
insert into app.schema_migrations(version) values ('0007_rls_and_runtime_grants') on conflict do nothing;
commit;
