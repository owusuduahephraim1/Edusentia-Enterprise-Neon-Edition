(() => {
"use strict";
const cfg=window.EDS_MASTER_CONFIG||{},base=String(cfg.apiBaseUrl||"").replace(/\/+$/,"");
const params=new URLSearchParams(location.search),token=String(params.get("token")||"").trim();
let turnstileToken="",widget=null,setup=null;
history.replaceState(null,"",location.pathname);
const byId=id=>document.getElementById(id),msg=(text,kind="")=>{const el=byId("setupMessage");el.textContent=text||"";el.dataset.kind=kind;};
async function post(path,body){const r=await fetch(base+path,{method:"POST",credentials:"include",headers:{"content-type":"application/json"},body:JSON.stringify(body)}),p=await r.json().catch(()=>({}));if(!r.ok)throw new Error(p?.error?.message||("Request failed ("+r.status+")"));return p;}
window.onAdminSetupTurnstileLoad=()=>{if(!cfg.turnstileSiteKey||widget!==null)return;widget=window.turnstile.render("#setupTurnstile",{sitekey:cfg.turnstileSiteKey,action:"admin_setup",theme:"auto",size:"flexible",callback:t=>{turnstileToken=String(t||"");msg("");},"expired-callback":()=>{turnstileToken="";msg("Verification expired. Please verify again.","error");}});};
async function inspect(){
  if(!token){byId("setupIntro").textContent="This administrator setup link is invalid.";return;}
  try{const r=await post("/api/public/admin-setup/inspect",{token});setup=r.setup;byId("setupIntro").textContent="Create the initial password for this school administrator account.";byId("setupSchool").textContent=setup.schoolName||"School administrator";byId("setupTenant").textContent=setup.tenantCode||"";byId("setupEmail").textContent=setup.adminEmail||"";byId("setupDetails").classList.remove("hidden");}
  catch(e){byId("setupIntro").textContent="This administrator setup link is invalid or has expired.";msg(e.message||"The setup link cannot be used.","error");}
}
byId("setupForm").addEventListener("submit",async e=>{e.preventDefault();msg("");const password=byId("setupPassword").value,confirm=byId("setupConfirm").value;if(password.length<12){msg("Use a password of at least 12 characters.","error");return;}if(password!==confirm){msg("The passwords do not match.","error");return;}if(!turnstileToken){msg("Complete the human verification before continuing.","error");return;}const button=e.currentTarget.querySelector('button[type="submit"]');button.disabled=true;try{const r=await post("/api/public/admin-setup/complete",{token,password,turnstileToken});byId("setupDetails").classList.add("hidden");byId("setupSuccess").classList.remove("hidden");const tenantCode=r.tenant_code||setup?.tenantCode||"",adminEmail=r.admin_email||setup?.adminEmail||"";byId("successTenant").value=tenantCode;byId("successEmail").value=adminEmail;const continueLink=byId("continueSchoolSignIn");if(continueLink)continueLink.href=`./index.html?school=${encodeURIComponent(tenantCode)}&email=${encodeURIComponent(adminEmail)}`;msg("Password created successfully.","success");}catch(err){msg(err.message||"Administrator setup failed.","error");turnstileToken="";if(window.turnstile&&widget!==null)window.turnstile.reset(widget);}finally{button.disabled=false;}});
inspect();
})();