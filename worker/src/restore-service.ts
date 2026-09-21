import JSZip from "jszip";
import type { Env, SessionContext } from "./types";
import type { TenantSql } from "./tenant-db";
import { tenantTx } from "./db";
import { performFullBackup } from "./backup-service";

const FORMAT_VERSION=2,SCHEMA_VERSION="7.4.0",MAX_UPLOAD=524288000;
const BACKUP_BUCKET="system-backups",RESTORE_PREFIX="restore-imports";
const RESTORABLE_TABLES=[
  "school_settings","profiles","id_card_settings","id_card_deletion_tombstones","teachers","headteachers",
  "academic_years","terms","classes","subjects","class_subjects","class_timetable_entries","school_prospectuses",
  "school_prospectus_sections","school_prospectus_items","school_prospectus_revisions","user_class_access","students",
  "student_guardians","guardian_links","enrollments","student_id_cards","id_card_events","staff_id_cards",
  "staff_id_card_events","class_attendance_registers","student_attendance_entries","grading_scales","assessment_schemes",
  "assessment_components","student_reports","subject_scores","subject_results","assessment_score_entries",
  "emergency_academic_delegations","emergency_academic_delegation_events","academic_period_controls",
  "report_correction_requests","report_correction_events","student_lifecycle_events","transcript_issuances",
  "certificate_templates","teacher_award_categories","certificate_batches","certificates","certificate_events",
  "report_workflow_events","report_revisions","report_publications","report_card_templates","notifications",
  "notification_outbox","import_batches","import_errors"
] as const;
const BUCKETS=[
  "student-photos","staff-photos","school-branding","report-pdfs",
  "headteacher-signatures","report-card-templates","certificate-pdfs","certificate-templates"
] as const;
const enc=new TextEncoder(),dec=new TextDecoder();

type StoredObject={source_bucket:string;source_path:string;backup_path:string;content_type:string;original_size:number;encrypted_size:number;checksum:string};
type Manifest={
  format_version:number;schema_version:string;backup_id:string;backup_key:string;generated_at:string;
  encryption:{algorithm:string;key_hint:string;payload_format:string};
  database:{path:string;checksum:string;row_counts:Record<string,number>;compressed_size:number;encrypted_size:number};
  storage:{buckets:string[];object_counts:Record<string,number>;total_bytes:number;objects:StoredObject[]};
  auth_users:{count:number;password_hashes_included:boolean;note:string};
};
type Payload={metadata?:Record<string,unknown>;tables?:Record<string,unknown[]>;auth_users?:Array<Record<string,unknown>>};

function fail(message:string,code="restore_failed",status=400):never{throw Object.assign(new Error(message),{code,status});}
function owned(bytes:Uint8Array){const copy=new Uint8Array(bytes.byteLength);copy.set(bytes);return copy.buffer;}
async function sha256(bytes:Uint8Array){const d=new Uint8Array(await crypto.subtle.digest("SHA-256",owned(bytes)));return Array.from(d,b=>b.toString(16).padStart(2,"0")).join("");}
function cleanPath(value:string){const path=String(value||"").replace(/^\/+/, "");if(!path||path.includes("\0")||path.includes("\\")||path.startsWith("/")||/^[A-Za-z]:/.test(path)||path.split("/").some(s=>s==="."||s===".."))fail("Unsafe restore path","restore_path_invalid",422);return path;}
function r2Key(tenantId:string,bucket:string,path:string){return `tenants/${tenantId}/${bucket}/${cleanPath(path)}`;}
function versionAtMost(source:string,current:string){const a=String(source||"0").split(".").map(x=>Number(x.replace(/\D.*/,""))||0),b=String(current||"0").split(".").map(x=>Number(x.replace(/\D.*/,""))||0);for(let i=0;i<Math.max(a.length,b.length);i++){if((a[i]||0)<(b[i]||0))return true;if((a[i]||0)>(b[i]||0))return false;}return true;}
function normalizeSchool(value:unknown){return String(value||"").normalize("NFKC").toLowerCase().replace(/[^a-z0-9]+/g," ").trim().replace(/\s+/g," ");}
function remap(value:unknown,map:Map<string,string>):unknown{if(typeof value==="string")return map.get(value)||value;if(Array.isArray(value))return value.map(v=>remap(v,map));if(value&&typeof value==="object")return Object.fromEntries(Object.entries(value as Record<string,unknown>).map(([k,v])=>[k,remap(v,map)]));return value;}

