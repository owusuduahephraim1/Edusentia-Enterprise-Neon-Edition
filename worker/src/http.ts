import type { Env } from "./types";
export function json(data: unknown, status=200, headers: HeadersInit={}) { const h=new Headers(headers); h.set("content-type","application/json; charset=utf-8"); h.set("cache-control","no-store"); return new Response(JSON.stringify(data),{status,headers:h}); }
export function error(code:string,message:string,status=400,requestId?:string){return json({error:{code,message,requestId}},status);}
// Only explicit production application origins may send credentialed requests.
// Never authorize wildcards or arbitrary *.pages.dev preview deployments.
export function isAllowedAppOrigin(env:Env, origin:string){
  if(!origin || !/^https:\/\/[^/]+$/i.test(origin))return false;
  const allowed=[env.APP_ORIGIN,...String(env.ADDITIONAL_APP_ORIGINS||"").split(",")].map(v=>String(v||"").trim());
  return allowed.includes(origin);
}
const PUBLIC_VERIFICATION_ORIGIN="https://verify.edusentia.com";
const PUBLIC_VERIFICATION_ROUTES=new Set([
  "/api/public/id-card-verification",
  "/api/public/document-verification"
]);
// The public verification site is deliberately NOT a trusted application
// origin: it may read two token-bound GET routes, never send authenticated
// or credential-bearing requests to privileged endpoints.
export function isAllowedPublicVerification(request:Request){
  return request.headers.get("origin")===PUBLIC_VERIFICATION_ORIGIN &&
    PUBLIC_VERIFICATION_ROUTES.has(new URL(request.url).pathname) &&
    ["GET","HEAD","OPTIONS"].includes(request.method.toUpperCase());
}
export function corsHeaders(request:Request, env:Env){
  const origin=request.headers.get("origin")||"";
  const h=new Headers();
  if(isAllowedAppOrigin(env,origin)){
    h.set("access-control-allow-origin",origin);
    h.set("access-control-allow-credentials","true");
    h.set("vary","Origin");
  }else if(isAllowedPublicVerification(request)){
    h.set("access-control-allow-origin",PUBLIC_VERIFICATION_ORIGIN);
    h.set("vary","Origin");
  }
  const publicOnly=isAllowedPublicVerification(request) && !isAllowedAppOrigin(env,origin);
  h.set("access-control-allow-methods",publicOnly?"GET,HEAD,OPTIONS":"GET,POST,PUT,PATCH,DELETE,OPTIONS");
  h.set("access-control-allow-headers",publicOnly?"accept":"content-type,x-request-id,x-csrf-token,authorization");
  h.set("access-control-max-age","86400");
  return h;
}
export function secureHeaders(h:Headers){h.set("x-content-type-options","nosniff");h.set("referrer-policy","no-referrer");h.set("permissions-policy","camera=(), microphone=(), geolocation=()");h.set("x-frame-options","DENY");h.set("content-security-policy","default-src 'none'; frame-ancestors 'none'; base-uri 'none'");return h;}
export function withHeaders(response:Response, request:Request, env:Env){const h=new Headers(response.headers);for(const [k,v] of corsHeaders(request,env)) h.set(k,v);secureHeaders(h);return new Response(response.body,{status:response.status,statusText:response.statusText,headers:h});}
export async function readJson<T=Record<string,unknown>>(request:Request):Promise<T>{if(!(request.headers.get("content-type")||"").toLowerCase().includes("application/json"))throw new Error("invalid_content_type");return await request.json() as T;}
export function cookieValue(request:Request,name:string){const raw=request.headers.get("cookie")||"";for(const part of raw.split(";")){const i=part.indexOf("=");if(i>0&&part.slice(0,i).trim()===name)return decodeURIComponent(part.slice(i+1).trim());}return "";}
