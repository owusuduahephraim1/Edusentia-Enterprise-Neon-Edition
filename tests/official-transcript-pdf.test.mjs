import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source=fs.readFileSync("frontend/official-transcript-pdf.js","utf8");
const workspace=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const index=fs.readFileSync("frontend/index.html","utf8");
const sql=fs.readFileSync("database/reference-compat/0045d_certified_rpc_helper_closure.sql","utf8");
const provider=fs.readFileSync("database/reference-compat/0048_certified_provider_rpc_neon_r2.sql","utf8");
const immutable={
  status:"valid",
  transcript_number:"QAD-TR-2026-000001",
  verification_token:"0146d531-eab1-4c37-b2e7-9b5a2b380004",
  issued_at:"2026-11-26T12:00:00Z",
  purpose:"Academic transcript",
  snapshot:{
    schema_version:"professional-transcript-v1",
    source_policy:"latest_currently_valid_published_report_per_term",
    student:{id:"synthetic-student",full_name:"Frozen Student A",admission_no:"QAD-STU-001"},
    school:{school_name:"EDUSENTIA QA SCHOOL",tenant_code:"QAD-900001",address:"Test Campus, Ghana"},
    principal:{full_name:"Frozen Principal",signature_path:"tenants/synthetic/principal-signatures/frozen.png"},
    academic_records:[{
      academic_year_name:"2026/2027",term_name:"Term 1",class_name:"JHS 1",
      average:82.5,days_school_opened:65,days_present:64,report_number:"QAD-REPORT-001",
      subjects:[
        {subject_name:"Mathematics",total_score:85,grade:"A",remark:"Excellent"},
        {subject_name:"Integrated Science",total_score:80,grade:"B",remark:"Very good"}
      ]
    }],
    summary:{academic_period_count:1,subject_result_count:2,cumulative_average:82.5,latest_class:"JHS 1"},
    lifecycle:[]
  }
};
function harness(){
  const log=[],pages=[],seen={signaturePaths:[],urls:[],signatureDraws:0};
  const document={
    createElement(type){
      assert.equal(type,"canvas");
      const ctx={
        fillStyle:"",strokeStyle:"",font:"",lineWidth:1,textAlign:"left",
        fillRect(){},strokeRect(){},beginPath(){},moveTo(){},lineTo(){},stroke(){},
        drawImage(){},fillText(text){log.push(String(text));},
        measureText(value){return {width:String(value).length*9};}
      };
      const canvas={width:0,height:0,getContext:()=>ctx};
      pages.push(canvas);
      return canvas;
    }
  };
  const window={};
  vm.runInNewContext(source,{document,window,console});
  const deps={
    readPrivateImage:async path=>{seen.signaturePaths.push(path);return {width:150,height:65};},
    verificationUrl:(token,kind,school)=>{
      seen.urls.push({token,kind,school});
      return "https://verify.edusentia.com/?transcript="+token+"&school="+school.tenant_code;
    },
    qrCanvas:async()=>({width:152,height:152}),
    loadSchoolLogo:async()=>({width:200,height:200}),
    safeColour:(value,fallback)=>value||fallback,
    drawImageContain:()=>{},
    drawSignature:()=>{seen.signatureDraws++;},
    canvasBlob:async() =>new Blob(["JPEG"],{type:"image/jpeg"}),
    imagesPdf:async (blobs,w,h,iW,iH)=>({pages:blobs.length,w,h,iW,iH}),
    releaseCanvas:()=>{}
  };
  return {render:window.EdusentiaOfficialTranscriptPdf.render,deps,log,pages,seen};
}
const fixture=()=>structuredClone(immutable);

test("a current issued transcript renders official portrait A4 pages with academic facts and verification QR",async()=>{
  const x=harness(),pdf=await x.render(fixture(),x.deps);
  assert.equal(pdf.pages,1);
  assert.equal(pdf.w,595.28);
  assert.equal(pdf.h,841.89);
  assert.equal(pdf.iW,1240);
  assert.equal(pdf.iH,1754);
  for(const value of ["OFFICIAL ACADEMIC TRANSCRIPT","Frozen Student A","QAD-TR-2026-000001","Mathematics","Integrated Science","85.0","82.5%","Frozen Principal"])
    assert.ok(x.log.some(t=>t.includes(value)),"Missing "+value);
  assert.equal(x.seen.signatureDraws,1);
  assert.deepEqual(x.seen.signaturePaths,["tenants/synthetic/principal-signatures/frozen.png"]);
  assert.equal(x.seen.urls[0].kind,"transcript");
  assert.equal(x.seen.urls[0].token,immutable.verification_token);
  assert.equal(x.seen.urls[0].school.tenant_code,"QAD-900001");
});

