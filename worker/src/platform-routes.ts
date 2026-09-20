// Reference-parity Platform Administration routes: master control plane + isolated tenant databases.
import type { Env } from "./types";
import { db } from "./db";
import { readJson, json, error } from "./http";
import { passwordHash, randomToken, sha256Hex } from "./crypto";
import { authenticatePlatform, platformLogin, completePlatformMfa, logoutPlatform, setPlatformCookie, clearPlatformCookie } from "./platform-auth";
import { verifyTurnstile } from "./turnstile";
import { provisionIsolatedTenant } from "./provisioning";
import { tenantDb } from "./tenant-db";
import { beginMfaEnrollment, listMfaFactors, removeMfaFactor, verifyMfaEnrollment } from "./mfa-management";

async function authed(request:Request,env:Env){
  const ctx=await authenticatePlatform(request,env);
  if(!ctx)throw Object.assign(new Error("Platform administrator authentication is required"),{code:"unauthenticated",status:401});
  if(ctx.role!=="platform_super_admin"||ctx.assuranceLevel<2)throw Object.assign(new Error("A verified Platform Super Administrator session is required"),{code:"forbidden",status:403});
  return ctx;
}
function uuidPath(path:string,pattern:RegExp){const m=path.match(pattern);return m?.[1]||"";}
function asIso(value:any){const d=new Date(String(value||""));if(Number.isNaN(d.getTime()))throw Object.assign(new Error("A valid date/time is required"),{code:"validation_error",status:422});return d.toISOString();}
async function adminSetupHash(env:Env,token:string){return sha256Hex(`edusentia:tenant-admin-setup:v2:${token}:${env.SESSION_PEPPER}`);}
async function licenseAuthorizationHash(env:Env,code:string){return sha256Hex(`edusentia:licence-authorization:v1:${String(code||"").trim().toUpperCase()}:${env.SESSION_PEPPER}`);}
function licenseAuthorizationCode(){
  const alphabet="ABCDEFGHJKLMNPQRSTUVWXYZ23456789",bytes=new Uint8Array(16);crypto.getRandomValues(bytes);
  const chars=Array.from(bytes,b=>alphabet[b%alphabet.length]).join("");
  return `EDU-${chars.slice(0,4)}-${chars.slice(4,8)}-${chars.slice(8,12)}-${chars.slice(12,16)}`;
}
function setupLink(env:Env,token:string){
  const base=String(env.APP_ORIGIN||"").replace(/\/+$/,""),path=String(env.APP_BASE_PATH||"").replace(/\/+$/,"");
  return `${base}${path}/admin-setup.html?token=${encodeURIComponent(token)}`;
}
async function tenantControl(sql:any,tenantId:string){
  const rows=await sql`select * from platform.tenant_control where tenant_id=${tenantId}::uuid limit 1`;
  const row=rows[0] as any;
  if(!row)throw Object.assign(new Error("Tenant was not found"),{code:"tenant_not_found",status:404});
  if(row.database_state!=="isolated_ready"||!row.database_name)throw Object.assign(new Error("The isolated school database is not ready"),{code:"tenant_database_not_ready",status:409});
  return row;
}
async function refreshTenantSnapshot(env:Env,master:any,tenantId:string){
  const t=await tenantControl(master,tenantId),tenantSql=tenantDb(env,String(t.database_name));
  const [healthRows,capacityRows]=await Promise.all([
    tenantSql`select app.platform_health_snapshot(${tenantId}::uuid) result`,
    tenantSql`select app.platform_capacity_snapshot(${tenantId}::uuid) result`
  ]);
  const health=(healthRows[0] as any)?.result||{},capacity=(capacityRows[0] as any)?.result||{};
  const releaseHealthy=health.schema_version==="0020"&&health.runtime_version==="neon-v1.0.0-r42-parity";
  const healthy=Boolean(health.ok)&&releaseHealthy;
  await master.transaction([
    master`update platform.tenant_control set
      student_capacity_base=${capacity.base_limit??null},student_capacity_limit=${capacity.effective_limit??null},
      student_active_count=${Number(capacity.active||0)},student_total_count=${Number(capacity.total||0)},
      student_capacity_status=${String(capacity.status||"unknown")},student_admissions_blocked=${Boolean(capacity.admissions_blocked)},
      student_capacity_checked_at=now(),last_health_status=${healthy?"healthy":"degraded"},last_health_checked_at=now(),
      schema_version=${String(health.schema_version||"")},runtime_version=${String(health.runtime_version||"")},
      release_status=${releaseHealthy?"current":"drifted"},release_checked_at=now(),updated_at=now()
      where tenant_id=${tenantId}::uuid`,
    master`insert into platform.tenant_health(tenant_id,healthy,services) values(
      ${tenantId}::uuid,${healthy},${JSON.stringify([{service:"database",healthy:Boolean(health.ok),database:t.database_name},{service:"release",healthy:releaseHealthy,schemaVersion:health.schema_version,runtimeVersion:health.runtime_version},{service:"storage",healthy:Boolean(env.OBJECTS)}])}::jsonb)`
  ]);
  return {tenant:t,health:{...health,healthy,releaseHealthy},capacity};
}

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

  const schoolCode=p.match(/^\/api\/public\/schools\/([A-Za-z]{3}-\d{6})$/)?.[1];
  if(method==="GET"&&schoolCode){
    const rows=await sql`select * from platform.resolve_public_school(${schoolCode})`;
    if(!rows[0])return error("school_not_found","School workspace was not found",404,requestId);
    return json({ok:true,school:rows[0]});
  }

  if(method==="POST"&&p==="/api/public/access-recovery"){
    const b=await readJson<any>(request);
    await verifyTurnstile(env,String(b.turnstileToken||""),request,"access_recovery");
    const identifier=String(b.identifier||"").trim(),contactEmail=String(b.contactEmail||"").trim().toLowerCase(),recoveryType=String(b.recoveryType||"mfa").trim();
    if(identifier.length<3||!/^\S+@\S+\.\S+$/.test(contactEmail)||!["password","mfa","both"].includes(recoveryType))return error("invalid_recovery_request","Enter the school code or administrator email and the registered primary contact email",422,requestId);
    await sql`select platform.submit_access_recovery(${identifier},${contactEmail},${recoveryType})`;
    return json({ok:true,accepted:true,message:"If the submitted details match the registered school record, the protected request is now awaiting Platform Administrator review."},202);
  }

  if(method==="POST"&&p==="/api/public/admin-setup/inspect"){
    const b=await readJson<any>(request),token=String(b.token||"").trim();
    if(!token||token.length>1024)return error("invalid_setup_token","The administrator setup link is invalid",400,requestId);
    const hash=await adminSetupHash(env,token),rows=await sql`select * from platform.inspect_tenant_admin_handoff(${hash})`,row=rows[0] as any;
    if(!row)return error("setup_token_invalid_or_expired","This administrator setup link is invalid or has expired",410,requestId);
    return json({ok:true,setup:{tenantCode:row.tenant_code,schoolName:row.school_name,adminEmail:row.admin_email,purpose:row.purpose,expiresAt:row.expires_at}});
  }

  if(method==="POST"&&p==="/api/public/admin-setup/complete"){
    const b=await readJson<any>(request),token=String(b.token||"").trim(),password=String(b.password||"");
    await verifyTurnstile(env,String(b.turnstileToken||""),request,"admin_setup");
    if(!token||token.length>1024)return error("invalid_setup_token","The administrator setup link is invalid",400,requestId);
    if(password.length<12)return error("weak_password","Administrator password must contain at least 12 characters",422,requestId);
    const hash=await adminSetupHash(env,token),rows=await sql`select * from platform.inspect_tenant_admin_handoff(${hash})`,handoff=rows[0] as any;
    if(!handoff)return error("setup_token_invalid_or_expired","This administrator setup link is invalid or has expired",410,requestId);
    const credential=await passwordHash(password),tenantSql=tenantDb(env,String(handoff.database_name));
    await tenantSql`select authn.platform_set_initial_password_by_email(${handoff.tenant_id}::uuid,${String(handoff.admin_email)},${credential.hash},${credential.salt})`;
    const consumed=await sql`select platform.consume_tenant_admin_handoff(${hash}) result`;
    return json((consumed[0] as any)?.result||{ok:true});
  }

  if(method==="POST"&&p==="/api/platform/bootstrap/initialize"){
    const supplied=request.headers.get("x-bootstrap-secret")||"",expected=env.PLATFORM_BOOTSTRAP_SECRET||env.BOOTSTRAP_ADMIN_SECRET||"";
    if(!expected||supplied!==expected)return error("bootstrap_denied","Platform bootstrap authorization failed",403,requestId);
    const b=await readJson<any>(request),password=String(b.password||"");
    if(password.length<12)return error("weak_password","Platform administrator password must contain at least 12 characters",422,requestId);
    const credential=await passwordHash(password);
    const rows=await sql`select platform.bootstrap_first_super_admin(${String(b.email||"").trim().toLowerCase()},${String(b.displayName||"").trim()},${credential.hash},${credential.salt}) result`;
    return json({ok:true,result:(rows[0] as any)?.result},201);
  }

  if(method==="POST"&&p==="/api/platform/auth/login"){
    const b=await readJson<any>(request);await verifyTurnstile(env,String(b.turnstileToken||""),request,"platform_login");return json(await platformLogin(env,b.email,b.password));
  }
  if(method==="POST"&&p==="/api/platform/auth/mfa/complete"){
    const b=await readJson<any>(request),result=await completePlatformMfa(env,b.challengeToken,b.code);const r=json({...result.session,recoveryCodes:result.recoveryCodes});r.headers.append("set-cookie",setPlatformCookie(env,result.token));return r;
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

  if(method==="GET"&&p==="/api/platform/mfa/factors"){
    return json({ok:true,factors:await listMfaFactors(sql,ctx.userId)});
  }
  if(method==="POST"&&p==="/api/platform/mfa/enroll"){
    const b=await readJson<any>(request);
    const enrollment=await beginMfaEnrollment(env,sql,ctx.userId,ctx.email,"Edusentia Platform Administration",String(b.friendlyName||""));
    await sql`insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
      values(${ctx.userId}::uuid,'platform.mfa.enrollment_started','platform_admin',${ctx.userId},${JSON.stringify({friendlyName:"pending"})}::jsonb)`;
    return json({ok:true,enrollment},201);
  }
  const platformMfaFactor=p.match(/^\/api\/platform\/mfa\/factors\/([0-9a-f-]{36})\/(verify|remove)$/i);
  if(method==="POST"&&platformMfaFactor){
    const [,factorId,action]=platformMfaFactor,b=await readJson<any>(request);
    if(action==="verify"){
      const result=await verifyMfaEnrollment(env,sql,ctx.userId,factorId,String(b.code||""));
      await sql`insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
        values(${ctx.userId}::uuid,'platform.mfa.factor_verified','mfa_factor',${factorId},'{}'::jsonb)`;
      return json(result);
    }
    const result=await removeMfaFactor(sql,ctx.userId,factorId);
    await sql`insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
      values(${ctx.userId}::uuid,'platform.mfa.factor_removed','mfa_factor',${factorId},${JSON.stringify({verified:true})}::jsonb)`;
    return json(result);
  }


  if(method==="GET"&&p==="/api/platform/overview"){
    const [registrations,tenants,plans,jobs,events,health,audit,recovery,authorizations,releaseRows]=await Promise.all([
      sql`select * from platform.school_registrations order by created_at desc limit 200`,
      sql`select * from platform.tenant_control order by created_at desc limit 500`,
      sql`select * from platform.license_plans order by sort_order,code`,
      sql`select * from platform.provisioning_jobs order by created_at desc limit 250`,
      sql`select * from platform.tenant_events order by created_at desc limit 150`,
      sql`select * from platform.tenant_health order by checked_at desc limit 150`,
      sql`select * from platform.admin_audit_events order by created_at desc limit 150`,
      sql`select * from platform.access_recovery_requests where status in('pending','processing') order by requested_at desc limit 200`,
      sql`select * from platform.plan_authorizations order by issued_at desc limit 200`,
      sql`select platform.release_gate() result`
    ]);
    const summary={
      pendingRegistrations:registrations.filter((r:any)=>r.status==="pending").length,
      activeTenants:tenants.filter((t:any)=>t.status==="active").length,
      provisioningTenants:tenants.filter((t:any)=>t.status==="provisioning").length,
      failedJobs:jobs.filter((j:any)=>j.status==="failed").length,
      suspendedTenants:tenants.filter((t:any)=>t.status==="suspended").length,
      capacityAttention:tenants.filter((t:any)=>["near_limit","at_limit","over_limit"].includes(String(t.student_capacity_status||""))).length,
      pendingRecovery:recovery.length
    };
    return json({ok:true,summary,registrations,tenants,plans,jobs,events,tenantHealth:health,auditEvents:audit,recoveryRequests:recovery,planAuthorizations:authorizations,releaseGate:(releaseRows[0] as any)?.result||null,checkedAt:new Date().toISOString()});
  }

  let id=uuidPath(p,/^\/api\/platform\/registrations\/([0-9a-f-]{36})\/license$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request),rows=await sql`select platform.configure_initial_license(${id}::uuid,${ctx.userId}::uuid,${String(b.periodType||"")},${String(b.periodLabel||"")},${asIso(b.startsAt)}::timestamptz,${asIso(b.expiresAt)}::timestamptz,${Number(b.graceDays??14)}::integer) result`;
    return json((rows[0] as any)?.result||{ok:true});
  }
  id=uuidPath(p,/^\/api\/platform\/registrations\/([0-9a-f-]{36})\/approve$/i);
  if(method==="POST"&&id){const rows=await sql`select platform.approve_registration(${id}::uuid,${ctx.userId}::uuid) result`;return json((rows[0] as any)?.result||{ok:true});}
  id=uuidPath(p,/^\/api\/platform\/registrations\/([0-9a-f-]{36})\/deny$/i);
  if(method==="POST"&&id){const b=await readJson<any>(request),rows=await sql`select platform.deny_registration(${id}::uuid,${ctx.userId}::uuid,${String(b.reason||"")}) result`;return json((rows[0] as any)?.result||{ok:true});}

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/provision$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request),action=String(b.action||"complete");if(action==="resume")await sql`select platform.resume_provisioning(${id}::uuid,${ctx.userId}::uuid)`;return json(await provisionIsolatedTenant(env,id,ctx.userId));
  }
  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/status$/i);
  if(method==="POST"&&id){const b=await readJson<any>(request),rows=await sql`select platform.set_tenant_status(${id}::uuid,${ctx.userId}::uuid,${String(b.status||"")}) result`;return json((rows[0] as any)?.result||{ok:true});}

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/capacity\/refresh$/i);
  if(method==="POST"&&id){return json(await refreshTenantSnapshot(env,sql,id));}

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/capacity$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request),limit=b.limit===null||b.limit===undefined||String(b.limit).trim()===""?null:Number(b.limit),reason=String(b.reason||"").trim();
    if(reason.length<5)return error("capacity_reason_required","Provide a reason for the capacity authorization",422,requestId);
    const t=await tenantControl(sql,id),tenantSql=tenantDb(env,String(t.database_name)),rows=await tenantSql`select app.platform_set_student_capacity(${id}::uuid,${limit}::integer) result`,capacity=(rows[0] as any)?.result||{};
    await sql`update platform.tenant_control set student_capacity_reason=${reason.slice(0,500)},student_capacity_base=${capacity.base_limit??null},student_capacity_limit=${capacity.effective_limit??null},student_active_count=${Number(capacity.active||0)},student_total_count=${Number(capacity.total||0)},student_capacity_status=${String(capacity.status||"unknown")},student_admissions_blocked=${Boolean(capacity.admissions_blocked)},student_capacity_checked_at=now(),updated_at=now() where tenant_id=${id}::uuid`;
    await sql`insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details) values(${ctx.userId}::uuid,'platform.tenant.capacity_override','tenant',${id},${JSON.stringify({limit,reason:reason.slice(0,500)})}::jsonb)`;
    return json(capacity);
  }

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/license$/i);
  if(method==="POST"&&id){
    const b=await readJson<any>(request),code=licenseAuthorizationCode(),hash=await licenseAuthorizationHash(env,code),validUntil=new Date(Date.now()+72*60*60*1000).toISOString();
    const rows=await sql`select platform.issue_plan_authorization(
      ${id}::uuid,${ctx.userId}::uuid,${String(b.planCode||"")},${String(b.periodType||"")},${String(b.periodLabel||"")},
      ${asIso(b.startsAt)}::timestamptz,${asIso(b.expiresAt)}::timestamptz,${Number(b.graceDays??14)}::integer,
      ${hash},${code.slice(-4)},${validUntil}::timestamptz,${String(b.reason||"Platform licence authorization")}
    ) result`;
    return json({...((rows[0] as any)?.result||{}),authorizationCode:code,codeHint:code.slice(-4)});
  }

  const authMatch=p.match(/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/license-authorizations\/([0-9a-f-]{36})\/(revoke|delete)$/i);
  if(method==="POST"&&authMatch){
    const [,tenantId,authorizationId,action]=authMatch,b=await readJson<any>(request);
    const rows=action==="revoke"
      ?await sql`select platform.revoke_plan_authorization(${authorizationId}::uuid,${tenantId}::uuid,${ctx.userId}::uuid,${String(b.reason||"")}) result`
      :await sql`select platform.delete_revoked_plan_authorization(${authorizationId}::uuid,${tenantId}::uuid,${ctx.userId}::uuid,${String(b.confirmation||"")}) result`;
    return json((rows[0] as any)?.result||{ok:true});
  }

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/admin-setup-link$/i);
  if(method==="POST"&&id){
    const token=randomToken(32),hash=await adminSetupHash(env,token),expiresAt=new Date(Date.now()+30*60*1000).toISOString();
    const rows=await sql`select platform.issue_tenant_admin_handoff(${id}::uuid,${ctx.userId}::uuid,${hash},'initial_setup',${expiresAt}::timestamptz,null) result`;
    return json({...((rows[0] as any)?.result||{}),setupLink:setupLink(env,token)});
  }

  const recoveryMatch=p.match(/^\/api\/platform\/recovery\/([0-9a-f-]{36})\/(resolve|deny)$/i);
  if(method==="POST"&&recoveryMatch){
    const [,requestIdValue,action]=recoveryMatch,b=await readJson<any>(request);
    if(action==="deny"){
      const rows=await sql`select platform.deny_access_recovery(${requestIdValue}::uuid,${ctx.userId}::uuid,${String(b.reason||"")}) result`;return json((rows[0] as any)?.result||{ok:true});
    }
    const mode=String(b.mode||"mfa"),claimedRows=await sql`select platform.claim_access_recovery(${requestIdValue}::uuid,${ctx.userId}::uuid,${mode}) result`,claim=(claimedRows[0] as any)?.result||{};
    const tenantSql=tenantDb(env,String(claim.database_name));
    if(mode==="mfa"||mode==="both")await tenantSql`select authn.platform_reset_mfa_by_email(${claim.tenant_id}::uuid,${String(claim.admin_email)})`;
    if(mode==="password"||mode==="both"){
      const token=randomToken(32),hash=await adminSetupHash(env,token),expiresAt=new Date(Date.now()+30*60*1000).toISOString(),purpose=mode==="both"?"password_and_mfa_recovery":"password_recovery";
      await sql`select platform.issue_tenant_admin_handoff(${claim.tenant_id}::uuid,${ctx.userId}::uuid,${hash},${purpose},${expiresAt}::timestamptz,${requestIdValue}::uuid)`;
      return json({ok:true,status:"processing",mode,tenantId:claim.tenant_id,adminEmail:claim.admin_email,setupLink:setupLink(env,token),expiresAt});
    }
    const completed=await sql`select platform.complete_access_recovery(${requestIdValue}::uuid,${ctx.userId}::uuid,${mode}) result`;
    return json((completed[0] as any)?.result||{ok:true});
  }

  id=uuidPath(p,/^\/api\/platform\/tenants\/([0-9a-f-]{36})\/health$/i);
  if(method==="POST"&&id){return json(await refreshTenantSnapshot(env,sql,id));}

  if(method==="POST"&&p==="/api/platform/release-gate"){
    const rows=await sql`select platform.record_release_gate() result`;return json((rows[0] as any)?.result||{ok:false});
  }

  return error("not_found","Platform endpoint not found",404,requestId);
}
