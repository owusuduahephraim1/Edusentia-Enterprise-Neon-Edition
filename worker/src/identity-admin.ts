import type { Env, SessionContext } from "./types";
import type { TenantSql } from "./tenant-db";
import { db, tenantTx } from "./db";
import { passwordHash } from "./crypto";

type Body={action?:unknown;payload?:Record<string,unknown>};
type AccessRow={class_id?:unknown;subject_id?:unknown;access_level?:unknown};

function fail(message:string,code="identity_operation_failed",status=400):never{
  throw Object.assign(new Error(message),{code,status});
}
function clean(value:unknown,max=500){return String(value??"").trim().slice(0,max);}
function bool(value:unknown,fallback=false){return value===undefined?fallback:value===true;}
function uuid(value:unknown){const v=clean(value,64);return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v)?v:"";}
const ACCOUNT_EMAIL_TITLES=new Set([
  "mr","mrs","ms","miss","madam","master","dr","doctor","rev","reverend",
  "prof","professor","principal","headmaster","headmistress"
]);
function accountEmailBase(fullName:unknown){
  const parts=String(fullName??"").normalize("NFKD").replace(/[\u0300-\u036f]/g,"").toLowerCase().split(/\s+/)
    .map(part=>part.replace(/[^a-z0-9]/g,"")).filter(Boolean);
  return parts.find(part=>!ACCOUNT_EMAIL_TITLES.has(part))||parts[0]||"user";
}

async function ensureWritable(sql:TenantSql,ctx:SessionContext){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.license_snapshot_for_role('system_admin') result`]);
  const snapshot=(rows[0] as any)?.result||{};
  if(snapshot.write_allowed!==true)fail(String(snapshot.warning||"The current licence is read-only."),"licence_write_restricted",403);
}
function requireAdmin(ctx:SessionContext){
  if(ctx.role!=="system_admin")fail("School System Administrator access required","forbidden",403);
  if(ctx.assuranceLevel<2)fail("A verified MFA session is required","mfa_required",403);
}
function normalizeAccess(value:unknown){
  if(!Array.isArray(value))return [];
  return value.slice(0,1000).map((row:any)=>({
    class_id:uuid(row?.class_id)||null,
    subject_id:uuid(row?.subject_id)||null,
    access_level:clean(row?.access_level||"view",32)
  }));
}
async function generateEmail(sql:TenantSql,ctx:SessionContext,fullName:string,targetUserId:string|null){
  const requestedBase=accountEmailBase(fullName);
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.generate_nip_user_email(${ctx.userId}::uuid,${requestedBase},${targetUserId}::uuid) email`
  ]);
  const email=String((rows[0] as any)?.email||"").trim().toLowerCase();
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))fail("Generated account email is invalid");
  return email;
}
async function validateBundle(sql:TenantSql,ctx:SessionContext,bundle:any,existing:boolean){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.admin_validate_user_bundle(${ctx.userId}::uuid,${JSON.stringify(bundle)}::jsonb,${existing}) result`
  ]);
  return (rows[0] as any)?.result;
}
function bundleFrom(payload:Record<string,unknown>,email:string,userId:string|null,override:Partial<Record<string,unknown>>={}){
  return {
    user_id:userId,
    full_name:clean(override.full_name??payload.full_name,200),
    phone:clean(override.phone??payload.phone,50),
    email,
    role:clean(override.role??payload.role??"parent_guardian",64),
    staff_record_id:override.staff_record_id===undefined?(uuid(payload.staff_record_id)||null):override.staff_record_id,
    active:override.active===undefined?(payload.active!==false):override.active,
    mfa_required:override.mfa_required===undefined?bool(payload.mfa_required,false):override.mfa_required,
    must_change_password:override.must_change_password===undefined?(payload.must_change_password===true||payload.force_password_change===true):override.must_change_password,
    access:normalizeAccess(override.access??payload.access),
    reason:clean(override.reason??payload.reason??"User account management",500)
  };
}

async function syncLoginRoute(env:Env,ctx:SessionContext,email:string,roleName:string,active:boolean){
  const master=db(env),normalized=clean(email,320).toLowerCase();
  if(!normalized)fail("User login route email is required","login_route_invalid",500);
  const rows=await master`select tenant_code,database_name
    from platform.tenant_control
    where tenant_id=${ctx.tenantId}::uuid
      and status='active'
      and database_state='isolated_ready'
      and database_name is not null
      and database_name<>''
    limit 1`;
  const route=rows[0] as any;
  if(!route)fail("School login routing is unavailable","login_route_unavailable",503);
  await master`insert into platform.login_directory(email_normalized,tenant_id,tenant_code,database_name,role_hint,active)
    values(${normalized},${ctx.tenantId}::uuid,${String(route.tenant_code)},${String(route.database_name)},${clean(roleName,64)},${active})
    on conflict(email_normalized,tenant_id) do update set
      tenant_code=excluded.tenant_code,
      database_name=excluded.database_name,
      role_hint=excluded.role_hint,
      active=excluded.active,
      updated_at=now()`;
}
async function removeLoginRoute(env:Env,ctx:SessionContext,email:string){
  const normalized=clean(email,320).toLowerCase();
  if(!normalized)return;
  await db(env)`delete from platform.login_directory where email_normalized=${normalized} and tenant_id=${ctx.tenantId}::uuid`;
}
async function identityEmail(sql:TenantSql,ctx:SessionContext,userId:string){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select email from authn.users where id=${userId}::uuid limit 1`
  ]);
  const row=(rows[0] as any)?.[0]??(rows[0] as any);
  return clean(row?.email,320).toLowerCase();
}

