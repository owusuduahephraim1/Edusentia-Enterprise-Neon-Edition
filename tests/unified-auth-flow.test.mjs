import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");

test("Platform Super Administrator uses the dedicated fail-safe sign-in page",()=>{
  const app=read("frontend/app.js");
  const canonical=read("frontend/platform-saas-admin.html");
  const consoleJs=read("frontend/platform-saas-admin.js");
  const legacy=read("frontend/platform-admin.html");

  assert.match(app,/platformMode\s*=\s*new URLSearchParams\(location\.search\)\.get\("platform"\)===["']1["']/);
  assert.match(app,/if\(platformMode\)\{location\.replace\(["']\.\/platform-saas-admin\.html["']\);return;\}/);
  assert.match(canonical,/id=["']paAuthView["'] class=["']pa-auth-view["'] aria-hidden=["']false["']/);
  assert.match(canonical,/challenges\.cloudflare\.com\/turnstile\/v0\/api\.js\?onload=onPlatformTurnstileLoad&render=explicit/);
  assert.match(canonical,/platform-saas-admin\.js\?v=platform-login-r43/);
  assert.match(consoleJs,/function showAuth\(mode=["']login["']\)/);
  assert.match(consoleJs,/paRecoveryCodes/);
  assert.match(consoleJs,/platformLogin\(/);
  assert.match(consoleJs,/platformCompleteMfa\(/);
  assert.match(consoleJs,/platformSession\(\)/);
  assert.match(consoleJs,/platformLogout\(\)/);
  assert.match(consoleJs,/location\.replace\(["']\.\/platform-saas-admin\.html["']\)/);
  assert.doesNotMatch(consoleJs,/location\.replace\(["']\.\/\?platform=1["']\)/);
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
  assert.match(auth,/\["system_admin","principal","platform_super_admin"\]\.includes\(canonicalAppRole\(role\)\)/);
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

test("Platform Administration exposes an accessible mobile navigation drawer",()=>{
  const html=read("frontend/platform-saas-admin.html");
  const js=read("frontend/platform-saas-admin.js");
  const mobile=read("frontend/platform-r40-mobile.css");

  assert.match(html,/id="paMobileMenuButton"/);
  assert.match(html,/aria-controls="paPlatformNav"/);
  assert.match(html,/id="paMobileDrawerBackdrop"/);
  assert.match(html,/id="paPlatformSidebar"/);
  assert.match(js,/function setMobileDrawer\(open=false\)/);
  assert.match(js,/function toggleMobileDrawer\(\)/);
  assert.match(js,/pa-mobile-drawer-open/);
  assert.match(js,/aria-expanded/);
  assert.match(js,/event\.key==="Escape"/);
  assert.match(js,/window\.innerWidth>820/);
  assert.match(mobile,/\.pa-sidebar\.pa-drawer-open\s*\{\s*transform:\s*translateX\(0\)/);
  assert.match(mobile,/\.pa-mobile-drawer-backdrop\.open/);
  assert.match(mobile,/\.pa-mobile-menu-button\s*\{/);
});


test("browser authentication scripts remain syntactically valid",()=>{
  for(const file of [
    "frontend/api-client.js",
    "frontend/app.js",
    "frontend/platform-api-client.js",
    "frontend/platform-saas-admin.js",
    "frontend/admin-setup.js"
  ]){
    assert.doesNotThrow(()=>new Function(read(file)),file+" must parse as browser JavaScript");
  }
  assert.doesNotMatch(read("frontend/api-client.js"),/\\\\n\s+listFinance/);
});


test("Tenant-managed users are synchronized into the master login directory",()=>{
  const identity=read("worker/src/identity-admin.ts");
  const upgrade=read("scripts/update-isolated-operational-tenants.sh");
  assert.match(identity,/import \{ db, tenantTx \} from "\.\/db"/);
  assert.match(identity,/async function syncLoginRoute/);
  assert.match(identity,/platform\.login_directory/);
  assert.match(identity,/on conflict\(email_normalized,tenant_id\) do update/);
  assert.match(identity,/async function removeLoginRoute/);
  assert.match(identity,/createIdentity\(env,sql,ctx,payload/);
  assert.match(identity,/updateIdentity\(env,sql,ctx,payload/);
  assert.match(upgrade,/Tenant \$tenant_code login directory synchronized/);
  assert.match(upgrade,/platform\.login_directory/);
  assert.match(upgrade,/tenant_login_count/);
});

test("Generated tenant user emails use the first usable name and can repair legacy addresses",()=>{
  const identity=read("worker/src/identity-admin.ts");
  const credentials=read("frontend/tenant-user-credential-actions-v3.js");
  const migration=read("database/reference-compat/0066_generated_user_email_first_name_fix.sql");

  assert.match(identity,/const ACCOUNT_EMAIL_TITLES=new Set\(/);
  assert.match(identity,/function accountEmailBase\(fullName:unknown\)/);
  assert.match(identity,/parts\.find\(part=>!ACCOUNT_EMAIL_TITLES\.has\(part\)\)\|\|parts\[0\]\|\|"user"/);
  assert.match(identity,/const requestedBase=accountEmailBase\(fullName\);/);
  assert.match(migration,/regexp_replace\(lower\(coalesce\(requested_base,''\)\),'\[\^a-z0-9\]','','g'\)/);
  assert.match(migration,/0066_generated_user_email_first_name_fix/);
  assert.match(identity,/generate_nip_user_email\(\$\{ctx\.userId\}::uuid,\$\{requestedBase\},\$\{targetUserId\}::uuid\)/);
  assert.match(identity,/action==="refresh_generated_email"/);
  assert.match(identity,/async function refreshGeneratedEmail\(/);
  assert.match(identity,/public\.list_profiles_with_access\(\)->'profiles'/);
  assert.match(identity,/profile->>'staff_record_id'/);
  assert.match(identity,/return refreshGeneratedEmail\(env,sql,ctx,payload\)/);
  assert.match(identity,/syncLoginRoute\(env,ctx,newEmail/);
  assert.match(identity,/removeLoginRoute\(env,ctx,oldEmail\)/);

  assert.match(credentials,/function accountEmailBase\(value\)/);
  assert.match(credentials,/function generatedEmailNeedsRepair\(profile\)/);
  assert.match(credentials,/Correct email/);
  assert.match(credentials,/adminUserManagement\("refresh_generated_email"/);
  assert.match(credentials,/staff_record_id: profile\.staff_record_id/);
});

test("Required password changes block workspace entry until completed",()=>{
  const app=read("frontend/app.js");
  const routes=read("worker/src/routes.ts");
  const identity=read("worker/src/identity-admin.ts");
  assert.match(routes,/profile:certifiedBootstrap\?\.profile\|\|null/);
  assert.match(app,/state\.boot\?\.profile\?\.must_change_password===true/);
  assert.match(app,/openRequiredPasswordChange\(\)/);
  assert.match(app,/complete_own_required_password_change/);
  assert.match(app,/Password Change Required/);
  assert.match(identity,/action==="complete_own_required_password_change"/);
  assert.match(identity,/resetPassword\(sql,ctx,ctx\.userId,password,false\)/);
});


test("Tenant logout returns to the branded school sign-in instead of the public registration page",()=>{
  const app=read("frontend/app.js");
  assert.match(app,/function tenantLoginUrl\(session=state\.session\)/);
  assert.match(app,/target\.searchParams\.set\("school",code\)/);
  assert.match(app,/const target=tenantLoginUrl\(\);[\s\S]*api\(\)\.logout\(\)[\s\S]*location\.replace\(target\)/);
  assert.match(app,/registerSchoolButton"\)\?\.classList\.toggle\("hidden",tenantMode\)/);
  assert.match(app,/authBrandName"\)\.textContent=tenantMode\?\(tenant\.school_name/);
});
