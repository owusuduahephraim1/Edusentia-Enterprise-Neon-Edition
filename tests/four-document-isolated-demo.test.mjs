import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

// Integration demo: genuine Edusentia verification-page code + mocked HTTP responses.
// No requests, students, or certificates are created in the production tenant.
const verifyPage=fs.readFileSync("frontend/verify-card.js","utf8");
const certificateUi=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const certificateSql=fs.readFileSync("database/reference-compat/0046_certified_reference_rpc_bulk.sql","utf8");
const reportSql=fs.readFileSync("database/reference-compat/0044_certified_report_workflow_privacy_integrity.sql","utf8");
const reportPdfSql=fs.readFileSync("database/reference-compat/0045_certified_report_pdf_integrity_r2.sql","utf8");
const publicHandler=fs.readFileSync("worker/src/public-document-verification.ts","utf8");
const registry=fs.readFileSync("worker/src/certified-rpc-registry.ts","utf8");

const fixtures=[
  {name:"student promotion certificate",key:"certificate",token:"0146d531-eab1-4c37-b2e7-9b5a2b380001",
   response:{kind:"certificate",found:true,valid:true,status:"active",school_name:"Edusentia QA Demo School",document_number:"QA/PROM/2026/001",recipient_name:"Demo Promotion Student",document_title:"Certificate of Promotion",academic_year:"2026/2027",issued_at:"2026-11-26"}},
  {name:"JHS completion certificate",key:"certificate",token:"0146d531-eab1-4c37-b2e7-9b5a2b380002",
   response:{kind:"certificate",found:true,valid:true,status:"active",school_name:"Edusentia QA Demo School",document_number:"QA/JHS/2026/001",recipient_name:"Demo JHS Graduate",document_title:"Certificate of Completion",academic_year:"2026/2027",issued_at:"2026-11-26"}},
  {name:"published report card",key:"verify",token:"0146d531-eab1-4c37-b2e7-9b5a2b380003",
   response:{kind:"report",found:true,valid:true,status:"active",school_name:"Edusentia QA Demo School",document_number:"QA/REPORT/001",recipient_name:"Demo Report Student",recipient_identifier:"QA-STU-001",class_name:"Basic 6",academic_year:"2026/2027",term_name:"Term 3",issued_at:"2026-11-26"}},
  {name:"issued academic transcript",key:"transcript",token:"0146d531-eab1-4c37-b2e7-9b5a2b380004",
   response:{kind:"transcript",found:true,valid:true,status:"active",school_name:"Edusentia QA Demo School",document_number:"QA/TRANSCRIPT/001",recipient_name:"Demo Graduate",recipient_identifier:"QA-STU-002",purpose:"Academic transcript",issued_at:"2026-11-26"}}
];
function mockBrowser(fixture,response=fixture.response){
  const names=["verificationFields","verificationDetails","verificationState","verificationIcon","verificationLabel","verificationDetail","verificationRetry","verificationSchool","verifyTitle"];
  const nodes=Object.fromEntries(names.map(id=>[id,{hidden:true,className:"",textContent:"",children:[],handlers:{},
    replaceChildren(){this.children=[];},appendChild(node){this.children.push(node);},
    addEventListener(name,fn){this.handlers[name]=fn;}}]));
  const calls=[];
  const document={
    title:"Edusentia public verification",
    getElementById:id=>nodes[id],
    createElement:tag=>({tag,textContent:"",children:[],append(...items){this.children.push(...items);}})
  };
  const host={
    document,location:{search:"?"+fixture.key+"="+fixture.token+"&school=QAD-900001"},
    window:{EDS_MASTER_CONFIG:{apiBaseUrl:"https://qa.invalid.example"}},
    URL,URLSearchParams,AbortController,Date,Intl,console,
    fetch:async (url,options)=>{calls.push({url,options});return{ok:true,json:async()=>({ok:true,verification:response})};},
    setTimeout:()=>1,clearTimeout:()=>{}
  };
  vm.runInNewContext(verifyPage,host);
  return {nodes,calls};
}
async function settle(){await new Promise(resolve=>setImmediate(resolve));}
function functionBody(src,name,next){
  const start=src.indexOf("-- "+name+"(");
  const end=next?src.indexOf("-- "+next+"(",start+3):-1;
  assert.ok(start>=0,name+" must exist in certified SQL");
  return src.slice(start,end>start?end:undefined);
}

