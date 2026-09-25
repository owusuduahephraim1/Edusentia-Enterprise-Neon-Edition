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
  assert.match(academics,/function classSubjectAssignmentGroups\(/);
  assert.match(academics,/assignmentCountText\(group\.classes\.size,"class","classes"\)/);
  assert.match(academics,/assignmentCountText\(group\.subjects\.size,"subject"\)/);
  assert.match(academics,/assignmentNamesPreview\(group\.classes\)/);
  assert.match(academics,/assignmentNamesPreview\(group\.subjects\)/);
  assert.match(academics,/id="toggleAssignmentList"/);
  assert.match(academics,/Compact list/);
  assert.match(academics,/Expand list/);
  assert.match(academics,/data-manage-assignment-group/);
  assert.match(academics,/Manage Teacher Assignments/);
  assert.match(academics,/assignment-group-summary/);
  assert.match(academics,/data-group-edit-assignment/);
  assert.match(academics,/data-group-remove-assignment/);
  assert.match(academics,/data-group-delete-assignment/);
  assert.match(academics,/Assign more/);
  assert.match(academics,/archive_academic_entity/);
  assert.match(academics,/delete_class_subject_assignment/);
  assert.match(academics,/id:id\|\|null/);
  assert.match(academics,/byId\("addAssignment"\)\.onclick=\(\)=>assignmentEditor\(\);/);
  assert.doesNotMatch(academics,/byId\("addAssignment"\)\.onclick=assignmentEditor;/);
  assert.match(academics,/id=typeof id==="string"\?id\.trim\(\):"";/);
  assert.match(academics,/teacherId=typeof teacherId==="string"\?teacherId\.trim\(\):"";/);

  for(const selector of [
    ".independent-check-grid",
    ".vertical-check-dropdown",
    ".vertical-check-panel",
    ".vertical-check-option"
  ]) assert.ok(css.includes(selector),selector);
});
