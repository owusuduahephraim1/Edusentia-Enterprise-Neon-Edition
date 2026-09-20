import type { SessionContext } from "./types";
import type { Sql } from "./db";
import { tenantTx } from "./db";

export const CERTIFIED_RPC_OPERATIONS = Object.freeze([
  "get_bootstrap_data",
  "get_academic_configuration"
] as const);

export type CertifiedRpcOperation=(typeof CERTIFIED_RPC_OPERATIONS)[number];

function noArguments(args:unknown){
  if(args==null)return;
  if(typeof args!=="object"||Array.isArray(args)||Object.keys(args as Record<string,unknown>).length!==0){
    throw Object.assign(new Error("This certified operation does not accept arguments"),{code:"invalid_rpc_arguments",status:422});
  }
}

export function isCertifiedRpcOperation(value:string):value is CertifiedRpcOperation{
  return (CERTIFIED_RPC_OPERATIONS as readonly string[]).includes(value);
}

export async function invokeCertifiedRpc(sql:Sql,ctx:SessionContext,operation:string,args:unknown){
  if(!isCertifiedRpcOperation(operation)){
    throw Object.assign(new Error("This certified operation is not exposed by the Neon API"),{code:"certified_rpc_not_allowed",status:404});
  }

  switch(operation){
    case "get_bootstrap_data":{
      noArguments(args);
      const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
        txn`select public.get_bootstrap_data() result`
      ]);
      return (rows[0] as any)?.result??null;
    }
    case "get_academic_configuration":{
      noArguments(args);
      const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[
        txn`select public.get_academic_configuration() result`
      ]);
      return (rows[0] as any)?.result??null;
    }
  }
}
