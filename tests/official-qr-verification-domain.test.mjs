import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const uuid="6c622ff5-82a8-4db8-8c78-d441522a16f3";
const idCardStart=source.indexOf('const OFFICIAL_VERIFICATION_BASE_URL=');
const idCardEnd=source.indexOf('  async function idCardBlobImage(',idCardStart);
assert.ok(idCardStart>=0 && idCardEnd>idCardStart,"Expected isolated URL and clipboard helper block");

function loadHelpers(tenant={code:"NIS-000001"}){
  const context={
    URL,window:{EdusentiaShell:{state:{boot:{tenant}}}},
    location:{origin:"https://owusuduahephraim1.github.io"},
    navigator:{},notify:()=>{}
  };
  return vm.runInNewContext(
    source.slice(idCardStart,idCardEnd)+
      "\n({idCardVerificationUrl,officialDocumentVerificationUrl,edusentiaVerificationBaseUrl})",
    context
  );
}

test("future ID card QR codes point at the dedicated secure verification origin",()=>{
  const {idCardVerificationUrl}=loadHelpers();
  for(const mode of ["staff","student"]){
    const link=idCardVerificationUrl(uuid,mode);
    const url=new URL(link);
    assert.equal(url.origin,"https://verify.edusentia.com");
    assert.equal(url.pathname,"/");
    assert.equal(url.searchParams.get(mode==="staff"?"staffcard":"idcard"),uuid);
    assert.equal(url.searchParams.get("school"),"NIS-000001");
    assert.equal([...url.searchParams.keys()].length,2);
  }
  assert.equal(
    new URL(idCardVerificationUrl(uuid,"staff",{tenant_code:"FEC-000001"})).searchParams.get("school"),
    "FEC-000001");
});

test("all five independently issued document types have correctly encoded official links",()=>{
  const {officialDocumentVerificationUrl,edusentiaVerificationBaseUrl}=loadHelpers();
  assert.equal(edusentiaVerificationBaseUrl(),"https://verify.edusentia.com/");
  const typeToParam={staff:"staffcard",student:"idcard",report:"verify",
    certificate:"certificate",transcript:"transcript"};
  for(const [kind,key] of Object.entries(typeToParam)){
    const url=new URL(officialDocumentVerificationUrl(uuid,kind));
    assert.equal(url.hostname,"verify.edusentia.com");
    assert.equal(url.searchParams.get(key),uuid);
    assert.equal(url.searchParams.get("school"),"NIS-000001");
  }
});

test("the QR helper rejects missing or malformed tokens rather than issuing unverifiable codes",()=>{
  const {idCardVerificationUrl,officialDocumentVerificationUrl}=loadHelpers({name:"School"});
  assert.throws(()=>idCardVerificationUrl("","staff"),/valid issued document/);
  assert.throws(()=>officialDocumentVerificationUrl("xyz","report"),/valid issued document/);
  assert.throws(()=>officialDocumentVerificationUrl(uuid,"unknown"),/valid issued document/);
  const url=new URL(officialDocumentVerificationUrl(uuid,"transcript"));
  assert.equal(url.searchParams.has("school"),false);
});

test("issued certificates and transcript links use canonical URL helper, with tokens unchanged",()=>{
  assert.match(source,/data-transcript-verification-link/);
  assert.match(source,/copyOfficialVerificationLink\(button\.dataset\.transcriptVerificationLink,"transcript"\)/);
  assert.match(source,/data-certificate-verify-link|certificateVerifyRecipient/);
  assert.match(source,/copyOfficialVerificationLink\(byId\("certificateVerifyRecipient"\)\.value,"certificate",detail\.school\|\|\{\}\)/);
  assert.match(source,/function idCardVerificationUrl\(token,mode,school=\{\}\)/);
  assert.doesNotMatch(source,/https:\/\/verify\.edusentia\.com\/\?staffcard=6c622ff5/);
});

test("legacy five document link formats remain supported independently of newly printed QR URLs",()=>{
  const publicVerification=fs.readFileSync("frontend/index.html","utf8");
  for(const key of ["staffcard","idcard","verify","certificate","transcript"])
    assert.ok(publicVerification.includes('q.has("'+key+'")'),key);
  const page=fs.readFileSync("frontend/verify-card.js","utf8");
  assert.match(page,/url\.searchParams\.set\(staff\?"staffcard":"idcard",staff\|\|student\)/);
  assert.match(page,/url\.searchParams\.set\(key,value\)/);
  const worker=fs.readFileSync("worker/src/public-id-verification.ts","utf8");
  assert.match(worker,/Old printed QR codes contain only a random UUID/);
});
