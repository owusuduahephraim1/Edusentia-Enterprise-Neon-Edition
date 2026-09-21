import JSZip from "jszip";
import type { Env, PlatformSessionContext } from "./types";
import type { Sql } from "./db";
import { db } from "./db";

const MAX_ARCHIVE_BYTES=48*1024*1024;
const MAX_UNCOMPRESSED_BYTES=512*1024*1024;
const MAX_FILES=10000;
const TEMPLATE_PREFIX="platform/package-templates";
const ARTIFACT_PREFIX="platform/generated-packages";
const PACKAGE_VERSION="neon-v1.0.0-r42";
const REQUIRED_FILES=[
  "frontend/index.html",
  "frontend/app.js",
  "frontend/config.js",
  "worker/package.json",
  "database/install-master.sh",
  "database/tenant-template/install.sh",
  "release/manifest.json"
] as const;
const enc=new TextEncoder(),dec=new TextDecoder();

type PackageBody=Record<string,unknown>;
type SigningContext={
  keyId:string;
  publicJwk:JsonWebKey;
  fingerprint:string;
  privateKey:CryptoKey;
};
type TemplateValidation={
  root:string;
  fileCount:number;
  uncompressedBytes:number;
  release:Record<string,unknown>;
};

function fail(message:string,code="package_error",status=400):never{
  throw Object.assign(new Error(message),{code,status});
}
function clean(value:unknown,max=500){return String(value??"").trim().slice(0,max);}
function uuid(value:unknown){const v=clean(value,64);return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v)?v:"";}
function owned(bytes:Uint8Array):ArrayBuffer{const c=new Uint8Array(bytes.byteLength);c.set(bytes);return c.buffer;}
function safePath(value:string){
  const path=String(value||"").replace(/^\/+/, "");
  if(!path||path.includes("\0")||path.includes("\\")||path.startsWith("/")||/^[A-Za-z]:/.test(path)||path.split("/").some(p=>p==="."||p===".."))fail("Unsafe package path","package_path_invalid",422);
  return path;
}
function b64url(bytes:Uint8Array){let s="";for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");}
function unb64url(value:string){const n=value.replaceAll("-","+").replaceAll("_","/")+"=".repeat((4-value.length%4)%4);const s=atob(n);return Uint8Array.from(s,c=>c.charCodeAt(0));}
function decodeBase64(value:string){
  const normalized=String(value||"").replace(/^data:[^,]+,/,"").replace(/\s+/g,"");
  if(!normalized)return new Uint8Array();
  try{const s=atob(normalized);return Uint8Array.from(s,c=>c.charCodeAt(0));}
  catch{fail("Template archive is not valid base64","package_archive_invalid",422);}
}
function canonicalise(value:unknown):unknown{
  if(Array.isArray(value))return value.map(canonicalise);
  if(value&&typeof value==="object"){
    return Object.fromEntries(Object.entries(value as Record<string,unknown>).sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>[k,canonicalise(v)]));
  }
  return value;
}
function canonicalJson(value:unknown){return JSON.stringify(canonicalise(value));}
async function sha256(bytes:Uint8Array){
  const d=new Uint8Array(await crypto.subtle.digest("SHA-256",owned(bytes)));
  return Array.from(d,b=>b.toString(16).padStart(2,"0")).join("");
}
async function transferKey(env:Env){
  const secret=String(env.PACKAGE_TRANSFER_SIGNING_SECRET||env.BACKUP_SIGNING_SECRET||env.SESSION_PEPPER||"");
  if(secret.length<32)fail("Package transfer signing secret is unavailable","package_signing_unavailable",503);
  return crypto.subtle.importKey("raw",enc.encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign","verify"]);
}
async function signTransfer(env:Env,payload:Record<string,unknown>){
  const body=b64url(enc.encode(JSON.stringify(payload)));
  const sig=b64url(new Uint8Array(await crypto.subtle.sign("HMAC",await transferKey(env),enc.encode(body))));
  return `${body}.${sig}`;
}
async function verifyTransfer(env:Env,token:string){
  const [body,sig]=String(token||"").split(".");
  if(!body||!sig)return null;
  const ok=await crypto.subtle.verify("HMAC",await transferKey(env),owned(unb64url(sig)),enc.encode(body));
  if(!ok)return null;
  const payload=JSON.parse(dec.decode(unb64url(body))) as Record<string,unknown>;
  if(!payload.exp||Date.now()>Number(payload.exp)*1000)return null;
  return payload;
}
function publicJwkOf(privateJwk:JsonWebKey):JsonWebKey{
  const {d, ...publicJwk}=privateJwk as JsonWebKey & {d?:string};
  return publicJwk;
}
async function signingContext(env:Env,sql:Sql):Promise<SigningContext>{
  const raw=String(env.RCE_PACKAGE_SIGNING_PRIVATE_JWK||"").trim();
  if(!raw)fail("RCE_PACKAGE_SIGNING_PRIVATE_JWK is required for package generation","package_signing_unavailable",503);
  let privateJwk:JsonWebKey;
  try{privateJwk=JSON.parse(raw) as JsonWebKey;}catch{fail("Package signing JWK is invalid JSON","package_signing_invalid",503);}
  if(privateJwk.kty!=="EC"||privateJwk.crv!=="P-256"||!privateJwk.d||!privateJwk.x||!privateJwk.y)fail("Package signing JWK must be a private P-256 EC key","package_signing_invalid",503);
  const publicJwk=publicJwkOf(privateJwk),fingerprint=await sha256(enc.encode(canonicalJson(publicJwk)));
  const keyId=clean(env.RCE_PACKAGE_SIGNING_KEY_ID,120)||`eds-p256-${fingerprint.slice(0,20)}`;
  if(!/^[A-Za-z0-9._:-]{6,120}$/.test(keyId))fail("Package signing key ID is invalid","package_signing_invalid",503);
  const existing=await sql`select key_id,public_fingerprint from platform.package_signing_keys where key_id=${keyId} limit 1`;
  if(existing[0]&&String((existing[0] as any).public_fingerprint)!==fingerprint)fail("Package signing key ID conflicts with the registered signing identity","package_signing_conflict",409);
  await sql`insert into platform.package_signing_keys(key_id,public_jwk,public_fingerprint,active,last_seen_at)
    values(${keyId},${JSON.stringify(publicJwk)}::jsonb,${fingerprint},true,now())
    on conflict(key_id) do update set active=true,last_seen_at=now()`;
  const privateKey=await crypto.subtle.importKey("jwk",privateJwk,{name:"ECDSA",namedCurve:"P-256"},false,["sign"]);
  return {keyId,publicJwk,fingerprint,privateKey};
}
async function signText(text:string,key:CryptoKey){
  return b64url(new Uint8Array(await crypto.subtle.sign({name:"ECDSA",hash:"SHA-256"},key,enc.encode(text))));
}

async function validateTemplate(bytes:Uint8Array):Promise<TemplateValidation>{
  if(bytes.byteLength<1024||bytes.byteLength>MAX_ARCHIVE_BYTES)fail("Package template ZIP size is outside the permitted range","package_template_size",413);
  const zip=await JSZip.loadAsync(owned(bytes),{checkCRC32:true});
  const entries=Object.values(zip.files).filter(e=>!e.dir);
  if(entries.length<1||entries.length>MAX_FILES)fail("Package template contains an unsafe number of files","package_template_resources",422);
  let total=0;
  for(const entry of entries){
    safePath(entry.name);
    const size=Number((entry as any)?._data?.uncompressedSize||0);
    if(size<0||size>MAX_UNCOMPRESSED_BYTES)fail(`Template file is too large: ${entry.name}`,"package_template_resources",422);
    total+=size;if(total>MAX_UNCOMPRESSED_BYTES)fail("Package template uncompressed size exceeds 512 MiB","package_template_resources",422);
  }
  const roots=[...new Set(entries.filter(e=>e.name.endsWith("frontend/index.html")).map(e=>e.name.slice(0,-"frontend/index.html".length)))];
  if(roots.length!==1)fail("Template must contain exactly one Edusentia Neon repository root","package_template_layout",422);
  const root=roots[0];
  for(const required of REQUIRED_FILES)if(!zip.file(`${root}${required}`))fail(`Template is missing required file: ${required}`,"package_template_layout",422);
  let release:Record<string,unknown>;
  try{release=JSON.parse(await zip.file(`${root}release/manifest.json`)!.async("string")) as Record<string,unknown>;}
  catch{fail("release/manifest.json is invalid","package_template_release",422);}
  const workerSources=entries.filter(e=>e.name.startsWith(`${root}worker/src/`)&&e.name.endsWith(".ts"));
  for(const entry of workerSources){
    const source=await entry.async("string");
    if(/@supabase\/supabase-js|supabase\.co\/functions\/v1|createClient\([^)]*SUPABASE/i.test(source))fail(`Supabase runtime dependency found in template: ${entry.name}`,"package_template_provider",422);
  }
  return {root,fileCount:entries.length,uncompressedBytes:total,release};
}
async function packageTemplate(sql:Sql){
  const rows=await sql`select * from platform.package_templates where active=true order by updated_at desc limit 1`;
  if(!rows[0])fail("No active Neon package template is installed","package_template_missing",409);
  return rows[0] as any;
}
function artifactName(tenantCode:string,id:string){return `Edusentia-Neon-${tenantCode}-${id.slice(0,8)}.zip`;}
function templateStageKey(actor:string,id:string){return `${TEMPLATE_PREFIX}/staging/${actor}/${id}.zip`;}
function templateActiveKey(id:string,version:string){return `${TEMPLATE_PREFIX}/active/${id}/Edusentia-Neon-Template-${version.replace(/[^A-Za-z0-9._-]+/g,"-")}.zip`;}
function artifactKey(tenantCode:string,id:string,filename:string){return `${ARTIFACT_PREFIX}/${tenantCode}/${id}/${filename}`;}

async function activateTemplateBytes(env:Env,sql:Sql,ctx:PlatformSessionContext,bytes:Uint8Array,sourceKey:string,filename:string,receiptDigest=""){
  const digest=await sha256(bytes);
  if(receiptDigest&&receiptDigest.toLowerCase()!==digest)fail("Uploaded template does not match its browser SHA-256 receipt","package_template_checksum",422);
  const validation=await validateTemplate(bytes),id=crypto.randomUUID(),version=clean(validation.release.version||validation.release.releaseVersion||PACKAGE_VERSION,80)||PACKAGE_VERSION;
  const objectKey=templateActiveKey(id,version);
  await env.OBJECTS.put(objectKey,owned(bytes),{httpMetadata:{contentType:"application/zip"},customMetadata:{sha256:digest,templateId:id,packageVersion:version}});
  try{
    await sql.transaction([
      sql`update platform.package_templates set active=false,updated_at=now() where active=true`,
      sql`insert into platform.package_templates(id,package_version,object_key,sha256,file_size,required_files,validation,active,uploaded_by)
        values(${id}::uuid,${version},${objectKey},${digest},${bytes.byteLength}::bigint,${JSON.stringify(REQUIRED_FILES)}::jsonb,
          ${JSON.stringify({file_count:validation.fileCount,uncompressed_bytes:validation.uncompressedBytes,release:validation.release,source_filename:filename})}::jsonb,true,${ctx.userId}::uuid)`,
      sql`insert into platform.package_events(actor_user_id,action,template_id,details)
        values(${ctx.userId}::uuid,'package.template.activated',${id}::uuid,${JSON.stringify({sha256:digest,file_size:bytes.byteLength,source_key:sourceKey})}::jsonb)`
    ]);
  }catch(e){await env.OBJECTS.delete(objectKey).catch(()=>undefined);throw e;}
  if(sourceKey&&sourceKey!==objectKey)await env.OBJECTS.delete(sourceKey).catch(()=>undefined);
  return {id,package_version:version,object_key:objectKey,sha256:digest,file_size:bytes.byteLength,active:true,validation:{file_count:validation.fileCount,uncompressed_bytes:validation.uncompressedBytes}};
}

async function generateArtifact(env:Env,sql:Sql,ctx:PlatformSessionContext,body:PackageBody,reason:string){
  const tenantId=uuid(body.tenant_id),tenantCode=clean(body.tenant_code,60).toUpperCase();
  const rows=tenantId
    ?await sql`select t.*,p.name plan_name,p.limits,p.feature_flags,p.billing_cycle
       from platform.tenant_control t left join platform.license_plans p on p.code=t.plan_code
       where t.tenant_id=${tenantId}::uuid limit 1`
    :await sql`select t.*,p.name plan_name,p.limits,p.feature_flags,p.billing_cycle
       from platform.tenant_control t left join platform.license_plans p on p.code=t.plan_code
       where upper(t.tenant_code)=${tenantCode} limit 1`;
  const tenant=rows[0] as any;if(!tenant)fail("Tenant was not found","tenant_not_found",404);
  if(!["active","provisioning","suspended"].includes(String(tenant.status)))fail("Tenant status does not permit package generation","package_tenant_state",409);
  const template=await packageTemplate(sql),source=await env.OBJECTS.get(String(template.object_key));
  if(!source)fail("Active package template is missing from R2","package_template_missing_r2",409);
  const templateBytes=new Uint8Array(await source.arrayBuffer());
  if(await sha256(templateBytes)!==String(template.sha256))fail("Active package template checksum no longer matches its catalog record","package_template_checksum",409);
  const validation=await validateTemplate(templateBytes),zip=await JSZip.loadAsync(owned(templateBytes),{checkCRC32:true});
  const artifactId=crypto.randomUUID(),filename=artifactName(String(tenant.tenant_code),artifactId),generatedAt=new Date().toISOString();
  const manifest={
    format_version:1,
    artifact_id:artifactId,
    package_version:PACKAGE_VERSION,
    source_template_id:String(template.id),
    source_template_sha256:String(template.sha256),
    generated_at:generatedAt,
    reason,
    backend:{database:"neon-postgresql",object_storage:"cloudflare-r2",runtime:"cloudflare-worker",supabase_dependency:false},
    release:{control_schema:"0025",tenant_runtime_schema:"0020",tenant_compatibility_schema:"0048",certified_rpc_count:172},
    tenant:{
      id:String(tenant.tenant_id),code:String(tenant.tenant_code),school_name:String(tenant.school_name),
      institution_type:String(tenant.institution_type),status:String(tenant.status),plan_code:String(tenant.plan_code||""),
      license_status:String(tenant.license_status||""),license_period_type:String(tenant.license_period_type||""),
      license_started_at:tenant.license_started_at||null,license_expires_at:tenant.license_expires_at||null,
      license_grace_ends_at:tenant.license_grace_ends_at||null
    },
    entitlement:{plan_name:String(tenant.plan_name||""),billing_cycle:String(tenant.billing_cycle||""),limits:tenant.limits||{},feature_flags:tenant.feature_flags||{}},
    api:{base_url:String(env.APP_ORIGIN||"")}
  };
  const signing=await signingContext(env,sql),canonical=canonicalJson(manifest),signature=await signText(canonical,signing.privateKey);
  zip.file(`${validation.root}EDUSENTIA_NEON_PACKAGE.json`,JSON.stringify(manifest,null,2));
  zip.file(`${validation.root}EDUSENTIA_NEON_PACKAGE_SIGNATURE.json`,JSON.stringify({
    algorithm:"ECDSA-P256-SHA256",key_id:signing.keyId,public_fingerprint:signing.fingerprint,
    public_jwk:signing.publicJwk,signature,canonical_manifest_sha256:await sha256(enc.encode(canonical))
  },null,2));
  const output=await zip.generateAsync({type:"uint8array",compression:"DEFLATE",compressionOptions:{level:6}});
  if(output.byteLength>MAX_ARCHIVE_BYTES)fail("Generated package exceeds the 48 MiB distribution limit","package_too_large",413);
  const digest=await sha256(output),objectKey=artifactKey(String(tenant.tenant_code),artifactId,filename);
  await env.OBJECTS.put(objectKey,owned(output),{httpMetadata:{contentType:"application/zip"},customMetadata:{sha256:digest,artifactId,tenantCode:String(tenant.tenant_code),signingKeyId:signing.keyId}});
  try{
    await sql.transaction([
      sql`update platform.package_artifacts set status='revoked',revoked_at=now(),revoked_by=${ctx.userId}::uuid
        where tenant_id=${tenant.tenant_id}::uuid and status='ready'`,
      sql`insert into platform.package_artifacts(
          id,tenant_id,tenant_code,school_name,plan_code,package_version,template_id,object_key,filename,sha256,file_size,
          status,signing_key_id,public_fingerprint,signature,manifest,metadata,generated_by
        ) values(
          ${artifactId}::uuid,${tenant.tenant_id}::uuid,${String(tenant.tenant_code)},${String(tenant.school_name)},${String(tenant.plan_code||"")},
          ${PACKAGE_VERSION},${template.id}::uuid,${objectKey},${filename},${digest},${output.byteLength}::bigint,'ready',
          ${signing.keyId},${signing.fingerprint},${signature},${JSON.stringify(manifest)}::jsonb,
          ${JSON.stringify({template_validation:validation,generated_reason:reason})}::jsonb,${ctx.userId}::uuid
        )`,
      sql`insert into platform.package_events(actor_user_id,action,artifact_id,template_id,details)
        values(${ctx.userId}::uuid,${reason==='renew_or_upgrade'?'package.artifact.renewed':'package.artifact.generated'},
          ${artifactId}::uuid,${template.id}::uuid,${JSON.stringify({tenant_code:tenant.tenant_code,sha256:digest,file_size:output.byteLength,signing_key_id:signing.keyId})}::jsonb)`
    ]);
  }catch(e){await env.OBJECTS.delete(objectKey).catch(()=>undefined);throw e;}
  return {id:artifactId,tenant_id:tenant.tenant_id,tenant_code:tenant.tenant_code,school_name:tenant.school_name,filename,object_key:objectKey,sha256:digest,file_size:output.byteLength,status:"ready",signing_key_id:signing.keyId,public_fingerprint:signing.fingerprint,generated_at:generatedAt};
}

async function status(sql:Sql,env:Env){
  const [templates,artifacts,reconciliation,keys]=await Promise.all([
    sql`select * from platform.package_templates order by active desc,updated_at desc limit 20`,
    sql`select id,tenant_id,tenant_code,school_name,plan_code,package_version,filename,sha256,file_size,status,signing_key_id,public_fingerprint,generated_at,revoked_at,download_count,last_downloaded_at from platform.package_artifacts order by generated_at desc limit 100`,
    sql`select * from platform.package_reconciliation where status in('pending','failed') order by updated_at desc limit 100`,
    sql`select key_id,public_fingerprint,active,first_seen_at,last_seen_at from platform.package_signing_keys order by last_seen_at desc limit 20`
  ]);
  return {ok:true,release:PACKAGE_VERSION,storage_provider:"cloudflare-r2",signing_configured:Boolean(env.RCE_PACKAGE_SIGNING_PRIVATE_JWK),templates,artifacts,reconciliation,signing_keys:keys};
}

export async function handlePlatformPackageTransfer(request:Request,env:Env):Promise<Response|null>{
  const url=new URL(request.url);if(url.pathname!=="/api/platform/package-transfer")return null;
  const payload=await verifyTransfer(env,url.searchParams.get("token")||"");
  if(!payload)return new Response("Invalid or expired package transfer",{status:403,headers:{"cache-control":"no-store"}});
  const op=String(payload.op||""),key=safePath(String(payload.key||""));
  if(op==="template-upload"){
    if(request.method!=="PUT"||!key.startsWith(`${TEMPLATE_PREFIX}/staging/`))return new Response("Invalid package upload scope",{status:403});
    const max=Math.min(MAX_ARCHIVE_BYTES,Math.max(1,Number(payload.max_bytes||MAX_ARCHIVE_BYTES)));
    const expected=Math.max(0,Number(payload.expected_size||0)),length=Number(request.headers.get("content-length")||0);
    if((length&&length>max)||(expected&&length&&length!==expected))return new Response("Template upload size mismatch",{status:413});
    if(!request.body)return new Response("Template upload body is required",{status:400});
    await env.OBJECTS.put(key,request.body,{httpMetadata:{contentType:"application/zip"}});
    const head=await env.OBJECTS.head(key);
    if(!head||head.size<1024||head.size>max||(expected&&head.size!==expected)){await env.OBJECTS.delete(key).catch(()=>undefined);return new Response("Template upload size mismatch",{status:413});}
    return new Response(JSON.stringify({ok:true,path:key,size:head.size}),{headers:{"content-type":"application/json","cache-control":"no-store"}});
  }
  if(op==="artifact-download"){
    if(request.method!=="GET"||!key.startsWith(`${ARTIFACT_PREFIX}/`))return new Response("Invalid package download scope",{status:403});
    const object=await env.OBJECTS.get(key);if(!object)return new Response("Package not found",{status:404});
    const h=new Headers();object.writeHttpMetadata(h);h.set("content-type","application/zip");h.set("cache-control","private, no-store");h.set("x-content-type-options","nosniff");
    const filename=clean(payload.filename,180).replace(/[^A-Za-z0-9._-]+/g,"-")||"Edusentia-Neon-Package.zip";
    h.set("content-disposition",`attachment; filename="${filename}"`);
    return new Response(object.body,{headers:h});
  }
  return new Response("Unsupported package transfer",{status:400});
}

export async function platformPackageMaintenance(env:Env,sql:Sql=db(env)){
  const now=Date.now(),staleBefore=now-24*60*60*1000;let staleStagingRemoved=0,missing=0,resolved=0,deletedObjects=0;
  let cursor:string|undefined;
  do{
    const list=await env.OBJECTS.list({prefix:`${TEMPLATE_PREFIX}/staging/`,cursor,limit:1000});
    for(const object of list.objects){
      if(object.uploaded.getTime()<staleBefore){await env.OBJECTS.delete(object.key);staleStagingRemoved++;}
    }
    cursor=list.truncated?list.cursor:undefined;
  }while(cursor);

  const templates=await sql`select id,object_key,active from platform.package_templates`;
  const artifacts=await sql`select id,object_key,status from platform.package_artifacts`;
  for(const row of [...templates.map((x:any)=>({...x,kind:"template"})),...artifacts.map((x:any)=>({...x,kind:"artifact"}))]){
    const head=await env.OBJECTS.head(String(row.object_key));
    if(row.kind==="artifact"&&row.status==="deleted"){
      if(head){await env.OBJECTS.delete(String(row.object_key));deletedObjects++;}
      await sql`insert into platform.package_reconciliation(object_key,object_kind,status,details,last_error,updated_at)
        values(${String(row.object_key)},'artifact','resolved','{"reason":"deleted_artifact_absent"}'::jsonb,'',now())
        on conflict(object_kind,object_key) do update set status='resolved',details=excluded.details,last_error='',updated_at=now()`;
      continue;
    }
    if(!head){
      missing++;
      await sql`insert into platform.package_reconciliation(object_key,object_kind,status,details,last_error,updated_at)
        values(${String(row.object_key)},${row.kind},'failed',${JSON.stringify({id:row.id,status:row.status??row.active})}::jsonb,'R2 object is missing',now())
        on conflict(object_kind,object_key) do update set status='failed',details=excluded.details,last_error=excluded.last_error,updated_at=now()`;
    }else{
      resolved++;
      await sql`insert into platform.package_reconciliation(object_key,object_kind,status,details,last_error,updated_at)
        values(${String(row.object_key)},${row.kind},'resolved','{}'::jsonb,'',now())
        on conflict(object_kind,object_key) do update set status='resolved',details='{}'::jsonb,last_error='',updated_at=now()`;
    }
  }
  const result={ok:missing===0,storage_provider:"cloudflare-r2",stale_staging_removed:staleStagingRemoved,missing_objects:missing,resolved_objects:resolved,deleted_objects_removed:deletedObjects};
  console.log(JSON.stringify({level:missing?"error":"info",service:"platform-package-maintenance",...result}));
  return result;
}

export async function handlePlatformPackageAction(env:Env,sql:Sql,ctx:PlatformSessionContext,body:PackageBody,origin:string){
  const action=clean(body.action||"status",80);
  if(action==="status")return status(sql,env);

  if(action==="create_template_upload"){
    const filename=clean(body.filename,180);
    const size=Number(body.file_size||0);
    if(!/\.zip$/i.test(filename)||size<1024||size>MAX_ARCHIVE_BYTES)fail("A valid template ZIP up to 48 MiB is required","package_template_upload",422);
    const key=templateStageKey(ctx.userId,crypto.randomUUID());
    const token=await signTransfer(env,{op:"template-upload",key,actor:ctx.userId,expected_size:size,max_bytes:MAX_ARCHIVE_BYTES,exp:Math.floor(Date.now()/1000)+900});
    return {ok:true,storage_path:key,expires_in_seconds:900,token:`${origin}/api/platform/package-transfer?token=${encodeURIComponent(token)}`};
  }

  if(action==="activate_template_upload"){
    const key=safePath(clean(body.storage_path,600)),requiredPrefix=`${TEMPLATE_PREFIX}/staging/${ctx.userId}/`;
    if(!key.startsWith(requiredPrefix))fail("Template staging path is outside the current administrator scope","package_template_scope",403);
    const object=await env.OBJECTS.get(key);if(!object)fail("Uploaded template was not found","package_template_missing",404);
    const bytes=new Uint8Array(await object.arrayBuffer());
    return {ok:true,template:await activateTemplateBytes(env,sql,ctx,bytes,key,clean(body.filename,180),clean((body.client_validation_receipt as any)?.archive_sha256||body.archive_sha256,64).toLowerCase())};
  }

  if(action==="upload_template"){
    const bytes=decodeBase64(clean(body.archive_base64,MAX_ARCHIVE_BYTES*2));
    if(bytes.byteLength<1024||bytes.byteLength>MAX_ARCHIVE_BYTES)fail("Template archive size is invalid","package_template_size",413);
    const stage=templateStageKey(ctx.userId,crypto.randomUUID());
    await env.OBJECTS.put(stage,owned(bytes),{httpMetadata:{contentType:"application/zip"}});
    return {ok:true,template:await activateTemplateBytes(env,sql,ctx,bytes,stage,clean(body.filename,180)||"Edusentia-Neon-Template.zip",clean(body.archive_sha256,64).toLowerCase())};
  }

  if(action==="generate"||action==="renew_or_upgrade"){
    return {ok:true,artifact:await generateArtifact(env,sql,ctx,body,action)};
  }

  if(action==="download"){
    const id=uuid(body.artifact_id);if(!id)fail("artifact_id is required","validation_error",422);
    const rows=await sql`select * from platform.package_artifacts where id=${id}::uuid limit 1`,artifact=rows[0] as any;
    if(!artifact||artifact.status!=="ready")fail("Ready package artifact was not found","package_not_downloadable",404);
    const head=await env.OBJECTS.head(String(artifact.object_key));
    if(!head||head.size!==Number(artifact.file_size)||String(head.customMetadata?.sha256||"")!==String(artifact.sha256))fail("Package artifact failed R2 integrity preflight","package_integrity_failed",409);
    const token=await signTransfer(env,{op:"artifact-download",key:String(artifact.object_key),filename:String(artifact.filename),artifact_id:id,exp:Math.floor(Date.now()/1000)+600});
    await sql.transaction([
      sql`update platform.package_artifacts set download_count=download_count+1,last_downloaded_at=now() where id=${id}::uuid`,
      sql`insert into platform.package_events(actor_user_id,action,artifact_id,details) values(${ctx.userId}::uuid,'package.artifact.download_authorized',${id}::uuid,'{"expires_in_seconds":600}'::jsonb)`
    ]);
    return {ok:true,artifact_id:id,filename:artifact.filename,sha256:artifact.sha256,expires_in_seconds:600,url:`${origin}/api/platform/package-transfer?token=${encodeURIComponent(token)}`};
  }

  if(action==="revoke"){
    const id=uuid(body.artifact_id);if(!id)fail("artifact_id is required","validation_error",422);
    const reason=clean(body.reason,500);
    const rows=await sql`update platform.package_artifacts set status='revoked',revoked_at=now(),revoked_by=${ctx.userId}::uuid where id=${id}::uuid and status='ready' returning id`;
    if(!rows[0])fail("Only a ready package can be revoked","package_state_conflict",409);
    await sql`insert into platform.package_events(actor_user_id,action,artifact_id,details) values(${ctx.userId}::uuid,'package.artifact.revoked',${id}::uuid,${JSON.stringify({reason})}::jsonb)`;
    return {ok:true,id,status:"revoked"};
  }

  if(action==="restore"){
    const id=uuid(body.artifact_id);if(!id)fail("artifact_id is required","validation_error",422);
    const rows=await sql`select * from platform.package_artifacts where id=${id}::uuid limit 1`,artifact=rows[0] as any;
    if(!artifact||artifact.status!=="revoked")fail("Only a revoked package can be restored","package_state_conflict",409);
    if(!(await env.OBJECTS.head(String(artifact.object_key))))fail("Package R2 object is missing","package_missing_r2",409);
    await sql.transaction([
      sql`update platform.package_artifacts set status='revoked',revoked_at=coalesce(revoked_at,now()),revoked_by=${ctx.userId}::uuid where tenant_id=${artifact.tenant_id}::uuid and status='ready' and id<>${id}::uuid`,
      sql`update platform.package_artifacts set status='ready',revoked_at=null,revoked_by=null where id=${id}::uuid`,
      sql`insert into platform.package_events(actor_user_id,action,artifact_id,details) values(${ctx.userId}::uuid,'package.artifact.restored',${id}::uuid,'{}'::jsonb)`
    ]);
    return {ok:true,id,status:"ready"};
  }

  if(action==="delete"){
    const id=uuid(body.artifact_id);if(!id)fail("artifact_id is required","validation_error",422);
    const rows=await sql`update platform.package_artifacts set status='deleted',deleted_at=now() where id=${id}::uuid and status='revoked' returning object_key`;
    const row=rows[0] as any;if(!row)fail("Revoke the package before deletion","package_state_conflict",409);
    await sql`insert into platform.package_events(actor_user_id,action,artifact_id,details) values(${ctx.userId}::uuid,'package.artifact.deleted',${id}::uuid,'{}'::jsonb)`;
    await env.OBJECTS.delete(String(row.object_key)).catch(async e=>{
      await sql`insert into platform.package_reconciliation(object_key,object_kind,status,last_error,details,updated_at)
        values(${String(row.object_key)},'artifact','failed',${String((e as any)?.message||e)},'{"reason":"delete_failed"}'::jsonb,now())
        on conflict(object_kind,object_key) do update set status='failed',last_error=excluded.last_error,details=excluded.details,updated_at=now()`;
    });
    return {ok:true,id,status:"deleted"};
  }

  if(action==="finalize_replacement"){
    const replacement=uuid(body.replacement_artifact_id),previous=uuid(body.previous_artifact_id);
    if(!replacement||!previous)fail("replacement_artifact_id and previous_artifact_id are required","validation_error",422);
    const rows=await sql`select id,tenant_id,status from platform.package_artifacts where id in(${replacement}::uuid,${previous}::uuid)`;
    const next=rows.find((r:any)=>String(r.id)===replacement) as any,old=rows.find((r:any)=>String(r.id)===previous) as any;
    if(!next||!old||String(next.tenant_id)!==String(old.tenant_id)||next.status!=="ready")fail("Replacement package relationship is invalid","package_replacement_invalid",409);
    await sql`update platform.package_artifacts set status='revoked',revoked_at=now(),revoked_by=${ctx.userId}::uuid where id=${previous}::uuid and status<>'deleted'`;
    await sql`insert into platform.package_events(actor_user_id,action,artifact_id,details) values(${ctx.userId}::uuid,'package.artifact.replacement_finalized',${replacement}::uuid,${JSON.stringify({previous_artifact_id:previous})}::jsonb)`;
    return {ok:true,replacement_artifact_id:replacement,previous_artifact_id:previous};
  }

  if(action==="repair_package_storage"){
    return platformPackageMaintenance(env,sql);
  }

  if(action==="archive_events"){
    const days=Math.max(30,Math.min(3650,Number(body.older_than_days||180)||180));
    const countRows=await sql`select count(*)::int count from platform.package_events where created_at<now()-(${days}::text||' days')::interval`;
    const count=Number((countRows[0] as any)?.count||0);
    await sql`insert into platform.admin_audit_events(actor_user_id,action,target_type,target_id,details)
      values(${ctx.userId}::uuid,'platform.package.events_archived','package_events','archive',${JSON.stringify({older_than_days:days,event_count:count})}::jsonb)`;
    await sql`delete from platform.package_events where created_at<now()-(${days}::text||' days')::interval`;
    return {ok:true,archived_events:count,older_than_days:days};
  }

  if(action==="clear_events"){
    if(clean(body.confirmation,80)!=="CLEAR PACKAGE EVENTS")fail("Typed confirmation is required","confirmation_required",422);
    const rows=await sql`with deleted as (delete from platform.package_events returning 1) select count(*)::int count from deleted`;
    return {ok:true,cleared_events:Number((rows[0] as any)?.count||0)};
  }

  if(action==="execute_restore_import"){
    return {ok:true,delegated:true,service:"tenant-backup-restore",endpoint:"/api/compat/functions/scheduled-backup",action:"execute_restore_import"};
  }

  fail("Unsupported platform package action","unsupported_action",400);
}