async function createIdentity(env:Env,sql:TenantSql,ctx:SessionContext,payload:Record<string,unknown>,overrides:Partial<Record<string,unknown>>={},guardianId:string|null=null){
  const password=String(payload.password??"");
  if(password.length<8||password.length>128)fail("Use a password between 8 and 128 characters.","invalid_password",422);
  const fullName=clean(overrides.full_name??payload.full_name,200);
  if(!fullName)fail("Full name is required","validation_error",422);
  const credential=await passwordHash(password);

  for(let attempt=0;attempt<5;attempt++){
    const email=await generateEmail(sql,ctx,fullName,null);
    const userId=crypto.randomUUID();
    const bundle=bundleFrom(payload,email,userId,overrides);
    await validateBundle(sql,ctx,{...bundle,user_id:null},false);
    try{
      await syncLoginRoute(env,ctx,email,String(bundle.role),bundle.active!==false);
      const results=await tenantTx<any[]>(sql,ctx,txn=>[
        txn`select public.neon_identity_create_auth_user(
          ${ctx.userId}::uuid,${ctx.tenantId}::uuid,${userId}::uuid,${email},
          ${bundle.full_name},${bundle.phone||null},${bundle.active}::boolean,${String(bundle.role)},
          ${bundle.mfa_required}::boolean,${bundle.must_change_password}::boolean,
          ${credential.hash},${credential.salt},${credential.algorithm}
        ) result`,
        txn`select public.admin_apply_user_bundle(${ctx.userId}::uuid,${JSON.stringify(bundle)}::jsonb) result`,
        ...(guardianId?[txn`select public.neon_identity_link_guardian(${ctx.userId}::uuid,${guardianId}::uuid,${userId}::uuid) result`]:[])
      ]);
      return {ok:true,id:userId,email,full_name:bundle.full_name,role:bundle.role,active:bundle.active,bundle:(results[1] as any)?.[0]?.result??(results[1] as any)?.result};
    }catch(e:any){
      await removeLoginRoute(env,ctx,email).catch(()=>{});
      if(String(e?.code||"")==="23505"&&/email|users_email_lower_uidx|already exists/i.test(String(e?.message||"")))continue;
      throw e;
    }
  }
  fail("A unique school user account email could not be created","email_generation_failed",409);
}

