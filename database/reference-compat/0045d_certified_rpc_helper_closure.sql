-- Edusentia Enterprise Neon Edition — certified RPC helper closure.
-- Certified source: a181e18e0ca044db756193209b5b089cd03efb0f
-- Helper functions are internal to certified RPCs and remain unavailable as browser RPC operations.
begin;

-- helper admin_validate_user_bundle(actor_id uuid, bundle jsonb, require_existing_user boolean)
CREATE OR REPLACE FUNCTION public.admin_validate_user_bundle(actor_id uuid, bundle jsonb, require_existing_user boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'authn', 'auth', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(bundle->>'user_id');staffrecordid uuid:=public.safe_uuid(bundle->>'staff_record_id');role_text text:=btrim(coalesce(bundle->>'role','viewer'));
  item jsonb;classid uuid;subjectid uuid;accesslevel text;scopekey text;seen_scopes text[]:='{}'::text[];has_class_scope boolean:=false;
begin
  if actor_id is null or not exists(select 1 from public.profiles p where p.id=actor_id and p.active and public.current_app_role_for(p.role)='system_admin') then raise exception 'Access denied' using errcode='42501'; end if;
  if require_existing_user and (targetid is null or not exists(select 1 from authn.users u where u.id=targetid)) then raise exception 'Authentication account was not found'; end if;
  if btrim(coalesce(bundle->>'staff_record_id',''))<>'' and staffrecordid is null then raise exception 'Selected directory record is invalid'; end if;
  if btrim(coalesce(bundle->>'full_name',''))='' then raise exception 'Full name is required'; end if;
  if btrim(coalesce(bundle->>'email',''))='' then raise exception 'Email address is required'; end if;
  if bundle->>'email' !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Email address is invalid'; end if;
  if role_text not in ('system_admin','principal','class_teacher','subject_teacher','parent_guardian','accountant','student') then raise exception 'User role is invalid'; end if;
  if role_text in ('class_teacher','subject_teacher') then
    if staffrecordid is null then raise exception 'Select the corresponding teacher record'; end if;
    if not exists(select 1 from public.teachers t where t.id=staffrecordid and t.deleted_at is null and t.active and (t.profile_id is null or t.profile_id=targetid)) then raise exception 'Selected teacher record is unavailable or already linked'; end if;
  elsif role_text='principal' then
    if staffrecordid is null then raise exception 'Select the corresponding Principal record'; end if;
    if not exists(select 1 from public.headteachers h where h.id=staffrecordid and h.deleted_at is null and h.active and (h.profile_id is null or h.profile_id=targetid)) then raise exception 'Selected Principal record is unavailable or already linked'; end if;
  elsif role_text='accountant' then
    if staffrecordid is null then raise exception 'Select the corresponding Accounts Office Staff record'; end if;
    if not exists(select 1 from public.accounts_office_staff a where a.id=staffrecordid and a.deleted_at is null and a.active and (a.profile_id is null or a.profile_id=targetid)) then raise exception 'Selected Accounts Office Staff record is unavailable or already linked'; end if;
  elsif role_text='student' then
    if staffrecordid is null then raise exception 'Select the corresponding Student record'; end if;
    if not exists(select 1 from public.students s where s.id=staffrecordid and s.deleted_at is null and s.status='active' and (s.profile_id is null or s.profile_id=targetid)) then raise exception 'Selected Student record is unavailable or already linked'; end if;
  elsif staffrecordid is not null then raise exception 'The selected role does not use a directory record'; end if;
  if jsonb_typeof(coalesce(bundle->'access','[]'::jsonb))<>'array' then raise exception 'Delegated access must be a list'; end if;
  for item in select value from jsonb_array_elements(coalesce(bundle->'access','[]'::jsonb)) loop
    classid:=public.safe_uuid(item->>'class_id');subjectid:=public.safe_uuid(item->>'subject_id');accesslevel:=coalesce(nullif(btrim(item->>'access_level'),''),'view');
    if classid is null or not exists(select 1 from public.classes c where c.id=classid and c.deleted_at is null and c.active) then raise exception 'A delegated class is invalid or inactive'; end if;
    if subjectid is not null and not exists(select 1 from public.class_subjects cs join public.subjects s on s.id=cs.subject_id where cs.class_id=classid and cs.subject_id=subjectid and cs.active and s.active and s.deleted_at is null) then raise exception 'A delegated subject is not actively assigned to the selected class'; end if;
    if accesslevel not in ('view','edit','score','review') then raise exception 'Delegated access level is invalid'; end if;
    if role_text='subject_teacher' and (subjectid is null or accesslevel not in ('score','edit','review')) then raise exception 'Subject teacher access is invalid'; end if;
    if role_text='class_teacher' and subjectid is null and accesslevel not in ('edit','review') then raise exception 'Class teacher access must permit class report editing'; end if;
    if role_text='class_teacher' and subjectid is null and accesslevel in ('edit','review') then has_class_scope:=true; end if;
    scopekey:=classid::text||'|'||coalesce(subjectid::text,'*');if scopekey=any(seen_scopes) then raise exception 'The same delegated class or subject access was entered more than once'; end if;seen_scopes:=array_append(seen_scopes,scopekey);
  end loop;
  return jsonb_build_object('valid',true,'role',role_text,'staff_record_id',staffrecordid,'access_count',coalesce(jsonb_array_length(bundle->'access'),0));
end $function$;
revoke all on function public.admin_validate_user_bundle(actor_id uuid, bundle jsonb, require_existing_user boolean) from public;

-- helper academic_analytics_v729(target_term_id uuid, target_class_id uuid)
CREATE OR REPLACE FUNCTION public.academic_analytics_v729(target_term_id uuid, target_class_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if public.current_app_role() not in ('system_admin','principal','class_teacher','subject_teacher') then raise exception 'Access denied' using errcode='42501'; end if;
  if target_class_id is not null and public.current_app_role() not in ('system_admin','principal') and not public.can_access_class(target_class_id,false) then raise exception 'Access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'term_id',target_term_id,'class_id',target_class_id,
    'summary',jsonb_build_object(
      'students',(select count(distinct e.student_id) from public.enrollments e join public.terms t on t.academic_year_id=e.academic_year_id where t.id=target_term_id and e.active and e.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'reports',(select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'average',(select round(avg(sr.total_score),2) from public.subject_results sr join public.student_reports r on r.id=sr.report_id join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'attendance_rate',(select round(100.0*sum(r.days_present)/nullif(sum(r.days_school_opened),0),2) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)),
      'published',(select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where r.term_id=target_term_id and r.status='published' and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id))
    ),
    'subjects',coalesce((select jsonb_agg(jsonb_build_object('subject_id',s.id,'subject_code',s.code,'subject_name',s.name,'average',q.average,'highest',q.highest,'lowest',q.lowest,'scored',q.scored) order by s.display_order,s.name)
      from public.subjects s join lateral (select round(avg(sr.total_score),2) average,max(sr.total_score) highest,min(sr.total_score) lowest,count(*) scored from public.subject_results sr join public.student_reports r on r.id=sr.report_id join public.enrollments e on e.id=r.enrollment_id where sr.subject_id=s.id and r.term_id=target_term_id and r.deleted_at is null and (target_class_id is null or e.class_id=target_class_id)) q on q.scored>0 where s.active and s.deleted_at is null),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('class_id',c.id,'class_name',c.name,'average',q.average,'attendance_rate',q.attendance_rate,'students',q.students,'published',q.published) order by c.level_order,c.name)
      from public.classes c join lateral (select round(avg(sr.total_score),2) average,round(100.0*sum(distinct r.days_present)/nullif(sum(distinct r.days_school_opened),0),2) attendance_rate,count(distinct e.student_id) students,count(distinct r.id) filter(where r.status='published') published from public.enrollments e left join public.student_reports r on r.enrollment_id=e.id and r.term_id=target_term_id and r.deleted_at is null left join public.subject_results sr on sr.report_id=r.id where e.class_id=c.id and e.active and e.deleted_at is null and e.academic_year_id=(select academic_year_id from public.terms where id=target_term_id)) q on q.students>0 where c.active and c.deleted_at is null and (target_class_id is null or c.id=target_class_id) and (public.current_app_role() in ('system_admin','principal') or public.can_access_class(c.id,false))),'[]'::jsonb)
  );
