// Keep the existing GitHub Pages and native application installation stable.
// Cloudflare Pages and the future app subdomain use the new custom API domain.
(() => {
  const hostname=String(window.location?.hostname||"").toLowerCase();
  const onCloudflareApp=hostname==="edusentia-app.pages.dev"||hostname==="app.edusentia.com";
  window.EDS_MASTER_CONFIG = Object.freeze({
    apiBaseUrl: onCloudflareApp
      ? "https://api.edusentia.com"
      : "https://edusentia-enterprise-neon-api.edusentia-enterprise-neon.workers.dev",
    productName: "Edusentia Enterprise Neon Edition",
    productVersion: "neon-v1.0.0-r42",
    repositoryBasePath: onCloudflareApp?"/":"/Edusentia-Enterprise-Neon-Edition/",
    logoPath: "assets/school-logo.png",
    turnstileSiteKey: "0x4AAAAAAE9z98I97UNWfs7m",
    platformAdminPhoneE164: "233240240898",
    platformAdminPhoneDisplay: "+233 24 024 0898",
    environment: "production"
  });
})();
