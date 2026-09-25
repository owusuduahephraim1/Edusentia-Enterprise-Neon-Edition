import type { Env, PlatformSessionContext } from "./types";
import { db } from "./db";
import { cookieValue } from "./http";
import { randomToken, sha256Hex, verifyPassword } from "./crypto";
import { decryptTotpSecret, encryptTotpSecret, generateRecoveryCodes, generateTotpSecret, normalizeRecoveryCode, otpauthUri, recoveryCodeHash, verifyTotp } from "./mfa";

const COOKIE_DEFAULT="__Host-edusentia_platform_session";
export function platformCookieName(env:Env){return env.PLATFORM_SESSION_COOKIE_NAME||COOKIE_DEFAULT;}
export function clearPlatformCookie(env:Env){return `${platformCookieName(env)}=; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=0`;}
export function setPlatformCookie(env:Env,token:string){const ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800));return `${platformCookieName(env)}=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=${ttl}`;}

async function challengeHash(env:Env,token:string){return sha256Hex(`edusentia:platform-mfa-challenge:v1:${token}:${env.SESSION_PEPPER}`);}
async function sessionHash(env:Env,token:string){return sha256Hex(`edusentia:platform-session:v1:${token}:${env.SESSION_PEPPER}`);}

export async function platformLogin(env:Env,emailRaw:string,password:string){
  const email=String(emailRaw||"").trim().toLowerCase();
  if(!email||!password)throw Object.assign(new Error("Email and password are required"),{code:"invalid_credentials",status:400});
  const sql=db(env);
  const rows=await sql`select * from platform.lookup_admin_login(${email})`;
  const row=rows[0] as any;
  if(!row||row.disabled_at||row.active!==true||row.role!=="platform_super_admin"||row.mfa_required!==true||!(await verifyPassword(password,row.password_salt,row.password_hash))){
    throw Object.assign(new Error("The email or password is incorrect"),{code:"invalid_credentials",status:401});
  }

  await sql`update platform.admin_login_challenges set used_at=coalesce(used_at,now()) where user_id=${row.user_id}::uuid and used_at is null`;
  const verified=await sql`select id from authn.mfa_totp_factors where user_id=${row.user_id}::uuid and verified_at is not null and disabled_at is null order by verified_at desc limit 1`;
  let factorId:string,mode:"enroll"|"verify",setup:undefined|{secret:string;otpauthUri:string};
  if(verified[0]){factorId=String((verified[0] as any).id);mode="verify";}
  else{
    await sql`delete from authn.mfa_totp_factors where user_id=${row.user_id}::uuid and verified_at is null and disabled_at is null`;
    const secret=generateTotpSecret(),ciphertext=await encryptTotpSecret(env,secret);
    const created=await sql`insert into authn.mfa_totp_factors(user_id,secret_ciphertext) values(${row.user_id}::uuid,${ciphertext}) returning id`;
    factorId=String((created[0] as any).id);mode="enroll";setup={secret,otpauthUri:otpauthUri(secret,row.email,"Edusentia Platform Administration")};
  }
  const token=randomToken(32),hash=await challengeHash(env,token);
  await sql`insert into platform.admin_login_challenges(user_id,factor_id,purpose,token_hash,expires_at) values(${row.user_id}::uuid,${factorId}::uuid,${mode==="enroll"?"mfa_enroll":"mfa_verify"},${hash},now()+interval '5 minutes')`;
  await sql`insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(${row.user_id}::uuid,'platform.auth.password_verified','platform_admin',${row.user_id}::text,${JSON.stringify({mfa:mode})}::jsonb)`;
  return {mfaRequired:true,mode,challengeToken:token,expiresInSeconds:300,setup};
}

