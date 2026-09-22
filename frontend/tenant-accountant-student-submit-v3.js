(() => {
  "use strict";
  if (window.EDS_ACCOUNTANT_STUDENT_SUBMIT_V3) return;
  window.EDS_ACCOUNTANT_STUDENT_SUBMIT_V3 = true;

  const EXTENDED_ROLES = new Set(["accountant", "student"]);
  let patchTimer = 0;

  const byId = (id) => document.getElementById(id);
  const roleValue = () => String(byId("userRoleSelect")?.value || "").trim();

  function submitExtendedForm(form) {
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit();
      return;
    }
    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
  }

  function patchForm() {
    const form = byId("userForm");
    const roleSelect = byId("userRoleSelect");
    const save = byId("userSave");
    if (!form || !roleSelect || !(save instanceof HTMLButtonElement)) return;

    form.autocomplete = "off";
    const password = byId("adminUserPassword");
    if (password) password.autocomplete = "new-password";
    const email = form.elements.email;
    if (email instanceof HTMLInputElement) email.autocomplete = "off";

    if (!save.__edsLegacyUserSaveHandler) {
      if (typeof save.onclick !== "function") {
        setTimeout(schedulePatch, 20);
        return;
      }
      save.__edsLegacyUserSaveHandler = save.onclick;
    }

    if (!save.__edsExtendedUserSaveHandler) {
      save.__edsExtendedUserSaveHandler = (event) => {
        if (!EXTENDED_ROLES.has(roleValue())) {
          return save.__edsLegacyUserSaveHandler?.call(save, event);
        }
        event?.preventDefault?.();
        event?.stopImmediatePropagation?.();
        submitExtendedForm(form);
      };
    }

    const apply = () => {
      const extended = EXTENDED_ROLES.has(roleValue());
      save.type = "button";
      save.dataset.extendedDirectoryRoute = extended ? "1" : "0";
      save.onclick = extended ? save.__edsExtendedUserSaveHandler : save.__edsLegacyUserSaveHandler;
    };

    if (!roleSelect.dataset.extendedRouteV3Bound) {
      roleSelect.dataset.extendedRouteV3Bound = "1";
      roleSelect.addEventListener("change", () => setTimeout(apply, 0));
    }
    apply();
  }

  function schedulePatch() {
    clearTimeout(patchTimer);
    patchTimer = setTimeout(patchForm, 25);
  }

  function loadUserAccessLinkageV4() {
    if (window.EDS_USER_ACCESS_LINKAGE_V4 || document.querySelector('script[data-edusentia-user-access-linkage-v4]')) return;
    const script = document.createElement("script");
    script.src = "tenant-user-access-linkage-v4.js?edusentia=r40-user-access-linkage-v4";
    script.defer = true;
    script.dataset.edusentiaUserAccessLinkageV4 = "1";
    script.addEventListener("error", () => console.error("user_access_linkage_v4_load_failed"), { once: true });
    document.body.appendChild(script);
  }

  function loadConsolidatedFinancePaymentsV1() {
    if (window.EDS_FINANCE_CONSOLIDATED_PAYMENTS_V1 || document.querySelector('script[data-edusentia-consolidated-finance-payments-v1]')) return;
    const script = document.createElement("script");
    script.src = "tenant-finance-consolidated-payments-v1.js?edusentia=r40-consolidated-finance-payments-v1";
    script.defer = true;
    script.dataset.edusentiaConsolidatedFinancePaymentsV1 = "1";
    script.addEventListener("error", () => console.error("consolidated_finance_payments_v1_load_failed"), { once: true });
    document.body.appendChild(script);
  }

  function loadSystemAdminFinanceTestCleanupV1() {
    if (window.EDS_SYSTEM_ADMIN_FINANCE_TEST_CLEANUP_V1 || document.querySelector('script[data-edusentia-system-admin-finance-test-cleanup-v1]')) return;
    const script = document.createElement("script");
    script.src = "tenant-system-admin-finance-test-cleanup-v1.js?edusentia=r40-system-admin-finance-test-cleanup-v1";
    script.defer = true;
    script.dataset.edusentiaSystemAdminFinanceTestCleanupV1 = "1";
    script.addEventListener("error", () => console.error("system_admin_finance_test_cleanup_v1_load_failed"), { once: true });
    document.body.appendChild(script);
  }

  const modal = byId("modal");
  if (modal) {
    new MutationObserver(schedulePatch).observe(modal, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["open"]
    });
  }

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (target?.closest("#createUserButton, [data-user-create], [data-user-edit]")) {
      setTimeout(schedulePatch, 0);
    }
  }, true);

  window.addEventListener("pageshow", () => {
    schedulePatch();
    loadUserAccessLinkageV4();
    loadConsolidatedFinancePaymentsV1();
    loadSystemAdminFinanceTestCleanupV1();
  }, { passive: true });
  schedulePatch();
  loadUserAccessLinkageV4();
  loadConsolidatedFinancePaymentsV1();
  loadSystemAdminFinanceTestCleanupV1();
})();
