import type { SessionContext } from "./types";
import type { Sql } from "./db";
import { tenantTx } from "./db";

export const CERTIFIED_RPC_OPERATIONS = Object.freeze([
  "get_bootstrap_data",
  "get_report_editor",
  "get_report_revisions",
  "list_audit_events",
  "list_notifications",
  "list_profiles_with_access",
  "search_students",
  "mark_notifications_read",
  "save_student",
  "bulk_import_students",
  "bulk_import_scores",
  "save_report_card",
  "transition_report_status"
] as const);

export type CertifiedRpcOperation=(typeof CERTIFIED_RPC_OPERATIONS)[number];
type Args=Record<string,unknown>;

function objectArgs(args:unknown):Args{
  if(args==null)return {};
  if(typeof args!=="object"||Array.isArray(args))throw Object.assign(new Error("Certified operation arguments must be an object"),{code:"invalid_rpc_arguments",status:422});
  return args as Args;
}
function noArguments(args:unknown){
  if(Object.keys(objectArgs(args)).length!==0)throw Object.assign(new Error("This certified operation does not accept arguments"),{code:"invalid_rpc_arguments",status:422});
}
function textArg(args:Args,name:string,{required=false,max=1000}:{required?:boolean,max?:number}={}){
  const raw=args[name];
  if(raw==null||raw===""){if(required)throw Object.assign(new Error(`${name} is required`),{code:"invalid_rpc_arguments",status:422});return null;}
  if(typeof raw!=="string"||raw.length>max)throw Object.assign(new Error(`${name} is invalid`),{code:"invalid_rpc_arguments",status:422});
  return raw;
}
function uuidArg(args:Args,name:string,required=false){
  const value=textArg(args,name,{required,max:64});
  if(value==null)return null;
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value))throw Object.assign(new Error(`${name} must be a UUID`),{code:"invalid_rpc_arguments",status:422});
  return value;
}
function intArg(args:Args,name:string,{required=true,min=0,max=1000}:{required?:boolean,min?:number,max?:number}={}){
  const raw=args[name];
  if(raw==null||raw===""){if(required)throw Object.assign(new Error(`${name} is required`),{code:"invalid_rpc_arguments",status:422});return null;}
  const value=Number(raw);
  if(!Number.isInteger(value)||value<min||value>max)throw Object.assign(new Error(`${name} is invalid`),{code:"invalid_rpc_arguments",status:422});
  return value;
}
function jsonArg(args:Args,name:string){
  const value=args[name];
  if(value==null||typeof value!=="object")throw Object.assign(new Error(`${name} is required`),{code:"invalid_rpc_arguments",status:422});
  return JSON.stringify(value);
}
function uuidArrayArg(args:Args,name:string){
  const value=args[name];
  if(value==null)return null;
  if(!Array.isArray(value)||value.length>500)throw Object.assign(new Error(`${name} is invalid`),{code:"invalid_rpc_arguments",status:422});
  const ids=value.map((item,index)=>uuidArg({value:item},"value",true)??"");
  return `{${ids.join(",")}}`;
}
async function singleResult(sql:Sql,ctx:SessionContext,build:(txn:any)=>any){
  const [rows]=await tenantTx<any[]>(sql,ctx,txn=>[build(txn)]);
  return (rows[0] as any)?.result??null;
}

export function isCertifiedRpcOperation(value:string):value is CertifiedRpcOperation{
  return (CERTIFIED_RPC_OPERATIONS as readonly string[]).includes(value);
}

