function stableScopeHash(value){
  let hash=2166136261;
  for(const character of String(value||"")){
    hash^=character.charCodeAt(0);
    hash=Math.imul(hash,16777619);
  }
  return(hash>>>0).toString(36);
}

const CACHE_SCOPE_KEY=stableScopeHash(self.registration?.scope||self.location.href);
const CACHE_FAMILY=`rce-report-card-${CACHE_SCOPE_KEY}-`;
// r42-v14 desktop auth transport: force one clean cache generation on Windows
// browsers/WebView2 and retire every older runtime cache in this registration scope.
const CACHE_NAME=`${CACHE_FAMILY}v7-4-0-r40-product-ready-v9-r42-windows-auth-v14`;
const RETIRED_WORKSPACE_ASSET_RE=/(?:^|\/)tenant-(?:library|transport|inventory-assets)-v\d+\.js$/i;

const STATIC_ASSETS=[
  "./","index.html","style.css","r37-final-ui.css","app.js","config.js","tenant-bootstrap.js",
  "tenant-r40-product-fixes.js","tenant-r40-v9-list-resilience.js","tenant-accountant-student-roles-v2.js",
  "tenant-accountant-student-submit-v3.js","tenant-accountant-dashboard-v1.js","tenant-user-credential-actions-v2.js","tenant-hr-staff-v1.js","tenant-student-services-v1.js","tenant-student-services-actions-v1.js",
  "tenant-student-portal-v1.js","tenant-student-portal-v2.js","tenant-student-portal-v2-refinements.js","tenant-audit-trail-v1.js","tenant-mfa-recovery-guard-v1.js","tenant-backup-r2-download-v1.js","tenant-professional-transcript-v1.js","tenant-system-health-v1.js","tenant-users-access-hardening-v1.js","tenant-academic-readiness-v1.js",
  "tenant-institution-academics-v1.js",
  "finance-professional-receipts.js","finance-enterprise.css","finance-core.js","finance-payroll.js","finance-accounts.js","finance-portals.js",
  "platform-saas-admin.html","platform-saas-admin.css","platform-saas-admin.js","platform-r40-mobile.css","platform-r40-product-fixes.js","platform-r40-v9-access-recovery.js","platform-institution-models-v1.js",
  "r40-v9.css","r40-v9-premium-workspace.css","workspace-canvas.css","registration-form.css","manifest.webmanifest",
  "about.html","support.html","privacy.html","terms.html","public-info.css",
  "assets/edusentia-mark.svg","assets/edusentia-login-background-final.webp","assets/edusentia-auth-scene.webp","assets/edusentia-auth-intelligence.webp","assets/edusentia-auth-learning.webp","assets/edusentia-workspace-canvas.svg",
  "assets/school-logo.png","assets/rce-master-logo.png","assets/rce-master-logo-192.png","assets/rce-master-logo-512.png","assets/rce-master-logo-maskable-512.png","assets/favicon-32.png",
  "assets/approved-terminal-report-template.png","assets/approved-terminal-report-template.pdf",
  "assets/vendor/supabase-2.110.5.js","assets/vendor/qrcode-1.0.0.min.js","assets/vendor/pdfjs-3.11.174.min.js","assets/vendor/pdfjs-3.11.174.worker.min.js",
  "assets/vendor/jszip-3.10.1.min.js?edusentia=r37","assets/vendor/docx-preview-0.4.0.min.js","assets/vendor/html2canvas-1.4.1.min.js"
];

const NETWORK_FIRST_PATHS=[
  "/tenant-bootstrap.js",
  "/r37-final-ui.css","/platform-saas-admin.css","/platform-r40-mobile.css","/workspace-canvas.css","/registration-form.css",
  "/assets/edusentia-workspace-canvas.svg","/platform-saas-admin.js","/platform-r40-product-fixes.js","/platform-r40-v9-access-recovery.js","/platform-institution-models-v1.js",
  "/r40-v9.css","/r40-v9-premium-workspace.css","/public-info.css","/tenant-r40-product-fixes.js","/tenant-r40-v9-list-resilience.js",
  "/tenant-accountant-student-roles-v2.js","/tenant-accountant-student-submit-v3.js","/tenant-accountant-dashboard-v1.js","/tenant-user-credential-actions-v2.js","/tenant-hr-staff-v1.js","/tenant-student-services-v1.js","/tenant-student-services-actions-v1.js",
  "/tenant-student-portal-v1.js","/tenant-student-portal-v2.js","/tenant-student-portal-v2-refinements.js","/tenant-audit-trail-v1.js","/tenant-mfa-recovery-guard-v1.js","/tenant-backup-r2-download-v1.js","/tenant-professional-transcript-v1.js","/tenant-system-health-v1.js","/tenant-users-access-hardening-v1.js","/tenant-academic-readiness-v1.js",
  "/tenant-institution-academics-loader-v1.js","/tenant-institution-academics-v1.js",
  "/finance-professional-receipts.js","/finance-enterprise.css","/finance-core.js","/finance-payroll.js","/finance-accounts.js","/finance-portals.js",
  "/assets/edusentia-login-background-final.webp","/assets/edusentia-auth-scene.webp","/assets/edusentia-auth-intelligence.webp","/assets/edusentia-auth-learning.webp"
];

