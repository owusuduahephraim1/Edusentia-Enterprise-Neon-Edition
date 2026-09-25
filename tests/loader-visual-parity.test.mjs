import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=file=>fs.readFileSync(file,"utf8");

test("startup loader remains animated and uses the lightweight education scene",()=>{
  const index=read("frontend/index.html");
  const css=read("frontend/style.css");
  const sw=read("frontend/service-worker.js");
  const asset="frontend/assets/loader-education-bg.svg";

  assert.match(index,/rel="preload" as="image" href="assets\/loader-education-bg\.svg"/);
  assert.match(index,/class="loader-shell"/);
  assert.match(index,/class="loader-orbit"/);
  assert.match(index,/class="loader-orbit-art"/);
  assert.match(index,/Preparing your connected school workspace/);
  assert.match(css,/\.spinner\{width:42px;height:42px;[^}]*animation:spin \.8s linear infinite\}/);
  assert.match(css,/\.loader-screen \.spinner\{[^}]*animation:spin \.9s linear infinite/);
  assert.match(css,/@media\(prefers-reduced-motion:reduce\)[\s\S]*?\.loader-screen \.spinner\{animation:spin \.9s linear infinite!important\}/);
  assert.match(css,/url\("assets\/loader-education-bg\.svg"\)/);
  assert.match(sw,/\.\/assets\/loader-education-bg\.svg/);
  assert.ok(fs.existsSync(asset),"loader background asset must exist");
  assert.ok(fs.statSync(asset).size < 40_000,"loader background must remain lightweight");
});
