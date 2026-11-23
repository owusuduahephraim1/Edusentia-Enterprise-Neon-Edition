import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const src=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const shell=fs.readFileSync("frontend/index.html","utf8");
const page=fs.readFileSync("frontend/verify-card.html","utf8");
const script=fs.readFileSync("frontend/verify-card.js","utf8");
const sw=fs.readFileSync("frontend/service-worker.js","utf8");
const api=fs.readFileSync("worker/src/public-id-verification.ts","utf8");
const router=fs.readFileSync("worker/src/routes.ts","utf8");

test("old staff and student QR links redirect to public verification before auth initializes",()=>{
  assert.match(shell,/<script>[\s\S]*?q\.has\("staffcard"\)\|\|q\.has\("idcard"\)/);
  assert.match(shell,/location\.replace\("\.\/verify-card\.html"\+location\.search\)/);
  assert.ok(shell.indexOf('location.replace("./verify-card.html"')<shell.indexOf('<script src="app.js">'));
  assert.doesNotMatch(page,/id="loginForm"/);
  assert.match(page,/id="verificationState"/);
  assert.match(page,/id="verificationRetry"/);
});

test("new ID QR links route to official public page with tenant code",()=>{
  const beginning=src.indexOf("function edusentiaVerificationBaseUrl(){");
  const ending=src.indexOf("  async function idCardBlobImage(",beginning);
  assert.ok(beginning>=0&&ending>beginning);
  const code=src.slice(beginning,ending);
  const context={
    window:{EDS_MASTER_CONFIG:{repositoryBasePath:"/Edusentia-Enterprise-Neon-Edition/"},
      EdusentiaShell:{state:{boot:{tenant:{code:"NIS-000001"}}}}},
    location:{origin:"https://owusuduahephraim1.github.io"},
    URL, String
  };
  const output=vm.runInNewContext(code+
    '\n[ idCardVerificationUrl("6c622ff5-82a8-4db8-8c78-d441522a16f3","staff"), idCardVerificationUrl("6c622ff5-82a8-4db8-8c78-d441522a16f3","student") ]',
    context);
  for(const href of output) {
    const url=new URL(href);
    assert.equal(url.origin,"https://owusuduahephraim1.github.io");
    assert.equal(url.pathname,"/Edusentia-Enterprise-Neon-Edition/verify-card.html");
    assert.equal(url.searchParams.get("school"),"NIS-000001");
  }
  assert.equal(new URL(output[0]).searchParams.get("staffcard"),"6c622ff5-82a8-4db8-8c78-d441522a16f3");
  assert.equal(new URL(output[1]).searchParams.get("idcard"),"6c622ff5-82a8-4db8-8c78-d441522a16f3");
});

function verificationDOM(search, payload, responseOk=true){
  const nodes={};
  const fields=[];
  for(const id of ["verificationFields","verificationDetails","verificationState","verificationIcon",
      "verificationLabel","verificationDetail","verificationRetry","verificationSchool"]){
    nodes[id]={hidden:false,textContent:"",className:"",listeners:{},
      replaceChildren(){fields.length=0},
      appendChild(node){fields.push(node)},
      addEventListener(name,callback){this.listeners[name]=callback}};
  }
  const pending=[];
  const host="https://edusentia-enterprise-neon-api.edusentia-enterprise-neon.workers.dev";
  const ctx={
    document:{getElementById:id=>nodes[id],createElement:tag=>({
      tagName:tag,textContent:"",children:[],append(...children){this.children.push(...children)}
    })},
    location:{search},window:{EDS_MASTER_CONFIG:{apiBaseUrl:host}},
    fetch:async (href,opts)=>{pending.push({href,opts});return {ok:responseOk,json:async()=>payload}},
    URL,URLSearchParams,AbortController,Date,Intl,
    setTimeout:()=>1,clearTimeout:()=>{},
    console
  };
  vm.runInNewContext(script,ctx);
  return {nodes,fields,pending};
}

test("public valid staff ID displays its school and status without signing in",async()=>{
  const x=verificationDOM("?staffcard=6c622ff5-82a8-4db8-8c78-d441522a16f3&school=NIS-000001",{
    ok:true,verification:{found:true,valid:true,status:"active",kind:"staff",
      card_number:"SCH-STAFF-20262027-000002",name:"Test Staff",
      identifier:"NIS000001-STF-000005",school_name:"Nipe International School",role:"Teacher"}
  });
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(x.nodes.verificationLabel.textContent,"Valid staff ID card");
  assert.equal(x.nodes.verificationSchool.textContent,"Nipe International School");
  assert.equal(x.nodes.verificationDetails.hidden,false);
  assert.equal(x.pending.length,1);
  const url=new URL(x.pending[0].href);
  assert.equal(url.pathname,"/api/public/id-card-verification");
  assert.equal(url.searchParams.get("school"),"NIS-000001");
  assert.equal(x.pending[0].opts.credentials,"omit");
  assert.equal(x.pending[0].opts.cache,"no-store");
});

test("expired or revoked card cannot be described as valid",async()=>{
  for(const state of ["expired","revoked","replaced","permanently_removed"]){
    const x=verificationDOM("?idcard=6c622ff5-82a8-4db8-8c78-d441522a16f3",{
      verification:{found:true,valid:false,status:state,kind:"student",school_name:"School"}
    });
    await new Promise(resolve=>setImmediate(resolve));
    assert.notEqual(x.nodes.verificationLabel.textContent,"Valid student ID card");
  }
});

test("malformed tokens fail locally without API calls or exposing private information",async()=>{
  const x=verificationDOM("?staffcard=not-a-uuid",{});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(x.nodes.verificationLabel.textContent,"Invalid verification link");
  assert.equal(x.pending.length,0);
  assert.doesNotMatch(script,/session\(|login\(|certifiedRpc\(/);
});

test("public verification endpoint uses original isolated-Neon certified status functions",()=>{
  assert.match(router,/handlePublicIdCardVerification\(request,env,requestId\)/);
  assert.ok(router.indexOf("handlePublicIdCardVerification(request,env,requestId)")<
    router.indexOf("const ctx=await authed(request,env)"));
  assert.match(api,/public\.verify_staff_id_card/);
  assert.match(api,/public\.verify_student_id_card/);
  assert.match(api,/id_card_verification|id-card-verification/);
  assert.match(api,/LEGACY_TENANT_LIMIT=64/);
  assert.match(api,/tenantDb\(env,route\.database_name\)/);
  assert.match(api,/noindex, nofollow, noarchive/);
  assert.doesNotMatch(api,/\bselect\s+\*\s+from\s+public\.(student|staff)_id_cards/i);
  assert.match(sw,/\.\/verify-card\.html/);
  assert.match(sw,/\.\/verify-card\.js/);
  assert.match(src,/settings\.verification_base_url\|\|edusentiaVerificationBaseUrl\(\)/);
});
