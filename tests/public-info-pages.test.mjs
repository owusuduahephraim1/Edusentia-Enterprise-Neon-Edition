import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
const read=file=>fs.readFileSync(file,"utf8");

test("public Edusentia links and sign-in surface carry the Nana K developer brand",()=>{
  const index=read("frontend/index.html");
  for(const page of ["about","support","privacy","terms"]){
    assert.match(index,new RegExp(`href=["']\\./${page}\\.html["']`));
  }
  assert.match(index,/Edusentia™/);
  assert.match(index,/Edusentia Enterprise™/);
  assert.match(index,/Developed by Nana K IT Solutions Consult/);
});

test("public pages use Supabase-parity hero images while retaining Neon architecture",()=>{
  const expected={about:"public-about-education.webp",support:"public-support-guidance.webp",privacy:"public-privacy-security.webp",terms:"public-terms-trust.webp"};
  const css=read("frontend/info-pages.css");
  for(const [page,image] of Object.entries(expected)){
    const html=read(`frontend/${page}.html`);
    assert.match(html,/class="public-info-page"/);
    assert.match(html,/class="hero-card"/);
    assert.match(html,new RegExp(image.replace(".","\\.")));
    assert.match(html,/Developed by Nana K IT Solutions Consult/);
    assert.match(html,/Edusentia™ and Edusentia Enterprise™ are trademarks of Nana K IT Solutions Consult/);
    assert.doesNotMatch(html,/Supabase project/i);
    assert.match(css,new RegExp(image.replace(".","\\.")));
    assert.ok(fs.existsSync(`frontend/assets/${image}`));
  }
  assert.match(read("frontend/about.html"),/isolated Neon PostgreSQL databases/i);
  assert.match(read("frontend/about.html"),/Cloudflare Workers/i);
  assert.match(read("frontend/about.html"),/Cloudflare R2/i);
});

test("PWA shell caches the public hero assets",()=>{
  const sw=read("frontend/service-worker.js");
  for(const asset of ["public-about-education.webp","public-support-guidance.webp","public-privacy-security.webp","public-terms-trust.webp"]){
    assert.match(sw,new RegExp(asset.replace(".","\\.")));
  }
});