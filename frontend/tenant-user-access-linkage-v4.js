(() => {
  "use strict";
  if (window.EDS_USER_ACCESS_LINKAGE_V4) return;
  window.EDS_USER_ACCESS_LINKAGE_V4 = true;

  const RELATIONSHIPS = Object.freeze([
    "Parent or Guardian",
    "Father",
    "Mother",
    "Legal Guardian",
    "Grandfather",
    "Grandmother",
    "Brother",
    "Sister",
    "Uncle",
    "Aunt",
    "Relative",
    "Other Guardian",
  ]);
  const USER_DATA_TTL_MS = 15000;

  const byId = (id) => document.getElementById(id);
  const F = () => window.EdusentiaFinanceRuntime || null;
  const esc = (value) => F()?.esc
    ? F().esc(value)
    : String(value ?? "").replace(/[&<>"']/g, (c) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
      }[c]));
  const attr = esc;

  let userDataCache = null;
  let userDataLoadedAt = 0;
  let guardianDataCache = null;
  let guardianDataLoadedAt = 0;
  let activeUserForm = null;
  let applyToken = 0;
  let applyTimer = 0;
  let pageObserver = null;
  let modalObserver = null;
  let credentialSource = null;
  let credentialRepairTimer = 0;
  let credentialReloading = false;
  let parentSubmitBusy = false;

  function runtimeRole() {
    return String(F()?.S?.role || F()?.S?.boot?.profile?.role || "");
  }

  async function waitForRuntime() {
    for (let i = 0; i < 240; i += 1) {
      const runtime = F();
      if (runtime?.S?.client && runtime?.S?.boot) return runtime;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return null;
  }

  async function rpc(name, args = {}) {
    const runtime = await waitForRuntime();
    if (!runtime) throw new Error("Tenant runtime is unavailable");
    return runtime.rpc(name, args);
  }

  function notify(title, message = "", kind = "info") {
    if (F()?.notify) F().notify(title, message, kind);
    else if (kind === "error") window.alert(`${title}${message ? `\n\n${message}` : ""}`);
  }

  function friendly(error) {
    return F()?.friendly?.(error) || String(error?.message || error || "Request failed");
  }

  async function loadUserData(force = false) {
    if (!force && userDataCache && Date.now() - userDataLoadedAt < USER_DATA_TTL_MS) return userDataCache;
    userDataCache = await rpc("list_profiles_with_access");
    userDataLoadedAt = Date.now();
    return userDataCache;
  }

  async function loadGuardianData(force = false) {
    if (!force && guardianDataCache && Date.now() - guardianDataLoadedAt < USER_DATA_TTL_MS) return guardianDataCache;
    const api = window.EdusentiaShell?.api;
    const data = typeof api?.guardianAccountRecords === "function"
      ? await api.guardianAccountRecords()
      : await rpc("admin_guardian_account_records");
    guardianDataCache = Array.isArray(data) ? data : Array.isArray(data?.rows) ? data.rows : [];
    guardianDataLoadedAt = Date.now();
    return guardianDataCache;
  }

  function ensureStyles() {
    if (byId("edsUserAccessLinkageV4Style")) return;
    const style = document.createElement("style");
    style.id = "edsUserAccessLinkageV4Style";
    style.textContent = `
      #edsStudentAccountClassFieldV4.hidden{display:none!important}
      #edsCredentialsWorkspaceLauncherPersistentV4{display:inline-flex;align-items:center;justify-content:center;min-height:40px;white-space:nowrap}
      .eds-user-record-help-v4{display:block;margin-top:5px;color:var(--muted,#64748b);font-size:10px;line-height:1.4}
    `;
    document.head.appendChild(style);
  }

  function patchGuardianRelationship() {
    const form = byId("studentForm");
    if (!form) return;
    const input = form.querySelector('input[name="relationship"]');
    if (!(input instanceof HTMLInputElement)) return;
    const current = String(input.value || "Parent or Guardian").trim() || "Parent or Guardian";
    const select = document.createElement("select");
    select.name = "relationship";
    select.id = input.id || "studentGuardianRelationship";
    select.required = true;
    const options = RELATIONSHIPS.includes(current) ? RELATIONSHIPS : [current, ...RELATIONSHIPS];
    select.innerHTML = options.map((value) => `<option value="${attr(value)}" ${value === current ? "selected" : ""}>${esc(value)}</option>`).join("");
    input.replaceWith(select);
  }

  function userFormExistingProfile(data, form) {
    const email = String(form.elements.email?.value || "").trim().toLowerCase();
    return (data?.profiles || []).find((profile) => String(profile.email || "").trim().toLowerCase() === email) || null;
  }

  function ensureClassField(staffField) {
    let field = byId("edsStudentAccountClassFieldV4");
    if (field) return field;
    field = document.createElement("label");
    field.id = "edsStudentAccountClassFieldV4";
    field.className = "field full hidden";
    field.innerHTML = '<span>Class</span><select id="edsStudentAccountClassSelectV4"><option value="">Select class</option></select><small class="eds-user-record-help-v4">Select a class first, then choose the student whose login account will be created.</small>';
    staffField.parentElement?.insertBefore(field, staffField);
    return field;
  }

  function childSummary(guardian) {
    const children = Array.isArray(guardian?.children) ? guardian.children : [];
    if (!children.length) return "No linked active student";
    const names = children.slice(0, 3).map((child) => `${child.student_name || "Student"}${child.class_name ? ` (${child.class_name})` : ""}`);
    if (children.length > 3) names.push(`+${children.length - 3} more`);
    return names.join(", ");
  }

  function syncReadonlyRecordFields(form, record, roleName) {
    const fullName = form.elements.full_name;
    const phone = form.elements.phone;
    if (fullName instanceof HTMLInputElement) {
      fullName.value = record?.full_name || "";
      fullName.readOnly = Boolean(record);
      fullName.dispatchEvent(new Event("input", { bubbles: true }));
    }
    if (phone instanceof HTMLInputElement) {
      phone.value = roleName === "parent_guardian" ? (record?.phone || "") : (record?.phone || "");
      phone.readOnly = roleName === "parent_guardian" && Boolean(record);
    }
    const email = form.elements.email;
    if (email instanceof HTMLInputElement && !email.value) email.placeholder = "Generated when the account is created";
  }

  function restoreEditableRecordFields(form) {
    const fullName = form.elements.full_name;
    const phone = form.elements.phone;
    if (fullName instanceof HTMLInputElement) fullName.readOnly = false;
    if (phone instanceof HTMLInputElement) phone.readOnly = false;
  }

  async function configureUserForm(force = false) {
    const form = byId("userForm");
    const roleSelect = byId("userRoleSelect");
    const staffField = byId("userStaffField");
    const staffSelect = byId("userStaffSelect");
    const staffLabel = byId("userStaffLabel");
    if (!(form instanceof HTMLFormElement) || !(roleSelect instanceof HTMLSelectElement) || !staffField || !(staffSelect instanceof HTMLSelectElement) || !staffLabel) return;

    const myToken = ++applyToken;
    activeUserForm = form;
    const [data, guardians] = await Promise.all([loadUserData(force), loadGuardianData(force)]);
    if (myToken !== applyToken || byId("userForm") !== form) return;

    const existing = userFormExistingProfile(data, form);
    const currentUserId = String(existing?.id || "");
    const classField = ensureClassField(staffField);
    const classSelect = byId("edsStudentAccountClassSelectV4");
    const accessSection = byId("userAccessSection");

    const apply = () => {
      if (byId("userForm") !== form) return;
      const selectedRole = String(roleSelect.value || "");
      const teachingRole = selectedRole === "class_teacher" || selectedRole === "subject_teacher";
      accessSection?.classList.toggle("hidden", !teachingRole);

      if (selectedRole === "student") {
        restoreEditableRecordFields(form);
        classField.classList.remove("hidden");
        staffField.classList.remove("hidden");
        staffSelect.required = true;
        if (classSelect) classSelect.required = true;
        staffLabel.textContent = "Student record";

        const allCandidates = (data.student_records || []).filter((row) => !row.profile_id || String(row.profile_id) === currentUserId);
        const selectedStudentId = String(existing?.student_id || staffSelect.value || "");
        const selectedRecord = allCandidates.find((row) => String(row.id) === selectedStudentId);
        const selectedClassId = String(classSelect?.value || selectedRecord?.class_id || "");
        const classRows = (data.classes || []).filter((row) => row.active !== false && !row.deleted_at);
        if (classSelect) {
          classSelect.innerHTML = `<option value="">Select class</option>${classRows.map((row) => `<option value="${attr(row.id)}" ${String(row.id) === selectedClassId ? "selected" : ""}>${esc(row.name)}</option>`).join("")}`;
        }

        const classId = String(classSelect?.value || selectedClassId || "");
        const candidates = allCandidates.filter((row) => classId && String(row.class_id || "") === classId);
        staffSelect.innerHTML = `<option value="">${classId ? "Select student" : "Select a class first"}</option>${candidates.map((row) => `<option value="${attr(row.id)}" ${String(row.id) === selectedStudentId ? "selected" : ""}>${esc(row.label || row.full_name)}${row.class_name ? ` • ${esc(row.class_name)}` : ""}</option>`).join("")}`;
        staffSelect.disabled = !classId;
        const record = candidates.find((row) => String(row.id) === String(staffSelect.value));
        if (record) syncReadonlyRecordFields(form, record, selectedRole);
        return;
      }

      classField.classList.add("hidden");
      if (classSelect) classSelect.required = false;

      if (selectedRole === "parent_guardian") {
        staffField.classList.remove("hidden");
        staffSelect.disabled = false;
        staffSelect.required = true;
        staffLabel.textContent = "Parent / Guardian record";
        const selectedGuardianId = String(
          guardians.find((row) => String(row.auth_user_id || "") === currentUserId)?.id || staffSelect.value || "",
        );
        const candidates = guardians.filter((row) => !row.auth_user_id || String(row.auth_user_id) === currentUserId);
        staffSelect.innerHTML = `<option value="">Select Parent or Guardian</option>${candidates.map((row) => {
          const relationship = row.relationship || "Parent or Guardian";
          const children = childSummary(row);
          return `<option value="${attr(row.id)}" ${String(row.id) === selectedGuardianId ? "selected" : ""}>${esc(row.full_name)} • ${esc(relationship)} • ${esc(children)}</option>`;
        }).join("")}`;
        const record = candidates.find((row) => String(row.id) === String(staffSelect.value));
        syncReadonlyRecordFields(form, record || null, selectedRole);
        return;
      }

      if (selectedRole !== "accountant" && selectedRole !== "principal" && selectedRole !== "class_teacher" && selectedRole !== "subject_teacher") {
        staffField.classList.add("hidden");
        staffSelect.required = false;
        staffSelect.disabled = false;
        restoreEditableRecordFields(form);
      } else if (selectedRole !== "accountant") {
        restoreEditableRecordFields(form);
      }
    };

    if (roleSelect.dataset.userAccessLinkageV4 !== "1") {
      roleSelect.dataset.userAccessLinkageV4 = "1";
      roleSelect.addEventListener("change", () => setTimeout(apply, 35));
      classSelect?.addEventListener("change", () => {
        staffSelect.value = "";
        setTimeout(apply, 0);
      });
      staffSelect.addEventListener("change", () => {
        const roleName = String(roleSelect.value || "");
        if (roleName === "student") {
          const record = (data.student_records || []).find((row) => String(row.id) === String(staffSelect.value));
          syncReadonlyRecordFields(form, record || null, roleName);
        } else if (roleName === "parent_guardian") {
          const record = guardians.find((row) => String(row.id) === String(staffSelect.value));
          syncReadonlyRecordFields(form, record || null, roleName);
        }
      });
    }
    setTimeout(apply, 35);
  }

  async function invokeDirectoryUser(action, payload) {
    const api = window.EdusentiaShell?.api;
    if (typeof api?.directoryUserManagement === "function") {
      return api.directoryUserManagement(action, payload);
    }
    const runtime = await waitForRuntime();
    if (!runtime) throw new Error("Tenant runtime is unavailable");
    const { data, error } = await runtime.S.client.functions.invoke("directory-user-management", {
      body: { action, payload },
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.message || data.error);
    return data;
  }

  async function submitParentGuardian(form) {
    if (parentSubmitBusy) return;
    parentSubmitBusy = true;
    const save = byId("userSave");
    if (save instanceof HTMLButtonElement) save.disabled = true;
    try {
      const guardians = await loadGuardianData(true);
      const guardianId = String(byId("userStaffSelect")?.value || "");
      const guardian = guardians.find((row) => String(row.id) === guardianId);
      if (!guardian) throw new Error("Select the Parent or Guardian record linked to the student");
      if (Number(guardian.linked_account_count || 0) > 1) throw new Error("This guardian record has conflicting portal-account links and must be reviewed before continuing");

      const existingId = String(guardian.auth_user_id || "");
      const password = String(byId("adminUserPassword")?.value || "");
      if (!existingId && password.length < 8) throw new Error("Use a password of at least eight characters");
      const payload = {
        role: "parent_guardian",
        guardian_record_id: guardianId,
        user_id: existingId || null,
        active: form.elements.active?.checked !== false,
        mfa_required: form.elements.mfa_required?.checked === true,
        must_change_password: form.elements.must_change_password?.checked === true,
        password,
      };
      const result = await invokeDirectoryUser(existingId ? "update" : "create", payload);
      byId("modal")?.close?.();
      userDataCache = null;
      guardianDataCache = null;
      notify(existingId ? "Parent or Guardian account updated" : "Parent or Guardian account created", result?.email ? `Sign-in email: ${result.email}` : "");
      setTimeout(() => document.querySelector('[data-view="users"]')?.click(), 40);
    } catch (error) {
      notify("Parent or Guardian account was not saved", friendly(error), "error");
    } finally {
      parentSubmitBusy = false;
      const current = byId("userSave");
      if (current instanceof HTMLButtonElement) current.disabled = false;
    }
  }

  function captureCredentialSource() {
    const original = byId("edsCredentialsWorkspaceLauncherV3");
    if (original && original !== byId("edsCredentialsWorkspaceLauncherPersistentV4")) credentialSource = original;
    if (!credentialSource || !credentialSource.isConnected) {
      const rowButton = document.querySelector(".eds-user-credential-button-v3");
      if (rowButton) credentialSource = rowButton;
    }
  }

  function triggerCredentialWorkspace() {
    captureCredentialSource();
    if (credentialSource) {
      credentialSource.click();
      return;
    }
    const existingDialog = byId("edsCredentialsWorkspaceDialogV3");
    if (existingDialog) {
      try { existingDialog.showModal(); }
      catch { existingDialog.setAttribute("open", ""); }
      return;
    }
    notify("Credentials are reloading", "The credential workspace is being restored. Please click Credentials again in a moment.");
    reloadCredentialV3();
  }

  function reloadCredentialV3() {
    if (credentialReloading || runtimeRole() !== "system_admin") return;
    credentialReloading = true;
    window.EDS_USER_CREDENTIAL_ACTIONS_V3 = false;
    const script = document.createElement("script");
    script.src = `tenant-user-credential-actions-v3.js?edusentia=r40-user-credentials-v4-repair-${Date.now()}`;
    script.defer = true;
    script.addEventListener("load", () => {
      credentialReloading = false;
      setTimeout(() => {
        captureCredentialSource();
        ensurePersistentCredentialLauncher();
      }, 140);
    }, { once: true });
    script.addEventListener("error", () => { credentialReloading = false; }, { once: true });
    document.body.appendChild(script);
  }

  function ensurePersistentCredentialLauncher() {
    ensureStyles();
    if (runtimeRole() !== "system_admin") return;
    const createButton = byId("userCreateButton") || byId("createUserButton");
    const userResults = byId("userResults");
    const persistent = byId("edsCredentialsWorkspaceLauncherPersistentV4");
    if (!createButton && !userResults) {
      persistent?.remove();
      return;
    }

    captureCredentialSource();
    if (byId("edsCredentialsWorkspaceLauncherV3")) {
      persistent?.remove();
      return;
    }

    if (!credentialSource && !credentialReloading) reloadCredentialV3();
    if (byId("edsCredentialsWorkspaceLauncherPersistentV4")) return;

    const button = document.createElement("button");
    button.id = "edsCredentialsWorkspaceLauncherPersistentV4";
    button.type = "button";
    button.className = "button secondary";
    button.textContent = "Credentials";
    button.addEventListener("click", triggerCredentialWorkspace);
    if (createButton?.parentElement) createButton.parentElement.insertBefore(button, createButton);
    else if (userResults?.parentElement) {
      const bar = document.createElement("div");
      bar.style.display = "flex";
      bar.style.justifyContent = "flex-end";
      bar.style.marginBottom = "10px";
      bar.dataset.edsPersistentCredentialBar = "1";
      bar.appendChild(button);
      userResults.parentElement.insertBefore(bar, userResults);
    }
  }

  function scheduleApply(force = false) {
    clearTimeout(applyTimer);
    applyTimer = setTimeout(() => {
      patchGuardianRelationship();
      ensurePersistentCredentialLauncher();
      if (byId("userForm")) {
        configureUserForm(force).catch((error) => console.warn("user_access_linkage_v4_form_failed", error));
      }
    }, 45);
  }

  function startObservers() {
    const content = byId("content");
    if (content && !pageObserver) {
      pageObserver = new MutationObserver(() => scheduleApply(false));
      pageObserver.observe(content, { childList: true, subtree: true });
    }
    const modal = byId("modal");
    if (modal && !modalObserver) {
      modalObserver = new MutationObserver(() => scheduleApply(false));
      modalObserver.observe(modal, { childList: true, subtree: true, attributes: true, attributeFilter: ["open"] });
    }
  }

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) return;
    if (target.closest('[data-view="users"],#userCreateButton,#createUserButton,[data-user-create],[data-user-edit]')) {
      setTimeout(() => scheduleApply(true), 20);
    }
    if (target.closest("#userSave") && String(byId("userRoleSelect")?.value || "") === "parent_guardian") {
      event.preventDefault();
      event.stopImmediatePropagation();
      const form = byId("userForm");
      if (form instanceof HTMLFormElement) {
        if (typeof form.requestSubmit === "function") form.requestSubmit();
        else form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
      }
    }
  }, true);

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || form.id !== "userForm") return;
    if (String(byId("userRoleSelect")?.value || "") !== "parent_guardian") return;
    event.preventDefault();
    event.stopImmediatePropagation();
    void submitParentGuardian(form);
  }, true);

  window.addEventListener("pageshow", () => scheduleApply(true), { passive: true });
  window.addEventListener("focus", () => ensurePersistentCredentialLauncher(), { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) ensurePersistentCredentialLauncher();
  });

  ensureStyles();
  startObservers();
  scheduleApply(true);
  clearInterval(credentialRepairTimer);
  credentialRepairTimer = window.setInterval(() => {
    startObservers();
    ensurePersistentCredentialLauncher();
  }, 1500);
})();