test("frozen issued snapshot, not mutable live academic records, is used",async()=>{
  const x=harness(),issued=fixture();
  issued.snapshot.academic_records[0].subjects[0].total_score=73;
  await x.render(issued,x.deps);
  assert.ok(x.log.includes("73.0"));
  assert.ok(!x.log.includes("85.0"));
});

test("long transcripts paginate and repeat subject table headings without dropping records",async()=>{
  const x=harness(),issued=fixture();
  issued.snapshot.academic_records[0].subjects=Array.from({length:83},(_,i)=>({
    subject_name:"Published subject "+(i+1),total_score:72+i%10,grade:"B",remark:"Satisfactory performance"
  }));
  const pdf=await x.render(issued,x.deps);
  assert.ok(pdf.pages>=4);
  assert.equal(x.log.filter(t=>t==="Published subject 83").length,1);
  assert.ok(x.log.filter(t=>t==="SUBJECT").length>=4);
  assert.equal(x.seen.signatureDraws,1);
  assert.ok(x.log.some(t=>t==="Page "+pdf.pages+" of "+pdf.pages));
});

test("revoked and superseded issuances cannot generate official PDFs",async()=>{
  for(const status of ["revoked","superseded"]){
    const x=harness(),issued=fixture();issued.status=status;
    await assert.rejects(x.render(issued,x.deps),/Only the current valid issued transcript/);
    assert.equal(x.pages.length,0);
  }
});

test("missing token, snapshot, published academic data, or frozen Principal signature fails closed",async()=>{
  const invalid=[
    x=>{x.verification_token="not-a-uuid";},
    x=>{delete x.snapshot;},
    x=>{x.snapshot.academic_records=[];},
    x=>{x.snapshot.principal.signature_path="";},
    x=>{x.snapshot.source_policy="unpublished_reports";}
  ];
  for(const mutate of invalid){
    const x=harness(),issued=fixture();mutate(issued);
    await assert.rejects(x.render(issued,x.deps));
    assert.equal(x.seen.signatureDraws,0);
  }
});

test("unavailable stored signature rejects instead of outputting an unsigned official document",async()=>{
  const x=harness();
  x.deps.readPrivateImage=async()=>{throw new Error("signature storage inaccessible");};
  await assert.rejects(x.render(fixture(),x.deps),/signature storage inaccessible/);
  assert.equal(x.seen.signatureDraws,0);
});

test("official download is gated to valid frozen issuance while preview remains clearly unofficial",()=>{
  assert.ok(index.indexOf('src="official-transcript-pdf.js?v=20261126-history-nav2"')<index.indexOf('src="parity-enterprise-workspaces.js?v=20261126-history-nav2"'));
  assert.match(workspace,/currentIssuance=obj\(data\?\.current_issuance\)/);
  assert.match(workspace,/currentIssuance\.status==="valid"/);
  assert.match(workspace,/data-transcript-official-pdf/);
  assert.match(workspace,/enterpriseTranscriptOfficialDownload/);
  assert.match(workspace,/window\.EdusentiaOfficialTranscriptPdf\.render\(issuance,deps\)/);
  assert.match(workspace,/Official_Transcript\.pdf/);
  assert.match(workspace,/Download transcript preview/);
  assert.match(workspace,/ACADEMIC TRANSCRIPT PREVIEW/);
});

test("official issuance includes school, Principal, immutable published results and digest validation",()=>{
  assert.match(sql,/'source_policy','latest_currently_valid_published_report_per_term'/);
  assert.match(sql,/'principal',principal_json/);
  assert.match(sql,/p\.revoked_at is null/);
  assert.match(sql,/r\.status='published'/);
  assert.match(provider,/snapshot_checksum/);
  assert.match(provider,/public\.verify_transcript\(token uuid\)/);
  assert.match(provider,/i\.status='valid'/);
});
