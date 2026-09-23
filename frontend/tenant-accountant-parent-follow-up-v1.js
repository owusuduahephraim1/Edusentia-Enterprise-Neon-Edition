(() => {
  "use strict";
  if (window.EDS_ACCOUNTANT_PARENT_FOLLOW_UP_V1) return;
  window.EDS_ACCOUNTANT_PARENT_FOLLOW_UP_V1 = true;

  let authReconcileBound = false;

  const state = {
    active: false,
    tab: "outstanding",
    yearId: "",
    termId: "",
    classId: "",
    status: "outstanding",
    search: "",
    data: null,
    history: null,
    requestToken: 0,
    searchTimer: 0,
  };

  const byId = (id) => document.getElementById(id);
  const F = () => window.EdusentiaFinanceRuntime || null;
  const esc = (value) => F()?.esc ? F().esc(value) : String(value ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  }[c]));
  const attr = esc;
  const money = (value) => F()?.money ? F().money(value) : `GHS ${Number(value || 0).toFixed(2)}`;
  const friendly = (error) => F()?.friendly?.(error) || String(error?.message || error || "Request failed");
  const notify = (title, message = "", kind = "info") => F()?.notify?.(title, message, kind);
  const statusLabel = (value) => F()?.statusLabel?.(value) || String(value || "").replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());

  async function waitForRuntime() {
    for (let i = 0; i < 240; i += 1) {
      const runtime = F();
      if (runtime?.S?.client && runtime?.S?.boot && runtime?.S?.role) return runtime;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return null;
  }

  function isAccountant() {
    return String(F()?.S?.role || "") === "accountant";
  }

  function formatDateTime(value) {
    if (!value) return "Never contacted";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleString("en-GH", { year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
  }

  function cleanPhone(value) {
    return String(value || "").trim().replace(/[^0-9+]/g, "");
  }

  function whatsappPhone(value) {
    let phone = cleanPhone(value);
    if (phone.startsWith("00")) phone = phone.slice(2);
    if (phone.startsWith("+")) phone = phone.slice(1);
    return phone.replace(/\D/g, "");
  }

  async function copyText(value) {
    const text = String(value || "");
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      const area = document.createElement("textarea");
      area.value = text;
      area.style.position = "fixed";
      area.style.opacity = "0";
      area.style.pointerEvents = "none";
      document.body.appendChild(area);
      area.select();
      const ok = document.execCommand("copy");
      area.remove();
      return ok;
    }
  }

  function installStyles() {
    if (byId("edsAccountantParentFollowUpStyleV1")) return;
    const style = document.createElement("style");
    style.id = "edsAccountantParentFollowUpStyleV1";
    style.textContent = `
      .accountant-parent-followup-nav-item{display:flex!important}.guardian-followup-workspace{display:grid;gap:14px;min-width:0}.guardian-followup-tabs{display:flex;gap:8px;overflow:auto;padding:4px;border:1px solid var(--line,#d8e1ef);border-radius:14px;background:var(--surface,#fff)}.guardian-followup-tab{border:0;background:transparent;border-radius:10px;padding:9px 13px;white-space:nowrap;font-size:12px;font-weight:800;color:#52647a;cursor:pointer}.guardian-followup-tab.active{background:#0b4da3;color:#fff;box-shadow:0 6px 14px rgba(11,77,163,.16)}
      .guardian-followup-filter-panel{border:1px solid var(--line,#d8e1ef);border-radius:16px;background:var(--surface,#fff);padding:14px 16px}.guardian-followup-filters{display:grid;grid-template-columns:1.05fr 1fr 1fr 1fr minmax(220px,1.5fr) auto;gap:10px;align-items:end}.guardian-followup-filters.history{grid-template-columns:1fr 1fr minmax(260px,2fr) auto}.guardian-followup-filter{display:grid;gap:5px;min-width:0}.guardian-followup-filter span{font-size:10px;font-weight:800;color:var(--muted,#64748b)}.guardian-followup-filter input,.guardian-followup-filter select{width:100%;min-height:40px;border:1px solid var(--line,#d8e1ef);border-radius:10px;padding:0 10px;background:var(--surface,#fff);color:inherit;min-width:0}
      .guardian-followup-metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:11px}.guardian-followup-metric{border:1px solid var(--line,#d8e1ef);border-radius:14px;background:var(--surface,#fff);padding:14px 15px;min-width:0}.guardian-followup-metric span{display:block;color:var(--muted,#64748b);font-size:10px;font-weight:800;margin-bottom:5px}.guardian-followup-metric strong{display:block;font-size:19px;line-height:1.2;overflow-wrap:anywhere}.guardian-followup-metric small{display:block;color:var(--muted,#64748b);font-size:9px;margin-top:4px;line-height:1.4}.guardian-followup-notice{border:1px solid #e7d7ae;border-radius:12px;background:#fff8e8;padding:10px 12px;font-size:11px;line-height:1.45;color:#6f5b2e}.guardian-followup-notice strong{color:#4d3d1a}
      .guardian-followup-panel{border:1px solid var(--line,#d8e1ef);border-radius:16px;background:var(--surface,#fff);overflow:hidden;min-width:0}.guardian-followup-panel-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;padding:14px 16px;border-bottom:1px solid var(--line,#d8e1ef)}.guardian-followup-panel-head h3{margin:0 0 3px;font-size:14px}.guardian-followup-panel-head p{margin:0;color:var(--muted,#64748b);font-size:10px;line-height:1.4}.guardian-followup-scroll,.guardian-followup-history-scroll{max-height:470px;overflow:auto;overscroll-behavior:contain;scrollbar-gutter:stable}.guardian-followup-scroll{padding:10px;background:rgba(245,248,252,.55)}.guardian-followup-scroll.expanded,.guardian-followup-history-scroll.expanded{max-height:70vh}.guardian-followup-list{display:grid;gap:9px}
      .guardian-followup-card{border:1px solid var(--line,#d8e1ef);border-radius:13px;background:var(--surface,#fff);padding:12px 13px;display:grid;gap:9px}.guardian-followup-card-top{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(170px,.7fr) auto;gap:12px;align-items:center}.guardian-followup-parent{min-width:0}.guardian-followup-parent strong{display:block;font-size:12px;line-height:1.3}.guardian-followup-parent span{display:block;color:var(--muted,#64748b);font-size:10px;line-height:1.35;margin-top:3px;overflow-wrap:anywhere}.guardian-followup-balance{text-align:right}.guardian-followup-balance span{display:block;color:var(--muted,#64748b);font-size:9px}.guardian-followup-balance strong{display:block;font-size:16px;margin-top:2px}.guardian-followup-actions{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}.guardian-followup-actions .button{min-height:31px;padding:5px 9px;white-space:nowrap}.guardian-followup-child-summary{font-size:10px;line-height:1.45;color:#465b73;overflow-wrap:anywhere}.guardian-followup-meta{display:flex;gap:9px;flex-wrap:wrap;color:var(--muted,#64748b);font-size:9px;line-height:1.35}.guardian-followup-details{border-top:1px solid var(--line,#e5ebf3);padding-top:8px}.guardian-followup-details summary{cursor:pointer;font-size:10px;font-weight:800;color:#245a96;list-style:none}.guardian-followup-details summary::-webkit-details-marker{display:none}.guardian-followup-children{display:grid;gap:6px;margin-top:8px}.guardian-followup-child{display:grid;grid-template-columns:minmax(0,1fr) auto auto;gap:10px;align-items:center;padding:8px 9px;border:1px solid var(--line,#e2e8f0);border-radius:10px;background:#f9fbfd}.guardian-followup-child strong{display:block;font-size:10px}.guardian-followup-child small{display:block;color:var(--muted,#64748b);font-size:9px;margin-top:2px}.guardian-followup-child-balance{text-align:right;font-size:10px;font-weight:800}
      .guardian-followup-status{display:inline-flex;align-items:center;min-height:23px;padding:0 8px;border-radius:999px;font-size:9px;font-weight:800;background:#edf2f8;color:#4a5d74}.guardian-followup-status.outstanding,.guardian-followup-status.unpaid{background:#fdebec;color:#9a2f37}.guardian-followup-status.partial_paid{background:#fff2d5;color:#815c0a}.guardian-followup-status.fully_paid{background:#e6f7ee;color:#176d49}.guardian-followup-status.not_configured{background:#edf2f8;color:#57697f}.guardian-followup-empty{padding:34px 20px;text-align:center;color:var(--muted,#64748b)}.guardian-followup-empty strong{display:block;margin-bottom:5px}.guardian-followup-empty span{display:block;font-size:10px;line-height:1.5}
      .guardian-followup-history-scroll table{width:100%;border-collapse:collapse}.guardian-followup-history-scroll th,.guardian-followup-history-scroll td{padding:10px 11px;border-bottom:1px solid var(--line,#e2e8f0);text-align:left;font-size:10px;vertical-align:top}.guardian-followup-history-scroll th{position:sticky;top:0;background:#f3f7fb;z-index:1;font-size:9px;text-transform:uppercase;color:#52647a}.guardian-followup-history-scroll tbody tr:last-child td{border-bottom:0}.guardian-followup-history-scroll small{display:block;color:var(--muted,#64748b);margin-top:2px}.guardian-reminder-preview{display:grid;gap:12px}.guardian-reminder-contact{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px}.guardian-reminder-contact>div{border:1px solid var(--line,#d8e1ef);border-radius:11px;padding:10px}.guardian-reminder-contact span{display:block;color:var(--muted,#64748b);font-size:9px}.guardian-reminder-contact strong{display:block;font-size:11px;margin-top:3px;overflow-wrap:anywhere}.guardian-reminder-preview label{display:grid;gap:6px}.guardian-reminder-preview label span{font-size:10px;font-weight:800}.guardian-reminder-preview textarea{width:100%;min-height:185px;resize:vertical;border:1px solid var(--line,#d8e1ef);border-radius:11px;padding:10px 11px;font:inherit;line-height:1.45;color:inherit;background:var(--surface,#fff)}
      @media(max-width:1180px){.guardian-followup-filters,.guardian-followup-filters.history{grid-template-columns:repeat(3,minmax(0,1fr))}.guardian-followup-filters .search-field{grid-column:span 2}.guardian-followup-card-top{grid-template-columns:minmax(0,1fr) auto}.guardian-followup-actions{grid-column:1/-1;justify-content:flex-start}.guardian-followup-balance{align-self:start}}@media(max-width:760px){.guardian-followup-filters,.guardian-followup-filters.history{grid-template-columns:1fr 1fr}.guardian-followup-filters .search-field{grid-column:1/-1}.guardian-followup-metrics{grid-template-columns:1fr 1fr}.guardian-followup-card-top{grid-template-columns:1fr}.guardian-followup-balance{text-align:left}.guardian-followup-actions{grid-column:auto}.guardian-followup-child{grid-template-columns:minmax(0,1fr) auto}.guardian-followup-child .guardian-followup-status{grid-column:1/-1;justify-self:start}.guardian-reminder-contact{grid-template-columns:1fr}}@media(max-width:500px){.guardian-followup-filters,.guardian-followup-filters.history,.guardian-followup-metrics{grid-template-columns:1fr}.guardian-followup-filter-panel{padding:12px}.guardian-followup-scroll{padding:7px}.guardian-followup-panel-head{padding:12px}.guardian-followup-actions .button{flex:1 1 calc(50% - 6px)}}
    `;
    document.head.appendChild(style);
  }

  function termsForYear() {
    return (F()?.S?.boot?.terms || []).filter((row) => !state.yearId || String(row.academic_year_id) === String(state.yearId));
  }

  function ensureDefaults() {
    const runtime = F();
    if (!runtime) return;
    const years = runtime.S.boot?.academic_years || [];
    const year = years.find((row) => String(row.id) === String(runtime.S.yearId)) || years.find((row) => row.is_active) || years[0];
    if (!state.yearId) state.yearId = String(year?.id || "");
    const terms = termsForYear();
    const term = terms.find((row) => String(row.id) === String(runtime.S.termId)) || terms.find((row) => row.is_active) || terms[0];
    if (!state.termId || !terms.some((row) => String(row.id) === String(state.termId))) state.termId = String(term?.id || "");
  }

  function optionRows(rows, selected, emptyLabel = "") {
    const empty = emptyLabel ? `<option value="">${esc(emptyLabel)}</option>` : "";
    return empty + rows.map((row) => `<option value="${attr(row.id)}" ${String(row.id) === String(selected) ? "selected" : ""}>${esc(row.name)}</option>`).join("");
  }

  function setNavActive() {
    const nav = byId("mainNav");
    nav?.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
    nav?.querySelector(".accountant-parent-followup-nav-item")?.classList.add("active");
    if (F()?.S) F().S.active = false;
  }

  function ensureNav() {
    const nav = byId("mainNav");
    let button = nav?.querySelector(".accountant-parent-followup-nav-item");
    if (!isAccountant()) {
      button?.remove();
      state.active = false;
      return false;
    }
    if (!nav) return false;
    if (!button) {
      button = document.createElement("button");
      button.type = "button";
      button.className = "nav-item accountant-parent-followup-nav-item";
      button.title = "Parent & Guardian Follow-up";
      button.innerHTML = '<span class="nav-icon">☎</span><span class="nav-label">Parent &amp; Guardian Follow-up</span><span class="nav-active-dot"></span>';
      button.addEventListener("click", async () => {
        state.active = true;
        setNavActive();
        await renderWorkspace();
      });
      nav.appendChild(button);
    }
    const finance = nav.querySelector(".accountant-finance-nav-item");
    if (finance && finance.nextElementSibling !== button) finance.insertAdjacentElement("afterend", button);
    return true;
  }

  function metric(label, value, help) {
    return `<div class="guardian-followup-metric"><span>${esc(label)}</span><strong>${esc(value)}</strong>${help ? `<small>${esc(help)}</small>` : ""}</div>`;
  }

  function childSummary(row) {
    return (row.children || []).map((child) => `${child.student || "Student"} (${child.class_name || "Class"})`).join(" • ");
  }

  function childRows(row) {
    return (row.children || []).map((child) => `<div class="guardian-followup-child"><div><strong>${esc(child.student || "Student")}</strong><small>${esc(child.admission_no || "")} • ${esc(child.class_name || "")}</small></div><div class="guardian-followup-child-balance">${esc(money(child.balance || 0))}</div><span class="guardian-followup-status ${attr(child.status || "")}">${esc(statusLabel(child.status || ""))}</span></div>`).join("");
  }

  function rowCard(row, index) {
    const phone = String(row.guardian_phone || "").trim();
    const outstanding = Number(row.total_outstanding || 0);
    const canMessage = Boolean(phone && outstanding > 0);
    const childrenText = childSummary(row) || "No linked children in this period";
    const last = row.last_contact_at ? `${statusLabel(row.last_contact_channel || "contact")} • ${formatDateTime(row.last_contact_at)}` : "No previous follow-up recorded";
    return `<article class="guardian-followup-card"><div class="guardian-followup-card-top"><div class="guardian-followup-parent"><strong>${esc(row.guardian_name || "Parent / Guardian")}</strong><span>${esc(phone || "No phone contact")}${row.guardian_email ? ` • ${esc(row.guardian_email)}` : ""}</span></div><div class="guardian-followup-balance"><span>Total outstanding</span><strong>${esc(money(outstanding))}</strong></div><div class="guardian-followup-actions"><button class="button secondary small" type="button" data-guardian-sms="${index}" ${canMessage ? "" : "disabled"}>SMS</button><button class="button secondary small" type="button" data-guardian-whatsapp="${index}" ${canMessage ? "" : "disabled"}>WhatsApp</button><button class="button ghost small" type="button" data-guardian-call="${index}" ${phone ? "" : "disabled"}>Call</button><button class="button ghost small" type="button" data-guardian-copy="${index}" ${outstanding > 0 ? "" : "disabled"}>Copy message</button></div></div><div class="guardian-followup-child-summary"><strong>${Number(row.child_count || 0)} child${Number(row.child_count || 0) === 1 ? "" : "ren"}:</strong> ${esc(childrenText)}</div><div class="guardian-followup-meta"><span>Due ${esc(money(row.total_due || 0))}</span><span>Paid ${esc(money(row.total_paid || 0))}</span><span>Last contact: ${esc(last)}</span></div><details class="guardian-followup-details"><summary>View child fee details</summary><div class="guardian-followup-children">${childRows(row)}</div></details></article>`;
  }

  function emptyFollowUp(data) {
    const missing = Number(data?.metrics?.missing_guardian_contact || 0);
    return missing > 0
      ? `<div class="guardian-followup-empty"><strong>No parent or guardian contacts match this view</strong><span>${missing} enrolled student record${missing === 1 ? "" : "s"} in the selected scope currently have no guardian contact information in Student Management. The Accountant cannot edit those records here.</span></div>`
      : '<div class="guardian-followup-empty"><strong>No parent or guardian records match this view</strong><span>Try another class, payment status, academic period, or search term.</span></div>';
  }

  function renderFollowUpResults(data) {
    state.data = data;
    const metrics = data?.metrics || {}, rows = data?.rows || [];
    const metricHolder = byId("guardianFollowUpMetrics");
    if (metricHolder) metricHolder.innerHTML = [
      metric("Parents / Guardians", String(metrics.guardians || 0), "Siblings are grouped under one contact"),
      metric("Children", String(metrics.children || 0), "Children represented in this view"),
      metric("Outstanding", money(metrics.outstanding || 0), "Live authoritative Finance ledger balance"),
      metric("Missing phone", String(metrics.missing_phone || 0), "Messaging and calls require a saved phone number"),
    ].join("");
    const notice = byId("guardianFollowUpNotice");
    if (notice) {
      const missing = Number(metrics.missing_guardian_contact || 0);
      notice.hidden = missing <= 0;
      notice.innerHTML = missing > 0 ? `<strong>${missing} student record${missing === 1 ? "" : "s"} missing guardian contact details.</strong> Update guardian information from Student Management as System Administrator. This Accountant workspace remains read-only.` : "";
    }
    const holder = byId("guardianFollowUpRows");
    if (holder) holder.innerHTML = rows.length ? `<div class="guardian-followup-list">${rows.map(rowCard).join("")}</div>` : emptyFollowUp(data);
    bindRowActions(rows);
  }

  function reminderMessage(row) {
    const school = F()?.schoolName?.() || "School";
    const period = state.data?.period || {};
    const children = (row.children || []).filter((child) => Number(child.balance || 0) > 0);
    const childText = children.map((child) => `${child.student || "Student"} (${child.class_name || "Class"}): ${money(child.balance || 0)}`).join("; ");
    const periodText = [period.term_name, period.academic_year_name].filter(Boolean).join(", ");
    return `Dear ${row.guardian_name || "Parent / Guardian"}, this is a school fee reminder from ${school}. ${periodText ? `For ${periodText}, ` : ""}${children.length > 1 ? "the following outstanding balances remain: " : "the outstanding balance is: "}${childText}. Total outstanding: ${money(row.total_outstanding || 0)}. Kindly contact the Accounts Office if payment has already been made or if you need clarification. Thank you.`;
  }

  async function logContact(row, channel, actionState, messageText = "") {
    try {
      const period = state.data?.period || {};
      await F().rpc("finance_log_guardian_contact", { payload: {
        guardian_key: row.guardian_key,
        guardian_name: row.guardian_name,
        guardian_phone: row.guardian_phone,
        guardian_email: row.guardian_email,
        channel,
        action_state: actionState,
        academic_year_id: period.academic_year_id || state.yearId || null,
        term_id: period.term_id || state.termId || null,
        class_id: state.classId || null,
        child_count: row.child_count || 0,
        total_outstanding: row.total_outstanding || 0,
        children: row.children || [],
        message_text: messageText || null,
      }});
      state.history = null;
      const local = state.data?.rows?.find((item) => item.guardian_key === row.guardian_key);
      if (local) {
        local.last_contact_at = new Date().toISOString();
        local.last_contact_channel = channel;
      }
    } catch (error) {
      notify("Contact history was not recorded", friendly(error), "warning");
    }
  }

  async function openCall(row) {
    const phone = cleanPhone(row.guardian_phone);
    if (!phone) return;
    await logContact(row, "call", "opened", "");
    window.location.href = `tel:${phone}`;
  }

  async function copyReminder(row, customMessage = "") {
    const message = customMessage || reminderMessage(row);
    if (await copyText(message)) {
      await logContact(row, "copy", "copied", message);
      notify("Fee reminder copied", "The message is ready to paste into another app.");
    }
  }

  function openReminderComposer(row, preferredChannel = "sms") {
    const runtime = F();
    if (!runtime?.dialog) return;
    const phone = cleanPhone(row.guardian_phone);
    const waPhone = whatsappPhone(row.guardian_phone);
    const dialog = runtime.dialog("Fee Reminder", "Review or edit the generated reminder before opening a messaging app.");
    byId("financeDialogBody").innerHTML = `<div class="guardian-reminder-preview"><div class="guardian-reminder-contact"><div><span>Parent / Guardian</span><strong>${esc(row.guardian_name || "Parent / Guardian")}</strong></div><div><span>Phone</span><strong>${esc(phone || "No phone number saved")}</strong></div></div><label><span>Reminder message</span><textarea id="guardianReminderMessage">${esc(reminderMessage(row))}</textarea></label><div class="button-row"><button class="button ${preferredChannel === "sms" ? "primary" : "secondary"}" id="guardianReminderSms" type="button" ${phone ? "" : "disabled"}>Open SMS</button><button class="button ${preferredChannel === "whatsapp" ? "primary" : "secondary"}" id="guardianReminderWhatsApp" type="button" ${waPhone ? "" : "disabled"}>Open WhatsApp</button><button class="button secondary" id="guardianReminderCopy" type="button">Copy message</button><button class="button ghost" id="guardianReminderCancel" type="button">Cancel</button></div><small class="help-text">Edusentia prepares the reminder, then your SMS or WhatsApp app performs the actual send. Contact History records the action as opened, not as confirmed delivered.</small></div>`;
    const messageValue = () => String(byId("guardianReminderMessage")?.value || "").trim();
    byId("guardianReminderSms")?.addEventListener("click", async () => {
      const message = messageValue();
      if (!phone || !message) return;
      await logContact(row, "sms", "opened", message);
      dialog.close();
      window.location.href = `sms:${phone}?body=${encodeURIComponent(message)}`;
    });
    byId("guardianReminderWhatsApp")?.addEventListener("click", () => {
      const message = messageValue();
      if (!waPhone || !message) return;
      const popup = window.open(`https://wa.me/${waPhone}?text=${encodeURIComponent(message)}`, "_blank");
      if (popup) popup.opener = null;
      else notify("WhatsApp window blocked", "Allow pop-ups for this site or use Copy message.", "warning");
      void logContact(row, "whatsapp", "opened", message);
      dialog.close();
    });
    byId("guardianReminderCopy")?.addEventListener("click", async () => {
      const message = messageValue();
      if (message) await copyReminder(row, message);
    });
    byId("guardianReminderCancel")?.addEventListener("click", () => dialog.close());
    dialog.showModal();
  }

  function bindRowActions(rows) {
    document.querySelectorAll("[data-guardian-sms]").forEach((button) => button.addEventListener("click", () => openReminderComposer(rows[Number(button.dataset.guardianSms)], "sms")));
    document.querySelectorAll("[data-guardian-whatsapp]").forEach((button) => button.addEventListener("click", () => openReminderComposer(rows[Number(button.dataset.guardianWhatsapp)], "whatsapp")));
    document.querySelectorAll("[data-guardian-call]").forEach((button) => button.addEventListener("click", () => void openCall(rows[Number(button.dataset.guardianCall)])));
    document.querySelectorAll("[data-guardian-copy]").forEach((button) => button.addEventListener("click", () => void copyReminder(rows[Number(button.dataset.guardianCopy)])));
  }

  async function refreshFollowUp() {
    const token = ++state.requestToken;
    const holder = byId("guardianFollowUpRows");
    if (holder) holder.innerHTML = '<div class="guardian-followup-empty"><span>Loading parent and guardian fee follow-up records…</span></div>';
    try {
      const data = await F().rpc("finance_guardian_follow_up", {
        target_academic_year_id: state.yearId || null,
        target_term_id: state.termId || null,
        target_class_id: state.classId || null,
        status_filter: state.status,
        search_text: state.search || null,
      });
      if (!state.active || token !== state.requestToken) return;
      renderFollowUpResults(data);
    } catch (error) {
      if (holder) holder.innerHTML = `<div class="guardian-followup-empty"><strong>Parent and guardian follow-up could not be loaded</strong><span>${esc(friendly(error))}</span><button class="button secondary" id="guardianFollowUpRetry" type="button" style="margin-top:10px">Retry</button></div>`;
      byId("guardianFollowUpRetry")?.addEventListener("click", () => void refreshFollowUp());
      notify("Parent follow-up error", friendly(error), "error");
    }
  }

  function historyMarkup(data) {
    const rows = data?.rows || [];
    if (!rows.length) return '<div class="guardian-followup-empty"><strong>No contact history for this period</strong><span>SMS, WhatsApp, Call and Copy Message actions will be recorded here.</span></div>';
    return `<div class="guardian-followup-history-scroll" id="guardianFollowUpHistoryScroll" data-tenant-scroll-ignore="1"><table><thead><tr><th>Date</th><th>Parent / Guardian</th><th>Channel</th><th>Period</th><th>Children</th><th>Outstanding</th><th>Accountant</th></tr></thead><tbody>${rows.map((row) => `<tr><td>${esc(formatDateTime(row.created_at))}</td><td><strong>${esc(row.guardian_name || "Parent / Guardian")}</strong><small>${esc(row.guardian_phone || "No phone")}</small></td><td><span class="guardian-followup-status">${esc(statusLabel(row.channel))} ${esc(statusLabel(row.action_state))}</span></td><td>${esc(row.academic_year_name || "—")}<small>${esc(row.term_name || "")}${row.class_name ? ` • ${esc(row.class_name)}` : ""}</small></td><td>${esc(String(row.child_count || 0))}</td><td><strong>${esc(money(row.total_outstanding || 0))}</strong></td><td>${esc(row.actor_name || "Accountant")}</td></tr>`).join("")}</tbody></table></div>`;
  }

  async function refreshHistory() {
    const token = ++state.requestToken;
    const holder = byId("guardianFollowUpHistory");
    if (holder) holder.innerHTML = '<div class="guardian-followup-empty"><span>Loading contact history…</span></div>';
    try {
      const data = await F().rpc("finance_guardian_contact_history", {
        target_academic_year_id: state.yearId || null,
        target_term_id: state.termId || null,
        search_text: state.search || null,
        page_number: 1,
        page_size: 200,
      });
      if (!state.active || token !== state.requestToken) return;
      state.history = data;
      if (holder) holder.innerHTML = historyMarkup(data);
      const subtitle = byId("guardianHistorySubtitle");
      if (subtitle) subtitle.textContent = `${Number(data?.total || 0).toLocaleString("en-GH")} recorded contact action${Number(data?.total || 0) === 1 ? "" : "s"}`;
    } catch (error) {
      if (holder) holder.innerHTML = `<div class="guardian-followup-empty"><strong>Contact history could not be loaded</strong><span>${esc(friendly(error))}</span></div>`;
      notify("Contact history error", friendly(error), "error");
    }
  }

  function toggleScroll(id, button) {
    const region = byId(id);
    if (!region) return;
    const expanded = region.classList.toggle("expanded");
    button.textContent = expanded ? "Collapse list" : "Expand list";
    button.setAttribute("aria-expanded", expanded ? "true" : "false");
    if (!expanded) region.scrollTo({ top: 0, behavior: "smooth" });
  }

  function bindFilters(isHistory) {
    byId("guardianFollowUpYear")?.addEventListener("change", (event) => {
      state.yearId = String(event.currentTarget.value || "");
      const terms = termsForYear();
      const term = terms.find((row) => row.is_active) || terms[0];
      state.termId = String(term?.id || "");
      state.data = null;
      state.history = null;
      void renderWorkspace();
    });
    byId("guardianFollowUpTerm")?.addEventListener("change", (event) => {
      state.termId = String(event.currentTarget.value || "");
      state.data = null;
      state.history = null;
      if (isHistory) void refreshHistory(); else void refreshFollowUp();
    });
    byId("guardianFollowUpClass")?.addEventListener("change", (event) => {
      state.classId = String(event.currentTarget.value || "");
      state.data = null;
      void refreshFollowUp();
    });
    byId("guardianFollowUpStatus")?.addEventListener("change", (event) => {
      state.status = String(event.currentTarget.value || "all");
      state.tab = state.status === "outstanding" ? "outstanding" : "all";
      document.querySelectorAll(".guardian-followup-tab").forEach((button) => button.classList.toggle("active", button.dataset.guardianFollowupTab === state.tab));
      state.data = null;
      void refreshFollowUp();
    });
    byId("guardianFollowUpSearch")?.addEventListener("input", (event) => {
      state.search = String(event.currentTarget.value || "").trim();
      clearTimeout(state.searchTimer);
      state.searchTimer = setTimeout(() => isHistory ? void refreshHistory() : void refreshFollowUp(), 280);
    });
    byId("guardianFollowUpRefresh")?.addEventListener("click", () => isHistory ? void refreshHistory() : void refreshFollowUp());
  }

  function filters(isHistory) {
    const runtime = F();
    const years = runtime?.S?.boot?.academic_years || [];
    const terms = termsForYear();
    const classes = runtime?.S?.boot?.classes || [];
    return `<section class="guardian-followup-filter-panel"><div class="guardian-followup-filters ${isHistory ? "history" : ""}"><label class="guardian-followup-filter"><span>Academic year</span><select id="guardianFollowUpYear">${optionRows(years,state.yearId)}</select></label><label class="guardian-followup-filter"><span>Term</span><select id="guardianFollowUpTerm">${optionRows(terms,state.termId)}</select></label>${isHistory ? "" : `<label class="guardian-followup-filter"><span>Class</span><select id="guardianFollowUpClass">${optionRows(classes,state.classId,"All classes")}</select></label><label class="guardian-followup-filter"><span>Payment status</span><select id="guardianFollowUpStatus"><option value="outstanding" ${state.status === "outstanding" ? "selected" : ""}>Outstanding</option><option value="partial_paid" ${state.status === "partial_paid" ? "selected" : ""}>Partially paid</option><option value="unpaid" ${state.status === "unpaid" ? "selected" : ""}>Unpaid</option><option value="fully_paid" ${state.status === "fully_paid" ? "selected" : ""}>Fully paid</option><option value="all" ${state.status === "all" ? "selected" : ""}>All parents</option></select></label>`}<label class="guardian-followup-filter search-field"><span>Search</span><input id="guardianFollowUpSearch" type="search" value="${attr(state.search)}" placeholder="Parent, student, admission no. or phone"></label><button class="button secondary" id="guardianFollowUpRefresh" type="button">Refresh</button></div></section>`;
  }

  function tabs() {
    return `<nav class="guardian-followup-tabs" aria-label="Parent and Guardian follow-up sections"><button class="guardian-followup-tab ${state.tab === "outstanding" ? "active" : ""}" type="button" data-guardian-followup-tab="outstanding">Outstanding</button><button class="guardian-followup-tab ${state.tab === "all" ? "active" : ""}" type="button" data-guardian-followup-tab="all">All Parents</button><button class="guardian-followup-tab ${state.tab === "history" ? "active" : ""}" type="button" data-guardian-followup-tab="history">Contact History</button></nav>`;
  }

  function bindTabs() {
    document.querySelectorAll("[data-guardian-followup-tab]").forEach((button) => button.addEventListener("click", () => {
      const tab = String(button.dataset.guardianFollowupTab || "outstanding");
      state.tab = tab;
      if (tab === "outstanding") state.status = "outstanding";
      if (tab === "all") state.status = "all";
      state.data = null;
      state.history = null;
      void renderWorkspace();
    }));
  }

  async function renderWorkspace() {
    if (!state.active || !isAccountant()) return;
    installStyles();
    ensureDefaults();
    setNavActive();
    const runtime = F(), content = byId("content");
    if (!runtime || !content) return;
    runtime.heading?.("Parent & Guardian Follow-up", "Guardian contacts, linked children, outstanding fees and payment reminders");

    if (state.tab === "history") {
      content.innerHTML = `<div class="guardian-followup-workspace"><div class="page-head"><div><h3>Parent & Guardian Follow-up</h3><p>Contact history records communication actions opened from the Accountant workspace.</p></div></div>${tabs()}${filters(true)}<section class="guardian-followup-panel"><div class="guardian-followup-panel-head"><div><h3>Contact History</h3><p id="guardianHistorySubtitle">Loading recorded contact actions…</p></div><button class="button ghost small" id="guardianHistoryExpand" type="button" aria-expanded="false">Expand list</button></div><div id="guardianFollowUpHistory"><div class="guardian-followup-empty"><span>Loading contact history…</span></div></div></section></div>`;
      bindTabs();
      bindFilters(true);
      byId("guardianHistoryExpand")?.addEventListener("click", (event) => toggleScroll("guardianFollowUpHistoryScroll", event.currentTarget));
      await refreshHistory();
      return;
    }

    content.innerHTML = `<div class="guardian-followup-workspace"><div class="page-head"><div><h3>Parent & Guardian Follow-up</h3><p>Read-only guardian contacts from Student Management with live Finance ledger balances.</p></div></div>${tabs()}${filters(false)}<div class="guardian-followup-metrics" id="guardianFollowUpMetrics">${metric("Parents / Guardians","…","")}${metric("Children","…","")}${metric("Outstanding","…","")}${metric("Missing phone","…","")}</div><div class="guardian-followup-notice" id="guardianFollowUpNotice" hidden></div><section class="guardian-followup-panel"><div class="guardian-followup-panel-head"><div><h3>${state.status === "outstanding" ? "Parents requiring fee follow-up" : "Parent and guardian directory"}</h3><p>Sibling records are grouped under one parent. Contact information cannot be edited by the Accountant.</p></div><button class="button ghost small" id="guardianFollowUpExpand" type="button" aria-expanded="false">Expand list</button></div><div class="guardian-followup-scroll" id="guardianFollowUpScroll" data-tenant-scroll-ignore="1"><div id="guardianFollowUpRows"><div class="guardian-followup-empty"><span>Loading parent and guardian records…</span></div></div></div></section></div>`;
    bindTabs();
    bindFilters(false);
    byId("guardianFollowUpExpand")?.addEventListener("click", (event) => toggleScroll("guardianFollowUpScroll", event.currentTarget));
    await refreshFollowUp();
  }

  async function install() {
    installStyles();
    const runtime = await waitForRuntime();
    if (!runtime) return;
    if (!authReconcileBound && runtime.S?.client?.auth?.onAuthStateChange) {
      authReconcileBound = true;
      runtime.S.client.auth.onAuthStateChange(() => {
        state.active = false;
        state.data = null;
        state.history = null;
        state.requestToken += 1;
        setTimeout(ensureNav, 200);
        setTimeout(ensureNav, 800);
      });
    }
    ensureNav();
    const nav = byId("mainNav");
    if (nav) new MutationObserver(ensureNav).observe(nav, { childList: true });

    document.addEventListener("click", (event) => {
      if (!state.active) return;
      if (event.target.closest?.(".accountant-parent-followup-nav-item")) return;
      if (event.target.closest?.("#mainNav .nav-item")) state.active = false;
      if (event.target.closest?.("#refreshButton")) {
        event.preventDefault();
        event.stopImmediatePropagation();
        state.active = true;
        setNavActive();
        if (state.tab === "history") void refreshHistory(); else void refreshFollowUp();
      }
    }, true);

    window.addEventListener("pageshow", ensureNav, { passive: true });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => void install(), { once: true });
  else void install();
})();
