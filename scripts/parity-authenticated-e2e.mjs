import crypto from "node:crypto";
import { neon } from "@neondatabase/serverless";

const ORIGIN=String(process.env.PARITY_ORIGIN||"").replace(/\/+$/,"");
const BOOTSTRAP_URL=process.env.PARITY_BOOTSTRAP_URL||"";
const TENANT_CODE="RPT-000001";
const TENANT_ID="fff24cf5-ce88-4107-af80-eff8bba44d8c";
const ADMIN_EMAIL="reference@rpt000001.app";
const TURNSTILE_TOKEN="XXXX.DUMMY.TOKEN.XXXX";

if(!/^https:\/\//.test(ORIGIN))throw new Error("PARITY_ORIGIN is required");
if(!BOOTSTRAP_URL)throw new Error("PARITY_BOOTSTRAP_URL is required");
if(!ORIGIN.includes("parity-test"))throw new Error("Authenticated E2E may run only against the isolated parity Worker");

const tenantUrl=new URL(BOOTSTRAP_URL);
tenantUrl.pathname="/edusentia_rpt_000001";
const sql=neon(tenantUrl.toString());

function passwordMaterial(){
  const password="E2E-"+crypto.randomBytes(24).toString("base64url")+"!9aZ";
  const salt=crypto.randomBytes(16);
  const hash=crypto.scryptSync(password,salt,32,{N:2**15,r:8,p:1,maxmem:40*1024*1024});
  return {password,salt:salt.toString("hex"),hash:hash.toString("hex")};
}
function base32Decode(value){
  const alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits="",out=[];
  for(const ch of String(value).replace(/=+$/,"").toUpperCase()){
    const v=alphabet.indexOf(ch);if(v<0)continue;bits+=v.toString(2).padStart(5,"0");
  }
  for(let i=0;i+8<=bits.length;i+=8)out.push(parseInt(bits.slice(i,i+8),2));
  return Buffer.from(out);
}
function totp(secret,at=Date.now()){
  const counter=Math.floor(at/30000);
  const buf=Buffer.alloc(8);buf.writeBigUInt64BE(BigInt(counter));
  const digest=crypto.createHmac("sha1",base32Decode(secret)).update(buf).digest();
  const offset=digest[digest.length-1]&15;
  const code=((digest.readUInt32BE(offset)&0x7fffffff)%1_000_000).toString().padStart(6,"0");
  return code;
}
function cookieValue(setCookie){
  const first=String(setCookie||"").split(/,(?=[^;,]+=)/)[0];
  return first.split(";")[0];
}
async function http(path,{method="GET",body,cookie,headers={}}={}){
  const response=await fetch(ORIGIN+path,{
    method,
    headers:{accept:"application/json",origin:ORIGIN,...(body!=null?{"content-type":"application/json"}:{}),...(cookie?{cookie}:{}),...headers},
    body:body==null?undefined:typeof body==="string"?body:JSON.stringify(body),
    redirect:"manual"
  });
  const type=response.headers.get("content-type")||"";
  const payload=type.includes("application/json")?await response.json().catch(()=>({})):Buffer.from(await response.arrayBuffer());
  if(!response.ok){
    const msg=Buffer.isBuffer(payload)?payload.toString("utf8").slice(0,500):JSON.stringify(payload).slice(0,1000);
    throw new Error(method+" "+path+" failed "+response.status+": "+msg);
  }
  return {response,payload};
}
async function rpc(cookie,operation,args={}){
  const {payload}=await http("/api/compat/rpc/"+encodeURIComponent(operation),{method:"POST",cookie,body:{args}});
  if(!payload?.ok)throw new Error(operation+" did not return ok");
  return payload.result;
}
function assert(condition,message){if(!condition)throw new Error(message);}

const fixtureRows=await sql`
  select r.id report_id,e.id enrollment_id,e.class_id,e.academic_year_id,r.term_id
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.status='published' and r.deleted_at is null
  order by r.published_at desc nulls last,r.updated_at desc
  limit 1`;
const fixture=fixtureRows[0];
assert(fixture?.report_id,"Published report QA fixture is required");

let activeCredential=passwordMaterial();
let cookie="";
try{
  await sql`select authn.platform_reset_mfa_by_email(${TENANT_ID}::uuid,${ADMIN_EMAIL})`;
  await sql`select authn.platform_set_initial_password_by_email(
    ${TENANT_ID}::uuid,${ADMIN_EMAIL},${activeCredential.hash},${activeCredential.salt}
  )`;

  const login=await http("/api/auth/login",{method:"POST",body:{
    tenantCode:TENANT_CODE,email:ADMIN_EMAIL,password:activeCredential.password,turnstileToken:TURNSTILE_TOKEN
  }});
  assert(login.payload?.mfaRequired===true,"System Administrator login must require MFA");
  assert(login.payload?.mode==="enroll","Fresh parity MFA reset must enter enrollment mode");
  assert(login.payload?.setup?.secret,"MFA enrollment secret was not returned");
  assert(login.payload?.challengeToken,"MFA challenge token was not returned");

  const expectedHash=crypto.createHash("sha256").update("edusentia:mfa-challenge:v2:"+String(login.payload.challengeToken)).digest("hex");
  const challengeState=await sql`
    select c.purpose,c.attempts,c.used_at,c.expires_at,now() db_now,
           (c.expires_at>now()) unexpired,
           (c.tenant_id=${TENANT_ID}::uuid) tenant_matches,
           (c.token_hash=${expectedHash}) challenge_hash_matches,
           (u.disabled_at is null) user_enabled,
           exists(select 1 from app.tenants t where t.id=c.tenant_id) tenant_exists,
           m.status membership_status
      from authn.login_challenges c
      join authn.users u on u.id=c.user_id
      left join app.tenant_memberships m on m.user_id=c.user_id and m.tenant_id=c.tenant_id
     where lower(u.email)=lower(${ADMIN_EMAIL})
     order by c.created_at desc
     limit 1`;
  console.error("MFA challenge diagnostic",JSON.stringify(challengeState[0]||{}));

  const complete=await http("/api/auth/mfa/complete",{method:"POST",body:{
    challengeToken:login.payload.challengeToken,
    code:totp(login.payload.setup.secret)
  }});
  cookie=cookieValue(complete.response.headers.get("set-cookie"));
  assert(cookie,"Authenticated session cookie was not issued");
  assert(complete.payload?.session?.assuranceLevel===2,"Authenticated E2E session must be AAL2");

  const session=(await http("/api/session",{cookie})).payload;
  assert(session.authenticated===true&&session.membership?.role==="system_admin","System Administrator session verification failed");

  const health=(await http("/api/health")).payload;
  assert(health.ok&&health.database&&health.storage,"Parity health is not fully ready");

  const bootstrap=(await http("/api/bootstrap",{cookie})).payload;
  assert(bootstrap?.tenant?.code===TENANT_CODE,"Tenant bootstrap returned the wrong school");

  const license=(await http("/api/license/status",{cookie})).payload;
  assert(license?.license,"Tenant license status is unavailable");

  const students=(await http("/api/students?limit=25",{cookie})).payload;
  assert(Array.isArray(students?.rows),"Student API did not return rows");
  const staff=(await http("/api/staff",{cookie})).payload;
  assert(Array.isArray(staff?.rows),"Staff API did not return rows");

  const financeSummary=(await http("/api/finance/summary",{cookie})).payload;
  assert(Number(financeSummary?.outstanding)>=0,"Finance summary is invalid");
  const invoices=(await http("/api/finance/invoices?limit=25",{cookie})).payload;
  const payments=(await http("/api/finance/payments?limit=25",{cookie})).payload;
  assert(Array.isArray(invoices?.rows)&&Array.isArray(payments?.rows),"Finance detail APIs failed");

  const operations=(await http("/api/operations/overview",{cookie})).payload;
  assert(operations?.counts&&Array.isArray(operations?.admissions),"Operations overview failed");

  const academic=await rpc(cookie,"get_academic_configuration",{});
  assert(Array.isArray(academic?.academic_years)&&Array.isArray(academic?.classes),"Academic configuration failed");
  const search=await rpc(cookie,"search_students_v5",{search_text:"",target_status:"active",archive_filter:"active",page_number:1,page_size:50});
  assert(Number(search?.total)>=1,"Certified student search fixture is missing");
  const teachers=await rpc(cookie,"list_teachers",{search_text:"",archive_filter:"active",employment_status:"active",page_number:1,page_size:50});
  const principals=await rpc(cookie,"list_headteachers",{search_text:"",archive_filter:"active",employment_status:"active",page_number:1,page_size:50});
  assert(Number(teachers?.total)>=1&&Number(principals?.total)>=1,"Certified staff workspaces are missing fixture data");

  const timetable=await rpc(cookie,"get_class_timetable_console",{target_academic_year_id:String(fixture.academic_year_id),target_class_id:String(fixture.class_id)});
  assert(timetable&&typeof timetable==="object","Timetable console failed");

  const editor=await rpc(cookie,"get_report_editor",{target_report_id:String(fixture.report_id)});
  assert(editor?.report?.status==="published","Published report editor did not load");
  const revisions=await rpc(cookie,"get_report_revisions",{target_report_id:String(fixture.report_id)});
  assert(Array.isArray(revisions)&&revisions.length>=1,"Report revision history is missing");
  await rpc(cookie,"get_report_headteacher_signature",{target_report_id:String(fixture.report_id)});

  const audit=await rpc(cookie,"list_audit_events_v2",{target_table:"",target_action:"",page_number:1,page_size:25});
  assert(audit&&typeof audit==="object","Audit workspace failed");
  const notifications=await rpc(cookie,"list_notifications",{page_number:1,page_size:30});
  assert(notifications&&typeof notifications==="object","Notification center failed");

  const pdf=Buffer.from("%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n");
  const checksum=crypto.createHash("sha256").update(pdf).digest("hex");
  const oldPublication=await sql`
    select storage_path from public.report_publications
    where report_id=${String(fixture.report_id)}::uuid and revoked_at is null
    order by published_at desc limit 1`;
  const oldPath=String(oldPublication[0]?.storage_path||"");

  const prepared=(await http("/api/reports/"+fixture.report_id+"/pdf/upload-url",{
    method:"POST",cookie,body:{filename:"parity-e2e-report.pdf",contentType:"application/pdf",size:pdf.length}
  })).payload;
  assert(prepared?.objectKey&&prepared?.uploadUrl,"Report PDF upload authorization failed");
  const uploaded=await fetch(ORIGIN+prepared.uploadUrl,{method:"PUT",headers:{cookie,origin:ORIGIN,"content-type":"application/pdf",accept:"application/json"},body:pdf});
  if(!uploaded.ok)throw new Error("Report PDF upload failed "+uploaded.status+": "+(await uploaded.text()).slice(0,500));

  await rpc(cookie,"register_report_pdf",{
    target_report_id:String(fixture.report_id),
    target_storage_path:String(prepared.objectKey),
    target_checksum:checksum,
    target_page_count:1
  });
  const downloaded=await http("/api/reports/"+fixture.report_id+"/pdf/download",{cookie,headers:{accept:"application/pdf"}});
  assert(Buffer.isBuffer(downloaded.payload)&&downloaded.payload.equals(pdf),"R2 official report PDF round-trip mismatch");

  if(oldPath&&oldPath!==prepared.objectKey){
    const cleanup=await fetch(ORIGIN+"/api/reports/"+fixture.report_id+"/pdf/object?key="+encodeURIComponent(oldPath),{
      method:"DELETE",headers:{cookie,origin:ORIGIN,accept:"application/json"}
    });
    if(!cleanup.ok&&cleanup.status!==404)throw new Error("Old report PDF cleanup failed "+cleanup.status);
  }

  console.log(JSON.stringify({
    ok:true,
    tenant:TENANT_CODE,
    assuranceLevel:2,
    modules:["session","bootstrap","students","staff","academics","timetable","reports","audit","notifications","finance","operations","r2-report-pdf"],
    reportStatus:"published",
    r2RoundTrip:true
  }));
}finally{
  try{
    const cleanup=passwordMaterial();
    await sql`select authn.platform_set_initial_password_by_email(
      ${TENANT_ID}::uuid,${ADMIN_EMAIL},${cleanup.hash},${cleanup.salt}
    )`;
    await sql`select authn.platform_reset_mfa_by_email(${TENANT_ID}::uuid,${ADMIN_EMAIL})`;
  }catch(e){
    console.error("QA credential cleanup failed:",e instanceof Error?e.message:String(e));
    process.exitCode=1;
  }
}
