import type { Env, SessionContext } from "./types";
import type { TenantSql } from "./tenant-db";
import { tenantTx } from "./db";

const SCHEMA_VERSION="7.4.0";
const FORMAT_VERSION=2;
const BACKUP_BUCKET="system-backups";
const SOURCE_BUCKETS=[
  "student-photos","staff-photos","school-branding","report-pdfs",
  "headteacher-signatures","report-card-templates","certificate-pdfs","certificate-templates"
] as const;
const TABLES=[
  "school_settings","id_card_settings","id_card_deletion_tombstones","profiles","teachers","headteachers",
  "academic_years","terms","classes","subjects","class_subjects","class_timetable_entries","school_prospectuses",
  "school_prospectus_sections","school_prospectus_items","school_prospectus_revisions","user_class_access","students",
  "student_guardians","guardian_links","enrollments","student_id_cards","id_card_events","staff_id_cards",
  "staff_id_card_events","class_attendance_registers","student_attendance_entries","grading_scales","assessment_schemes",
  "assessment_components","student_reports","subject_scores","subject_results","assessment_score_entries",
  "emergency_academic_delegations","emergency_academic_delegation_events","academic_period_controls",
  "report_correction_requests","report_correction_events","student_lifecycle_events","transcript_issuances",
  "data_retention_policies","privacy_requests","security_events","security_verification_runs","recovery_test_runs",
  "certificate_templates","teacher_award_categories","certificate_batches","certificates","certificate_events",
  "report_workflow_events","report_revisions","report_publications","report_card_templates","license_plans",
  "school_licenses","platform_access_locks","license_events","license_verification_logs","license_feature_catalog",
  "license_plan_revisions","license_entitlement_overrides","license_binding_sessions","platform_distribution_authorities",
  "platform_audit_archives","platform_package_templates","platform_package_artifacts","platform_package_events",
  "platform_package_reconciliation","notifications","notification_outbox","import_batches","import_errors","audit_log",
  "audit_log_archives","audit_log_archive_entries","client_error_events","system_maintenance_log","backup_exports",
  "backup_storage_objects"
] as const;

type BackupRow={
  id:string;backup_key:string;status:string;manifest_path:string;database_path:string;storage_path:string;
  checksum:string;backup_type:string;created_at?:string;verification_status?:string;
};
type StoredObject={
  source_bucket:string;source_path:string;backup_path:string;content_type:string;
  original_size:number;encrypted_size:number;checksum:string;
};
type BackupManifest={
  format_version:number;schema_version:string;backup_id:string;backup_key:string;generated_at:string;
  encryption:{algorithm:string;key_hint:string;payload_format:string};
  database:{path:string;checksum:string;row_counts:Record<string,number>;compressed_size:number;encrypted_size:number};
  storage:{buckets:string[];object_counts:Record<string,number>;total_bytes:number;objects:StoredObject[]};
  auth_users:{count:number;password_hashes_included:boolean;note:string};
};

const enc=new TextEncoder(),dec=new TextDecoder();

function fail(message:string,code="backup_failed",status=400):never{
  throw Object.assign(new Error(message),{code,status});
}
function asArray<T=any>(value:unknown):T[]{return Array.isArray(value)?value as T[]:[];}
function r2Key(tenantId:string,bucket:string,path:string){
  const clean=String(path||"").replace(/^\/+/, "");
  if(!clean||clean.includes("\0")||clean.includes("\\")||clean.split("/").some(x=>x==="."||x===".."))fail("Invalid storage path","invalid_storage_path",400);
  return `tenants/${tenantId}/${bucket}/${clean}`;
}
function backupR2Key(tenantId:string,path:string){return r2Key(tenantId,BACKUP_BUCKET,path);}
function encodedPath(path:string){return path.split("/").map(s=>encodeURIComponent(s)).join("/");}
function contentTypeOf(obj:R2ObjectBody){return String(obj.httpMetadata?.contentType||"application/octet-stream");}

