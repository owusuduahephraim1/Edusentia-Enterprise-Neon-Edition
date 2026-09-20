(() => {
  "use strict";

  async function uploadSignedTemplate(instance, authorization, file) {
    const token=String(authorization?.upload_token||"");
    if(/^https:\/\//i.test(token)){
      const response=await fetch(token,{method:"PUT",headers:{"Content-Type":"application/zip"},body:file,redirect:"error"});
      if(!response.ok)throw new Error((await response.text().catch(()=>""))||`Cloudflare R2 upload failed (${response.status})`);
      return;
    }
    const {error}=await instance.storage.from("platform-package-templates").uploadToSignedUrl(authorization.storage_path,authorization.upload_token,file,{contentType:"application/zip"});
    if(error)throw error;
  }
  const BUILD = "7.4.0-r38-cloudflare-r2-template-upload";
  window.RCE_TEMPLATE_UPLOAD_BUILD = BUILD;
  const MAX_BYTES = 48 * 1024 * 1024;

  function notify(title, message, ok = false) {
    const existing = document.getElementById("rceTemplateUploadV37Notice");
    if (existing) existing.remove();
    const box = document.createElement("div");
    box.id = "rceTemplateUploadV37Notice";
    box.setAttribute("role", "status");
    box.style.cssText = `position:fixed;right:20px;bottom:20px;z-index:99999;max-width:430px;padding:14px 16px;border-radius:12px;color:#fff;background:${ok ? "#166534" : "#b4232f"};box-shadow:0 12px 30px rgba(0,0,0,.22);font:600 14px/1.35 system-ui,sans-serif`;
    const strong = document.createElement("div"); strong.textContent = title; strong.style.marginBottom = "4px";
    const text = document.createElement("div"); text.textContent = message; text.style.fontWeight = "500";
    box.append(strong, text); document.body.appendChild(box);
    setTimeout(() => box.remove(), ok ? 7000 : 12000);
  }
  function hex(bytes) { return [...bytes].map(b => b.toString(16).padStart(2, "0")).join(""); }
  async function sha256File(file) {
    const bytes = await file.arrayBuffer();
    return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
  }
  async function edgeError(error, data) {
    if (data?.error) return String(data.error);
    try {
      const response = error?.context;
      if (response && typeof response.clone === "function") {
        const parsed = await response.clone().json();
        if (parsed?.error) return String(parsed.error);
        if (parsed?.message) return String(parsed.message);
      }
    } catch {}
    return error?.message || String(error || "Platform package operation failed");
  }
  function config() {
    const c = window.RCE_CONFIG || window.NIS_CONFIG || {};
    return { url: c.supabaseUrl || "", key: c.supabaseAnonKey || "" };
  }
  async function client() {
    const c = config();
    if (!window.supabase?.createClient || !/^https:\/\//.test(c.url) || !c.key) throw new Error("Supabase client configuration is unavailable.");
    const instance = window.supabase.createClient(c.url, c.key, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } });
    const { data: { session }, error } = await instance.auth.getSession();
    if (error) throw error;
    if (!session?.access_token) throw new Error("Your administrator session is no longer active. Sign in again.");
    return instance;
  }
  async function invoke(instance, action, payload = {}) {
    const { data, error } = await instance.functions.invoke("platform-package-manager", { body: { action, ...payload } });
    if (error) throw new Error(await edgeError(error, data));
    if (!data?.ok) throw new Error(data?.error || "Platform package operation failed");
    return data;
  }
  async function install(button) {
    const input = document.getElementById("platformPackageTemplate");
    const file = input?.files?.[0];
    if (!file) throw new Error("Select the official package template ZIP.");
    if (!file.name.toLowerCase().endsWith(".zip")) throw new Error("Select a ZIP package template.");
    if (file.size < 1000 || file.size > MAX_BYTES) throw new Error("The protected template must be between 1 KB and 48 MB.");
    if (!confirm("Install this protected package template? The server will independently validate the uploaded ZIP before activation.")) return;
    const original = button.textContent;
    button.disabled = true;
    try {
      button.textContent = "Hashing";
      const archive_sha256 = await sha256File(file);
      const instance = await client();
      button.textContent = "Authorizing";
      const authorization = await invoke(instance, "create_template_upload", { filename: file.name, file_size: file.size });
      const serverMax = Number(authorization.max_bytes || MAX_BYTES);
      if (file.size > serverMax) throw new Error(`File exceeds the server maximum of ${serverMax} bytes.`);
      button.textContent = "Uploading";
      await uploadSignedTemplate(instance, authorization, file);
      button.textContent = "Server validating";
      await invoke(instance, "activate_template_upload", { storage_path: authorization.storage_path, filename: file.name, client_validation_receipt: { archive_sha256 } });
      notify("Protected template installed", "Archive SHA-256 matched and the authoritative server ZIP validation passed.", true);
      setTimeout(() => location.reload(), 1000);
    } finally {
      button.disabled = false;
      button.textContent = original || "Install or replace template";
    }
  }
  document.addEventListener("click", async event => {
    const button = event.target?.closest?.("#platformTemplateUpload");
    if (!button) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    try { await install(button); }
    catch (error) { notify("Template not installed", error?.message || String(error)); }
  }, true);
})();
// Pages rebuild marker: r31-template-upload-v37
