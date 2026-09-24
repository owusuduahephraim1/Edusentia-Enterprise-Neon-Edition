// Reference-parity front/back ID-card rendering refresh, cache generation v40.
// Includes the QR renderer and enterprise ID-card workspace in the deployed shell.
// Staff & HR now uses the native shell route for Principal and System Administrator responsive workspaces.
// Student, Parent or Guardian, and Accounts Office navigation now follows the certified extension-navigation contract.
// System Administrator Accounts Office Staff directory navigation is restored, and report-card design files are separated from class-range summaries.
// Starter template controls now show an upgrade notice, and every click keeps exactly one active navigator.
// Academics Assign Subjects now uses certified checkbox class/subject assignment selectors.
// Class Subject Assignments now groups one teacher into compact class and subject counts, with an optional expanded list.
// Backup & Restore runtime repair: stable Worker secrets, resilient backup reads, and larger status icons.
// Manage Teacher Assignments now supports edit, remove/archive, delete inactive assignments, and assign-more parity.
// Commercial plan tiering v2 is active in the Upgrade Plan workspace and entitlement cache.
// Backup & Restore now provides one-tap manual ZIP backups for every plan, Weekly/Monthly automation for Professional and Enterprise, and protected ZIP restore with a pre-restore safety backup.
// Backup manual execution now uses resilient batched Neon reads, stable Worker encryption secrets, stale-job recovery, and full-size SVG status icons.
// System-wide statistic icons now use the certified Supabase centered shape geometry and responsive mobile sizing.
// Backup & Restore production deployment marker: v41 Supabase icon parity release.
const CACHE = "edusentia-neon-v41";
const SHELL = ["./","./index.html","./about.html","./support.html","./privacy.html","./terms.html","./info-pages.css","./config.js","./api-client.js","./app.js","./parity-common.js","./parity-academics.js","./parity-students.js","./parity-teachers.js","./parity-principal.js","./parity-timetable.js","./parity-reports.js","./parity-audit-security-finance.js","./parity-operations.js","./parity-enterprise-workspaces.js","./tenant-class-teacher-workspace-parity-v1.js","./style.css","./r37-final-ui.css","./neon-edition.css","./manifest.webmanifest","./assets/edusentia-mark.svg","./assets/school-logo.png","./assets/vendor/jszip-3.10.1.min.js","./tenant-r40-product-fixes.js","./tenant-r40-v9-list-resilience.js","./tenant-accountant-parent-follow-up-v1.js","./tenant-accountant-parent-follow-up-v2.js","./tenant-user-credential-actions-v2.js","./tenant-user-credential-actions-v3.js","./tenant-backup-r2-download-v1.js","./tenant-backup-r2-download-core-r42-v18.js","./tenant-teacher-subject-summary.js","./tenant-teacher-subject-summary-v2.js","./platform-admin.html","./platform-saas-admin.html","./platform-api-client.js","./platform-admin.js","./platform-saas-admin.js","./platform-saas-admin.css","./platform-r40-mobile.css","./workspace-canvas.css","./r40-v9.css","./platform-r40-v9-mfa-resilience.css","./platform-r40-v9-list-resilience.css","./assets/vendor/qrcode-1.0.0.min.js","./register.html","./register.js","./admin-setup.html","./admin-setup.js","./neon-supabase-compat.js","./finance-enterprise.css","./finance-core.js","./finance-payroll.js","./finance-accounts.js","./finance-professional-receipts.js","./finance-portals.js","./finance-invoices-v1.js","./tenant-accountant-dashboard-v1.js","./tenant-accountant-student-roles-v2.js","./tenant-accountant-student-submit-v3.js","./tenant-hr-staff-v1.js","./tenant-student-services-v1.js","./tenant-student-services-actions-v1.js","./tenant-student-portal-v1.js","./tenant-student-portal-v2.js","./tenant-student-portal-v2-refinements.js","./tenant-institution-academics-loader-v1.js","./tenant-institution-academics-v1.js"];
self.addEventListener("install", e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener("activate", e => e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (url.origin !== self.location.origin || e.request.method !== "GET") return;
  e.respondWith(fetch(e.request).then(r => { const copy=r.clone(); caches.open(CACHE).then(c => c.put(e.request,copy)); return r; }).catch(() => caches.match(e.request).then(r => r || caches.match("./index.html"))));
});
