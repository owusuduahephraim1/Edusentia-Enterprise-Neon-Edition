import type { Env, PlatformSessionContext } from "./types";
import { db } from "./db";
import { readJson, json, error } from "./http";
import { passwordHash, randomToken, sha256Hex } from "./crypto";
import { authenticatePlatform, platformLogin, completePlatformMfa, logoutPlatform, setPlatformCookie, clearPlatformCookie } from "./platform-auth";
import { verifyTurnstile } from "./turnstile";

async function authed(request:Request,env:Env){
  const ctx=await authenticatePlatform(request,env);
  if(!ctx)throw Object.assign(new Error("Platform administrator authentication is required"),{code:"unauthenticated",status:401});
  if(ctx.role!=="platform_super_admin"||ctx.assuranceLevel<2)throw Object.assign(new Error("A verified Platform Super Administrator session is required"),{code:"forbidden",status:403});
  return ctx;
}
function uuidPath(path:string,pattern:RegExp){const m=path.match(pattern);return m?.[1]||"";}
function asIso(value:any){const d=new Date(String(value||""));if(Number.isNaN(d.getTime()))throw Object.assign(new Error("A valid date/time is required"),{code:"validation_error",status:422});return d.toISOString();}
async function adminSetupHash(env:Env,token:string){return sha256Hex(`edusentia:tenant-admin-setup:v1:${token}:${env.SESSION_PEPPER}`);}