async function licence(sql:TenantSql,ctx:SessionContext){
  const [s,f]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.license_snapshot_for_role('system_admin') result`,
    txn`select public.license_feature_enabled('manual_backup') enabled`
  ]);
  const snap=(s[0] as any)?.result||{};
  if(snap.write_allowed!==true)fail(String(snap.warning||"The current licence does not permit restoration"),"licence_restricted",403);
  if((f[0] as any)?.enabled!==true)fail("Licence feature not included: manual_backup","licence_feature_not_included",403);
  return snap;
}
async function keyFrom(secret:string){
  if(secret.length<32)return null;
  const digest=new Uint8Array(await crypto.subtle.digest("SHA-256",enc.encode(secret)));
  return {key:await crypto.subtle.importKey("raw",owned(digest),{name:"AES-GCM"},false,["decrypt"]),hint:(await sha256(digest)).slice(0,16)};
}
async function restoreKeys(env:Env){
  const values=[String(env.RESTORE_IMPORT_KEY||""),String(env.BACKUP_ENCRYPTION_KEY||"")];
  if(env.TURNSTILE_TEST_MODE==="true")values.push(`edusentia:parity-backup:v1:${env.SESSION_PEPPER}`);
  const out:Array<{key:CryptoKey;hint:string}> = [],seen=new Set<string>();
  for(const v of values){if(!v||seen.has(v))continue;seen.add(v);const k=await keyFrom(v);if(k)out.push(k);}
  if(!out.length)fail("No restore encryption key is configured","restore_key_unavailable",503);
  return out;
}
async function decrypt(bytes:Uint8Array,key:CryptoKey){
  if(dec.decode(bytes.slice(0,5))!=="NISB2")fail("Unsupported encrypted backup payload","restore_format_invalid",422);
  return new Uint8Array(await crypto.subtle.decrypt({name:"AES-GCM",iv:owned(bytes.slice(5,17))},key,owned(bytes.slice(17))));
}
async function gunzip(bytes:Uint8Array){return new Uint8Array(await new Response(new Blob([owned(bytes)]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer());}

function b64url(bytes:Uint8Array){let s="";for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");}
function unb64url(value:string){const n=value.replaceAll("-","+").replaceAll("_","/")+"=".repeat((4-value.length%4)%4);const s=atob(n);return Uint8Array.from(s,c=>c.charCodeAt(0));}
async function transferKey(env:Env){return crypto.subtle.importKey("raw",enc.encode(String(env.BACKUP_SIGNING_SECRET||env.SESSION_PEPPER)),{name:"HMAC",hash:"SHA-256"},false,["sign","verify"]);}
async function signTransfer(env:Env,payload:Record<string,unknown>){const body=b64url(enc.encode(JSON.stringify(payload))),sig=b64url(new Uint8Array(await crypto.subtle.sign("HMAC",await transferKey(env),enc.encode(body))));return `${body}.${sig}`;}
async function verifyTransfer(env:Env,token:string){const [body,sig]=String(token||"").split(".");if(!body||!sig)return null;const ok=await crypto.subtle.verify("HMAC",await transferKey(env),owned(unb64url(sig)),enc.encode(body));if(!ok)return null;const payload=JSON.parse(dec.decode(unb64url(body))) as any;if(!payload?.exp||Date.now()>Number(payload.exp)*1000)return null;return payload;}

async function registerR2(sql:TenantSql,ctx:SessionContext,key:string,name:string,type:string,size:number){
  await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_register_r2_object(${ctx.tenantId}::uuid,${key},${name},${type},${size}::bigint,${ctx.userId}::uuid)`]);
}
async function markDeleted(sql:TenantSql,ctx:SessionContext,key:string){
  await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_mark_r2_deleted(${ctx.tenantId}::uuid,${key})`]);
}
async function restoreJob(sql:TenantSql,ctx:SessionContext,id:string){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_restore_job(${id}::uuid,${ctx.userId}::uuid) result`]);
  return (rows[0] as any)?.result||null;
}

