select version from app.schema_migrations order by version;

select n.nspname as schema_name,count(*)::int as table_count
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where c.relkind='r' and n.nspname in('app','authn','academics','finance','storage','audit','services','documents','ops','platform')
group by n.nspname order by n.nspname;

select count(*) as tenant_tables_without_rls
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
join pg_attribute a on a.attrelid=c.oid and a.attname='tenant_id'
where c.relkind='r'
  and n.nspname in('app','academics','finance','storage','audit','services','documents','ops')
  and not c.relrowsecurity;

select count(*) as operational_tenant_tables_without_forced_rls
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
join pg_attribute a on a.attrelid=c.oid and a.attname='tenant_id'
where c.relkind='r'
  and n.nspname in('app','academics','finance','storage','audit','services','documents','ops')
  and not (n.nspname='app' and c.relname='tenant_memberships')
  and not (n.nspname='audit' and c.relname='events')
  and not c.relforcerowsecurity;

select count(*) as tenant_tables_without_tenant_policy
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
join pg_attribute a on a.attrelid=c.oid and a.attname='tenant_id'
where c.relkind='r'
  and n.nspname in('app','academics','finance','storage','audit','services','documents','ops')
  and not exists(select 1 from pg_policies p where p.schemaname=n.nspname and p.tablename=c.relname and p.policyname in('tenant_isolation','tenant_context'));

select exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app' and p.proname='set_request_context') as context_function_exists;
select exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='authn' and p.proname='bootstrap_first_admin') as first_admin_bootstrap_exists;
select exists(select 1 from pg_trigger where tgname='accounts_office_staff_no_hard_delete' and not tgisinternal) as accounts_office_retention_guard_exists;
select schema_version,source_baseline,source_commit from app.release_identity where edition='Edusentia Enterprise Neon Edition';
