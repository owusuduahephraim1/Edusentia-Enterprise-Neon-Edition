(()=>{
  "use strict";
  if(window.EDS_NEON_REFERENCE_COMPAT)return;
  window.EDS_NEON_REFERENCE_COMPAT=true;
  const api=()=>window.EdusentiaApi;
  const listeners=new Set();
  const tenantCode=String(new URLSearchParams(location.search).get("school")||"NEON").trim().toUpperCase()||"NEON";
  window.RCE_CONFIG=Object.assign({masterEdition:false,tenantCode},window.RCE_CONFIG||{});
  window.NIS_CONFIG=window.RCE_CONFIG;

  async function sessionValue(){
    const s=await api().session();
    if(!s?.authenticated)return null;
    return {
      user:{
        id:s.user?.id||"",
        email:s.user?.email||"",
        user_metadata:{display_name:s.user?.displayName||""},
        app_metadata:{role:s.membership?.role||""}
      },
      assurance_level:s.session?.assuranceLevel||1,
      access_token:"worker-cookie-session"
    };
  }
  function asError(error){return error instanceof Error?error:Object.assign(new Error(String(error||"Request failed")),{code:error?.code});}
  async function rpc(name,args={}){
    try{
      const response=await api().certifiedRpc(name,args||{});
      return {data:response?.result??response,error:null};
    }catch(error){return {data:null,error:asError(error)};}
  }
  async function invoke(name,{body={}}={}){
    try{
      const action=String(body?.action||"");
      const payload=(body?.payload&&typeof body.payload==="object")?body.payload:{};
      let data;
      if(name==="directory-user-management")data=await api().directoryUserManagement(action,payload);
      else if(name==="admin-user-management")data=await api().adminUserManagement(action,payload);
      else if(name==="finance-user-management"){
        data=action==="reset_password"
          ?await api().adminUserManagement(action,payload)
          :await api().directoryUserManagement(action,payload);
      }else if(name==="tenant-auth-recovery")data=await api().tenantAuthRecovery(action,body);
      else throw Object.assign(new Error("Unsupported compatibility function: "+name),{code:"compat_function_not_supported"});
      return {data,error:null};
    }catch(error){return {data:null,error:asError(error)};}
  }
  function channel(){
    const c={on(){return c;},subscribe(){return c;},unsubscribe(){return Promise.resolve("ok");}};
    return c;
  }
  const auth={
    async getSession(){try{return {data:{session:await sessionValue()},error:null};}catch(error){return {data:{session:null},error:asError(error)};}},
    onAuthStateChange(callback){
      let active=true;listeners.add(callback);
      queueMicrotask(async()=>{if(!active)return;const session=await sessionValue().catch(()=>null);if(active)callback(session?"SIGNED_IN":"SIGNED_OUT",session);});
      return {data:{subscription:{unsubscribe(){active=false;listeners.delete(callback);}}}};
    }
  };
  const client={rpc,auth,functions:{invoke},channel,removeChannel(){return Promise.resolve("ok");}};
  window.EdusentiaCompatClient=client;
  window.EDS_TENANT_AUTH_CLIENT=client;
  window.addEventListener("edusentia:session-refresh",async()=>{
    const session=await sessionValue().catch(()=>null);
    for(const callback of listeners)try{callback(session?"TOKEN_REFRESHED":"SIGNED_OUT",session)}catch{}
  });
})();