export async function handleRestoreTransfer(request:Request,env:Env){
  const url=new URL(request.url);if(url.pathname!=="/api/restore/transfer")return null;
  if(request.method!=="PUT")return new Response("Method not allowed",{status:405});
  const payload=await verifyTransfer(env,url.searchParams.get("token")||"");
  if(!payload||payload.op!=="restore-upload")return new Response("Invalid or expired restore transfer",{status:403,headers:{"cache-control":"no-store"}});
  const key=String(payload.key||""),tenantId=String(payload.tenantId||""),expected=Number(payload.size||0);
  if(!key.startsWith(`tenants/${tenantId}/system-backups/${RESTORE_PREFIX}/`)||expected<1||expected>MAX_UPLOAD)return new Response("Invalid restore scope",{status:403});
  const type=String(request.headers.get("content-type")||"").split(";")[0].trim().toLowerCase();
  if(!["application/zip","application/x-zip-compressed","application/x-zip","multipart/x-zip","application/octet-stream"].includes(type))return new Response("Invalid content type",{status:415});
  if(!request.body)return new Response("Restore upload body is required",{status:400});
  await env.OBJECTS.put(key,request.body,{httpMetadata:{contentType:"application/zip"}});
  const head=await env.OBJECTS.head(key);
  if(!head||head.size!==expected){await env.OBJECTS.delete(key).catch(()=>undefined);return new Response("Restore upload size mismatch",{status:413});}
  return new Response(JSON.stringify({ok:true,size:head.size}),{headers:{"content-type":"application/json","cache-control":"no-store"}});
}

export async function prepareRestore(env:Env,sql:TenantSql,ctx:SessionContext,body:Record<string,unknown>,origin:string){
  if(ctx.role!=="system_admin"||ctx.assuranceLevel<2)fail("A verified System Administrator session is required","mfa_required",403);
  await licence(sql,ctx);
  const fileName=String(body.file_name||""),fileSize=Number(body.file_size||0),checksum=String(body.checksum||"").toLowerCase();
  if(!/\.zip$/i.test(fileName)||fileSize<1||fileSize>MAX_UPLOAD||!/^[a-f0-9]{64}$/.test(checksum))fail("A valid ZIP up to 500 MB, size and SHA-256 checksum are required","restore_upload_invalid",422);
  const path=`${RESTORE_PREFIX}/${crypto.randomUUID()}.zip`,key=r2Key(ctx.tenantId,BACKUP_BUCKET,path);
  const [jobRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.school_restore_begin(${fileName},${path},${checksum},${fileSize}::bigint,${ctx.userId}::uuid) job_id`]);
  const jobId=String((jobRows[0] as any)?.job_id||"");if(!jobId)fail("Restore job could not be created");
  const token=await signTransfer(env,{op:"restore-upload",tenantId:ctx.tenantId,key,size:fileSize,exp:Math.floor(Date.now()/1000)+900});
  return {job_id:jobId,path,token:`${origin}/api/restore/transfer?token=${encodeURIComponent(token)}`};
}

export async function cancelRestore(env:Env,sql:TenantSql,ctx:SessionContext,body:Record<string,unknown>){
  const id=String(body.job_id||"");if(!/^[0-9a-f-]{36}$/i.test(id))fail("Restore job is required","validation_error",422);
  const job=await restoreJob(sql,ctx,id);if(!job)fail("Restore job not found","not_found",404);
  if(["validating","restoring","completed"].includes(String(job.status)))fail("This restore job can no longer be cancelled","restore_not_cancellable",409);
  if(job.import_path){const key=r2Key(ctx.tenantId,BACKUP_BUCKET,String(job.import_path));await env.OBJECTS.delete(key).catch(()=>undefined);await markDeleted(sql,ctx,key).catch(()=>undefined);}
  await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.school_restore_set_status(${id}::uuid,'cancelled','Restore upload cancelled before validation.','No production data was changed.')`]);
  return {job_id:id,status:"cancelled"};
}

