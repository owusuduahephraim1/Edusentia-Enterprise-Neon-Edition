import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const read=p=>fs.readFileSync(p,"utf8");
const URL="https://owusuduahephraim1.github.io/Edusentia-Enterprise-Neon-Edition/";

test("Neon Windows package stays separate from the Supabase native identity",()=>{
  const cargo=read("native/windows/src-tauri/Cargo.toml");
  const conf=read("native/windows/src-tauri/tauri.conf.json");
  const shell=read("native/windows/shell/index.html");
  assert.match(cargo,/name = "edusentia-enterprise-neon"/);
  assert.match(conf,/"identifier": "app\.edusentia\.enterprise\.neon"/);
  assert.ok(conf.includes(URL));
  assert.ok(shell.includes(URL));
  assert.match(conf,/"targets": \[\s*"msi",\s*"nsis"/);
});

test("Neon Android package is independently installable and targets only the Neon site",()=>{
  const gradle=read("native/android/app/build.gradle.kts");
  const manifest=read("native/android/app/src/main/AndroidManifest.xml");
  const main=read("native/android/app/src/main/java/app/edusentia/enterprise/neon/MainActivity.java");
  assert.match(gradle,/applicationId = "app\.edusentia\.enterprise\.neon"/);
  assert.match(gradle,/minSdk = 23/);
  assert.match(gradle,/targetSdk = 35/);
  assert.ok(main.includes(URL));
  assert.match(manifest,/android:host="owusuduahephraim1\.github\.io"/);
  assert.match(manifest,/android:pathPrefix="\/Edusentia-Enterprise-Neon-Edition"/);
});

test("native installer workflow produces MSI EXE and an installable APK",()=>{
  const workflow=read(".github/workflows/native-installers.yml");
  assert.match(workflow,/Edusentia-Enterprise-Neon-Windows-x64\.msi/);
  assert.match(workflow,/Edusentia-Enterprise-Neon-Setup-x64\.exe/);
  assert.match(workflow,/Edusentia-Enterprise-Neon-Android\.apk/);
  assert.match(workflow,/assembleRelease/);
  assert.match(workflow,/assembleDebug/);
});
