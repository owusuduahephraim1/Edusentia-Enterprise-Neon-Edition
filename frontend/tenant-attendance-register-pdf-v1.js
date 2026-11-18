/* Edusentia attendance register: offline-capable, vector PDF with school header and optional logo.
   All marks and dates are supplied by the role-authorized Neon attendance export RPC. */
(() => {
  "use strict";
  if(window.EdusentiaAttendancePdf)return;

  const WIDTH=842,HEIGHT=595;
  const COLORS={navy:"#123a79",ink:"#17233b",muted:"#53657c",line:"#d2ddec",
    pale:"#edf4fb",blue:"#1d4ed8",green:"#15803d",red:"#b91c1c",amber:"#a16207",purple:"#7e22ce"};
  const classes=["boys","girls","review"];
  const groupLabels={boys:"BOYS",girls:"GIRLS",review:"GENDER REVIEW REQUIRED"};
  const headers=["#","Student name","Admission No.","Mon","Tue","Wed","Thu","Fri",
    "W-P","W-A","W-L","W-E","C-P","C-A","C-L","C-E","Rate"];
  const widths=[24,180,100,32,32,32,32,32,39,32,31,31,42,32,30,30,42];

  function bytes(value){
    const s=String(value),output=new Uint8Array(s.length);
    for(let i=0;i<s.length;i++)output[i]=s.charCodeAt(i)&255;
    return output;
  }
  function normalized(value){
    return String(value??"").replace(/[\u2018\u2019]/g,"'").replace(/[\u201c\u201d]/g,'"')
      .replace(/[\u2013\u2014]/g,"-").replace(/\u2026/g,"...")
      .split("").map(c=>{
        const code=c.charCodeAt(0);
        if(code>=32&&code<=126||code>=160&&code<=255)return c;
        if(code===9||code===10||code===13)return " ";
        const latin=c.normalize("NFKD").replace(/[\u0300-\u036f]/g,"");
        return latin.length===1&&latin.charCodeAt(0)<127?latin:"?";
      }).join("");
  }
  function literal(s){
    return "("+normalized(s).replace(/\\/g,"\\\\").replace(/\(/g,"\\(").replace(/\)/g,"\\)")+")";
  }
  function rgb(hex){
    const h=(/^#[0-9a-f]{6}$/i.test(hex||"")?hex:"#17233b").slice(1);
    return [0,2,4].map(i=>(parseInt(h.slice(i,i+2),16)/255).toFixed(3)).join(" ");
  }
  function textWidth(v,size){return normalized(v).split("").reduce((n,c)=>n+("ilI1.,' :;!".includes(c)?.26:("MW@".includes(c)?.86:.54)),0)*size;}
  function drawText(p,v,x,y,size=8,color=COLORS.ink,bold=false,align="left",maxWidth=0){
    let str=normalized(v);
    if(maxWidth){
      while(str.length>3&&textWidth(str,size)>maxWidth)str=str.slice(0,-4)+"...";
    }
    const dx=align==="center"?x-textWidth(str,size)/2:align==="right"?x-textWidth(str,size):x;
    p.cmd.push("BT /"+(bold?"FB":"FR")+" "+size+" Tf "+rgb(color)+" rg 1 0 0 1 "+dx.toFixed(2)+" "+y.toFixed(2)+" Tm "+literal(str)+" Tj ET");
  }
  function rect(p,x,y,w,h,color,stroke=null){
    p.cmd.push(rgb(color)+" rg "+(stroke?rgb(stroke)+" RG ":"")+x.toFixed(2)+" "+y.toFixed(2)+" "+w.toFixed(2)+" "+h.toFixed(2)+" re "+(stroke?"B":"f"));
  }
  function line(p,x1,y1,x2,y2,color=COLORS.line,thick=.5){
    p.cmd.push(rgb(color)+" RG "+thick+" w "+x1+" "+y1.toFixed(2)+" m "+x2+" "+y2.toFixed(2)+" l S");
  }
  function cleanDate(value){return /^\d{4}-\d{2}-\d{2}$/.test(String(value||""))?String(value):"";}
  function niceDate(value){
    const d=cleanDate(value);
    if(!d)return "-";
    return d.slice(8,10)+"/"+d.slice(5,7)+"/"+d.slice(0,4);
  }
  function shiftDate(value,offset){
    const date=new Date(cleanDate(value)+"T12:00:00Z");
    if(Number.isNaN(date.getTime()))return "";
    date.setUTCDate(date.getUTCDate()+offset);
    return date.toISOString().slice(0,10);
  }
  function shortText(v,n=30){
    const text=normalized(v);
    if(text.length<=n)return text;
    return text.slice(0,Math.max(0,n-3))+"...";
  }
  function wrapName(name,maxChars=34){
    const words=normalized(name||"Student").split(/\s+/),lines=[];
    for(const word of words){
      const last=lines.length-1;
      if(last>=0&&lines[last].length+word.length+1<=maxChars)lines[last]+=" "+word;
      else lines.push(word);
    }
    return lines.length?lines:["Student"];
  }
  function addCounts(target,status){
    if(status==="present"||status==="late")target.p++;
    if(status==="absent")target.a++;
    if(status==="late")target.l++;
    if(status==="excused")target.e++;
  }
  function getRecords(data,options={}){
    const weeks=Array.isArray(data?.weeks)?data.weeks:[];
    const students=Array.isArray(data?.students)?data.students:[];
    if(!weeks.length)throw new Error("No weeks are configured for the selected term.");
    const from=String(options.fromWeek||weeks[0].week_start);
    const through=String(options.toWeek||weeks[weeks.length-1].week_start);
    if(from>through||!weeks.some(w=>String(w.week_start)===from)||!weeks.some(w=>String(w.week_start)===through))
      throw new Error("Select a valid start and end week.");
    const selected=weeks.filter(w=>String(w.week_start)>=from&&String(w.week_start)<=through);
    const calendar=new Map((Array.isArray(data.calendar)?data.calendar:[]).map(d=>[String(d.date),String(d.day_status)]));
    const marks=new Map((Array.isArray(data.marks)?data.marks:[]).map(m=>[String(m.enrollment_id)+"|"+String(m.date),String(m.status)]));
    const sorted=students.slice().sort((a,b)=>{
      const ia=classes.indexOf(a.gender),ib=classes.indexOf(b.gender);
      if(ia!==ib)return (ia<0?99:ia)-(ib<0?99:ib);
      return String(a.name||"").localeCompare(String(b.name||""))||String(a.admission_no||"").localeCompare(String(b.admission_no||""));
    });
    const stats=(student,begin,end)=>{
      const out={p:0,a:0,l:0,e:0};
      for(const [day,state] of calendar){
        if(day<begin||day>end||state!=="recorded")continue;
        addCounts(out,marks.get(String(student.enrollment_id)+"|"+day));
      }
      return out;
    };
    const countDays=(begin,end,state)=>[...calendar].filter(([day,s])=>day>=begin&&day<=end&&s===state).length;
    function symbol(student,day){
      if(day<data.term_start||day>data.term_end)return "";
      const state=calendar.get(day);
      if(!state)return "";
      if(state==="closed")return "H";
      if(state==="upcoming")return "F";
      if(state!=="recorded")return "U";
      const mark=marks.get(String(student.enrollment_id)+"|"+day);
      return ({present:"I",absent:"0",late:"I(L)",excused:"E"})[mark]||"U";
    }
    function rate(student,through){
      const start=String(data.term_start),c=stats(student,start,through);
      // A missing student mark must never lower the attendance percentage.
      // Only explicitly marked present/late or absent days enter the denominator.
      const eligible=c.p+c.a;
      return eligible>0?Math.min(100,Math.round(c.p*1000/eligible)/10).toFixed(1)+"%":"N/A";
    }
    return {weeks:selected,students:sorted,calendar,stats,countDays,symbol,rate,from,through};
  }
  function buildBlob(data,options={},logo=null){
    const index=getRecords(data,options);
    const pages=[],school=data?.school||{};
    const schoolName=school.name||window.EdusentiaShell?.state?.boot?.tenant?.name||"School";
    const className=data.class_name||"Class";
    const pColor=/^#[0-9a-f]{6}$/i.test(school.primary_colour||"")?school.primary_colour:COLORS.navy;
    const tableX=34,tableWidth=widths.reduce((a,b)=>a+b,0);
    const fmtWeek=w=>"Week "+Number(w.week_number||0)+"  |  "+niceDate(w.start_date)+" - "+niceDate(w.end_date);
    function newPage(heading,range){
      const p={cmd:[],heading};
      pages.push(p);
      rect(p,28,493,786,80,pColor);
      if(logo)p.cmd.push("q 56 0 0 56 39 506 cm /Logo Do Q");
      drawText(p,schoolName,421,549,16,"#ffffff",true,"center",logo?475:670);
      drawText(p,"STUDENTS REGISTER ATTENDANCE SUMMARY DETAILS",421,527,11.6,"#ffffff",true,"center",690);
      drawText(p,(className+"  |  "+(data.term||"Term")).toUpperCase(),421,509,10,"#ffffff",true,"center",670);
      rect(p,34,449,774,37,COLORS.pale);
      drawText(p,"ACADEMIC YEAR: "+(data.academic_year||"-"),44,470,8.4,COLORS.ink,true);
      drawText(p,"MAIN CLASS TEACHER: "+shortText(data.main_teacher||"Not assigned",45),450,470,8.2,COLORS.ink,true);
      drawText(p,range,44,457,8,COLORS.muted);
      drawText(p,shortText([school.motto,school.address,school.phone].filter(Boolean).join("  |  "),113),807,457,7,COLORS.muted,false,"right");
      line(p,34,42,807,42,COLORS.line,.7);
      drawText(p,"I Present  |  0 Absent  |  I(L) Late + present  |  E Excused  |  H Closed  |  U Unrecorded  |  F Future",34,30,7,COLORS.muted);
      drawText(p,"W = weekly; C = cumulative from term opening; Rate uses marked present/absent only.",34,19,6.8,COLORS.muted);
      return p;
    }
    function sectionHeader(p,title,subtitle){
      drawText(p,title,34,432,11,COLORS.navy,true);
      drawText(p,subtitle,807,433,7.8,COLORS.muted,false,"right");
    }
    function tableHeader(p,y){
      rect(p,tableX,y-23,tableWidth,23,COLORS.pale);
      let x=tableX;
      headers.forEach((head,i)=>{
        drawText(p,head,x+widths[i]/2,y-14,i===1?7.4:7.1,COLORS.navy,true,"center",widths[i]-4);
        x+=widths[i];
      });
      line(p,tableX,y-23,tableX+tableWidth,y-23,"#96aecd",.9);
      return y-23;
    }
    function weeklyRow(p,student,indexNo,week,y,cursor){
      const nameLines=wrapName(student.name,36);
      const height=Math.max(25,12+nameLines.length*8);
      if(indexNo%2===0)rect(p,tableX,y-height,tableWidth,height,"#f7fafd");
      const dayValues=Array.from({length:5},(_,d)=>cursor.symbol(student,shiftDate(week.week_start,d)));
      const weekly=cursor.stats(student,week.start_date,week.end_date);
      const cumulative=cursor.stats(student,data.term_start,week.end_date);
      const cells=[String(indexNo),null,student.admission_no||"",...dayValues,
        weekly.p,weekly.a,weekly.l,weekly.e,cumulative.p,cumulative.a,cumulative.l,cumulative.e,cursor.rate(student,week.end_date)];
      let x=tableX;
      cells.forEach((value,i)=>{
        if(i===1){
          nameLines.forEach((part,j)=>drawText(p,part,x+5,y-height/2+((nameLines.length-1)/2-j)*9+1,7.5,COLORS.ink,true,"left",widths[i]-9));
        }else{
          const symbolValue=String(value??"");
          const tone=i>=3&&i<=7?(symbolValue==="0"?COLORS.red:
            symbolValue==="I"?COLORS.green:symbolValue==="I(L)"?COLORS.amber:
            symbolValue==="E"||symbolValue==="H"?COLORS.purple:symbolValue==="U"?COLORS.amber:COLORS.muted):
            i===8||i===12?COLORS.blue:i===9||i===13?COLORS.red:
            i===10||i===14?COLORS.amber:i===11||i===15?COLORS.purple:COLORS.ink;
          drawText(p,symbolValue,x+widths[i]/2,y-height/2-2.5,7.6,tone,i>7,"center",widths[i]-4);
        }
        x+=widths[i];
      });
      line(p,tableX,y-height,tableX+tableWidth,y-height,COLORS.line,.5);
      return y-height;
    }
    function renderWeekGroup(week,gender){
      const group=index.students.filter(st=>(classes.includes(st.gender)?st.gender:"review")===gender);
      if(!group.length&&gender==="review")return;
      if(!group.length){
        const p=newPage(groupLabels[gender]+" - WEEKLY ATTENDANCE",fmtWeek(week));
        sectionHeader(p,groupLabels[gender]+" ATTENDANCE REGISTER",fmtWeek(week));
        drawText(p,"No students registered in this category.",35,395,10,COLORS.muted);
        return;
      }
      let offset=0,p=null,y=0;
      while(offset<group.length){
        p=newPage(groupLabels[gender]+" - WEEKLY ATTENDANCE",fmtWeek(week));
        sectionHeader(p,groupLabels[gender]+" ATTENDANCE REGISTER",fmtWeek(week)+(offset?"  |  continued":""));
        y=tableHeader(p,418);
        while(offset<group.length){
          const student=group[offset];
          const need=Math.max(25,12+wrapName(student.name,36).length*8);
          if(y-need<77)break;
          y=weeklyRow(p,student,offset+1,week,y,index);offset++;
        }
        if(offset===group.length){
          const counts={p:0,a:0,l:0,e:0};
          for(const st of group){
            const c=index.stats(st,week.start_date,week.end_date);
            for(const k of ["p","a","l","e"])counts[k]+=c[k];
          }
          const recorded=index.countDays(week.start_date,week.end_date,"recorded");
          drawText(p,group.length+" learners  |  "+recorded+" recorded teaching days  |  "+counts.p+" present pupil-days  |  "+counts.a+" absences",35,Math.max(60,y-17),8,COLORS.navy,true);
        }
      }
    }
    function summaryPage(gender,lastWeek){
      const group=index.students.filter(st=>(classes.includes(st.gender)?st.gender:"review")===gender);
      if(!group.length&&gender==="review")return;
      if(!group.length){
        const p=newPage(groupLabels[gender]+" - CUMULATIVE SUMMARY","Cumulative totals from term opening through "+niceDate(lastWeek.end_date));
        sectionHeader(p,groupLabels[gender]+" - CUMULATIVE ATTENDANCE","Through Week "+lastWeek.week_number);
        drawText(p,"No students registered in this category.",35,397,10,COLORS.muted);
        return;
      }
      let n=0,y=0,p=null;
      const labels=["#","Student name","Admission number","Present","Absent","Late","Excused","Days recorded","Rate"];
      const dims=[26,246,122,66,64,52,62,74,60];
      const wide=dims.reduce((a,b)=>a+b,0);
      while(n<group.length){
        p=newPage(groupLabels[gender]+" - CUMULATIVE SUMMARY","Cumulative totals from term opening through "+niceDate(lastWeek.end_date));
        sectionHeader(p,groupLabels[gender]+" - CUMULATIVE ATTENDANCE","Through Week "+lastWeek.week_number);
        rect(p,tableX,395,wide,23,COLORS.pale);
        let x=tableX;
        labels.forEach((v,i)=>{drawText(p,v,x+dims[i]/2,403,8,COLORS.navy,true,"center",dims[i]-5);x+=dims[i]});
        y=395;
        while(n<group.length){
          const student=group[n],nameLines=wrapName(student.name,48),height=Math.max(25,12+nameLines.length*8);
          if(y-height<77)break;
          if(n%2===0)rect(p,tableX,y-height,wide,height,"#f7fafd");
          const c=index.stats(student,data.term_start,lastWeek.end_date);
          const values=[n+1,null,student.admission_no||"",c.p,c.a,c.l,c.e,
            index.countDays(data.term_start,lastWeek.end_date,"recorded"),index.rate(student,lastWeek.end_date)];
          let dx=tableX;
          values.forEach((v,i)=>{
            if(i===1)nameLines.forEach((val,j)=>drawText(p,val,dx+5,y-height/2+((nameLines.length-1)/2-j)*9,8,COLORS.ink,true));
            else drawText(p,String(v),dx+dims[i]/2,y-height/2-2.5,8,i===3?COLORS.blue:i===4?COLORS.red:COLORS.ink,i>=3,"center",dims[i]-6);
            dx+=dims[i];
          });
          line(p,tableX,y-height,tableX+wide,y-height,COLORS.line,.5);
          y-=height;n++;
        }
        if(n===group.length){
          const sums={p:0,a:0,l:0,e:0};
          group.forEach(st=>{const c=index.stats(st,data.term_start,lastWeek.end_date);for(const k of ["p","a","l","e"])sums[k]+=c[k]});
          drawText(p,group.length+" learners  |  Present: "+sums.p+"  |  Absent: "+sums.a+"  |  Late: "+sums.l+"  |  Excused: "+sums.e,35,Math.max(57,y-19),8.5,COLORS.navy,true);
        }
      }
    }

    index.weeks.forEach(week=>classes.forEach(group=>renderWeekGroup(week,group)));
    const lastWeek=index.weeks[index.weeks.length-1];
    classes.forEach(group=>summaryPage(group,lastWeek));
    if(!pages.length){
      const p=newPage("No active enrollments","Selected academic term");
      drawText(p,"There are no students currently enrolled in this class and term.",34,419,11,COLORS.muted);
    }
    pages.forEach((page,i)=>{
      drawText(page,"Generated: "+new Date(data.generated_at||Date.now()).toLocaleDateString("en-GB"),807,30,6.7,COLORS.muted,false,"right");
      drawText(page,"Page "+(i+1)+" of "+pages.length,807,19,6.7,COLORS.muted,false,"right");
    });

    const objects=[null];
    function alloc(body=""){objects.push(body);return objects.length-1;}
    const catalogId=alloc(),pagesId=alloc();
    const fontId=alloc("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
    const boldId=alloc("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
    let imageId=0;
    if(logo&&logo.bytes?.length){
      imageId=alloc([bytes("<< /Type /XObject /Subtype /Image /Width "+logo.width+" /Height "+logo.height+
        " /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length "+logo.bytes.length+" >>\nstream\n"),
        logo.bytes,bytes("\nendstream")]);
    }
    const pageIds=[];
    for(const page of pages){
      const stream=bytes(page.cmd.join("\n")+"\n");
      const streamId=alloc([bytes("<< /Length "+stream.length+" >>\nstream\n"),stream,bytes("endstream")]);
      const pageId=alloc("<< /Type /Page /Parent "+pagesId+" 0 R /MediaBox [0 0 "+WIDTH+" "+HEIGHT+
        "] /Resources << /Font << /FR "+fontId+" 0 R /FB "+boldId+" 0 R >>"+
        (imageId?" /XObject << /Logo "+imageId+" 0 R >>":"")+
        " >> /Contents "+streamId+" 0 R >>");
      pageIds.push(pageId);
    }
    objects[catalogId]="<< /Type /Catalog /Pages "+pagesId+" 0 R >>";
    objects[pagesId]="<< /Type /Pages /Count "+pageIds.length+" /Kids ["+pageIds.map(id=>id+" 0 R").join(" ")+"] >>";
    const out=[],offsets=[0];
    let pos=0;
    function append(part){out.push(part);pos+=part.length;}
    append(bytes("%PDF-1.4\n%\u00e2\u00e3\u00cf\u00d3\n"));
    objects.slice(1).forEach((obj,i)=>{
      const id=i+1;offsets[id]=pos;
      append(bytes(id+" 0 obj\n"));
      for(const part of Array.isArray(obj)?obj:[bytes(obj)])append(part);
      append(bytes("\nendobj\n"));
    });
    const xref=pos;
    append(bytes("xref\n0 "+objects.length+"\n0000000000 65535 f \n"));
    for(let i=1;i<objects.length;i++)append(bytes(String(offsets[i]).padStart(10,"0")+" 00000 n \n"));
    append(bytes("trailer\n<< /Size "+objects.length+" /Root "+catalogId+" 0 R >>\nstartxref\n"+xref+"\n%%EOF"));
    return new Blob(out,{type:"application/pdf"});
  }
  async function schoolLogo(){
    try{
      // Prefer the already authenticated school branding image instead of re-fetching
      // and potentially revoking the sidebar's current R2 object URL.
      const currentLogo=document.getElementById("brandLogo");
      const url=currentLogo?.src||await window.EdusentiaShell?.resolveTenantLogoSource?.();
      if(!url)return null;
      const img=new Image();
      img.crossOrigin="anonymous";
      img.src=url;
      if(typeof img.decode==="function")await img.decode();
      else await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;});
      const canvas=document.createElement("canvas");canvas.width=320;canvas.height=320;
      const ctx=canvas.getContext("2d");
      ctx.fillStyle="#ffffff";ctx.fillRect(0,0,320,320);
      const s=Math.min(300/img.naturalWidth,300/img.naturalHeight);
      const w=img.naturalWidth*s,h=img.naturalHeight*s;
      ctx.drawImage(img,(320-w)/2,(320-h)/2,w,h);
      const data=canvas.toDataURL("image/jpeg",.93).split(",")[1],binary=atob(data);
      const buffer=new Uint8Array(binary.length);
      for(let i=0;i<binary.length;i++)buffer[i]=binary.charCodeAt(i);
      return {bytes:buffer,width:320,height:320};
    }catch(error){console.warn("attendance_export_logo_unavailable",error);return null;}
  }
  async function download(data,options={}){
    const image=await schoolLogo();
    const pdf=buildBlob(data,options,image);
    const P=window.EdusentiaParity;
    const safe=P?.safeName||((s)=>String(s).replace(/[^a-z0-9]+/gi,"_"));
    const label=options.fromWeek===options.toWeek?"Week_"+options.fromWeek:"Weeks_"+options.fromWeek+"_to_"+options.toWeek;
    const filename=safe((data.class_name||"Class")+"_Attendance_"+label)+".pdf";
    if(P?.downloadBlob)P.downloadBlob(filename,pdf);
    else {const url=URL.createObjectURL(pdf),a=document.createElement("a");a.href=url;a.download=filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),15000);}
    return filename;
  }
  window.EdusentiaAttendancePdf=Object.freeze({buildBlob,download,getRecords});
})();