async function updateIdentity(env:Env,sql:TenantSql,ctx:SessionContext,payload:Record<string,unknown>,overrides:Partial<Record<string,unknown>>={},guardianId:string|null=null){
  const userId=uuid(payload.user_id);if(!userId)fail("User account is required","validation_error",422);
  if(String(payload.password??""))fail("Use the protected Reset password action for password changes.","use_reset_password_action",400);
  const fullName=clean(overrides.full_name??payload.full_name,200);if(!fullName)fail("Full name is required","validation_error",422);
  const oldEmail=await identityEmail(sql,ctx,userId);
  const email=await generateEmail(sql,ctx,fullName,userId);
  const bundle=bundleFrom(payload,email,userId,overrides);
  await validateBundle(sql,ctx,bundle,true);
  const results=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.neon_identity_update_auth_user(
      ${ctx.userId}::uuid,${ctx.tenantId}::uuid,${userId}::uuid,${email},
      ${bundle.full_name},${bundle.phone||null},${bundle.active}::boolean,${String(bundle.role)},
      ${bundle.mfa_required}::boolean,${bundle.must_change_password}::boolean
    ) result`,
    txn`select public.admin_apply_user_bundle(${ctx.userId}::uuid,${JSON.stringify(bundle)}::jsonb) result`,
    ...(guardianId?[txn`select public.neon_identity_link_guardian(${ctx.userId}::uuid,${guardianId}::uuid,${userId}::uuid) result`]:[])
  ]);
  await syncLoginRoute(env,ctx,email,String(bundle.role),bundle.active!==false);
  if(oldEmail&&oldEmail!==email)await removeLoginRoute(env,ctx,oldEmail);
  return {ok:true,id:userId,email,full_name:bundle.full_name,role:bundle.role,active:bundle.active,bundle:(results[1] as any)?.[0]?.result??(results[1] as any)?.result};
}

async function refreshGeneratedEmail(env:Env,sql:TenantSql,ctx:SessionContext,selector:Record<string,unknown>){
  const requestedUserId=uuid(selector.user_id);
  const requestedEmail=clean(selector.email,320).toLowerCase();
  const requestedStaffId=uuid(selector.staff_record_id);
  if(!requestedUserId&&!requestedEmail&&!requestedStaffId)fail("User account is required","validation_error",422);
  const requestedUserIdParam=requestedUserId||null;
  const requestedStaffIdParam=requestedStaffId||null;

  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`
    with directory as (
      select jsonb_array_elements(coalesce(public.list_profiles_with_access()->'profiles','[]'::jsonb)) profile
    )
    select profile
    from directory
    where (${requestedUserIdParam}::uuid is not null and profile->>'id'=${requestedUserId})
       or (${requestedEmail}<>'' and lower(coalesce(profile->>'email',''))=${requestedEmail})
       or (${requestedStaffIdParam}::uuid is not null and profile->>'staff_record_id'=${requestedStaffId})
    order by
      case when ${requestedUserIdParam}::uuid is not null and profile->>'id'=${requestedUserId} then 0
           when ${requestedEmail}<>'' and lower(coalesce(profile->>'email',''))=${requestedEmail} then 1
           else 2 end
    limit 1`
  ]);
  const directoryRow=(rows[0] as any)?.[0]??(rows[0] as any);
  const profile=(directoryRow as any)?.profile;
  const userId=uuid(profile?.id);
  if(!profile||!userId)fail("User profile not found","not_found",404);

  const oldEmail=await identityEmail(sql,ctx,userId);
  const newEmail=await generateEmail(sql,ctx,clean(profile.full_name,200),userId);
  if(oldEmail===newEmail)return {ok:true,id:userId,email:newEmail,changed:false};

  await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.neon_identity_update_auth_user(
      ${ctx.userId}::uuid,${ctx.tenantId}::uuid,${userId}::uuid,${newEmail},
      ${clean(profile.full_name,200)},${clean(profile.phone,50)||null},${profile.active!==false}::boolean,${clean(profile.role,64)},
      ${profile.mfa_required===true}::boolean,${profile.must_change_password===true}::boolean
    ) result`
  ]);
  await syncLoginRoute(env,ctx,newEmail,clean(profile.role,64),profile.active!==false);
  if(oldEmail&&oldEmail!==newEmail)await removeLoginRoute(env,ctx,oldEmail);
  return {ok:true,id:userId,email:newEmail,changed:true,old_email:oldEmail};
}

