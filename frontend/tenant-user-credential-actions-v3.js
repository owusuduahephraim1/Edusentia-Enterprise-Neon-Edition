(() => {
  "use strict";
  if (window.EDS_USER_CREDENTIAL_ACTIONS_V3) return;
  window.EDS_USER_CREDENTIAL_ACTIONS_V3 = true;
  window.EDS_USER_CREDENTIAL_ACTIONS_V2 = true;
  window.EDS_USER_CREDENTIAL_ACTIONS_V1 = true;

  const PROFILE_CACHE_TTL_MS = 15000;
  const TEMP_PASSWORD_TTL_MS = 30 * 60 * 1000;
  const ROLE_LABELS = Object.freeze({
    system_admin: "System Administrator",
    principal: "Principal",
    class_teacher: "Class Teacher",
    subject_teacher: "Subject Teacher",
    parent_guardian: "Parent / Guardian",
    accountant: "Accountant",
    student: "Student",
  });

  const byId = (id) => document.getElementById(id);
  const F = () => window.EdusentiaFinanceRuntime || null;
  const esc = (value) => F()?.esc
    ? F().esc(value)
    : String(value ?? "").replace(/[&<>"']/g, (c) => ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;",
      }[c]));

  const tempPasswords = new Map();
  let profileCache = null;
  let profileLoadedAt = 0;
  let activeProfileId = "";
  let decorateTimer = 0;
  let tableObserver = null;
  let observedTableBody = null;
  let launcherTimer = 0;

  async function waitForRuntime() {
    for (let i = 0; i < 240; i += 1) {
      const runtime = F();
      if (runtime?.S?.client && runtime?.S?.boot) return runtime;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return null;
  }

  function runtimeRole(runtime = F()) {
    return String(runtime?.S?.role || runtime?.S?.boot?.profile?.role || "");
  }

  function notify(title, message = "", kind = "info") {
    if (F()?.notify) F().notify(title, message, kind);
    else if (typeof window.EdusentiaNotify === "function") window.EdusentiaNotify(title, message, kind);
    else console[kind === "error" ? "error" : "log"](title, message);
  }

  function roleLabel(value) {
    return ROLE_LABELS[value] || String(value || "User")
      .replaceAll("_", " ")
      .replace(/\b\w/g, (c) => c.toUpperCase());
  }

  const ACCOUNT_EMAIL_TITLES = new Set([
    "mr","mrs","ms","miss","madam","master","dr","doctor","rev","reverend",
    "prof","professor","principal","headmaster","headmistress",
  ]);
  function accountEmailBase(value) {
    const parts = String(value || "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().split(/\s+/)
      .map((part) => part.replace(/[^a-z0-9]/g, "")).filter(Boolean);
    return parts.find((part) => !ACCOUNT_EMAIL_TITLES.has(part)) || parts[0] || "";
  }
  function generatedEmailNeedsRepair(profile) {
    const base = accountEmailBase(profile?.full_name);
    const local = String(profile?.email || "").split("@")[0].toLowerCase();
    if (!base || !local || !local.startsWith(base)) return Boolean(base && local);
    const suffix = local.slice(base.length);
    return Boolean(suffix && !/^\d+$/.test(suffix));
  }

  function normalizeProfiles(data) {
    if (Array.isArray(data)) return data;
    if (Array.isArray(data?.profiles)) return data.profiles;
    if (Array.isArray(data?.data)) return data.data;
    return [];
  }

  async function loadProfiles(force = false) {
    if (!force && profileCache && Date.now() - profileLoadedAt < PROFILE_CACHE_TTL_MS) return profileCache;
    const runtime = await waitForRuntime();
    if (!runtime) throw new Error("Tenant runtime is unavailable");
    const response = await runtime.rpc("list_profiles_with_access");
    profileCache = normalizeProfiles(response);
    profileLoadedAt = Date.now();
    return profileCache;
  }

  function normalizePhoneForWhatsApp(value) {
    let phone = String(value || "").trim().replace(/[^0-9+]/g, "");
    if (phone.startsWith("00")) phone = phone.slice(2);
    if (phone.startsWith("+")) phone = phone.slice(1);
    return phone.replace(/\D/g, "");
  }

  function signInUrl() {
    try {
      const url = new URL(window.location.href);
      url.hash = "";
      url.searchParams.delete("platform");
      const tenantCode = String(
        F()?.cfg?.()?.tenantCode || window.RCE_CONFIG?.tenantCode || window.NIS_CONFIG?.tenantCode || "",
      ).trim();
      if (tenantCode) url.searchParams.set("tenant", tenantCode);
      return url.toString();
    } catch {
      return window.location.href;
    }
  }

  function secretFor(profile) {
    const key = String(profile?.id || "");
    const secret = tempPasswords.get(key);
    if (!secret) return null;
    if (Date.now() - secret.createdAt > TEMP_PASSWORD_TTL_MS) {
      tempPasswords.delete(key);
      return null;
    }
    return secret;
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

  function credentialMessage(profile, secret) {
    const school = F()?.schoolName?.() || window.RCE_CONFIG?.schoolName || window.NIS_CONFIG?.schoolName || "Your school";
    const lines = [
      `${school} - Edusentia sign-in`,
      "",
      `Name: ${profile.full_name || "User"}`,
      `Role: ${roleLabel(profile.role)}`,
      `Email: ${profile.email || ""}`,
      `Temporary password: ${secret?.password || ""}`,
      `Sign in: ${signInUrl()}`,
      "You will be required to change this temporary password after signing in.",
    ];
    if (profile.mfa_required === true) lines.push("Multi-factor authentication is required for this account.");
    lines.push("Please keep these credentials private.");
    return lines.join("\n");
  }

  function generateTemporaryPassword() {
    const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    const lower = "abcdefghijkmnopqrstuvwxyz";
    const digits = "23456789";
    const symbols = "!@#$%";
    const all = upper + lower + digits + symbols;
    const pick = (set) => set[crypto.getRandomValues(new Uint32Array(1))[0] % set.length];
    const chars = [pick(upper), pick(lower), pick(digits), pick(symbols)];
    for (let i = chars.length; i < 16; i += 1) chars.push(pick(all));
    for (let i = chars.length - 1; i > 0; i -= 1) {
      const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
      [chars[i], chars[j]] = [chars[j], chars[i]];
    }
    return chars.join("");
  }

  async function issueTemporaryPassword(profile) {
    const runtime = await waitForRuntime();
    if (!runtime) throw new Error("Tenant runtime is unavailable");
    const reason = F()?.askReason
      ? await F().askReason(
          "Issue temporary password",
          `This replaces ${profile.full_name || "the user's"} current password and forces a password change at the next sign-in.`,
          "Issue password",
        )
      : typeof window.EdusentiaPrompt === "function"
        ? String(await window.EdusentiaPrompt(
            "Reason for issuing a new temporary password:",
            "",
            { title: "Issue temporary password", confirmLabel: "Issue password", required: true },
          ) || "").trim()
        : "";
    if (!reason) return false;

    const password = generateTemporaryPassword();
    const { data, error } = await runtime.S.client.functions.invoke("admin-user-management", {
      body: {
        action: "reset_password",
        payload: {
          user_id: profile.id,
          password,
          must_change_password: true,
          reason,
        },
      },
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.message || data.error);

    tempPasswords.set(String(profile.id), { password, createdAt: Date.now() });
    profile.must_change_password = true;
    notify("Temporary password issued", "It is available only in this browser session for up to 30 minutes.");
    return true;
  }

  function installStyles() {
    if (byId("edsCredentialsWorkspaceStyleV3")) return;
    const style = document.createElement("style");
    style.id = "edsCredentialsWorkspaceStyleV3";
    style.textContent = `
      #edsCredentialsWorkspaceLauncherV3{display:inline-flex;align-items:center;justify-content:center;gap:7px;min-height:40px;white-space:nowrap;}
      .eds-user-contact-line-v3{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:5px;font-size:12px;line-height:1.25;}
      .eds-user-phone-v3{color:var(--muted,#64748b);white-space:nowrap;}
      .eds-user-credential-button-v3{padding:4px 8px!important;min-height:28px!important;white-space:nowrap;}
      #edsCredentialsWorkspaceDialogV3{width:min(1180px,calc(100vw - 36px));max-width:1180px;padding:0;border:0;border-radius:18px;overflow:hidden;background:var(--surface,#fff);box-shadow:0 28px 80px rgba(15,35,70,.24);}
      #edsCredentialsWorkspaceDialogV3::backdrop{background:rgba(8,25,52,.42);backdrop-filter:blur(2px);}
      .eds-cred-frame-v3{display:flex;flex-direction:column;max-height:min(88vh,860px);background:var(--surface,#fff);}
      .eds-cred-header-v3{display:flex;align-items:flex-start;justify-content:space-between;gap:18px;padding:20px 22px;border-bottom:1px solid var(--line,#d8e1ef);}
      .eds-cred-header-v3 h3{margin:0 0 4px;font-size:20px;line-height:1.2;}
      .eds-cred-header-v3 p{margin:0;color:var(--muted,#64748b);font-size:13px;}
      .eds-cred-close-v3{border:1px solid var(--line,#d8e1ef);background:var(--surface,#fff);width:36px;height:36px;border-radius:10px;font-size:22px;line-height:1;cursor:pointer;}
      .eds-cred-body-v3{display:grid;grid-template-columns:minmax(280px,340px) minmax(0,1fr);min-height:0;flex:1;overflow:hidden;}
      .eds-cred-directory-v3{display:flex;flex-direction:column;min-height:0;border-right:1px solid var(--line,#d8e1ef);background:color-mix(in srgb,var(--surface,#fff) 96%,#eef5ff 4%);}
      .eds-cred-directory-tools-v3{padding:14px;border-bottom:1px solid var(--line,#d8e1ef);display:grid;gap:9px;}
      .eds-cred-directory-tools-v3 input,.eds-cred-directory-tools-v3 select{width:100%;min-height:40px;border:1px solid var(--line,#d8e1ef);border-radius:10px;padding:0 11px;background:var(--surface,#fff);color:inherit;}
      .eds-cred-user-list-v3{overflow:auto;overscroll-behavior:contain;min-height:220px;padding:8px;}
      .eds-cred-user-v3{display:block;width:100%;text-align:left;border:1px solid transparent;background:transparent;border-radius:12px;padding:10px 11px;margin:0 0 5px;cursor:pointer;color:inherit;}
      .eds-cred-user-v3:hover{background:rgba(42,105,190,.07);}
      .eds-cred-user-v3.active{background:rgba(42,105,190,.11);border-color:rgba(42,105,190,.22);}
      .eds-cred-user-v3 strong{display:block;font-size:13px;margin-bottom:3px;}
      .eds-cred-user-v3 span{display:block;color:var(--muted,#64748b);font-size:11px;line-height:1.35;overflow-wrap:anywhere;}
      .eds-cred-detail-v3{overflow:auto;overscroll-behavior:contain;padding:20px 22px;min-width:0;}
      .eds-cred-status-v3{display:flex;gap:10px;align-items:flex-start;border:1px solid var(--line,#d8e1ef);border-radius:12px;padding:12px 13px;background:#f7faff;margin-bottom:14px;}
      .eds-cred-status-v3.success{background:#f1fbf6;border-color:#cdecdc;}
      .eds-cred-status-v3.warning{background:#fff9ed;border-color:#f0dfb8;}
      .eds-cred-status-v3 strong{display:block;font-size:13px;margin-bottom:2px;}
      .eds-cred-status-v3 span{display:block;color:var(--muted,#64748b);font-size:12px;line-height:1.4;}
      .eds-credential-grid-v3{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;}
      .eds-credential-card-v3{border:1px solid var(--line,#d8e1ef);border-radius:12px;padding:12px;background:var(--surface,#fff);min-width:0;}
      .eds-credential-card-v3 small{display:block;color:var(--muted,#64748b);margin-bottom:4px;font-size:11px;}
      .eds-credential-card-v3 strong{display:block;overflow-wrap:anywhere;font-size:13px;}
      .eds-cred-password-v3{margin-top:14px;}
      .eds-cred-password-v3>span{display:block;font-size:12px;font-weight:700;margin-bottom:6px;}
      .eds-cred-password-row-v3{display:flex;gap:8px;align-items:center;}
      .eds-cred-password-row-v3 input{flex:1;min-width:0;min-height:40px;border:1px solid var(--line,#d8e1ef);border-radius:10px;padding:0 11px;background:var(--surface,#fff);color:inherit;}
      .eds-credential-actions-v3{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px;}
      .eds-credential-actions-v3 .button{min-height:36px;}
      .eds-cred-issue-v3{margin-top:16px;display:flex;align-items:center;gap:10px;flex-wrap:wrap;}
      .eds-cred-help-v3{margin:10px 0 0;color:var(--muted,#64748b);font-size:12px;line-height:1.45;}
      .eds-cred-empty-v3{display:grid;place-items:center;min-height:320px;text-align:center;color:var(--muted,#64748b);padding:32px;}
      .eds-cred-footer-v3{display:flex;justify-content:flex-end;padding:14px 22px;border-top:1px solid var(--line,#d8e1ef);}
      @media(max-width:820px){
        #edsCredentialsWorkspaceDialogV3{width:min(96vw,1180px);}
        .eds-cred-frame-v3{max-height:92vh;}
        .eds-cred-body-v3{display:block;overflow:auto;}
        .eds-cred-directory-v3{border-right:0;border-bottom:1px solid var(--line,#d8e1ef);}
        .eds-cred-user-list-v3{max-height:230px;}
        .eds-cred-detail-v3{overflow:visible;}
      }
      @media(max-width:620px){
        .eds-credential-grid-v3{grid-template-columns:1fr;}
        .eds-cred-header-v3,.eds-cred-detail-v3{padding-left:14px;padding-right:14px;}
        .eds-cred-footer-v3{padding-left:14px;padding-right:14px;}
      }
    `;
    document.head.appendChild(style);
  }

  function ensureDialog() {
    let dialog = byId("edsCredentialsWorkspaceDialogV3");
    if (dialog) return dialog;

    dialog = document.createElement("dialog");
    dialog.id = "edsCredentialsWorkspaceDialogV3";
    dialog.innerHTML = `
      <div class="eds-cred-frame-v3">
        <header class="eds-cred-header-v3">
          <div><h3>Credentials</h3><p>Issue temporary passwords and securely prepare sign-in details for users.</p></div>
          <button class="eds-cred-close-v3" id="edsCredentialsWorkspaceCloseV3" type="button" aria-label="Close">×</button>
        </header>
        <section class="eds-cred-body-v3">
          <aside class="eds-cred-directory-v3">
            <div class="eds-cred-directory-tools-v3">
              <input id="edsCredentialsSearchV3" type="search" placeholder="Search name, email, or phone" autocomplete="off">
              <select id="edsCredentialsRoleFilterV3" aria-label="Filter by role"><option value="">All roles</option></select>
            </div>
            <div class="eds-cred-user-list-v3" id="edsCredentialsUserListV3"></div>
          </aside>
          <main class="eds-cred-detail-v3" id="edsCredentialsDetailV3">
            <div class="eds-cred-empty-v3">Choose a user to manage credentials.</div>
          </main>
        </section>
        <footer class="eds-cred-footer-v3"><button class="button primary" id="edsCredentialsWorkspaceDoneV3" type="button">Done</button></footer>
      </div>`;
    document.body.appendChild(dialog);

    const close = () => {
      if (dialog.open && dialog.close) dialog.close();
      else dialog.removeAttribute("open");
    };
    byId("edsCredentialsWorkspaceCloseV3").onclick = close;
    byId("edsCredentialsWorkspaceDoneV3").onclick = close;
    dialog.addEventListener("cancel", (event) => {
      event.preventDefault();
      close();
    });
    byId("edsCredentialsSearchV3").addEventListener("input", renderDirectory);
    byId("edsCredentialsRoleFilterV3").addEventListener("change", renderDirectory);
    return dialog;
  }

  function populateRoleFilter(profiles) {
    const select = byId("edsCredentialsRoleFilterV3");
    if (!select) return;
    const current = select.value;
    const roles = [...new Set(profiles.map((p) => String(p.role || "")).filter(Boolean))]
      .sort((a, b) => roleLabel(a).localeCompare(roleLabel(b)));
    select.innerHTML = `<option value="">All roles</option>${roles
      .map((role) => `<option value="${esc(role)}">${esc(roleLabel(role))}</option>`)
      .join("")}`;
    if (roles.includes(current)) select.value = current;
  }

  function filteredProfiles() {
    const profiles = Array.isArray(profileCache) ? profileCache : [];
    const query = String(byId("edsCredentialsSearchV3")?.value || "").trim().toLowerCase();
    const role = String(byId("edsCredentialsRoleFilterV3")?.value || "");
    return profiles.filter((profile) => {
      if (role && String(profile.role || "") !== role) return false;
      if (!query) return true;
      const haystack = [profile.full_name, profile.email, profile.phone, roleLabel(profile.role)]
        .map((value) => String(value || "").toLowerCase())
        .join(" ");
      return haystack.includes(query);
    });
  }

  function renderDirectory() {
    const list = byId("edsCredentialsUserListV3");
    if (!list) return;
    const profiles = filteredProfiles();
    if (!profiles.length) {
      list.innerHTML = `<div class="eds-cred-empty-v3" style="min-height:180px">No users match this filter.</div>`;
      renderDetail(null);
      return;
    }

    if (!profiles.some((profile) => String(profile.id) === String(activeProfileId))) {
      activeProfileId = String(profiles[0].id || "");
    }
    list.innerHTML = profiles.map((profile) => {
      const active = String(profile.id) === String(activeProfileId) ? " active" : "";
      const phone = String(profile.phone || "").trim();
      return `<button type="button" class="eds-cred-user-v3${active}" data-eds-cred-profile="${esc(profile.id)}">
        <strong>${esc(profile.full_name || "Unnamed user")}</strong>
        <span>${esc(roleLabel(profile.role))}</span>
        <span>${esc(profile.email || "No email")}${phone ? ` • ${esc(phone)}` : ""}</span>
      </button>`;
    }).join("");

    list.querySelectorAll("[data-eds-cred-profile]").forEach((button) => {
      button.addEventListener("click", () => {
        activeProfileId = String(button.dataset.edsCredProfile || "");
        renderDirectory();
      });
    });

    renderDetail(profiles.find((profile) => String(profile.id) === String(activeProfileId)) || profiles[0]);
  }

  function renderDetail(profile) {
    const detail = byId("edsCredentialsDetailV3");
    if (!detail) return;
    if (!profile) {
      detail.innerHTML = `<div class="eds-cred-empty-v3">Choose a user to manage credentials.</div>`;
      return;
    }

    const secret = secretFor(profile);
    const phone = String(profile.phone || "").trim();
    const whatsappPhone = normalizePhoneForWhatsApp(phone);
    const hasSecret = Boolean(secret?.password);
    const emailNeedsRepair = generatedEmailNeedsRepair(profile);
    const expectedBase = accountEmailBase(profile.full_name);
    const status = hasSecret
      ? "A temporary password is available in this browser session for up to 30 minutes."
      : "The current password cannot be retrieved. Issue a new temporary password before copying or sending complete credentials.";

    detail.innerHTML = `
      <div class="eds-cred-status-v3 ${hasSecret ? "success" : "warning"}">
        <div><strong>${hasSecret ? "Temporary password available" : "Password protected"}</strong><span>${esc(status)}</span></div>
      </div>
      ${emailNeedsRepair ? `<div class="eds-cred-status-v3 warning"><div><strong>Generated email does not match the first usable name</strong><span>This account should use an address beginning with ${esc(expectedBase)}. The correction keeps the school domain and updates sign-in routing.</span></div><button class="button secondary small" id="edsCredentialsRepairEmailV3" type="button">Correct email</button></div>` : ""}
      <div class="eds-credential-grid-v3">
        <div class="eds-credential-card-v3"><small>User</small><strong>${esc(profile.full_name || "—")}</strong></div>
        <div class="eds-credential-card-v3"><small>Role</small><strong>${esc(roleLabel(profile.role))}</strong></div>
        <div class="eds-credential-card-v3"><small>Email address</small><strong>${esc(profile.email || "—")}</strong></div>
        <div class="eds-credential-card-v3"><small>Phone contact</small><strong>${esc(phone || "No phone number available")}</strong></div>
      </div>
      <label class="eds-cred-password-v3"><span>Temporary password</span>
        <div class="eds-cred-password-row-v3">
          <input id="edsCredentialsPasswordV3" type="password" readonly value="${hasSecret ? esc(secret.password) : ""}" placeholder="Not available">
          <button class="button ghost small" id="edsCredentialsPasswordToggleV3" type="button" ${hasSecret ? "" : "disabled"}>Show</button>
        </div>
      </label>
      <div class="eds-credential-actions-v3">
        <button class="button secondary" id="edsCredentialsCopyEmailV3" type="button">Copy email</button>
        <button class="button secondary" id="edsCredentialsCopyPasswordV3" type="button" ${hasSecret ? "" : "disabled"}>Copy password</button>
        <button class="button secondary" id="edsCredentialsCopyBothV3" type="button" ${hasSecret ? "" : "disabled"}>Copy email & password</button>
        <button class="button secondary" id="edsCredentialsCopyMessageV3" type="button" ${hasSecret ? "" : "disabled"}>Copy sign-in message</button>
        <button class="button secondary" id="edsCredentialsSmsV3" type="button" ${hasSecret && phone ? "" : "disabled"}>Send via SMS</button>
        <button class="button secondary" id="edsCredentialsWhatsAppV3" type="button" ${hasSecret && whatsappPhone ? "" : "disabled"}>Send via WhatsApp</button>
      </div>
      <div class="eds-cred-issue-v3"><button class="button primary" id="edsCredentialsIssuePasswordV3" type="button">Issue new temporary password</button></div>
      <p class="eds-cred-help-v3">${phone
        ? "SMS and WhatsApp use the saved phone contact. Review the prepared message in your messaging app before sending."
        : "No phone contact is saved for this user, so SMS and WhatsApp remain disabled."}</p>`;

    const passwordInput = byId("edsCredentialsPasswordV3");
    byId("edsCredentialsPasswordToggleV3").onclick = () => {
      if (!hasSecret) return;
      const visible = passwordInput.type === "text";
      passwordInput.type = visible ? "password" : "text";
      byId("edsCredentialsPasswordToggleV3").textContent = visible ? "Show" : "Hide";
    };
    byId("edsCredentialsCopyEmailV3").onclick = async () => {
      if (await copyText(profile.email || "")) notify("Email copied", "Copied to clipboard.");
    };
    byId("edsCredentialsCopyPasswordV3").onclick = async () => {
      if (hasSecret && await copyText(secret.password)) notify("Password copied", "Copied to clipboard.");
    };
    byId("edsCredentialsCopyBothV3").onclick = async () => {
      if (hasSecret && await copyText(`Email: ${profile.email || ""}\nPassword: ${secret.password}`)) {
        notify("Credentials copied", "Copied to clipboard.");
      }
    };
    byId("edsCredentialsCopyMessageV3").onclick = async () => {
      if (hasSecret && await copyText(credentialMessage(profile, secret))) notify("Sign-in message copied", "Copied to clipboard.");
    };
    byId("edsCredentialsSmsV3").onclick = () => {
      if (!hasSecret || !phone) return;
      window.location.href = `sms:${encodeURIComponent(phone)}?body=${encodeURIComponent(credentialMessage(profile, secret))}`;
    };
    byId("edsCredentialsWhatsAppV3").onclick = () => {
      if (!hasSecret || !whatsappPhone) return;
      window.open(
        `https://wa.me/${whatsappPhone}?text=${encodeURIComponent(credentialMessage(profile, secret))}`,
        "_blank",
        "noopener,noreferrer",
      );
    };
    byId("edsCredentialsRepairEmailV3")?.addEventListener("click", async () => {
      const button = byId("edsCredentialsRepairEmailV3");
      if (!window.EdusentiaApi?.adminUserManagement) {
        notify("Email not corrected", "The user-management service is unavailable.", "error");
        return;
      }
      button.disabled = true;
      try {
        const result = await window.EdusentiaApi.adminUserManagement("refresh_generated_email", { user_id: profile.id });
        profileCache = null;
        profileLoadedAt = 0;
        await loadProfiles(true);
        notify("Generated email corrected", result?.email ? `New sign-in email: ${result.email}` : "The account email now matches the user's first usable name.");
        renderDirectory();
      } catch (error) {
        notify("Email not corrected", F()?.friendly?.(error) || String(error), "error");
      } finally {
        const current = byId("edsCredentialsRepairEmailV3");
        if (current) current.disabled = false;
      }
    });
    byId("edsCredentialsIssuePasswordV3").onclick = async () => {
      const button = byId("edsCredentialsIssuePasswordV3");
      button.disabled = true;
      try {
        if (await issueTemporaryPassword(profile)) renderDetail(profile);
      } catch (error) {
        notify("Temporary password was not issued", F()?.friendly?.(error) || String(error), "error");
      } finally {
        const current = byId("edsCredentialsIssuePasswordV3");
        if (current) current.disabled = false;
      }
    };
  }

  async function openWorkspace() {
    const dialog = ensureDialog();
    const runtime = await waitForRuntime();
    if (!runtime || runtimeRole(runtime) !== "system_admin") {
      notify("Credentials unavailable", "Only the System Administrator can manage user credentials.", "error");
      return;
    }

    const list = byId("edsCredentialsUserListV3");
    const detail = byId("edsCredentialsDetailV3");
    if (list) list.innerHTML = `<div class="eds-cred-empty-v3" style="min-height:180px">Loading users…</div>`;
    if (detail) detail.innerHTML = `<div class="eds-cred-empty-v3">Loading credential workspace…</div>`;
    if (!dialog.open) {
      try { dialog.showModal(); }
      catch { dialog.setAttribute("open", ""); }
    }

    try {
      const profiles = await loadProfiles(true);
      populateRoleFilter(profiles);
      if (!profiles.length) {
        if (list) list.innerHTML = `<div class="eds-cred-empty-v3" style="min-height:180px">No user accounts are available.</div>`;
        renderDetail(null);
        return;
      }
      if (!profiles.some((profile) => String(profile.id) === String(activeProfileId))) {
        activeProfileId = String(profiles[0].id || "");
      }
      renderDirectory();
    } catch (error) {
      if (list) list.innerHTML = `<div class="eds-cred-empty-v3" style="min-height:180px">Users could not be loaded.</div>`;
      if (detail) detail.innerHTML = `<div class="eds-cred-empty-v3"><div><strong>Credential data could not be loaded.</strong><br><span>${esc(F()?.friendly?.(error) || String(error))}</span></div></div>`;
    }
  }

  function ensureLauncher() {
    installStyles();
    const runtime = F();
    if (runtime && runtimeRole(runtime) && runtimeRole(runtime) !== "system_admin") return false;
    if (byId("edsCredentialsWorkspaceLauncherV3")) return true;

    const createButton = byId("userCreateButton");
    const userResults = byId("userResults");
    if (!createButton && !userResults) return false;

    const button = document.createElement("button");
    button.id = "edsCredentialsWorkspaceLauncherV3";
    button.type = "button";
    button.className = "button secondary";
    button.textContent = "Credentials";
    button.addEventListener("click", openWorkspace);

    if (createButton?.parentElement) {
      createButton.parentElement.insertBefore(button, createButton);
    } else if (userResults?.parentElement) {
      const bar = document.createElement("div");
      bar.style.display = "flex";
      bar.style.justifyContent = "flex-end";
      bar.style.marginBottom = "10px";
      bar.appendChild(button);
      userResults.parentElement.insertBefore(bar, userResults);
    }
    return true;
  }

  function scheduleLauncher() {
    window.clearTimeout(launcherTimer);
    let attempts = 0;
    const run = () => {
      attempts += 1;
      if (ensureLauncher()) return;
      if (attempts < 80) launcherTimer = window.setTimeout(run, 100);
    };
    run();
  }

  function findRowEmail(row) {
    const text = String(row?.children?.[0]?.textContent || row?.textContent || "");
    return (text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)?.[0] || "").toLowerCase();
  }

  async function decorateUsers(force = false) {
    const root = byId("userResults");
    if (!root) return false;
    const runtime = await waitForRuntime();
    if (!runtime || runtimeRole(runtime) !== "system_admin") return false;
    const profiles = await loadProfiles(force);
    const byEmail = new Map(profiles.map((profile) => [String(profile.email || "").toLowerCase(), profile]));

    root.querySelectorAll("tbody tr").forEach((row) => {
      const email = findRowEmail(row);
      const profile = byEmail.get(email);
      if (!profile) return;
      const first = row.children?.[0];
      if (!first) return;
      first.querySelector(".eds-user-contact-line-v3")?.remove();
      const line = document.createElement("div");
      line.className = "eds-user-contact-line-v3";
      const phone = document.createElement("span");
      phone.className = "eds-user-phone-v3";
      phone.textContent = profile.phone ? `☎ ${profile.phone}` : "☎ No phone";
      const button = document.createElement("button");
      button.type = "button";
      button.className = "button ghost small eds-user-credential-button-v3";
      button.textContent = "Credentials";
      button.addEventListener("click", async () => {
        activeProfileId = String(profile.id || "");
        await openWorkspace();
      });
      line.append(phone, button);
      first.appendChild(line);
    });

    const body = root.querySelector("tbody");
    if (body && observedTableBody !== body) {
      tableObserver?.disconnect();
      observedTableBody = body;
      tableObserver = new MutationObserver(() => scheduleDecorate(true));
      tableObserver.observe(body, { childList: true });
    }
    return true;
  }

  function scheduleDecorate(force = false) {
    window.clearTimeout(decorateTimer);
    decorateTimer = window.setTimeout(async () => {
      try { await decorateUsers(force); }
      catch (error) { console.error("user_credentials_v3_decorate_failed", error); }
    }, 80);
  }

  document.addEventListener("click", (event) => {
    if (event.target.closest('[data-view="users"],#userSave,#userCreateButton')) {
      scheduleLauncher();
      scheduleDecorate(true);
    }
  }, true);
  window.addEventListener("pageshow", () => {
    scheduleLauncher();
    scheduleDecorate(true);
  }, { passive: true });

  scheduleLauncher();
  scheduleDecorate(true);
})();
