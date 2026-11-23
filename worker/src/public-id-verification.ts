// Public read-only staff/student ID verification; no tenant session is required.
// Token-bound lookups use existing certified Neon security-definer functions.
// Never return the stored snapshot or protected documents to public callers.
import type { Env } from "./types";
import { db } from "./db";
import { tenantDb } from "./tenant-db";
import { json, error } from "./http";

const UUID_V4=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SCHOOL_CODE=/^[A-Z]{3}-\d{6}$/;
const LEGACY_TENANT_LIMIT=64;
const BATCH_SIZE=4;

type RouteRow={tenant_code:string;school_name:string;database_name:string};
type CardLookup={found?:boolean;valid?:boolean;status?:string;
  card_number?:string;staff_name?:string;student_name?:string;staff_no?:string;
  admission_no?:string;staff_role?:string;class_name?:string;academic_year?:string;
  school_name?:string;issue_date?:string;expires_on?:string;revision?:number;
  replacement_card_number?:string};
const STATUSES=new Set(["active","expired","revoked","replaced","permanently_removed"]);

function publicReply(value:unknown,status=200){
  const response=json(value,status);
  response.headers.set("x-robots-tag","noindex, nofollow, noarchive");
  return response;
}

export function parseCardVerification(url:URL){
  const staff=url.searchParams.get("staffcard");
  const student=url.searchParams.get("idcard");
  if((staff && student) || (!staff && !student))
    return {error:"Provide exactly one staffcard or idcard token."};
  const token=String(staff||student||"").trim();
  if(!UUID_V4.test(token))
    return {error:"The QR verification reference is invalid."};
  const school=String(url.searchParams.get("school")||"").trim().toUpperCase();
  if(school && !SCHOOL_CODE.test(school))
    return {error:"The school verification code is invalid."};
  return {mode:staff?"staff":"student",token,school};
}

function sanitise(row:CardLookup,mode:"staff"|"student",fallbackSchool:string){
  const status=String(row.status||"").toLowerCase();
  const state=STATUSES.has(status)?status:"not_found";
  const found=row.found===true;
  return {
    found,
    valid:found&&row.valid===true&&state==="active",
    status:found?state:"not_found",
    kind:mode,
    school_name:found?String(row.school_name||fallbackSchool||""):"",
    card_number:found?String(row.card_number||""):"",
    name:found?String(mode==="staff"?row.staff_name||"":row.student_name||""):"",
    identifier:found?String(mode==="staff"?row.staff_no||"":row.admission_no||""):"",
    role:found&&mode==="staff"?String(row.staff_role||""):"",
    class_name:found&&mode==="student"?String(row.class_name||""):"",
    academic_year:found?String(row.academic_year||""):"",
    issue_date:found?String(row.issue_date||""):"",
    expires_on:found?String(row.expires_on||""):"",
    revision:found?Math.max(1,Math.min(10000,Number(row.revision||1))):null,
    replacement_card_number:found?String(row.replacement_card_number||""):""
  };
}

async function lookupInTenant(env:Env,route:RouteRow,token:string,mode:"staff"|"student"){
  const sql=tenantDb(env,route.database_name);
  const rows=mode==="staff"
    ? await sql`select public.verify_staff_id_card(${token}::uuid) result`
    : await sql`select public.verify_student_id_card(${token}::uuid) result`;
  return sanitise(((rows[0] as any)?.result||{}) as CardLookup,mode,route.school_name);
}

export async function handlePublicIdCardVerification(
  request:Request,env:Env,requestId:string
):Promise<Response|null>{
  const url=new URL(request.url);
  if(url.pathname!=="/api/public/id-card-verification")return null;
  if(request.method!=="GET")return error("method_not_allowed","Only GET verification requests are supported.",405,requestId);
  const parsed=parseCardVerification(url);
  if("error" in parsed)return error("invalid_id_card_reference",parsed.error!,422,requestId);
  const {mode,token,school}=parsed as {mode:"staff"|"student";token:string;school:string};
  const master=db(env);
  let routes:RouteRow[];
  if(school){
    routes=await master`
      select tenant_code,school_name,database_name
      from platform.tenant_control
      where upper(tenant_code)=${school} and status='active'
        and database_state='isolated_ready' and database_name is not null limit 1
    ` as RouteRow[];
  }else{
    // Old printed QR codes contain only a random UUID. Scan a bounded
    // number of isolated school databases; new cards include school=...
    // and require just one tenant lookup.
    routes=await master`
      select tenant_code,school_name,database_name
      from platform.tenant_control
      where status='active' and database_state='isolated_ready'
        and database_name is not null
      order by created_at limit ${LEGACY_TENANT_LIMIT+1}
    ` as RouteRow[];
  }
  let unavailable=false;
  for(let offset=0;offset<routes.length;offset+=BATCH_SIZE){
    const batch=routes.slice(offset,offset+BATCH_SIZE);
    const results=await Promise.allSettled(batch.map(tenant=>lookupInTenant(env,tenant,token,mode)));
    for(const result of results){
      if(result.status==="fulfilled"&&result.value.found)
        return publicReply({ok:true,verification:result.value});
      if(result.status==="rejected")unavailable=true;
    }
  }
  if(!school && routes.length>LEGACY_TENANT_LIMIT)
    return error("legacy_qr_school_code_required",
      "This legacy QR needs a school-specific verification link. Ask the issuing school for a newly generated card.",422,requestId);
  if(unavailable)
    return error("verification_unavailable",
      "ID verification is temporarily unavailable. Please try again.",503,requestId);
  return publicReply({ok:true,verification:{
    found:false,valid:false,status:"not_found",kind:mode
  }});
}
