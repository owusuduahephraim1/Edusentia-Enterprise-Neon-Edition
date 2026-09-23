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

test("teacher photo Worker uses only the narrow authorization bridge", () => {
  const routes = read("worker/src/routes.ts");
  const start = routes.indexOf('kind==="staff-photos"');
  const end = routes.indexOf('if(method==="GET"&&p==="/api/files/download")');
  const photoSection = routes.slice(start, end);
  assert.ok(photoSection.includes("public.neon_authorize_teacher_photo_upload"));
  assert.ok(photoSection.includes("public.neon_teacher_photo_descriptor"));
  assert.equal(photoSection.includes("auth.uid()"), false);
  assert.equal(photoSection.includes("public.can_manage_teachers()"), false);
  assert.equal(photoSection.includes("from public.teachers"), false);
});

test("teacher photo bridge preserves certified Supabase authorization semantics", () => {
  const sql = read("database/reference-compat/0055_teacher_photo_r2_authorization.sql");
  for (const marker of [
    "public.is_system_admin() or t.profile_id=auth.uid()",
    "perform public.require_sensitive_access()",
    "public.license_write_allowed()",
    "public.can_manage_teachers()",
    "t.profile_id is distinct from auth.uid()",
    "grant execute on function public.neon_authorize_teacher_photo_upload(uuid) to edusentia_worker_runtime",
    "grant execute on function public.neon_teacher_photo_descriptor(uuid) to edusentia_worker_runtime"
  ]) assert.ok(sql.includes(marker), marker);
});
test("teacher photo Neon bridge uses Worker request context without auth-schema access", () => {
  const sql = read("database/reference-compat/0056_teacher_photo_neon_context_fix.sql");
  const install = read("database/reference-compat/install-operational-parity.sh");
  const upgrade = read("scripts/update-isolated-operational-tenants.sh");
  assert.ok(sql.includes("app.current_user_id()"));
  assert.equal(sql.includes("auth.uid()"), false);
  assert.ok(sql.includes("public.is_system_admin() or t.profile_id=app.current_user_id()"));
  assert.ok(sql.includes("t.profile_id is distinct from app.current_user_id()"));
  assert.ok(sql.includes("grant execute on function public.neon_authorize_teacher_photo_upload(uuid) to edusentia_worker_runtime"));
  assert.ok(sql.includes("grant execute on function public.neon_teacher_photo_descriptor(uuid) to edusentia_worker_runtime"));
  assert.ok(install.includes("0056_teacher_photo_neon_context_fix"));
  assert.ok(upgrade.includes("0056_teacher_photo_neon_context_fix"));
});

test("teacher photo storage contract stays teacher-relative and private", () => {
  const routes = read("worker/src/routes.ts");
  const certified = read("database/reference-compat/0038_certified_teacher_principal_crud.sql");
  for (const marker of [
    'kind==="staff-photos"',
    "referencePath=",
    'p==="/api/files/staff-photo"',
    'h.set("content-disposition","inline")',
    'h.set("cache-control","private, no-store")'
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
