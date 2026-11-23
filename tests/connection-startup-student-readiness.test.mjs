import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const shell=fs.readFileSync("frontend/app.js","utf8");
const students=fs.readFileSync("frontend/parity-students.js","utf8");

function extract(source,start,end){
  const a=source.indexOf(start),b=source.indexOf(end,a+start.length);
  assert.ok(a!==-1 && b>a, "Expected source boundary: "+start);
  return source.slice(a,b).trim();
}

test("connection badge is not turned into a page-loading spinner",()=>{
  const attributes=[];
  const busy=vm.runInNewContext("("+extract(shell,"function setBusy(busy){","  function status(")+")",{
    byId:id=>id==="content"?{setAttribute:(key,value)=>attributes.push([key,value])}:null,
    setSync:()=>{throw new Error("Page fetches must not change authenticated connection status");}
  });
  busy(true);
  busy(false);
  assert.deepEqual(attributes,[["aria-busy","true"],["aria-busy","false"]]);
  assert.match(shell,/setSync\(navigator\.onLine\?"online":"offline",navigator\.onLine\?"Connected":"Offline"\)/);
});

test("authenticated startup does not duplicate bootstrap or wait for logo/notification fetches",async()=>{
  const enter=vm.runInNewContext("("+extract(shell,"async function enter(session){","  function openRequiredPasswordChange(){")+")",{
    state:{session:null,boot:null,initialDashboardBootstrap:false},
    api:()=>({bootstrap:async()=>({tenant:{name:"Demo School"},profile:{must_change_password:false}})}),
    byId:()=>({textContent:"",alt:""}),
    show:()=>{},setSync:()=>{},navigator:{onLine:true},
    applyTenantBrandLogo:()=>new Promise(()=>{}),
    loadNotificationCount:()=>new Promise(()=>{}),
    renderNav:()=>{}, navigate:async()=>{},
    console, String
  });
  let done=false;
  enter({user:{displayName:"Administrator"},membership:{role:"system_admin"}}).then(()=>{done=true;});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(done,true,"Non-critical image and notification requests must not delay entry");
  assert.match(shell,/initialDashboardBootstrap=true/);
  assert.match(shell,/if\(state\.initialDashboardBootstrap&&state\.boot\)state\.initialDashboardBootstrap=false;/);
  assert.match(shell,/const session=await api\(\)\.session\(\);\s*if\(!session\?\.authenticated\)\{\s*await prepareLoginContext\(\)/);
});

test("directory becomes interactive before slow photographs and row permissions finish",async()=>{
  const source=extract(students,"async function loadCertifiedStudents(){","  async function openStudentRecord(");
  const data={rows:[{id:"s1",first_name:"Test",last_name:"Student",photo_url:"s1/a.jpg",status:"active"}]};
  const box={innerHTML:"",querySelectorAll:()=>[]};
  let photoStarted=false,permissionsStarted=false;
  let finishPhoto,finishPermissions;
  const photo=new Promise(resolve=>{finishPhoto=resolve});
  const permissions=new Promise(resolve=>{finishPermissions=resolve});
  const context={
    byId:id=>id==="studentCertifiedResults"?box:null,
    currentRole:()=>"class_teacher",isSystemAdmin:()=>false,
    loading:()=>"loading...",certified:async()=>data,
    formatDate:()=>"",esc:value=>String(value||""),status:()=>"",
    studentAvatarHtml:()=>"photo",empty:()=>"empty",pageError:e=>String(e),
    hydrateStudentPhotos:()=>{photoStarted=true;return photo;},
    hydrateStudentEditPermissions:()=>{permissionsStarted=true;return permissions;},
    console
  };
  const load=vm.runInNewContext("("+source+")",context);
  let done=false;load().then(()=>{done=true;});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(photoStarted,true);
  assert.equal(permissionsStarted,true);
  assert.equal(done,true,"Visible student rows must not wait for background photos/permissions");
  assert.match(box.innerHTML,/Test/);
  finishPhoto();finishPermissions();
});

test("protected photos are fetched in bounded batches and detached rows are ignored",async()=>{
  const source=extract(students,"async function hydrateStudentPhotos(root=document){","  async function hydrateStudentEditPermissions(");
  const images=Array.from({length:10},(_,i)=>({
    dataset:{studentId:"s"+i,studentPhoto:"s"+i+"/image.jpg"},
    isConnected:true,parentElement:{classList:{add(){}}}
  }));
  const pending=[];
  let active=0,peak=0;
  const hydrate=vm.runInNewContext("("+source+")",{
    STUDENT_BACKGROUND_CONCURRENCY:4,
    studentPhotoUrl:()=>new Promise(resolve=>{
      active++;peak=Math.max(peak,active);
      pending.push(()=>{active--;resolve("blob:photo")});
    }),
    console
  });
  const job=hydrate({querySelectorAll:()=>images});
  assert.equal(pending.length,4,"Only four photo requests may start together");
  for(let i=0;i<3;i++){
    const chunk=pending.splice(0);
    chunk.forEach(resolve=>resolve());
    await new Promise(resolve=>setImmediate(resolve));
  }
  await job;
  assert.equal(peak,4);
  assert.equal(images.filter(x=>x.src==="blob:photo").length,10);
  assert.match(students,/studentPhotoRequests\.has\(cacheKey\)/);
  assert.match(students,/if\(!img\.isConnected\)continue;/);
});
