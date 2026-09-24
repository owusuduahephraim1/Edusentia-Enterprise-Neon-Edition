import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("Assign Subjects uses the certified tickable class and subject selectors",()=>{
  const academics=read("frontend/parity-academics.js");
  const css=read("frontend/style.css");

  assert.doesNotThrow(()=>new Function(academics));
  assert.match(academics,/function renderVerticalChecklistDropdown\(/);
  assert.match(academics,/id="assignmentClassDropdown"/);
  assert.match(academics,/id="assignmentSubjectDropdown"/);
  assert.match(academics,/data-check-id/);
  assert.match(academics,/data-check-all/);
  assert.match(academics,/All subjects/);
  assert.match(academics,/assignmentCombinationSummary/);
  assert.match(academics,/assignmentClassSelections:new Set\(\)/);
  assert.match(academics,/assignmentSubjectSelections:new Set\(\)/);
  assert.match(academics,/save_class_subject_assignments_batch/);
  assert.doesNotMatch(academics,/name="class_ids" multiple size="8"/);
  assert.doesNotMatch(academics,/name="subject_ids" multiple size="8"/);

  for(const selector of [
    ".independent-check-grid",
    ".vertical-check-dropdown",
    ".vertical-check-panel",
    ".vertical-check-option"
  ]) assert.ok(css.includes(selector),selector);
});
