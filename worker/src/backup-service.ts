// Backup scheduling release: manual backup for all licensed schools; weekly/monthly automation for eligible plans.
import type { Env, SessionContext } from "./types";
import { tenantDb, type TenantSql } from "./tenant-db";
import { db, tenantTx } from "./db";

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
  "report_workflow_events","report_revisions","report_publications","report_card_templates",
  "notifications","notification_outbox","import_batches","import_errors","audit_log",
  "audit_log_archives","audit_log_archive_entries","client_error_events","system_maintenance_log"
] as const;
const DATABASE_BATCH_SIZE=12;

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
function ownedBuffer(bytes:Uint8Array):ArrayBuffer{const copy=new Uint8Array(bytes.byteLength);copy.set(bytes);return copy.buffer;}

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
  const hash=new Uint8Array(await crypto.subtle.digest("SHA-256",ownedBuffer(bytes)));
  return Array.from(hash,b=>b.toString(16).padStart(2,"0")).join("");
}
async function encryptionMaterial(env:Env){
  const configured=String(env.BACKUP_ENCRYPTION_KEY||"");
  const source=configured||(env.TURNSTILE_TEST_MODE==="true"?`edusentia:parity-backup:v1:${env.SESSION_PEPPER}`:"");
  if(source.length<32)fail("BACKUP_ENCRYPTION_KEY must contain at least 32 characters","backup_encryption_unavailable",503);
  const digest=new Uint8Array(await crypto.subtle.digest("SHA-256",enc.encode(source)));
  const key=await crypto.subtle.importKey("raw",ownedBuffer(digest),{name:"AES-GCM"},false,["encrypt","decrypt"]);
  return {key,hint:(await sha256Bytes(digest)).slice(0,16)};
}
async function encryptPayload(bytes:Uint8Array,key:CryptoKey){
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const ciphertext=new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv},key,ownedBuffer(bytes)));
  const magic=enc.encode("NISB2"),out=new Uint8Array(magic.length+iv.length+ciphertext.length);
  out.set(magic);out.set(iv,magic.length);out.set(ciphertext,magic.length+iv.length);return out;
}
async function decryptPayload(bytes:Uint8Array,key:CryptoKey){
  if(dec.decode(bytes.slice(0,5))!=="NISB2")fail("Unsupported encrypted backup payload","backup_format_invalid",422);
  return new Uint8Array(await crypto.subtle.decrypt({name:"AES-GCM",iv:ownedBuffer(bytes.slice(5,17))},key,ownedBuffer(bytes.slice(17))));
}
async function gzip(bytes:Uint8Array){
  return new Uint8Array(await new Response(new Blob([ownedBuffer(bytes)]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer());
}
async function gunzip(bytes:Uint8Array){
  return new Uint8Array(await new Response(new Blob([ownedBuffer(bytes)]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer());
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

type BackupReadRequest={table:string;offset:number;limit:number};

async function readBatch(sql:TenantSql,ctx:SessionContext,backupId:string,requests:BackupReadRequest[]){
  const [pageRows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_read_batch(${backupId}::uuid,${JSON.stringify(requests)}::jsonb) rows`
  ]);
  const result=(pageRows[0] as any)?.rows;
  return result&&typeof result==="object"&&!Array.isArray(result)?result as Record<string,unknown[]>:{};
}

async function buildDatabaseSnapshot(sql:TenantSql,ctx:SessionContext,backup:BackupRow){
  const tables:Record<string,unknown[]>={},rowCounts:Record<string,number>={};
  const pending:BackupReadRequest[]=TABLES.map(table=>({table,offset:0,limit:1000}));

  while(pending.length){
    const requests=pending.splice(0,DATABASE_BATCH_SIZE);
    const batch=await readBatch(sql,ctx,backup.id,requests);
    for(const request of requests){
      const page=asArray(batch[request.table]);
      const accumulated=tables[request.table]||[];
      accumulated.push(...page);
      tables[request.table]=accumulated;
      if(page.length===request.limit){
        const nextOffset=request.offset+request.limit;
        if(nextOffset>1_000_000)fail(`Backup table ${request.table} exceeded the safe export limit`,"backup_row_limit",413);
        pending.push({...request,offset:nextOffset});
      }
    }
  }

  for(const table of TABLES)rowCounts[table]=(tables[table]||[]).length;
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

async function createBackupRecord(sql:TenantSql,ctx:SessionContext,mode:"manual"|"scheduled"|"pre_restore"){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_create(${ctx.userId}::uuid,${mode}) result`
  ]);
  return (rows[0] as any)?.result as BackupRow;
}

export async function performFullBackup(env:Env,sql:TenantSql,ctx:SessionContext,mode:"manual"|"scheduled"|"pre_restore"="manual"){
  await licence(sql,ctx,mode==="scheduled"?"scheduled_backup":"manual_backup",true);
  if(mode!=="scheduled"&&ctx.assuranceLevel<2)fail("Multi-factor authentication is required for manual backup","mfa_required",403);
  const backup=await createBackupRecord(sql,ctx,mode);
  if(!backup?.id)fail("Backup record could not be created");
  const maxObjects=Math.max(1,Math.min(20000,Number(env.BACKUP_MAX_OBJECTS||5000)));
  const maxBytes=Math.max(1024,Math.min(5*1024*1024*1024,Number(env.BACKUP_MAX_BYTES||536870912)));
  const prefix=`full/${backup.backup_key}`;
  const databasePath=`${prefix}/database/database.json.gz.nisb`,manifestPath=`${prefix}/manifest.json.nisb`,indexPath=`${prefix}/index.json`;
  const storedObjects:StoredObject[]=[],objectCounts:Record<string,number>={};let totalBytes=0,discovered=0;
  try{
    // Resolve encryption inside the guarded section so a configuration problem
    // is recorded as a failed backup instead of leaving a phantom processing row.
    const material=await encryptionMaterial(env);
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
    // Persist failure state before best-effort R2 cleanup so an interrupted
    // cleanup cannot leave the tenant blocked behind a phantom processing job.
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_fail(${backup.id}::uuid,${message})`]).catch(()=>undefined);
    await removeBackupPrefix(env,sql,ctx,prefix).catch(()=>undefined);
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
  const ok=await crypto.subtle.verify("HMAC",await transferKey(env),ownedBuffer(unb64url(sig)),enc.encode(body));if(!ok)return null;
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

async function purgeBackupCandidate(env:Env,sql:TenantSql,ctx:SessionContext,row:any){
  const id=String(row?.id||""),key=String(row?.backup_key||"");if(!id||!key)return false;
  const [purgedRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_purge_backup(${id}::uuid) purged`]);
  const purged=(purgedRows[0] as any)?.purged===true;
  if(purged)await removeBackupPrefix(env,sql,ctx,`full/${key}`).catch(e=>console.error(JSON.stringify({level:"error",service:"backup-maintenance",backupId:id,message:String((e as any)?.message||e)})));
  return purged;
}

export async function performStorageMaintenance(env:Env,sql:TenantSql,ctx:SessionContext){
  if(ctx.role!=="system_admin"||ctx.assuranceLevel<2)fail("A verified System Administrator session is required","mfa_required",403);
  const [staleRows,restoreRows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_reconcile_stale_backups() count`,
    txn`select public.backup_worker_reconcile_stale_restore_jobs() jobs`
  ]);
  const staleBackups=Number((staleRows[0] as any)?.count||0),restoreJobs=asArray<any>((restoreRows[0] as any)?.jobs);
  let restoreUploadsRemoved=0;
  for(const job of restoreJobs){
    const path=String(job?.import_path||""),id=String(job?.id||"");if(!path||!id)continue;
    const key=backupR2Key(ctx.tenantId,path);
    await env.OBJECTS.delete(key).catch(()=>undefined);
    await tenantTx<any[]>(sql,ctx,txn=>[
      txn`select public.backup_worker_mark_r2_deleted(${ctx.tenantId}::uuid,${key})`,
      txn`select public.backup_worker_clear_restore_import_path(${id}::uuid)`
    ]).catch(()=>undefined);
    restoreUploadsRemoved++;
  }

  const settings=await readTable(sql,ctx,"school_settings"),backups=await readTable(sql,ctx,"backup_exports");
  const minimum=Math.min(365,Math.max(1,Number((settings[0] as any)?.backup_minimum_copies??2)||2));
  const completed=backups.filter((x:any)=>x.status==="completed"&&x.backup_type==="full").sort((a:any,b:any)=>Date.parse(String(b.created_at||""))-Date.parse(String(a.created_at||"")));
  const failed=backups.filter((x:any)=>x.status==="failed"&&x.backup_type==="full");
  let failedPurged=0,expiredPurged=0;
  for(const row of failed)if(await purgeBackupCandidate(env,sql,ctx,row))failedPurged++;
  for(let i=minimum;i<completed.length;i++){
    const row:any=completed[i],expires=Date.parse(String(row.expires_at||""));
    if(Number.isFinite(expires)&&expires<Date.now()&&await purgeBackupCandidate(env,sql,ctx,row))expiredPurged++;
  }
  return {status:"completed",stale_backups_reconciled:staleBackups,failed_backups_purged:failedPurged,expired_backups_purged:expiredPurged,restore_uploads_removed:restoreUploadsRemoved,minimum_copies:minimum};
}

async function runRecoveryTest(env:Env,sql:TenantSql,ctx:SessionContext,backupId:string){
  if(!/^[0-9a-f-]{36}$/i.test(backupId))fail("backup_id is required","validation_error",422);
  const [startRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_recovery_test_begin(${backupId}::uuid,${ctx.userId}::uuid) run_id`]);
  const runId=String((startRows[0] as any)?.run_id||"");if(!runId)fail("Recovery rehearsal record could not be created");
  try{
    const result=await verifyBackup(env,sql,ctx,backupId);
    const notes="Recovery rehearsal passed. The encrypted database was reconstructed in memory and all protected R2 objects were decrypted and checksum-verified without overwriting production data.";
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_recovery_test_complete(
      ${runId}::uuid,'passed',${Number(result.checked_tables||0)}::integer,${Number(result.checked_rows||0)}::bigint,
      ${Number(result.checked_objects||0)}::integer,${Number(result.checked_bytes||0)}::bigint,${notes},''
    )`]);
    return {...result,recovery_test_id:runId,recovery_status:"passed"};
  }catch(e:any){
    await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.backup_worker_recovery_test_complete(
      ${runId}::uuid,'failed',0,0,0,0,'Recovery rehearsal failed before production data was changed.',${String(e?.message||e).slice(0,1900)}
    )`]).catch(()=>undefined);
    throw e;
  }
}

