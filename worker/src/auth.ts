import type { Env, SessionContext } from "./types";
import { db } from "./db";
import { cookieValue } from "./http";
import { randomToken, sha256Hex, verifyPassword } from "./crypto";
import { tenantDb, routedToken, tokenTenantCode } from "./tenant-db";
import { decryptTotpSecret, encryptTotpSecret, generateRecoveryCodes, generateTotpSecret, normalizeRecoveryCode, otpauthUri, recoveryCodeHash, verifyTotp } from "./mfa";

const COOKIE_DEFAULT="__Host-edusentia_session";
export function sessionCookieName(env:Env){return env.SESSION_COOKIE_NAME||COOKIE_DEFAULT;}
export function clearCookie(env:Env){return `${sessionCookieName(env)}=; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=0`;}
export function setCookie(env:Env,token:string){const ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800));return `${sessionCookieName(env)}=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=${ttl}`;}
function privilegedRoleRequiresMfa(role:unknown){return ["system_admin","platform_super_admin"].includes(String(role||"").trim());}

async function routeForLogin(env:Env,email:string,tenantCode:string){
  const master=db(env);
  const rows=await master`select * from platform.resolve_login_route(${email},${tenantCode||null})`;
  if(!rows.length)throw Object.assign(new Error("The email or institution could not be found"),{code:"invalid_credentials",status:401});
  if(rows.length>1&&!tenantCode)throw Object.assign(new Error("This email belongs to more than one school. Enter the institution code."),{code:"tenant_selection_required",status:409});
  return rows[0] as any;
}
async function routeForCode(env:Env,tenantCode:string){
  const master=db(env);
  const rows=await master`select tenant_id,tenant_code,school_name,database_name from platform.tenant_control where upper(tenant_code)=upper(${tenantCode}) and status='active' and database_state='isolated_ready' limit 1`;
  const row=rows[0] as any;
  if(!row)throw Object.assign(new Error("The school workspace is unavailable"),{code:"tenant_unavailable",status:503});
  return row;
}
async function issueSession(env:Env,sql:any,row:any,assuranceLevel:number){
  const opaque=randomToken(32),token=routedToken(String(row.tenant_code),opaque),tokenHash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`);
  const ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800)),sessionId=crypto.randomUUID();
  await sql`insert into authn.sessions(id,user_id,tenant_id,token_hash,role,assurance_level,expires_at) values(${sessionId}::uuid,${row.user_id}::uuid,${row.tenant_id}::uuid,${tokenHash},${row.role},${assuranceLevel},now()+(${ttl}::text||' seconds')::interval)`;
  return {token,session:{authenticated:true,user:{id:row.user_id,email:row.email,displayName:row.display_name},membership:{tenantId:row.tenant_id,tenantCode:row.tenant_code,tenantName:row.tenant_name,role:row.role,roleLabel:String(row.role).replaceAll('_',' ')},session:{id:sessionId,assuranceLevel}}};
}
async function challengeHash(token:string){return sha256Hex(`edusentia:mfa-challenge:v2:${token}`);}

export async function login(env:Env,emailRaw:string,password:string,tenantCodeRaw:string){
  const email=String(emailRaw||"").trim().toLowerCase(),tenantCode=String(tenantCodeRaw||"").trim().toUpperCase();
  if(!email||!password)throw Object.assign(new Error("Email and password are required"),{code:"invalid_credentials",status:400});
  const route=await routeForLogin(env,email,tenantCode),sql=tenantDb(env,String(route.database_name));
  const rows=await sql`select * from authn.lookup_login(${email},${String(route.tenant_code)})`;
  const row=rows[0] as any;
  if(!row||row.disabled_at||row.status!=="active"||!(await verifyPassword(password,row.password_salt,row.password_hash))){
    await sql`select audit.record_auth_event(null,null,'auth.login.failed',${JSON.stringify({email,tenantCode:route.tenant_code})}::jsonb)`;
    throw Object.assign(new Error("The email or password is incorrect"),{code:"invalid_credentials",status:401});
  }
  if(!row.mfa_required){
    if(!privilegedRoleRequiresMfa(row.role)){
      const issued=await issueSession(env,sql,row,1);
      await sql`select audit.record_auth_event(${row.tenant_id}::uuid,${row.user_id}::uuid,'auth.login.success','{"aal":1}'::jsonb)`;
      return {mfaRequired:false,...issued};
    }
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
  const challengeToken=routedToken(String(row.tenant_code),randomToken(32)),hash=await challengeHash(challengeToken);
  await sql`insert into authn.login_challenges(user_id,tenant_id,factor_id,purpose,token_hash,expires_at) values(${row.user_id}::uuid,${row.tenant_id}::uuid,${factorId}::uuid,${mode==="enroll"?"mfa_enroll":"mfa_verify"},${hash},now()+interval '5 minutes')`;
  await sql`select audit.record_auth_event(${row.tenant_id}::uuid,${row.user_id}::uuid,'auth.login.password_verified',${JSON.stringify({mfa:mode})}::jsonb)`;
  return {mfaRequired:true,mode,challengeToken,expiresInSeconds:300,tenant:{code:row.tenant_code,name:row.tenant_name},setup};
}

export async function completeMfa(env:Env,challengeTokenRaw:string,codeRaw:string){
  const challengeToken=String(challengeTokenRaw||"").trim(),code=String(codeRaw||"").trim(),tenantCode=tokenTenantCode(challengeToken);
  if(!challengeToken||!code||!tenantCode)throw Object.assign(new Error("MFA challenge and verification code are required"),{code:"mfa_invalid",status:400});
  const route=await routeForCode(env,tenantCode),sql=tenantDb(env,String(route.database_name)),hash=await challengeHash(challengeToken);
  const challengeRows=await sql`
    select id,user_id,tenant_id,factor_id,purpose,attempts,used_at,expires_at,(used_at is null and expires_at>now()) active
      from authn.login_challenges
     where token_hash=${hash}
     limit 1`;
  const challenge=challengeRows[0] as any;
  if(!challenge||!challenge.active)throw Object.assign(new Error("The MFA challenge is invalid or has expired"),{code:"mfa_challenge_expired",status:401});
  if(Number(challenge.attempts)>=5)throw Object.assign(new Error("Too many verification attempts. Sign in again."),{code:"mfa_attempts_exceeded",status:429});

  const [,contextRows]=await sql.transaction([
    sql`select app.set_request_context(${challenge.tenant_id}::uuid,${challenge.user_id}::uuid,'mfa_pending'::text,1::smallint)`,
    sql`
      select u.email,u.display_name,t.code tenant_code,t.name tenant_name,m.role,m.status
        from authn.users u
        join app.tenants t on t.id=${challenge.tenant_id}::uuid
        join app.tenant_memberships m on m.user_id=u.id and m.tenant_id=${challenge.tenant_id}::uuid
       where u.id=${challenge.user_id}::uuid and u.disabled_at is null
       limit 1`
  ]);
  const context=contextRows[0] as any;
  if(!context||context.status!=="active")throw Object.assign(new Error("The MFA challenge is invalid or has expired"),{code:"mfa_challenge_expired",status:401});
  const row={...challenge,...context};
  const factors=await sql`select id,secret_ciphertext,disabled_at from authn.mfa_totp_factors where id=${row.factor_id}::uuid and user_id=${row.user_id}::uuid limit 1`;
  const factor=factors[0] as any;
  if(!factor||factor.disabled_at)throw Object.assign(new Error("The MFA factor is unavailable"),{code:"mfa_factor_unavailable",status:401});

  let valid=false,recoveryId:string|undefined;
  if(/^\d{6}$/.test(code)){valid=await verifyTotp(await decryptTotpSecret(env,String(factor.secret_ciphertext)),code);}
  else if(row.purpose==="mfa_verify"){
    const normalized=normalizeRecoveryCode(code);
    if([12,13].includes(normalized.length)){
      const recoveryHash=await recoveryCodeHash(env,normalized);
      const recovery=await sql`select id from authn.mfa_recovery_codes
        where user_id=${row.user_id}::uuid and code_hash=${recoveryHash}
          and used_at is null and expires_at>now()
        limit 1`;
      if(recovery[0]){valid=true;recoveryId=String((recovery[0] as any).id);}
    }
  }
  if(!valid){
    await sql`update authn.login_challenges set attempts=least(attempts+1,10) where id=${row.id}::uuid`;
    throw Object.assign(new Error("The verification code is incorrect"),{code:"mfa_invalid_code",status:401});
  }

  const opaque=randomToken(32),sessionToken=routedToken(String(row.tenant_code),opaque),sessionHash=await sha256Hex(`${sessionToken}.${env.SESSION_PEPPER}`);
  const ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800)),sessionId=crypto.randomUUID(),recoveryCodes=row.purpose==="mfa_enroll"?generateRecoveryCodes(8):[];
  const recoveryHashes=await Promise.all(recoveryCodes.map(c=>recoveryCodeHash(env,c))),generationId=crypto.randomUUID(),expiresAt=new Date(Date.now()+365*86400000).toISOString(),queries:any[]=[sql`update authn.login_challenges set used_at=now() where id=${row.id}::uuid and used_at is null`];
  if(row.purpose==="mfa_enroll"){
    queries.push(sql`update authn.mfa_totp_factors set verified_at=coalesce(verified_at,now()) where id=${row.factor_id}::uuid and disabled_at is null`);
    queries.push(sql`delete from authn.mfa_recovery_codes where user_id=${row.user_id}::uuid`);
    for(const h of recoveryHashes)queries.push(sql`insert into authn.mfa_recovery_codes(user_id,code_hash,generation_id,expires_at) values(${row.user_id}::uuid,${h},${generationId}::uuid,${expiresAt}::timestamptz)`);
  }else if(recoveryId){
    queries.push(sql`delete from authn.mfa_totp_factors where user_id=${row.user_id}::uuid`);
    queries.push(sql`delete from authn.mfa_recovery_codes where user_id=${row.user_id}::uuid`);
  }
  queries.push(sql`insert into authn.sessions(id,user_id,tenant_id,token_hash,role,assurance_level,expires_at) values(${sessionId}::uuid,${row.user_id}::uuid,${row.tenant_id}::uuid,${sessionHash},${row.role},2,now()+(${ttl}::text||' seconds')::interval)`);
  await sql.transaction(queries);
  return {token:sessionToken,recoveryCodes,session:{authenticated:true,user:{id:row.user_id,email:row.email,displayName:row.display_name},membership:{tenantId:row.tenant_id,tenantCode:row.tenant_code,tenantName:row.tenant_name,role:row.role,roleLabel:String(row.role).replaceAll('_',' ')},session:{id:sessionId,assuranceLevel:2}}};
}

export async function authenticate(request:Request,env:Env):Promise<SessionContext|null>{
  const token=cookieValue(request,sessionCookieName(env)),tenantCode=tokenTenantCode(token||"");
  if(!token||!tenantCode)return null;
  let route:any;try{route=await routeForCode(env,tenantCode);}catch{return null;}
  const hash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`),sql=tenantDb(env,String(route.database_name));
  const sessionRows=await sql`
    select s.id session_id,s.user_id,s.tenant_id,s.role,s.assurance_level,u.email,u.display_name
      from authn.sessions s
      join authn.users u on u.id=s.user_id
     where s.token_hash=${hash} and s.revoked_at is null and s.expires_at>now() and u.disabled_at is null
     limit 1`;
  const session=sessionRows[0] as any;
  if(!session||String(session.tenant_id)!==String(route.tenant_id))return null;

  const [,contextRows]=await sql.transaction([
    sql`select app.set_request_context(${session.tenant_id}::uuid,${session.user_id}::uuid,${String(session.role)}::text,${Number(session.assurance_level)}::smallint)`,
    sql`
      select t.code tenant_code,t.name tenant_name,m.role,m.status,m.mfa_required
        from app.tenants t
        join app.tenant_memberships m on m.tenant_id=t.id and m.user_id=${session.user_id}::uuid
       where t.id=${session.tenant_id}::uuid
       limit 1`
  ]);
  const context=contextRows[0] as any;
  if(!context||context.status!=="active"||(context.mfa_required&&Number(session.assurance_level)<2)||(privilegedRoleRequiresMfa(context.role)&&Number(session.assurance_level)<2))return null;
  const assuranceLevel=Number(session.assurance_level);
  return {sessionId:session.session_id,userId:session.user_id,tenantId:session.tenant_id,tenantCode:context.tenant_code,tenantName:context.tenant_name,databaseName:String(route.database_name),role:context.role,assuranceLevel,email:session.email,displayName:session.display_name};
}
export async function logout(request:Request,env:Env){
  const token=cookieValue(request,sessionCookieName(env)),tenantCode=tokenTenantCode(token||"");if(!token||!tenantCode)return;
  let route:any;try{route=await routeForCode(env,tenantCode);}catch{return;}
  const hash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`);
  await tenantDb(env,String(route.database_name))`update authn.sessions set revoked_at=coalesce(revoked_at,now()) where token_hash=${hash}`;
}