async function parseRestore(env:Env,ctx:SessionContext,bytes:Uint8Array,licenceSnapshot:any){
  const zip=await JSZip.loadAsync(owned(bytes),{checkCRC32:true});
  const files=Object.values(zip.files).filter(f=>!f.dir);
  if(files.length>10000)fail("Restore ZIP contains too many files","restore_zip_limit",413);
  let declared=0;
  for(const entry of files){cleanPath(entry.name);declared+=Number((entry as any)?._data?.uncompressedSize||0);}
  if(declared>1073741824)fail("Restore ZIP declares more than 1 GiB of uncompressed data","restore_zip_limit",413);
  const manifestEntry=zip.file("manifest.json.nisb"),databaseEntry=zip.file("database/database.json.gz.nisb");
  if(!manifestEntry||!databaseEntry)fail("Backup ZIP is missing its encrypted manifest or database payload","restore_package_invalid",422);
  const encryptedManifest=new Uint8Array(await manifestEntry.async("arraybuffer"));
  let manifest:Manifest|null=null,key:CryptoKey|null=null;
  for(const material of await restoreKeys(env)){try{const candidate=JSON.parse(dec.decode(await decrypt(encryptedManifest,material.key))) as Manifest;if(candidate&&typeof candidate==="object"){manifest=candidate;key=material.key;break;}}catch{}}
  if(!manifest||!key)fail("The imported backup could not be decrypted","restore_decryption_failed",422);
  if(manifest.format_version!==FORMAT_VERSION||!versionAtMost(manifest.schema_version,SCHEMA_VERSION))fail(`Unsupported backup format/schema ${manifest.format_version}/${manifest.schema_version}`,"restore_version_unsupported",422);
  if(!manifest.backup_key||!manifest.database?.checksum||!Array.isArray(manifest.storage?.objects))fail("Backup manifest inventory is incomplete","restore_manifest_invalid",422);
  const databaseBytes=await gunzip(await decrypt(new Uint8Array(await databaseEntry.async("arraybuffer")),key));
  if(await sha256(databaseBytes)!==manifest.database.checksum)fail("Database checksum verification failed","restore_checksum_failed",422);
  const payload=JSON.parse(dec.decode(databaseBytes)) as Payload,tables=payload.tables||{};
  if(String(payload.metadata?.backup_key||"")!==manifest.backup_key)fail("Database payload identity does not match manifest","restore_manifest_invalid",422);
  for(const [table,count] of Object.entries(manifest.database.row_counts||{})){const rows=table==="auth_users"?payload.auth_users:tables[table];if(!Array.isArray(rows)||rows.length!==Number(count))fail(`Row-count verification failed for ${table}`,"restore_row_count_failed",422);}
  for(const table of RESTORABLE_TABLES)if(tables[table]!==undefined&&!Array.isArray(tables[table]))fail(`Restore table payload is invalid for ${table}`,"restore_table_invalid",422);

  const students=Array.isArray(tables.students)?tables.students:[],teachers=Array.isArray(tables.teachers)?tables.teachers:[];
  const activeStudents=students.filter((r:any)=>String(r?.status??"active").toLowerCase()==="active"&&!r?.deleted_at).length;
  const activeTeachers=teachers.filter((r:any)=>r?.active!==false&&!r?.deleted_at).length;
  const plan=licenceSnapshot?.plan||{},maxStudents=Number(plan.max_students),maxTeachers=Number(plan.max_teachers);
  if(Number.isFinite(maxStudents)&&maxStudents>=0&&activeStudents>maxStudents)fail(`Backup contains ${activeStudents} active students but the current plan permits ${maxStudents}`,"restore_capacity_exceeded",409);
  if(Number.isFinite(maxTeachers)&&maxTeachers>=0&&activeTeachers>maxTeachers)fail(`Backup contains ${activeTeachers} active teachers but the current plan permits ${maxTeachers}`,"restore_capacity_exceeded",409);

  const settings=(Array.isArray(tables.school_settings)?tables.school_settings[0]:{}) as any;
  const sourceCode=String(settings?.tenant_code||"").toUpperCase(),sourceName=normalizeSchool(settings?.school_name);
  if(/^[A-Z]{3}-\d{6}$/.test(sourceCode)){if(sourceCode!==ctx.tenantCode)fail(`Backup belongs to tenant ${sourceCode}, not ${ctx.tenantCode}`,"restore_wrong_tenant",409);}
  else if(sourceName&&sourceName!==normalizeSchool(ctx.tenantName))fail("Backup school identity does not match this tenant","restore_wrong_tenant",409);

  const objects=(manifest.storage.objects||[]).filter(o=>(BUCKETS as readonly string[]).includes(o.source_bucket)),seen=new Set<string>(),counts:Record<string,number>={};
  for(const o of objects){
    const id=`${o.source_bucket}/${o.source_path}`;if(!o.source_path||seen.has(id))fail("Backup manifest has duplicate/missing storage path","restore_manifest_invalid",422);seen.add(id);cleanPath(o.source_path);
    const rel=o.backup_path.replace(`full/${manifest.backup_key}/`,"");cleanPath(rel);const entry=zip.file(rel);if(!entry)fail(`Backup ZIP is missing ${rel}`,"restore_package_invalid",422);
    const original=await decrypt(new Uint8Array(await entry.async("arraybuffer")),key);
    if(original.byteLength!==Number(o.original_size)||await sha256(original)!==o.checksum)fail(`Storage checksum failed for ${id}`,"restore_checksum_failed",422);
    counts[o.source_bucket]=(counts[o.source_bucket]||0)+1;
  }
  for(const bucket of BUCKETS)if((counts[bucket]||0)!==Number(manifest.storage.object_counts?.[bucket]||0))fail(`Storage count verification failed for ${bucket}`,"restore_inventory_failed",422);
  return {zip,manifest,payload,key,objects};
}

