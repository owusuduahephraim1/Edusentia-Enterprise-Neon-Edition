// Public document authentication for already-issued reports, certificates,
// and academic transcripts. Read-only and deliberately no anonymous file access.
import type { Env } from "./types";
import { db } from "./db";
import { tenantDb } from "./tenant-db";
import { json, error } from "./http";

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SCHOOL_CODE=/^[A-Z]{3}-\d{6}$/;
const LEGACY_TENANT_LIMIT=64;
type Kind="report"|"certificate"|"transcript";
type Route={tenant_code:string;school_name:string;database_name:string};
type Verification=Record<string,unknown>;

function field(value:unknown,max=200){return String(value??"").slice(0,max);}
function publicJson(data:unknown){
  const response=json(data);
  response.headers.set("x-robots-tag","noindex, nofollow, noarchive");
  return response;
}
export function documentVerificationRequest(url:URL){
  const keys=["verify","certificate","transcript"] as const;
  const present=keys.filter(k=>url.searchParams.has(k));
  if(present.length!==1)return {error:"Provide exactly one document verification reference."};
  const value=String(url.searchParams.get(present[0])||"").trim();
  if(!UUID.test(value))return {error:"The document verification reference is invalid."};
  const school=String(url.searchParams.get("school")||"").trim().toUpperCase();
  if(school&&!SCHOOL_CODE.test(school))return {error:"The issuing school code is invalid."};
  return {kind:(present[0]==="verify"?"report":present[0]) as Kind,token:value,school};
}

export function publicDocumentFields(kind:Kind,raw:Verification,schoolName:string){
  const found=raw.found===true || (
    kind==="report" && Boolean(raw.report_number)
  ) || (
    kind==="transcript" && Boolean(raw.student_name)
  );
  const valid=found && raw.valid===true;
  const rawStatus=field(raw.status,32).toLowerCase();
  const status=valid
    ? "active"
    : raw.revoked===true || rawStatus==="revoked" || (kind==="report" && rawStatus==="withdrawn")
      ? "revoked"
      : rawStatus==="superseded"?"superseded"
      : found?"not_valid":"not_found";
  // Never return raw DB JSON, full student grade data, stored PDFs,
  // financial holds, academic transcripts, or recipient addresses.
  const base={
    kind,found,valid,status,
    school_name:found?field(raw.school_name||schoolName):""
  };
  if(kind==="report")return {...base,
    document_number:found?field(raw.report_number,120):"",
    recipient_name:found?field(raw.student_name):"",
    recipient_identifier:found?field(raw.admission_no,80):"",
    class_name:found?field(raw.class_name,100):"",
    academic_year:found?field(raw.academic_year,60):"",
    term_name:found?field(raw.term_name,100):"",
    issued_at:found?field(raw.published_at,40):""
  };
  if(kind==="certificate")return {...base,
    document_number:found?field(raw.certificate_number,120):"",
    recipient_name:found?field(raw.recipient_name):"",
    document_title:found?field(raw.certificate_title||raw.certificate_type_label):"",
    class_name:found?field(raw.class_name,100):"",
    academic_year:found?field(raw.academic_year,60):"",
    issued_at:found?field(raw.issue_date,40):"",
    replacement_number:found?field(raw.superseded_by,120):""
  };
  return {...base,
    document_number:found?field(raw.transcript_number,120):"",
    recipient_name:found?field(raw.student_name):"",
    recipient_identifier:found?field(raw.admission_no,80):"",
    purpose:found?field(raw.purpose,200):"",
    issued_at:found?field(raw.issued_at,40):""
  };
}

async function lookup(env:Env,school:Route,token:string,kind:Kind){
  const sql=tenantDb(env,school.database_name);
  const rows=kind==="report"
    ? await sql`select public.verify_report(${token}::uuid) result`
    : kind==="certificate"
      ? await sql`select public.verify_certificate(${token}::uuid) result`
      : await sql`select public.verify_transcript(${token}::uuid) result`;
  return publicDocumentFields(kind,(rows[0] as any)?.result||{},school.school_name);
}

export async function handlePublicDocumentVerification(
  request:Request,env:Env,requestId:string
):Promise<Response|null>{
  const url=new URL(request.url);
  if(url.pathname!=="/api/public/document-verification")return null;
  if(request.method!=="GET")return error("method_not_allowed","Only GET verification requests are supported.",405,requestId);
  const parsed=documentVerificationRequest(url);
  if("error" in parsed)return error("invalid_document_reference",parsed.error!,422,requestId);
  const {kind,token,school}=parsed as {kind:Kind;token:string;school:string};
  const master=db(env);
  const routes=school
    ? await master`select tenant_code,school_name,database_name from platform.tenant_control
        where upper(tenant_code)=${school} and status='active'
          and database_state='isolated_ready' and database_name is not null limit 1` as Route[]
    : await master`select tenant_code,school_name,database_name from platform.tenant_control
        where status='active' and database_state='isolated_ready'
          and database_name is not null order by created_at limit ${LEGACY_TENANT_LIMIT+1}` as Route[];
  let unavailable=false;
  for(let i=0;i<routes.length;i+=4){
    const resolved=await Promise.allSettled(routes.slice(i,i+4).map(route=>lookup(env,route,token,kind)));
    for(const result of resolved){
      if(result.status==="fulfilled" && result.value.found)
        return publicJson({ok:true,verification:result.value});
      if(result.status==="rejected")unavailable=true;
    }
  }
  if(!school && routes.length>LEGACY_TENANT_LIMIT)
    return error("legacy_school_code_required",
      "This older document reference needs its issuing-school verification code. Contact the school.",422,requestId);
  if(unavailable)return error("verification_unavailable",
    "The document verification service is temporarily unavailable. Please retry.",503,requestId);
  return publicJson({ok:true,verification:{kind,found:false,valid:false,status:"not_found"}});
}
