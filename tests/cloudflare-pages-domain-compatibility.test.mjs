import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const configSource=fs.readFileSync("frontend/config.js","utf8");
const corsSource=fs.readFileSync("worker/src/http.ts","utf8");
const workerSource=fs.readFileSync("worker/src/index.ts","utf8");
const turnstileSource=fs.readFileSync("worker/src/turnstile.ts","utf8");
const wrangler=JSON.parse(fs.readFileSync("worker/wrangler.jsonc","utf8"));

function configFor(hostname){
  const window={location:{hostname}};
  vm.runInNewContext(configSource,{window});
  return window.EDS_MASTER_CONFIG;
}
const legacyOrigin="https://owusuduahephraim1.github.io";
const legacyApi="https://edusentia-enterprise-neon-api.edusentia-enterprise-neon.workers.dev";
const newApi="https://api.edusentia.com";
const pagesOrigin="https://edusentia-app.pages.dev";
const appOrigin="https://app.edusentia.com";

function originCheck(){
  const start=corsSource.indexOf("export function isAllowedAppOrigin(");
  const end=corsSource.indexOf("const PUBLIC_VERIFICATION_ORIGIN=",start);
  assert.ok(start>=0 && end>start);
  const src=corsSource.slice(start,end)
    .replace("export function isAllowedAppOrigin(env:Env, origin:string)","function isAllowedAppOrigin(env, origin)");
  return vm.runInNewContext(src+"\nisAllowedAppOrigin", {});
}

test("Cloudflare Pages and official application host use custom API and root path",()=>{
  for(const host of ["edusentia-app.pages.dev","app.edusentia.com"]){
    const c=configFor(host);
    assert.equal(c.apiBaseUrl,newApi);
    assert.equal(c.repositoryBasePath,"/");
  }
});

test("Original GitHub Pages and native shell API destinations are preserved",()=>{
  for(const host of ["owusuduahephraim1.github.io","unknown.example","e0da9f3a.edusentia-app.pages.dev"]){
    const c=configFor(host);
    assert.equal(c.apiBaseUrl,legacyApi);
    assert.equal(c.repositoryBasePath,"/Edusentia-Enterprise-Neon-Edition/");
  }
  const windows=JSON.parse(fs.readFileSync("native/windows/src-tauri/tauri.conf.json","utf8"));
  assert.equal(windows.app.windows[0].url,legacyOrigin+"/Edusentia-Enterprise-Neon-Edition/");
});

test("Only explicitly authorized HTTPS application origins pass Worker CORS and origin check",()=>{
  const isAllowedAppOrigin=originCheck();
  const env={
    APP_ORIGIN:legacyOrigin,
    ADDITIONAL_APP_ORIGINS:pagesOrigin+","+appOrigin
  };
  for(const origin of [legacyOrigin,pagesOrigin,appOrigin])
    assert.equal(isAllowedAppOrigin(env,origin),true,origin);
  for(const origin of ["https://evil.example","https://app.edusentia.com.evil.example",
    "http://app.edusentia.com","https://e0da9f3a.edusentia-app.pages.dev",
    pagesOrigin+"/", "null","", "https://edusentia.com"])
    assert.equal(isAllowedAppOrigin(env,origin),false,origin);
  assert.match(corsSource,/if\(isAllowedAppOrigin\(env,origin\)\)/);
  assert.match(corsSource,/access-control-allow-credentials/);
  assert.match(workerSource,/unsafe && !bootstrapCli && !isAllowedAppOrigin\(env,origin\)/);
});

test("Turnstile challenge host is bound to the invoking allowed application origin",()=>{
  assert.match(turnstileSource,/import \{ isAllowedAppOrigin \} from "\.\/http";/);
  assert.match(turnstileSource,/const requestOrigin=request\.headers\.get\("origin"\)\|\|"";/);
  assert.match(turnstileSource,/const originTrusted=isAllowedAppOrigin\(env,requestOrigin\)/);
  assert.match(turnstileSource,/const expectedHostname=originTrusted\?new URL\(requestOrigin\)\.hostname:"";/);
  assert.match(turnstileSource,/const hostnameMismatch=!originTrusted\|\|result\.hostname!==expectedHostname/);
});

test("Deployment keeps legacy APP_ORIGIN, adds two exact origins, and retains one Neon database",()=>{
  assert.equal(wrangler.vars.APP_ORIGIN,legacyOrigin);
  assert.equal(wrangler.vars.ADDITIONAL_APP_ORIGINS,pagesOrigin+","+appOrigin);
  assert.equal(wrangler.vars.APP_BASE_PATH,"/Edusentia-Enterprise-Neon-Edition");
  assert.equal(wrangler.r2_buckets.length,1);
  assert.equal(wrangler.r2_buckets[0].bucket_name,"edusentia-enterprise-neon");
});