async function sha256Bytes(bytes:Uint8Array){
  const hash=new Uint8Array(await crypto.subtle.digest("SHA-256",bytes));
  return Array.from(hash,b=>b.toString(16).padStart(2,"0")).join("");
}
async function encryptionMaterial(env:Env){
  const configured=String(env.BACKUP_ENCRYPTION_KEY||"");
  const source=configured||(env.TURNSTILE_TEST_MODE==="true"?`edusentia:parity-backup:v1:${env.SESSION_PEPPER}`:"");
  if(source.length<32)fail("BACKUP_ENCRYPTION_KEY must contain at least 32 characters","backup_encryption_unavailable",503);
  const digest=new Uint8Array(await crypto.subtle.digest("SHA-256",enc.encode(source)));
  const key=await crypto.subtle.importKey("raw",digest,{name:"AES-GCM"},false,["encrypt","decrypt"]);
  return {key,hint:(await sha256Bytes(digest)).slice(0,16)};
}
async function encryptPayload(bytes:Uint8Array,key:CryptoKey){
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const ciphertext=new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv},key,bytes));
  const magic=enc.encode("NISB2"),out=new Uint8Array(magic.length+iv.length+ciphertext.length);
  out.set(magic);out.set(iv,magic.length);out.set(ciphertext,magic.length+iv.length);return out;
}
async function decryptPayload(bytes:Uint8Array,key:CryptoKey){
  if(dec.decode(bytes.slice(0,5))!=="NISB2")fail("Unsupported encrypted backup payload","backup_format_invalid",422);
  return new Uint8Array(await crypto.subtle.decrypt({name:"AES-GCM",iv:bytes.slice(5,17)},key,bytes.slice(17)));
}
async function gzip(bytes:Uint8Array){
  return new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer());
}
async function gunzip(bytes:Uint8Array){
  return new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer());
}

async function licence(sql:TenantSql,ctx:SessionContext,feature:string,write:boolean){
  const [snapshotRows,featureRows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.license_snapshot_for_role('system_admin') result`,
    txn`select public.license_feature_enabled(${feature}) enabled`
  ]);
  const snapshot=(snapshotRows[0] as any)?.result||{};
  const allowed=write?snapshot.write_allowed===true:snapshot.read_allowed===true;
  if(!allowed)fail(String(snapshot.warning||"The current licence does not permit this backup operation"),"licence_restricted",403);
  if((featureRows[0] as any)?.enabled!==true)fail(`Licence feature not included: ${feature}`,"licence_feature_not_included",403);
}

async function readTable(sql:TenantSql,ctx:SessionContext,table:string){
  const rows:any[]=[];
  for(let offset=0;;offset+=1000){
    const [pageRows]=await tenantTx<any[]>(sql,ctx,txn=>[
      txn`select public.backup_worker_read_table(${table},${offset},1000) rows`
    ]);
    const page=asArray((pageRows[0] as any)?.rows);
    rows.push(...page);
    if(page.length<1000)break;
    if(offset>=1_000_000)fail(`Backup table ${table} exceeded the safe export limit`,"backup_row_limit",413);
  }
  return rows;
}
async function buildDatabaseSnapshot(sql:TenantSql,ctx:SessionContext,backup:BackupRow){
  const tables:Record<string,unknown[]>={},rowCounts:Record<string,number>={};
  for(const table of TABLES){
    let rows=await readTable(sql,ctx,table);
    if(table==="backup_exports")rows=rows.filter((r:any)=>String(r.id||"")!==backup.id);
    if(table==="backup_storage_objects")rows=rows.filter((r:any)=>String(r.backup_export_id||"")!==backup.id);
    tables[table]=rows;rowCounts[table]=rows.length;
  }
  const [authRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_auth_users() users`]);
  const authUsers=asArray((authRows[0] as any)?.users);
  rowCounts.auth_users=authUsers.length;
  const bytes=enc.encode(JSON.stringify({
    metadata:{
      format_version:FORMAT_VERSION,schema_version:SCHEMA_VERSION,backup_id:backup.id,backup_key:backup.backup_key,
      generated_at:new Date().toISOString(),auth_password_hashes_included:false,
      auth_restore_note:"Authentication identities and metadata are included without password hashes. Recreated users must set or reset passwords after disaster recovery."
    },
    tables,auth_users:authUsers
  }));
  return {bytes,checksum:await sha256Bytes(bytes),rowCounts,authUserCount:authUsers.length};
}
async function registerObject(sql:TenantSql,ctx:SessionContext,key:string,name:string,type:string,size:number){
  await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_register_r2_object(${ctx.tenantId}::uuid,${key},${name},${type},${size}::bigint,${ctx.userId}::uuid)`
  ]);
}
async function putBackupObject(env:Env,sql:TenantSql,ctx:SessionContext,path:string,bytes:Uint8Array,type:string){
  const key=backupR2Key(ctx.tenantId,path);
  await env.OBJECTS.put(key,bytes,{httpMetadata:{contentType:type}});
  await registerObject(sql,ctx,key,path.split("/").pop()||"backup-object",type,bytes.byteLength);
}
async function removeBackupPrefix(env:Env,sql:TenantSql,ctx:SessionContext,prefix:string){
  let cursor:string|undefined;
  const fullPrefix=backupR2Key(ctx.tenantId,prefix.endsWith("/")?prefix:prefix+"/");
  do{
    const listed=await env.OBJECTS.list({prefix:fullPrefix,cursor,limit:1000});
    for(const object of listed.objects){
      await env.OBJECTS.delete(object.key);
      await tenantTx<any[]>(sql,ctx,txn=>[
        txn`select public.backup_worker_mark_r2_deleted(${ctx.tenantId}::uuid,${object.key})`
      ]);
    }
    cursor=listed.truncated?listed.cursor:undefined;
  }while(cursor);
}

async function createBackupRecord(sql:TenantSql,ctx:SessionContext,mode:"manual"|"scheduled"){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_create(${ctx.userId}::uuid,${mode}) result`
  ]);
  return (rows[0] as any)?.result as BackupRow;
}

