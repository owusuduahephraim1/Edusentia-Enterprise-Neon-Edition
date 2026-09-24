import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read = file => fs.readFileSync(file,"utf8");

test("public Edusentia information links use standalone pages",()=>{
  const index=read("frontend/index.html");
  for(const page of ["about","support","privacy","terms"]){
    assert.match(index,new RegExp(`href=["']\\./${page}\\.html["']`));
    assert.doesNotMatch(index,new RegExp(`href=["']#${page}["']`));
  }
});

test("public information pages preserve Edusentia navigation and Neon architecture",()=>{
  for(const page of ["about","support","privacy","terms"]){
    const html=read(`frontend/${page}.html`);
    assert.match(html,/Edusentia Enterprise/);
    assert.match(html,/href="\.\/index\.html"/);
    for(const destination of ["about","support","privacy","terms"]){
      assert.match(html,new RegExp(`href=["']\\./${destination}\\.html["']`));
    }
    assert.doesNotMatch(html,/Supabase project/i);
  }
  assert.match(read("frontend/about.html"),/isolated Neon PostgreSQL database/i);
  assert.match(read("frontend/about.html"),/Cloudflare Workers/i);
  assert.match(read("frontend/about.html"),/Cloudflare R2/i);
  assert.match(read("frontend/support.html"),/Account recovery/i);
  assert.match(read("frontend/privacy.html"),/Tenant isolation and access control/i);
  assert.match(read("frontend/terms.html"),/Licensing, capacity and availability/i);
});

test("PWA shell caches public information pages",()=>{
  const sw=read("frontend/service-worker.js");
  assert.match(sw,/edusentia-neon-v26/);
  for(const asset of ["about.html","support.html","privacy.html","terms.html","info-pages.css"]){
    assert.match(sw,new RegExp(asset.replace(".","\\.")));
  }
});