export async function platformRoute(request:Request,env:Env,requestId:string):Promise<Response|null>{
  const url=new URL(request.url),p=url.pathname,method=request.method.toUpperCase(),sql=db(env);

  if(method==="POST"&&p==="/api/public/school-registration"){
    const b=await readJson<any>(request);
    await verifyTurnstile(env,String(b.turnstileToken||""),request,"school_registration");
    const school=String(b.schoolName||"").trim().slice(0,200),name=String(b.contactName||"").trim().slice(0,160),email=String(b.contactEmail||"").trim().toLowerCase().slice(0,254);
    const phone=String(b.contactPhone||"").trim().slice(0,60),country=String(b.country||"").trim().slice(0,100),institutionType=String(b.institutionType||"basic_jhs").trim().toLowerCase();
    const allowed=new Set(["basic_jhs","senior_high","combined_pretertiary","tertiary"]);
    if(school.length<2||name.length<2||!/^\S+@\S+\.\S+$/.test(email)||!allowed.has(institutionType))return error("invalid_registration","Enter valid school and contact details",422,requestId);
    try{
      const rows=await sql`insert into platform.school_registrations(school_name,contact_name,contact_email,contact_phone,country,requested_plan_code,institution_type,status) values(${school},${name},${email},${phone},${country},'starter',${institutionType},'pending') returning id,status,created_at,requested_plan_code,institution_type`;
      return json({ok:true,registration:rows[0]},201);
    }catch(e:any){
      if(String(e?.code||"")==="23505")return error("registration_already_open","A registration is already open for this contact email",409,requestId);
      throw e;
    }
  }

  if(method==="POST"&&p==="/api/public/admin-setup/inspect"){
    const b=await readJson<any>(request),token=String(b.token||"").trim();
    if(!token||token.length>1024)return error("invalid_setup_token","The administrator setup link is invalid",400,requestId);
    const hash=await adminSetupHash(env,token);
    const rows=await sql`select * from platform.inspect_admin_setup_token(${hash})`;
    const row=rows[0] as any;
    if(!row)return error("setup_token_invalid_or_expired","This administrator setup link is invalid or has expired",410,requestId);
    return json({ok:true,setup:{tenantCode:row.tenant_code,schoolName:row.school_name,adminEmail:row.admin_email,displayName:row.display_name,expiresAt:row.expires_at}});
  }

  if(method==="POST"&&p==="/api/public/admin-setup/complete"){
    const b=await readJson<any>(request),token=String(b.token||"").trim(),password=String(b.password||"");
    await verifyTurnstile(env,String(b.turnstileToken||""),request,"admin_setup");
    if(!token||token.length>1024)return error("invalid_setup_token","The administrator setup link is invalid",400,requestId);
    if(password.length<12)return error("weak_password","Administrator password must contain at least 12 characters",422,requestId);
    const credential=await passwordHash(password),hash=await adminSetupHash(env,token);
    const rows=await sql`select platform.complete_admin_setup(${hash},${credential.hash},${credential.salt}) result`;
    return json((rows[0] as any)?.result||{ok:true});
  }

  if(method==="POST"&&p==="/api/platform/bootstrap/initialize"){
    const supplied=request.headers.get("x-bootstrap-secret")||"";
    const expected=env.PLATFORM_BOOTSTRAP_SECRET||env.BOOTSTRAP_ADMIN_SECRET||"";
    if(!expected||supplied!==expected)return error("bootstrap_denied","Platform bootstrap authorization failed",403,requestId);
    const b=await readJson<any>(request),password=String(b.password||"");
    if(password.length<12)return error("weak_password","Platform administrator password must contain at least 12 characters",422,requestId);
    const credential=await passwordHash(password);
    const rows=await sql`select platform.bootstrap_first_super_admin(${String(b.email||"").trim().toLowerCase()},${String(b.displayName||"").trim()},${credential.hash},${credential.salt}) result`;
    return json({ok:true,result:(rows[0] as any)?.result},201);
  }

  if(method==="POST"&&p==="/api/platform/auth/login"){
    const b=await readJson<any>(request);
    await verifyTurnstile(env,String(b.turnstileToken||""),request,"platform_login");
    return json(await platformLogin(env,b.email,b.password));
  }
  if(method==="POST"&&p==="/api/platform/auth/mfa/complete"){
    const b=await readJson<any>(request),result=await completePlatformMfa(env,b.challengeToken,b.code);
    const r=json({...result.session,recoveryCodes:result.recoveryCodes});r.headers.append("set-cookie",setPlatformCookie(env,result.token));return r;
  }
  if(method==="POST"&&p==="/api/platform/auth/logout"){
    await logoutPlatform(request,env);const r=json({ok:true});r.headers.append("set-cookie",clearPlatformCookie(env));return r;
  }
  if(method==="GET"&&p==="/api/platform/session"){
    const ctx=await authenticatePlatform(request,env);if(!ctx)return json({authenticated:false});
    return json({authenticated:true,user:{id:ctx.userId,email:ctx.email,displayName:ctx.displayName},platform:{role:ctx.role,roleLabel:"Platform Super Administrator"},session:{id:ctx.sessionId,assuranceLevel:ctx.assuranceLevel}});
  }

  if(!p.startsWith("/api/platform/"))return null;
  const ctx=await authed(request,env);

  if(method==="GET"&&p==="/api/platform/overview"){
    const [registrations,tenants,plans,jobs,events,health,audit,recovery]=await Promise.all([
      sql`select * from platform.school_registrations order by created_at desc limit 200`,
      sql`select * from platform.tenant_control order by created_at desc limit 500`,
      sql`select * from platform.license_plans order by sort_order,code`,
      sql`select * from platform.provisioning_jobs order by created_at desc limit 250`,
      sql`select * from platform.tenant_events order by created_at desc limit 150`,
      sql`select * from platform.tenant_health order by checked_at desc limit 150`,
      sql`select * from platform.admin_audit_events order by created_at desc limit 150`,
      sql`select * from platform.access_recovery_requests where status='pending' order by requested_at desc limit 200`
    ]);
    const summary={
      pendingRegistrations:registrations.filter((r:any)=>r.status==="pending").length,
      activeTenants:tenants.filter((t:any)=>t.status==="active").length,
      provisioningTenants:tenants.filter((t:any)=>t.status==="provisioning").length,
      failedJobs:jobs.filter((j:any)=>j.status==="failed").length,
      suspendedTenants:tenants.filter((t:any)=>t.status==="suspended").length,
      capacityAttention:tenants.filter((t:any)=>["near_limit","at_limit","over_limit"].includes(String(t.student_capacity_status||""))).length
    };
    return json({ok:true,summary,registrations,tenants,plans,jobs,events,tenantHealth:health,auditEvents:audit,recoveryRequests:recovery,checkedAt:new Date().toISOString()});
  }

  let id=uuidPath(p,/^\/api\/platform\/registrations\/([0-9a-f-]{36})\/license$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request);
    const rows=await sql`select platform.configure_initial_license(${id}::uuid,${ctx.userId}::uuid,${String(b.periodType||"")},${String(b.periodLabel||"")},${asIso(b.startsAt)}::timestamptz,${asIso(b.expiresAt)}::timestamptz,${Number(b.graceDays??14)}::integer) result`;
    return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/registrations\/([0-9a-f-]{36})\/approve$/i);
  if(method==="POST"&&id){
    const rows=await sql`select platform.approve_registration(${id}::uuid,${ctx.userId}::uuid) result`;return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/registrations\/([0-9a-f-]{36})\/deny$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request);const rows=await sql`select platform.deny_registration(${id}::uuid,${ctx.userId}::uuid,${String(b.reason||"")}) result`;return json((rows[0] as any)?.result||{ok:true});
  }

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/provision$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request),action=String(b.action||"complete");
    const rows=action==="resume"
      ?await sql`select platform.resume_provisioning(${id}::uuid,${ctx.userId}::uuid) result`
      :await sql`select platform.complete_provisioning(${id}::uuid,${ctx.userId}::uuid) result`;
    return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/status$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request),rows=await sql`select platform.set_tenant_status(${id}::uuid,${ctx.userId}::uuid,${String(b.status||"")}) result`;return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/capacity\/refresh$/i);
  if(method==="POST"&&id){
    const rows=await sql`select platform.refresh_tenant_capacity(${id}::uuid,${ctx.userId}::uuid) result`;return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/capacity$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request),limit=b.limit===null||b.limit===undefined||String(b.limit).trim()===""?null:Number(b.limit);
    const rows=await sql`select platform.set_student_capacity(${id}::uuid,${ctx.userId}::uuid,${limit}::integer,${String(b.reason||"")}) result`;return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/license$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request);
    const rows=await sql`select platform.set_tenant_license(${id}::uuid,${ctx.userId}::uuid,${String(b.planCode||"")},${String(b.periodType||"")},${String(b.periodLabel||"")},${asIso(b.startsAt)}::timestamptz,${asIso(b.expiresAt)}::timestamptz,${Number(b.graceDays??14)}::integer) result`;
    return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/admin-setup-link$/i);
  if(method==="POST"&&id){
    const token=randomToken(32),hash=await adminSetupHash(env,token),expiresAt=new Date(Date.now()+30*60*1000).toISOString();
    const rows=await sql`select platform.issue_admin_setup_token(${id}::uuid,${ctx.userId}::uuid,${hash},${expiresAt}::timestamptz) result`;
    const result=(rows[0] as any)?.result||{};
    const basePath=String(env.APP_BASE_PATH||"").replace(/\/+$/,"");
    const setupLink=`${String(env.APP_ORIGIN||"").replace(/\/+$/,"")}${basePath}/admin-setup.html?token=${encodeURIComponent(token)}`;
    return json({...result,setupLink});
  }

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/health$/i);
  if(method==="POST"&&id){
    const capacity=await sql`select platform.refresh_tenant_capacity(${id}::uuid,${ctx.userId}::uuid) result`;
    const services=[{service:"database",healthy:true},{service:"storage",healthy:Boolean(env.OBJECTS)}],healthy=services.every(x=>x.healthy);
    await sql.transaction([
      sql`insert into platform.tenant_health(tenant_id,healthy,services) values(${id}::uuid,${healthy},${JSON.stringify(services)}::jsonb)`,
      sql`update platform.tenant_control set last_health_status=${healthy?"healthy":"degraded"},last_health_checked_at=now(),updated_at=now() where tenant_id=${id}::uuid`
    ]);
    return json({ok:true,health:{healthy,services},capacity:(capacity[0] as any)?.result||null});
  }

  return error("not_found","Platform endpoint not found",404,requestId);
}
