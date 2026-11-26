import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const html=fs.readFileSync("frontend/index.html","utf8");
const sw=fs.readFileSync("frontend/service-worker.js","utf8");
const shell=fs.readFileSync("frontend/app.js","utf8");
const workspace=fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const revision="20261126-history-nav2";

test("school app loads versioned shell and Academic History modules instead of old cached URLs",()=>{
  for(const name of ["app.js","parity-enterprise-workspaces.js","official-transcript-pdf.js"]){
    assert.ok(html.includes('src="'+name+'?v='+revision+'"'),name+" missing revision");
    assert.ok(sw.includes('"./'+name+'?v='+revision+'"'),name+" missing from new PWA cache");
  }
  assert.ok(!html.includes('src="app.js"'));
  assert.ok(!html.includes('src="parity-enterprise-workspaces.js"'));
});
test("service worker invalidates the old cache and fetches live scripts from the network",()=>{
  assert.ok(sw.includes('const CACHE = "edusentia-neon-v45-academic-history"'));
  assert.match(sw,/e\.request\.destination/);
  assert.match(sw,/fetch\(networkRequest\)/);
  assert.match(sw,/keys\.filter\(k => k !== CACHE\)/);
});
test("versioned shell reserves and full module renders the exact Student Academic History entry",()=>{
  assert.match(shell,/\{id:"history",label:"Student Academic History"/);
  assert.match(workspace,/registerView\(\{id:"history",label:"Student Academic History"/);
  assert.match(shell,/system_admin:\["dashboard","operations","students","student_services","staff","history","teachers"/);
  assert.match(workspace,/render:renderHistory/);
});
