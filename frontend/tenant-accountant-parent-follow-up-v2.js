(() => {
  "use strict";
  if (window.EDS_ACCOUNTANT_PARENT_FOLLOW_UP_V2) return;
  window.EDS_ACCOUNTANT_PARENT_FOLLOW_UP_V2 = true;

  const byId = (id) => document.getElementById(id);
  const F = () => window.EdusentiaFinanceRuntime || null;
  let observer = null;
  let scheduled = false;

  function isAccountant() {
    return String(F()?.S?.role || "") === "accountant";
  }

  function notify(title, message = "", kind = "info") {
    if (F()?.notify) F().notify(title, message, kind);
    else if (typeof window.EdusentiaNotify === "function") window.EdusentiaNotify(title, message, kind);
    else console[kind === "error" ? "error" : "log"](title, message);
  }

  function friendly(error) {
    return F()?.friendly?.(error) || String(error?.message || error || "Request failed");
  }

  function installStyles() {
    if (byId("edsAccountantParentFollowUpStyleV2")) return;
    const style = document.createElement("style");
    style.id = "edsAccountantParentFollowUpStyleV2";
    style.textContent = `
      .guardian-followup-history-scroll{max-height:300px!important;overflow-y:auto!important;overscroll-behavior:contain;scrollbar-gutter:stable}
      .guardian-followup-history-scroll.expanded{max-height:70vh!important}
      .guardian-followup-history-actions-v2{display:flex;align-items:center;gap:8px;flex-wrap:wrap;justify-content:flex-end}
      #guardianHistoryResetAll.button{white-space:nowrap}
      @media(max-width:640px){.guardian-followup-history-scroll{max-height:280px!important}.guardian-followup-history-actions-v2{width:100%;justify-content:flex-start}.guardian-followup-panel-head:has(#guardianHistoryResetAll){flex-wrap:wrap}}
    `;
    document.head.appendChild(style);
  }

  async function clearAllHistory(dialog) {
    const button = byId("guardianHistoryConfirmResetAll");
    if (button) {
      button.disabled = true;
      button.textContent = "Clearing…";
    }
    try {
      const result = await F().rpc("finance_clear_guardian_contact_history");
      dialog?.close?.();
      notify(
        "Contact history cleared",
        `${Number(result?.cleared || 0).toLocaleString("en-GH")} contact action${Number(result?.cleared || 0) === 1 ? "" : "s"} removed.`,
      );
      const refresh = byId("guardianFollowUpRefresh");
      if (refresh) refresh.click();
    } catch (error) {
      notify("Contact history was not cleared", friendly(error), "error");
      if (button) {
        button.disabled = false;
        button.textContent = "Clear history";
      }
    }
  }

  function openResetConfirmation() {
    const runtime = F();
    if (!runtime?.dialog || !isAccountant()) return;
    const dialog = runtime.dialog(
      "Clear Contact History",
      "Permanently remove every Parent & Guardian Follow-up contact-history record in this school workspace.",
    );
    const body = byId("financeDialogBody");
    if (!body) return;
    body.innerHTML = `
      <div class="template-information warning">
        <strong>Clear all recorded contact actions?</strong>
        <span>This removes SMS opened, WhatsApp opened, call opened, and copied-message history for all academic years and terms. Parent, student, fee, and guardian records are not changed. This action cannot be undone.</span>
      </div>
      <div class="button-row" style="margin-top:16px">
        <button class="button danger" id="guardianHistoryConfirmResetAll" type="button">Clear history</button>
        <button class="button ghost" id="guardianHistoryCancelResetAll" type="button">Cancel</button>
      </div>`;
    byId("guardianHistoryConfirmResetAll")?.addEventListener("click", () => void clearAllHistory(dialog));
    byId("guardianHistoryCancelResetAll")?.addEventListener("click", () => dialog.close());
    dialog.showModal();
  }

  function decorateHistoryHeader() {
    if (!isAccountant()) return;
    const expand = byId("guardianHistoryExpand");
    if (!expand || byId("guardianHistoryResetAll")) return;

    const header = expand.closest(".guardian-followup-panel-head");
    if (!header) return;

    let actions = header.querySelector(".guardian-followup-history-actions-v2");
    if (!actions) {
      actions = document.createElement("div");
      actions.className = "guardian-followup-history-actions-v2";
      header.appendChild(actions);
    }
    actions.appendChild(expand);

    const reset = document.createElement("button");
    reset.id = "guardianHistoryResetAll";
    reset.type = "button";
    reset.className = "button danger small";
    reset.textContent = "Reset all";
    reset.title = "Clear all contact history";
    reset.addEventListener("click", openResetConfirmation);
    actions.insertBefore(reset, expand);
  }

  function apply() {
    scheduled = false;
    installStyles();
    decorateHistoryHeader();
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(apply);
  }

  function start() {
    installStyles();
    const content = byId("content");
    if (!content) {
      setTimeout(start, 100);
      return;
    }
    if (!observer) {
      observer = new MutationObserver(schedule);
      observer.observe(content, { childList: true, subtree: true });
    }
    schedule();
  }

  document.addEventListener("click", (event) => {
    if (event.target.closest('[data-guardian-followup-tab="history"],#guardianFollowUpRefresh')) setTimeout(schedule, 0);
  }, true);
  window.addEventListener("pageshow", schedule, { passive: true });

  start();
})();