async function cacheMatch(request){
  return(await caches.open(CACHE_NAME)).match(request);
}

async function cachePut(request,response){
  if(!response||!response.ok||!["basic","default"].includes(response.type))return;
  try{await(await caches.open(CACHE_NAME)).put(request,response.clone());}catch{}
}

async function networkFirstWithBaseFallback(request,url){
  try{
    const response=await fetch(request,{cache:"no-store"});
    await cachePut(request,response);
    return response;
  }catch{
    const direct=await cacheMatch(request);
    if(direct)return direct;
    const fallback=new Request(new URL(url.pathname,self.location.origin).href,{method:"GET"});
    return await cacheMatch(fallback)||new Response("Required application asset is unavailable.",{
      status:503,
      headers:{"Content-Type":"text/plain; charset=utf-8","Cache-Control":"no-store"}
    });
  }
}

async function injectTenantEnhancements(response){
  if(!response||!response.ok)return response;
  const contentType=String(response.headers.get("content-type")||"").toLowerCase();
  if(!contentType.includes("text/html"))return response;
  const html=await response.text();
  const headers=new Headers(response.headers);headers.delete("content-length");
  if(!html.includes('id="appShell"'))return new Response(html,{status:response.status,statusText:response.statusText,headers});
  const additions=[];
  if(!html.includes("data-edusentia-audit-trail"))additions.push('<script src="tenant-audit-trail-v1.js?edusentia=r40-audit-console-v1" data-edusentia-audit-trail="1"></script>');
  if(!html.includes("data-edusentia-mfa-recovery-guard"))additions.push('<script src="tenant-mfa-recovery-guard-v1.js?edusentia=r40-mfa-recovery-guard-v1" data-edusentia-mfa-recovery-guard="1"></script>');
  if(!html.includes("data-edusentia-backup-r2-download"))additions.push('<script src="tenant-backup-r2-download-v1.js?edusentia=r40-backup-r2-download-v1" data-edusentia-backup-r2-download="1"></script>');
  if(!html.includes("data-edusentia-professional-transcript"))additions.push('<script src="tenant-professional-transcript-v1.js?edusentia=r40-professional-transcript-v1" data-edusentia-professional-transcript="1"></script>');
  if(!html.includes("data-edusentia-system-health"))additions.push('<script src="tenant-system-health-v1.js?edusentia=r40-system-health-v1" data-edusentia-system-health="1"></script>');
  if(!html.includes("data-edusentia-users-access-hardening"))additions.push('<script src="tenant-users-access-hardening-v1.js?edusentia=r40-users-access-v1" data-edusentia-users-access-hardening="1"></script>');
  if(!html.includes("data-edusentia-academic-readiness"))additions.push('<script src="tenant-academic-readiness-v1.js?edusentia=r40-academic-readiness-v1" data-edusentia-academic-readiness="1"></script>');
  if(!html.includes("data-edusentia-hr-staff"))additions.push('<script src="tenant-hr-staff-v1.js?edusentia=r40-hr-staff-v1" data-edusentia-hr-staff="1"></script>');
  if(!html.includes("data-edusentia-student-services"))additions.push('<script src="tenant-student-services-v1.js?edusentia=r40-student-services-v1" data-edusentia-student-services="1"></script>');
  if(!html.includes("data-edusentia-student-services-actions"))additions.push('<script src="tenant-student-services-actions-v1.js?edusentia=r42-student-services-actions-v1" data-edusentia-student-services-actions="1"></script>');
  if(!additions.length)return new Response(html,{status:response.status,statusText:response.statusText,headers});
  const scripts=additions.join("");
  const body=html.includes("</body>")?html.replace("</body>",`${scripts}</body>`):`${html}${scripts}`;
  return new Response(body,{status:response.status,statusText:response.statusText,headers});
}