for(const fixture of fixtures){
  test("isolated demo: "+fixture.name+" authentic public verification",async()=>{
    const app=mockBrowser(fixture);
    await settle();
    assert.equal(app.nodes.verificationState.className,"state state-valid");
    assert.match(app.nodes.verificationLabel.textContent,/Authentic (certificate|report card|academic transcript)/);
    assert.equal(app.nodes.verificationSchool.textContent,"Edusentia QA Demo School");
    assert.equal(app.nodes.verificationDetails.hidden,false);
    assert.equal(app.calls.length,1);
    const url=new URL(app.calls[0].url);
    assert.equal(url.pathname,"/api/public/document-verification");
    assert.equal(url.searchParams.get(fixture.key),fixture.token);
    assert.equal(url.searchParams.get("school"),"QAD-900001");
    assert.equal(app.calls[0].options.credentials,"omit");
    assert.equal(app.calls[0].options.cache,"no-store");
    const details=app.nodes.verificationFields.children.map(node=>node.children.map(v=>v.textContent).join(":"));
    assert.ok(details.some(v=>v.includes(fixture.response.document_number)),fixture.name+" must display its number");
    assert.ok(details.some(v=>v.includes(fixture.response.recipient_name)),fixture.name+" must display its recipient");
  });
  test("isolated demo: "+fixture.name+" revoked and superseded states fail closed",async()=>{
    for(const status of ["revoked","superseded"]){
      const app=mockBrowser(fixture,{...fixture.response,valid:false,status});
      await settle();
      assert.notEqual(app.nodes.verificationState.className,"state state-valid");
      assert.match(app.nodes.verificationLabel.textContent,/revoked|withdrawn|superseded/i);
    }
  });
}
test("student promotion eligibility requires published Term 3 result and destination class",()=>{
  const src=functionBody(certificateSql,"create_certificate_batch","create_certificate_replacement_draft");
  assert.match(src,/v_certificate_type='student_promotion'/);
  assert.match(src,/tr\.sequence=3/);
  assert.match(src,/r\.status='published'/);
  assert.match(src,/r\.promoted_to_class_id/);
  assert.match(src,/r\.term_id=v_term_id/);
  assert.match(src,/r\.id as report_id/);
});
test("JHS completion eligibility requires a configured JHS 3 class and published result",()=>{
  const src=functionBody(certificateSql,"create_certificate_batch","create_certificate_replacement_draft");
  assert.match(src,/v_certificate_type='jhs_completion'/);
  assert.match(src,/certificate_completion_class_id/);
  assert.match(src,/r\.status='published'/);
  assert.match(src,/sr\.id is not null/);
});
test("promotion and JHS certificate issuance retain Principal approval and frozen snapshots",()=>{
  const issue=functionBody(certificateSql,"issue_certificate_batch","issue_staff_id_cards");
  const review=functionBody(certificateSql,"review_certificate_batch");
  assert.match(issue,/batch_row\.status<>'approved'/);
  assert.match(issue,/status='issued'/);
  assert.match(issue,/signature_path/);
  assert.match(issue,/verification_token/);
  assert.match(review,/decision/);
  assert.match(certificateUi,/id="certificateDownloadSingle"/);
  assert.match(certificateUi,/officialDocumentVerificationUrl\(certificate\.verification_token,"certificate",school\)/);
});
test("published report card has a guarded PDF registration and public verification route",()=>{
  assert.match(reportSql,/CREATE OR REPLACE FUNCTION public\.transition_report_status/i);
  assert.match(reportSql,/published/i);
  assert.match(reportPdfSql,/create or replace function public\.register_report_pdf/i);
  assert.match(reportPdfSql,/can_manage_report_pdf/);
  assert.match(publicHandler,/public\.verify_report/);
  assert.doesNotMatch(publicHandler,/select\\s+\\*\\s+from\\s+public\\.(student_reports|certificates)/i);
});
test("academic transcript issuance is separate from the local preview and verifies publicly",()=>{
  assert.match(certificateUi,/certified\("issue_student_transcript",\{target_student_id:selected,purpose_text:/);
  assert.match(registry,/"issue_student_transcript":/);
  assert.match(publicHandler,/public\.verify_transcript/);
  assert.match(certificateUi,/ACADEMIC TRANSCRIPT PREVIEW/);
  assert.match(certificateUi,/Download transcript preview/);
  assert.match(certificateUi,/copyOfficialVerificationLink\(button\.dataset\.transcriptVerificationLink,"transcript"\)/);
});
test("public endpoint does not disclose grades, stored PDFs or raw snapshots",()=>{
  assert.match(publicHandler,/x-robots-tag/);
  assert.match(publicHandler,/noindex, nofollow, noarchive/);
  assert.doesNotMatch(publicHandler,/select\s+\*\s+from\s+public\.student_reports/);
  assert.match(publicHandler,/Never return raw DB JSON, full student grade data, stored PDFs/);
});
test("malformed synthetic document tokens never reach the verification service",async()=>{
  const x={...fixtures[0],token:"not-a-valid-uuid"};
  const app=mockBrowser(x);await settle();
  assert.equal(app.calls.length,0);
  assert.equal(app.nodes.verificationLabel.textContent,"Invalid verification link");
});
test.todo("Live isolated tenant: seed published reports; issue promotion/JHS; approve, sign, download PDFs, scan real QR");
test.todo("Live isolated tenant: publish report card, register official PDF in R2, verify current and withdrawn states");
test.todo("Official transcript PDF with printed QR and issuer signature (currently only local preview export exists)");
