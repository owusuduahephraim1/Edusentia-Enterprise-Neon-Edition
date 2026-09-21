(() => {
  "use strict";
  const P=window.EdusentiaParity;
  if(!P)return;
  const {registerView,certified,role,esc,status,formatDate,formatDateTime,loading,empty,pageError,byId,academicConfig}=P;
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
    byId("content").innerHTML=sectionHead("Users and Access","Accounts, delegated access, and guardian portal identities")+loading("Loading users");
    try{
      const [profiles,guardians]=await Promise.all([certified("list_profiles_with_access",{}),certified("list_guardian_portal_accounts",{})]);
      byId("content").innerHTML=sectionHead("Users and Access","Accounts, delegated access, and guardian portal identities")+
        '<div class="section-title"><h4>Profiles and delegated access</h4></div>'+recordTable(firstArray(profiles)||profiles,["full_name","email","role","active"])+
        '<div class="section-title"><h4>Guardian portal accounts</h4></div>'+recordTable(firstArray(guardians)||guardians,["full_name","email","student_name","status"]);
    }catch(e){byId("content").innerHTML=sectionHead("Users and Access","Accounts, delegated access, and guardian portal identities")+pageError(e);}
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
    byId("content").innerHTML=sectionHead("Licence Capacity","Current school entitlement, capacity usage, and storage position")+loading("Loading licence capacity");
    try{const data=await certified("get_school_license_capacity_console",{});byId("content").innerHTML=sectionHead("Licence Capacity","Current school entitlement, capacity usage, and storage position")+objectPanels(data);}
    catch(e){byId("content").innerHTML=sectionHead("Licence Capacity","Current school entitlement, capacity usage, and storage position")+pageError(e);}
  }

  registerView({id:"attendance",label:"Attendance",icon:"✓",subtitle:"Daily class registers and term attendance",roles:["system_admin","principal","class_teacher"],render:renderAttendance});
  registerView({id:"history",label:"Academic History",icon:"◷",subtitle:"Published results, lifecycle, and transcripts",roles:["system_admin","principal"],render:renderHistory});
  registerView({id:"prospectus",label:"School Prospectus",icon:"▤",subtitle:"Fees, requirements, transport, policies, and revisions",roles:["system_admin"],render:renderProspectus});
  registerView({id:"delegations",label:"Emergency Delegation",icon:"⚑",subtitle:"Temporary academic access and continuity",roles:["system_admin","principal"],render:renderDelegations});
  registerView({id:"certificates",label:"Certificates",icon:"✦",subtitle:"Promotion, completion, and recognition awards",roles:["system_admin","principal"],render:renderCertificates});
  registerView({id:"id_cards",label:"ID Card Management",icon:"▥",subtitle:"Student and staff identity cards",roles:["system_admin"],render:renderIdCards});
  registerView({id:"insights",label:"Insights",icon:"◩",subtitle:"Performance, attendance, and completion trends",roles:["system_admin","principal","class_teacher","subject_teacher"],render:renderInsights});
  registerView({id:"children",label:"My Children",icon:"♥",subtitle:"Published academic records",roles:["parent_guardian"],render:renderChildren});
  registerView({id:"users",label:"Users and Access",icon:"♟",subtitle:"Accounts and delegated access",roles:["system_admin"],render:renderUsers});
  registerView({id:"compliance",label:"Compliance",icon:"⚿",subtitle:"Privacy, retention, and security evidence",roles:["system_admin"],render:renderCompliance});
  registerView({id:"backup_restore",label:"Backup & Recovery",icon:"↻",subtitle:"Backup history and recovery readiness",roles:["system_admin"],render:renderBackup});
  registerView({id:"license_capacity",label:"Licence Capacity",icon:"◇",subtitle:"Entitlement and capacity usage",roles:["system_admin"],render:renderLicenseCapacity});
})();