end $function$;
revoke all on function public.academic_analytics_v729(target_term_id uuid, target_class_id uuid) from public;

-- helper admin_apply_user_bundle(actor_id uuid, bundle jsonb)
CREATE OR REPLACE FUNCTION public.admin_apply_user_bundle(actor_id uuid, bundle jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  targetid uuid:=public.safe_uuid(bundle->>'user_id');staffrecordid uuid:=public.safe_uuid(bundle->>'staff_record_id');role_text text:=btrim(coalesce(bundle->>'role','viewer'));
  item jsonb;classid uuid;subjectid uuid;accesslevel text;previous jsonb;resolved_name text:=btrim(coalesce(bundle->>'full_name',''));resolved_phone text:=btrim(coalesce(bundle->>'phone',''));
begin
  perform public.admin_validate_user_bundle(actor_id,bundle,true);
  if role_text in ('class_teacher','subject_teacher') then select concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),coalesce(nullif(t.phone,''),resolved_phone) into resolved_name,resolved_phone from public.teachers t where t.id=staffrecordid and t.deleted_at is null;
  elsif role_text='principal' then select concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),coalesce(nullif(h.phone,''),resolved_phone) into resolved_name,resolved_phone from public.headteachers h where h.id=staffrecordid and h.deleted_at is null;
  elsif role_text='accountant' then select a.full_name,coalesce(nullif(a.phone,''),resolved_phone) into resolved_name,resolved_phone from public.accounts_office_staff a where a.id=staffrecordid and a.deleted_at is null;
  elsif role_text='student' then select concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) into resolved_name from public.students s where s.id=staffrecordid and s.deleted_at is null;
  end if;
  select jsonb_build_object('profile',to_jsonb(p),'teacher',(select to_jsonb(t) from public.teachers t where t.profile_id=targetid and t.deleted_at is null limit 1),'principal',(select to_jsonb(h) from public.headteachers h where h.profile_id=targetid and h.deleted_at is null limit 1),'accountant',(select to_jsonb(a) from public.accounts_office_staff a where a.profile_id=targetid and a.deleted_at is null limit 1),'student',(select to_jsonb(s) from public.students s where s.profile_id=targetid and s.deleted_at is null limit 1),'access',coalesce((select jsonb_agg(to_jsonb(x)) from public.user_class_access x where x.user_id=targetid),'[]'::jsonb)) into previous from public.profiles p where p.id=targetid;
  insert into public.profiles(id,full_name,role,active,mfa_required,must_change_password,phone,updated_at)
  values(targetid,resolved_name,role_text::public.app_role,public.safe_boolean(bundle->>'active',true),public.safe_boolean(bundle->>'mfa_required',false),public.safe_boolean(bundle->>'must_change_password',false),resolved_phone,now())
  on conflict(id) do update set full_name=excluded.full_name,role=excluded.role,active=excluded.active,mfa_required=excluded.mfa_required,must_change_password=excluded.must_change_password,phone=excluded.phone,updated_at=now();
  update public.teachers set profile_id=null,updated_at=now() where profile_id=targetid and (role_text not in ('class_teacher','subject_teacher') or id<>staffrecordid);
  update public.headteachers set profile_id=null,updated_at=now() where profile_id=targetid and (role_text<>'principal' or id<>staffrecordid);
  update public.accounts_office_staff set profile_id=null where profile_id=targetid and (role_text<>'accountant' or id<>staffrecordid);
  update public.students set profile_id=null,updated_at=now() where profile_id=targetid and (role_text<>'student' or id<>staffrecordid);
  if role_text in ('class_teacher','subject_teacher') then update public.teachers set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  elsif role_text='principal' then update public.headteachers set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  elsif role_text='accountant' then update public.accounts_office_staff set profile_id=targetid,finance_role='accountant',job_title='Accountant' where id=staffrecordid and deleted_at is null;
  elsif role_text='student' then update public.students set profile_id=targetid,updated_at=now() where id=staffrecordid and deleted_at is null;
  end if;
  delete from public.user_class_access where user_id=targetid;
  for item in select value from jsonb_array_elements(coalesce(bundle->'access','[]'::jsonb)) loop classid:=public.safe_uuid(item->>'class_id');subjectid:=public.safe_uuid(item->>'subject_id');accesslevel:=coalesce(nullif(btrim(item->>'access_level'),''),'view');insert into public.user_class_access(user_id,class_id,subject_id,access_level) values(targetid,classid,subjectid,accesslevel);end loop;
  if role_text in ('class_teacher','subject_teacher') then perform public.sync_teacher_responsibility_access(targetid); end if;
  insert into public.audit_log(actor_id,table_name,record_id,action,old_data,new_data,reason)
  values(actor_id,'profiles',targetid,case when previous is null then 'ADMIN_CREATE_USER' else 'ADMIN_UPDATE_USER' end,previous,jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where p.id=targetid),'teacher',(select to_jsonb(t) from public.teachers t where t.profile_id=targetid and t.deleted_at is null limit 1),'principal',(select to_jsonb(h) from public.headteachers h where h.profile_id=targetid and h.deleted_at is null limit 1),'accountant',(select to_jsonb(a) from public.accounts_office_staff a where a.profile_id=targetid and a.deleted_at is null limit 1),'student',(select to_jsonb(s) from public.students s where s.profile_id=targetid and s.deleted_at is null limit 1),'access',coalesce((select jsonb_agg(to_jsonb(x)) from public.user_class_access x where x.user_id=targetid),'[]'::jsonb)),coalesce(nullif(bundle->>'reason',''),'User account management'));
  return jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where p.id=targetid),'accountant',(select to_jsonb(a) from public.accounts_office_staff a where a.profile_id=targetid and a.deleted_at is null limit 1),'student',(select to_jsonb(s) from public.students s where s.profile_id=targetid and s.deleted_at is null limit 1));
