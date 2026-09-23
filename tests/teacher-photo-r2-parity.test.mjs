import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read = p => fs.readFileSync(p, "utf8");

test("teacher photo UI parity", () => {
  const teachers = read("frontend/parity-teachers.js");
  for (const marker of [
    "staff-avatar-photo",
    "data-teacher-photo",
    "hydrateTeacherPhotos",
    "staff-photo-editor",
    "teacherPhotoPreview",
    "downloadStaffPhoto",
    'uploadFile(file,"staff-photos",{subfolder:teacher.id})',
    "target_photo_url:photoPath"
  ]) assert.ok(teachers.includes(marker), marker);
  assert.doesNotThrow(() => new Function(teachers));
});

test("teacher photo storage contract", () => {
  const routes = read("worker/src/routes.ts");
  const certified = read("database/reference-compat/0038_certified_teacher_principal_crud.sql");
  for (const marker of [
    'kind==="staff-photos"',
    "referencePath=",
    "public.can_manage_teachers() or t.profile_id=auth.uid()",
    'p==="/api/files/staff-photo"',
    'h.set("content-disposition","inline")',
    'h.set("cache-control","private, no-store")',
    "public.license_write_allowed()"
  ]) assert.ok(routes.includes(marker), marker);
  assert.ok(certified.includes("split_part(clean_path,'/',1)<>target_teacher_id::text"));
});

test("teacher photo API client parity", () => {
  const api = read("frontend/api-client.js");
  for (const marker of [
    "async function downloadStaffPhoto",
    "referencePath:payload.referencePath||prepared.referencePath||",
    "downloadStaffPhoto,"
  ]) assert.ok(api.includes(marker), marker);
});
