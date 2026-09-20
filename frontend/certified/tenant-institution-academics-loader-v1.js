(()=>{
  "use strict";
  // r42-v16 clock-safe managed tenant session lifetime.
  // Windows tenant forensics proved that a valid password session could rotate 36-37
  // refresh tokens in roughly 14 seconds. Supabase JS calls auth.getSession() before
  // authenticated REST/RPC requests, and getSession() refreshes whenever expires_at is
  // within its proactive wall-clock margin. Edusentia therefore owns tenant refresh timing
  // from the relative expires_in lifetime instead of allowing a device wall clock to turn
  // every protected request into another refresh. Platform/master Auth is unchanged.
  //
  // r42-v15 tenant explicit-refresh storm guard.
  // r42-v14 desktop lock-safe MFA continuity.
  // r42-v13 post-MFA AAL2 token synchronization.
  // r42-v12 all-pre-login session-read barrier.
  // r42-v11 canonical tenant authentication client.
  // r42-v10 tenant authentication initialization barrier.
  const sdk=window.supabase;
  if(sdk&&typeof sdk.createClient==="function"&&!sdk.__edusentiaTenantAuthInitBarrierInstalled){
    const previousCreateClient=sdk.createClient.bind(sdk);
    const normaliseUrl=value=>String(value||"").replace(/\/+$/,"");
    const sessionClients=new Map();
    const patchedClients=new WeakSet();
    const EXPLICIT_REFRESH_COOLDOWN_MS=5000;
    const REFRESH_SAFETY_MS=120000;
    const MIN_REFRESH_DELAY_MS=60000;
    const DEFAULT_SESSION_LIFETIME_MS=3600000;
    const MAX_SESSION_LIFETIME_MS=86400000;

    const decodeJwtPayload=token=>{
      try{
        const part=String(token||"").split(".")[1];
        if(!part)return null;
        const padded=part.replace(/-/g,"+").replace(/_/g,"/")+"===".slice((part.length+3)%4);
        return JSON.parse(atob(padded));
      }catch{return null}
    };
    const sessionIdOf=session=>String(decodeJwtPayload(session?.access_token)?.session_id||"");
    const lifetimeMsOf=session=>{
      const relative=Number(session?.expires_in||0)*1000;
      if(Number.isFinite(relative)&&relative>=300000)return Math.min(relative,MAX_SESSION_LIFETIME_MS);
      const payload=decodeJwtPayload(session?.access_token);
      const jwtLifetime=(Number(payload?.exp||0)-Number(payload?.iat||0))*1000;
      if(Number.isFinite(jwtLifetime)&&jwtLifetime>=300000)return Math.min(jwtLifetime,MAX_SESSION_LIFETIME_MS);
      return DEFAULT_SESSION_LIFETIME_MS;
    };

    sdk.createClient=(...args)=>{
      const clientUrl=normaliseUrl(args[0]);
      const masterUrl=normaliseUrl(window.EDS_MASTER_CONFIG?.supabaseUrl);
      const options=args[2]&&typeof args[2]==="object"?args[2]:{};
      const authOptions=options.auth&&typeof options.auth==="object"?options.auth:{};
      const isTenantProjectClient=Boolean(clientUrl&&masterUrl&&clientUrl!==masterUrl);
      const ownsPersistentSession=isTenantProjectClient&&authOptions.persistSession!==false;

      if(ownsPersistentSession&&sessionClients.has(clientUrl)){
        const canonical=sessionClients.get(clientUrl);
        window.EDS_TENANT_AUTH_CLIENT=canonical;
        window.EDS_TENANT_AUTH_CLIENT_URL=clientUrl;
        return canonical;
      }

      // r42-v16: the tenant client does not use GoTrue's wall-clock-driven automatic
      // refresh ticker. Edusentia refreshes from relative expires_in time below. This is
      // intentionally tenant-only; Platform Administration keeps the stock Supabase flow.
      const effectiveOptions=ownsPersistentSession
        ?{...options,auth:{...authOptions,autoRefreshToken:false}}
        :options;
      const client=previousCreateClient(args[0],args[1],effectiveOptions);
      try{
        if(ownsPersistentSession){
          sessionClients.set(clientUrl,client);
          window.EDS_TENANT_AUTH_CLIENT=client;
          window.EDS_TENANT_AUTH_CLIENT_URL=clientUrl;
        }
        if(isTenantProjectClient&&!patchedClients.has(client)&&client?.auth&&typeof client.auth.getSession==="function"&&typeof client.auth.signInWithPassword==="function"){
          patchedClients.add(client);
          const originalGetSession=client.auth.getSession.bind(client.auth);
          const originalSignInWithPassword=client.auth.signInWithPassword.bind(client.auth);
          const inheritedRefreshSession=typeof client.auth.refreshSession==="function"?client.auth.refreshSession.bind(client.auth):null;
          const originalSignOut=typeof client.auth.signOut==="function"?client.auth.signOut.bind(client.auth):null;
          const originalOnAuthStateChange=typeof client.auth.onAuthStateChange==="function"?client.auth.onAuthStateChange.bind(client.auth):null;
          const mfa=client.auth.mfa;
          const originalReadAssurance=typeof mfa?.getAuthenticatorAssuranceLevel==="function"?mfa.getAuthenticatorAssuranceLevel.bind(mfa):null;
          const originalChallengeAndVerify=typeof mfa?.challengeAndVerify==="function"?mfa.challengeAndVerify.bind(mfa):null;
          const originalRpc=typeof client.rpc==="function"?client.rpc.bind(client):null;
          const storageKey=String(client.storageKey||authOptions.storageKey||"");
          const projectRef=(()=>{try{return new URL(clientUrl).hostname.split(".")[0]||"tenant"}catch{return"tenant"}})();
          const relativeMetaKey=`eds-relative-session-v16:${projectRef}`;
          let initialSessionRead=null;
          let initialSessionSettled=false;
          let passwordSignInCommitted=false;
          let aalRepairPromise=null;
          let explicitRefreshInFlight=null;
          let lastExplicitRefreshAt=0;
          let stableSession=null;
          let stableRefreshAtPerf=0;
          let stableExpiresAtPerf=0;
          let managedRefreshTimer=null;
          let seedPromise=null;
          const pendingPreSignInReads=new Set();
          const perfNow=()=>Number(window.performance?.now?.()||0);
          const currentResult=(session,error=null)=>({data:{session:session||null,user:session?.user||null},error});
          const permissionDenied=result=>Boolean(result?.error&&(String(result.error.code||"")==="42501"||/access denied|not authorised|not authorized|permission denied|multi-factor authentication is required/i.test(String(result.error.message||""))));
          const recordDiagnostic=(type,detail={})=>{
            const diagnostics=window.EDS_AUTH_DIAGNOSTICS;
            if(!diagnostics||typeof diagnostics!=="object")return;
            if(Array.isArray(diagnostics.events)){
              diagnostics.events.push({type,at:new Date().toISOString(),project:clientUrl,...detail});
              if(diagnostics.events.length>80)diagnostics.events.splice(0,diagnostics.events.length-80);
            }
          };
          const recordRefreshSuppressed=type=>{
            const diagnostics=window.EDS_AUTH_DIAGNOSTICS;
            if(diagnostics&&typeof diagnostics==="object")diagnostics.suppressedRefreshes=Number(diagnostics.suppressedRefreshes||0)+1;
            recordDiagnostic(type);
          };
          const clearManagedTimer=()=>{
            if(managedRefreshTimer!==null){clearTimeout(managedRefreshTimer);managedRefreshTimer=null;}
          };
          const clearStableSession=(removeMeta=true)=>{
            clearManagedTimer();
            stableSession=null;
            stableRefreshAtPerf=0;
            stableExpiresAtPerf=0;
            if(removeMeta)try{localStorage.removeItem(relativeMetaKey)}catch{}
          };
          const persistRelativeMeta=(session,lifetimeMs)=>{
            try{
              localStorage.setItem(relativeMetaKey,JSON.stringify({
                user_id:String(session?.user?.id||""),
                session_id:sessionIdOf(session),
                received_at_ms:Date.now(),
                lifetime_ms:lifetimeMs
              }));
            }catch{}
          };
          const readRelativeMeta=session=>{
            try{
              const raw=JSON.parse(localStorage.getItem(relativeMetaKey)||"null");
              if(!raw||String(raw.user_id||"")!==String(session?.user?.id||""))return null;
              const sid=sessionIdOf(session);
              if(sid&&raw.session_id&&String(raw.session_id)!==sid)return null;
              const lifetime=Number(raw.lifetime_ms||0),received=Number(raw.received_at_ms||0);
              if(!Number.isFinite(lifetime)||lifetime<300000||!Number.isFinite(received)||received<=0)return null;
              const elapsed=Date.now()-received;
              // A negative elapsed interval means the device clock was moved backwards;
              // do not infer freshness from it. A stable offset itself is harmless here.
              if(!Number.isFinite(elapsed)||elapsed<0)return null;
              return{remainingMs:lifetime-elapsed,lifetimeMs:lifetime};
            }catch{return null}
          };
          const readStoredSession=()=>{
            if(!storageKey)return null;
            try{
              const parsed=JSON.parse(localStorage.getItem(storageKey)||"null");
              return parsed&&parsed.access_token&&parsed.refresh_token&&parsed.user?.id?parsed:null;
            }catch{return null}
          };
          const scheduleManagedRefresh=delayMs=>{
            clearManagedTimer();
            const delay=Math.max(MIN_REFRESH_DELAY_MS,Math.floor(delayMs));
            managedRefreshTimer=setTimeout(()=>{void managedRefresh("timer")},delay);
          };
          const adoptSession=(session,remainingMs=null,persistMeta=true)=>{
            if(!session?.access_token||!session?.refresh_token||!session?.user?.id)return null;
            const lifetime=Math.max(300000,Math.min(Number(remainingMs)||lifetimeMsOf(session),MAX_SESSION_LIFETIME_MS));
            const now=perfNow();
            stableSession=session;
            stableExpiresAtPerf=now+lifetime;
            stableRefreshAtPerf=now+Math.max(MIN_REFRESH_DELAY_MS,lifetime-REFRESH_SAFETY_MS);
            if(persistMeta)persistRelativeMeta(session,lifetime);
            scheduleManagedRefresh(stableRefreshAtPerf-now);
            recordDiagnostic("relative_session_adopted",{lifetime_ms:lifetime,aal:String(decodeJwtPayload(session.access_token)?.aal||"")});
            try{void client.realtime?.setAuth?.(session.access_token)}catch{}
            return session;
          };
          const refreshStableSession=async(reason="managed")=>{
            if(!inheritedRefreshSession)return false;
            if(aalRepairPromise)return aalRepairPromise;
            aalRepairPromise=(async()=>{
              try{
                const basis=stableSession||readStoredSession();
                if(!basis?.refresh_token)return false;
                recordDiagnostic("relative_refresh_started",{reason});
                const refreshed=await inheritedRefreshSession(basis);
                const next=refreshed?.data?.session||null;
                if(refreshed?.error||!next?.user?.id)return false;
                adoptSession(next);
                recordDiagnostic("relative_refresh_completed",{reason});
                return true;
              }catch(error){
                recordDiagnostic("relative_refresh_failed",{reason,message:String(error?.message||error||"").slice(0,180)});
                return false;
              }
            })().finally(()=>{aalRepairPromise=null;});
            return aalRepairPromise;
          };
          async function managedRefresh(reason="managed"){
            const ok=await refreshStableSession(reason);
            if(!ok&&stableSession){
              // Preserve a still-present browser session and retry later rather than creating
              // a tight failure loop. Protected RPCs remain fail-closed by server RLS/AAL.
              scheduleManagedRefresh(MIN_REFRESH_DELAY_MS);
            }
            return ok;
          }
          const seedStableSession=async()=>{
            if(stableSession){
              if(perfNow()<stableRefreshAtPerf)return currentResult(stableSession);
              await managedRefresh("relative_expiry");
              return currentResult(stableSession);
            }
            if(seedPromise)return seedPromise;
            seedPromise=(async()=>{
              const stored=readStoredSession();
              if(stored){
                const meta=readRelativeMeta(stored);
                if(meta&&meta.remainingMs>REFRESH_SAFETY_MS){
                  adoptSession(stored,meta.remainingMs);
                  return currentResult(stableSession);
                }
                if(inheritedRefreshSession){
                  try{
                    const refreshed=await inheritedRefreshSession(stored);
                    const next=refreshed?.data?.session||null;
                    if(!refreshed?.error&&next?.user?.id){
                      adoptSession(next);
                      return currentResult(stableSession);
                    }
                    return currentResult(null,refreshed?.error||null);
                  }catch(error){return currentResult(null,error)}
                }
              }
              const result=await originalGetSession();
              const session=result?.data?.session||null;
              if(session)adoptSession(session);
              return result;
            })().finally(()=>{seedPromise=null;});
            return seedPromise;
          };

          client.auth.getSession=(...sessionArgs)=>{
            // getSession has no meaningful public arguments in this runtime. Keep the
            // signature tolerant, but never ask GoTrue to re-evaluate absolute expires_at
            // for an already adopted tenant session.
            const result=Promise.resolve(seedStableSession(...sessionArgs));
            if(!initialSessionRead){
              initialSessionRead=result.then(()=>undefined,()=>undefined).finally(()=>{initialSessionSettled=true;});
            }
            if(!passwordSignInCommitted){
              const tracked=result.then(()=>undefined,()=>undefined);
              pendingPreSignInReads.add(tracked);
              tracked.finally(()=>pendingPreSignInReads.delete(tracked));
            }
            return result;
          };

          client.auth.signInWithPassword=async(...signInArgs)=>{
            if(initialSessionRead&&!initialSessionSettled){
              await initialSessionRead;
              await Promise.resolve();
            }
            while(true){
              const pending=[...pendingPreSignInReads];
              if(pending.length){await Promise.all(pending);continue;}
              await Promise.resolve();
              if(!pendingPreSignInReads.size)break;
            }
            passwordSignInCommitted=true;
            clearStableSession(true);
            const result=await originalSignInWithPassword(...signInArgs);
            if(!result?.error&&result?.data?.session)adoptSession(result.data.session);
            return result;
          };

          if(inheritedRefreshSession){
            client.auth.refreshSession=async(...refreshArgs)=>{
              if(explicitRefreshInFlight)return explicitRefreshInFlight;
              const now=Date.now();
              if(lastExplicitRefreshAt&&now-lastExplicitRefreshAt<EXPLICIT_REFRESH_COOLDOWN_MS&&stableSession){
                recordRefreshSuppressed("explicit_refresh_suppressed");
                return currentResult(stableSession);
              }
              lastExplicitRefreshAt=now;
              explicitRefreshInFlight=(async()=>{
                const basis=refreshArgs[0]||stableSession||readStoredSession();
                const result=await inheritedRefreshSession(basis||undefined);
                if(!result?.error&&result?.data?.session)adoptSession(result.data.session);
                return result;
              })().finally(()=>{explicitRefreshInFlight=null;});
              return explicitRefreshInFlight;
            };
          }

          const readAssurance=async()=>{
            if(!originalReadAssurance)return{data:null,error:new Error("MFA assurance API unavailable")};
            try{return await originalReadAssurance()}catch(error){return{data:null,error}}
          };
          const refreshToAal2=async()=>{
            if(await refreshStableSession("aal2_repair")){
              const assurance=await readAssurance();
              return !assurance?.error&&assurance?.data?.currentLevel==="aal2";
            }
            return false;
          };

          if(originalChallengeAndVerify){
            mfa.challengeAndVerify=async(...verifyArgs)=>{
              const result=await originalChallengeAndVerify(...verifyArgs);
              if(result?.error)return result;
              if(result?.data?.access_token){
                const merged={...(stableSession||{}),...result.data,user:result.data.user||stableSession?.user};
                adoptSession(merged);
              }
              let assurance=await readAssurance();
              if(assurance?.error||assurance?.data?.currentLevel!=="aal2"){
                await refreshToAal2();
                assurance=await readAssurance();
              }
              if(assurance?.error||assurance?.data?.currentLevel!=="aal2"){
                const error=new Error("MFA verification completed, but the secure browser session did not reach AAL2. Please verify again.");
                error.code="mfa_aal2_sync_failed";
                return{data:result?.data||null,error};
              }
              return result;
            };
          }

          if(originalOnAuthStateChange){
            client.auth.onAuthStateChange=callback=>originalOnAuthStateChange((event,session)=>{
              if(event==="SIGNED_OUT"||!session)clearStableSession(true);
              else if(["SIGNED_IN","TOKEN_REFRESHED","MFA_CHALLENGE_VERIFIED","USER_UPDATED"].includes(String(event||"")))adoptSession(session);
              return callback(event,session);
            });
          }

          if(originalSignOut){
            client.auth.signOut=async(...signOutArgs)=>{
              clearStableSession(true);
              return originalSignOut(...signOutArgs);
            };
          }

          if(originalRpc){
            client.rpc=async(...rpcArgs)=>{
              let result=await originalRpc(...rpcArgs);
              if(!permissionDenied(result))return result;
              const assurance=await readAssurance();
              if(assurance?.error||assurance?.data?.currentLevel==="aal2"||assurance?.data?.nextLevel!=="aal2")return result;
              if(await refreshToAal2())result=await originalRpc(...rpcArgs);
              return result;
            };
          }
        }
      }catch(error){console.error("tenant_auth_client_guard_install_failed",error);}
      return client;
    };
    try{
      Object.defineProperty(sdk,"__edusentiaTenantAuthInitBarrierInstalled",{value:true,enumerable:false,configurable:false});
    }catch{sdk.__edusentiaTenantAuthInitBarrierInstalled=true;}
  }
})();

