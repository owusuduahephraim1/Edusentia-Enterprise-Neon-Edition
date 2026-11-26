import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import {
  describeMailDns,
  safeDnsQuery,
  checkEndpoint,
  runReadinessCheck,
  endpointSpecs,
  summaryMarkdown
} from "../scripts/check-production-readiness.mjs";

test("marketing, app, verification and privacy endpoints are all monitored without credentials",()=>{
  const ids=endpointSpecs.map(x=>x.id);
  for(const required of ["public_apex","public_www","public_privacy","public_security","school_app","document_verification"])
    assert.ok(ids.includes(required));
  const src=fs.readFileSync("scripts/check-production-readiness.mjs","utf8");
  assert.doesNotMatch(src,/Authorization:\s*Bearer|process\.env\.CLOUDFLARE_API_TOKEN|process\.env\.NEON_DATABASE_URL/);
});
test("business mail records are warnings until mailbox provider and real delivery confirmed",()=>{
  assert.deepEqual(describeMailDns({mx:[],rootTxt:[],dmarcTxt:[]}),{
    mx:"pending",spf:"pending",dmarc:"pending",dkim:"requires selected sender and selector",
    outgoingMail:"not tested",delivery:"not tested"
  });
  const ok=describeMailDns({
    mx:[{exchange:"example.mail.test",priority:10}],
    rootTxt:[["v=spf1 include:example.invalid -all"]],
    dmarcTxt:[["v=DMARC1; p=none"]]
  });
  assert.equal(ok.mx,"configured");
  assert.equal(ok.spf,"configured");
  assert.equal(ok.dmarc,"configured");
  assert.equal(ok.delivery,"not tested");
  assert.equal(describeMailDns({rootTxt:[["v=spf1 -all"],["v=spf1 include:x.invalid ~all"]]}).spf,"conflict");
});
test("missing DNS records fail safely and resolver errors are inconclusive",async()=>{
  assert.deepEqual(await safeDnsQuery(async()=>{const e=new Error("missing");e.code="ENODATA";throw e;},"test"),{ok:true,answers:[]});
  const err=await safeDnsQuery(async()=>{throw new Error("connection");},"test");
  assert.equal(err.ok,false);
  assert.equal(err.error,"DNS resolver temporarily unavailable");
});
test("HTTP checks enforce HTTPS and expected branding",async()=>{
  const spec=endpointSpecs[0];
  const good=await checkEndpoint(spec,{fetcher:async url=>({
    ok:true,url,headers:{get:()=> "text/html; charset=utf-8"},text:async()=>"<title>Edusentia Enterprise</title>"
  })});
  assert.equal(good.status,"passed");
  const spoof=await checkEndpoint(spec,{fetcher:async url=>({
    ok:true,url,headers:{get:()=> "text/html"},text:async()=>"<title>Other product</title>"
  })});
  assert.equal(spoof.status,"failed");
  const insecure=await checkEndpoint(spec,{fetcher:async()=>({
    ok:true,url:"http://edusentia.com/",headers:{get:()=> "text/html"},text:async()=>"<title>Edusentia Enterprise</title>"
  })});
  assert.equal(insecure.status,"failed");
});
test("full summary never equates mail DNS with confirmed delivery or validated backups",async()=>{
  const checker=await runReadinessCheck({
    fetcher:async url=>({
      ok:true,url,headers:{get:()=> "text/html"},
      text:async()=>"<title>Edusentia Enterprise - Security & Trust - Website Privacy Notice - Verify School Document</title>"
    }),
    dns:{
      resolve4:async()=>["104.21.22.101"],
      resolveMx:async()=>[],
      resolveTxt:async()=>[]
    }
  });
  assert.equal(checker.publicStatus,"passed");
  assert.equal(checker.email.mx,"pending");
  assert.match(summaryMarkdown(checker),/does not prove authenticated application workflows/);
  assert.match(summaryMarkdown(checker),/PENDING/);
});
test("unavailable public host marks health red without false email failure",async()=>{
  const report=await runReadinessCheck({
    fetcher:async url=>({
      ok:!url.includes("verify.edusentia.com"),status:503,url,
      headers:{get:()=> "text/html"},
      text:async()=>"<title>Edusentia Enterprise - Security & Trust - Website Privacy Notice</title>"
    }),
    dns:{
      resolve4:async()=>["172.67.204.45"],
      resolveMx:async()=>[],
      resolveTxt:async()=>[]
    }
  });
  assert.equal(report.publicStatus,"failed");
  assert.equal(report.endpoints.find(x=>x.id==="document_verification").status,"failed");
});
test("backup audit is select-only and never prints connection secrets or student data",()=>{
  const sh=fs.readFileSync("scripts/check-backup-freshness.sh","utf8");
  assert.match(sh,/platform\.tenant_control/);
  assert.match(sh,/public\.backup_exports/);
  assert.match(sh,/verification_status='verified'/);
  assert.match(sh,/::add-mask::/);
  assert.doesNotMatch(sh,/\b(?:delete|truncate|insert|update|alter|drop)\s+(?:table|from|into|public\.)/i);
  assert.doesNotMatch(sh,/student_name|student_id|email_address|source_path|backup_path/);
});
test("scheduled readiness checks cannot access or alter production deploy secrets",()=>{
  const yaml=fs.readFileSync(".github/workflows/production-readiness-health.yml","utf8");
  assert.match(yaml,/cron: "17 7 \* \* \*"/);
  assert.match(yaml,/workflow_dispatch:/);
  assert.match(yaml,/permissions:\s*\n\s+contents: read/);
  assert.match(yaml,/node scripts\/check-production-readiness\.mjs/);
  assert.match(yaml,/bash scripts\/check-backup-freshness\.sh/);
  assert.doesNotMatch(yaml,/wrangler\s+deploy|cloudflare\/.*\/dns_records|on:\s*delete/);
});