async function ensureDeletable(sql:TenantSql,ctx:SessionContext,userId:string){
  if(userId===ctx.userId)fail("You cannot delete your current account","cannot_delete_current_account",400);
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`
    select p.role::text role,p.active,
      (select count(*)::int from public.profiles q
        where q.active and public.current_app_role_for(q.role)='system_admin' and q.id<>${userId}::uuid) other_admins
    from public.profiles p where p.id=${userId}::uuid limit 1`]);
  const row=(rows[0] as any)?.[0]??(rows[0] as any);
  if(!row)fail("User profile not found","not_found",404);
  if(row.active===true&&String(row.role)==="system_admin"&&Number(row.other_admins||0)<1)fail("At least one active School System Administrator must remain","last_administrator",409);
}
async function resetPassword(sql:TenantSql,ctx:SessionContext,userId:string,password:string,mustChange:boolean){
  if(!userId)fail("User account is required","validation_error",422);
  if(password.length<8||password.length>128)fail("Use a password between 8 and 128 characters.","invalid_password",422);
  const credential=await passwordHash(password);
  await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.neon_identity_reset_password(
      ${ctx.userId}::uuid,${ctx.tenantId}::uuid,${userId}::uuid,
      ${credential.hash},${credential.salt},${credential.algorithm},${mustChange}::boolean
    ) result`
  ]);
  return {ok:true,id:userId,password_reset:true,must_change_password:mustChange};
}

async function genericAdmin(env:Env,sql:TenantSql,ctx:SessionContext,body:Body){
  const action=clean(body.action,80),payload=(body.payload&&typeof body.payload==="object"?body.payload:{}) as Record<string,unknown>;
  if(action==="complete_own_required_password_change"){
    const password=String(payload.password??"");
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select must_change_password from public.profiles where id=${ctx.userId}::uuid limit 1`]);
    const profile=(rows[0] as any)?.[0]??(rows[0] as any);
    if(!profile)fail("User profile not found","not_found",404);
    if(profile.must_change_password!==true)return {ok:true,password_changed:true,id:ctx.userId,must_change_password:false,already_completed:true};
    const result=await resetPassword(sql,ctx,ctx.userId,password,false);
    return {...result,password_changed:true};
  }

  requireAdmin(ctx);await ensureWritable(sql,ctx);
  if(action==="create")return createIdentity(env,sql,ctx,payload);
  if(action==="update")return updateIdentity(env,sql,ctx,payload);
  if(action==="reset_password"){
    const userId=uuid(payload.user_id),password=String(payload.password??"");
    return resetPassword(sql,ctx,userId,password,payload.must_change_password!==false);
  }
  if(action==="refresh_generated_email"){
    return refreshGeneratedEmail(env,sql,ctx,payload);
  }
  if(action==="delete"){
    const userId=uuid(payload.user_id);if(!userId)fail("User account is required","validation_error",422);
    await ensureDeletable(sql,ctx,userId);
    const email=await identityEmail(sql,ctx,userId);
    await tenantTx<any[]>(sql,ctx,txn=>[
      txn`select public.neon_identity_delete_auth_user(
        ${ctx.userId}::uuid,${ctx.tenantId}::uuid,${userId}::uuid,${clean(payload.reason,500)}
      ) result`
    ]);
    await removeLoginRoute(env,ctx,email);
    return {ok:true,id:userId,deleted:true};
  }
  fail("Unsupported user-management action","unsupported_action",400);
}

