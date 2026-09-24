import type { SessionContext } from "./types";
import type { Sql } from "./db";
import { tenantTx } from "./db";
import { CERTIFIED_RPC_REGISTRY_NAMES, invokeRegistryCertifiedRpc } from "./certified-rpc-registry";

const EXPLICIT_CERTIFIED_RPC_OPERATIONS = Object.freeze([
  "get_bootstrap_data",
  "get_academic_configuration",
  "get_academic_calendar_context",
  "get_my_emergency_academic_delegations",
  "academic_configuration_readiness",
  "set_active_period",
  "get_report_editor",
  "get_report_revisions",
  "get_report_headteacher_signature",
  "delete_report_card_permanently",
  "list_report_pdf_paths",
  "register_report_pdf",
  "list_audit_events",
  "list_audit_events_v2",
  "list_audit_archives_v1",
  "list_audit_archive_entries_v1",
  "list_notifications",
  "list_profiles_with_access",
  "search_students",
  "search_students_v5",
  "mark_notifications_read",
  "save_student",
  "bulk_import_students",
  "bulk_import_scores",
  "save_report_card",
  "transition_report_status",
  "generate_school_identifier",
  "validate_student_import",
  "save_promotion_cutoff",
  "save_academic_entity",
  "archive_academic_entity",
  "save_grading_scale",
  "archive_grading_scale",
  "save_assessment_scheme",
  "save_class_subject_assignments_batch",
  "list_teachers",
  "get_teacher_record",
  "get_my_teacher_profile",
  "save_teacher",
  "archive_teacher",
  "restore_teacher",
  "set_teacher_photo",
  "list_headteachers",
  "get_headteacher_record",
  "get_my_headteacher_signature",
  "save_headteacher",
  "archive_headteacher",
  "restore_headteacher",
  "set_headteacher_photo",
  "set_my_headteacher_signature",
  "get_class_timetable_console",
  "save_class_timetable_entry"
] as const);

