const CACHE = "edusentia-neon-v3";
const SHELL = ["./","./index.html","./config.js","./api-client.js","./app.js","./style.css","./r37-final-ui.css","./neon-edition.css","./manifest.webmanifest","./assets/edusentia-mark.svg","./platform-admin.html","./platform-api-client.js","./platform-admin.js","./platform-saas-admin.css","./register.html","./register.js","./admin-setup.html","./admin-setup.js"];
self.addEventListener("install", e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener("activate", e => e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (url.origin !== self.location.origin || e.request.method !== "GET") return;
  e.respondWith(fetch(e.request).then(r => { const copy=r.clone(); caches.open(CACHE).then(c => c.put(e.request,copy)); return r; }).catch(() => caches.match(e.request).then(r => r || caches.match("./index.html"))));
});
