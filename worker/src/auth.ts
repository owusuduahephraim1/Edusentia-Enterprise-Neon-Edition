import type { Env, SessionContext } from "./types";
import { db } from "./db";
import { cookieValue } from "./http";
import { randomToken, sha256Hex, verifyPassword } from "./crypto";

const COOKIE_DEFAULT="__Host-edusentia_session";
export function sessionCookieName(env:Env){return env.SESSION_COOKIE_NAME||COOKIE_DEFAULT;}
export function clearCookie(env:Env){return `${sessionCookieName(env)}=; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=0`;}
export function setCookie(env:Env, token:string){const ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800));return `${sessionCookieName(env)}=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=None; Partitioned; Max-Age=${ttl}`;}

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
  const token=randomToken(32), tokenHash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`), ttl=Math.max(300,Number(env.SESSION_TTL_SECONDS||28800));
  const created=await sql`
    insert into authn.sessions(user_id,tenant_id,token_hash,role,assurance_level,expires_at)
    values (${row.user_id}::uuid,${row.tenant_id}::uuid,${tokenHash},${row.role},1,now()+(${ttl}::text||' seconds')::interval)
    returning id`;
  await sql`select audit.record_auth_event(${row.tenant_id}::uuid,${row.user_id}::uuid,'auth.login.success','{}'::jsonb)`;
  return {token, session:{authenticated:true,user:{id:row.user_id,email:row.email,displayName:row.display_name},membership:{tenantId:row.tenant_id,tenantCode:row.tenant_code,tenantName:row.tenant_name,role:row.role,roleLabel:row.role.replaceAll('_',' ')},session:{id:(created[0] as any).id,assuranceLevel:1}}};
}

export async function authenticate(request:Request,env:Env):Promise<SessionContext|null>{
  const token=cookieValue(request,sessionCookieName(env)); if(!token)return null;
  const hash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`),sql=db(env);
  const rows=await sql`
    select s.id as session_id,s.user_id,s.tenant_id,s.role,s.assurance_level,u.email,u.display_name
      from authn.sessions s join authn.users u on u.id=s.user_id
     where s.token_hash=${hash} and s.revoked_at is null and s.expires_at>now() and u.disabled_at is null limit 1`;
  const r=rows[0] as any;if(!r)return null;
  return {sessionId:r.session_id,userId:r.user_id,tenantId:r.tenant_id,role:r.role,assuranceLevel:Number(r.assurance_level),email:r.email,displayName:r.display_name};
}
export async function logout(request:Request,env:Env){const token=cookieValue(request,sessionCookieName(env));if(!token)return;const hash=await sha256Hex(`${token}.${env.SESSION_PEPPER}`);await db(env)`update authn.sessions set revoked_at=coalesce(revoked_at,now()) where token_hash=${hash}`;}
