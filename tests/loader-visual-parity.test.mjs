import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=file=>fs.readFileSync(file,"utf8");

test("startup loader uses the current Windows 11 solid donut progress indicator",()=>{
  const index=read("frontend/index.html");
  const css=read("frontend/style.css");
  const sw=read("frontend/service-worker.js");
  const asset="frontend/assets/loader-education-bg.svg";

  assert.match(index,/rel="preload" as="image" href="assets\/loader-education-bg\.svg"/);
  assert.match(index,/class="loader-content"/);
  assert.match(index,/class="windows11-progress-ring"/);
  assert.match(index,/<circle cx="22" cy="22" r="17"><\/circle>/);
  assert.doesNotMatch(index,/windows-loader-spinner/);
  assert.doesNotMatch(index,/<i><\/i><i><\/i>/);

  assert.match(css,/\.loader-screen img\{width:118px;height:118px/);
  assert.match(css,/\.windows11-progress-ring\{display:block;width:40px;height:40px\}/);
  assert.match(css,/\.windows11-progress-ring svg\{[^}]*animation:windows11-progress-spin 1\.05s linear infinite/);
  assert.match(css,/\.windows11-progress-ring circle\{[^}]*stroke-linecap:round;stroke-dasharray:38 69/);
  assert.match(css,/@keyframes windows11-progress-spin\{to\{transform:rotate\(360deg\)\}\}/);
  assert.match(css,/@media\(prefers-reduced-motion:reduce\)[\s\S]*?\.windows11-progress-ring svg\{animation-duration:1\.05s!important;animation-iteration-count:infinite!important\}/);
  assert.match(css,/url\("assets\/loader-education-bg\.svg"\)/);
  assert.match(sw,/\.\/assets\/loader-education-bg\.svg/);

  assert.ok(fs.existsSync(asset),"loader background asset must exist");
  assert.ok(fs.statSync(asset).size < 40_000,"loader background must remain lightweight");
});