end $function$;
revoke all on function public.admin_apply_user_bundle(actor_id uuid, bundle jsonb) from public;

-- helper apply_certificate_placeholders(template_text text, context_data jsonb)
CREATE OR REPLACE FUNCTION public.apply_certificate_placeholders(template_text text, context_data jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare result text:=coalesce(template_text,''); item record;
begin
  for item in select key,value from jsonb_each_text(coalesce(context_data,'{}'::jsonb)) loop
    result:=replace(result,'{{'||item.key||'}}',coalesce(item.value,''));
  end loop;
  result:=regexp_replace(result,'[[:space:]]+',' ','g');
  return btrim(result);
end $function$;
revoke all on function public.apply_certificate_placeholders(template_text text, context_data jsonb) from public;

-- helper attendance_counts_for_enrollment(target_enrollment_id uuid, target_term_id uuid)
CREATE OR REPLACE FUNCTION public.attendance_counts_for_enrollment(target_enrollment_id uuid, target_term_id uuid)
 RETURNS TABLE(days_school_opened integer, days_present integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select count(r.id)::integer,
    count(a.id) filter(where a.attendance_status in ('present','late'))::integer
  from public.enrollments e
  join public.class_attendance_registers r on r.class_id=e.class_id and r.term_id=target_term_id
  left join public.student_attendance_entries a on a.register_id=r.id and a.enrollment_id=e.id
  where e.id=target_enrollment_id
$function$;
revoke all on function public.attendance_counts_for_enrollment(target_enrollment_id uuid, target_term_id uuid) from public;

-- helper build_school_prospectus_snapshot(target_prospectus_id uuid)
CREATE OR REPLACE FUNCTION public.build_school_prospectus_snapshot(target_prospectus_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
select jsonb_build_object(
 'school',(select jsonb_build_object('school_name',s.school_name,'motto',s.motto,'address',s.address,'phone',s.phone,'email',s.email,'website',s.website,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour) from public.school_settings s limit 1),
 'academic_year',jsonb_build_object('id',y.id,'name',y.name),
 'prospectus',jsonb_build_object('id',p.id,'academic_year_id',p.academic_year_id,'class_range',p.class_range,'class_range_label',public.prospectus_class_range_label(p.class_range),'title',p.title,'currency_code',p.currency_code,'status',p.status,'effective_date',p.effective_date,'revision_no',p.revision_no,'general_notes',p.general_notes,'published_at',p.published_at,'created_at',p.created_at,'updated_at',p.updated_at),
 'sections',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'section_type',s.section_type,'title',s.title,'instructions',s.instructions,'display_order',s.display_order,'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'item_name',i.item_name,'description',i.description,'amount',i.amount,'charge_basis',i.charge_basis,'quantity',i.quantity,'unit',i.unit,'calculation_units',i.calculation_units,'include_in_total',i.include_in_total,'required',i.required,'notes',i.notes,'display_order',i.display_order) order by i.display_order,i.item_name,i.id) from public.school_prospectus_items i where i.section_id=s.id),'[]'::jsonb)) order by s.display_order,s.title,s.id) from public.school_prospectus_sections s where s.prospectus_id=p.id),'[]'::jsonb)
) from public.school_prospectuses p join public.academic_years y on y.id=p.academic_year_id where p.id=target_prospectus_id
$function$;
revoke all on function public.build_school_prospectus_snapshot(target_prospectus_id uuid) from public;

-- helper build_staff_id_card_snapshot(target_staff_type text, target_staff_id uuid, target_academic_year_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date)
CREATE OR REPLACE FUNCTION public.build_staff_id_card_snapshot(target_staff_type text, target_staff_id uuid, target_academic_year_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare kind text:=lower(btrim(coalesce(target_staff_type,'')));staff jsonb;y public.academic_years%rowtype;s public.school_settings%rowtype;cfg public.id_card_settings%rowtype;
begin
  if kind='teacher' then select jsonb_build_object('id',t.id,'staff_no',t.staff_no,'emis_code',t.emis_code,'full_name',concat_ws(' ',t.first_name,nullif(t.middle_name,''),t.last_name),'role','Teacher','qualification',t.qualification,'specialization',t.specialization,'photo_url',t.photo_url) into staff from public.teachers t where t.id=target_staff_id and t.deleted_at is null and t.active;
  elsif kind='principal' then select jsonb_build_object('id',h.id,'staff_no',h.staff_no,'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),'role','Principal','qualification',h.qualification,'photo_url',h.photo_url) into staff from public.headteachers h where h.id=target_staff_id and h.deleted_at is null and h.active;
  else raise exception 'Unsupported staff type';end if;
  if staff is null then raise exception 'Active staff record not found';end if;select * into y from public.academic_years where id=target_academic_year_id and deleted_at is null;select * into s from public.school_settings limit 1;select * into cfg from public.id_card_settings limit 1;if y.id is null then raise exception 'Academic year not found';end if;if s.id is null or cfg.id is null then raise exception 'School or ID card settings are not configured';end if;
  return jsonb_build_object('schema','rce-staff-id-card/v1','staff_type',kind,'staff',staff,'academic',jsonb_build_object('academic_year_id',y.id,'academic_year_name',y.name),'school',jsonb_build_object('school_name',s.school_name,'motto',s.motto,'address',s.address,'phone',s.phone,'email',s.email,'website',s.website,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour),'principal',public.current_id_card_principal_snapshot(),'card',jsonb_build_object('card_number',target_card_number,'verification_token',target_verification_token,'issue_date',target_issue_date,'expires_on',target_expires_on),'template',to_jsonb(cfg)-'updated_by'-'created_at'-'updated_at');
end$function$;
revoke all on function public.build_staff_id_card_snapshot(target_staff_type text, target_staff_id uuid, target_academic_year_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date) from public;

-- helper build_student_id_card_snapshot(target_student_id uuid, target_enrollment_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date)
CREATE OR REPLACE FUNCTION public.build_student_id_card_snapshot(target_student_id uuid, target_enrollment_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare st public.students%rowtype;e public.enrollments%rowtype;c public.classes%rowtype;y public.academic_years%rowtype;s public.school_settings%rowtype;cfg public.id_card_settings%rowtype;guardian_phone text:='';
begin
  select * into st from public.students where id=target_student_id and deleted_at is null and status='active';if st.id is null then raise exception 'Active student not found';end if;select * into e from public.enrollments where id=target_enrollment_id and student_id=target_student_id and deleted_at is null;if e.id is null then raise exception 'Student enrolment not found';end if;select * into c from public.classes where id=e.class_id;select * into y from public.academic_years where id=e.academic_year_id;select * into s from public.school_settings limit 1;select * into cfg from public.id_card_settings limit 1;if c.id is null or y.id is null then raise exception 'Student enrolment references an unavailable class or academic year';end if;if s.id is null then raise exception 'School settings are not configured';end if;if cfg.id is null then raise exception 'ID card settings are not initialized';end if;
  select coalesce(nullif(g.phone,''),nullif(st.guardian_phone,''),'') into guardian_phone from public.guardian_links gl join public.student_guardians g on g.id=gl.guardian_id where gl.student_id=st.id order by g.is_primary desc,gl.created_at limit 1;if guardian_phone is null then guardian_phone:=coalesce(st.guardian_phone,'');end if;
  return jsonb_build_object('schema','rce-student-id-card/v2','student',jsonb_build_object('id',st.id,'admission_no',st.admission_no,'full_name',concat_ws(' ',st.first_name,nullif(st.middle_name,''),st.last_name),'gender',case when cfg.show_gender then st.gender else null end,'date_of_birth',case when cfg.show_date_of_birth then st.date_of_birth else null end,'photo_url',st.photo_url,'guardian_phone',case when cfg.show_guardian_phone then guardian_phone else '' end),'academic',jsonb_build_object('enrollment_id',e.id,'academic_year_id',y.id,'academic_year_name',y.name,'class_id',c.id,'class_name',c.name),'school',jsonb_build_object('school_name',s.school_name,'motto',s.motto,'address',s.address,'phone',s.phone,'email',s.email,'website',s.website,'logo_url',s.logo_url,'primary_colour',s.primary_colour,'accent_colour',s.accent_colour),'principal',public.current_id_card_principal_snapshot(),'card',jsonb_build_object('card_number',target_card_number,'verification_token',target_verification_token,'issue_date',target_issue_date,'expires_on',target_expires_on),'template',to_jsonb(cfg)-'updated_by'-'created_at'-'updated_at');
end$function$;
revoke all on function public.build_student_id_card_snapshot(target_student_id uuid, target_enrollment_id uuid, target_card_number text, target_verification_token uuid, target_issue_date date, target_expires_on date) from public;

-- helper build_student_transcript_snapshot(target_student_id uuid)
CREATE OR REPLACE FUNCTION public.build_student_transcript_snapshot(target_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  student_json jsonb;
  school_json jsonb;
  principal_json jsonb;
  records_json jsonb;
  lifecycle_json jsonb;
  summary_json jsonb;
  first_record jsonb;
  latest_record jsonb;
  period_count integer:=0;
  subject_count integer:=0;
  cumulative_average numeric:=null;
begin
  if target_student_id is null then
    raise exception 'Student is required' using errcode='22023';
  end if;

  if auth.uid() is not null
     and coalesce(current_setting('request.jwt.claim.role',true),'') not in ('service_role','supabase_admin')
     and not public.can_view_student_history(target_student_id) then
    raise exception 'Access denied' using errcode='42501';
  end if;

  select jsonb_build_object(
    'id',s.id,
    'admission_no',s.admission_no,
    'full_name',concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name),
    'gender',s.gender,
    'date_of_birth',s.date_of_birth,
    'date_admitted',coalesce((select min(e.created_at)::date from public.enrollments e where e.student_id=s.id),s.created_at::date),
    'status',s.status,
    'archived',s.deleted_at is not null
  )
  into student_json
  from public.students s
  where s.id=target_student_id;

  if student_json is null then raise exception 'Student not found'; end if;

  select jsonb_build_object(
    'id',ss.id,
    'school_name',ss.school_name,
    'motto',ss.motto,
    'address',ss.address,
    'phone',ss.phone,
    'email',ss.email,
    'website',ss.website,
    'logo_url',ss.logo_url,
    'primary_colour',ss.primary_colour,
    'accent_colour',ss.accent_colour,
    'tenant_code',ss.tenant_code,
    'verification_base_url',ss.verification_base_url,
    'head_name',ss.head_name
  )
  into school_json
  from public.school_settings ss
  order by ss.created_at,ss.id
  limit 1;

  select jsonb_build_object(
    'id',h.id,
    'profile_id',h.profile_id,
    'full_name',concat_ws(' ',h.first_name,nullif(h.middle_name,''),h.last_name),
    'title','Principal',
    'signature_path',h.signature_path
  )
  into principal_json
  from public.headteachers h
  where h.active and h.deleted_at is null
  order by h.date_appointed desc nulls last,h.created_at desc,h.id
  limit 1;

  principal_json:=coalesce(principal_json,jsonb_build_object('full_name',coalesce(school_json->>'head_name',''),'title','Principal','signature_path',''));

  with latest_publication_per_term as (
    select distinct on (r.term_id)
      p.id as publication_id,
      p.verification_token as publication_verification_token,
      p.published_at as publication_published_at,
      r.id as report_id,
      r.term_id,
      e.class_id,
      t.academic_year_id,
      rr.id as revision_id,
      rr.version as publication_revision,
      rr.snapshot as published_snapshot
    from public.report_publications p
    join public.student_reports r on r.id=p.report_id
    join public.enrollments e on e.id=r.enrollment_id
    join public.terms t on t.id=r.term_id
    join public.report_revisions rr on rr.id=p.revision_id
    where e.student_id=target_student_id
      and p.revoked_at is null
      and r.deleted_at is null
      and r.status='published'
    order by r.term_id,p.published_at desc,p.id desc
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'report_id',q.report_id,
      'publication_id',q.publication_id,
      'publication_verification_token',q.publication_verification_token,
      'publication_revision',q.publication_revision,
      'report_number',coalesce(q.published_snapshot->'report'->>'report_number',r.report_number::text),
      'status','published',
      'term_id',t.id,
      'term_name',coalesce(q.published_snapshot->'student'->>'term',t.name),
      'term_sequence',t.sequence,
      'term_start_date',t.start_date,
      'term_end_date',t.end_date,
      'academic_year_id',y.id,
      'academic_year_name',coalesce(q.published_snapshot->'student'->>'academic_year',y.name),
      'academic_year_start_date',y.start_date,
      'academic_year_end_date',y.end_date,
      'class_id',c.id,
      'class_name',coalesce(q.published_snapshot->'student'->>'class_name',c.name),
      'days_school_opened',coalesce(nullif(q.published_snapshot->'report'->>'days_school_opened','')::integer,0),
      'days_present',coalesce(nullif(q.published_snapshot->'report'->>'days_present','')::integer,0),
      'teacher_comment',coalesce(q.published_snapshot->'report'->>'teacher_comment',''),
      'head_comment',coalesce(q.published_snapshot->'report'->>'head_comment',''),
      'attitude',coalesce(q.published_snapshot->'report'->>'attitude',''),
      'conduct',coalesce(q.published_snapshot->'report'->>'conduct',''),
      'interest',coalesce(q.published_snapshot->'report'->>'interest',''),
      'average',coalesce(nullif(q.published_snapshot->'summary'->>'average','')::numeric,0),
      'aggregate',coalesce(nullif(q.published_snapshot->'summary'->>'aggregate','')::numeric,0),
      'subjects',coalesce(q.published_snapshot->'results','[]'::jsonb),
      'promotion',coalesce(q.published_snapshot->'promotion','{}'::jsonb),
      'published_at',q.publication_published_at
    )
    order by y.start_date,t.sequence,c.level_order,q.publication_published_at
  ),'[]'::jsonb)
  into records_json
  from latest_publication_per_term q
  join public.student_reports r on r.id=q.report_id
  join public.terms t on t.id=q.term_id
  join public.academic_years y on y.id=q.academic_year_id
  join public.classes c on c.id=q.class_id;

  period_count:=jsonb_array_length(records_json);
  if period_count>0 then
    first_record:=records_json->0;
    latest_record:=records_json->(period_count-1);
    select count(*),round(avg(nullif(subject->>'total_score','')::numeric),2)
      into subject_count,cumulative_average
    from jsonb_array_elements(records_json) record
    cross join lateral jsonb_array_elements(coalesce(record->'subjects','[]'::jsonb)) subject;
  end if;

  summary_json:=jsonb_build_object(
    'academic_period_count',period_count,
    'subject_result_count',coalesce(subject_count,0),
    'cumulative_average',cumulative_average,
    'first_academic_year',coalesce(first_record->>'academic_year_name',''),
    'first_term',coalesce(first_record->>'term_name',''),
    'latest_academic_year',coalesce(latest_record->>'academic_year_name',''),
    'latest_term',coalesce(latest_record->>'term_name',''),
    'latest_class',coalesce(latest_record->>'class_name','')
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',l.id,'event_type',l.event_type,'effective_date',l.effective_date,
    'from_class_name',fc.name,'to_class_name',tc.name,'destination_school',l.destination_school,
    'reason',l.reason,'reference',l.reference,'created_at',l.created_at,'actor_name',p.full_name
  ) order by l.effective_date,l.created_at),'[]'::jsonb)
  into lifecycle_json
  from public.student_lifecycle_events l
  left join public.classes fc on fc.id=l.from_class_id
  left join public.classes tc on tc.id=l.to_class_id
  left join public.profiles p on p.id=l.created_by
  where l.student_id=target_student_id;

  return jsonb_build_object(
    'schema_version','professional-transcript-v1',
    'student',student_json,
    'school',coalesce(school_json,'{}'::jsonb),
    'principal',principal_json,
    'generated_at',now(),
    'source_policy','latest_currently_valid_published_report_per_term',
    'academic_records',records_json,
    'summary',summary_json,
    'lifecycle',lifecycle_json
  );
end
$function$;
revoke all on function public.build_student_transcript_snapshot(target_student_id uuid) from public;

-- helper can_manage_certificates()
CREATE OR REPLACE FUNCTION public.can_manage_certificates()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.license_write_allowed() and public.is_system_admin() $function$;
revoke all on function public.can_manage_certificates() from public;

-- helper can_manage_class_report_fields(target_class_id uuid)
CREATE OR REPLACE FUNCTION public.can_manage_class_report_fields(target_class_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.is_official_class_teacher_for_class(target_class_id)
$function$;
revoke all on function public.can_manage_class_report_fields(target_class_id uuid) from public;

-- helper can_review_certificates()
CREATE OR REPLACE FUNCTION public.can_review_certificates()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ select public.license_write_allowed() and public.has_role(array['principal']) $function$;
revoke all on function public.can_review_certificates() from public;

-- helper can_view_student_history(target_student_id uuid)
CREATE OR REPLACE FUNCTION public.can_view_student_history(target_student_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.current_app_role() in ('system_admin','principal')
    or public.can_view_student(target_student_id)
    or exists(select 1 from public.guardian_links g where g.student_id=target_student_id and g.auth_user_id=auth.uid() and g.can_view_reports)
$function$;
revoke all on function public.can_view_student_history(target_student_id uuid) from public;

-- helper canonical_school_email_domain()
CREATE OR REPLACE FUNCTION public.canonical_school_email_domain()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
  select lower(public.canonical_school_identity_prefix()) || '.app'
$function$;
revoke all on function public.canonical_school_email_domain() from public;

-- helper certificate_type_code(target_type text)
CREATE OR REPLACE FUNCTION public.certificate_type_code(target_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ select case target_type when 'student_promotion' then 'PROM' when 'jhs_completion' then 'COMP' when 'teacher_recognition' then 'STAFF' else 'CERT' end $function$;
revoke all on function public.certificate_type_code(target_type text) from public;

-- helper certificate_type_label(target_type text)
CREATE OR REPLACE FUNCTION public.certificate_type_label(target_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog', 'extensions'
AS $function$ select case target_type when 'student_promotion' then 'Student Promotion' when 'jhs_completion' then 'JHS 3 Completion' when 'teacher_recognition' then 'Teacher Recognition' else 'Certificate' end $function$;
revoke all on function public.certificate_type_label(target_type text) from public;

-- helper generate_staff_id_card_number(target_academic_year_id uuid)
CREATE OR REPLACE FUNCTION public.generate_staff_id_card_number(target_academic_year_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare prefix text;year_code text;candidate text;seq bigint;attempt integer:=0;
begin select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'RCE'),'[^0-9A-Za-z]','','g')) into prefix from public.school_settings limit 1;select regexp_replace(name::text,'[^0-9A-Za-z]','','g') into year_code from public.academic_years where id=target_academic_year_id and deleted_at is null;if year_code is null then raise exception 'Academic year not found';end if;loop attempt:=attempt+1;if attempt>1000 then raise exception 'Unable to allocate a unique staff ID card number';end if;seq:=nextval('public.staff_id_card_number_seq');candidate:=coalesce(nullif(prefix,''),'RCE')||'-STAFF-'||year_code||'-'||lpad(seq::text,6,'0');exit when not exists(select 1 from public.staff_id_cards where card_number=candidate);end loop;return candidate;end$function$;
revoke all on function public.generate_staff_id_card_number(target_academic_year_id uuid) from public;

-- helper generate_student_id_card_number(target_academic_year_id uuid)
CREATE OR REPLACE FUNCTION public.generate_student_id_card_number(target_academic_year_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare prefix text;year_code text;candidate text;seq bigint;attempt integer:=0; begin select upper(regexp_replace(coalesce(nullif(report_number_prefix,''),'RCE'),'[^0-9A-Za-z]','','g')) into prefix from public.school_settings limit 1; select regexp_replace(name::text,'[^0-9A-Za-z]','','g') into year_code from public.academic_years where id=target_academic_year_id and deleted_at is null; if year_code is null then raise exception 'Academic year not found';end if;year_code:=coalesce(nullif(year_code,''),upper(substr(replace(target_academic_year_id::text,'-',''),1,8))); loop attempt:=attempt+1;if attempt>1000 then raise exception 'Unable to allocate a unique ID card number';end if; seq:=nextval('public.student_id_card_number_seq');candidate:=coalesce(nullif(prefix,''),'RCE')||'-ID-'||year_code||'-'||lpad(seq::text,6,'0'); exit when not exists(select 1 from public.student_id_cards where card_number=candidate); end loop; return candidate; end$function$;
revoke all on function public.generate_student_id_card_number(target_academic_year_id uuid) from public;

-- helper get_role_dashboard(target_term_id uuid)
CREATE OR REPLACE FUNCTION public.get_role_dashboard(target_term_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare termid uuid:=target_term_id;
declare v_current_role text:=public.current_app_role()::text;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if termid is null then select id into termid from public.terms where is_active and deleted_at is null limit 1; end if;
  return jsonb_build_object(
    'role',v_current_role,
    'active_students',(select count(*) from public.students s where s.status='active' and s.deleted_at is null and public.can_view_student(s.id)),
    'active_classes',(select count(*) from public.classes c where c.active and c.deleted_at is null and (public.is_records_manager() or public.can_access_class(c.id,false))),
    'active_teachers',case when public.can_manage_teachers() or public.has_role(array['system_admin','principal','academic_admin'])
      then (select count(*) from public.teachers t where t.active and t.deleted_at is null) else 0 end,
    'active_users',case when public.is_system_admin() then (select count(*) from public.profiles p where p.active) else 0 end,
    'reports',(select count(*) from public.student_reports r where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id)),
    'published',(select count(*) from public.student_reports r where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)),
    'draft_returned',(select count(*) from public.student_reports r where r.term_id=termid and r.status in ('draft','returned') and r.deleted_at is null and public.can_view_report(r.id)),
    'pending_review',(select count(*) from public.student_reports r where r.term_id=termid and r.status in ('submitted','class_reviewed','approved') and r.deleted_at is null and public.can_view_report(r.id)),
    'assigned_classes',(select count(distinct c.id) from public.classes c where c.deleted_at is null and c.active and public.can_access_class(c.id,false)),
    'assigned_subjects',(select count(distinct cs.subject_id) from public.class_subjects cs join public.classes c on c.id=cs.class_id
      where cs.active and c.deleted_at is null and (cs.teacher_id=auth.uid() or public.is_academic_manager())),
    'missing_guardians',case when public.is_records_manager() then (
      select count(*) from public.students s where s.deleted_at is null and not exists(
        select 1 from public.guardian_links gl where gl.student_id=s.id
      )
    ) else 0 end,
    'missing_photos',case when public.is_records_manager() then (
      select count(*) from public.students s where s.deleted_at is null and btrim(coalesce(s.photo_url,''))=''
    ) else 0 end,
    'children',case when v_current_role='parent_guardian' then (
      select count(distinct gl.student_id) from public.guardian_links gl where gl.auth_user_id=auth.uid()
    ) else 0 end,
    'unread_notifications',(select count(*) from public.notifications n where n.recipient_id=auth.uid() and n.read_at is null),
    'average',coalesce((select round(avg(sr.total_score),2) from public.subject_results sr
      join public.student_reports r on r.id=sr.report_id
      where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)),0),
    'by_status',coalesce((select jsonb_object_agg(status,count_value) from (
      select r.status::text status,count(*) count_value from public.student_reports r
      where r.term_id=termid and r.deleted_at is null and public.can_view_report(r.id) group by r.status
    ) q),'{}'::jsonb),
    'class_performance',coalesce((select jsonb_agg(to_jsonb(q) order by q.class_name) from (
      select c.id class_id,c.name class_name,round(avg(sr.total_score),2) average
      from public.subject_results sr join public.student_reports r on r.id=sr.report_id
      join public.enrollments e on e.id=r.enrollment_id join public.classes c on c.id=e.class_id
      where r.term_id=termid and r.status='published' and r.deleted_at is null and public.can_view_report(r.id)
      group by c.id,c.name
    ) q),'[]'::jsonb),
    'recent',coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from (
      select r.id,r.report_number,r.status,r.version,r.updated_at,
        concat_ws(' ',s.first_name,nullif(s.middle_name,''),s.last_name) student_name,
        c.name class_name,t.name term_name,round(coalesce(avg(sr.total_score),0),2) average
      from public.student_reports r join public.enrollments e on e.id=r.enrollment_id
      join public.students s on s.id=e.student_id join public.classes c on c.id=e.class_id
      join public.terms t on t.id=r.term_id left join public.subject_results sr on sr.report_id=r.id
      where r.deleted_at is null and public.can_view_report(r.id)
      group by r.id,s.id,c.id,t.id order by r.updated_at desc limit 8
    ) q),'[]'::jsonb)
  );
end $function$;
revoke all on function public.get_role_dashboard(target_term_id uuid) from public;

-- helper get_role_workspace()
CREATE OR REPLACE FUNCTION public.get_role_workspace()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare termid uuid; v_current_role text:=public.current_app_role();
begin
  if v_current_role not in ('class_teacher','subject_teacher','system_admin','principal','academic_admin') then return jsonb_build_object('classes','[]'::jsonb,'subjects','[]'::jsonb); end if;
  select id into termid from public.terms where is_active and deleted_at is null limit 1;
  return jsonb_build_object(
    'classes',coalesce((select jsonb_agg(to_jsonb(q) order by q.level_order,q.class_name) from (
      select c.id class_id,c.name class_name,c.level_order,
        (select count(*) from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and s.deleted_at is null) student_count,
        (select count(*) from public.class_subjects cs where cs.class_id=c.id and cs.active) subject_count,
        (select count(*) from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and s.deleted_at is null) expected_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('published','approved')) completed_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('draft','returned')) open_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('submitted','class_reviewed','approved')) review_reports,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status='published') published_reports
      from public.classes c where c.active and c.deleted_at is null and public.can_manage_class_report_fields_for_term(c.id,termid)
    ) q),'[]'::jsonb),
    'subjects',coalesce((select jsonb_agg(to_jsonb(q) order by q.class_name,q.subject_name) from (
      select c.id class_id,c.name class_name,s.id subject_id,s.code subject_code,s.name subject_name,
        (select count(*) from public.enrollments e join public.students st on st.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and st.deleted_at is null) student_count,
        (select count(*) from public.student_reports r join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and r.term_id=termid and r.deleted_at is null and r.status in ('draft','returned')) open_reports,
        (select count(*) from public.subject_results sr join public.student_reports r on r.id=sr.report_id join public.enrollments e on e.id=r.enrollment_id where e.class_id=c.id and sr.subject_id=s.id and r.term_id=termid and r.deleted_at is null) scored_reports,
        (select count(*) from public.enrollments e join public.students st on st.id=e.student_id where e.class_id=c.id and e.active and e.deleted_at is null and st.deleted_at is null) expected_reports
      from public.class_subjects cs join public.classes c on c.id=cs.class_id join public.subjects s on s.id=cs.subject_id
      where cs.active and c.active and c.deleted_at is null and s.active and s.deleted_at is null and public.can_score_class_subject_for_term(c.id,s.id,termid)
    ) q),'[]'::jsonb)
  );
