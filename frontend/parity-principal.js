(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  // ---------- Principal: certified record hydration + protected photograph parity ----------
  const principalPhotoUrls=new Map();
  function principalInitials(row={}){
    const name=String(row.full_name||[row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" ")||"Principal").trim();
    const words=name.split(/\s+/).filter(Boolean);
    return esc(((words[0]?.[0]||"P")+(words.length>1?(words.at(-1)?.[0]||""):"")).toUpperCase());
  }
  function principalAvatarHtml(row={}){
    const initials=principalInitials(row);
    return row.photo_url
      ?`<span class="staff-avatar-photo"><img data-principal-photo="${esc(row.photo_url)}" data-principal-id="${esc(row.id||"")}" alt="Principal photograph"><span>${initials}</span></span>`
      :`<span class="avatar">${initials}</span>`;
  }
  async function principalPhotoUrl(principalId,photoPath){
    const id=String(principalId||"").trim(),path=String(photoPath||"").trim();if(!id||!path)return "";
    const cacheKey=id+"|"+path;if(principalPhotoUrls.has(cacheKey))return principalPhotoUrls.get(cacheKey);
    const blob=await api().downloadPrincipalPhoto(id,path);
    const url=URL.createObjectURL(blob);principalPhotoUrls.set(cacheKey,url);return url;
  }
  async function hydratePrincipalPhotos(root=document){
    const images=[...root.querySelectorAll("[data-principal-photo]")];
    await Promise.all(images.map(async img=>{
      const id=img.dataset.principalId,path=img.dataset.principalPhoto;if(!id||!path)return;
      try{img.src=await principalPhotoUrl(id,path);img.onload=()=>img.parentElement?.classList.add("loaded");}
      catch(error){console.warn("principal_photo_display_failed",error);}
    }));
  }
  async function renderPrincipal(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>Principal</h3><p>Certified Principal record, account link and photograph.</p></div><div class="page-actions"><button id="principalAdvancedAdd" class="button primary" type="button">Add Principal</button></div></div><section class="panel"><div class="toolbar"><label class="search"><input id="principalAdvancedSearch" type="search" placeholder="Search name, staff no. or contact"></label><select id="principalAdvancedArchive"><option value="active">Current</option><option value="archived">Archived</option><option value="all">All</option></select><button id="principalAdvancedSearchButton" class="button secondary" type="button">Search</button></div><div id="principalAdvancedResults">${loading("Loading Principal records")}</div></section>`;
    byId("principalAdvancedAdd").onclick=()=>openPrincipalEditor();
    byId("principalAdvancedSearchButton").onclick=loadAdvancedPrincipals;byId("principalAdvancedArchive").onchange=loadAdvancedPrincipals;
    await loadAdvancedPrincipals();
  }
  async function loadAdvancedPrincipals(){
    const box=byId("principalAdvancedResults");if(!box)return;box.innerHTML=loading("Loading Principal records");
    try{
      const data=await certified("list_headteachers",{search_text:byId("principalAdvancedSearch")?.value?.trim()||"",status_filter:"",archive_filter:byId("principalAdvancedArchive")?.value||"active",page_number:1,page_size:100});
      const rows=Array.isArray(data?.rows)?data.rows:[];
      if(!rows.length){box.innerHTML=empty("No Principal records match the current filter.");return;}
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Principal</th><th>Staff no.</th><th>Contact</th><th>Account</th><th>Signature</th><th>Actions</th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main">${principalAvatarHtml(row)}<span class="cell-copy"><strong>${esc(row.full_name||"Principal")}</strong><small>${esc(row.profile_email||"No linked account")}</small></span></div></td><td>${esc(row.staff_no||"—")}</td><td>${esc(row.phone||"—")}</td><td>${esc(row.profile_role||"—")}</td><td>${row.signature_path?status("uploaded"):status("not uploaded")}</td><td><div class="table-actions">${row.deleted_at?`<button class="button success small" data-principal-restore="${esc(row.id)}">Restore</button>`:`<button class="button secondary small" data-principal-edit="${esc(row.id)}">Edit</button><button class="button danger small" data-principal-archive="${esc(row.id)}">Remove</button>`}</div></td></tr>`).join("")}</tbody></table></div>`;
      await hydratePrincipalPhotos(box);
      box.querySelectorAll("[data-principal-edit]").forEach(b=>b.onclick=()=>openPrincipalEditor(b.dataset.principalEdit));
      box.querySelectorAll("[data-principal-archive]").forEach(b=>b.onclick=()=>archivePrincipal(b.dataset.principalArchive));
      box.querySelectorAll("[data-principal-restore]").forEach(b=>b.onclick=()=>restorePrincipal(b.dataset.principalRestore));
    }catch(error){box.innerHTML=pageError(error);}
  }
  async function openPrincipalEditor(id=""){
    let row={};
    if(id){
      const data=await certified("get_headteacher_record",{target_headteacher_id:id});
      row=data?.principal||data?.headteacher||data||{};
    }else{
      try{row.staff_no=await certified("generate_school_identifier",{identifier_kind:"principal"});}catch(_){row.staff_no="";}
    }
    let photoUrl="";
    if(row.id&&row.photo_url){try{photoUrl=await principalPhotoUrl(row.id,row.photo_url);}catch(_){}}
    const initials=principalInitials(row);
    openModal(id?"Edit Principal":"Add Principal","Single-current-Principal protection remains enforced by the certified database.",`
      <form id="principalAdvancedForm" class="form-stack">
        <input type="hidden" name="id" value="${esc(row.id||"")}">
        <input type="hidden" name="updated_at" value="${esc(row.updated_at||"")}">
        <input type="hidden" name="profile_id" value="${esc(row.profile_id||"")}">
        <input type="hidden" name="staff_no" value="${esc(row.staff_no||"")}">
        <div class="staff-photo-editor">${photoUrl?`<img id="principalPhotoPreview" src="${esc(photoUrl)}" alt="Principal photograph">`:`<span id="principalPhotoPreview">${initials}</span>`}<label class="field"><span>Principal photograph</span><input id="principalPhotoAdvanced" type="file" accept="image/jpeg,image/png,image/webp"><small>JPEG, PNG or WebP. The photograph is stored privately in the school’s dedicated R2 space.</small></label></div>
        <div class="form-grid">
          <label class="field"><span>Full name</span><input name="full_name" value="${esc(row.full_name||[row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" "))}" required></label>
          <label class="field"><span>Contact phone</span><input name="contact" value="${esc(row.phone||row.contact||"")}" required></label>
        </div>
        <p id="principalAdvancedMessage" class="form-message hidden" role="alert"></p>
      </form>`,
      '<button id="principalAdvancedCancel" class="button ghost" type="button">Cancel</button><button id="principalAdvancedSave" class="button primary" type="submit" form="principalAdvancedForm">Save Principal</button>');
    let localPhotoPreview="";
    byId("principalPhotoAdvanced").onchange=e=>{
      const file=e.target.files?.[0];if(!file)return;
      if(!["image/jpeg","image/png","image/webp"].includes(String(file.type||"").toLowerCase())){showMessage("principalAdvancedMessage","Principal photographs must be JPEG, PNG or WebP images.");e.target.value="";return;}
      if(file.size>8*1024*1024){showMessage("principalAdvancedMessage","Principal photographs must be 8 MB or smaller.");e.target.value="";return;}
      if(localPhotoPreview)URL.revokeObjectURL(localPhotoPreview);localPhotoPreview=URL.createObjectURL(file);
      const current=byId("principalPhotoPreview"),next=document.createElement("img");next.id="principalPhotoPreview";next.alt="Principal photograph";next.src=localPhotoPreview;current?.replaceWith(next);
    };
    byId("principalAdvancedCancel").onclick=()=>{if(localPhotoPreview)URL.revokeObjectURL(localPhotoPreview);closeModal();};
    byId("principalAdvancedForm").onsubmit=async e=>{
      e.preventDefault();const button=byId("principalAdvancedSave");button.disabled=true;
      try{
        const payload=formValues(e.currentTarget);payload.reason=id?"Principal record updated":"Principal record created";
        let saved=await certified("save_headteacher",{payload}),record=saved?.principal||saved?.headteacher||saved;
        const file=byId("principalPhotoAdvanced")?.files?.[0];
        if(file){
          const principalId=record?.id||row.id;if(!principalId)throw new Error("The Principal photograph owner could not be verified.");
          const uploaded=await api().uploadFile(file,"principal-photos",{subfolder:principalId});
          const photoPath=String(uploaded.referencePath||String(uploaded.objectKey||"").split("/staff-photos/")[1]||"").trim();
          if(!photoPath||!photoPath.startsWith(principalId+"/"))throw new Error("The Principal photograph path could not be verified.");
          saved=await certified("set_headteacher_photo",{target_headteacher_id:principalId,target_photo_url:photoPath,expected_updated_at:record?.updated_at||null});
        }
        if(localPhotoPreview){URL.revokeObjectURL(localPhotoPreview);localPhotoPreview="";}
        closeModal();await loadAdvancedPrincipals();
      }catch(error){showMessage("principalAdvancedMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }
  async function archivePrincipal(id){if(!await window.EdusentiaConfirm("Remove this Principal record?"))return;try{const removed=await certified("archive_headteacher",{target_headteacher_id:id,reason_text:"Principal removed from active records"});if(removed!==true)throw new Error("The remove operation did not complete.");await loadAdvancedPrincipals();}catch(error){alert(friendly(error));}}
  async function restorePrincipal(id){try{const restored=await certified("restore_headteacher",{target_headteacher_id:id,reason_text:"Principal restored to active records"});if(restored!==true)throw new Error("The restore operation did not complete.");await loadAdvancedPrincipals();}catch(error){alert(friendly(error));}}

  async function renderMySignature(){
    byId("content").innerHTML=`<div class="page-head"><div><h3>My Principal Signature</h3><p>Manage the authenticated Principal signature used by protected report workflows.</p></div></div>${loading("Loading signature state")}`;
    try{
      const data=await certified("get_my_headteacher_signature");
      byId("content").innerHTML=`<div class="page-head"><div><h3>My Principal Signature</h3><p>Manage the authenticated Principal signature used by protected report workflows.</p></div></div>
        <section class="panel pad"><div class="detail-grid"><div><span>Linked Principal record</span><strong>${esc(data?.full_name||"Not linked")}</strong></div><div><span>Signature</span><strong>${data?.signature_path?"Configured":"Not configured"}</strong></div><div><span>Last updated</span><strong>${formatDateTime(data?.signature_updated_at)}</strong></div></div>
        <form id="signatureUploadForm" class="form-stack"><label class="field"><span>Signature image</span><input id="signatureUploadFile" type="file" accept="image/jpeg,image/png,image/webp" required></label><p id="signatureMessage" class="form-message hidden" role="alert"></p><button class="button primary" type="submit">Upload signature</button></form></section>`;
      byId("signatureUploadForm").onsubmit=async e=>{e.preventDefault();const file=byId("signatureUploadFile").files?.[0],button=e.currentTarget.querySelector("button");if(!file)return;button.disabled=true;try{const uploaded=await api().uploadFile(file,"principal-signatures");await certified("set_my_headteacher_signature",{target_signature_path:uploaded.objectKey,expected_updated_at:data?.updated_at||null});await renderMySignature();}catch(error){showMessage("signatureMessage",friendly(error));}finally{button.disabled=false;}};
    }catch(error){byId("content").innerHTML=pageError(error);}
  }

  registerView({id:"headteachers",label:"Principals",icon:"★",subtitle:"Principal records and appointments",permission:"manage_headteachers",render:renderPrincipal});
  registerView({id:"principal-signature",label:"My Signature",icon:"✎",subtitle:"Principal signing identity for reports",roles:["principal"],render:renderMySignature});
})();