export async function performFullBackup(env:Env,sql:TenantSql,ctx:SessionContext,mode:"manual"|"scheduled"="manual"){
  await licence(sql,ctx,mode==="scheduled"?"scheduled_backup":"manual_backup",true);
  if(mode==="manual"&&ctx.assuranceLevel<2)fail("Multi-factor authentication is required for manual backup","mfa_required",403);
  const backup=await createBackupRecord(sql,ctx,mode);
  if(!backup?.id)fail("Backup record could not be created");
  const maxObjects=Math.max(1,Math.min(20000,Number(env.BACKUP_MAX_OBJECTS||5000)));
  const maxBytes=Math.max(1024,Math.min(5*1024*1024*1024,Number(env.BACKUP_MAX_BYTES||536870912)));
  const material=await encryptionMaterial(env),prefix=`full/${backup.backup_key}`;
  const databasePath=`${prefix}/database/database.json.gz.nisb`,manifestPath=`${prefix}/manifest.json.nisb`,indexPath=`${prefix}/index.json`;
  const storedObjects:StoredObject[]=[],objectCounts:Record<string,number>={};let totalBytes=0,discovered=0;
  try{
    const database=await buildDatabaseSnapshot(sql,ctx,backup);
    const compressed=await gzip(database.bytes),encrypted=await encryptPayload(compressed,material.key);
    await putBackupObject(env,sql,ctx,databasePath,encrypted,"application/octet-stream");

    for(const bucket of SOURCE_BUCKETS){
      const sourcePrefix=`tenants/${ctx.tenantId}/${bucket}/`;let cursor:string|undefined,count=0;
      do{
        const listed=await env.OBJECTS.list({prefix:sourcePrefix,cursor,limit:1000});
        for(const item of listed.objects){
          discovered++;if(discovered>maxObjects)fail(`Storage object limit exceeded (${maxObjects})`,"backup_object_limit",413);
          const object=await env.OBJECTS.get(item.key);if(!object)continue;
          const bytes=new Uint8Array(await object.arrayBuffer());totalBytes+=bytes.byteLength;
          if(totalBytes>maxBytes)fail(`Storage byte limit exceeded (${maxBytes})`,"backup_byte_limit",413);
          const sourcePath=item.key.slice(sourcePrefix.length),checksum=await sha256Bytes(bytes),sealed=await encryptPayload(bytes,material.key);
          const backupPath=`${prefix}/storage/${bucket}/${encodedPath(sourcePath)}.nisb`;
          await putBackupObject(env,sql,ctx,backupPath,sealed,"application/octet-stream");
          const row:StoredObject={source_bucket:bucket,source_path:sourcePath,backup_path:backupPath,content_type:contentTypeOf(object),original_size:bytes.byteLength,encrypted_size:sealed.byteLength,checksum};
          storedObjects.push(row);count++;
          await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_record_object(
            ${backup.id}::uuid,${bucket},${sourcePath},${backupPath},${row.content_type},
            ${row.original_size}::bigint,${row.encrypted_size}::bigint,${checksum}
          )`]);
        }
        cursor=listed.truncated?listed.cursor:undefined;
      }while(cursor);
      objectCounts[bucket]=count;
    }

    const generatedAt=new Date().toISOString();
    const manifest:BackupManifest={
      format_version:FORMAT_VERSION,schema_version:SCHEMA_VERSION,backup_id:backup.id,backup_key:backup.backup_key,generated_at:generatedAt,
      encryption:{algorithm:"AES-256-GCM",key_hint:material.hint,payload_format:"NISB2 + 12-byte IV + ciphertext/tag"},
      database:{path:databasePath,checksum:database.checksum,row_counts:database.rowCounts,compressed_size:compressed.byteLength,encrypted_size:encrypted.byteLength},
      storage:{buckets:[...SOURCE_BUCKETS],object_counts:objectCounts,total_bytes:totalBytes,objects:storedObjects},
      auth_users:{count:database.authUserCount,password_hashes_included:false,note:"Neon identity metadata is exported; password hashes are intentionally excluded from portable tenant backups."}
    };
    const sealedManifest=await encryptPayload(enc.encode(JSON.stringify(manifest)),material.key);
    await putBackupObject(env,sql,ctx,manifestPath,sealedManifest,"application/octet-stream");
    const index=enc.encode(JSON.stringify({
      format_version:FORMAT_VERSION,schema_version:SCHEMA_VERSION,backup_id:backup.id,backup_key:backup.backup_key,
      generated_at:generatedAt,encrypted:true,algorithm:"AES-256-GCM",key_hint:material.hint,
      manifest_path:manifestPath,database_path:databasePath,storage_object_counts:objectCounts,storage_bytes:totalBytes
    },null,2));
    await putBackupObject(env,sql,ctx,indexPath,index,"application/json");
    const [completedRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_complete(
      ${backup.id}::uuid,${indexPath},${database.checksum},${JSON.stringify(database.rowCounts)}::jsonb,
      ${manifestPath},${databasePath},${JSON.stringify(objectCounts)}::jsonb,${totalBytes}::bigint,${material.hint}
    ) result`]);
    return (completedRows[0] as any)?.result||{...backup,status:"completed"};
  }catch(e:any){
    const message=String(e?.message||e);
    await removeBackupPrefix(env,sql,ctx,prefix).catch(()=>undefined);
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_fail(${backup.id}::uuid,${message})`]).catch(()=>undefined);
    throw e;
  }
}

async function getBackup(sql:TenantSql,ctx:SessionContext,id:string|null){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_get(${id}::uuid) result`
  ]);
  return ((rows[0] as any)?.result||null) as BackupRow|null;
}
async function getInventory(sql:TenantSql,ctx:SessionContext,id:string){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_inventory(${id}::uuid) result`
  ]);
  return asArray<StoredObject>((rows[0] as any)?.result);
}
async function readBackupBytes(env:Env,ctx:SessionContext,path:string){
  const object=await env.OBJECTS.get(backupR2Key(ctx.tenantId,path));
  if(!object)fail(`Backup object not found: ${path}`,"backup_object_missing",404);
  return new Uint8Array(await object.arrayBuffer());
}

export async function verifyBackup(env:Env,sql:TenantSql,ctx:SessionContext,id:string|null){
  await licence(sql,ctx,"manual_backup",false);
  if(ctx.assuranceLevel<2)fail("Multi-factor authentication is required for backup verification","mfa_required",403);
  const backup=await getBackup(sql,ctx,id);if(!backup||backup.status!=="completed"||backup.backup_type!=="full")fail("Completed full backup not found","backup_not_found",404);
  await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_set_verification(${backup.id}::uuid,'not_tested','Verification started')`]);
  try{
    const material=await encryptionMaterial(env);
    const manifest=JSON.parse(dec.decode(await decryptPayload(await readBackupBytes(env,ctx,backup.manifest_path),material.key))) as BackupManifest;
    if(manifest.format_version!==FORMAT_VERSION||manifest.backup_id!==backup.id||manifest.backup_key!==backup.backup_key)fail("Backup manifest identity is invalid","backup_manifest_invalid",422);
    const databaseBytes=await gunzip(await decryptPayload(await readBackupBytes(env,ctx,manifest.database.path),material.key));
    if(await sha256Bytes(databaseBytes)!==manifest.database.checksum)fail("Database checksum verification failed","backup_checksum_failed",422);
    const payload=JSON.parse(dec.decode(databaseBytes)) as any;
    let checkedRows=0,checkedTables=0;
    for(const [table,declared] of Object.entries(manifest.database.row_counts||{})){
      const rows=table==="auth_users"?payload.auth_users:payload.tables?.[table];
      if(!Array.isArray(rows)||rows.length!==Number(declared))fail(`Database row count verification failed for ${table}`,"backup_row_count_failed",422);
      checkedRows+=rows.length;checkedTables++;
    }
    const inventory=await getInventory(sql,ctx,backup.id);let checkedBytes=0;
    if(inventory.length!==manifest.storage.objects.length)fail("Backup object inventory count mismatch","backup_inventory_failed",422);
    for(const item of inventory){
      const original=await decryptPayload(await readBackupBytes(env,ctx,item.backup_path),material.key);
      if(original.byteLength!==Number(item.original_size)||await sha256Bytes(original)!==item.checksum)fail(`Storage checksum failed for ${item.source_bucket}/${item.source_path}`,"backup_storage_checksum_failed",422);
      checkedBytes+=original.byteLength;
    }
    const notes=`Verification passed: ${checkedTables} table inventories, ${checkedRows} rows and ${inventory.length} R2 objects decrypted and checksum-verified.`;
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_set_verification(${backup.id}::uuid,'passed',${notes})`]);
    return {status:"passed",backup_id:backup.id,checked_tables:checkedTables,checked_rows:checkedRows,checked_objects:inventory.length,checked_bytes:checkedBytes};
  }catch(e:any){
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_set_verification(${backup.id}::uuid,'failed',${String(e?.message||e).slice(0,3900)})`]).catch(()=>undefined);
    throw e;
  }
}

