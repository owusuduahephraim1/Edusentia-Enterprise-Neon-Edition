(() => {
  "use strict";
  if (window.EDS_STUDENT_PORTAL_V2) return;
  window.EDS_STUDENT_PORTAL_V2 = true;
  window.EDS_STUDENT_PORTAL_V1 = true;

  const MODULES = Object.freeze([
    ["overview", "Overview", "▦", "Academic and school account overview"],
    ["results", "Results", "✓", "Published grades and teacher comments"],
    ["fees", "Fees", "₵", "Balances, payments and fee statements"],
    ["timetable", "Timetable", "▤", "Your class teaching schedule"],
    ["attendance", "Attendance", "◎", "Current and previous term attendance"],
    ["notifications", "Notifications", "◆", "School and workflow alerts"],
    ["profile", "Profile", "●", "Student, guardian and account details"],
  ]);
  const DAYS = Object.freeze(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]);
  const state = { data: null, module: "overview", notifications: null, rendering: false, navTimer: 0 };

  const F = () => window.EdusentiaFinanceRuntime || null;
  const byId = (id) => document.getElementById(id);
  const esc = (value) => F()?.esc ? F().esc(value) : String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const attr = esc;
  const money = (value) => F()?.money ? F().money(value) : `GHS ${Number(value || 0).toFixed(2)}`;
  const friendly = (error) => F()?.friendly?.(error) || String(error?.message || error || "Request failed");
  const notify = (title, message = "", kind = "info") => F()?.notify?.(title, message, kind);
  const num = (value, digits = 0) => Number(value || 0).toLocaleString("en-GH", { minimumFractionDigits: digits, maximumFractionDigits: digits });
  const moduleMeta = (key = state.module) => MODULES.find(([id]) => id === key) || MODULES[0];

  async function waitForRuntime() {
    for (let i = 0; i < 240; i += 1) {
      const runtime = F();
      if (runtime?.S?.client && runtime?.S?.boot) return runtime;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return null;
  }

  function currentRole() { return String(F()?.S?.role || F()?.S?.boot?.profile?.role || ""); }
  function formatDate(value) {
    if (!value) return "—";
    const d = new Date(value); if (Number.isNaN(d.getTime())) return String(value);
    return d.toLocaleDateString("en-GH", { year: "numeric", month: "short", day: "numeric" });
  }
  function formatDateTime(value) {
    if (!value) return "—";
    const d = new Date(value); if (Number.isNaN(d.getTime())) return String(value);
    return d.toLocaleString("en-GH", { year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
  }
  function time(value) { return String(value || "").slice(0, 5) || "—"; }

  function installStyles() {
    if (byId("edsStudentPortalStyleV2")) return;
    const style = document.createElement("style");
    style.id = "edsStudentPortalStyleV2";
    style.textContent = `
      .student-module-nav-item{display:flex!important}.student-module-nav-item .student-nav-badge{margin-left:auto;min-width:20px;height:20px;padding:0 6px;border-radius:999px;display:none;place-items:center;background:#dfeaff;color:#0b4da3;font-size:10px;font-weight:900}.student-module-nav-item.has-badge .student-nav-badge{display:grid}
      .student-portal-tabs{display:none!important}.student-portal-workspace{display:grid;gap:16px;min-width:0}.student-portal-hero{position:relative;overflow:hidden;display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:16px;align-items:center;padding:20px 22px;border:1px solid var(--line,#d8e1ef);border-radius:18px;background:linear-gradient(135deg,rgba(13,72,150,.08),rgba(255,255,255,.96) 44%,rgba(218,167,39,.08))}.student-portal-hero:after{content:"";position:absolute;width:220px;height:220px;border-radius:50%;right:-80px;top:-130px;background:rgba(32,120,210,.06);pointer-events:none}.student-portal-avatar{width:64px;height:64px;border-radius:18px;display:grid;place-items:center;background:#0b4da3;color:#fff;font-size:27px;font-weight:900;box-shadow:0 10px 28px rgba(11,77,163,.18)}.student-portal-hero-copy{min-width:0}.student-portal-hero-copy h3{margin:0 0 4px;font-size:22px;line-height:1.2}.student-portal-hero-copy p{margin:0;color:var(--muted,#64748b);font-size:13px}.student-portal-hero-meta{display:flex;gap:7px;flex-wrap:wrap;margin-top:9px}.student-portal-chip{display:inline-flex;align-items:center;min-height:27px;padding:0 9px;border:1px solid var(--line,#d8e1ef);border-radius:999px;background:rgba(255,255,255,.8);font-size:11px;font-weight:700;color:#42536a}.student-portal-period{text-align:right;position:relative;z-index:1}.student-portal-period strong{display:block;font-size:13px}.student-portal-period span{display:block;color:var(--muted,#64748b);font-size:11px;margin-top:4px}
      .student-portal-metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.student-portal-metric{border:1px solid var(--line,#d8e1ef);border-radius:15px;background:var(--surface,#fff);padding:15px 16px}.student-portal-metric span{display:block;color:var(--muted,#64748b);font-size:11px;font-weight:700;margin-bottom:6px}.student-portal-metric strong{display:block;font-size:21px}.student-portal-metric small{display:block;color:var(--muted,#64748b);font-size:10px;margin-top:5px}.student-portal-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.student-portal-panel{border:1px solid var(--line,#d8e1ef);border-radius:16px;background:var(--surface,#fff);min-width:0;overflow:hidden}.student-portal-panel-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;padding:15px 16px;border-bottom:1px solid var(--line,#d8e1ef)}.student-portal-panel-head h4{margin:0 0 3px;font-size:14px}.student-portal-panel-head p{margin:0;color:var(--muted,#64748b);font-size:11px}.student-portal-panel-body{padding:15px 16px}.student-portal-actions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.student-portal-action{border:1px solid var(--line,#d8e1ef);background:#f8fbff;border-radius:13px;padding:13px;text-align:left;cursor:pointer;color:inherit}.student-portal-action strong{display:block;font-size:12px}.student-portal-action span{display:block;color:var(--muted,#64748b);font-size:10px;margin-top:3px}.student-portal-banner{border:1px solid #ead8ad;border-radius:13px;background:#fff8e9;padding:12px 14px}.student-portal-banner strong{display:block;font-size:12px}.student-portal-banner span{display:block;font-size:11px;color:#6e5a31;margin-top:3px}.student-portal-empty{padding:28px 20px;text-align:center;color:var(--muted,#64748b)}.student-portal-empty strong{display:block;margin-bottom:5px}.student-portal-empty span{display:block;font-size:11px}.student-portal-table-scroll{overflow:auto;max-width:100%}.student-portal-table-scroll table{width:100%;border-collapse:collapse}.student-portal-table-scroll th,.student-portal-table-scroll td{padding:10px 11px;border-bottom:1px solid var(--line,#e2e8f0);text-align:left;font-size:11px;vertical-align:top}.student-portal-table-scroll th{position:sticky;top:0;background:#f4f7fb;color:#53647a;font-size:10px;text-transform:uppercase;z-index:1}.student-portal-result-list{display:grid;gap:10px}.student-portal-result-card{display:grid;grid-template-columns:minmax(0,1fr) auto auto;gap:12px;align-items:center;border:1px solid var(--line,#d8e1ef);border-radius:13px;padding:12px 13px}.student-portal-result-card h4{margin:0 0 3px;font-size:13px}.student-portal-result-card p{margin:0;color:var(--muted,#64748b);font-size:10px}.student-portal-result-score{text-align:right}.student-portal-result-score strong{display:block;font-size:17px}.student-portal-result-score span{font-size:9px;color:var(--muted,#64748b)}.student-portal-week{display:grid;grid-template-columns:repeat(5,minmax(210px,1fr));gap:10px;overflow:auto}.student-portal-day{border:1px solid var(--line,#d8e1ef);border-radius:14px;background:var(--surface,#fff);min-width:210px;overflow:hidden}.student-portal-day-head{padding:11px 12px;background:#f4f7fb;border-bottom:1px solid var(--line,#d8e1ef)}.student-portal-period-row{display:grid;grid-template-columns:58px minmax(0,1fr);gap:9px;padding:10px 11px;border-bottom:1px solid var(--line,#e2e8f0)}.student-portal-period-time{font-size:9px;font-weight:800;color:#36506e}.student-portal-period-copy strong{display:block;font-size:11px}.student-portal-period-copy span{display:block;color:var(--muted,#64748b);font-size:9px;margin-top:2px}.student-portal-attendance-cards{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}.student-portal-attendance-card{border:1px solid var(--line,#d8e1ef);border-radius:13px;padding:12px;background:var(--surface,#fff)}.student-portal-attendance-card span{display:block;color:var(--muted,#64748b);font-size:10px}.student-portal-attendance-card strong{display:block;font-size:19px;margin-top:4px}.student-portal-notifications{display:grid;gap:8px}.student-portal-notification{display:grid;grid-template-columns:8px minmax(0,1fr) auto;gap:10px;border:1px solid var(--line,#d8e1ef);border-radius:13px;padding:11px 12px}.student-portal-notification-dot{width:8px;height:8px;border-radius:50%;background:#c7d1df;margin-top:5px}.student-portal-notification.unread .student-portal-notification-dot{background:#0b69c7}.student-portal-notification-copy strong{display:block;font-size:11px}.student-portal-notification-copy p{margin:3px 0 0;color:var(--muted,#64748b);font-size:10px}.student-portal-notification-copy small{display:block;color:#7a8798;font-size:9px;margin-top:5px}.student-portal-profile-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.student-portal-profile-card{border:1px solid var(--line,#d8e1ef);border-radius:14px;padding:14px;background:var(--surface,#fff)}.student-portal-profile-card h4{margin:0 0 10px;font-size:13px}.student-portal-detail{display:grid;grid-template-columns:minmax(110px,.45fr) minmax(0,1fr);gap:8px;padding:7px 0;border-bottom:1px solid var(--line,#edf1f6);font-size:10px}.student-portal-detail span{color:var(--muted,#64748b)}.student-portal-status{display:inline-flex;align-items:center;min-height:24px;padding:0 8px;border-radius:999px;font-size:9px;font-weight:800;background:#edf2f8;color:#465a73}.student-portal-status.good{background:#e7f7ef;color:#15714a}.student-portal-status.warn{background:#fff3d8;color:#805d10}.student-portal-status.bad{background:#fdeaea;color:#9a2f37}.student-portal-modal-summary{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-bottom:12px}.student-portal-modal-summary>div{border:1px solid var(--line,#d8e1ef);border-radius:12px;padding:11px}
      @media(max-width:1050px){.student-portal-metrics{grid-template-columns:repeat(2,minmax(0,1fr))}.student-portal-actions{grid-template-columns:repeat(2,minmax(0,1fr))}.student-portal-attendance-cards{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:760px){.student-portal-hero{grid-template-columns:auto minmax(0,1fr);padding:16px}.student-portal-period{grid-column:1/-1;text-align:left}.student-portal-grid,.student-portal-profile-grid{grid-template-columns:1fr}.student-portal-attendance-cards{grid-template-columns:repeat(2,minmax(0,1fr))}.student-portal-actions{grid-template-columns:1fr 1fr}}@media(max-width:520px){.student-portal-metrics,.student-portal-actions,.student-portal-attendance-cards{grid-template-columns:1fr}.student-portal-detail{grid-template-columns:1fr}.student-portal-notification{grid-template-columns:8px minmax(0,1fr)}}
    `;
    document.head.appendChild(style);
  }

  function setNavActive() {
    const nav = byId("mainNav"); if (!nav) return;
    nav.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
    nav.querySelector(`[data-student-module="${state.module}"]`)?.classList.add("active");
  }

  function updateNotificationBadge() {
    const button = byId("mainNav")?.querySelector('[data-student-module="notifications"]');
    if (!button) return;
    const unread = Number(state.data?.notifications?.unread || state.notifications?.unread || 0);
    button.classList.toggle("has-badge", unread > 0);
    const badge = button.querySelector(".student-nav-badge"); if (badge) badge.textContent = unread > 99 ? "99+" : String(unread);
  }

  async function openModule(module) {
    if (!MODULES.some(([key]) => key === module)) module = "overview";
    state.module = module;
    setNavActive(); updateHeading();
    if (!state.data) {
      const runtime = await waitForRuntime(); if (!runtime) return;
      runtime.S.active = true; await runtime.open(); return;
    }
    await renderActiveModule();
    byId("studentPortalModuleContent")?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }

  function ensureNav() {
    if (currentRole() !== "student") return false;
    const nav = byId("mainNav"); if (!nav) return false;
    nav.querySelectorAll(".nav-item:not(.student-module-nav-item)").forEach((item) => {
      if (item.style.display !== "none") item.style.display = "none";
      if (item.getAttribute("aria-hidden") !== "true") item.setAttribute("aria-hidden", "true");
      if (item.tabIndex !== -1) item.tabIndex = -1;
    });
    nav.querySelectorAll(".student-portal-nav-item").forEach((item) => item.remove());
    for (const [key, label, icon] of MODULES) {
      let button = nav.querySelector(`[data-student-module="${key}"]`);
      if (!button) {
        button = document.createElement("button"); button.type = "button"; button.className = "nav-item student-module-nav-item"; button.dataset.studentModule = key;
        button.innerHTML = `<span class="nav-icon">${esc(icon)}</span><span class="nav-label">${esc(label)}</span>${key === "notifications" ? '<span class="student-nav-badge" aria-label="Unread notifications">0</span>' : ''}<span class="nav-active-dot"></span>`;
        button.addEventListener("click", () => openModule(key)); nav.appendChild(button);
      }
    }
    setNavActive(); updateNotificationBadge(); return true;
  }
  function scheduleNav() { clearTimeout(state.navTimer); state.navTimer = setTimeout(ensureNav, 50); }
  function updateHeading() { const [, label,, subtitle] = moduleMeta(); F()?.heading?.(label === "Overview" ? "Student Portal" : label, subtitle); }
  function featureUnavailable(title, description) { return `<section class="student-portal-panel"><div class="student-portal-empty"><strong>${esc(title)}</strong><span>${esc(description)}</span></div></section>`; }
  function holdBanner(data) { return data?.financial_hold?.locked ? `<div class="student-portal-banner"><strong>Financial clearance restriction active</strong><span>${esc(data.financial_hold.reason || "Contact the Accounts Office for clearance details.")}</span></div>` : ""; }

  function heroHtml(data) {
    const s = data.student || {}, initial = String(s.first_name || s.full_name || "S").trim().slice(0,1).toUpperCase();
    const meta = [s.admission_no, s.class_name, s.roll_number ? `Roll ${s.roll_number}` : "", s.class_teacher ? `Class teacher: ${s.class_teacher}` : ""].filter(Boolean);
    return `<section class="student-portal-hero"><div class="student-portal-avatar">${esc(initial)}</div><div class="student-portal-hero-copy"><h3>${esc(s.full_name || "Student")}</h3><p>Your secure academic and school account workspace</p><div class="student-portal-hero-meta">${meta.map(v => `<span class="student-portal-chip">${esc(v)}</span>`).join("")}</div></div><div class="student-portal-period"><strong>${esc(s.academic_year_name || "Academic year")}</strong><span>${esc(s.term_name || "Current term")}</span></div></section>`;
  }

  function overviewHtml(data) {
    const s=data.student||{}, fees=data.fee_statement||{}, att=data.attendance?.current||{}, n=data.notifications||{}, finance=data.features?.finance===true, attendance=data.features?.attendance===true, latest=(data.reports||[])[0];
    return `${holdBanner(data)}<div class="student-portal-metrics"><div class="student-portal-metric"><span>Attendance</span><strong>${attendance?`${num(att.percentage,1)}%`:"Not enabled"}</strong><small>${attendance?`${num(att.days_present)} of ${num(att.days_opened)} school days`:"Attendance module is not enabled."}</small></div><div class="student-portal-metric"><span>Current class</span><strong>${esc(s.class_name||"—")}</strong><small>Current active enrollment</small></div><div class="student-portal-metric"><span>Outstanding fees</span><strong>${finance?esc(money(fees.outstanding||0)):"Not enabled"}</strong><small>${finance?"Live Accounts Office balance":"Finance statements are not enabled."}</small></div><div class="student-portal-metric"><span>Unread notifications</span><strong>${num(n.unread||0)}</strong><small>${num(n.total||0)} total notifications</small></div></div><div class="student-portal-grid"><section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Quick access</h4><p>Open the records you use most often.</p></div></div><div class="student-portal-panel-body"><div class="student-portal-actions">${MODULES.filter(([k])=>k!=="overview").map(([k,l,,copy])=>`<button type="button" class="student-portal-action" data-student-module-action="${k}"><strong>${esc(l)}</strong><span>${esc(copy)}</span></button>`).join("")}</div></div></section><section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Latest published result</h4><p>Your most recent published academic record.</p></div>${latest?`<button class="button ghost small" data-student-result="${attr(latest.id)}">View result</button>`:""}</div><div class="student-portal-panel-body">${latest?`<div class="student-portal-result-card" style="grid-template-columns:minmax(0,1fr) auto"><div><h4>${esc(latest.academic_year_name)} • ${esc(latest.term_name)}</h4><p>${esc(latest.report_number||"Published report")}</p></div><div class="student-portal-result-score"><strong>${latest.locked?"—":`${num(latest.average,1)}%`}</strong><span>${latest.locked?"Restricted":"Average"}</span></div></div>`:`<div class="student-portal-empty"><strong>No published results yet</strong><span>Published term results will appear automatically.</span></div>`}</div></section></div>`;
  }

  function resultsHtml(data) {
    const rows=data.reports||[]; return `<section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Published Academic Results</h4><p>Read-only school records by academic year and term.</p></div></div><div class="student-portal-panel-body"><div class="student-portal-result-list">${rows.length?rows.map(r=>`<article class="student-portal-result-card"><div><h4>${esc(r.academic_year_name)} • ${esc(r.term_name)}</h4><p>${esc(r.report_number||"Published report")} • Published ${formatDate(r.published_at)}</p></div><div class="student-portal-result-score"><strong>${r.locked?"—":`${num(r.average,1)}%`}</strong><span>${r.locked?"Restricted":"Average"}</span></div><button class="button ${r.locked?"ghost":"primary"} small" data-student-result="${attr(r.id)}">${r.locked?"View status":"View grades"}</button></article>`).join(""):`<div class="student-portal-empty"><strong>No published academic results</strong><span>Results appear after the school publishes them.</span></div>`}</div></div></section>`;
  }

  function feesHtml(data) {
    if(data.features?.finance!==true)return featureUnavailable("Fee statements are not enabled","Your school plan does not currently expose finance statements in the Student Portal.");
    const s=data.fee_statement||{},accounts=s.accounts||[],payments=s.payments||[];
    return `${holdBanner(data)}<div class="student-portal-metrics" style="grid-template-columns:repeat(2,minmax(0,1fr))"><div class="student-portal-metric"><span>Outstanding balance</span><strong>${esc(money(s.outstanding||0))}</strong><small>Live balance from the Accounts Office ledger</small></div><div class="student-portal-metric"><span>Financial clearance</span><strong>${s.hold?.locked?"Restricted":"Clear"}</strong><small>${esc(s.hold?.reason||"No active finance restriction")}</small></div></div><section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Fee Statement</h4><p>Term fees, payments and current balances.</p></div><div class="button-row"><button class="button secondary small" id="studentPortalPrintFees">Full statement</button><button class="button ghost small" id="studentPortalPrintFeeSummary">A6 summary</button></div></div><div class="student-portal-table-scroll"><table><thead><tr><th>Academic Year</th><th>Term</th><th>Class</th><th>Term Fee</th><th>Paid</th><th>Balance</th><th>Status</th></tr></thead><tbody>${accounts.length?accounts.map(r=>`<tr><td>${esc(r.academic_year_name||"")}</td><td>${esc(r.term_name||"")}</td><td>${esc(r.class_name||"")}</td><td>${esc(money(r.term_fee||0))}</td><td>${esc(money(r.paid||0))}</td><td>${esc(money(r.balance||0))}</td><td><span class="student-portal-status ${r.status==="fully_paid"?"good":r.status==="partial_paid"?"warn":"bad"}">${esc(F()?.statusLabel?.(r.status)||String(r.status||"").replaceAll("_"," "))}</span></td></tr>`).join(""):'<tr><td colspan="7">No fee obligations are recorded.</td></tr>'}</tbody></table></div></section><section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Payment History & Receipts</h4><p>Posted payments from the school finance ledger.</p></div></div><div class="student-portal-table-scroll"><table><thead><tr><th>Receipt</th><th>Date</th><th>Amount</th><th>Method</th><th>Reference</th><th>Status</th></tr></thead><tbody>${payments.length?payments.map(r=>`<tr><td><strong>${esc(r.receipt_no||"—")}</strong></td><td>${formatDate(r.transaction_date)}</td><td>${esc(money(r.amount||0))}</td><td>${esc(F()?.statusLabel?.(r.method)||String(r.method||"").replaceAll("_"," "))}</td><td>${esc(r.reference||"—")}</td><td><span class="student-portal-status ${r.reversed?"bad":"good"}">${r.reversed?"Reversed":"Posted"}</span></td></tr>`).join(""):'<tr><td colspan="6">No payments have been recorded.</td></tr>'}</tbody></table></div></section>`;
  }

  function timetableHtml(data) {
    if(data.features?.timetable!==true)return featureUnavailable("Timetable is not enabled","Your school plan does not currently expose the timetable module in the Student Portal.");
    const t=data.timetable||{},entries=t.entries||[],grouped=Object.fromEntries(DAYS.map(day=>[day,entries.filter(e=>e.day_of_week===day)]));
    return `<section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Class Timetable</h4><p>${esc(t.class_name||data.student?.class_name||"Current class")} • ${esc(t.academic_year_name||data.student?.academic_year_name||"")}</p></div></div><div class="student-portal-panel-body"><div class="student-portal-week">${DAYS.map(day=>`<article class="student-portal-day"><div class="student-portal-day-head"><strong>${day}</strong></div>${grouped[day].length?grouped[day].map(e=>`<div class="student-portal-period-row"><div class="student-portal-period-time">${esc(time(e.period_start))}<br>${esc(time(e.period_end))}</div><div class="student-portal-period-copy"><strong>${esc(e.subject_name||"Subject")}</strong><span>${esc(e.teacher_name||"Teacher")}${e.notes?` • ${esc(e.notes)}`:""}</span></div></div>`).join(""):`<div class="student-portal-empty" style="padding:18px 12px"><span>No periods</span></div>`}</article>`).join("")}</div></div></section>`;
  }

  function attendanceHtml(data) {
    if(data.features?.attendance!==true)return featureUnavailable("Attendance is not enabled","Your school plan does not currently expose attendance records in the Student Portal.");
    const a=data.attendance||{},c=a.current||null,h=a.history||[];
    return `${c?`<div class="student-portal-attendance-cards"><div class="student-portal-attendance-card"><span>Attendance rate</span><strong>${num(c.percentage,1)}%</strong></div><div class="student-portal-attendance-card"><span>Days present</span><strong>${num(c.days_present)}</strong></div><div class="student-portal-attendance-card"><span>Late</span><strong>${num(c.late)}</strong></div><div class="student-portal-attendance-card"><span>Absent</span><strong>${num(c.absent)}</strong></div><div class="student-portal-attendance-card"><span>Excused</span><strong>${num(c.excused)}</strong></div></div>`:""}<section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Attendance History</h4><p>Term attendance totals from class registers.</p></div></div><div class="student-portal-table-scroll"><table><thead><tr><th>Academic Year</th><th>Term</th><th>Class</th><th>Days Opened</th><th>Present</th><th>Late</th><th>Absent</th><th>Excused</th><th>Rate</th></tr></thead><tbody>${h.length?h.map(r=>`<tr><td>${esc(r.academic_year_name||"")}</td><td>${esc(r.term_name||"")}</td><td>${esc(r.class_name||"")}</td><td>${num(r.days_opened)}</td><td>${num(r.present)}</td><td>${num(r.late)}</td><td>${num(r.absent)}</td><td>${num(r.excused)}</td><td><strong>${num(r.percentage,1)}%</strong></td></tr>`).join(""):'<tr><td colspan="9">No attendance records are available yet.</td></tr>'}</tbody></table></div></section>`;
  }

  function profileHtml(data) {
    const s=data.student||{},a=data.account||{},security=a.must_change_password?'<span class="student-portal-status warn">Password change required</span>':'<span class="student-portal-status good">Password current</span>',mfa=a.mfa_required?'<span class="student-portal-status good">MFA required</span>':'<span class="student-portal-status">MFA optional</span>';
    const details=(rows)=>rows.map(([l,v])=>`<div class="student-portal-detail"><span>${esc(l)}</span><strong>${esc(v||"—")}</strong></div>`).join("");
    return `<div class="student-portal-profile-grid"><section class="student-portal-profile-card"><h4>Student Information</h4>${details([["Full name",s.full_name],["Admission number",s.admission_no],["Class",s.class_name],["Roll number",s.roll_number||"—"],["Academic year",s.academic_year_name],["Current term",s.term_name],["Class teacher",s.class_teacher||"—"],["Gender",s.gender||"—"],["Date of birth",formatDate(s.date_of_birth)],["Student status",s.status||"—"]])}</section><section class="student-portal-profile-card"><h4>Guardian Contact</h4>${details([["Guardian",s.guardian_name||"—"],["Phone",s.guardian_phone||"—"],["Email",s.guardian_email||"—"],["Record policy","Read-only in Student Portal"]])}</section><section class="student-portal-profile-card"><h4>Portal Account</h4>${details([["Sign-in email",a.email||"—"],["Phone contact",a.phone||"—"],["Last seen",formatDateTime(a.last_seen_at)]])}</section><section class="student-portal-profile-card"><h4>Security</h4><div class="student-portal-detail"><span>Password</span><strong>${security}</strong></div><div class="student-portal-detail"><span>Multi-factor authentication</span><strong>${mfa}</strong></div><div class="student-portal-detail"><span>Account linkage</span><strong><span class="student-portal-status good">Linked to this student record</span></strong></div><div class="student-portal-detail"><span>Tenant access</span><strong>Restricted to this school workspace</strong></div></section></div>`;
  }

  function notificationRows(rows) { return rows.length?rows.map(r=>`<article class="student-portal-notification ${r.read_at?"":"unread"}"><span class="student-portal-notification-dot"></span><div class="student-portal-notification-copy"><strong>${esc(r.title||"Notification")}</strong><p>${esc(r.body||"")}</p><small>${formatDateTime(r.created_at)}${r.category?` • ${esc(String(r.category).replaceAll("_"," "))}`:""}</small></div>${r.read_at?'<span class="student-portal-status">Read</span>':`<button class="button ghost small" data-student-notification-read="${attr(r.id)}">Mark read</button>`}</article>`).join(""):`<div class="student-portal-empty"><strong>No notifications</strong><span>School alerts and workflow updates will appear here.</span></div>`; }
  async function notificationsHtml(data) {
    if(data.features?.notifications!==true)return featureUnavailable("Notifications are not enabled","Your school plan does not currently expose notifications in the Student Portal.");
    if(!state.notifications){try{state.notifications=await F().rpc("list_notifications",{page_number:1,page_size:100})}catch(e){return featureUnavailable("Notifications could not be loaded",friendly(e))}}
    const rows=state.notifications?.rows||[],unread=Number(state.notifications?.unread||0); return `<section class="student-portal-panel"><div class="student-portal-panel-head"><div><h4>Notifications</h4><p>${num(unread)} unread • ${num(state.notifications?.total||0)} total</p></div>${unread?'<button class="button secondary small" id="studentPortalMarkAllRead">Mark all read</button>':""}</div><div class="student-portal-panel-body"><div class="student-portal-notifications">${notificationRows(rows)}</div></div></section>`;
  }

  async function renderActiveModule() {
    const holder=byId("studentPortalModuleContent"); if(!holder||!state.data)return;
    holder.innerHTML='<div class="student-portal-empty"><span>Loading section…</span></div>'; let html="";
    if(state.module==="overview")html=overviewHtml(state.data); else if(state.module==="results")html=resultsHtml(state.data); else if(state.module==="fees")html=feesHtml(state.data); else if(state.module==="timetable")html=timetableHtml(state.data); else if(state.module==="attendance")html=attendanceHtml(state.data); else if(state.module==="notifications")html=await notificationsHtml(state.data); else html=profileHtml(state.data);
    holder.innerHTML=html; bindActions(holder); setNavActive(); updateNotificationBadge(); updateHeading();
  }

  async function openResult(reportId) {
    try { const d=await F().rpc("finance_portal_report_detail",{target_report_id:reportId}),q=F().dialog("Published Academic Result","Read-only school academic record"),body=byId("financeDialogBody");
      if(d.locked)body.innerHTML=`<div class="student-portal-banner"><strong>Grades are currently restricted</strong><span>${esc(d.hold?.reason||"Contact the Accounts Office for financial clearance.")}</span></div><div class="button-row" style="margin-top:16px"><button class="button ghost" id="studentResultClose">Close</button></div>`;
      else { const r=d.report||{},subs=d.subjects||[]; body.innerHTML=`<div class="student-portal-modal-summary"><div><span>Average</span><strong>${num(d.average,1)}%</strong></div><div><span>Position</span><strong>${esc(r.position??"—")}</strong></div></div><div class="student-portal-table-scroll"><table><thead><tr><th>Subject</th><th>Total</th><th>Grade</th><th>Remark</th></tr></thead><tbody>${subs.map(x=>`<tr><td>${esc(x.subject||"")}</td><td>${num(x.total_score,1)}</td><td><strong>${esc(x.grade||"")}</strong></td><td>${esc(x.remark||"")}</td></tr>`).join("")||'<tr><td colspan="4">No subject results are recorded.</td></tr>'}</tbody></table></div><div class="button-row" style="margin-top:16px"><button class="button ghost" id="studentResultClose">Close</button></div>`; }
      byId("studentResultClose").onclick=()=>q.close(); if(!q.open)q.showModal();
    } catch(e){notify("Result could not be opened",friendly(e),"error")}
  }

  async function markNotifications(ids) {
    const unique=[...new Set((ids||[]).filter(Boolean))]; if(!unique.length)return;
    try{await F().rpc("mark_notifications_read",{notification_ids:unique});state.notifications=null;state.data=await F().rpc("get_my_student_portal_v2");await renderActiveModule();notify("Notifications updated")}catch(e){notify("Notifications were not updated",friendly(e),"error")}
  }

  function bindActions(root=document) {
    root.querySelectorAll?.("[data-student-module-action]").forEach(b=>b.onclick=()=>openModule(String(b.dataset.studentModuleAction||"overview")));
    root.querySelectorAll?.("[data-student-result]").forEach(b=>b.onclick=()=>openResult(b.dataset.studentResult));
    byId("studentPortalPrintFees")?.addEventListener("click",()=>{const p=window.EdusentiaFinancePortals;if(p?.printFee)p.printFee(state.data?.fee_statement);else notify("Print unavailable","The finance print service is not ready.","warning")});
    byId("studentPortalPrintFeeSummary")?.addEventListener("click",()=>{const p=window.EdusentiaFinancePortals;if(p?.printFeeSummary)p.printFeeSummary(state.data?.fee_statement);else notify("Print unavailable","The finance print service is not ready.","warning")});
    root.querySelectorAll?.("[data-student-notification-read]").forEach(b=>b.onclick=()=>markNotifications([b.dataset.studentNotificationRead]));
    byId("studentPortalMarkAllRead")?.addEventListener("click",()=>markNotifications((state.notifications?.rows||[]).filter(r=>!r.read_at).map(r=>r.id)));
  }

  async function renderStudentPortal() {
    if(state.rendering)return; state.rendering=true; installStyles(); ensureNav(); updateHeading();
    const runtime=await waitForRuntime(); if(!runtime){state.rendering=false;return} const content=byId("content"); if(!content){state.rendering=false;return}
    content.innerHTML='<section class="panel pad"><div class="skeleton"></div></section>';
    try{const data=await runtime.rpc("get_my_student_portal_v2");state.data=data;state.notifications=null;if(!data.linked){content.innerHTML=`<div class="finance-workspace student-portal-workspace"><section class="student-portal-panel"><div class="student-portal-empty"><strong>No Student Management record is linked to this account</strong><span>Ask the System Administrator to link this login to the correct Student Management record.</span></div></section></div>`;return}content.innerHTML=`<div class="finance-workspace student-portal-workspace">${heroHtml(data)}<main id="studentPortalModuleContent"></main></div>`;await renderActiveModule()}catch(e){content.innerHTML=`<div class="finance-workspace student-portal-workspace"><section class="student-portal-panel"><div class="student-portal-empty"><strong>Student Portal could not be loaded</strong><span>${esc(friendly(e))}</span><button class="button secondary" id="studentPortalRetry" style="margin-top:12px">Retry</button></div></section></div>`;byId("studentPortalRetry")?.addEventListener("click",()=>renderStudentPortal());notify("Student Portal error",friendly(e),"error")}finally{state.rendering=false}
  }

  async function initialize() {
    installStyles(); const runtime=await waitForRuntime(); if(!runtime)return; runtime.register("student",renderStudentPortal); if(currentRole()!=="student")return;
    ensureNav(); const nav=byId("mainNav"); if(nav)new MutationObserver(scheduleNav).observe(nav,{childList:true,subtree:true}); setTimeout(async()=>{runtime.S.active=true;ensureNav();await runtime.open()},0);
  }

  document.addEventListener("click",(event)=>{if(currentRole()!=="student")return;if(event.target.closest("#refreshButton"))setTimeout(()=>{state.data=null;state.notifications=null},0)},true);
  window.addEventListener("pageshow",scheduleNav,{passive:true}); initialize().catch(e=>console.error("student_portal_v2_init_failed",e));
})();
