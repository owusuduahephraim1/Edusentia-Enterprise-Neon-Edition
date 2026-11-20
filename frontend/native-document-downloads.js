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
  const tauriInvoke = trusted && typeof window.__TAURI__?.core?.invoke === "function"
    ? window.__TAURI__.core.invoke : null;
  const supported = !!(android || tauriInvoke);
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

  async function saveBlob(filename, blob) {
    if (!(blob instanceof Blob)) return {saved: false, message: "No document was generated."};
    if (!blob.size) return {saved: false, message: "The generated document is empty."};
    if (blob.size > MAX_DOCUMENT_BYTES)
      return {saved: false, message: "This document exceeds the 64 MB native export limit. Export a smaller selection."};
    const safe = cleanName(filename);
    if (android) return androidSave(safe, blob);
    if (tauriInvoke) return windowsSave(safe, blob);
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

  window.EdusentiaNativeDownloads = Object.freeze({supported, saveBlob, cleanName});
})();
