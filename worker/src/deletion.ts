import { neon } from "@neondatabase/serverless";
import type { Env } from "./types";
import { db } from "./db";
import { validateDatabaseName } from "./tenant-db";

function ident(value:string){
  const v=validateDatabaseName(value);
  return '"'+v.replaceAll('"','""')+'"';
}
async function raw(sql:any,text:string){return sql.query(text,[]);}

async function deleteTenantDatabase(env:Env,databaseName:string){
  if(!env.PROVISIONER_DATABASE_URL)throw Object.assign(new Error("Tenant provisioner is not configured"),{code:"provisioner_not_configured",status:503});
  const template=String(env.TENANT_TEMPLATE_DATABASE||"edusentia_tenant_template");
  const name=validateDatabaseName(databaseName);
  if(name===template)throw Object.assign(new Error("The tenant template database cannot be deleted"),{code:"protected_database",status:409});
  const provisioner=neon(env.PROVISIONER_DATABASE_URL);
  const rows=await provisioner`select 1 as ok from pg_database where datname=${name}`;
  if(!rows[0])return {deleted:false,alreadyMissing:true};
  await raw(provisioner,`drop database ${ident(name)} with (force)`);
  return {deleted:true,alreadyMissing:false};
}

async function deleteTenantObjects(env:Env,tenantId:string){
  const prefix=`tenants/${tenantId}/`;
  let cursor:string|undefined,total=0;
  do{
    const listed=await env.OBJECTS.list({prefix,cursor,limit:1000});
    const keys=listed.objects.map(object=>object.key);
    if(keys.length){await env.OBJECTS.delete(keys);total+=keys.length;}
    cursor=listed.truncated?listed.cursor:undefined;
  }while(cursor);
  return {deletedObjects:total,prefix};
}

export async function deleteIsolatedTenant(env:Env,tenantId:string,actorId:string,confirmation:string,reason:string){
  const master=db(env);
  const preparedRows=await master`select platform.prepare_school_deletion(${tenantId}::uuid,${actorId}::uuid,${confirmation},${reason}) result`;
  const job=(preparedRows[0] as any)?.result||{};
  const jobId=String(job.job_id||"");
  if(!jobId)throw new Error("Deletion job could not be created");
  await master`select platform.mark_school_deletion_stage(${jobId}::uuid,${actorId}::uuid,'running','')`;
  try{
    const database=await deleteTenantDatabase(env,String(job.database_name));
    await master`select platform.mark_school_deletion_stage(${jobId}::uuid,${actorId}::uuid,'database_deleted','')`;
    const storage=await deleteTenantObjects(env,tenantId);
    await master`select platform.mark_school_deletion_stage(${jobId}::uuid,${actorId}::uuid,'r2_deleted','')`;
    const finalRows=await master`select platform.finalize_school_deletion(${jobId}::uuid,${actorId}::uuid) result`;
    return {ok:true,...((finalRows[0] as any)?.result||{}),database,storage};
  }catch(e:any){
    try{await master`select platform.mark_school_deletion_stage(${jobId}::uuid,${actorId}::uuid,'failed',${String(e?.message||e).slice(0,1900)})`;}catch{}
    throw e;
  }
}
