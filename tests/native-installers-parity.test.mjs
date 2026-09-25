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
  assert.match(gradle,/targetSdk = 36/);
  assert.ok(main.includes(URL));
  assert.match(gradle,/com\.google\.android\.play:app-update:2\.1\.0/);
  assert.match(main,/AppUpdateManagerFactory\.create\(this\)/);
  assert.match(main,/AppUpdateType\.IMMEDIATE/);
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


test("Windows signed release channel uses Tauri updater verification and a GitHub latest manifest",()=>{
  const cargo=read("native/windows/src-tauri/Cargo.toml");
  const lib=read("native/windows/src-tauri/src/lib.rs");
  const template=read("native/windows/src-tauri/tauri.release.template.json");
  const release=read(".github/workflows/publish-native-release.yml");
  assert.match(cargo,/tauri-plugin-updater = "2"/);
  assert.match(lib,/EDUSENTIA_NEON_ENABLE_NATIVE_UPDATER/);
  assert.match(lib,/download_and_install/);
  assert.match(template,/releases\/latest\/download\/latest\.json/);
  assert.match(template,/createUpdaterArtifacts/);
  assert.match(release,/EDUSENTIA_NEON_TAURI_SIGNING_PRIVATE_KEY/);
  assert.match(release,/latest\.json/);
});

test("signed native publication is gated by permanent Windows and Android signing identities",()=>{
  const release=read(".github/workflows/publish-native-release.yml");
  for(const secret of [
    "EDUSENTIA_NEON_TAURI_SIGNING_PRIVATE_KEY",
    "EDUSENTIA_NEON_TAURI_UPDATER_PUBLIC_KEY",
    "EDUSENTIA_NEON_ANDROID_KEYSTORE_BASE64",
    "EDUSENTIA_NEON_ANDROID_KEY_ALIAS"
  ]) assert.ok(release.includes(secret));
  assert.match(release,/assembleRelease :app:bundleRelease/);
  assert.match(release,/gh release create/);
});
