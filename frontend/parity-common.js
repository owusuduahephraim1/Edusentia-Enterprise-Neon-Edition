(() => {
  "use strict";
  const shell=window.EdusentiaShell;
  if(!shell)return;
  if(!shell)return;
  const {registerView,api,certified,role,escapeHtml:esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly}=shell;
  const currentRole=()=>role();
  const isSystemAdmin=()=>currentRole()==="system_admin";
  const modal=()=>byId("modal");

  function openModal(title,subtitle,body,footer=""){
    byId("modalTitle").textContent=title||"";
    byId("modalSubtitle").textContent=subtitle||"";
    byId("modalBody").innerHTML=body||"";
    byId("modalFooter").innerHTML=footer||"";
    const d=modal();if(typeof d?.showModal==="function")d.showModal();else d?.setAttribute("open","");
    return d;
  }
  function closeModal(){const d=modal();if(typeof d?.close==="function")d.close();else d?.removeAttribute("open");}
  function formValues(form){return Object.fromEntries(new FormData(form).entries());}
  function optionRows(rows,valueKey,labelKey,selected="",blank="Select"){
    return `<option value="">${esc(blank)}</option>`+(rows||[]).map(row=>`<option value="${esc(row[valueKey]||"")}" ${String(row[valueKey]||"")===String(selected||"")?"selected":""}>${esc(row[labelKey]||row.name||"")}</option>`).join("");
  }
  function yesNo(value){return value?'<span class="status active">Yes</span>':'<span class="status inactive">No</span>';}
  function showMessage(id,text,kind="error"){const el=byId(id);if(!el)return;el.textContent=text||"";el.classList.toggle("hidden",!text);el.dataset.kind=kind;}
  function downloadBlob(name,blob){const url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  function safeName(value){return String(value||"file").replace(/[^A-Za-z0-9._-]+/g,"-").replace(/^-+|-+$/g,"").slice(0,100)||"file";}
  async function sha256(blob){const bytes=await blob.arrayBuffer(),digest=await crypto.subtle.digest("SHA-256",bytes);return [...new Uint8Array(digest)].map(x=>x.toString(16).padStart(2,"0")).join("");}
  function csvParse(text){
    const rows=[];let row=[],cell="",quoted=false;
    for(let i=0;i<String(text||"").length;i++){
      const ch=text[i],next=text[i+1];
      if(ch==='"'&&quoted&&next==='"'){cell+='"';i++;continue;}
      if(ch==='"'){quoted=!quoted;continue;}
      if(ch===","&&!quoted){row.push(cell);cell="";continue;}
      if((ch==="\n"||ch==="\r")&&!quoted){if(ch==="\r"&&next==="\n")i++;row.push(cell);cell="";if(row.some(v=>String(v).trim()!==""))rows.push(row);row=[];continue;}
      cell+=ch;
    }
    row.push(cell);if(row.some(v=>String(v).trim()!==""))rows.push(row);
    if(rows.length<2)return [];
    const headers=rows[0].map(v=>String(v).trim().toLowerCase().replace(/\s+/g,"_"));
    return rows.slice(1).map(values=>Object.fromEntries(headers.map((h,i)=>[h,String(values[i]??"").trim()])));
  }

  async function certifiedAllRows(name,args={},maxPages=500){
    const rows=[];let page=1,last={};
    while(page<=maxPages){
      const data=await certified(name,{...args,page_number:page,page_size:100})||{};
      const batch=Array.isArray(data.rows)?data.rows:[];rows.push(...batch);last=data;
      const totalRaw=data.total,total=totalRaw===null||totalRaw===undefined||totalRaw===""?Number.NaN:Number(totalRaw);
      if(!batch.length||(Number.isFinite(total)&&rows.length>=total)||batch.length<100){
        return {...last,rows,total:Number.isFinite(total)?total:rows.length};
      }
      page+=1;
    }
    throw new Error("The "+name+" result exceeded the safe pagination limit. Narrow the search and try again.");
  }

  async function academicConfig(){
    if(isSystemAdmin())return certified("get_academic_configuration");
    const boot=window.EdusentiaShell?.state?.boot||await api().bootstrap();
    return {
      academic_years:Array.isArray(boot?.academic_years)?boot.academic_years:[],
      terms:Array.isArray(boot?.terms)?boot.terms:[],
      classes:Array.isArray(boot?.classes)?boot.classes:[],
      subjects:Array.isArray(boot?.subjects)?boot.subjects:[],
      class_subjects:[],
      grading_scales:[],
      assessment_schemes:[]
    };
  }

  window.EdusentiaParity=Object.freeze({
    registerView,api,certified,certifiedAllRows,role,esc,status,formatDate,formatDateTime,formatAmount,loading,empty,pageError,byId,friendly,
    currentRole,isSystemAdmin,modal,openModal,closeModal,formValues,optionRows,yesNo,showMessage,downloadBlob,safeName,sha256,csvParse,academicConfig
  });
})();
