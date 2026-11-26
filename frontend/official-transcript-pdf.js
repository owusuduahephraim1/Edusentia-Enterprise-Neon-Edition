/* Edusentia official academic transcript. Read-only renderer for issued, frozen snapshots.
   The caller supplies the existing authenticated image, QR and PDF primitives. */
(()=>{
  "use strict";
  const WIDTH=1240,HEIGHT=1754,LEFT=68,RIGHT=1172,CONTENT_BOTTOM=1470;
  const validUuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const safe=value=>String(value??"").replace(/\s+/g," ").trim();
  const number=(value,digits=1)=>{
    if(value===null||value===undefined||value==="")return "—";
    const n=Number(value);
    return Number.isFinite(n)?n.toFixed(digits):"—";
  };
  const date=value=>safe(value).slice(0,10)||"—";
  const label=value=>safe(value).replace(/_/g," ").replace(/\b\w/g,char=>char.toUpperCase());
  function fit(ctx,value,maxWidth,size,min=15,weight="bold",family="Arial, sans-serif"){
    let font="";
    do{
      font=weight+" "+size+"px "+family;
      ctx.font=font;
      if(ctx.measureText(value).width<=maxWidth||size<=min)break;
      size-=2;
    }while(true);
    return font;
  }
  function wrap(ctx,value,maxWidth,maxLines=5){
    const text=safe(value);
    if(!text)return ["—"];
    const words=text.split(" "),lines=[];let current="";
    const put=word=>{
      const next=current?current+" "+word:word;
      if(ctx.measureText(next).width<=maxWidth){current=next;return;}
      if(current){lines.push(current);current="";}
      if(ctx.measureText(word).width<=maxWidth){current=word;return;}
      let fragment="";
      for(const char of word){
        if(fragment&&ctx.measureText(fragment+char).width>maxWidth){lines.push(fragment);fragment=char;}
        else fragment+=char;
      }
      current=fragment;
    };
    words.forEach(put);
    if(current)lines.push(current);
    if(lines.length>maxLines){
      const kept=lines.slice(0,maxLines),last=kept.length-1;
      while(kept[last]&&ctx.measureText(kept[last]+"…").width>maxWidth)
        kept[last]=kept[last].slice(0,-1);
      kept[last]+="…";
      return kept;
    }
    return lines;
  }
  function rounded(ctx,x,y,w,h,fill,stroke){
    ctx.fillStyle=fill;ctx.fillRect(x,y,w,h);
    if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=1.5;ctx.strokeRect(x,y,w,h);}
  }
  async function render(issuance,deps){
    if(!issuance||issuance.status!=="valid")
      throw new Error("Only the current valid issued transcript can be downloaded as an official PDF.");
    if(!issuance.transcript_number||!validUuid.test(String(issuance.verification_token||"")))
      throw new Error("This issuance is missing its official transcript number or verification token.");
    const snapshot=issuance.snapshot;
    if(!snapshot||typeof snapshot!=="object"||Array.isArray(snapshot))
      throw new Error("The frozen issued transcript snapshot is missing. Reissue only through the authorized school workflow.");
    const student=snapshot.student||{},school=snapshot.school||{},principal=snapshot.principal||{};
    const records=Array.isArray(snapshot.academic_records)?snapshot.academic_records:[];
    const events=Array.isArray(snapshot.lifecycle)?snapshot.lifecycle:[];
    const summary=snapshot.summary||{};
    if(!student.id||!safe(student.full_name)||!safe(school.school_name)||!records.length)
      throw new Error("The issued snapshot lacks the student, school, or published academic records.");
    if(safe(snapshot.source_policy)!=="latest_currently_valid_published_report_per_term")
      throw new Error("The issued transcript uses an unsupported academic source policy.");
    const signingPath=safe(principal.signature_path);
    if(!signingPath)throw new Error("No Principal signature was frozen with this transcript issuance. Contact the Principal before issuing another official transcript.");
    let signature;
    try{signature=await deps.readPrivateImage(signingPath);}
    catch(error){throw new Error("The signing Principal's saved signature could not be loaded: "+(error?.message||"Please check the Principal signature storage."));}
    if(!signature?.width&&!signature?.naturalWidth)throw new Error("The signing Principal signature image is unreadable.");
    const verificationUrl=deps.verificationUrl(issuance.verification_token,"transcript",school);
    const qr=await deps.qrCanvas(verificationUrl,152);
    if(!qr)throw new Error("The official transcript verification QR could not be prepared.");
    let logo=null;
    try{logo=await deps.loadSchoolLogo(school);}catch(_){/* Logo is cosmetic, verification and signature are mandatory. */}
    const navy=deps.safeColour(school.primary_colour,"#0a2f73");
    const gold=deps.safeColour(school.accent_colour,"#f1b51c");
    const pages=[];
    function newPage(){
      const canvas=document.createElement("canvas");canvas.width=WIDTH;canvas.height=HEIGHT;
      const ctx=canvas.getContext("2d");
      if(!ctx)throw new Error("The browser cannot render the transcript pages.");
      ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality="high";
      ctx.fillStyle="#ffffff";ctx.fillRect(0,0,WIDTH,HEIGHT);
      ctx.fillStyle=navy;ctx.fillRect(0,0,WIDTH,168);
      ctx.fillStyle=gold;ctx.fillRect(0,168,WIDTH,7);
      if(logo)deps.drawImageContain(ctx,logo,70,21,118,118);
      ctx.textAlign="center";ctx.fillStyle="#ffffff";
      const schoolName=safe(school.school_name).toUpperCase();
      ctx.font=fit(ctx,schoolName,790,38,23,"bold","Georgia, serif");
      ctx.fillText(schoolName,WIDTH/2,59);
      ctx.font="18px Arial, sans-serif";ctx.fillText(safe(school.address||school.motto),WIDTH/2,96);
      ctx.font="bold 27px Georgia, serif";ctx.fillText("OFFICIAL ACADEMIC TRANSCRIPT",WIDTH/2,139);
      ctx.textAlign="left";
      const page={canvas,ctx,y:218};pages.push(page);
      return page;
    }
    let page=newPage();
    const ensure=space=>{
      if(page.y+space>CONTENT_BOTTOM)page=newPage();
    };
    function drawStudentPanel(){
      ensure(195);
      const {ctx}=page,y=page.y;
      rounded(ctx,LEFT,y,RIGHT-LEFT,181,"#f5f8fc","#d7e1ee");
      ctx.fillStyle=navy;ctx.font=fit(ctx,safe(student.full_name),825,31,19);
      ctx.fillText(safe(student.full_name),LEFT+22,y+42);
      const fields=[
        ["ADMISSION NO.",student.admission_no||"—"],
        ["TRANSCRIPT NO.",issuance.transcript_number],
        ["ISSUED",date(issuance.issued_at)],
        ["PURPOSE",issuance.purpose||"Academic transcript"]
      ];
      for(let i=0;i<fields.length;i++){
        const col=i%2,row=Math.floor(i/2),x=LEFT+22+col*535,yy=y+77+row*44;
        ctx.fillStyle="#61718a";ctx.font="bold 14px Arial, sans-serif";ctx.fillText(fields[i][0],x,yy);
        ctx.fillStyle="#1f304a";ctx.font=fit(ctx,safe(fields[i][1]),475,19,13);
        ctx.fillText(safe(fields[i][1]),x,yy+23);
      }
      page.y+=202;
    }
    function drawSummary(){
      ensure(96);
      const {ctx}=page,y=page.y,w=(RIGHT-LEFT)/4;
      const entries=[
        ["ACADEMIC PERIODS",String(records.length)],
        ["SUBJECT RESULTS",String(summary.subject_result_count??"—")],
        ["CUMULATIVE AVERAGE",number(summary.cumulative_average)+"%"],
        ["LATEST CLASS",summary.latest_class||"—"]
      ];
      entries.forEach(([name,value],i)=>{
        const x=LEFT+i*w;
        rounded(ctx,x,y,w-8,79,"#fffbec","#ead9a3");
        ctx.fillStyle="#67748b";ctx.font="bold 13px Arial, sans-serif";ctx.fillText(name,x+12,y+27);
        ctx.fillStyle=navy;ctx.font=fit(ctx,safe(value),w-24,21,13);ctx.fillText(safe(value),x+12,y+58);
      });
      page.y+=102;
    }
    const columns=[LEFT,LEFT+490,LEFT+628,LEFT+754,RIGHT];
    function drawPeriodHeader(record,continued=false){
      const {ctx}=page,y=page.y;
      rounded(ctx,LEFT,y,RIGHT-LEFT,52,navy);
      ctx.fillStyle="#ffffff";ctx.font=fit(ctx,
        safe(record.academic_year_name)+" • "+safe(record.term_name)+" • "+safe(record.class_name)+(continued?" (continued)":""),
        RIGHT-LEFT-35,22,14);
      ctx.fillText(safe(record.academic_year_name)+" • "+safe(record.term_name)+" • "+safe(record.class_name)+(continued?" (continued)":""),LEFT+15,y+34);
      page.y+=58;
      const headerY=page.y;
      rounded(ctx,LEFT,headerY,RIGHT-LEFT,39,"#ebf1f8","#cfd9e5");
      ["SUBJECT","SCORE","GRADE","REMARK"].forEach((title,i)=>{
        ctx.fillStyle=navy;ctx.font="bold 14px Arial, sans-serif";ctx.fillText(title,columns[i]+12,headerY+26);
      });
      page.y+=39;
    }
    function drawSubject(subject){
      const {ctx}=page;
      ctx.font="17px Arial, sans-serif";
      const subjects=wrap(ctx,subject.subject_name||"Subject",columns[1]-columns[0]-25,5);
      const remarks=wrap(ctx,subject.remark||"—",columns[4]-columns[3]-25,5);
      const rowH=Math.max(43,18+22*Math.max(subjects.length,remarks.length));
      if(page.y+rowH+55>CONTENT_BOTTOM){
        page=newPage();drawPeriodHeader(drawSubject.currentPeriod,true);
      }
      const target=page.ctx,y=page.y;
      rounded(target,LEFT,y,RIGHT-LEFT,rowH,"#ffffff","#dfe6ef");
      target.strokeStyle="#dfe6ef";target.lineWidth=1;
      for(const x of columns.slice(1,4)){target.beginPath();target.moveTo(x,y);target.lineTo(x,y+rowH);target.stroke();}
      target.fillStyle="#172a45";target.textAlign="left";target.font="17px Arial, sans-serif";
      subjects.forEach((t,i)=>target.fillText(t,columns[0]+12,y+28+i*22));
      target.textAlign="center";target.font="bold 17px Arial, sans-serif";
      target.fillText(number(subject.total_score),columns[1]+(columns[2]-columns[1])/2,y+28);
      target.fillText(safe(subject.grade)||"—",columns[2]+(columns[3]-columns[2])/2,y+28);
      target.textAlign="left";target.font="16px Arial, sans-serif";
      remarks.forEach((t,i)=>target.fillText(t,columns[3]+12,y+28+i*22));
      page.y+=rowH;
    }
    function drawRecordSummary(record){
      ensure(64);
      const {ctx}=page,y=page.y;
      rounded(ctx,LEFT,y,RIGHT-LEFT,43,"#f5f8fc","#dfe6ef");
      ctx.fillStyle=navy;ctx.font="bold 16px Arial, sans-serif";
      ctx.fillText("TERM AVERAGE: "+number(record.average)+"%",LEFT+12,y+29);
      const daysOpen=Number(record.days_school_opened),daysPresent=Number(record.days_present);
      const attendance=Number.isFinite(daysOpen)&&daysOpen>0&&Number.isFinite(daysPresent)
        ?daysPresent+" / "+daysOpen+" days":"Not recorded";
      ctx.fillText("ATTENDANCE: "+attendance,LEFT+366,y+29);
      ctx.fillStyle="#52617a";ctx.font="15px Arial, sans-serif";ctx.textAlign="right";
      ctx.fillText("REPORT: "+safe(record.report_number||"—"),RIGHT-12,y+29);
      ctx.textAlign="left";page.y+=64;
    }
    function drawEvent(event){
      ensure(48);
      const {ctx}=page,y=page.y;
      rounded(ctx,LEFT,y,RIGHT-LEFT,37,"#f7f9fc","#dee6f0");
      ctx.fillStyle="#293a55";ctx.font="16px Arial, sans-serif";
      const eventText=date(event.effective_date)+" • "+label(event.event_type)+" • "+safe(event.from_class_name||"—")+
        (event.to_class_name?" → "+safe(event.to_class_name):"");
      ctx.fillText(eventText.slice(0,125),LEFT+14,y+25);
      page.y+=43;
    }
    drawStudentPanel();
    drawSummary();
    for(const record of records){
      ensure(173);
      drawSubject.currentPeriod=record;
      drawPeriodHeader(record);
      const subjects=Array.isArray(record.subjects)?record.subjects:[];
      if(!subjects.length){
        ensure(53);rounded(page.ctx,LEFT,page.y,RIGHT-LEFT,43,"#ffffff","#dfe6ef");
        page.ctx.fillStyle="#67748b";page.ctx.font="17px Arial, sans-serif";
        page.ctx.fillText("No published subject results.",LEFT+12,page.y+28);
        page.y+=43;
      }
      for(const subject of subjects)drawSubject(subject);
      drawRecordSummary(record);
    }
    if(events.length){
      ensure(92);
      page.ctx.fillStyle=navy;page.ctx.font="bold 21px Arial, sans-serif";
      page.ctx.fillText("STUDENT LIFECYCLE HISTORY",LEFT,page.y+25);page.y+=42;
      events.forEach(drawEvent);
    }
    pages.forEach((item,index)=>{
      const {ctx}=item,last=index===pages.length-1;
      ctx.strokeStyle=gold;ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(LEFT,1518);ctx.lineTo(RIGHT,1518);ctx.stroke();
      ctx.fillStyle="#364961";ctx.font="bold 16px Arial, sans-serif";ctx.fillText("TRANSCRIPT NO.",LEFT,1552);
      ctx.font="16px Arial, sans-serif";ctx.fillText(safe(issuance.transcript_number),LEFT,1577);
      ctx.fillText("Issued: "+date(issuance.issued_at),LEFT,1607);
      ctx.fillStyle="#52617a";ctx.font="14px Arial, sans-serif";
      ctx.fillText("Public verification confirms current validity.",LEFT,1640);
      ctx.drawImage(qr,477,1532,136,136);
      ctx.textAlign="center";ctx.font="bold 13px Arial, sans-serif";ctx.fillText("SCAN TO VERIFY",545,1690);
      if(last){
        deps.drawSignature(ctx,signature,735,1125,1590,87);
        ctx.fillStyle=navy;ctx.font=fit(ctx,safe(principal.full_name||"Principal"),390,20,13);
        ctx.fillText(safe(principal.full_name||"Principal"),930,1624);
        ctx.fillStyle="#52617a";ctx.font="14px Arial, sans-serif";ctx.fillText("PRINCIPAL / HEAD",930,1648);
      }else{
        ctx.fillStyle="#687b92";ctx.font="italic 16px Georgia, serif";
        ctx.fillText("Official transcript, continued",930,1618);
      }
      ctx.textAlign="left";ctx.font="14px Arial, sans-serif";ctx.fillStyle="#52617a";
      ctx.fillText("Frozen academic record at issuance • "+safe(snapshot.schema_version||"professional-transcript-v1"),LEFT,1714);
      ctx.textAlign="right";ctx.fillText("Page "+(index+1)+" of "+pages.length,RIGHT,1714);
      ctx.textAlign="left";
    });
    try{
      const jpegs=[];
      for(const item of pages)jpegs.push(await deps.canvasBlob(item.canvas,.96));
      return await deps.imagesPdf(jpegs,595.28,841.89,WIDTH,HEIGHT);
    }finally{for(const item of pages)deps.releaseCanvas?.(item.canvas);}
  }
  window.EdusentiaOfficialTranscriptPdf=Object.freeze({render});
})();
