import type { Env, SessionContext } from "./types";
import { db, tenantTx } from "./db";
import { readJson, json, error } from "./http";
import { authenticate, login, completeMfa, logout, setCookie, clearCookie } from "./auth";
import { verifyTurnstile } from "./turnstile";
import { platformRoute } from "./platform-routes";

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
    return json({authenticated:true,user:{id:ctx.userId,email:ctx.email,displayName:ctx.displayName},membership:{tenantId:ctx.tenantId,role:ctx.role,roleLabel:ctx.role.replaceAll('_',' ')},session:{id:ctx.sessionId,assuranceLevel:ctx.assuranceLevel}});
  }
  const ctx=await authed(request,env),sql=db(env);
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
  if(method==="POST"&&p==="/api/files/upload-url"){
    const b=await readJson<any>(request),kind=String(b.kind||"document").replace(/[^a-z0-9_-]/gi,"_").slice(0,40),name=String(b.filename||"file").replace(/[^a-zA-Z0-9._-]/g,"_").slice(0,120),type=String(b.contentType||"application/octet-stream");
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
    const key=url.searchParams.get("key")||"";if(!key.startsWith(`tenants/${ctx.tenantId}/`))return error("forbidden","Invalid object scope",403,requestId);const [meta]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select content_type,original_name from storage.object_metadata where tenant_id=${ctx.tenantId}::uuid and object_key=${key} and status='active' limit 1`]);if(!meta[0])return error("not_found","File not found",404,requestId);const obj=await env.OBJECTS.get(key);if(!obj)return error("not_found","File not found",404,requestId);const h=new Headers();obj.writeHttpMetadata(h);h.set("content-type",String((meta[0] as any).content_type));h.set("content-disposition",`attachment; filename*=UTF-8''${encodeURIComponent(String((meta[0] as any).original_name))}`);h.set("cache-control","private, no-store");return new Response(obj.body,{headers:h});
  }
  return error("not_found","Endpoint not found",404,requestId);
}
