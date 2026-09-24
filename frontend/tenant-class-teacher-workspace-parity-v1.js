(() => {
  "use strict";
  if(window.__EDUSENTIA_CLASS_TEACHER_WORKSPACE_PARITY_V1__)return;
  window.__EDUSENTIA_CLASS_TEACHER_WORKSPACE_PARITY_V1__=true;

  const P=window.EdusentiaParity,S=window.EdusentiaShell;
  if(!P||!S)return;
  const {registerView,api,certified,role,esc,formatDate,loading,empty,pageError,byId,friendly,downloadBlob,academicConfig}=P;
  const local={attendance:{},insights:{}};
  const arr=value=>Array.isArray(value)?value:[];
  const obj=value=>value&&typeof value==="object"&&!Array.isArray(value)?value:{};
  const state=()=>S.state||{};
  const nav=view=>S.navigate?.(view);
  const writable=()=>state().boot?.license?.write_allowed!==false;
  const n=(value,digits=0)=>{const x=Number(value||0);return Number.isFinite(x)?(digits?x.toFixed(digits):String(Math.round(x))):"0";};
  const progress=(done,total)=>{const t=Number(total||0);return t?Math.max(0,Math.min(100,Math.round(Number(done||0)/t*100))):0;};
  const initials=name=>String(name||"Teacher").trim().split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]||"").join("").toUpperCase()||"T";
  const currentRoleLabel=()=>({class_teacher:"Class Teacher",subject_teacher:"Subject Teacher"})[role()]||"Teacher";
  const notify=(title,body="",kind="success")=>{
    if(window.EdusentiaNotify){window.EdusentiaNotify(title,body,kind);return;}
    const stack=byId("toastStack");if(!stack){if(kind==="error")alert(title+(body?": "+body:""));return;}
    const node=document.createElement("div");node.className="toast "+kind;node.innerHTML="<strong>"+esc(title)+"</strong>"+(body?"<span>"+esc(body)+"</span>":"");stack.appendChild(node);setTimeout(()=>node.remove(),4500);
  };
  const sectionHead=(title,subtitle,actions="")=>'<div class="page-head"><div><h3>'+esc(title)+'</h3><p>'+esc(subtitle)+'</p></div><div class="page-actions">'+actions+'</div></div>';
  const stat=(tone,icon,label,value)=>'<article class="stat-card"><span class="stat-icon '+esc(tone)+'" aria-hidden="true">'+esc(icon)+'</span><div><span>'+esc(label)+'</span><strong>'+esc(value)+'</strong></div></article>';
  const csv=value=>'"'+String(value??"").replaceAll('"','""')+'"';
  const uniqueSubjectNames=rows=>{const seen=new Set(),out=[];for(const row of arr(rows)){const name=String(row?.subject_name||"").trim(),key=name.toLowerCase();if(name&&!seen.has(key)){seen.add(key);out.push(name);}}return out;};
  const localDateValue=(date=new Date())=>{const offset=date.getTimezoneOffset()*60000;return new Date(date.getTime()-offset).toISOString().slice(0,10);};
  const termDate=term=>{const today=localDateValue();if(term?.start_date&&today<term.start_date)return term.start_date;if(term?.end_date&&today>term.end_date)return term.end_date;return today;};

  async function renderTeacherProfile(){
    byId("content").innerHTML=sectionHead("My Teacher Profile","Your official staff details, photograph, qualifications, and current teaching assignments")+loading("Loading teacher profile");
    try{
      const data=await certified("get_my_teacher_profile",{});
      if(!data?.linked){byId("content").innerHTML=sectionHead("My Teacher Profile","Your official staff details, photograph, qualifications, and current teaching assignments")+empty("No linked teacher record. Ask the System Administrator to link your account to a teacher record.");return;}
      const teacher=obj(data.teacher),classes=arr(data.classes),subjects=arr(data.subjects),subjectNames=uniqueSubjectNames(subjects);
      let photo="";
      if(teacher.photo_url){try{photo=URL.createObjectURL(await api().downloadStaffPhoto(teacher.photo_url));}catch{}}
      const metric=(label,value)=>'<div class="metric maturity-metric"><span>'+esc(label)+'</span><strong>'+esc(value==null||value===""?"—":value)+'</strong></div>';
      const field=(label,value)=>'<div class="verify-field"><span>'+esc(label)+'</span><strong>'+esc(value==null||value===""?"—":value)+'</strong></div>';
      byId("content").innerHTML=sectionHead("My Teacher Profile","Your official staff details, photograph, qualifications, and current teaching assignments")+
        '<div class="grid two teacher-profile-layout"><section class="panel pad"><div class="teacher-profile-hero">'+
          (photo?'<img src="'+esc(photo)+'" alt="Teacher photograph">':'<span>'+esc(initials(teacher.full_name))+'</span>')+
          '<div><h3>'+esc(teacher.full_name||"Teacher")+'</h3><p>'+esc(teacher.staff_no||"")+(teacher.emis_code?" • EMIS "+esc(teacher.emis_code):"")+'</p><span class="status published">● '+esc(currentRoleLabel())+'</span></div></div>'+
          '<div class="metric-row wrap">'+metric("Assigned classes",Number(data.assigned_class_count||classes.length||0))+metric("Subject assignments",subjectNames.length)+metric("Qualification",teacher.qualification||"—")+'</div>'+
          '<div class="profile-detail-grid">'+field("Date of birth",formatDate(teacher.date_of_birth))+field("Gender",teacher.gender||"—")+field("Telephone",teacher.phone||"—")+field("Email",teacher.email||teacher.profile_email||"—")+field("Specialization",teacher.specialization||"—")+field("Date joined",formatDate(teacher.date_joined))+'</div></section>'+
        '<section class="panel pad"><div class="section-title"><h4>Profile photograph</h4></div><p class="help-text">Upload or replace your own photograph. Updates appear immediately in the System Administrator teacher directory and future staff ID cards.</p>'+
          '<label class="field"><span>Choose photograph</span><input id="myTeacherPhoto" type="file" accept="image/jpeg,image/png,image/webp"></label><div class="button-row"><button class="button primary" id="myTeacherPhotoSave" type="button">Save / replace photo</button>'+(teacher.photo_url?'<button class="button danger" id="myTeacherPhotoRemove" type="button">Remove current photo</button>':"")+'</div>'+
          '<div class="section-title" style="margin-top:24px"><h4>Assigned classes</h4></div><div class="chip-list">'+(classes.map(row=>'<span class="chip">'+esc(row.name||row.class_name||"Class")+'</span>').join("")||'<span class="muted">No class-teacher assignment</span>')+'</div>'+
          '<div class="section-title" style="margin-top:18px"><h4>Subject assignments</h4></div><div class="chip-list">'+(subjectNames.map(name=>'<span class="chip">'+esc(name)+'</span>').join("")||'<span class="muted">No subject assignment</span>')+'</div></section></div>';
      byId("myTeacherPhotoSave")?.addEventListener("click",async()=>{
        const file=byId("myTeacherPhoto")?.files?.[0];if(!file){notify("Choose a photograph first","Select a JPEG, PNG, or WebP image before saving.","warning");return;}
        const button=byId("myTeacherPhotoSave");button.disabled=true;
        try{
          const uploaded=await api().uploadFile(file,"staff-photos",{subfolder:teacher.id});
          const photoPath=String(uploaded?.referencePath||String(uploaded?.objectKey||"").split("/staff-photos/")[1]||"").trim();
          if(!photoPath)throw new Error("The uploaded photograph reference was not returned.");
          await certified("set_teacher_photo",{target_teacher_id:teacher.id,target_photo_url:photoPath,expected_updated_at:teacher.updated_at||null});
          notify("Profile photograph updated");await renderTeacherProfile();
        }catch(error){notify("Photograph not saved",friendly(error),"error");}
        finally{button.disabled=false;}
      });
      byId("myTeacherPhotoRemove")?.addEventListener("click",async()=>{
        const ok=await window.EdusentiaConfirm("Remove your current profile photograph?");if(!ok)return;
        try{await certified("set_teacher_photo",{target_teacher_id:teacher.id,target_photo_url:"",expected_updated_at:teacher.updated_at||null});notify("Profile photograph removed");await renderTeacherProfile();}
        catch(error){notify("Photograph not removed",friendly(error),"error");}
      });
    }catch(error){byId("content").innerHTML=sectionHead("My Teacher Profile","Your official staff details, photograph, qualifications, and current teaching assignments")+pageError(error);}
  }

  async function renderMyClass(){
    byId("content").innerHTML=sectionHead("My Class","Assigned learners, subjects, and report completion")+loading("Loading class workspace");
    try{
      const data=await certified("get_role_workspace",{}),rows=arr(data?.classes);
      byId("content").innerHTML=sectionHead("My Class","Assigned learners, subjects, and report completion")+
        (rows.length?'<div class="grid two">'+rows.map(item=>{const completion=progress(item.completed_reports,item.expected_reports);return '<section class="panel pad"><div class="panel-header"><div><h3>'+esc(item.class_name||"Class")+'</h3><p>'+Number(item.student_count||0)+' learners • '+Number(item.subject_count||0)+' subjects</p></div><span class="status '+(completion===100?"published":"draft")+'">● '+completion+'% Complete</span></div><div class="metric-row"><div class="metric"><span>Draft or returned</span><strong>'+Number(item.open_reports||0)+'</strong></div><div class="metric"><span>In review</span><strong>'+Number(item.review_reports||0)+'</strong></div><div class="metric"><span>Published</span><strong>'+Number(item.published_reports||0)+'</strong></div></div><div class="progress"><span style="width:'+completion+'%"></span></div><div class="button-row" style="margin-top:15px"><button class="button secondary small" data-workspace-students="'+esc(item.class_id)+'">Students</button><button class="button primary small" data-workspace-reports="'+esc(item.class_id)+'">Report Cards</button></div></section>';}).join("")+'</div>':empty("No assigned class"));
      byId("content").querySelectorAll("[data-workspace-students]").forEach(button=>button.addEventListener("click",()=>{state().studentClassFilter=button.dataset.workspaceStudents;nav("students");}));
      byId("content").querySelectorAll("[data-workspace-reports]").forEach(button=>button.addEventListener("click",()=>{state().reportClassFilter=button.dataset.workspaceReports;nav("reports");}));
    }catch(error){byId("content").innerHTML=sectionHead("My Class","Assigned learners, subjects, and report completion")+pageError(error);}
  }

  async function renderMySubjects(){
    byId("content").innerHTML=sectionHead("My Subjects","Assigned classes and assessment workload")+loading("Loading subject workspace");
    try{
      const data=await certified("get_role_workspace",{}),rows=arr(data?.subjects);
      byId("content").innerHTML=sectionHead("My Subjects","Assigned classes and assessment workload")+
        '<section class="panel"><div class="table-wrap"><table><thead><tr><th>Class</th><th>Subject</th><th>Learners</th><th>Open reports</th><th>Scored</th><th>Progress</th><th></th></tr></thead><tbody>'+
        (rows.length?rows.map(item=>{const completion=progress(item.scored_reports,item.expected_reports);return '<tr><td><strong>'+esc(item.class_name||"Class")+'</strong></td><td><div class="cell-copy"><strong>'+esc(item.subject_name||"Subject")+'</strong><small>'+esc(item.subject_code||"")+'</small></div></td><td>'+Number(item.student_count||0)+'</td><td>'+Number(item.open_reports||0)+'</td><td>'+Number(item.scored_reports||0)+' / '+Number(item.expected_reports||0)+'</td><td><div class="bar-track"><span style="width:'+completion+'%"></span></div><small>'+completion+'%</small></td><td><button class="button primary small" data-subject-reports="'+esc(item.class_id)+'">Report Cards</button></td></tr>';}).join(""):'<tr><td colspan="7"><div class="empty"><strong>No assigned subjects</strong></div></td></tr>')+
        '</tbody></table></div></section>';
      byId("content").querySelectorAll("[data-subject-reports]").forEach(button=>button.addEventListener("click",()=>{state().reportClassFilter=button.dataset.subjectReports;nav("reports");}));
    }catch(error){byId("content").innerHTML=sectionHead("My Subjects","Assigned classes and assessment workload")+pageError(error);}
  }

  const attendanceStatusOptions=selected=>[["present","Present"],["absent","Absent"],["late","Late"],["excused","Excused"]].map(([value,label])=>'<option value="'+value+'" '+(selected===value?"selected":"")+'>'+label+'</option>').join("");
  const attendanceStatusButtons=row=>[["present","Present"],["absent","Absent"],["late","Late"],["excused","Excused"]].map(([value,label])=>'<button type="button" class="attendance-status-button '+(row.attendance_status===value?"active":"")+'" data-attendance-button="'+esc(row.enrollment_id)+'" data-status="'+value+'" aria-pressed="'+String(row.attendance_status===value)+'">'+label+'</button>').join("");
  function attendanceSelector(id){return byId("attendanceResults")?.querySelector('[data-attendance-enrollment="'+String(id).replaceAll('"','\\"')+'"]');}
  function setAttendanceStatus(id,value){
    const root=byId("attendanceResults"),select=attendanceSelector(id);if(!root||!select)return;select.value=value;
    root.querySelectorAll('[data-attendance-button="'+String(id).replaceAll('"','\\"')+'"]').forEach(button=>{const active=button.dataset.status===value;button.classList.toggle("active",active);button.setAttribute("aria-pressed",String(active));});
    updateAttendanceSummary();
  }
  function updateAttendanceSummary(){
    const root=byId("attendanceResults");if(!root)return;
    const counts={present:0,absent:0,late:0,excused:0,unmarked:0},selects=[...root.querySelectorAll("[data-attendance-enrollment]")];
    selects.forEach(select=>{if(select.value&&counts[select.value]!==undefined)counts[select.value]++;else counts.unmarked++;});
    Object.entries(counts).forEach(([key,value])=>{const el=byId("attendanceCount-"+key);if(el)el.textContent=String(value);});
    const disabled=!writable()||counts.unmarked>0||!selects.length;
    for(const id of ["attendanceSave","attendanceSaveTop"]){const b=byId(id);if(b)b.disabled=disabled;}
    const label=byId("attendanceSaveState");if(label)label.textContent=counts.unmarked?counts.unmarked+" student"+(counts.unmarked===1?"":"s")+" unmarked":"All students marked and ready to save";
  }
  async function loadAttendanceRegister(){
    const root=byId("attendanceResults"),a=local.attendance;if(!root||!a.termId||!a.classId||!a.date)return;
    root.innerHTML=loading("Loading attendance register");
    try{
      const data=await certified("get_class_attendance_register",{target_term_id:a.termId,target_class_id:a.classId,target_date:a.date}),rows=arr(data?.students),opened=Number(data?.days_school_opened||0),marked=Boolean(data?.register?.id);
      root.innerHTML='<div class="panel-header attendance-header"><div><h3>'+esc(data?.class?.name||"Assigned Class")+'</h3><p>'+esc(formatDate(a.date))+' • '+(marked?"Attendance already recorded":"New attendance register")+'</p></div><div class="button-row"><button class="button outline small" id="attendanceAllPresent" type="button" '+(rows.length&&writable()?"":"disabled")+'>Mark all present</button><button class="button primary attendance-desktop-save" id="attendanceSaveTop" type="button" '+(rows.length&&writable()?"":"disabled")+'>Save attendance</button></div></div>'+
        '<div class="panel-body attendance-body"><div class="metric-row attendance-summary"><div class="metric"><span>Students</span><strong>'+rows.length+'</strong></div><div class="metric"><span>School days recorded</span><strong>'+opened+'</strong></div><div class="metric"><span>Selected date</span><strong>'+(marked?"Recorded":"Not recorded")+'</strong></div></div>'+
        (rows.length?'<div class="attendance-live-summary" aria-live="polite"><span>Present <b id="attendanceCount-present">0</b></span><span>Absent <b id="attendanceCount-absent">0</b></span><span>Late <b id="attendanceCount-late">0</b></span><span>Excused <b id="attendanceCount-excused">0</b></span><span>Unmarked <b id="attendanceCount-unmarked">0</b></span></div>'+
        '<label class="field attendance-search-field"><span>Find student</span><input id="attendanceSearch" type="search" placeholder="Name or admission number" autocomplete="off"></label>'+
        '<div class="attendance-mobile-list">'+rows.map(row=>'<article class="attendance-student-card" data-attendance-card data-search="'+esc((String(row.full_name||"")+" "+String(row.admission_no||"")).toLowerCase())+'"><div class="attendance-student-identity"><div class="student-avatar-placeholder" aria-hidden="true">'+esc(String(row.full_name||"?").slice(0,1).toUpperCase())+'</div><div><strong>'+esc(row.full_name||"Student")+'</strong><small>'+esc(row.admission_no||"")+(row.roll_number?" • Roll "+esc(row.roll_number):"")+'</small></div></div><div class="attendance-status-buttons">'+attendanceStatusButtons(row)+'</div><div class="attendance-term-total">Term total: <strong>'+Number(row.days_present||0)+' / '+Number(row.days_school_opened||0)+'</strong> days present</div></article>').join("")+'</div>'+
        '<div class="table-wrap attendance-desktop-table"><table><thead><tr><th>Student</th><th>Admission No.</th><th>Daily status</th><th>Term attendance</th></tr></thead><tbody>'+rows.map(row=>'<tr><td><div class="cell-copy"><strong>'+esc(row.full_name||"Student")+'</strong><small>'+(row.roll_number?"Roll "+esc(row.roll_number):"")+'</small></div></td><td>'+esc(row.admission_no||"")+'</td><td><select class="attendance-status-select" data-attendance-enrollment="'+esc(row.enrollment_id)+'">'+attendanceStatusOptions(row.attendance_status||"")+'</select></td><td><strong>'+Number(row.days_present||0)+' / '+Number(row.days_school_opened||0)+'</strong><small class="attendance-term-label"> days present</small></td></tr>').join("")+'</tbody></table></div>'+
        '<label class="field attendance-notes"><span>Attendance note (optional)</span><textarea id="attendanceNotes">'+esc(data?.register?.notes||"")+'</textarea></label><div class="attendance-sticky-save"><div><strong>'+esc(data?.class?.name||"Class attendance")+'</strong><small id="attendanceSaveState">Review all students before saving</small></div><button class="button primary" id="attendanceSave" type="button">Save attendance</button></div>':
        '<div class="empty"><strong>No students found</strong><span>No active students are enrolled in this class for the selected term.</span></div>')+'</div>';
      byId("attendanceAllPresent")?.addEventListener("click",()=>root.querySelectorAll("[data-attendance-enrollment]").forEach(select=>setAttendanceStatus(select.dataset.attendanceEnrollment,"present")));
      byId("attendanceSave")?.addEventListener("click",saveAttendance);byId("attendanceSaveTop")?.addEventListener("click",saveAttendance);
      root.querySelectorAll("[data-attendance-button]").forEach(button=>button.addEventListener("click",()=>setAttendanceStatus(button.dataset.attendanceButton,button.dataset.status)));
      root.querySelectorAll("[data-attendance-enrollment]").forEach(select=>select.addEventListener("change",()=>setAttendanceStatus(select.dataset.attendanceEnrollment,select.value)));
      byId("attendanceSearch")?.addEventListener("input",()=>{const q=String(byId("attendanceSearch")?.value||"").trim().toLowerCase();root.querySelectorAll("[data-attendance-card]").forEach(card=>card.hidden=Boolean(q&&!String(card.dataset.search||"").includes(q)));});
      updateAttendanceSummary();
    }catch(error){root.innerHTML=pageError(error);}
  }
  async function saveAttendance(){
    const root=byId("attendanceResults"),a=local.attendance;if(!root)return;
    const entries=[...root.querySelectorAll("[data-attendance-enrollment]")].map(select=>({enrollment_id:select.dataset.attendanceEnrollment,attendance_status:select.value}));if(!entries.length)return;
    const buttons=[byId("attendanceSave"),byId("attendanceSaveTop")].filter(Boolean);buttons.forEach(b=>{b.disabled=true;b.dataset.oldText=b.textContent;b.textContent="Saving";});
    try{
      const data=await certified("save_class_attendance",{target_term_id:a.termId,target_class_id:a.classId,target_date:a.date,entries,notes_text:String(byId("attendanceNotes")?.value||"").trim()});
      notify("Attendance saved",Number(data?.days_school_opened||0)+" school day"+(Number(data?.days_school_opened||0)===1?"":"s")+" recorded for this term.");await loadAttendanceRegister();
    }catch(error){notify("Attendance not saved",friendly(error),"error");}
    finally{buttons.forEach(b=>{b.disabled=false;b.textContent=b.dataset.oldText||"Save attendance";});}
  }
  async function renderAttendance(){
    byId("content").innerHTML=sectionHead("Class Attendance","Mark daily attendance for your assigned class. Term totals update report cards automatically.")+loading("Loading attendance controls");
    try{
      if(role()!=="class_teacher")throw new Error("Attendance is available only to assigned class teachers");
      const cfg=await academicConfig(),terms=arr(cfg?.terms),termId=local.attendance.termId||terms.find(t=>t.is_active)?.id||terms[0]?.id||"",term=terms.find(t=>String(t.id)===String(termId))||terms[0]||null;
      const classes=termId?arr(await certified("list_my_attendance_classes",{target_term_id:termId})):[];
      let classId=local.attendance.classId;if(!classes.some(x=>String(x.id)===String(classId)))classId=classes[0]?.id||"";
      const today=localDateValue(),maxDate=term?.end_date&&term.end_date<today?term.end_date:today;let date=local.attendance.date||termDate(term);
      if(term?.start_date&&date<term.start_date)date=term.start_date;if(date>maxDate)date=maxDate;
      local.attendance={termId:term?.id||termId,classId,date};
      const options=(rows,selected)=>rows.map(x=>'<option value="'+esc(x.id)+'" '+(String(x.id)===String(selected)?"selected":"")+'>'+esc(x.name||x.class_name||"")+'</option>').join("");
      byId("content").innerHTML=sectionHead("Class Attendance","Mark daily attendance for your assigned class. Term totals update report cards automatically.")+
        '<section class="panel pad"><div class="form-grid three attendance-controls"><label class="field"><span>Academic term</span><select id="attendanceTerm">'+options(terms,local.attendance.termId)+'</select></label><label class="field"><span>Assigned class</span><select id="attendanceClass">'+(classes.length?options(classes,classId):'<option value="">No assigned class</option>')+'</select></label><label class="field"><span>School date</span><input id="attendanceDate" type="date" value="'+esc(date)+'" '+(term?.start_date?'min="'+esc(term.start_date)+'"':"")+' max="'+esc(maxDate)+'"></label></div></section><section class="panel" id="attendanceResults">'+loading("Loading attendance register")+'</section>';
      byId("attendanceTerm").addEventListener("change",()=>{local.attendance.termId=byId("attendanceTerm").value;local.attendance.classId="";local.attendance.date="";renderAttendance();});
      byId("attendanceClass").addEventListener("change",()=>{local.attendance.classId=byId("attendanceClass").value;loadAttendanceRegister();});
      byId("attendanceDate").addEventListener("change",()=>{local.attendance.date=byId("attendanceDate").value;loadAttendanceRegister();});
      if(classId)await loadAttendanceRegister();else byId("attendanceResults").innerHTML='<div class="empty"><strong>No class-teacher assignment</strong><span>Ask the System Administrator to assign you as a class teacher.</span></div>';
    }catch(error){byId("content").innerHTML=sectionHead("Class Attendance","Mark daily attendance for your assigned class. Term totals update report cards automatically.")+pageError(error);}
  }

  async function renderInsights(){
    byId("content").innerHTML=sectionHead("Academic Insights","Privacy-aware class, subject, attendance, and report-completion trends")+loading("Loading academic insights");
    try{
      const cfg=await academicConfig(),terms=arr(cfg?.terms),classes=arr(cfg?.classes),termId=local.insights.termId||terms.find(t=>t.is_active)?.id||terms[0]?.id||"",classId=local.insights.classId||"";
      local.insights={termId,classId};
      if(!termId){byId("content").innerHTML=sectionHead("Academic Insights","Privacy-aware class, subject, attendance, and report-completion trends")+empty("No academic term is configured.");return;}
      const data=await certified("academic_analytics",{target_term_id:termId,target_class_id:classId||null}),summary=obj(data?.summary),subjects=arr(data?.subjects),classRows=arr(data?.classes);
      const termOptions=terms.map(x=>'<option value="'+esc(x.id)+'" '+(String(x.id)===String(termId)?"selected":"")+'>'+esc(x.name||"Term")+'</option>').join("");
      const classOptions='<option value="">All authorised classes</option>'+classes.map(x=>'<option value="'+esc(x.id)+'" '+(String(x.id)===String(classId)?"selected":"")+'>'+esc(x.name||x.class_name||"Class")+'</option>').join("");
      byId("content").innerHTML=sectionHead("Academic Insights","Privacy-aware class, subject, attendance, and report-completion trends",'<button class="button secondary" id="insightsExport" type="button">Export summary</button>')+
        '<section class="panel pad"><div class="form-grid"><label class="field"><span>Term</span><select id="insightsTerm">'+termOptions+'</select></label><label class="field"><span>Class</span><select id="insightsClass">'+classOptions+'</select></label></div></section>'+
        '<section class="stat-grid maturity-stat-grid" style="margin-top:18px">'+stat("blue","◉","Students",n(summary.students))+stat("purple","▤","Reports",n(summary.reports))+stat("gold","%","Average",n(summary.average,1)+"%")+stat("green","✓","Attendance",n(summary.attendance_rate,1)+"%")+'</section>'+
        '<div class="grid two maturity-grid"><section class="panel pad"><div class="section-title"><h4>Subject performance</h4></div>'+
          (subjects.length?'<div class="bar-list analytics-bars">'+subjects.map(item=>{const avg=Math.max(0,Math.min(100,Number(item.average||0)));return '<div class="bar-item"><label><strong>'+esc(item.subject_name||"Subject")+'</strong><small>'+Number(item.scored||0)+' records • '+n(item.lowest,1)+'–'+n(item.highest,1)+'</small></label><div class="bar-track"><span style="width:'+avg+'%"></span></div><b>'+n(item.average,1)+'%</b></div>';}).join("")+'</div>':empty("No subject results"))+
        '</section><section class="panel pad"><div class="section-title"><h4>Class overview</h4></div>'+
          (classRows.length?'<div class="table-wrap"><table><thead><tr><th>Class</th><th>Students</th><th>Average</th><th>Attendance</th><th>Published</th></tr></thead><tbody>'+classRows.map(item=>'<tr><td>'+esc(item.class_name||"Class")+'</td><td>'+Number(item.students||0)+'</td><td>'+n(item.average,1)+'%</td><td>'+n(item.attendance_rate,1)+'%</td><td>'+Number(item.published||0)+'</td></tr>').join("")+'</tbody></table></div>':empty("No class analytics"))+
        '</section></div>';
      byId("insightsTerm").addEventListener("change",()=>{local.insights.termId=byId("insightsTerm").value;local.insights.classId=byId("insightsClass").value;renderInsights();});
      byId("insightsClass").addEventListener("change",()=>{local.insights.classId=byId("insightsClass").value;renderInsights();});
      byId("insightsExport").addEventListener("click",()=>{const lines=[["class","students","average","attendance_rate","published"].join(","),...classRows.map(item=>[item.class_name,item.students,item.average,item.attendance_rate,item.published].map(csv).join(","))];downloadBlob("academic-insights.csv",new Blob([lines.join("\n")],{type:"text/csv;charset=utf-8"}));});
    }catch(error){byId("content").innerHTML=sectionHead("Academic Insights","Privacy-aware class, subject, attendance, and report-completion trends")+pageError(error);}
  }

  registerView({id:"teacher_profile",label:"My Profile",icon:"♙",subtitle:"Teacher profile, photograph, qualifications, and assignments",roles:["class_teacher","subject_teacher"],render:renderTeacherProfile});
  registerView({id:"my_class",label:"My Class",icon:"▣",subtitle:"Assigned class, learners, and report progress",roles:["class_teacher"],render:renderMyClass});
  registerView({id:"attendance",label:"Attendance",icon:"✓",subtitle:"Daily class attendance and automatic term totals",roles:["class_teacher"],feature:"attendance",render:renderAttendance});
  registerView({id:"my_subjects",label:"My Subjects",icon:"⌘",subtitle:"Assigned subjects, classes, and assessment progress",roles:["class_teacher","subject_teacher"],render:renderMySubjects});
  registerView({id:"insights",label:"Insights",icon:"◩",subtitle:"Performance, attendance, completion, and class trends",roles:["system_admin","principal","class_teacher","subject_teacher"],feature:"analytics",render:renderInsights});
})();
