(() => {
  "use strict";
  const byId = id => document.getElementById(id);
  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  const api = () => window.EdusentiaApi;
  const turnstileSiteKey = String(window.EDS_MASTER_CONFIG?.turnstileSiteKey || "").trim();
  let turnstileToken = "", turnstileWidgetId = null, mfaChallenge = "", pendingSession = null;

  function resetTurnstile(){turnstileToken="";if(window.turnstile&&turnstileWidgetId!=null){try{window.turnstile.reset(turnstileWidgetId);}catch{}}}
  function renderTurnstile(){
    if(!turnstileSiteKey||!window.turnstile||turnstileWidgetId!=null||!byId("turnstileWidget"))return;
    turnstileWidgetId=window.turnstile.render("#turnstileWidget",{sitekey:turnstileSiteKey,action:"login",theme:"auto",size:"flexible",callback:token=>{turnstileToken=String(token||"");message("");},"expired-callback":()=>{turnstileToken="";message("Verification expired. Please verify again.","error");},"error-callback":()=>{turnstileToken="";message("Human verification could not be completed. Please try again.","error");}});
  }
  window.onTurnstileLoad=renderTurnstile;
  function show(view){for(const id of ["loader","authView","appShell","fatalView"])byId(id)?.classList.add("hidden");byId(view)?.classList.remove("hidden");}
  function showAuthStep(step){for(const id of ["loginForm","mfaPanel","recoveryPanel"])byId(id)?.classList.add("hidden");byId(step)?.classList.remove("hidden");}
  function message(text,kind=""){const el=byId("authMessage");if(!el)return;el.textContent=text||"";el.dataset.kind=kind;}
  async function boot(){
    show("loader");
    try{const session=await api().session();if(!session?.authenticated){show("authView");showAuthStep("loginForm");renderTurnstile();return;}await enter(session);}
    catch(error){show("authView");showAuthStep("loginForm");renderTurnstile();if(error?.code!=="unauthenticated")message("The secure API is not reachable yet. Check the Worker configuration.","error");}
  }
  async function enter(session){
    const data=await api().bootstrap();
    byId("userName").textContent=session.user?.displayName||session.user?.email||"User";
    byId("userRole").textContent=session.membership?.roleLabel||session.membership?.role||"Member";
    byId("tenantName").textContent=data.tenant?.name||"Edusentia Enterprise";
    const cards=[["Students",data.metrics?.students??0],["Staff",data.metrics?.staff??0],["Classes",data.metrics?.classes??0],["Subjects",data.metrics?.subjects??0],["Attendance",data.metrics?.attendanceToday??0],["Pending reports",data.metrics?.pendingReports??0]];
    byId("dashboardCards").innerHTML=cards.map(([k,v])=>`<article class="metric-card"><span>${escapeHtml(k)}</span><strong>${escapeHtml(v)}</strong></article>`).join("");
    show("appShell");
  }
  function beginMfa(result){
    mfaChallenge=String(result.challengeToken||"");showAuthStep("mfaPanel");
    const enrolling=result.mode==="enroll";
    byId("mfaTitle").textContent=enrolling?"Set up two-step verification":"Two-step verification";
    byId("mfaHelp").textContent=enrolling?"Your administrator account requires MFA. Add the setup key to your authenticator app, then enter the current six-digit code.":"Enter the current six-digit code from your authenticator app, or a saved recovery code.";
    byId("mfaSetup").classList.toggle("hidden",!enrolling);byId("mfaSecret").textContent=enrolling?String(result.setup?.secret||""):"";
    byId("mfaCode").value="";byId("mfaCode").focus();
  }
  byId("loginForm")?.addEventListener("submit",async event=>{
    event.preventDefault();message("");const fd=new FormData(event.currentTarget),button=event.currentTarget.querySelector('button[type="submit"]');
    if(turnstileSiteKey&&!turnstileToken){message("Complete the human verification before signing in.","error");renderTurnstile();return;}
    button.disabled=true;
    try{const result=await api().login(fd.get("email"),fd.get("password"),fd.get("tenantCode"),turnstileToken);turnstileToken="";if(result?.mfaRequired){beginMfa(result);return;}await enter(result);}
    catch(error){message(error.message||"Sign-in failed","error");resetTurnstile();}
    finally{button.disabled=false;}
  });
  byId("mfaForm")?.addEventListener("submit",async event=>{
    event.preventDefault();message("");const button=event.currentTarget.querySelector('button[type="submit"]'),code=String(byId("mfaCode").value||"").trim();button.disabled=true;
    try{const result=await api().completeMfa(mfaChallenge,code);mfaChallenge="";if(Array.isArray(result.recoveryCodes)&&result.recoveryCodes.length){pendingSession=result;byId("recoveryCodes").textContent=result.recoveryCodes.join("\n");showAuthStep("recoveryPanel");}else await enter(result);}
    catch(error){message(error.message||"Verification failed","error");byId("mfaCode").select();}
    finally{button.disabled=false;}
  });
  byId("mfaBack")?.addEventListener("click",()=>{mfaChallenge="";showAuthStep("loginForm");resetTurnstile();renderTurnstile();message("");});
  byId("recoveryContinue")?.addEventListener("click",async()=>{if(!pendingSession)return;const s=pendingSession;pendingSession=null;byId("recoveryCodes").textContent="";await enter(s);});
  byId("logoutButton")?.addEventListener("click",async()=>{try{await api().logout();}finally{location.reload();}});
  if('serviceWorker'in navigator)window.addEventListener('load',()=>navigator.serviceWorker.register('./service-worker.js').catch(()=>{}),{once:true});
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot,{once:true});else boot();
})();