export async function completePlatformMfa(env:Env,challengeTokenRaw:string,codeRaw:string){
  const challengeToken=String(challengeTokenRaw||"").trim(),code=String(codeRaw||"").trim();
  if(!challengeToken||!code)throw Object.assign(new Error("MFA challenge and verification code are required"),{code:"mfa_invalid",status:400});
  const sql=db(env),hash=await challengeHash(env,challengeToken);
  const rows=await sql`
    select c.id,c.user_id,c.factor_id,c.purpose,c.attempts,u.email,u.display_name,a.role,a.active,a.mfa_required
      from platform.admin_login_challenges c
      join authn.users u on u.id=c.user_id
      join platform.admins a on a.user_id=c.user_id
     where c.token_hash=${hash} and c.used_at is null and c.expires_at>now() and u.disabled_at is null
     limit 1`;
  const row=rows[0] as any;
  if(!row||row.active!==true||row.role!=="platform_super_admin"||row.mfa_required!==true)throw Object.assign(new Error("The MFA challenge is invalid or has expired"),{code:"mfa_challenge_expired",status:401});
  if(Number(row.attempts)>=5)throw Object.assign(new Error("Too many verification attempts. Sign in again."),{code:"mfa_attempts_exceeded",status:429});
  const factors=await sql`select id,secret_ciphertext,disabled_at from authn.mfa_totp_factors where id=${row.factor_id}::uuid and user_id=${row.user_id}::uuid limit 1`;
  const factor=factors[0] as any;
  if(!factor||factor.disabled_at)throw Object.assign(new Error("The MFA factor is unavailable"),{code:"mfa_factor_unavailable",status:401});

  let valid=false,recoveryId:string|undefined;
  if(/^\d{6}$/.test(code)){valid=await verifyTotp(await decryptTotpSecret(env,String(factor.secret_ciphertext)),code);}
  else if(row.purpose==="mfa_verify"){
    const normalized=normalizeRecoveryCode(code);
    if(normalized.length===12){
      const recoveryHash=await recoveryCodeHash(env,normalized);
      const recovery=await sql`select id from authn.mfa_recovery_codes where user_id=${row.user_id}::uuid and code_hash=${recoveryHash} and used_at is null limit 1`;
      if(recovery[0]){valid=true;recoveryId=String((recovery[0] as any).id);}
    }
  }
  if(!valid){
    await sql`update platform.admin_login_challenges set attempts=least(attempts+1,10) where id=${row.id}::uuid`;
    throw Object.assign(new Error("The verification code is incorrect"),{code:"mfa_invalid_code",status:401});
  }

  const token=randomToken(32),tokenHash=await sessionHash(env,token),ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800)),sessionId=crypto.randomUUID();
  const recoveryCodes=row.purpose==="mfa_enroll"?generateRecoveryCodes(8):[];
  const recoveryHashes=await Promise.all(recoveryCodes.map(c=>recoveryCodeHash(env,c)));
  const queries:any[]=[sql`update platform.admin_login_challenges set used_at=now() where id=${row.id}::uuid and used_at is null`];
  if(row.purpose==="mfa_enroll"){
    queries.push(sql`update authn.mfa_totp_factors set verified_at=coalesce(verified_at,now()) where id=${row.factor_id}::uuid and disabled_at is null`);
    queries.push(sql`delete from authn.mfa_recovery_codes where user_id=${row.user_id}::uuid`);
    for(const h of recoveryHashes)queries.push(sql`insert into authn.mfa_recovery_codes(user_id,code_hash) values(${row.user_id}::uuid,${h})`);
  }else if(recoveryId)queries.push(sql`update authn.mfa_recovery_codes set used_at=now() where id=${recoveryId}::uuid and used_at is null`);
  queries.push(sql`insert into platform.admin_sessions(id,user_id,token_hash,assurance_level,expires_at) values(${sessionId}::uuid,${row.user_id}::uuid,${tokenHash},2,now()+(${ttl}::text||' seconds')::interval)`);
  queries.push(sql`insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(${row.user_id}::uuid,'platform.auth.login_success','platform_admin',${row.user_id}::text,'{"aal":2,"mfa":"totp"}'::jsonb)`);
  await sql.transaction(queries);
  return {token,recoveryCodes,session:{authenticated:true,user:{id:row.user_id,email:row.email,displayName:row.display_name},platform:{role:"platform_super_admin",roleLabel:"Platform Super Administrator"},session:{id:sessionId,assuranceLevel:2}}};
}

function platformRequestTokens(request:Request,env:Env){
  const tokens:string[]=[];
  const authorization=String(request.headers.get("authorization")||"").trim();
  const bearer=authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim()||"";
  if(bearer)tokens.push(bearer);
  const cookie=cookieValue(request,platformCookieName(env));
  if(cookie&&!tokens.includes(cookie))tokens.push(cookie);
  return tokens.slice(0,2);
}

export async function authenticatePlatform(request:Request,env:Env):Promise<PlatformSessionContext|null>{
  const tokens=platformRequestTokens(request,env);if(!tokens.length)return null;
  const sql=db(env);
  for(const token of tokens){
    const hash=await sessionHash(env,token);
    const rows=await sql`
      select s.id session_id,s.user_id,s.assurance_level,u.email,u.display_name,a.role
        from platform.admin_sessions s
        join authn.users u on u.id=s.user_id
        join platform.admins a on a.user_id=s.user_id
       where s.token_hash=${hash} and s.revoked_at is null and s.expires_at>now()
         and u.disabled_at is null and a.active=true and a.role='platform_super_admin' and a.mfa_required=true and s.assurance_level>=2
       limit 1`;
    const row=rows[0] as any;
    if(!row)continue;
    await sql`update platform.admin_sessions set last_seen_at=now() where id=${row.session_id}::uuid`;
    return {sessionId:row.session_id,userId:row.user_id,role:"platform_super_admin",assuranceLevel:Number(row.assurance_level),email:row.email,displayName:row.display_name};
  }
  return null;
}
export async function logoutPlatform(request:Request,env:Env){
  const tokens=platformRequestTokens(request,env);if(!tokens.length)return;
  const sql=db(env);
  for(const token of tokens){
    const hash=await sessionHash(env,token);
    await sql`update platform.admin_sessions set revoked_at=coalesce(revoked_at,now()) where token_hash=${hash}`;
  }
}
