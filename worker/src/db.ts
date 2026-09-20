import { neon, type NeonQueryFunction } from "@neondatabase/serverless";
import type { Env, SessionContext } from "./types";
export type Sql = NeonQueryFunction<false,false>;
export function db(env:Env):Sql{return neon(env.DATABASE_URL);}
export async function tenantTx<T extends unknown[]>(sql:Sql,ctx:SessionContext,build:(txn:any)=>any[]):Promise<T>{
  const result=await sql.transaction((txn:any)=>[
    txn`select app.set_request_context(${ctx.tenantId}::uuid,${ctx.userId}::uuid,${ctx.role},${ctx.assuranceLevel}::smallint)`,
    ...build(txn)
  ]);
  return result.slice(1) as T;
}
