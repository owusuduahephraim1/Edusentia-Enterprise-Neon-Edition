(() => {
  "use strict";
  const SELECTOR='[data-backup-download]';
  const busy=new WeakSet();
  function config(){return window.RCE_CONFIG||window.NIS_CONFIG||{}}
  function tenantClient(){return window.EDS_TENANT_AUTH_CLIENT||window.EdusentiaCompatClient||null}
  function notice(title,message,type="success"){
    if(typeof window.EdusentiaNotify==="function"){window.EdusentiaNotify(title,message,type);return}
    const stack=document.getElementById("toastStack");if(!stack)return;
    const item=document.createElement("div");item.className=`toast ${type}`;item.innerHTML=`<strong></strong><span></span>`;item.querySelector("strong").textContent=title;item.querySelector("span").textContent=message;stack.appendChild(item);setTimeout(()=>item.remove(),type==="error"?10000:6500);
  }
  async function requireAal2(client){const {data,error}=await client.auth.mfa.getAuthenticatorAssuranceLevel();if(error)throw error;if(data?.currentLevel!=="aal2")throw new Error("Multi-factor authentication is required to download an encrypted school backup.")}
  async function gateway(client,backupId){const {data,error}=await client.functions.invoke("backup-download-gateway",{body:{backup_id:backupId}});if(error)throw error;if(!data?.ok)throw new Error(String(data?.error||"Backup download authorization failed").replaceAll("_"," "));return data}
  function safeName(value){return String(value||"backup").replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/^-+|-+$/g,"").slice(0,120)||"backup"}
  async function downloadPackage(button){
    if(busy.has(button))return;
    const backupId=String(button.dataset.backupDownload||"");if(!backupId)return;
    if(!window.JSZip){notice("Download unavailable","The ZIP packaging library did not load.","error");return}
    const confirmDownload=window.EdusentiaConfirm||window.EdusentiaShell?.confirmAction;if(typeof confirmDownload!=="function"){notice("Download unavailable","The secure confirmation dialog could not be opened.","error");return}if(!await confirmDownload("Only the encrypted backup payload is downloaded. Keep the backup encryption secret in a separate secure location.",{title:"Download encrypted school backup?",confirmLabel:"Download backup",kind:"primary"}))return;
    const client=tenantClient();if(!client){notice("Download unavailable","Tenant authentication service is unavailable.","error");return}
    busy.add(button);const previous=button.textContent;button.disabled=true;button.textContent="Authorizing…";
    try{
      await requireAal2(client);
      const data=await gateway(client,backupId),files=Array.isArray(data.files)?data.files:[];
      if(!files.length)throw new Error("The backup package inventory is empty.");
      const zip=new window.JSZip();
      for(let i=0;i<files.length;i++){
        const file=files[i],relative=String(file.relative_path||"");
        if(!relative||relative.includes("..")||relative.startsWith("/")||!/^https:\/\//i.test(String(file.url||"")))throw new Error("The protected backup inventory is invalid.");
        button.textContent=`Packaging ${i+1}/${files.length}`;
        const response=await fetch(file.url,{method:"GET",cache:"no-store",redirect:"error"});
        if(!response.ok)throw new Error(`Backup object download failed (${response.status}).`);
        zip.file(relative,await response.arrayBuffer(),{binary:true});
      }
      zip.file("RESTORE_README.txt",[
        "Edusentia Enterprise encrypted school backup",
        `Backup key: ${String(data.backup_key||"")}`,
        `Created: ${String(data.created_at||"")}`,
        `Verification status at download: ${String(data.verification_status||"unknown")}`,
        "",
        "This ZIP contains AES-256-GCM encrypted database and protected-file payloads.",
        "Store this ZIP separately from the backup encryption secret.",
        "Use Backup & Restore in a compatible licensed tenant workspace to perform a protected restore.",
        "Authentication password hashes are not contained in the supported backup export."
      ].join("\n"));
      button.textContent="Finalizing…";
      const blob=await zip.generateAsync({type:"blob",compression:"STORE"});
      const url=URL.createObjectURL(blob),anchor=document.createElement("a"),tenant=safeName(config().tenantCode||config().schoolShortName||"school");
      anchor.href=url;anchor.download=`${tenant}-encrypted-backup-${safeName(data.backup_key)}.zip`;document.body.appendChild(anchor);anchor.click();anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),2000);
      notice("Encrypted backup package ready",`${files.length} protected backup objects were authorized through ${data.storage_provider==="cloudflare-r2"?"Cloudflare R2":"private storage"}. Confirm an off-site copy only after storing the ZIP in a separate protected location.`);
    }catch(error){notice("Backup download unsuccessful",String(error?.message||error).replaceAll("_"," "),"error")}
    finally{busy.delete(button);button.disabled=false;button.textContent=previous}
  }
  document.addEventListener("click",event=>{const target=event.target instanceof Element?event.target.closest(SELECTOR):null;if(!target)return;event.preventDefault();event.stopPropagation();event.stopImmediatePropagation();void downloadPackage(target)},{capture:true});
})();
