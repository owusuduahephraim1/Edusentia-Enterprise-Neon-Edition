import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const ui=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const certified=fs.readFileSync("reference/certified-ui/app.js","utf8");
const issueSql=fs.readFileSync("database/reference-compat/0046_certified_reference_rpc_bulk.sql","utf8");
const start=ui.indexOf("async function certificatePrincipalSignature(data,certificate){");
const end=ui.indexOf("async function downloadIssuedCertificate(data,certificate,button){",start);
const signer=ui.slice(start,end);

test("issued certificate PDF downloads Principal signature from protected school storage",()=>{
  assert.ok(start>0&&end>start);
  assert.match(signer,/obj\(frozen\.principal\),obj\(data\?\.principal\)/);
  assert.match(signer,/certified\("get_current_principal_signature",\{\}\)/);
  assert.match(signer,/api\(\)\.downloadFile\(path\)/);
  assert.match(signer,/idCardBlobImage\(blob\)/);
  assert.match(signer,/png\|jpeg\|webp/);
});

test("Principal image is rendered on the certificate signature line",()=>{
  assert.match(signer,/const signature=await certificatePrincipalSignature\(data,certificate\)/);
  assert.match(signer,/idCardDrawSignatureOnLine\(ctx,signature\.image,675,1115,1030,110\)/);
  assert.match(ui,/function idCardPreparedSignature\(image\)/);
  assert.match(ui,/function idCardDrawSignatureOnLine\(ctx,image,left,right,lineY,maxHeight=72\)/);
});

test("certificate renderer never fabricates a missing signature",()=>{
  assert.match(signer,/No active Principal signature is uploaded/);
  assert.match(signer,/could not be loaded/);
  assert.match(signer,/throw new Error/);
  assert.match(signer,/issuedPrincipal&&principal\.full_name/);
  assert.match(signer,/signature\.full_name\|\|principal\.full_name/);
});

test("fix preserves certificate number, issue date, QR token and PDF download workflow",()=>{
  assert.match(signer,/certificate\.certificate_number/);
  assert.match(signer,/certificate\.issue_date/);
  assert.match(signer,/officialDocumentVerificationUrl\(certificate\.verification_token,"certificate",school\)/);
  assert.match(signer,/idCardQrCanvas\(verification,170\)/);
  assert.match(signer,/idCardImagesPdf\(\[image\],842,595,width,height\)/);
  assert.match(signer,/return \{blob:pdf,source:"generated"\}/);
});

test("reference issuance freezes the signing Principal identity and signature path",()=>{
  assert.match(issueSql,/snapshot=snapshot\|\|jsonb_build_object\('school',to_jsonb\(school\),'principal',jsonb_build_object\('full_name',principal\.full_name,'signature_path',principal\.signature_path\)/);
  assert.match(certified,/drawSignatureOnLine\(ctx,signature,650,1104,1068,92/);
});
