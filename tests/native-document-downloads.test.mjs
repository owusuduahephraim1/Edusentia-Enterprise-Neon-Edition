import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const script = fs.readFileSync("frontend/native-document-downloads.js", "utf8");
const origin = {origin:"https://owusuduahephraim1.github.io",
  pathname:"/Edusentia-Enterprise-Neon-Edition/"};

function environment(window, overrides={}) {
  class Link {
    hasAttribute(name) { return name === "download" && !!this.download; }
    click() { this.clicked = true; }
  }
  const context = {
    window, location: origin, Blob, Uint8Array, Date, Promise, JSON, String, Map,
    URL:{createObjectURL:()=> "blob:mock",revokeObjectURL:()=>{}},
    document:{body:{appendChild(){}},createElement:()=>new Link()},
    HTMLAnchorElement:Link, btoa: value=>Buffer.from(value,"binary").toString("base64"),
    atob: value=>Buffer.from(value,"base64").toString("binary"),
    fetch:async()=>({ok:true,blob:async()=>new Blob(["test"])}),
    setTimeout: callback=>{callback();return 0}, ...overrides
  };
  vm.runInNewContext(script,context);
  return {api:window.EdusentiaNativeDownloads,context,Link};
}

test("Android streams the generated file, opens save, and waits for native completion",async()=>{
  const messages=[];
  let listener=()=>{};
  const android={
    addEventListener:(type,handler)=>{assert.equal(type,"message");listener=handler;},
    postMessage: json=>{
      const item=JSON.parse(json);
      messages.push(item);
      if(item.type==="finish") queueMicrotask(()=>listener({data:JSON.stringify({
        id:item.id,status:"saved",filename:"attendance.pdf"
      })}));
    }
  };
  const {api}=environment({EdusentiaAndroidDownloads:android});
  assert.equal(api.supported,true);
  const result=await api.saveBlob("attendance.pdf",new Blob(["%PDF-1.4\nTest"],{type:"application/pdf"}));
  assert.equal(result.saved,true);
  assert.equal(result.filename,"attendance.pdf");
  assert.deepEqual(messages.map(m=>m.type),["begin","chunk","finish"]);
  assert.equal(messages[0].mimeType,"application/pdf");
  assert.equal(Buffer.from(messages[1].data,"base64").toString(),"%PDF-1.4\nTest");
});

test("Android user cancellation is never shown as a successful download",async()=>{
  let listener=()=>{};
  const android={
    addEventListener:(_t,handler)=>{listener=handler},
    postMessage:json=>{
      const item=JSON.parse(json);
      if(item.type==="finish") queueMicrotask(()=>listener({data:JSON.stringify({id:item.id,status:"cancelled"})}));
    }
  };
  const {api}=environment({EdusentiaAndroidDownloads:android});
  const result=await api.saveBlob("report.pdf",new Blob(["data"]));
  assert.equal(result.saved,false);
  assert.equal(result.cancelled,true);
});

test("Windows passes document bytes to the native save command and waits for its result",async()=>{
  let invoked=null;
  const window={__TAURI__:{core:{invoke:async(cmd,args)=>{
    invoked={cmd,args};return {filename:args.filename,path:"C:\\Users\\School\\Documents\\"+args.filename};
  }}}};
  const {api}=environment(window);
  const result=await api.saveBlob("../report.pdf",new Blob(["%PDF"],{type:"application/pdf"}));
  assert.equal(result.saved,true);
  assert.equal(invoked.cmd,"save_document");
  assert.equal(invoked.args.filename,"_report.pdf");
  assert.equal(Buffer.from(invoked.args.dataBase64,"base64").toString(),"%PDF");
});

test("Native save errors and oversized documents cannot report success",async()=>{
  const {api}=environment({__TAURI__:{core:{invoke:async()=>{throw new Error("Disk is full");}}}});
  const error=await api.saveBlob("test.pdf",new Blob(["data"]));
  assert.equal(error.saved,false);
  assert.match(error.message,/Disk is full/);
  const tooLarge={size:64*1024*1024+1,type:"application/pdf"};
  const large=await api.saveBlob("huge.pdf",tooLarge);
  assert.equal(large.saved,false);
});

test("Only the trusted hosted Edusentia origin can activate native filesystem access",()=>{
  let invoked=0;
  const {api}=environment({__TAURI__:{core:{invoke:async()=>{invoked++;}}}},
    {location:{origin:"https://example.com",pathname:"/Edusentia-Enterprise-Neon-Edition/"}});
  assert.equal(api.supported,false);
  assert.equal(invoked,0);
});

test("Native hosts use OS save dialogs with restricted permissions and avoid false success",()=>{
  const android=fs.readFileSync("native/android/app/src/main/java/app/edusentia/enterprise/neon/MainActivity.java","utf8");
  const windows=fs.readFileSync("native/windows/src-tauri/src/lib.rs","utf8");
  const config=JSON.parse(fs.readFileSync("native/windows/src-tauri/tauri.conf.json","utf8"));
  const html=fs.readFileSync("frontend/index.html","utf8");
  const parity=fs.readFileSync("frontend/parity-common.js","utf8");
  const attendance=fs.readFileSync("frontend/tenant-attendance-register-pdf-v1.js","utf8");
  assert.match(android,/WebViewCompat\.addWebMessageListener/);
  assert.match(android,/!isMainFrame/);
  assert.match(android,/Intent\.ACTION_CREATE_DOCUMENT/);
  assert.match(android,/getContentResolver\(\)\.openOutputStream/);
  assert.match(android,/document\.stagingFile/);
  assert.match(windows,/fn save_document/);
  assert.match(windows,/AsyncFileDialog::new\(\)/);
  assert.match(windows,/spawn_blocking/);
  assert.match(windows,/on_download/);
  assert.equal(config.app.withGlobalTauri,true);
  assert.equal(config.app.windows[0].create,false);
  assert.deepEqual(config.app.security.capabilities[0].permissions,["allow-save-document"]);
  assert.match(html,/native-document-downloads\.js/);
  assert.match(parity,/EdusentiaNativeDownloads\.saveBlob/);
  assert.match(attendance,/const result=await P\.downloadBlob\(filename,pdf\)/);
  assert.match(attendance,/if\(!result\?\.saved\)throw new Error/);
});
