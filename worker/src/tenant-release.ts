export const TENANT_RUNTIME_SCHEMA_VERSION="0020";
export const CERTIFIED_COMPAT_SCHEMA_VERSION="0027";
export const TENANT_RUNTIME_VERSION="neon-v1.0.0-r42-parity";

export type TenantReleaseStatus={
  runtimeSchemaVersion:string;
  runtimeVersion:string;
  compatibilitySchemaVersion:string;
  certifiedCoreReady:boolean;
  ready:boolean;
};

export async function inspectTenantRelease(sql:any):Promise<TenantReleaseStatus>{
  const rows=await sql`
    select
      coalesce((select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1),'') runtime_schema_version,
      coalesce((select version from app.release_identity where edition='Edusentia Enterprise Neon Tenant Runtime' limit 1),'') runtime_version,
      coalesce((select schema_version from app.release_identity where edition='Edusentia Enterprise Neon Edition' limit 1),'') compatibility_schema_version,
      exists(
        select 1
          from pg_proc p
          join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='get_bootstrap_data'
      ) certified_core_ready
  `;
  const row=(rows[0]||{}) as any;
  const runtimeSchemaVersion=String(row.runtime_schema_version||"");
  const runtimeVersion=String(row.runtime_version||"");
  const compatibilitySchemaVersion=String(row.compatibility_schema_version||"");
  const certifiedCoreReady=Boolean(row.certified_core_ready);
  return {
    runtimeSchemaVersion,
    runtimeVersion,
    compatibilitySchemaVersion,
    certifiedCoreReady,
    ready:
      runtimeSchemaVersion===TENANT_RUNTIME_SCHEMA_VERSION &&
      runtimeVersion===TENANT_RUNTIME_VERSION &&
      compatibilitySchemaVersion===CERTIFIED_COMPAT_SCHEMA_VERSION &&
      certifiedCoreReady
  };
}