async function schedulePolicy(sql:TenantSql,ctx:SessionContext){
  const [policyRows,featureRows,snapshotRows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_schedule_policy() result`,
    txn`select public.license_feature_enabled('scheduled_backup') enabled`,
    txn`select public.license_snapshot_for_role('system_admin') result`
  ]);
  const policy=(policyRows[0] as any)?.result||{},snapshot=(snapshotRows[0] as any)?.result||{};
  return {
    ...policy,
    scheduled_available:(featureRows[0] as any)?.enabled===true,
    plan_code:String(snapshot?.plan?.code||snapshot?.plan_code||"")
  };
}

async function setSchedulePolicy(sql:TenantSql,ctx:SessionContext,mode:string){
  if(ctx.assuranceLevel<2)fail("Multi-factor authentication is required to change automatic backup settings","mfa_required",403);
  const normalized=String(mode||"").trim().toLowerCase();
  if(!["off","weekly","monthly"].includes(normalized))fail("Backup schedule must be Off, Weekly, or Monthly","validation_error",422);
  if(normalized!=="off")await licence(sql,ctx,"scheduled_backup",true);
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.backup_worker_set_schedule_policy(${normalized},${ctx.userId}::uuid) result`
  ]);
  const policy=(rows[0] as any)?.result||{};
  return {...policy,scheduled_available:normalized!=="off"?true:(await schedulePolicy(sql,ctx)).scheduled_available};
}

