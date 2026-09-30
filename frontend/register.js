(() => {
"use strict";
const cfg=window.EDS_MASTER_CONFIG||{},base=String(cfg.apiBaseUrl||"").replace(/\/+$/,"");
let token="",widget=null;
const msg=(t,k="")=>{const e=document.getElementById("registrationMessage");e.textContent=t;e.dataset.kind=k;};
const alertBox=()=>document.getElementById("registrationAlertActions");
function normalizePhone(value){return String(value||"").replace(/[^0-9]/g,"");}
function registrationAlertMessage(body,registration){
  const id=String(registration?.id||"").trim();
  const contact=[body.contactName,body.contactEmail,body.contactPhone].map(v=>String(v||"").trim()).filter(Boolean).join(" · ");
  return `Hello Edusentia Platform Super Administrator, I have successfully submitted a new school registration for ${String(body.schoolName||"").trim()}.${id?` Registration ID: ${id}.`:""}${contact?` Contact: ${contact}.`:""} Please review the registration for onboarding. Thank you.`;
}
function showRegistrationAlerts(body,registration){
  const box=alertBox();if(!box)return;
  const e164=normalizePhone(cfg.platformAdminPhoneE164||cfg.platformAdminPhoneDisplay);
  if(!e164){box.hidden=true;box.innerHTML="";return;}
  const message=registrationAlertMessage(body,registration);
  const smsPhone=String(cfg.platformAdminPhoneDisplay||("+"+e164)).replace(/\s+/g,"");
  box.innerHTML=`<div class="pa-info success"><strong>Registration received</strong><span>You can optionally alert the Platform Super Administrator now. Edusentia prepares the message, then WhatsApp or your SMS app performs the actual send.</span></div><div class="pa-actions"><a class="pa-btn secondary" href="https://wa.me/${encodeURIComponent(e164)}?text=${encodeURIComponent(message)}" target="_blank" rel="noopener noreferrer">Open WhatsApp</a><a class="pa-btn ghost" href="sms:${smsPhone}?body=${encodeURIComponent(message)}">Open SMS</a></div>`;
  box.hidden=false;
}
window.onRegistrationTurnstileLoad=()=>{
  widget=window.turnstile.render("#registrationTurnstile",{sitekey:cfg.turnstileSiteKey,action:"school_registration",theme:"auto",size:"flexible",callback:t=>{token=String(t||"");msg("");},"expired-callback":()=>{token="";msg("Verification expired.","error");}});
};
document.getElementById("registrationForm").addEventListener("submit",async e=>{
  e.preventDefault();msg("");const box=alertBox();if(box){box.hidden=true;box.innerHTML="";}
  if(!token){msg("Complete the human verification before submitting.","error");return;}
  const b=e.currentTarget.querySelector('button[type="submit"]');b.disabled=true;
  try{
    const f=new FormData(e.currentTarget),body={schoolName:f.get("schoolName"),institutionType:f.get("institutionType"),contactName:f.get("contactName"),contactEmail:f.get("contactEmail"),contactPhone:f.get("contactPhone"),country:f.get("country"),turnstileToken:token};
    const r=await fetch(base+"/api/public/school-registration",{method:"POST",credentials:"include",headers:{"content-type":"application/json"},body:JSON.stringify(body)}),p=await r.json().catch(()=>({}));
    if(!r.ok)throw new Error(p?.error?.message||"Registration could not be submitted");
    showRegistrationAlerts(body,p?.registration||{});
    e.currentTarget.reset();
    msg("Registration submitted successfully. The Platform Super Administrator will review it before onboarding.","success");
    token="";if(window.turnstile&&widget!==null)window.turnstile.reset(widget);
  }catch(err){
    msg(err.message||"Registration failed","error");
    if(window.turnstile&&widget!==null)window.turnstile.reset(widget);token="";
  }finally{b.disabled=false;}
});
})();