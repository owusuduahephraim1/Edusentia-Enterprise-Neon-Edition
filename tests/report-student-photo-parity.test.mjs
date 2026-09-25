import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=path=>fs.readFileSync(path,"utf8");

test("report cards resolve the protected student photograph for current print/PDF output",()=>{
  const reports=read("frontend/parity-reports.js");
  assert.match(reports,/api\(\)\.downloadStudentPhoto\(id,path\)/);
  assert.match(reports,/student\.photo_url/);
  assert.match(reports,/get_report_editor/);
  assert.match(reports,/reportStudentPhotoDataUrl/);
  assert.match(reports,/Print \/ Save PDF/);
  assert.match(reports,/STUDENT<br>PHOTO/);
  assert.match(reports,/object-fit:cover/);
  assert.match(reports,/Generated from the current protected school record/);
});