function b64url(bytes:Uint8Array){let s="";for(const b of bytes)s+=String.fromCharCode(b);return btoa(s).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");}
function unb64url(value:string){const n=value.replaceAll("-","+").replaceAll("_","/")+"=".repeat((4-value.length%4)%4);const s=atob(n);return Uint8Array.from(s,c=>c.charCodeAt(0));}
async function transferKey(env:Env){return crypto.subtle.importKey("raw",enc.encode(String(env.BACKUP_SIGNING_SECRET||env.SESSION_PEPPER)),{name:"HMAC",hash:"SHA-256"},false,["sign","verify"]);}
async function signTransfer(env:Env,payload:Record<string,unknown>){
  const body=b64url(enc.encode(JSON.stringify(payload))),sig=b64url(new Uint8Array(await crypto.subtle.sign("HMAC",await transferKey(env),enc.encode(body))));
  return `${body}.${sig}`;
}
async function verifyTransfer(env:Env,token:string){
  const [body,sig]=String(token||"").split(".");if(!body||!sig)return null;
  const ok=await crypto.subtle.verify("HMAC",await transferKey(env),unb64url(sig),enc.encode(body));if(!ok)return null;
  const payload=JSON.parse(dec.decode(unb64url(body))) as any;
  if(!payload?.exp||Date.now()>Number(payload.exp)*1000)return null;
  return payload;
}

export async function handleBackupTransfer(request:Request,env:Env){
  const url=new URL(request.url);if(url.pathname!=="/api/backup/transfer")return null;
  const token=url.searchParams.get("token")||"",payload=await verifyTransfer(env,token);
  if(!payload||payload.op!=="download")return new Response("Invalid or expired backup transfer",{status:403,headers:{"cache-control":"no-store"}});
  if(request.method!=="GET")return new Response("Method not allowed",{status:405});
  const key=String(payload.key||"");
  if(!key.startsWith(`tenants/${payload.tenantId}/system-backups/full/`))return new Response("Invalid backup scope",{status:403});
  const object=await env.OBJECTS.get(key);if(!object)return new Response("Not found",{status:404});
  const h=new Headers();object.writeHttpMetadata(h);h.set("cache-control","private, no-store");h.set("x-content-type-options","nosniff");
  return new Response(object.body,{headers:h});
}

export async function backupDownloadGateway(env:Env,sql:TenantSql,ctx:SessionContext,body:Record<string,unknown>,origin:string){
  if(ctx.role!=="system_admin"||ctx.assuranceLevel<2)fail("A verified System Administrator session is required","mfa_required",403);
  await licence(sql,ctx,"manual_backup",false);
  const id=String(body.backup_id||"");if(!/^[0-9a-f-]{36}$/i.test(id))fail("backup_id is required","validation_error",422);
  const backup=await getBackup(sql,ctx,id);if(!backup||backup.status!=="completed"||backup.backup_type!=="full")fail("Completed encrypted backup not found","backup_not_found",404);
  const inventory=await getInventory(sql,ctx,id),prefix=`full/${backup.backup_key}/`;
  const paths=[backup.storage_path,backup.manifest_path,backup.database_path,...inventory.map(x=>x.backup_path)].filter(Boolean);
  const unique=[...new Set(paths)];
  if(!unique.length||unique.length>5005||unique.some(path=>!path.startsWith(prefix)))fail("Backup inventory is invalid","backup_inventory_invalid",409);
  const files=[] as Array<{path:string;relative_path:string;url:string}>;
  for(const path of unique){
    const key=backupR2Key(ctx.tenantId,path);
    if(!(await env.OBJECTS.head(key)))fail(`Backup object missing: ${path}`,"backup_object_missing",404);
    const token=await signTransfer(env,{op:"download",tenantId:ctx.tenantId,key,exp:Math.floor(Date.now()/1000)+600});
    files.push({path,relative_path:path.slice(prefix.length),url:`${origin}/api/backup/transfer?token=${encodeURIComponent(token)}`});
  }
  await tenantTx<any[]>(sql,ctx,txn=>[txn`select audit.record_auth_event(
    ${ctx.tenantId}::uuid,${ctx.userId}::uuid,'backup.package_download_authorized',
    ${JSON.stringify({backup_id:id,backup_key:backup.backup_key,file_count:files.length,expires_in_seconds:600,storage_provider:"cloudflare-r2"})}::jsonb
  )`]).catch(()=>undefined);
  return {ok:true,backup_id:id,backup_key:backup.backup_key,created_at:backup.created_at,verification_status:backup.verification_status,expires_in_seconds:600,storage_provider:"cloudflare-r2",files};
}

export async function handleScheduledBackupCompat(env:Env,sql:TenantSql,ctx:SessionContext,body:Record<string,unknown>){
  if(ctx.role!=="system_admin")fail("School System Administrator access required","forbidden",403);
  const action=String(body.action||"create");
  if(action==="create")return performFullBackup(env,sql,ctx,"manual");
  if(action==="verify")return verifyBackup(env,sql,ctx,String(body.backup_id||""));
  if(action==="verify_latest")return verifyBackup(env,sql,ctx,null);
  if(action==="recovery_test"){
    const result=await verifyBackup(env,sql,ctx,String(body.backup_id||""));
    return {...result,recovery_status:"passed"};
  }
  fail("Unsupported backup action","unsupported_action",400);
}
