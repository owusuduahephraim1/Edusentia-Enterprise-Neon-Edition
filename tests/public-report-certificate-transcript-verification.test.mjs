import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const src=fs.readFileSync("frontend/verify-card.js","utf8");
const index=fs.readFileSync("frontend/index.html","utf8");
const routes=fs.readFileSync("worker/src/routes.ts","utf8");
const doc=fs.readFileSync("worker/src/public-document-verification.ts","utf8");
const page=fs.readFileSync("frontend/verify-card.html","utf8");
const token="6c622ff5-82a8-4db8-8c78-d441522a16f3";

function pageRun(search,documentValue){
  const ids=["verificationFields","verificationDetails","verificationState","verificationIcon","verificationLabel",
    "verificationDetail","verificationRetry","verificationSchool","verifyTitle"];
  const nodes=Object.fromEntries(ids.map(id=>[id,{hidden:true,className:"",textContent:"",listeners:{},
    children:[],replaceChildren(){this.children=[];},appendChild(v){this.children.push(v);},
    addEventListener(name,fn){this.listeners[name]=fn;}}]));
  const pending=[];
  const host={
    document:{title:"Verify ID Card | Edusentia Enterprise",getElementById:id=>nodes[id],
      createElement:tag=>({tag,textContent:"",children:[],append(...items){this.children.push(...items)}})},
    location:{search},window:{EDS_MASTER_CONFIG:{apiBaseUrl:"https://edusentia-enterprise-neon-api.edusentia-enterprise-neon.workers.dev"}},
    fetch:async (href,opts)=>{
      pending.push({href,opts});
      return {ok:true,json:async()=>({ok:true,verification:documentValue})};
    },
    URL,URLSearchParams,AbortController,Date,Intl,console,
    setTimeout:()=>1,clearTimeout:()=>{}
  };
  vm.runInNewContext(src,host);
  return {nodes,pending,host};
}

test("all five document card types have public pre-login QR handlers",()=>{
  for(const key of ["staffcard","idcard","verify","certificate","transcript"])
    assert.ok(index.includes('q.has("'+key+'")'),key+" must route publicly");
  assert.ok(index.indexOf('location.replace("./verify-card.html"')<index.indexOf('<script src="app.js?v=20261126-history-nav2">'));
  assert.match(page,/id="verificationState"/);
  assert.doesNotMatch(page,/id="loginForm"/);
  assert.match(routes,/handlePublicDocumentVerification\(request,env,requestId\)/);
  assert.ok(routes.indexOf("handlePublicDocumentVerification(request,env,requestId)")<
    routes.indexOf("const ctx=await authed(request,env)"));
});

test("public document endpoint permits only verified token-bound certified reads",()=>{
  for(const functionName of ["verify_report","verify_certificate","verify_transcript"])
    assert.ok(doc.includes("public."+functionName),functionName);
  assert.match(doc,/\/api\/public\/document-verification/);
  assert.match(doc,/noindex, nofollow, noarchive/);
  assert.match(doc,/tenantDb\(env,school\.database_name\)/);
  assert.match(doc,/LEGACY_TENANT_LIMIT=64/);
  assert.doesNotMatch(doc,/\bselect\s+\*\s+from\s+public\.(student_reports|certificates|transcripts|report_publications)/i);
  assert.doesNotMatch(doc,/pdf_storage_path|storage_path|raw_snapshot|subject_results|finance_student_hold_status/);
});

test("QR report verification opens public page, never login, and renders live result",async()=>{
  const x=pageRun("?verify="+token+"&school=NIS-000001",{
    kind:"report",found:true,valid:true,status:"active",
    school_name:"Nipe International School",
    document_number:"NIS-REPORT-2026-001",recipient_name:"Student Sample",
    recipient_identifier:"NIS000001-STU-BS003",academic_year:"2026/2027",term_name:"Term 1"
  });
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(x.nodes.verificationLabel.textContent,"Authentic report card");
  assert.equal(x.nodes.verificationDetails.hidden,false);
  assert.equal(x.nodes.verificationSchool.textContent,"Nipe International School");
  assert.equal(x.pending.length,1);
  assert.equal(new URL(x.pending[0].href).pathname,"/api/public/document-verification");
  assert.equal(new URL(x.pending[0].href).searchParams.get("school"),"NIS-000001");
  assert.equal(x.pending[0].opts.credentials,"omit");
  assert.equal(x.pending[0].opts.cache,"no-store");
});

test("revoked and superseded documents never render green valid status",async()=>{
  for(const [key,status] of [["verify","revoked"],["certificate","revoked"],["certificate","superseded"],["transcript","revoked"],["transcript","superseded"]]){
    const x=pageRun("?"+key+"="+token,{found:true,valid:false,status,kind:key});
    await new Promise(resolve=>setImmediate(resolve));
    assert.notEqual(x.nodes.verificationState.className,"state state-valid");
  }
});

test("malformed public document reference never reaches backend",async()=>{
  const x=pageRun("?verify=not-a-uuid",{});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(x.pending.length,0);
  assert.equal(x.nodes.verificationLabel.textContent,"Invalid verification link");
});
