/* Cross-platform, origin-limited document save adapter.
   Browser downloads keep their existing path. Android WebView and Windows Tauri
   request an actual native destination and only resolve after the file is written. */
(() => {
  "use strict";
  if (window.EdusentiaNativeDownloads) return;

  const TRUSTED_ORIGIN = "https://owusuduahephraim1.github.io";
  const TRUSTED_PATH = "/Edusentia-Enterprise-Neon-Edition/";
  const MAX_DOCUMENT_BYTES = 64 * 1024 * 1024;
  const CHUNK_BYTES = 24 * 1024;
  const trusted = location.origin === TRUSTED_ORIGIN && location.pathname.startsWith(TRUSTED_PATH);
  const android = trusted && typeof window.EdusentiaAndroidDownloads?.postMessage === "function"
    ? window.EdusentiaAndroidDownloads : null;
  // WebView2 can load a remote service-worker-controlled page without exposing
  // the optional public Tauri global. Detect the native Windows host separately.
  const tauriInvoke = !trusted ? null
    : typeof window.__TAURI__?.core?.invoke === "function"
      ? (command, args) => window.__TAURI__.core.invoke(command, args)
      : typeof window.__TAURI_INTERNALS__?.invoke === "function"
        ? (command, args) => window.__TAURI_INTERNALS__.invoke(command, args)
        : null;
  const windowsHost = trusted && (window.__EDUSENTIA_WINDOWS_DESKTOP__ === true || !!tauriInvoke);
  const windowsPickerAvailable = windowsHost && typeof window.showSaveFilePicker === "function";
  const supported = !!(android || windowsHost);
  const requests = new Map();
  let serial = 0;

  function cleanName(value) {
    const normalized = String(value || "document").replace(/[\\/<>:"|?*\x00-\x1F]/g, "_")
      .replace(/^\.+/, "").trim().slice(0, 140);
    return normalized || "document";
  }

  function encodeBytes(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 8192)
      binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    return btoa(binary);
  }

  if (android) {
    android.addEventListener("message", event => {
      let reply;
      try { reply = JSON.parse(String(event.data)); } catch { return; }
      const request = requests.get(reply.id);
      if (!request) return;
      if (reply.status !== "saved" && reply.status !== "cancelled" && reply.status !== "error") return;
      requests.delete(reply.id);
      request({saved: reply.status === "saved", cancelled: reply.status === "cancelled",
        filename: reply.filename || "", message: reply.message || ""});
    });
  }

  async function androidSave(filename, blob) {
    const id = "eds-" + Date.now().toString(36) + "-" + (++serial).toString(36);
    let complete;
    const result = new Promise(resolve => { complete = resolve; });
    requests.set(id, complete);
    const send = message => android.postMessage(JSON.stringify({id, ...message}));
    try {
      send({type: "begin", filename, mimeType: blob.type || "application/octet-stream", size: blob.size});
      for (let offset = 0; offset < blob.size; offset += CHUNK_BYTES) {
        const bytes = new Uint8Array(await blob.slice(offset, offset + CHUNK_BYTES).arrayBuffer());
        send({type: "chunk", data: encodeBytes(bytes)});
        // Allow the WebView message queue to drain during large PDF / ZIP exports.
        if (offset && offset % (CHUNK_BYTES * 32) === 0)
          await new Promise(resolve => setTimeout(resolve, 0));
      }
      send({type: "finish"});
      return await result;
    } catch (error) {
      requests.delete(id);
      try { send({type: "abort"}); } catch {}
      return {saved: false, message: error?.message || "Android save bridge failed."};
    }
  }

  async function windowsSave(filename, blob) {
    try {
      const dataBase64 = encodeBytes(new Uint8Array(await blob.arrayBuffer()));
      const value = await tauriInvoke("save_document", {
        filename, mimeType: blob.type || "application/octet-stream", dataBase64
      });
      return {saved: true, filename: value?.filename || filename, path: value?.path || ""};
    } catch (error) {
      const message = String(error?.message || error || "Windows document save failed.");
      return {saved: false, cancelled: /cancelled|canceled/i.test(message), message};
    }
  }

  function saveError(error) {
    const message = String(error?.message || error || "Save As could not be completed.");
    return {saved:false, cancelled:error?.name === "AbortError" || /cancelled|canceled/i.test(message), message};
  }

  // Chromium/WebView2's user-approved Save As picker requires a *direct*
  // user gesture. Open it at the start of a click, BEFORE any async PDF
  // rendering or R2 fetch, and write bytes only once the PDF is ready.
  // This also provides a reliable alternative when remote Tauri IPC is blocked.
  function prepareSave(filename, mimeType="application/octet-stream") {
    const safe=cleanName(filename);
    if(!windowsPickerAvailable)return {filename:safe,saveBlob:blob=>saveBlob(safe,blob)};
    let picked;
    try {
      const extension=safe.match(/\.[a-z0-9]{1,12}$/i)?.[0]?.toLowerCase() || "";
      const mime=String(mimeType||"application/octet-stream").split(";")[0];
      const types=extension && /^[\w.+-]+\/[\w.+-]+$/.test(mime)
        ? [{description:"Edusentia document",accept:{[mime]:[extension]}}] : [];
      picked=window.showSaveFilePicker({suggestedName:safe,...(types.length?{types}:{})});
    } catch (error) {
      picked=Promise.reject(error);
    }
    // Prevent an unhandled rejection if PDF preparation later fails.
    picked.catch(()=>{});
    let used=false;
    return {filename:safe,async saveBlob(blob){
      if(used)return {saved:false,message:"This Save As request has already been used."};
      used=true;
      if(!(blob instanceof Blob)||!blob.size)return {saved:false,message:"No document was generated."};
      if(blob.size>MAX_DOCUMENT_BYTES)return {saved:false,message:"This document exceeds the 64 MB native export limit."};
      try {
        const handle=await picked;
        const writer=await handle.createWritable();
        try {
          await writer.write(blob);
          await writer.close();
        } catch(error) {
          try{await writer.abort();}catch{}
          throw error;
        }
        return {saved:true,filename:handle.name || safe,method:"windows-file-picker"};
      } catch(error) {
        const result=saveError(error);
        // A blocked/unsupported WebView2 picker may fall back to the
        // origin-scoped Tauri native command, which has no gesture requirement.
        if(!result.cancelled && tauriInvoke && /SecurityError|NotAllowedError|NotSupportedError|user gesture|permission|not supported/i.test(
          error?.name+" "+result.message)) return windowsSave(safe,blob);
        return result;
      }
    }};
  }

  async function saveBlob(filename, blob) {
    if (!(blob instanceof Blob)) return {saved: false, message: "No document was generated."};
    if (!blob.size) return {saved: false, message: "The generated document is empty."};
    if (blob.size > MAX_DOCUMENT_BYTES)
      return {saved: false, message: "This document exceeds the 64 MB native export limit. Export a smaller selection."};
    const safe = cleanName(filename);
    if (android) return androidSave(safe, blob);
    if (windowsHost) {
      if (windowsPickerAvailable) return prepareSave(safe,blob.type).saveBlob(blob);
      if (tauriInvoke) return windowsSave(safe, blob);
      return {saved:false,message:"Windows Save As is not available in this application. Install the updated Edusentia Windows application."};
    }
    const url = URL.createObjectURL(blob), link = document.createElement("a");
    link.href = url;
    link.download = safe;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 15000);
    return {saved: true, initiated: true, filename: safe};
  }

  // Also handle older modules that use object-URL anchors rather than the
  // shared downloadBlob function, including exports made by detached anchors.
  if (supported) {
    const click = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function() {
      const url = this.href || "";
      if (this.hasAttribute("download") && /^(blob:|data:)/i.test(url)) {
        const filename = this.download || "document";
        fetch(url).then(response => {
          if (!response.ok) throw new Error("Unable to read the generated document.");
          return response.blob();
        }).then(blob => saveBlob(filename, blob)).then(result => {
          if (!result.saved && !result.cancelled)
            window.alert(result.message || "The document could not be saved.");
        }).catch(error => window.alert(error?.message || "Unable to save document."));
        return;
      }
      return click.apply(this, arguments);
    };
  }

  window.EdusentiaNativeDownloads = Object.freeze({
    supported, windowsHost, windowsPickerAvailable, prepareSave, saveBlob, cleanName
  });
})();
