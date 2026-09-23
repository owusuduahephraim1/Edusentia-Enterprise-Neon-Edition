import type { Env, SessionContext } from "./types";
import { db, tenantTx } from "./db";
import { readJson, json, error } from "./http";
import { authenticate, login, completeMfa, logout, setCookie, clearCookie } from "./auth";
import { verifyTurnstile } from "./turnstile";
import { platformRoute } from "./platform-routes";
import { tenantDb } from "./tenant-db";
import { sha256Hex } from "./crypto";
import { beginMfaEnrollment, listMfaFactors, removeMfaFactor, verifyMfaEnrollment } from "./mfa-management";
import { invokeCertifiedRpc } from "./certified-rpc";
import { handleLegacyIdentityFunction } from "./identity-admin";
import { handleTenantAuthRecovery } from "./recovery-compat";
import { backupDownloadGateway, handleBackupTransfer, handleScheduledBackupCompat } from "./backup-service";
import { cancelRestore, executeRestore, handleRestoreTransfer, prepareRestore } from "./restore-service";

// Authentication and authorization routes fail closed before tenant data access.
// Protected uploads use tenant-scoped R2 keys and fail closed with actionable errors.
function requireRole(ctx:SessionContext, roles:string[]){if(!roles.includes(ctx.role))throw Object.assign(new Error("You do not have permission for this operation"),{code:"forbidden",status:403});}
async function authed(request:Request,env:Env){const ctx=await authenticate(request,env);if(!ctx)throw Object.assign(new Error("Authentication is required"),{code:"unauthenticated",status:401});return ctx;}
function uploadContentType(filename:string,value:unknown){
  const supplied=String(value||"").split(";")[0].trim().toLowerCase();
  if(supplied&&supplied!=="application/octet-stream")return supplied;
  const name=String(filename||"").toLowerCase();
  if(name.endsWith(".png"))return "image/png";
  if(/\.(jpe?g)$/i.test(name))return "image/jpeg";
  if(name.endsWith(".webp"))return "image/webp";
  if(name.endsWith(".gif"))return "image/gif";
  if(name.endsWith(".pdf"))return "application/pdf";
  if(name.endsWith(".csv"))return "text/csv";
  if(name.endsWith(".docx"))return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  if(name.endsWith(".xlsx"))return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  return supplied||"application/octet-stream";
}

