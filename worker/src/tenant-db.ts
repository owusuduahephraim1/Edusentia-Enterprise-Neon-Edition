import { neon, type NeonQueryFunction } from "@neondatabase/serverless";
import type { Env } from "./types";

export type TenantSql = NeonQueryFunction<false,false>;

export function validateDatabaseName(name:string){
  const value=String(name||"").trim();
  if(!/^edusentia_[a-z0-9_]{3,50}$/.test(value)) throw Object.assign(new Error("Invalid tenant database route"),{code:"tenant_route_invalid",status:500});
  return value;
}
export function tenantDatabaseName(tenantCode:string){
  const code=String(tenantCode||"").trim().toUpperCase();
  if(!/^[A-Z]{3}-\d{6}$/.test(code)) throw Object.assign(new Error("Invalid institution code"),{code:"tenant_code_invalid",status:422});
  return `edusentia_${code.toLowerCase().replace(/-/g,"_")}`;
}
export function databaseUrl(baseUrl:string,databaseName:string){
  const name=validateDatabaseName(databaseName),u=new URL(baseUrl);
  u.pathname=`/${name}`;
  return u.toString();
}
export function tenantDb(env:Env,databaseName:string):TenantSql{
  return neon(databaseUrl(env.DATABASE_URL,databaseName));
}
export function routedToken(tenantCode:string,opaque:string){
  const code=String(tenantCode||"").trim().toUpperCase();
  if(!/^[A-Z]{3}-\d{6}$/.test(code))throw new Error("Invalid tenant code");
  return `${code}.${opaque}`;
}
export function tokenTenantCode(token:string){
  const i=String(token||"").indexOf(".");
  if(i<=0)return "";
  const code=token.slice(0,i).toUpperCase();
  return /^[A-Z]{3}-\d{6}$/.test(code)?code:"";
}
