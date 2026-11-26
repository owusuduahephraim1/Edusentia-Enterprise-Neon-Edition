// CI-only validation of the Edusentia public website's published static assets.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root=path.resolve("public-site");
const read=file=>fs.readFileSync(path.join(root,file),"utf8");
const pages=["index.html","security.html","privacy.html","404.html"];
for(const filename of pages){
  const source=read(filename);
  assert.match(source,/<!doctype html>/i,filename+" must be HTML5");
  assert.match(source,/name="viewport"/,filename+" missing mobile viewport");
  assert.match(source,/<main[^>]*id="main"|<main /,filename+" missing landmark");
  assert.match(source,/Edusentia/i,filename+" missing brand identity");
  assert.doesNotMatch(source,/\b(lorem ipsum|REPLACE_ME|TBD)\b/i,filename+" contains unfinished copy");
}
for(const filename of ["index.html","security.html","privacy.html"]){
  const source=read(filename);
  assert.match(source,/class="menu-button"/);
  assert.match(source,/id="main-menu"/);
  assert.match(source,/href="https:\/\/app\.edusentia\.com\//);
  assert.match(source,/href="https:\/\/verify\.edusentia\.com\//);
  assert.match(source,/href="\/security\.html"/);
  assert.match(source,/href="\/privacy\.html"/);
  assert.match(source,/src="\/site\.js"/);
  assert.match(source,/href="\/styles\.css"/);
}
const home=read("index.html");
for(const anchor of ["platform","solutions","security","how-it-works","plans"]){
  assert.match(home,new RegExp('id="'+anchor+'"'),"missing "+anchor+" section");
}
for(const asset of ["assets/edusentia-mark.svg","assets/public-about-education.webp"]){
  const location=path.join(root,asset);
  assert.ok(fs.existsSync(location),"missing deploy asset "+asset);
  assert.ok(fs.statSync(location).size>50,"invalid asset "+asset);
}
for(const filename of ["styles.css","site.js","robots.txt","sitemap.xml","_headers","_redirects"]){
  assert.ok(fs.statSync(path.join(root,filename)).size>0,"missing "+filename);
}
new vm.Script(read("site.js"),{filename:"site.js"});
const css=read("styles.css");
assert.match(css,/@media\(max-width:710px\)/);
assert.match(css, /prefers-reduced-motion/);
assert.match(home,/rel="noopener noreferrer"/);
assert.doesNotMatch(home,/(?:\$|GHS)\s*\d{2,}/,"do not publish unapproved prices");
assert.match(read("_headers"),/Content-Security-Policy:/);
assert.match(read("_headers"),/frame-ancestors 'none'/);
assert.match(read("_redirects"),/www\.edusentia\.com\/\*/);
assert.match(read("robots.txt"),/Sitemap: https:\/\/edusentia\.com\/sitemap\.xml/);
assert.match(read("privacy.html"),/does not include a contact form/);
console.log("Edusentia public-site validation passed: 4 pages, 2 assets, responsive navigation, links, security headers and SEO.");