end $function$;
revoke all on function public.get_role_workspace() from public;

-- helper id_card_effective_status(target_status text, target_expires_on date)
CREATE OR REPLACE FUNCTION public.id_card_effective_status(target_status text, target_expires_on date)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$ select case when target_status='active' and target_expires_on<current_date then 'expired' else target_status end $function$;
revoke all on function public.id_card_effective_status(target_status text, target_expires_on date) from public;

-- helper record_certificate_event(target_batch_id uuid, target_certificate_id uuid, event_name text, reason_text text, details_data jsonb)
CREATE OR REPLACE FUNCTION public.record_certificate_event(target_batch_id uuid, target_certificate_id uuid, event_name text, reason_text text DEFAULT ''::text, details_data jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ begin
  insert into public.certificate_events(batch_id,certificate_id,event_type,reason,details)
  values(target_batch_id,target_certificate_id,event_name,btrim(coalesce(reason_text,'')),coalesce(details_data,'{}'::jsonb));
end $function$;
revoke all on function public.record_certificate_event(target_batch_id uuid, target_certificate_id uuid, event_name text, reason_text text, details_data jsonb) from public;

-- helper record_id_card_event(target_card_id uuid, target_student_id uuid, target_event_type text, target_details jsonb)
CREATE OR REPLACE FUNCTION public.record_id_card_event(target_card_id uuid, target_student_id uuid, target_event_type text, target_details jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin insert into public.id_card_events(card_id,student_id,event_type,actor_id,details) values(target_card_id,target_student_id,left(btrim(coalesce(target_event_type,'')),80),auth.uid(),coalesce(target_details,'{}'::jsonb));end$function$;
revoke all on function public.record_id_card_event(target_card_id uuid, target_student_id uuid, target_event_type text, target_details jsonb) from public;

-- helper record_staff_id_card_event(target_card_id uuid, target_staff_type text, target_staff_id uuid, event_name text, event_details jsonb)
CREATE OR REPLACE FUNCTION public.record_staff_id_card_event(target_card_id uuid, target_staff_type text, target_staff_id uuid, event_name text, event_details jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$begin insert into public.staff_id_card_events(card_id,staff_type,staff_record_id,event_type,actor_id,details) values(target_card_id,target_staff_type,target_staff_id,event_name,auth.uid(),coalesce(event_details,'{}'::jsonb));end$function$;
revoke all on function public.record_staff_id_card_event(target_card_id uuid, target_staff_type text, target_staff_id uuid, event_name text, event_details jsonb) from public;

-- helper require_platform_super_admin()
CREATE OR REPLACE FUNCTION public.require_platform_super_admin()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not public.is_platform_super_admin() then
    raise exception 'Platform Super Administrator access required' using errcode='42501';
  end if;
  if public.current_aal()<>'aal2' then
    raise exception 'Multi-factor authentication is required for platform licensing actions' using errcode='42501';
  end if;
end $function$;
revoke all on function public.require_platform_super_admin() from public;

-- helper resolve_report_grading_guide(target_report_id uuid)
CREATE OR REPLACE FUNCTION public.resolve_report_grading_guide(target_report_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.resolve_grading_guide(e.academic_year_id,e.class_id)
  from public.student_reports r
  join public.enrollments e on e.id=r.enrollment_id
  where r.id=target_report_id and r.deleted_at is null
$function$;
revoke all on function public.resolve_report_grading_guide(target_report_id uuid) from public;

-- helper save_class_subject_assignment(payload jsonb)
CREATE OR REPLACE FUNCTION public.save_class_subject_assignment(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare targetid uuid:=public.safe_uuid(payload->>'id'); classid uuid:=public.safe_uuid(payload->>'class_id'); subjectid uuid:=public.safe_uuid(payload->>'subject_id'); teacherid uuid:=public.safe_uuid(payload->>'teacher_id');
begin
  if not public.is_academic_manager() then raise exception 'Access denied' using errcode='42501'; end if;
  if btrim(coalesce(payload->>'id',''))<>'' and targetid is null then raise exception 'Subject assignment identifier is invalid'; end if;
  if btrim(coalesce(payload->>'class_id',''))<>'' and classid is null then raise exception 'Class identifier is invalid'; end if;
  if btrim(coalesce(payload->>'subject_id',''))<>'' and subjectid is null then raise exception 'Subject identifier is invalid'; end if;
  if btrim(coalesce(payload->>'teacher_id',''))<>'' and teacherid is null then raise exception 'Teacher identifier is invalid'; end if;
  if classid is null or not exists(select 1 from public.classes where id=classid and deleted_at is null and active) then raise exception 'Selected class is invalid or inactive'; end if;
  if subjectid is null or not exists(select 1 from public.subjects where id=subjectid and deleted_at is null and active) then raise exception 'Selected subject is invalid or inactive'; end if;
  if teacherid is not null and not exists(select 1 from public.profiles p where p.id=teacherid and p.active and public.current_app_role_for(p.role) in ('principal','academic_admin','class_teacher','subject_teacher')) then raise exception 'Selected teacher account is invalid'; end if;
  perform set_config('app.change_reason',coalesce(nullif(payload->>'reason',''),'Class subject assignment update'),true);
  if targetid is null then
    insert into public.class_subjects(class_id,subject_id,teacher_id,active,updated_at) values(classid,subjectid,teacherid,public.safe_boolean(payload->>'active',true),now())
    on conflict(class_id,subject_id) do update set teacher_id=excluded.teacher_id,active=excluded.active,updated_at=now() returning id into targetid;
  else
    update public.class_subjects set class_id=classid,subject_id=subjectid,teacher_id=teacherid,active=public.safe_boolean(payload->>'active',true),updated_at=now() where id=targetid;
    if not found then raise exception 'Subject assignment not found'; end if;
  end if;
  return public.get_academic_configuration();
exception when unique_violation then raise exception 'This subject is already assigned to the selected class';
end $function$;
revoke all on function public.save_class_subject_assignment(payload jsonb) from public;

-- helper staff_id_card_photo_reference_count(target_staff_id uuid, target_photo_path text)
CREATE OR REPLACE FUNCTION public.staff_id_card_photo_reference_count(target_staff_id uuid, target_photo_path text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
 select case when auth.uid() is not null and (
   public.is_system_admin()
   or exists(select 1 from public.teachers t where t.id=target_staff_id and t.profile_id=auth.uid() and t.deleted_at is null)
   or exists(select 1 from public.headteachers h where h.id=target_staff_id and h.profile_id=auth.uid() and h.deleted_at is null)
 ) then (select count(*) from public.staff_id_cards c where btrim(coalesce(target_photo_path,''))<>'' and c.snapshot#>>'{staff,id}'=target_staff_id::text and c.snapshot#>>'{staff,photo_url}'=target_photo_path) else 0 end
$function$;
revoke all on function public.staff_id_card_photo_reference_count(target_staff_id uuid, target_photo_path text) from public;

-- helper sync_attendance_reports(target_term_id uuid, target_class_id uuid)
CREATE OR REPLACE FUNCTION public.sync_attendance_reports(target_term_id uuid, target_class_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare affected integer:=0;
begin
  perform set_config('app.report_write','on',true);
  update public.student_reports r
  set days_school_opened=counts.days_school_opened,
      days_present=least(counts.days_present,counts.days_school_opened),
      updated_at=now()
  from public.enrollments e
  cross join lateral public.attendance_counts_for_enrollment(e.id,target_term_id) counts
  where r.enrollment_id=e.id
    and r.term_id=target_term_id
    and e.class_id=target_class_id
    and r.deleted_at is null
    and counts.days_school_opened>0;
  get diagnostics affected=row_count;
  return affected;
end $function$;
revoke all on function public.sync_attendance_reports(target_term_id uuid, target_class_id uuid) from public;

create or replace function public.platform_preview_license_change(target_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','app','platform','storage','pg_catalog'
as $preview$
declare
  p platform.license_plans%rowtype;
  students_count bigint;
  teachers_count bigint;
  admins_count bigint;
  guardians_count bigint;
  storage_mb numeric;
  tenant uuid:=app.current_tenant_id();
  max_students integer;
  max_teachers integer;
  max_admins integer;
  max_guardians integer;
  max_storage integer;
  plan_json jsonb;
begin
  perform public.require_platform_super_admin();
  select * into p from platform.license_plans where id=target_plan_id;
  if p.id is null then raise exception 'Licence plan not found' using errcode='22023'; end if;
  select count(*) into students_count from public.students where status='active' and deleted_at is null;
  select count(*) into teachers_count from public.teachers where active and deleted_at is null;
  select count(*) into admins_count from public.profiles where active and public.current_app_role_for(role)::text='system_admin';
  select count(*) into guardians_count from public.profiles where active and public.current_app_role_for(role)::text='parent_guardian';
  select round(coalesce(sum(size_bytes),0)/1048576.0,2) into storage_mb
  from storage.object_metadata where tenant_id=tenant and status='active';
  max_students:=nullif(p.limits->>'max_students','')::integer;
  max_teachers:=nullif(p.limits->>'max_teachers','')::integer;
  max_admins:=nullif(p.limits->>'max_system_admins','')::integer;
  max_guardians:=nullif(p.limits->>'max_guardians','')::integer;
  max_storage:=nullif(p.limits->>'max_storage_mb','')::integer;
  plan_json:=to_jsonb(p)||jsonb_build_object(
    'max_students',max_students,'max_teachers',max_teachers,'max_system_admins',max_admins,
    'max_guardians',max_guardians,'max_storage_mb',max_storage,
    'default_term_days',coalesce(nullif(p.limits->>'default_term_days','')::integer,365),
    'grace_days',coalesce(nullif(p.limits->>'grace_days','')::integer,30),
    'perpetual_allowed',coalesce((p.limits->>'perpetual_allowed')::boolean,false),
    'support_level',coalesce(nullif(p.limits->>'support_level',''),'standard'),
    'revision',coalesce(nullif(p.limits->>'revision','')::integer,1)
  );
  return jsonb_build_object(
    'plan',plan_json,
    'usage',jsonb_build_object('active_students',students_count,'active_teachers',teachers_count,'active_system_admins',admins_count,'active_guardians',guardians_count,'storage_mb',storage_mb),
    'compatible',(max_students is null or students_count<=max_students) and (max_teachers is null or teachers_count<=max_teachers) and (max_admins is null or admins_count<=max_admins) and (max_guardians is null or guardians_count<=max_guardians) and (max_storage is null or storage_mb<=max_storage),
    'excess',jsonb_build_object(
      'students',greatest(students_count-coalesce(max_students,students_count),0),
      'teachers',greatest(teachers_count-coalesce(max_teachers,teachers_count),0),
      'system_admins',greatest(admins_count-coalesce(max_admins,admins_count),0),
      'guardians',greatest(guardians_count-coalesce(max_guardians,guardians_count),0),
      'storage_mb',greatest(storage_mb-coalesce(max_storage,storage_mb),0)
    )
  );
end
$preview$;
revoke all on function public.platform_preview_license_change(uuid) from public;

insert into app.schema_migrations(version) values ('0045d_certified_rpc_helper_closure') on conflict do nothing;
update app.release_identity set schema_version='0045d' where edition='Edusentia Enterprise Neon Edition';
commit;
