import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { spawnSync } from "node:child_process";

const root=process.cwd();
const http=fs.readFileSync(path.join(root,"worker/src/http.ts"),"utf8");
const wrangler=JSON.parse(fs.readFileSync(path.join(root,"worker/wrangler.jsonc"),"utf8"));
const buildScript=fs.readFileSync(path.join(root,"scripts/build-verification-site.mjs"),"utf8");
const originalPortal=fs.readFileSync(path.join(root,"frontend/verify-card.html"),"utf8");
const publicUi=fs.readFileSync(path.join(root,"frontend/verify-card.js"),"utf8");
const sourceReference=fs.readFileSync(path.join(root,"reference/certified-ui/app.js"),"utf8");

function policy(){
  const start=http.indexOf("export function isAllowedAppOrigin(");
  const end=http.indexOf("export function secureHeaders(",start);
  assert.ok(start>=0 && end>start,"Expected isolated CORS functions");
  const body=http.slice(start,end)
    .replace("export function isAllowedAppOrigin(env:Env, origin:string)",
      "function isAllowedAppOrigin(env,origin)")
    .replace("export function isAllowedPublicVerification(request:Request)",
      "function isAllowedPublicVerification(request)")
    .replace("export function corsHeaders(request:Request, env:Env)",
      "function corsHeaders(request,env)");
  return vm.runInNewContext(body+"\n({corsHeaders,isAllowedAppOrigin,isAllowedPublicVerification})",
    {Headers,URL,Request});
}

test("verification portal may read token-bound GET endpoints but is not an authenticated application origin",()=>{
  const {corsHeaders,isAllowedAppOrigin,isAllowedPublicVerification}=policy();
  const env={APP_ORIGIN:"https://owusuduahephraim1.github.io",
    ADDITIONAL_APP_ORIGINS:"https://edusentia-app.pages.dev,https://app.edusentia.com"};
  const verifyOrigin="https://verify.edusentia.com";
  assert.equal(isAllowedAppOrigin(env,verifyOrigin),false);
  assert.equal(wrangler.vars.ADDITIONAL_APP_ORIGINS.includes(verifyOrigin),false);
  const paths=["/api/public/id-card-verification","/api/public/document-verification"];
  for(const endpoint of paths){
    for(const method of ["GET","HEAD","OPTIONS"]){
      const request=new Request("https://api.edusentia.com"+endpoint,{method,
        headers:{Origin:verifyOrigin}});
      const h=corsHeaders(request,env);
      assert.equal(isAllowedPublicVerification(request),true);
      assert.equal(h.get("access-control-allow-origin"),verifyOrigin);
      assert.equal(h.get("access-control-allow-credentials"),null);
      assert.equal(h.get("access-control-allow-methods"),"GET,HEAD,OPTIONS");
      assert.equal(h.get("access-control-allow-headers"),"accept");
    }
  }
  for(const [method,endpoint] of [
    ["POST","/api/public/document-verification"],
    ["GET","/api/auth/session"],["GET","/api/health"],
    ["PATCH","/api/public/id-card-verification"],["GET","/api/tenant/bootstrap"]
  ]){
    const req=new Request("https://api.edusentia.com"+endpoint,{method,
      headers:{Origin:verifyOrigin}});
    assert.equal(isAllowedPublicVerification(req),false);
    assert.equal(corsHeaders(req,env).get("access-control-allow-origin"),null);
  }
  const privilegedRequest=new Request("https://api.edusentia.com/api/auth/session",{
    method:"GET",headers:{Origin:"https://app.edusentia.com"}});
  const privilegedHeaders=corsHeaders(privilegedRequest,env);
  assert.equal(privilegedHeaders.get("access-control-allow-credentials"),"true");
});

test("standalone Pages build contains only public verification assets and restrictive security headers",()=>{
  const r=spawnSync(process.execPath,["scripts/build-verification-site.mjs"],
    {cwd:root,encoding:"utf8"});
  assert.equal(r.status,0,r.stderr||r.stdout);
  const output=path.join(root,"dist/verification");
  const names=fs.readdirSync(output).sort();
  assert.deepEqual(names,["_headers","assets","config.js","index.html",
    "robots.txt","verify-card.css","verify-card.html","verify-card.js"].sort());
  assert.deepEqual(fs.readdirSync(path.join(output,"assets")),["edusentia-mark.svg"]);
  const html=fs.readFileSync(path.join(output,"index.html"),"utf8");
  assert.match(html,/Official School Document Verification/);
  assert.match(html,/verify-card\.js/);
  assert.doesNotMatch(html,/app\.js|native-document-downloads|loginForm|turnstileWidget/);
  assert.match(html,/href="https:\/\/app\.edusentia\.com\/"/);
  const config=fs.readFileSync(path.join(output,"config.js"),"utf8");
  assert.match(config,/apiBaseUrl:"https:\/\/api\.edusentia\.com"/);
  assert.doesNotMatch(config,/APP_ORIGIN|csrf|secret|siteKey|password|platformAdminPhone/);
  const headers=fs.readFileSync(path.join(output,"_headers"),"utf8");
  for(const name of ["X-Robots-Tag: noindex","Cache-Control: no-store",
    "Referrer-Policy: no-referrer","X-Frame-Options: DENY",
    "connect-src https://api.edusentia.com","form-action 'none'"]){
    assert.ok(headers.includes(name),name);
  }
  assert.equal(fs.readFileSync(path.join(output,"robots.txt"),"utf8"),
    "User-agent: *\nDisallow: /\n");
});

test("existing verification links remain supported and current UI permits both API hostnames",()=>{
  const index=fs.readFileSync(path.join(root,"frontend/index.html"),"utf8");
  for(const key of ["staffcard","idcard","verify","certificate","transcript"]){
    assert.ok(index.includes('q.has("'+key+'")'),"Legacy "+key);
  }
  assert.match(originalPortal,/connect-src https:\/\/api\.edusentia\.com https:\/\/edusentia-enterprise-neon-api\.edusentia-enterprise-neon\.workers\.dev;/);
  assert.match(publicUi,/Scan an official school document/);
  assert.match(sourceReference,/publicType=staffCardToken\?"staffcard"/);
  assert.match(buildScript,/join\(frontend,"verify-card\.html"\)/);
});

test("issued-card QR addresses remain on their currently active hosts until the new verification domain goes live",()=>{
  const source=fs.readFileSync(path.join(root,"frontend/parity-enterprise-workspaces.js"),"utf8");
  assert.match(source,/function idCardVerificationUrl\(token,mode,school=\{\}\)/);
  assert.match(source,/new URL\("verify-card\.html",edusentiaVerificationBaseUrl\(\)\)/);
  assert.doesNotMatch(source,/new URL\("https:\/\/verify\.edusentia\.com/);
});
