import fs from "node:fs";
import { neon } from "@neondatabase/serverless";

const source=fs.readFileSync(new URL("../reference/certified-ui/app.js",import.meta.url),"utf8");
const rpcNames=new Set();
for(const re of [
  /\.rpc\(\s*["']([^"']+)["']/g,
  /\brpc\(\s*["']([^"']+)["']/g,
  /\bcallRpc\(\s*["']([^"']+)["']/g,
  /\bcallRPC\(\s*["']([^"']+)["']/g
]){
  let match;
  while((match=re.exec(source)))rpcNames.add(match[1]);
}
const expected=[...rpcNames].sort();
const base=String(process.env.PARITY_WORKER_DATABASE_URL||"");
if(!base)throw new Error("PARITY_WORKER_DATABASE_URL is required");
const url=new URL(base);
url.pathname="/edusentia_rpt_000001";
const sql=neon(url.toString());
const rows=await sql`
  select distinct p.proname,
         bool_or(has_function_privilege(current_user,p.oid,'EXECUTE')) can_execute
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
   group by p.proname
   order by p.proname
`;
const installed=new Map(rows.map(row=>[String(row.proname),Boolean(row.can_execute)]));
const present=expected.filter(name=>installed.has(name));
const executable=expected.filter(name=>installed.get(name)===true);
const missing=expected.filter(name=>!installed.has(name));
const blocked=present.filter(name=>installed.get(name)!==true);

const classify=name=>{
  const n=name.toLowerCase();
  if(/history|transcript|transfer/.test(n))return "history";
  if(/attendance/.test(n))return "attendance";
  if(/prospect/.test(n))return "prospectus";
  if(/delegat/.test(n))return "delegations";
  if(/certificate|award/.test(n))return "certificates";
  if(/id_card|identity_card/.test(n))return "id_cards";
  if(/analytic|insight|trend/.test(n))return "insights";
  if(/guardian|parent|children/.test(n))return "guardian_parent";
  if(/privacy|compliance|retention|security/.test(n))return "compliance";
  if(/backup|restore/.test(n))return "backup_restore";
  if(/license|licence|plan|capacity/.test(n))return "license_capacity";
  if(/user|access|profile/.test(n))return "users_access";
  if(/teacher/.test(n))return "teachers";
  if(/headteacher|principal/.test(n))return "principal";
  if(/timetable/.test(n))return "timetable";
  if(/report/.test(n))return "reports";
  if(/student/.test(n))return "students";
  if(/academic|subject|class|grading|assessment|period/.test(n))return "academics";
  if(/notification/.test(n))return "notifications";
  if(/audit/.test(n))return "audit";
  if(/operation|health|recovery|correction/.test(n))return "operations";
  return "other";
};
const domains={};
for(const name of expected){
  const key=classify(name);
  const d=domains[key]??={expected:0,present:0,executable:0,missing:[],blocked:[]};
  d.expected++;
  if(installed.has(name))d.present++;else d.missing.push(name);
  if(installed.get(name)===true)d.executable++;
  else if(installed.has(name))d.blocked.push(name);
}
const result={
  ok:missing.length===0&&blocked.length===0,
  referenceRpcCount:expected.length,
  installedReferenceRpcCount:present.length,
  executableReferenceRpcCount:executable.length,
  missingCount:missing.length,
  blockedCount:blocked.length,
  missing,
  blocked,
  domains
};
console.log(JSON.stringify(result));
