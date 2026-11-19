/* Principal attendance navigator: protected class, academic period, week-range filters and PDF export. */
(() => {
  "use strict";
  if(window.__EDUSENTIA_PRINCIPAL_ATTENDANCE_NAVIGATOR__)return;
  window.__EDUSENTIA_PRINCIPAL_ATTENDANCE_NAVIGATOR__=true;
  const P=window.EdusentiaParity,S=window.EdusentiaShell;
  if(!P||!S)return;
  const {registerView,certified,academicConfig,byId,esc,loading,empty,pageError,formatDate,friendly}=P;
  const persist={yearId:"",termId:"",classId:"",fromWeek:"",toWeek:""};
  const arr=x=>Array.isArray(x)?x:[];
  const monday=value=>{
    if(!/^\d{4}-\d{2}-\d{2}$/.test(String(value||"")))return "";
    const date=new Date(value+"T12:00:00Z");
    date.setUTCDate(date.getUTCDate()-(date.getUTCDay()||7)+1);
    return date.toISOString().slice(0,10);
  };
  const addDays=(value,days)=>{
    const date=new Date(value+"T12:00:00Z");date.setUTCDate(date.getUTCDate()+days);
    return date.toISOString().slice(0,10);
  };
  const today=()=>{const date=new Date();return date.getFullYear()+"-"+String(date.getMonth()+1).padStart(2,"0")+"-"+String(date.getDate()).padStart(2,"0");};
  const options=(rows,chosen)=>rows.map(row=>'<option value="'+esc(row.id)+'" '+(String(chosen)===String(row.id)?"selected":"")+'>'+esc(row.name||row.class_name||"")+'</option>').join("");
  const weeksOf=term=>{
    if(!/^\d{4}-\d{2}-\d{2}$/.test(term?.start_date||"")||!/^\d{4}-\d{2}-\d{2}$/.test(term?.end_date||""))return [];
    const first=monday(term.start_date),last=monday(term.end_date),out=[];
    for(let d=first,i=1;d<=last&&i<=54;d=addDays(d,7),i++){
      const weekStart=term.start_date>d?term.start_date:d;
      const friday=addDays(d,4);
      const weekEnd=term.end_date<friday?term.end_date:friday;
      // Do not offer a calendar week with no teaching days (e.g., a term starting on Sunday).
      if(weekStart<=weekEnd)out.push({week_start:d,week_number:i,start_date:weekStart,end_date:weekEnd});
    }
    return out;
  };
  function weekOptions(weeks,value){
    return weeks.map(w=>'<option value="'+esc(w.week_start)+'" '+(w.week_start===value?"selected":"")+'>'+
      'Week '+w.week_number+' · '+esc(formatDate(w.start_date))+' to '+esc(formatDate(w.end_date))+'</option>').join("");
  }
  async function renderAttendanceNavigator(){
    byId("content").innerHTML='<div class="page-head"><div><h3>Attendance Records</h3><p>Review and export class attendance by academic year, term and teaching week.</p></div></div>'+loading("Loading attendance records");
    try{
      if(S.role()!=="principal")throw new Error("The Attendance Records is reserved for the Principal");
      const config=await academicConfig();
      const years=arr(config?.academic_years),terms=arr(config?.terms);
      const activeYear=years.find(x=>x.is_active)||years[0];
      let yearId=persist.yearId;
      if(!years.some(y=>String(y.id)===String(yearId)))yearId=activeYear?.id||"";
      const availableTerms=terms.filter(t=>String(t.academic_year_id)===String(yearId));
      let term=availableTerms.find(t=>String(t.id)===String(persist.termId))||
        availableTerms.find(t=>t.is_active)||availableTerms[0];
      persist.yearId=yearId;persist.termId=term?.id||"";
      if(!term){
        byId("content").innerHTML='<div class="page-head"><div><h3>Attendance Records</h3></div></div>'+
          empty("Configure an academic year and term with opening and closing dates first.");
        return;
      }
      const available=arr(await certified("list_attendance_export_classes",{target_term_id:term.id}));
      let clazz=available.find(x=>String(x.id)===String(persist.classId))||available[0];
      persist.classId=clazz?.id||"";
      const weeks=weeksOf(term);
      const current=monday(today());
      const defaultTo=weeks.findLast(w=>w.week_start<=current)?.week_start||weeks[0]?.week_start||"";
      if(!weeks.some(w=>w.week_start===persist.toWeek))persist.toWeek=defaultTo;
      if(!weeks.some(w=>w.week_start===persist.fromWeek)||persist.fromWeek>persist.toWeek)persist.fromWeek=weeks[0]?.week_start||"";
      const yearOptions=options(years,yearId);
      byId("content").innerHTML=
        '<div class="page-head"><div><h3>Attendance Records</h3><p>Official boys and girls attendance registers, weekly tallies and cumulative term totals.</p></div></div>'+
        '<section class="panel pad"><div class="section-title"><h4>Filter attendance records</h4><span class="chip">Principal oversight</span></div>'+
        '<div class="form-grid three attendance-navigator-controls">'+
        '<label class="field"><span>Academic year</span><select id="navigatorYear">'+yearOptions+'</select></label>'+
        '<label class="field"><span>Academic term</span><select id="navigatorTerm">'+options(availableTerms,term.id)+'</select></label>'+
        '<label class="field"><span>Class</span><select id="navigatorClass">'+(available.length?options(available,clazz?.id):'<option value="">No classes available</option>')+'</select></label>'+
        '<label class="field"><span>From week</span><select id="navigatorFromWeek">'+weekOptions(weeks,persist.fromWeek)+'</select></label>'+
        '<label class="field"><span>Through week</span><select id="navigatorToWeek">'+weekOptions(weeks,persist.toWeek)+'</select></label>'+
        '</div>'+
        '<div class="attendance-navigator-info"><strong>Report format</strong><p>School report-card header, Monday to Friday tally marks (I, 0, I(L), E), separate boys and girls sections, weekly and cumulative totals and attendance percentages.</p>'+
        '<p class="muted">Public holidays and closure days are excluded. Unrecorded days are not absences. Gender values not classified as male or female appear in a separate review section.</p></div>'+
        '<div class="page-actions"><button type="button" class="button primary" id="navigatorDownload" '+(clazz&&weeks.length?"":"disabled")+'>Download attendance PDF</button>'+
        '<button type="button" class="button outline" id="navigatorTermToDate" '+(clazz&&weeks.length?"":"disabled")+'>Download term-to-date PDF</button></div>'+
        '<p id="navigatorMessage" class="form-message" role="status" aria-live="polite"></p></section>'+
        '<section class="panel pad" id="navigatorSummary"><div class="section-title"><h4>Selected register</h4></div>'+
        (clazz?'<div class="metric-row wrap"><div class="metric"><span>Class</span><strong>'+esc(clazz.name||"")+'</strong></div>'+
        '<div class="metric"><span>Main Class Teacher</span><strong>'+esc(clazz.main_teacher||"Not assigned")+'</strong></div>'+
        '<div class="metric"><span>Selected term</span><strong>'+esc(term.name||"")+'</strong></div></div>':
          '<p class="muted">There are no active classes to export.</p>')+
        '</section>';
      byId("navigatorYear")?.addEventListener("change",()=>{persist.yearId=byId("navigatorYear").value;persist.termId="";persist.classId="";persist.fromWeek="";persist.toWeek="";renderAttendanceNavigator();});
      byId("navigatorTerm")?.addEventListener("change",()=>{persist.termId=byId("navigatorTerm").value;persist.classId="";persist.fromWeek="";persist.toWeek="";renderAttendanceNavigator();});
      byId("navigatorClass")?.addEventListener("change",()=>{persist.classId=byId("navigatorClass").value;renderAttendanceNavigator();});
      byId("navigatorFromWeek")?.addEventListener("change",()=>{
        persist.fromWeek=byId("navigatorFromWeek").value;
        if(persist.fromWeek>persist.toWeek){persist.toWeek=persist.fromWeek;byId("navigatorToWeek").value=persist.toWeek;}
      });
      byId("navigatorToWeek")?.addEventListener("change",()=>{
        persist.toWeek=byId("navigatorToWeek").value;
        if(persist.toWeek<persist.fromWeek){persist.fromWeek=persist.toWeek;byId("navigatorFromWeek").value=persist.fromWeek;}
      });
      async function exportPdf(entireTerm){
        const button=byId(entireTerm?"navigatorTermToDate":"navigatorDownload"),message=byId("navigatorMessage");
        const classId=byId("navigatorClass")?.value,termId=byId("navigatorTerm")?.value;
        const from=entireTerm?weeks[0]?.week_start:byId("navigatorFromWeek")?.value;
        const to=entireTerm?defaultTo:byId("navigatorToWeek")?.value;
        if(!classId||!from||!to){message.textContent="Choose a class and a valid date range.";return;}
        const previous=button.textContent;
        button.disabled=true;button.textContent="Preparing official PDF...";
        try{
          const data=await certified("get_attendance_register_export",{
            target_term_id:termId,target_class_id:classId,target_through_week_start:to
          });
          if(!data?.weeks?.length)throw new Error("No attendance weeks were returned for this class.");
          const name=await window.EdusentiaAttendancePdf.download(data,{fromWeek:from,toWeek:to});
          message.dataset.kind="success";message.textContent="Attendance PDF downloaded: "+name;
        }catch(error){
          message.dataset.kind="error";message.textContent=friendly(error);
        }finally{if(button.isConnected){button.disabled=false;button.textContent=previous;}}
      }
      byId("navigatorDownload")?.addEventListener("click",()=>exportPdf(false));
      byId("navigatorTermToDate")?.addEventListener("click",()=>exportPdf(true));
    }catch(error){
      byId("content").innerHTML='<div class="page-head"><div><h3>Attendance Records</h3></div></div>'+pageError(error);
    }
  }
  registerView({id:"attendance_navigator",label:"Attendance Records",icon:"▤",
    subtitle:"Class-level weekly and cumulative attendance PDF reports",roles:["principal"],
    feature:"attendance",render:renderAttendanceNavigator});
})();