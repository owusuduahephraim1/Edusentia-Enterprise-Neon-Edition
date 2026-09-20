(() => {
  "use strict";
  class ApiError extends Error { constructor(message,status,code,details){super(message);this.name="ApiError";this.status=status;this.code=code;this.details=details;} }
  const cfg=window.EDS_MASTER_CONFIG||{},base=String(cfg.apiBaseUrl||"").replace(/\/+$/,"");
  async function request(path,options={}){
    const method=options.method||"GET",body=options.body,headers=new Headers(options.headers||{});
    if(body!==undefined)headers.set("content-type","application/json");
    const response=await fetch(base+path,{method,credentials:"include",headers,body:body===undefined?undefined:JSON.stringify(body)});
    const payload=await response.json().catch(()=>({}));
    if(!response.ok){const e=payload&&payload.error||{};throw new ApiError(e.message||("Request failed ("+response.status+")"),response.status,e.code||"request_failed",e.details);}
    return payload;
  }
  window.EdusentiaPlatformApi=Object.freeze({
    session:()=>request("/api/platform/session"),
    login:(email,password,turnstileToken)=>request("/api/platform/auth/login",{method:"POST",body:{email,password,turnstileToken}}),
    completeMfa:(challengeToken,code)=>request("/api/platform/auth/mfa/complete",{method:"POST",body:{challengeToken,code}}),
    logout:()=>request("/api/platform/auth/logout",{method:"POST",body:{}}),
    overview:()=>request("/api/platform/overview"),
    configureInitialLicense:(id,payload)=>request("/api/platform/registrations/"+id+"/license",{method:"POST",body:payload}),
    approveRegistration:id=>request("/api/platform/registrations/"+id+"/approve",{method:"POST",body:{}}),
    denyRegistration:(id,reason)=>request("/api/platform/registrations/"+id+"/deny",{method:"POST",body:{reason}}),
    provisionTenant:(id,action="complete")=>request("/api/platform/tenants/"+id+"/provision",{method:"POST",body:{action}}),
    setTenantStatus:(id,status)=>request("/api/platform/tenants/"+id+"/status",{method:"POST",body:{status}}),
    refreshCapacity:id=>request("/api/platform/tenants/"+id+"/capacity/refresh",{method:"POST",body:{}}),
    setCapacity:(id,limit,reason)=>request("/api/platform/tenants/"+id+"/capacity",{method:"POST",body:{limit,reason}}),
    setLicense:(id,payload)=>request("/api/platform/tenants/"+id+"/license",{method:"POST",body:payload}),
    adminSetupLink:id=>request("/api/platform/tenants/"+id+"/admin-setup-link",{method:"POST",body:{}}),
    health:id=>request("/api/platform/tenants/"+id+"/health",{method:"POST",body:{}})
  });
})();