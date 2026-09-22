(() => {
  "use strict";
  const P=window.EdusentiaParity;
  if(!P)return;
  const {registerView,api,certified,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,academicConfig,openModal,closeModal,formValues,showMessage,friendly}=P;
  const local={attendance:{},history:{},insights:{},prospectus:{},delegations:{},certificates:{},idCards:{},users:{},compliance:{},backup:{},license:{}};
  const arr=value=>Array.isArray(value)?value:[];
  const obj=value=>value&&typeof value==="object"&&!Array.isArray(value)?value:{};
  const title=value=>String(value||"").replaceAll("_"," ").replace(/\b\w/g,m=>m.toUpperCase());
  const text=value=>value==null||value===""?"—":String(value);
  const simple=value=>value==null||["string","number","boolean"].includes(typeof value);
  const firstArray=data=>{
    if(Array.isArray(data))return data;
    for(const value of Object.values(obj(data)))if(Array.isArray(value))return value;
    return [];
  };
  function sectionHead(name,subtitle,actions=""){
    return '<div class="page-head"><div><h3>'+esc(name)+'</h3><p>'+esc(subtitle)+'</p></div><div class="page-actions">'+actions+'</div></div>';
  }
  function metrics(data){
    const entries=Object.entries(obj(data)).filter(([,v])=>simple(v)).slice(0,8);
    if(!entries.length)return "";
    return '<section class="stat-grid">'+entries.map(([k,v])=>'<article class="stat-card"><span class="stat-icon blue" aria-hidden="true">•</span><div><span>'+esc(title(k))+'</span><strong>'+esc(text(v))+'</strong></div></article>').join("")+'</section>';
  }
  function recordTable(rows,preferred=[]){
    rows=arr(rows);
    if(!rows.length)return empty("No records are available for the current filters.");
    const sample=obj(rows[0]);
    const keys=[...preferred.filter(k=>Object.prototype.hasOwnProperty.call(sample,k)),...Object.keys(sample).filter(k=>simple(sample[k])&&!preferred.includes(k))].slice(0,8);
    if(!keys.length)return '<section class="panel pad"><pre class="json-preview">'+esc(JSON.stringify(rows,null,2))+'</pre></section>';
    return '<section class="panel"><div class="table-wrap"><table><thead><tr>'+keys.map(k=>'<th>'+esc(title(k))+'</th>').join("")+'</tr></thead><tbody>'+
      rows.map(row=>'<tr>'+keys.map(k=>'<td>'+(
        /status/i.test(k)?status(row[k]):/(_at|_date|date_|expires_on|issued_on)$/i.test(k)?formatDate(row[k]):esc(text(row[k]))
      )+'</td>').join("")+'</tr>').join("")+'</tbody></table></div></section>';
  }
  function objectPanels(data){
    data=obj(data);
    const blocks=[];
    const scalar=Object.fromEntries(Object.entries(data).filter(([,v])=>simple(v)));
    if(Object.keys(scalar).length)blocks.push(metrics(scalar));
    for(const [key,value] of Object.entries(data)){
      if(Array.isArray(value))blocks.push('<div class="section-title"><h4>'+esc(title(key))+'</h4></div>'+recordTable(value));
      else if(value&&typeof value==="object"&&!Array.isArray(value)){
        const entries=Object.entries(value).filter(([,v])=>simple(v)).slice(0,16);
        if(entries.length)blocks.push('<section class="panel pad"><div class="section-title"><h4>'+esc(title(key))+'</h4></div><div class="detail-grid">'+entries.map(([k,v])=>'<div><span>'+esc(title(k))+'</span><strong>'+esc(text(v))+'</strong></div>').join("")+'</div></section>');
      }
    }
    return blocks.join("")||empty("No data is available yet.");
  }
  async function config(){
    const c=await academicConfig();
    return {years:arr(c?.academic_years),terms:arr(c?.terms),classes:arr(c?.classes),subjects:arr(c?.subjects)};
  }
  function options(rows,selected,label="name"){
    return '<option value="">Select</option>'+rows.map(r=>'<option value="'+esc(r.id||"")+'" '+(String(r.id||"")===String(selected||"")?"selected":"")+'>'+esc(r[label]||r.name||r.code||r.id)+'</option>').join("");
  }
  const ROLE_LABELS={system_admin:"System Administrator",principal:"Principal (Headmaster/Headmistress)",class_teacher:"Class Teacher",subject_teacher:"Subject Teacher",parent_guardian:"Parent or Guardian",accountant:"Accounts Office Staff",student:"Student"};
  function notify(titleText,body="",kind="success"){const stack=byId("toastStack");if(!stack){if(kind==="error")alert(titleText+(body?": "+body:""));return;}const node=document.createElement("div");node.className="toast "+kind;node.innerHTML="<strong>"+esc(titleText)+"</strong>"+(body?"<span>"+esc(body)+"</span>":"");stack.appendChild(node);setTimeout(()=>node.remove(),4500);}
  function generatedPassword(length=14){const sets=["ABCDEFGHJKLMNPQRSTUVWXYZ","abcdefghijkmnopqrstuvwxyz","23456789","!@#$%&*"],values=new Uint32Array(length);crypto.getRandomValues(values);const chars=sets.map((set,i)=>set[values[i]%set.length]),all=sets.join("");for(let i=chars.length;i<length;i++)chars.push(all[values[i]%all.length]);for(let i=chars.length-1;i>0;i--){const j=values[i]%(i+1);[chars[i],chars[j]]=[chars[j],chars[i]];}return chars.join("");}
  function capacityPercent(used,limit){const l=Number(limit),u=Number(used||0);return Number.isFinite(l)&&l>0?Math.min(100,Math.max(0,u/l*100)):0;}

  async function renderAttendance(){
    byId("content").innerHTML=sectionHead("Attendance","Class daily register and term attendance records")+loading("Loading attendance controls");
    try{
      const c=await config(),termId=local.attendance.termId||c.terms[0]?.id||"",classId=local.attendance.classId||c.classes[0]?.id||"",date=local.attendance.date||new Date().toISOString().slice(0,10);
      local.attendance={termId,classId,date};
      const data=termId&&classId?await certified("get_class_attendance_register",{target_term_id:termId,target_class_id:classId,target_date:date}):null;
      const rows=arr(data?.rows||data?.students||data?.entries||firstArray(data));
      byId("content").innerHTML=sectionHead("Attendance","Class daily register and term attendance records")+
        '<section class="panel pad"><div class="form-grid three"><label class="field"><span>Term</span><select id="attendanceTerm">'+options(c.terms,termId)+'</select></label><label class="field"><span>Class</span><select id="attendanceClass">'+options(c.classes,classId)+'</select></label><label class="field"><span>Date</span><input id="attendanceDate" type="date" value="'+esc(date)+'"></label></div></section>'+
        metrics(data?.summary||{})+recordTable(rows,["full_name","admission_no","attendance_status","status"]);
      for(const id of ["attendanceTerm","attendanceClass","attendanceDate"])byId(id)?.addEventListener("change",()=>{local.attendance.termId=byId("attendanceTerm").value;local.attendance.classId=byId("attendanceClass").value;local.attendance.date=byId("attendanceDate").value;renderAttendance();});
    }catch(e){byId("content").innerHTML=sectionHead("Attendance","Class daily register and term attendance records")+pageError(e);}
  }

  async function renderHistory(){
    byId("content").innerHTML=sectionHead("Academic History","Published results, lifecycle records, and official transcript history")+loading("Loading student history");
    try{
      const search=local.history.search||"";
      const found=await certified("search_students_v5",{search_text:search,target_class_id:null,target_status:null,archive_filter:"all",page_number:1,page_size:50});
      const students=arr(found?.rows);
      const selected=local.history.studentId||students[0]?.id||"";
      local.history.studentId=selected;
      const history=selected?await certified("get_student_academic_history",{target_student_id:selected}):null;
      byId("content").innerHTML=sectionHead("Academic History","Published results, lifecycle records, and official transcript history",selected?'<button id="issueTranscript" class="button secondary" type="button">Issue transcript</button>':"")+
        '<section class="panel pad"><div class="form-grid"><label class="field"><span>Search student</span><input id="historySearch" value="'+esc(search)+'" placeholder="Name or admission number"></label><label class="field"><span>Student</span><select id="historyStudent">'+options(students,selected,"full_name")+'</select></label></div></section>'+
        objectPanels(history||{});
      byId("historySearch")?.addEventListener("change",()=>{local.history.search=byId("historySearch").value.trim();local.history.studentId="";renderHistory();});
      byId("historyStudent")?.addEventListener("change",()=>{local.history.studentId=byId("historyStudent").value;renderHistory();});
      byId("issueTranscript")?.addEventListener("click",async()=>{const b=byId("issueTranscript");b.disabled=true;try{await certified("issue_student_transcript",{target_student_id:selected,purpose_text:"Academic transcript"});await renderHistory();}catch(e){alert(e?.message||"Transcript could not be issued.");}finally{b.disabled=false;}});
    }catch(e){byId("content").innerHTML=sectionHead("Academic History","Published results, lifecycle records, and official transcript history")+pageError(e);}
  }

  async function renderProspectus(){
    byId("content").innerHTML=sectionHead("School Prospectus","Academic-year fees, requirements, transportation, policies, and publication revisions")+loading("Loading prospectus");
    try{
      const c=await config(),yearId=local.prospectus.yearId||c.years[0]?.id||"";local.prospectus.yearId=yearId;
      const data=yearId?await certified("get_school_prospectus_console",{target_academic_year_id:yearId}):{};
      byId("content").innerHTML=sectionHead("School Prospectus","Academic-year fees, requirements, transportation, policies, and publication revisions")+
        '<section class="panel pad"><label class="field"><span>Academic year</span><select id="prospectusYear">'+options(c.years,yearId)+'</select></label></section>'+objectPanels(data);
      byId("prospectusYear")?.addEventListener("change",()=>{local.prospectus.yearId=byId("prospectusYear").value;renderProspectus();});
    }catch(e){byId("content").innerHTML=sectionHead("School Prospectus","Academic-year fees, requirements, transportation, policies, and publication revisions")+pageError(e);}
  }

  async function renderDelegations(){
    byId("content").innerHTML=sectionHead("Emergency Delegation","Temporary academic access and continuity controls")+loading("Loading delegations");
    try{
      const data=await certified("get_emergency_delegation_console",{});
      byId("content").innerHTML=sectionHead("Emergency Delegation","Temporary academic access and continuity controls")+objectPanels(data);
    }catch(e){byId("content").innerHTML=sectionHead("Emergency Delegation","Temporary academic access and continuity controls")+pageError(e);}
  }

  async function renderCertificates(){
    byId("content").innerHTML=sectionHead("Certificates","Promotion, completion, and teacher-recognition certificates")+loading("Loading certificate console");
    try{const data=await certified("get_certificate_console",{});byId("content").innerHTML=sectionHead("Certificates","Promotion, completion, and teacher-recognition certificates")+objectPanels(data);}
    catch(e){byId("content").innerHTML=sectionHead("Certificates","Promotion, completion, and teacher-recognition certificates")+pageError(e);}
  }

  async function renderIdCards(){
    byId("content").innerHTML=sectionHead("ID Card Management","Student and staff ID card issuance, lifecycle, and verification")+loading("Loading ID card console");
    try{
      const [student,staff]=await Promise.all([certified("get_id_card_console",{}),certified("get_staff_id_card_console",{})]);
      byId("content").innerHTML=sectionHead("ID Card Management","Student and staff ID card issuance, lifecycle, and verification")+
        '<div class="section-title"><h4>Student cards</h4></div>'+objectPanels(student)+'<div class="section-title"><h4>Staff cards</h4></div>'+objectPanels(staff);
    }catch(e){byId("content").innerHTML=sectionHead("ID Card Management","Student and staff ID card issuance, lifecycle, and verification")+pageError(e);}
  }

  async function renderInsights(){
    byId("content").innerHTML=sectionHead("Insights","Performance, attendance, completion, and class trends")+loading("Loading academic insights");
    try{
      const c=await config(),termId=local.insights.termId||c.terms[0]?.id||"",classId=local.insights.classId||"";local.insights.termId=termId;
      const data=termId?await certified("academic_analytics",{target_term_id:termId,target_class_id:classId||null}):{};
      byId("content").innerHTML=sectionHead("Insights","Performance, attendance, completion, and class trends")+
        '<section class="panel pad"><div class="form-grid"><label class="field"><span>Term</span><select id="insightsTerm">'+options(c.terms,termId)+'</select></label><label class="field"><span>Class</span><select id="insightsClass">'+options(c.classes,classId)+'</select></label></div></section>'+objectPanels(data);
      byId("insightsTerm")?.addEventListener("change",()=>{local.insights.termId=byId("insightsTerm").value;renderInsights();});
      byId("insightsClass")?.addEventListener("change",()=>{local.insights.classId=byId("insightsClass").value;renderInsights();});
    }catch(e){byId("content").innerHTML=sectionHead("Insights","Performance, attendance, completion, and class trends")+pageError(e);}
  }

  async function renderChildren(){
    byId("content").innerHTML=sectionHead("My Children","Published academic records for linked children")+loading("Loading linked children");
    try{const data=await certified("list_my_children_reports",{});byId("content").innerHTML=sectionHead("My Children","Published academic records for linked children")+objectPanels(data);}
    catch(e){byId("content").innerHTML=sectionHead("My Children","Published academic records for linked children")+pageError(e);}
  }

  async function renderUsers(){
    byId("content").innerHTML=sectionHead("Users and Access","Accounts, credentials, roles, classes, and security",'<button class="button primary" id="userAdd">Create user</button>')+loading("Loading users");
    try{
      const data=await certified("list_profiles_with_access",{}),profiles=arr(data?.profiles||firstArray(data));local.users.data=data;local.users.search="";local.users.role="";local.users.status="";
      byId("content").innerHTML=sectionHead("Users and Access","Accounts, credentials, roles, classes, and security",'<button class="button primary" id="userAdd">Create user</button>')+
        '<section class="panel"><div class="toolbar"><label class="search"><input id="userSearch" type="search" placeholder="Search name or email"></label><select id="userRoleFilter"><option value="">All roles</option>'+["system_admin","principal","class_teacher","subject_teacher","parent_guardian","accountant","student"].map(r=>'<option value="'+r+'">'+esc(ROLE_LABELS[r]||title(r))+'</option>').join("")+'</select><select id="userStatusFilter"><option value="">All accounts</option><option value="active">Active</option><option value="inactive">Inactive</option></select></div><div id="userResults"></div></section>';
      const renderRows=()=>{
        const q=(byId("userSearch")?.value||"").trim().toLowerCase(),rf=byId("userRoleFilter")?.value||"",sf=byId("userStatusFilter")?.value||"";
        const rows=profiles.filter(u=>(!q||((u.full_name||"")+" "+(u.email||"")+" "+(u.phone||"")).toLowerCase().includes(q))&&(!rf||u.role===rf)&&(!sf||(sf==="active"?u.active!==false:u.active===false)));
        byId("userResults").innerHTML=rows.length?'<div class="table-wrap"><table><thead><tr><th>User</th><th>Role</th><th>Account</th><th>MFA</th><th>Password</th><th>Class Access</th><th>Last Seen</th><th></th></tr></thead><tbody>'+rows.map(u=>'<tr><td><div class="cell-copy"><strong>'+esc(u.full_name||"Unnamed user")+'</strong><small>'+esc(u.email||u.phone||"")+(u.staff_no?" • "+esc(u.staff_no):"")+'</small></div></td><td>'+esc(ROLE_LABELS[u.role]||title(u.role))+'</td><td>'+(u.active!==false?'<span class="status published">Active</span>':'<span class="status withdrawn">Inactive</span>')+'</td><td>'+(u.mfa_required?'<span class="status approved">Required</span>':'<span class="status draft">Optional</span>')+'</td><td>'+(u.must_change_password?'<span class="status withdrawn">Change required</span>':'<span class="status published">Current</span>')+'</td><td>'+(arr(u.access).length?'<div class="chip-list">'+arr(u.access).slice(0,3).map(a=>'<span class="chip">'+esc(a.class_name||"Class")+(a.subject_name?" • "+esc(a.subject_name):"")+'</span>').join("")+(arr(u.access).length>3?'<span class="chip">+'+(arr(u.access).length-3)+'</span>':"")+'</div>':"School role")+'</td><td>'+formatDateTime(u.last_seen_at||u.last_sign_in_at)+'</td><td><div class="table-actions"><button class="button ghost small" data-user-edit="'+esc(u.id)+'">Edit</button><button class="button secondary small" data-user-reset="'+esc(u.id)+'">Reset password</button>'+(String(u.id)!==String(P.shell?.state?.session?.user?.id||window.EdusentiaShell?.state?.session?.user?.id||"")?'<button class="button danger small" data-user-delete="'+esc(u.id)+'">Delete</button>':"")+'</div></td></tr>').join("")+'</tbody></table></div>':empty("No users found");
        byId("userResults").querySelectorAll("[data-user-edit]").forEach(b=>b.onclick=()=>openUserEditor(b.dataset.userEdit));
        byId("userResults").querySelectorAll("[data-user-reset]").forEach(b=>b.onclick=()=>openUserPasswordReset(b.dataset.userReset));
        byId("userResults").querySelectorAll("[data-user-delete]").forEach(b=>b.onclick=()=>deleteUserAccount(b.dataset.userDelete));
      };
      const staffForRole=(roleName,userId="")=>{const source=roleName==="principal"?arr(data?.headteacher_records):roleName==="accountant"?arr(data?.accountant_records):["class_teacher","subject_teacher"].includes(roleName)?arr(data?.teacher_records):[];return source.filter(x=>!x.profile_id||String(x.profile_id)===String(userId));};
      const openUserEditor=(id="")=>{
        const user=id?profiles.find(x=>String(x.id)===String(id)):{role:"parent_guardian",active:true,mfa_required:false,must_change_password:false,access:[]};if(!user)return;
        openModal(id?"Edit User Account":"Create User Account",user.email||"",'<form id="userForm" class="form-stack"><div class="form-grid"><label class="field full hidden" id="userStaffField"><span id="userStaffLabel">Staff record</span><select name="staff_record_id" id="userStaffSelect"></select></label><label class="field"><span>Full name</span><input name="full_name" value="'+esc(user.full_name||"")+'" required></label><label class="field"><span>Email address</span><input name="email" type="email" value="'+esc(user.email||"")+'" readonly placeholder="Generated when the account is created"></label><label class="field"><span>Telephone</span><input name="phone" value="'+esc(user.phone||"")+'"></label><label class="field"><span>Role</span><select id="userRoleSelect" name="role">'+["system_admin","principal","class_teacher","subject_teacher","parent_guardian","accountant"].map(r=>'<option value="'+r+'" '+(r===user.role?"selected":"")+'>'+esc(ROLE_LABELS[r])+'</option>').join("")+'</select></label>'+(id?'<div class="help-text full">Use the separate <strong>Reset password</strong> action after saving account details.</div>':'<label class="field full"><span>Password</span><div class="password-wrap"><input id="adminUserPassword" name="password" type="password" minlength="8" autocomplete="new-password" required><button id="generateUserPassword" class="button ghost small" type="button">Generate</button></div></label>')+'<label class="check-field"><input name="active" type="checkbox" '+(user.active!==false?"checked":"")+'><span>Active account</span></label><label class="check-field"><input name="mfa_required" type="checkbox" '+(user.mfa_required?"checked":"")+'><span>Require multi-factor authentication</span></label><label class="check-field full"><input name="must_change_password" type="checkbox" '+(user.must_change_password?"checked":"")+'><span>Force password change on next login</span></label></div><div class="template-information"><strong>Teaching responsibilities</strong><span>Class-teacher and subject-teaching access is synchronised from Academics.</span></div><p id="userFormMessage" class="form-message hidden" role="alert"></p></form>','<button class="button ghost" id="userCancel" type="button">Cancel</button><button class="button primary" id="userSave" type="button">'+(id?"Save account":"Create account")+'</button>');
        const form=byId("userForm"),roleSelect=byId("userRoleSelect"),staffField=byId("userStaffField"),staffSelect=byId("userStaffSelect"),staffLabel=byId("userStaffLabel");
        const syncStaff=()=>{const r=roleSelect.value,required=["principal","class_teacher","subject_teacher","accountant"].includes(r),rows=staffForRole(r,id),selected=user.headteacher_id||user.teacher_id||user.accountant_id||user.staff_record_id||"";staffField.classList.toggle("hidden",!required);staffSelect.required=required;staffLabel.textContent=r==="principal"?"Principal record":r==="accountant"?"Accounts Office Staff record":"Teacher record";staffSelect.innerHTML=required?'<option value="">Select linked record</option>'+rows.map(x=>'<option value="'+esc(x.id)+'" '+(String(x.id)===String(selected)?"selected":"")+'>'+esc(x.label||x.full_name||x.staff_no||x.id)+'</option>').join(""):'<option value="">Not applicable</option>';if(r==="accountant"){form.elements.mfa_required.checked=true;form.elements.mfa_required.disabled=true}else form.elements.mfa_required.disabled=false;};
        roleSelect.onchange=syncStaff;syncStaff();
        byId("generateUserPassword")?.addEventListener("click",()=>{const value=generatedPassword();byId("adminUserPassword").value=value;byId("adminUserPassword").type="text";});
        byId("userCancel").onclick=closeModal;
        byId("userSave").onclick=async()=>{if(!form.reportValidity())return;const v=formValues(form),button=byId("userSave");button.disabled=true;try{if(!id&&String(v.password||"").length<8)throw new Error("Password must contain at least 8 characters");await api().adminUserManagement(id?"update":"create",{user_id:id||undefined,full_name:String(v.full_name||"").trim(),phone:String(v.phone||"").trim(),role:v.role,staff_record_id:v.staff_record_id||"",password:id?"":String(v.password||""),active:form.elements.active.checked,mfa_required:v.role==="accountant"?true:form.elements.mfa_required.checked,must_change_password:form.elements.must_change_password.checked,access:arr(user.access).map(a=>({class_id:a.class_id||null,subject_id:a.subject_id||null,access_level:a.access_level||"view"})),reason:id?"User account updated":"User account created"});closeModal();notify(id?"User account saved":"User account created");await renderUsers();}catch(e){showMessage("userFormMessage",friendly(e));}finally{button.disabled=false;}};
      };
      const openUserPasswordReset=id=>{const user=profiles.find(x=>String(x.id)===String(id));if(!user)return;openModal("Reset User Password",user.email||user.full_name||"",'<form id="passwordResetForm" class="form-stack"><label class="field"><span>Temporary password</span><div class="password-wrap"><input name="password" type="text" value="'+esc(generatedPassword())+'" minlength="8" required><button class="button ghost small" id="regenerateResetPassword" type="button">Generate</button></div></label><label class="check-field"><input name="force_password_change" type="checkbox" checked><span>Force password change on next login</span></label><p id="passwordResetMessage" class="form-message hidden"></p></form>','<button class="button ghost" id="passwordResetCancel">Cancel</button><button class="button primary" id="passwordResetSave">Reset password</button>');byId("regenerateResetPassword").onclick=()=>{byId("passwordResetForm").elements.password.value=generatedPassword()};byId("passwordResetCancel").onclick=closeModal;byId("passwordResetSave").onclick=async()=>{const form=byId("passwordResetForm"),button=byId("passwordResetSave");if(!form.reportValidity())return;button.disabled=true;try{await api().adminUserManagement("reset_password",{user_id:id,password:form.elements.password.value,force_password_change:form.elements.force_password_change.checked,must_change_password:form.elements.force_password_change.checked,reason:"Password reset by the System Administrator"});closeModal();notify("Password reset",form.elements.force_password_change.checked?"The user must change it at the next login.":"The temporary password is active.");await renderUsers();}catch(e){showMessage("passwordResetMessage",friendly(e));}finally{button.disabled=false;}};};
      const deleteUserAccount=async id=>{const user=profiles.find(x=>String(x.id)===String(id));if(!user||!confirm("Permanently delete "+(user.full_name||user.email||"this account")+"?"))return;try{await api().adminUserManagement("delete",{user_id:id,reason:"User account permanently deleted by the System Administrator"});notify("User account deleted");await renderUsers();}catch(e){notify("User account not deleted",friendly(e),"error");}};
      byId("userAdd").onclick=()=>openUserEditor();
      ["userSearch","userRoleFilter","userStatusFilter"].forEach(id=>byId(id).addEventListener(id==="userSearch"?"input":"change",renderRows));
      renderRows();
    }catch(e){byId("content").innerHTML=sectionHead("Users and Access","Accounts, credentials, roles, classes, and security")+pageError(e);}
  }

  async function renderCompliance(){
    byId("content").innerHTML=sectionHead("Compliance","Privacy, retention, security events, and verification evidence")+loading("Loading compliance console");
    try{const data=await certified("get_compliance_console",{});byId("content").innerHTML=sectionHead("Compliance","Privacy, retention, security events, and verification evidence")+objectPanels(data);}
    catch(e){byId("content").innerHTML=sectionHead("Compliance","Privacy, retention, security events, and verification evidence")+pageError(e);}
  }

  async function renderBackup(){
    byId("content").innerHTML=sectionHead("Backup and Recovery","Backup history, off-site status, recovery tests, and restore readiness")+loading("Loading backup and recovery");
    try{
      const [backups,recovery]=await Promise.all([certified("backup_dashboard",{}),certified("get_recovery_console",{})]);
      byId("content").innerHTML=sectionHead("Backup and Recovery","Backup history, off-site status, recovery tests, and restore readiness")+
        '<div class="section-title"><h4>Backup</h4></div>'+objectPanels(backups)+'<div class="section-title"><h4>Recovery</h4></div>'+objectPanels(recovery);
    }catch(e){byId("content").innerHTML=sectionHead("Backup and Recovery","Backup history, off-site status, recovery tests, and restore readiness")+pageError(e);}
  }

  async function renderLicenseCapacity(){
    byId("content").innerHTML=sectionHead("Licence and Capacity","Signed entitlement, capacity usage, verification health, and storage position",'<button class="button secondary" id="licenseCapacityRefresh">Refresh status</button>')+loading("Loading licence capacity");
    try{
      const data=await certified("get_school_license_capacity_console",{}),snapshot=obj(data?.snapshot),plan=obj(data?.plan),capacity=arr(data?.capacity),storage=arr(data?.storage_buckets),history=arr(data?.verification_history),computed=String(snapshot.computed_status||snapshot.status||"unknown");
      byId("content").innerHTML=sectionHead("Licence and Capacity","Signed entitlement, capacity usage, verification health, and storage position",'<button class="button secondary" id="licenseCapacityRefresh">Refresh status</button>')+
        '<section class="panel pad"><div class="section-title"><div><h4>'+esc(plan.name||plan.code||"School licence")+'</h4><p>'+esc(snapshot.license_reference||"No licence reference")+'</p></div>'+status(computed)+'</div>'+
        (snapshot.warning?'<div class="template-information warning"><strong>Licence attention</strong><span>'+esc(snapshot.warning)+'</span></div>':'<div class="template-information success"><strong>Licence status verified</strong><span>The signed entitlement is verified and the current school access rules are active.</span></div>')+
        '<div class="metric-row wrap" style="margin-top:14px"><div class="metric"><span>Access mode</span><strong>'+esc(title(snapshot.access_mode||"full"))+'</strong><small>'+(snapshot.write_allowed===false?"Writes restricted":"Writes permitted")+'</small></div><div class="metric"><span>Issue date</span><strong>'+formatDate(snapshot.issued_on)+'</strong><small>Activated '+formatDateTime(snapshot.activated_at)+'</small></div><div class="metric"><span>Expiry</span><strong>'+(snapshot.expires_at?formatDateTime(snapshot.expires_at):"No expiry")+'</strong><small>'+(snapshot.days_remaining==null?"—":esc(snapshot.days_remaining)+" days remaining")+'</small></div><div class="metric"><span>Plan revision</span><strong>'+esc(text(plan.revision||snapshot.plan_revision))+'</strong><small>'+esc(plan.billing_cycle||"custom")+' billing</small></div></div></section>'+
        '<section class="panel pad" style="margin-top:18px"><div class="section-title"><div><h4>Capacity usage</h4><p>Current active usage against the signed entitlement. Unlimited limits remain unrestricted.</p></div></div><div class="license-capacity-grid">'+(capacity.length?capacity.map(item=>{const p=capacityPercent(item.used,item.limit),unlimited=item.limit==null,stateClass=unlimited||p<90?"published":p<100?"approved":"withdrawn",remaining=unlimited?"Unlimited":Math.max(Number(item.limit||0)-Number(item.used||0),0);return '<article class="license-capacity-card"><header><div><strong>'+esc(item.label||title(item.key))+'</strong><small>'+esc(item.unit||"records")+'</small></div><span class="status '+stateClass+'">'+(unlimited?"Available":p>=100?"Full":p>=90?"Attention":"Available")+'</span></header><div class="license-capacity-value"><b>'+esc(text(item.used))+'</b><span>of '+(unlimited?"Unlimited":esc(item.limit))+'</span></div><div class="bar-track"><span style="width:'+p+'%"></span></div><small>'+(unlimited?"No signed maximum":esc(remaining)+" remaining • "+p.toFixed(1)+"% used")+'</small></article>';}).join(""):empty("No capacity data is available."))+'</div></section>'+
        '<div class="grid two" style="margin-top:18px"><section class="panel pad"><div class="section-title"><h4>Verification and binding</h4></div><div class="detail-grid"><div><span>Signature</span><strong>'+esc(title(snapshot.signature_status||"unknown"))+'</strong></div><div><span>Authority</span><strong>'+esc(title(snapshot.authority_status||"unknown"))+'</strong></div><div><span>Authority last success</span><strong>'+formatDateTime(snapshot.authority_last_success_at)+'</strong></div><div><span>Binding</span><strong>'+(snapshot.binding_verified===true?"Verified":"Attention required")+'</strong></div><div><span>Tenant code</span><strong>'+esc(snapshot.tenant_code||"—")+'</strong></div><div><span>Package ID</span><strong>'+esc(snapshot.package_id||"—")+'</strong></div></div></section>'+
        '<section class="panel pad"><div class="section-title"><h4>School storage</h4></div><div class="table-wrap"><table><thead><tr><th>Bucket</th><th>Storage MB</th><th>Objects</th></tr></thead><tbody>'+(storage.length?storage.map(row=>'<tr><td>'+esc(row.bucket||row.bucket_id||"—")+'</td><td>'+formatAmount(row.storage_mb||row.size_mb||0)+'</td><td>'+esc(text(row.object_count))+'</td></tr>').join(""):'<tr><td colspan="3">No storage rows</td></tr>')+'</tbody></table></div></section></div>'+
        '<section class="panel" style="margin-top:18px"><div class="panel-header"><div><h3>Verification history</h3><p>Recent authority and signature checks</p></div></div><div class="table-wrap"><table><thead><tr><th>Checked at</th><th>Access mode</th><th>Computed status</th><th>Verification source</th></tr></thead><tbody>'+(history.length?history.slice(0,25).map(row=>'<tr><td>'+formatDateTime(row.checked_at||row.created_at)+'</td><td>'+esc(title(row.access_mode||"—"))+'</td><td>'+esc(title(row.computed_status||row.status||"—"))+'</td><td>'+esc(row.verification_source||row.source||"—")+'</td></tr>').join(""):'<tr><td colspan="4">No verification history</td></tr>')+'</tbody></table></div></section>';
      byId("licenseCapacityRefresh").onclick=renderLicenseCapacity;
    }catch(e){byId("content").innerHTML=sectionHead("Licence and Capacity","Signed entitlement, capacity usage, verification health, and storage position")+pageError(e);}
  }

  async function renderTeacherProfile(){
    byId("content").innerHTML=sectionHead("My Teacher Profile","Official staff details, qualifications, and current teaching assignments")+loading("Loading teacher profile");
    try{
      const data=await certified("get_my_teacher_profile",{});
      if(!data?.linked){byId("content").innerHTML=sectionHead("My Teacher Profile","Official staff details, qualifications, and current teaching assignments")+empty("No linked teacher record. Ask the System Administrator to link your account to a teacher record.");return;}
      const teacher=obj(data.teacher),classes=arr(data.classes),subjects=arr(data.subjects);
      byId("content").innerHTML=sectionHead("My Teacher Profile","Official staff details, qualifications, and current teaching assignments")+
        '<section class="panel pad"><div class="detail-grid">'+Object.entries(teacher).filter(([,v])=>simple(v)).slice(0,18).map(([k,v])=>'<div><span>'+esc(title(k))+'</span><strong>'+esc(text(v))+'</strong></div>').join("")+'</div></section>'+
        '<div class="section-title"><h4>Assigned classes</h4></div>'+recordTable(classes,["class_name","student_count","subject_count"])+
        '<div class="section-title"><h4>Subject assignments</h4></div>'+recordTable(subjects,["class_name","subject_name","subject_code"]);
    }catch(e){byId("content").innerHTML=sectionHead("My Teacher Profile","Official staff details, qualifications, and current teaching assignments")+pageError(e);}
  }

  async function renderMyClass(){
    byId("content").innerHTML=sectionHead("My Class","Assigned learners, subjects, and report completion")+loading("Loading class workspace");
    try{
      const data=await certified("get_role_workspace",{}),rows=arr(data?.classes);
      byId("content").innerHTML=sectionHead("My Class","Assigned learners, subjects, and report completion")+
        recordTable(rows,["class_name","student_count","subject_count","open_reports","review_reports","published_reports","completed_reports","expected_reports"]);
    }catch(e){byId("content").innerHTML=sectionHead("My Class","Assigned learners, subjects, and report completion")+pageError(e);}
  }

  async function renderMySubjects(){
    byId("content").innerHTML=sectionHead("My Subjects","Assigned classes and assessment workload")+loading("Loading subject workspace");
    try{
      const data=await certified("get_role_workspace",{}),rows=arr(data?.subjects);
      byId("content").innerHTML=sectionHead("My Subjects","Assigned classes and assessment workload")+
        recordTable(rows,["class_name","subject_name","subject_code","student_count","open_reports","scored_reports","expected_reports"]);
    }catch(e){byId("content").innerHTML=sectionHead("My Subjects","Assigned classes and assessment workload")+pageError(e);}
  }

  async function renderPlanUpgrade(){
    byId("content").innerHTML=sectionHead("Upgrade Plan","Renew or activate an authorized Edusentia plan")+loading("Loading licence status");
    try{
      const [capacity,licence]=await Promise.all([certified("get_school_license_capacity_console",{}),api().licenseStatus().catch(()=>null)]);
      const plan=obj(capacity?.plan),snapshot=obj(capacity?.snapshot);
      byId("content").innerHTML=sectionHead("Upgrade Plan","Renew or activate an authorized Edusentia plan")+
        metrics({plan:plan.name||plan.code||"Current plan",status:snapshot.computed_status||snapshot.status||licence?.status||"active",expires_at:snapshot.expires_at||licence?.expiresAt||"—"})+
        '<section class="panel pad"><form id="planUpgradeForm" class="form-stack"><label class="field"><span>Activation code</span><input name="code" autocomplete="off" maxlength="512" required></label><p class="muted">Use only a one-time code issued for this school workspace.</p><p id="planUpgradeMessage" class="form-message hidden" role="alert"></p><div class="button-row"><button class="button primary" type="submit">Verify and activate</button></div></form></section>';
      byId("planUpgradeForm")?.addEventListener("submit",async event=>{
        event.preventDefault();const form=event.currentTarget,button=form.querySelector('button[type="submit"]'),msg=byId("planUpgradeMessage"),code=String(new FormData(form).get("code")||"").trim();
        button.disabled=true;msg.classList.add("hidden");
        try{await api().activateLicense(code);msg.textContent="Licence activation completed successfully.";msg.dataset.kind="success";msg.classList.remove("hidden");form.reset();setTimeout(()=>renderPlanUpgrade(),500);}
        catch(e){msg.textContent=e?.message||"Licence activation failed.";msg.dataset.kind="error";msg.classList.remove("hidden");}
        finally{button.disabled=false;}
      });
    }catch(e){byId("content").innerHTML=sectionHead("Upgrade Plan","Renew or activate an authorized Edusentia plan")+pageError(e);}
  }

  async function renderSettings(){
    byId("content").innerHTML=sectionHead("Settings","School identity, security, health, and resilience")+loading("Loading system settings");
    try{
      const [boot,health,backup,readiness,templates]=await Promise.all([api().bootstrap(),certified("system_health",{}).catch(()=>null),certified("backup_dashboard",{}).catch(()=>null),certified("validate_operational_readiness",{}).catch(()=>null),certified("list_report_card_templates",{}).catch(()=>[])]);
      const school=obj(boot?.school||boot?.tenant),templateRows=arr(templates),rangeLabels={early_years:"Creche to Kindergarten (KG 1 and KG 2)",basic_1_6:"Basic 1 to Basic 6",basic_7_9:"Basic 7 to Basic 9"};
      byId("content").innerHTML=sectionHead("Settings","School identity, security, health, and resilience")+
        '<div class="grid two"><section class="panel pad"><div class="section-title"><h4>School identity</h4></div><form class="form-grid"><label class="field"><span>School name</span><input value="'+esc(school.name||school.school_name||"")+'" readonly></label><label class="field"><span>Institution type</span><input value="'+esc(title(school.institution_type||""))+'" readonly></label><label class="field"><span>Tenant code</span><input value="'+esc(school.code||"")+'" readonly></label><label class="field"><span>Time zone</span><input value="'+esc(school.timezone||school.settings?.timezone||"Africa/Accra")+'" readonly></label><div class="field full school-logo-settings"><span>Official school logo</span><input id="schoolLogoFile" type="file" accept="image/png" required><div class="button-row"><button class="button secondary small" id="schoolLogoSave" type="button">Upload / Change logo</button></div><small>Used automatically on official school documents. Upload a clear PNG image.</small><p id="schoolLogoMessage" class="form-message hidden"></p></div></form></section>'+
        '<div class="grid"><section class="panel pad"><div class="section-title"><h4>Account Security</h4></div><div class="metric-row"><div class="metric"><span>Role</span><strong>'+esc(ROLE_LABELS[role()]||title(role()))+'</strong></div><div class="metric"><span>MFA policy</span><strong>'+((boot?.capabilities?.assuranceLevel||1)>=2?"Verified":"Required")+'</strong></div></div></section>'+
        '<section class="panel pad"><div class="section-title"><h4>System Health</h4><button class="button ghost small" id="healthRefresh">Refresh</button></div><div class="metric-row wrap"><div class="metric"><span>Active users</span><strong>'+Number(health?.active_users||0)+'</strong></div><div class="metric"><span>Active teachers</span><strong>'+Number(health?.active_teachers||0)+'</strong></div><div class="metric"><span>Active students</span><strong>'+Number(health?.active_students||0)+'</strong></div><div class="metric"><span>Pending messages</span><strong>'+Number(health?.pending_notifications||0)+'</strong></div><div class="metric"><span>Errors, 24h</span><strong>'+Number(health?.client_errors_24h||0)+'</strong></div></div><div class="hr"></div><div class="diff-row"><span>Latest full backup</span><b>'+formatDateTime(health?.latest_backup)+'</b></div><div class="diff-row"><span>Latest verified backup</span><b>'+formatDateTime(health?.latest_verified_backup)+'</b></div><div class="diff-row"><span>Latest off-site copy</span><b>'+formatDateTime(health?.latest_offsite_copy)+'</b></div><div class="diff-row"><span>Record save services</span><b>'+(readiness?.ready?"Operational":"Attention required")+'</b></div><div class="diff-row"><span>Data security</span><b>'+(readiness&&Object.values(obj(readiness.rls)).every(Boolean)?"Protected":"Attention required")+'</b></div></section></div></div>'+
        '<div class="grid two" style="margin-top:18px"><section class="panel pad"><div class="section-title"><h4>Backup and Recovery</h4></div><form id="backupPolicyForm" class="form-grid compact"><label class="field"><span>Retention days</span><input name="retention_days" type="number" min="7" max="365" value="'+esc(backup?.retention_days??backup?.policy?.retention_days??30)+'"></label><label class="field"><span>Minimum retained copies</span><input name="minimum_copies" type="number" min="2" max="90" value="'+esc(backup?.minimum_copies??backup?.policy?.minimum_copies??7)+'"></label><div class="full button-row"><button class="button secondary" id="backupPolicySave" type="button">Save retention policy</button></div><p id="backupPolicyMessage" class="form-message hidden full"></p></form></section>'+
        '<section class="panel pad"><div class="section-title"><h4>Scheduled Operations</h4></div><div class="button-row"><button class="button secondary" id="notifyIncomplete">Queue incomplete-report alerts</button></div></section></div>'+
        '<section class="panel pad report-template-admin" style="margin-top:18px"><div class="section-title"><div><h4>Report Card Templates by Class Range</h4><p>Uploaded PDF or DOCX designs remain linked to the fixed class ranges and use the current official school header during generation.</p></div></div><div class="template-information"><strong>Protected dynamic header</strong><span>The current official school logo and identity are applied during generation.</span></div><div class="report-template-grid">'+["early_years","basic_1_6","basic_7_9"].map(key=>{const item=templateRows.find(row=>row.range_key===key);return '<article class="report-template-card"><div class="report-template-card-head"><div><h5>'+esc(rangeLabels[key])+'</h5></div><span class="status '+(item?"published":"draft")+'">'+(item?"Assigned":"Built-in fallback")+'</span></div>'+(item?'<div class="template-file-summary"><strong>'+esc(item.original_name||"Uploaded template")+'</strong><span>'+esc(String(item.mime_type||"").includes("pdf")?"PDF":"DOCX")+' • Version '+Number(item.version||1)+'</span><small>Updated '+formatDateTime(item.updated_at)+'</small></div>':'<div class="template-file-summary empty-template"><strong>No uploaded template</strong><span>The approved built-in terminal-report design is used automatically for this class range.</span></div>')+'</article>';}).join("")+'</div></section>';
      byId("healthRefresh").onclick=renderSettings;
      byId("schoolLogoSave").onclick=async()=>{const file=byId("schoolLogoFile").files?.[0],button=byId("schoolLogoSave"),msg=byId("schoolLogoMessage");if(!file)return;if(file.type!=="image/png"){msg.textContent="The official logo must be a PNG file.";msg.dataset.kind="error";msg.classList.remove("hidden");return;}button.disabled=true;try{const uploaded=await api().uploadFile(file,"school-branding");await certified("set_school_logo_reference",{target_logo_url:uploaded.objectKey});msg.textContent="Official school logo updated successfully.";msg.dataset.kind="success";msg.classList.remove("hidden");byId("schoolLogoFile").value="";}catch(e){msg.textContent=friendly(e);msg.dataset.kind="error";msg.classList.remove("hidden");}finally{button.disabled=false;}};
      byId("backupPolicySave").onclick=async()=>{const form=byId("backupPolicyForm"),v=formValues(form),button=byId("backupPolicySave");button.disabled=true;try{await certified("save_backup_policy",{target_retention_days:Number(v.retention_days),target_minimum_copies:Number(v.minimum_copies)});notify("Backup retention policy saved");await renderSettings();}catch(e){showMessage("backupPolicyMessage",friendly(e));}finally{button.disabled=false;}};
      byId("notifyIncomplete").onclick=async()=>{const button=byId("notifyIncomplete");button.disabled=true;try{const c=await config(),term=c.terms.find(row=>row.is_active)||c.terms[0];if(!term?.id)throw new Error("An academic term is required before queuing report alerts.");const count=await certified("queue_incomplete_report_notifications",{target_term_id:term.id});notify("Incomplete-report alerts queued",Number(count||0)+" notification"+(Number(count||0)===1?"":"s")+" queued.");}catch(e){notify("Alerts were not queued",friendly(e),"error");}finally{button.disabled=false;}};
    }catch(e){byId("content").innerHTML=sectionHead("Settings","School identity, security, health, and resilience")+pageError(e);}
  }

  registerView({id:"teacher_profile",label:"My Profile",icon:"♙",subtitle:"Teacher profile, photograph, qualifications, and assignments",roles:["class_teacher","subject_teacher"],render:renderTeacherProfile});
  registerView({id:"my_class",label:"My Class",icon:"▣",subtitle:"Assigned class, learners, and report progress",roles:["class_teacher"],render:renderMyClass});
  registerView({id:"my_subjects",label:"My Subjects",icon:"⌘",subtitle:"Assigned subjects, classes, and assessment progress",roles:["class_teacher","subject_teacher"],render:renderMySubjects});
  registerView({id:"attendance",label:"Attendance",icon:"✓",subtitle:"Daily class attendance and automatic term totals",roles:["class_teacher"],feature:"attendance",render:renderAttendance});
  registerView({id:"history",label:"Academic History",icon:"▧",subtitle:"Cumulative transcripts, lifecycle, transfers, and verification",roles:["system_admin","principal","class_teacher","subject_teacher"],feature:"academic_history",render:renderHistory});
  registerView({id:"prospectus",label:"School Prospectus",icon:"▤",subtitle:"Academic-year fees, requirements, transportation, policies, revisions, and PDF output",roles:["system_admin"],feature:"school_prospectus",render:renderProspectus});
  registerView({id:"delegations",label:"Emergency Delegation",icon:"⚑",subtitle:"Temporary academic access and continuity",roles:["system_admin","principal"],render:renderDelegations});
  registerView({id:"certificates",label:"Certificates",icon:"✦",subtitle:"Promotion, completion, and teacher recognition awards",roles:["system_admin","principal"],feature:"certificates",render:renderCertificates});
  registerView({id:"id_cards",label:"ID Card Management",icon:"▥",subtitle:"Professional student and staff ID cards, QR verification, printing, and lifecycle",roles:["system_admin"],feature:"id_cards",render:renderIdCards});
  registerView({id:"insights",label:"Insights",icon:"◩",subtitle:"Performance, attendance, completion, and class trends",roles:["system_admin","principal","class_teacher","subject_teacher"],feature:"analytics",render:renderInsights});
  registerView({id:"children",label:"My Children",icon:"♥",subtitle:"Published academic records",roles:["parent_guardian"],render:renderChildren});
  registerView({id:"users",label:"Users and Access",icon:"♟",subtitle:"Roles, classes, and security",permission:"manage_users",render:renderUsers});
  registerView({id:"compliance",label:"Privacy and Security",icon:"◈",subtitle:"Retention, privacy requests, security events, and verification",roles:["system_admin","principal"],feature:"governance",render:renderCompliance});
  registerView({id:"backup_restore",label:"Backup & Restore",icon:"↻",subtitle:"Downloadable full-school continuity and disaster recovery",roles:["system_admin"],render:renderBackup});
  registerView({id:"plan_upgrade",label:"Upgrade Plan",icon:"◇",subtitle:"Verify and activate a platform-authorized plan upgrade",roles:["system_admin"],render:renderPlanUpgrade});
  registerView({id:"settings",label:"Settings",icon:"⚙",subtitle:"School identity, security, and resilience",roles:["system_admin"],render:renderSettings});
  registerView({id:"license_capacity",label:"Licence and Capacity",icon:"◫",subtitle:"Read-only licence status, limits, usage, and verification",roles:["system_admin"],render:renderLicenseCapacity});
})();