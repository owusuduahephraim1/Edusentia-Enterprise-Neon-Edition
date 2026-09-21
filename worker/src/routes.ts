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

// Authentication and authorization routes fail closed before tenant data access.
function requireRole(ctx:SessionContext, roles:string[]){if(!roles.includes(ctx.role))throw Object.assign(new Error("You do not have permission for this operation"),{code:"forbidden",status:403});}
async function authed(request:Request,env:Env){const ctx=await authenticate(request,env);if(!ctx)throw Object.assign(new Error("Authentication is required"),{code:"unauthenticated",status:401});return ctx;}

export async function route(request:Request,env:Env,requestId:string):Promise<Response>{
  const url=new URL(request.url), p=url.pathname, method=request.method.toUpperCase();
  const platformResponse=await platformRoute(request,env,requestId);if(platformResponse)return platformResponse;
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

  const certifiedRpcMatch=p.match(/^\/api\/compat\/rpc\/([a-z0-9_]+)$/);
  if(method==="POST"&&certifiedRpcMatch){
    const body=await readJson<any>(request);
    const result=await invokeCertifiedRpc(sql,ctx,certifiedRpcMatch[1],body?.args??{});
    return json({ok:true,operation:certifiedRpcMatch[1],result});
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
    const rows=await sql`
      select lp.code plan_code,lp.name plan_name,tl.status,tl.starts_at,tl.expires_at,tl.feature_overrides,tl.limits_override,lp.feature_flags,lp.limits
      from app.tenant_licenses tl left join platform.license_plans lp on lp.id=tl.plan_id
      where tl.tenant_id=${ctx.tenantId}::uuid limit 1`;
    return json({license:rows[0]||null});
  }
  if(method==="GET"&&p==="/api/bootstrap"){
    const [tenant,metrics]=await tenantTx<any[]>(sql,ctx,txn=>[
      txn`select id,code,name,institution_type,settings from app.tenants where id=${ctx.tenantId}::uuid`,
      txn`select
        (select count(*)::int from app.students where tenant_id=${ctx.tenantId}::uuid and archived_at is null) students,
        (select count(*)::int from app.staff where tenant_id=${ctx.tenantId}::uuid and archived_at is null) staff,
        (select count(*)::int from academics.classes where tenant_id=${ctx.tenantId}::uuid and archived_at is null) classes,
        (select count(*)::int from academics.subjects where tenant_id=${ctx.tenantId}::uuid and archived_at is null) subjects,
        (select count(*)::int from academics.attendance_entries where tenant_id=${ctx.tenantId}::uuid and attendance_date=current_date) attendance_today,
        (select count(*)::int from academics.student_reports where tenant_id=${ctx.tenantId}::uuid and status in ('draft','submitted','class_reviewed')) pending_reports`
    ]);
    return json({tenant:(tenant[0]||null),metrics:metrics[0]||{},capabilities:{role:ctx.role,assuranceLevel:ctx.assuranceLevel}});
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
    await tenantTx<any[]>(sql,ctx,txn=>[txn`insert into storage.object_metadata(tenant_id,object_key,original_name,content_type,size_bytes,created_by,status) values(${ctx.tenantId}::uuid,${key},${name},'application/pdf',${size},${ctx.userId}::uuid,'pending')`]);
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
    const [metaRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select content_type,original_name,status from storage.object_metadata where tenant_id=${ctx.tenantId}::uuid and object_key=${key} and status='active' limit 1`]);
    const meta=metaRows[0] as any;if(!meta)return error("not_found","Official report PDF object is not available",404,requestId);
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
    const [metaRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select id,status from storage.object_metadata where tenant_id=${ctx.tenantId}::uuid and object_key=${key} and status='active' limit 1`]);
    const meta=metaRows[0] as any;if(!meta)return error("not_found","Report PDF object was not found",404,requestId);
    await env.OBJECTS.delete(key);
    await tenantTx<any[]>(sql,ctx,txn=>[txn`update storage.object_metadata set status='deleted',deleted_at=now() where id=${meta.id}::uuid`]);
    return json({ok:true,objectKey:key});
  }
  if(method==="POST"&&p==="/api/files/upload-url"){
    const b=await readJson<any>(request),kind=String(b.kind||"document").replace(/[^a-z0-9_-]/gi,"_").slice(0,40),name=String(b.filename||"file").replace(/[^a-zA-Z0-9._-]/g,"_").slice(0,120),type=String(b.contentType||"application/octet-stream");
    if(kind==="report-pdfs")return error("forbidden","Use the report PDF upload endpoint",403,requestId);
    const size=Number(b.size||0);if(size<=0||size>20*1024*1024)return error("invalid_file_size","File size must be between 1 byte and 20 MB",422,requestId);
    const allowed=["image/","application/pdf","text/csv","application/vnd.openxmlformats-officedocument"];
    if(!allowed.some(x=>type.startsWith(x)))return error("invalid_content_type","This file type is not allowed",422,requestId);
    const key=`tenants/${ctx.tenantId}/${kind}/${crypto.randomUUID()}-${name}`;
    await tenantTx<any[]>(sql,ctx,txn=>[txn`insert into storage.object_metadata(tenant_id,object_key,original_name,content_type,size_bytes,created_by,status) values(${ctx.tenantId}::uuid,${key},${name},${type},${size},${ctx.userId}::uuid,'pending')`]);
    // R2 native binding does not expose public credentials. Upload is proxied by the Worker in the dedicated PUT route.
    return json({objectKey:key,uploadUrl:`/api/files/upload?key=${encodeURIComponent(key)}`,method:"PUT",expiresInSeconds:900});
  }
  if(method==="PUT"&&p==="/api/files/upload"){
    const key=url.searchParams.get("key")||"";if(!key.startsWith(`tenants/${ctx.tenantId}/`))return error("forbidden","Invalid object scope",403,requestId);
    const [meta]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select id,content_type,size_bytes,status from storage.object_metadata where tenant_id=${ctx.tenantId}::uuid and object_key=${key} and status='pending' limit 1`]);if(!meta[0])return error("not_found","Upload authorization was not found",404,requestId);
    const expectedSize=Number((meta[0] as any).size_bytes);
    const expectedType=String((meta[0] as any).content_type).toLowerCase();
    const receivedType=String(request.headers.get("content-type")||"").split(";")[0].trim().toLowerCase();
    if(receivedType!==expectedType)return error("invalid_content_type","Upload content type does not match authorization",415,requestId);
    const bytes=await request.arrayBuffer();
    if(bytes.byteLength!==expectedSize)return error("invalid_file_size","Upload size does not match authorization",413,requestId);
    await env.OBJECTS.put(key,bytes,{httpMetadata:{contentType:expectedType}});
    await tenantTx<any[]>(sql,ctx,txn=>[txn`update storage.object_metadata set status='active',stored_at=now() where id=${(meta[0] as any).id}::uuid`]);
    return json({ok:true,objectKey:key,size:bytes.byteLength});
  }
  if(method==="GET"&&p==="/api/files/download"){
    const key=url.searchParams.get("key")||"";
    if(!key.startsWith(`tenants/${ctx.tenantId}/`))return error("forbidden","Invalid object scope",403,requestId);
    if(key.startsWith(`tenants/${ctx.tenantId}/report-pdfs/`))return error("forbidden","Use the guarded report PDF download endpoint",403,requestId);
    const [meta]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select content_type,original_name from storage.object_metadata where tenant_id=${ctx.tenantId}::uuid and object_key=${key} and status='active' limit 1`]);
    if(!meta[0])return error("not_found","File not found",404,requestId);
    const obj=await env.OBJECTS.get(key);if(!obj)return error("not_found","File not found",404,requestId);
    const h=new Headers();obj.writeHttpMetadata(h);h.set("content-type",String((meta[0] as any).content_type));h.set("content-disposition",`attachment; filename*=UTF-8''${encodeURIComponent(String((meta[0] as any).original_name))}`);h.set("cache-control","private, no-store");return new Response(obj.body,{headers:h});
  }
  return error("not_found","Endpoint not found",404,requestId);
}