async function reconcileUsers(sql:TenantSql,ctx:SessionContext,users:Array<Record<string,unknown>>){
  const map=new Map<string,string>();
  for(const raw of users){
    const old=String(raw.id||""),email=String(raw.email||"").toLowerCase();if(!old||!email)continue;
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_reconcile_auth_user(
      ${old}::uuid,${email},${String(raw.phone||"")},${JSON.stringify(raw.user_metadata||{})}::jsonb,${JSON.stringify(raw.app_metadata||{})}::jsonb
    ) user_id`]);
    const id=String((rows[0] as any)?.user_id||"");if(!id)fail(`Authentication identity reconciliation failed for ${email}`);map.set(old,id);
  }
  return map;
}
async function putRestoredObject(env:Env,sql:TenantSql,ctx:SessionContext,bucket:string,path:string,bytes:Uint8Array,type:string){
  const key=r2Key(ctx.tenantId,bucket,path);await env.OBJECTS.put(key,owned(bytes),{httpMetadata:{contentType:type||"application/octet-stream"}});
  const check=await env.OBJECTS.get(key);if(!check)fail(`Restored R2 object missing: ${bucket}/${path}`);
  const verify=new Uint8Array(await check.arrayBuffer());if(verify.byteLength!==bytes.byteLength||await sha256(verify)!==await sha256(bytes))fail(`Post-upload verification failed for ${bucket}/${path}`);
  await registerR2(sql,ctx,key,path.split("/").pop()||"restored-object",type||"application/octet-stream",bytes.byteLength);
}
async function reconcileBucket(env:Env,sql:TenantSql,ctx:SessionContext,bucket:string,expected:Set<string>){
  const prefix=`tenants/${ctx.tenantId}/${bucket}/`;let cursor:string|undefined;const existing:string[]=[];
  do{const list=await env.OBJECTS.list({prefix,cursor,limit:1000});existing.push(...list.objects.map(o=>o.key.slice(prefix.length)));cursor=list.truncated?list.cursor:undefined;}while(cursor);
  for(const path of existing)if(!expected.has(path)){const key=r2Key(ctx.tenantId,bucket,path);await env.OBJECTS.delete(key);await markDeleted(sql,ctx,key).catch(()=>undefined);}
  const final:string[]=[];cursor=undefined;do{const list=await env.OBJECTS.list({prefix,cursor,limit:1000});final.push(...list.objects.map(o=>o.key.slice(prefix.length)));cursor=list.truncated?list.cursor:undefined;}while(cursor);
  if(final.length!==expected.size||[...expected].some(p=>!final.includes(p)))fail(`Restore final R2 inventory mismatch for ${bucket}`,"restore_inventory_failed",500);
}

export async function executeRestore(env:Env,sql:TenantSql,ctx:SessionContext,body:Record<string,unknown>){
  if(ctx.role!=="system_admin"||ctx.assuranceLevel<2)fail("A verified System Administrator session is required","mfa_required",403);
  const snap=await licence(sql,ctx);if(String(body.confirmation||"")!=="RESTORE SCHOOL")fail("Typed confirmation is invalid","restore_confirmation_invalid",422);
  const id=String(body.job_id||"");if(!/^[0-9a-f-]{36}$/i.test(id))fail("Restore job is required","validation_error",422);
  const job=await restoreJob(sql,ctx,id);if(!job)fail("Restore job not found","not_found",404);
  const importPath=String(job.import_path||""),key=r2Key(ctx.tenantId,BACKUP_BUCKET,importPath),object=await env.OBJECTS.get(key);
  if(!object)fail("Uploaded restore package not found","restore_upload_missing",404);
  const bytes=new Uint8Array(await object.arrayBuffer());
  if(bytes.byteLength!==Number(job.package_size)||await sha256(bytes)!==String(job.package_checksum))fail("Uploaded package integrity does not match","restore_upload_integrity_failed",422);
  await registerR2(sql,ctx,key,String(job.source_filename||"restore.zip"),"application/zip",bytes.byteLength);
  await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.school_restore_set_status(${id}::uuid,'validating','','Encrypted package uploaded and checksum verified.')`]);
  try{
    const prepared=await parseRestore(env,ctx,bytes,snap);
    const map=await reconcileUsers(sql,ctx,prepared.payload.auth_users||[]);
    const pre=await performFullBackup(env,sql,ctx,"manual");
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_set_restore_prebackup(${id}::uuid,${ctx.userId}::uuid,${String(pre.id)}::uuid)`]);
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.school_restore_clear_operational_data(${id}::uuid)`]);
    const tables=prepared.payload.tables||{};
    for(const table of RESTORABLE_TABLES){
      const rows=Array.isArray(tables[table])?tables[table].map(r=>remap(r,map)):[];
      await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.school_restore_apply_table(${id}::uuid,${table},${JSON.stringify(rows)}::jsonb)`]);
    }
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_rebuild_memberships(${ctx.tenantId}::uuid)`]);
    const expected=new Map<string,Set<string>>();for(const b of BUCKETS)expected.set(b,new Set());
    for(const item of prepared.objects){
      const rel=item.backup_path.replace(`full/${prepared.manifest.backup_key}/`,""),entry=prepared.zip.file(rel);if(!entry)fail(`Backup ZIP is missing ${rel}`);
      const original=await decrypt(new Uint8Array(await entry.async("arraybuffer")),prepared.key);
      await putRestoredObject(env,sql,ctx,item.source_bucket,item.source_path,original,item.content_type);
      expected.get(item.source_bucket)?.add(item.source_path);
    }
    for(const b of BUCKETS)await reconcileBucket(env,sql,ctx,b,expected.get(b)||new Set());
    const notes=`Full school restore passed: ${RESTORABLE_TABLES.length} table inventories processed, ${prepared.objects.length} protected R2 objects restored and checksum-verified, stale protected objects reconciled, and ${map.size} authentication identities reconciled. Restored identities without credentials must reset passwords.`;
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.school_restore_complete(
      ${id}::uuid,${JSON.stringify(prepared.manifest.database.row_counts)}::jsonb,${JSON.stringify(prepared.manifest.storage.object_counts)}::jsonb,
      ${(prepared.payload.auth_users||[]).length}::integer,${map.size}::integer,${prepared.manifest.backup_key},${prepared.manifest.schema_version},
      ${String((prepared.payload.tables?.school_settings as any[])?.[0]?.school_name||"")},${ctx.tenantCode},${notes}
    )`]);
    await env.OBJECTS.delete(key).catch(()=>undefined);await markDeleted(sql,ctx,key).catch(()=>undefined);
    return {job_id:id,status:"completed",verification_notes:notes};
  }catch(e:any){
    const message=String(e?.message||e);await env.OBJECTS.delete(key).catch(()=>undefined);await markDeleted(sql,ctx,key).catch(()=>undefined);
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.school_restore_set_status(${id}::uuid,'failed',${message.slice(0,2000)},'Restore stopped with structured error evidence; terminal upload removed.')`]).catch(()=>undefined);
    throw e;
  }
}
