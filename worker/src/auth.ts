import type { Env, SessionContext } from "./types";
import { db } from "./db";
import { cookieValue } from "./http";
import { randomToken, sha256Hex, verifyPassword } from "./crypto";
import { decryptTotpSecret, encryptTotpSecret, generateRecoveryCodes, generateTotpSecret, normalizeRecoveryCode, otpauthUri, recoveryCodeHash, verifyTotp } from "./mfa";

const COOKIE_DEFAULT="__Host-edusentia_session";
export function sessionCookieName(env:Env){return env.SESSION_COOKIE_NAME||COOKIE_DEFAULT;}
export function clearCookie(env:Env){return `${sessionCookieName(env)}=; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=0`;}
export function setCookie(env:Env, token:string){const ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800));return `${sessionCookieName(env)}=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=${ttl}`;}

async function issueSession(env:Env,row:any,assuranceLevel:number){
  const token=randomToken(32),tokenHash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`),ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800)),sessionId=crypto.randomUUID(),sql=db(env);
  await sql`insert into authn.sessions(id,user_id,tenant_id,token_hash,role,assurance_level,expires_at) values (${sessionId}::uuid,${row.user_id}::uuid,${row.tenant_id}::uuid,${tokenHash},${row.role},${assuranceLevel},now()+(${ttl}::text||' seconds')::interval)`;
  return {token,session:{authenticated:true,user:{id:row.user_id,email:row.email,displayName:row.display_name},membership:{tenantId:row.tenant_id,tenantCode:row.tenant_code,tenantName:row.tenant_name,role:row.role,roleLabel:String(row.role).replaceAll('_',' ')},session:{id:sessionId,assuranceLevel}}};
}
async function challengeHash(env:Env,token:string){return sha256Hex(`edusentia:mfa-challenge:v1:${token}:${env.SESSION_PEPPER}`);}

export async function login(env:Env,emailRaw:string,password:string,tenantCodeRaw:string){
  const email=String(emailRaw||"").trim().toLowerCase(),tenantCode=String(tenantCodeRaw||"").trim().toUpperCase();
  if(!email||!password||!tenantCode) throw Object.assign(new Error("Email, password and institution code are required"),{code:"invalid_credentials",status:400});
  const sql=db(env);
  const rows=await sql`select * from authn.lookup_login(${email},${tenantCode})`;
  const row=rows[0] as any;
  if(!row || row.disabled_at || row.status!=="active" || !(await verifyPassword(password,row.password_salt,row.password_hash))) {
    await sql`select audit.record_auth_event(null,null,'auth.login.failed',${JSON.stringify({email,tenantCode})}::jsonb)`;
    throw Object.assign(new Error("The email, password or institution code is incorrect"),{code:"invalid_credentials",status:401});
  }
  if(!row.mfa_required){
    const issued=await issueSession(env,row,1);
    await sql`select audit.record_auth_event(${row.tenant_id}::uuid,${row.user_id}::uuid,'auth.login.success','{"aal":1}'::jsonb)`;
    return {mfaRequired:false,...issued};
  }
  await sql`update authn.login_challenges set used_at=coalesce(used_at,now()) where user_id=${row.user_id}::uuid and tenant_id=${row.tenant_id}::uuid and used_at is null`;
  const verified=await sql`select id from authn.mfa_totp_factors where user_id=${row.user_id}::uuid and verified_at is not null and disabled_at is null order by verified_at desc limit 1`;
  let factorId:string,mode:"enroll"|"verify",setup:undefined|{secret:string;otpauthUri:string};
  if(verified[0]){factorId=String((verified[0] as any).id);mode="verify";}
  else{
    await sql`delete from authn.mfa_totp_factors where user_id=${row.user_id}::uuid and verified_at is null and disabled_at is null`;
    const secret=generateTotpSecret(),ciphertext=await encryptTotpSecret(env,secret);
    const created=await sql`insert into authn.mfa_totp_factors(user_id,secret_ciphertext) values(${row.user_id}::uuid,${ciphertext}) returning id`;
    factorId=String((created[0] as any).id);mode="enroll";setup={secret,otpauthUri:otpauthUri(secret,row.email,row.tenant_name)};
  }
  const challengeToken=randomToken(32),hash=await challengeHash(env,challengeToken);
  await sql`insert into authn.login_challenges(user_id,tenant_id,factor_id,purpose,token_hash,expires_at) values(${row.user_id}::uuid,${row.tenant_id}::uuid,${factorId}::uuid,${mode==="enroll"?"mfa_enroll":"mfa_verify"},${hash},now()+interval '5 minutes')`;
  await sql`select audit.record_auth_event(${row.tenant_id}::uuid,${row.user_id}::uuid,'auth.login.password_verified',${JSON.stringify({mfa:mode})}::jsonb)`;
  return {mfaRequired:true,mode,challengeToken,expiresInSeconds:300,setup};
}

export async function completeMfa(env:Env,challengeTokenRaw:string,codeRaw:string){
  const challengeToken=String(challengeTokenRaw||"").trim(),code=String(codeRaw||"").trim();
  if(!challengeToken||!code)throw Object.assign(new Error("MFA challenge and verification code are required"),{code:"mfa_invalid",status:400});
  const sql=db(env),hash=await challengeHash(env,challengeToken);
  const rows=await sql`
    select c.id,c.user_id,c.tenant_id,c.factor_id,c.purpose,c.attempts,c.expires_at,u.email,u.display_name,t.code tenant_code,t.name tenant_name,m.role,m.status
      from authn.login_challenges c
      join authn.users u on u.id=c.user_id
      join app.tenants t on t.id=c.tenant_id
      join app.tenant_memberships m on m.user_id=c.user_id and m.tenant_id=c.tenant_id
     where c.token_hash=${hash} and c.used_at is null and c.expires_at>now() and u.disabled_at is null limit 1`;
  const row=rows[0] as any;
  if(!row||row.status!=="active")throw Object.assign(new Error("The MFA challenge is invalid or has expired"),{code:"mfa_challenge_expired",status:401});
  if(Number(row.attempts)>=5)throw Object.assign(new Error("Too many verification attempts. Sign in again."),{code:"mfa_attempts_exceeded",status:429});
  const factors=await sql`select id,secret_ciphertext,verified_at,disabled_at from authn.mfa_totp_factors where id=${row.factor_id}::uuid and user_id=${row.user_id}::uuid limit 1`;
  const factor=factors[0] as any;
  if(!factor||factor.disabled_at)throw Object.assign(new Error("The MFA factor is unavailable"),{code:"mfa_factor_unavailable",status:401});
  let valid=false,recoveryId:string|undefined;
  if(/^\d{6}$/.test(code)){const secret=await decryptTotpSecret(env,String(factor.secret_ciphertext));valid=await verifyTotp(secret,code);}
  else if(row.purpose==="mfa_verify"){
    const normalized=normalizeRecoveryCode(code);
    if(normalized.length===12){
      const recoveryHash=await recoveryCodeHash(env,normalized);
      const recovery=await sql`select id from authn.mfa_recovery_codes where user_id=${row.user_id}::uuid and code_hash=${recoveryHash} and used_at is null limit 1`;
      if(recovery[0]){valid=true;recoveryId=String((recovery[0] as any).id);}
    }
  }
  if(!valid){
    await sql`update authn.login_challenges set attempts=least(attempts+1,10) where id=${row.id}::uuid`;
    await sql`select audit.record_auth_event(${row.tenant_id}::uuid,${row.user_id}::uuid,'auth.mfa.failed','{}'::jsonb)`;
    throw Object.assign(new Error("The verification code is incorrect"),{code:"mfa_invalid_code",status:401});
  }
  const sessionToken=randomToken(32),sessionHash=await sha256Hex(`${sessionToken}.${env.SESSION_PEPPER}`),ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800)),sessionId=crypto.randomUUID();
  const recoveryCodes=row.purpose==="mfa_enroll"?generateRecoveryCodes(8):[];
  const recoveryHashes=await Promise.all(recoveryCodes.map(c=>recoveryCodeHash(env,c)));
  const queries:any[]=[sql`update authn.login_challenges set used_at=now() where id=${row.id}::uuid and used_at is null`];
  if(row.purpose==="mfa_enroll"){
    queries.push(sql`update authn.mfa_totp_factors set verified_at=coalesce(verified_at,now()) where id=${row.factor_id}::uuid and disabled_at is null`);
    queries.push(sql`delete from authn.mfa_recovery_codes where user_id=${row.user_id}::uuid`);
    for(const h of recoveryHashes)queries.push(sql`insert into authn.mfa_recovery_codes(user_id,code_hash) values(${row.user_id}::uuid,${h})`);
  }else if(recoveryId)queries.push(sql`update authn.mfa_recovery_codes set used_at=now() where id=${recoveryId}::uuid and used_at is null`);
  queries.push(sql`insert into authn.sessions(id,user_id,tenant_id,token_hash,role,assurance_level,expires_at) values(${sessionId}::uuid,${row.user_id}::uuid,${row.tenant_id}::uuid,${sessionHash},${row.role},2,now()+(${ttl}::text||' seconds')::interval)`);
  queries.push(sql`select audit.record_auth_event(${row.tenant_id}::uuid,${row.user_id}::uuid,'auth.login.success','{"aal":2,"mfa":"totp"}'::jsonb)`);
  await sql.transaction(queries);
  return {token:sessionToken,recoveryCodes,session:{authenticated:true,user:{id:row.user_id,email:row.email,displayName:row.display_name},membership:{tenantId:row.tenant_id,tenantCode:row.tenant_code,tenantName:row.tenant_name,role:row.role,roleLabel:String(row.role).replaceAll('_',' ')},session:{id:sessionId,assuranceLevel:2}}};
}

export async function authenticate(request:Request,env:Env):Promise<SessionContext|null>{
  const token=cookieValue(request,sessionCookieName(env)); if(!token)return null;
  const hash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`),sql=db(env);
  const rows=await sql`
    select s.id as session_id,s.user_id,s.tenant_id,s.role,s.assurance_level,u.email,u.display_name
      from authn.sessions s join authn.users u on u.id=s.user_id join app.tenant_memberships m on m.user_id=s.user_id and m.tenant_id=s.tenant_id
     where s.token_hash=${hash} and s.revoked_at is null and s.expires_at>now() and u.disabled_at is null and m.status='active'
       and (not m.mfa_required or s.assurance_level>=2) limit 1`;
  const r=rows[0] as any;if(!r)return null;
  return {sessionId:r.session_id,userId:r.user_id,tenantId:r.tenant_id,role:r.role,assuranceLevel:Number(r.assurance_level),email:r.email,displayName:r.display_name};
}
export async function logout(request:Request,env:Env){const token=cookieValue(request,sessionCookieName(env));if(!token)return;const hash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`);await db(env)`update authn.sessions set revoked_at=coalesce(revoked_at,now()) where token_hash=${hash}`;}
