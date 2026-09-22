import { neon, type NeonQueryFunction } from "@neondatabase/serverless";
import type { Env, SessionContext } from "./types";
export type Sql = NeonQueryFunction<false,false>;
export function db(env:Env):Sql{return neon(env.DATABASE_URL);}
export function canonicalAppRole(role:unknown){
  const value=String(role||"").trim();
  if(value==="admin")return "system_admin";
  if(value==="teacher")return "class_teacher";
  return value;
}
export async function tenantTx<T extends unknown[]>(sql:Sql,ctx:SessionContext,build:(txn:any)=>any[]):Promise<T>{
  const role=canonicalAppRole(ctx.role);
  const result=await sql.transaction((txn:any)=>[
    txn`select app.set_request_context(${ctx.tenantId}::uuid,${ctx.userId}::uuid,${role},${ctx.assuranceLevel}::smallint)`,
    ...build(txn)
  ]);
  return result.slice(1) as T;
}