export async function route(request:Request,env:Env,requestId:string):Promise<Response>{
  const url=new URL(request.url), p=url.pathname, method=request.method.toUpperCase();
  const platformResponse=await platformRoute(request,env,requestId);if(platformResponse)return platformResponse;
  const backupTransfer=await handleBackupTransfer(request,env);if(backupTransfer)return backupTransfer;
  const restoreTransfer=await handleRestoreTransfer(request,env);if(restoreTransfer)return restoreTransfer;
  if(method==="GET"&&p==="/api/health"){
    const sql=db(env);let database=false;try{const r=await sql`select 1 as ok`;database=Number((r[0] as any)?.ok)===1;}catch{}
    return json({ok:database,service:"edusentia-neon-api",version:env.PRODUCT_VERSION||"dev",database,storage:Boolean(env.OBJECTS),requestId},database?200:503);
  }
  if(method==="POST"&&p==="/api/bootstrap/initialize"){
    const supplied=request.headers.get("x-bootstrap-secret")||"";
    if(!env.BOOTSTRAP_ADMIN_SECRET || supplied!==env.BOOTSTRAP_ADMIN_SECRET) return error("bootstrap_denied","Bootstrap authorization failed",403,requestId);
    const body=await readJson<any>(request);
    if(String(body.password||"").length<12) return error("weak_password","Initial administrator password must contain at least 12 characters",422,requestId);
    const { passwordHash } = await import("./crypto");
    const credential=await passwordHash(String(body.password));
    const sql=db(env);
    const rows=await sql`select authn.bootstrap_first_admin(${String(body.tenantCode||"").trim().toUpperCase()},${String(body.tenantName||"").trim()},${String(body.institutionType||"basic_jhs")},${String(body.email||"").trim().toLowerCase()},${String(body.displayName||"").trim()},${credential.hash},${credential.salt}) as result`;
    return json({ok:true,result:(rows[0] as any)?.result},201);
  }
  if(method==="POST"&&p==="/api/auth/login"){
    const body=await readJson<any>(request);
    await verifyTurnstile(env,String(body.turnstileToken||""),request);
    const result=await login(env,body.email,body.password,body.tenantCode);
    if(!("session" in result)) return json(result);
    const r=json(result.session);r.headers.append("set-cookie",setCookie(env,result.token));return r;
  }
  if(method==="POST"&&p==="/api/auth/mfa/complete"){
    const body=await readJson<any>(request);
    const result=await completeMfa(env,body.challengeToken,body.code);
    const r=json({...result.session,recoveryCodes:result.recoveryCodes});
    r.headers.append("set-cookie",setCookie(env,result.token));
    return r;
  }
  if(method==="POST"&&p==="/api/auth/logout"){
    await logout(request,env);const r=json({ok:true});r.headers.append("set-cookie",clearCookie(env));return r;
  }
  if(method==="GET"&&p==="/api/session"){
    const ctx=await authenticate(request,env);if(!ctx)return json({authenticated:false});
    return json({authenticated:true,user:{id:ctx.userId,email:ctx.email,displayName:ctx.displayName},membership:{tenantId:ctx.tenantId,tenantCode:ctx.tenantCode,tenantName:ctx.tenantName,role:ctx.role,roleLabel:ctx.role.replaceAll('_',' ')},session:{id:ctx.sessionId,assuranceLevel:ctx.assuranceLevel}});
  }
  const ctx=await authed(request,env),sql=tenantDb(env,ctx.databaseName),master=db(env);
  const legacyIdentity=p.match(/^\/api\/compat\/functions\/(admin-user-management|directory-user-management)$/);
  if(method==="POST"&&legacyIdentity){
    const body=await readJson<any>(request);
    return json(await handleLegacyIdentityFunction(legacyIdentity[1],sql,ctx,body));
  }
  if(method==="POST"&&p==="/api/compat/functions/tenant-auth-recovery"){
    const body=await readJson<Record<string,unknown>>(request);
    return json(await handleTenantAuthRecovery(env,sql,ctx,body));
  }
  if(method==="POST"&&p==="/api/compat/functions/scheduled-backup"){
    const body=await readJson<Record<string,unknown>>(request);
    const action=String(body.action||"create");
    if(action==="prepare_restore_import")return json(await prepareRestore(env,sql,ctx,body,url.origin),201);
    if(action==="execute_restore_import")return json(await executeRestore(env,sql,ctx,body));
    if(action==="cancel_restore_import")return json(await cancelRestore(env,sql,ctx,body));
    return json(await handleScheduledBackupCompat(env,sql,ctx,body));
  }
  if(method==="POST"&&p==="/api/compat/functions/backup-download-gateway"){
    const body=await readJson<Record<string,unknown>>(request);
    return json(await backupDownloadGateway(env,sql,ctx,body,url.origin));
  }
  if(method==="GET"&&p==="/api/security/mfa/factors"){
    requireRole(ctx,["system_admin"]);
    if(ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required",403,requestId);
    return json({ok:true,factors:await listMfaFactors(sql,ctx.userId)});
  }
  if(method==="POST"&&p==="/api/security/mfa/enroll"){
    requireRole(ctx,["system_admin"]);
    if(ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required",403,requestId);
    const b=await readJson<any>(request);
    const enrollment=await beginMfaEnrollment(env,sql,ctx.userId,ctx.email,ctx.tenantName,String(b.friendlyName||""));
    await sql`select audit.record_auth_event(${ctx.tenantId}::uuid,${ctx.userId}::uuid,'auth.mfa.enrollment_started',${JSON.stringify({scope:"tenant"})}::jsonb)`;
    return json({ok:true,enrollment},201);
  }
  const tenantMfaFactor=p.match(/^\/api\/security\/mfa\/factors\/([0-9a-f-]{36})\/(verify|remove)$/i);
  if(method==="POST"&&tenantMfaFactor){
    requireRole(ctx,["system_admin"]);
    if(ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required",403,requestId);
    const [,factorId,action]=tenantMfaFactor,b=await readJson<any>(request);
    if(action==="verify"){
      const result=await verifyMfaEnrollment(env,sql,ctx.userId,factorId,String(b.code||""));
      await sql`select audit.record_auth_event(${ctx.tenantId}::uuid,${ctx.userId}::uuid,'auth.mfa.factor_verified',${JSON.stringify({scope:"tenant"})}::jsonb)`;
      return json(result);
    }
    const result=await removeMfaFactor(sql,ctx.userId,factorId);
    await sql`select audit.record_auth_event(${ctx.tenantId}::uuid,${ctx.userId}::uuid,'auth.mfa.factor_removed',${JSON.stringify({scope:"tenant"})}::jsonb)`;
    return json(result);
  }

  if(method==="GET"&&p==="/api/academics/shs"){
    requireRole(ctx,["system_admin","principal"]);
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.neon_shs_academic_console() result`]);
    return json({ok:true,result:(rows[0] as any)?.result||{}});
  }
  if(method==="POST"&&p==="/api/academics/shs/insert"){
    requireRole(ctx,["system_admin","principal"]);
    const b=await readJson<any>(request);
    const entity=String(b.entity||"").trim().toLowerCase();
    const payload=b.payload&&typeof b.payload==="object"&&!Array.isArray(b.payload)?b.payload:{};
    if(!["programme","level","mapping","enrollment"].includes(entity))return error("validation_error","Unsupported Senior High academic entity",422,requestId);
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.neon_shs_academic_insert(${entity},${JSON.stringify(payload)}::jsonb) result`]);
    return json({ok:true,result:(rows[0] as any)?.result||null},201);
  }
  if(method==="POST"&&p==="/api/academics/shs/remove"){
    requireRole(ctx,["system_admin","principal"]);
    if(ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required to remove Senior High academic records",403,requestId);
    const b=await readJson<any>(request);
    const entity=String(b.entity||"").trim().toLowerCase(),id=String(b.id||"").trim();
    if(!["programme","level","mapping","enrollment"].includes(entity))return error("validation_error","Unsupported Senior High academic entity",422,requestId);
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id))return error("validation_error","A valid record ID is required",422,requestId);
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.neon_shs_academic_remove(${entity},${id}::uuid) result`]);
    if((rows[0] as any)?.result!==true)return error("mutation_not_applied","The requested Senior High academic record was not removed",409,requestId);
    return json({ok:true,result:true});
  }

  const certifiedRpcMatch=p.match(/^\/api\/compat\/rpc\/([a-z0-9_]+)$/);
  if(method==="POST"&&certifiedRpcMatch){
    const operation=certifiedRpcMatch[1],destructiveMutation=/^(archive_|delete_|remove_)/.test(operation);
    if(destructiveMutation&&["system_admin","admin"].includes(String(ctx.role))&&ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required for remove and delete operations",403,requestId);
    const body=await readJson<any>(request);
    const result=await invokeCertifiedRpc(sql,ctx,operation,body?.args??{});
    if(destructiveMutation&&result===false)return error("mutation_not_applied","The requested remove or delete operation did not complete",409,requestId);
    return json({ok:true,operation,result});
  }

  if(method==="POST"&&p==="/api/license/activate"){
    requireRole(ctx,["system_admin"]);
    if(ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required to activate a licence",403,requestId);
    const b=await readJson<any>(request),code=String(b.code||"").trim().toUpperCase();
    if(!/^EDU-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(code))return error("invalid_license_code","Enter a valid Edusentia licence authorization code",422,requestId);
    const hash=await sha256Hex(`edusentia:licence-authorization:v1:${code}:${env.SESSION_PEPPER}`);
    const claimedRows=await master`select platform.claim_plan_authorization(${ctx.tenantId}::uuid,${hash},${ctx.userId}) result`,claim=(claimedRows[0] as any)?.result||{};
    try{
      const appliedRows=await sql`select app.platform_apply_license(
        ${ctx.tenantId}::uuid,${ctx.userId}::uuid,${String(claim.plan_code)},
        ${claim.starts_at}::timestamptz,${claim.expires_at}::timestamptz,${Number(claim.grace_days||0)}::integer,
        ${String(claim.period_type)},${String(claim.period_label)}
      ) result`;
      const completedRows=await master`select platform.complete_plan_authorization(${claim.authorization_id}::uuid,${ctx.tenantId}::uuid,${ctx.userId}) result`;
      return json({ok:true,license:(appliedRows[0] as any)?.result,authorization:(completedRows[0] as any)?.result});
    }catch(e:any){
      await master`select platform.release_plan_authorization_claim(${claim.authorization_id}::uuid,${ctx.tenantId}::uuid,${String(e?.message||e).slice(0,500)})`;
      throw e;
    }
  }
  if(method==="GET"&&p==="/api/license/status"){
    requireRole(ctx,["system_admin","principal","accountant"]);
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`
      select lp.code plan_code,lp.name plan_name,tl.status,tl.starts_at,tl.expires_at,tl.feature_overrides,tl.limits_override,lp.feature_flags,lp.limits
      from app.tenant_licenses tl left join platform.license_plans lp on lp.id=tl.plan_id
      where tl.tenant_id=${ctx.tenantId}::uuid limit 1`]);
    return json({license:rows[0]||null});
  }
  if(method==="GET"&&p==="/api/admin/guardian-account-records"){
    requireRole(ctx,["system_admin"]);
    if(ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required to manage guardian accounts",403,requestId);
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`
      select
        sg.id,
        linked.auth_user_id,
        linked.linked_account_count,
        au.email portal_email,
        sg.full_name,
        sg.relationship,
        sg.phone,
        sg.email,
        sg.address,
        sg.is_primary,
        coalesce(children.children,'[]'::jsonb) children
      from public.student_guardians sg
      left join lateral (
        select min(gl.auth_user_id::text)::uuid auth_user_id,
               count(distinct gl.auth_user_id)::integer linked_account_count
        from public.guardian_links gl
        where gl.guardian_id=sg.id and gl.auth_user_id is not null
      ) linked on true
      left join authn.users au on au.id=linked.auth_user_id
      left join lateral (
        select jsonb_agg(
          jsonb_build_object(
            'student_id',s.id,
            'student_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
            'admission_no',s.admission_no,
            'class_id',ce.class_id,
            'class_name',ce.class_name
          )
          order by lower(concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name)),s.admission_no::text
        ) children
        from public.guardian_links gl2
        join public.students s on s.id=gl2.student_id and s.deleted_at is null and s.status='active'
        left join lateral (
          select e.class_id,c.name::text class_name
          from public.enrollments e
          join public.classes c on c.id=e.class_id and c.deleted_at is null
          join public.academic_years y on y.id=e.academic_year_id and y.deleted_at is null
          where e.student_id=s.id and e.deleted_at is null
          order by y.is_active desc,e.active desc,y.start_date desc,e.updated_at desc
          limit 1
        ) ce on true
        where gl2.guardian_id=sg.id
      ) children on true
      where exists(
        select 1
        from public.guardian_links gl3
        join public.students s3 on s3.id=gl3.student_id and s3.deleted_at is null and s3.status='active'
        where gl3.guardian_id=sg.id
      )
      order by lower(sg.full_name),lower(coalesce(sg.phone,'')),sg.id
    `]);
    return json({rows});
  }
  if(method==="POST"&&p==="/api/settings/school"){
    requireRole(ctx,["system_admin"]);
    if(ctx.assuranceLevel<2)return error("mfa_required","A verified MFA session is required to change school settings",403,requestId);
    const b=await readJson<any>(request);
    const clean=(value:unknown,max=500)=>String(value??"").trim().slice(0,max);
    const webAddress=(value:unknown,max=500)=>{const raw=clean(value,max);return raw&&!/^[a-z][a-z0-9+.-]*:\/\//i.test(raw)?`https://${raw}`:raw;};
    const name=clean(b.name,200);
    if(!name)return error("validation_error","School name is required",422,requestId);
    const brandingRequested=["primary_colour","accent_colour","report_body_font","report_body_font_size"].some(key=>b[key]!==undefined);
    if(brandingRequested){
      const [featureRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.license_feature_enabled('custom_branding') enabled`]);
      if((featureRows[0] as any)?.enabled!==true)return error("feature_not_available","Custom branding is not available on the current school plan",403,requestId);
    }
    const allowed={
      motto:clean(b.motto,240),address:clean(b.address,500),phone:clean(b.phone,80),email:clean(b.email,254),
      website:webAddress(b.website,500),head_name:clean(b.head_name,200),report_number_prefix:clean(b.report_number_prefix,30),
      user_email_domain:clean(b.user_email_domain,180),timezone:clean(b.timezone,80)||"Africa/Accra",
      verification_base_url:webAddress(b.verification_base_url,500),primary_colour:clean(b.primary_colour,20),
      accent_colour:clean(b.accent_colour,20),report_body_font:clean(b.report_body_font,80),
      report_body_font_size:Math.min(24,Math.max(8,Number(b.report_body_font_size||11)))
    };
    const [updated]=await tenantTx<any[]>(sql,ctx,txn=>[
      txn`update app.tenants set name=${name},settings=coalesce(settings,'{}'::jsonb)||${JSON.stringify(allowed)}::jsonb,updated_at=now() where id=${ctx.tenantId}::uuid returning id,code,name,institution_type,settings,updated_at`,
      txn`select audit.record_auth_event(${ctx.tenantId}::uuid,${ctx.userId}::uuid,'tenant.settings.updated',${JSON.stringify({scope:"school_identity"})}::jsonb)`
    ]);
    return json({ok:true,tenant:updated[0]||null});
  }
  if(method==="GET"&&p==="/api/bootstrap"){
    const [tenant,metrics,licenseRows,permissionRows,certifiedBootstrapRows]=await tenantTx<any[]>(sql,ctx,txn=>[
      txn`select t.id,t.code,t.name,t.institution_type,coalesce(t.settings,'{}'::jsonb) settings
        from app.tenants t
        where t.id=${ctx.tenantId}::uuid`,
      txn`select
        (select count(*)::int from app.students where tenant_id=${ctx.tenantId}::uuid and archived_at is null) students,
        (select count(*)::int from app.staff where tenant_id=${ctx.tenantId}::uuid and archived_at is null) staff,
        (select count(*)::int from academics.classes where tenant_id=${ctx.tenantId}::uuid and archived_at is null) classes,
        (select count(*)::int from academics.subjects where tenant_id=${ctx.tenantId}::uuid and archived_at is null) subjects,
        (select count(*)::int from academics.attendance_entries where tenant_id=${ctx.tenantId}::uuid and attendance_date=current_date) attendance_today,
        (select count(*)::int from academics.student_reports where tenant_id=${ctx.tenantId}::uuid and status in ('draft','submitted','class_reviewed')) pending_reports`,
      txn`select
        tl.status,tl.starts_at,tl.expires_at,
        coalesce(lp.code,'') plan_code,coalesce(lp.name,'') plan_name,
        coalesce(lp.feature_flags,'{}'::jsonb)||coalesce(tl.feature_overrides,'{}'::jsonb) feature_flags,
        coalesce(lp.limits,'{}'::jsonb)||coalesce(tl.limits_override,'{}'::jsonb) limits
        from app.tenant_licenses tl
        left join platform.license_plans lp on lp.id=tl.plan_id
        where tl.tenant_id=${ctx.tenantId}::uuid
        order by tl.updated_at desc limit 1`,
      txn`select coalesce(jsonb_object_agg(permission_code,true),'{}'::jsonb) permissions
        from app.role_permissions where role=${ctx.role}`,
      txn`select public.get_bootstrap_data() result`
    ]);
    // Expose certified blueprint permission aliases while retaining Neon-native dotted permissions.\n    // Blueprint System Administrator permission inheritance is intentional and regression-tested.\n    // School-logo parity is reconciled during every isolated-tenant upgrade.\n    // Class-scoped student admission numbering is reconciled through 0049x.\n    // Permanent audit reset parity is reconciled through 0049y.
    const rawPermissions={...((permissionRows[0] as any)?.permissions||{})};
    const isSystemAdmin=ctx.role==="system_admin";
    const permissions={
      ...rawPermissions,
      manage_academics:isSystemAdmin||Boolean(rawPermissions["academics.write"]),
      manage_teachers:isSystemAdmin||Boolean(rawPermissions["staff.write"]),
      manage_headteachers:isSystemAdmin||Boolean(rawPermissions["admin.tenant"]),
      manage_users:isSystemAdmin||Boolean(rawPermissions["admin.users"]),
      view_audit:isSystemAdmin||Boolean(rawPermissions["admin.tenant"])
    };
    const tenantRow=(tenant[0]||null) as any;
    const certifiedBootstrap=((certifiedBootstrapRows[0] as any)?.result||{}) as any;
    const canonicalLogo=String(certifiedBootstrap?.school?.logo_url||tenantRow?.settings?.logo_url||"assets/school-logo.png").trim()||"assets/school-logo.png";
    const tenantPayload=tenantRow?{...tenantRow,settings:{...(tenantRow.settings||{}),logo_url:canonicalLogo}}:null;
    const licenseRow=(licenseRows[0]||{}) as any;
    const now=Date.now(),expires=licenseRow.expires_at?Date.parse(String(licenseRow.expires_at)):NaN;
    const license={
      status:String(licenseRow.status||"unknown"),
      read_allowed:String(licenseRow.status||"").toLowerCase()!=="revoked",
      write_allowed:String(licenseRow.status||"").toLowerCase()==="active" && (!Number.isFinite(expires)||expires>=now),
      starts_at:licenseRow.starts_at||null,expires_at:licenseRow.expires_at||null,
      plan:{code:licenseRow.plan_code||"",name:licenseRow.plan_name||"",feature_flags:licenseRow.feature_flags||{},limits:licenseRow.limits||{}}
    };
    return json({
      tenant:tenantPayload,metrics:metrics[0]||{},
      permissions,
      license,
      capabilities:{role:ctx.role,assuranceLevel:ctx.assuranceLevel}
    });
  }
  if(method==="GET"&&p==="/api/students"){
    const q=(url.searchParams.get("q")||"").trim(),limit=Math.min(100,Math.max(1,Number(url.searchParams.get("limit")||25))),offset=Math.max(0,Number(url.searchParams.get("offset")||0));
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select id,student_no,first_name,middle_name,last_name,gender,date_of_birth,status,created_at from app.students where tenant_id=${ctx.tenantId}::uuid and archived_at is null and (${q}='' or search_text ilike ${'%'+q+'%'}) order by last_name,first_name limit ${limit} offset ${offset}`]);
    return json({rows,limit,offset});
  }
  if(method==="POST"&&p==="/api/students"){
    requireRole(ctx,["system_admin","principal","academic_admin","records_officer"]);const b=await readJson<any>(request);
    const capacityRows=await sql`select app.platform_capacity_snapshot(${ctx.tenantId}::uuid) result`,capacity=(capacityRows[0] as any)?.result||{};
    if(capacity.admissions_blocked)return error("student_capacity_reached","Student admission is blocked because the licensed capacity has been reached",409,requestId);
    if(!b.firstName||!b.lastName||!b.studentNo) return error("validation_error","Student number, first name and last name are required",422,requestId);
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`insert into app.students(tenant_id,student_no,first_name,middle_name,last_name,gender,date_of_birth,status,created_by) values(${ctx.tenantId}::uuid,${String(b.studentNo).trim()},${String(b.firstName).trim()},${String(b.middleName||'').trim()},${String(b.lastName).trim()},${String(b.gender||'unspecified')},${b.dateOfBirth||null},'active',${ctx.userId}::uuid) returning *`]);
    return json({student:rows[0]},201);
  }
  if(method==="GET"&&p==="/api/staff"){
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select id,staff_no,full_name,email,phone,job_title,staff_type,active from app.staff where tenant_id=${ctx.tenantId}::uuid and archived_at is null order by full_name limit 100`]);
    return json({rows});
  }
  if(method==="GET"&&p==="/api/finance/summary"){
    requireRole(ctx,["system_admin","principal","accountant"]);
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select
      coalesce((select sum(amount_due-amount_paid) from finance.invoices where tenant_id=${ctx.tenantId}::uuid and status<>'void'),0)::numeric as outstanding,
      coalesce((select sum(amount) from finance.payments where tenant_id=${ctx.tenantId}::uuid and received_at::date=current_date and reversed_at is null),0)::numeric as received_today,
      (select count(*)::int from finance.invoices where tenant_id=${ctx.tenantId}::uuid and status='overdue') overdue_invoices`]);
    return json(rows[0]||{});
  }

  if(method==="GET"&&p==="/api/finance/invoices"){
    requireRole(ctx,["system_admin","principal","accountant"]);
    const limit=Math.min(200,Math.max(1,Number(url.searchParams.get("limit")||100)));
    const offset=Math.max(0,Number(url.searchParams.get("offset")||0));
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select
      i.id,i.invoice_no,i.student_id,i.term_id,i.amount_due,i.amount_paid,i.status,i.due_date,i.created_at,
      concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
      t.name term_name
      from finance.invoices i
      left join app.students s on s.id=i.student_id and s.tenant_id=i.tenant_id
      left join academics.terms t on t.id=i.term_id and t.tenant_id=i.tenant_id
      where i.tenant_id=${ctx.tenantId}::uuid
      order by i.created_at desc,i.invoice_no desc
      limit ${limit} offset ${offset}`]);
    return json({rows,limit,offset});
  }
  if(method==="GET"&&p==="/api/finance/payments"){
    requireRole(ctx,["system_admin","principal","accountant"]);
    const limit=Math.min(200,Math.max(1,Number(url.searchParams.get("limit")||100)));
    const offset=Math.max(0,Number(url.searchParams.get("offset")||0));
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select
      pmt.id,pmt.receipt_no,pmt.student_id,pmt.invoice_id,pmt.amount,pmt.method,pmt.reference,pmt.received_at,pmt.reversed_at,pmt.reversal_reason,
      concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
      i.invoice_no
      from finance.payments pmt
      left join app.students s on s.id=pmt.student_id and s.tenant_id=pmt.tenant_id
      left join finance.invoices i on i.id=pmt.invoice_id and i.tenant_id=pmt.tenant_id
      where pmt.tenant_id=${ctx.tenantId}::uuid
      order by pmt.received_at desc,pmt.receipt_no desc
      limit ${limit} offset ${offset}`]);
    return json({rows,limit,offset});
  }

  if(method==="GET"&&p==="/api/operations/overview"){
    requireRole(ctx,["system_admin","principal"]);
    const [counts,admissions,attendance,discipline,welfare,health,hostel,payroll,communications,documents,continuity]=await tenantTx<any[]>(sql,ctx,txn=>[
      txn`select
        (select count(*)::int from app.admissions_applications where tenant_id=${ctx.tenantId}::uuid) admissions,
        (select count(*)::int from academics.attendance_registers where tenant_id=${ctx.tenantId}::uuid) attendance_registers,
        (select count(*)::int from services.discipline_incidents where tenant_id=${ctx.tenantId}::uuid) discipline_incidents,
        (select count(*)::int from services.welfare_cases where tenant_id=${ctx.tenantId}::uuid) welfare_cases,
        (select count(*)::int from services.health_visits where tenant_id=${ctx.tenantId}::uuid) health_visits,
        (select count(*)::int from services.hostel_allocations where tenant_id=${ctx.tenantId}::uuid) hostel_allocations,
        (select count(*)::int from finance.payroll_runs where tenant_id=${ctx.tenantId}::uuid) payroll_runs,
        (select count(*)::int from services.communication_campaigns where tenant_id=${ctx.tenantId}::uuid) communication_campaigns,
        (select count(*)::int from documents.certificate_batches where tenant_id=${ctx.tenantId}::uuid) certificate_batches,
        (select count(*)::int from ops.import_batches where tenant_id=${ctx.tenantId}::uuid) import_batches`,
      txn`select a.id,a.application_no,concat_ws(' ',a.first_name,nullif(a.middle_name,''),a.last_name) applicant_name,a.status,a.submitted_at,c.name applying_class
        from app.admissions_applications a left join academics.classes c on c.id=a.applying_class_id and c.tenant_id=a.tenant_id
        where a.tenant_id=${ctx.tenantId}::uuid order by a.created_at desc limit 20`,
      txn`select r.id,r.attendance_date,r.status,c.name class_name,t.name term_name,
        (select count(*)::int from academics.attendance_entries e where e.register_id=r.id and e.tenant_id=r.tenant_id) entry_count
        from academics.attendance_registers r
        left join academics.classes c on c.id=r.class_id and c.tenant_id=r.tenant_id
        left join academics.terms t on t.id=r.term_id and t.tenant_id=r.tenant_id
        where r.tenant_id=${ctx.tenantId}::uuid order by r.attendance_date desc,r.created_at desc limit 20`,
      txn`select d.id,d.incident_date,d.category,d.severity,d.summary,d.status,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name
        from services.discipline_incidents d left join app.students s on s.id=d.student_id and s.tenant_id=d.tenant_id
        where d.tenant_id=${ctx.tenantId}::uuid order by d.incident_date desc,d.created_at desc limit 20`,
      txn`select w.id,w.case_type,w.priority,w.summary,w.status,w.opened_at,w.closed_at,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name
        from services.welfare_cases w left join app.students s on s.id=w.student_id and s.tenant_id=w.tenant_id
        where w.tenant_id=${ctx.tenantId}::uuid order by w.opened_at desc limit 20`,
      txn`select h.id,h.visited_at,h.complaint,h.assessment,h.disposition,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name
        from services.health_visits h left join app.students s on s.id=h.student_id and s.tenant_id=h.tenant_id
        where h.tenant_id=${ctx.tenantId}::uuid order by h.visited_at desc limit 20`,
      txn`select h.id,h.starts_on,h.ends_on,h.status,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name
        from services.hostel_allocations h left join app.students s on s.id=h.student_id and s.tenant_id=h.tenant_id
        where h.tenant_id=${ctx.tenantId}::uuid order by h.starts_on desc limit 20`,
      txn`select p.id,p.period_start,p.period_end,p.status,p.created_at,
        (select count(*)::int from finance.payroll_entries e where e.payroll_run_id=p.id and e.tenant_id=p.tenant_id) entry_count,
        coalesce((select sum(e.net_amount) from finance.payroll_entries e where e.payroll_run_id=p.id and e.tenant_id=p.tenant_id),0)::numeric total_net
        from finance.payroll_runs p where p.tenant_id=${ctx.tenantId}::uuid order by p.period_end desc,p.created_at desc limit 20`,
      txn`select id,name,channel,audience,subject,status,scheduled_at,published_at,created_at
        from services.communication_campaigns where tenant_id=${ctx.tenantId}::uuid order by created_at desc limit 20`,
      txn`select b.id,b.batch_no,b.certificate_type,b.status,b.submitted_at,b.reviewed_at
        from documents.certificate_batches b where b.tenant_id=${ctx.tenantId}::uuid order by coalesce(b.reviewed_at,b.submitted_at) desc nulls last limit 20`,
      txn`select id,import_type,file_name,status,row_count,success_count,error_count,created_at,completed_at
        from ops.import_batches where tenant_id=${ctx.tenantId}::uuid order by created_at desc limit 20`
    ]);
    return json({counts:counts[0]||{},admissions,attendance,discipline,welfare,health,hostel,payroll,communications,documents,continuity});
  }

  const reportPdfUpload=p.match(/^\/api\/reports\/([0-9a-f-]{36})\/pdf\/upload-url$/i);
  if(method==="POST"&&reportPdfUpload){
    const reportId=reportPdfUpload[1];
    const [allowedRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.can_manage_report_pdf(${reportId}::uuid) allowed`]);
    if(!(allowedRows[0] as any)?.allowed)return error("forbidden","You are not authorized to manage the official report PDF",403,requestId);
    const b=await readJson<any>(request);
    const name=String(b.filename||"report.pdf").replace(/[^a-zA-Z0-9._-]/g,"_").slice(0,120);
    const type=String(b.contentType||"application/pdf").split(";")[0].trim().toLowerCase();
    const size=Number(b.size||0);
    if(type!=="application/pdf")return error("invalid_content_type","Official report files must be PDF",415,requestId);
    if(size<=0||size>20*1024*1024)return error("invalid_file_size","Report PDF size must be between 1 byte and 20 MB",422,requestId);
    const key=`tenants/${ctx.tenantId}/report-pdfs/${reportId}/${crypto.randomUUID()}-${name}`;
    try{
      const [preparedRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.prepare_object_upload(${key},${name},'application/pdf',${size}::bigint) metadata`]);
      if(!(preparedRows[0] as any)?.metadata)throw new Error("Upload metadata was not created");
    }catch(cause){
      console.error(JSON.stringify({level:"error",requestId,code:"upload_prepare_failed",message:String((cause as any)?.message||cause)}));
      throw Object.assign(new Error("The report PDF upload could not be prepared. Please retry."),{code:"upload_prepare_failed",status:503});
    }
    return json({objectKey:key,uploadUrl:`/api/files/upload?key=${encodeURIComponent(key)}`,method:"PUT",expiresInSeconds:900});
  }

  const reportPdfDownload=p.match(/^\/api\/reports\/([0-9a-f-]{36})\/pdf\/download$/i);
  if(method==="GET"&&reportPdfDownload){
    const reportId=reportPdfDownload[1];
    const [descriptorRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.get_report_pdf_descriptor(${reportId}::uuid) descriptor`]);
    const descriptor=(descriptorRows[0] as any)?.descriptor||{};
    const key=String(descriptor.storage_path||"");
    if(!key)return error("not_found","Official report PDF is not registered",404,requestId);
    if(!key.startsWith(`tenants/${ctx.tenantId}/report-pdfs/${reportId}/`))return error("forbidden","Invalid report PDF scope",403,requestId);
    const [metaRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.get_object_upload_metadata(${key},'active') metadata`]);
    const meta=(metaRows[0] as any)?.metadata as any;if(!meta)return error("not_found","Official report PDF object is not available",404,requestId);
    const obj=await env.OBJECTS.get(key);if(!obj)return error("not_found","Official report PDF object is not available",404,requestId);
    const h=new Headers();obj.writeHttpMetadata(h);
    h.set("content-type","application/pdf");
    h.set("content-disposition",`attachment; filename*=UTF-8''${encodeURIComponent(String(meta.original_name||"report.pdf"))}`);
    h.set("cache-control","private, no-store");
    h.set("x-content-type-options","nosniff");
    return new Response(obj.body,{headers:h});
  }

  const reportPdfDelete=p.match(/^\/api\/reports\/([0-9a-f-]{36})\/pdf\/object$/i);
  if(method==="DELETE"&&reportPdfDelete){
    const reportId=reportPdfDelete[1],key=url.searchParams.get("key")||"";
    if(!key.startsWith(`tenants/${ctx.tenantId}/report-pdfs/${reportId}/`))return error("forbidden","Invalid report PDF scope",403,requestId);
    const [allowedRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.can_delete_report_pdf_object(${reportId}::uuid,${key}) allowed`]);
    if(!(allowedRows[0] as any)?.allowed)return error("forbidden","This report PDF object cannot be deleted",403,requestId);
    const [metaRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.get_object_upload_metadata(${key},'active') metadata`]);
    const meta=(metaRows[0] as any)?.metadata as any;if(!meta)return error("not_found","Report PDF object was not found",404,requestId);
    await env.OBJECTS.delete(key);
    const [transitionRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.transition_object_upload(${meta.id}::uuid,'active','deleted') changed`]);
    if(!(transitionRows[0] as any)?.changed)throw Object.assign(new Error("Report PDF metadata could not be retired"),{code:"upload_metadata_transition_failed",status:503});
    return json({ok:true,objectKey:key});
  }
  if(method==="POST"&&p==="/api/files/upload-url"){
    const b=await readJson<any>(request),kind=String(b.kind||"document").replace(/[^a-z0-9_-]/gi,"_").slice(0,40),name=String(b.filename||"file").replace(/[^a-zA-Z0-9._-]/g,"_").slice(0,120),type=uploadContentType(String(b.filename||"file"),b.contentType);
    if(kind==="report-pdfs")return error("forbidden","Use the report PDF upload endpoint",403,requestId);
    const size=Number(b.size||0);if(size<=0||size>20*1024*1024)return error("invalid_file_size","File size must be between 1 byte and 20 MB",422,requestId);
    const allowed=["image/","application/pdf","text/csv","application/vnd.openxmlformats-officedocument"];
    if(!allowed.some(x=>type.startsWith(x)))return error("invalid_content_type","This file type is not allowed",422,requestId);
    const rawSubfolder=String(b.subfolder||"").trim();
    let subfolder="";
    if(rawSubfolder){
      if(kind!=="report-card-templates"||!["early_years","basic_1_6","basic_7_9"].includes(rawSubfolder))return error("invalid_upload_scope","Invalid report-card template class range",422,requestId);
      subfolder=`/${rawSubfolder}`;
    }
    const key=`tenants/${ctx.tenantId}/${kind}${subfolder}/${crypto.randomUUID()}-${name}`;
    try{
      const [preparedRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.prepare_object_upload(${key},${name},${type},${size}::bigint) metadata`]);
      if(!(preparedRows[0] as any)?.metadata)throw new Error("Upload metadata was not created");
    }catch(cause){
      console.error(JSON.stringify({level:"error",requestId,code:"upload_prepare_failed",message:String((cause as any)?.message||cause)}));
      throw Object.assign(new Error("The upload could not be prepared. Please retry."),{code:"upload_prepare_failed",status:503});
    }
    // R2 native binding does not expose public credentials. Upload is proxied by the Worker in the dedicated PUT route.
    return json({objectKey:key,uploadUrl:`/api/files/upload?key=${encodeURIComponent(key)}`,method:"PUT",expiresInSeconds:900,contentType:type});
  }
  if(method==="PUT"&&p==="/api/files/upload"){
    const key=url.searchParams.get("key")||"";if(!key.startsWith(`tenants/${ctx.tenantId}/`))return error("forbidden","Invalid object scope",403,requestId);
    let metadata:any;
    try{
      const [metaRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.get_object_upload_metadata(${key},'pending') metadata`]);
      metadata=(metaRows[0] as any)?.metadata||null;
    }catch(cause){
      console.error(JSON.stringify({level:"error",requestId,code:"upload_authorization_lookup_failed",message:String((cause as any)?.message||cause)}));
      throw Object.assign(new Error("The upload authorization could not be verified. Please retry."),{code:"upload_authorization_lookup_failed",status:503});
    }
    if(!metadata)return error("not_found","Upload authorization was not found",404,requestId);
    const expectedSize=Number(metadata.size_bytes);
    const expectedType=String(metadata.content_type).toLowerCase();
    const receivedType=String(request.headers.get("content-type")||"").split(";")[0].trim().toLowerCase();
    if(receivedType!==expectedType)return error("invalid_content_type","Upload content type does not match authorization",415,requestId);
    const bytes=await request.arrayBuffer();
    if(bytes.byteLength!==expectedSize)return error("invalid_file_size","Upload size does not match authorization",413,requestId);
    try{
      await env.OBJECTS.put(key,bytes,{httpMetadata:{contentType:expectedType}});
    }catch(cause){
      await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.transition_object_upload(${metadata.id}::uuid,'pending','quarantined') changed`]).catch(()=>{});
      console.error(JSON.stringify({level:"error",requestId,code:"object_storage_write_failed",message:String((cause as any)?.message||cause)}));
      throw Object.assign(new Error("Object storage is temporarily unavailable. Please retry the upload."),{code:"object_storage_write_failed",status:503});
    }
    try{
      const [transitionRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.transition_object_upload(${metadata.id}::uuid,'pending','active') changed`]);
      if(!(transitionRows[0] as any)?.changed)throw new Error("Upload metadata was not finalized");
    }catch(cause){
      await env.OBJECTS.delete(key).catch(()=>{});
      console.error(JSON.stringify({level:"error",requestId,code:"upload_finalize_failed",message:String((cause as any)?.message||cause)}));
      throw Object.assign(new Error("The upload could not be finalized. Please retry."),{code:"upload_finalize_failed",status:503});
    }
    return json({ok:true,objectKey:key,size:bytes.byteLength,contentType:expectedType});
  }
  if(method==="GET"&&p==="/api/files/download"){
    const key=url.searchParams.get("key")||"";
    if(!key.startsWith(`tenants/${ctx.tenantId}/`))return error("forbidden","Invalid object scope",403,requestId);
    if(key.startsWith(`tenants/${ctx.tenantId}/report-pdfs/`))return error("forbidden","Use the guarded report PDF download endpoint",403,requestId);
    const [metaRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.get_object_upload_metadata(${key},'active') metadata`]);
    const metadata=(metaRows[0] as any)?.metadata as any;
    if(!metadata)return error("not_found","File not found",404,requestId);
    const obj=await env.OBJECTS.get(key);if(!obj)return error("not_found","File not found",404,requestId);
    const h=new Headers();obj.writeHttpMetadata(h);h.set("content-type",String(metadata.content_type));h.set("content-disposition",`attachment; filename*=UTF-8''${encodeURIComponent(String(metadata.original_name))}`);h.set("cache-control","private, no-store");return new Response(obj.body,{headers:h});
  }
  return error("not_found","Endpoint not found",404,requestId);
}