(()=>{
  "use strict";
  // Tertiary Institution support has been retired from active registration and runtime selection.
  // Combined pre-tertiary registration has also been retired.
  // Only Basic / Junior High School and Senior High School are supported registration choices.
  if(window.EDS_INSTITUTION_ACADEMICS_LOADER_V1)return;
  window.EDS_INSTITUTION_ACADEMICS_LOADER_V1=true;

  const SUPPORTED=Object.freeze([
    ["basic_jhs","Basic / Junior High School"],
    ["senior_high","Senior High School"]
  ]);
  const SUPPORTED_CODES=new Set(SUPPORTED.map(([code])=>code));

  function rebuild(select){
    if(!(select instanceof HTMLSelectElement))return;
    const previous=String(select.value||"");
    const options=[...select.options];
    const correct=options.length===SUPPORTED.length&&SUPPORTED.every(([code,label],index)=>options[index]?.value===code&&options[index]?.textContent===label);
    if(!correct){
      select.replaceChildren(...SUPPORTED.map(([code,label])=>{
        const option=document.createElement("option");
        option.value=code;
        option.textContent=label;
        return option;
      }));
    }
    select.value=SUPPORTED_CODES.has(previous)?previous:"basic_jhs";
    select.dataset.supportedSchoolScope="1";
    const hint=select.closest("label")?.querySelector("small");
    const hintText="Choose Basic / Junior High School or Senior High School.";
    if(hint&&hint.textContent!==hintText)hint.textContent=hintText;
  }

  function enforceRegistrationScope(){
    document.querySelectorAll('form#registrationForm select[name="institution_type"], select[name="institution_type"]').forEach(rebuild);
  }

  // Android/WebView native select pickers snapshot their options at pointer/focus time.
  // Sanitize synchronously before the picker opens, in addition to mutation monitoring.
  for(const eventName of ["pointerdown","mousedown","touchstart","focusin","click"]){
    document.addEventListener(eventName,event=>{
      const target=event.target;
      if(target instanceof HTMLSelectElement&&target.name==="institution_type")rebuild(target);
      if(target instanceof Element&&target.closest?.("#registerSchoolButton"))queueMicrotask(enforceRegistrationScope);
    },true);
  }

  document.addEventListener("submit",event=>{
    const form=event.target;
    if(!(form instanceof HTMLFormElement)||form.id!=="registrationForm")return;
    const select=form.elements?.institution_type;
    if(select instanceof HTMLSelectElement)rebuild(select);
    if(select&&!SUPPORTED_CODES.has(String(select.value||""))){
      event.preventDefault();
      event.stopImmediatePropagation();
      select.value="basic_jhs";
      select.reportValidity?.();
    }
  },true);

  const observer=new MutationObserver(enforceRegistrationScope);
  if(document.documentElement)observer.observe(document.documentElement,{subtree:true,childList:true});
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",enforceRegistrationScope,{once:true});else enforceRegistrationScope();
  window.addEventListener("pageshow",enforceRegistrationScope,{passive:true});
})();

(()=>{
  "use strict";
  function loadStudentServicesActions(){
    if(window.EDS_STUDENT_SERVICES_ACTIONS_V1||document.querySelector('script[data-edusentia-student-services-actions]'))return;
    const script=document.createElement("script");
    script.src="tenant-student-services-actions-v1.js?edusentia=r42-student-services-actions-v1";
    script.defer=true;
    script.dataset.edusentiaStudentServicesActions="1";
    script.addEventListener("error",()=>console.error("student_services_actions_v1_load_failed"),{once:true});
    document.body.appendChild(script);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",loadStudentServicesActions,{once:true});else loadStudentServicesActions();
  window.addEventListener("pageshow",loadStudentServicesActions,{passive:true});
})();