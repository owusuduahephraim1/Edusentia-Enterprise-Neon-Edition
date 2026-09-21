import fs from "node:fs";
import { neon } from "@neondatabase/serverless";

const source=fs.readFileSync(new URL("../reference/certified-ui/app.js",import.meta.url),"utf8");
const rpcNames=new Set();
for(const re of [
  /\.rpc\(\s*["']([^"']+)["']/g,
  /\brpc\(\s*["']([^"']+)["']/g,
  /\bcallRpc\(\s*["']([^"']+)["']/g,
  /\bcallRPC\(\s*["']([^"']+)["']/g,
  /\brpcAllRows\(\s*["']([^"']+)["']/g
]){
  let match;
  while((match=re.exec(source)))rpcNames.add(match[1]);
}
for(const match of source.matchAll(/\bcacheableRpc\(\s*["'][^"']+["']\s*,\s*["']([^"']+)["']/g))rpcNames.add(match[1]);
const expected=[...rpcNames].sort();
const explicit=String(process.env.TARGET_DATABASE_URL||"");
const base=explicit||String(process.env.PARITY_WORKER_DATABASE_URL||"");
if(!base)throw new Error("TARGET_DATABASE_URL or PARITY_WORKER_DATABASE_URL is required");
const url=new URL(base);
if(!explicit)url.pathname="/edusentia_rpt_000001";
const sql=neon(url.toString());
const rows=await sql`
  select distinct p.proname,
         bool_or(has_function_privilege('edusentia_worker_runtime',p.oid,'EXECUTE')) can_execute
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
const helperFunctions=[
  "academic_analytics_v729","admin_apply_user_bundle","admin_validate_user_bundle","apply_certificate_placeholders",
  "attendance_counts_for_enrollment","build_report_snapshot","build_school_prospectus_snapshot","build_staff_id_card_snapshot",
  "build_student_id_card_snapshot","build_student_transcript_snapshot","can_access_class","can_create_report_for_class_term",
  "can_manage_certificates","can_manage_class_report_fields","can_manage_student","can_review_certificates",
  "can_score_class_subject_for_term","can_view_report","can_view_student","can_view_student_history","canonical_school_email_domain",
  "certificate_type_code","certificate_type_label","create_notification","create_workflow_notifications","current_aal","current_app_role",
  "current_app_role_for","default_grading_interpretation","finance_student_hold_status","generate_report_number",
  "generate_school_identifier","generate_staff_id_card_number","generate_student_id_card_number","get_report_editor",
  "get_role_dashboard","get_role_workspace","has_role","id_card_effective_status","is_academic_manager",
  "is_assigned_class_teacher","is_records_manager","is_system_admin","is_term_three","license_read_allowed",
  "license_write_allowed","next_promotion_academic_year","platform_preview_license_change","record_certificate_event",
  "record_id_card_event","record_staff_id_card_event","refresh_report_promotion","report_class_id","report_promotion_evaluation",
  "require_license_feature","require_platform_super_admin","require_sensitive_access","resolve_assessment_scheme",
  "resolve_report_grading_guide","safe_boolean","safe_date","safe_numeric","safe_timestamptz","safe_uuid",
  "save_academic_entity","save_assessment_scheme","save_class_subject_assignment","save_grading_scale","save_headteacher",
  "save_report_card","save_student","save_teacher","staff_id_card_photo_reference_count","sync_attendance_reports",
  "term_control_snapshot","term_phase_writable","transition_report_status",
  "can_create_report_scope","canonical_school_identity_prefix","current_id_card_principal_snapshot",
  "has_any_active_emergency_delegation","prospectus_class_range_label"
];

const result={
  ok:missing.length===0&&blocked.length===0,
  referenceRpcCount:expected.length,
  installedReferenceRpcCount:present.length,
  executableReferenceRpcCount:executable.length,
  missingCount:missing.length,
  blockedCount:blocked.length,
  missing,
  blocked,
  helperFunctionCount:helperFunctions.length,
  missingHelperFunctions:helperFunctions.filter(name=>!installed.has(name)),
  blockedHelperFunctions:helperFunctions.filter(name=>installed.has(name)&&installed.get(name)!==true),
  domains
};
console.log(JSON.stringify(result));