export async function invokeCertifiedRpc(sql:Sql,ctx:SessionContext,operation:string,argsInput:unknown){
  if(!isCertifiedRpcOperation(operation)){
    throw Object.assign(new Error("This certified operation is not exposed by the Neon API"),{code:"certified_rpc_not_allowed",status:404});
  }
  const args=objectArgs(argsInput);

  switch(operation){
    case "get_bootstrap_data":
      noArguments(args);
      return singleResult(sql,ctx,txn=>txn`select public.get_bootstrap_data() result`);

    case "get_report_editor":{
      const reportId=uuidArg(args,"target_report_id");
      const enrollmentId=uuidArg(args,"target_enrollment_id");
      const termId=uuidArg(args,"target_term_id");
      if(!reportId&&!enrollmentId)throw Object.assign(new Error("target_report_id or target_enrollment_id is required"),{code:"invalid_rpc_arguments",status:422});
      return singleResult(sql,ctx,txn=>txn`select public.get_report_editor(${reportId}::uuid,${enrollmentId}::uuid,${termId}::uuid) result`);
    }
    case "get_report_revisions":{
      const reportId=uuidArg(args,"target_report_id",true);
      return singleResult(sql,ctx,txn=>txn`select public.get_report_revisions(${reportId}::uuid) result`);
    }
    case "list_audit_events":{
      const table=textArg(args,"target_table",{max:128});
      const recordId=uuidArg(args,"target_record_id");
      const page=intArg(args,"page_number",{min:1,max:100000});
      const pageSize=intArg(args,"page_size",{min:1,max:500});
      return singleResult(sql,ctx,txn=>txn`select public.list_audit_events(${table},${recordId}::uuid,${page}::integer,${pageSize}::integer) result`);
    }
    case "list_notifications":{
      const page=intArg(args,"page_number",{min:1,max:100000});
      const pageSize=intArg(args,"page_size",{min:1,max:500});
      return singleResult(sql,ctx,txn=>txn`select public.list_notifications(${page}::integer,${pageSize}::integer) result`);
    }
    case "list_profiles_with_access":
      noArguments(args);
      return singleResult(sql,ctx,txn=>txn`select public.list_profiles_with_access() result`);

    case "search_students":{
      const search=textArg(args,"search_text",{max:200})??"";
      const classId=uuidArg(args,"target_class_id");
      const status=textArg(args,"target_status",{max:32});
      const page=intArg(args,"page_number",{min:1,max:100000});
      const pageSize=intArg(args,"page_size",{min:1,max:500});
      return singleResult(sql,ctx,txn=>txn`select public.search_students(${search},${classId}::uuid,${status}::public.student_status,${page}::integer,${pageSize}::integer) result`);
    }
    case "mark_notifications_read":{
      const ids=uuidArrayArg(args,"notification_ids");
      return singleResult(sql,ctx,txn=>txn`select public.mark_notifications_read(${ids}::uuid[]) result`);
    }
    case "save_student":{
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_student(${payload}::jsonb) result`);
    }
    case "bulk_import_students":{
      const rows=jsonArg(args,"rows");
      const filename=textArg(args,"filename",{required:true,max:255});
      return singleResult(sql,ctx,txn=>txn`select public.bulk_import_students(${rows}::jsonb,${filename}) result`);
    }
    case "bulk_import_scores":{
      const termId=uuidArg(args,"target_term_id",true);
      const classId=uuidArg(args,"target_class_id",true);
      const rows=jsonArg(args,"rows");
      const filename=textArg(args,"filename",{required:true,max:255});
      return singleResult(sql,ctx,txn=>txn`select public.bulk_import_scores(${termId}::uuid,${classId}::uuid,${rows}::jsonb,${filename}) result`);
    }
    case "save_report_card":{
      const payload=jsonArg(args,"payload");
      const version=intArg(args,"expected_version",{min:0,max:2147483647});
      return singleResult(sql,ctx,txn=>txn`select public.save_report_card(${payload}::jsonb,${version}::integer) result`);
    }
    case "transition_report_status":{
      const reportId=uuidArg(args,"target_report_id",true);
      const status=textArg(args,"target_status",{required:true,max:32});
      const comment=textArg(args,"comment_text",{max:2000});
      const version=intArg(args,"expected_version",{min:0,max:2147483647});
      return singleResult(sql,ctx,txn=>txn`select public.transition_report_status(${reportId}::uuid,${status}::public.report_status,${comment},${version}::integer) result`);
    }
  }
}
