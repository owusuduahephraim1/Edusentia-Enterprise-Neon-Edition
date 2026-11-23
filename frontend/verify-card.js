(() => {
  "use strict";
  const byId=id=>document.getElementById(id);
  const fields=byId("verificationFields"),container=byId("verificationDetails"),
    badge=byId("verificationState"),icon=byId("verificationIcon"),
    label=byId("verificationLabel"),detail=byId("verificationDetail"),
    retry=byId("verificationRetry");
  const params=new URLSearchParams(location.search);
  const staff=params.get("staffcard"),student=params.get("idcard");
  const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  function show(kind,title,message,symbol){
    badge.className="state state-"+kind;
    label.textContent=title;
    detail.textContent=message;
    icon.textContent=symbol;
  }
  function appendField(title,value){
    const text=String(value==null?"":value).trim();
    if(!text)return;
    const holder=document.createElement("div"),dt=document.createElement("dt"),dd=document.createElement("dd");
    dt.textContent=title;dd.textContent=text;holder.append(dt,dd);fields.appendChild(holder);
  }
  function formatDate(value){
    const valueString=String(value||"").slice(0,10),time=Date.parse(valueString+"T00:00:00Z");
    return Number.isFinite(time)?new Intl.DateTimeFormat(undefined,{dateStyle:"medium",timeZone:"UTC"}).format(new Date(time)):"";
  }

  async function verify(){
    container.hidden=true;retry.hidden=true;fields.replaceChildren();
    if(Boolean(staff)===Boolean(student)||!UUID.test(String(staff||student||""))){
      show("invalid","Invalid verification link","The card QR code is incomplete or malformed. Ask the school for a valid card.", "×");
      return;
    }
    show("loading","Checking card authenticity","Contacting the secure Edusentia verification service.","◷");
    const school=String(params.get("school")||"").trim();
    if(school&&!/^[A-Z]{3}-\d{6}$/i.test(school)){
      show("invalid","Invalid verification link","The issuing school code is not valid.","×");
      return;
    }
    const url=new URL("/api/public/id-card-verification",
      String(window.EDS_MASTER_CONFIG?.apiBaseUrl||"https://edusentia-enterprise-neon-api.edusentia-enterprise-neon.workers.dev"));
    url.searchParams.set(staff?"staffcard":"idcard",staff||student);
    if(school)url.searchParams.set("school",school.toUpperCase());
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(),16000);
    try{
      const response=await fetch(url.toString(),{method:"GET",credentials:"omit",cache:"no-store",
        headers:{accept:"application/json"},signal:controller.signal});
      const body=await response.json().catch(()=>({}));
      if(!response.ok)throw new Error(String(body?.error?.message||"The verification service is unavailable."));
      const v=body.verification||{},status=String(v.status||"not_found");
      if(!v.found){
        show("invalid","ID card not verified","No issued card matches this verification reference.","×");
        return;
      }
      const titles={
        active:["valid","Valid "+(staff?"staff":"student")+" ID card","This card is currently recognized as valid by the issuing school.","✓"],
        expired:["warning","ID card expired","The card has passed its authorized expiry date.","!"],
        revoked:["invalid","ID card revoked","The issuing school has revoked this card. It is no longer valid.","×"],
        replaced:["warning","ID card replaced","This card has been replaced by a later issue. It is no longer valid.","!"],
        permanently_removed:["invalid","ID card permanently removed","The issuing school has permanently removed this card's issuance record.","×"]
      };
      const result=titles[status]||["invalid","ID card not verified","The card cannot be verified as currently valid.","×"];
      if(status==="active"&&!v.valid){
        show("invalid","ID card not verified","The card is not currently valid.","×");
      }else show(result[0],result[1],result[2],result[3]);
      byId("verificationSchool").textContent=String(v.school_name||"Issuing school");
      appendField("Card number",v.card_number);
      appendField(staff?"Staff name":"Student name",v.name);
      appendField(staff?"Staff number":"Admission number",v.identifier);
      appendField(staff?"Role":"Class",staff?v.role:v.class_name);
      appendField("Academic year",v.academic_year);
      appendField("Issued on",formatDate(v.issue_date));
      appendField("Expires on",formatDate(v.expires_on));
      if(v.revision)appendField("Card revision","R"+v.revision);
      appendField("Replacement card",v.replacement_card_number);
      container.hidden=false;
    }catch(error){
      show("warning","Verification temporarily unavailable",
        error?.name==="AbortError"?"The verification request timed out. Please try again.":String(error?.message||"Please check your connection and try again."),"!");
      retry.hidden=false;
    }finally{clearTimeout(timeout);}
  }
  retry.addEventListener("click",verify);
  verify();
})();