export const CERTIFIED_RPC_OPERATIONS=Object.freeze(
  Array.from(new Set<string>([...EXPLICIT_CERTIFIED_RPC_OPERATIONS,...CERTIFIED_RPC_REGISTRY_NAMES])).sort()
);
export type CertifiedRpcOperation=string;
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
function pathArg(args:Args,name:string,max=1024){
  const raw=args[name];
  if(raw==null)return "";
  if(typeof raw!=="string"||raw.length>max)throw Object.assign(new Error(`${name} is invalid`),{code:"invalid_rpc_arguments",status:422});
  return raw;
}
function timestampArg(args:Args,name:string){
  const raw=args[name];
  if(raw==null||raw==="")return null;
  if(typeof raw!=="string"||raw.length>64||Number.isNaN(Date.parse(raw)))throw Object.assign(new Error(`${name} is invalid`),{code:"invalid_rpc_arguments",status:422});
  return raw;
}
function staffListArgs(args:Args){
  const search=textArg(args,"search_text",{max:200})??"";
  const status=textArg(args,"status_filter",{max:32})??"";
  const archive=textArg(args,"archive_filter",{max:16})??"active";
  if(status&&!["active","leave","suspended","resigned","retired"].includes(status))throw Object.assign(new Error("status_filter is invalid"),{code:"invalid_rpc_arguments",status:422});
  if(!["active","archived","all"].includes(archive))throw Object.assign(new Error("archive_filter is invalid"),{code:"invalid_rpc_arguments",status:422});
  const page=intArg(args,"page_number",{required:false,min:1,max:100000})??1;
  const pageSize=intArg(args,"page_size",{required:false,min:1,max:100})??20;
  return {search,status,archive,page,pageSize};
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

    case "get_academic_configuration":
      noArguments(args);
      return singleResult(sql,ctx,txn=>txn`select public.get_academic_configuration() result`);

    case "get_academic_calendar_context":
      noArguments(args);
      return singleResult(sql,ctx,txn=>txn`select public.get_academic_calendar_context() result`);

    case "get_my_emergency_academic_delegations":{
      const classId=uuidArg(args,"target_class_id");
      const termId=uuidArg(args,"target_term_id");
      return singleResult(sql,ctx,txn=>txn`select public.get_my_emergency_academic_delegations(${classId}::uuid,${termId}::uuid) result`);
    }

    case "academic_configuration_readiness":
      noArguments(args);
      return singleResult(sql,ctx,txn=>txn`select public.academic_configuration_readiness() result`);

    case "set_active_period":{
      const academicYearId=uuidArg(args,"target_academic_year_id",true);
      const termId=uuidArg(args,"target_term_id",true);
      return singleResult(sql,ctx,txn=>txn`select public.set_active_period(${academicYearId}::uuid,${termId}::uuid) result`);
    }

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
    case "get_report_headteacher_signature":{
      const reportId=uuidArg(args,"target_report_id",true);
      return singleResult(sql,ctx,txn=>txn`select public.get_report_headteacher_signature(${reportId}::uuid) result`);
    }
    case "delete_report_card_permanently":{
      const reportId=uuidArg(args,"target_report_id",true);
      const reason=textArg(args,"reason_text",{max:2000});
      return singleResult(sql,ctx,txn=>txn`select public.delete_report_card_permanently(${reportId}::uuid,${reason}) result`);
    }
    case "list_report_pdf_paths":{
      const reportId=uuidArg(args,"target_report_id",true);
      return singleResult(sql,ctx,txn=>txn`select public.list_report_pdf_paths(${reportId}::uuid) result`);
    }
    case "register_report_pdf":{
      const reportId=uuidArg(args,"target_report_id",true);
      const storagePath=textArg(args,"target_storage_path",{required:true,max:700});
      const checksum=textArg(args,"target_checksum",{required:true,max:64});
      if(!/^[0-9a-f]{64}$/i.test(checksum||""))throw Object.assign(new Error("target_checksum must be a SHA-256 digest"),{code:"invalid_rpc_arguments",status:422});
      const pageCount=intArg(args,"target_page_count",{required:false,min:1,max:200})??1;
      return singleResult(sql,ctx,txn=>txn`select public.register_report_pdf(${reportId}::uuid,${storagePath},${checksum},${pageCount}::integer) result`);
    }
    case "list_audit_events":{
      const table=textArg(args,"target_table",{max:128});
      const recordId=uuidArg(args,"target_record_id");
      const page=intArg(args,"page_number",{min:1,max:100000});
      const pageSize=intArg(args,"page_size",{min:1,max:500});
      return singleResult(sql,ctx,txn=>txn`select public.list_audit_events(${table},${recordId}::uuid,${page}::integer,${pageSize}::integer) result`);
    }
    case "list_audit_events_v2":{
      const table=textArg(args,"target_table",{max:128});
      const action=textArg(args,"target_action",{max:64});
      const actorId=uuidArg(args,"target_actor_id");
      const recordId=uuidArg(args,"target_record_id");
      const page=intArg(args,"page_number",{required:false,min:1,max:100000})??1;
      const pageSize=intArg(args,"page_size",{required:false,min:1,max:100})??25;
      return singleResult(sql,ctx,txn=>txn`select public.list_audit_events_v2(${table},${action},${actorId}::uuid,${recordId}::uuid,${page}::integer,${pageSize}::integer) result`);
    }
    case "list_audit_archives_v1":{
      const page=intArg(args,"page_number",{required:false,min:1,max:100000})??1;
      const pageSize=intArg(args,"page_size",{required:false,min:1,max:100})??25;
      return singleResult(sql,ctx,txn=>txn`select public.list_audit_archives_v1(${page}::integer,${pageSize}::integer) result`);
    }
    case "list_audit_archive_entries_v1":{
      const archiveId=uuidArg(args,"target_archive_id",true);
      const page=intArg(args,"page_number",{required:false,min:1,max:100000})??1;
      const pageSize=intArg(args,"page_size",{required:false,min:1,max:100})??25;
      return singleResult(sql,ctx,txn=>txn`select public.list_audit_archive_entries_v1(${archiveId}::uuid,${page}::integer,${pageSize}::integer) result`);
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
    case "search_students_v5":{
      const search=textArg(args,"search_text",{max:200})??"";
      const classId=uuidArg(args,"target_class_id");
      const status=textArg(args,"target_status",{max:32});
      if(status&&!["active","graduated","withdrawn","suspended"].includes(status))throw Object.assign(new Error("target_status is invalid"),{code:"invalid_rpc_arguments",status:422});
      const archive=textArg(args,"archive_filter",{max:16})??"active";
      if(!["active","archived","all"].includes(archive))throw Object.assign(new Error("archive_filter is invalid"),{code:"invalid_rpc_arguments",status:422});
      const page=intArg(args,"page_number",{required:false,min:1,max:100000})??1;
      const requestedPageSize=intArg(args,"page_size",{required:false,min:1,max:500})??20;
      const pageSize=Math.min(100,requestedPageSize);
      return singleResult(sql,ctx,txn=>txn`select public.search_students_v5(${search},${classId}::uuid,${status}::public.student_status,${archive},${page}::integer,${pageSize}::integer) result`);
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
    case "generate_school_identifier":{
      const kind=textArg(args,"identifier_kind",{required:true,max:32});
      return singleResult(sql,ctx,txn=>txn`select public.generate_school_identifier(${kind}) result`);
    }
    case "validate_student_import":{
      const rows=jsonArg(args,"rows");
      const academicYearId=uuidArg(args,"target_academic_year_id",true);
      const classId=uuidArg(args,"target_class_id",true);
      const filename=textArg(args,"filename",{max:255})??"";
      return singleResult(sql,ctx,txn=>txn`select public.validate_student_import(${rows}::jsonb,${academicYearId}::uuid,${classId}::uuid,${filename}) result`);
    }
    case "save_promotion_cutoff":{
      const score=intArg(args,"target_score",{min:40,max:60});
      return singleResult(sql,ctx,txn=>txn`select public.save_promotion_cutoff(${score}::integer) result`);
    }
    case "save_academic_entity":{
      const entityType=textArg(args,"entity_type",{required:true,max:64});
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_academic_entity(${entityType},${payload}::jsonb) result`);
    }
    case "archive_academic_entity":{
      const entityType=textArg(args,"entity_type",{required:true,max:64});
      const targetId=uuidArg(args,"target_id",true);
      const reason=textArg(args,"reason_text",{max:1000});
      return singleResult(sql,ctx,txn=>txn`select public.archive_academic_entity(${entityType},${targetId}::uuid,${reason}) result`);
    }
    case "save_grading_scale":{
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_grading_scale(${payload}::jsonb) result`);
    }
    case "archive_grading_scale":{
      const gradeId=uuidArg(args,"target_grade_id",true);
      const reason=textArg(args,"reason_text",{max:1000});
      return singleResult(sql,ctx,txn=>txn`select public.archive_grading_scale(${gradeId}::uuid,${reason}) result`);
    }
    case "save_assessment_scheme":{
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_assessment_scheme(${payload}::jsonb) result`);
    }
    case "save_class_subject_assignments_batch":{
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_class_subject_assignments_batch(${payload}::jsonb) result`);
    }
    case "list_teachers":{
      const {search,status,archive,page,pageSize}=staffListArgs(args);
      return singleResult(sql,ctx,txn=>txn`select public.list_teachers(${search},${status},${archive},${page}::integer,${pageSize}::integer) result`);
    }
    case "get_teacher_record":{
      const id=uuidArg(args,"target_teacher_id",true);
      return singleResult(sql,ctx,txn=>txn`select public.get_teacher_record(${id}::uuid) result`);
    }
    case "get_my_teacher_profile":
      noArguments(args);
      return singleResult(sql,ctx,txn=>txn`select public.get_my_teacher_profile() result`);
    case "save_teacher":{
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_teacher(${payload}::jsonb) result`);
    }
    case "archive_teacher":{
      const id=uuidArg(args,"target_teacher_id",true);
      const reason=textArg(args,"reason_text",{max:1000});
      return singleResult(sql,ctx,txn=>txn`select public.archive_teacher(${id}::uuid,${reason}) result`);
    }
    case "restore_teacher":{
      const id=uuidArg(args,"target_teacher_id",true);
      const reason=textArg(args,"reason_text",{max:1000});
      return singleResult(sql,ctx,txn=>txn`select public.restore_teacher(${id}::uuid,${reason}) result`);
    }
    case "set_teacher_photo":{
      const id=uuidArg(args,"target_teacher_id",true);
      const photo=pathArg(args,"target_photo_url");
      const expected=timestampArg(args,"expected_updated_at");
      return singleResult(sql,ctx,txn=>txn`select public.set_teacher_photo(${id}::uuid,${photo},${expected}::timestamptz) result`);
    }
    case "list_headteachers":{
      const {search,status,archive,page,pageSize}=staffListArgs(args);
      return singleResult(sql,ctx,txn=>txn`select public.list_headteachers(${search},${status},${archive},${page}::integer,${pageSize}::integer) result`);
    }
    case "get_headteacher_record":{
      const id=uuidArg(args,"target_headteacher_id",true);
      return singleResult(sql,ctx,txn=>txn`select public.get_headteacher_record(${id}::uuid) result`);
    }
    case "get_my_headteacher_signature":
      noArguments(args);
      return singleResult(sql,ctx,txn=>txn`select public.get_my_headteacher_signature() result`);
    case "save_headteacher":{
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_headteacher(${payload}::jsonb) result`);
    }
    case "archive_headteacher":{
      const id=uuidArg(args,"target_headteacher_id",true);
      const reason=textArg(args,"reason_text",{max:1000});
      return singleResult(sql,ctx,txn=>txn`select public.archive_headteacher(${id}::uuid,${reason}) result`);
    }
    case "restore_headteacher":{
      const id=uuidArg(args,"target_headteacher_id",true);
      const reason=textArg(args,"reason_text",{max:1000});
      return singleResult(sql,ctx,txn=>txn`select public.restore_headteacher(${id}::uuid,${reason}) result`);
    }
    case "set_headteacher_photo":{
      const id=uuidArg(args,"target_headteacher_id",true);
      const photo=pathArg(args,"target_photo_url");
      const expected=timestampArg(args,"expected_updated_at");
      return singleResult(sql,ctx,txn=>txn`select public.set_headteacher_photo(${id}::uuid,${photo},${expected}::timestamptz) result`);
    }
    case "set_my_headteacher_signature":{
      const signature=pathArg(args,"target_signature_path");
      const expected=timestampArg(args,"expected_updated_at");
      return singleResult(sql,ctx,txn=>txn`select public.set_my_headteacher_signature(${signature},${expected}::timestamptz) result`);
    }
    case "get_class_timetable_console":{
      const academicYearId=uuidArg(args,"target_academic_year_id",true);
      const classId=uuidArg(args,"target_class_id",true);
      return singleResult(sql,ctx,txn=>txn`select public.get_class_timetable_console(${academicYearId}::uuid,${classId}::uuid) result`);
    }
    case "save_class_timetable_entry":{
      const payload=jsonArg(args,"payload");
      return singleResult(sql,ctx,txn=>txn`select public.save_class_timetable_entry(${payload}::jsonb) result`);
    }
  }
  return invokeRegistryCertifiedRpc(sql,ctx,operation,args);
}
