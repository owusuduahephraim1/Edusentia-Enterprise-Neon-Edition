import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=file=>fs.readFileSync(file,"utf8");

test("startup loader follows the Supabase-like centered layout with Windows-style dot motion",()=>{
  const index=read("frontend/index.html");
  const css=read("frontend/style.css");
  const sw=read("frontend/service-worker.js");
  const asset="frontend/assets/loader-education-bg.svg";

  assert.match(index,/rel="preload" as="image" href="assets\/loader-education-bg\.svg"/);
  assert.match(index,/class="loader-content"/);
  assert.match(index,/class="windows-loader-spinner"/);
  assert.match(index,/<i><\/i><i><\/i><i><\/i><i><\/i><i><\/i><i><\/i>/);
  assert.doesNotMatch(index,/class="loader-orbit"/);
  assert.doesNotMatch(index,/Preparing your connected school workspace/);

  assert.match(css,/\.loader-screen img\{width:118px;height:118px/);
  assert.match(css,/\.windows-loader-spinner\{[^}]*width:40px;height:40px/);
  assert.match(css,/\.windows-loader-spinner i\{[^}]*animation:windows11-loader 1\.55s/);
  assert.match(css,/@keyframes windows11-loader\{0%\{transform:rotate\(0deg\)\}45%\{transform:rotate\(210deg\)\}72%\{transform:rotate\(390deg\)\}100%\{transform:rotate\(720deg\)\}\}/);
  assert.match(css,/@media\(prefers-reduced-motion:reduce\)[\s\S]*?\.windows-loader-spinner i\{animation-duration:1\.55s!important;animation-iteration-count:infinite!important\}/);
  assert.match(css,/url\("assets\/loader-education-bg\.svg"\)/);
  assert.match(sw,/\.\/assets\/loader-education-bg\.svg/);

  assert.ok(fs.existsSync(asset),"loader background asset must exist");
  assert.ok(fs.statSync(asset).size < 40_000,"loader background must remain lightweight");
});
