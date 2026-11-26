#!/usr/bin/env node
// Read-only Edusentia public launch check.
// Checks public HTTPS endpoints and email DNS; never makes configuration changes.
import {resolve4,resolveMx,resolveTxt} from "node:dns/promises";
import {pathToFileURL} from "node:url";

export const endpointSpecs=Object.freeze([
  {id:"public_apex",url:"https://edusentia.com/",marker:/Edusentia Enterprise/i},
  {id:"public_www",url:"https://www.edusentia.com/",marker:/Edusentia Enterprise/i},
  {id:"public_privacy",url:"https://edusentia.com/privacy.html",marker:/Website Privacy Notice/i},
  {id:"public_security",url:"https://edusentia.com/security.html",marker:/Security & Trust/i},
  {id:"school_app",url:"https://app.edusentia.com/",marker:/Edusentia/i},
  {id:"document_verification",url:"https://verify.edusentia.com/",marker:/Verify School Document|Edusentia/i}
]);
function isMissingDns(error){
  return ["ENODATA","ENOTFOUND","ENONAME","ESERVFAIL"].includes(String(error?.code||""));
}
export async function safeDnsQuery(resolver,name){
  try{return {ok:true,answers:await resolver(name)};}
  catch(error){
    if(isMissingDns(error))return {ok:true,answers:[]};
    return {ok:false,answers:[],error:"DNS resolver temporarily unavailable"};
  }
}
export function describeMailDns({mx=[],rootTxt=[],dmarcTxt=[]}={}){
  const records=txt=>txt.flat().map(x=>String(x).trim());
  const root=records(rootTxt),dmarc=records(dmarcTxt);
  const spf=root.filter(x=>/^v=spf1(?:\s|$)/i.test(x));
  const dmarcPolicy=dmarc.filter(x=>/^v=dmarc1(?:\s|;|$)/i.test(x));
  return {
    mx:mx.length?"configured":"pending",
    spf:spf.length===1?"configured":spf.length>1?"conflict":"pending",
    dmarc:dmarcPolicy.length?"configured":"pending",
    dkim:"requires selected sender and selector",
    outgoingMail:"not tested",
    delivery:"not tested"
  };
}
export async function checkEndpoint(spec,{fetcher=fetch}={}){
  try{
    const response=await fetcher(spec.url,{redirect:"follow",headers:{"accept":"text/html"},signal:AbortSignal.timeout(15000)});
    if(!response.ok)return {id:spec.id,url:spec.url,status:"failed",detail:"HTTP "+response.status};
    const type=String(response.headers.get("content-type")||"");
    if(type && !type.includes("text/html"))return {id:spec.id,url:spec.url,status:"failed",detail:"Unexpected content type"};
    const content=await response.text();
    if(!spec.marker.test(content))return {id:spec.id,url:spec.url,status:"failed",detail:"Expected application branding not found"};
    const finalUrl=new URL(response.url||spec.url);
    if(finalUrl.protocol!=="https:")return {id:spec.id,url:spec.url,status:"failed",detail:"Redirected outside HTTPS"};
    return {id:spec.id,url:spec.url,status:"passed",finalUrl:finalUrl.toString()};
  }catch{
    return {id:spec.id,url:spec.url,status:"failed",detail:"Network request or timeout failed"};
  }
}
export async function runReadinessCheck({fetcher=fetch,dns={resolve4,resolveMx,resolveTxt}}={}){
  const endpoints=[];
  for(const item of endpointSpecs)endpoints.push(await checkEndpoint(item,{fetcher}));
  const [apex,www,mx,rootTxt,dmarcTxt]=await Promise.all([
    safeDnsQuery(dns.resolve4,"edusentia.com"),
    safeDnsQuery(dns.resolve4,"www.edusentia.com"),
    safeDnsQuery(dns.resolveMx,"edusentia.com"),
    safeDnsQuery(dns.resolveTxt,"edusentia.com"),
    safeDnsQuery(dns.resolveTxt,"_dmarc.edusentia.com")
  ]);
  const dnsFailures=[apex,www].some(x=>!x.ok||!x.answers.length);
  const email=describeMailDns({mx:mx.answers,rootTxt:rootTxt.answers,dmarcTxt:dmarcTxt.answers});
  const siteFailed=dnsFailures||endpoints.some(x=>x.status==="failed");
  return {
    checkedAt:new Date().toISOString(),
    publicStatus:siteFailed?"failed":"passed",
    endpoints,
    dns:{apex:apex.ok&&apex.answers.length?"resolves":"failed",www:www.ok&&www.answers.length?"resolves":"failed"},
    email,
    emailCheckStatus:mx.ok&&rootTxt.ok&&dmarcTxt.ok?"checked":"inconclusive",
    caveats:[
      "Public endpoint checks do not authenticate users or verify backend business operations.",
      "DKIM requires a real mail provider selector; mailbox sending and receiving require live test messages.",
      "Backups, off-site copies, and restoration must be tested separately."
    ]
  };
}
export function summaryMarkdown(result){
  const label=v=>v==="passed"?"PASS":v==="configured"?"CONFIGURED":v==="failed"?"FAIL":"PENDING";
  const lines=[
    "## Edusentia production readiness (public, read-only)",
    "- Checked at: "+result.checkedAt,
    "- Public web status: **"+label(result.publicStatus)+"**",
    "",
    "| Service | HTTP / page check |",
    "|---|---|",
    ...result.endpoints.map(e=>"| "+e.id+" | "+label(e.status)+" |"),
    "",
    "| Business mail component | Result |",
    "|---|---|",
    ...Object.entries(result.email).map(([k,v])=>"| "+k+" | "+(v==="pending"?"PENDING":v==="configured"?"CONFIGURED":v==="conflict"?"CONFLICT":v)+" |"),
    "",
    "**Important:** A green web status does not prove authenticated application workflows, verified email delivery, or restore recovery."
  ];
  return lines.join("\n")+"\n";
}
async function main(){
  const result=await runReadinessCheck();
  const markdown=summaryMarkdown(result);
  console.log(markdown);
  if(process.env.GITHUB_STEP_SUMMARY){
    const {appendFile}=await import("node:fs/promises");
    await appendFile(process.env.GITHUB_STEP_SUMMARY,markdown);
  }
  for(const entry of Object.entries(result.email)){
    if(entry[1]==="pending"||entry[1]==="conflict")console.log("::warning::Business mail "+entry[0]+" is "+entry[1]);
  }
  if(result.publicStatus==="failed")process.exitCode=1;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await main();