self.addEventListener("install",event=>{
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache=>cache.addAll(STATIC_ASSETS))
      .then(()=>self.skipWaiting())
  );
});

self.addEventListener("activate",event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(key=>key.startsWith(CACHE_FAMILY)&&key!==CACHE_NAME).map(key=>caches.delete(key))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener("fetch",event=>{
  const request=event.request;
  if(request.method!=="GET")return;
  const url=new URL(request.url);

  // r42-v14: never put service-worker code in the Auth/Data API transport path.
  // Supabase, Turnstile, R2 signed URLs and every other cross-origin request must
  // be handled directly by the browser/WebView networking stack so native network
  // and Auth errors reach their SDKs unchanged. In particular, do not transform
  // a failed Auth GET into an artificial HTTP 503 response.
  if(url.origin!==self.location.origin)return;

  if(RETIRED_WORKSPACE_ASSET_RE.test(url.pathname)){
    event.respondWith(Promise.resolve(new Response("This Edusentia workspace has been permanently retired.",{
      status:410,
      headers:{"Content-Type":"text/plain; charset=utf-8","Cache-Control":"no-store"}
    })));
    return;
  }

  if(NETWORK_FIRST_PATHS.some(path=>url.pathname.endsWith(path))){
    event.respondWith(networkFirstWithBaseFallback(request,url));
    return;
  }

  if(url.pathname.endsWith("/app.js")||url.pathname.endsWith("/assets/vendor/jszip-3.10.1.min.js")){
    event.respondWith((async()=>{
      try{
        const response=await fetch(request,{cache:"no-store"});
        await cachePut(request,response);
        return response;
      }catch{
        const direct=await cacheMatch(request);
        if(direct)return direct;
        const fallback=new Request(new URL(url.pathname,self.location.origin).href,{method:"GET"});
        return await cacheMatch(fallback)||new Response("Required runtime asset is unavailable.",{
          status:503,
          headers:{"Content-Type":"text/plain; charset=utf-8","Cache-Control":"no-store"}
        });
      }
    })());
    return;
  }

  if(url.pathname.endsWith("/config.js")){
    event.respondWith((async()=>{
      try{
        const response=await fetch(request,{cache:"no-store"});
        await cachePut(request,response);
        return response;
      }catch{
        return await cacheMatch(request)||new Response('window.RCE_CONFIG=Object.freeze({supabaseUrl:"YOUR_SUPABASE_URL",supabaseAnonKey:"YOUR_SUPABASE_PUBLISHABLE_KEY"});',{
          status:503,
          headers:{"Content-Type":"application/javascript","Cache-Control":"no-store"}
        });
      }
    })());
    return;
  }

  if(request.mode==="navigate"){
    const platformAdmin=url.pathname.endsWith("/platform-saas-admin.html");
    const fallback=new URL(platformAdmin?"platform-saas-admin.html":"index.html",self.registration.scope).href;
    event.respondWith((async()=>{
      try{
        const response=await fetch(request,{cache:"no-store"});
        const delivered=platformAdmin?response:await injectTenantEnhancements(response);
        if(delivered.ok)await cachePut(new Request(fallback,{method:"GET"}),delivered);
        return delivered;
      }catch{
        return await cacheMatch(new Request(fallback,{method:"GET"}))||new Response(
          platformAdmin?"Platform administration is unavailable while offline.":"Edusentia is offline and has not completed its first installation.",
          {status:503,headers:{"Content-Type":"text/plain; charset=utf-8","Cache-Control":"no-store"}}
        );
      }
    })());
    return;
  }

  event.respondWith((async()=>{
    const cached=await cacheMatch(request);
    if(cached)return cached;
    const response=await fetch(request);
    await cachePut(request,response);
    return response;
  })());
});

self.addEventListener("sync",event=>{
  if(event.tag==="rce-outbox"||event.tag==="nis-outbox"){
    event.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(clients=>clients.forEach(client=>client.postMessage({type:"FLUSH_OUTBOX"}))));
  }
});

self.addEventListener("message",event=>{
  if(event.data?.type==="SKIP_WAITING")self.skipWaiting();
});
