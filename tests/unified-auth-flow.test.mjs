import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("Platform Super Administrator uses the shared blueprint sign-in",()=>{
  const app=read("frontend/app.js");
  const canonical=read("frontend/platform-saas-admin.html");
  const consoleJs=read("frontend/platform-saas-admin.js");
  const legacy=read("frontend/platform-admin.html");

  assert.match(app,/platformMode\s*=\s*new URLSearchParams\(location\.search\)\.get\("platform"\)===["']1["']/);
  assert.match(app,/api\(\)\.platformSession\(\)/);
  assert.match(app,/api\(\)\.platformLogin/);
  assert.match(app,/api\(\)\.platformCompleteMfa/);
  assert.match(app,/platformMode\?["']platform_login["']:["']login["']/);
  assert.match(app,/location\.replace\(["']\.\/platform-saas-admin\.html["']\)/);

  assert.match(canonical,/id=["']paAuthView["'] class=["']pa-auth-view hidden["']/);
  assert.match(consoleJs,/location\.replace\(["']\.\/\?platform=1["']\)/);
  assert.match(consoleJs,/platformSession\(\)/);
  assert.match(consoleJs,/platformLogout\(\)/);
  assert.match(legacy,/location\.replace\(["']\.\/platform-saas-admin\.html["']\)/);
});

test("Tenant sign-in remains isolated-school aware",()=>{
  const app=read("frontend/app.js");
  const auth=read("worker/src/auth.ts");

  assert.match(app,/resolveSchool\(code\)/);
  assert.match(app,/api\(\)\.login\(fd\.get\(["']email["']\),fd\.get\(["']password["']\),tenantCode,turnstileToken\)/);
  assert.match(app,/tenant_selection_required/);
  assert.match(app,/Student Academic Service/);
  assert.match(auth,/platform\.resolve_login_route/);
  assert.match(auth,/tenantDb\(env,String\(route\.database_name\)\)/);
  assert.match(auth,/mfaRequired:true/);
  assert.match(auth,/assuranceLevel:2/);
});

test("Approved school administrator setup returns to branded tenant sign-in",()=>{
  const html=read("frontend/admin-setup.html");
  const js=read("frontend/admin-setup.js");

  assert.match(html,/id=["']continueSchoolSignIn["']/);
  assert.match(js,/index\.html\?school=/);
  assert.match(js,/encodeURIComponent\(tenantCode\)/);
  assert.match(js,/encodeURIComponent\(adminEmail\)/);
});

test("Canonical platform console preserves Neon-only operations",()=>{
  const html=read("frontend/platform-saas-admin.html");
  const js=read("frontend/platform-saas-admin.js");
  const sw=read("frontend/service-worker.js");
  const css=read("frontend/platform-saas-admin.css");

  assert.match(html,/data-view=["']packages["']/);
  assert.match(html,/platform-api-client\.js/);
  assert.match(js,/packageStatus\(\)/);
  assert.match(js,/packageAction\(["']generate["']/);
  assert.match(js,/package-template-upload/);
  assert.match(js,/package-maintain/);
  assert.match(sw,/platform-saas-admin\.html/);
  assert.match(sw,/platform-saas-admin\.js/);
  assert.match(css,/\.hidden\{display:none!important\}/);
});
