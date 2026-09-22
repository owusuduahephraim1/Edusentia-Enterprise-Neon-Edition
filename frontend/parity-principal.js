(() => {
  "use strict";
  const P=window.EdusentiaParity;if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig}=P;
  // ---------- Principal ----------
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
      box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>Principal</th><th>Staff no.</th><th>Contact</th><th>Account</th><th>Signature</th><th>Actions</th></tr></thead><tbody>${rows.map(row=>`<tr><td><div class="cell-main"><span class="avatar">${esc(String(row.full_name||"P").charAt(0))}</span><span class="cell-copy"><strong>${esc(row.full_name||"Principal")}</strong><small>${esc(row.profile_email||"No linked account")}</small></span></div></td><td>${esc(row.staff_no||"—")}</td><td>${esc(row.phone||"—")}</td><td>${esc(row.profile_role||"—")}</td><td>${row.signature_path?status("uploaded"):status("not uploaded")}</td><td><div class="table-actions">${row.deleted_at?`<button class="button success small" data-principal-restore="${esc(row.id)}">Restore</button>`:`<button class="button secondary small" data-principal-edit="${esc(row.id)}">Edit</button><button class="button danger small" data-principal-archive="${esc(row.id)}">Remove</button>`}</div></td></tr>`).join("")}</tbody></table></div>`;
      box.querySelectorAll("[data-principal-edit]").forEach(b=>b.onclick=()=>openPrincipalEditor(b.dataset.principalEdit));
      box.querySelectorAll("[data-principal-archive]").forEach(b=>b.onclick=()=>archivePrincipal(b.dataset.principalArchive));
      box.querySelectorAll("[data-principal-restore]").forEach(b=>b.onclick=()=>restorePrincipal(b.dataset.principalRestore));
    }catch(error){box.innerHTML=pageError(error);}
  }
  async function openPrincipalEditor(id=""){
    let row={};
    if(id){
      const data=await certified("get_headteacher_record",{target_headteacher_id:id});row=data?.headteacher||data||{};
    }else{
      try{row.staff_no=await certified("generate_school_identifier",{identifier_kind:"principal"});}catch(_){row.staff_no="";}
    }
    openModal(id?"Edit Principal":"Add Principal","Single-current-Principal protection remains enforced by the certified database.",`
      <form id="principalAdvancedForm" class="form-stack"><input type="hidden" name="id" value="${esc(row.id||"")}"><input type="hidden" name="updated_at" value="${esc(row.updated_at||"")}"><input type="hidden" name="staff_no" value="${esc(row.staff_no||"")}"><div class="form-grid">
        <label class="field"><span>Full name</span><input name="full_name" value="${esc(row.full_name||[row.first_name,row.middle_name,row.last_name].filter(Boolean).join(" "))}" required></label>
        <label class="field"><span>Contact phone</span><input name="contact" value="${esc(row.phone||row.contact||"")}" required></label>
        <label class="field full"><span>Photograph</span><input id="principalPhotoAdvanced" type="file" accept="image/jpeg,image/png,image/webp"></label>
      </div><p id="principalAdvancedMessage" class="form-message hidden" role="alert"></p></form>`,
      '<button id="principalAdvancedCancel" class="button ghost" type="button">Cancel</button><button id="principalAdvancedSave" class="button primary" type="submit" form="principalAdvancedForm">Save Principal</button>');
    byId("principalAdvancedCancel").onclick=closeModal;
    byId("principalAdvancedForm").onsubmit=async e=>{
      e.preventDefault();const button=byId("principalAdvancedSave");button.disabled=true;
      try{
        const payload=formValues(e.currentTarget);payload.reason=id?"Principal record updated from Neon testing workspace":"Principal record created from Neon testing workspace";
        let saved=await certified("save_headteacher",{payload}),record=saved?.headteacher||saved;
        const file=byId("principalPhotoAdvanced")?.files?.[0];
        if(file){const uploaded=await api().uploadFile(file,"staff-photos");await certified("set_headteacher_photo",{target_headteacher_id:record.id,target_photo_url:uploaded.objectKey,expected_updated_at:record.updated_at||null});}
        closeModal();await loadAdvancedPrincipals();
      }catch(error){showMessage("principalAdvancedMessage",friendly(error));}
      finally{button.disabled=false;}
    };
  }
  async function archivePrincipal(id){if(!confirm("Remove this Principal record?"))return;try{await certified("archive_headteacher",{target_headteacher_id:id,reason_text:"Principal removed from active records"});await loadAdvancedPrincipals();}catch(error){alert(friendly(error));}}
  async function restorePrincipal(id){try{await certified("restore_headteacher",{target_headteacher_id:id,reason_text:"Principal restored to active records"});await loadAdvancedPrincipals();}catch(error){alert(friendly(error));}}

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
