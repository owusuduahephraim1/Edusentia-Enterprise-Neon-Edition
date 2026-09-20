(() => {
  "use strict";
  const cfg = window.EDS_MASTER_CONFIG || {};
  const apiBase = String(cfg.apiBaseUrl || "").replace(/\/+$/, "");

  class ApiError extends Error {
    constructor(message, status, code, details) {
      super(message); this.name = "ApiError"; this.status = status; this.code = code; this.details = details;
    }
  }

  async function request(path, options = {}) {
    if (!apiBase || !/^https:\/\//i.test(apiBase)) throw new ApiError("API is not configured", 0, "api_not_configured");
    const headers = new Headers(options.headers || {});
    if (options.body != null && !(options.body instanceof FormData) && !headers.has("content-type")) headers.set("content-type", "application/json");
    headers.set("accept", "application/json");
    const response = await fetch(`${apiBase}${path}`, {
      ...options,
      headers,
      credentials: "include",
      body: options.body == null || options.body instanceof FormData || typeof options.body === "string"
        ? options.body
        : JSON.stringify(options.body)
    });
    const type = response.headers.get("content-type") || "";
    const payload = type.includes("application/json") ? await response.json().catch(() => ({})) : await response.text();
    if (!response.ok) {
      const err = payload?.error || {};
      throw new ApiError(err.message || `Request failed (${response.status})`, response.status, err.code || "request_failed", err.details);
    }
    return payload;
  }

  window.EdusentiaApi = Object.freeze({
    request,
    health: () => request("/api/health"),
    session: () => request("/api/session"),
    login: (email, password, tenantCode) => request("/api/auth/login", { method: "POST", body: { email, password, tenantCode } }),
    logout: () => request("/api/auth/logout", { method: "POST" }),
    bootstrap: () => request("/api/bootstrap"),
    listStudents: (query = {}) => request(`/api/students?${new URLSearchParams(query)}`),
    createStudent: (payload) => request("/api/students", { method: "POST", body: payload }),
    listStaff: (query = {}) => request(`/api/staff?${new URLSearchParams(query)}`),
    listFinanceSummary: () => request("/api/finance/summary"),
    prepareUpload: (payload) => request("/api/files/upload-url", { method: "POST", body: payload }),
    uploadFile: async (file, kind = "document") => {
      const prepared = await request("/api/files/upload-url", { method: "POST", body: { filename: file.name, contentType: file.type || "application/octet-stream", size: file.size, kind } });
      const response = await fetch(`${apiBase}${prepared.uploadUrl}`, { method: prepared.method || "PUT", credentials: "include", headers: { "content-type": file.type || "application/octet-stream" }, body: file });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) {
        const err = payload?.error || {};
        throw new ApiError(err.message || `Upload failed (${response.status})`, response.status, err.code || "upload_failed", err.details);
      }
      return payload;
    }
  });
})();