export async function handleScheduledBackupCompat(env:Env,sql:TenantSql,ctx:SessionContext,body:Record<string,unknown>){
  if(ctx.role!=="system_admin")fail("School System Administrator access required","forbidden",403);
  const action=String(body.action||"create");
  if(action==="create")return performFullBackup(env,sql,ctx,"manual");
  if(action==="policy")return schedulePolicy(sql,ctx);
  if(action==="set_schedule")return setSchedulePolicy(sql,ctx,String(body.mode||""));
  if(action==="verify")return verifyBackup(env,sql,ctx,String(body.backup_id||""));
  if(action==="verify_latest")return verifyBackup(env,sql,ctx,null);
  if(action==="recovery_test")return runRecoveryTest(env,sql,ctx,String(body.backup_id||""));
  if(action==="storage_maintenance")return performStorageMaintenance(env,sql,ctx);
  fail("Unsupported backup action","unsupported_action",400);
}

export async function dispatchScheduledBackups(env:Env){
  const master=db(env);
  const tenants=await master`
    select tenant_id,tenant_code,school_name,database_name
      from platform.tenant_control
     where status='active' and database_state='isolated_ready' and database_name is not null
     order by tenant_code
     limit 500
  `;
  let completed=0,failed=0,skipped=0;
  for(let offset=0;offset<tenants.length;offset+=2){
    const batch=(tenants as any[]).slice(offset,offset+2);
    const results=await Promise.allSettled(batch.map(async tenant=>{
      const sql=tenantDb(env,String(tenant.database_name));
      const rows=await sql`select public.backup_worker_scheduled_context() context`;
      const raw=(rows[0] as any)?.context;
      if(!raw){skipped++;return;}
      const ctx:SessionContext={
        sessionId:"scheduled-backup",
        userId:String(raw.user_id),
        tenantId:String(raw.tenant_id),
        tenantCode:String(raw.tenant_code),
        tenantName:String(raw.tenant_name),
        databaseName:String(tenant.database_name),
        role:"system_admin",
        assuranceLevel:2,
        email:String(raw.email||""),
        displayName:String(raw.display_name||"System Administrator")
      };
      const policy=await schedulePolicy(sql,ctx);
      const mode=String(policy.mode||"off");
      if(!policy.scheduled_available||!["weekly","monthly"].includes(mode)){skipped++;return;}
      const nextAt=Date.parse(String(policy.next_scheduled_backup_at||""));
      if(Number.isFinite(nextAt)&&nextAt>Date.now()){skipped++;return;}
      await performStorageMaintenance(env,sql,ctx);
      const backup=await performFullBackup(env,sql,ctx,"scheduled");
      if(backup?.id)await verifyBackup(env,sql,ctx,String(backup.id));
      completed++;
    }));
    for(const result of results)if(result.status==="rejected"){
      failed++;
      console.error(JSON.stringify({level:"error",service:"scheduled-backup",message:String(result.reason?.message||result.reason)}));
    }
  }
  const summary={completed,failed,skipped,tenants:tenants.length};
  console.log(JSON.stringify({level:"info",service:"scheduled-backup",...summary}));
  return summary;
}
