(() => {
  "use strict";
  if (window.EDS_ACCOUNTANT_DASHBOARD_V1) return;
  window.EDS_ACCOUNTANT_DASHBOARD_V1 = true;

  let rendering = false;
  let restoreTimer = 0;
  let installed = false;
  let authBound = false;

  const byId = (id) => document.getElementById(id);
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const F = () => window.EdusentiaFinanceRuntime || null;
  const esc = (value) => F()?.esc ? F().esc(value) : String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const money = (value) => F()?.money ? F().money(value) : `GHS ${Number(value || 0).toFixed(2)}`;
  const date = (value) => F()?.date ? F().date(value) : (value ? new Date(value).toLocaleDateString("en-GH") : "—");
  const statusLabel = (value) => F()?.statusLabel ? F().statusLabel(value) : String(value || "").replaceAll("_", " ");
  const statusClass = (value) => F()?.statusClass ? F().statusClass(value) : "draft";

  async function waitForRuntime() {
    for (let i = 0; i < 240; i += 1) {
      const runtime = F();
      if (runtime?.S?.client && runtime?.S?.boot && runtime.S.role) return runtime;
      await sleep(100);
    }
    return null;
  }

  function isAccountant() {
    return ["accountant","accounts_office"].includes(String(F()?.S?.role || ""));
  }

  function dashboardButton() {
    return byId("mainNav")?.querySelector('[data-view="dashboard"]') || null;
  }

  function dashboardIsActive() {
    return Boolean(dashboardButton()?.classList.contains("active"));
  }

  function currentPeriod() {
    const runtime = F();
    const boot = runtime?.S?.boot || {};
    const year = (boot.academic_years || []).find((x) => String(x.id) === String(runtime?.S?.yearId))
      || (boot.academic_years || []).find((x) => x.is_active)
      || (boot.academic_years || [])[0];
    const term = (boot.terms || []).find((x) => String(x.id) === String(runtime?.S?.termId))
      || (boot.terms || []).find((x) => x.is_active)
      || (boot.terms || []).find((x) => !year?.id || String(x.academic_year_id) === String(year.id));
    return { year, term };
  }

  function setDashboardActive() {
    const nav = byId("mainNav");
    nav?.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
    dashboardButton()?.classList.add("active");
    if (F()?.S) F().S.active = false;
  }

  function quickAction(id, label, tab, primary = false) {
    return `<button class="button ${primary ? "primary" : "secondary"}" id="${id}" type="button" data-finance-target="${tab}">${esc(label)}</button>`;
  }

  function metric(label, value) {
    return `<div class="finance-metric"><span>${esc(label)}</span><strong>${esc(value)}</strong></div>`;
  }

  function paymentsTable(rows) {
    return `<div class="finance-table-scroll small"><table><thead><tr><th>Receipt</th><th>Student</th><th>Class</th><th>Paid</th><th>Balance</th><th>Method</th><th>Date</th></tr></thead><tbody>${rows.length ? rows.map((row) => `<tr><td><strong>${esc(row.receipt_no || "—")}</strong></td><td><strong>${esc(row.student || "")}</strong><small>${esc(row.admission_no || "")}</small></td><td>${esc(row.class_name || "")}</td><td>${esc(money(row.transaction_amount))}</td><td>${esc(money(row.balance))}</td><td>${esc(statusLabel(row.method || "—"))}</td><td>${esc(date(row.transaction_date))}</td></tr>`).join("") : '<tr><td colspan="7"><div class="empty"><strong>No fee payments recorded yet</strong><span>Posted payments will appear here.</span></div></td></tr>'}</tbody></table></div>`;
  }

  function outstandingTable(rows) {
    const outstanding = rows
      .filter((row) => Number(row.balance || 0) > 0)
      .sort((a, b) => Number(b.balance || 0) - Number(a.balance || 0))
      .slice(0, 8);
    return `<div class="finance-table-scroll small"><table><thead><tr><th>Student</th><th>Class</th><th>Due</th><th>Paid</th><th>Balance</th><th>Status</th></tr></thead><tbody>${outstanding.length ? outstanding.map((row) => `<tr><td><strong>${esc(row.student || "")}</strong><small>${esc(row.admission_no || "")}</small></td><td>${esc(row.class_name || "")}</td><td>${esc(money(row.due))}</td><td>${esc(money(row.paid))}</td><td><strong>${esc(money(row.balance))}</strong></td><td><span class="status ${statusClass(row.status)}">${esc(statusLabel(row.status))}</span></td></tr>`).join("") : '<tr><td colspan="6"><div class="empty"><strong>No outstanding balances</strong></div></td></tr>'}</tbody></table></div>`;
  }

  async function openFinance(tab) {
    const runtime = F();
    if (!runtime) return;
    runtime.S.tab = tab;
    const finance = byId("mainNav")?.querySelector(".accountant-finance-nav-item");
    if (finance) finance.click();
    else await runtime.open?.();
  }

  async function renderAccountantDashboard() {
    if (!isAccountant() || rendering) return;
    const runtime = F(), content = byId("content");
    if (!runtime || !content) return;
    rendering = true;
    setDashboardActive();
    runtime.heading?.("Dashboard", "Finance operations overview");
    content.innerHTML = '<div data-accountant-dashboard-loading="1" class="panel pad"><div class="skeleton"></div></div>';
    try {
      const yearId = runtime.S.yearId || null;
      const termId = runtime.S.termId || null;
      const [consoleData, paymentData] = await Promise.all([
        runtime.rpc("finance_accounts_console", { target_academic_year_id: yearId, target_term_id: termId, target_class_id: null }),
        runtime.rpc("finance_payment_register", { target_academic_year_id: yearId, target_term_id: termId, target_class_id: null })
      ]);
      if (!isAccountant() || !dashboardIsActive()) return;
      const metrics = consoleData?.metrics || {};
      const statements = consoleData?.statements || [];
      const payments = paymentData?.rows || [];
      const { year, term } = currentPeriod();
      const profile = runtime.S.boot?.profile || {};
      const accountName = profile.full_name || profile.name || "Accountant";
      const planName = runtime.S.boot?.license?.plan?.name || runtime.S.boot?.license?.plan?.code || "Current plan";
      const payrollEnabled = runtime.hasFeature?.("payroll") === true;

      byId("pageTitle").textContent = "Accountant Dashboard";
      byId("pageSubtitle").textContent = "Fees, collections, balances and finance operations";
      content.innerHTML = `<div data-accountant-dashboard-root="1" class="finance-workspace">
        <div class="page-head"><div><h3>Accountant Dashboard</h3><p>Finance operations overview for ${esc(accountName)}</p></div><div class="button-row">${quickAction("accountantDashAddPayment", "Add fee payment", "payments", true)}${quickAction("accountantDashStatements", "Fee statements", "statements")}${quickAction("accountantDashSettings", "Term fee settings", "settings")}${payrollEnabled ? quickAction("accountantDashPayroll", "Payroll", "payroll") : ""}</div></div>
        <section class="panel pad"><div class="finance-readonly-grid"><div><span>Academic year</span><strong>${esc(year?.name || "Not set")}</strong></div><div><span>Term</span><strong>${esc(term?.name || "Not set")}</strong></div><div><span>Licence plan</span><strong>${esc(String(planName))}</strong></div><div><span>Finance role</span><strong>Accountant</strong></div></div></section>
        <div class="finance-metrics">${metric("Expected fees", money(metrics.expected))}${metric("Collected", money(metrics.collected))}${metric("Outstanding", money(metrics.outstanding))}${metric("Fully paid", String(metrics.fully_paid || 0))}${metric("Partially paid", String(metrics.partial_paid || 0))}${metric("Unpaid", String(metrics.unpaid || 0))}</div>
        <div class="grid two">
          <section class="panel"><div class="panel-header"><div><h3>Recent fee payments</h3><p>Latest posted receipts for the selected academic period</p></div><button class="button ghost small" id="accountantDashAllPayments" type="button">View payments</button></div>${paymentsTable(payments.slice(0, 8))}</section>
          <section class="panel"><div class="panel-header"><div><h3>Outstanding fee accounts</h3><p>Highest balances requiring Accounts Office attention</p></div><button class="button ghost small" id="accountantDashAllStatements" type="button">View statements</button></div>${outstandingTable(statements)}</section>
        </div>
      </div>`;

      byId("accountantDashAddPayment")?.addEventListener("click", () => openFinance("payments"));
      byId("accountantDashStatements")?.addEventListener("click", () => openFinance("statements"));
      byId("accountantDashSettings")?.addEventListener("click", () => openFinance("settings"));
      byId("accountantDashPayroll")?.addEventListener("click", () => openFinance("payroll"));
      byId("accountantDashAllPayments")?.addEventListener("click", () => openFinance("payments"));
      byId("accountantDashAllStatements")?.addEventListener("click", () => openFinance("statements"));
    } catch (error) {
      if (!dashboardIsActive()) return;
      content.innerHTML = `<section class="panel pad"><strong>Accountant Dashboard could not be loaded</strong><p>${esc(runtime.friendly?.(error) || String(error))}</p><button class="button secondary" id="accountantDashboardRetry" type="button">Retry</button></section>`;
      byId("accountantDashboardRetry")?.addEventListener("click", renderAccountantDashboard);
    } finally {
      rendering = false;
    }
  }

  function scheduleRestore() {
    if (!isAccountant() || !dashboardIsActive() || rendering) return;
    clearTimeout(restoreTimer);
    restoreTimer = setTimeout(() => {
      if (!isAccountant() || !dashboardIsActive() || rendering) return;
      const root = byId("content")?.querySelector('[data-accountant-dashboard-root="1"], [data-accountant-dashboard-loading="1"]');
      if (!root) void renderAccountantDashboard();
    }, 80);
  }

  async function install() {
    if (installed) return;
    const runtime = await waitForRuntime();
    if (!runtime) return;
    if (!authBound && runtime.S?.client?.auth?.onAuthStateChange) {
      authBound = true;
      runtime.S.client.auth.onAuthStateChange(() => {
        setTimeout(() => { if (!installed && isAccountant()) void install(); }, 200);
        setTimeout(() => { if (!installed && isAccountant()) void install(); }, 800);
      });
    }
    if (!["accountant","accounts_office"].includes(String(runtime.S.role || ""))) return;
    const nav = byId("mainNav"), content = byId("content"), title = byId("pageTitle");
    if (!nav || !content) return;
    installed = true;

    nav.addEventListener("click", (event) => {
      const target = event.target.closest?.('[data-view="dashboard"]');
      if (!target || !isAccountant()) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      void renderAccountantDashboard();
    }, true);

    const observer = new MutationObserver(scheduleRestore);
    observer.observe(content, { childList: true });
    if (title) observer.observe(title, { childList: true, characterData: true, subtree: true });

    // Replace the legacy fallback dashboard immediately if it is currently visible.
    const currentText = String(content.textContent || "");
    if (dashboardIsActive() || /Parent and Guardian Dashboard/i.test(currentText)) {
      void renderAccountantDashboard();
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => void install(), { once: true });
  else void install();
})();
