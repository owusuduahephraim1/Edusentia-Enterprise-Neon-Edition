import type { Env, SessionContext } from "./types";
import type { TenantSql } from "./tenant-db";
import { tenantTx } from "./db";
import { normalizeRecoveryCode, recoveryCodeHash } from "./mfa";

const ALPHABET="ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const REGEN_COOLDOWN_MS=60_000;

function fail(message:string,code="recovery_failed",status=400):never{
  throw Object.assign(new Error(message),{code,status});
}
function requireAdministrator(ctx:SessionContext){
  if(ctx.role!=="system_admin")fail("School System Administrator access required","forbidden",403);
}
function certifiedCode(){
  const bytes=new Uint8Array(10);crypto.getRandomValues(bytes);
  const raw=Array.from(bytes,b=>ALPHABET[b%ALPHABET.length]).join("");
  return `EDS-${raw.slice(0,5)}-${raw.slice(5,10)}`;
}
async function audit(sql:TenantSql,ctx:SessionContext,action:string,details:Record<string,unknown>){
  await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select audit.record_auth_event(${ctx.tenantId}::uuid,${ctx.userId}::uuid,${action},${JSON.stringify(details)}::jsonb)`
  ]);
}
async function activeGeneration(sql:TenantSql,ctx:SessionContext){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`
    select generation_id,min(created_at) created_at,max(expires_at) expires_at,count(*)::int unused_count
      from authn.mfa_recovery_codes
     where user_id=${ctx.userId}::uuid
       and used_at is null
       and expires_at>now()
     group by generation_id
     order by min(created_at) desc
     limit 1
  `]);
  return ((rows as any[])?.[0]||null) as any;
}
async function issue(env:Env,sql:TenantSql,ctx:SessionContext,force:boolean){
  if(ctx.assuranceLevel<2)fail("A verified MFA session is required","aal2_required",403);
  const active=await activeGeneration(sql,ctx);
  if(active&&!force){
    return {ok:true,codes:[],existing_generation:true,generation_id:active.generation_id,expires_at:active.expires_at,unused_count:Number(active.unused_count||0)};
  }
  if(active&&force){
    const age=Date.now()-Date.parse(String(active.created_at||""));
    if(Number.isFinite(age)&&age>=0&&age<REGEN_COOLDOWN_MS){
      fail("Recovery codes were regenerated too recently","recovery_codes_regeneration_too_soon",429);
    }
  }

  const generationId=crypto.randomUUID(),expiresAt=new Date(Date.now()+365*86400000).toISOString();
  const codes:string[]=[];
  const hashes:string[]=[];
  while(codes.length<8){
    const code=certifiedCode(),hash=await recoveryCodeHash(env,code);
    if(!hashes.includes(hash)){codes.push(code);hashes.push(hash);}
  }
  const queries:any[]=[sql`delete from authn.mfa_recovery_codes where user_id=${ctx.userId}::uuid`];
  for(const hash of hashes){
    queries.push(sql`insert into authn.mfa_recovery_codes(user_id,code_hash,generation_id,expires_at)
      values(${ctx.userId}::uuid,${hash},${generationId}::uuid,${expiresAt}::timestamptz)`);
  }
  await sql.transaction(queries);
  await audit(sql,ctx,"auth.mfa.recovery_codes_issued",{generation_id:generationId,count:8,expires_at:expiresAt,forced_regeneration:force});
  return {ok:true,codes,generation_id:generationId,expires_at:expiresAt,regenerated:force};
}
async function redeem(env:Env,sql:TenantSql,ctx:SessionContext,raw:string){
  const normalized=normalizeRecoveryCode(raw);
  if(![12,13].includes(normalized.length))fail("Recovery code is invalid","recovery_code_invalid",400);
  const hash=await recoveryCodeHash(env,normalized);
  const rows=await sql`
    with claimed as (
      update authn.mfa_recovery_codes
         set used_at=now()
       where user_id=${ctx.userId}::uuid
         and code_hash=${hash}
         and used_at is null
         and expires_at>now()
      returning generation_id
    ),
    removed_factors as (
      delete from authn.mfa_totp_factors
       where user_id=${ctx.userId}::uuid
         and exists(select 1 from claimed)
      returning id
    ),
    invalidated_codes as (
      delete from authn.mfa_recovery_codes
       where user_id=${ctx.userId}::uuid
         and exists(select 1 from claimed)
      returning id
    )
    select
      (select generation_id from claimed limit 1) generation_id,
      (select count(*)::int from removed_factors) removed_factors,
      (select count(*)::int from invalidated_codes) invalidated_codes
  `;
  const row=(rows[0]||{}) as any;
  if(!row.generation_id)fail("Recovery code is invalid, expired, or already used","recovery_code_invalid_or_used",400);
  await audit(sql,ctx,"auth.mfa.recovery_code_redeemed",{
    generation_id:row.generation_id,
    removed_factors:Number(row.removed_factors||0),
    invalidated_codes:Number(row.invalidated_codes||0),
    reenrolment_required:true
  });
  return {ok:true,mfa_reset:true,removed_factors:Number(row.removed_factors||0),reenrolment_required:true,recovery_generation_invalidated:true};
}

export async function handleTenantAuthRecovery(env:Env,sql:TenantSql,ctx:SessionContext,body:Record<string,unknown>){
  requireAdministrator(ctx);
  const action=String(body.action||"");
  if(action==="issue_recovery_codes")return issue(env,sql,ctx,body.force_regenerate===true);
  if(action==="redeem_recovery_code")return redeem(env,sql,ctx,String(body.recovery_code||""));
  if(action==="record_password_recovery"){
    await audit(sql,ctx,"auth.password.recovery_completed",{source:"tenant-auth-recovery"});
    return {ok:true,recorded:true};
  }
  fail("Unsupported recovery action","unsupported_action",400);
}
