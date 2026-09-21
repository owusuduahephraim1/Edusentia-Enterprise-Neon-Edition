import type { SessionContext } from "./types";
import type { TenantSql } from "./tenant-db";
import { tenantTx } from "./db";
import { passwordHash } from "./crypto";

type Body={action?:unknown;payload?:Record<string,unknown>};
type AccessRow={class_id?:unknown;subject_id?:unknown;access_level?:unknown};

function fail(message:string,code="identity_operation_failed",status=400):never{
  throw Object.assign(new Error(message),{code,status});
}
function clean(value:unknown,max=500){return String(value??"").trim().slice(0,max);}
function bool(value:unknown,fallback=false){return value===undefined?fallback:value===true;}
function uuid(value:unknown){const v=clean(value,64);return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v)?v:"";}

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
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select public.generate_nip_user_email(${ctx.userId}::uuid,${fullName},${targetUserId}::uuid) email`
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

async function createIdentity(sql:TenantSql,ctx:SessionContext,payload:Record<string,unknown>,overrides:Partial<Record<string,unknown>>={},guardianId:string|null=null){
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
      const results=await tenantTx<any[]>(sql,ctx,txn=>[
        txn`insert into authn.users(
              id,email,display_name,phone,disabled_at,raw_user_meta_data,raw_app_meta_data
            ) values(
              ${userId}::uuid,${email},${bundle.full_name},${bundle.phone||null},
              case when ${bundle.active}::boolean then null else now() end,
              ${JSON.stringify({full_name:bundle.full_name,must_change_password:bundle.must_change_password})}::jsonb,
              ${JSON.stringify({role:bundle.role})}::jsonb
            )`,
        txn`insert into authn.password_credentials(user_id,password_hash,password_salt,algorithm)
            values(${userId}::uuid,${credential.hash},${credential.salt},${credential.algorithm})`,
        txn`insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required)
            values(${ctx.tenantId}::uuid,${userId}::uuid,${String(bundle.role)},
              case when ${bundle.active}::boolean then 'active' else 'suspended' end,${bundle.mfa_required})
            on conflict(tenant_id,user_id) do update set
              role=excluded.role,status=excluded.status,mfa_required=excluded.mfa_required`,
        txn`select public.admin_apply_user_bundle(${ctx.userId}::uuid,${JSON.stringify(bundle)}::jsonb) result`,
        ...(guardianId?[txn`update public.guardian_links set auth_user_id=${userId}::uuid where guardian_id=${guardianId}::uuid`]:[])
      ]);
      return {ok:true,id:userId,email,full_name:bundle.full_name,role:bundle.role,active:bundle.active,bundle:(results[3] as any)?.[0]?.result??(results[3] as any)?.result};
    }catch(e:any){
      if(String(e?.code||"")==="23505"&&/email|users_email_lower_uidx/i.test(String(e?.message||"")))continue;
      throw e;
    }
  }
  fail("A unique school user account email could not be created","email_generation_failed",409);
}

async function updateIdentity(sql:TenantSql,ctx:SessionContext,payload:Record<string,unknown>,overrides:Partial<Record<string,unknown>>={},guardianId:string|null=null){
  const userId=uuid(payload.user_id);if(!userId)fail("User account is required","validation_error",422);
  if(String(payload.password??""))fail("Use the protected Reset password action for password changes.","use_reset_password_action",400);
  const fullName=clean(overrides.full_name??payload.full_name,200);if(!fullName)fail("Full name is required","validation_error",422);
  const email=await generateEmail(sql,ctx,fullName,userId);
  const bundle=bundleFrom(payload,email,userId,overrides);
  await validateBundle(sql,ctx,bundle,true);
  const results=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`update authn.users set
          email=${email},display_name=${bundle.full_name},phone=${bundle.phone||null},
          disabled_at=case when ${bundle.active}::boolean then null else coalesce(disabled_at,now()) end,
          raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||${JSON.stringify({full_name:bundle.full_name,must_change_password:bundle.must_change_password})}::jsonb,
          raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||${JSON.stringify({role:bundle.role})}::jsonb,
          updated_at=now()
        where id=${userId}::uuid`,
    txn`insert into app.tenant_memberships(tenant_id,user_id,role,status,mfa_required)
        values(${ctx.tenantId}::uuid,${userId}::uuid,${String(bundle.role)},
          case when ${bundle.active}::boolean then 'active' else 'suspended' end,${bundle.mfa_required})
        on conflict(tenant_id,user_id) do update set
          role=excluded.role,status=excluded.status,mfa_required=excluded.mfa_required`,
    txn`select public.admin_apply_user_bundle(${ctx.userId}::uuid,${JSON.stringify(bundle)}::jsonb) result`,
    ...(guardianId?[txn`update public.guardian_links set auth_user_id=${userId}::uuid where guardian_id=${guardianId}::uuid`]:[])
  ]);
  return {ok:true,id:userId,email,full_name:bundle.full_name,role:bundle.role,active:bundle.active,bundle:(results[2] as any)?.[0]?.result??(results[2] as any)?.result};
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
    txn`insert into authn.password_credentials(user_id,password_hash,password_salt,algorithm,password_changed_at,failed_attempts,locked_until)
        values(${userId}::uuid,${credential.hash},${credential.salt},${credential.algorithm},now(),0,null)
        on conflict(user_id) do update set
          password_hash=excluded.password_hash,password_salt=excluded.password_salt,algorithm=excluded.algorithm,
          password_changed_at=now(),failed_attempts=0,locked_until=null`,
    txn`update authn.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||
          ${JSON.stringify({must_change_password:mustChange})}::jsonb,updated_at=now() where id=${userId}::uuid`,
    txn`update public.profiles set must_change_password=${mustChange},updated_at=now() where id=${userId}::uuid`,
    txn`select audit.record_auth_event(${ctx.tenantId}::uuid,${ctx.userId}::uuid,'auth.password.admin_reset',
          ${JSON.stringify({target_user_id:userId,must_change_password:mustChange})}::jsonb)`
  ]);
  return {ok:true,id:userId,password_reset:true,must_change_password:mustChange};
}

async function genericAdmin(sql:TenantSql,ctx:SessionContext,body:Body){
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
  if(action==="create")return createIdentity(sql,ctx,payload);
  if(action==="update")return updateIdentity(sql,ctx,payload);
  if(action==="reset_password"){
    const userId=uuid(payload.user_id),password=String(payload.password??"");
    return resetPassword(sql,ctx,userId,password,payload.must_change_password!==false);
  }
  if(action==="delete"){
    const userId=uuid(payload.user_id);if(!userId)fail("User account is required","validation_error",422);
    await ensureDeletable(sql,ctx,userId);
    await tenantTx<any[]>(sql,ctx,txn=>[
      txn`select audit.record_auth_event(${ctx.tenantId}::uuid,${ctx.userId}::uuid,'auth.user.delete',
            ${JSON.stringify({target_user_id:userId,reason:clean(payload.reason,500)})}::jsonb)`,
      txn`delete from authn.users where id=${userId}::uuid`
    ]);
    return {ok:true,id:userId,deleted:true};
  }
  fail("Unsupported user-management action","unsupported_action",400);
}

async function directoryRecord(sql:TenantSql,ctx:SessionContext,role:string,recordId:string){
  if(role==="accountant"){
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select id,profile_id,full_name,phone,active,deleted_at from public.accounts_office_staff where id=${recordId}::uuid limit 1`]);
    const row=(rows[0] as any)?.[0]??(rows[0] as any);if(!row||row.deleted_at||row.active!==true)fail("Accounts Office Staff record is unavailable","directory_record_unavailable",404);
    return {profileId:row.profile_id||null,fullName:String(row.full_name||""),phone:String(row.phone||"")};
  }
  if(role==="student"){
    const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select id,profile_id,first_name,middle_name,last_name,status,deleted_at from public.students where id=${recordId}::uuid limit 1`]);
    const row=(rows[0] as any)?.[0]??(rows[0] as any);if(!row||row.deleted_at||row.status!=="active")fail("Student record is unavailable","directory_record_unavailable",404);
    return {profileId:row.profile_id||null,fullName:[row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" ").trim(),phone:""};
  }
  const [guardianRows,linkRows]=await tenantTx<any[]>(sql,ctx,txn=>[
    txn`select id,full_name,phone from public.student_guardians where id=${recordId}::uuid limit 1`,
    txn`select distinct auth_user_id from public.guardian_links where guardian_id=${recordId}::uuid and auth_user_id is not null`
  ]);
  const guardian=(guardianRows[0] as any)?.[0]??(guardianRows[0] as any);
  const links=Array.isArray(linkRows)?linkRows:[];if(!guardian)fail("Parent or Guardian record is unavailable","directory_record_unavailable",404);
  if(!links.length){
    const [countRows]=await tenantTx<any[]>(sql,ctx,txn=>[txn`select count(*)::int count from public.guardian_links where guardian_id=${recordId}::uuid`]);
    const count=Number(((countRows[0] as any)?.[0]??(countRows[0] as any))?.count||0);
    if(count<1)fail("This Parent or Guardian record is not linked to a student","directory_record_unavailable",409);
  }
  if(links.length>1)fail("This Parent or Guardian record has conflicting portal-account links","directory_link_conflict",409);
  return {profileId:links[0]?.auth_user_id||null,fullName:String(guardian.full_name||""),phone:String(guardian.phone||"")};
}

async function directoryAdmin(sql:TenantSql,ctx:SessionContext,body:Body){
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
    return createIdentity(sql,ctx,payload,overrides,role==="parent_guardian"?recordId:null);
  }
  if(action==="update"){
    if(!targetId||record.profileId!==targetId)fail("The selected account is not linked to this directory record","directory_link_mismatch",409);
    return updateIdentity(sql,ctx,payload,overrides,role==="parent_guardian"?recordId:null);
  }
  fail("Unsupported directory user action","unsupported_action",400);
}

export async function handleLegacyIdentityFunction(name:string,sql:TenantSql,ctx:SessionContext,body:Body){
  if(name==="admin-user-management")return genericAdmin(sql,ctx,body);
  if(name==="directory-user-management")return directoryAdmin(sql,ctx,body);
  fail("Unsupported identity function","not_found",404);
}
