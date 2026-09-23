(()=>{
  "use strict";
  if(window.EDS_INSTITUTION_ACADEMICS_V1)return;
  window.EDS_INSTITUTION_ACADEMICS_V1=true;

  let activeTab="";
  let renderToken=0;
  let observerTimer=0;
  const byId=id=>document.getElementById(id);
  const esc=value=>String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[ch]));
  const api=()=>window.EdusentiaApi;
  const institutionType=()=>String(window.EdusentiaShell?.state?.boot?.tenant?.institution_type||window.EDS_MASTER_CONFIG?.institutionType||"basic_jhs");
  function academicPage(){return String(document.querySelector("#content .page-head h3")?.textContent||"").trim()==="Academic Configuration"}
  function notify(text,kind="info"){if(typeof window.EdusentiaNotify==="function"){window.EdusentiaNotify(kind==="error"?"Senior High workspace":"Senior High academic workspace",text,kind);return}let root=byId("institutionAcademicsToast");if(!root){root=document.createElement("div");root.id="institutionAcademicsToast";root.className="toast-stack";document.body.append(root)}const el=document.createElement("div");el.className=`toast ${kind}`;el.textContent=text;root.append(el);setTimeout(()=>el.remove(),4500)}
  function fail(error){console.error("institution_academics",error);notify(String(error?.message||error).replaceAll("_"," "),"error")}
  async function run(task,success){try{await task();if(success)notify(success,"success");await renderActive()}catch(error){fail(error)}}
  function val(form,name){return String(new FormData(form).get(name)||"").trim()}
  function num(form,name){const raw=val(form,name);return raw===""?null:Number(raw)}
  function checked(form,name){return new FormData(form).get(name)==="on"}
  function optionRows(items,value="id",label="name",selected="",blank="Select…"){return `${blank!==null?`<option value="">${esc(blank)}</option>`:""}${items.map(item=>`<option value="${esc(item[value])}" ${String(item[value])===String(selected)?"selected":""}>${esc(item[label]??item[value])}</option>`).join("")}`}
  function table(headers,body,empty="No records yet."){return `<div class="table-wrap"><table><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${body||`<tr><td colspan="${headers.length}" class="muted">${esc(empty)}</td></tr>`}</tbody></table></div>`}
  function panel(title,subtitle,body,actions=""){return `<section class="panel pad institution-academic-panel"><div class="section-title"><div><h4>${esc(title)}</h4><p class="help-text">${esc(subtitle)}</p></div>${actions}</div>${body}</section>`}
  function editor(title,fields,button="Save"){return `<form class="institution-inline-form form-stack"><h5>${esc(title)}</h5><div class="form-grid">${fields}</div><div class="button-row"><button class="button primary small" type="submit">${esc(button)}</button></div></form>`}
  function field(name,label,input,wide=false){return `<label class="field ${wide?"full":""}"><span>${esc(label)}</span>${input.replace("__NAME__",esc(name))}</label>`}
  function textInput(name,required=true,placeholder=""){return `<input name="${esc(name)}" ${required?"required":""} placeholder="${esc(placeholder)}">`}
  function numberInput(name,required=true,step="1",min="0"){return `<input name="${esc(name)}" type="number" ${required?"required":""} step="${esc(step)}" min="${esc(min)}">`}
  function selectInput(name,html,required=true){return `<select name="${esc(name)}" ${required?"required":""}>${html}</select>`}
  function checkboxInput(name,label="Active",checkedValue=true){return `<label class="check-field"><input name="${esc(name)}" type="checkbox" ${checkedValue?"checked":""}><span>${esc(label)}</span></label>`}

  function ensureTabs(){
    if(!academicPage()||institutionType()!=="senior_high")return;
    const tabs=document.querySelector("#content .tabs");if(!tabs)return;
    const id="shs-programmes",label="SHS Programmes";
    let button=tabs.querySelector(`[data-institution-academic-tab="${id}"]`);
    if(!button){button=document.createElement("button");button.type="button";button.className="tab";button.dataset.institutionAcademicTab=id;button.textContent=label;tabs.append(button)}
    button.classList.toggle("active",activeTab===id);
    if(activeTab){tabs.querySelectorAll("[data-academic-tab]").forEach(coreButton=>coreButton.classList.remove("active"))}
  }
  function installStyles(){if(byId("institutionAcademicsStyles"))return;const style=document.createElement("style");style.id="institutionAcademicsStyles";style.textContent=`
    .institution-academic-stack{display:grid;gap:16px}.institution-academic-panel{overflow:hidden}.institution-inline-form{border:1px solid var(--border,#d8dee9);border-radius:12px;padding:14px;margin:12px 0;background:rgba(255,255,255,.72)}.institution-inline-form h5{margin:0 0 10px}.institution-academic-panel .table-wrap{overflow:auto}.institution-academic-panel table{width:100%;border-collapse:collapse}.institution-academic-panel th,.institution-academic-panel td{padding:9px 10px;border-bottom:1px solid var(--border,#e5e7eb);text-align:left;vertical-align:top}.institution-academic-panel .row-actions{display:flex;gap:6px;flex-wrap:wrap}.institution-academic-panel .muted{color:var(--muted,#64748b)}.institution-inline-form .form-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px}.institution-inline-form .full{grid-column:1/-1}@media(max-width:720px){.institution-inline-form .form-grid{grid-template-columns:1fr}}
  `;document.head.append(style)}

  async function renderSHS(){
    const data=await api().shsAcademicConsole();
    const programmes=Array.isArray(data?.programmes)?data.programmes:[];
    const levels=Array.isArray(data?.levels)?data.levels:[];
    const subjects=Array.isArray(data?.subjects)?data.subjects:[];
    const years=Array.isArray(data?.years)?data.years:[];
    const students=Array.isArray(data?.students)?data.students:[];
    const shsEnrollments=Array.isArray(data?.enrollments)?data.enrollments:[];
    const mappings=Array.isArray(data?.mappings)?data.mappings:[];
    const levelById=new Map(levels.map(x=>[x.id,x])),programmeById=new Map(programmes.map(x=>[x.id,x])),subjectById=new Map(subjects.map(x=>[x.id,x])),studentById=new Map(students.map(x=>[x.id,x])),yearById=new Map(years.map(x=>[x.id,x]));
    const root=byId("academicPanel");if(!root)return;
    const programmeRows=programmes.map(p=>`<tr><td><strong>${esc(p.name)}</strong><br><small>${esc(p.code)}</small></td><td>${esc(p.award_type||"SHS programme")}</td><td>${levels.filter(l=>l.programme_id===p.id).map(l=>esc(l.name)).join(", ")||"—"}</td><td class="row-actions"><button class="button ghost small" data-delete-programme="${p.id}">Delete</button></td></tr>`).join("");
    const mappingRows=mappings.map(m=>`<tr><td>${esc(programmeById.get(m.programme_id)?.name||"—")}</td><td>${esc(levelById.get(m.level_id)?.name||"All levels")}</td><td>${esc(subjectById.get(m.subject_id)?.name||"—")}</td><td>${esc(m.subject_category)}</td><td>${m.required?"Required":"Optional"}</td><td class="row-actions"><button class="button ghost small" data-delete-mapping="${m.id}">Remove</button></td></tr>`).join("");
    const enrollmentRows=shsEnrollments.map(e=>{const student=studentById.get(e.student_id);return `<tr><td>${esc(student?`${student.first_name} ${student.last_name}`:"—")}<br><small>${esc(student?.admission_no||"")}</small></td><td>${esc(programmeById.get(e.programme_id)?.name||"—")}</td><td>${esc(levelById.get(e.level_id)?.name||"—")}</td><td>${esc(yearById.get(e.academic_year_id)?.name||"—")}</td><td>${esc(e.status)}</td><td class="row-actions"><button class="button ghost small" data-delete-enrollment="${e.id}">Remove</button></td></tr>`}).join("");
    root.innerHTML=`<div class="institution-academic-stack">
      ${panel("SHS Programme Structure","Create the institution's own programmes or tracks. Edusentia does not impose a national programme list.",editor("Add programme",field("code","Programme code",textInput("code"))+field("name","Programme name",textInput("name"))+field("award_type","Award / description",textInput("award_type",false))+field("duration_years","Duration (years)",numberInput("duration_years",false,"0.5","0.5")),"Add programme")+table(["Programme","Type","Levels",""],programmeRows))}
      ${panel("Programme Levels","Define SHS 1/2/3 or another institution-approved level structure.",editor("Add level",field("programme_id","Programme",selectInput("programme_id",optionRows(programmes)))+field("code","Level code",textInput("code"))+field("name","Level name",textInput("name"))+field("level_order","Order",numberInput("level_order",true,"1","1")),"Add level")+table(["Programme","Code","Level","Order",""],levels.map(l=>`<tr><td>${esc(programmeById.get(l.programme_id)?.name||"—")}</td><td>${esc(l.code)}</td><td>${esc(l.name)}</td><td>${Number(l.level_order)}</td><td class="row-actions"><button class="button ghost small" data-delete-level="${l.id}">Delete</button></td></tr>`).join("")))}
      ${panel("Programme Subjects","Map existing Edusentia subjects to each SHS programme as core, elective or optional.",editor("Assign subject",field("programme_id","Programme",selectInput("programme_id",optionRows(programmes)))+field("level_id","Level (optional)",selectInput("level_id",optionRows(levels),false))+field("subject_id","Subject",selectInput("subject_id",optionRows(subjects)))+field("subject_category","Category",selectInput("subject_category",`<option value="core">Core</option><option value="elective">Elective</option><option value="optional">Optional</option>`))+checkboxInput("required","Required",true),"Assign subject")+table(["Programme","Level","Subject","Category","Requirement",""],mappingRows))}
      ${panel("Student Programme Assignment","Assign learners to an SHS programme, academic year and level while preserving the existing class/report-card workflow.",editor("Assign student",field("student_id","Student",selectInput("student_id",`<option value="">Select…</option>${students.map(s=>`<option value="${s.id}">${esc(`${s.admission_no} — ${s.first_name} ${s.last_name}`)}</option>`).join("")}`))+field("programme_id","Programme",selectInput("programme_id",optionRows(programmes)))+field("academic_year_id","Academic year",selectInput("academic_year_id",optionRows(years)))+field("level_id","Level",selectInput("level_id",optionRows(levels)))+field("status","Status",selectInput("status",`<option>active</option><option>completed</option><option>withdrawn</option><option>deferred</option><option>suspended</option>`)),"Assign student")+table(["Student","Programme","Level","Academic year","Status",""],enrollmentRows))}
    </div>`;
    const forms=root.querySelectorAll("form.institution-inline-form");
    forms[0]?.addEventListener("submit",ev=>{ev.preventDefault();const form=ev.currentTarget;run(()=>api().shsAcademicInsert("programme",{code:val(form,"code"),name:val(form,"name"),award_type:val(form,"award_type"),duration_years:num(form,"duration_years")}),"Programme added")});
    forms[1]?.addEventListener("submit",ev=>{ev.preventDefault();const form=ev.currentTarget;run(()=>api().shsAcademicInsert("level",{programme_id:val(form,"programme_id"),code:val(form,"code"),name:val(form,"name"),level_order:num(form,"level_order")}),"Level added")});
    forms[2]?.addEventListener("submit",ev=>{ev.preventDefault();const form=ev.currentTarget;run(()=>api().shsAcademicInsert("mapping",{programme_id:val(form,"programme_id"),level_id:val(form,"level_id")||null,subject_id:val(form,"subject_id"),subject_category:val(form,"subject_category"),required:checked(form,"required")}),"Subject assigned")});
    forms[3]?.addEventListener("submit",ev=>{ev.preventDefault();const form=ev.currentTarget;run(()=>api().shsAcademicInsert("enrollment",{student_id:val(form,"student_id"),programme_id:val(form,"programme_id"),academic_year_id:val(form,"academic_year_id"),level_id:val(form,"level_id")||null,status:val(form,"status")}),"Student programme assigned")});
    const bindDelete=(selector,entity,label)=>root.querySelectorAll(selector).forEach(button=>button.onclick=async()=>{const id=button.dataset[Object.keys(button.dataset)[0]];const confirmAction=window.EdusentiaConfirm||window.EdusentiaShell?.confirmAction;if(typeof confirmAction!=="function")return;if(!await confirmAction(`Remove this ${label} from the Senior High academic structure?`,{title:`Remove ${label}`,confirmLabel:"Remove",kind:"danger"}))return;run(()=>api().shsAcademicRemove(entity,id),`${label.charAt(0).toUpperCase()+label.slice(1)} removed`)});
    bindDelete("[data-delete-programme]","programme","programme");
    bindDelete("[data-delete-level]","level","level");
    bindDelete("[data-delete-mapping]","mapping","subject mapping");
    bindDelete("[data-delete-enrollment]","enrollment","student programme assignment");
  }

  async function renderActive(){
    if(!academicPage()||institutionType()!=="senior_high"||activeTab!=="shs-programmes")return;
    ensureTabs();const root=byId("academicPanel");if(!root)return;
    const token=++renderToken;root.innerHTML=`<div class="panel pad"><div class="skeleton"></div></div>`;
    try{await renderSHS()}catch(error){if(token===renderToken){root.innerHTML=`<div class="panel pad"><h4>Senior High academic workspace unavailable</h4><p class="help-text">${esc(error?.message||error)}</p></div>`;fail(error)}}
  }

  function attach(){
    if(!academicPage()||institutionType()!=="senior_high"){activeTab="";return}
    installStyles();ensureTabs();
    document.querySelectorAll("[data-institution-academic-tab]").forEach(button=>{if(button.dataset.boundInstitutionTab)return;button.dataset.boundInstitutionTab="1";button.addEventListener("click",ev=>{ev.preventDefault();ev.stopPropagation();activeTab="shs-programmes";ensureTabs();renderActive()})});
    document.querySelectorAll("[data-academic-tab]").forEach(button=>{if(button.dataset.boundInstitutionReset)return;button.dataset.boundInstitutionReset="1";button.addEventListener("click",()=>{activeTab="";ensureTabs()},true)})
  }
  const observer=new MutationObserver(()=>{clearTimeout(observerTimer);observerTimer=setTimeout(()=>{if(academicPage())attach();else activeTab=""},80)});
  observer.observe(document.documentElement,{subtree:true,childList:true});
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",attach,{once:true});else attach();
})();
