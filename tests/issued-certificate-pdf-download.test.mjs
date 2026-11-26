import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const source=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const registry=fs.readFileSync("worker/src/certified-rpc-registry.ts","utf8");

test("issued certificate dialog exposes individual PDF and batch ZIP actions",()=>{
  assert.match(source,/id="certificateDownloadSingle"/);
  assert.match(source,/id="certificateDownloadAll"/);
  assert.match(source,/downloadIssuedCertificate\(detail,certificate,e\.currentTarget\)/);
  assert.match(source,/downloadIssuedCertificateBatch\(detail,e\.currentTarget\)/);
});

test("download uses only issued immutable certificates with number and token",()=>{
  assert.match(source,/certificate\.status!=="issued"/);
  assert.match(source,/certificate\.certificate_number\|\|!certificate\.verification_token/);
  assert.match(source,/certs\.find\(c=>c\.verification_token===token&&c\.status==="issued"\)/);
  assert.match(source,/frozen=obj\(certificate\.snapshot\)/);
});

test("PDF includes public verification QR, school details and issued record",()=>{
  assert.match(source,/officialDocumentVerificationUrl\(certificate\.verification_token,"certificate",school\)/);
  assert.match(source,/idCardQrCanvas\(verification,170\)/);
  assert.match(source,/certificate\.statement_text/);
  assert.match(source,/certificate\.certificate_number/);
  assert.match(source,/certificate\.issue_date/);
  assert.match(source,/idCardImagesPdf\(\[image\],842,595,width,height\)/);
  assert.match(source,/drawImageContain\(ctx,logo/);
});

test("download prioritizes stored official PDF but has a generated fallback",()=>{
  assert.match(source,/if\(certificate\.pdf_storage_path\)/);
  assert.match(source,/api\(\)\.downloadFile\(certificate\.pdf_storage_path\)/);
  assert.match(source,/return \{blob:stored,source:"stored"\}/);
  assert.match(source,/return \{blob:pdf,source:"generated"\}/);
});

test("ZIP packages only issued PDFs with failure manifest",()=>{
  assert.match(source,/arr\(data\.certificates\)\.filter\(c=>c\.status==="issued"\)/);
  assert.match(source,/new window\.JSZip/);
  assert.match(source,/zip\.file\("MANIFEST\.txt"/);
  assert.match(source,/zip\.generateAsync\(\{type:"blob",compression:"DEFLATE"\}\)/);
});

test("certificate PDF download does not mutate issued records or bypass approval",()=>{
  const start=source.indexOf("function certificateDownloadName(");
  const end=source.indexOf("  // ID-card issue/expiry",start);
  assert.ok(start>=0&&end>start);
  const downloadCode=source.slice(start,end);
  assert.doesNotMatch(downloadCode,/register_certificate_pdf|issue_certificate_batch|save_certificate_template/);
  assert.match(registry,/"register_certificate_pdf":/);
});
