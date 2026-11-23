import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const script = fs.readFileSync("frontend/native-document-downloads.js","utf8");
const winSource = fs.readFileSync("native/windows/src-tauri/src/lib.rs","utf8");
const idCardSource = fs.readFileSync("frontend/parity-enterprise-workspaces.js","utf8");
const parity = fs.readFileSync("frontend/parity-common.js","utf8");

function desktop(windowOverrides={}) {
  const window={__EDUSENTIA_WINDOWS_DESKTOP__:true,...windowOverrides};
  class Anchor {click(){}}
  const context={
    window,location:{origin:"https://owusuduahephraim1.github.io",pathname:"/Edusentia-Enterprise-Neon-Edition/"},
    Blob,Uint8Array,Promise,Map,Date,JSON,String,URL:{
      createObjectURL:()=> "blob:document",revokeObjectURL(){}},
    HTMLAnchorElement:Anchor,
    document:{body:{appendChild(){}},createElement:()=>new Anchor()},
    setTimeout,fetch:async()=>({ok:true,blob:async()=>new Blob(["content"])}),
    btoa:content=>Buffer.from(content,"binary").toString("base64")
  };
  vm.runInNewContext(script,context);
  return window.EdusentiaNativeDownloads;
}

test("Windows host without Tauri IPC still invokes WebView2 Save As from the click", async()=>{
  const events=[];
  let pickerCallCount=0;
  const api=desktop({showSaveFilePicker:options=>{
    pickerCallCount++;events.push("picker:"+options.suggestedName);
    return Promise.resolve({name:options.suggestedName,createWritable:async()=>({
      write:async blob=>{events.push("write:"+await blob.text());},
      close:async()=>events.push("close")
    })});
  }});
  assert.equal(api.supported,true);
  assert.equal(api.windowsHost,true);
  assert.equal(api.windowsPickerAvailable,true);

  const destination=api.prepareSave("staff-id.pdf","application/pdf");
  assert.equal(pickerCallCount,1,"Picker must open before asynchronous PDF generation");
  // Simulates delayed CR80 PDF rendering after the direct click has ended.
  await Promise.resolve();
  const response=await destination.saveBlob(new Blob(["%PDF:staff"],{type:"application/pdf"}));
  assert.equal(response.saved,true);
  assert.equal(response.method,"windows-file-picker");
  assert.deepEqual(events,["picker:staff-id.pdf","write:%PDF:staff","close"]);
});

test("Windows cancellation does not create a file or report download success",async()=>{
  const api=desktop({showSaveFilePicker:()=>Promise.reject(
    Object.assign(new Error("User cancelled"),{name:"AbortError"}))});
  const prepared=api.prepareSave("cards.pdf","application/pdf");
  const result=await prepared.saveBlob(new Blob(["PDF"]));
  assert.equal(result.saved,false);
  assert.equal(result.cancelled,true);
});

test("Windows picker failure falls back to Tauri native command without falsely claiming success",async()=>{
  const calls=[];
  const api=desktop({
    showSaveFilePicker:()=>Promise.reject(Object.assign(
      new Error("Must be handling a user gesture"),{name:"SecurityError"})),
    __TAURI__:{core:{invoke:async(cmd,args)=>{
      calls.push({cmd,args});return {filename:args.filename,path:"C:\\Test\\cards.pdf"};
    }}}
  });
  const result=await api.prepareSave("cards.pdf","application/pdf")
    .saveBlob(new Blob(["%PDF"],{type:"application/pdf"}));
  assert.equal(result.saved,true);
  assert.equal(calls.length,1);
  assert.equal(calls[0].cmd,"save_document");
  assert.equal(calls[0].args.filename,"cards.pdf");
});

test("Windows host with missing picker and missing native IPC fails closed rather than pretending to download",async()=>{
  const api=desktop();
  const result=await api.saveBlob("report.pdf",new Blob(["%PDF"]));
  assert.equal(result.saved,false);
  assert.match(result.message,/Windows Save As is not available/);
  assert.equal(api.supported,true);
});

test("CR80 and A4 ID-card handlers prepare Save As before PDF rendering and await confirmed writes",()=>{
  assert.match(idCardSource,/idPreviewDownload"\)\.onclick=async\(\)=>\{[\s\S]*?prepared=window\.EdusentiaNativeDownloads\?\.prepareSave\(filename,"application\/pdf"\);button\.disabled=true;try\{const result=await downloadBlob\(filename,await createParityIdCardPdf\(card,mode\),prepared\)/);
  assert.match(idCardSource,/idCardPrintButton"\)\.onclick=async\(\)=>\{[\s\S]*?prepared=window\.EdusentiaNativeDownloads\?\.prepareSave\(filename,"application\/pdf"\);button\.disabled=true;[\s\S]*?const result=await downloadBlob\(filename,pdf,prepared\)/);
  assert.match(idCardSource,/if\(!result\?\.saved\)throw new Error\(result\?\.message\|\|"ID card PDF was not saved\."\)/);
  assert.match(idCardSource,/if\(!result\?\.saved\)throw new Error\(result\?\.message\|\|"Printable ID cards were not saved\."\)/);
  assert.match(parity,/function downloadBlob\(name,blob,preparedSave=null\)/);
  assert.match(parity,/return preparedSave\.saveBlob\(blob\)/);
});

test("Windows native shell parents dialogs, injects Windows marker, and retains strict remote permissions",()=>{
  const dev=JSON.parse(fs.readFileSync("native/windows/src-tauri/tauri.conf.json","utf8"));
  const release=JSON.parse(fs.readFileSync("native/windows/src-tauri/tauri.release.template.json","utf8"));
  for (const cfg of [dev,release]){
    assert.equal(cfg.app.windows[0].label,"main");
    assert.equal(cfg.app.withGlobalTauri,true);
    assert.deepEqual(cfg.app.security.capabilities[0].permissions,["allow-save-document"]);
    assert.deepEqual(cfg.app.security.capabilities[0].remote.urls,
      ["https://owusuduahephraim1.github.io/Edusentia-Enterprise-Neon-Edition/*"]);
  }
  assert.match(winSource,/window: tauri::WebviewWindow/);
  assert.match(winSource,/\.set_parent\(&window\)/);
  assert.match(winSource,/\.initialization_script\(r#/);
  assert.match(winSource,/__EDUSENTIA_WINDOWS_DESKTOP__/);
  assert.equal(dev.version,"7.4.2");
});
