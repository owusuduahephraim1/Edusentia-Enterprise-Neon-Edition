(() => {
  "use strict";
  const byId = id => document.getElementById(id);
  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  const api = () => window.EdusentiaApi;
  const turnstileSiteKey = String(window.EDS_MASTER_CONFIG?.turnstileSiteKey || "").trim();
  let turnstileToken = "";
  let turnstileWidgetId = null;

  function resetTurnstile() {
    turnstileToken = "";
    if (window.turnstile && turnstileWidgetId != null) {
      try { window.turnstile.reset(turnstileWidgetId); } catch {}
    }
  }

  function renderTurnstile() {
    if (!turnstileSiteKey || !window.turnstile || turnstileWidgetId != null || !byId("turnstileWidget")) return;
    turnstileWidgetId = window.turnstile.render("#turnstileWidget", {
      sitekey: turnstileSiteKey,
      action: "login",
      theme: "auto",
      size: "flexible",
      callback: token => { turnstileToken = String(token || ""); message(""); },
      "expired-callback": () => { turnstileToken = ""; message("Verification expired. Please verify again.", "error"); },
      "error-callback": () => { turnstileToken = ""; message("Human verification could not be completed. Please try again.", "error"); }
    });
  }
  window.onTurnstileLoad = renderTurnstile;

  function show(view) {
    for (const id of ["loader","authView","appShell","fatalView"]) byId(id)?.classList.add("hidden");
    byId(view)?.classList.remove("hidden");
  }
  function message(text, kind="") {
    const el=byId("authMessage"); if (!el) return; el.textContent=text || ""; el.dataset.kind=kind;
  }
  async function boot() {
    show("loader");
    try {
      const session = await api().session();
      if (!session?.authenticated) { show("authView"); renderTurnstile(); return; }
      await enter(session);
    } catch (error) {
      show("authView"); renderTurnstile();
      if (error?.code !== "unauthenticated") message("The secure API is not reachable yet. Check the Worker configuration.", "error");
    }
  }
  async function enter(session) {
    const data = await api().bootstrap();
    byId("userName").textContent = session.user?.displayName || session.user?.email || "User";
    byId("userRole").textContent = session.membership?.roleLabel || session.membership?.role || "Member";
    byId("tenantName").textContent = data.tenant?.name || "Edusentia Enterprise";
    const cards = [
      ["Students", data.metrics?.students ?? 0], ["Staff", data.metrics?.staff ?? 0],
      ["Classes", data.metrics?.classes ?? 0], ["Subjects", data.metrics?.subjects ?? 0],
      ["Attendance", data.metrics?.attendanceToday ?? 0], ["Pending reports", data.metrics?.pendingReports ?? 0]
    ];
    byId("dashboardCards").innerHTML = cards.map(([k,v]) => `<article class="metric-card"><span>${escapeHtml(k)}</span><strong>${escapeHtml(v)}</strong></article>`).join("");
    show("appShell");
  }
  byId("loginForm")?.addEventListener("submit", async event => {
    event.preventDefault(); message("");
    const fd=new FormData(event.currentTarget); const button=event.currentTarget.querySelector('button[type="submit"]');
    if (turnstileSiteKey && !turnstileToken) { message("Complete the human verification before signing in.", "error"); renderTurnstile(); return; }
    button.disabled=true;
    try {
      const s=await api().login(fd.get("email"),fd.get("password"),fd.get("tenantCode"),turnstileToken);
      turnstileToken="";
      await enter(s);
    }
    catch(error){ message(error.message || "Sign-in failed", "error"); resetTurnstile(); }
    finally { button.disabled=false; }
  });
  byId("logoutButton")?.addEventListener("click", async () => { try { await api().logout(); } finally { location.reload(); } });
  if ('serviceWorker' in navigator) window.addEventListener('load',()=>navigator.serviceWorker.register('./service-worker.js').catch(()=>{}),{once:true});
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, {once:true}); else boot();
})();
