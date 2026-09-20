import type { Env } from "./types";
import { decryptTotpSecret, encryptTotpSecret, generateTotpSecret, otpauthUri, verifyTotp } from "./mfa";

export async function listMfaFactors(sql:any,userId:string){
  const rows=await sql`
    select id,friendly_name,verified_at,created_at
      from authn.mfa_totp_factors
     where user_id=${userId}::uuid and disabled_at is null
     order by verified_at desc nulls last,created_at`;
  return rows.map((r:any)=>({
    id:String(r.id),
    friendlyName:String(r.friendly_name||"Authenticator"),
    verified:Boolean(r.verified_at),
    verifiedAt:r.verified_at||null,
    createdAt:r.created_at
  }));
}

export async function beginMfaEnrollment(env:Env,sql:any,userId:string,email:string,accountLabel:string,friendlyNameRaw:string){
  const friendlyName=String(friendlyNameRaw||"").trim();
  if(friendlyName.length<3||friendlyName.length>64)throw Object.assign(new Error("Authenticator name must contain 3 to 64 characters"),{code:"mfa_name_invalid",status:422});
  const countRows=await sql`select count(*)::int count from authn.mfa_totp_factors where user_id=${userId}::uuid and disabled_at is null`;
  if(Number((countRows[0] as any)?.count||0)>=10)throw Object.assign(new Error("The maximum number of authenticator factors has been reached"),{code:"mfa_factor_limit",status:409});
  const secret=generateTotpSecret(),ciphertext=await encryptTotpSecret(env,secret);
  const rows=await sql`insert into authn.mfa_totp_factors(user_id,secret_ciphertext,friendly_name) values(${userId}::uuid,${ciphertext},${friendlyName}) returning id,created_at`;
  return {factorId:String((rows[0] as any).id),friendlyName,secret,otpauthUri:otpauthUri(secret,email,accountLabel),createdAt:(rows[0] as any).created_at};
}

export async function verifyMfaEnrollment(env:Env,sql:any,userId:string,factorId:string,codeRaw:string){
  const code=String(codeRaw||"").trim();
  if(!/^\d{6}$/.test(code))throw Object.assign(new Error("Enter the current six-digit authenticator code"),{code:"mfa_invalid_code",status:422});
  const rows=await sql`select id,secret_ciphertext,verified_at from authn.mfa_totp_factors where id=${factorId}::uuid and user_id=${userId}::uuid and disabled_at is null limit 1`;
  const factor=rows[0] as any;
  if(!factor)throw Object.assign(new Error("Authenticator factor was not found"),{code:"mfa_factor_not_found",status:404});
  if(factor.verified_at)return {ok:true,alreadyVerified:true};
  const valid=await verifyTotp(await decryptTotpSecret(env,String(factor.secret_ciphertext)),code);
  if(!valid)throw Object.assign(new Error("The authenticator code is incorrect"),{code:"mfa_invalid_code",status:401});
  await sql`update authn.mfa_totp_factors set verified_at=now() where id=${factorId}::uuid and user_id=${userId}::uuid and disabled_at is null and verified_at is null`;
  return {ok:true,verified:true};
}

export async function removeMfaFactor(sql:any,userId:string,factorId:string){
  const rows=await sql`select id,friendly_name,verified_at from authn.mfa_totp_factors where id=${factorId}::uuid and user_id=${userId}::uuid and disabled_at is null limit 1`;
  const factor=rows[0] as any;
  if(!factor)throw Object.assign(new Error("Authenticator factor was not found"),{code:"mfa_factor_not_found",status:404});
  if(factor.verified_at){
    const countRows=await sql`select count(*)::int count from authn.mfa_totp_factors where user_id=${userId}::uuid and verified_at is not null and disabled_at is null`;
    if(Number((countRows[0] as any)?.count||0)<=1)throw Object.assign(new Error("The final verified authenticator cannot be removed. Add and verify a backup authenticator first."),{code:"mfa_final_factor",status:409});
  }
  await sql`update authn.mfa_totp_factors set disabled_at=now() where id=${factorId}::uuid and user_id=${userId}::uuid and disabled_at is null`;
  return {ok:true,friendlyName:String(factor.friendly_name||"Authenticator"),verified:Boolean(factor.verified_at)};
}
