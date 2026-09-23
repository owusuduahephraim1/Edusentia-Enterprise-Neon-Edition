(() => {
  "use strict";
  if (window.EDS_USER_CREDENTIAL_ACTIONS_V3) return;
  if (document.querySelector('script[data-edusentia-user-credential-actions-v3]')) return;
  const script = document.createElement("script");
  script.src = "tenant-user-credential-actions-v3.js?edusentia=r40-user-credential-actions-v3-credentials-workspace";
  script.defer = true;
  script.dataset.edusentiaUserCredentialActionsV3 = "1";
  script.addEventListener("error", () => console.error("user_credential_actions_v3_load_failed"), { once: true });
  document.body.appendChild(script);
})();