async function directoryRecord(sql:TenantSql,ctx:SessionContext,role:string,recordId:string){
  if(role==="accountant"||role==="student"){
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.list_profiles_with_access() result`]);
    const data=(rows[0] as any)?.result||{};
    const source=role==="accountant"?(Array.isArray(data.accountant_records)?data.accountant_records:[]):(Array.isArray(data.student_records)?data.student_records:[]);
    const row=source.find((item:any)=>String(item?.id||"")===recordId);
    if(!row||row.active===false)fail(role==="accountant"?"Accounts Office Staff record is unavailable":"Student record is unavailable","directory_record_unavailable",404);
    return {profileId:row.profile_id||null,fullName:String(row.full_name||""),phone:role==="accountant"?String(row.phone||""):""};
  }
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select public.neon_guardian_account_records() result`]);
  const guardians=Array.isArray((rows[0] as any)?.result)?(rows[0] as any).result:[];
  const guardian=guardians.find((item:any)=>String(item?.id||"")===recordId);
  if(!guardian)fail("Parent or Guardian record is unavailable","directory_record_unavailable",404);
  if(Number(guardian.linked_account_count||0)>1)fail("This Parent or Guardian record has conflicting portal-account links","directory_link_conflict",409);
  if(!Array.isArray(guardian.children)||guardian.children.length<1)fail("This Parent or Guardian record is not linked to a student","directory_record_unavailable",409);
  return {profileId:guardian.auth_user_id||null,fullName:String(guardian.full_name||""),phone:String(guardian.phone||"")};
}

async function directoryAdmin(env:Env,sql:TenantSql,ctx:SessionContext,body:Body){
  requireAdmin(ctx);await ensureWritable(sql,ctx);
  const action=clean(body.action,40),payload=(body.payload&&typeof body.payload==="object"?body.payload:{}) as Record<string,unknown>;
  const role=clean(payload.role,64);
  if(!["accountant","student","parent_guardian"].includes(role))fail("Unsupported directory role","unsupported_directory_role",400);
  const recordId=uuid(role==="parent_guardian"?payload.guardian_record_id:(payload.staff_record_id??payload.student_id));
  if(!recordId)fail("Directory record is required","validation_error",422);
  const record=await directoryRecord(sql,ctx,role,recordId);
  const targetId=uuid(payload.user_id);
  if(record.profileId&&record.profileId!==targetId)fail("This directory record is already linked to another account","directory_already_linked",409);
  const overrides:any={role,full_name:record.fullName,phone:record.phone,access:[],reason:`${role} account ${action==="create"?"created":"updated"}`};
  if(role!=="parent_guardian")overrides.staff_record_id=recordId;else overrides.staff_record_id=null;
  if(action==="create"){
    if(record.profileId)fail("This directory record already has an account","directory_already_linked",409);
    return createIdentity(env,sql,ctx,payload,overrides,role==="parent_guardian"?recordId:null);
  }
  if(action==="update"){
    if(!targetId||record.profileId!==targetId)fail("The selected account is not linked to this directory record","directory_link_mismatch",409);
    return updateIdentity(env,sql,ctx,payload,overrides,role==="parent_guardian"?recordId:null);
  }
  fail("Unsupported directory user action","unsupported_action",400);
}

export async function handleLegacyIdentityFunction(name:string,env:Env,sql:TenantSql,ctx:SessionContext,body:Body){
  if(name==="admin-user-management")return genericAdmin(env,sql,ctx,body);
  if(name==="directory-user-management")return directoryAdmin(env,sql,ctx,body);
  fail("Unsupported identity function","not_found",404);
}
