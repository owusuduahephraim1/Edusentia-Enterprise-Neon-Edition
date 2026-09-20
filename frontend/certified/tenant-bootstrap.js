(() => {
  "use strict";
  const MASTER=window.EDS_MASTER_CONFIG||window.RCE_CONFIG||{};
  const SESSION_KEY="edusentia_tenant_context_r39";
  const byId=id=>document.getElementById(id);
  const fnUrl=slug=>`${String(MASTER.supabaseUrl||"").replace(/\/+$/,"")}/functions/v1/${slug}`;
  const headers=()=>({"content-type":"application/json","apikey":MASTER.supabaseAnonKey});
  let authMessageTimer=0;
  let currentTenant=null;
  let recoveryWidgetId=null;
  let recoveryToken="";
  const FALLBACK_INSTITUTION_TYPES=Object.freeze([
    {code:"basic_jhs",name:"Basic / Junior High School"},
    {code:"senior_high",name:"Senior High School"}
  ]);
  const SUPPORTED_INSTITUTION_TYPE_CODES=new Set(FALLBACK_INSTITUTION_TYPES.map(item=>item.code));
  const message=(text="",timeout=8000)=>{const el=byId("authMessage");if(!el)return;clearTimeout(authMessageTimer);const value=String(text||"").trim();el.textContent=value;el.classList.toggle("hidden",!value);if(value&&timeout>0)authMessageTimer=setTimeout(()=>message("",0),timeout)};
  function configured(){return /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(String(MASTER.supabaseUrl||""))&&String(MASTER.supabaseAnonKey||"").length>20}
  function makeTenantConfig(t){return Object.freeze({...MASTER,supabaseUrl:t.supabase_url,supabaseAnonKey:t.publishable_key,masterEdition:false,generatedSchoolPackage:false,schoolName:t.school_name||"",schoolShortName:t.tenant_code||"",tenantCode:t.tenant_code||"",institutionType:t.institution_type||"basic_jhs",projectRef:t.project_ref||"",authorizedDomain:"edusentia.app",productVersion:"7.4.0-r40-product-ready-v9",appName:"Edusentia Enterprise"})}
  async function call(slug,body,method="POST"){const r=await fetch(fnUrl(slug),{method,headers:headers(),body:method==="GET"?undefined:JSON.stringify(body||{}),cache:"no-store",redirect:"error"});const d=await r.json().catch(()=>({}));if(!r.ok||d.ok!==true)throw new Error(d.error||`Request failed (${r.status})`);return d}
  async function resolveTenant(code){const d=await call("tenant-resolver",{tenant_code:String(code||"").trim().toUpperCase()});currentTenant=d.tenant||null;sessionStorage.setItem(SESSION_KEY,JSON.stringify(d.tenant));return d.tenant}
  async function resolveWorkspace(email){const d=await call("tenant-resolver",{email:String(email||"").trim().toLowerCase()});if(d?.workspace==="tenant"&&d.tenant)currentTenant=d.tenant;return d}
  function script(src){return new Promise((resolve,reject)=>{const s=document.createElement("script");s.src=src;s.onload=resolve;s.onerror=reject;document.body.appendChild(s)})}
  async function enforceReleaseWorker(){if(window.RCE_ANDROID_APP||!("serviceWorker" in navigator))return;try{const registration=await navigator.serviceWorker.register("service-worker.js?rce=r40-product-ready-v9",{updateViaCache:"none"});await registration.update()}catch(error){console.warn("service_worker_release_update_failed",error)}}
  let loaded=false;
  let turnstileWidgetId=null;
  let turnstileToken="";
  function turnstileConfigured(){const k=String(MASTER.turnstileSiteKey||"").trim();return k.length>10&&!/^YOUR_/i.test(k)}
  async function ensureTurnstile(){if(window.turnstile?.render)return window.turnstile;if(!document.querySelector('script[data-edusentia-turnstile]')){const el=document.createElement("script");el.src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";el.defer=true;el.dataset.edusentiaTurnstile="1";document.head.appendChild(el)}for(let i=0;i<80;i++){if(window.turnstile?.render)return window.turnstile;await new Promise(r=>setTimeout(r,50))}throw new Error("verification_unavailable")}
  async function renderRegistrationTurnstile(){turnstileToken="";if(!turnstileConfigured())throw new Error("registration_security_not_configured");const ts=await ensureTurnstile();if(turnstileWidgetId!==null){try{ts.reset(turnstileWidgetId);return}catch{turnstileWidgetId=null}}const container=byId("registrationTurnstile");if(!container)throw new Error("verification_unavailable");turnstileWidgetId=ts.render(container,{sitekey:String(MASTER.turnstileSiteKey),action:"school_registration",theme:"auto",appearance:"always",callback:t=>{turnstileToken=String(t||"")},"expired-callback":()=>{turnstileToken=""},"error-callback":()=>{turnstileToken=""}})}
  async function handlePasswordRecovery(config){
    const params=new URLSearchParams(location.search);if(params.get("recovery")!=="1")return false;
    const view=byId("passwordRecoveryView"),form=byId("passwordRecoveryForm"),messageEl=byId("passwordRecoveryMessage");if(!view||!form)return false;
    window.RCE_CONFIG=config;window.NIS_CONFIG=config;
    const recoveryClient=window.supabase.createClient(config.supabaseUrl,config.supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
    let session=null;
    for(let i=0;i<40&&!session;i++){session=(await recoveryClient.auth.getSession()).data.session;if(!session)await new Promise(r=>setTimeout(r,100))}
    document.querySelectorAll("main.auth-view").forEach(el=>el.classList.add("hidden"));view.classList.remove("hidden");
    if(!session){if(messageEl){messageEl.textContent="This recovery link is invalid or has expired. Request a new administrator recovery link.";messageEl.classList.remove("hidden")}return true}
    byId("toggleRecoveryPassword")?.addEventListener("click",()=>{const input=byId("recoveryPassword");if(input)input.type=input.type==="password"?"text":"password"});
    form.addEventListener("submit",async ev=>{ev.preventDefault();const password=String(byId("recoveryPassword")?.value||""),confirm=String(byId("recoveryPasswordConfirm")?.value||""),button=form.querySelector('button[type="submit"]');if(messageEl){messageEl.textContent="";messageEl.classList.add("hidden")}if(password.length<8){if(messageEl){messageEl.textContent="Use at least eight characters.";messageEl.classList.remove("hidden")}return}if(password!==confirm){if(messageEl){messageEl.textContent="The two passwords do not match.";messageEl.classList.remove("hidden")}return}button.disabled=true;button.textContent="Updating…";try{const {error}=await recoveryClient.auth.updateUser({password});if(error)throw error;await recoveryClient.functions.invoke("tenant-auth-recovery",{body:{action:"record_password_recovery"}}).catch(()=>{});await recoveryClient.auth.signOut({scope:"local"}).catch(()=>{});if(messageEl){messageEl.textContent="Password changed successfully. Returning to secure sign in…";messageEl.classList.remove("hidden")}const url=new URL(location.href);url.searchParams.delete("recovery");url.hash="";setTimeout(()=>location.replace(url.pathname+url.search),700)}catch(error){if(messageEl){messageEl.textContent=String(error?.message||error).replaceAll("_"," ");messageEl.classList.remove("hidden")}button.disabled=false;button.textContent="Set new password"}});
    return true;
  }
  async function loadRuntime(config,submit=false){if(loaded)return;loaded=true;currentTenant=currentTenant||{tenant_code:config.tenantCode,school_name:config.schoolName,institution_type:config.institutionType||"basic_jhs",supabase_url:config.supabaseUrl,publishable_key:config.supabaseAnonKey};window.RCE_CONFIG=config;window.NIS_CONFIG=config;window.dispatchEvent(new Event("edusentia:tenant-ready"));if(await handlePasswordRecovery(config)){await enforceReleaseWorker();return}const schoolField=byId("loginSchoolCode")?.closest("label");if(schoolField)schoolField.classList.add("hidden");const register=byId("registerSchoolButton"),reset=byId("changeSchoolButton");if(register)register.classList.add("hidden");if(reset)reset.classList.add("hidden");await script("app.js?edusentia=r40-product-ready-v9");window.RCE_RUNTIME_BUILD="7.4.0-r40-product-ready-v9";await enforceReleaseWorker();await script("template-upload-v37.js?edusentia=r39-multitenant");if(String(config.institutionType||"basic_jhs")!=="basic_jhs")await script("tenant-institution-academics-v1.js?edusentia=r41-institution-academics-v1");if(submit)setTimeout(()=>byId("loginForm")?.requestSubmit(),0)}
  async function platformMode(){sessionStorage.removeItem(SESSION_KEY);message("",0);const url=new URL(location.href);url.searchParams.delete("platform");history.replaceState(null,"",`${url.pathname}${url.search}${url.hash}`)}
  async function signInPlatform(email,password){
    const client=window.supabase.createClient(MASTER.supabaseUrl,MASTER.supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true}});
    const {error}=await client.auth.signInWithPassword({email,password});
    if(error)throw error;
    location.href="platform-saas-admin.html";
  }
  function setRegistrationState(success=false){const form=byId("registrationForm"),done=byId("registrationSuccess");form?.classList.toggle("hidden",success);done?.classList.toggle("hidden",!success)}
  function ensureInstitutionTypeField(items=FALLBACK_INSTITUTION_TYPES){
    const form=byId("registrationForm"),schoolInput=form?.elements?.school_name;if(!form||!schoolInput)return null;
    let select=form.elements.institution_type;
    if(!select){
      const schoolGrid=schoolInput.closest(".registration-grid");if(!schoolGrid)return null;
      const label=document.createElement("label");label.className="field registration-wide";label.dataset.institutionTypeField="1";
      const title=document.createElement("span");title.textContent="Institution type";
      const hint=document.createElement("small");hint.textContent="Choose Basic / Junior High School or Senior High School.";title.append(" ",hint);
      select=document.createElement("select");select.name="institution_type";select.required=true;
      label.append(title,select);schoolGrid.append(label);
    }
    const requested=Array.isArray(items)&&items.length?items:FALLBACK_INSTITUTION_TYPES;
    const allowed=requested.filter(item=>SUPPORTED_INSTITUTION_TYPE_CODES.has(String(item?.code||"").trim()));
    const effective=allowed.length?allowed:FALLBACK_INSTITUTION_TYPES;
    select.replaceChildren();
    for(const item of effective){const code=String(item?.code||"").trim(),name=String(item?.name||code).trim();const option=document.createElement("option");option.value=code;option.textContent=name;select.append(option)}
    for(const fallback of FALLBACK_INSTITUTION_TYPES){if([...select.options].some(option=>option.value===fallback.code))continue;const option=document.createElement("option");option.value=fallback.code;option.textContent=fallback.name;select.append(option)}
    select.value="basic_jhs";
    select.dataset.supportedSchoolScope="1";
    return select;
  }
  function closeRegistration(){turnstileToken="";if(window.turnstile&&turnstileWidgetId!==null)try{window.turnstile.reset(turnstileWidgetId)}catch{}const dialog=byId("registrationDialog");if(dialog?.open)dialog.close()}
  async function registration(){const dialog=byId("registrationDialog");if(!dialog)return;const form=byId("registrationForm"),msg=byId("registrationMessage"),summary=byId("registrationSuccessSchool");ensureInstitutionTypeField();setRegistrationState(false);form?.reset();form?.removeAttribute("aria-busy");if(form?.elements?.institution_type)form.elements.institution_type.value="basic_jhs";if(msg)msg.textContent="";if(summary)summary.textContent="";const plan=byId("registrationPlan");if(plan)plan.value="starter";dialog.showModal();requestAnimationFrame(()=>form?.elements?.school_name?.focus());try{const d=await call("tenant-registration",null,"GET");if(d.initial_plan?.code!=="starter")throw new Error("starter_plan_unavailable");ensureInstitutionTypeField(d.institution_types);await renderRegistrationTurnstile()}catch(e){if(msg)msg.textContent="Registration service unavailable."}}
  async function submitRegistration(ev){ev.preventDefault();const form=ev.currentTarget,msg=byId("registrationMessage"),btn=form.querySelector("button[type=submit]"),defaultLabel=btn.textContent;btn.disabled=true;btn.textContent="Submitting…";form.setAttribute("aria-busy","true");if(msg)msg.textContent="";try{if(!turnstileToken)throw new Error("complete_security_verification");const v=Object.fromEntries(new FormData(form).entries()),schoolName=String(v.school_name||"").trim(),institutionType=String(v.institution_type||"basic_jhs").trim();if(!SUPPORTED_INSTITUTION_TYPE_CODES.has(institutionType))throw new Error("unsupported_institution_type");await call("tenant-registration",{school_name:schoolName,institution_type:institutionType,contact_name:v.contact_name,contact_email:v.contact_email,contact_phone:v.contact_phone,country:v.country,plan_code:"starter",turnstile_token:turnstileToken});form.reset();const plan=byId("registrationPlan");if(plan)plan.value="starter";if(form.elements.institution_type)form.elements.institution_type.value="basic_jhs";turnstileToken="";if(window.turnstile&&turnstileWidgetId!==null)window.turnstile.reset(turnstileWidgetId);const summary=byId("registrationSuccessSchool");if(summary)summary.textContent=schoolName;setRegistrationState(true);requestAnimationFrame(()=>byId("registrationSuccessClose")?.focus())}catch(e){turnstileToken="";if(window.turnstile&&turnstileWidgetId!==null)try{window.turnstile.reset(turnstileWidgetId)}catch{}if(msg)msg.textContent=String(e.message||e).replaceAll("_"," ")}finally{btn.disabled=false;btn.textContent=defaultLabel;form.removeAttribute("aria-busy")}}
  async function renderRecoveryTurnstile(){
    recoveryToken="";
    if(!turnstileConfigured())throw new Error("recovery_security_not_configured");
    const ts=await ensureTurnstile(),container=byId("accessRecoveryTurnstile");if(!container)throw new Error("verification_unavailable");
    if(recoveryWidgetId!==null){try{ts.remove(recoveryWidgetId)}catch{}recoveryWidgetId=null;container.innerHTML=""}
    recoveryWidgetId=ts.render(container,{sitekey:String(MASTER.turnstileSiteKey),action:"tenant_admin_recovery",theme:"auto",appearance:"always",callback:t=>{recoveryToken=String(t||"")},"expired-callback":()=>{recoveryToken=""},"error-callback":()=>{recoveryToken=""}});
  }
  function recoveryTypeLabel(type){return type==="mfa"?"Authenticator recovery":type==="both"?"Password and authenticator recovery":"Password recovery"}
  async function openAccessRecovery(type="password",identifier=""){
    const dialog=byId("accessRecoveryDialog"),form=byId("accessRecoveryForm"),messageEl=byId("accessRecoveryMessage");if(!dialog||!form)return;
    const recoveryType=["password","mfa","both"].includes(type)?type:"password";
    byId("accessRecoveryType").value=recoveryType;byId("accessRecoveryTitle").textContent=recoveryTypeLabel(recoveryType);
    const resolved=String(identifier||currentTenant?.tenant_code||byId("loginEmail")?.value||"").trim();byId("accessRecoveryIdentifier").value=resolved;
    if(messageEl)messageEl.textContent="";recoveryToken="";dialog.showModal();requestAnimationFrame(()=>byId("accessRecoveryContactEmail")?.focus());
    try{await renderRecoveryTurnstile()}catch(e){if(messageEl)messageEl.textContent="Recovery verification is temporarily unavailable."}
  }
  function closeAccessRecovery(){recoveryToken="";const dialog=byId("accessRecoveryDialog");if(dialog?.open)dialog.close();if(window.turnstile&&recoveryWidgetId!==null){try{window.turnstile.remove(recoveryWidgetId)}catch{}recoveryWidgetId=null}}
  async function submitAccessRecovery(ev){
    ev.preventDefault();const form=ev.currentTarget,button=byId("accessRecoverySubmit"),messageEl=byId("accessRecoveryMessage");if(!form.reportValidity())return;if(!recoveryToken){if(messageEl)messageEl.textContent="Complete the security verification first.";return}
    button.disabled=true;button.textContent="Submitting…";if(messageEl)messageEl.textContent="";
    try{
      const values=Object.fromEntries(new FormData(form).entries());const d=await call("tenant-access-recovery",{identifier:values.identifier,contact_email:values.contact_email,recovery_type:values.recovery_type,turnstile_token:recoveryToken});
      if(messageEl)messageEl.textContent=String(d.message||"Recovery request recorded.");form.querySelectorAll("input").forEach(input=>{if(input.name==="contact_email")input.value=""});
      recoveryToken="";if(window.turnstile&&recoveryWidgetId!==null)try{window.turnstile.reset(recoveryWidgetId)}catch{}
    }catch(e){if(messageEl)messageEl.textContent=String(e.message||e).replaceAll("_"," ");recoveryToken="";if(window.turnstile&&recoveryWidgetId!==null)try{window.turnstile.reset(recoveryWidgetId)}catch{}
    }finally{button.disabled=false;button.textContent="Submit protected request"}
  }
  function installRecoveryControls(){
    byId("forgotPasswordButton")?.addEventListener("click",()=>openAccessRecovery("password",currentTenant?.tenant_code||byId("loginEmail")?.value||""));
    byId("accessRecoveryForm")?.addEventListener("submit",submitAccessRecovery);
    byId("accessRecoveryClose")?.addEventListener("click",closeAccessRecovery);byId("accessRecoveryCancel")?.addEventListener("click",closeAccessRecovery);
    byId("accessRecoveryDialog")?.addEventListener("cancel",ev=>{ev.preventDefault();closeAccessRecovery()});
    window.EdusentiaAccessRecovery=Object.freeze({open:openAccessRecovery});
  }
  async function init(){message("",0);installRecoveryControls();document.getElementById("loader")?.classList.add("hidden");document.getElementById("authView")?.classList.remove("hidden");if(!configured()){message("Service unavailable.");return}const params=new URLSearchParams(location.search);if(params.get("platform")==="1")platformMode();const qTenant=params.get("tenant");if(qTenant){try{return await loadRuntime(makeTenantConfig(await resolveTenant(qTenant)),false)}catch{message("School access unavailable.");return}}try{const saved=JSON.parse(sessionStorage.getItem(SESSION_KEY)||"null");if(saved?.tenant_code&&saved?.supabase_url&&saved?.publishable_key){currentTenant=saved;return await loadRuntime(makeTenantConfig(saved),false)}}catch{sessionStorage.removeItem(SESSION_KEY)}const form=byId("loginForm");["loginEmail","loginPassword"].forEach(id=>byId(id)?.addEventListener("input",()=>message("",0)));form?.addEventListener("submit",async ev=>{if(loaded)return;ev.preventDefault();ev.stopImmediatePropagation();message("");const email=String(byId("loginEmail")?.value||"").trim().toLowerCase(),password=String(byId("loginPassword")?.value||"");if(!email||!password){message("Enter your email address and password.");return}const btn=form.querySelector("button[type=submit]");btn.disabled=true;try{const workspace=await resolveWorkspace(email);if(workspace.workspace==="tenant"&&workspace.tenant){sessionStorage.setItem(SESSION_KEY,JSON.stringify(workspace.tenant));await loadRuntime(makeTenantConfig(workspace.tenant),true);return}if(workspace.workspace==="platform"){await signInPlatform(email,password);return}throw new Error("workspace_unavailable")}catch(error){console.error("workspace_login_failed",error);message("Email or password is incorrect, or this workspace is unavailable.")}finally{btn.disabled=false}},true);byId("togglePassword")?.addEventListener("click",()=>{const input=byId("loginPassword");if(!input)return;input.type=input.type==="password"?"text":"password"});byId("registerSchoolButton")?.addEventListener("click",()=>{message("",0);registration()});byId("changeSchoolButton")?.addEventListener("click",()=>{sessionStorage.removeItem(SESSION_KEY);location.href=location.pathname});byId("registrationForm")?.addEventListener("submit",submitRegistration);byId("registrationForm")?.addEventListener("change",()=>{const msg=byId("registrationMessage");if(msg)msg.textContent=""});["registrationClose","registrationCancel","registrationSuccessClose"].forEach(id=>byId(id)?.addEventListener("click",closeRegistration));byId("registrationDialog")?.addEventListener("cancel",ev=>{ev.preventDefault();closeRegistration()})}
  init().catch(e=>{console.error(e);message("Service unavailable.")});
})();
