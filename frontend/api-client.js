(() => {
  "use strict";
  const cfg=window.EDS_MASTER_CONFIG||{};
  const apiBase=String(cfg.apiBaseUrl||"").replace(/\/+$/,"");

  class ApiError extends Error{
    constructor(message,status,code,details){super(message);this.name="ApiError";this.status=status;this.code=code;this.details=details;}
  }

  async function request(path,options={}){
    if(!apiBase||!/^https:\/\//i.test(apiBase))throw new ApiError("API is not configured",0,"api_not_configured");
    const headers=new Headers(options.headers||{});
    if(options.body!=null&&!(options.body instanceof FormData)&&!headers.has("content-type"))headers.set("content-type","application/json");
    headers.set("accept","application/json");
    const response=await fetch(`${apiBase}${path}`,{
      ...options,headers,credentials:"include",
      body:options.body==null||options.body instanceof FormData||typeof options.body==="string"?options.body:JSON.stringify(options.body)
    });
    const type=response.headers.get("content-type")||"";
    const payload=type.includes("application/json")?await response.json().catch(()=>({})):await response.text();
    if(!response.ok){const e=payload?.error||{};throw new ApiError(e.message||`Request failed (${response.status})`,response.status,e.code||"request_failed",e.details);}
    return payload;
  }
  const post=(path,body={})=>request(path,{method:"POST",body});

  async function uploadFile(file,kind="document"){
    const prepared=await post("/api/files/upload-url",{filename:file.name,contentType:file.type||"application/octet-stream",size:file.size,kind});
    const response=await fetch(`${apiBase}${prepared.uploadUrl}`,{method:prepared.method||"PUT",credentials:"include",headers:{"content-type":file.type||"application/octet-stream"},body:file});
    const payload=await response.json().catch(()=>({}));
    if(!response.ok){const e=payload?.error||{};throw new ApiError(e.message||`Upload failed (${response.status})`,response.status,e.code||"upload_failed",e.details);}
    return payload;
  }

  async function uploadReportPdf(reportId,file){
    const type=String(file?.type||"application/pdf");
    const prepared=await post(`/api/reports/${encodeURIComponent(reportId)}/pdf/upload-url`,{filename:file?.name||"report.pdf",contentType:type,size:Number(file?.size||0)});
    const response=await fetch(`${apiBase}${prepared.uploadUrl}`,{method:prepared.method||"PUT",credentials:"include",headers:{"content-type":type},body:file});
    const payload=await response.json().catch(()=>({}));
    if(!response.ok){const e=payload?.error||{};throw new ApiError(e.message||`Upload failed (${response.status})`,response.status,e.code||"upload_failed",e.details);}
    return {...payload,objectKey:prepared.objectKey};
  }
  async function downloadReportPdf(reportId){
    const response=await fetch(`${apiBase}/api/reports/${encodeURIComponent(reportId)}/pdf/download`,{credentials:"include",headers:{accept:"application/pdf"}});
    if(!response.ok){
      const payload=await response.json().catch(()=>({}));const e=payload?.error||{};
      throw new ApiError(e.message||`Download failed (${response.status})`,response.status,e.code||"download_failed",e.details);
    }
    return response.blob();
  }
  async function deleteReportPdfObject(reportId,key){
    return request(`/api/reports/${encodeURIComponent(reportId)}/pdf/object?key=${encodeURIComponent(key)}`,{method:"DELETE"});
  }


  async function downloadFile(objectKey){
    const response=await fetch(`${apiBase}/api/files/download?key=${encodeURIComponent(String(objectKey||""))}`,{credentials:"include"});
    if(!response.ok){const payload=await response.json().catch(()=>({}));const e=payload?.error||{};throw new ApiError(e.message||`Download failed (${response.status})`,response.status,e.code||"download_failed",e.details);}
    return response.blob();
  }

  window.EdusentiaApi=Object.freeze({
    request,health:()=>request("/api/health"),

    registerSchool:(payload)=>post("/api/public/school-registration",payload),
    resolveSchool:(tenantCode)=>request(`/api/public/schools/${encodeURIComponent(String(tenantCode||"").trim().toUpperCase())}`),
    requestAccessRecovery:(payload)=>post("/api/public/access-recovery",payload),
    inspectAdminSetup:(token)=>post("/api/public/admin-setup/inspect",{token}),
    completeAdminSetup:(payload)=>post("/api/public/admin-setup/complete",payload),

    session:()=>request("/api/session"),
    login:(email,password,tenantCode="",turnstileToken="")=>post("/api/auth/login",{email,password,tenantCode,turnstileToken}),
    completeMfa:(challengeToken,code)=>post("/api/auth/mfa/complete",{challengeToken,code}),
    logout:()=>post("/api/auth/logout"),
    bootstrap:()=>request("/api/bootstrap"),
    updateSchoolSettings:(payload)=>post("/api/settings/school",payload),
    guardianAccountRecords:()=>request("/api/admin/guardian-account-records"),
    certifiedRpc:(operation,args={})=>post(`/api/compat/rpc/${encodeURIComponent(String(operation||""))}`,{args}),
    adminUserManagement:(action,payload={})=>post("/api/compat/functions/admin-user-management",{action,payload}),
    directoryUserManagement:(action,payload={})=>post("/api/compat/functions/directory-user-management",{action,payload}),
    tenantAuthRecovery:(action,payload={})=>post("/api/compat/functions/tenant-auth-recovery",{action,...payload}),
    scheduledBackup:(action,payload={})=>post("/api/compat/functions/scheduled-backup",{action,...payload}),
    backupDownloadGateway:(backupId)=>post("/api/compat/functions/backup-download-gateway",{backup_id:backupId}),
    licenseStatus:()=>request("/api/license/status"),
    activateLicense:(code)=>post("/api/license/activate",{code}),
    mfaFactors:()=>request("/api/security/mfa/factors"),
    mfaEnroll:(friendlyName)=>post("/api/security/mfa/enroll",{friendlyName}),
    mfaVerify:(factorId,code)=>post(`/api/security/mfa/factors/${factorId}/verify`,{code}),
    mfaRemove:(factorId)=>post(`/api/security/mfa/factors/${factorId}/remove`,{}),
    listStudents:(query={})=>request(`/api/students?${new URLSearchParams(query)}`),
    createStudent:(payload)=>post("/api/students",payload),
    listStaff:(query={})=>request(`/api/staff?${new URLSearchParams(query)}`),
    listFinanceSummary:()=>request("/api/finance/summary"),
    listFinanceInvoices:(query={})=>request(`/api/finance/invoices?${new URLSearchParams(query)}`),
    listFinancePayments:(query={})=>request(`/api/finance/payments?${new URLSearchParams(query)}`),
    listOperationsOverview:()=>request("/api/operations/overview"),
    prepareUpload:(payload)=>post("/api/files/upload-url",payload),
    uploadFile,
    downloadFile,
    uploadReportPdf,
    downloadReportPdf,
    deleteReportPdfObject,

    platformSession:()=>request("/api/platform/session"),
    platformLogin:(email,password,turnstileToken="")=>post("/api/platform/auth/login",{email,password,turnstileToken}),
    platformCompleteMfa:(challengeToken,code)=>post("/api/platform/auth/mfa/complete",{challengeToken,code}),
    platformLogout:()=>post("/api/platform/auth/logout"),
    platformOverview:()=>request("/api/platform/overview"),
    platformMfaFactors:()=>request("/api/platform/mfa/factors"),
    platformMfaEnroll:(friendlyName)=>post("/api/platform/mfa/enroll",{friendlyName}),
    platformMfaVerify:(factorId,code)=>post(`/api/platform/mfa/factors/${factorId}/verify`,{code}),
    platformMfaRemove:(factorId)=>post(`/api/platform/mfa/factors/${factorId}/remove`,{}),
    configureInitialLicense:(registrationId,payload)=>post(`/api/platform/registrations/${registrationId}/license`,payload),
    approveRegistration:(registrationId)=>post(`/api/platform/registrations/${registrationId}/approve`,{}),
    denyRegistration:(registrationId,reason)=>post(`/api/platform/registrations/${registrationId}/deny`,{reason}),
    provisionTenant:(tenantId,action="complete")=>post(`/api/platform/tenants/${tenantId}/provision`,{action}),
    setTenantStatus:(tenantId,status)=>post(`/api/platform/tenants/${tenantId}/status`,{status}),
    refreshTenantCapacity:(tenantId)=>post(`/api/platform/tenants/${tenantId}/capacity/refresh`,{}),
    setTenantCapacity:(tenantId,limit,reason)=>post(`/api/platform/tenants/${tenantId}/capacity`,{limit,reason}),
    issueTenantLicense:(tenantId,payload)=>post(`/api/platform/tenants/${tenantId}/license`,payload),
    revokeLicenseAuthorization:(tenantId,authorizationId,reason)=>post(`/api/platform/tenants/${tenantId}/license-authorizations/${authorizationId}/revoke`,{reason}),
    deleteRevokedLicenseAuthorization:(tenantId,authorizationId)=>post(`/api/platform/tenants/${tenantId}/license-authorizations/${authorizationId}/delete`,{confirmation:"DELETE"}),
    tenantAdminSetupLink:(tenantId)=>post(`/api/platform/tenants/${tenantId}/admin-setup-link`,{}),
    resolveRecovery:(requestId,mode)=>post(`/api/platform/recovery/${requestId}/resolve`,{mode}),
    denyRecovery:(requestId,reason)=>post(`/api/platform/recovery/${requestId}/deny`,{reason}),
    tenantHealth:(tenantId)=>post(`/api/platform/tenants/${tenantId}/health`,{}),
    deleteTenant:(tenantId,confirmation,reason)=>post(`/api/platform/tenants/${tenantId}/delete`,{confirmation,reason}),
    runReleaseGate:()=>post("/api/platform/release-gate",{})
  });
})();