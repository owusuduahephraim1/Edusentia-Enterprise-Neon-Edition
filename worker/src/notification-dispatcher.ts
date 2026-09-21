import type { Env } from "./types";
import { db } from "./db";
import { tenantDb } from "./tenant-db";

type NotificationJob={
  id:string;
  channel:string;
  recipient_email:string|null;
  payload:Record<string,unknown>|null;
};

function cleanSubject(value:unknown){
  return String(value??"Edusentia").replace(/[\r\n]+/g," ").trim().slice(0,200)||"Edusentia";
}
function cleanBody(value:unknown){return String(value??"").slice(0,100000);}

async function complete(sql:any,jobId:string,workerId:string,success:boolean,errorText=""){
  const rows=await sql`select public.complete_notification_job(
    ${jobId}::uuid,${workerId},${success},${errorText.slice(0,2000)}
  ) completed`;
  return Boolean((rows[0] as any)?.completed);
}

async function dispatchTenant(env:Env,databaseName:string){
  const sql=tenantDb(env,databaseName);
  const [snapshotRows,featureRows]=await Promise.all([
    sql`select public.license_snapshot_for_role('system_admin') result`,
    sql`select public.license_feature_enabled('notifications') enabled`
  ]);
  const snapshot=(snapshotRows[0] as any)?.result||{};
  if(snapshot.write_allowed!==true)return {processed:0,failed:0,disabled:true,reason:String(snapshot.warning||"licence_write_disabled")};
  if((featureRows[0] as any)?.enabled!==true)return {processed:0,failed:0,disabled:true,reason:"notifications_not_licensed"};

  const workerId=crypto.randomUUID();
  const claimed=await sql`select to_jsonb(q) job from public.claim_notification_jobs(50,${workerId}) q`;
  let processed=0,failed=0;
  for(const row of claimed as any[]){
    const job=(row?.job||{}) as NotificationJob;
    try{
      if(job.channel!=="email"||!job.recipient_email)throw new Error("Unsupported or incomplete notification channel");
      const response=await fetch("https://api.resend.com/emails",{
        method:"POST",
        headers:{
          "authorization":`Bearer ${env.RESEND_API_KEY}`,
          "content-type":"application/json",
          "idempotency-key":`edusentia-notification-${job.id}`
        },
        body:JSON.stringify({
          from:env.EMAIL_FROM,
          to:[job.recipient_email],
          subject:cleanSubject(job.payload?.title),
          text:cleanBody(job.payload?.body)
        })
      });
      if(!response.ok)throw new Error(`Email provider returned ${response.status}`);
      if(!(await complete(sql,job.id,workerId,true)))throw new Error("Notification lock ownership changed");
      processed++;
    }catch(e:any){
      await complete(sql,job.id,workerId,false,String(e?.message||e));
      failed++;
    }
  }
  return {processed,failed,disabled:false};
}

export async function dispatchScheduledNotifications(env:Env){
  if(!env.RESEND_API_KEY||!env.EMAIL_FROM){
    console.log(JSON.stringify({level:"info",service:"notification-dispatcher",disabled:true,reason:"email_provider_not_configured"}));
    return {processed:0,failed:0,tenants:0,disabled:true};
  }

  const master=db(env);
  const rows=await master`
    select tenant_code,database_name
      from platform.tenant_control
     where status='active'
       and database_state='isolated_ready'
       and database_name is not null
     order by tenant_code
     limit 500
  `;

  let processed=0,failed=0,tenantFailures=0;
  const tenants=rows as any[];
  for(let offset=0;offset<tenants.length;offset+=10){
    const batch=tenants.slice(offset,offset+10);
    const results=await Promise.allSettled(batch.map(async t=>{
      const result=await dispatchTenant(env,String(t.database_name));
      return {tenantCode:String(t.tenant_code),...result};
    }));
    for(const result of results){
      if(result.status==="fulfilled"){
        processed+=Number(result.value.processed||0);
        failed+=Number(result.value.failed||0);
      }else{
        tenantFailures++;
        console.error(JSON.stringify({level:"error",service:"notification-dispatcher",message:String(result.reason?.message||result.reason)}));
      }
    }
  }
  const summary={processed,failed,tenantFailures,tenants:tenants.length,disabled:false};
  console.log(JSON.stringify({level:"info",service:"notification-dispatcher",...summary}));
  return summary;
}
