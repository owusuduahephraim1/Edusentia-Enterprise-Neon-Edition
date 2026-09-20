import { neon } from "@neondatabase/serverless";
import type { Env } from "./types";
import { db } from "./db";
import { tenantDatabaseName, tenantDb, validateDatabaseName } from "./tenant-db";

function ident(value:string){
  const v=validateDatabaseName(value);
  return '"'+v.replaceAll('"','""')+'"';
}
function templateIdent(env:Env){
  const value=String(env.TENANT_TEMPLATE_DATABASE||"edusentia_tenant_template");
  if(!/^edusentia_[a-z0-9_]{3,50}$/.test(value))throw Object.assign(new Error("Tenant template database is not configured safely"),{code:"tenant_template_invalid",status:500});
  return '"'+value.replaceAll('"','""')+'"';
}
async function raw(sql:any,text:string){return sql.query(text,[]);}

export async function provisionIsolatedTenant(env:Env,tenantId:string,actorId:string){
  if(!env.PROVISIONER_DATABASE_URL)throw Object.assign(new Error("Tenant provisioner is not configured"),{code:"provisioner_not_configured",status:503});
  const master=db(env);
  const rows=await master`
    select tc.tenant_id,tc.registration_id,tc.tenant_code,tc.school_name,tc.institution_type,tc.admin_email,tc.status,
           tc.database_name,tc.database_state,tc.plan_code,tc.license_started_at,tc.license_expires_at,
           r.contact_name
      from platform.tenant_control tc
      join platform.school_registrations r on r.id=tc.registration_id
     where tc.tenant_id=${tenantId}::uuid
     limit 1`;
  const t=rows[0] as any;
  if(!t)throw Object.assign(new Error("Tenant was not found"),{code:"tenant_not_found",status:404});
  if(t.status==="denied")throw Object.assign(new Error("Denied schools cannot be provisioned"),{code:"tenant_denied",status:409});
  if(t.database_state==="isolated_ready"&&t.database_name){
    const health=await tenantDb(env,String(t.database_name))`select app.platform_health_snapshot(${tenantId}::uuid) result`;
    return {ok:true,alreadyReady:true,databaseName:t.database_name,health:(health[0] as any)?.result};
  }

  const databaseName=tenantDatabaseName(String(t.tenant_code)),provisioner=neon(env.PROVISIONER_DATABASE_URL);
  try{
    await master`update platform.provisioning_jobs set status='running',stage='database_create',attempts=attempts+1,started_at=coalesce(started_at,now()),updated_at=now(),last_error='' where tenant_id=${tenantId}::uuid and status<>'cancelled'`;
    await master`update platform.tenant_control set database_name=${databaseName},database_state='creating',updated_at=now() where tenant_id=${tenantId}::uuid`;

    const exists=await provisioner`select 1 as ok from pg_database where datname=${databaseName}`;
    if(!exists[0]){
      await raw(provisioner,`create database ${ident(databaseName)} template ${templateIdent(env)}`);
    }
    await raw(provisioner,`revoke connect on database ${ident(databaseName)} from public`);
    await raw(provisioner,`grant connect on database ${ident(databaseName)} to edusentia_worker_runtime`);
    await raw(provisioner,`grant connect on database ${ident(databaseName)} to edusentia_runtime`);

    await master`update platform.provisioning_jobs set stage='tenant_initialize',updated_at=now() where tenant_id=${tenantId}::uuid and status='running'`;
    const tenantSql=tenantDb(env,databaseName);
    const initialized=await tenantSql`select app.platform_initialize_tenant(
      ${tenantId}::uuid,${String(t.tenant_code)},${String(t.school_name)},${String(t.institution_type)},
      ${String(t.admin_email)},${String(t.contact_name||"System Administrator")},${String(t.plan_code||"starter")},
      ${t.license_started_at}::timestamptz,${t.license_expires_at}::timestamptz
    ) result`;
    const healthRows=await tenantSql`select app.platform_health_snapshot(${tenantId}::uuid) result`;
    const health=(healthRows[0] as any)?.result||{};
    if(health.schema_version!=="0020")throw new Error("Tenant template schema verification failed");

    await master`update platform.provisioning_jobs set stage='release_verify',updated_at=now() where tenant_id=${tenantId}::uuid and status='running'`;
    const ready=await master`select platform.mark_isolated_tenant_ready(
      ${tenantId}::uuid,${actorId}::uuid,${databaseName},'neon-v1.0.0-r42-parity',''
    ) result`;

    return {ok:true,databaseName,initialized:(initialized[0] as any)?.result,health,control:(ready[0] as any)?.result};
  }catch(e:any){
    await master`update platform.provisioning_jobs set status='failed',stage='failed',last_error=${String(e?.message||e).slice(0,1000)},updated_at=now() where tenant_id=${tenantId}::uuid and status<>'cancelled'`;
    await master`update platform.tenant_control set database_state='failed',release_status='unhealthy',updated_at=now() where tenant_id=${tenantId}::uuid`;
    throw e;
  }
}
