(() => {
  "use strict";
  if (window.EDS_ACCOUNTANT_STUDENT_ROLES_V2) return;
  window.EDS_ACCOUNTANT_STUDENT_ROLES_V2 = true;
  // Compatibility flags prevent older cached integration overlays from attaching duplicate observers.
  window.EDS_ACCOUNTANT_STUDENT_ROLES_V1 = true;
  window.EDS_ACCOUNTS_DIRECTORY_V2 = true;

  const ROLE_LABELS = Object.freeze({ accountant: "Accountant", student: "Student" });
  const DIRECTORY_SESSION_KEY = "edusentia_accounts_office_directory_active";
  const USER_CACHE_TTL_MS = 15000;
  const SEARCH_DEBOUNCE_MS = 280;

  let directoryActive = sessionStorage.getItem(DIRECTORY_SESSION_KEY) === "1";
  let directoryRendering = false;
  let directoryRenderToken = 0;
  let directoryRestoreTimer = 0;
  let accountantAutoOpened = false;
  let userDataCache = null;
  let userDataLoadedAt = 0;
  let pendingCredential = null;
  let contentPatchTimer = 0;
  let modalPatchTimer = 0;

  const byId = (id) => document.getElementById(id);
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const F = () => window.EdusentiaFinanceRuntime || null;
  const esc = (value) => F()?.esc ? F().esc(value) : String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));
  const attr = esc;
  const currentRole = () => String(F()?.S?.role || "");

  async function waitForRuntime() {
    for (let i = 0; i < 240; i += 1) {
      if (F()?.S?.client && F()?.S?.boot) return F();
      await sleep(100);
    }
    return null;
  }

  async function rpc(name, args = {}) {
    const runtime = await waitForRuntime();
    if (!runtime) throw new Error("Tenant runtime is unavailable");
    return runtime.rpc(name, args);
  }

  function notify(title, message = "", kind = "info") {
    F()?.notify?.(title, message, kind);
  }

  function setDirectoryActive(value) {
    directoryActive = Boolean(value);
    if (directoryActive) sessionStorage.setItem(DIRECTORY_SESSION_KEY, "1");
    else sessionStorage.removeItem(DIRECTORY_SESSION_KEY);
  }

  function setRoleLabel() {
    const role = currentRole();
    if (ROLE_LABELS[role] && byId("userRole")) byId("userRole").textContent = ROLE_LABELS[role];
  }

  function hideSystemAdminFinance() {
    if (currentRole() !== "system_admin") return;
    document.querySelectorAll(".finance-nav-item").forEach((node) => {
      node.style.display = "none";
      node.setAttribute("aria-hidden", "true");
      node.tabIndex = -1;
    });
    if (F()?.S) F().S.active = false;
  }

  function setExternalNavActive(button) {
    const nav = byId("mainNav");
    nav?.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
    button?.classList.add("active");
  }

  function ensureAccountantFinance() {
    const runtime = F(), accounts = window.EdusentiaFinanceAccounts;
    if (!runtime || !accounts || currentRole() !== "accountant") return;

    if (!accounts.__accountantRoleInstalledV2) {
      accounts.__accountantRoleInstalledV2 = true;
      runtime.register("accountant", async () => {
        await accounts.render();
        const payroll = runtime.hasFeature?.("payroll") === true;
        const title = payroll ? "Finance & Payroll" : "Finance";
        const subtitle = payroll
          ? "Fees, statements, receipts, financial clearance and payroll operations"
          : "Fees, statements, receipts and finance operations";
        runtime.heading?.(title, subtitle);
        const head = byId("content")?.querySelector(".finance-workspace .page-head");
        if (head) {
          const h = head.querySelector("h3"), p = head.querySelector("p");
          if (h) h.textContent = title;
          if (p) p.textContent = subtitle;
        }
        byId("content")?.querySelectorAll('[data-finance-tab="staff"]').forEach((node) => node.remove());
      });
    }

    const nav = byId("mainNav");
    if (!nav) return;
    let button = nav.querySelector(".accountant-finance-nav-item");
    document.querySelectorAll(".finance-nav-item:not(.accountant-finance-nav-item)").forEach((node) => node.style.display = "none");
    if (!button) {
      button = document.createElement("button");
      button.type = "button";
      button.className = "nav-item finance-nav-item accountant-finance-nav-item";
      button.innerHTML = '<span class="nav-icon">₵</span><span class="nav-label">Finance</span><span class="nav-active-dot"></span>';
      button.addEventListener("click", async () => {
        setDirectoryActive(false);
        setExternalNavActive(button);
        await runtime.open();
      });
      nav.appendChild(button);
    }
    button.style.display = "";
    if (!accountantAutoOpened && byId("appShell") && !byId("appShell").classList.contains("hidden")) {
      accountantAutoOpened = true;
      setTimeout(() => button.click(), 0);
    }
  }

  function ensureAccountsDirectoryNav() {
    const nav = byId("mainNav");
    if (!nav) return;
    const existing = nav.querySelector(".accounts-directory-nav-item");
    if (currentRole() === "system_admin") {
      existing?.remove();
      setDirectoryActive(false);
      return;
    }
    existing?.remove();
  }

  function directoryTable(rows) {
    return rows.length ? `<div class="table-wrap"><table><thead><tr><th>Staff</th><th>Contact</th><th>Address</th><th>Login</th><th>Status</th><th></th></tr></thead><tbody>${rows.map((row) => {
      const active = Boolean(row.active && !row.deleted_at);
      const unlinked = !row.profile_id;
      return `<tr>
        <td><div class="cell-copy"><strong>${esc(row.full_name)}</strong><small>${esc(row.staff_no || "")}</small></div></td>
        <td>${esc(row.phone || "—")}<small>${esc(row.email || "")}</small></td>
        <td>${esc(row.contact_address || "—")}</td>
        <td>${row.profile_id ? `<span class="status published">${esc(row.portal_email || "Linked")}</span>` : '<span class="status draft">Not created</span>'}</td>
        <td>${active ? '<span class="status published">Active</span>' : '<span class="status withdrawn">Inactive</span>'}</td>
        <td><div class="table-actions">
          <button class="button ghost small" data-accountant-edit="${attr(row.id)}">Edit</button>
          ${active ? `<button class="button secondary small" data-accountant-delete="${attr(row.id)}">Archive</button>` : ""}
        </div></td>
      </tr>`;
    }).join("")}</tbody></table></div>` : '<div class="empty"><strong>No Accounts Office Staff records</strong><span>Add an Accountant directory record to begin.</span></div>';
  }

  function bindDirectoryActions(rows) {
    document.querySelectorAll("[data-accountant-edit]").forEach((button) => button.addEventListener("click", () => {
      openAccountantDirectoryEditor(rows.find((x) => String(x.id) === String(button.dataset.accountantEdit)));
    }));

    document.querySelectorAll("[data-accountant-delete]").forEach((button) => button.addEventListener("click", async () => {
      const row = rows.find((x) => String(x.id) === String(button.dataset.accountantDelete));
      if (!row) return;
      const reason = F()?.askReason
        ? await F().askReason("Archive Accounts Office Staff", "The directory record will be archived so historical financial audit records remain intact and recoverable.", "Archive")
        : (window.prompt("Reason for deleting this Accounts Office Staff record:") || "");
      if (!reason) return;
      button.disabled = true;
      try {
        await rpc("admin_deactivate_accounts_staff", { target_staff_id: row.id, reason_text: reason });
        notify("Accounts Office Staff archived", "The directory record was retained as inactive and any linked login was deactivated.");
        userDataCache = null;
        setDirectoryActive(true);
        await renderAccountsDirectory();
      } catch (error) {
        notify("Staff record was not archived", F()?.friendly?.(error) || String(error), "error");
        button.disabled = false;
      }
    }));

  }

  async function renderAccountsDirectory() {
    if (!directoryActive || currentRole() !== "system_admin" || directoryRendering) return;
    const content = byId("content");
    if (!content) return;
    const token = ++directoryRenderToken;
    directoryRendering = true;
    if (byId("pageTitle")) byId("pageTitle").textContent = "Accounts Office Staff";
    if (byId("pageSubtitle")) byId("pageSubtitle").textContent = "Accountant directory records and login linkage";
    setExternalNavActive(document.querySelector("#mainNav .accounts-directory-nav-item"));
    content.innerHTML = '<div data-accountant-directory-loading="1" class="panel pad"><div class="skeleton"></div></div>';
    try {
      const data = await rpc("admin_accounts_staff_directory", { search_text: "", include_inactive: true });
      if (!directoryActive || token !== directoryRenderToken) return;
      const rows = data?.rows || [];
      content.innerHTML = `<div data-accountant-directory-root="1">
        <div class="page-head"><div><h3>Accounts Office Staff</h3><p>Add and maintain Accountant directory records. Login accounts are created separately in Users and Access.</p></div><div class="page-actions"><button class="button primary" id="accountantDirectoryAdd">Add Accounts Office Staff</button></div></div>
        <section class="panel"><div class="toolbar"><label class="search"><input id="accountantDirectorySearch" type="search" placeholder="Search staff name, number, phone, email or address"></label></div>
        <div id="accountantDirectoryRows">${directoryTable(rows)}</div></section></div>`;
      byId("accountantDirectoryAdd")?.addEventListener("click", () => openAccountantDirectoryEditor());
      bindDirectoryActions(rows);

      const search = byId("accountantDirectorySearch");
      if (search) {
        let searchTimer = 0;
        let searchToken = 0;
        search.addEventListener("input", () => {
          clearTimeout(searchTimer);
          const q = String(search.value || "").trim();
          const myToken = ++searchToken;
          searchTimer = setTimeout(async () => {
            try {
              const next = await rpc("admin_accounts_staff_directory", { search_text: q, include_inactive: true });
              if (myToken !== searchToken || !directoryActive) return;
              const holder = byId("accountantDirectoryRows");
              if (holder) holder.innerHTML = directoryTable(next?.rows || []);
              bindDirectoryActions(next?.rows || []);
            } catch (error) {
              notify("Directory search failed", F()?.friendly?.(error) || String(error), "error");
            }
          }, SEARCH_DEBOUNCE_MS);
        });
      }
    } catch (error) {
      if (token === directoryRenderToken) {
        content.innerHTML = `<section class="panel pad"><strong>Accounts Office Staff directory could not be loaded</strong><p>${esc(F()?.friendly?.(error) || String(error))}</p></section>`;
      }
    } finally {
      if (token === directoryRenderToken) directoryRendering = false;
    }
  }

  function openAccountantDirectoryEditor(row = {}) {
    const runtime = F();
    if (!runtime?.dialog) return;
    const d = runtime.dialog(row.id ? "Edit Accounts Office Staff" : "Add Accounts Office Staff", "The corresponding login role will be Accountant and is created separately in Users and Access.");
    byId("financeDialogBody").innerHTML = `<form id="accountantDirectoryForm" class="finance-form">
      <label><span>Full name</span><input name="full_name" value="${attr(row.full_name || "")}" required></label>
      <label><span>Phone</span><input name="phone" value="${attr(row.phone || "")}"></label>
      <label><span>Email</span><input name="email" type="email" value="${attr(row.email || "")}"></label>
      <label><span>Contact address</span><input name="contact_address" value="${attr(row.contact_address || "")}"></label>
      <div class="full"><small class="help-text">Portal role: <strong>Accountant</strong>. Create the login later under Users and Access.</small></div>
      <div class="button-row full"><button class="button primary" type="submit">Save staff</button><button class="button ghost" id="accountantDirectoryCancel" type="button">Cancel</button></div>
    </form>`;
    const form = byId("accountantDirectoryForm");
    byId("accountantDirectoryCancel")?.addEventListener("click", () => d.close());
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const fd = new FormData(form), button = form.querySelector('button[type="submit"]');
      button.disabled = true;
      try {
        await rpc("admin_save_accounts_staff", { payload: {
          id: row.id || null,
          full_name: fd.get("full_name"),
          phone: fd.get("phone"),
          email: fd.get("email"),
          contact_address: fd.get("contact_address"),
          active: true
        }});
        d.close();
        userDataCache = null;
        setDirectoryActive(true);
        notify("Accounts Office Staff saved");
        await renderAccountsDirectory();
      } catch (error) {
        notify("Staff record not saved", F()?.friendly?.(error) || String(error), "error");
      } finally {
        button.disabled = false;
      }
    });
    d.showModal();
  }

  function scheduleDirectoryRestore() {
    if (!directoryActive || directoryRendering || currentRole() !== "system_admin") return;
    clearTimeout(directoryRestoreTimer);
    directoryRestoreTimer = setTimeout(() => {
      if (!directoryActive || directoryRendering || currentRole() !== "system_admin") return;
      const root = byId("content")?.querySelector('[data-accountant-directory-root="1"], [data-accountant-directory-loading="1"]');
      if (root) return;
      void renderAccountsDirectory();
    }, 90);
  }

  async function loadUserData(force = false) {
    if (!force && userDataCache && Date.now() - userDataLoadedAt < USER_CACHE_TTL_MS) return userDataCache;
    userDataCache = await rpc("list_profiles_with_access");
    userDataLoadedAt = Date.now();
    return userDataCache;
  }

  function addOption(select, value, label) {
    if (!select || [...select.options].some((o) => o.value === value)) return;
    const option = document.createElement("option");
    option.value = value;
    option.textContent = label;
    select.appendChild(option);
  }

  function labelUserRows() {
    document.querySelectorAll("#userResults tbody tr").forEach((row) => {
      const roleCell = row.children?.[1];
      if (!roleCell) return;
      const value = roleCell.textContent.trim();
      if (ROLE_LABELS[value]) roleCell.textContent = ROLE_LABELS[value];
    });
  }

  async function configureExtendedRoleEditor() {
    const roleSelect = byId("userRoleSelect"), form = byId("userForm");
    if (!roleSelect || !form) return;
    addOption(roleSelect, "accountant", "Accountant");
    addOption(roleSelect, "student", "Student");
    if (roleSelect.dataset.extendedRoleEditorV2 === "1") return;
    roleSelect.dataset.extendedRoleEditorV2 = "1";

    const data = await loadUserData();
    const email = String(form.elements.email?.value || "").trim().toLowerCase();
    const existing = (data.profiles || []).find((p) => String(p.email || "").trim().toLowerCase() === email);
    if (existing && ["accountant", "student"].includes(existing.role) && roleSelect.value !== existing.role) roleSelect.value = existing.role;

    const apply = () => {
      const selectedRole = roleSelect.value;
      const extended = selectedRole === "accountant" || selectedRole === "student";
      const field = byId("userStaffField"), select = byId("userStaffSelect"), label = byId("userStaffLabel");
      if (!extended) {
        if (form.elements.full_name) form.elements.full_name.readOnly = false;
        byId("userAccessSection")?.classList.remove("hidden");
        return;
      }
      if (!field || !select || !label) return;
      field.classList.remove("hidden");
      select.required = true;
      label.textContent = selectedRole === "accountant" ? "Accounts Office Staff record" : "Student record";
      const rows = selectedRole === "accountant" ? (data.accountant_records || []) : (data.student_records || []);
      const currentId = existing?.id || "";
      const candidates = rows.filter((r) => !r.profile_id || String(r.profile_id) === String(currentId));
      const selected = existing?.staff_record_id || select.value || "";
      select.innerHTML = `<option value="">Select ${selectedRole === "accountant" ? "Accounts Office Staff" : "Student"}</option>${candidates.map((r) => `<option value="${attr(r.id)}" ${String(r.id) === String(selected) ? "selected" : ""}>${esc(r.label || r.full_name)}</option>`).join("")}`;
      const sync = () => {
        const record = candidates.find((r) => String(r.id) === String(select.value));
        if (!record) return;
        if (form.elements.full_name) {
          form.elements.full_name.value = record.full_name || "";
          form.elements.full_name.readOnly = true;
          form.elements.full_name.dispatchEvent(new Event("input", { bubbles: true }));
        }
        if (form.elements.phone) form.elements.phone.value = selectedRole === "accountant" ? (record.phone || "") : (record.phone || "");
        if (form.elements.email && !form.elements.email.value) form.elements.email.placeholder = "Generated when the account is created";
      };
      select.onchange = sync;
      sync();
      byId("userAccessSection")?.classList.add("hidden");
    };

    roleSelect.addEventListener("change", () => setTimeout(apply, 0));
    apply();
  }

  function installPasswordVisibility() {
    const input = byId("adminUserPassword");
    if (!input || input.dataset.visibilityV2 === "1") return;
    input.dataset.visibilityV2 = "1";
    const wrap = input.closest(".password-wrap") || input.parentElement;
    if (!wrap) return;
    const generate = byId("generateUserPassword");
    const toggle = document.createElement("button");
    toggle.id = "toggleUserPasswordVisibility";
    toggle.type = "button";
    toggle.className = "button ghost small";
    const sync = () => {
      const visible = input.type === "text";
      toggle.textContent = visible ? "Hide" : "Show";
      toggle.setAttribute("aria-pressed", visible ? "true" : "false");
      toggle.setAttribute("aria-label", visible ? "Hide password" : "Show password");
    };
    toggle.addEventListener("click", () => {
      input.type = input.type === "password" ? "text" : "password";
      sync();
      input.focus();
    });
    if (generate) wrap.insertBefore(toggle, generate);
    else wrap.appendChild(toggle);
    generate?.addEventListener("click", () => setTimeout(sync, 0));
    sync();
  }

  function roleLabel(value) {
    return ROLE_LABELS[value] || String(value || "User").replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function signInUrl() {
    try {
      const url = new URL(window.location.href);
      url.hash = "";
      url.searchParams.delete("platform");
      const tenantCode = String(F()?.cfg?.()?.tenantCode || window.RCE_CONFIG?.tenantCode || window.NIS_CONFIG?.tenantCode || "").trim();
      if (tenantCode) url.searchParams.set("tenant", tenantCode);
      return url.toString();
    } catch {
      return window.location.href;
    }
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
      document.body.appendChild(area);
      area.select();
      const ok = document.execCommand("copy");
      area.remove();
      return ok;
    }
  }

  function credentialMessage(data) {
    const school = F()?.schoolName?.() || window.RCE_CONFIG?.schoolName || window.NIS_CONFIG?.schoolName || "Your school";
    const lines = [
      `${school} - Edusentia login`,
      "",
      `Name: ${data.fullName || "User"}`,
      `Role: ${roleLabel(data.role)}`,
      `Email: ${data.email}`,
      `Password: ${data.password}`,
      `Sign in: ${signInUrl()}`
    ];
    if (data.mustChange) lines.push("You will be required to change this password after signing in.");
    if (data.mfaRequired) lines.push("Multi-factor authentication is required for this account.");
    lines.push("Please keep these credentials private.");
    return lines.join("\n");
  }

  function normalizeWhatsAppPhone(value) {
    let phone = String(value || "").trim().replace(/[^0-9+]/g, "");
    if (phone.startsWith("00")) phone = phone.slice(2);
    if (phone.startsWith("+")) phone = phone.slice(1);
    return phone.replace(/\D/g, "");
  }

  function ensureCredentialDialog() {
    let dialog = byId("edsCredentialDialog");
    if (dialog) return dialog;
    dialog = document.createElement("dialog");
    dialog.id = "edsCredentialDialog";
    dialog.className = "modal";
    dialog.innerHTML = `<div class="modal-frame" style="max-width:760px">
      <header class="modal-header"><div><h3>Login credentials created</h3><p>Copy or share the sign-in details securely.</p></div><button class="icon-button" id="edsCredentialClose" type="button">×</button></header>
      <section class="modal-body">
        <div class="template-information warning"><strong>Temporary credential display</strong><span>The password is available here only from the account-creation form. Edusentia does not retrieve stored passwords later.</span></div>
        <div class="form-grid" style="margin-top:16px">
          <label class="field full"><span>Email address</span><div class="password-wrap"><input id="edsCredentialEmail" readonly><button class="button ghost small" id="edsCopyEmail" type="button">Copy</button></div></label>
          <label class="field full"><span>Password</span><div class="password-wrap"><input id="edsCredentialPassword" type="password" readonly><button class="button ghost small" id="edsCredentialPasswordToggle" type="button">Show</button><button class="button ghost small" id="edsCopyPassword" type="button">Copy</button></div></label>
          <label class="field full"><span>Phone contact</span><input id="edsCredentialPhone" readonly></label>
        </div>
        <div class="button-row" style="margin-top:18px;flex-wrap:wrap">
          <button class="button primary" id="edsCopyCredentials" type="button">Copy email & password</button>
          <button class="button secondary" id="edsCopyCredentialMessage" type="button">Copy sign-in message</button>
          <button class="button secondary" id="edsCredentialSms" type="button">Send via SMS</button>
          <button class="button secondary" id="edsCredentialWhatsApp" type="button">Send via WhatsApp</button>
        </div>
        <p class="help-text" id="edsCredentialPhoneHelp" style="margin-top:12px"></p>
      </section>
      <footer class="modal-footer"><button class="button primary" id="edsCredentialDone" type="button">Done</button></footer>
    </div>`;
    document.body.appendChild(dialog);
    const close = () => {
      const password = byId("edsCredentialPassword");
      if (password) password.value = "";
      if (dialog.open) dialog.close();
    };
    byId("edsCredentialClose").onclick = close;
    byId("edsCredentialDone").onclick = close;
    dialog.addEventListener("cancel", (event) => { event.preventDefault(); close(); });
    return dialog;
  }

  function showCredentialDialog(data) {
    if (!data?.email || !data?.password) return;
    const dialog = ensureCredentialDialog();
    const email = byId("edsCredentialEmail"), password = byId("edsCredentialPassword"), phone = byId("edsCredentialPhone");
    email.value = data.email;
    password.value = data.password;
    password.type = "password";
    phone.value = data.phone || "Not provided";
    const message = credentialMessage(data);
    const copyNotice = (label) => notify(label, "Copied to clipboard.");

    byId("edsCredentialPasswordToggle").textContent = "Show";
    byId("edsCredentialPasswordToggle").onclick = () => {
      const visible = password.type === "text";
      password.type = visible ? "password" : "text";
      byId("edsCredentialPasswordToggle").textContent = visible ? "Show" : "Hide";
    };
    byId("edsCopyEmail").onclick = async () => { if (await copyText(data.email)) copyNotice("Email copied"); };
    byId("edsCopyPassword").onclick = async () => { if (await copyText(data.password)) copyNotice("Password copied"); };
    byId("edsCopyCredentials").onclick = async () => {
      if (await copyText(`Email: ${data.email}\nPassword: ${data.password}`)) copyNotice("Credentials copied");
    };
    byId("edsCopyCredentialMessage").onclick = async () => { if (await copyText(message)) copyNotice("Sign-in message copied"); };

    const rawPhone = String(data.phone || "").trim();
    const whatsappPhone = normalizeWhatsAppPhone(rawPhone);
    const sms = byId("edsCredentialSms"), whatsapp = byId("edsCredentialWhatsApp"), help = byId("edsCredentialPhoneHelp");
    const hasPhone = Boolean(rawPhone);
    sms.disabled = !hasPhone;
    whatsapp.disabled = !whatsappPhone;
    help.textContent = hasPhone
      ? "SMS and WhatsApp open the device/app with the sign-in message prepared. Review the message before sending. International phone format is recommended for WhatsApp."
      : "No phone contact is stored for this user. Copy the credentials or sign-in message instead.";
    sms.onclick = () => {
      if (!rawPhone) return;
      window.location.href = `sms:${encodeURIComponent(rawPhone)}?body=${encodeURIComponent(message)}`;
    };
    whatsapp.onclick = () => {
      if (!whatsappPhone) return;
      window.open(`https://wa.me/${whatsappPhone}?text=${encodeURIComponent(message)}`, "_blank", "noopener,noreferrer");
    };

    if (!dialog.open) dialog.showModal();
  }

  function capturePendingCredential(form) {
    const password = byId("adminUserPassword");
    if (!password) return;
    pendingCredential = {
      fullName: String(form.elements.full_name?.value || "").trim(),
      email: String(form.elements.email?.value || "").trim(),
      phone: String(form.elements.phone?.value || "").trim(),
      role: String(byId("userRoleSelect")?.value || form.elements.role?.value || ""),
      password: String(password.value || ""),
      mustChange: form.elements.must_change_password?.checked === true,
      mfaRequired: form.elements.mfa_required?.checked === true
    };
  }

  function handleToastNode(node) {
    const text = String(node?.textContent || "").trim();
    if (!text || !pendingCredential) return;
    if (/user account not saved/i.test(text)) {
      pendingCredential = null;
      return;
    }
    if (!/user account created/i.test(text)) return;
    const match = text.match(/Sign-in email:\s*([^\s]+)/i);
    const credential = { ...pendingCredential };
    if (match?.[1]) credential.email = match[1].trim();
    pendingCredential = null;
    if (credential.email && credential.password) showCredentialDialog(credential);
  }

  async function patchUsersAndAccess() {
    if (currentRole() !== "system_admin") return;
    const filter = byId("userRoleFilter");
    if (filter) {
      addOption(filter, "accountant", "Accountant");
      addOption(filter, "student", "Student");
    }
    labelUserRows();
    installPasswordVisibility();
    if (byId("userRoleSelect")) {
      try { await configureExtendedRoleEditor(); }
      catch (error) { console.warn("extended_user_editor_patch_failed", error); }
    }
  }

  async function invokeDirectoryUser(action, payload) {
    const runtime = await waitForRuntime();
    if (!runtime) throw new Error("Tenant runtime is unavailable");
    const { data, error } = await runtime.S.client.functions.invoke("directory-user-management", { body: { action, payload } });
    if (error) throw error;
    if (data?.error) throw new Error(String(data.error));
    return data;
  }

  document.addEventListener("submit", async (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || form.id !== "userForm") return;
    capturePendingCredential(form);
    const selectedRole = String(byId("userRoleSelect")?.value || "");
    if (!["accountant", "student"].includes(selectedRole)) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    try {
      const data = await loadUserData(true);
      const recordId = String(byId("userStaffSelect")?.value || "");
      const records = selectedRole === "accountant" ? (data.accountant_records || []) : (data.student_records || []);
      const record = records.find((r) => String(r.id) === recordId);
      if (!record) throw new Error(`Select the corresponding ${selectedRole === "accountant" ? "Accounts Office Staff" : "Student"} record`);
      const existingId = record.profile_id || null;
      const password = String(byId("adminUserPassword")?.value || "");
      const payload = {
        role: selectedRole,
        staff_record_id: recordId,
        user_id: existingId,
        active: form.elements.active?.checked !== false,
        mfa_required: form.elements.mfa_required?.checked === true,
        must_change_password: form.elements.must_change_password?.checked === true,
        password
      };
      const result = await invokeDirectoryUser(existingId ? "update" : "create", payload);
      byId("modal")?.close?.();
      notify(existingId ? "User account updated" : "User account created", result?.email ? `Sign-in email: ${result.email}` : "");
      if (!existingId && pendingCredential) {
        const credential = { ...pendingCredential, email: result?.email || pendingCredential.email };
        pendingCredential = null;
        if (credential.email && credential.password) showCredentialDialog(credential);
      } else {
        pendingCredential = null;
      }
      userDataCache = null;
      userDataLoadedAt = 0;
      setTimeout(() => document.querySelector('[data-view="users"]')?.click(), 100);
    } catch (error) {
      pendingCredential = null;
      notify("User account not saved", F()?.friendly?.(error) || String(error), "error");
    }
  }, true);

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) return;
    if (target.closest("#mainNav .accounts-directory-nav-item")) {
      setDirectoryActive(true);
      return;
    }
    if (target.closest("#mainNav [data-view], #mainNav .finance-nav-item, #mainNav .accountant-finance-nav-item")) {
      setDirectoryActive(false);
    }
  }, true);

  function scheduleContentPatch() {
    clearTimeout(contentPatchTimer);
    contentPatchTimer = setTimeout(() => {
      scheduleDirectoryRestore();
      if (currentRole() === "system_admin" && byId("userResults")) {
        labelUserRows();
        const filter = byId("userRoleFilter");
        if (filter) {
          addOption(filter, "accountant", "Accountant");
          addOption(filter, "student", "Student");
        }
      }
    }, 70);
  }

  function scheduleModalPatch() {
    clearTimeout(modalPatchTimer);
    modalPatchTimer = setTimeout(() => {
      installPasswordVisibility();
      if (byId("userForm")) void patchUsersAndAccess();
    }, 60);
  }

  async function start() {
    await waitForRuntime();
    setRoleLabel();
    hideSystemAdminFinance();
    ensureAccountsDirectoryNav();
    ensureAccountantFinance();
    void patchUsersAndAccess();

    const nav = byId("mainNav");
    if (nav) {
      new MutationObserver(() => {
        ensureAccountsDirectoryNav();
        ensureAccountantFinance();
        hideSystemAdminFinance();
      }).observe(nav, { childList: true });
    }

    const content = byId("content");
    if (content) new MutationObserver(scheduleContentPatch).observe(content, { childList: true });

    const modal = byId("modal");
    if (modal) new MutationObserver(scheduleModalPatch).observe(modal, { childList: true, subtree: true });

    const toastStack = byId("toastStack");
    if (toastStack) {
      new MutationObserver((records) => {
        for (const record of records) {
          for (const node of record.addedNodes) handleToastNode(node);
        }
      }).observe(toastStack, { childList: true });
    }

    if (currentRole() === "system_admin") setDirectoryActive(false);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => void start(), { once: true });
  else void start();
})();
