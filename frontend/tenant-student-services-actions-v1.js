(()=>{
  "use strict";
  if(window.EDS_STUDENT_SERVICES_ACTIONS_V1)return;
  window.EDS_STUDENT_SERVICES_ACTIONS_V1=true;

  const BUILD="r43-student-services-enrollment-reversal-v1";
  const STATE={client:null,clientUrl:"",clientKey:"",session:null,sessionAt:0,navQueued:false,contentQueued:false};
  const decorating=new WeakSet();
  const $=id=>document.getElementById(id);
  const esc=value=>String(value??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const messageOf=value=>String(value?.message||value||"Request failed").replaceAll("_"," ");

  function client(){
    if(STATE.client)return STATE.client;
    STATE.session=null;STATE.sessionAt=0;
    STATE.client=window.EdusentiaCompatClient||null;
    return STATE.client;
  }

  async function rpc(name,args={}){
    const c=client();
    if(!c)throw new Error("Student Services unavailable");
    const {data,error}=await c.rpc(name,args);
    if(error)throw error;
    return data;
  }

  async function session(force=false){
    client();
    if(!force&&STATE.session&&Date.now()-STATE.sessionAt<60000)return STATE.session;
    const data=await rpc("student_services_session");
    STATE.session=data||{};
    STATE.sessionAt=Date.now();
    return STATE.session;
  }

  function toast(title,detail="",kind="info"){
    const stack=$("toastStack");
    if(!stack){
      if(typeof window.EdusentiaNotify==="function")window.EdusentiaNotify(title,detail,kind);
      else console[kind==="error"?"error":"log"](title,detail);
      return;
    }
    const node=document.createElement("div");
    node.className=`toast ${kind}`;
    node.innerHTML=`<strong>${esc(title)}</strong>${detail?`<span>${esc(detail)}</span>`:""}`;
    stack.appendChild(node);
    setTimeout(()=>node.remove(),4600);
  }

  function ensureCss(){
    if($("ssApplicantActionsCss"))return;
    const style=document.createElement("style");
    style.id="ssApplicantActionsCss";
    style.textContent=`
      .ss-applicant-actions-note{font-size:12px;opacity:.72;margin:6px 0 0}
      .ss-action-danger{border-color:#b42318!important;color:#b42318!important}
      .ss-action-danger-strong{background:#b42318!important;border-color:#b42318!important;color:#fff!important}
      .ss-status-action{background:transparent;cursor:pointer;font:inherit;line-height:inherit}
      .ss-status-action:hover,.ss-status-action:focus-visible{box-shadow:0 0 0 2px color-mix(in srgb,currentColor 20%,transparent)}
      .ss-applicant-edit{border:0;border-radius:14px;max-width:860px;width:min(94vw,860px);padding:0;box-shadow:0 24px 70px #0005}
      .ss-applicant-edit::backdrop{background:#0006}
      .ss-applicant-edit-frame{padding:18px;display:grid;gap:14px}
      .ss-applicant-edit-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}
      .ss-applicant-edit-head h3{margin:0}.ss-applicant-edit-head p{margin:4px 0 0;opacity:.7}
      .ss-applicant-edit-form{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
      .ss-applicant-edit-form label{display:grid;gap:4px}.ss-applicant-edit-form .full{grid-column:1/-1}
      .ss-applicant-edit-form input,.ss-applicant-edit-form select,.ss-applicant-edit-form textarea{width:100%;padding:9px;border:1px solid var(--line,#d8dde6);border-radius:8px;background:var(--surface,#fff);color:inherit}
      .ss-applicant-edit-actions{display:flex;justify-content:flex-end;gap:8px;grid-column:1/-1;margin-top:4px}
      @media(max-width:700px){.ss-applicant-edit-form{grid-template-columns:1fr}.ss-applicant-edit-form .full{grid-column:auto}}
    `;
    document.head.appendChild(style);
  }

  function moveAfter(node,anchor){
    if(!node||!anchor||node===anchor||anchor.nextElementSibling===node)return false;
    anchor.parentElement?.insertBefore(node,anchor.nextElementSibling);
    return true;
  }

  function ensureNavigationOrder(){
    STATE.navQueued=false;
    const nav=$("mainNav");
    if(!nav)return;
    const operations=nav.querySelector('[data-view="operations"]');
    const studentServices=$("studentServicesNav");
    if(operations&&studentServices&&studentServices.parentElement===nav)moveAfter(studentServices,operations);

    const licence=nav.querySelector('[data-view="license_capacity"]');
    const notifications=nav.querySelector('[data-view="notifications"]');
    if(licence&&notifications&&licence.parentElement===nav&&notifications.parentElement===nav)moveAfter(notifications,licence);
  }

  function queueNavigationOrder(){
    if(STATE.navQueued)return;
    STATE.navQueued=true;
    requestAnimationFrame(ensureNavigationOrder);
  }

  function optionRows(rows,labelKey,selected){
    const options=['<option value="">Select</option>'];
    for(const row of rows||[]){
      const id=String(row.id||"");
      options.push(`<option value="${esc(id)}" ${id===String(selected||"")?"selected":""}>${esc(row[labelKey]||id)}</option>`);
    }
    return options.join("");
  }

  function genderOptions(selected){
    return ["Male","Female","Other"].map(value=>`<option value="${value}" ${value===selected?"selected":""}>${value}</option>`).join("");
  }

  function editDialog(){
    let dialog=$("ssApplicantEditDialog");
    if(dialog)return dialog;
    ensureCss();
    dialog=document.createElement("dialog");
    dialog.id="ssApplicantEditDialog";
    dialog.className="ss-applicant-edit";
    document.body.appendChild(dialog);
    return dialog;
  }

  async function editApplicant(record){
    try{
      const [detail,ref]=await Promise.all([
        rpc("admissions_application_detail",{target_application_id:record.id}),
        rpc("admissions_reference_data")
      ]);
      const dialog=editDialog();
      dialog.innerHTML=`<div class="ss-applicant-edit-frame">
        <header class="ss-applicant-edit-head"><div><h3>Edit applicant</h3><p>${esc(detail.application_no)} · ${esc(record.applicant)}</p></div><button type="button" class="icon-button" data-close-applicant-edit>×</button></header>
        <form class="ss-applicant-edit-form" id="ssApplicantEditForm">
          <label><span>First name</span><input name="first_name" required value="${esc(detail.first_name||"")}"></label>
          <label><span>Middle name</span><input name="middle_name" value="${esc(detail.middle_name||"")}"></label>
          <label><span>Last name</span><input name="last_name" required value="${esc(detail.last_name||"")}"></label>
          <label><span>Gender</span><select name="gender" required>${genderOptions(detail.gender)}</select></label>
          <label><span>Date of birth</span><input name="date_of_birth" type="date" value="${esc(String(detail.date_of_birth||"").slice(0,10))}"></label>
          <label><span>Guardian</span><input name="guardian_name" required value="${esc(detail.guardian_name||"")}"></label>
          <label><span>Guardian phone</span><input name="guardian_phone" value="${esc(detail.guardian_phone||"")}"></label>
          <label><span>Guardian email</span><input name="guardian_email" type="email" value="${esc(detail.guardian_email||"")}"></label>
          <label><span>Academic year</span><select name="target_academic_year_id">${optionRows(ref?.academic_years,"name",detail.target_academic_year_id)}</select></label>
          <label><span>Applying class</span><select name="applying_class_id">${optionRows(ref?.classes,"name",detail.applying_class_id)}</select></label>
          <label><span>Previous school</span><input name="previous_school" value="${esc(detail.previous_school||"")}"></label>
          <label class="full"><span>Address</span><textarea name="address">${esc(detail.address||"")}</textarea></label>
          <label class="full"><span>Applicant notes</span><textarea name="applicant_notes">${esc(detail.applicant_notes||"")}</textarea></label>
          <label class="full"><span>Internal notes</span><textarea name="internal_notes">${esc(detail.internal_notes||"")}</textarea></label>
          <div class="ss-applicant-edit-actions"><button type="button" class="button ghost" data-cancel-applicant-edit>Cancel</button><button type="submit" class="button primary">Save changes</button></div>
        </form>
      </div>`;
      dialog.querySelector("[data-close-applicant-edit]").onclick=()=>dialog.close();
      dialog.querySelector("[data-cancel-applicant-edit]").onclick=()=>dialog.close();
      dialog.querySelector("#ssApplicantEditForm").onsubmit=async event=>{
        event.preventDefault();
        const submit=event.currentTarget.querySelector('button[type="submit"]');
        submit.disabled=true;
        try{
          const payload=Object.fromEntries(new FormData(event.currentTarget));
          payload.id=record.id;
          await rpc("admissions_save_application",{payload});
          dialog.close();
          toast("Applicant updated");
          refreshAdmissions();
        }catch(error){
          toast("Update failed",messageOf(error),"error");
        }finally{submit.disabled=false}
      };
      if(!dialog.open)dialog.showModal();
    }catch(error){
      toast("Applicant could not be opened",messageOf(error),"error");
    }
  }

  async function deleteApplicant(record){
    const reason=await window.EdusentiaPrompt(`Reason for deleting ${record.application_no} from the active applicant register:`);
    if(reason===null)return;
    if(!await window.EdusentiaConfirm(`Delete ${record.application_no} from the active applicant register?\n\nThe record will be withdrawn and retained in the audit history.`))return;
    try{
      await rpc("admissions_delete_application",{target_application_id:record.id,reason:String(reason).trim()||null});
      toast("Applicant deleted from register",record.application_no);
      refreshAdmissions();
    }catch(error){
      toast("Delete failed",messageOf(error),"error");
    }
  }

  async function markNotEnrolled(record){
    if(record.student_link_active){
      toast("Student is still active","Withdraw or remove the linked student from Student Directory before reopening this admission.","warning");
      return;
    }
    const reason=await window.EdusentiaPrompt(`Reason for marking ${record.application_no} as Not enrolled:`);
    if(reason===null)return;
    if(String(reason).trim().length<5){
      toast("Status change cancelled","Enter a reason of at least 5 characters.","warning");
      return;
    }
    if(!await window.EdusentiaConfirm(`Mark ${record.application_no} as Not enrolled?\n\nThe historical student link will be retained for audit purposes.`))return;
    try{
      await rpc("admissions_mark_not_enrolled",{target_application_id:record.id,reason:String(reason).trim()});
      toast("Application reopened","Status changed to Not enrolled.");
      refreshAdmissions();
    }catch(error){
      toast("Status change failed",messageOf(error),"error");
    }
  }

  async function permanentlyRemoveApplicant(record){
    const typed=await window.EdusentiaPrompt(`PERMANENT REMOVAL\n\nType the application number exactly to continue:\n${record.application_no}`);
    if(typed===null)return;
    if(String(typed).trim()!==String(record.application_no)){
      toast("Permanent removal cancelled","Application number did not match.","warning");
      return;
    }
    const reason=await window.EdusentiaPrompt("State the reason for permanent removal (required):");
    if(reason===null)return;
    if(String(reason).trim().length<5){
      toast("Permanent removal cancelled","Enter a reason of at least 5 characters.","warning");
      return;
    }
    if(!await window.EdusentiaConfirm(`Permanently remove ${record.application_no}?\n\nThis deletes the applicant and linked admission rows and cannot be undone.`))return;
    try{
      await rpc("admissions_permanently_remove_application",{
        target_application_id:record.id,
        confirmation_application_no:record.application_no,
        reason:String(reason).trim()
      });
      toast("Applicant permanently removed",record.application_no);
      refreshAdmissions();
    }catch(error){
      toast("Permanent removal failed",messageOf(error),"error");
    }
  }

  function actionButton(label,className,handler){
    const button=document.createElement("button");
    button.type="button";
    button.className=className;
    button.textContent=label;
    button.onclick=async()=>{
      if(button.disabled)return;
      button.disabled=true;
      try{await handler()}finally{button.disabled=false}
    };
    return button;
  }

  function applicantRegisterTable(){
    const content=$("content");
    if(!content||String($("pageTitle")?.textContent||"").trim()!=="Admissions")return null;
    const section=[...content.querySelectorAll("section")].find(node=>String(node.querySelector("h3")?.textContent||"").trim()==="Applicant register");
    return section?.querySelector("table")||null;
  }

  async function decorateApplicantRegister(){
    STATE.contentQueued=false;
    const table=applicantRegisterTable();
    if(!table||table.dataset.applicantActionsBuild===BUILD||decorating.has(table))return;
    decorating.add(table);
    const activeClient=client();
    try{
      const [s,records]=await Promise.all([
        session(true),
        rpc("admissions_application_register",{search_text:null,status_filter:null})
      ]);
      if(client()!==activeClient||!table.isConnected)return;
      const byNo=new Map((records||[]).map(record=>[String(record.application_no),record]));
      const canWrite=Boolean(s?.capabilities?.admissions_write);
      const isSystemAdmin=String(s?.app_role||"")==="system_admin";

      for(const row of table.querySelectorAll("tbody tr")){
        const cells=row.querySelectorAll("td");
        if(cells.length<6)continue;
        const applicationNo=String(cells[0].textContent||"").trim();
        const record=byNo.get(applicationNo);
        if(!record)continue;

        const hasActiveStudentLink=Boolean(record.student_link_active);
        const statusCell=cells[4];
        if(isSystemAdmin&&canWrite&&record.status==="enrolled"){
          const badge=statusCell.querySelector(".ssb");
          if(badge&&!statusCell.querySelector('[data-applicant-enrollment-status-v1]')){
            const statusButton=actionButton("Enrolled","ssb ss-status-action",()=>markNotEnrolled(record));
            statusButton.dataset.applicantEnrollmentStatusV1="enrolled";
            statusButton.title=hasActiveStudentLink
              ?"Student is active. Remove or withdraw the student first."
              :"Mark this application as Not enrolled";
            badge.replaceWith(statusButton);
          }
        }

        const actions=cells[cells.length-1].querySelector(".ssa")||cells[cells.length-1];
        if(actions.querySelector('[data-applicant-actions-v1]'))continue;

        const additions=[];
        if(canWrite&&!hasActiveStudentLink&&["draft","submitted","under_review","waitlisted","offered","not_enrolled"].includes(record.status)){
          const edit=actionButton("Edit","button ghost small",()=>editApplicant(record));
          edit.dataset.applicantActionsV1="edit";
          additions.push(edit);
        }
        if(canWrite&&!hasActiveStudentLink&&!["accepted","enrolled","withdrawn"].includes(record.status)){
          const del=actionButton("Delete","button ghost small ss-action-danger",()=>deleteApplicant(record));
          del.dataset.applicantActionsV1="delete";
          additions.push(del);
        }
        if(isSystemAdmin&&canWrite&&!hasActiveStudentLink&&!["accepted","enrolled"].includes(record.status)){
          const remove=actionButton("Remove permanently","button small ss-action-danger-strong",()=>permanentlyRemoveApplicant(record));
          remove.dataset.applicantActionsV1="permanent";
          additions.push(remove);
        }
        for(let index=additions.length-1;index>=0;index--)actions.insertBefore(additions[index],actions.firstChild);
      }

      const section=table.closest("section");
      const head=section?.querySelector(".page-head");
      if(head&&!section.querySelector(".ss-applicant-actions-note")){
        const note=document.createElement("p");
        note.className="ss-applicant-actions-note";
        note.textContent=isSystemAdmin
          ?"Delete withdraws an applicant and preserves audit history. Enrolled applications can be reopened only after the linked student is no longer active. Not enrolled applicants can be edited or removed; permanent removal remains MFA-protected and irreversible."
          :"Delete withdraws an applicant from the active register while preserving audit history.";
        head.insertAdjacentElement("afterend",note);
      }
      table.dataset.applicantActionsBuild=BUILD;
    }catch(error){
      if(!/multi-factor|aal2|access denied/i.test(messageOf(error)))console.warn("student_services_applicant_actions_load_failed",error);
    }finally{decorating.delete(table)}
  }

  function refreshAdmissions(){
    STATE.sessionAt=0;
    const tab=document.querySelector('[data-sstab="admissions"]');
    if(tab){tab.click();return}
    $("studentServicesNav")?.click();
    setTimeout(()=>document.querySelector('[data-sstab="admissions"]')?.click(),120);
  }

  function queueApplicantDecoration(){
    if(STATE.contentQueued)return;
    STATE.contentQueued=true;
    setTimeout(()=>requestAnimationFrame(decorateApplicantRegister),60);
  }

  function start(){
    ensureCss();
    queueNavigationOrder();
    queueApplicantDecoration();
    const nav=$("mainNav");
    if(nav)new MutationObserver(queueNavigationOrder).observe(nav,{childList:true,subtree:false});
    const content=$("content");
    if(content)new MutationObserver(queueApplicantDecoration).observe(content,{childList:true,subtree:true});
    window.addEventListener("pageshow",()=>{queueNavigationOrder();queueApplicantDecoration()},{passive:true});
  }

  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
})();